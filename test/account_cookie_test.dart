import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asterlink/domain/auth.dart';
import 'package:asterlink/domain/models.dart';
import 'package:asterlink/main.dart';
import 'package:asterlink/ui/account_cookie.dart';
import 'package:asterlink/ui/cloud_accounts_page.dart';
import 'package:asterlink/ui/login_page.dart';
import 'browser_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cookies = {
    CloudPlatform.baidu: 'BDUSS=fixture; STOKEN=fixture%3D%3D',
    CloudPlatform.quark: '__pus=fixture; __puus=fixture==',
    CloudPlatform.uc: '__pus=uc-fixture; __puus=uc-fixture==',
    CloudPlatform.tianyi: 'COOKIE_LOGIN_USER=fixture; JSESSIONID=session',
    CloudPlatform.c139: 'auth_token=fixture; ud_id=001',
    CloudPlatform.lanzou: 'ylogin=fixture; phpdisk_info=fixture%2Bvalue',
    CloudPlatform.weiyun: 'p_uin=o1234; p_skey=fixture; wyctoken=fixture',
    CloudPlatform.pan115: 'UID=fixture; CID=fixture; SEID=fixture',
    CloudPlatform.ctfile: 'ctfile_session=fixture; remember=1',
  };
  for (final entry in cookies.entries) {
    test('copies only the saved cookie for ${entry.key.key}', () {
      final credential = Credential('私有账号名称', {
        'primary': 'Cookie: ${entry.value}',
        'secondary': 'password-not-a-cookie',
        'password': 'private-password',
        'accessToken': 'private-token',
        'clientSecret': 'private-client-secret',
      });
      expect(LoginCredentials.savedCookie(entry.key, credential), entry.value);
    });
  }
  for (final platform in CloudPlatform.values.where(
    (p) => !cookies.containsKey(p),
  )) {
    test(
      'token or password primary is not copied as cookie for ${platform.key}',
      () {
        for (final primary in [
          'encoded-token==',
          'name=password',
          '{"access_token":"fixture"}',
        ]) {
          expect(
            LoginCredentials.savedCookie(
              platform,
              Credential('账号', {
                'primary': primary,
                'secondary': 'password',
                'accessToken': 'fixture',
              }),
            ),
            isNull,
          );
        }
      },
    );
  }
  test('legacy browser captures export cookies without captured metadata', () {
    for (final platform in [CloudPlatform.weiyun, CloudPlatform.tianyi]) {
      expect(
        LoginCredentials.savedCookie(
          platform,
          Credential('账号', {
            'primary': jsonEncode({
              'cookie': cookies[platform],
              'browserId': 'private-browser',
              'tokenInfo': {'access_token': 'private-token'},
            }),
          }),
        ),
        cookies[platform],
      );
    }
  });
  test('copy keeps empty values repeated names and encoding intact', () {
    const value =
        'BDUSS=fixture; empty=; duplicate=a; duplicate=b; padded=abc==; encoded=%2B%3D';
    expect(
      LoginCredentials.savedCookie(
        CloudPlatform.baidu,
        Credential('账号', {'primary': value}),
      ),
      value,
    );
  });
  test('missing or malformed cookies and ctfile API tokens are not copied', () {
    expect(LoginCredentials.savedCookie(CloudPlatform.baidu, null), isNull);
    for (final value in [
      '',
      'Bearer abc==',
      '{"password":"abc=def"}',
      'bad name=value',
      'BDUSS=fixture\r\nAuthorization: private',
    ]) {
      expect(
        LoginCredentials.savedCookie(
          CloudPlatform.baidu,
          Credential('账号', {'primary': value}),
        ),
        isNull,
      );
    }
    expect(
      LoginCredentials.savedCookie(
        CloudPlatform.ctfile,
        Credential('账号', {'primary': 'ctfile-api-session-token'}),
      ),
      isNull,
    );
  });
  test('an explicitly saved cookie is usable alongside token login', () {
    expect(
      LoginCredentials.savedCookie(
        CloudPlatform.aliyun,
        Credential('账号', {
          'primary': 'refresh-token',
          'cookie': 'session=real-cookie',
        }),
      ),
      'session=real-cookie',
    );
  });

  late String? copied;
  late bool failClipboard;
  setUp(() {
    copied = null;
    failClipboard = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            if (failClipboard) {
              throw PlatformException(
                code: 'clipboard',
                message: 'BDUSS=private-error',
              );
            }
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<String> addAccount(
    BrowserUiFixture fixture,
    String name,
    String cookie,
  ) async {
    final vault = fixture.services.vault;
    final id = await vault.createAccount(CloudPlatform.tianyi);
    await vault.withAccount(
      CloudPlatform.tianyi,
      id,
      () => vault.putCredential(
        CloudPlatform.tianyi,
        Credential(name, {'primary': cookie}),
      ),
    );
    return id;
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(393, 864), const Size(1100, 780)]) {
    testWidgets('account manager copies the chosen inactive account at $size', (
      tester,
    ) async {
      final fixture = await BrowserUiFixture.create();
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        final vault = fixture.services.vault;
        final active = vault.activeAccountId(CloudPlatform.tianyi);
        final second = await addAccount(
          fixture,
          '家庭账号',
          'COOKIE_LOGIN_USER=second',
        );
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(Brightness.light),
            home: CloudAccountsPage(
              fixture.services,
              platform: CloudPlatform.tianyi,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, find.byTooltip('家庭账号的账号操作'));
        // The menu must use a freshly renewed cookie belonging to this account.
        await vault.withAccount(
          CloudPlatform.tianyi,
          second,
          () => vault.putCredential(
            CloudPlatform.tianyi,
            Credential('家庭账号', {'primary': 'COOKIE_LOGIN_USER=renewed'}),
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, find.text('复制 Cookie'));
        expect(copied, 'COOKIE_LOGIN_USER=renewed');
        expect(vault.activeAccountId(CloudPlatform.tianyi), active);
        expect(find.text('Cookie 已复制'), findsOneWidget);
        expect(find.textContaining('COOKIE_LOGIN_USER='), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await fixture.close();
      }
    });
  }

  testWidgets('cloud menu copy stays bound to the account shown when opened', (
    tester,
  ) async {
    final fixture = await BrowserUiFixture.create();
    try {
      final vault = fixture.services.vault;
      await vault.putCredential(
        CloudPlatform.tianyi,
        Credential('工作账号', {'primary': 'COOKIE_LOGIN_USER=work'}),
      );
      final second = await addAccount(
        fixture,
        '家庭账号',
        'COOKIE_LOGIN_USER=family',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => accountMenu(
                  context,
                  fixture.services,
                  CloudPlatform.tianyi,
                ),
                child: const Text('账号菜单'),
              ),
            ),
          ),
        ),
      );
      await tap(tester, find.text('账号菜单'));
      await vault.activate(CloudPlatform.tianyi, second);
      await tester.pumpAndSettle();
      await tap(tester, find.text('复制 Cookie'));
      expect(copied, 'COOKIE_LOGIN_USER=work');
      expect(vault.activeAccountId(CloudPlatform.tianyi), second);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.close();
    }
  });

  testWidgets('token-only and removed accounts leave the clipboard unchanged', (
    tester,
  ) async {
    final fixture = await BrowserUiFixture.create();
    try {
      final vault = fixture.services.vault;
      await vault.putCredential(
        CloudPlatform.aliyun,
        Credential('阿里账号', {
          'primary': 'refresh-token',
          'accessToken': 'access-token',
          'loginUsername': 'private-name',
          'loginPassword': 'private-password',
        }),
      );
      final id = vault.activeAccountId(CloudPlatform.aliyun);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => copyCloudAccountCookie(
                  context,
                  vault,
                  CloudPlatform.aliyun,
                  id,
                ),
                child: const Text('复制'),
              ),
            ),
          ),
        ),
      );
      await tap(tester, find.text('复制'));
      expect(copied, isNull);
      expect(find.text('此账号未保存可复制的 Cookie，可能使用 Token 或其他方式登录'), findsOneWidget);
      await vault.removeAccount(CloudPlatform.aliyun, id!);
      await tap(tester, find.text('复制'));
      expect(copied, isNull);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.close();
    }
  });

  testWidgets(
    'clipboard errors show a generic message without exposing the cookie',
    (tester) async {
      final fixture = await BrowserUiFixture.create();
      try {
        final vault = fixture.services.vault;
        await vault.putCredential(
          CloudPlatform.baidu,
          Credential('百度账号', {'primary': 'BDUSS=private-cookie'}),
        );
        final id = vault.activeAccountId(CloudPlatform.baidu);
        failClipboard = true;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => copyCloudAccountCookie(
                    context,
                    vault,
                    CloudPlatform.baidu,
                    id,
                  ),
                  child: const Text('复制'),
                ),
              ),
            ),
          ),
        );
        await tap(tester, find.text('复制'));
        expect(copied, isNull);
        expect(find.text('复制失败，请重试'), findsOneWidget);
        expect(find.textContaining('BDUSS='), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await fixture.close();
      }
    },
  );
}
