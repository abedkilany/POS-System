import 'dart:async';
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
  static const String _appIdentityKey = 'app_identity_v1';
  static const String _legacySecureDeviceTokenKey =
      'app_identity_device_token_v1';
  static const String _secureRecoveryKeyKey = 'app_identity_recovery_key_v1';
  static final Map<String, String> _secureStringMirror = <String, String>{};
  static Map<String, String>? _memoryStoreForTesting;
  static Map<String, String>? _webStore;
  static SharedPreferences? _webPreferences;
  static final Map<String, String> _sqliteMirror = <String, String>{};
  static final Map<String, String> _pendingScalarWrites = <String, String>{};
  static final Set<String> _pendingScalarDeletes = <String>{};
  static final Map<String, List<_PendingBusinessEntityWrite>>
      _pendingBusinessEntityWrites = <String, List<_PendingBusinessEntityWrite>>{};
  static final List<SyncChange> _pendingSyncChanges = <SyncChange>[];
  static final List<SyncQueueItem> _pendingSyncQueueItems = <SyncQueueItem>[];
  static Timer? _flushTimer;
  static Future<void>? _flushInProgress;
  static const Duration _flushDelay = Duration(milliseconds: 120);
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
    _pendingScalarWrites.clear();
    _pendingScalarDeletes.clear();
    _pendingBusinessEntityWrites.clear();
    _pendingSyncChanges.clear();
    _pendingSyncQueueItems.clear();
    _flushTimer?.cancel();
    _flushTimer = null;
    _flushInProgress = null;
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
    // Phase 1 security split:
    // - recoveryKey stays in FlutterSecureStorage.
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

    await _deleteRawScalarValueImmediate('cloud_api_token');

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
          await _writeRawScalarValueImmediate(_appIdentityKey, sanitized);
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
    if (_pendingScalarDeletes.contains(key)) return null;
    final pending = _pendingScalarWrites[key];
    if (pending != null) return pending;
    final memory = _memoryStore;
    if (memory != null) return memory[key];
    if (_webStore != null) return _webStore![key];
    return _sqliteMirror[key];
  }

  static Future<void> _writeRawScalarValueImmediate(String key, String value) async {
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

  static Future<void> _deleteRawScalarValueImmediate(String key) async {
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

  static void _scheduleFlush() {
    if (_memoryStore != null || _webStore != null) return;
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushDelay, () {
      unawaited(flushPendingWrites());
    });
  }

  static String? getString(String key) {
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
    if (_webStore != null) return;
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    final pending = _pendingBusinessEntityWrites.putIfAbsent(
      key,
      () => <_PendingBusinessEntityWrite>[],
    );
    pending.add(
      _PendingBusinessEntityWrite(
        payload: Map<String, dynamic>.from(payloadJson),
        sortIndex: sortIndex,
      ),
    );
    _scheduleFlush();
  }

  static Future<void> upsertSyncChange(SyncChange change) async {
    final memory = _memoryStore;
    if (memory != null) return;
    if (_webStore != null) return;
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    _pendingSyncChanges.add(change);
    _scheduleFlush();
  }

  static Future<void> upsertSyncQueueItem(SyncQueueItem item) async {
    final memory = _memoryStore;
    if (memory != null) return;
    if (_webStore != null) return;
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    _pendingSyncQueueItems.add(item);
    _scheduleFlush();
  }

  static Future<void> setString(String key, String value) async {
    if (key == _appIdentityKey) {
      if (_memoryStore != null || _webStore != null) {
        await _writeRawScalarValueImmediate(key, value);
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
      await _writeRawScalarValueImmediate(key, _sanitizeAppIdentityJson(value));
      return;
    }
    final memory = _memoryStore;
    if (memory != null) {
      await _writeRawScalarValueImmediate(key, value);
      return;
    }
    if (_webStore != null) {
      await _writeRawScalarValueImmediate(key, value);
      return;
    }
    if (_sqliteReady) {
      _pendingScalarDeletes.remove(key);
      _pendingScalarWrites[key] = value;
      _sqliteMirror[key] = value;
      _scheduleFlush();
      return;
    }
    await _writeRawScalarValueImmediate(key, value);
  }

  static bool containsKey(String key) {
    if (_pendingScalarDeletes.contains(key)) return false;
    if (_pendingScalarWrites.containsKey(key)) return true;
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
          _pendingScalarWrites.remove(key);
          _pendingScalarDeletes.add(key);
          _sqliteMirror.remove(key);
          _scheduleFlush();
        }
        return;
      }
    }
    return;
  }

  static Future<void> clearAll() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingScalarWrites.clear();
    _pendingScalarDeletes.clear();
    _pendingBusinessEntityWrites.clear();
    _pendingSyncChanges.clear();
    _pendingSyncQueueItems.clear();
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
    await _secureStorage.delete(key: _legacySecureDeviceTokenKey);
    await _secureStorage.delete(key: _secureRecoveryKeyKey);
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

  static Future<void> flushPendingWrites() async {
    if (_memoryStore != null || _webStore != null) return;
    if (_flushInProgress != null) return _flushInProgress!;

    final completer = Completer<void>();
    _flushInProgress = completer.future;
    _flushTimer?.cancel();
    _flushTimer = null;

    try {
      final db = SqliteMigrationManager.database;
      if (!_sqliteReady || db == null) return;

      final scalarDeletes = List<String>.from(_pendingScalarDeletes);
      final scalarWrites = Map<String, String>.from(_pendingScalarWrites);
      final businessWrites =
          Map<String, List<_PendingBusinessEntityWrite>>.from(
        _pendingBusinessEntityWrites,
      );
      final syncChanges = List<SyncChange>.from(_pendingSyncChanges);
      final syncQueueItems = List<SyncQueueItem>.from(_pendingSyncQueueItems);

      _pendingScalarDeletes.clear();
      _pendingScalarWrites.clear();
      _pendingBusinessEntityWrites.clear();
      _pendingSyncChanges.clear();
      _pendingSyncQueueItems.clear();

      for (final key in scalarDeletes) {
        await _deleteRawScalarValueImmediate(key);
      }
      for (final entry in scalarWrites.entries) {
        await _writeRawScalarValueImmediate(entry.key, entry.value);
      }
      for (final entry in businessWrites.entries) {
        await BusinessSqliteStore.upsertEntityPayloads(
          db,
          entry.key,
          entry.value.map((item) => item.payload).toList(growable: false),
          sortIndices: entry.value
              .map((item) => item.sortIndex)
              .toList(growable: false),
        );
      }
      if (syncChanges.isNotEmpty) {
        await SyncSqliteStore.upsertSyncChanges(db, syncChanges);
      }
      if (syncQueueItems.isNotEmpty) {
        await SyncSqliteStore.upsertSyncQueueItems(db, syncQueueItems);
      }
    } finally {
      _flushInProgress = null;
      completer.complete();
      if (_pendingScalarDeletes.isNotEmpty ||
          _pendingScalarWrites.isNotEmpty ||
          _pendingBusinessEntityWrites.isNotEmpty ||
          _pendingSyncChanges.isNotEmpty ||
          _pendingSyncQueueItems.isNotEmpty) {
        _scheduleFlush();
      }
    }
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

class _PendingBusinessEntityWrite {
  const _PendingBusinessEntityWrite({
    required this.payload,
    this.sortIndex,
  });

  final Map<String, dynamic> payload;
  final int? sortIndex;
}
