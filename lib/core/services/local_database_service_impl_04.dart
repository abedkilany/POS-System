part of 'local_database_service.dart';

extension _LocalDatabaseServiceImplPart4
    on _LocalDatabaseServiceImplementation {
  /// Full diagnostic/admin snapshot for the Database page.
  ///
  /// `allEntries()` intentionally stays startup-fast after SQLite became
  /// authoritative and only returns the scalar mirror. The Database page,
  /// however, is an explicit admin browser and must show the real typed SQLite
  /// tables as well. This method hydrates those tables on demand.
  Future<Map<String, String>> adminEntries() async {
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
      final warehouseInventory = await getWarehouseInventoriesFromSqlite();
      if (warehouseInventory != null) {
        entries['warehouse_inventory'] = jsonEncode(warehouseInventory
            .map((item) => item.toJson())
            .toList(growable: false));
      }
      final stockOperations = await getStockOperationsFromSqlite();
      if (stockOperations != null) {
        entries['stock_operations'] = jsonEncode(stockOperations);
      }
      final inventoryReconciliations =
          await getInventoryReconciliationsFromSqlite();
      if (inventoryReconciliations != null) {
        entries['inventory_reconciliations'] = jsonEncode(
          inventoryReconciliations
              .map((item) => item.toJson())
              .toList(growable: false),
        );
      }
      final inventoryMigrationAdjustments =
          await getInventoryMigrationAdjustmentsFromSqlite();
      if (inventoryMigrationAdjustments != null) {
        entries['inventory_migration_adjustments'] =
            jsonEncode(inventoryMigrationAdjustments);
      }
      for (final key in SyncSqliteStore.sqliteBackedKeys) {
        final value = await SyncSqliteStore.readKeyJson(db, key);
        if (value != null) entries[key] = value;
      }
      return entries;
    }
    return const <String, String>{};
  }

  VentioDriftDatabase? _syncDatabase() {
    if (_memoryStoreForTesting != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return SqliteMigrationManager.database;
  }

  List<SyncChange> _memorySyncChanges() {
    final raw = _memoryStore?[SyncSqliteStore.syncChangesKey];
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
    final raw = _memoryStore?[SyncSqliteStore.syncQueueKey];
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

  Future<int> pendingSyncQueueCountForTarget(
    String target, {
    bool readyOnly = true,
  }) async {
    final memory = _memoryStore;
    if (memory != null) {
      final queue = _memorySyncQueue();
      final now = DateTime.now();
      final staleCutoff = now.subtract(const Duration(seconds: 45));
      return queue.where((item) {
        if (item.target != target) return false;
        final isActive = item.status == 'pending' ||
            item.status == 'failed' ||
            (item.status == 'inProgress' &&
                item.updatedAt.isBefore(staleCutoff));
        if (!isActive) return false;
        if (!readyOnly) return true;
        return item.nextRetryAt == null || !item.nextRetryAt!.isAfter(now);
      }).length;
    }
    if (_webStore != null) {
      final queueRaw = _webStore![SyncSqliteStore.syncQueueKey] ?? '[]';
      try {
        final decoded = jsonDecode(queueRaw);
        if (decoded is! List) return 0;
        final queue = decoded
            .whereType<Map>()
            .map((item) =>
                SyncQueueItem.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false);
        final now = DateTime.now();
        final staleCutoff = now.subtract(const Duration(seconds: 45));
        return queue.where((item) {
          if (item.target != target) return false;
          final isActive = item.status == 'pending' ||
              item.status == 'failed' ||
              (item.status == 'inProgress' &&
                  item.updatedAt.isBefore(staleCutoff));
          if (!isActive) return false;
          if (!readyOnly) return true;
          return item.nextRetryAt == null || !item.nextRetryAt!.isAfter(now);
        }).length;
      } catch (_) {
        return 0;
      }
    }
    final db = _syncDatabase();
    if (db == null) return 0;
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

  Future<int> pendingSyncChangesCount() async {
    final memory = _memoryStore;
    if (memory != null) {
      return _memorySyncChanges().where((item) => !item.isSynced).length;
    }
    if (_webStore != null) {
      final raw = _webStore![SyncSqliteStore.syncChangesKey] ?? '[]';
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! List) return 0;
        return decoded
            .whereType<Map>()
            .map((item) => SyncChange.fromJson(Map<String, dynamic>.from(item)))
            .where((item) => !item.isSynced)
            .length;
      } catch (_) {
        return 0;
      }
    }
    final db = _syncDatabase();
    if (db == null) return 0;
    final row = await db
        .customSelect(
          "SELECT COUNT(*) AS value FROM sync_events WHERE is_synced = 0",
        )
        .getSingle();
    return (row.data['value'] as num?)?.toInt() ?? 0;
  }

  Future<int> outstandingSyncQueueCountForTarget(String target) async {
    final memory = _memoryStore;
    if (memory != null) {
      return _memorySyncQueue()
          .where((item) => item.target == target && item.status != 'synced')
          .length;
    }
    if (_webStore != null) {
      final queueRaw = _webStore![SyncSqliteStore.syncQueueKey] ?? '[]';
      try {
        final decoded = jsonDecode(queueRaw);
        if (decoded is! List) return 0;
        return decoded
            .whereType<Map>()
            .map((item) =>
                SyncQueueItem.fromJson(Map<String, dynamic>.from(item)))
            .where((item) => item.target == target && item.status != 'synced')
            .length;
      } catch (_) {
        return 0;
      }
    }
    final db = _syncDatabase();
    if (db == null) return 0;
    final row = await db.customSelect(
      "SELECT COUNT(*) AS value FROM sync_queue WHERE target = ? AND status != 'synced'",
      variables: <Variable<Object>>[Variable<String>(target)],
    ).getSingle();
    return (row.data['value'] as num?)?.toInt() ?? 0;
  }

  bool get isEmpty {
    final memory = _memoryStore;
    if (memory != null) return memory.isEmpty;
    if (_sqliteReady) return _sqliteMirror.isEmpty;
    return true;
  }
}
