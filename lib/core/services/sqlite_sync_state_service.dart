import 'dart:convert';

import 'package:drift/drift.dart';

import 'local_database_service.dart';
import '../repositories/business_session_context.dart';
import '../storage/sqlite/business_sqlite_store.dart';
import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/sync_sqlite_store.dart';
import '../storage/sqlite/ventio_drift_database.dart';
import '../repositories/warehouse_inventory_repository.dart';
import '../../models/app_identity.dart';
import '../../models/sync_change.dart';
import '../../models/sync_queue_item.dart';
import '../../models/store_profile.dart';
import '../../models/stock_movement.dart';
import '../../models/warehouse_inventory.dart';

const String _appIdentityKey = 'app_identity_v1';
const String _storeProfileKey = 'store_profile_v5';
const String _hostTransferRequestKey = 'host_transfer_request_v1';
const String _hostTransferApprovedDeviceKey =
    'host_transfer_approved_device_v1';
const String _cloudHostBootstrapMarkerPrefix =
    'cloud_host_bootstrap_snapshot_v3_';
const String _invoiceCounterKey = 'invoice_counter_v1';
const String _purchaseCounterKey = 'purchase_counter_v1';

enum _StockOperationState {
  proceed,
  completed,
  inProgress,
}

class SqliteSyncStateService {
  const SqliteSyncStateService();

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
          .map((item) => SyncQueueItem.fromJson(Map<String, dynamic>.from(item)))
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
            (item.status == 'inProgress' && item.updatedAt.isBefore(staleCutoff));
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
      final staleCutoff = now
          .subtract(const Duration(seconds: 45))
          .toIso8601String();
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
            (item.status == 'inProgress' && item.updatedAt.isBefore(staleCutoff));
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
    final staleCutoff = now
        .subtract(const Duration(seconds: 45))
        .toIso8601String();
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
        return item != null && item.target == target && item.status == 'submitted' && !change.isSynced;
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
            (item.status == 'inProgress' && item.updatedAt.isBefore(staleCutoff));
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
    BusinessSessionContext context,
    String target,
    {bool readyOnly = true}
  ) async {
    final db = _db();
    if (db == null) {
      if (!_useMemoryFallback) return 0;
      final now = DateTime.now();
      final staleCutoff = now.subtract(const Duration(seconds: 45));
      return _memorySyncQueue().where((item) {
        final isActive = item.status == 'pending' ||
            item.status == 'failed' ||
            (item.status == 'inProgress' && item.updatedAt.isBefore(staleCutoff));
        if (!isActive || item.target != target) return false;
        if (!readyOnly) return true;
        return item.nextRetryAt == null || !item.nextRetryAt!.isAfter(now);
      }).length;
    }
    final now = DateTime.now();
    final staleCutoff = now
        .subtract(const Duration(seconds: 45))
        .toIso8601String();
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
        : active == 'cloud'
            ? 'cloud_host'
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
    final row = await db.customSelect(
      'SELECT COALESCE(MAX(sequence), 0) AS value FROM sync_events',
    ).getSingle();
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
    final ids = changeIds.map((item) => item.trim()).where((item) => item.isNotEmpty).toList(growable: false);
    if (db == null) {
      if (!_useMemoryFallback || ids.isEmpty) return;
      final now = DateTime.now();
      final idSet = ids.toSet();
      final queue = _memorySyncQueue()
          .map((item) => idSet.contains(item.changeId) && item.status != 'synced'
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
      final queue = _memorySyncQueue()
          .map((item) {
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
          })
          .toList(growable: false);
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

  Future<void> retryFailedSyncQueue(
    BusinessSessionContext context, {
    String? target,
  }) async {
    final db = _db();
    if (db == null) {
      if (!_useMemoryFallback) return;
      final now = DateTime.now();
      final queue = _memorySyncQueue()
          .map((item) {
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
          })
          .toList(growable: false);
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
      final queue = _memorySyncQueue()
          .map((item) {
            if (item.status != 'inProgress' ||
                !item.updatedAt.isBefore(cutoff) ||
                (target != null && item.target != target)) {
              return item;
            }
            return item.copyWith(
              status: 'pending',
              lastError: 'Recovered stale in-progress sync item after timeout/crash.',
              updatedAt: now,
              clearNextRetryAt: true,
            );
          })
          .toList(growable: false);
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
      final queue = _memorySyncQueue()
          .map((item) {
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
          })
          .toList(growable: false);
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

  Future<int> removeLegacyCloudBootstrapSnapshotQueue(
    BusinessSessionContext context,
  ) async {
    final db = _db();
    if (db == null || !context.appIdentity.isHost || !context.appIdentity.isCloudEnabled) {
      return 0;
    }
    final rows = await db.customSelect(
      '''
      SELECT id
      FROM sync_events
      WHERE entity_type = 'system'
        AND entity_id = 'store'
        AND operation = 'restore_snapshot'
        AND store_id = ?
        AND is_synced = 0
      ''',
      variables: <Variable<Object>>[Variable<String>(context.appIdentity.storeId)],
    ).get();
    final ids = rows
        .map((row) => row.read<String>('id'))
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) return 0;
    final placeholders = List<String>.filled(ids.length, '?').join(', ');
    await db.transaction(() async {
      await db.customStatement(
        'DELETE FROM sync_queue WHERE change_id IN ($placeholders)',
        ids,
      );
      await db.customStatement(
        'DELETE FROM sync_events WHERE id IN ($placeholders)',
        ids,
      );
    });
    await _refreshSyncKeys(context);
    return ids.length;
  }

  Future<int> repairMissingHostCloudQueueForPendingChanges(
    BusinessSessionContext context,
  ) async {
    final db = _db();
    if (db == null || !context.appIdentity.isHost || !context.appIdentity.isCloudEnabled) {
      return 0;
    }
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final rows = await db.customSelect(
      '''
      SELECT id, device_id, store_id, branch_id, payload_json, operation,
             entity_type, entity_id, created_at, store_epoch, sequence
      FROM sync_events
      WHERE is_synced = 0
        AND (store_id = ? OR store_id = '')
      ORDER BY sequence ASC, created_at ASC, id ASC
      ''',
      variables: <Variable<Object>>[Variable<String>(context.appIdentity.storeId)],
    ).get();
    final existingCloudQueueIds = await db.customSelect(
      "SELECT change_id FROM sync_queue WHERE target = 'cloud' AND status != 'synced'",
    ).get();
    final existingAnyCloudQueueIds = await db.customSelect(
      "SELECT change_id FROM sync_queue WHERE target = 'cloud'",
    ).get();
    final pendingIds = existingCloudQueueIds
        .map((row) => row.read<String>('change_id'))
        .toSet();
    final anyIds = existingAnyCloudQueueIds
        .map((row) => row.read<String>('change_id'))
        .toSet();

    var repaired = 0;
    for (final row in rows) {
      final change = _changeFromRow(
        row,
      );
      if (change.deviceId == 'cloud-snapshot') continue;
      if (change.isSynced) continue;
      final meta = _decodeMap(change.payload['_syncV2'] is Map
          ? jsonEncode(change.payload['_syncV2'])
          : '{}');
      final kind = (meta['kind'] ?? '').toString();
      final isAuthoritative =
          kind.isEmpty || kind == 'authoritativeEvent' || change.deviceId == context.deviceId;
      if (!isAuthoritative) continue;
      if (pendingIds.contains(change.id)) continue;
      if (anyIds.contains(change.id)) {
        await db.customUpdate(
          "UPDATE sync_queue SET status = 'pending', updated_at = ?, next_retry_at = '', last_error = '' WHERE target = 'cloud' AND change_id = ? AND status = 'synced'",
          variables: <Variable<Object>>[
            Variable<String>(nowIso),
            Variable<String>(change.id),
          ],
        );
        pendingIds.add(change.id);
        repaired += 1;
        continue;
      }
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO sync_queue
          (id, change_id, target, status, attempts, last_error, next_retry_at, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>('${change.id}-cloud'),
          Variable<String>(change.id),
          Variable<String>('cloud'),
          const Variable<String>('pending'),
          const Variable<int>(0),
          const Variable<String>(''),
          const Variable<String>(''),
          Variable<String>(nowIso),
          Variable<String>(nowIso),
        ],
      );
      pendingIds.add(change.id);
      anyIds.add(change.id);
      repaired += 1;
    }
    if (repaired > 0) {
      await _refreshSyncKeys(context);
    }
    return repaired;
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
      final changes = _memorySyncChanges()
          .map((change) {
            final matches = idSet.contains(change.id) ||
                idSet.contains(_syncMetaString(change, 'eventId')) ||
                idSet.contains(_syncMetaString(change, 'requestId')) ||
                idSet.contains(_syncMetaString(change, 'sourceCommandId'));
            if (!matches) return change;
            return change.copyWith(isSynced: true, syncedAt: now);
          })
          .toList(growable: false);
      final queue = _memorySyncQueue().map((item) {
        final change = changesById[item.changeId];
        final matches = idSet.contains(item.changeId) ||
            idSet.contains(item.id) ||
            (change != null &&
                (idSet.contains(_syncMetaString(change, 'eventId')) ||
                    idSet.contains(_syncMetaString(change, 'requestId')) ||
                    idSet.contains(_syncMetaString(change, 'sourceCommandId'))));
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
      final idSet = rejected.keys.map((item) => item.trim()).where((item) => item.isNotEmpty).toSet();
      final queue = _memorySyncQueue()
          .map((item) => idSet.contains(item.changeId) && item.status != 'synced'
              ? item.copyWith(
                  status: 'rejected',
                  lastError: rejected[item.changeId] ?? rejected.values.join(' | '),
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
    final ids = rejected.keys.map((item) => item.trim()).where((item) => item.isNotEmpty).toList(growable: false);
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
      final queue = _memorySyncQueue()
          .map((item) {
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
          })
          .toList(growable: false);
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
    final changeRow = await db.customSelect(
      'SELECT COUNT(*) AS value FROM sync_events',
    ).getSingle();
    final queueRow = await db.customSelect(
      'SELECT COUNT(*) AS value FROM sync_queue',
    ).getSingle();
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
    bool mirrorToCloud = false,
  }) async {
    final db = _db();
    if (db == null) return;
    await LocalDatabaseService.runSqliteAuthoritativeTransaction(() async {
      await _applyRemoteSyncChanges(
        context,
        db,
        incoming,
        markAppliedAsSynced: markAppliedAsSynced,
        mirrorToCloud: mirrorToCloud,
      );
    });
    await _refreshSummaryTables();
    await _refreshSyncKeys(context);
  }

  Future<void> _applyRemoteSyncChanges(
    BusinessSessionContext context,
    VentioDriftDatabase db,
    List<SyncChange> incoming, {
    required bool markAppliedAsSynced,
    required bool mirrorToCloud,
  }) async {
    final sorted = [...incoming]..sort((a, b) {
        final epochCompare = a.storeEpoch.compareTo(b.storeEpoch);
        if (epochCompare != 0) return epochCompare;
        if (a.sequence != 0 || b.sequence != 0) {
          return a.sequence.compareTo(b.sequence);
        }
        return a.createdAt.compareTo(b.createdAt);
      });

    final latestSequence = await latestStoredAuthoritativeSequence(context);
    final currentEpoch = context.appIdentity.storeEpoch;
    final refreshKeys = <String>{};
    final storedChanges = <SyncChange>[];
    final queueItems = <SyncQueueItem>[];
    var nextSequence = await currentSyncSequence(context);
    var changed = false;
    var businessChanged = false;

    for (final change in sorted) {
      if (change.sequence > 0 && change.sequence <= latestSequence) {
        continue;
      }
      if (change.storeEpoch < currentEpoch &&
          !(change.entityType == 'system' &&
              change.operation == 'reset_store_data')) {
        continue;
      }

      final acceptedAt = DateTime.now();
      final shouldRestampAsHostAuthority =
          context.appIdentity.isHost && change.deviceId != context.deviceId;
      final incomingMeta = _decodeMap(
        change.payload['_syncV2'] is Map
            ? jsonEncode(change.payload['_syncV2'])
            : '{}',
      );
      final requestId = (incomingMeta['requestId'] ?? change.id).toString();
      final authoritativeEventId = shouldRestampAsHostAuthority
          ? 'evt_${acceptedAt.microsecondsSinceEpoch}'
          : change.id;
      final authoritativePayload = shouldRestampAsHostAuthority
          ? <String, dynamic>{
              ...change.payload,
              '_syncV2': <String, dynamic>{
                ...incomingMeta,
                'kind': 'authoritativeEvent',
                'requestId': requestId,
                'eventId': authoritativeEventId,
                'acceptedByHostDeviceId': context.deviceId,
                'acceptedAt': acceptedAt.toIso8601String(),
                'sourceCommandId': requestId,
                'sourceCommandDeviceId': change.deviceId,
              },
            }
          : change.payload;
      final authoritativeChange = shouldRestampAsHostAuthority
          ? change.copyWith(
              id: authoritativeEventId,
              createdAt: acceptedAt,
              deviceId: context.deviceId,
              storeId: context.appIdentity.storeId,
              branchId: context.appIdentity.branchId,
              payload: authoritativePayload,
              storeEpoch: context.appIdentity.storeEpoch,
              sequence: nextSequence = nextSequence + 1,
            )
          : change;
      final storedChange = markAppliedAsSynced && !mirrorToCloud
          ? authoritativeChange.copyWith(
              isSynced: true,
              syncedAt: acceptedAt,
            )
          : authoritativeChange.copyWith(
              isSynced: false,
              syncedAt: null,
            );
      storedChanges.add(storedChange);
      changed = true;

      final key = _businessKeyForEntityType(change.entityType);
      if (key != null) {
        refreshKeys.add(key);
      }

      switch (change.entityType) {
        case 'system':
          if (change.operation == 'reset_store_data') {
            await _applySystemReset(
              context,
              keepStoreProfile: change.payload['keepStoreProfile'] as bool? ?? true,
            );
            businessChanged = true;
          } else if (change.operation == 'request_snapshot') {
            if (context.appIdentity.isHost && context.appIdentity.isCloudEnabled) {
              await LocalDatabaseService.setString(
                '$_cloudHostBootstrapMarkerPrefix${context.appIdentity.storeId}',
                'direct_chunked',
              );
            }
          }
          break;
        case 'host_transfer':
          if (change.operation == 'request') {
            if (context.appIdentity.isHost) {
              await LocalDatabaseService.setString(
                _hostTransferRequestKey,
                _encodePayloadJson(change.payload),
              );
            }
          } else if (change.operation == 'approve') {
            final approvedDeviceId =
                change.payload['approvedDeviceId']?.toString().trim() ?? '';
            if (approvedDeviceId == context.deviceId) {
              await LocalDatabaseService.setString(
                _hostTransferApprovedDeviceKey,
                approvedDeviceId,
              );
            }
          }
          break;
        case 'store_profile':
          await BusinessSqliteStore.saveKeyJson(
            db,
            _storeProfileKey,
            _encodePayloadJson(change.payload),
          );
          refreshKeys.add(_storeProfileKey);
          businessChanged = true;
          break;
        case 'app_identity':
          if (change.entityId == context.deviceId) {
            final incomingIdentity = AppIdentity.fromJson(change.payload)
                .copyWith(
                  deviceId: context.deviceId,
                  platform: context.appIdentity.platform,
                  updatedAt: DateTime.now(),
                );
            await BusinessSqliteStore.saveKeyJson(
              db,
              _appIdentityKey,
              _encodePayloadJson(incomingIdentity.toJson()),
            );
            refreshKeys.add(_appIdentityKey);
          }
          break;
        case 'role':
        case 'user':
        case 'product':
        case 'customer':
        case 'supplier':
        case 'expense':
        case 'category':
        case 'brand':
        case 'unit':
        case 'sale':
        case 'sale_quotation':
        case 'delivery_note':
        case 'bill_of_materials':
        case 'manufacturing_order':
        case 'purchase':
        case 'account_transaction':
        case 'inventory_count':
          await _applyBusinessEntityChange(
            db,
            change,
            refreshKeys: refreshKeys,
          );
          businessChanged = true;
          break;
        case 'supplier_product_price':
          await _applySupplierPriceChange(
            db,
            change,
            refreshKeys: refreshKeys,
          );
          businessChanged = true;
          break;
        case 'stock_movement':
          await _applyStockMovementChange(
            context,
            db,
            change,
            refreshKeys: refreshKeys,
          );
          businessChanged = true;
          break;
      }

      if (mirrorToCloud &&
          context.appIdentity.isHost &&
          change.deviceId != context.deviceId &&
          change.deviceId != 'cloud-snapshot') {
        queueItems.add(
          SyncQueueItem(
            id: '${storedChange.id}-cloud',
            changeId: storedChange.id,
            target: 'cloud',
            status: 'pending',
            attempts: 0,
            createdAt: acceptedAt,
            updatedAt: acceptedAt,
          ),
        );
      }
    }

    if (storedChanges.isNotEmpty) {
      await SyncSqliteStore.upsertSyncChanges(db, storedChanges);
    }
    if (queueItems.isNotEmpty) {
      await SyncSqliteStore.upsertSyncQueueItems(db, queueItems);
    }

    if (businessChanged) {
      await _refreshSummaryTables();
      await _refreshKeys(context, refreshKeys);
    }
    if (changed) {
      await _refreshSyncKeys(context);
    }
  }

  Future<void> _applyBusinessEntityChange(
    VentioDriftDatabase db,
    SyncChange change, {
    required Set<String> refreshKeys,
  }) async {
    final key = _businessKeyForEntityType(change.entityType);
    if (key == null) return;
    final table = _sqliteTableForKey(key);
    final isDelete = change.operation == 'delete' && change.payload.isEmpty;
    if (isDelete) {
      await db.customStatement(
        'DELETE FROM $table WHERE id = ?',
        <Object?>[change.entityId],
      );
      return;
    }

    await BusinessSqliteStore.upsertEntityPayload(
      db,
      key,
      change.payload,
    );
    refreshKeys.add(key);

    if (change.entityType == 'sale') {
      final invoice = _sequenceFromDocumentNo(
        change.payload['invoiceNo']?.toString() ?? '',
      );
      if (invoice > 0) {
        final current = await _currentCounterValue(db, _invoiceCounterKey);
        if (invoice > current) {
          await BusinessSqliteStore.saveKeyJson(
            db,
            _invoiceCounterKey,
            invoice.toString(),
          );
        }
      }
    }
    if (change.entityType == 'purchase') {
      final purchase = _sequenceFromDocumentNo(
        change.payload['purchaseNo']?.toString() ?? '',
      );
      if (purchase > 0) {
        final current = await _currentCounterValue(db, _purchaseCounterKey);
        if (purchase > current) {
          await BusinessSqliteStore.saveKeyJson(
            db,
            _purchaseCounterKey,
            purchase.toString(),
          );
        }
      }
    }
  }

  Future<void> _applySupplierPriceChange(
    VentioDriftDatabase db,
    SyncChange change, {
    required Set<String> refreshKeys,
  }) async {
    final key = BusinessSqliteStore.supplierProductPricesKey;
    final table = _sqliteTableForKey(key);
    final isDelete = change.operation == 'delete' && change.payload.isEmpty;
    if (isDelete) {
      await db.customStatement(
        'DELETE FROM $table WHERE id = ?',
        <Object?>[change.entityId],
      );
      return;
    }
    await BusinessSqliteStore.upsertEntityPayload(
      db,
      key,
      change.payload,
    );
    refreshKeys.add(key);
    final isPreferred = change.payload['isPreferred'] == true ||
        change.payload['isPreferred'] == 1;
    if (isPreferred) {
      final productId = change.payload['productId']?.toString() ?? '';
      final supplierId = change.payload['supplierId']?.toString() ?? '';
      if (productId.isNotEmpty && supplierId.isNotEmpty) {
        await db.customUpdate(
          """
          UPDATE supplier_product_prices
          SET is_preferred = 0, updated_at = ?
          WHERE product_id = ? AND supplier_id = ? AND id <> ? AND deleted_at = ''
          """,
          variables: <Variable<Object>>[
            Variable<String>(DateTime.now().toIso8601String()),
            Variable<String>(productId),
            Variable<String>(supplierId),
            Variable<String>(change.entityId),
          ],
        );
      }
    }
  }

  Future<void> _applyStockMovementChange(
    BusinessSessionContext context,
    VentioDriftDatabase db,
    SyncChange change, {
    required Set<String> refreshKeys,
  }) async {
    final key = BusinessSqliteStore.stockMovementsKey;
    final table = _sqliteTableForKey(key);
    final isDelete = change.operation == 'delete' && change.payload.isEmpty;
    if (isDelete) {
      await db.customStatement(
        'DELETE FROM $table WHERE id = ?',
        <Object?>[change.entityId],
      );
      return;
    }

    final movement = StockMovement.fromJson(change.payload).copyWith(
      id: change.entityId,
      syncStatus: 'synced',
      storeId: change.storeId.isEmpty ? context.appIdentity.storeId : change.storeId,
      branchId:
          change.branchId.trim().isEmpty ? context.appIdentity.branchId : change.branchId.trim(),
      movementGroupId:
          _syncMetaString(change, 'movementGroupId').trim().isNotEmpty
              ? _syncMetaString(change, 'movementGroupId').trim()
              : _syncMetaString(change, 'groupId').trim(),
      documentLineId: _syncMetaString(change, 'documentLineId').trim(),
      sourceMovementId: _syncMetaString(change, 'sourceMovementId').trim(),
      reversalOfMovementId:
          _syncMetaString(change, 'reversalOfMovementId').trim(),
      idempotencyKey: _stockOperationIdempotencyKey(
        change,
        StockMovement.fromJson(change.payload),
      ),
    );
    final operationKey = _stockOperationIdempotencyKey(change, movement);
    final operation = await _acquireStockOperation(
      db,
      context: context,
      change: change,
      movement: movement,
      idempotencyKey: operationKey,
    );
    if (operation == _StockOperationState.completed) {
      refreshKeys.add(key);
      return;
    }
    if (operation == _StockOperationState.inProgress) {
      return;
    }

    try {
      await BusinessSqliteStore.upsertEntityPayload(
        db,
        key,
        movement.toJson(),
      );
      refreshKeys.add(key);

      final hasAppliedMovement = await _hasAppliedStockMovement(
        db,
        movement: movement,
      );
      if (!hasAppliedMovement) {
        await _applyWarehouseAwareMovement(
          db,
          context: context,
          movement: movement,
        );
      }

      await _updateProductCompatibilityCacheFromWarehouseInventory(
        db,
        storeId: movement.storeId.isEmpty
            ? context.appIdentity.storeId
            : movement.storeId,
        productId: movement.productId,
      );
      refreshKeys.add(BusinessSqliteStore.productsKey);
      await _markStockOperationCompleted(
        db,
        context: context,
        change: change,
        movement: movement,
        idempotencyKey: operationKey,
      );
    } catch (error) {
      await _markStockOperationFailed(
        db,
        context: context,
        change: change,
        movement: movement,
        idempotencyKey: operationKey,
        reason: error.toString(),
      );
      rethrow;
    }
  }

  String _stockOperationIdempotencyKey(
    SyncChange change,
    StockMovement movement,
  ) {
    final payloadKey = _syncMetaString(change, 'idempotencyKey').trim();
    if (payloadKey.isNotEmpty) return payloadKey;
    final requestId = _syncMetaString(change, 'requestId').trim();
    if (requestId.isNotEmpty) return requestId;
    final explicit = movement.idempotencyKey.trim();
    if (explicit.isNotEmpty) return explicit;
    return change.id.trim();
  }

  Future<_StockOperationState> _acquireStockOperation(
    VentioDriftDatabase db, {
    required BusinessSessionContext context,
    required SyncChange change,
    required StockMovement movement,
    required String idempotencyKey,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await db.customSelect(
      '''
      SELECT status, updated_at AS updatedAt
      FROM stock_operations
      WHERE store_id = ? AND idempotency_key = ?
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(change.storeId.isEmpty
            ? context.appIdentity.storeId
            : change.storeId),
        Variable<String>(idempotencyKey),
      ],
    ).get();
    if (rows.isNotEmpty) {
      final status = rows.first.read<String>('status');
      final updatedAt = DateTime.tryParse(rows.first.read<String>('updatedAt'));
      if (status == 'completed') return _StockOperationState.completed;
      if (status == 'pending' &&
          updatedAt != null &&
          DateTime.now().toUtc().difference(updatedAt).inSeconds < 30) {
        return _StockOperationState.inProgress;
      }
    }
    await db.customInsert(
      '''
      INSERT INTO stock_operations
        (id, store_id, branch_id, operation_type, document_type, document_id,
         movement_group_id, idempotency_key, status, created_at, started_at,
         updated_at, completed_at, failure_reason, attempt_count, device_id,
         last_modified_by_device_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?, '', '', 0, ?, ?)
      ON CONFLICT(store_id, idempotency_key) DO UPDATE SET
        branch_id = excluded.branch_id,
        operation_type = excluded.operation_type,
        document_type = excluded.document_type,
        document_id = excluded.document_id,
        movement_group_id = excluded.movement_group_id,
        status = CASE
          WHEN stock_operations.status = 'completed' THEN stock_operations.status
          ELSE 'pending'
        END,
        started_at = CASE
          WHEN stock_operations.status = 'completed' THEN stock_operations.started_at
          ELSE excluded.started_at
        END,
        updated_at = excluded.updated_at,
        failure_reason = CASE
          WHEN stock_operations.status = 'completed' THEN stock_operations.failure_reason
          ELSE ''
        END,
        attempt_count = CASE
          WHEN stock_operations.status = 'completed' THEN stock_operations.attempt_count
          ELSE stock_operations.attempt_count + 1
        END,
        device_id = excluded.device_id,
        last_modified_by_device_id = excluded.last_modified_by_device_id
      ''',
      variables: <Variable<Object>>[
        Variable<String>('op_${movement.id}'),
        Variable<String>(change.storeId.isEmpty
            ? context.appIdentity.storeId
            : change.storeId),
        Variable<String>(change.branchId.trim().isEmpty
            ? context.appIdentity.branchId
            : change.branchId.trim()),
        Variable<String>('sync_replay'),
        Variable<String>('stock_movement'),
        Variable<String>(change.entityId),
        Variable<String>(movement.movementGroupId.isEmpty
            ? movement.id
            : movement.movementGroupId),
        Variable<String>(idempotencyKey),
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(movement.deviceId),
        Variable<String>(movement.lastModifiedByDeviceId),
      ],
    );
    return _StockOperationState.proceed;
  }

  Future<bool> _hasAppliedStockMovement(
    VentioDriftDatabase db, {
    required StockMovement movement,
  }) async {
    final rows = await db.customSelect(
      '''
      SELECT id
      FROM stock_movements
      WHERE (idempotency_key <> '' AND idempotency_key = ?)
         OR id = ?
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(movement.idempotencyKey.trim()),
        Variable<String>(movement.id),
      ],
    ).get();
    return rows.isNotEmpty;
  }

  Future<void> _applyWarehouseAwareMovement(
    VentioDriftDatabase db, {
    required BusinessSessionContext context,
    required StockMovement movement,
  }) async {
    final storeId = movement.storeId.trim().isEmpty
        ? context.appIdentity.storeId
        : movement.storeId.trim();
    final branchId = movement.branchId.trim().isEmpty
        ? context.appIdentity.branchId
        : movement.branchId.trim();
    final warehouseId = movement.warehouseId.trim().isEmpty
        ? 'main'
        : movement.warehouseId.trim();
    final inventory = await WarehouseInventoryRepository.getByIdentity(
      db,
      storeId: storeId,
      warehouseId: warehouseId,
      productId: movement.productId,
    );
    final nextQuantity = (inventory?.quantity ?? 0) + movement.quantity;
    await WarehouseInventoryRepository.upsert(
      db,
      WarehouseInventory(
        id: inventory?.id ??
            'wi_${storeId}_${warehouseId}_${movement.productId}',
        storeId: storeId,
        branchId: branchId,
        warehouseId: warehouseId,
        productId: movement.productId,
        quantity: nextQuantity,
        version: (inventory?.version ?? 0) + 1,
        createdAt: inventory?.createdAt ?? movement.createdAt,
        updatedAt: movement.updatedAt,
        deviceId: movement.deviceId,
        syncStatus: 'synced',
        lastModifiedByDeviceId: movement.lastModifiedByDeviceId,
      ),
    );
  }

  Future<void> _updateProductCompatibilityCacheFromWarehouseInventory(
    VentioDriftDatabase db, {
    required String storeId,
    required String productId,
  }) async {
    final rows = await db.customSelect(
      '''
      SELECT COALESCE(SUM(quantity), 0) AS quantity
      FROM warehouse_inventory
      WHERE store_id = ? AND product_id = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(productId),
      ],
    ).get();
    if (rows.isEmpty) return;
    final quantity = rows.first.read<num>('quantity').toDouble();
    await db.customUpdate(
      '''
      UPDATE products
      SET stock = ?, updated_at = ?
      WHERE store_id = ? AND id = ?
      ''',
      variables: <Variable<Object>>[
        Variable<double>(quantity),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
        Variable<String>(storeId),
        Variable<String>(productId),
      ],
    );
  }

  Future<void> _markStockOperationCompleted(
    VentioDriftDatabase db, {
    required BusinessSessionContext context,
    required SyncChange change,
    required StockMovement movement,
    required String idempotencyKey,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.customUpdate(
      '''
      UPDATE stock_operations
      SET status = 'completed',
          updated_at = ?,
          completed_at = ?,
          failure_reason = '',
          attempt_count = attempt_count + 1
      WHERE store_id = ? AND idempotency_key = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(change.storeId.isEmpty
            ? context.appIdentity.storeId
            : change.storeId),
        Variable<String>(idempotencyKey),
      ],
    );
  }

  Future<void> _markStockOperationFailed(
    VentioDriftDatabase db, {
    required BusinessSessionContext context,
    required SyncChange change,
    required StockMovement movement,
    required String idempotencyKey,
    required String reason,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.customUpdate(
      '''
      UPDATE stock_operations
      SET status = 'failed',
          updated_at = ?,
          failure_reason = ?,
          attempt_count = attempt_count + 1
      WHERE store_id = ? AND idempotency_key = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(reason),
        Variable<String>(change.storeId.isEmpty
            ? context.appIdentity.storeId
            : change.storeId),
        Variable<String>(idempotencyKey),
      ],
    );
  }

  Future<void> _applySystemReset(
    BusinessSessionContext context, {
    required bool keepStoreProfile,
  }) async {
    final db = _db();
    if (db == null) return;
    final nextEpoch =
        context.appIdentity.storeEpoch + 1;
    final nextIdentity = context.appIdentity.copyWith(
      storeEpoch: nextEpoch,
      updatedAt: DateTime.now(),
    );
    await BusinessSqliteStore.deleteKey(db, BusinessSqliteStore.productsKey);
    await BusinessSqliteStore.deleteKey(db, BusinessSqliteStore.customersKey);
    await BusinessSqliteStore.deleteKey(db, BusinessSqliteStore.salesKey);
    await BusinessSqliteStore.deleteKey(
        db, BusinessSqliteStore.saleQuotationsKey);
    await BusinessSqliteStore.deleteKey(db, BusinessSqliteStore.deliveryNotesKey);
    await BusinessSqliteStore.deleteKey(
        db, BusinessSqliteStore.billsOfMaterialsKey);
    await BusinessSqliteStore.deleteKey(
        db, BusinessSqliteStore.manufacturingOrdersKey);
    await BusinessSqliteStore.deleteKey(db, BusinessSqliteStore.suppliersKey);
    await BusinessSqliteStore.deleteKey(
        db, BusinessSqliteStore.supplierProductPricesKey);
    await BusinessSqliteStore.deleteKey(db, BusinessSqliteStore.expensesKey);
    await BusinessSqliteStore.deleteKey(db, BusinessSqliteStore.purchasesKey);
    await BusinessSqliteStore.deleteKey(db, BusinessSqliteStore.stockMovementsKey);
    await BusinessSqliteStore.deleteKey(
        db, BusinessSqliteStore.accountTransactionsKey);
    await BusinessSqliteStore.saveKeyJson(
      db,
      _appIdentityKey,
      _encodePayloadJson(nextIdentity.toJson()),
    );
    if (!keepStoreProfile) {
      await BusinessSqliteStore.saveKeyJson(
        db,
        _storeProfileKey,
        _encodePayloadJson(StoreProfile.defaults.toJson()),
      );
    }
    await BusinessSqliteStore.saveKeyJson(db, _invoiceCounterKey, '0');
    await BusinessSqliteStore.saveKeyJson(db, _purchaseCounterKey, '0');
    await db.customStatement('DELETE FROM sync_queue');
    await db.customStatement('DELETE FROM pending_sync_changes');
    await db.customStatement('DELETE FROM sync_events');
    await SyncSqliteStore.saveSyncSequence(db, '0');
  }

  Future<int> _currentCounterValue(
    VentioDriftDatabase db,
    String key,
  ) async {
    final rows = await db.customSelect(
      'SELECT value FROM settings WHERE key = ?',
      variables: <Variable<Object>>[Variable<String>(key)],
    ).get();
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first.read<String>('value')) ?? 0;
  }
}
