part of 'batch_inventory_service.dart';

extension BatchInventoryServiceSplitPart4 on BatchInventoryService {

  Future<void> applySyncedBatchMovementInTransaction({
    required String productId,
    required String productName,
    required String warehouseId,
    required String batchId,
    required double quantity,
    required double unitCost,
    required DateTime movementDate,
    required String storeId,
    required String branchId,
    required String deviceId,
  }) async {
    if (batchId.trim().isEmpty || quantity.abs() <= 0.000001) return;
    final normalizedBatchId = batchId.trim();
    final nowText = movementDate.toUtc().toIso8601String();
    if (BatchInventoryService.isDeficitBatchId(normalizedBatchId)) {
      if (quantity < 0) {
        final productRow = await db.customSelect(
          'SELECT expiry_tracking_enabled FROM products WHERE id = ? LIMIT 1',
          variables: <Variable<Object>>[Variable<String>(productId)],
        ).getSingleOrNull();
        final expiryTracked =
            (productRow?.data['expiry_tracking_enabled'] as num? ?? 0).toInt() == 1;
        await _ensureDeficitBatchAndRecordInTransaction(
          productId: productId,
          productName: productName,
          warehouseId: warehouseId,
          deficitBatchId: normalizedBatchId,
          quantity: quantity.abs(),
          provisionalUnitCost: unitCost,
          createdAt: movementDate,
          storeId: storeId,
          branchId: branchId,
          deviceId: deviceId,
          expiryTracked: expiryTracked,
          syncStatus: 'synced',
        );
        return;
      }
      final localDeficit = await db.customSelect(
        '''
        SELECT id FROM inventory_stock_deficits
        WHERE deficit_batch_id = ? AND store_id = ? AND warehouse_id = ?
          AND product_id = ?
        LIMIT 1
        ''',
        variables: <Variable<Object>>[
          Variable<String>(normalizedBatchId),
          Variable<String>(storeId),
          Variable<String>(warehouseId),
          Variable<String>(productId),
        ],
      ).getSingleOrNull();
      if (localDeficit != null) {
        await _restoreDeficitAllocationInTransaction(
          deficitBatchId: normalizedBatchId,
          quantity: quantity,
          restoredAt: movementDate,
          storeId: storeId,
          warehouseId: warehouseId,
          productId: productId,
          productName: productName,
          branchId: branchId,
          deviceId: deviceId,
          postAccountingAdjustments: false,
        );
        return;
      }
      throw LocalizedDomainException(
        'error_batch_restore_invalid',
        values: <String, Object?>{'batch': normalizedBatchId},
        fallback:
            'A synchronized negative-stock reversal arrived before its source deficit. Retry synchronization after the source movement is available.',
      );
    }

    final batchExists = await db.customSelect(
      'SELECT id FROM inventory_batches WHERE id = ? LIMIT 1',
      variables: <Variable<Object>>[Variable<String>(normalizedBatchId)],
    ).getSingleOrNull();
    if (batchExists == null) {
      await db.customStatement(
        '''
        INSERT INTO inventory_batches
          (id, product_id, product_name, supplier_batch_number,
           manufacturing_date, expiration_date, status, source_type,
           source_id, source_line_id, unit_cost, initial_quantity,
           cost_currency, exchange_rate, received_at, store_id, branch_id,
           created_at, updated_at, device_id, last_modified_by_device_id,
           sync_status, version)
        VALUES (?, ?, ?, '', '', '', 'active', 'sync_movement', ?, '', ?, ?,
                'USD', 1, ?, ?, ?, ?, ?, ?, ?, 'synced', 1)
        ''',
        <Object?>[
          normalizedBatchId,
          productId,
          productName,
          normalizedBatchId,
          unitCost < 0 ? 0.0 : unitCost,
          quantity > 0 ? quantity : 0.0,
          nowText,
          storeId,
          branchId.trim().isEmpty ? 'main' : branchId.trim(),
          nowText,
          nowText,
          deviceId,
          deviceId,
        ],
      );
    }

    var balanceDelta = quantity;
    if (quantity > 0 && !BatchInventoryService.isDeficitBatchId(normalizedBatchId)) {
      final settled = await _settleOpenDeficitsWithIncomingBatchInTransaction(
        productId: productId,
        productName: productName,
        warehouseId: warehouseId,
        incomingBatchId: normalizedBatchId,
        incomingQuantity: quantity,
        actualUnitCost: unitCost,
        settledAt: movementDate,
        storeId: storeId,
        branchId: branchId,
        deviceId: deviceId,
        postAccountingAdjustments: false,
      );
      balanceDelta = quantity - settled;
    }
    final balanceId = '$storeId::$warehouseId::$productId::$normalizedBatchId';
    if (quantity > 0) {
      final persistedBalanceDelta =
          balanceDelta <= 0.000001 ? 0.0 : balanceDelta;
      await db.customStatement(
        '''
        INSERT INTO inventory_batch_balances
          (id, batch_id, product_id, warehouse_id, store_id, branch_id,
           quantity, reserved_quantity, version, created_at, updated_at,
           device_id, last_modified_by_device_id, sync_status)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1, ?, ?, ?, ?, 'synced')
        ON CONFLICT(store_id, warehouse_id, product_id, batch_id) DO UPDATE SET
          quantity = inventory_batch_balances.quantity + excluded.quantity,
          version = inventory_batch_balances.version + 1,
          updated_at = excluded.updated_at,
          device_id = excluded.device_id,
          last_modified_by_device_id = excluded.last_modified_by_device_id,
          sync_status = 'synced'
        ''',
        <Object?>[
          balanceId,
          normalizedBatchId,
          productId,
          warehouseId,
          storeId,
          branchId.trim().isEmpty ? 'main' : branchId.trim(),
          persistedBalanceDelta,
          nowText,
          nowText,
          deviceId,
          deviceId,
        ],
      );
      await _refreshBatchLifecycleStatusInTransaction(
        batchId: normalizedBatchId,
        storeId: storeId,
        updatedAt: movementDate,
        deviceId: deviceId,
        syncStatus: 'synced',
      );
      return;
    }
    if (balanceDelta.abs() <= 0.000001) return;
    final updated = await db.customUpdate(
      '''
      UPDATE inventory_batch_balances
      SET quantity = quantity + ?, version = version + 1,
          updated_at = ?, device_id = ?, last_modified_by_device_id = ?,
          sync_status = 'synced'
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
        AND batch_id = ? AND quantity + ? >= -0.000001
      ''',
      variables: <Variable<Object>>[
        Variable<double>(balanceDelta),
        Variable<String>(nowText),
        Variable<String>(deviceId),
        Variable<String>(deviceId),
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(productId),
        Variable<String>(normalizedBatchId),
        Variable<double>(balanceDelta),
      ],
      updates: const <TableInfo<Table, Object?>>{},
    );
    if (updated != 1) {
      throw const LocalizedDomainException(
        'error_batch_missing_or_insufficient',
        fallback: 'The batch does not exist or has insufficient stock.',
      );
    }
    await _refreshBatchLifecycleStatusInTransaction(
      batchId: normalizedBatchId,
      storeId: storeId,
      updatedAt: movementDate,
      deviceId: deviceId,
      syncStatus: 'synced',
    );
  }

