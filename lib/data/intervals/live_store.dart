import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Where the intervals.icu API key lives.
abstract interface class KeyStore {
  Future<String?> read();
  Future<void> write(String? value);
}

/// iOS Keychain / Android Keystore.
class SecureKeyStore implements KeyStore {
  const SecureKeyStore();
  static const _key = 'intervals_api_key';
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      return null; // no keychain (tests, unsupported platform)
    }
  }

  @override
  Future<void> write(String? value) =>
      value == null ? _storage.delete(key: _key) : _storage.write(key: _key, value: value);
}

class MemoryKeyStore implements KeyStore {
  MemoryKeyStore([this.value]);
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String? v) async => value = v;
}

/// The synced data set, kept on the phone between launches.
abstract interface class LiveFile {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic>? data);
}

/// A JSON file in the app's private support directory.
class AppLiveFile implements LiveFile {
  const AppLiveFile();

  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/intervals_sync.json');

  static Map<String, dynamic> _decode(String raw) => jsonDecode(raw) as Map<String, dynamic>;

  @override
  Future<Map<String, dynamic>?> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      return await compute(_decode, await f.readAsString());
    } catch (_) {
      return null; // missing or unreadable: the next sync rebuilds it
    }
  }

  @override
  Future<void> write(Map<String, dynamic>? data) async {
    final f = await _file();
    if (data == null) {
      if (await f.exists()) await f.delete();
      return;
    }
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(data), flush: true);
  }
}

class MemoryLiveFile implements LiveFile {
  MemoryLiveFile([this.data]);
  Map<String, dynamic>? data;

  @override
  Future<Map<String, dynamic>?> read() async => data;

  @override
  Future<void> write(Map<String, dynamic>? d) async => data = d;
}
