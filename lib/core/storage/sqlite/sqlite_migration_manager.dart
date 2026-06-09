import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';

import '../../services/local_database_service.dart';
import 'business_sqlite_store.dart';
import 'sync_sqlite_store.dart';
import 'ventio_drift_database.dart';

class SqliteMigrationStatus {
  const SqliteMigrationStatus({
    required this.phase,
    required this.sqliteFoundationReady,
    required this.hiveBackupAvailable,
    this.lastRunId = '',
    this.lastStatus = '',
    this.message = '',
  });

  final int phase;
  final bool sqliteFoundationReady;
  final bool hiveBackupAvailable;
  final String lastRunId;
  final String lastStatus;
  final String message;
}

/// Safe staged migration coordinator.
///
/// Phase 3 responsibilities:
/// - keep the Phase 1/2 foundation and Hive safety backup;
/// - keep sync_queue, pending_sync_changes, sync_events, and sync_conflicts in SQLite;
/// - migrate all remaining business/settings JSON keys from Hive into SQLite;
/// - stop writing active app data back to Hive after migration succeeds.
class SqliteMigrationManager {
  SqliteMigrationManager._();

  static const int currentPhase = 3;
  static const String _hiveBackupKey = 'sqlite_phase1_hive_backup_v1';
  static VentioDriftDatabase? _database;
  static bool _initialized = false;
  static Object? _lastError;

  static bool get isInitialized => _initialized;
  static Object? get lastError => _lastError;
  static VentioDriftDatabase? get database => _database;


  static Future<SqliteMigrationStatus> initializeFromExistingSqliteIfValidated() async {
    if (_initialized && _database != null) {
      return const SqliteMigrationStatus(
        phase: currentPhase,
        sqliteFoundationReady: true,
        hiveBackupAvailable: true,
        lastStatus: 'completed',
        message: 'SQLite/Drift phase 3B already initialized from validated typed tables.',
      );
    }

    try {
      final db = VentioDriftDatabase();
      await db.initializeFoundation();
      final validated = await BusinessSqliteStore.isValidationPassed(db);
      if (!validated) {
        await db.close();
        return const SqliteMigrationStatus(
          phase: currentPhase,
          sqliteFoundationReady: false,
          hiveBackupAvailable: false,
          lastStatus: 'needs_hive_migration',
          message: 'Validated SQLite typed tables were not found; Hive migration is required.',
        );
      }
      _database = db;
      _initialized = true;
      _lastError = null;
      return const SqliteMigrationStatus(
        phase: currentPhase,
        sqliteFoundationReady: true,
        hiveBackupAvailable: true,
        lastStatus: 'completed',
        message: 'SQLite/Drift phase 3B restored from validated typed tables; Hive is not opened.',
      );
    } catch (error, stackTrace) {
      _lastError = error;
      debugPrint('SQLite validated startup failed: $error\n$stackTrace');
      return SqliteMigrationStatus(
        phase: currentPhase,
        sqliteFoundationReady: false,
        hiveBackupAvailable: false,
        lastStatus: 'failed',
        message: error.toString(),
      );
    }
  }



