import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';

import 'business_sqlite_store.dart';
import 'sync_sqlite_store.dart';
import 'ventio_drift_database.dart';

class SqliteMigrationStatus {
  const SqliteMigrationStatus({
    required this.phase,
    required this.sqliteFoundationReady,
    required this.legacyBackupAvailable,
    this.lastRunId = '',
    this.lastStatus = '',
    this.message = '',
  });

  final int phase;
  final bool sqliteFoundationReady;
  final bool legacyBackupAvailable;
  final String lastRunId;
  final String lastStatus;
  final String message;
}

/// Safe staged migration coordinator.
///
/// Phase 3 responsibilities:
/// - keep the Phase 1/2 foundation and legacy storage safety backup;
/// - keep sync_queue, pending_sync_changes, sync_events, and sync_conflicts in SQLite;
/// - migrate all remaining business/settings JSON keys from legacy storage into SQLite;
/// - stop writing active app data back to legacy storage after migration succeeds.
class SqliteMigrationManager {
  SqliteMigrationManager._();

  static const int currentPhase = 3;
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
        legacyBackupAvailable: true,
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
          legacyBackupAvailable: false,
          lastStatus: 'needs_legacy_migration',
          message: 'Validated SQLite typed tables were not found; legacy storage migration is required.',
        );
      }
      _database = db;
      await SyncSqliteStore.markSyncMigrationCompleted(db);
      _initialized = true;
      _lastError = null;
      return const SqliteMigrationStatus(
        phase: currentPhase,
        sqliteFoundationReady: true,
        legacyBackupAvailable: true,
        lastStatus: 'completed',
        message: 'SQLite/Drift phase 3B restored from validated typed tables; legacy storage is not opened.',
      );
    } catch (error, stackTrace) {
      _lastError = error;
      debugPrint('SQLite validated startup failed: $error\n$stackTrace');
      return SqliteMigrationStatus(
        phase: currentPhase,
        sqliteFoundationReady: false,
        legacyBackupAvailable: false,
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
        legacyBackupAvailable: false,
        lastStatus: 'completed',
        message: 'Fresh SQLite/Drift store already initialized.',
      );
    }

    try {
      final db = VentioDriftDatabase();
      await db.initializeFoundation();
      _database = db;
      await BusinessSqliteStore.markFreshInstallValidated(db);
      await SyncSqliteStore.markSyncMigrationCompleted(db);
      final runId = 'fresh_${DateTime.now().toUtc().millisecondsSinceEpoch}';
      final now = DateTime.now().toUtc().toIso8601String();
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO migration_runs
          (id, phase, status, started_at, finished_at, legacy_backup_json, message)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(runId),
          const Variable<int>(currentPhase),
          const Variable<String>('completed'),
          Variable<String>(now),
          Variable<String>(now),
          const Variable<String>(''),
          const Variable<String>('Fresh SQLite/Drift store initialized without opening or creating legacy storage.'),
        ],
      );
      _initialized = true;
      _lastError = null;
      return SqliteMigrationStatus(
        phase: currentPhase,
        sqliteFoundationReady: true,
        legacyBackupAvailable: false,
        lastRunId: runId,
        lastStatus: 'completed',
        message: 'Fresh SQLite/Drift store initialized without opening or creating legacy storage.',
      );
    } catch (error, stackTrace) {
      _lastError = error;
      debugPrint('Fresh SQLite initialization failed: $error\n$stackTrace');
      return SqliteMigrationStatus(
        phase: currentPhase,
        sqliteFoundationReady: false,
        legacyBackupAvailable: false,
        lastStatus: 'failed',
        message: error.toString(),
      );
    }
  }


  static Future<SqliteMigrationStatus> initializePhase3() async => initializeFreshSqlite();

  static Future<SqliteMigrationStatus> initializePhase1() => initializePhase3();

  static Future<SqliteMigrationStatus> initializePhase2() => initializePhase3();

  static void attachDatabaseOverride(VentioDriftDatabase database) {
    _database = database;
    _initialized = true;
    _lastError = null;
  }

  @visibleForTesting
  static void useDatabaseForTesting(VentioDriftDatabase database) {
    attachDatabaseOverride(database);
  }

  /// Flushes WAL pages into the main SQLite file and closes the Drift database.
  ///
  /// This is intended for a graceful application shutdown. Ventio keeps WAL
  /// enabled during normal operation for concurrency/performance, then forces a
  /// final TRUNCATE checkpoint so a standalone `ventio.sqlite` contains all
  /// committed data before the process exits.
  static Future<void> shutdown({
    Duration retryDelay = const Duration(milliseconds: 150),
    int maxAttempts = 4,
  }) async {
    final db = _database;
    if (db == null) {
      _initialized = false;
      return;
    }

    Object? checkpointError;
    try {
      // Give SQLite a bounded amount of time to finish any short-lived lock.
      await db.customStatement('PRAGMA busy_timeout = 5000;');

      for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
        try {
          final rows = await db
              .customSelect('PRAGMA wal_checkpoint(TRUNCATE);')
              .get();
          if (rows.isEmpty) {
            checkpointError = null;
            break;
          }

          // wal_checkpoint returns: busy, log, checkpointed. A zero busy value
          // means the checkpoint completed without another connection blocking it.
          final data = rows.first.data;
          final busy = (data['busy'] as num?)?.toInt() ??
              (data.values.isNotEmpty ? (data.values.first as num?)?.toInt() : 0) ??
              0;
          if (busy == 0) {
            checkpointError = null;
            break;
          }
          checkpointError = StateError(
            'SQLite WAL checkpoint remained busy (attempt $attempt/$maxAttempts).',
          );
        } catch (error) {
          checkpointError = error;
        }

        if (attempt < maxAttempts) {
          await Future<void>.delayed(retryDelay);
        }
      }

      if (checkpointError != null) {
        // Closing is still safe: committed WAL data remains durable and SQLite
        // will recover it on the next open. Surface the condition in debug logs.
        debugPrint('SQLite shutdown checkpoint warning: $checkpointError');
      }
    } finally {
      // Clear the shared reference before awaiting close so no new caller can
      // start work on a database that is shutting down.
      _database = null;
      _initialized = false;
      _lastError = checkpointError;
      await db.close();
    }
  }

  static Future<void> resetForTesting() async {
    final db = _database;
    _database = null;
    _initialized = false;
    _lastError = null;
    if (db != null) {
      await db.close();
    }
  }

}