  /// Unified allocation for all stock-tracked products.
  ///
  /// Expiry products use FEFO. Non-expiry products use oldest received batch
  /// first. This phase-1 API never creates anonymous negative-stock slices.
  Future<List<BatchAllocation>> allocateUnifiedInTransaction({
    required Product product,
    required String warehouseId,
    required double quantity,
    required DateTime movementDate,
    required String storeId,
    required String deviceId,
    String branchId = 'main',
    bool allowNegativeStock = false,
  }) async {
    if (!product.trackStock || quantity <= 0) {
      return const <BatchAllocation>[];
    }
    final startOfMovementDay = _calendarDateText(movementDate);
    final expiryPredicate = product.expiryTrackingEnabled
        ? "trim(b.expiration_date) <> '' AND substr(b.expiration_date, 1, 10) >= ?"
        : "trim(b.expiration_date) = ''";
    final ordering = product.expiryTrackingEnabled
        ? '''substr(b.expiration_date, 1, 10) ASC,
             CASE WHEN trim(b.received_at) = '' THEN b.created_at ELSE b.received_at END ASC,
             b.id ASC'''
        : '''CASE WHEN trim(b.received_at) = '' THEN b.created_at ELSE b.received_at END ASC,
             b.id ASC''';
    final variables = <Variable<Object>>[
      Variable<String>(storeId),
      Variable<String>(warehouseId),
      Variable<String>(product.id),
      if (product.expiryTrackingEnabled)
        Variable<String>(startOfMovementDay),
    ];
    final rows = await db.customSelect(
      '''
      SELECT b.id AS batch_id, b.supplier_batch_number,
             b.manufacturing_date, b.expiration_date, b.unit_cost,
             bb.quantity, bb.reserved_quantity
      FROM inventory_batch_balances bb
      JOIN inventory_batches b ON b.id = bb.batch_id
        AND b.product_id = bb.product_id AND b.store_id = bb.store_id
      WHERE bb.store_id = ? AND bb.warehouse_id = ? AND bb.product_id = ?
        AND b.status = 'active'
        AND b.source_type <> 'inventory_deficit'
        AND b.id NOT LIKE 'deficit:%'
        AND (bb.quantity - bb.reserved_quantity) > 0.000001
        AND $expiryPredicate
      ORDER BY $ordering
      ''',
      variables: variables,
    ).get();

    var remaining = quantity;
    final allocations = <BatchAllocation>[];
    for (final row in rows) {
      if (remaining <= 0.000001) break;
      final available =
          row.read<double>('quantity') - row.read<double>('reserved_quantity');
      final used = available < remaining ? available : remaining;
      if (used <= 0) continue;
      final batchId = row.read<String>('batch_id');
      final updated = await db.customUpdate(
        '''
        UPDATE inventory_batch_balances
        SET quantity = quantity - ?, version = version + 1,
            updated_at = ?, device_id = ?, last_modified_by_device_id = ?,
            sync_status = 'pending'
        WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
          AND batch_id = ? AND (quantity - reserved_quantity) >= ?
        ''',
        variables: <Variable<Object>>[
          Variable<double>(used),
          Variable<String>(movementDate.toUtc().toIso8601String()),
          Variable<String>(deviceId),
          Variable<String>(deviceId),
          Variable<String>(storeId),
          Variable<String>(warehouseId),
          Variable<String>(product.id),
          Variable<String>(batchId),
          Variable<double>(used),
        ],
        updates: const <TableInfo<Table, Object?>>{},
      );
      if (updated != 1) {
        throw const LocalizedDomainException(
          'error_batch_concurrent_change',
          fallback: 'Batch stock changed while allocating inventory.',
        );
      }
      await _refreshBatchLifecycleStatusInTransaction(
        batchId: batchId,
        storeId: storeId,
        updatedAt: movementDate,
        deviceId: deviceId,
      );
      allocations.add(BatchAllocation(
        batchId: batchId,
        quantity: used,
        supplierBatchNumber: row.read<String>('supplier_batch_number'),
        manufacturingDate:
            DateTime.tryParse(row.read<String>('manufacturing_date')),
        expirationDate:
            DateTime.tryParse(row.read<String>('expiration_date')),
        unitCost: row.read<double>('unit_cost'),
      ));
      remaining -= used;
    }
    if (remaining > 0.000001) {
      if (!allowNegativeStock) {
        throw LocalizedDomainException(
          'error_insufficient_batch_stock',
          values: {'product': product.name},
          fallback: 'Insufficient batch stock for ${product.name}.',
        );
      }
      final provisionalUnitCost =
          await _provisionalDeficitUnitCostInTransaction(
        product: product,
        warehouseId: warehouseId,
        storeId: storeId,
      );
      final counterRow = await db.customSelect(
        '''
        SELECT COUNT(*) AS c
        FROM inventory_stock_deficits
        WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
        ''',
        variables: <Variable<Object>>[
          Variable<String>(storeId),
          Variable<String>(warehouseId),
          Variable<String>(product.id),
        ],
      ).getSingle();
      final deficitSequence =
          ((counterRow.data['c'] as num?)?.toInt() ?? 0) + 1;
      final deficitBatchId =
          'deficit:$storeId:$warehouseId:${product.id}:${movementDate.microsecondsSinceEpoch}:$deficitSequence';
      await _ensureDeficitBatchAndRecordInTransaction(
        productId: product.id,
        productName: product.name,
        warehouseId: warehouseId,
        deficitBatchId: deficitBatchId,
        quantity: remaining,
        provisionalUnitCost: provisionalUnitCost,
        createdAt: movementDate,
        storeId: storeId,
        branchId: branchId,
        deviceId: deviceId,
        expiryTracked: product.expiryTrackingEnabled,
        syncStatus: 'pending',
      );
      allocations.add(BatchAllocation(
        batchId: deficitBatchId,
        quantity: remaining,
        supplierBatchNumber: 'NEGATIVE-STOCK-DEFICIT',
        expirationDate: product.expiryTrackingEnabled
            ? DateTime.utc(9999, 12, 31)
            : null,
        unitCost: provisionalUnitCost,
      ));
    }
    return allocations;
  }

