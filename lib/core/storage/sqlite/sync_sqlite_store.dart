import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../models/sync_change.dart';
import '../../../models/sync_queue_item.dart';
import 'ventio_drift_database.dart';

/// SQLite-backed storage for Ventio sync data.
///
/// Phase 2 moves sync state out of Hive's large JSON blob rewrite path while
/// keeping the public LocalDatabaseService get/set API unchanged for the rest
/// of the app. Business data continues to live in Hive until Phase 3.
class SyncSqliteStore {
  SyncSqliteStore._();

  static const String syncChangesKey = 'sync_changes_v1';
  static const String syncQueueKey = 'sync_queue_v1';
  static const String syncSequenceKey = 'sync_sequence_v1';

  static const Set<String> sqliteBackedKeys = <String>{
    syncChangesKey,
    syncQueueKey,
    syncSequenceKey,
  };

  static bool isSqliteBackedKey(String key) => sqliteBackedKeys.contains(key);

  static Future<Map<String, String>> hydrateKeyMirror(VentioDriftDatabase db) async {
    return <String, String>{
      syncChangesKey: await readSyncChangesJson(db),
      syncQueueKey: await readSyncQueueJson(db),
      syncSequenceKey: await readSyncSequence(db),
    };
  }

  static Future<Map<String, String>> hydrateScalarKeyMirror(VentioDriftDatabase db) async {
    return <String, String>{
      syncSequenceKey: await readSyncSequence(db),
    };
  }

  static Future<String?> readKeyJson(VentioDriftDatabase db, String key) async {
    switch (key) {
      case syncChangesKey:
        return readSyncChangesJson(db);
      case syncQueueKey:
        return readSyncQueueJson(db);
      case syncSequenceKey:
        return readSyncSequence(db);
    }
    return null;
  }

