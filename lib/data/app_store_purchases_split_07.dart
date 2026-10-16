part of 'app_store.dart';

extension _AppStoreSplitPurchasesPart7 on AppStore {
  Future<void> returnPurchase(
    String id, {
    bool reverseStock = true,
    String reason = '',
    bool recordSupplierReturnLedger = true,
  }) async {
    requirePermission(AppPermission.purchasesCancel);
    _requireSensitiveActionAuthorization(SensitiveAction.purchaseReverse);
    final index = _purchaseIndexForId(id);
    final purchase =
        index == -1 ? await _purchaseByIdFromSqlite(id) : _purchases[index];
    if (purchase == null) throw ArgumentError('Purchase not found.');
    if (purchase.isCancelled) return;
    if (!purchase.isReceived) {
      throw StateError(
        'Only received purchase invoices can be returned. Delete draft invoices instead.',
      );
    }
    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      final partialReturnRow = await sqliteDb.customSelect(
        '''
        SELECT 1 AS found
        FROM purchases
        WHERE document_type = 'purchase_return'
          AND source_purchase_id = ?
          AND deleted_at = ''
          AND lower(status) NOT IN ('cancelled', 'returned')
        LIMIT 1
        ''',
        variables: <Variable<Object>>[Variable<String>(purchase.id)],
      ).getSingleOrNull();
      if (partialReturnRow != null) {
        throw StateError(
          'This purchase already has a partial return. Create another return invoice for the remaining quantity.',
        );
      }
    }
    // A purchase return reverses inventory/accounting only. It does not pay
    // cash out of the drawer, so the original purchase payment must never be
    // revalidated here. Any cash received back from the supplier is posted
    // separately through refundPurchaseCash() as a Cash In operation.
    await _waitForPendingPurchaseAccounting(purchase.id);
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      final now = DateTime.now();
      var reversalApplied = purchase.reversalApplied;
      final stockService = StockTransactionService(
        sqliteDb,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => false,
      );
      late Purchase returned;
      await sqliteDb.transaction(() async {
        if (reverseStock && !purchase.reversalApplied) {
          await _requirePurchaseBatchesUnusedInTransaction(sqliteDb, purchase);
          await _closeInventoryCostLayersForPurchaseInTransaction(
            sqliteDb,
            purchase,
            now,
          );
          for (var lineIndex = 0;
              lineIndex < purchase.items.length;
              lineIndex += 1) {
            final item = purchase.items[lineIndex];
            final product = _findProductById(item.productId);
            if (product == null) {
              throw StateError('Product ${item.productId} was not found.');
            }
            if (!product.trackStock) continue;
            var originalMovements = await _activePurchaseReceiveMovements(
              sqliteDb,
              purchaseId: purchase.id,
              productId: item.productId,
              documentLineId: _stablePurchaseLineId(purchase, item, lineIndex),
            );
            if (originalMovements.isEmpty) {
              originalMovements = await _activePurchaseReceiveMovements(
                sqliteDb,
                purchaseId: purchase.id,
                productId: item.productId,
                documentLineId: '${purchase.id}-line-$lineIndex',
              );
            }
            if (originalMovements.isEmpty) {
              throw StateError(
                'Active stock receipt is missing for ${purchase.purchaseNo}, line $lineIndex.',
              );
            }
            final activeReceivedQuantity = originalMovements.fold<double>(
              0,
              (sum, movement) => sum + movement.quantity,
            );
            if ((activeReceivedQuantity - item.baseQuantity).abs() > 0.000001) {
              throw StateError(
                'Active stock receipt quantity mismatch for ${purchase.purchaseNo}, line $lineIndex.',
              );
            }
            final batchService = BatchInventoryService(sqliteDb);
            for (final originalMovement in originalMovements) {
              if (originalMovement.batchId.trim().isNotEmpty) {
                await batchService.adjustUnifiedBatchInTransaction(
                  product: product,
                  warehouseId: originalMovement.warehouseId,
                  batchId: originalMovement.batchId,
                  quantityDelta: -originalMovement.quantity,
                  adjustedAt: now,
                  storeId: appIdentity.storeId,
                  deviceId: _deviceId,
                );
              }
              await stockService.recordReversalInTransaction(
                originalMovement: originalMovement,
                operationType: 'purchase_return',
                documentType: 'purchase',
                documentId: purchase.id,
                reason:
                    reason.trim().isEmpty ? 'Purchase returned' : reason.trim(),
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                deviceId: _deviceId,
              );
              if (originalMovement.batchId.trim().isNotEmpty) {
                await batchService.assertWarehouseBatchBalanceInTransaction(
                  productId: item.productId,
                  warehouseId: originalMovement.warehouseId.trim().isEmpty
                      ? Warehouse.defaultId
                      : originalMovement.warehouseId.trim(),
                  storeId: appIdentity.storeId,
                );
              }
            }
          }
          reversalApplied = true;
        }
        returned = _purchaseSyncMetaPreview(
          purchase.copyWith(
            status: 'Returned',
            cancelledAt: now,
            cancelledByDeviceId: _deviceId,
            cancelReason: reason.trim(),
            reversalApplied: reversalApplied,
            note: 'Returned on ${now.toIso8601String()}',
          ),
          now,
        );
        await BusinessSqliteStore.upsertEntityPayloads(
          sqliteDb,
          AppStore._purchasesKey,
          <Map<String, dynamic>>[returned.toJson()],
          sortIndices: <int?>[0],
        );
        await _requirePostedJournalInTransaction(
          sqliteDb,
          referenceType: 'purchase',
          referenceId: purchase.id,
          includePurchaseEditFamily: true,
          failureMessage:
              'Active purchase journal is missing; purchase return was rolled back.',
        );
        await AccountingService.reversePurchaseEntriesForPurchase(
          purchaseId: purchase.id,
          reason: reason.trim().isEmpty ? 'Purchase returned' : reason.trim(),
          createdBy: _deviceId,
          adjustCashLocationBalance: false,
          notifyChange: false,
          withinExistingTransaction: true,
        );
        await _requireNoActiveJournalInTransaction(
          sqliteDb,
          referenceType: 'purchase',
          referenceId: purchase.id,
          includePurchaseEditFamily: true,
          failureMessage:
              'Purchase journal reversal did not complete; purchase return was rolled back.',
        );
        if (recordSupplierReturnLedger &&
            purchase.supplierId.trim().isNotEmpty &&
            purchase.subtotal > 0) {
          await _persistAccountTransactionInExistingTransaction(
            sqliteDb,
            AccountTransaction(
              id: '${purchase.id}-purchase-return',
              accountType: 'supplier',
              accountId: purchase.supplierId,
              accountName: purchase.supplierName,
              date: now,
              type: 'purchaseReturn',
              referenceId: purchase.id,
              referenceNo: purchase.purchaseNo,
              debit: purchase.subtotal,
              note: reason.trim().isEmpty
                  ? 'Purchase return ${purchase.purchaseNo}'
                  : reason.trim(),
              createdAt: now,
              updatedAt: now,
              deviceId: _deviceId,
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              lastModifiedByDeviceId: _deviceId,
            ),
          );
        }
      });
      if (index != -1) {
        _putPurchaseAtIndex(returned, index);
      } else {
        _putPurchaseAtIndex(returned, _purchases.length);
      }
      _recordSyncChange(
        entityType: 'purchase',
        entityId: id,
        operation: 'return',
        payload: returned.toJson(),
      );
      // Refresh the derived product inventory projection from authoritative warehouse stock
      // before refreshing product rows. This keeps the in-memory projection aligned
      // immediately without relying on a later dirty-row flush.
      await _refreshProductStockCompatibilityCache(
        purchase.items.map((item) => item.productId),
      );
      // Return ledger and FIFO changes were committed inside the same SQLite
      // transaction, so only product-metadata/sync rows remain to be flushed.
      await _saveDirty(
        purchases: false,
        products: reverseStock && !purchase.reversalApplied,
        productDerivedData: false,
        stockMovements: false,
        accountTransactions: false,
        sync: true,
      );
      await refreshAfterDatabaseChange(AppStore._inventoryCostLayersKey);
      await refreshAfterDatabaseChange(AppStore._stockMovementsKey);
      await _refreshAccountTransactionsFromSqlite();
      _touchPurchasesData();
      notifyListeners();
      return;
    }
    final now = DateTime.now();
    var reversalApplied = purchase.reversalApplied;
    if (reverseStock && !purchase.reversalApplied) {
      if (_inventoryCostingMethod == InventoryCostingMethod.fifo &&
          _purchaseHasConsumedCostLayers(purchase.id)) {
        throw StateError(
            'Cannot reverse this purchase after FIFO layers have been consumed by sales. Return/cancel the related sales first or create a stock revaluation.');
      }
      for (var lineIndex = 0;
          lineIndex < purchase.items.length;
          lineIndex += 1) {
        final item = purchase.items[lineIndex];
        final productIndex = _productIndexById[item.productId];
        if (productIndex == null) continue;
        final product = _products[productIndex];
        if (!product.trackStock) continue;
        final qty = -item.baseQuantity;
        if (!_storeProfile.allowNegativeStock &&
            product.stock + qty < -0.000001) {
          throw StateError('Insufficient stock in ${product.name}.');
        }
        _products[productIndex] = _withSyncMeta<Product>(
          product.copyWith(stock: product.stock + qty),
          now,
        );
        _addStockMovement(
          StockMovement(
            id: '${purchase.id}-$lineIndex-${item.productId}-purchase-return',
            productId: item.productId,
            productName: item.productName,
            type: 'purchase_return',
            quantity: qty,
            date: now,
            referenceId: purchase.id,
            referenceNo: purchase.purchaseNo,
            reason: reason.trim().isEmpty ? 'Purchase returned' : reason.trim(),
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
      _closeInventoryCostLayersForPurchase(purchase.id, now);
      reversalApplied = true;
    }
    final returned = _withSyncMeta<Purchase>(
      purchase.copyWith(
        status: 'Returned',
        cancelledAt: now,
        cancelledByDeviceId: _deviceId,
        cancelReason: reason.trim(),
        reversalApplied: reversalApplied,
        note: 'Returned on ${now.toIso8601String()}',
      ),
      now,
    );
    if (index != -1) _putPurchaseAtIndex(returned, index);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: id,
      operation: 'return',
      payload: returned.toJson(),
    );
    await AccountingService.reversePurchaseEntriesForPurchase(
      purchaseId: purchase.id,
      reason: reason.trim().isEmpty ? 'Purchase returned' : reason.trim(),
      createdBy: _deviceId,
      adjustCashLocationBalance: false,
    );
    if (recordSupplierReturnLedger) {
      await _recordPurchaseCancelLedger(purchase, now,
          reason: reason, isReturn: true);
    }
    await _saveDirty(
      purchases: true,
      products: reverseStock && !purchase.reversalApplied,
      stockMovements: reverseStock && !purchase.reversalApplied,
      accountTransactions: true,
      sync: true,
    );
    unawaited(
      AppLogger.info(
        area: 'purchases',
        action: 'return_purchase',
        message: 'Purchase returned successfully.',
        details:
            'purchaseId=$id purchaseNo=${purchase.purchaseNo} reverseStock=$reverseStock',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'purchase',
        entityId: id,
        action: 'return',
        summary: 'Purchase returned',
        details: jsonEncode(returned.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'purchases',
        isImportant: true,
      ),
    );
    _touchPurchasesData();
    notifyListeners();
  }

  Future<void> cancelPurchase(
    String id, {
    bool reverseStock = true,
    String reason = '',
  }) async {
    requirePermission(AppPermission.purchasesCancel);
    _requireSensitiveActionAuthorization(SensitiveAction.purchaseReverse);
    final index = _purchaseIndexForId(id);
    final purchase =
        index == -1 ? await _purchaseByIdFromSqlite(id) : _purchases[index];
    if (purchase == null) throw ArgumentError('Purchase not found.');
    if (purchase.isCancelled) return;
    if (!purchase.isReceived) {
      throw StateError(
        'Only received purchase invoices can be cancelled. Delete draft invoices instead.',
      );
    }
    // Cancelling a received purchase reverses its business/accounting effect;
    // it is not a new cash payment. Cash recovery from a supplier is handled
    // explicitly by the supplier-refund Cash In workflow.
    final sqliteDb = SqliteMigrationManager.database;
    await _waitForPendingPurchaseAccounting(purchase.id);
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      final now = DateTime.now();
      var reversalApplied = purchase.reversalApplied;
      final stockService = StockTransactionService(
        sqliteDb,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => false,
      );
      await sqliteDb.transaction(() async {
        if (reverseStock && !purchase.reversalApplied) {
          await _requirePurchaseBatchesUnusedInTransaction(sqliteDb, purchase);
          await _closeInventoryCostLayersForPurchaseInTransaction(
            sqliteDb,
            purchase,
            now,
          );
          for (var lineIndex = 0;
              lineIndex < purchase.items.length;
              lineIndex += 1) {
            final item = purchase.items[lineIndex];
            final product = _findProductById(item.productId);
            if (product == null) {
              throw StateError('Product ${item.productId} was not found.');
            }
            if (!product.trackStock) continue;
            var originalMovements = await _activePurchaseReceiveMovements(
              sqliteDb,
              purchaseId: purchase.id,
              productId: item.productId,
              documentLineId: _stablePurchaseLineId(purchase, item, lineIndex),
            );
            if (originalMovements.isEmpty) {
              originalMovements = await _activePurchaseReceiveMovements(
                sqliteDb,
                purchaseId: purchase.id,
                productId: item.productId,
                documentLineId: '${purchase.id}-line-$lineIndex',
              );
            }
            if (originalMovements.isEmpty) {
              throw StateError(
                'Active stock receipt is missing for ${purchase.purchaseNo}, line $lineIndex.',
              );
            }
            final activeReceivedQuantity = originalMovements.fold<double>(
              0,
              (sum, movement) => sum + movement.quantity,
            );
            if ((activeReceivedQuantity - item.baseQuantity).abs() > 0.000001) {
              throw StateError(
                'Active stock receipt quantity mismatch for ${purchase.purchaseNo}, line $lineIndex.',
              );
            }
            final batchService = BatchInventoryService(sqliteDb);
            for (final originalMovement in originalMovements) {
              if (originalMovement.batchId.trim().isNotEmpty) {
                await batchService.adjustUnifiedBatchInTransaction(
                  product: product,
                  warehouseId: originalMovement.warehouseId,
                  batchId: originalMovement.batchId,
                  quantityDelta: -originalMovement.quantity,
                  adjustedAt: now,
                  storeId: appIdentity.storeId,
                  deviceId: _deviceId,
                );
              }
              await stockService.recordReversalInTransaction(
                originalMovement: originalMovement,
                operationType: 'purchase_cancel',
                documentType: 'purchase',
                documentId: purchase.id,
                reason: reason.trim().isEmpty
                    ? 'Purchase cancelled'
                    : reason.trim(),
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                deviceId: _deviceId,
              );
              if (originalMovement.batchId.trim().isNotEmpty) {
                await batchService.assertWarehouseBatchBalanceInTransaction(
                  productId: item.productId,
                  warehouseId: originalMovement.warehouseId.trim().isEmpty
                      ? Warehouse.defaultId
                      : originalMovement.warehouseId.trim(),
                  storeId: appIdentity.storeId,
                );
              }
            }
          }
          reversalApplied = true;
        }
        final cancelled = _purchaseSyncMetaPreview(
          purchase.copyWith(
            status: 'Cancelled',
            cancelledAt: now,
            cancelledByDeviceId: _deviceId,
            cancelReason: reason.trim(),
            reversalApplied: reversalApplied,
          ),
          now,
        );
        await _requirePostedJournalInTransaction(
          sqliteDb,
          referenceType: 'purchase',
          referenceId: purchase.id,
          includePurchaseEditFamily: true,
          failureMessage:
              'Active purchase journal is missing; purchase cancellation was rolled back.',
        );
        await AccountingService.reversePurchaseEntriesForPurchase(
          purchaseId: purchase.id,
          reason: reason.trim().isEmpty ? 'Purchase cancelled' : reason.trim(),
          createdBy: _deviceId,
          notifyChange: false,
          withinExistingTransaction: true,
        );
        await _requireNoActiveJournalInTransaction(
          sqliteDb,
          referenceType: 'purchase',
          referenceId: purchase.id,
          includePurchaseEditFamily: true,
          failureMessage:
              'Purchase journal reversal did not complete; purchase cancellation was rolled back.',
        );
        await BusinessSqliteStore.upsertEntityPayloads(
          sqliteDb,
          AppStore._purchasesKey,
          <Map<String, dynamic>>[cancelled.toJson()],
          sortIndices: <int?>[0],
        );
        if (purchase.supplierId.trim().isNotEmpty && purchase.subtotal > 0) {
          await _persistAccountTransactionInExistingTransaction(
            sqliteDb,
            AccountTransaction(
              id: '${purchase.id}-purchase-cancel',
              accountType: 'supplier',
              accountId: purchase.supplierId,
              accountName: purchase.supplierName,
              date: now,
              type: 'cancel',
              referenceId: purchase.id,
              referenceNo: purchase.purchaseNo,
              debit: purchase.subtotal,
              note:
                  reason.trim().isEmpty ? 'Purchase cancelled' : reason.trim(),
              createdAt: now,
              updatedAt: now,
              deviceId: _deviceId,
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              lastModifiedByDeviceId: _deviceId,
            ),
          );
        }
      });
      final cancelled = _purchaseSyncMetaPreview(
        purchase.copyWith(
          status: 'Cancelled',
          cancelledAt: now,
          cancelledByDeviceId: _deviceId,
          cancelReason: reason.trim(),
          reversalApplied: reversalApplied,
        ),
        now,
      );
      if (index != -1) {
        _putPurchaseAtIndex(cancelled, index);
      } else {
        _putPurchaseAtIndex(cancelled, _purchases.length);
      }
      _recordSyncChange(
        entityType: 'purchase',
        entityId: id,
        operation: 'cancel',
        payload: cancelled.toJson(),
      );
      // Refresh the derived product inventory projection from authoritative warehouse stock
      // before persisting product rows. This avoids leaving a RAM-only cache
      // update after a fully committed purchase cancellation.
      await _refreshProductStockCompatibilityCache(
        purchase.items.map((item) => item.productId),
      );
      // Cancel ledger and FIFO changes were committed inside the same SQLite
      // transaction, so only product-metadata/sync rows remain to be flushed.
      await _saveDirty(
        purchases: false,
        products: reverseStock && !purchase.reversalApplied,
        productDerivedData: false,
        stockMovements: false,
        accountTransactions: false,
        sync: true,
      );
      await refreshAfterDatabaseChange(AppStore._inventoryCostLayersKey);
      await refreshAfterDatabaseChange(AppStore._stockMovementsKey);
      await _refreshAccountTransactionsFromSqlite();
      _touchPurchasesData();
      notifyListeners();
      return;
    }
    final now = DateTime.now();
    var reversalApplied = purchase.reversalApplied;
    if (reverseStock && purchase.isReceived && !purchase.reversalApplied) {
      if (_inventoryCostingMethod == InventoryCostingMethod.fifo &&
          _purchaseHasConsumedCostLayers(purchase.id)) {
        throw StateError(
            'Cannot reverse this purchase after FIFO layers have been consumed by sales. Return/cancel the related sales first or create a stock revaluation.');
      }
      for (var lineIndex = 0;
          lineIndex < purchase.items.length;
          lineIndex += 1) {
        final item = purchase.items[lineIndex];
        final productIndex = _productIndexById[item.productId];
        if (productIndex == null) continue;
        final product = _products[productIndex];
        if (!product.trackStock) continue;
        final qty = -item.baseQuantity;
        if (!_storeProfile.allowNegativeStock &&
            product.stock + qty < -0.000001) {
          throw StateError('Insufficient stock in ${product.name}.');
        }
        _products[productIndex] = _withSyncMeta<Product>(
          product.copyWith(stock: product.stock + qty),
          now,
        );
        _addStockMovement(
          StockMovement(
            id: '${purchase.id}-$lineIndex-${item.productId}-purchase-cancel',
            productId: item.productId,
            productName: item.productName,
            type: 'purchase_cancel',
            quantity: qty,
            date: now,
            referenceId: purchase.id,
            referenceNo: purchase.purchaseNo,
            reason:
                reason.trim().isEmpty ? 'Purchase cancelled' : reason.trim(),
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
      _closeInventoryCostLayersForPurchase(purchase.id, now);
      reversalApplied = true;
    }
    final cancelled = _withSyncMeta<Purchase>(
      purchase.copyWith(
        status: 'Cancelled',
        cancelledAt: now,
        cancelledByDeviceId: _deviceId,
        cancelReason: reason.trim(),
        reversalApplied: reversalApplied,
      ),
      now,
    );
    if (index != -1) _putPurchaseAtIndex(cancelled, index);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: id,
      operation: 'cancel',
      payload: cancelled.toJson(),
    );
    await _recordPurchaseCancelLedger(purchase, now, reason: reason);
    await _waitForPendingPurchaseAccounting(purchase.id);
    await AccountingService.reversePurchaseEntriesForPurchase(
      purchaseId: purchase.id,
      reason: reason.trim().isEmpty ? 'Purchase cancelled' : reason.trim(),
      createdBy: _deviceId,
    );
    await _saveDirty(
      purchases: true,
      products: reverseStock && !purchase.reversalApplied,
      stockMovements: reverseStock && !purchase.reversalApplied,
      accountTransactions: true,
      sync: true,
    );
    unawaited(
      AppLogger.info(
        area: 'purchases',
        action: 'cancel_purchase',
        message: 'Purchase cancelled successfully.',
        details:
            'purchaseId=$id purchaseNo=${purchase.purchaseNo} reverseStock=$reverseStock',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'purchase',
        entityId: id,
        action: 'cancel',
        summary: 'Purchase cancelled',
        details: jsonEncode(cancelled.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'purchases',
        isImportant: true,
      ),
    );
    _touchPurchasesData();
    notifyListeners();
  }
}
