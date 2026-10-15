part of 'sqlite_sync_state_service.dart';

extension SqliteSyncStateServiceSplitPart2 on SqliteSyncStateService {

  Future<void> retryFailedSyncQueue(
    BusinessSessionContext context, {
    String? target,
  }) async {
    final db = _db();
    if (db == null) {
      if (!_useMemoryFallback) return;
      final now = DateTime.now();
      final queue = _memorySyncQueue().map((item) {
        if (item.status != 'failed' ||
            (target != null && item.target != target) ||
            (target != null &&
                item.nextRetryAt != null &&
                item.nextRetryAt!.isAfter(now))) {
          return item;
        }
        return item.copyWith(
          status: 'pending',
          updatedAt: now,
          clearNextRetryAt: true,
        );
      }).toList(growable: false);
      await _saveMemorySyncQueue(queue);
      await _refreshSyncKeys(context);
      return;
    }
    final now = DateTime.now().toIso8601String();
    if (target == null) {
      await db.customUpdate(
        "UPDATE sync_queue SET status = 'pending', updated_at = ?, next_retry_at = '' WHERE status = 'failed' AND (next_retry_at = '' OR next_retry_at <= ?)",
        variables: <Variable<Object>>[
          Variable<String>(now),
          Variable<String>(now),
        ],
      );
    } else {
      await db.customUpdate(
        "UPDATE sync_queue SET status = 'pending', updated_at = ?, next_retry_at = '' WHERE status = 'failed' AND target = ? AND (next_retry_at = '' OR next_retry_at <= ?)",
        variables: <Variable<Object>>[
          Variable<String>(now),
          Variable<String>(target),
          Variable<String>(now),
        ],
      );
    }
    await _refreshSyncKeys(context);
  }

  Future<void> recoverStaleInProgressSyncQueue(
    BusinessSessionContext context, {
    String? target,
    Duration staleAfter = const Duration(seconds: 45),
  }) async {
    final db = _db();
    if (db == null) {
      if (!_useMemoryFallback) return;
      final now = DateTime.now();
      final cutoff = now.subtract(staleAfter);
      final queue = _memorySyncQueue().map((item) {
        if (item.status != 'inProgress' ||
            !item.updatedAt.isBefore(cutoff) ||
            (target != null && item.target != target)) {
          return item;
        }
        return item.copyWith(
          status: 'pending',
          lastError:
              'Recovered stale in-progress sync item after timeout/crash.',
          updatedAt: now,
          clearNextRetryAt: true,
        );
      }).toList(growable: false);
      await _saveMemorySyncQueue(queue);
      await _refreshSyncKeys(context);
      return;
    }
    final now = DateTime.now();
    final cutoff = now.subtract(staleAfter).toIso8601String();
    if (target == null) {
      await db.customUpdate(
        "UPDATE sync_queue SET status = 'pending', last_error = ?, updated_at = ?, next_retry_at = '' WHERE status = 'inProgress' AND updated_at < ?",
        variables: <Variable<Object>>[
          Variable<String>(
            'Recovered stale in-progress sync item after timeout/crash.',
          ),
          Variable<String>(now.toIso8601String()),
          Variable<String>(cutoff),
        ],
      );
    } else {
      await db.customUpdate(
        "UPDATE sync_queue SET status = 'pending', last_error = ?, updated_at = ?, next_retry_at = '' WHERE status = 'inProgress' AND target = ? AND updated_at < ?",
        variables: <Variable<Object>>[
          Variable<String>(
            'Recovered stale in-progress sync item after timeout/crash.',
          ),
          Variable<String>(now.toIso8601String()),
          Variable<String>(target),
          Variable<String>(cutoff),
        ],
      );
    }
    await _refreshSyncKeys(context);
  }

