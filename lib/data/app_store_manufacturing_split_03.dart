part of 'app_store.dart';

extension _AppStoreSplitManufacturingPart3 on AppStore {
  Future<ManufacturingOrder> completeManufacturingOrder({
    required String bomId,
    required double quantity,
    String rawMaterialsWarehouseId = '',
    String rawMaterialsWarehouseName = '',
    String finishedGoodsWarehouseId = '',
    String finishedGoodsWarehouseName = '',
    String notes = '',
    List<BatchAllocation> outputBatchAllocations = const <BatchAllocation>[],
    Map<String, double> actualConsumedQuantities = const <String, double>{},
    Map<String, double> wasteQuantities = const <String, double>{},
    Map<String, String> wasteReasons = const <String, String>{},
    String existingOrderId = '',
    bool allowCompletedRepostInternal = false,
    bool withinExistingTransactionInternal = false,
    bool suppressPostCommitInternal = false,
    String technicalReferenceIdOverride = '',
    String operationReferenceIdOverride = '',
    ManufacturingOrder? existingOrderOverride,
  }) async {
    requirePermission(AppPermission.inventoryManufacturingManage);
    if (!LocalDatabaseService.isSqliteAuthoritative ||
        SqliteMigrationManager.database == null) {
      throw StateError(
          'Manufacturing completion requires the authoritative SQLite store.');
    }
    // Prevent a stale debounced ProductCost snapshot from racing the finished
    // goods cost written atomically by the manufacturing transaction.
    if (!withinExistingTransactionInternal) {
      await _flushProductDerivedData();
    }
    if (quantity <= 0) {
      throw ArgumentError('Manufacturing quantity must be greater than zero.');
    }
    final existingOrderIndex = existingOrderId.trim().isEmpty
        ? -1
        : _manufacturingOrders.indexWhere(
            (item) => item.id == existingOrderId && !item.isDeleted,
          );
    if (existingOrderId.trim().isNotEmpty &&
        existingOrderIndex == -1 &&
        existingOrderOverride == null) {
      throw ArgumentError('Manufacturing order was not found.');
    }
    final existingOrder = existingOrderOverride ??
        (existingOrderIndex == -1
            ? null
            : _manufacturingOrders[existingOrderIndex]);
    if (existingOrder != null &&
        <String>{'completed', 'reversed'}
            .contains(existingOrder.status.trim().toLowerCase()) &&
        !allowCompletedRepostInternal) {
      return existingOrder;
    }
    final bom = _billsOfMaterials.firstWhere(
      (item) => item.id == bomId && !item.isDeleted && item.isActive,
      orElse: () => throw ArgumentError('BOM was not found.'),
    );
    final output = _findProductById(bom.outputProductId);
    if (output == null) throw ArgumentError('Output product was not found.');
    if (!output.trackStock) {
      throw StateError('Manufacturing output must be a stock-tracked product.');
    }
    final factor = quantity / bom.outputQuantity;
    final now = DateTime.now();
    final rawWarehouse = _resolveWarehouseForPurchase(
      warehouseId: rawMaterialsWarehouseId,
    );
    final finishedWarehouse = _resolveWarehouseForSale(
      warehouseId: finishedGoodsWarehouseId,
    );
    final orderPreview = ManufacturingOrder(
      id: existingOrder?.id ?? '${now.microsecondsSinceEpoch}-mfg',
      orderNo: existingOrder?.orderNo ??
          'MFG-${now.microsecondsSinceEpoch.toString().substring(6)}',
      bomId: bom.id,
      bomName: bom.name,
      outputProductId: output.id,
      outputProductName: output.name,
      quantity: quantity,
      rawMaterialsWarehouseId: rawWarehouse.id,
      rawMaterialsWarehouseName: rawMaterialsWarehouseName.trim().isEmpty
          ? rawWarehouse.name
          : rawMaterialsWarehouseName.trim(),
      finishedGoodsWarehouseId: finishedWarehouse.id,
      finishedGoodsWarehouseName: finishedGoodsWarehouseName.trim().isEmpty
          ? finishedWarehouse.name
          : finishedGoodsWarehouseName.trim(),
      notes: notes.trim(),
      date: existingOrder?.date ?? now,
      createdAt: existingOrder?.createdAt,
      status: 'completed',
    );
    var order = suppressPostCommitInternal && existingOrder != null
        ? orderPreview.copyWith(
            updatedAt: now,
            deviceId: _deviceId,
            syncStatus: 'pending',
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            version: existingOrder.version + 1,
            lastModifiedByDeviceId: _deviceId,
          )
        : _withSyncMeta<ManufacturingOrder>(
            orderPreview,
            now,
            isCreate: existingOrder == null,
          );
    final operationReferenceId = operationReferenceIdOverride.trim().isEmpty
        ? order.id
        : operationReferenceIdOverride.trim();
    final technicalReferenceId = technicalReferenceIdOverride.trim().isEmpty
        ? order.id
        : technicalReferenceIdOverride.trim();
    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      final stockService = StockTransactionService(
        sqliteDb,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
      );
      final batchService = BatchInventoryService(sqliteDb);
      final movements = <StockMovement>[];
      var producedBatchAllocations = const <BatchAllocation>[];
      Product? persistedOutputProduct;
      ProductCost? persistedOutputCost;
      double consumedCost = 0;
      double wasteCost = 0;
      late double producedUnitCost;
      final materialCosts = <ManufacturingMaterialCost>[];
      final wasteLines = <ManufacturingWasteLine>[];
      Future<void> persistCompletion() async {
        for (var lineIndex = 0;
            lineIndex < bom.components.length;
            lineIndex += 1) {
          final component = bom.components[lineIndex];
          final product = _findProductById(component.productId);
          if (product == null || !product.trackStock) continue;
          final requestedActual = actualConsumedQuantities[component.productId];
          final usedQty = requestedActual ?? component.quantity * factor;
          if (usedQty <= 0) continue;
          await _ensureUnifiedBatchCutoverForProductInTransaction(
            sqliteDb,
            product: product,
            warehouseId: rawWarehouse.id,
            at: now,
          );
          await _repairZeroCostManufacturingInputBatchesInTransaction(
            sqliteDb,
            batchService: batchService,
            product: product,
            warehouseId: rawWarehouse.id,
            requiredQuantity: usedQty,
            repairedAt: now,
            referenceId: technicalReferenceId,
            referenceNo: order.orderNo,
          );
          // Manufacturing follows the store-wide negative-stock policy.
          // When negative stock is disabled we keep the strict physical-batch
          // guard. When it is enabled, Unified Batch consumes real batches
          // first and creates a tracked deficit only for the shortage. The
          // deficit carries a provisional reference cost and is reconciled by
          // the existing deficit-settlement variance journal when real stock
          // arrives later.
          if (!_storeProfile.allowNegativeStock) {
            await batchService.requirePhysicalUnifiedStockInTransaction(
              product: product,
              warehouseId: rawWarehouse.id,
              quantity: usedQty,
              movementDate: now,
              storeId: appIdentity.storeId,
              operation: 'manufacturing',
            );
          } else {
            final preview =
                await batchService.previewUnifiedAllocationInTransaction(
              product: product,
              warehouseId: rawWarehouse.id,
              quantity: usedQty,
              movementDate: now,
              storeId: appIdentity.storeId,
              includeProvisionalShortage: true,
            );
            if (preview.hasShortage &&
                (!preview.usesProvisionalCost ||
                    preview.provisionalUnitCost <= 0.000001)) {
              throw LocalizedDomainException(
                'error_manufacturing_provisional_cost_missing',
                values: <String, Object?>{'product': product.name},
                fallback:
                    'Manufacturing cannot use negative stock for ${product.name} because no valid reference cost is available. Set a cost or receive a costed batch first.',
              );
            }
          }
          final allocations = await batchService.allocateUnifiedInTransaction(
            product: product,
            warehouseId: rawWarehouse.id,
            quantity: usedQty,
            movementDate: now,
            storeId: appIdentity.storeId,
            deviceId: _deviceId,
            branchId: appIdentity.branchId,
            allowNegativeStock: _storeProfile.allowNegativeStock,
          );
          final lineTotalCost = allocations.fold<double>(
            0,
            (sum, allocation) =>
                sum + (allocation.quantity * allocation.unitCost),
          );
          final lineUnitCost = usedQty <= 0 ? 0.0 : lineTotalCost / usedQty;
          if (lineUnitCost <= 0.000001) {
            throw LocalizedDomainException(
              'error_manufacturing_material_cost_missing',
              values: <String, Object?>{'product': product.name},
              fallback:
                  'Manufacturing cost is missing for ${product.name}. Set a valid batch/reference cost before completing the order.',
            );
          }
          consumedCost += lineTotalCost;
          final requestedWaste = wasteQuantities[component.productId] ?? 0;
          if (requestedWaste < 0 || requestedWaste > usedQty + 0.000001) {
            throw ArgumentError(
                'Manufacturing waste must be between zero and actual consumption for ${product.name}.');
          }
          final lineWasteCost = requestedWaste * lineUnitCost;
          wasteCost += lineWasteCost;
          if (requestedWaste > 0) {
            wasteLines.add(ManufacturingWasteLine(
              productId: product.id,
              productName: product.name,
              quantity: requestedWaste,
              unitCost: lineUnitCost,
              value: lineWasteCost,
              reason: (wasteReasons[product.id] ?? '').trim().isEmpty
                  ? 'Manufacturing waste'
                  : wasteReasons[product.id]!.trim(),
            ));
          }
          final baseMovement = StockMovement(
            id: '$operationReferenceId-$lineIndex-${component.productId}-manufacturing-consume',
            productId: component.productId,
            productName: product.name,
            type: 'manufacturing_consume',
            quantity: -usedQty,
            date: now,
            referenceId: order.id,
            referenceNo: order.orderNo,
            reason: 'Manufacturing component consumption',
            warehouseId: rawWarehouse.id,
            warehouseName: rawWarehouse.name,
            movementGroupId: operationReferenceId,
            documentLineId: '$operationReferenceId-consume-$lineIndex',
            idempotencyKey:
                '$operationReferenceId:manufacture:consume:$lineIndex',
            unitCost: lineUnitCost,
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            lastModifiedByDeviceId: _deviceId,
          );
          final lineMovementIds = <String>[];
          for (var batchIndex = 0;
              batchIndex < allocations.length;
              batchIndex += 1) {
            final allocation = allocations[batchIndex];
            final movementId = '${baseMovement.id}-batch-$batchIndex';
            lineMovementIds.add(movementId);
            movements.add(baseMovement.copyWith(
              id: movementId,
              quantity: -allocation.quantity,
              batchId: allocation.batchId,
              unitCost: allocation.unitCost,
              documentLineId:
                  '$operationReferenceId-consume-$lineIndex-batch-$batchIndex',
              idempotencyKey:
                  '$operationReferenceId:manufacture:consume:$lineIndex:$batchIndex',
            ));
          }
          materialCosts.add(ManufacturingMaterialCost(
            productId: product.id,
            productName: product.name,
            quantity: usedQty,
            unitCost: lineUnitCost,
            totalCost: lineTotalCost,
            costingMethod: 'unified_batch',
            movementIds: lineMovementIds,
            layerConsumptions: <Map<String, dynamic>>[
              for (final allocation in allocations)
                <String, dynamic>{
                  'batchId': allocation.batchId,
                  'quantity': allocation.quantity,
                  'unitCost': allocation.unitCost,
                },
            ],
          ));
        }
        final eligibleCost = max(0.0, consumedCost - wasteCost);
        producedUnitCost = quantity <= 0 ? 0.0 : eligibleCost / quantity;
        final outputMovement = StockMovement(
          id: '$operationReferenceId-${output.id}-manufacturing-output',
          productId: output.id,
          productName: output.name,
          type: 'manufacturing_produce',
          quantity: quantity,
          date: now,
          referenceId: order.id,
          referenceNo: order.orderNo,
          reason: 'Manufacturing finished goods output',
          warehouseId: finishedWarehouse.id,
          warehouseName: finishedWarehouse.name,
          movementGroupId: operationReferenceId,
          documentLineId: '$operationReferenceId-produce',
          idempotencyKey: '$operationReferenceId:manufacture:produce',
          unitCost: producedUnitCost,
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
        );
        await _ensureUnifiedBatchCutoverForProductInTransaction(
          sqliteDb,
          product: output,
          warehouseId: finishedWarehouse.id,
          at: now,
        );
        final requestedOutputBatches = output.expiryTrackingEnabled
            ? outputBatchAllocations
            : <BatchAllocation>[
                BatchAllocation(
                  batchId:
                      '$operationReferenceId-${output.id}-manufacturing-batch',
                  quantity: quantity,
                  manufacturingDate: now,
                  unitCost: producedUnitCost,
                ),
              ];
        if (output.expiryTrackingEnabled && requestedOutputBatches.isEmpty) {
          throw LocalizedDomainException(
            'error_expiry_batches_required',
            values: {'product': output.name},
            fallback: 'Expiry batches are required for ${output.name}.',
          );
        }
        final outputBatchTotal = requestedOutputBatches.fold<double>(
          0,
          (sum, allocation) => sum + allocation.quantity,
        );
        if ((outputBatchTotal - quantity).abs() > 0.000001) {
          throw LocalizedDomainException(
            'error_batch_quantity_total',
            values: {'product': output.name, 'quantity': quantity},
            fallback:
                'Batch quantities for ${output.name} must equal $quantity.',
          );
        }
        final resolvedOutputBatches = <BatchAllocation>[];
        for (var batchIndex = 0;
            batchIndex < requestedOutputBatches.length;
            batchIndex += 1) {
          final requested = requestedOutputBatches[batchIndex];
          final resolved = await batchService.addUnifiedBatchStockInTransaction(
            product: output,
            warehouseId: finishedWarehouse.id,
            batchId: operationReferenceId != order.id
                ? '$operationReferenceId-${output.id}-manufacturing-batch-$batchIndex'
                : requested.batchId.trim().isEmpty
                    ? '$operationReferenceId-${output.id}-manufacturing-batch-$batchIndex'
                    : requested.batchId.trim(),
            quantity: requested.quantity,
            unitCost: producedUnitCost,
            sourceType: 'manufacturing_output',
            sourceId: operationReferenceId,
            sourceLineId: '$operationReferenceId:output:$batchIndex',
            receivedAt: now,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            deviceId: _deviceId,
            supplierBatchNumber: requested.supplierBatchNumber,
            manufacturingDate: requested.manufacturingDate ?? now,
            expirationDate: requested.expirationDate,
            costCurrency: 'USD',
            exchangeRate: 1,
          );
          resolvedOutputBatches.add(resolved);
          movements.add(outputMovement.copyWith(
            id: '${outputMovement.id}-batch-$batchIndex',
            quantity: resolved.quantity,
            batchId: resolved.batchId,
            unitCost: producedUnitCost,
            documentLineId: '$operationReferenceId-produce-batch-$batchIndex',
            idempotencyKey:
                '$operationReferenceId:manufacture:produce:$batchIndex',
          ));
        }
        producedBatchAllocations = resolvedOutputBatches;
        order = order.copyWith(
          actualOutputQuantity: quantity,
          totalMaterialCost: consumedCost,
          totalWasteCost: wasteCost,
          totalEligibleCost: eligibleCost,
          actualUnitCost: producedUnitCost,
          materialCosts: materialCosts,
          wasteLines: wasteLines,
          completedAt: now,
          completedBy: _activeUser?.id ?? '',
          updatedAt: now,
        );
        await BusinessSqliteStore.upsertManufacturingOrderPayloadInTransaction(
          sqliteDb,
          order.toJson(),
          id: order.id,
          payloadJson: jsonEncode(order.toJson()),
          createdAt: order.createdAt.toIso8601String(),
          updatedAt: order.updatedAt.toIso8601String(),
          deletedAt: '',
          sortIndex: 0,
        );
        await stockService.recordMovementsInTransaction(
          operationType: 'manufacturing',
          documentType: 'manufacturing_order',
          documentId: order.id,
          movementGroupId: operationReferenceId,
          idempotencyKey: '$operationReferenceId:manufacture',
          movements: movements,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          deviceId: _deviceId,
        );
        await _assertUnifiedBatchMovementBalancesInTransaction(
          batchService,
          movements,
        );
        await InventoryTraceabilityService(sqliteDb)
            .assertManufacturingTraceabilityInTransaction(
          orderId: order.id,
          storeId: appIdentity.storeId,
          operationReferenceId: operationReferenceId,
          expectedOutputQuantity: quantity,
          expectedMaterialCost: consumedCost,
          expectedWasteCost: wasteCost,
          expectedEligibleCost: eligibleCost,
        );
        // Unified Batch carries finished-goods quantity and cost; no new legacy cost layer is created.

        // Persist the manufactured product's costing state in the same SQLite
        // transaction as stock, cost layers, the manufacturing order and the
        // journal. A crash after commit must never leave ProductCost in RAM only.
        final persistedCosts =
            await BusinessSqliteStore.readProductCosts(sqliteDb);
        final currentCost = persistedCosts.firstWhere(
          (item) => item.productId == output.id,
          orElse: () => ProductCost(
            productId: output.id,
            averageCost: _safeUsdCost(output),
            lastCost: _safeUsdCost(output),
            currencyCode: 'USD',
            createdAt: output.createdAt,
            updatedAt: now,
          ),
        );
        final batchValueRow = await sqliteDb.customSelect(
          '''
          SELECT COALESCE(SUM(bb.quantity), 0) AS quantity,
                 COALESCE(SUM(bb.quantity * b.unit_cost), 0) AS value
          FROM inventory_batch_balances bb
          JOIN inventory_batches b ON b.id = bb.batch_id
            AND b.product_id = bb.product_id AND b.store_id = bb.store_id
          WHERE bb.store_id = ? AND bb.product_id = ?
          ''',
          variables: <Variable<Object>>[
            Variable<String>(appIdentity.storeId),
            Variable<String>(output.id),
          ],
        ).getSingle();
        final stockAfter =
            (batchValueRow.data['quantity'] as num? ?? 0).toDouble();
        final carryingValue =
            (batchValueRow.data['value'] as num? ?? 0).toDouble();
        final nextAverageCost = stockAfter <= 0.000001
            ? producedUnitCost
            : carryingValue / stockAfter;
        persistedOutputCost = currentCost.copyWith(
          averageCost: nextAverageCost,
          lastCost: producedUnitCost,
          currencyCode: 'USD',
          updatedAt: now,
        );
        await BusinessSqliteStore.upsertEntityPayloads(
          sqliteDb,
          AppStore._productCostsKey,
          <Map<String, dynamic>>[persistedOutputCost!.toJson()],
          sortIndices: const <int?>[0],
        );
        // Finished-goods valuation lives in the produced Unified Batch.
        // Keep the product reference cost user-maintained and independent.
        final outputPreview = output.copyWith(stock: stockAfter);
        persistedOutputProduct = suppressPostCommitInternal
            ? outputPreview.copyWith(
                updatedAt: now,
                deviceId: _deviceId,
                syncStatus: 'pending',
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                version: output.version + 1,
                lastModifiedByDeviceId: _deviceId,
              )
            : _withSyncMeta<Product>(outputPreview, now);
        await BusinessSqliteStore.upsertEntityPayloads(
          sqliteDb,
          AppStore._productsKey,
          <Map<String, dynamic>>[persistedOutputProduct!.toJson()],
          sortIndices: const <int?>[0],
        );

        final journalEntryId =
            await AccountingService.recordManufacturingCompletionInTransaction(
          database: sqliteDb,
          order: order,
          technicalReferenceId: technicalReferenceId,
        );
        if (journalEntryId.isEmpty) {
          throw StateError('Manufacturing accounting journal was not created.');
        }
        order = order.copyWith(journalEntryId: journalEntryId);
        await BusinessSqliteStore.upsertManufacturingOrderPayloadInTransaction(
          sqliteDb,
          order.toJson(),
          id: order.id,
          payloadJson: jsonEncode(order.toJson()),
          createdAt: order.createdAt.toIso8601String(),
          updatedAt: order.updatedAt.toIso8601String(),
          deletedAt: '',
          sortIndex: 0,
        );
      }

      if (withinExistingTransactionInternal) {
        await persistCompletion();
      } else {
        await sqliteDb.transaction(persistCompletion);
      }
      if (suppressPostCommitInternal) return order;
      _mirrorAuthoritativeStockMovements(movements);
      _inventoryCostLayers
        ..clear()
        ..addAll(await BusinessSqliteStore.readInventoryCostLayers(sqliteDb));
      _rebuildInventoryCostLayerLookupCache();
      final touchedProductIds = <String>{
        for (final component in bom.components) component.productId,
        output.id,
      };
      final outputIndex = _productIndexById[output.id];
      if (outputIndex != null && persistedOutputProduct != null) {
        _products[outputIndex] = persistedOutputProduct!;
      }
      _productCosts
        ..clear()
        ..addAll(await BusinessSqliteStore.readProductCosts(sqliteDb));
      _rebuildProductCostLookupCache();
      await _refreshProductStockCompatibilityCache(touchedProductIds);
      if (existingOrderIndex == -1) {
        _manufacturingOrders.add(order);
      } else {
        _manufacturingOrders[existingOrderIndex] = order;
      }
      if (producedBatchAllocations.isNotEmpty) {
        _recordInventoryBatchSyncChanges(
          product: output,
          allocations: producedBatchAllocations,
          sourceType: 'manufacturing_output',
          sourceId: order.id,
          now: now,
          unitCost: producedUnitCost,
          sourceLineIds: <String>[
            for (var index = 0;
                index < producedBatchAllocations.length;
                index += 1)
              '${order.id}:output:$index',
          ],
        );
      }
      for (final movement in movements) {
        _recordSyncChange(
          entityType: 'stock_movement',
          entityId: movement.id,
          operation: 'manufacturing',
          payload: movement.toJson(),
        );
      }
      _recordSyncChange(
        entityType: 'manufacturing_order',
        entityId: order.id,
        operation: 'complete',
        payload: order.toJson(),
      );
      notifyListeners();
      return order;
    }

