import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:asterlink/core/json.dart';
import 'package:asterlink/domain/downloads.dart';
import 'package:asterlink/domain/models.dart';
import 'package:asterlink/domain/remote_control.dart';
import 'package:asterlink/platform/file_access.dart';
import 'app_update_support.dart';

void main() {
  late UpdateFixture f;
  setUp(() => f = UpdateFixture());
  tearDown(() => f.close());

  test(
    'Single share file uses the configured passcode and a recoverable download origin',
    () async {
      expect(await f.service.start(f.current!), isTrue);
      expect(f.connector.opened!.passcode, '1234');
      final task = f.downloads.tasks.single;
      expect(task.spec.fileName, 'app.apk');
      expect(task.spec.needsPreparation, isTrue);
      expect(task.spec.platform, CloudPlatform.lanzou);
      expect(task.spec.appUpdateKey, f.service.keyFor(f.current!));
      expect(task.spec.source!['file']['id'], 'file');
      expect(f.installer.opens, 0);
      final restored = DownloadTask.fromJson(
        jsonDecode(jsonEncode(task.toJson())),
      );
      expect(restored.spec.appUpdateKey, task.spec.appUpdateKey);
    },
  );

  test(
    'Repeated clicks coalesce and reuse paused, failed and finished tasks',
    () async {
      f.connector.pending = Completer<void>();
      final a = f.service.start(f.current!), b = f.service.start(f.current!);
      expect(identical(a, b), isTrue);
      f.connector.pending!.complete();
      await a;
      await f.service.start(f.current!);
      expect(f.downloads.created, 1);
      await f.service.pause(f.current!);
      await f.service.start(f.current!);
      expect(f.downloads.resumed, 1);
      f.downloads.change(f.downloads.tasks.single.id, {
        'status': 'failed',
        'error': '网络故障',
      });
      await f.service.start(f.current!);
      expect(f.downloads.resumed, 2);
      f.complete();
      await f.service.start(f.current!);
      expect(f.downloads.created, 1);
      expect(f.installer.opens, 0);
    },
  );

  test(
    'Existing persisted update downloads are recovered without another share request',
    () async {
      await f.service.start(f.current!);
      final restored = DownloadTask.fromJson(
        jsonDecode(jsonEncode(f.downloads.tasks.single.toJson())),
      );
      f.close();
      f = UpdateFixture();
      f.downloads.records.add(restored.update({'status': 'paused'}));
      expect(await f.service.start(f.current!), isTrue);
      expect(f.connector.opened, isNull);
      expect(f.downloads.created, 0);
      expect(f.downloads.resumed, 1);
    },
  );

  for (final entries in <List<CloudFile>>[
    [],
    [const CloudFile(id: 'dir', name: '安装包', isDirectory: true)],
    [
      const CloudFile(id: 'a', name: 'app.apk'),
      const CloudFile(id: 'b', name: 'readme.txt'),
    ],
    [const CloudFile(id: 'a', name: 'installer.exe')],
  ]) {
    test(
      'Rejects invalid share selection ${entries.map((f) => f.name).join(',')}',
      () async {
        f.connector.entries = entries;
        expect(await f.service.start(f.current!), isFalse);
        expect(f.service.error(f.current!), isNotEmpty);
        expect(f.downloads.tasks, isEmpty);
      },
    );
  }

  test(
    'Login failures remain visible and never queue a webpage as an APK',
    () async {
      f.connector.failure = const AppException('请先登录网盘账号');
      expect(await f.service.start(f.current!), isFalse);
      expect(f.service.error(f.current!), contains('登录'));
      f.current = RemoteUpdate(
        '1.2.0',
        120,
        Uri.parse('https://downloads.example.test/browser'),
        '',
      );
      expect(await f.service.start(f.current!), isFalse);
      expect(f.service.error(f.current!), contains('浏览器更新'));
      expect(f.downloads.tasks, isEmpty);
    },
  );

  for (final platform in ['android', 'windows']) {
    test(
      '$platform supports direct installation assets including GitHub fallback',
      () async {
        f.close();
        f = UpdateFixture(platform: platform);
        final extension = platform == 'android' ? 'apk' : 'exe';
        f.current = RemoteUpdate(
          '1.2.0',
          0,
          Uri.parse(
            'https://github.com/z7786/wenxi/releases/download/v1.2.0/app.$extension',
          ),
          '',
          releaseKey: 'github:v1.2.0',
        );
        expect(await f.service.start(f.current!), isTrue);
        expect(
          f.downloads.tasks.single.spec.url,
          f.current!.downloadUrl.toString(),
        );
        expect(f.connector.opened, isNull);
      },
    );
  }

  test(
    'Changed update URL invalidates pending parsing, including unchanged build',
    () async {
      final old = f.current!;
      f.connector.pending = Completer<void>();
      final operation = f.service.start(old);
      await Future<void>.delayed(Duration.zero);
      f.current = RemoteUpdate(
        old.version,
        old.build,
        Uri.parse('https://example.test/new.apk'),
        '',
      );
      f.connector.pending!.complete();
      expect(await operation, isFalse);
      expect(f.downloads.tasks, isEmpty);
      expect(f.service.error(old), contains('已变化'));
    },
  );

  test(
    'Missing completed files download again; inaccessible files report permissions',
    () async {
      await f.service.start(f.current!);
      f.complete();
      f.files.availability['/saved/app.apk'] = FileAvailability.inaccessible;
      expect(await f.service.start(f.current!), isFalse);
      expect(f.downloads.created, 1);
      f.files.availability['/saved/app.apk'] = FileAvailability.missing;
      expect(await f.service.start(f.current!), isTrue);
      expect(f.downloads.created, 2);
    },
  );

  test(
    'Installation requires completion, foreground and a successful validation',
    () async {
      final update = f.current!;
      await f.service.start(update);
      expect(await f.service.install(update), isFalse);
      f.complete();
      f.foreground = false;
      expect(await f.service.install(update), isFalse);
      f.foreground = true;
      f.installer.failure = const AppException('签名不一致');
      expect(await f.service.install(update), isFalse);
      expect(f.installer.opens, 0);
      f.installer.failure = null;
      expect(await f.service.install(update), isTrue);
      expect(f.installer.opens, 1);
      expect(await f.service.start(update, redownload: true), isTrue);
      expect(f.downloads.created, 2);
    },
  );

  test(
    'Withdrawing update while validation runs never launches installer',
    () async {
      final update = f.current!;
      await f.service.start(update);
      f.complete();
      f.installer.pending = Completer<void>();
      final operation = f.service.install(update);
      await Future<void>.delayed(Duration.zero);
      f.current = null;
      f.installer.pending!.complete();
      expect(await operation, isFalse);
      expect(f.installer.opens, 0);
    },
  );
}
