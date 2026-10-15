part of 'app_store.dart';

extension _AppStoreSplitInventoryPart5 on AppStore {
  Future<void> adjustStock({
    required String productId,
    required String warehouseId,
    required double quantityDelta,
    required String reason,
    String adjustmentCategory = 'other',
    String notes = '',
    String evidenceRef = '',
    List<BatchAllocation> batchAllocations = const <BatchAllocation>[],
    String operationReferenceId = '',
  }) async {
    requirePermission(AppPermission.inventoryCorrectionsManage);
    if (quantityDelta == 0) return;
    final index = _productIndexById[productId];
    if (index == null) throw ArgumentError('Product not found.');
    final now = DateTime.now();
    final product = _products[index];
    if (!product.trackStock) {
      throw StateError('This product does not track stock.');
    }
    final resolvedWarehouse =
        resolveWarehouseForPurchase(warehouseId: warehouseId);
    if (LocalDatabaseService.isSqliteAuthoritative &&
        SqliteMigrationManager.database != null) {
      final sqliteDb = SqliteMigrationManager.database!;
      final stockService = StockTransactionService(
        sqliteDb,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
      );
      final operationId = operationReferenceId.trim().isEmpty
          ? '${now.microsecondsSinceEpoch}-$productId-adjustment'
          : operationReferenceId.trim();
      final existingAdjustment = await sqliteDb.customSelect(
        '''
        SELECT id
        FROM stock_movements
        WHERE movement_group_id = ?
          AND deleted_at = ''
        LIMIT 1
        ''',
        variables: <Variable<Object>>[Variable<String>(operationId)],
      ).getSingleOrNull();
      if (existingAdjustment != null) {
        await _refreshProductStockCompatibilityCache(<String>[productId]);
        return;
      }
      final baseMovement = StockMovement(
        id: operationId,
        productId: productId,
        productName: product.name,
        type: quantityDelta < 0 ? 'inventory_loss' : 'inventory_adjustment',
        quantity: quantityDelta,
        date: now,
        referenceId: productId,
        referenceNo: product.code,
        reason: reason.trim().isEmpty ? 'Manual adjustment' : reason.trim(),
        adjustmentCategory: adjustmentCategory.trim().isEmpty
            ? 'other'
            : adjustmentCategory.trim(),
        notes: notes.trim(),
        evidenceRef: evidenceRef.trim(),
        warehouseId: resolvedWarehouse.id,
        warehouseName: resolvedWarehouse.name,
        movementGroupId: operationId,
        documentLineId: '$operationId-line',
        // Replaced with the resolved historic cost before posting.
        unitCost: 0,
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      );
      var movements = <StockMovement>[baseMovement];
      var resolvedBatchAllocations = const <BatchAllocation>[];
      var adjustmentUnitCost = _safeUsdCost(product);
      var adjustmentValue = 0.0;
      final batchService = BatchInventoryService(sqliteDb);
      Product? persistedAdjustedProduct;
      await _traceAsync<void>('inventory.adjustStock', 'sqlite_transaction',
          () async {
        await sqliteDb.transaction(() async {
          await _ensureUnifiedBatchCutoverForProductInTransaction(
            sqliteDb,
            product: product,
            warehouseId: resolvedWarehouse.id,
            at: now,
          );
          if (quantityDelta < 0) {
            final allocations = await batchService.allocateUnifiedInTransaction(
              product: product,
              warehouseId: resolvedWarehouse.id,
              quantity: quantityDelta.abs(),
              movementDate: now,
              storeId: appIdentity.storeId,
              deviceId: _deviceId,
              branchId: appIdentity.branchId,
              allowNegativeStock: _storeProfile.allowNegativeStock,
            );
            resolvedBatchAllocations = allocations;
            adjustmentValue = allocations.fold<double>(
              0,
              (sum, allocation) =>
                  sum + (allocation.quantity * allocation.unitCost),
            );
            adjustmentUnitCost = quantityDelta.abs() <= 0
                ? 0
                : adjustmentValue / quantityDelta.abs();
            movements = <StockMovement>[
              for (var batchIndex = 0;
                  batchIndex < allocations.length;
                  batchIndex += 1)
                baseMovement.copyWith(
                  id: '$operationId-batch-$batchIndex',
                  quantity: -allocations[batchIndex].quantity,
                  batchId: allocations[batchIndex].batchId,
                  unitCost: allocations[batchIndex].unitCost,
                  documentLineId: '$operationId-line-batch-$batchIndex',
                  idempotencyKey: '$operationId:batch:$batchIndex',
                ),
            ];
          } else {
            adjustmentUnitCost =
                await _unifiedOpeningCostForProductInTransaction(
              sqliteDb,
              product: product,
              warehouseId: resolvedWarehouse.id,
            );
            final requested = product.expiryTrackingEnabled
                ? batchAllocations
                : <BatchAllocation>[
                    BatchAllocation(
                      batchId: '$operationId-batch-0',
                      quantity: quantityDelta,
                      unitCost: adjustmentUnitCost,
                    ),
                  ];
            if (product.expiryTrackingEnabled && requested.isEmpty) {
              throw LocalizedDomainException(
                'error_expiry_batches_required',
                values: {'product': product.name},
                fallback: 'Expiry batches are required for ${product.name}.',
              );
            }
            final requestedTotal = requested.fold<double>(
              0,
              (sum, allocation) => sum + allocation.quantity,
            );
            if ((requestedTotal - quantityDelta).abs() > 0.000001) {
              throw LocalizedDomainException(
                'error_batch_quantity_total',
                values: {'product': product.name, 'quantity': quantityDelta},
                fallback:
                    'Batch quantities for ${product.name} must equal $quantityDelta.',
              );
            }
            final allocations = <BatchAllocation>[];
            for (var batchIndex = 0;
                batchIndex < requested.length;
                batchIndex += 1) {
              final input = requested[batchIndex];
              final allocation =
                  await batchService.addUnifiedBatchStockInTransaction(
                product: product,
                warehouseId: resolvedWarehouse.id,
                batchId: input.batchId.trim().isEmpty
                    ? '$operationId-batch-$batchIndex'
                    : input.batchId.trim(),
                quantity: input.quantity,
                unitCost: adjustmentUnitCost,
                sourceType: 'manual_adjustment',
                sourceId: operationId,
                sourceLineId: '$operationId:adjustment:$batchIndex',
                receivedAt: now,
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                deviceId: _deviceId,
                supplierBatchNumber: input.supplierBatchNumber,
                manufacturingDate: input.manufacturingDate,
                expirationDate: input.expirationDate,
              );
              allocations.add(allocation);
            }
            resolvedBatchAllocations = allocations;
            adjustmentValue = quantityDelta * adjustmentUnitCost;
            movements = <StockMovement>[
              for (var batchIndex = 0;
                  batchIndex < allocations.length;
                  batchIndex += 1)
                baseMovement.copyWith(
                  id: '$operationId-batch-$batchIndex',
                  quantity: allocations[batchIndex].quantity,
                  batchId: allocations[batchIndex].batchId,
                  unitCost: allocations[batchIndex].unitCost,
                  documentLineId: '$operationId-line-batch-$batchIndex',
                  idempotencyKey: '$operationId:batch:$batchIndex',
                ),
            ];
          }
          await stockService.recordMovementsInTransaction(
            operationType: 'manual_adjustment',
            documentType: 'inventory_adjustment',
            documentId: operationId,
            movementGroupId: operationId,
            idempotencyKey: '$operationId-op',
            movements: movements,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            deviceId: _deviceId,
          );
          await _assertUnifiedBatchMovementBalancesInTransaction(
            batchService,
            movements,
          );
          await AccountingService.recordManualInventoryAdjustmentInTransaction(
            database: sqliteDb,
            entryDate: now,
            referenceId: operationId,
            referenceNo: product.code,
            productId: product.id,
            productName: product.name,
            quantityDelta: quantityDelta,
            value: adjustmentValue,
            adjustmentCategory: adjustmentCategory,
            reason: reason,
            createdBy: _activeUser?.fullName ?? _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
          );
          final stockAfterRow = await sqliteDb.customSelect(
            '''
            SELECT COALESCE(SUM(quantity), 0) AS quantity
            FROM warehouse_inventory
            WHERE product_id = ?
            ''',
            variables: <Variable<Object>>[Variable<String>(product.id)],
          ).getSingleOrNull();
          final stockAfter =
              (stockAfterRow?.data['quantity'] as num? ?? 0).toDouble();
          persistedAdjustedProduct = _withSyncMeta<Product>(
            product.copyWith(stock: stockAfter, updatedAt: now),
            now,
          );
          await BusinessSqliteStore.upsertEntityPayloads(
            sqliteDb,
            AppStore._productsKey,
            <Map<String, dynamic>>[persistedAdjustedProduct!.toJson()],
            sortIndices: const <int?>[0],
          );
        });
      });
      _mirrorAuthoritativeStockMovements(movements);
      if (persistedAdjustedProduct != null) {
        _products[index] = persistedAdjustedProduct!;
      }
      _inventoryCostLayers
        ..clear()
        ..addAll(await BusinessSqliteStore.readInventoryCostLayers(sqliteDb));
      _rebuildInventoryCostLayerLookupCache();
      if (quantityDelta > 0 && resolvedBatchAllocations.isNotEmpty) {
        _recordInventoryBatchSyncChanges(
          product: product,
          allocations: resolvedBatchAllocations,
          sourceType: 'manual_adjustment',
          sourceId: operationId,
          now: now,
          unitCost: adjustmentUnitCost,
          sourceLineIds: <String>[
            for (var index = 0;
                index < resolvedBatchAllocations.length;
                index += 1)
              '$operationId:adjustment:$index',
          ],
        );
      }
      await _traceAsync<void>(
        'inventory.adjustStock',
        'refresh_product_stock_cache',
        () => _refreshProductStockCompatibilityCache(<String>[productId]),
      );
      _traceSync('inventory.adjustStock', 'record_sync_change', () {
        for (final movement in movements) {
          _recordSyncChange(
            entityType: 'stock_movement',
            entityId: movement.id,
            operation: 'adjust',
            payload: movement.toJson(),
          );
        }
      });
      notifyListeners();
      return;
    }
    final nextStock = product.stock + quantityDelta;
    if (!_storeProfile.allowNegativeStock && nextStock < -0.000001) {
      throw StateError('Insufficient stock in ${resolvedWarehouse.name}.');
    }
    _products[index] = _withSyncMeta<Product>(
      product.copyWith(stock: product.stock + quantityDelta),
      now,
    );
    _addStockMovement(
      StockMovement(
        id: operationReferenceId.trim().isEmpty
            ? '${now.microsecondsSinceEpoch}-$productId-adjustment'
            : operationReferenceId.trim(),
        productId: productId,
        productName: product.name,
        type: quantityDelta < 0 ? 'inventory_loss' : 'inventory_adjustment',
        quantity: quantityDelta,
        date: now,
        referenceId: productId,
        referenceNo: product.code,
        reason: reason.trim().isEmpty ? 'Manual adjustment' : reason.trim(),
        adjustmentCategory: adjustmentCategory.trim().isEmpty
            ? 'other'
            : adjustmentCategory.trim(),
        notes: notes.trim(),
        evidenceRef: evidenceRef.trim(),
        unitCost: product.usdCost,
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      recordSync: true,
    );
    await _saveDirty(
      products: true,
      productDerivedData: false,
      stockMovements: true,
      sync: true,
    );
    notifyListeners();
  }

  Future<void> recordWasteLoss({
    required String productId,
    required String warehouseId,
    required double quantity,
    required String reason,
    String adjustmentCategory = 'other',
    String notes = '',
  }) async {
    requirePermission(AppPermission.inventoryWasteManage);
    if (!quantity.isFinite || quantity <= 0) {
      throw ArgumentError('يجب أن تكون كمية الهدر أكبر من صفر.');
    }
    final product = _findProductById(productId);
    if (product == null) throw ArgumentError('Product not found.');
    if (!product.trackStock) {
      throw StateError('This product does not track stock.');
    }
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw StateError(
          'Inventory waste requires the authoritative SQLite store.');
    }
    final now = DateTime.now();
    final operationId = '${now.microsecondsSinceEpoch}-$productId-waste';
    final warehouse = resolveWarehouseForSale(warehouseId: warehouseId);
    var movement = StockMovement(
      id: '$operationId-movement',
      productId: product.id,
      productName: product.name,
      type: 'waste',
      quantity: -quantity,
      date: now,
      referenceId: operationId,
      referenceNo: product.code,
      reason: reason.trim(),
      adjustmentCategory: adjustmentCategory,
      notes: notes.trim(),
      warehouseId: warehouse.id,
      warehouseName: warehouse.name,
      movementGroupId: operationId,
      documentLineId: '$operationId-line',
      idempotencyKey: '$operationId:waste',
      unitCost: _safeUsdCost(product),
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      lastModifiedByDeviceId: _deviceId,
    );
    final stockService = StockTransactionService(
      db,
      deviceId: _deviceId,
      defaultStoreId: appIdentity.storeId,
      defaultBranchId: appIdentity.branchId,
      defaultSyncTarget: _stockTransactionSyncTarget,
      allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
    );
    final roleKey = switch (adjustmentCategory.trim().toLowerCase()) {
      'expired' || 'expiry' => 'inventory_expiry',
      'weight' || 'weight_variance' => 'inventory_weight_variance',
      _ => 'inventory_damage',
    };
    var movements = <StockMovement>[movement];
    final batchService = BatchInventoryService(db);
    var wasteValue = 0.0;
    await db.transaction(() async {
      await _ensureUnifiedBatchCutoverForProductInTransaction(
        db,
        product: product,
        warehouseId: warehouse.id,
        at: now,
      );
      final allocations = await batchService.allocateUnifiedInTransaction(
        product: product,
        warehouseId: warehouse.id,
        quantity: quantity,
        movementDate: now,
        storeId: appIdentity.storeId,
        deviceId: _deviceId,
        branchId: appIdentity.branchId,
        allowNegativeStock: _storeProfile.allowNegativeStock,
      );
      wasteValue = allocations.fold<double>(
        0,
        (sum, allocation) => sum + (allocation.quantity * allocation.unitCost),
      );
      movements = <StockMovement>[
        for (var index = 0; index < allocations.length; index += 1)
          movement.copyWith(
            id: '$operationId-batch-$index',
            quantity: -allocations[index].quantity,
            batchId: allocations[index].batchId,
            unitCost: allocations[index].unitCost,
            documentLineId: '$operationId-line-batch-$index',
            idempotencyKey: '$operationId:waste:batch:$index',
          ),
      ];
      final wasteJournalId = await AccountingService.recordInventoryWaste(
        entryDate: now,
        referenceId: operationId,
        referenceNo: product.code,
        amount: wasteValue,
        productName: product.name,
        productId: product.id,
        createdBy: _activeUser?.fullName ?? _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        notes: notes,
        expenseRoleKey: roleKey,
        database: db,
        withinExistingTransaction: true,
      );
      if (wasteJournalId.trim().isEmpty) {
        throw StateError('Waste loss requires a posted accounting journal.');
      }
      await _requirePostedJournalInTransaction(
        db,
        referenceType: 'inventory_waste',
        referenceId: operationId,
        failureMessage:
            'Waste journal was not persisted; the waste operation was rolled back.',
      );
      await stockService.recordMovementsInTransaction(
        operationType: 'inventory_waste',
        documentType: 'inventory_waste',
        documentId: operationId,
        movementGroupId: operationId,
        idempotencyKey: '$operationId:waste',
        movements: movements,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        deviceId: _deviceId,
      );
      await _assertUnifiedBatchMovementBalancesInTransaction(
        batchService,
        movements,
      );
    });
    _mirrorAuthoritativeStockMovements(movements);
    await _refreshProductStockCompatibilityCache(<String>{product.id});
    _inventoryCostLayers
      ..clear()
      ..addAll(await BusinessSqliteStore.readInventoryCostLayers(db));
    _rebuildInventoryCostLayerLookupCache();
    for (final postedMovement in movements) {
      _recordSyncChange(
        entityType: 'stock_movement',
        entityId: postedMovement.id,
        operation: 'inventory_waste',
        payload: postedMovement.toJson(),
      );
    }
    notifyListeners();
  }