  Future<void> recoverSubmittedSyncQueue(
    BusinessSessionContext context, {
    String? target,
  }) async {
    final db = _db();
    if (db == null) {
      if (!_useMemoryFallback) return;
      final now = DateTime.now();
      final queue = _memorySyncQueue().map((item) {
        if (item.status != 'submitted' ||
            (target != null && item.target != target)) {
          return item;
        }
        return item.copyWith(
          status: 'pending',
          lastError:
              'Recovered legacy submitted sync item for direct Host relay confirmation.',
          updatedAt: now,
          clearNextRetryAt: true,
        );
      }).toList(growable: false);
      await _saveMemorySyncQueue(queue);
      await _refreshSyncKeys(context);
      return;
    }
    final now = DateTime.now().toIso8601String();
    if (target == null) {
      await db.customUpdate(
        "UPDATE sync_queue SET status = 'pending', last_error = ?, updated_at = ?, next_retry_at = '' WHERE status = 'submitted'",
        variables: <Variable<Object>>[
          Variable<String>(
            'Recovered legacy submitted sync item for direct Host relay confirmation.',
          ),
          Variable<String>(now),
        ],
      );
    } else {
      await db.customUpdate(
        "UPDATE sync_queue SET status = 'pending', last_error = ?, updated_at = ?, next_retry_at = '' WHERE status = 'submitted' AND target = ?",
        variables: <Variable<Object>>[
          Variable<String>(
            'Recovered legacy submitted sync item for direct Host relay confirmation.',
          ),
          Variable<String>(now),
          Variable<String>(target),
        ],
      );
    }
    await _refreshSyncKeys(context);
  }

  Future<void> markSyncChangesSubmittedByIds(
    BusinessSessionContext context,
    Iterable<String> ids,
  ) async {
    final db = _db();
    final cleanIds = ids
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (db == null) {
      if (!_useMemoryFallback || cleanIds.isEmpty) return;
      final now = DateTime.now();
      final idSet = cleanIds.toSet();
      final queue = _memorySyncQueue()
          .map((item) => idSet.contains(item.changeId) &&
                  item.status != 'synced' &&
                  item.status != 'rejected'
              ? item.copyWith(
                  status: 'submitted',
                  updatedAt: now,
                  clearNextRetryAt: true,
                  lastError: '',
                )
              : item)
          .toList(growable: false);
      await _saveMemorySyncQueue(queue);
      await _refreshSyncKeys(context);
      return;
    }
    if (cleanIds.isEmpty) return;
    final placeholders = List<String>.filled(cleanIds.length, '?').join(', ');
    final now = DateTime.now().toIso8601String();
    await db.customUpdate(
      "UPDATE sync_queue SET status = 'submitted', last_error = '', updated_at = ?, next_retry_at = '' WHERE change_id IN ($placeholders) AND status NOT IN ('synced', 'rejected')",
      variables: <Variable<Object>>[
        Variable<String>(now),
        ...cleanIds.map((id) => Variable<String>(id)),
      ],
    );
    await _refreshSyncKeys(context);
  }

  Future<void> markSyncChangesSyncedByIds(
    BusinessSessionContext context,
    Iterable<String> ids,
  ) async {
    final db = _db();
    final cleanIds = ids
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (db == null) {
      if (!_useMemoryFallback || cleanIds.isEmpty) return;
      final now = DateTime.now();
      final idSet = cleanIds.toSet();
      final changesById = <String, SyncChange>{
        for (final change in _memorySyncChanges()) change.id: change,
      };
      final changes = _memorySyncChanges().map((change) {
        final matches = idSet.contains(change.id) ||
            idSet.contains(_syncMetaString(change, 'eventId')) ||
            idSet.contains(_syncMetaString(change, 'requestId')) ||
            idSet.contains(_syncMetaString(change, 'sourceCommandId'));
        if (!matches) return change;
        return change.copyWith(isSynced: true, syncedAt: now);
      }).toList(growable: false);
      final queue = _memorySyncQueue().map((item) {
        final change = changesById[item.changeId];
        final matches = idSet.contains(item.changeId) ||
            idSet.contains(item.id) ||
            (change != null &&
                (idSet.contains(_syncMetaString(change, 'eventId')) ||
                    idSet.contains(_syncMetaString(change, 'requestId')) ||
                    idSet
                        .contains(_syncMetaString(change, 'sourceCommandId'))));
        if (!matches) return item;
        return item.copyWith(
          status: 'synced',
          updatedAt: now,
          clearNextRetryAt: true,
          lastError: '',
        );
      }).toList(growable: false);
      await _saveMemorySyncChanges(changes);
      await _saveMemorySyncQueue(queue);
      await _refreshSyncKeys(context);
      return;
    }
    if (cleanIds.isEmpty) return;
    final placeholders = List<String>.filled(cleanIds.length, '?').join(', ');
    final now = DateTime.now().toIso8601String();
    await db.transaction(() async {
      await db.customUpdate(
        "UPDATE sync_events SET is_synced = 1, synced_at = ? WHERE id IN ($placeholders)",
        variables: <Variable<Object>>[
          Variable<String>(now),
          ...cleanIds.map((id) => Variable<String>(id)),
        ],
      );
      await db.customStatement(
        'DELETE FROM pending_sync_changes WHERE event_id IN ($placeholders)',
        cleanIds,
      );
      await db.customUpdate(
        "UPDATE sync_queue SET status = 'synced', updated_at = ?, next_retry_at = '', last_error = '' WHERE change_id IN ($placeholders)",
        variables: <Variable<Object>>[
          Variable<String>(now),
          ...cleanIds.map((id) => Variable<String>(id)),
        ],
      );
    });
    await _refreshSyncKeys(context);
  }

