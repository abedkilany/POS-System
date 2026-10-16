part of 'app_store.dart';

extension _AppStoreSplitManufacturingPart5 on AppStore {
  Future<ManufacturingOrder> reverseManufacturingOrder({
    required String orderId,
    required String reason,
    bool withinExistingTransactionInternal = false,
    bool suppressPostCommitInternal = false,
    String operationReferenceIdOverride = '',
  }) async {
    requirePermission(AppPermission.inventoryManufacturingManage);
    if (reason.trim().isEmpty) {
      throw ArgumentError('A manufacturing reversal reason is required.');
    }
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw StateError(
          'Manufacturing reversal requires the authoritative SQLite store.');
    }
    final persistedOrders =
        await BusinessSqliteStore.readManufacturingOrders(db);
    final order = persistedOrders.firstWhere(
      (item) => item.id == orderId && !item.isDeleted,
      orElse: () => throw ArgumentError('Manufacturing order was not found.'),
    );
    if (order.status.trim().toLowerCase() == 'reversed') return order;
    if (order.status.trim().toLowerCase() != 'completed') {
      throw StateError('Only a completed manufacturing order can be reversed.');
    }
    final allMovements = await BusinessSqliteStore.readStockMovements(db);
    final reversedMovementIds = allMovements
        .where((movement) => movement.reversalOfMovementId.isNotEmpty)
        .map((movement) => movement.reversalOfMovementId)
        .toSet();
    final originals = allMovements
        .where((movement) =>
            movement.referenceId == order.id &&
            movement.reversalOfMovementId.isEmpty &&
            !reversedMovementIds.contains(movement.id) &&
            <String>{'manufacturing_consume', 'manufacturing_produce'}
                .contains(movement.type))
        .toList(growable: false);
    if (originals.isEmpty) {
      throw StateError('Manufacturing stock movements are missing.');
    }
    final unifiedOutputBatchRow = await db.customSelect(
      '''
      SELECT id
      FROM inventory_batches
      WHERE store_id = ? AND source_type = 'manufacturing_output'
        AND source_id = ? AND trim(source_line_id) <> ''
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(appIdentity.storeId),
        Variable<String>(order.id),
      ],
    ).getSingleOrNull();
    final unifiedBatchOrder = order.materialCosts.any(
          (line) => line.costingMethod.trim().toLowerCase() == 'unified_batch',
        ) ||
        unifiedOutputBatchRow != null;
    final outputMovements = originals
        .where((movement) => movement.type == 'manufacturing_produce')
        .toList(growable: false);
    final fifoBasis = _inventoryCostingMethod == InventoryCostingMethod.fifo
        ? _currentOpenFifoEffectiveFrom()
        : null;
    if (!unifiedBatchOrder &&
        fifoBasis != null &&
        originals.any((movement) => movement.date.isBefore(fifoBasis))) {
      throw StateError(
        'Cannot reverse a manufacturing order that predates the current FIFO opening basis. Reverse it before changing costing method, or use a documented inventory adjustment.',
      );
    }
    // Historical movements remain immutable. A downstream issue only blocks
    // manufacturing reversal while that movement is still active; if it has
    // already been reversed, its original negative row must not block forever.
    for (final outputMovement in outputMovements) {
      final unsafe = allMovements.any((movement) =>
          movement.productId == outputMovement.productId &&
          movement.warehouseId == outputMovement.warehouseId &&
          (outputMovement.batchId.isEmpty ||
              movement.batchId == outputMovement.batchId) &&
          movement.referenceId != order.id &&
          movement.reversalOfMovementId.isEmpty &&
          !reversedMovementIds.contains(movement.id) &&
          movement.date.isAfter(outputMovement.date) &&
          movement.quantity < 0);
      if (unsafe) {
        throw StateError(
            'This manufacturing order cannot be reversed because its finished goods moved afterward. Reverse the downstream movement first.');
      }
    }
    final now = DateTime.now();
    final actor = _activeUser?.id ?? '';
    final stockService = StockTransactionService(
      db,
      deviceId: _deviceId,
      defaultStoreId: appIdentity.storeId,
      defaultBranchId: appIdentity.branchId,
      defaultSyncTarget: _stockTransactionSyncTarget,
      allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
    );
    final batchService = BatchInventoryService(db);
    final reversalOperationReferenceId =
        operationReferenceIdOverride.trim().isEmpty
            ? '${order.id}:reversal'
            : operationReferenceIdOverride.trim();
    final reversalTransactionIdempotencyKey =
        operationReferenceIdOverride.trim().isEmpty
            ? '${order.id}:manufacturing:reversal'
            : '$reversalOperationReferenceId:manufacturing';
    final reversalMovements = originals
        .map((original) => original.copyWith(
              id: '${original.id}-reversal',
              type: '${original.type}_reversal',
              quantity: -original.quantity,
              date: now,
              reason: reason.trim(),
              sourceMovementId: original.id,
              reversalOfMovementId: original.id,
              movementGroupId: reversalOperationReferenceId,
              idempotencyKey: '$reversalOperationReferenceId:${original.id}',
              createdAt: now,
              updatedAt: now,
              reviewedBy: '',
              reviewNote: '',
              clearReviewedAt: true,
            ))
        .toList(growable: false);
    late ManufacturingOrder reversedOrder;
    Product? reversedOutputProduct;
    ProductCost? reversedOutputCost;
    Future<void> persistReversal() async {
      final duplicate = await db.customSelect(
        '''
        SELECT id FROM stock_movements
        WHERE reversal_of_movement_id IN (${List.filled(originals.length, '?').join(',')})
        LIMIT 1
        ''',
        variables: <Variable<Object>>[
          for (final movement in originals) Variable<String>(movement.id),
        ],
      ).getSingleOrNull();
      if (duplicate != null) {
        throw StateError('This manufacturing order has already been reversed.');
      }
      for (final movement in originals) {
        if (movement.batchId.isEmpty) continue;
        final product = _findProductById(movement.productId);
        if (product == null) {
          throw StateError('Product ${movement.productId} was not found.');
        }
        await batchService.reverseUnifiedMovementEffectInTransaction(
          product: product,
          warehouseId: movement.warehouseId,
          batchId: movement.batchId,
          movementQuantity: movement.quantity,
          unitCost: movement.unitCost,
          reversedAt: now,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          deviceId: _deviceId,
        );
      }
      await stockService.recordMovementsInTransaction(
        operationType: 'manufacturing_reversal',
        documentType: 'manufacturing_order',
        documentId: order.id,
        movementGroupId: reversalOperationReferenceId,
        idempotencyKey: reversalTransactionIdempotencyKey,
        movements: reversalMovements,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        deviceId: _deviceId,
      );
      if (unifiedBatchOrder) {
        await _assertUnifiedBatchMovementBalancesInTransaction(
          batchService,
          reversalMovements,
        );
      }

      if (!unifiedBatchOrder) {
        final layers = await BusinessSqliteStore.readInventoryCostLayers(db);
        final layersById = <String, InventoryCostLayer>{
          for (final layer in layers) layer.id: layer,
        };
        for (final costLine in order.materialCosts) {
          for (final snapshot in costLine.layerConsumptions) {
            final layerId = snapshot['layerId']?.toString() ?? '';
            if (layerId.isEmpty || layerId.startsWith('negative_stock:')) {
              continue;
            }
            final layer = layersById[layerId];
            if (layer == null) {
              throw StateError('Historical FIFO layer $layerId is missing.');
            }
            final restored = (snapshot['quantity'] as num? ?? 0).toDouble();
            final updated = layer.copyWith(
              quantityRemaining: layer.quantityRemaining + restored,
              isClosed: false,
              updatedAt: now,
            );
            layersById[layerId] = updated;
            await BusinessSqliteStore.upsertEntityPayloads(
              db,
              AppStore._inventoryCostLayersKey,
              <Map<String, dynamic>>[updated.toJson()],
              sortIndices: const <int?>[0],
            );
          }
        }
        final outputLayerId =
            '${order.id}-${order.outputProductId}-manufacturing-layer';
        final outputLayer = layersById[outputLayerId];
        if (outputLayer != null) {
          if (outputLayer.quantityRemaining + 0.000001 <
              outputLayer.quantityReceived) {
            throw StateError(
                'The manufacturing output cost layer has already been consumed.');
          }
          final closed = outputLayer.copyWith(
            quantityRemaining: 0,
            isClosed: true,
            updatedAt: now,
          );
          await BusinessSqliteStore.upsertEntityPayloads(
            db,
            AppStore._inventoryCostLayersKey,
            <Map<String, dynamic>>[closed.toJson()],
            sortIndices: const <int?>[0],
          );
        }
      }

      // The manufactured receipt changed both stock and the product costing
      // snapshot. Reverse that costing effect in the same SQLite transaction so
      // a crash cannot leave stock reversed while ProductCost still includes
      // the removed production receipt.
      final outputProduct = _findProductById(order.outputProductId);
      if (outputProduct != null) {
        final costRows = await BusinessSqliteStore.readProductCosts(db);
        final currentCost = costRows.firstWhere(
          (item) => item.productId == order.outputProductId,
          orElse: () => _productCostFor(order.outputProductId),
        );
        final stockRow = await db.customSelect(
          '''
          SELECT COALESCE(SUM(quantity), 0) AS qty
          FROM warehouse_inventory
          WHERE product_id = ?
          ''',
          variables: <Variable<Object>>[
            Variable<String>(order.outputProductId),
          ],
        ).getSingleOrNull();
        final stockAfter = max(
          0.0,
          (stockRow?.data['qty'] as num? ?? 0).toDouble(),
        );
        final producedQty = outputMovements.fold<double>(
          0,
          (sum, movement) => sum + max(0.0, movement.quantity),
        );
        final stockBefore = stockAfter + producedQty;
        var nextAverage = 0.0;
        if (unifiedBatchOrder) {
          final batchValueRow = await db.customSelect(
            '''
            SELECT COALESCE(SUM(bb.quantity * b.unit_cost), 0) AS value,
                   COALESCE(SUM(bb.quantity), 0) AS qty
            FROM inventory_batch_balances bb
            JOIN inventory_batches b ON b.id = bb.batch_id
              AND b.product_id = bb.product_id AND b.store_id = bb.store_id
            WHERE bb.store_id = ? AND bb.product_id = ?
              AND bb.quantity > 0.000001
            ''',
            variables: <Variable<Object>>[
              Variable<String>(appIdentity.storeId),
              Variable<String>(order.outputProductId),
            ],
          ).getSingleOrNull();
          final batchQty = (batchValueRow?.data['qty'] as num? ?? 0).toDouble();
          final batchValue =
              (batchValueRow?.data['value'] as num? ?? 0).toDouble();
          nextAverage = batchQty <= 0 ? 0.0 : batchValue / batchQty;
        } else if (_inventoryCostingMethod == InventoryCostingMethod.fifo) {
          final fifoRow = await db.customSelect(
            '''
            SELECT COALESCE(SUM(quantity_remaining * unit_cost), 0) AS value,
                   COALESCE(SUM(quantity_remaining), 0) AS qty
            FROM inventory_cost_layers
            WHERE product_id = ?
              AND deleted_at = ''
              AND quantity_remaining > 0.000001
            ''',
            variables: <Variable<Object>>[
              Variable<String>(order.outputProductId),
            ],
          ).getSingleOrNull();
          final fifoQty = (fifoRow?.data['qty'] as num? ?? 0).toDouble();
          final fifoValue = (fifoRow?.data['value'] as num? ?? 0).toDouble();
          nextAverage = fifoQty <= 0 ? 0.0 : fifoValue / fifoQty;
        } else if (stockAfter > 0 && stockBefore > 0) {
          final valueBefore = stockBefore * currentCost.averageCost;
          final removedValue = producedQty * order.actualUnitCost;
          nextAverage = max(0.0, (valueBefore - removedValue) / stockAfter);
        }

        final outputOriginalIds =
            outputMovements.map((item) => item.id).toSet();
        final activePositiveCosts = allMovements
            .where((movement) =>
                movement.productId == order.outputProductId &&
                movement.quantity > 0 &&
                movement.unitCost > 0 &&
                movement.reversalOfMovementId.isEmpty &&
                !reversedMovementIds.contains(movement.id) &&
                !outputOriginalIds.contains(movement.id))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        final nextLast = activePositiveCosts.isNotEmpty
            ? activePositiveCosts.first.unitCost
            : nextAverage;
        reversedOutputCost = currentCost.copyWith(
          averageCost: nextAverage,
          lastCost: nextLast,
          updatedAt: now,
        );
        await BusinessSqliteStore.upsertEntityPayloads(
          db,
          AppStore._productCostsKey,
          <Map<String, dynamic>>[reversedOutputCost!.toJson()],
          sortIndices: const <int?>[0],
        );
        final reversedOutputPreview = outputProduct.copyWith(
          stock: stockAfter,
          updatedAt: now,
        );
        reversedOutputProduct = suppressPostCommitInternal
            ? reversedOutputPreview.copyWith(
                deviceId: _deviceId,
                syncStatus: 'pending',
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                version: outputProduct.version + 1,
                lastModifiedByDeviceId: _deviceId,
              )
            : _withSyncMeta<Product>(reversedOutputPreview, now);
        await BusinessSqliteStore.upsertEntityPayloads(
          db,
          AppStore._productsKey,
          <Map<String, dynamic>>[reversedOutputProduct!.toJson()],
          sortIndices: const <int?>[0],
        );
      }
      await AccountingService.reverseEntryForReference(
        referenceType: 'manufacturing_order',
        referenceId: order.id,
        reason: reason.trim(),
        createdBy: actor,
        adjustCashLocationBalance: false,
        notifyChange: false,
        withinExistingTransaction: true,
      );
      final reversalJournal = await db.customSelect(
        '''
        SELECT id FROM journal_entries
        WHERE reference_type = 'manufacturing_order_reversal'
          AND reference_id = ? AND reversed_entry_id = ?
          AND status = 'posted' AND deleted_at = ''
        LIMIT 1
        ''',
        variables: <Variable<Object>>[
          Variable<String>(order.id),
          Variable<String>(order.journalEntryId),
        ],
      ).getSingleOrNull();
      if (reversalJournal == null) {
        throw StateError('Manufacturing reversal journal was not created.');
      }
      reversedOrder = order.copyWith(
        status: 'reversed',
        reversedAt: now,
        reversedBy: actor,
        reversalReason: reason.trim(),
        reversalJournalEntryId: reversalJournal.data['id']?.toString() ?? '',
        updatedAt: now,
      );
      await BusinessSqliteStore.upsertManufacturingOrderPayloadInTransaction(
        db,
        reversedOrder.toJson(),
        id: reversedOrder.id,
        payloadJson: jsonEncode(reversedOrder.toJson()),
        createdAt: reversedOrder.createdAt.toIso8601String(),
        updatedAt: reversedOrder.updatedAt.toIso8601String(),
        deletedAt: '',
        sortIndex: 0,
      );
    }

    if (withinExistingTransactionInternal) {
      await persistReversal();
    } else {
      await db.transaction(persistReversal);
    }
    if (suppressPostCommitInternal) return reversedOrder;
    _mirrorAuthoritativeStockMovements(reversalMovements);
    final index =
        _manufacturingOrders.indexWhere((item) => item.id == order.id);
    if (index == -1) {
      _manufacturingOrders.add(reversedOrder);
    } else {
      _manufacturingOrders[index] = reversedOrder;
    }
    _inventoryCostLayers
      ..clear()
      ..addAll(await BusinessSqliteStore.readInventoryCostLayers(db));
    _rebuildInventoryCostLayerLookupCache();
    if (reversedOutputProduct != null) {
      final outputIndex = _productIndexById[reversedOutputProduct!.id];
      if (outputIndex != null) _products[outputIndex] = reversedOutputProduct!;
    }
    if (reversedOutputCost != null) {
      _productCosts
        ..clear()
        ..addAll(await BusinessSqliteStore.readProductCosts(db));
      _rebuildProductCostLookupCache();
    }
    await _refreshProductStockCompatibilityCache(<String>{
      for (final movement in originals) movement.productId,
    });
    _recordSyncChange(
      entityType: 'manufacturing_order',
      entityId: order.id,
      operation: 'reverse',
      payload: reversedOrder.toJson(),
    );
    for (final movement in reversalMovements) {
      _recordSyncChange(
        entityType: 'stock_movement',
        entityId: movement.id,
        operation: 'manufacturing_reversal',
        payload: movement.toJson(),
      );
    }
    notifyListeners();
    return reversedOrder;
  }
}