  Future<void> reverseWasteLossGroup(String movementId) async {
    requirePermission(AppPermission.inventoryWasteManage);
    final selected = _stockMovements.firstWhere(
      (item) => item.id == movementId,
      orElse: () => throw ArgumentError('Waste movement not found.'),
    );
    final groupId = selected.movementGroupId.isEmpty
        ? selected.id
        : selected.movementGroupId;
    final originals = _stockMovements
        .where((item) =>
            (item.movementGroupId.isEmpty ? item.id : item.movementGroupId) ==
                groupId &&
            <String>{'waste', 'inventory_loss'}.contains(item.type))
        .toList();
    if (originals.isEmpty ||
        originals.any((item) => item.reversalOfMovementId.isNotEmpty) ||
        _stockMovements.any((item) => originals
            .any((original) => item.reversalOfMovementId == original.id))) {
      throw StateError('This waste operation has already been reversed.');
    }
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw StateError(
          'Waste reversal requires the authoritative SQLite store.');
    }
    final now = DateTime.now();
    final stockService = StockTransactionService(
      db,
      deviceId: _deviceId,
      defaultStoreId: appIdentity.storeId,
      defaultBranchId: appIdentity.branchId,
      defaultSyncTarget: _stockTransactionSyncTarget,
      allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
    );
    final reversals = <StockMovement>[];
    await db.transaction(() async {
      for (final original in originals) {
        final product = _findProductById(original.productId);
        if (product == null) {
          throw StateError('Waste product no longer exists.');
        }
        if (original.batchId.isNotEmpty) {
          await BatchInventoryService(db).restoreUnifiedInTransaction(
            product: product,
            warehouseId: original.warehouseId,
            allocations: <BatchAllocation>[
              BatchAllocation(
                batchId: original.batchId,
                quantity: original.quantity.abs(),
                unitCost: original.unitCost,
              ),
            ],
            restoredAt: now,
            storeId: appIdentity.storeId,
            deviceId: _deviceId,
          );
        } else {
          // Legacy pre-Unified waste rows keep their historical cost-layer
          // reversal behavior for backward compatibility only.
          await BusinessSqliteStore.upsertEntityPayloads(
            db,
            AppStore._inventoryCostLayersKey,
            <Map<String, dynamic>>[
              InventoryCostLayer(
                id: 'reversal_${original.id}_cost_layer',
                productId: product.id,
                productName: product.name,
                quantityReceived: original.quantity.abs(),
                quantityRemaining: original.quantity.abs(),
                unitCost: original.unitCost,
                currencyCode: 'USD',
                exchangeRate: 1,
                sourceType: 'inventory_waste_reversal',
                sourceId: original.id,
                createdAt: now,
                updatedAt: now,
              ).toJson(),
            ],
            sortIndices: const <int?>[0],
          );
        }
        final reversal = original.copyWith(
          id: 'reversal_${original.id}',
          type: '${original.type}_reversal',
          quantity: -original.quantity,
          date: now,
          reason: 'Safe reversal of waste operation',
          sourceMovementId: original.id,
          reversalOfMovementId: original.id,
          movementGroupId: 'reversal-$groupId',
          idempotencyKey: 'reversal:${original.id}',
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          syncStatus: 'pending',
          lastModifiedByDeviceId: _deviceId,
        );
        await stockService.recordReversalInTransaction(
          originalMovement: original,
          operationType: 'inventory_waste_reversal',
          documentType: 'inventory_waste',
          documentId: groupId,
          reason: reversal.reason,
          reversalMovementId: reversal.id,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          deviceId: _deviceId,
          syncTarget: _stockTransactionSyncTarget,
        );
        reversals.add(reversal);
      }
      await _assertUnifiedBatchMovementBalancesInTransaction(
        BatchInventoryService(db),
        reversals.where((movement) => movement.batchId.isNotEmpty),
      );
      await _requirePostedJournalInTransaction(
        db,
        referenceType: 'inventory_waste',
        referenceId: groupId,
        failureMessage:
            'Waste journal is missing; the waste reversal was rolled back.',
      );
      await AccountingService.reverseEntryForReference(
        referenceType: 'inventory_waste',
        referenceId: groupId,
        reason: 'Safe reversal of waste operation',
        createdBy: _actorName(),
        notifyChange: false,
        withinExistingTransaction: true,
      );
      await _requireNoActiveJournalInTransaction(
        db,
        referenceType: 'inventory_waste',
        referenceId: groupId,
        failureMessage:
            'Waste journal reversal did not complete; the waste reversal was rolled back.',
      );
    });
    _mirrorAuthoritativeStockMovements(reversals);
    await _refreshProductStockCompatibilityCache(
        originals.map((item) => item.productId));
    _inventoryCostLayers
      ..clear()
      ..addAll(await BusinessSqliteStore.readInventoryCostLayers(db));
    _rebuildInventoryCostLayerLookupCache();
    for (final reversal in reversals) {
      _recordSyncChange(
          entityType: 'stock_movement',
          entityId: reversal.id,
          operation: 'reverse_waste',
          payload: reversal.toJson());
    }
    AccountingService.notifyCommittedMutation();
    notifyListeners();
  }
}