  Future<void> markSyncChangesRejectedByIds(
    BusinessSessionContext context,
    Map<String, String> rejected,
  ) async {
    final db = _db();
    if (db == null) {
      if (!_useMemoryFallback || rejected.isEmpty) return;
      final now = DateTime.now();
      final idSet = rejected.keys
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet();
      final queue = _memorySyncQueue()
          .map(
              (item) => idSet.contains(item.changeId) && item.status != 'synced'
                  ? item.copyWith(
                      status: 'rejected',
                      lastError: rejected[item.changeId] ??
                          rejected.values.join(' | '),
                      updatedAt: now,
                      clearNextRetryAt: true,
                    )
                  : item)
          .toList(growable: false);
      final changes = _memorySyncChanges()
          .map((change) => idSet.contains(change.id) ||
                  idSet.contains(_syncMetaString(change, 'eventId')) ||
                  idSet.contains(_syncMetaString(change, 'requestId')) ||
                  idSet.contains(_syncMetaString(change, 'sourceCommandId'))
              ? change.copyWith(isSynced: true, syncedAt: now)
              : change)
          .toList(growable: false);
      await _saveMemorySyncChanges(changes);
      await _saveMemorySyncQueue(queue);
      await _refreshSyncKeys(context);
      return;
    }
    if (rejected.isEmpty) return;
    final ids = rejected.keys
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) return;
    final placeholders = List<String>.filled(ids.length, '?').join(', ');
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final rows = await db.customSelect(
      '''
      SELECT id, entity_type, entity_id, operation, device_id, store_id,
             branch_id, payload_json, created_at, is_synced, synced_at,
             store_epoch, sequence
      FROM sync_events
      WHERE id IN ($placeholders)
      ''',
      variables: ids.map((id) => Variable<String>(id)).toList(growable: false),
    ).get();
    final rejectedChanges = rows.map(_changeFromRow).toList(growable: false);

    await db.transaction(() async {
      await db.customUpdate(
        "UPDATE sync_queue SET status = 'rejected', last_error = ?, updated_at = ?, next_retry_at = '' WHERE change_id IN ($placeholders) AND status != 'synced'",
        variables: <Variable<Object>>[
          Variable<String>(rejected.values.join(' | ')),
          Variable<String>(nowIso),
          ...ids.map((id) => Variable<String>(id)),
        ],
      );
      await db.customUpdate(
        "UPDATE sync_events SET is_synced = 1, synced_at = ? WHERE id IN ($placeholders)",
        variables: <Variable<Object>>[
          Variable<String>(nowIso),
          ...ids.map((id) => Variable<String>(id)),
        ],
      );
      await db.customStatement(
        'DELETE FROM pending_sync_changes WHERE event_id IN ($placeholders)',
        ids,
      );
    });

