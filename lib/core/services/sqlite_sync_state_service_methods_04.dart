part of 'sqlite_sync_state_service.dart';

extension SqliteSyncStateServiceSplitPart4 on SqliteSyncStateService {

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
    final nextEpoch = context.appIdentity.storeEpoch + 1;
    final nextIdentity = context.appIdentity.copyWith(
      storeEpoch: nextEpoch,
      updatedAt: DateTime.now(),
    );
    await BusinessSqliteStore.deleteKey(db, BusinessSqliteStore.productsKey);
    await BusinessSqliteStore.deleteKey(db, BusinessSqliteStore.customersKey);
    await BusinessSqliteStore.deleteKey(db, BusinessSqliteStore.salesKey);
    await BusinessSqliteStore.deleteKey(
        db, BusinessSqliteStore.saleQuotationsKey);
    await BusinessSqliteStore.deleteKey(
        db, BusinessSqliteStore.deliveryNotesKey);
    await BusinessSqliteStore.deleteKey(
        db, BusinessSqliteStore.billsOfMaterialsKey);
    await BusinessSqliteStore.deleteKey(
        db, BusinessSqliteStore.manufacturingOrdersKey);
    await BusinessSqliteStore.deleteKey(db, BusinessSqliteStore.suppliersKey);
    await BusinessSqliteStore.deleteKey(
        db, BusinessSqliteStore.supplierProductPricesKey);
    await BusinessSqliteStore.deleteKey(db, BusinessSqliteStore.expensesKey);
    await BusinessSqliteStore.deleteKey(db, BusinessSqliteStore.purchasesKey);
    await BusinessSqliteStore.deleteKey(
        db, BusinessSqliteStore.stockMovementsKey);
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