  Future<void> restoreUnifiedInTransaction({
    required Product product,
    required String warehouseId,
    required List<BatchAllocation> allocations,
    required DateTime restoredAt,
    required String storeId,
    required String deviceId,
    String branchId = 'main',
  }) async {
    if (!product.trackStock || allocations.isEmpty) return;
    for (final allocation in allocations) {
      final batchId = allocation.batchId.trim();
      if (batchId.isEmpty || allocation.quantity <= 0) {
        throw const LocalizedDomainException(
          'error_batch_restore_invalid',
          fallback: 'A valid batch and positive quantity are required.',
        );
      }
      if (BatchInventoryService.isDeficitBatchId(batchId)) {
        await _restoreDeficitAllocationInTransaction(
          deficitBatchId: batchId,
          quantity: allocation.quantity,
          restoredAt: restoredAt,
          storeId: storeId,
          warehouseId: warehouseId,
          productId: product.id,
          productName: product.name,
          branchId: branchId,
          deviceId: deviceId,
          postAccountingAdjustments: true,
        );
        continue;
      }
      final updated = await db.customUpdate(
        '''
        UPDATE inventory_batch_balances
        SET quantity = quantity + ?, version = version + 1, updated_at = ?,
            device_id = ?, last_modified_by_device_id = ?, sync_status = 'pending'
        WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
          AND batch_id = ?
          AND EXISTS (
            SELECT 1 FROM inventory_batches b
            WHERE b.id = inventory_batch_balances.batch_id
              AND b.product_id = ? AND b.store_id = ?
          )
        ''',
        variables: <Variable<Object>>[
          Variable<double>(allocation.quantity),
          Variable<String>(restoredAt.toUtc().toIso8601String()),
          Variable<String>(deviceId),
          Variable<String>(deviceId),
          Variable<String>(storeId),
          Variable<String>(warehouseId),
          Variable<String>(product.id),
          Variable<String>(batchId),
          Variable<String>(product.id),
          Variable<String>(storeId),
        ],
        updates: const <TableInfo<Table, Object?>>{},
      );
      if (updated != 1) {
        throw LocalizedDomainException(
          'error_batch_no_longer_exists',
          values: {'batch': batchId},
          fallback: 'Batch $batchId no longer exists.',
        );
      }
      await _refreshBatchLifecycleStatusInTransaction(
        batchId: batchId,
        storeId: storeId,
        updatedAt: restoredAt,
        deviceId: deviceId,
      );
    }
  }