    var businessChanged = false;
    for (final change in rejectedChanges) {
      if (change.deviceId != context.deviceId || change.operation == 'delete') {
        continue;
      }
      final reason = rejected[change.id] ?? 'Rejected by Host.';
      final key = _businessKeyForEntityType(change.entityType);
      if (key == null) continue;
      final payload = Map<String, dynamic>.from(change.payload)
        ..['deletedAt'] = nowIso
        ..['updatedAt'] = nowIso
        ..['syncStatus'] = 'rejected: $reason'
        ..['deviceId'] = context.deviceId
        ..['lastModifiedByDeviceId'] = context.deviceId;
      final table = _sqliteTableForKey(key);
      if (change.entityType == 'product' ||
          change.entityType == 'customer' ||
          change.entityType == 'supplier' ||
          change.entityType == 'supplier_product_price') {
        await db.customStatement(
          'DELETE FROM $table WHERE id = ?',
          <Object?>[change.entityId],
        );
        await BusinessSqliteStore.upsertEntityPayload(db, key, payload);
        businessChanged = true;
      }
    }
    if (businessChanged) {
      await _refreshSummaryTables();
      await _refreshKeys(
        context,
        rejectedChanges
            .map((change) => _businessKeyForEntityType(change.entityType))
            .whereType<String>(),
      );
    }
    await _refreshSyncKeys(context);
  }

  Future<void> markSyncQueueItemFailed(
    BusinessSessionContext context,
    String queueItemId,
    String error,
  ) async {
    final db = _db();
    if (db == null) {
      if (!_useMemoryFallback || queueItemId.trim().isEmpty) return;
      final now = DateTime.now();
      final queue = _memorySyncQueue().map((item) {
        if (item.id != queueItemId || item.status == 'synced') {
          return item;
        }
        final attempts = item.attempts + 1;
        return item.copyWith(
          status: 'failed',
          attempts: attempts,
          lastError: error,
          updatedAt: now,
          nextRetryAt: now.add(Duration(minutes: attempts.clamp(1, 30))),
        );
      }).toList(growable: false);
      await _saveMemorySyncQueue(queue);
      await _refreshSyncKeys(context);
      return;
    }
    if (queueItemId.trim().isEmpty) return;
    final now = DateTime.now();
    await db.customUpdate(
      "UPDATE sync_queue SET status = 'failed', attempts = attempts + 1, last_error = ?, updated_at = ?, next_retry_at = ? WHERE id = ? AND status != 'synced'",
      variables: <Variable<Object>>[
        Variable<String>(error),
        Variable<String>(now.toIso8601String()),
        Variable<String>(now.add(const Duration(minutes: 1)).toIso8601String()),
        Variable<String>(queueItemId),
      ],
    );
    await _refreshSyncKeys(context);
  }

  Future<Map<String, int>> compactSyncedSyncHistoryForMaintenance(
    BusinessSessionContext context, {
    int keepRecentSyncedChanges = 200,
    int minChangesBeforeCompact = 1000,
  }) async {
    final db = _db();
    if (db == null) {
      return const <String, int>{
        'removedChanges': 0,
        'removedQueue': 0,
        'remainingChanges': 0,
        'remainingQueue': 0,
        'pendingChanges': 0,
        'pendingQueue': 0,
        'safeFloorSequence': 0,
        'earliestSequence': 0,
        'latestSequence': 0,
        'skipped': 1,
      };
    }
    final latestSequence = await latestStoredAuthoritativeSequence(context);
    final pendingQueue = await pendingSyncQueueCount(context);
    final pendingChanges = await pendingSyncCount(context);
    if (!context.appIdentity.isHost ||
        latestSequence <= 0 ||
        pendingQueue > 0 ||
        pendingChanges > 0) {
      final counts = await _countsSnapshot(db);
      return <String, int>{...counts, 'skipped': 1};
    }
    final rows = await db.customSelect('''
      SELECT id, sequence
      FROM sync_events
      WHERE is_synced = 1 AND sequence > 0
      ORDER BY sequence DESC, created_at DESC, id DESC
    ''').get();
    if (rows.length <= minChangesBeforeCompact) {
      final counts = await _countsSnapshot(db);
      return <String, int>{...counts, 'skipped': 1};
    }
    final deleteIds = rows
        .skip(keepRecentSyncedChanges)
        .map((row) => row.read<String>('id'))
        .toList(growable: false);
    if (deleteIds.isEmpty) {
      final counts = await _countsSnapshot(db);
      return <String, int>{...counts, 'skipped': 1};
    }
    final placeholders = List<String>.filled(deleteIds.length, '?').join(', ');
    await db.transaction(() async {
      await db.customStatement(
        'DELETE FROM pending_sync_changes WHERE event_id IN ($placeholders)',
        deleteIds,
      );
      await db.customStatement(
        'DELETE FROM sync_events WHERE id IN ($placeholders)',
        deleteIds,
      );
    });
    await _refreshSyncKeys(context);
    final counts = await _countsSnapshot(db);
    return {
      ...counts,
      'removedChanges': deleteIds.length,
      'removedQueue': 0,
      'pendingChanges': pendingChanges,
      'pendingQueue': pendingQueue,
      'safeFloorSequence': latestSequence,
      'earliestSequence': rows.isEmpty ? 0 : rows.last.read<int>('sequence'),
      'latestSequence': latestSequence,
      'skipped': 0,
    };
  }

  Future<Map<String, int>> compactClientSyncedSyncHistoryForMaintenance(
    BusinessSessionContext context, {
    int keepRecentSyncedChanges = 200,
  }) async {
    final db = _db();
    if (db == null) {
      return const <String, int>{
        'removedChanges': 0,
        'removedQueue': 0,
        'remainingChanges': 0,
        'remainingQueue': 0,
        'pendingChanges': 0,
        'pendingQueue': 0,
        'safeFloorSequence': 0,
        'earliestSequence': 0,
        'latestSequence': 0,
        'skipped': 1,
      };
    }
    final latestSequence = await latestStoredAuthoritativeSequence(context);
    final counts = await _countsSnapshot(db);
    if (!context.appIdentity.isClient) {
      return {...counts, 'skipped': 1};
    }
    final rows = await db.customSelect('''
      SELECT id, sequence
      FROM sync_events
      WHERE is_synced = 1 AND sequence > 0
      ORDER BY sequence DESC, created_at DESC, id DESC
    ''').get();
    if (rows.length <= keepRecentSyncedChanges) {
      return {...counts, 'skipped': 1};
    }
    final deleteIds = rows
        .skip(keepRecentSyncedChanges)
        .map((row) => row.read<String>('id'))
        .toList(growable: false);
    if (deleteIds.isNotEmpty) {
      final placeholders =
          List<String>.filled(deleteIds.length, '?').join(', ');
      await db.transaction(() async {
        await db.customStatement(
          'DELETE FROM pending_sync_changes WHERE event_id IN ($placeholders)',
          deleteIds,
        );
        await db.customStatement(
          'DELETE FROM sync_events WHERE id IN ($placeholders)',
          deleteIds,
        );
      });
      await _refreshSyncKeys(context);
    }
    final afterCounts = await _countsSnapshot(db);
    return {
      ...afterCounts,
      'removedChanges': deleteIds.length,
      'removedQueue': 0,
      'pendingChanges': await pendingSyncCount(context),
      'pendingQueue': await pendingSyncQueueCount(context),
      'safeFloorSequence': latestSequence,
      'earliestSequence': rows.isEmpty ? 0 : rows.last.read<int>('sequence'),
      'latestSequence': latestSequence,
      'skipped': 0,
    };
  }

  Future<Map<String, int>> _countsSnapshot(VentioDriftDatabase db) async {
    final changeRow = await db
        .customSelect(
          'SELECT COUNT(*) AS value FROM sync_events',
        )
        .getSingle();
    final queueRow = await db
        .customSelect(
          'SELECT COUNT(*) AS value FROM sync_queue',
        )
        .getSingle();
    return <String, int>{
      'remainingChanges': (changeRow.data['value'] as num?)?.toInt() ?? 0,
      'remainingQueue': (queueRow.data['value'] as num?)?.toInt() ?? 0,
      'pendingChanges': 0,
      'pendingQueue': 0,
      'removedChanges': 0,
      'removedQueue': 0,
      'safeFloorSequence': 0,
      'earliestSequence': 0,
      'latestSequence': 0,
      'skipped': 0,
    };
  }

  Future<void> applyAuthoritativeSyncChangesToSqliteTransaction(
    BusinessSessionContext context,
    List<SyncChange> incoming, {
    bool markAppliedAsSynced = false,
    bool mirrorToDirect = false,
  }) async {
    final db = _db();
    if (db == null) return;
    await LocalDatabaseService.runSqliteAuthoritativeTransaction(() async {
      await _applyRemoteSyncChanges(
        context,
        db,
        incoming,
        markAppliedAsSynced: markAppliedAsSynced,
        mirrorToDirect: mirrorToDirect,
      );
    });
    await _refreshSummaryTables();
    await _refreshSyncKeys(context);
  }
}
