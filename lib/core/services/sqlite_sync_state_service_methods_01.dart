part of 'sqlite_sync_state_service.dart';

extension SqliteSyncStateServiceSplitPart1 on SqliteSyncStateService {

  VentioDriftDatabase? _db() {
    if (_useMemoryFallback) return null;
    return SqliteMigrationManager.database;
  }

  bool get _useMemoryFallback => LocalDatabaseService.isInMemoryStoreForTesting;

  List<SyncChange> _memorySyncChanges() {
    final raw = LocalDatabaseService.getString(SyncSqliteStore.syncChangesKey);
    if (raw == null || raw.trim().isEmpty) return const <SyncChange>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <SyncChange>[];
      return decoded
          .whereType<Map>()
          .map((item) => SyncChange.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } catch (_) {
      return const <SyncChange>[];
    }
  }

  List<SyncQueueItem> _memorySyncQueue() {
    final raw = LocalDatabaseService.getString(SyncSqliteStore.syncQueueKey);
    if (raw == null || raw.trim().isEmpty) return const <SyncQueueItem>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <SyncQueueItem>[];
      return decoded
          .whereType<Map>()
          .map(
              (item) => SyncQueueItem.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } catch (_) {
      return const <SyncQueueItem>[];
    }
  }

  Future<void> _saveMemorySyncChanges(List<SyncChange> changes) async {
    await LocalDatabaseService.setString(
      SyncSqliteStore.syncChangesKey,
      jsonEncode(changes.map((item) => item.toJson()).toList(growable: false)),
    );
  }

  Future<void> _saveMemorySyncQueue(List<SyncQueueItem> queue) async {
    await LocalDatabaseService.setString(
      SyncSqliteStore.syncQueueKey,
      jsonEncode(queue.map((item) => item.toJson()).toList(growable: false)),
    );
  }

  String _syncMetaString(SyncChange change, String key) {
    final meta = change.payload['_syncV2'];
    if (meta is Map) {
      return (meta[key] ?? '').toString();
    }
    return '';
  }

  String _encodePayloadJson(Map<String, dynamic> payload) =>
      jsonEncode(payload);

