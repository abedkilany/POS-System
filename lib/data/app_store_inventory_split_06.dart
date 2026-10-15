part of 'app_store.dart';

extension _AppStoreSplitInventoryPart6 on AppStore {
  Future<void> deleteWasteLoss(String movementId) async {
    requirePermission(AppPermission.inventoryWasteManage);
    final index = _stockMovements.indexWhere((item) => item.id == movementId);
    if (index == -1) throw ArgumentError('Waste movement not found.');
    final original = _stockMovements[index];
    // `waste` is canonical; `inventory_loss` remains supported for legacy data.
    if (!<String>{'waste', 'inventory_loss'}.contains(original.type)) {
      throw StateError('Only waste movements can be deleted safely.');
    }
    if (original.movementGroupId.isNotEmpty &&
        _stockMovements
                .where((item) =>
                    item.movementGroupId == original.movementGroupId &&
                    item.reversalOfMovementId.isEmpty)
                .length >
            1) {
      return reverseWasteLossGroup(movementId);
    }
    if (original.reversalOfMovementId.isNotEmpty ||
        _stockMovements.any(
          (item) => item.reversalOfMovementId == original.id,
        )) {
      throw StateError('This waste movement has already been reversed.');
    }

    final now = DateTime.now();
    final reversal = original.copyWith(
      id: 'reversal_${original.id}',
      type: 'inventory_loss_reversal',
      quantity: -original.quantity,
      reason: 'حذف آمن لحركة الهدر',
      sourceMovementId: original.id,
      reversalOfMovementId: original.id,
      movementGroupId: 'reversal-${original.id}',
      idempotencyKey: 'reversal:${original.id}',
      date: now,
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      lastModifiedByDeviceId: _deviceId,
    );
    final db = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && db != null) {
      final stockService = StockTransactionService(
        db,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
      );
      await db.transaction(() async {
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
          final restoredLayer = InventoryCostLayer(
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
          );
          await BusinessSqliteStore.upsertEntityPayloads(
            db,
            AppStore._inventoryCostLayersKey,
            <Map<String, dynamic>>[restoredLayer.toJson()],
            sortIndices: const <int?>[0],
          );
        }
        await stockService.recordReversalInTransaction(
          originalMovement: original,
          operationType: 'inventory_waste_reversal',
          documentType: 'inventory_waste',
          documentId: original.movementGroupId.isEmpty
              ? original.id
              : original.movementGroupId,
          reason: 'حذف آمن لحركة الهدر',
          reversalMovementId: reversal.id,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          deviceId: _deviceId,
          syncTarget: _stockTransactionSyncTarget,
        );
        if (original.batchId.isNotEmpty) {
          await BatchInventoryService(db)
              .assertWarehouseBatchBalanceInTransaction(
            productId: original.productId,
            warehouseId: original.warehouseId,
            storeId: appIdentity.storeId,
          );
        }
        final wasteReferenceId = original.movementGroupId.isEmpty
            ? original.id
            : original.movementGroupId;
        await _requirePostedJournalInTransaction(
          db,
          referenceType: 'inventory_waste',
          referenceId: wasteReferenceId,
          failureMessage:
              'Waste journal is missing; the safe delete was rolled back.',
        );
        await AccountingService.reverseEntryForReference(
          referenceType: 'inventory_waste',
          referenceId: wasteReferenceId,
          reason: 'حذف آمن لحركة الهدر',
          createdBy: _deviceId,
          notifyChange: false,
          withinExistingTransaction: true,
        );
        await _requireNoActiveJournalInTransaction(
          db,
          referenceType: 'inventory_waste',
          referenceId: wasteReferenceId,
          failureMessage:
              'Waste journal reversal did not complete; the safe delete was rolled back.',
        );
      });
      _mirrorAuthoritativeStockMovements(<StockMovement>[reversal]);
      await _refreshProductStockCompatibilityCache(
          <String>[original.productId]);
      _inventoryCostLayers
        ..clear()
        ..addAll(await BusinessSqliteStore.readInventoryCostLayers(db));
      _rebuildInventoryCostLayerLookupCache();
      _recordSyncChange(
        entityType: 'stock_movement',
        entityId: reversal.id,
        operation: 'reverse_waste',
        payload: reversal.toJson(),
      );
      AccountingService.notifyCommittedMutation();
      notifyListeners();
      return;
    }

    final productIndex = _productIndexById[original.productId];
    if (productIndex != null) {
      final product = _products[productIndex];
      _products[productIndex] = _withSyncMeta<Product>(
        product.copyWith(stock: product.stock - original.quantity),
        now,
      );
    }
    _addStockMovement(reversal, recordSync: true);
    await AccountingService.reverseEntryForReference(
      referenceType: 'inventory_waste',
      referenceId: original.movementGroupId.isEmpty
          ? original.id
          : original.movementGroupId,
      reason: 'حذف آمن لحركة الهدر',
      createdBy: _deviceId,
    );
    await _saveDirty(
      products: productIndex != null,
      productDerivedData: false,
      stockMovements: true,
      sync: true,
    );
    notifyListeners();
  }

  void _applyPurchaseStock(Purchase purchase, DateTime now) {
    for (var lineIndex = 0; lineIndex < purchase.items.length; lineIndex += 1) {
      final item = purchase.items[lineIndex];
      final index = _productIndexById[item.productId];
      if (index == null) continue;
      final product = _products[index];
      if (!product.trackStock) continue;
      final receivedQty = item.baseQuantity;
      final newStock = product.stock + receivedQty;
      final baseUnitCost = item.unitCostPerBase;
      _upsertProductCostFromPurchase(
        product: product,
        receivedQty: receivedQty,
        baseUnitCost: baseUnitCost,
        now: now,
      );
      _addInventoryCostLayerFromPurchase(
        purchase: purchase,
        item: item,
        lineIndex: lineIndex,
        quantity: receivedQty,
        unitCost: baseUnitCost,
        now: now,
      );
      _products[index] = _withSyncMeta<Product>(
        product.copyWith(stock: newStock),
        now,
      );
      _addStockMovement(
        StockMovement(
          id: '${purchase.id}-$lineIndex-${item.productId}-purchase-receive',
          productId: item.productId,
          productName: item.productName,
          type: 'purchase_receive',
          quantity: item.baseQuantity,
          date: now,
          referenceId: purchase.id,
          referenceNo: purchase.purchaseNo,
          reason: 'Purchase received',
          unitCost: item.unitCostPerBase,
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
  }

  void _addStockMovement(StockMovement movement, {bool recordSync = false}) {
    final index = _stockMovementIndexForId(movement.id);
    if (index != -1) return;
    _putStockMovementAtIndex(movement, _stockMovements.length);
    if (recordSync) {
      _recordSyncChange(
        entityType: 'stock_movement',
        entityId: movement.id,
        operation: movement.type,
        payload: movement.toJson(),
      );
    }
  }

  Future<void> _reconcileInventoryAccountsAfterBomChange(
    BillOfMaterials bom, {
    VentioDriftDatabase? database,
    bool withinExistingTransaction = false,
  }) async {
    if (kIsWeb ||
        !LocalDatabaseService.isSqliteAuthoritative ||
        !AccountingService.isAvailable) {
      return;
    }
    final reconciled =
        await AccountingService.reconcileInventoryAccountClassification(
      referenceContext: 'bom:${bom.id}:v${bom.version}',
      database: database,
      withinExistingTransaction: withinExistingTransaction,
    );
    if (!reconciled) {
      // Temporary controlled deferral: the BOM itself is valid and can be
      // saved, while the inventory account classification journal waits for
      // the user's final stock count and valuation audit. Other inventory
      // mutations still run their normal reconciliation guards.
      await AccountingService.deferBomInventoryAccountReconciliation(
        referenceContext: 'bom:${bom.id}:v${bom.version}',
        database: database,
      );
    }
  }
}
