import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:asterlink/app_services.dart';
import 'package:asterlink/core/json.dart';
import 'package:asterlink/data/backup.dart';
import 'package:asterlink/data/state_store.dart';
import 'package:asterlink/domain/models.dart';
import 'package:asterlink/domain/settings.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Legacy display migrates and invalid per-cloud options fall back safely',
    () {
      final legacy = AppSettings.fromJson({'browserView': 'grid'});
      for (final platform in CloudPlatform.values) {
        expect(legacy.browserDisplayFor(platform).view, 'grid');
        expect(legacy.browserDisplayFor(platform).sort, 'name');
        expect(legacy.browserDisplayFor(platform).ascending, isTrue);
      }
      final invalid = AppSettings.fromJson({
        'browserDisplays': {
          'quark': {'view': 'bad', 'sort': 'bad', 'ascending': 'bad'},
          'baidu': null,
          'unknown': {'view': 'grid'},
        },
      });
      expect(invalid.browserDisplayFor(CloudPlatform.quark).toJson(), {
        'view': 'list',
        'sort': 'name',
        'ascending': true,
      });
      expect(invalid.browserDisplays.keys, ['quark']);
    },
  );

  test(
    'Per-cloud preferences survive simultaneous saves, disk reopen and backup',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'browser-preferences-',
      );
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final store = await StateStore.open(directory, testKey: key);
      final services = AppServices(
        controlEnabled: false,
        store: store,
        dataDirectory: directory,
        cacheDirectory: Directory('${directory.path}/cache'),
        transport: FakeNative(),
        files: FakeFiles(Directory('${directory.path}/saved')),
        platformFeatures: false,
        http: FakeHttp(),
      );
      var closed = false;
      try {
        await services.initialize();
        await Future.wait([
          services.updateBrowserDisplay(CloudPlatform.quark, view: 'grid'),
          services.updateBrowserDisplay(CloudPlatform.quark, sort: 'date'),
          services.updateSettings({'theme': 'Dark'}),
          services.updateBrowserDisplay(CloudPlatform.uc, sort: 'size'),
        ]);
        await services.updateBrowserDisplay(CloudPlatform.quark, sort: 'date');
        final expected = {'view': 'grid', 'sort': 'date', 'ascending': false};
        expect(
          services.settings.browserDisplayFor(CloudPlatform.quark).toJson(),
          expected,
        );
        expect(services.settings.browserDisplayFor(CloudPlatform.uc).toJson(), {
          'view': 'list',
          'sort': 'size',
          'ascending': true,
        });
        expect(
          services.settings.browserDisplayFor(CloudPlatform.baidu).toJson(),
          {'view': 'list', 'sort': 'name', 'ascending': true},
        );
        expect(services.settings.theme, 'Dark');
        await services.close();
        closed = true;
        final reopened = await StateStore.open(directory, testKey: key);
        expect(
          AppSettings.fromJson(
            reopened.data.obj('settings'),
          ).browserDisplayFor(CloudPlatform.quark).toJson(),
          expected,
        );
        final backup = await BackupRepository(
          reopened,
        ).create('fixture-password');
        final restored = StateStore.memory();
        await BackupRepository(restored).restore(backup, 'fixture-password');
        expect(
          AppSettings.fromJson(
            restored.data.obj('settings'),
          ).browserDisplayFor(CloudPlatform.quark).toJson(),
          expected,
        );
        expect(
          AppSettings.fromJson(restored.data.obj('settings')).theme,
          'Dark',
        );
      } finally {
        if (!closed) await services.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