    for (var lineIndex = 0; lineIndex < bom.components.length; lineIndex += 1) {
      final component = bom.components[lineIndex];
      final index = _productIndexById[component.productId];
      if (index == null) continue;
      final product = _products[index];
      if (!product.trackStock) continue;
      final usedQty = component.quantity * factor;
      if (usedQty <= 0) continue;
      if (!_storeProfile.allowNegativeStock &&
          _stockForWarehouse(component.productId, rawWarehouse.id) < usedQty) {
        throw ArgumentError(
          'Insufficient stock for ${product.name} in ${rawWarehouse.name}.',
        );
      }
      _products[index] = _withSyncMeta<Product>(
        product.copyWith(stock: product.stock - usedQty),
        now,
      );
      _addStockMovement(
        StockMovement(
          id: '${order.id}-$lineIndex-${component.productId}-manufacturing-consume',
          productId: component.productId,
          productName: product.name,
          type: 'manufacturing_consume',
          quantity: -usedQty,
          date: now,
          referenceId: order.id,
          referenceNo: order.orderNo,
          reason: 'Manufacturing component consumption',
          warehouseId: rawWarehouse.id,
          warehouseName: rawWarehouse.name,
          movementGroupId: order.id,
          documentLineId: '${order.id}-consume-$lineIndex',
          idempotencyKey: '${order.id}:manufacture:consume:$lineIndex',
          unitCost: _safeUsdCost(product),
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
        ),
        recordSync: true,
      );
    }

