import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:asterlink/core/json.dart';
import 'package:asterlink/data/http.dart';
import 'package:asterlink/data/providers/lanzou.dart';
import 'package:asterlink/domain/auth.dart';
import 'lanzou_password_support.dart';
import 'lanzou_support.dart';
import 'support.dart';

void main() {
  test(
    'official password fields, isolated cookies and personal API verification',
    () async {
      final fixture = LanzouPasswordFixture();
      final result = await LanzouConnector(
        fixture.http,
      ).password('  fixture-user  ', ' Pass+&word! ');
      final post = fixture.http.calls.singleWhere(
        (r) => r.method == 'POST' && r.uri.path == '/accounts.php',
      );
      expect(Uri.splitQueryString(post.body as String), {
        'task': 'uselogin',
        'username': 'fixture-user',
        'password': ' Pass+&word! ',
        'ref': 'pc.woozooo.com',
      });
      expect(post.headers['Cookie'], 'account-session=isolated');
      expect(post.headers['User-Agent'], WebLoginTarget.desktopUserAgent);
      expect(post.headers['Origin'], 'https://accounts.woozooo.com');
      expect(fixture.http.redirects, everyElement(isFalse));
      for (final call in fixture.http.calls.where(
        (r) => r.uri.host == 'pc.woozooo.com',
      )) {
        expect(
          call.headers['Cookie'] ?? '',
          isNot(contains('account-session')),
        );
      }
      expect(fixture.http.calls.last.uri.path, '/doupload.php');
      expect(result.credential.field('userId'), '12345');
      expect(result.credential.field('authType'), 'passwordCookie');
      expect(result.credential.field('username'), 'fixture-user');
      expect(result.credential.field('password'), ' Pass+&word! ');
      expect(
        result.credential.primary,
        contains('phpdisk_info=session-cookie'),
      );
      expect(result.credential.primary, isNot(contains('account-session')));
    },
  );

  test(
    'fresh session handles the official preliminary cookie challenge once',
    () async {
      final fixture = LanzouPasswordFixture();
      var pages = 0;
      fixture.intercept = (r) {
        if (r.uri.path == '/accounts.php' && r.method == 'GET') {
          pages++;
          if (pages == 1) return const HttpResult(200, lanzouTestChallenge);
          expect(r.headers['Cookie'], contains('acw_sc__v2='));
        }
        return null;
      };
      await LanzouConnector(fixture.http).password('fixture-user', 'password');
      expect(pages, 2);
    },
  );

  test('repeated challenge stops before password submission', () async {
    final fixture = LanzouPasswordFixture();
    fixture.intercept = (_) => const HttpResult(200, lanzouTestChallenge);
    await expectLater(
      LanzouConnector(fixture.http).password('fixture-user', 'password'),
      throwsA(
        isA<AppException>().having(
          (e) => e.message,
          'message',
          contains('网页验证'),
        ),
      ),
    );
    expect(fixture.http.calls.length, 2);
    expect(fixture.http.calls.every((r) => r.method == 'GET'), isTrue);
  });

  test(
    'password rejection does not call the personal API or echo secrets',
    () async {
      final fixture = LanzouPasswordFixture();
      fixture.intercept = (r) =>
          r.method == 'POST' && r.uri.path == '/accounts.php'
          ? jsonResponse({'zt': 0, 'msgs': '密码错误: private-password'})
          : null;
      await expectLater(
        LanzouConnector(
          fixture.http,
        ).password('fixture-user', 'private-password'),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            allOf(contains('密码错误'), isNot(contains('private-password'))),
          ),
        ),
      );
      expect(fixture.http.calls.length, 2);
    },
  );

  for (final url in [
    'https://evil.invalid/callback',
    'http://pc.woozooo.com/callback',
    'https://pc.woozooo.com.evil.invalid/callback',
  ]) {
    test('unsafe callback is rejected: $url', () async {
      final fixture = LanzouPasswordFixture()..callback = url;
      await expectLater(
        LanzouConnector(fixture.http).password('fixture-user', 'password'),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('跳转地址异常'),
          ),
        ),
      );
      expect(fixture.http.calls.length, 2);
    });
  }

  test(
    'having cookies is insufficient if the personal file API rejects them',
    () async {
      final fixture = LanzouPasswordFixture()..fileStatus = 9;
      await expectLater(
        LanzouConnector(fixture.http).password('fixture-user', 'password'),
        throwsA(isA<AccountLoginRequired>()),
      );
    },
  );

  test('simultaneous accounts do not share cookies', () async {
    final first = LanzouPasswordFixture(userId: '111')..cookie = 'first';
    final second = LanzouPasswordFixture(userId: '222')..cookie = 'second';
    final results = await Future.wait([
      LanzouConnector(first.http).password('first-user', 'first-password'),
      LanzouConnector(second.http).password('second-user', 'second-password'),
    ]);
    expect(results[0].credential.primary, contains('phpdisk_info=first'));
    expect(results[0].credential.primary, isNot(contains('second')));
    expect(results[1].credential.primary, contains('phpdisk_info=second'));
    expect(results[1].credential.primary, isNot(contains('first')));
  });

  test(
    'cancelling a pending password response stops callback and commit',
    () async {
      final fixture = LanzouPasswordFixture(), scope = RequestScope();
      final submitted = Completer<void>(), response = Completer<HttpResult>();
      fixture.intercept = (r) {
        if (r.method == 'POST' && r.uri.path == '/accounts.php') {
          submitted.complete();
          return response.future;
        }
        return null;
      };
      final attempt = scope.run(
        () =>
            LanzouConnector(fixture.http).password('fixture-user', 'password'),
      );
      final fails = expectLater(attempt, throwsA(anything));
      await submitted.future;
      scope.cancel();
      response.complete(jsonResponse({'zt': 1, 'msgs': fixture.callback}));
      await fails;
      expect(fixture.http.calls.length, 2);
    },
  );
}