  static Future<void> saveKeyJson(VentioDriftDatabase db, String key, String value) async {
    switch (key) {
      case syncChangesKey:
        final decoded = _decodeList(value);
        final changes = decoded
            .map((item) => SyncChange.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(growable: false);
        await replaceSyncChanges(db, changes);
        return;
      case syncQueueKey:
        final decoded = _decodeList(value);
        final queue = decoded
            .map((item) => SyncQueueItem.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(growable: false);
        await replaceSyncQueue(db, queue);
        return;
      case syncSequenceKey:
        await saveSyncSequence(db, value);
        return;
    }
  }



  static Future<void> upsertSyncChange(VentioDriftDatabase db, SyncChange change) async {
    final payloadJson = jsonEncode(change.payload);
    final syncedAt = change.syncedAt?.toIso8601String() ?? '';
    await db.transaction(() async {
      await db.customInsert(
        """
        INSERT OR REPLACE INTO sync_events
          (id, entity_type, entity_id, operation, device_id, store_id, branch_id,
           payload_json, is_synced, created_at, synced_at, store_epoch, sequence)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        variables: <Variable<Object>>[
          Variable<String>(change.id),
          Variable<String>(change.entityType),
          Variable<String>(change.entityId),
          Variable<String>(change.operation),
          Variable<String>(change.deviceId),
          Variable<String>(change.storeId),
          Variable<String>(change.branchId),
          Variable<String>(payloadJson),
          Variable<int>(change.isSynced ? 1 : 0),
          Variable<String>(change.createdAt.toIso8601String()),
          Variable<String>(syncedAt),
          Variable<int>(change.storeEpoch),
          Variable<int>(change.sequence),
        ],
      );
      if (change.isSynced) {
        await db.customStatement('DELETE FROM pending_sync_changes WHERE event_id = ?;', <Object?>[change.id]);
      } else {
        await db.customInsert(
          """
          INSERT OR REPLACE INTO pending_sync_changes
            (id, event_id, entity_type, entity_id, operation, device_id, store_id,
             branch_id, payload_json, created_at, store_epoch, sequence)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
          variables: <Variable<Object>>[
            Variable<String>('pending_${change.id}'),
            Variable<String>(change.id),
            Variable<String>(change.entityType),
            Variable<String>(change.entityId),
            Variable<String>(change.operation),
            Variable<String>(change.deviceId),
            Variable<String>(change.storeId),
            Variable<String>(change.branchId),
            Variable<String>(payloadJson),
            Variable<String>(change.createdAt.toIso8601String()),
            Variable<int>(change.storeEpoch),
            Variable<int>(change.sequence),
          ],
        );
      }
    });
  }

  static Future<void> upsertSyncQueueItem(VentioDriftDatabase db, SyncQueueItem item) async {
    await db.customInsert(
      """
      INSERT OR REPLACE INTO sync_queue
        (id, change_id, target, status, attempts, last_error, next_retry_at, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
      variables: <Variable<Object>>[
        Variable<String>(item.id),
        Variable<String>(item.changeId),
        Variable<String>(item.target),
        Variable<String>(item.status),
        Variable<int>(item.attempts),
        Variable<String>(item.lastError),
        Variable<String>(item.nextRetryAt?.toIso8601String() ?? ''),
        Variable<String>(item.createdAt.toIso8601String()),
        Variable<String>(item.updatedAt.toIso8601String()),
      ],
    );
  }

  static Future<void> migrateFromHiveIfNeeded(
    VentioDriftDatabase db, {
    required String? syncChangesJson,
    required String? syncQueueJson,
    required String? syncSequence,
  }) async {
    final metaRows = await db.customSelect(
      'SELECT value FROM migration_meta WHERE key = ?',
      variables: <Variable<Object>>[const Variable<String>('sqlite_phase2_sync_migrated')],
    ).get();
    if (metaRows.isNotEmpty && metaRows.first.read<String>('value') == 'true') return;

    if (syncChangesJson != null && syncChangesJson.trim().isNotEmpty) {
      await saveKeyJson(db, syncChangesKey, syncChangesJson);
    }
    if (syncQueueJson != null && syncQueueJson.trim().isNotEmpty) {
      await saveKeyJson(db, syncQueueKey, syncQueueJson);
    }
    if (syncSequence != null && syncSequence.trim().isNotEmpty) {
      await saveSyncSequence(db, syncSequence);
    }
    await db.customInsert(
      'INSERT OR REPLACE INTO migration_meta (key, value, updated_at) VALUES (?, ?, ?)',
      variables: <Variable<Object>>[
        const Variable<String>('sqlite_phase2_sync_migrated'),
        const Variable<String>('true'),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
      ],
    );
  }

  static Future<void> replaceSyncChanges(VentioDriftDatabase db, List<SyncChange> changes) async {
    // Performance fix: merge changes instead of deleting/reinserting the whole
    // sync history. With thousands of pending changes, the old path made every
    // normal save rewrite thousands of rows and kept the old Hive slowdown alive.
    final existingEventRows = await db.customSelect('''
      SELECT id, payload_json, is_synced, synced_at, sequence
      FROM sync_events
    ''').get();
    final existingEventSignatureById = <String, String>{
      for (final row in existingEventRows)
        row.read<String>('id'): "${row.read<String>('payload_json')}|${row.read<int>('is_synced')}|${row.read<String>('synced_at')}|${row.read<int>('sequence')}",
    };
    final existingPendingRows = await db.customSelect('SELECT event_id FROM pending_sync_changes').get();
    final existingPendingEventIds = <String>{
      for (final row in existingPendingRows) row.read<String>('event_id'),
    };
    final seenEventIds = <String>{};
    final pendingEventIds = <String>{};

    await db.transaction(() async {
      for (final change in changes) {
        seenEventIds.add(change.id);
        final payloadJson = jsonEncode(change.payload);
        final syncedAt = change.syncedAt?.toIso8601String() ?? '';
        final signature = '$payloadJson|${change.isSynced ? 1 : 0}|$syncedAt|${change.sequence}';
        if (existingEventSignatureById[change.id] != signature) {
          await db.customInsert(
            '''
            INSERT OR REPLACE INTO sync_events
              (id, entity_type, entity_id, operation, device_id, store_id, branch_id,
               payload_json, is_synced, created_at, synced_at, store_epoch, sequence)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''',
            variables: <Variable<Object>>[
              Variable<String>(change.id),
              Variable<String>(change.entityType),
              Variable<String>(change.entityId),
              Variable<String>(change.operation),
              Variable<String>(change.deviceId),
              Variable<String>(change.storeId),
              Variable<String>(change.branchId),
              Variable<String>(payloadJson),
              Variable<int>(change.isSynced ? 1 : 0),
              Variable<String>(change.createdAt.toIso8601String()),
              Variable<String>(syncedAt),
              Variable<int>(change.storeEpoch),
              Variable<int>(change.sequence),
            ],
          );
        }

        if (!change.isSynced) {
          pendingEventIds.add(change.id);
          if (!existingPendingEventIds.contains(change.id) || existingEventSignatureById[change.id] != signature) {
            await db.customInsert(
              '''
              INSERT OR REPLACE INTO pending_sync_changes
                (id, event_id, entity_type, entity_id, operation, device_id, store_id,
                 branch_id, payload_json, created_at, store_epoch, sequence)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ''',
              variables: <Variable<Object>>[
                Variable<String>('pending_${change.id}'),
                Variable<String>(change.id),
                Variable<String>(change.entityType),
                Variable<String>(change.entityId),
                Variable<String>(change.operation),
                Variable<String>(change.deviceId),
                Variable<String>(change.storeId),
                Variable<String>(change.branchId),
                Variable<String>(payloadJson),
                Variable<String>(change.createdAt.toIso8601String()),
                Variable<int>(change.storeEpoch),
                Variable<int>(change.sequence),
              ],
            );
          }
        }
      }

      final staleEventIds = existingEventSignatureById.keys.where((id) => !seenEventIds.contains(id)).toList(growable: false);
      for (final id in staleEventIds) {
        await db.customStatement('DELETE FROM sync_events WHERE id = ?;', <Object?>[id]);
      }
      final stalePendingIds = existingPendingEventIds.where((id) => !pendingEventIds.contains(id)).toList(growable: false);
      for (final eventId in stalePendingIds) {
        await db.customStatement('DELETE FROM pending_sync_changes WHERE event_id = ?;', <Object?>[eventId]);
      }
    });
  }

  static Future<void> replaceSyncQueue(VentioDriftDatabase db, List<SyncQueueItem> queue) async {
    // Performance fix: merge queue rows instead of full-table replacement.
    final existingRows = await db.customSelect('''
      SELECT id, change_id, target, status, attempts, last_error, next_retry_at, updated_at
      FROM sync_queue
    ''').get();
    final existingSignatureById = <String, String>{
      for (final row in existingRows)
        row.read<String>('id'): "${row.read<String>('change_id')}|${row.read<String>('target')}|${row.read<String>('status')}|${row.read<int>('attempts')}|${row.read<String>('last_error')}|${row.read<String>('next_retry_at')}|${row.read<String>('updated_at')}",
    };
    final seenIds = <String>{};

    await db.transaction(() async {
      for (final item in queue) {
        seenIds.add(item.id);
        final nextRetryAt = item.nextRetryAt?.toIso8601String() ?? '';
        final updatedAt = item.updatedAt.toIso8601String();
        final signature = '${item.changeId}|${item.target}|${item.status}|${item.attempts}|${item.lastError}|$nextRetryAt|$updatedAt';
        if (existingSignatureById[item.id] == signature) {
          continue;
        }
        await db.customInsert(
          '''
          INSERT OR REPLACE INTO sync_queue
            (id, change_id, target, status, attempts, last_error, next_retry_at, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          variables: <Variable<Object>>[
            Variable<String>(item.id),
            Variable<String>(item.changeId),
            Variable<String>(item.target),
            Variable<String>(item.status),
            Variable<int>(item.attempts),
            Variable<String>(item.lastError),
            Variable<String>(nextRetryAt),
            Variable<String>(item.createdAt.toIso8601String()),
            Variable<String>(updatedAt),
          ],
        );
      }

      final staleIds = existingSignatureById.keys.where((id) => !seenIds.contains(id)).toList(growable: false);
      for (final id in staleIds) {
        await db.customStatement('DELETE FROM sync_queue WHERE id = ?;', <Object?>[id]);
      }
    });
  }

  static Future<void> saveSyncSequence(VentioDriftDatabase db, String value) async {
    await db.customInsert(
      'INSERT OR REPLACE INTO migration_meta (key, value, updated_at) VALUES (?, ?, ?)',
      variables: <Variable<Object>>[
        const Variable<String>(syncSequenceKey),
        Variable<String>(value),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
      ],
    );
  }

  static Future<String> readSyncSequence(VentioDriftDatabase db) async {
    final rows = await db.customSelect(
      'SELECT value FROM migration_meta WHERE key = ?',
      variables: <Variable<Object>>[const Variable<String>(syncSequenceKey)],
    ).get();
    return rows.isEmpty ? '0' : rows.first.read<String>('value');
  }

  static Future<String> readSyncChangesJson(VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT id, entity_type, entity_id, operation, device_id, store_id, branch_id,
             payload_json, is_synced, created_at, synced_at, store_epoch, sequence
      FROM sync_events
      ORDER BY sequence ASC, created_at ASC, id ASC
    ''').get();
    final items = rows.map((row) {
      final syncedAt = row.read<String>('synced_at');
      return <String, dynamic>{
        'id': row.read<String>('id'),
        'entityType': row.read<String>('entity_type'),
        'entityId': row.read<String>('entity_id'),
        'operation': row.read<String>('operation'),
        'deviceId': row.read<String>('device_id'),
        'createdAt': row.read<String>('created_at'),
        'payload': _decodeMap(row.read<String>('payload_json')),
        'storeId': row.read<String>('store_id'),
        'branchId': row.read<String>('branch_id'),
        'isSynced': row.read<int>('is_synced') == 1,
        'syncedAt': syncedAt.isEmpty ? null : syncedAt,
        'storeEpoch': row.read<int>('store_epoch'),
        'sequence': row.read<int>('sequence'),
      };
    }).toList(growable: false);
    return jsonEncode(items);
  }

  static Future<String> readSyncQueueJson(VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT id, change_id, target, status, attempts, last_error, next_retry_at, created_at, updated_at
      FROM sync_queue
      ORDER BY created_at ASC, id ASC
    ''').get();
    final items = rows.map((row) {
      final nextRetryAt = row.read<String>('next_retry_at');
      return <String, dynamic>{
        'id': row.read<String>('id'),
        'changeId': row.read<String>('change_id'),
        'target': row.read<String>('target'),
        'status': row.read<String>('status'),
        'attempts': row.read<int>('attempts'),
        'createdAt': row.read<String>('created_at'),
        'updatedAt': row.read<String>('updated_at'),
        'lastError': row.read<String>('last_error'),
        'nextRetryAt': nextRetryAt.isEmpty ? null : nextRetryAt,
      };
    }).toList(growable: false);
    return jsonEncode(items);
  }

  static List<dynamic> _decodeList(String value) {
    if (value.trim().isEmpty) return <dynamic>[];
    final decoded = jsonDecode(value);
    return decoded is List ? decoded : <dynamic>[];
  }

  static Map<String, dynamic> _decodeMap(String value) {
    if (value.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(value);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
  }
}