    final outputIndex = _productIndexById[output.id];
    final producedCost = bom.components.fold<double>(
          0,
          (sum, component) {
            final product = _findProductById(component.productId);
            if (product == null || !product.trackStock) return sum;
            return sum + component.quantity * factor * _safeUsdCost(product);
          },
        ) /
        (quantity <= 0 ? 1 : quantity);
    if (outputIndex != null && output.trackStock) {
      _products[outputIndex] = _withSyncMeta<Product>(
        output.copyWith(stock: output.stock + quantity),
        now,
      );
      _addInventoryCostLayerFromStockIncrease(
        id: '${order.id}-${output.id}-manufacturing-layer',
        product: output,
        quantity: quantity,
        unitCost: producedCost,
        sourceType: 'manufacturing_output',
        sourceId: order.id,
        now: now,
      );
      _addStockMovement(
        StockMovement(
          id: '${order.id}-${output.id}-manufacturing-output',
          productId: output.id,
          productName: output.name,
          type: 'manufacturing_produce',
          quantity: quantity,
          date: now,
          referenceId: order.id,
          referenceNo: order.orderNo,
          reason: 'Manufacturing finished goods output',
          warehouseId: finishedWarehouse.id,
          warehouseName: finishedWarehouse.name,
          movementGroupId: order.id,
          documentLineId: '${order.id}-produce',
          idempotencyKey: '${order.id}:manufacture:produce',
          unitCost: producedCost,
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
        ),
        recordSync: true,
      );
    }

    if (existingOrderIndex == -1) {
      _manufacturingOrders.add(order);
    } else {
      _manufacturingOrders[existingOrderIndex] = order;
    }
    _recordSyncChange(
      entityType: 'manufacturing_order',
      entityId: order.id,
      operation: 'complete',
      payload: order.toJson(),
    );
    await _saveDirty(
      products: true,
      productDerivedData: true,
      stockMovements: true,
      manufacturingOrders: true,
      sync: true,
    );
    notifyListeners();
    return order;
  }
}
