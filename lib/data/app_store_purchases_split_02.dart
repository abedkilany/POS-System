part of 'app_store.dart';

extension _AppStoreSplitPurchasesPart2 on AppStore {
  Future<Purchase> createPurchase({
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    bool receiveNow = true,
    String note = '',
    String paymentStatus = 'paid',
    String paymentMethod = 'Cash',
    double? paidAmount,
    String warehouseId = '',
    String warehouseName = '',
  }) async {
    requirePermission(AppPermission.purchasesManage);
    _traceSync('purchases.createPurchase', 'validate_input', () {
      if (items.isEmpty) {
        throw ArgumentError('Purchase must contain at least one item.');
      }
      for (final item in items) {
        if (item.quantity <= 0 ||
            item.conversionToBase <= 0 ||
            item.unitCost < 0) {
          throw ArgumentError('Invalid purchase item values.');
        }
        if (_findProductById(item.productId) == null) {
          throw ArgumentError('Product not found: ${item.productName}');
        }
      }
    });
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError(
        'Purchase posting requires the SQLite authoritative store.',
      );
    }
    // A recently created/edited product may still have a debounced derived-data
    // write pending. Flush that snapshot before the authoritative transaction so
    // it cannot overwrite the newer purchase cost after the transaction commits.
    await _flushProductDerivedData();
    if (LocalDatabaseService.isSqliteAuthoritative) {
      final purchaseNoPrefix = 'PO-$_purchaseDevicePrefix-';
      final purchaseIdPrefix = 'purchase_${_purchaseDevicePrefix}_';
      final row = await sqliteDb.customSelect(
        '''
        SELECT MAX(sequence_no) AS max_sequence
        FROM (
          SELECT CAST(substr(purchase_no, length(?) + 1) AS INTEGER) AS sequence_no
          FROM purchases
          WHERE purchase_no LIKE ?
          UNION ALL
          SELECT CAST(substr(entity_id, length(?) + 1) AS INTEGER) AS sequence_no
          FROM sync_events
          WHERE entity_type = 'purchase' AND entity_id LIKE ?
        )
        ''',
        variables: <Variable<Object>>[
          Variable<String>(purchaseNoPrefix),
          Variable<String>('$purchaseNoPrefix%'),
          Variable<String>(purchaseIdPrefix),
          Variable<String>('$purchaseIdPrefix%'),
        ],
      ).getSingleOrNull();
      final persistedMax = (row?.data['max_sequence'] as num?)?.toInt() ?? 0;
      if (persistedMax > _purchaseCounter) {
        _purchaseCounter = persistedMax;
      }
    }
    _purchaseCounter += 1;
    final now = DateTime.now();
    final purchaseTotal = items.fold<double>(
      0,
      (sum, item) => sum + item.lineTotal,
    );
    final normalizedPaymentStatus =
        paymentStatus.trim().toLowerCase() == 'credit'
            ? 'credit'
            : paymentStatus.trim().toLowerCase() == 'partial'
                ? 'partial'
                : 'paid';
    final normalizedPaymentMethod =
        paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim();
    final normalizedPaidAmount = normalizedPaymentStatus == 'paid'
        ? purchaseTotal
        : normalizedPaymentStatus == 'credit'
            ? 0.0
            : (paidAmount ?? 0).clamp(0, purchaseTotal).toDouble();
    await AccountingService.validatePurchasePayment(
      paymentMethod: normalizedPaymentMethod,
      paidAmount: normalizedPaidAmount,
      deviceId: _deviceId,
      branchId: appIdentity.branchId,
    );
    final resolvedWarehouse = resolveWarehouseForPurchase(
      warehouseId: warehouseId,
    );
    final normalizedWarehouseName = warehouseName.trim().isEmpty
        ? resolvedWarehouse.name
        : warehouseName.trim();
    var purchase = Purchase(
      id: 'purchase_${_purchaseDevicePrefix}_${_purchaseCounter.toString().padLeft(6, '0')}',
      purchaseNo:
          'PO-$_purchaseDevicePrefix-${_purchaseCounter.toString().padLeft(6, '0')}',
      supplierId: supplierId,
      supplierName:
          supplierName.trim().isEmpty ? 'Supplier' : supplierName.trim(),
      date: now,
      status: receiveNow ? 'Received' : 'Draft',
      items: items,
      note: note,
      paymentStatus:
          normalizedPaidAmount > 0 ? 'credit' : normalizedPaymentStatus,
      paymentMethod: normalizedPaymentMethod,
      paidAmount: 0,
      warehouseId: resolvedWarehouse.id,
      warehouseName: normalizedWarehouseName,
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: _deviceId,
    );
    // A new purchase always owns fresh line identities. Never reuse a lineId
    // copied from a template/duplicated invoice, because purchase_items.id is
    // globally unique and the Batch source identity is anchored to it.
    purchase = purchase.copyWith(
      items: purchase.items.indexed.map((entry) {
        return _copyPurchaseItemWith(
          item: entry.$2,
          lineId: '${purchase.id}:pl:${entry.$1}',
        );
      }).toList(growable: false),
    );
    final legacyDefaultVatRatePercent =
        await AccountingService.readDefaultVatRatePercent();
    final taxProfileIdByProductId = <String, String>{
      for (final product in _products) product.id: product.taxProfileId,
    };
    if (LocalDatabaseService.isSqliteAuthoritative) {
      final stockService = StockTransactionService(
        sqliteDb,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
      );
      final batchService = BatchInventoryService(sqliteDb);
      final receiptMovements = <StockMovement>[];
      final productCostPreviews = <String, ProductCost>{};
      final productPreviews = <String, Product>{};
      final resolvedPurchaseItems = List<PurchaseItem>.of(purchase.items);
      if (receiveNow) {
        for (var lineIndex = 0;
            lineIndex < purchase.items.length;
            lineIndex += 1) {
          final item = purchase.items[lineIndex];
          final product = productPreviews[item.productId] ??
              _findProductById(item.productId);
          if (product == null || !product.trackStock) continue;
          final currentCost = productCostPreviews[item.productId] ??
              productCostFor(item.productId);
          final receivedQty = item.baseQuantity;
          final unitCost = _purchaseInventoryUnitCostPerBase(
            item,
            legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
          );
          final stockBefore = productPreviews.containsKey(item.productId)
              ? max(0.0, product.stock)
              : max(0.0, await totalWarehouseStockFromSqlite(item.productId));
          final stockAfter = stockBefore + receivedQty;
          final averageCost = stockAfter <= 0
              ? unitCost
              : ((stockBefore * currentCost.averageCost) +
                      (receivedQty * unitCost)) /
                  stockAfter;
          final updatedCost = currentCost.copyWith(
            averageCost: averageCost,
            lastCost: unitCost,
            currencyCode: 'USD',
            updatedAt: now,
          );
          productCostPreviews[item.productId] = updatedCost;
          productPreviews[item.productId] = product.copyWith(
            stock: stockAfter,
            updatedAt: now,
          );
        }
      }
      await _traceAsync<void>('purchases.createPurchase', 'sqlite_transaction',
          () async {
        await sqliteDb.transaction(() async {
          final ensuredUnifiedCutovers = <String>{};
          await BusinessSqliteStore.upsertEntityPayloads(
            sqliteDb,
            AppStore._purchasesKey,
            <Map<String, dynamic>>[purchase.toJson()],
            sortIndices: <int?>[0],
          );
          if (receiveNow) {
            for (var lineIndex = 0;
                lineIndex < purchase.items.length;
                lineIndex += 1) {
              final item = purchase.items[lineIndex];
              final product = _findProductById(item.productId);
              if (product == null || !product.trackStock) continue;
              final allocation = await _receiveUnifiedPurchaseLineInTransaction(
                sqliteDb,
                batchService: batchService,
                purchase: purchase,
                item: item,
                lineIndex: lineIndex,
                product: product,
                warehouseId: resolvedWarehouse.id,
                receivedAt: now,
                inventoryUnitCost: _purchaseInventoryUnitCostPerBase(
                  item,
                  legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
                ),
                ensuredCutovers: ensuredUnifiedCutovers,
              );
              resolvedPurchaseItems[lineIndex] = _copyPurchaseItemWith(
                item: item,
                batchAllocations: <BatchAllocation>[allocation],
              );
              receiptMovements.add(StockMovement(
                id: '${purchase.id}-$lineIndex-${allocation.batchId}-purchase-receive',
                productId: item.productId,
                productName: item.productName,
                type: 'purchase_receive',
                quantity: allocation.quantity,
                date: now,
                referenceId: purchase.id,
                referenceNo: purchase.purchaseNo,
                reason: 'Purchase received (Unified Batch)',
                unitCost: allocation.unitCost,
                warehouseId: resolvedWarehouse.id,
                warehouseName: normalizedWarehouseName,
                batchId: allocation.batchId,
                movementGroupId: purchase.id,
                documentLineId:
                    _stablePurchaseLineId(purchase, item, lineIndex),
                idempotencyKey:
                    '${purchase.id}:purchase_receive:$lineIndex:${allocation.batchId}',
                createdAt: now,
                updatedAt: now,
                deviceId: purchase.deviceId,
                syncStatus: purchase.syncStatus,
                storeId: purchase.storeId,
                branchId: purchase.branchId,
                version: purchase.version,
                lastModifiedByDeviceId: purchase.lastModifiedByDeviceId,
              ));
            }
            purchase = purchase.copyWith(items: resolvedPurchaseItems);
            Supplier? snapshotSupplier;
            for (final candidate in _suppliers) {
              if (candidate.id == purchase.supplierId && !candidate.isDeleted) {
                snapshotSupplier = candidate;
                break;
              }
            }
            purchase = purchase.copyWith(
              postedSnapshot: PostedDocumentSnapshotService.forPurchase(
                purchase: purchase,
                profile: _storeProfile,
                supplier: snapshotSupplier,
                user: _activeUser,
                role: currentUserRole,
                displayedPaidAmount: normalizedPaidAmount,
                displayedPaymentStatus:
                    normalizedPaidAmount >= purchaseTotal - 0.000001
                        ? 'paid'
                        : normalizedPaidAmount > 0
                            ? 'partial'
                            : normalizedPaymentStatus,
                taxProfileIdByProductId: taxProfileIdByProductId,
                legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
              ),
            );
            await BusinessSqliteStore.upsertEntityPayloads(
              sqliteDb,
              AppStore._purchasesKey,
              <Map<String, dynamic>>[purchase.toJson()],
              sortIndices: <int?>[0],
            );
            await stockService.recordMovementsInTransaction(
              operationType: 'purchase_receive',
              documentType: 'purchase',
              documentId: purchase.id,
              movementGroupId: purchase.id,
              idempotencyKey: '${purchase.id}:purchase_receive',
              movements: receiptMovements,
              storeId: purchase.storeId,
              branchId: purchase.branchId,
              deviceId: purchase.deviceId,
              skipExistingMovementLookup: true,
            );
            await _assertUnifiedBatchMovementBalancesInTransaction(
              batchService,
              receiptMovements,
            );
            if (productCostPreviews.isNotEmpty) {
              await BusinessSqliteStore.upsertEntityPayloads(
                sqliteDb,
                AppStore._productCostsKey,
                productCostPreviews.values
                    .map((item) => item.toJson())
                    .toList(growable: false),
              );
              await BusinessSqliteStore.upsertEntityPayloads(
                sqliteDb,
                AppStore._productsKey,
                productPreviews.values
                    .map((item) => item.toJson())
                    .toList(growable: false),
              );
            }
          }
          if (receiveNow) {
            final accountingPosted = await AccountingService.recordPurchase(
              purchase,
              paymentPostedSeparately: true,
              withinExistingTransaction: true,
            );
            if (!accountingPosted) {
              throw StateError(
                'Purchase accounting posting failed; the purchase transaction was rolled back.',
              );
            }
            await _requirePostedJournalInTransaction(
              sqliteDb,
              referenceType: 'purchase',
              referenceId: purchase.id,
              failureMessage:
                  'Purchase journal was not persisted; the purchase transaction was rolled back.',
            );
            await _persistAccountTransactionInExistingTransaction(
              sqliteDb,
              AccountTransaction(
                id: '${purchase.id}-purchase-invoice',
                accountType: 'supplier',
                accountId: purchase.supplierId,
                accountName: purchase.supplierName,
                date: purchase.date,
                type: 'purchaseInvoice',
                referenceId: purchase.id,
                referenceNo: purchase.purchaseNo,
                credit: purchase.subtotal,
                note: 'Purchase invoice ${purchase.purchaseNo}',
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
      });
      if (receiveNow) {
        await refreshAfterDatabaseChange(AppStore._productsKey);
        await refreshAfterDatabaseChange(AppStore._productCostsKey);
        await refreshAfterDatabaseChange(AppStore._inventoryCostLayersKey);
        await refreshAfterDatabaseChange(AppStore._stockMovementsKey);
        if (normalizedPaidAmount > 0) {
          purchase = await settlePurchasePayment(
            purchaseId: purchase.id,
            amount: normalizedPaidAmount,
            paymentMethod: normalizedPaymentMethod,
            notes: 'Initial payment for ${purchase.purchaseNo}',
            idempotencyKey: '${purchase.id}:initial-payment:v1',
            date: now,
          );
        }
      }
      _traceSync('purchases.createPurchase', 'memory_ledger_and_sync', () {
        _putPurchaseAtIndex(purchase, _purchases.length);
        _recordSyncChange(
          entityType: 'purchase',
          entityId: purchase.id,
          operation: 'create',
          payload: purchase.toJson(),
        );
      });
      // Purchase accounting + supplier ledger were committed atomically above.
      // Do not write the financial ledger a second time after commit.
      await _saveDirty(
        // Product costs and FIFO layers were committed and refreshed by the
        // authoritative purchase transaction above. Scheduling the legacy
        // derived-data flush here can replay that pre-sale snapshot after a
        // subsequent sale and overwrite its direct FIFO layer consumption.
        productDerivedData: false,
        purchaseCounter: true,
        sync: true,
      );
      _touchPurchasesData();
      notifyListeners();
      return purchase;
    }
    if (receiveNow && normalizedPaidAmount > 0) {
      throw StateError(
          'Purchase payments require the SQLite authoritative store.');
    }
    _putPurchaseAtIndex(purchase, _purchases.length);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: purchase.id,
      operation: 'create',
      payload: purchase.toJson(),
    );
    if (receiveNow) {
      _applyPurchaseStock(purchase, now);
    }
    await _saveDirty(
      purchases: true,
      products: receiveNow,
      productDerivedData: receiveNow,
      stockMovements: receiveNow,
      accountTransactions: receiveNow,
      purchaseCounter: true,
      sync: true,
    );
    if (receiveNow) {
      final accountingPosted = await _schedulePurchaseAccounting(purchase);
      if (accountingPosted) {
        await _recordPurchaseLedger(purchase, now);
        await _saveDirty(accountTransactions: true);
      }
    }
    unawaited(
      AppLogger.info(
        area: 'purchases',
        action: 'create_purchase',
        message: 'Purchase created successfully.',
        details:
            'purchaseId=${purchase.id} purchaseNo=${purchase.purchaseNo} total=$purchaseTotal receiveNow=$receiveNow',
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
        entityId: purchase.id,
        action: 'create',
        summary: 'Purchase created',
        details: jsonEncode(purchase.toJson()),
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
    return purchase;
  }
}
