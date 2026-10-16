part of 'app_store.dart';

extension _AppStoreSplitSalesReturnsPart8 on AppStore {
  Future<void> cancelSale(
    String id, {
    String status = 'Cancelled',
    bool restoreStock = true,
  }) async {
    requirePermission(AppPermission.salesCancel);
    _requireSensitiveActionAuthorization(SensitiveAction.saleReverse);
    final index = _sales.indexWhere((sale) => sale.id == id);
    final sale = index == -1 ? await _saleByIdFromSqlite(id) : _sales[index];
    if (sale == null) {
      throw ArgumentError('Sale not found.');
    }
    if (sale.isCancelled) return;
    final returnedQuantities = await _returnedSaleQuantitiesByProduct(sale.id);
    if (returnedQuantities.values.any((quantity) => quantity > 0.000001)) {
      throw StateError(
        'Cannot cancel a sale after a return has been posted. Return the remaining quantities or reverse the return workflow first.',
      );
    }

    var cancelJournalReversedInSqliteTransaction = false;

    final now = DateTime.now();
    final cancelledSaleBase = sale.copyWith(
      status: status,
      paymentStatus: 'cancelled',
      paidAmount: 0,
      cashReceivedAmount: 0,
      paidAmountInPaymentCurrency: 0,
      cashReceivedAmountInPaymentCurrency: 0,
      paidBaseAmount: 0,
      exchangeDifferenceAmount: 0,
      note: 'Stock restored on ${now.toIso8601String()}',
    );
    var cancelledSale = _saleSyncMetaPreview(cancelledSaleBase, now);
    if (restoreStock) {
      final sqliteDb = SqliteMigrationManager.database;
      if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
        final stockService = StockTransactionService(
          sqliteDb,
          deviceId: _deviceId,
          defaultStoreId: appIdentity.storeId,
          defaultBranchId: appIdentity.branchId,
          defaultSyncTarget: _stockTransactionSyncTarget,
          allowNegativeStockResolver: (_, __) =>
              _storeProfile.allowNegativeStock,
        );
        final batchService = BatchInventoryService(sqliteDb);
        await sqliteDb.transaction(() async {
          // Validate reversibility inside the transaction before restoring
          // batches/cost layers. This prevents concurrent cancel/return calls
          // from restoring the same sold quantity twice.
          for (var lineIndex = 0;
              lineIndex < sale.items.length;
              lineIndex += 1) {
            final item = sale.items[lineIndex];
            final product = _findProductForHistoricalSale(item.productId);
            if (product == null) {
              throw StateError('Product ${item.productId} was not found.');
            }
            if (!product.trackStock) continue;
            final movementAllocations = item.batchAllocations.isEmpty
                ? <BatchAllocation>[
                    BatchAllocation(
                      batchId: '',
                      quantity: item.effectiveBaseQuantity,
                    )
                  ]
                : item.batchAllocations;
            for (final allocation in movementAllocations) {
              final hasBatch = allocation.batchId.isNotEmpty;
              final sourceMovementId = _saleStockMovementId(
                sale: sale,
                item: item,
                allocation: allocation,
                lineIndex: lineIndex,
              );
              final reversible =
                  await _remainingReversibleStockQuantityInTransaction(
                sqliteDb,
                sourceMovementId,
              );
              if (reversible == null) {
                if (hasBatch) {
                  throw StateError(
                    'Original unified-batch sale movement is missing; sale cancellation was rolled back.',
                  );
                }
                continue;
              }
              if (allocation.quantity > reversible + 0.000001) {
                throw StateError(
                  'Cannot cancel this sale because some stock has already been returned or reversed.',
                );
              }
            }
          }

          final legacyCostItems = sale.items
              .where((item) =>
                  item.batchAllocations.isEmpty &&
                  (_findProductForHistoricalSale(item.productId)?.trackStock ??
                      false))
              .toList(growable: false);
          if (legacyCostItems.isNotEmpty) {
            await _restoreInventoryCostLayersFromSaleItemsInTransaction(
              sqliteDb,
              legacyCostItems,
              now,
              originalSaleDate: sale.date,
              restorationSourceType: 'sale_cancel_rebase',
              restorationSourceId: sale.id,
            );
          }
          for (var lineIndex = 0;
              lineIndex < sale.items.length;
              lineIndex += 1) {
            final item = sale.items[lineIndex];
            final product = _findProductForHistoricalSale(item.productId);
            if (product == null) {
              throw StateError('Product ${item.productId} was not found.');
            }
            if (!product.trackStock) continue;
            if (item.batchAllocations.isNotEmpty) {
              await batchService.restoreUnifiedInTransaction(
                product: product,
                warehouseId: sale.warehouseId.isEmpty
                    ? Warehouse.defaultId
                    : sale.warehouseId,
                allocations: item.batchAllocations,
                restoredAt: now,
                storeId: appIdentity.storeId,
                deviceId: _deviceId,
              );
            }
            final movementAllocations = item.batchAllocations.isEmpty
                ? <BatchAllocation>[
                    BatchAllocation(
                        batchId: '', quantity: item.effectiveBaseQuantity)
                  ]
                : item.batchAllocations;
            for (var batchIndex = 0;
                batchIndex < movementAllocations.length;
                batchIndex += 1) {
              final allocation = movementAllocations[batchIndex];
              final hasBatch = allocation.batchId.isNotEmpty;
              final sourceMovementId = _saleStockMovementId(
                sale: sale,
                item: item,
                allocation: allocation,
                lineIndex: lineIndex,
              );
              if (!hasBatch) {
                final reversible =
                    await _remainingReversibleStockQuantityInTransaction(
                  sqliteDb,
                  sourceMovementId,
                );
                if (reversible == null) continue;
              }
              final originalMovement = StockMovement(
                id: _saleStockMovementId(
                  sale: sale,
                  item: item,
                  allocation: allocation,
                  lineIndex: lineIndex,
                ),
                productId: _operationalProductIdForStorage(item.productId),
                productName: item.productName,
                type: 'sale',
                quantity: -allocation.quantity,
                date: sale.date,
                referenceId: sale.id,
                referenceNo: sale.invoiceNo,
                reason: 'Sale invoice',
                unitCost: hasBatch ? allocation.unitCost : item.unitCostPerBase,
                warehouseId: sale.warehouseId.isEmpty
                    ? Warehouse.defaultId
                    : sale.warehouseId,
                warehouseName: sale.warehouseName.isEmpty
                    ? Warehouse.defaultName
                    : sale.warehouseName,
                batchId: allocation.batchId,
                movementGroupId: _saleMovementGroupId(sale),
                documentLineId: '${sale.id}-line-$lineIndex',
                sourceMovementId: '',
                reversalOfMovementId: '',
                idempotencyKey: _saleStockMovementIdempotencyKey(
                  sale: sale,
                  lineIndex: lineIndex,
                  batchIndex: batchIndex,
                  hasBatch: hasBatch,
                ),
                createdAt: sale.createdAt,
                updatedAt: sale.updatedAt,
                deviceId: sale.deviceId,
                syncStatus: sale.syncStatus,
                storeId: sale.storeId,
                branchId: sale.branchId,
                version: sale.version,
                lastModifiedByDeviceId: sale.lastModifiedByDeviceId,
              );
              await stockService.recordReversalInTransaction(
                originalMovement: originalMovement,
                operationType: 'sale_cancel',
                documentType: 'sale',
                documentId: sale.id,
                reason: 'Sale cancelled',
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                deviceId: _deviceId,
              );
            }
            if (item.batchAllocations.isNotEmpty) {
              await batchService.assertWarehouseBatchBalanceInTransaction(
                productId: _operationalProductIdForStorage(item.productId),
                warehouseId: sale.warehouseId.isEmpty
                    ? Warehouse.defaultId
                    : sale.warehouseId,
                storeId: appIdentity.storeId,
              );
            }
          }
          await _requirePostedJournalInTransaction(
            sqliteDb,
            referenceType: 'sale',
            referenceId: sale.id,
            includeSaleEditFamily: true,
            failureMessage:
                'Active sale journal is missing; sale cancellation was rolled back.',
          );
          await AccountingService.reverseSaleEntriesForSale(
            saleId: sale.id,
            reason: 'Sale cancelled',
            createdBy: _deviceId,
            notifyChange: false,
            withinExistingTransaction: true,
          );
          await _requireNoActiveJournalInTransaction(
            sqliteDb,
            referenceType: 'sale',
            referenceId: sale.id,
            includeSaleEditFamily: true,
            failureMessage:
                'Sale journal reversal did not complete; sale cancellation was rolled back.',
          );
          cancelJournalReversedInSqliteTransaction = true;
          await BusinessSqliteStore.upsertEntityPayloads(
            sqliteDb,
            AppStore._salesKey,
            <Map<String, dynamic>>[cancelledSale.toJson()],
            sortIndices: <int?>[0],
          );
          final saleAccountId = sale.customerId.trim().isNotEmpty
              ? sale.customerId.trim()
              : sale.customerName.trim();
          final saleLedgerTotal = sale.invoiceTotal > 0
              ? sale.invoiceTotal
              : ((sale.items.fold<double>(
                          0, (sum, item) => sum + item.lineTotal) -
                      sale.discount)
                  .clamp(0, double.infinity)
                  .toDouble());
          if (saleAccountId.isNotEmpty && saleLedgerTotal > 0) {
            await _persistAccountTransactionInExistingTransaction(
              sqliteDb,
              AccountTransaction(
                id: '${sale.id}-sale-cancel',
                accountType: 'customer',
                accountId: saleAccountId,
                accountName: sale.customerName,
                date: now,
                type: 'cancel',
                referenceId: sale.id,
                referenceNo: sale.invoiceNo,
                credit: saleLedgerTotal,
                currency: sale.invoiceCurrency,
                note: 'Sale cancelled',
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
        await refreshAfterDatabaseChange(AppStore._inventoryCostLayersKey);
      } else {
        for (final item in sale.items) {
          _restoreInventoryCostLayersFromSaleItem(item, now);
        }
        for (var lineIndex = 0; lineIndex < sale.items.length; lineIndex += 1) {
          final item = sale.items[lineIndex];
          final index = _productIndexById[item.productId];
          if (index == null) continue;
          final product = _products[index];
          if (!product.trackStock) continue;
          _products[index] = _withSyncMeta<Product>(
            product.copyWith(
              stock: product.stock + item.effectiveBaseQuantity,
            ),
            now,
          );
          _addStockMovement(
            StockMovement(
              id: '${sale.id}-${item.productId}-sale-cancel-$lineIndex',
              productId: item.productId,
              productName: item.productName,
              type: 'sale_cancel',
              quantity: item.effectiveBaseQuantity,
              date: now,
              referenceId: sale.id,
              referenceNo: sale.invoiceNo,
              reason: 'Sale cancelled',
              unitCost: item.unitCostPerBase,
              warehouseId: sale.warehouseId.isEmpty
                  ? Warehouse.defaultId
                  : sale.warehouseId,
              warehouseName: sale.warehouseName.isEmpty
                  ? Warehouse.defaultName
                  : sale.warehouseName,
              movementGroupId: sale.id,
              documentLineId: '${sale.id}-line-$lineIndex',
              sourceMovementId: '',
              reversalOfMovementId: '',
              idempotencyKey: '${sale.id}:sale_cancel:$lineIndex',
              createdAt: now,
              updatedAt: now,
              deviceId: _deviceId,
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              syncStatus: 'pending',
              lastModifiedByDeviceId: _deviceId,
            ),
            recordSync: true,
          );
        }
      }
      await _refreshProductStockCompatibilityCache(
        sale.items.map((item) => item.productId),
      );
    }

    final authoritativeCancelDb = SqliteMigrationManager.database;
    if (!restoreStock &&
        LocalDatabaseService.isSqliteAuthoritative &&
        authoritativeCancelDb != null) {
      await authoritativeCancelDb.transaction(() async {
        await _requirePostedJournalInTransaction(
          authoritativeCancelDb,
          referenceType: 'sale',
          referenceId: sale.id,
          includeSaleEditFamily: true,
          failureMessage:
              'Active sale journal is missing; sale cancellation was rolled back.',
        );
        await AccountingService.reverseSaleEntriesForSale(
          saleId: sale.id,
          reason: 'Sale cancelled',
          createdBy: _deviceId,
          notifyChange: false,
          withinExistingTransaction: true,
        );
        await _requireNoActiveJournalInTransaction(
          authoritativeCancelDb,
          referenceType: 'sale',
          referenceId: sale.id,
          includeSaleEditFamily: true,
          failureMessage:
              'Sale journal reversal did not complete; sale cancellation was rolled back.',
        );
        cancelJournalReversedInSqliteTransaction = true;
        await BusinessSqliteStore.upsertEntityPayloads(
          authoritativeCancelDb,
          AppStore._salesKey,
          <Map<String, dynamic>>[cancelledSale.toJson()],
          sortIndices: const <int?>[0],
        );
        final saleAccountId = sale.customerId.trim().isNotEmpty
            ? sale.customerId.trim()
            : sale.customerName.trim();
        final saleLedgerTotal = sale.invoiceTotal > 0
            ? sale.invoiceTotal
            : ((sale.items
                        .fold<double>(0, (sum, item) => sum + item.lineTotal) -
                    sale.discount)
                .clamp(0, double.infinity)
                .toDouble());
        if (saleAccountId.isNotEmpty && saleLedgerTotal > 0) {
          await _persistAccountTransactionInExistingTransaction(
            authoritativeCancelDb,
            AccountTransaction(
              id: '${sale.id}-sale-cancel',
              accountType: 'customer',
              accountId: saleAccountId,
              accountName: sale.customerName,
              date: now,
              type: 'cancel',
              referenceId: sale.id,
              referenceNo: sale.invoiceNo,
              credit: saleLedgerTotal,
              currency: sale.invoiceCurrency,
              note: 'Sale cancelled',
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
    }

    if (!cancelJournalReversedInSqliteTransaction) {
      await AccountingService.reverseSaleEntriesForSale(
        saleId: sale.id,
        reason: 'Sale cancelled',
        createdBy: _deviceId,
      );
    }
    final saleCancelWasAtomic = LocalDatabaseService.isSqliteAuthoritative &&
        SqliteMigrationManager.database != null;
    cancelledSale = saleCancelWasAtomic
        ? _saleSyncMetaPreview(cancelledSaleBase, now)
        : _withSyncMeta<Sale>(cancelledSaleBase, now);
    if (index != -1) {
      _sales[index] = cancelledSale;
    }
    _recordSyncChange(
      entityType: 'sale',
      entityId: id,
      operation: 'cancel',
      payload: cancelledSale.toJson(),
    );
    if (!saleCancelWasAtomic) {
      await _recordSaleCancelLedger(sale, now);
    }
    await _saveDirty(
      products: restoreStock,
      productDerivedData: !saleCancelWasAtomic &&
          restoreStock &&
          sale.items.any((item) => item.costLayerConsumptions.isNotEmpty),
      sales: !saleCancelWasAtomic,
      stockMovements: false,
      accountTransactions: !saleCancelWasAtomic,
      sync: true,
    );
    notifyListeners();
  }


  double estimateProfit() {
    final grossProfit = _sales.fold<double>(
      0,
      (sum, sale) => sum + sale.grossProfit,
    );
    return grossProfit - _totalExpensesAmount;
  }
}