  Map<String, dynamic> _decodeMap(String value) {
    if (value.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(value);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  SyncChange _changeFromRow(QueryRow row) {
    final syncedAt = row.read<String>('synced_at');
    return SyncChange.fromJson(<String, dynamic>{
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
    });
  }

  SyncQueueItem _queueFromRow(QueryRow row) {
    final nextRetryAt = row.read<String>('next_retry_at');
    return SyncQueueItem.fromJson(<String, dynamic>{
      'id': row.read<String>('id'),
      'changeId': row.read<String>('change_id'),
      'target': row.read<String>('target'),
      'status': row.read<String>('status'),
      'attempts': row.read<int>('attempts'),
      'createdAt': row.read<String>('created_at'),
      'updatedAt': row.read<String>('updated_at'),
      'lastError': row.read<String>('last_error'),
      'nextRetryAt': nextRetryAt.isEmpty ? null : nextRetryAt,
    });
  }

  String? _businessKeyForEntityType(String entityType) {
    switch (entityType) {
      case 'role':
        return BusinessSqliteStore.rolesKey;
      case 'user':
        return BusinessSqliteStore.usersKey;
      case 'product':
        return BusinessSqliteStore.productsKey;
      case 'customer':
        return BusinessSqliteStore.customersKey;
      case 'supplier':
        return BusinessSqliteStore.suppliersKey;
      case 'supplier_product_price':
        return BusinessSqliteStore.supplierProductPricesKey;
      case 'expense':
        return BusinessSqliteStore.expensesKey;
      case 'category':
        return BusinessSqliteStore.categoriesKey;
      case 'brand':
        return BusinessSqliteStore.brandsKey;
      case 'unit':
        return BusinessSqliteStore.unitsKey;
      case 'sale':
        return BusinessSqliteStore.salesKey;
      case 'sale_quotation':
        return BusinessSqliteStore.saleQuotationsKey;
      case 'delivery_note':
        return BusinessSqliteStore.deliveryNotesKey;
      case 'bill_of_materials':
        return BusinessSqliteStore.billsOfMaterialsKey;
      case 'manufacturing_order':
        return BusinessSqliteStore.manufacturingOrdersKey;
      case 'purchase':
        return BusinessSqliteStore.purchasesKey;
      case 'warehouse_transfer_order':
        return BusinessSqliteStore.warehouseTransferOrdersKey;
      case 'inventory_count':
        return BusinessSqliteStore.inventoryCountsKey;
      case 'stock_movement':
        return BusinessSqliteStore.stockMovementsKey;
      case 'account_transaction':
        return BusinessSqliteStore.accountTransactionsKey;
    }
    return null;
  }

  String _sqliteTableForKey(String key) {
    switch (key) {
      case BusinessSqliteStore.rolesKey:
        return 'user_roles';
      case BusinessSqliteStore.usersKey:
        return 'app_users';
      case BusinessSqliteStore.productsKey:
        return 'products';
      case BusinessSqliteStore.customersKey:
        return 'customers';
      case BusinessSqliteStore.suppliersKey:
        return 'suppliers';
      case BusinessSqliteStore.supplierProductPricesKey:
        return 'supplier_product_prices';
      case BusinessSqliteStore.expensesKey:
        return 'expenses';
      case BusinessSqliteStore.categoriesKey:
        return 'catalog_categories';
      case BusinessSqliteStore.brandsKey:
        return 'catalog_brands';
      case BusinessSqliteStore.unitsKey:
        return 'catalog_units';
      case BusinessSqliteStore.salesKey:
        return 'sales';
      case BusinessSqliteStore.saleQuotationsKey:
        return 'sale_quotations';
      case BusinessSqliteStore.deliveryNotesKey:
        return 'delivery_notes';
      case BusinessSqliteStore.billsOfMaterialsKey:
        return 'bill_of_materials';
      case BusinessSqliteStore.manufacturingOrdersKey:
        return 'manufacturing_orders';
      case BusinessSqliteStore.purchasesKey:
        return 'purchases';
      case BusinessSqliteStore.warehouseTransferOrdersKey:
        return 'warehouse_transfer_orders';
      case BusinessSqliteStore.inventoryCountsKey:
        return 'inventory_counts';
      case BusinessSqliteStore.stockMovementsKey:
        return 'stock_movements';
      case BusinessSqliteStore.accountTransactionsKey:
        return 'account_transactions';
    }
    return key;
  }

  String _invoiceSequenceFromNo(String invoiceNo) {
    final matches = RegExp(r'(\d+)').allMatches(invoiceNo).toList();
    if (matches.isEmpty) return 0.toString();
    return matches.last.group(1) ?? '0';
  }

  int _sequenceFromDocumentNo(String value) {
    final raw = _invoiceSequenceFromNo(value);
    return int.tryParse(raw) ?? 0;
  }

  Future<void> _refreshKeys(
    BusinessSessionContext context,
    Iterable<String> keys,
  ) async {
    for (final key in keys.toSet()) {
      await context.refreshAfterDatabaseChange(key);
    }
  }

  Future<void> _refreshSyncKeys(BusinessSessionContext context) async {
    await _refreshKeys(context, <String>{
      SyncSqliteStore.syncChangesKey,
      SyncSqliteStore.syncQueueKey,
      SyncSqliteStore.syncSequenceKey,
    });
  }

  Future<void> _refreshSummaryTables() async {
    final db = _db();
    if (db == null) return;
    await BusinessSqliteStore.refreshSummaryTables(
      db,
      reference: DateTime.now(),
      force: true,
    );
  }

  Future<List<SyncQueueItem>> pendingSyncQueueForTarget(
    BusinessSessionContext context,
    String target, {
    bool readyOnly = true,
  }) async {
    final db = _db();
    if (db == null) {
      if (!_useMemoryFallback) return const <SyncQueueItem>[];
      final now = DateTime.now();
      final staleCutoff = now.subtract(const Duration(seconds: 45));
      return _memorySyncQueue().where((item) {
        if (item.target != target) return false;
        if (!readyOnly) {
          return item.status != 'synced' && item.status != 'rejected';
        }
        final isActive = item.status == 'pending' ||
            item.status == 'failed' ||
            (item.status == 'inProgress' &&
                item.updatedAt.isBefore(staleCutoff));
        if (!isActive) return false;
        return item.nextRetryAt == null || !item.nextRetryAt!.isAfter(now);
      }).toList(growable: false);
    }
    final now = DateTime.now();
    final conditions = <String>[
      'target = ?',
    ];
    final variables = <Variable<Object>>[
      Variable<String>(target),
    ];
    if (readyOnly) {
      final staleCutoff =
          now.subtract(const Duration(seconds: 45)).toIso8601String();
      conditions.add(
        "(status IN ('pending', 'failed') OR (status = 'inProgress' AND updated_at < ?))",
      );
      variables.add(Variable<String>(staleCutoff));
      conditions.add("(next_retry_at = '' OR next_retry_at <= ?)");
      variables.add(Variable<String>(now.toIso8601String()));
    } else {
      conditions.add("status NOT IN ('synced', 'rejected')");
    }
    final rows = await db.customSelect(
      '''
      SELECT id, change_id, target, status, attempts, last_error,
             next_retry_at, created_at, updated_at
      FROM sync_queue
      WHERE ${conditions.join(' AND ')}
      ORDER BY created_at ASC, id ASC
      ''',
      variables: variables,
    ).get();
    return rows.map(_queueFromRow).toList(growable: false);
  }

  Future<List<SyncChange>> pendingSyncChangesForTarget(
    BusinessSessionContext context,
    String target, {
    bool readyOnly = true,
    int? limit,
  }) async {
    final db = _db();
    if (db == null) {
      if (!_useMemoryFallback) return const <SyncChange>[];
      final now = DateTime.now();
      final staleCutoff = now.subtract(const Duration(seconds: 45));
      final queueByChangeId = <String, SyncQueueItem>{
        for (final item in _memorySyncQueue()) item.changeId: item,
      };
      final changes = _memorySyncChanges();
      final filtered = changes.where((change) {
        if (change.isSynced) return false;
        final item = queueByChangeId[change.id];
        if (item == null || item.target != target) return false;
        final isActive = item.status == 'pending' ||
            item.status == 'failed' ||
            (item.status == 'inProgress' &&
                item.updatedAt.isBefore(staleCutoff));
        if (!isActive) return false;
        if (readyOnly) {
          return item.nextRetryAt == null || !item.nextRetryAt!.isAfter(now);
        }
        return true;
      });
      final list = filtered.toList(growable: false);
      if (limit != null && limit > 0 && list.length > limit) {
        return list.take(limit).toList(growable: false);
      }
      return list;
    }
    final now = DateTime.now();
    final staleCutoff =
        now.subtract(const Duration(seconds: 45)).toIso8601String();
    final conditions = <String>[
      "q.target = ?",
      "(q.status IN ('pending', 'failed') OR (q.status = 'inProgress' AND q.updated_at < ?))",
    ];
    final variables = <Variable<Object>>[
      Variable<String>(target),
      Variable<String>(staleCutoff),
    ];
    if (readyOnly) {
      conditions.add("(q.next_retry_at = '' OR q.next_retry_at <= ?)");
      variables.add(Variable<String>(now.toIso8601String()));
    }
    final limitClause =
        limit != null && limit > 0 ? 'LIMIT ${limit.toInt()}' : '';
    final rows = await db.customSelect(
      '''
      SELECT p.event_id AS id, p.entity_type, p.entity_id, p.operation, p.device_id,
             p.store_id, p.branch_id, p.payload_json, p.created_at,
             p.store_epoch, p.sequence, e.is_synced, e.synced_at
      FROM pending_sync_changes p
      INNER JOIN sync_queue q ON q.change_id = p.event_id
      INNER JOIN sync_events e ON e.id = p.event_id
      WHERE ${conditions.join(' AND ')}
      ORDER BY p.sequence ASC, p.created_at ASC, p.id ASC
      $limitClause
      ''',
      variables: variables,
    ).get();
    return rows
        .map((row) => _changeFromRow(row))
        .where((item) => !item.isSynced)
        .toList(growable: false);
  }

  Future<List<SyncChange>> submittedSyncChangesForTarget(
    BusinessSessionContext context,
    String target,
  ) async {
    final db = _db();
    if (db == null) {
      if (!_useMemoryFallback) return const <SyncChange>[];
      final queueByChangeId = <String, SyncQueueItem>{
        for (final item in _memorySyncQueue()) item.changeId: item,
      };
      return _memorySyncChanges().where((change) {
        final item = queueByChangeId[change.id];
        return item != null &&
            item.target == target &&
            item.status == 'submitted' &&
            !change.isSynced;
      }).toList(growable: false);
    }
    final rows = await db.customSelect(
      '''
      SELECT p.event_id AS id, p.entity_type, p.entity_id, p.operation, p.device_id,
             p.store_id, p.branch_id, p.payload_json, p.created_at,
             p.store_epoch, p.sequence, e.is_synced, e.synced_at
      FROM pending_sync_changes p
      INNER JOIN sync_queue q ON q.change_id = p.event_id
      INNER JOIN sync_events e ON e.id = p.event_id
      WHERE q.target = ? AND q.status = 'submitted'
      ORDER BY p.sequence ASC, p.created_at ASC, p.id ASC
      ''',
      variables: <Variable<Object>>[Variable<String>(target)],
    ).get();
    return rows
        .map((row) => _changeFromRow(row))
        .where((item) => !item.isSynced)
        .toList(growable: false);
  }

  Future<int> pendingSyncQueueCount(BusinessSessionContext context) async {
    final db = _db();
    if (db == null) {
      if (!_useMemoryFallback) return 0;
      final now = DateTime.now();
      final staleCutoff = now.subtract(const Duration(seconds: 45));
      return _memorySyncQueue().where((item) {
        return item.status == 'pending' ||
            item.status == 'failed' ||
            (item.status == 'inProgress' &&
                item.updatedAt.isBefore(staleCutoff));
      }).length;
    }
    final rows = await db.customSelect(
      '''
      SELECT COUNT(*) AS value
      FROM sync_queue
      WHERE status IN ('pending', 'failed')
         OR (status = 'inProgress' AND updated_at < ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(
          DateTime.now()
              .subtract(const Duration(seconds: 45))
              .toIso8601String(),
        ),
      ],
    ).getSingle();
    return (rows.data['value'] as num?)?.toInt() ?? 0;
  }

  Future<int> pendingSyncCount(BusinessSessionContext context) async {
    return pendingSyncQueueCount(context);
  }

  Future<int> pendingSyncQueueCountForTarget(
      BusinessSessionContext context, String target,
      {bool readyOnly = true}) async {
    final db = _db();
    if (db == null) {
      if (!_useMemoryFallback) return 0;
      final now = DateTime.now();
      final staleCutoff = now.subtract(const Duration(seconds: 45));
      return _memorySyncQueue().where((item) {
        final isActive = item.status == 'pending' ||
            item.status == 'failed' ||
            (item.status == 'inProgress' &&
                item.updatedAt.isBefore(staleCutoff));
        if (!isActive || item.target != target) return false;
        if (!readyOnly) return true;
        return item.nextRetryAt == null || !item.nextRetryAt!.isAfter(now);
      }).length;
    }
    final now = DateTime.now();
    final staleCutoff =
        now.subtract(const Duration(seconds: 45)).toIso8601String();
    final conditions = <String>[
      'target = ?',
      "(status IN ('pending', 'failed') OR (status = 'inProgress' AND updated_at < ?))",
    ];
    final variables = <Variable<Object>>[
      Variable<String>(target),
      Variable<String>(staleCutoff),
    ];
    if (readyOnly) {
      conditions.add("(next_retry_at = '' OR next_retry_at <= ?)");
      variables.add(Variable<String>(now.toIso8601String()));
    }
    final row = await db.customSelect(
      '''
      SELECT COUNT(*) AS value
      FROM sync_queue
      WHERE ${conditions.join(' AND ')}
      ''',
      variables: variables,
    ).getSingle();
    return (row.data['value'] as num?)?.toInt() ?? 0;
  }

  Future<int> outstandingSyncQueueCountForTarget(
    BusinessSessionContext context,
    String target,
  ) async {
    final db = _db();
    if (db == null) {
      if (!_useMemoryFallback) return 0;
      return _memorySyncQueue()
          .where((item) => item.target == target && item.status != 'synced')
          .length;
    }
    final row = await db.customSelect(
      "SELECT COUNT(*) AS value FROM sync_queue WHERE target = ? AND status != 'synced'",
      variables: <Variable<Object>>[Variable<String>(target)],
    ).getSingle();
    return (row.data['value'] as num?)?.toInt() ?? 0;
  }

  Future<int> activeClientPendingSyncCount(
    BusinessSessionContext context,
  ) async {
    final active = context.appIdentity.activeSyncTransportNormalized;
    final target = active == 'lan'
        ? 'host'
        : active == 'direct'
            ? 'host'
            : '';
    if (target.isEmpty) return pendingSyncCount(context);
    return pendingSyncQueueCountForTarget(context, target);
  }

  Future<DateTime?> latestResetSyncAt(BusinessSessionContext context) async {
    final db = _db();
    if (db == null) return null;
    final row = await db.customSelect(
      '''
      SELECT MAX(created_at) AS value
      FROM sync_events
      WHERE entity_type = 'system' AND operation = 'reset_store_data'
      ''',
    ).getSingle();
    final raw = row.data['value']?.toString() ?? '';
    return DateTime.tryParse(raw);
  }

  Future<int> currentSyncSequence(BusinessSessionContext context) async {
    final db = _db();
    if (db == null) return 0;
    final raw = await SyncSqliteStore.readSyncSequence(db);
    return int.tryParse(raw) ?? 0;
  }

  Future<int> latestStoredAuthoritativeSequence(
    BusinessSessionContext context,
  ) async {
    final db = _db();
    if (db == null) return 0;
    final sequenceRaw = await SyncSqliteStore.readSyncSequence(db);
    final sequence = int.tryParse(sequenceRaw) ?? 0;
    final row = await db
        .customSelect(
          'SELECT COALESCE(MAX(sequence), 0) AS value FROM sync_events',
        )
        .getSingle();
    final latest = (row.data['value'] as num?)?.toInt() ?? 0;
    return latest > sequence ? latest : sequence;
  }

  Future<void> clearPendingSyncQueue(BusinessSessionContext context) async {
    final db = _db();
    if (db == null) {
      if (!_useMemoryFallback) return;
      await _saveMemorySyncQueue(const <SyncQueueItem>[]);
      await _refreshSyncKeys(context);
      return;
    }
    await db.customStatement('DELETE FROM sync_queue');
    await _refreshSyncKeys(context);
  }

  Future<void> markAllSyncChangesSynced(BusinessSessionContext context) async {
    final db = _db();
    if (db == null) {
      if (!_useMemoryFallback) return;
      final now = DateTime.now();
      final changes = _memorySyncChanges()
          .map((change) => change.copyWith(isSynced: true, syncedAt: now))
          .toList(growable: false);
      final queue = _memorySyncQueue()
          .map((item) => item.copyWith(
                status: 'synced',
                updatedAt: now,
                clearNextRetryAt: true,
              ))
          .toList(growable: false);
      await _saveMemorySyncChanges(changes);
      await _saveMemorySyncQueue(queue);
      await _refreshSyncKeys(context);
      return;
    }
    final now = DateTime.now().toIso8601String();
    await db.transaction(() async {
      await db.customUpdate(
        "UPDATE sync_events SET is_synced = 1, synced_at = ? WHERE is_synced = 0",
        variables: <Variable<Object>>[Variable<String>(now)],
      );
      await db.customUpdate(
        "UPDATE sync_queue SET status = 'synced', updated_at = ?, next_retry_at = '', last_error = '' WHERE status != 'synced'",
        variables: <Variable<Object>>[Variable<String>(now)],
      );
      await db.customStatement('DELETE FROM pending_sync_changes');
    });
    await _refreshSyncKeys(context);
  }

  Future<void> markSyncQueueChangesInProgress(
    BusinessSessionContext context,
    Iterable<String> changeIds,
  ) async {
    final db = _db();
    final ids = changeIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (db == null) {
      if (!_useMemoryFallback || ids.isEmpty) return;
      final now = DateTime.now();
      final idSet = ids.toSet();
      final queue = _memorySyncQueue()
          .map(
              (item) => idSet.contains(item.changeId) && item.status != 'synced'
                  ? item.copyWith(
                      status: 'inProgress',
                      updatedAt: now,
                      clearNextRetryAt: true,
                    )
                  : item)
          .toList(growable: false);
      await _saveMemorySyncQueue(queue);
      await _refreshSyncKeys(context);
      return;
    }
    if (ids.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    final placeholders = List<String>.filled(ids.length, '?').join(', ');
    await db.customUpdate(
      "UPDATE sync_queue SET status = 'inProgress', updated_at = ?, next_retry_at = '' WHERE change_id IN ($placeholders) AND status != 'synced'",
      variables: <Variable<Object>>[
        Variable<String>(now),
        ...ids.map((id) => Variable<String>(id)),
      ],
    );
    await _refreshSyncKeys(context);
  }

  Future<void> markSyncQueueChangesFailed(
    BusinessSessionContext context,
    Iterable<String> changeIds,
    String error,
  ) async {
    final db = _db();
    final ids = changeIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (db == null) {
      if (!_useMemoryFallback || ids.isEmpty) return;
      final now = DateTime.now();
      final idSet = ids.toSet();
      final queue = _memorySyncQueue().map((item) {
        if (!idSet.contains(item.changeId) || item.status == 'synced') {
          return item;
        }
        final attempts = item.attempts + 1;
        return item.copyWith(
          status: 'failed',
          attempts: attempts,
          lastError: error,
          updatedAt: now,
          nextRetryAt: now.add(Duration(seconds: (attempts * 5).clamp(5, 30))),
        );
      }).toList(growable: false);
      await _saveMemorySyncQueue(queue);
      await _refreshSyncKeys(context);
      return;
    }
    if (ids.isEmpty) return;
    final now = DateTime.now();
    final nextRetry = now.add(const Duration(seconds: 15)).toIso8601String();
    final placeholders = List<String>.filled(ids.length, '?').join(', ');
    await db.customUpdate(
      "UPDATE sync_queue SET status = 'failed', attempts = attempts + 1, last_error = ?, updated_at = ?, next_retry_at = ? WHERE change_id IN ($placeholders) AND status != 'synced'",
      variables: <Variable<Object>>[
        Variable<String>(error),
        Variable<String>(now.toIso8601String()),
        Variable<String>(nextRetry),
        ...ids.map((id) => Variable<String>(id)),
      ],
    );
    await _refreshSyncKeys(context);
  }
}
