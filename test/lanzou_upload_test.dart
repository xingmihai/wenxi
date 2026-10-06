import 'package:flutter_test/flutter_test.dart';
import 'package:asterlink/core/json.dart';
import 'package:asterlink/data/http.dart';
import 'package:asterlink/data/providers/lanzou.dart';
import 'package:asterlink/data/providers/lanzou_protocol.dart';
import 'package:asterlink/domain/auth.dart';
import 'package:asterlink/domain/models.dart';
import 'package:asterlink/domain/uploads.dart';
import 'support.dart';
import 'lanzou_support.dart';

const _page = r"""<html><script>var uploadVei='fixture-vei';
$.ajax({url:'/doupload.php?uid=12345',data:{'vei':uploadVei}});</script></html>""";
Credential _credential() => Credential('fixture', {
  'primary': 'ylogin=fixture; phpdisk_info=personal-cookie',
}, updatedAt: 42);
const _session = BrowseSession(
  platform: CloudPlatform.lanzou,
  mode: BrowseMode.personal,
  title: 'files',
  rootId: '-1',
);

void main() {
  test('Folder rename preserves its existing description', () async {
    final http = FakeHttp((r) {
      if (r.uri.path == '/mydisk.php') return const HttpResult(200, _page);
      final fields = Uri.splitQueryString(r.body as String);
      if (fields['task'] == '18') {
        expect(fields['folder_id'], '1');
        return jsonResponse({
          'zt': 1,
          'info': {'des': 'original description'},
        });
      }
      expect(fields['task'], '4');
      expect(fields['folder_description'], 'original description');
      expect(fields['folder_name'], 'new name');
      return jsonResponse({'zt': 1});
    });
    await LanzouConnector(http).rename(
      _session,
      const CloudFile(id: 'd:1', name: 'old name', isDirectory: true),
      'new name',
      _credential(),
    );
  });

  test(
    'Folder sharing uses folder_id and can set a retrieval password',
    () async {
      final tasks = <String>[];
      final http = FakeHttp((r) {
        if (r.uri.path == '/mydisk.php') return const HttpResult(200, _page);
        final fields = Uri.splitQueryString(r.body as String);
        tasks.add(fields['task']!);
        expect(fields['folder_id'], '123');
        expect(fields.containsKey('file_id'), false);
        if (fields['task'] == '16') {
          expect(fields['shows'], '1');
          expect(fields['shownames'], 'a7B9');
          return jsonResponse({'zt': 1});
        }
        return jsonResponse({
          'zt': 1,
          'info': {
            'new_url': 'https://wwanc.lanzouq.com/b02vrzkcrg',
            'pwd': 'a7B9',
          },
        });
      });
      final share = await LanzouConnector(http).createShare(
        _session,
        [const CloudFile(id: 'd:123', name: 'folder', isDirectory: true)],
        const ShareOptions('folder', passcode: 'a7B9'),
        _credential(),
      );
      expect(tasks, ['16', '18']);
      expect(share.passcode, 'a7B9');
    },
  );

  test('Membership rejection retains the server explanation', () async {
    final http = FakeHttp(
      (r) => r.uri.path == '/mydisk.php'
          ? const HttpResult(200, _page)
          : jsonResponse({'zt': 0, 'info': '此功能仅会员使用，请先开通会员'}),
    );
    await expectLater(
      LanzouConnector(http).rename(
        _session,
        const CloudFile(id: 'f:1', name: 'old.zip'),
        'new.zip',
        _credential(),
      ),
      throwsA(
        isA<AppException>().having(
          (e) => e.message,
          'message',
          contains('仅会员使用'),
        ),
      ),
    );
  });

  test(
    'Recursive deletion reads the subtree then removes children before parents',
    () async {
      final deletions = <String>[];
      final http = FakeHttp((r) {
        if (r.uri.path == '/mydisk.php') return const HttpResult(200, _page);
        final fields = Uri.splitQueryString(r.body as String);
        if (fields['task'] == '47') {
          expect(deletions, isEmpty);
          return jsonResponse({
            'zt': 1,
            'text': fields['folder_id'] == '1'
                ? [
                    {'fol_id': '2', 'name': 'child'},
                  ]
                : [],
          });
        }
        if (fields['task'] == '5') {
          expect(deletions, isEmpty);
          return jsonResponse({
            'zt': 1,
            'text': fields['folder_id'] == '2' && fields['pg'] == '1'
                ? [
                    {'id': '3', 'name_all': 'fixture.zip', 'size': '1 K'},
                  ]
                : [],
          });
        }
        deletions.add(
          '${fields['task']}:${fields['folder_id'] ?? fields['file_id']}',
        );
        return jsonResponse({'zt': 1});
      });
      await LanzouConnector(http).delete(_session, [
        const CloudFile(id: 'd:1', name: 'parent', isDirectory: true),
        const CloudFile(id: 'd:2', name: 'child', isDirectory: true),
      ], _credential());
      expect(deletions, ['6:3', '3:2', '3:1']);
    },
  );

  test('A subtree listing error prevents any deletion', () async {
    final http = FakeHttp((r) {
      if (r.uri.path == '/mydisk.php') return const HttpResult(200, _page);
      final fields = Uri.splitQueryString(r.body as String);
      expect(fields['task'], '47');
      return jsonResponse({'zt': 0, 'info': '读取目录失败'});
    });
    await expectLater(
      LanzouConnector(http).delete(_session, [
        const CloudFile(id: 'f:3', name: 'fixture.zip'),
        const CloudFile(id: 'd:1', name: 'folder', isDirectory: true),
      ], _credential()),
      throwsA(isA<AppException>()),
    );
  });

  test(
    'Browser login validates file access and retains renewed cookies and identity',
    () async {
      final http = FakeHttp((r) {
        if (r.uri.path == '/mydisk.php') {
          return const HttpResult(200, _page, {
            'Set-Cookie': ['phpdisk_info=renewed; Path=/; HttpOnly'],
          });
        }
        expect(r.uri.path, '/doupload.php');
        expect(r.headers['Cookie'], contains('phpdisk_info=renewed'));
        expect(Uri.splitQueryString(r.body as String), {
          'task': '5',
          'folder_id': '-1',
          'pg': '1',
        });
        return jsonResponse({'zt': 2, 'text': []});
      });
      final result = await LanzouConnector(http).authenticate(_credential());
      expect(result.credential.primary, contains('phpdisk_info=renewed'));
      expect(result.credential.field('userId'), '12345');
      expect(result.credential.updatedAt, 42);
      expect(http.calls, hasLength(2));
    },
  );

  test(
    'A visible disk page does not count as login when file access is denied',
    () async {
      final http = FakeHttp(
        (r) => r.uri.path == '/mydisk.php'
            ? const HttpResult(200, _page)
            : jsonResponse({'zt': 9}),
      );
      await expectLater(
        LanzouConnector(http).authenticate(_credential()),
        throwsA(isA<AccountLoginRequired>()),
      );
    },
  );

  for (final empty in [false, true]) {
    test(
      'Cookie login survives a disk page without API parameters, empty=$empty',
      () async {
        final http = FakeHttp((r) {
          if (r.uri.path == '/mydisk.php') {
            return const HttpResult(200, '<html><div id="files"></div></html>');
          }
          expect(r.uri.path, '/doupload.php');
          expect(r.uri.queryParameters, isEmpty);
          expect(r.headers['Cookie'], contains('phpdisk_info=personal-cookie'));
          expect(Uri.splitQueryString(r.body as String), {
            'task': '5',
            'folder_id': '-1',
            'pg': '1',
          });
          return jsonResponse(
            empty
                ? {'zt': 2}
                : {
                    'zt': 1,
                    'text': [
                      {'id': '7', 'name': 'fixture.txt'},
                    ],
                  },
          );
        });
        final result = await LanzouConnector(http).authenticate(
          Credential('fixture', {
            'primary': 'ylogin=12345; phpdisk_info=personal-cookie',
          }, updatedAt: 42),
        );
        expect(result.credential.field('userId'), '12345');
        expect(
          result.credential.primary,
          contains('phpdisk_info=personal-cookie'),
        );
        expect(result.credential.updatedAt, 42);
        expect(http.calls, hasLength(2));
      },
    );
  }

  for (final invalid in [
    const HttpResult(401, ''),
    jsonResponse({'zt': 9}),
    jsonResponse({'zt': 1}),
    const HttpResult(200, '<html>verification required</html>'),
  ]) {
    test(
      'Missing page parameters never bypass file access validation: ${invalid.status}/${invalid.body}',
      () async {
        final http = FakeHttp(
          (r) => r.uri.path == '/mydisk.php'
              ? const HttpResult(200, '<html>alternate disk page</html>')
              : invalid,
        );
        await expectLater(
          LanzouConnector(http).authenticate(
            Credential('fixture', {
              'primary': 'ylogin=12345; phpdisk_info=personal-cookie',
            }),
          ),
          throwsA(isA<AppException>()),
        );
        expect(http.calls, hasLength(2));
      },
    );
  }

  test('Login scans management paths and the official accounts host', () {
    final target = WebLoginTarget.targets[CloudPlatform.lanzou]!;
    expect(target.url, 'https://pc.woozooo.com/account.php?action=login');
    final urls = target.cookieUrls(
      'https://accounts.woozooo.com/accounts.php?action=login',
    );
    expect(urls.first, 'https://pc.woozooo.com/mydisk.php');
    expect(urls, contains('https://accounts.woozooo.com/accounts.php'));
    expect(
      target.cookieUrls('https://evil.example/mydisk.php'),
      isNot(contains('https://evil.example/mydisk.php')),
    );
    final cookie = LoginCredentials.fromBrowser(
      CloudPlatform.lanzou,
      cookies: ['ylogin=owner; phpdisk_info=path-cookie', 'phpdisk_info=stale'],
    );
    expect(cookie, contains('phpdisk_info=path-cookie'));
    expect(cookie, isNot(contains('stale')));
  });
  test(
    'Lanzou personal login and account parameters preserve anonymous sharing',
    () {
      expect(LanzouPage(_page).accountParameters, {
        'uid': '12345',
        'vei': 'fixture-vei',
      });
      expect(
        LoginCredentials.plausible(CloudPlatform.lanzou, _credential().primary),
        true,
      );
      expect(
        LoginCredentials.plausible(CloudPlatform.lanzou, 'ylogin=only'),
        false,
      );
      expect(
        WebLoginTarget.targets[CloudPlatform.lanzou]!.userAgent,
        contains('Windows NT'),
      );
      expect(CloudPlatform.lanzou.shareRequiresAccount, false);
    },
  );
  test(
    'Lanzou creates a folder, streams the selected bytes and confirms its file ID',
    () async {
      var uploaded = false;
      final received = <int>[];
      final http = FakeHttp((r) async {
        expect(r.uri.host, 'pc.woozooo.com');
        expect(r.headers['Cookie'], contains('phpdisk_info=personal-cookie'));
        if (r.uri.path == '/mydisk.php') return const HttpResult(200, _page);
        if (r.uri.path == '/html5wup.php') fail('Unexpected upload endpoint');
        if (r.uri.path == '/html5up.php') {
          final body = r.body as HttpUpload;
          expect(body.fieldName, 'upload_file');
          expect(body.fields!['folder_id_bb_n'], '7');
          expect(body.fields!['name'], 'sample.txt');
          received.addAll(await body.open().expand((c) => c).toList());
          uploaded = true;
          return jsonResponse({
            'zt': 1,
            'text': [
              {'id': '42', 'name_all': 'sample.txt', 'size': '0.1 K'},
            ],
          });
        }
        expect(r.uri.queryParameters, {'uid': '12345', 'vei': 'fixture-vei'});
        final fields = Uri.splitQueryString(r.body as String);
        switch (fields['task']) {
          case '2':
            expect(fields['parent_id'], '-1');
            expect(fields['folder_name'], 'new folder');
            return jsonResponse({'zt': 1, 'text': '7'});
          case '47':
            return jsonResponse({'zt': 1, 'text': []});
          case '5':
            return jsonResponse({
              'zt': fields['pg'] == '1' ? 1 : 2,
              'text': uploaded && fields['pg'] == '1'
                  ? [
                      {'id': '42', 'name_all': 'sample.txt', 'size': '0.1 K'},
                    ]
                  : [],
            });
          default:
            throw StateError('Unexpected task');
        }
      });
      final connector = LanzouConnector(http), c = _credential();
      final folder = await connector.createFolder(
        _session,
        '-1',
        'new folder',
        c,
      );
      expect(folder.id, 'd:7');
      final file = await connector.upload(
        _session,
        folder.id,
        UploadFile(
          name: 'sample.txt',
          size: 3,
          read: (start, end) => Stream.value([1, 2, 3].sublist(start, end)),
        ),
        c,
      );
      expect(file.id, 'f:42');
      expect(file.parentId, 'd:7');
      expect(received, [1, 2, 3]);
    },
  );
  test(
    'Lanzou personal download uses the returned share domain without leaking account cookies',
    () async {
      final public = LanzouFixture()..exactSize = 3;
      final http = FakeHttp((r) async {
        if (r.uri.host == 'pc.woozooo.com') {
          if (r.uri.path == '/mydisk.php') return const HttpResult(200, _page);
          expect(Uri.splitQueryString(r.body as String)['task'], '22');
          return jsonResponse({
            'zt': 1,
            'info': {
              'f_id': 'iExample123',
              'is_newd': 'https://author.lanzouu.com',
              'pwd': '',
            },
          });
        }
        expect(r.headers['Cookie'] ?? '', isNot(contains('personal-cookie')));
        return public.respond(r);
      });
      final spec = await LanzouConnector(http).download(
        _session,
        const CloudFile(
          id: 'f:42',
          name: 'sample.txt',
          size: 103,
          parentId: 'd:7',
        ),
        _credential(),
      );
      expect(spec.url, lanzouTestFinal);
      expect(spec.expectedSize, 3);
      expect(spec.headers.values.join(), isNot(contains('personal-cookie')));
    },
  );
  test(
    'Lanzou login expiry and upload rejection never report success',
    () async {
      for (final status in [401, 200]) {
        final http = FakeHttp(
          (r) => r.uri.path == '/mydisk.php'
              ? const HttpResult(200, _page)
              : status == 401
              ? const HttpResult(401, '<html>login</html>')
              : jsonResponse({'zt': 0, 'info': 'unsupported'}),
        );
        await expectLater(
          LanzouConnector(http).upload(
            _session,
            '-1',
            UploadFile(
              name: 'sample.txt',
              size: 1,
              read: (start, end) => Stream.value([1]),
            ),
            _credential(),
          ),
          throwsA(isA<AppException>()),
        );
        expect(http.calls.any((r) => r.uri.path == '/doupload.php'), false);
      }
    },
  );
}