  Future<void> adjustUnifiedBatchInTransaction({
    required Product product,
    required String warehouseId,
    required String batchId,
    required double quantityDelta,
    required DateTime adjustedAt,
    required String storeId,
    required String deviceId,
  }) async {
    if (!product.trackStock || quantityDelta == 0) return;
    final updated = await db.customUpdate(
      '''
      UPDATE inventory_batch_balances
      SET quantity = quantity + ?, version = version + 1, updated_at = ?,
          device_id = ?, last_modified_by_device_id = ?, sync_status = 'pending'
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ? AND batch_id = ?
        AND quantity + ? >= 0
      ''',
      variables: <Variable<Object>>[
        Variable<double>(quantityDelta),
        Variable<String>(adjustedAt.toUtc().toIso8601String()),
        Variable<String>(deviceId),
        Variable<String>(deviceId),
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
        Variable<String>(batchId.trim()),
        Variable<double>(quantityDelta),
      ],
      updates: const <TableInfo<Table, Object?>>{},
    );
    if (updated != 1) {
      throw const LocalizedDomainException(
        'error_batch_missing_or_insufficient',
        fallback: 'The batch does not exist or has insufficient stock.',
      );
    }
    await _refreshBatchLifecycleStatusInTransaction(
      batchId: batchId.trim(),
      storeId: storeId,
      updatedAt: adjustedAt,
      deviceId: deviceId,
    );
  }

