import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalDatabaseService {
  LocalDatabaseService._();

  static const String boxName = 'store_manager_local_db';
  static const String _encryptionKeyPrefsKey = 'store_manager_local_db_key_v1';
  static Box<String>? _box;

  static Future<void> initialize() async {
    if (_box != null && _box!.isOpen) return;

    // Web-safe initialization. Hive.initFlutter() works on Flutter Web and
    // desktop/mobile without importing dart:io. Direct Platform/Directory usage
    // breaks dart2js compilation.
    await Hive.initFlutter();

    final key = await _loadOrCreateEncryptionKey();
    _box = await Hive.openBox<String>(boxName, encryptionCipher: HiveAesCipher(key));
  }

  static Future<Uint8List> _loadOrCreateEncryptionKey() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_encryptionKeyPrefsKey);
    if (existing != null && existing.isNotEmpty) {
      return Uint8List.fromList(base64Url.decode(existing));
    }

    final random = Random.secure();
    final key = Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
    await prefs.setString(_encryptionKeyPrefsKey, base64UrlEncode(key));
    return key;
  }

  static Box<String> get _requireBox {
    final box = _box;
    if (box == null || !box.isOpen) {
      throw StateError('Local database has not been initialized.');
    }
    return box;
  }

  static String? getString(String key) => _requireBox.get(key);

  static Future<void> setString(String key, String value) async {
    await _requireBox.put(key, value);
  }

  static bool containsKey(String key) => _requireBox.containsKey(key);

  static Future<void> deleteString(String key) async {
    await _requireBox.delete(key);
  }

  static bool get isEmpty => _requireBox.isEmpty;
}
