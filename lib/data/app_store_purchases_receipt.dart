part of 'app_store.dart';

extension _AppStorePurchasesReceipt on AppStore {
  Future<void> receivePurchase(
    String id, {
    bool settleInitialPayment = true,
    bool postAccounting = true,
    Map<int, List<BatchAllocation>> batchAllocationsByLine =
        const <int, List<BatchAllocation>>{},
  }) async {
    requirePermission(AppPermission.purchasesManage);
    final index = _purchaseIndexForId(id);
    final purchase =
        index == -1 ? await _purchaseByIdFromSqlite(id) : _purchases[index];
    if (purchase == null) throw ArgumentError('Purchase not found.');
    if (purchase.isReceived || purchase.isCancelled) return;
    final plannedPayment = const PurchaseReceiptService().plannedInitialPayment(
      purchase,
      settleInitialPayment: settleInitialPayment,
    );
    await AccountingService.validatePurchasePayment(
      paymentMethod: purchase.paymentMethod,
      paidAmount: plannedPayment,
      deviceId: purchase.deviceId,
      branchId: purchase.branchId,
    );
    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      final now = DateTime.now();
      // Include the posting version in stock identity so reversal/repost cycles
      // never collide with a previous receipt's idempotency key.
      final receiptPlan = const PurchaseReceiptService().prepare(
        purchase: purchase,
        now: now,
        settleInitialPayment: settleInitialPayment,
        batchAllocationsByLine: batchAllocationsByLine,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
      );
      final receivePostingKey = receiptPlan.idempotencyKey;
      var received = receiptPlan.purchase;
      final legacyDefaultVatRatePercent =
          await AccountingService.readDefaultVatRatePercent();
      final taxProfileIdByProductId = <String, String>{
        for (final product in _products) product.id: product.taxProfileId,
      };
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
      for (var lineIndex = 0;
          lineIndex < received.items.length;
          lineIndex += 1) {
        final item = received.items[lineIndex];
        final product =
            productPreviews[item.productId] ?? _findProductById(item.productId);
        if (product == null || !product.trackStock) continue;
        final currentCost = productCostPreviews[item.productId] ??
            _productCostFor(item.productId);
        final receivedQty = item.baseQuantity;
        final unitCost = _purchaseInventoryUnitCostPerBase(
          item,
          legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
        );
        final stockBefore = productPreviews.containsKey(item.productId)
            ? max(0.0, product.stock)
            : max(0.0, await _totalWarehouseStockFromSqlite(item.productId));
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
      await sqliteDb.transaction(() async {
        final ensuredUnifiedCutovers = <String>{};
        await BusinessSqliteStore.upsertEntityPayloads(
          sqliteDb,
          AppStore._purchasesKey,
          <Map<String, dynamic>>[received.toJson()],
          sortIndices: <int?>[0],
        );
        final resolvedReceivedItems = List<PurchaseItem>.of(received.items);
        for (var lineIndex = 0;
            lineIndex < received.items.length;
            lineIndex += 1) {
          final item = received.items[lineIndex];
          final product = _findProductById(item.productId);
          if (product == null || !product.trackStock) continue;
          final warehouseId = received.warehouseId.isEmpty
              ? Warehouse.defaultId
              : received.warehouseId;
          final warehouseName = received.warehouseName.isEmpty
              ? Warehouse.defaultName
              : received.warehouseName;
          final allocation = await _receiveUnifiedPurchaseLineInTransaction(
            sqliteDb,
            batchService: batchService,
            purchase: received,
            item: item,
            lineIndex: lineIndex,
            product: product,
            warehouseId: warehouseId,
            receivedAt: now,
            inventoryUnitCost: _purchaseInventoryUnitCostPerBase(
              item,
              legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
            ),
            ensuredCutovers: ensuredUnifiedCutovers,
          );
          resolvedReceivedItems[lineIndex] = _copyPurchaseItemWith(
            item: item,
            batchAllocations: <BatchAllocation>[allocation],
          );
          receiptMovements.add(StockMovement(
            id: '${received.id}-$lineIndex-${allocation.batchId}-purchase-receive-v${received.version}',
            productId: item.productId,
            productName: item.productName,
            type: 'purchase_receive',
            quantity: allocation.quantity,
            date: now,
            referenceId: received.id,
            referenceNo: received.purchaseNo,
            reason: 'Purchase received (Unified Batch)',
            unitCost: allocation.unitCost,
            warehouseId: warehouseId,
            warehouseName: warehouseName,
            batchId: allocation.batchId,
            movementGroupId: received.id,
            documentLineId: _stablePurchaseLineId(received, item, lineIndex),
            idempotencyKey:
                '$receivePostingKey:$lineIndex:${allocation.batchId}',
            createdAt: now,
            updatedAt: now,
            deviceId: received.deviceId,
            syncStatus: received.syncStatus,
            storeId: received.storeId,
            branchId: received.branchId,
            version: received.version,
            lastModifiedByDeviceId: received.lastModifiedByDeviceId,
          ));
        }
        received = received.copyWith(items: resolvedReceivedItems);
        Supplier? snapshotSupplier;
        for (final candidate in _suppliers) {
          if (candidate.id == received.supplierId && !candidate.isDeleted) {
            snapshotSupplier = candidate;
            break;
          }
        }
        received = received.copyWith(
          postedSnapshot: PostedDocumentSnapshotService.forPurchase(
            purchase: received,
            profile: _storeProfile,
            supplier: snapshotSupplier,
            user: _activeUser,
            role: _currentUserRole,
            displayedPaidAmount: plannedPayment,
            displayedPaymentStatus:
                plannedPayment >= received.subtotal - 0.000001
                    ? 'paid'
                    : plannedPayment > 0
                        ? 'partial'
                        : received.paymentStatus,
            taxProfileIdByProductId: taxProfileIdByProductId,
            legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
          ),
        );
        await BusinessSqliteStore.upsertEntityPayloads(
          sqliteDb,
          AppStore._purchasesKey,
          <Map<String, dynamic>>[received.toJson()],
          sortIndices: <int?>[0],
        );
        if (receiptMovements.isNotEmpty) {
          await stockService.recordMovementsInTransaction(
            operationType: 'purchase_receive',
            documentType: 'purchase',
            documentId: received.id,
            movementGroupId: '$receivePostingKey:group',
            idempotencyKey: receivePostingKey,
            movements: receiptMovements,
            storeId: received.storeId,
            branchId: received.branchId,
            deviceId: received.deviceId,
          );
          await _assertUnifiedBatchMovementBalancesInTransaction(
            batchService,
            receiptMovements,
          );
        }
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
        if (postAccounting) {
          final accountingPosted = await AccountingService.recordPurchase(
            received,
            paymentPostedSeparately: true,
            withinExistingTransaction: true,
          );
          if (!accountingPosted) {
            throw StateError(
              'Purchase accounting posting failed; purchase receipt was rolled back.',
            );
          }
          await _requirePostedJournalInTransaction(
            sqliteDb,
            referenceType: 'purchase',
            referenceId: received.id,
            failureMessage:
                'Purchase journal was not persisted; purchase receipt was rolled back.',
          );
          if (received.supplierId.trim().isNotEmpty && received.subtotal > 0) {
            await _persistAccountTransactionInExistingTransaction(
              sqliteDb,
              AccountTransaction(
                id: '${received.id}-purchase-invoice',
                accountType: 'supplier',
                accountId: received.supplierId,
                accountName: received.supplierName,
                date: received.date,
                type: 'purchaseInvoice',
                referenceId: received.id,
                referenceNo: received.purchaseNo,
                credit: received.subtotal,
                note: 'Purchase invoice ${received.purchaseNo}',
                createdAt: now,
                updatedAt: now,
                deviceId: _deviceId,
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                lastModifiedByDeviceId: _deviceId,
              ),
            );
          }
        }
      });
      if (index == -1) {
        _putPurchaseAtIndex(received, _purchases.length);
      } else {
        _putPurchaseAtIndex(received, index);
      }
      _recordSyncChange(
        entityType: 'purchase',
        entityId: received.id,
        operation: 'receive',
        payload: received.toJson(),
      );
      await refreshAfterDatabaseChange(AppStore._productsKey);
      await refreshAfterDatabaseChange(AppStore._productCostsKey);
      await refreshAfterDatabaseChange(AppStore._inventoryCostLayersKey);
      await refreshAfterDatabaseChange(AppStore._stockMovementsKey);
      if (plannedPayment > 0) {
        received = await _settlePurchasePayment(
          purchaseId: received.id,
          amount: plannedPayment,
          paymentMethod: purchase.paymentMethod,
          notes: 'Payment on receiving ${received.purchaseNo}',
          idempotencyKey: '${received.id}:receive-payment:v1',
          date: now,
        );
      }
      if (postAccounting) await _refreshAccountTransactionsFromSqlite();
      _touchPurchasesData();
      notifyListeners();
      return;
    }
    final now = DateTime.now();
    final received = _withSyncMeta<Purchase>(
      purchase.copyWith(status: 'Received'),
      now,
    );
    if (index != -1) _putPurchaseAtIndex(received, index);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: received.id,
      operation: 'receive',
      payload: received.toJson(),
    );
    _applyPurchaseStock(received, now);
    await _saveDirty(
      purchases: true,
      products: true,
      productDerivedData: true,
      stockMovements: true,
      accountTransactions: true,
      sync: true,
    );
    if (postAccounting) {
      final accountingPosted = await _schedulePurchaseAccounting(received);
      if (accountingPosted) {
        await _recordPurchaseLedger(received, now);
        await _saveDirty(accountTransactions: true);
      }
    }
    unawaited(
      AppLogger.info(
        area: 'purchases',
        action: 'receive_purchase',
        message: 'Purchase received successfully.',
        details: 'purchaseId=${received.id} purchaseNo=${received.purchaseNo}',
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
        entityId: received.id,
        action: 'receive',
        summary: 'Purchase received',
        details: jsonEncode(received.toJson()),
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

  Future<void> deleteDraftPurchase(String id) async {
    requirePermission(AppPermission.purchasesManage);
    final index = _purchaseIndexForId(id);
    final purchase =
        index == -1 ? await _purchaseByIdFromSqlite(id) : _purchases[index];
    if (purchase == null) return;
    final now = DateTime.now();
    final deleted = const PurchaseDraftService().softDeleteDraft(
      current: purchase,
      now: now,
      deviceId: _deviceId,
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
    );
    if (index != -1) _putPurchaseAtIndex(deleted, index);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _saveDirty(purchases: true, sync: true);
    unawaited(
      AppLogger.info(
        area: 'purchases',
        action: 'delete_purchase',
        message: 'Draft purchase deleted successfully.',
        details: 'purchaseId=$id purchaseNo=${purchase.purchaseNo}',
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
        action: 'delete',
        summary: 'Draft purchase deleted',
        details: jsonEncode(deleted.toJson()),
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

  Future<void> _requirePostedJournalInTransaction(
    dynamic sqliteDb, {
    required String referenceType,
    required String referenceId,
    bool includePurchaseEditFamily = false,
    bool includeSaleEditFamily = false,
    required String failureMessage,
  }) =>
      JournalPostingGuard(sqliteDb).requirePosted(
        referenceType: referenceType,
        referenceId: referenceId,
        includePurchaseEditFamily: includePurchaseEditFamily,
        includeSaleEditFamily: includeSaleEditFamily,
        failureMessage: failureMessage,
      );

  Future<void> _requireNoActiveJournalInTransaction(
    dynamic sqliteDb, {
    required String referenceType,
    required String referenceId,
    bool includePurchaseEditFamily = false,
    bool includeSaleEditFamily = false,
    required String failureMessage,
  }) =>
      JournalPostingGuard(sqliteDb).requireReversed(
        referenceType: referenceType,
        referenceId: referenceId,
        includePurchaseEditFamily: includePurchaseEditFamily,
        includeSaleEditFamily: includeSaleEditFamily,
        failureMessage: failureMessage,
      );

  Future<List<StockMovement>> _activePurchaseReceiveMovements(
    dynamic sqliteDb, {
    required String purchaseId,
    required String productId,
    required String documentLineId,
  }) async {
    final rows = await sqliteDb.customSelect(
      '''
      SELECT sm.*
      FROM stock_movements sm
      WHERE sm.reference_id = ?
        AND sm.product_id = ?
        AND sm.document_line_id = ?
        AND sm.movement_type = 'purchase_receive'
        AND sm.deleted_at = ''
        AND NOT EXISTS (
          SELECT 1
          FROM stock_movements reversal
          WHERE reversal.reversal_of_movement_id = sm.id
            AND reversal.deleted_at = ''
        )
      ORDER BY sm.created_at DESC, sm.updated_at DESC, sm.id DESC
      ''',
      variables: <Variable<Object>>[
        Variable<String>(purchaseId),
        Variable<String>(productId),
        Variable<String>(documentLineId),
      ],
    ).get();
    return rows.map<StockMovement>((row) {
      final data = row.data;
      return StockMovement.fromJson(<String, dynamic>{
        'id': data['id'],
        'productId': data['product_id'],
        'productName': data['product_name'],
        'type': data['movement_type'],
        'quantity': data['quantity'],
        'date': data['movement_date'],
        'referenceId': data['reference_id'],
        'referenceNo': data['reference_no'],
        'reason': data['reason'],
        'adjustmentCategory': data['adjustment_category'],
        'notes': data['notes'],
        'evidenceRef': data['evidence_ref'],
        'warehouseId': data['warehouse_id'],
        'warehouseName': data['warehouse_name'],
        'batchId': data['batch_id'],
        'movementGroupId': data['movement_group_id'],
        'documentLineId': data['document_line_id'],
        'sourceMovementId': data['source_movement_id'],
        'reversalOfMovementId': data['reversal_of_movement_id'],
        'idempotencyKey': data['idempotency_key'],
        'unitCost': data['unit_cost'],
        'createdAt': data['created_at'],
        'updatedAt': data['updated_at'],
        'deviceId': data['device_id'],
        'syncStatus': data['sync_status'],
        'storeId': data['store_id'],
        'branchId': data['branch_id'],
        'version': data['version'],
        'lastModifiedByDeviceId': data['last_modified_by_device_id'],
        'reviewedAt': data['reviewed_at'],
        'reviewedBy': data['reviewed_by'],
        'reviewNote': data['review_note'],
      });
    }).toList(growable: false);
  }
}
