import '../core/json.dart';
import 'models.dart';

class BrowserDisplaySettings {
  const BrowserDisplaySettings({
    this.view = 'list',
    this.sort = 'name',
    this.ascending = true,
  });

  final String view, sort;
  final bool ascending;

  Json toJson() => {'view': view, 'sort': sort, 'ascending': ascending};

  factory BrowserDisplaySettings.fromJson(Json j) => BrowserDisplaySettings(
    view: j.str('view') == 'grid' ? 'grid' : 'list',
    sort: ['name', 'size', 'date'].contains(j.str('sort'))
        ? j.str('sort')
        : 'name',
    ascending: j.boolean('ascending', true),
  );
}

class AppSettings {
  const AppSettings({
    this.theme = 'System',
    this.threads = 64,
    this.concurrent = 3,
    this.retries = 3,
    this.speedLimit = 0,
    this.threadOverrides = const {},
    this.destination,
    this.browserView = 'list',
    this.browserDisplays = const {},
    this.clipboardRecognition = true,
    this.quarkGuestDirectDownload = false,
    this.ucGuestDirectDownload = false,
    this.quarkAuthenticatedDirectDownload = false,
    this.hideGuestDownloadNotice = false,
    this.hideBaiduDownloadNotice = false,
  });
  final String theme;
  final int threads, concurrent, retries, speedLimit;
  final Map<String, int> threadOverrides;
  final String? destination;
  final String browserView;
  final Map<String, BrowserDisplaySettings> browserDisplays;
  BrowserDisplaySettings browserDisplayFor(CloudPlatform platform) =>
      browserDisplays[platform.key] ??
      BrowserDisplaySettings(view: browserView);
  final bool clipboardRecognition;
  final bool quarkGuestDirectDownload;
  final bool ucGuestDirectDownload;
  final bool quarkAuthenticatedDirectDownload;
  final bool hideGuestDownloadNotice;
  final bool hideBaiduDownloadNotice;
  static const profiles = {
    'feijipan': ('小飞机网盘', 8),
    'ctfile': ('城通网盘', 8),
    'baidu': ('百度网盘', 1),
    'quark_route_1': ('夸克 · 直链', 512),
    'quark_route_2': ('夸克 · 快传', 64),
    'uc': ('UC网盘', 512),
    'xunlei': ('迅雷网盘', 64),
    'pan123': ('123网盘', 64),
    'guangya': ('光鸭云盘', 64),
    'aliyun': ('阿里云盘', 64),
    'yidong': ('中国移动云盘', 64),
    'tianyi': ('天翼云盘', 64),
    'ilanzou': ('蓝奏云优享版', 64),
    'weiyun': ('腾讯微云', 64),
    'pan115': ('115网盘', 16),
    'wopan': ('中国联通云盘', 64),
  };
  String? connectionProfileFor(CloudPlatform? platform, [String? profile]) =>
      profile == 'baidu_preview' || profiles.containsKey(profile)
      ? profile
      : switch (platform) {
          CloudPlatform.feijipan => 'feijipan',
          CloudPlatform.ctfile => 'ctfile',
          CloudPlatform.baidu => 'baidu',
          CloudPlatform.quark => 'quark_route_1',
          CloudPlatform.uc => 'uc',
          CloudPlatform.xunlei => 'xunlei',
          CloudPlatform.pan123 => 'pan123',
          CloudPlatform.guangya => 'guangya',
          CloudPlatform.aliyun => 'aliyun',
          CloudPlatform.c139 => 'yidong',
          CloudPlatform.tianyi => 'tianyi',
          CloudPlatform.ilanzou => 'ilanzou',
          CloudPlatform.weiyun => 'weiyun',
          CloudPlatform.pan115 => 'pan115',
          CloudPlatform.wopan => 'wopan',
          CloudPlatform.lanzou || null => null,
        };
  int connectionsFor(CloudPlatform? platform, [String? profile]) {
    if (platform == CloudPlatform.baidu ||
        profile == 'baidu' ||
        profile == 'baidu_preview') {
      return 1;
    }
    final key = connectionProfileFor(platform, profile);
    if (key == null) return threads.clamp(1, 512);
    final override = threadOverrides[key];
    final configured =
        (override == null
                ? profiles[key]!.$2
                : override == 0
                ? threads
                : override)
            .clamp(1, 512);
    return configured;
  }

  Json toJson() => {
    'theme': theme,
    'threads': threads,
    'concurrent': concurrent,
    'retries': retries,
    'speedLimit': speedLimit,
    'downloadThreadOverrides': threadOverrides,
    'destination': destination,
    'browserView': browserView,
    'browserDisplays': {
      for (final entry in browserDisplays.entries)
        entry.key: entry.value.toJson(),
    },
    'clipboardRecognition': clipboardRecognition,
    'quarkGuestDirectDownload': quarkGuestDirectDownload,
    'ucGuestDirectDownload': ucGuestDirectDownload,
    'quarkAuthenticatedDirectDownload': quarkAuthenticatedDirectDownload,
    'hideGuestDownloadNotice': hideGuestDownloadNotice,
    'hideBaiduDownloadNotice': hideBaiduDownloadNotice,
  };
  factory AppSettings.fromJson(Json j) => AppSettings(
    theme: ['System', 'Light', 'Dark'].contains(j.str('theme'))
        ? j.str('theme')
        : 'System',
    threads: j.integer('threads', 64).clamp(1, 512),
    concurrent: j.integer('concurrent', 3).clamp(1, 3),
    retries: j.integer('retries', 3).clamp(0, 3),
    speedLimit: j.integer('speedLimit').clamp(0, 1 << 50),
    threadOverrides: {
      for (final e in j.obj('downloadThreadOverrides').entries)
        if (profiles.containsKey(e.key))
          e.key: (int.tryParse('${e.value}') ?? 0).clamp(0, 512),
    },
    destination: j['destination']?.toString(),
    browserView: j.str('browserView') == 'grid' ? 'grid' : 'list',
    browserDisplays: {
      for (final entry in j.obj('browserDisplays').entries)
        if (CloudPlatform.fromKey(entry.key) != null && entry.value is Map)
          entry.key: BrowserDisplaySettings.fromJson(asJson(entry.value)),
    },
    clipboardRecognition: j.boolean('clipboardRecognition', true),
    quarkGuestDirectDownload: j.boolean('quarkGuestDirectDownload', false),
    ucGuestDirectDownload: j.boolean('ucGuestDirectDownload', false),
    quarkAuthenticatedDirectDownload: j.boolean(
      'quarkAuthenticatedDirectDownload',
      false,
    ),
    hideGuestDownloadNotice: j.boolean('hideGuestDownloadNotice', false),
    hideBaiduDownloadNotice: j.boolean('hideBaiduDownloadNotice', false),
  );
  AppSettings update(Json fields) =>
      AppSettings.fromJson({...toJson(), ...fields});
}
