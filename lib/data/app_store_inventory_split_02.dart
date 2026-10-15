part of 'app_store.dart';

extension _AppStoreSplitInventoryPart2 on AppStore {
  Future<void> reverseInventoryCount(
    String sessionId, {
    String reason = '',
  }) async {
    requirePermission(AppPermission.inventoryCountsManage);
    final sessionIndex = _inventoryCounts.indexWhere(
      (session) => session.id == sessionId,
    );
    if (sessionIndex == -1) {
      throw ArgumentError('Inventory count session not found.');
    }
    final session = _inventoryCounts[sessionIndex];
    if (!session.isApproved) {
      if (session.isReversed) return;
      throw StateError('Only approved inventory counts can be reversed.');
    }
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError(
          'عكس الجرد المعتمد يتطلب قاعدة SQLite المهيأة لهذا الإصدار.');
    }
    final now = DateTime.now();
    final stockService = StockTransactionService(
      sqliteDb,
      deviceId: _deviceId,
      defaultStoreId: appIdentity.storeId,
      defaultBranchId: appIdentity.branchId,
      defaultSyncTarget: _stockTransactionSyncTarget,
      allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
    );
    final committedReversals = <StockMovement>[];
    InventoryCountSession? reversedSession;
    var reversalJournalEntryId = '';
    await sqliteDb.transaction(() async {
      final originals =
          await BusinessSqliteStore.readUnreversedInventoryCountMovements(
        sqliteDb,
        session.id,
      );
      final reversals = <StockMovement>[];
      for (final original in originals) {
        if (original.batchId.isNotEmpty) {
          final product = _findProductById(original.productId);
          if (product == null) {
            throw StateError('Count product no longer exists.');
          }
          await BatchInventoryService(sqliteDb)
              .reverseUnifiedMovementEffectInTransaction(
            product: product,
            warehouseId: original.warehouseId,
            batchId: original.batchId,
            movementQuantity: original.quantity,
            unitCost: original.unitCost,
            reversedAt: now,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            deviceId: _deviceId,
          );
        } else {
          // Restore the exact historical value carried by the original count
          // movement.  A positive count layer may only be removed while it has
          // not been consumed by a downstream document; otherwise a reversal
          // would fabricate quantity/value out of sequence.
          if (original.quantity < -0.000001) {
            final product = _findProductById(original.productId);
            if (product == null) {
              throw StateError('Count product no longer exists.');
            }
            final restoredLayer = InventoryCostLayer(
              id: 'reversal_${original.id}_cost_layer',
              productId: product.id,
              productName: product.name,
              quantityReceived: original.quantity.abs(),
              quantityRemaining: original.quantity.abs(),
              unitCost: original.unitCost,
              currencyCode: 'USD',
              exchangeRate: 1,
              sourceType: 'inventory_count_reversal',
              sourceId: original.id,
              createdAt: now,
              updatedAt: now,
            );
            await BusinessSqliteStore.upsertEntityPayloads(
              sqliteDb,
              AppStore._inventoryCostLayersKey,
              <Map<String, dynamic>>[restoredLayer.toJson()],
              sortIndices: const <int?>[0],
            );
          } else if (original.quantity > 0.000001) {
            final layers =
                await BusinessSqliteStore.readInventoryCostLayers(sqliteDb);
            final layer = layers.firstWhere(
              (item) =>
                  item.productId == original.productId &&
                  item.sourceType == 'inventory_count' &&
                  item.sourceId == session.id,
              orElse: () =>
                  throw StateError('Historical count cost layer is missing.'),
            );
            if (layer.quantityRemaining + 0.000001 < original.quantity) {
              throw StateError(
                  'Inventory count gain has downstream consumption and cannot be reversed.');
            }
            final remaining = layer.quantityRemaining - original.quantity;
            await BusinessSqliteStore.upsertEntityPayloads(
              sqliteDb,
              AppStore._inventoryCostLayersKey,
              <Map<String, dynamic>>[
                layer
                    .copyWith(
                      quantityRemaining: remaining,
                      isClosed: remaining <= 0.000001,
                      updatedAt: now,
                    )
                    .toJson(),
              ],
              sortIndices: const <int?>[0],
            );
          }
        }
        reversals.add(original.copyWith(
          id: 'reversal_${original.id}',
          type: 'count_adjustment_reversal',
          quantity: -original.quantity,
          date: now,
          reason: reason.trim().isEmpty
              ? 'Reversal of inventory count ${session.countNo}'
              : reason.trim(),
          adjustmentCategory: 'stock_count_reversal',
          notes: 'Reversal of ${original.id}',
          movementGroupId: '${session.id}-reversal',
          documentLineId: '${original.documentLineId}-reversal',
          sourceMovementId: original.id,
          reversalOfMovementId: original.id,
          idempotencyKey: '${session.id}:count:reversal:${original.id}',
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          syncStatus: 'pending',
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
          clearReviewedAt: true,
          reviewedBy: '',
          reviewNote: '',
        ));
      }
      if (reversals.isNotEmpty) {
        await stockService.recordMovementsInTransaction(
          operationType: 'inventory_count_reversal',
          documentType: 'inventory_count',
          documentId: session.id,
          movementGroupId: '${session.id}-reversal',
          idempotencyKey: '${session.id}:count:reversal',
          movements: reversals,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          deviceId: _deviceId,
          skipExistingMovementLookup: true,
        );
        await _assertUnifiedBatchMovementBalancesInTransaction(
          BatchInventoryService(sqliteDb),
          reversals.where((movement) => movement.batchId.isNotEmpty),
        );
      }
      reversalJournalEntryId =
          await AccountingService.reverseInventoryCountAdjustmentInTransaction(
        database: sqliteDb,
        referenceId: session.id,
        reason: reason,
        createdBy: _actorName(),
      );
      reversedSession = session.copyWith(
        status: 'reversed',
        reversalJournalEntryId: reversalJournalEntryId,
        reversedAt: now,
        reversedBy: _actorName(),
        reversalReason: reason.trim(),
        updatedAt: now,
      );
      await BusinessSqliteStore.upsertInventoryCountInTransaction(
        sqliteDb,
        reversedSession!,
      );
      await AccountingService.recordInventoryCountAuditInTransaction(
        database: sqliteDb,
        action: 'reverse_inventory_count',
        inventoryCountId: session.id,
        details: reason.trim().isEmpty
            ? 'تم عكس الجرد ${session.countNo}.'
            : 'تم عكس الجرد ${session.countNo}: ${reason.trim()}',
        createdBy: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        createdAt: now,
      );
      committedReversals.addAll(reversals);
    });

