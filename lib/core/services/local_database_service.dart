import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/sqlite/business_sqlite_store.dart';
import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/sync_sqlite_store.dart';
import '../../models/sync_change.dart';
import '../../models/sync_queue_item.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalDatabaseService {
  LocalDatabaseService._();

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _cloudApiTokenKey = 'cloud_api_token';
  static const String _appIdentityKey = 'app_identity_v1';
  static const String _legacySecureDeviceTokenKey =
      'app_identity_device_token_v1';
  static const String _secureRecoveryKeyKey = 'app_identity_recovery_key_v1';
  static final Map<String, String> _secureStringMirror = <String, String>{};
  static Map<String, String>? _memoryStoreForTesting;
  static Map<String, String>? _webStore;
  static SharedPreferences? _webPreferences;
  static final Map<String, String> _sqliteMirror = <String, String>{};
  static bool _sqliteReady = false;

  static bool get isSqliteAuthoritative =>
      _sqliteReady && SqliteMigrationManager.database != null;

  @visibleForTesting
  static void useInMemoryStoreForTesting([Map<String, String>? seed]) {
    _memoryStoreForTesting =
        Map<String, String>.from(seed ?? const <String, String>{});
  }

  @visibleForTesting
  static void clearInMemoryStoreForTesting() {
    _memoryStoreForTesting = null;
  }

  static Future<void> initialize() async {
    if (_memoryStoreForTesting != null) return;
    if (_sqliteReady && SqliteMigrationManager.database != null) return;

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      _webPreferences = prefs;
      _webStore = <String, String>{
        for (final key in prefs.getKeys())
          if (prefs.getString(key) != null) key: prefs.getString(key)!,
      };
      return;
    }

    final existingSqliteStatus =
        await SqliteMigrationManager.initializeFromExistingSqliteIfValidated();
    var db = SqliteMigrationManager.database;
    if (!existingSqliteStatus.sqliteFoundationReady || db == null) {
      await SqliteMigrationManager.initializeFreshSqlite();
      db = SqliteMigrationManager.database;
    }
    if (db == null) {
      throw StateError('SQLite database failed to initialize.');
    }

    _sqliteMirror
      ..clear()
      ..addAll(await BusinessSqliteStore.hydrateScalarKeyMirror(db))
      ..addAll(await SyncSqliteStore.hydrateScalarKeyMirror(db));
    _sqliteReady = true;
    await _hydrateAndMigrateSecureScalars();
  }

  static Map<String, String>? get _memoryStore => _memoryStoreForTesting;

  static Future<void> _persistWebString(String key, String value) async {
    final prefs = _webPreferences;
    if (prefs != null) await prefs.setString(key, value);
  }

  static Future<void> _deleteWebString(String key) async {
    final prefs = _webPreferences;
    if (prefs != null) await prefs.remove(key);
  }

  static Future<void> _hydrateAndMigrateSecureScalars() async {
    final secureCloudToken = await _secureStorage.read(key: _cloudApiTokenKey);
    if (secureCloudToken != null) {
      _secureStringMirror[_cloudApiTokenKey] = secureCloudToken;
    }
    // Phase 1 security split:
    // - cloud_api_token and recoveryKey stay in FlutterSecureStorage.
    // - deviceToken is application identity data and is stored back inside
    //   app_identity_v1 in the local database. Keep this legacy secure key only
    //   long enough to migrate devices that used the previous secure-token build.
    final legacySecureDeviceToken =
        (await _secureStorage.read(key: _legacySecureDeviceTokenKey))?.trim() ??
            '';
    final secureRecoveryKey =
        await _secureStorage.read(key: _secureRecoveryKeyKey);
    if (secureRecoveryKey != null) {
      _secureStringMirror[_secureRecoveryKeyKey] = secureRecoveryKey;
    }

    final legacyCloudToken = _rawScalarValue(_cloudApiTokenKey)?.trim() ?? '';
    if (legacyCloudToken.isNotEmpty &&
        (_secureStringMirror[_cloudApiTokenKey] ?? '').isEmpty) {
      await _secureStorage.write(
          key: _cloudApiTokenKey, value: legacyCloudToken);
      _secureStringMirror[_cloudApiTokenKey] = legacyCloudToken;
    }
    await _deleteRawScalarValue(_cloudApiTokenKey);

    final rawIdentity = _rawScalarValue(_appIdentityKey);
    if (rawIdentity != null && rawIdentity.trim().isNotEmpty) {
      final decoded = _tryDecodeJsonMap(rawIdentity);
      if (decoded != null) {
        final legacyDeviceToken =
            (decoded['deviceToken'] ?? decoded['device_token'] ?? '')
                .toString()
                .trim();
        if (legacyDeviceToken.isEmpty && legacySecureDeviceToken.isNotEmpty) {
          decoded['deviceToken'] = legacySecureDeviceToken;
        }
        final legacyRecoveryKey =
            (decoded['recoveryKey'] ?? decoded['recovery_key'] ?? '')
                .toString()
                .trim();
        if (legacyRecoveryKey.isNotEmpty &&
            (_secureStringMirror[_secureRecoveryKeyKey] ?? '').isEmpty) {
          final cleanRecoveryKey = legacyRecoveryKey.toUpperCase();
          await _secureStorage.write(
              key: _secureRecoveryKeyKey, value: cleanRecoveryKey);
          _secureStringMirror[_secureRecoveryKeyKey] = cleanRecoveryKey;
        }
        final sanitized = _sanitizeAppIdentityJson(jsonEncode(decoded));
        if (sanitized != rawIdentity) {
          await _writeRawScalarValue(_appIdentityKey, sanitized);
        }
      }
    }
    if (legacySecureDeviceToken.isNotEmpty) {
      await _secureStorage.delete(key: _legacySecureDeviceTokenKey);
      _secureStringMirror.remove(_legacySecureDeviceTokenKey);
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
    decoded.remove('recoveryKey');
    decoded.remove('recovery_key');
    return jsonEncode(decoded);
  }

  static String _mergeSecureIdentitySecretsIntoIdentityJson(String value) {
    final recoveryKey =
        (_secureStringMirror[_secureRecoveryKeyKey] ?? '').trim();
    if (recoveryKey.isEmpty) return value;
    final decoded = _tryDecodeJsonMap(value);
    if (decoded == null) return value;
    if (recoveryKey.isNotEmpty) decoded['recoveryKey'] = recoveryKey;
    return jsonEncode(decoded);
  }

  static String? _rawScalarValue(String key) {
    final memory = _memoryStore;
    if (memory != null) return memory[key];
    if (_webStore != null) return _webStore![key];
    return _sqliteMirror[key];
  }

  static Future<void> _writeRawScalarValue(String key, String value) async {
    final memory = _memoryStore;
    if (memory != null) {
      memory[key] = value;
      return;
    }
    if (_webStore != null) {
      _webStore![key] = value;
      await _persistWebString(key, value);
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
    throw StateError('SQLite database has not been initialized.');
  }

  static Future<void> _deleteRawScalarValue(String key) async {
    final memory = _memoryStore;
    if (memory != null) {
      memory.remove(key);
      return;
    }
    if (_webStore != null) {
      _webStore!.remove(key);
      await _deleteWebString(key);
      return;
    }
    if (_sqliteReady) {
      final db = SqliteMigrationManager.database;
      if (db != null) {
        if (SyncSqliteStore.isSqliteBackedKey(key)) {
          await SyncSqliteStore.saveKeyJson(
              db, key, key == SyncSqliteStore.syncSequenceKey ? '0' : '[]');
        } else {
          await BusinessSqliteStore.deleteKey(db, key);
          _sqliteMirror.remove(key);
        }
        return;
      }
    }
  }

  static String? getString(String key) {
    if (key == _cloudApiTokenKey) {
      final memory = _memoryStore;
      if (memory != null) return memory[_cloudApiTokenKey] ?? '';
      if (_webStore != null) return _webStore![_cloudApiTokenKey] ?? '';
      return _secureStringMirror[_cloudApiTokenKey] ?? '';
    }
    final value = _rawScalarValue(key);
    if (key == _appIdentityKey && value != null) {
      return _mergeSecureIdentitySecretsIntoIdentityJson(value);
    }
    return value;
  }

  static Future<String?> getBusinessEntityListJson(String key) async {
    final memory = _memoryStore;
    if (memory != null) return memory[key];
    if (_webStore != null) return _webStore![key];
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
    return null;
  }

  static Future<void> upsertBusinessEntityJson(
      String key, Map<String, dynamic> payloadJson,
      {int? sortIndex}) async {
    final memory = _memoryStore;
    if (memory != null) return;
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    await BusinessSqliteStore.upsertEntityPayload(db, key, payloadJson,
        sortIndex: sortIndex);
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
      final memory = _memoryStore;
      if (memory != null) {
        if (clean.isEmpty) {
          memory.remove(_cloudApiTokenKey);
        } else {
          memory[_cloudApiTokenKey] = clean;
        }
        return;
      }
      if (_webStore != null) {
        if (clean.isEmpty) {
          _webStore!.remove(_cloudApiTokenKey);
          await _deleteWebString(_cloudApiTokenKey);
        } else {
          _webStore![_cloudApiTokenKey] = clean;
          await _persistWebString(_cloudApiTokenKey, clean);
        }
        return;
      }
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
      if (_memoryStore != null || _webStore != null) {
        await _writeRawScalarValue(key, value);
        return;
      }
      final decoded = _tryDecodeJsonMap(value);
      final recoveryKey =
          (decoded?['recoveryKey'] ?? decoded?['recovery_key'] ?? '')
              .toString()
              .trim();
      if (recoveryKey.isNotEmpty) {
        final cleanRecoveryKey = recoveryKey.toUpperCase();
        await _secureStorage.write(
            key: _secureRecoveryKeyKey, value: cleanRecoveryKey);
        _secureStringMirror[_secureRecoveryKeyKey] = cleanRecoveryKey;
      }
      await _writeRawScalarValue(key, _sanitizeAppIdentityJson(value));
      return;
    }
    await _writeRawScalarValue(key, value);
  }

  static bool containsKey(String key) {
    final memory = _memoryStore;
    if (memory != null) return memory.containsKey(key);
    if (_webStore != null) return _webStore!.containsKey(key);
    if (_sqliteReady) {
      return _sqliteMirror.containsKey(key);
    }
    return false;
  }

  static Future<void> deleteString(String key) async {
    final memory = _memoryStore;
    if (memory != null) {
      memory.remove(key);
      return;
    }
    if (_webStore != null) {
      _webStore!.remove(key);
      await _deleteWebString(key);
      return;
    }

    if (key == _cloudApiTokenKey) {
      await _secureStorage.delete(key: _cloudApiTokenKey);
      _secureStringMirror.remove(_cloudApiTokenKey);
      await _deleteRawScalarValue(_cloudApiTokenKey);
      return;
    }
    if (key == _appIdentityKey) {
      await _secureStorage.delete(key: _legacySecureDeviceTokenKey);
      await _secureStorage.delete(key: _secureRecoveryKeyKey);
      _secureStringMirror.remove(_legacySecureDeviceTokenKey);
      _secureStringMirror.remove(_secureRecoveryKeyKey);
    }
    if (_sqliteReady) {
      final db = SqliteMigrationManager.database;
      if (db != null) {
        if (SyncSqliteStore.isSqliteBackedKey(key)) {
          await setString(
              key, key == SyncSqliteStore.syncSequenceKey ? '0' : '[]');
        } else {
          await BusinessSqliteStore.deleteKey(db, key);
          _sqliteMirror.remove(key);
        }
        return;
      }
    }
    return;
  }

  static Future<void> clearAll() async {
    final memory = _memoryStore;
    if (memory != null) {
      memory.clear();
      return;
    }
    if (_webStore != null) {
      final prefs = _webPreferences;
      final keys = List<String>.from(_webStore!.keys);
      _webStore!.clear();
      if (prefs != null) {
        for (final key in keys) {
          await prefs.remove(key);
        }
      }
      return;
    }
    await _secureStorage.delete(key: _cloudApiTokenKey);
    await _secureStorage.delete(key: _legacySecureDeviceTokenKey);
    await _secureStorage.delete(key: _secureRecoveryKeyKey);
    _secureStringMirror.remove(_cloudApiTokenKey);
    _secureStringMirror.remove(_legacySecureDeviceTokenKey);
    _secureStringMirror.remove(_secureRecoveryKeyKey);
    final db = SqliteMigrationManager.database;
    if (_sqliteReady && db != null) {
      await BusinessSqliteStore.clear(db);
      await SyncSqliteStore.saveKeyJson(
          db, SyncSqliteStore.syncChangesKey, '[]');
      await SyncSqliteStore.saveKeyJson(db, SyncSqliteStore.syncQueueKey, '[]');
      await SyncSqliteStore.saveKeyJson(
          db, SyncSqliteStore.syncSequenceKey, '0');
      _sqliteMirror
        ..clear()
        ..addAll(<String, String>{
          SyncSqliteStore.syncChangesKey: '[]',
          SyncSqliteStore.syncQueueKey: '[]',
          SyncSqliteStore.syncSequenceKey: '0',
        });
      return;
    }
    return;
  }

  static List<String> keys() {
    final memory = _memoryStore;
    if (memory != null) return memory.keys.toList()..sort();
    if (_webStore != null) return _webStore!.keys.toList()..sort();
    if (_sqliteReady) return _sqliteMirror.keys.toList()..sort();
    return const <String>[];
  }

  static Map<String, String> allEntries() {
    final memory = _memoryStore;
    if (memory != null) return Map<String, String>.from(memory);
    if (_webStore != null) return Map<String, String>.from(_webStore!);
    if (_sqliteReady) return Map<String, String>.from(_sqliteMirror);
    return const <String, String>{};
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
    if (_webStore != null) return Map<String, String>.from(_webStore!);
    if (_sqliteReady) {
      final db = SqliteMigrationManager.database;
      if (db == null) return Map<String, String>.from(_sqliteMirror);
      final entries = Map<String, String>.from(_sqliteMirror);
      for (final key in BusinessSqliteStore.adminEntityKeys) {
        final value =
            await BusinessSqliteStore.readEntityListJsonByKey(db, key);
        if (value != null) entries[key] = value;
      }
      for (final key in SyncSqliteStore.sqliteBackedKeys) {
        final value = await SyncSqliteStore.readKeyJson(db, key);
        if (value != null) entries[key] = value;
      }
      return entries;
    }
    return const <String, String>{};
  }

  static bool get isEmpty {
    final memory = _memoryStore;
    if (memory != null) return memory.isEmpty;
    if (_sqliteReady) return _sqliteMirror.isEmpty;
    return true;
  }
}
