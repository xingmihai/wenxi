import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import '../core/crypto_box.dart';
import '../core/json.dart';

class StateKeyRead {
  final keys = <Uint8List>[];
  bool unavailable = false, invalid = false;
  String? primary, copy;
  bool needsRepair(Uint8List key) =>
      primary != base64Encode(key) || copy != base64Encode(key);
}

/// Only a namespace and a password-encrypted key envelope live beside the state.
/// A second secure record repairs individual records, not a lost OS keystore.
class LocalStateKey {
  LocalStateKey(this.directory, this.storage);
  final Directory directory;
  final FlutterSecureStorage storage;
  static const name = 'asterlink.flutter.state-key.v1';
  static const locationName = 'state-key-location.json';
  static const recoveryName = 'state-key-recovery.json';
  static const sidecars = [
    locationName,
    '$locationName.tmp',
    recoveryName,
    '$recoveryName.tmp',
  ];
  static const options = AndroidOptions(
    resetOnError: false,
    migrateWithBackup: true,
  );
  static const channel = MethodChannel('com.asterlink.app/native');
  static final _namespacePattern = RegExp(r'^state_[a-f0-9]{32}$');

  File localFile(String name) => File(p.join(directory.path, name));

  Future<String?> _namespace() async {
    final file = localFile(locationName);
    if (!await file.exists()) return null;
    require(await file.length() <= 1024, '本地密钥位置记录损坏');
    final value = asJson(
      jsonDecode(await file.readAsString()),
    ).str('namespace');
    require(_namespacePattern.hasMatch(value), '本地密钥位置记录损坏');
    return value;
  }

  AndroidOptions _options(String? namespace) => namespace == null
      ? options
      : AndroidOptions(
          resetOnError: false,
          migrateWithBackup: true,
          storageNamespace: namespace,
        );
  String _name(String? namespace) =>
      namespace == null ? name : '$name.$namespace';

  Future<String?> _read(String key, String? namespace) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await storage.read(key: key, aOptions: _options(namespace));
      } on PlatformException {
        if (attempt >= 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
      }
    }
  }

  Future<StateKeyRead> read() async {
    final result = StateKeyRead();
    String? namespace;
    try {
      namespace = await _namespace();
    } on FormatException {
      result.invalid = true;
      return result;
    } on AppException {
      result.invalid = true;
      return result;
    }
    for (final copy in [false, true]) {
      try {
        final value = await _read(
          '${_name(namespace)}${copy ? '.copy' : ''}',
          namespace,
        );
        if (copy) {
          result.copy = value;
        } else {
          result.primary = value;
        }
        if (value == null) continue;
        final key = base64Decode(value);
        if (key.length != 32) {
          result.invalid = true;
        } else if (!result.keys.any((k) => listEquals(k, key))) {
          result.keys.add(key);
        }
      } on PlatformException {
        result.unavailable = true;
      } on FormatException {
        result.invalid = true;
      }
    }
    return result;
  }

  Future<void> _write(Uint8List key, String? namespace) async {
    require(key.length == 32, '本地密钥格式错误');
    final value = base64Encode(key);
    for (final suffix in ['', '.copy']) {
      await storage.write(
        key: '${_name(namespace)}$suffix',
        value: value,
        aOptions: _options(namespace),
      );
    }
    if (Platform.isAndroid) {
      require(
        await channel.invokeMethod<bool>('flushStateKeyStorage', {
              'namespace': namespace,
            }) ==
            true,
        '本地密钥未能保存到设备，请检查可用存储空间后重试',
      );
    }
    for (final suffix in ['', '.copy']) {
      require(
        await _read('${_name(namespace)}$suffix', namespace) == value,
        '本地加密密钥保存失败，请检查系统安全存储后重试',
      );
    }
  }

  Future<void> save(Uint8List key) async => _write(key, await _namespace());

  /// Call only with a key authenticated against local data or a verified backup.
  /// Old storage is left intact; the pointer switches only after durable writes.
  Future<void> saveFresh(Uint8List key) async {
    final namespace =
        'state_${CryptoBox.random(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    await _write(key, namespace);
    await writeAtomic(
      localFile(locationName),
      utf8.encode(jsonEncode({'namespace': namespace})),
    );
  }

  Future<bool> canUnlock() => localFile(recoveryName).exists();

  Future<Uint8List> prepareRecovery(Uint8List key, String password) =>
      compute(_wrapKey, (key, password));

  Future<Uint8List> unlock(String password) async {
    final file = localFile(recoveryName);
    require(await file.exists(), '此设备尚未建立密码恢复保护，请选择备份文件恢复');
    require(await file.length() <= 8192, '本地密码恢复文件损坏');
    return compute(_unwrapKey, (await file.readAsBytes(), password));
  }

  Future<void> installRecovery(List<int> bytes) =>
      writeAtomic(localFile(recoveryName), bytes);

  static Future<void> writeAtomic(File file, List<int> bytes) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    require(listEquals(bytes, await temporary.readAsBytes()), '本地文件保存校验失败');
    await temporary.rename(file.path);
  }
}

const _purpose = 'wenxi-local-state-key-v1';

Uint8List _wrapKey((Uint8List, String) input) {
  require(input.$2.length >= 6, '备份密码至少需要 6 位');
  final salt = CryptoBox.random(16);
  final wrappingKey = CryptoBox.derive(input.$2, salt, 210000);
  final plain = Uint8List.fromList(
    utf8.encode(
      jsonEncode({'purpose': _purpose, 'key': base64Encode(input.$1)}),
    ),
  );
  try {
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': _purpose,
          'salt': base64Encode(salt),
          'iterations': 210000,
          'data': base64Encode(CryptoBox.seal(wrappingKey, plain)),
        }),
      ),
    );
  } finally {
    wrappingKey.fillRange(0, wrappingKey.length, 0);
    plain.fillRange(0, plain.length, 0);
  }
}

Uint8List _unwrapKey((Uint8List, String) input) {
  Uint8List? wrappingKey, plain;
  try {
    final envelope = asJson(jsonDecode(utf8.decode(input.$1)));
    require(envelope.str('format') == _purpose, '恢复文件格式错误');
    wrappingKey = CryptoBox.derive(
      input.$2,
      base64Decode(envelope.str('salt')),
      envelope.integer('iterations'),
    );
    plain = CryptoBox.open(wrappingKey, base64Decode(envelope.str('data')));
    final payload = asJson(jsonDecode(utf8.decode(plain)));
    require(payload.str('purpose') == _purpose, '恢复文件格式错误');
    final key = base64Decode(payload.str('key'));
    require(key.length == 32, '恢复密钥格式错误');
    return key;
  } on FormatException {
    throw const AppException('备份密码错误或本地恢复文件已损坏');
  } on AppException {
    throw const AppException('备份密码错误或本地恢复文件已损坏');
  } finally {
    wrappingKey?.fillRange(0, wrappingKey.length, 0);
    plain?.fillRange(0, plain.length, 0);
  }
}