  Future<List<BatchAllocation>> transferUnifiedInTransaction({
    required Product product,
    required String fromWarehouseId,
    required String toWarehouseId,
    required double quantity,
    required DateTime transferredAt,
    required String storeId,
    required String branchId,
    required String deviceId,
    bool allowNegativeStock = false,
  }) async {
    // A warehouse transfer is a physical lineage operation. The store may
    // allow negative stock for sales, but a virtual deficit must never become
    // positive stock in another warehouse with a provisional cost.
    await requirePhysicalUnifiedStockInTransaction(
      product: product,
      warehouseId: fromWarehouseId,
      quantity: quantity,
      movementDate: transferredAt,
      storeId: storeId,
      operation: 'warehouse transfer',
    );
    final allocations = await allocateUnifiedInTransaction(
      product: product,
      warehouseId: fromWarehouseId,
      quantity: quantity,
      movementDate: transferredAt,
      storeId: storeId,
      deviceId: deviceId,
      branchId: branchId,
      allowNegativeStock: false,
    );
    final nowText = transferredAt.toUtc().toIso8601String();
    for (final allocation in allocations) {
      final settledAtDestination =
          await _settleOpenDeficitsWithIncomingBatchInTransaction(
        productId: product.id,
        productName: product.name,
        warehouseId: toWarehouseId,
        incomingBatchId: allocation.batchId,
        incomingQuantity: allocation.quantity,
        actualUnitCost: allocation.unitCost,
        settledAt: transferredAt,
        storeId: storeId,
        branchId: branchId,
        deviceId: deviceId,
        postAccountingAdjustments: true,
      );
      final destinationBalanceQuantity =
          allocation.quantity - settledAtDestination;
      final persistedDestinationBalance = destinationBalanceQuantity <= 0.000001
          ? 0.0
          : destinationBalanceQuantity;
      final id = '$storeId::$toWarehouseId::${product.id}::${allocation.batchId}';
      await db.customStatement(
        '''
        INSERT INTO inventory_batch_balances
          (id, batch_id, product_id, warehouse_id, store_id, branch_id,
           quantity, reserved_quantity, version, created_at, updated_at,
           device_id, last_modified_by_device_id, sync_status)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1, ?, ?, ?, ?, 'pending')
        ON CONFLICT(store_id, warehouse_id, product_id, batch_id) DO UPDATE SET
          quantity = inventory_batch_balances.quantity + excluded.quantity,
          version = inventory_batch_balances.version + 1,
          updated_at = excluded.updated_at,
          device_id = excluded.device_id,
          last_modified_by_device_id = excluded.last_modified_by_device_id,
          sync_status = 'pending'
        ''',
        <Object?>[
          id,
          allocation.batchId,
          product.id,
          toWarehouseId,
          storeId,
          branchId,
          persistedDestinationBalance,
          nowText,
          nowText,
          deviceId,
          deviceId,
        ],
      );
      await _refreshBatchLifecycleStatusInTransaction(
        batchId: allocation.batchId,
        storeId: storeId,
        updatedAt: transferredAt,
        deviceId: deviceId,
      );
    }
    return allocations;
  }