    _inventoryCounts[sessionIndex] = reversedSession!;
    if (committedReversals.isNotEmpty) {
      _mirrorAuthoritativeStockMovements(committedReversals);
      await _refreshProductStockCompatibilityCache(
        committedReversals.map((movement) => movement.productId),
      );
      _inventoryCostLayers
        ..clear()
        ..addAll(await BusinessSqliteStore.readInventoryCostLayers(sqliteDb));
      _rebuildInventoryCostLayerLookupCache();
    }
    _rememberSqliteDirtyBusinessRow(
      AppStore._inventoryCountsKey,
      reversedSession!.toJson(),
    );
    await _saveDirty(inventoryCounts: true, sync: true);
    if (reversalJournalEntryId.isNotEmpty) {
      AccountingService.notifyCommittedMutation();
    }
    notifyListeners();
  }

  Future<void> cancelInventoryCount(String sessionId) async {
    requirePermission(AppPermission.inventoryCountsManage);
    final sessionIndex = _inventoryCounts.indexWhere(
      (session) => session.id == sessionId,
    );
    if (sessionIndex == -1) {
      throw ArgumentError('Inventory count session not found.');
    }
    final session = _inventoryCounts[sessionIndex];
    if (!session.isOpen) return;
    final now = DateTime.now();
    _inventoryCounts[sessionIndex] = session.copyWith(
      status: 'cancelled',
      updatedAt: now,
    );
    _rememberSqliteDirtyBusinessRow(
      AppStore._inventoryCountsKey,
      _inventoryCounts[sessionIndex].toJson(),
    );
    await _saveDirty(inventoryCounts: true);
    notifyListeners();
  }

  Future<void> reviewAutoCorrection(
    String movementId, {
    String note = '',
  }) async {
    requirePermission(AppPermission.inventoryCorrectionsManage);
    final index = _stockMovements.indexWhere(
      (movement) => movement.id == movementId,
    );
    if (index == -1) throw ArgumentError('Stock movement not found.');
    final movement = _stockMovements[index];
    if (movement.type != 'auto_correction') {
      throw StateError('Only automatic corrections can be reviewed here.');
    }
    if (movement.isReviewed) return;
    final now = DateTime.now();
    final reviewer = _activeUser?.fullName.trim().isNotEmpty == true
        ? _activeUser!.fullName.trim()
        : (_activeUser?.username ?? currentRole);
    final updated = movement.copyWith(
      reviewedAt: now,
      reviewedBy: reviewer,
      reviewNote: note.trim(),
      updatedAt: now,
      syncStatus: 'pending',
      version: movement.version + 1,
      lastModifiedByDeviceId: _deviceId,
    );
    _putStockMovementAtIndex(updated, index);
    _recordSyncChange(
      entityType: 'stock_movement',
      entityId: updated.id,
      operation: 'review',
      payload: updated.toJson(),
    );
    await _saveDirty(stockMovements: true, sync: true);
    notifyListeners();
  }

  Future<void> setExpiryBatchStatus(String batchId, String status) async {
    requirePermission(AppPermission.inventoryCorrectionsManage);
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw const LocalizedDomainException('error_batch_database_required',
          fallback: 'Batch management requires the local database.');
    }
    final now = DateTime.now();
    await db.transaction(
        () => BatchInventoryService(db).setBatchStatusInTransaction(
              batchId: batchId,
              status: status,
              updatedAt: now,
              storeId: appIdentity.storeId,
              deviceId: _deviceId,
            ));
    _recordSyncChange(
      entityType: 'inventory_batch',
      entityId: batchId,
      operation: 'status',
      payload: <String, dynamic>{
        'id': batchId,
        'status': status,
        'updatedAt': now.toIso8601String(),
      },
    );
    notifyListeners();
  }

  void _recordInventoryBatchSyncChanges({
    required Product product,
    required List<BatchAllocation> allocations,
    required String sourceType,
    required String sourceId,
    required DateTime now,
    double unitCost = 0,
    String sourceLineId = '',
    List<String> sourceLineIds = const <String>[],
    DateTime? receivedAt,
  }) {
    for (var allocationIndex = 0;
        allocationIndex < allocations.length;
        allocationIndex += 1) {
      final allocation = allocations[allocationIndex];
      final resolvedSourceLineId = sourceLineIds.length > allocationIndex
          ? sourceLineIds[allocationIndex]
          : sourceLineId;
      _recordSyncChange(
        entityType: 'inventory_batch',
        entityId: allocation.batchId,
        operation: 'upsert',
        payload: <String, dynamic>{
          'id': allocation.batchId,
          'productId': product.id,
          'productName': product.name,
          'supplierBatchNumber': allocation.supplierBatchNumber,
          'manufacturingDate': allocation.manufacturingDate?.toIso8601String(),
          'expirationDate': allocation.expirationDate?.toIso8601String(),
          'status': 'active',
          'sourceType': sourceType,
          'sourceId': sourceId,
          'sourceLineId': resolvedSourceLineId,
          'unitCost': allocation.unitCost > 0 ? allocation.unitCost : unitCost,
          'initialQuantity': allocation.quantity,
          'costCurrency': 'USD',
          'exchangeRate': 1,
          'receivedAt': (receivedAt ?? now).toIso8601String(),
          'storeId': appIdentity.storeId,
          'branchId': appIdentity.branchId,
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
          'deviceId': _deviceId,
          'lastModifiedByDeviceId': _deviceId,
          'syncStatus': 'pending',
          'version': 1,
        },
      );
    }
  }

  Future<void> adjustExpiryBatchStock({
    required String productId,
    required String warehouseId,
    required String batchId,
    required double quantityDelta,
    required String reason,
    String adjustmentCategory = 'other',
  }) async {
    requirePermission(AppPermission.inventoryCorrectionsManage);
    if (quantityDelta == 0) return;
    final product = _findProductById(productId);
    if (product == null || !product.trackStock) {
      throw const LocalizedDomainException(
          'error_batch_requires_stock_tracking',
          fallback: 'Stock-tracked product not found.');
    }
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw const LocalizedDomainException('error_batch_database_required',
          fallback: 'Batch management requires the local database.');
    }
    final now = DateTime.now();
    final operationId = '${now.microsecondsSinceEpoch}-$batchId-batch-adjust';
    final warehouse = resolveWarehouseForPurchase(warehouseId: warehouseId);
    var movement = StockMovement(
      id: operationId,
      productId: product.id,
      productName: product.name,
      type: quantityDelta < 0 ? 'inventory_loss' : 'count_adjustment',
      quantity: quantityDelta,
      date: now,
      referenceId: batchId,
      referenceNo: product.code,
      reason: reason,
      adjustmentCategory: adjustmentCategory,
      warehouseId: warehouse.id,
      warehouseName: warehouse.name,
      batchId: batchId,
      movementGroupId: operationId,
      documentLineId: '$operationId-line',
      idempotencyKey: '$operationId-movement',
      unitCost: 0,
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      lastModifiedByDeviceId: _deviceId,
    );
    final batchService = BatchInventoryService(db);
    await db.transaction(() async {
      await _ensureUnifiedBatchCutoverForProductInTransaction(
        db,
        product: product,
        warehouseId: warehouse.id,
        at: now,
      );
      final batchRow = await db.customSelect(
        '''
        SELECT unit_cost
        FROM inventory_batches
        WHERE id = ? AND product_id = ? AND store_id = ?
        LIMIT 1
        ''',
        variables: <Variable<Object>>[
          Variable<String>(batchId),
          Variable<String>(product.id),
          Variable<String>(appIdentity.storeId),
        ],
      ).getSingleOrNull();
      if (batchRow == null) {
        throw StateError('Inventory batch was not found.');
      }
      final unitCost = (batchRow.data['unit_cost'] as num? ?? 0).toDouble();
      movement = movement.copyWith(unitCost: unitCost);
      await batchService.adjustUnifiedBatchInTransaction(
        product: product,
        warehouseId: warehouse.id,
        batchId: batchId,
        quantityDelta: quantityDelta,
        adjustedAt: now,
        storeId: appIdentity.storeId,
        deviceId: _deviceId,
      );
      final normalizedCategory = adjustmentCategory.trim().toLowerCase();
      final isExplicitExpiryDisposal = quantityDelta < 0 &&
          <String>{'expired', 'expiry'}.contains(normalizedCategory);
      if (isExplicitExpiryDisposal) {
        final expiryJournalId = await AccountingService.recordInventoryWaste(
          entryDate: now,
          referenceId: operationId,
          referenceNo: product.code,
          amount: quantityDelta.abs() * unitCost,
          productName: product.name,
          productId: product.id,
          createdBy: _activeUser?.fullName ?? _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          notes: reason,
          expenseRoleKey: 'inventory_expiry',
          database: db,
          withinExistingTransaction: true,
        );
        if (expiryJournalId.trim().isEmpty) {
          throw StateError(
              'Expiry stock loss requires a posted accounting journal.');
        }
        await _requirePostedJournalInTransaction(
          db,
          referenceType: 'inventory_waste',
          referenceId: operationId,
          failureMessage:
              'Expiry stock loss journal was not persisted; the adjustment was rolled back.',
        );
      } else {
        final adjustmentJournalId = await AccountingService
            .recordManualInventoryAdjustmentInTransaction(
          database: db,
          entryDate: now,
          referenceId: operationId,
          referenceNo: product.code,
          productId: product.id,
          productName: product.name,
          quantityDelta: quantityDelta,
          value: quantityDelta * unitCost,
          adjustmentCategory: adjustmentCategory,
          reason: reason,
          createdBy: _activeUser?.fullName ?? _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
        );
        if (adjustmentJournalId.trim().isEmpty) {
          throw StateError(
              'Batch inventory adjustment requires a posted accounting journal.');
        }
        await _requirePostedJournalInTransaction(
          db,
          referenceType: 'inventory_adjustment',
          referenceId: operationId,
          failureMessage:
              'Batch inventory adjustment journal was not persisted; the adjustment was rolled back.',
        );
      }
      await StockTransactionService(
        db,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
      ).recordMovementsInTransaction(
        operationType: 'batch_adjustment',
        documentType: 'inventory_batch',
        documentId: batchId,
        movementGroupId: operationId,
        idempotencyKey: '$operationId-op',
        movements: <StockMovement>[movement],
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        deviceId: _deviceId,
      );
      await batchService.assertWarehouseBatchBalanceInTransaction(
        productId: product.id,
        warehouseId: warehouse.id,
        storeId: appIdentity.storeId,
      );
    });
    _mirrorAuthoritativeStockMovements(<StockMovement>[movement]);
    await _refreshProductStockCompatibilityCache(<String>[productId]);
    _inventoryCostLayers
      ..clear()
      ..addAll(await BusinessSqliteStore.readInventoryCostLayers(db));
    _rebuildInventoryCostLayerLookupCache();
    _recordSyncChange(
      entityType: 'stock_movement',
      entityId: movement.id,
      operation: 'adjust_batch',
      payload: movement.toJson(),
    );
    notifyListeners();
  }
}
