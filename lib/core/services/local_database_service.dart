import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalDatabaseService {
  LocalDatabaseService._();

  static const String boxName = 'store_manager_local_db';
  static const String _encryptionKeyPrefsKey = 'ventio_local_db_key_v1';
  static const String _legacyEncryptionKeyPrefsKey = 'store_manager_local_db_key_v1';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static Box<String>? _box;
  static Map<String, String>? _memoryStoreForTesting;

  @visibleForTesting
  static void useInMemoryStoreForTesting([Map<String, String>? seed]) {
    _memoryStoreForTesting = Map<String, String>.from(seed ?? const <String, String>{});
    _box = null;
  }

  @visibleForTesting
  static void clearInMemoryStoreForTesting() {
    _memoryStoreForTesting = null;
  }

  static Future<void> initialize() async {
    if (_memoryStoreForTesting != null) return;
    if (_box != null && _box!.isOpen) return;

    // Web-safe initialization. Hive.initFlutter() works on Flutter Web and
    // desktop/mobile without importing dart:io. Direct Platform/Directory usage
    // breaks dart2js compilation.
    await Hive.initFlutter();

    final key = await _loadOrCreateEncryptionKey();
    _box = await Hive.openBox<String>(boxName, encryptionCipher: HiveAesCipher(key));
  }

  static Future<Uint8List> _loadOrCreateEncryptionKey() async {
    final secureExisting = await _secureStorage.read(key: _encryptionKeyPrefsKey);
    if (secureExisting != null && secureExisting.isNotEmpty) {
      return Uint8List.fromList(base64Url.decode(secureExisting));
    }

    // One-time migration from the older SharedPreferences key storage.
    final prefs = await SharedPreferences.getInstance();
    final legacyExisting = prefs.getString(_legacyEncryptionKeyPrefsKey) ?? prefs.getString(_encryptionKeyPrefsKey);
    if (legacyExisting != null && legacyExisting.isNotEmpty) {
      await _secureStorage.write(key: _encryptionKeyPrefsKey, value: legacyExisting);
      await prefs.remove(_legacyEncryptionKeyPrefsKey);
      await prefs.remove(_encryptionKeyPrefsKey);
      return Uint8List.fromList(base64Url.decode(legacyExisting));
    }

    final random = Random.secure();
    final key = Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
    await _secureStorage.write(key: _encryptionKeyPrefsKey, value: base64UrlEncode(key));
    return key;
  }

  static Map<String, String>? get _memoryStore => _memoryStoreForTesting;

  static Box<String> get _requireBox {
    final box = _box;
    if (box == null || !box.isOpen) {
      throw StateError('Local database has not been initialized.');
    }
    return box;
  }

  static String? getString(String key) {
    final memory = _memoryStore;
    if (memory != null) return memory[key];
    return _requireBox.get(key);
  }

  static Future<void> setString(String key, String value) async {
    final memory = _memoryStore;
    if (memory != null) {
      memory[key] = value;
      return;
    }
    await _requireBox.put(key, value);
  }

  static bool containsKey(String key) {
    final memory = _memoryStore;
    if (memory != null) return memory.containsKey(key);
    return _requireBox.containsKey(key);
  }

  static Future<void> deleteString(String key) async {
    final memory = _memoryStore;
    if (memory != null) {
      memory.remove(key);
      return;
    }
    await _requireBox.delete(key);
  }

  static Future<void> clearAll() async {
    final memory = _memoryStore;
    if (memory != null) {
      memory.clear();
      return;
    }
    await _requireBox.clear();
  }

  static bool get isEmpty {
    final memory = _memoryStore;
    if (memory != null) return memory.isEmpty;
    return _requireBox.isEmpty;
  }
}
