import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asterlink/core/json.dart';
import 'package:asterlink/data/startup_recovery.dart';
import 'package:asterlink/data/state_store.dart';
import 'package:asterlink/main.dart';

class _Recovery extends StartupRecovery {
  _Recovery(super.failure);
  int resets = 0, restores = 0, unlocks = 0;
  bool passwordRecovery = false;
  Completer<StartupRecoveryResult>? pending;
  bool fail = false;
  @override
  Future<bool> canUnlock() async => passwordRecovery;
  @override
  Future<void> unlock(String password) async {
    unlocks++;
    if (fail) throw const AppException('备份密码错误或本地恢复文件已损坏');
    await pending?.future;
  }

  @override
  Future<StartupRecoveryResult> reinitialize() async {
    resets++;
    return await pending?.future ??
        StartupRecoveryResult(Directory('fixture-archive'));
  }

  @override
  Future<StartupRecoveryResult> restore(
    Uint8List bytes,
    String password,
  ) async {
    restores++;
    if (fail) throw const AppException('备份密码错误或文件已损坏');
    return StartupRecoveryResult(Directory('fixture-archive'), accounts: 2);
  }
}

void main() {
  final failure = StateRecoveryRequired(
    Directory('fixture'),
    StateRecoveryCause.missingKey,
  );
  late _Recovery recovery;
  setUp(() => recovery = _Recovery(failure));
  Future<void> render(
    WidgetTester tester, {
    Object? error,
    Future<XFile?> Function()? choose,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: appTheme(Brightness.light),
      home: StartupFailurePage(
        error ?? failure,
        recovery: recovery,
        chooseBackup: choose,
        onRetry: () {},
      ),
    ),
  );
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('only local state failures expose recovery actions', (
    tester,
  ) async {
    await render(tester, error: const AppException('网络连接失败'));
    expect(find.text('恢复备份'), findsNothing);
    expect(find.byKey(const Key('startup-reinitialize')), findsNothing);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('导出故障日志'), findsOneWidget);
  });

  testWidgets(
    'reset requires confirmation and cancellation does not change data',
    (tester) async {
      await render(tester);
      await tap(tester, find.byKey(const Key('startup-reinitialize')));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(recovery.resets, 0);
      await tester.tapAt(const Offset(4, 4));
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tap(tester, find.text('取消'));
      expect(recovery.resets, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'reset blocks repeated actions while writing and exposes restart on success',
    (tester) async {
      recovery.pending = Completer<StartupRecoveryResult>();
      await render(tester);
      await tap(tester, find.byKey(const Key('startup-reinitialize')));
      await tap(tester, find.text('保留并重新初始化'));
      expect(recovery.resets, 1);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('startup-reinitialize')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '重试'))
            .onPressed,
        isNull,
      );
      recovery.pending!.complete(
        StartupRecoveryResult(Directory('fixture-archive')),
      );
      await tester.pumpAndSettle();
      expect(find.text('进入应用'), findsOneWidget);
      expect(find.byKey(const Key('startup-reinitialize')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelled picker performs no recovery', (tester) async {
    await render(tester, choose: () async => null);
    await tap(tester, find.byKey(const Key('startup-restore-backup')));
    expect(recovery.restores, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'password recovery needs no picker and preserves current records',
    (tester) async {
      recovery.passwordRecovery = true;
      recovery.pending = Completer<StartupRecoveryResult>();
      var pickerCalls = 0;
      await render(
        tester,
        choose: () async {
          pickerCalls++;
          return null;
        },
      );
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('startup-unlock')));
      await tester.tapAt(const Offset(4, 4));
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'fixture-password');
      await tap(tester, find.text('确定'));
      expect(recovery.unlocks, 1);
      expect(pickerCalls, 0);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('startup-unlock')))
            .onPressed,
        isNull,
      );
      recovery.pending!.complete(StartupRecoveryResult(Directory('fixture')));
      await tester.pumpAndSettle();
      expect(find.text('本地数据已解锁，当前账号、设置和下载记录均已保留。'), findsOneWidget);
      expect(find.text('进入应用'), findsOneWidget);
    },
  );

  testWidgets(
    'wrong local password permits retry; legacy data has no unlock button',
    (tester) async {
      await render(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('startup-unlock')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      recovery.passwordRecovery = true;
      recovery.fail = true;
      await render(tester);
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('startup-unlock')));
      await tester.enterText(find.byType(TextField), 'wrong-password');
      await tap(tester, find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('备份密码错误或本地恢复文件已损坏'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('startup-unlock')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('restore reports wrong password and permits another try', (
    tester,
  ) async {
    recovery.fail = true;
    await render(
      tester,
      choose: () async =>
          XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'backup.json'),
    );
    await tap(tester, find.byKey(const Key('startup-restore-backup')));
    await tester.enterText(find.byType(TextField), 'wrong-password');
    await tap(tester, find.text('确定'));
    await tap(tester, find.text('验证并恢复'));
    await tester.pumpAndSettle();
    expect(recovery.restores, 1);
    expect(find.text('备份密码错误或文件已损坏'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('startup-restore-backup')))
          .onPressed,
      isNotNull,
    );
    expect(find.byKey(const Key('startup-reinitialize')), findsOneWidget);
  });

  testWidgets('recovery actions fit a narrow screen with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    recovery.passwordRecovery = true;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.5)),
          child: child!,
        ),
        home: StartupFailurePage(failure, recovery: recovery, onRetry: () {}),
      ),
    );
    await tap(tester, find.byKey(const Key('startup-reinitialize')));
    expect(find.text('保留并重新初始化'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
