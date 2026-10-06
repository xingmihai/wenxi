import 'dart:async';
import 'package:asterlink/data/http.dart';
import 'lanzou_support.dart';
import 'support.dart';

class LanzouPasswordFixture {
  LanzouPasswordFixture({this.userId = '12345'}) {
    http = LanzouTestHttp((r) async => await intercept?.call(r) ?? respond(r));
  }
  final String userId;
  late final LanzouTestHttp http;
  FutureOr<HttpResult?> Function(RecordedRequest)? intercept;
  String callback = 'https://accounts.woozooo.com/bridge?ticket=fixture';
  String cookie = 'session-cookie';
  int fileStatus = 2;

  HttpResult respond(RecordedRequest r) {
    switch (r.uri.path) {
      case '/accounts.php':
        if (r.method == 'GET') {
          return const HttpResult(
            200,
            '<input id="username"><input id="password">',
            {
              'set-cookie': ['account-session=isolated; Path=/; Secure'],
            },
          );
        }
        return jsonResponse({'zt': 1, 'msgs': callback});
      case '/bridge':
        return const HttpResult(
          200,
          '<script>window.location.href="https://pc.woozooo.com/callback?ticket=fixture";</script>',
        );
      case '/callback':
        return HttpResult(302, '', {
          'location': ['/mydisk.php'],
          'set-cookie': [
            'ylogin=$userId; Domain=.woozooo.com; Path=/; Secure; HttpOnly',
            'phpdisk_info=$cookie; Domain=.woozooo.com; Path=/; Secure; HttpOnly',
          ],
        });
      case '/mydisk.php':
        return HttpResult(200, '''<script>var vei='fixture-vei';
          var api='/doupload.php?uid=$userId';</script>''');
      case '/doupload.php':
        return jsonResponse({'zt': fileStatus, 'text': []});
    }
    throw StateError('Unexpected fixture endpoint');
  }
}
