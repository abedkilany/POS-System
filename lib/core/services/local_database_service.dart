import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'local_database_path.dart';
import '../storage/sqlite/business_sqlite_store.dart';
import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/sync_sqlite_store.dart';
import '../../models/sync_change.dart';
import '../../models/sync_queue_item.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalDatabaseService {
  LocalDatabaseService._();

  static const String boxName = 'ventio';
  static const String _encryptionKeyPrefsKey = 'ventio_local_db_key_v1';
  static const String _legacyEncryptionKeyPrefsKey = 'store_manager_local_db_key_v1';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _cloudApiTokenKey = 'cloud_api_token';
  static const String _appIdentityKey = 'app_identity_v1';
  static const String _secureDeviceTokenKey = 'app_identity_device_token_v1';
  static final Map<String, String> _secureStringMirror = <String, String>{};
  static Box<String>? _box;
  static Map<String, String>? _memoryStoreForTesting;
  static final Map<String, String> _sqliteMirror = <String, String>{};
  static bool _sqliteReady = false;

  static bool get isSqliteAuthoritative => _sqliteReady && SqliteMigrationManager.database != null;

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

    // If phase 3B has already been validated on this device, start directly
    // from SQLite and do not open Hive. This is the practical retirement path:
    // Hive is only opened once on older installs that still need migration.
    if (!kIsWeb) {
      final existingSqliteStatus = await SqliteMigrationManager.initializeFromExistingSqliteIfValidated();
      var existingDb = SqliteMigrationManager.database;
      if (existingSqliteStatus.sqliteFoundationReady && existingDb != null) {
        _sqliteMirror
          ..clear()
          ..addAll(await BusinessSqliteStore.hydrateScalarKeyMirror(existingDb))
          ..addAll(await SyncSqliteStore.hydrateScalarKeyMirror(existingDb));
        _sqliteReady = true;
        await _hydrateAndMigrateSecureScalars();
        await retireLegacyVentioHiveFilesIfPresent();
        return;
      }

      // Fresh installs do not have a legacy Hive box to migrate. Do not call
      // Hive.openBox in that case, because merely opening the box creates
      // AppData\Roaming\ventio\ventio.hive even though SQLite is the
      // authoritative storage engine.
      final legacyHiveExists = await hasLegacyVentioHiveDatabase();
      if (!legacyHiveExists) {
        final freshSqliteStatus = await SqliteMigrationManager.initializeFreshSqlite();
        existingDb = SqliteMigrationManager.database;
        if (freshSqliteStatus.sqliteFoundationReady && existingDb != null) {
          _sqliteMirror
            ..clear()
            ..addAll(await BusinessSqliteStore.hydrateScalarKeyMirror(existingDb))
            ..addAll(await SyncSqliteStore.hydrateScalarKeyMirror(existingDb));
          _sqliteReady = true;
          await _hydrateAndMigrateSecureScalars();
          return;
        }
      }
    }

    // Keep web on Hive's browser-safe storage, but force desktop/mobile to use
    // the application support directory instead of user-visible folders such as
    // Documents. On Windows this resolves under AppData\Roaming.
    if (kIsWeb) {
      await Hive.initFlutter();
    } else {
      final hiveDirectoryPath = await getVentioHiveDirectoryPath();
      Hive.init(hiveDirectoryPath);
    }

    final key = await _loadOrCreateEncryptionKey();
    _box = await Hive.openBox<String>(boxName, encryptionCipher: HiveAesCipher(key));

    // Phase 1 SQLite/Drift foundation: initialize the parallel SQLite store
    // and write a Hive safety backup. This is deliberately non-authoritative
    // so existing devices keep using Hive until the later migration phases.
    final sqliteStatus = await SqliteMigrationManager.initializePhase3();
    final db = SqliteMigrationManager.database;
    if (sqliteStatus.sqliteFoundationReady && db != null) {
      _sqliteMirror
        ..clear()
        ..addAll(await BusinessSqliteStore.hydrateScalarKeyMirror(db))
        ..addAll(await SyncSqliteStore.hydrateScalarKeyMirror(db));
      _sqliteReady = true;
      await _hydrateAndMigrateSecureScalars();
      if (!kIsWeb) await retireLegacyVentioHiveFilesIfPresent();
    }
    if (!_sqliteReady) {
      await _hydrateAndMigrateSecureScalars();
    }
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

  static Future<void> _hydrateAndMigrateSecureScalars() async {
    final secureCloudToken = await _secureStorage.read(key: _cloudApiTokenKey);
    if (secureCloudToken != null) {
      _secureStringMirror[_cloudApiTokenKey] = secureCloudToken;
    }
    final secureDeviceToken = await _secureStorage.read(key: _secureDeviceTokenKey);
    if (secureDeviceToken != null) {
      _secureStringMirror[_secureDeviceTokenKey] = secureDeviceToken;
    }

    final legacyCloudToken = _rawScalarValue(_cloudApiTokenKey)?.trim() ?? '';
    if (legacyCloudToken.isNotEmpty && (_secureStringMirror[_cloudApiTokenKey] ?? '').isEmpty) {
      await _secureStorage.write(key: _cloudApiTokenKey, value: legacyCloudToken);
      _secureStringMirror[_cloudApiTokenKey] = legacyCloudToken;
    }
    await _deleteRawScalarValue(_cloudApiTokenKey);

    final rawIdentity = _rawScalarValue(_appIdentityKey);
    if (rawIdentity != null && rawIdentity.trim().isNotEmpty) {
      final decoded = _tryDecodeJsonMap(rawIdentity);
      final legacyDeviceToken = (decoded?['deviceToken'] ?? decoded?['device_token'] ?? '').toString().trim();
      if (legacyDeviceToken.isNotEmpty && (_secureStringMirror[_secureDeviceTokenKey] ?? '').isEmpty) {
        await _secureStorage.write(key: _secureDeviceTokenKey, value: legacyDeviceToken);
        _secureStringMirror[_secureDeviceTokenKey] = legacyDeviceToken;
      }
      final sanitized = _sanitizeAppIdentityJson(rawIdentity);
      if (sanitized != rawIdentity) await _writeRawScalarValue(_appIdentityKey, sanitized);
    }
  }

  static Map<String, dynamic>? _tryDecodeJsonMap(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static String _sanitizeAppIdentityJson(String value) {
    final decoded = _tryDecodeJsonMap(value);
    if (decoded == null) return value;
    decoded.remove('deviceToken');
    decoded.remove('device_token');
    return jsonEncode(decoded);
  }

  static String _mergeSecureDeviceTokenIntoIdentityJson(String value) {
    final token = (_secureStringMirror[_secureDeviceTokenKey] ?? '').trim();
    if (token.isEmpty) return value;
    final decoded = _tryDecodeJsonMap(value);
    if (decoded == null) return value;
    decoded['deviceToken'] = token;
    return jsonEncode(decoded);
  }

  static String? _rawScalarValue(String key) {
    final memory = _memoryStore;
    if (memory != null) return memory[key];
    if (_sqliteReady) return _sqliteMirror[key];
    final box = _box;
    if (box == null || !box.isOpen) return null;
    return box.get(key);
  }

  static Future<void> _writeRawScalarValue(String key, String value) async {
    final memory = _memoryStore;
    if (memory != null) {
      memory[key] = value;
      return;
    }
    if (_sqliteReady) {
      final db = SqliteMigrationManager.database;
      if (db != null) {
        if (SyncSqliteStore.isSqliteBackedKey(key)) {
          await SyncSqliteStore.saveKeyJson(db, key, value);
        } else {
          await BusinessSqliteStore.saveKeyJson(db, key, value);
        }
        _sqliteMirror[key] = value;
        return;
      }
    }
    await _requireBox.put(key, value);
  }

  static Future<void> _deleteRawScalarValue(String key) async {
    final memory = _memoryStore;
    if (memory != null) {
      memory.remove(key);
      return;
    }
    if (_sqliteReady) {
      final db = SqliteMigrationManager.database;
      if (db != null) {
        if (SyncSqliteStore.isSqliteBackedKey(key)) {
          await SyncSqliteStore.saveKeyJson(db, key, key == SyncSqliteStore.syncSequenceKey ? '0' : '[]');
        } else {
          await BusinessSqliteStore.deleteKey(db, key);
          _sqliteMirror.remove(key);
        }
        return;
      }
    }
    final box = _box;
    if (box != null && box.isOpen) await box.delete(key);
  }

  static String? getString(String key) {
    if (key == _cloudApiTokenKey) {
      return _secureStringMirror[_cloudApiTokenKey] ?? '';
    }
    final value = _rawScalarValue(key);
    if (key == _appIdentityKey && value != null) {
      return _mergeSecureDeviceTokenIntoIdentityJson(value);
    }
    return value;
  }

  static String? getRawHiveString(String key) {
    final memory = _memoryStore;
    if (memory != null) return memory[key];
    final box = _box;
    if (box == null || !box.isOpen) return null;
    return box.get(key);
  }



  static Future<String?> getBusinessEntityListJson(String key) async {
    final memory = _memoryStore;
    if (memory != null) return memory[key];
    if (_sqliteReady) {
      final cached = _sqliteMirror[key];
      if (cached != null) return cached;
      final db = SqliteMigrationManager.database;
      if (db == null) return null;
      String? value;
      if (BusinessSqliteStore.isTypedEntityKey(key)) {
        value = await BusinessSqliteStore.readEntityListJsonByKey(db, key);
      } else if (SyncSqliteStore.isSqliteBackedKey(key)) {
        value = await SyncSqliteStore.readKeyJson(db, key);
      }
      if (value != null) _sqliteMirror[key] = value;
      return value;
    }
    return _requireBox.get(key);
  }

  static Future<void> upsertBusinessEntityJson(String key, Map<String, dynamic> payloadJson, {int? sortIndex}) async {
    final memory = _memoryStore;
    if (memory != null) return;
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    await BusinessSqliteStore.upsertEntityPayload(db, key, payloadJson, sortIndex: sortIndex);
  }

  static Future<void> upsertSyncChange(SyncChange change) async {
    final memory = _memoryStore;
    if (memory != null) return;
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    await SyncSqliteStore.upsertSyncChange(db, change);
  }

  static Future<void> upsertSyncQueueItem(SyncQueueItem item) async {
    final memory = _memoryStore;
    if (memory != null) return;
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    await SyncSqliteStore.upsertSyncQueueItem(db, item);
  }

  static Future<void> setString(String key, String value) async {
    if (key == _cloudApiTokenKey) {
      final clean = value.trim();
      if (clean.isEmpty) {
        await _secureStorage.delete(key: _cloudApiTokenKey);
        _secureStringMirror.remove(_cloudApiTokenKey);
      } else {
        await _secureStorage.write(key: _cloudApiTokenKey, value: clean);
        _secureStringMirror[_cloudApiTokenKey] = clean;
      }
      await _deleteRawScalarValue(_cloudApiTokenKey);
      return;
    }
    if (key == _appIdentityKey) {
      final decoded = _tryDecodeJsonMap(value);
      final token = (decoded?['deviceToken'] ?? decoded?['device_token'] ?? '').toString().trim();
      if (token.isNotEmpty) {
        await _secureStorage.write(key: _secureDeviceTokenKey, value: token);
        _secureStringMirror[_secureDeviceTokenKey] = token;
      }
      await _writeRawScalarValue(key, _sanitizeAppIdentityJson(value));
      return;
    }
    await _writeRawScalarValue(key, value);
  }

  static bool containsKey(String key) {
    final memory = _memoryStore;
    if (memory != null) return memory.containsKey(key);
    if (_sqliteReady) {
      return _sqliteMirror.containsKey(key);
    }
    return _requireBox.containsKey(key);
  }

  static Future<void> deleteString(String key) async {
    if (key == _cloudApiTokenKey) {
      await _secureStorage.delete(key: _cloudApiTokenKey);
      _secureStringMirror.remove(_cloudApiTokenKey);
      await _deleteRawScalarValue(_cloudApiTokenKey);
      return;
    }
    if (key == _appIdentityKey) {
      await _secureStorage.delete(key: _secureDeviceTokenKey);
      _secureStringMirror.remove(_secureDeviceTokenKey);
    }
    final memory = _memoryStore;
    if (memory != null) {
      memory.remove(key);
      return;
    }
    if (_sqliteReady) {
      final db = SqliteMigrationManager.database;
      if (db != null) {
        if (SyncSqliteStore.isSqliteBackedKey(key)) {
          await setString(key, key == SyncSqliteStore.syncSequenceKey ? '0' : '[]');
        } else {
          await BusinessSqliteStore.deleteKey(db, key);
          _sqliteMirror.remove(key);
        }
        return;
      }
    }
    await _requireBox.delete(key);
  }

  static Future<void> clearAll() async {
    await _secureStorage.delete(key: _cloudApiTokenKey);
    await _secureStorage.delete(key: _secureDeviceTokenKey);
    _secureStringMirror.remove(_cloudApiTokenKey);
    _secureStringMirror.remove(_secureDeviceTokenKey);
    final memory = _memoryStore;
    if (memory != null) {
      memory.clear();
      return;
    }
    final db = SqliteMigrationManager.database;
    if (_sqliteReady && db != null) {
      await BusinessSqliteStore.clear(db);
      await SyncSqliteStore.saveKeyJson(db, SyncSqliteStore.syncChangesKey, '[]');
      await SyncSqliteStore.saveKeyJson(db, SyncSqliteStore.syncQueueKey, '[]');
      await SyncSqliteStore.saveKeyJson(db, SyncSqliteStore.syncSequenceKey, '0');
      _sqliteMirror
        ..clear()
        ..addAll(<String, String>{
          SyncSqliteStore.syncChangesKey: '[]',
          SyncSqliteStore.syncQueueKey: '[]',
          SyncSqliteStore.syncSequenceKey: '0',
        });
      // Do not clear/write Hive during normal app operation after SQLite is authoritative.
      // Hive is kept only as a migration backup source for upgraded devices.
      return;
    }
    await _requireBox.clear();
  }


  static List<String> keys() {
    final memory = _memoryStore;
    if (memory != null) return memory.keys.toList()..sort();
    if (_sqliteReady) return _sqliteMirror.keys.toList()..sort();
    final keys = <String>{..._requireBox.keys.map((key) => key.toString())};
    return keys.toList()..sort();
  }

  static Map<String, String> allEntries() {
    final memory = _memoryStore;
    if (memory != null) return Map<String, String>.from(memory);
    if (_sqliteReady) return Map<String, String>.from(_sqliteMirror);
    return <String, String>{
      for (final key in _requireBox.keys) key.toString(): _requireBox.get(key)?.toString() ?? '',
    };
  }

  /// Full diagnostic/admin snapshot for the Database page.
  ///
  /// `allEntries()` intentionally stays startup-fast after SQLite became
  /// authoritative and only returns the scalar mirror. The Database page,
  /// however, is an explicit admin browser and must show the real typed SQLite
  /// tables as well. This method hydrates those tables on demand.
  static Future<Map<String, String>> adminEntries() async {
    final memory = _memoryStore;
    if (memory != null) return Map<String, String>.from(memory);
    if (_sqliteReady) {
      final db = SqliteMigrationManager.database;
      if (db == null) return Map<String, String>.from(_sqliteMirror);
      final entries = Map<String, String>.from(_sqliteMirror);
      for (final key in BusinessSqliteStore.adminEntityKeys) {
        final value = await BusinessSqliteStore.readEntityListJsonByKey(db, key);
        if (value != null) entries[key] = value;
      }
      for (final key in SyncSqliteStore.sqliteBackedKeys) {
        final value = await SyncSqliteStore.readKeyJson(db, key);
        if (value != null) entries[key] = value;
      }
      return entries;
    }
    return <String, String>{
      for (final key in _requireBox.keys) key.toString(): _requireBox.get(key)?.toString() ?? '',
    };
  }
  static Map<String, String> allRawHiveEntries() {
    final memory = _memoryStore;
    if (memory != null) return Map<String, String>.from(memory);
    final box = _box;
    if (box == null || !box.isOpen) return const <String, String>{};
    return <String, String>{
      for (final key in box.keys) key.toString(): box.get(key)?.toString() ?? '',
    };
  }


  static bool get isEmpty {
    final memory = _memoryStore;
    if (memory != null) return memory.isEmpty;
    if (_sqliteReady) return _sqliteMirror.isEmpty;
    return _requireBox.isEmpty;
  }
}