  static Future<SqliteMigrationStatus> initializeFreshSqlite() async {
    if (_initialized && _database != null) {
      return const SqliteMigrationStatus(
        phase: currentPhase,
        sqliteFoundationReady: true,
        hiveBackupAvailable: false,
        lastStatus: 'completed',
        message: 'Fresh SQLite/Drift store already initialized.',
      );
    }

    try {
      final db = VentioDriftDatabase();
      await db.initializeFoundation();
      _database = db;
      await BusinessSqliteStore.markFreshInstallValidated(db);
      final runId = 'fresh_${DateTime.now().toUtc().millisecondsSinceEpoch}';
      final now = DateTime.now().toUtc().toIso8601String();
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO migration_runs
          (id, phase, status, started_at, finished_at, hive_backup_json, message)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(runId),
          const Variable<int>(currentPhase),
          const Variable<String>('completed'),
          Variable<String>(now),
          Variable<String>(now),
          const Variable<String>(''),
          const Variable<String>('Fresh SQLite/Drift store initialized without opening or creating legacy Hive.'),
        ],
      );
      _initialized = true;
      _lastError = null;
      return SqliteMigrationStatus(
        phase: currentPhase,
        sqliteFoundationReady: true,
        hiveBackupAvailable: false,
        lastRunId: runId,
        lastStatus: 'completed',
        message: 'Fresh SQLite/Drift store initialized without opening or creating legacy Hive.',
      );
    } catch (error, stackTrace) {
      _lastError = error;
      debugPrint('Fresh SQLite initialization failed: $error\n$stackTrace');
      return SqliteMigrationStatus(
        phase: currentPhase,
        sqliteFoundationReady: false,
        hiveBackupAvailable: false,
        lastStatus: 'failed',
        message: error.toString(),
      );
    }
  }


  static Future<SqliteMigrationStatus> initializePhase3() async {
    if (_initialized) {
      return SqliteMigrationStatus(
        phase: currentPhase,
        sqliteFoundationReady: true,
        hiveBackupAvailable: LocalDatabaseService.containsKey(_hiveBackupKey),
        message: 'SQLite/Drift phase 3 already initialized.',
      );
    }

    try {
      final db = VentioDriftDatabase();
      await db.initializeFoundation();
      _database = db;

      final backupJson = await _createHiveSafetyBackupIfMissing();
      await SyncSqliteStore.migrateFromHiveIfNeeded(
        db,
        syncChangesJson: LocalDatabaseService.getRawHiveString(SyncSqliteStore.syncChangesKey),
        syncQueueJson: LocalDatabaseService.getRawHiveString(SyncSqliteStore.syncQueueKey),
        syncSequence: LocalDatabaseService.getRawHiveString(SyncSqliteStore.syncSequenceKey),
      );
      final hiveEntries = LocalDatabaseService.allRawHiveEntries();
      await BusinessSqliteStore.migrateFromHiveIfNeeded(
        db,
        hiveEntries: hiveEntries,
      );
      final validation = await BusinessSqliteStore.validateAgainstHive(db, hiveEntries: hiveEntries);
      if (!validation.ok) {
        throw StateError('SQLite phase 3 validation failed: ${validation.message}');
      }
      final runId = 'phase3_${DateTime.now().toUtc().millisecondsSinceEpoch}';
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO migration_runs
          (id, phase, status, started_at, finished_at, hive_backup_json, message)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(runId),
          const Variable<int>(currentPhase),
          const Variable<String>('completed'),
          Variable<String>(DateTime.now().toUtc().toIso8601String()),
          Variable<String>(DateTime.now().toUtc().toIso8601String()),
          Variable<String>(backupJson),
          Variable<String>('SQLite/Drift phase 3B completed and validated; sync plus typed business tables now use SQLite. ${validation.message} Hive is retained only as a read-only migration backup source.'),
        ],
      );

      _initialized = true;
      _lastError = null;
      return SqliteMigrationStatus(
        phase: currentPhase,
        sqliteFoundationReady: true,
        hiveBackupAvailable: true,
        lastRunId: runId,
        lastStatus: 'completed',
        message: 'SQLite/Drift phase 3B completed and validated; sync plus typed business tables now use SQLite. ${validation.message} Hive is retained only as a read-only migration backup source.',
      );
    } catch (error, stackTrace) {
      _lastError = error;
      debugPrint('SQLite phase 3 initialization failed: $error\n$stackTrace');
      return SqliteMigrationStatus(
        phase: currentPhase,
        sqliteFoundationReady: false,
        hiveBackupAvailable: LocalDatabaseService.containsKey(_hiveBackupKey),
        lastStatus: 'failed',
        message: error.toString(),
      );
    }
  }

  static Future<SqliteMigrationStatus> initializePhase1() => initializePhase3();

  static Future<SqliteMigrationStatus> initializePhase2() => initializePhase3();

  static Future<String> _createHiveSafetyBackupIfMissing() async {
    final existing = LocalDatabaseService.getString(_hiveBackupKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final entries = LocalDatabaseService.allEntries();
    final backup = <String, dynamic>{
      'version': 1,
      'phase': currentPhase,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'source': 'hive',
      'entryCount': entries.length,
      'entries': entries,
    };
    final encoded = jsonEncode(backup);
    await LocalDatabaseService.setString(_hiveBackupKey, encoded);
    return encoded;
  }
}