  /// Compares the aggregate warehouse quantity with the sum of batch balances.
  /// Phase 1 exposes the invariant without enforcing it on legacy write paths;
  /// phase 2+ callers can assert it after each unified transaction.
  Future<BatchInventoryBalanceCheck> checkWarehouseBatchBalanceInTransaction({
    required String productId,
    required String warehouseId,
    required String storeId,
    double tolerance = 0.000001,
  }) async {
    final aggregateRow = await db.customSelect(
      '''
      SELECT COALESCE(quantity, 0) AS quantity
      FROM warehouse_inventory
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(productId),
      ],
    ).getSingleOrNull();
    final batchRow = await db.customSelect(
      '''
      SELECT COALESCE(SUM(bb.quantity), 0) AS quantity,
             COALESCE(SUM(bb.quantity * b.unit_cost), 0) AS carrying_value
      FROM inventory_batch_balances bb
      JOIN inventory_batches b ON b.id = bb.batch_id
        AND b.product_id = bb.product_id AND b.store_id = bb.store_id
      WHERE bb.store_id = ? AND bb.warehouse_id = ? AND bb.product_id = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(productId),
      ],
    ).getSingle();
    final deficitRow = await db.customSelect(
      '''
      SELECT COALESCE(SUM(quantity_open), 0) AS quantity,
             COALESCE(SUM(quantity_open * provisional_unit_cost), 0) AS carrying_value
      FROM inventory_stock_deficits
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
        AND status = 'open' AND quantity_open > 0.000001
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(productId),
      ],
    ).getSingle();
    final physicalQuantity =
        (batchRow.data['quantity'] as num? ?? 0).toDouble();
    final physicalValue =
        (batchRow.data['carrying_value'] as num? ?? 0).toDouble();
    final deficitQuantity =
        (deficitRow.data['quantity'] as num? ?? 0).toDouble();
    final deficitValue =
        (deficitRow.data['carrying_value'] as num? ?? 0).toDouble();
    return BatchInventoryBalanceCheck(
      productId: productId,
      warehouseId: warehouseId,
      warehouseQuantity:
          (aggregateRow?.data['quantity'] as num? ?? 0).toDouble(),
      batchQuantity: physicalQuantity - deficitQuantity,
      batchCarryingValue: physicalValue - deficitValue,
      tolerance: tolerance,
    );
  }

  Future<void> assertWarehouseBatchBalanceInTransaction({
    required String productId,
    required String warehouseId,
    required String storeId,
    double tolerance = 0.000001,
  }) async {
    final virtualBalance = await db.customSelect(
      '''
      SELECT bb.batch_id
      FROM inventory_batch_balances bb
      INNER JOIN inventory_batches b ON b.id = bb.batch_id
        AND b.product_id = bb.product_id AND b.store_id = bb.store_id
      WHERE bb.store_id = ? AND bb.warehouse_id = ? AND bb.product_id = ?
        AND bb.quantity > ?
        AND (b.source_type = 'inventory_deficit' OR b.id LIKE 'deficit:%')
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(productId),
        Variable<double>(tolerance),
      ],
    ).getSingleOrNull();
    if (virtualBalance != null) {
      throw LocalizedDomainException(
        'error_batch_warehouse_balance_mismatch',
        values: <String, Object?>{
          'warehouseQuantity': 'virtual_deficit_balance',
          'batchQuantity': virtualBalance.data['batch_id']?.toString() ?? '',
        },
        fallback:
            'Virtual negative-stock deficit batches cannot hold physical warehouse balances for $productId.',
      );
    }
    final check = await checkWarehouseBatchBalanceInTransaction(
      productId: productId,
      warehouseId: warehouseId,
      storeId: storeId,
      tolerance: tolerance,
    );
    if (!check.isConsistent) {
      throw LocalizedDomainException(
        'error_batch_warehouse_balance_mismatch',
        values: <String, Object?>{
          'warehouseQuantity': check.warehouseQuantity,
          'batchQuantity': check.batchQuantity,
        },
        fallback:
            'Warehouse inventory and batch balances do not match for $productId.',
      );
    }
  }
}
