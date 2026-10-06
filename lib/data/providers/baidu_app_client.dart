import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import '../../core/json.dart';
import '../../domain/models.dart';
import '../state_store.dart';

/// One installation identity is shared by SAPI, preview and ordinary requests.
/// It is independent of account cookies and never uses hardware identifiers.
class BaiduAppClient {
  BaiduAppClient({
    this.store,
    Future<Json> Function()? readEnvironment,
    String? deviceId,
  }) : _readEnvironment = readEnvironment ?? _nativeEnvironment,
       _deviceId = deviceId ?? '${newId().replaceAll('-', '').toUpperCase()}|0';

  static const version = '13.15.4';
  static const downloadVersion = version;
  static const fallbackUserAgent =
      'netdisk;$version;AsterLink;android-android;13;JSbridge4.4.0;jointBridge;1.1.0;';
  static const _deviceKey = 'baidu.installation_device';
  static const _channel = MethodChannel('com.asterlink.app/native');
  final CredentialStore? store;
  final Future<Json> Function() _readEnvironment;
  String _deviceId;
  Future<void>? _initializing;
  Json _environment = {};

  String get deviceId => _deviceId;
  String get _model => _environment.str('model').trim().ifEmpty('AsterLink');
  String get _release => _environment.str('osVersion').trim().ifEmpty('13');
  // Android uses Java URLEncoder for these two UA fields.
  String get userAgent => _agentForVersion(version);
  String get downloadUserAgent => _agentForVersion(downloadVersion);
  String _agentForVersion(String agentVersion) =>
      'netdisk;$agentVersion;${Uri.encodeQueryComponent(_model)};android-android;'
      '${Uri.encodeQueryComponent(_release)};JSbridge4.4.0;jointBridge;1.1.0;';
  String get channel => 'android_${_release}_${_model}_bd-netdisk_1';

  Json get serviceDevice => {
    'downloadVersion': downloadVersion,
    'id': deviceId,
    'model': _model,
    'osVersion': _release,
    'networkType': _environment.str('networkType'),
    'networkSubtype': _environment.integer('networkSubtype').clamp(0, 100),
  };

  Map<String, Object?> get parameters {
    final network = _environment.str('networkType').toLowerCase();
    final validNetwork = RegExp(r'^[a-z0-9._-]{1,64}$').hasMatch(network);
    final subtype = _environment.integer('networkSubtype').clamp(0, 100);
    final apn = switch (network) {
      'wifi' => 1,
      '3gnet' => 21,
      '3gwap' => 22,
      'cmnet' => 31,
      'uninet' => 32,
      'ctnet' => 33,
      'cmwap' => 41,
      'uniwap' => 42,
      'ctwap' => 43,
      _ => 0,
    };
    return {
      'devuid': deviceId,
      'cuid': deviceId,
      if (validNetwork) 'network_type': network,
      'apn_id': validNetwork ? '${apn}_$subtype' : '0_0',
      'freeisp': 0,
      // The App's default is 2 (no configured traffic-free query). A value of
      // 0 is rejected by locatedownload with errno 31023.
      'queryfree': 2,
    };
  }

  Future<void> prepare() async {
    try {
      await (_initializing ??= _loadIdentity());
    } catch (_) {
      _initializing = null;
      rethrow;
    }
    _environment = await _readEnvironment();
  }

  Future<void> _loadIdentity() async {
    final saved = store?.secret(_deviceKey);
    if (saved != null && RegExp(r'^[A-Fa-f0-9]{32}\|0$').hasMatch(saved)) {
      _deviceId = saved;
    } else {
      await store?.putSecret(_deviceKey, _deviceId);
    }
  }

  static Future<Json> _nativeEnvironment() async {
    // Windows uses the compatible Android protocol profile without inventing
    // a phone's network/APN. Missing native support must not block downloads.
    if (!Platform.isAndroid) return {};
    try {
      return asJson(
        await _channel
            .invokeMethod<Object?>('clientEnvironment')
            .timeout(const Duration(seconds: 2)),
      );
    } on MissingPluginException {
      return {};
    } on PlatformException {
      return {};
    } on TimeoutException {
      return {};
    }
  }
}
