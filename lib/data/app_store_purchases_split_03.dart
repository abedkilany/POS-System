part of 'app_store.dart';

extension _AppStoreSplitPurchasesPart3 on AppStore {
  Future<Purchase> updatePurchaseDraft({
    required String purchaseId,
    required int expectedVersion,
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    String paymentStatus = 'paid',
    String paymentMethod = 'Cash',
    double? paidAmount,
    String warehouseId = '',
    String warehouseName = '',
  }) async {
    requirePermission(AppPermission.purchasesManage);
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
    final index = _purchaseIndexForId(purchaseId);
    final current = LocalDatabaseService.isSqliteAuthoritative &&
            SqliteMigrationManager.database != null
        ? await _purchaseByIdFromSqlite(purchaseId)
        : (index == -1
            ? await _purchaseByIdFromSqlite(purchaseId)
            : _purchases[index]);
    if (current == null) throw ArgumentError('Purchase not found.');
    if (current.isCancelled) {
      throw StateError('Cancelled/returned purchases cannot be edited.');
    }
    if (current.version != expectedVersion) {
      throw StateError(
          'Purchase changed by another user. Reload it before editing.');
    }

    final now = DateTime.now();
    final resolvedWarehouse =
        resolveWarehouseForPurchase(warehouseId: warehouseId);
    final normalizedStatus = paymentStatus.trim().toLowerCase() == 'credit'
        ? 'credit'
        : paymentStatus.trim().toLowerCase() == 'partial'
            ? 'partial'
            : 'paid';
    final total = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    if (current.isReceived && current.paidAmount > total + 0.000001) {
      throw StateError(
        'Cannot reduce the purchase below its already allocated payment. Reverse or adjust the payment first.',
      );
    }
    if (current.isReceived &&
        current.paidAmount > 0.000001 &&
        supplierId.trim() != current.supplierId.trim()) {
      throw StateError(
        'Cannot change the supplier of a received purchase with allocated payments. Reverse the payment first.',
      );
    }
    final normalizedPaid = normalizedStatus == 'paid'
        ? total
        : normalizedStatus == 'credit'
            ? 0.0
            : (paidAmount ?? 0).clamp(0, total).toDouble();
    final receivedPaymentStatus = _receivedPurchasePaymentStatus(
      paidAmount: current.paidAmount.clamp(0, total).toDouble(),
      total: total,
    );
    final existingLineIds = current.items
        .map((item) => item.lineId.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final usedLineIds = <String>{};
    final normalizedItems = items.indexed.map((entry) {
      final item = entry.$2;
      final requestedLineId = item.lineId.trim();
      if (requestedLineId.isNotEmpty &&
          existingLineIds.contains(requestedLineId) &&
          usedLineIds.add(requestedLineId)) {
        return item;
      }
      var generatedLineId =
          '${current.id}:pl:v${current.version + 1}:${entry.$1}:${now.microsecondsSinceEpoch}';
      var suffix = 0;
      while (!usedLineIds.add(generatedLineId)) {
        suffix += 1;
        generatedLineId =
            '${current.id}:pl:v${current.version + 1}:${entry.$1}:${now.microsecondsSinceEpoch}:$suffix';
      }
      return _copyPurchaseItemWith(
        item: item,
        lineId: generatedLineId,
      );
    }).toList(growable: false);
    var updated = current.copyWith(
      supplierId: supplierId,
      supplierName:
          supplierName.trim().isEmpty ? 'Supplier' : supplierName.trim(),
      items: normalizedItems,
      paymentStatus: current.isReceived
          ? receivedPaymentStatus
          : (normalizedPaid > 0 ? 'credit' : normalizedStatus),
      paymentMethod: current.isReceived
          ? current.paymentMethod
          : (paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim()),
      paidAmount: current.isReceived ? current.paidAmount : 0,
      warehouseId: resolvedWarehouse.id,
      warehouseName: warehouseName.trim().isEmpty
          ? resolvedWarehouse.name
          : warehouseName.trim(),
      updatedAt: now,
      version: current.version + 1,
      lastModifiedByDeviceId: _deviceId,
      syncStatus: 'pending',
      clearPostedSnapshot: current.isReceived,
    );
    final beforeJson = jsonEncode(current.toJson());
    final sqliteDb = SqliteMigrationManager.database;
    final legacyDefaultVatRatePercent =
        await AccountingService.readDefaultVatRatePercent();
    final taxProfileIdByProductId = <String, String>{
      for (final product in _products) product.id: product.taxProfileId,
    };

    if (current.isDraft) {
      if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
        await sqliteDb.transaction(() async {
          await BusinessSqliteStore.upsertEntityPayloads(
            sqliteDb,
            AppStore._purchasesKey,
            <Map<String, dynamic>>[updated.toJson()],
            sortIndices: <int?>[index < 0 ? 0 : index],
          );
        });
      }
    } else if (current.isReceived) {
      if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
        throw StateError(
            'Received purchase editing requires the SQLite authoritative store.');
      }
      await _waitForPendingPurchaseAccounting(current.id);
      final stockService = StockTransactionService(
        sqliteDb,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => false,
      );
      final batchService = BatchInventoryService(sqliteDb);
      final repostMovements = <StockMovement>[];
      await sqliteDb.transaction(() async {
        final ensuredUnifiedCutovers = <String>{};
        DateTime? originalReceiptAt;
        await _requirePurchaseBatchesUnusedInTransaction(sqliteDb, current);
        await _closeInventoryCostLayersForPurchaseInTransaction(
          sqliteDb,
          current,
          now,
        );

        for (var lineIndex = 0;
            lineIndex < current.items.length;
            lineIndex += 1) {
          final oldItem = current.items[lineIndex];
          final product = _findProductById(oldItem.productId);
          if (product == null) {
            throw StateError('Product ${oldItem.productId} was not found.');
          }
          if (!product.trackStock) continue;
          var originalMovements = await _activePurchaseReceiveMovements(
            sqliteDb,
            purchaseId: current.id,
            productId: oldItem.productId,
            documentLineId: _stablePurchaseLineId(current, oldItem, lineIndex),
          );
          if (originalMovements.isEmpty) {
            originalMovements = await _activePurchaseReceiveMovements(
              sqliteDb,
              purchaseId: current.id,
              productId: oldItem.productId,
              documentLineId: '${current.id}-line-$lineIndex',
            );
          }
          if (originalMovements.isEmpty) {
            throw StateError(
                'Active stock receipt is missing for ${current.purchaseNo}, line $lineIndex.');
          }
          for (final movement in originalMovements) {
            if (originalReceiptAt == null ||
                movement.date.isBefore(originalReceiptAt)) {
              originalReceiptAt = movement.date;
            }
            if (movement.batchId.trim().isNotEmpty) {
              await batchService.adjustUnifiedBatchInTransaction(
                product: product,
                warehouseId: movement.warehouseId,
                batchId: movement.batchId,
                quantityDelta: -movement.quantity,
                adjustedAt: now,
                storeId: appIdentity.storeId,
                deviceId: _deviceId,
              );
            }
            await stockService.recordReversalInTransaction(
              originalMovement: movement,
              operationType: 'purchase_edit_reverse',
              documentType: 'purchase',
              documentId: current.id,
              reason: 'Purchase edit reverse v${current.version}',
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              deviceId: _deviceId,
            );
            if (movement.batchId.trim().isNotEmpty) {
              await batchService.assertWarehouseBatchBalanceInTransaction(
                productId: oldItem.productId,
                warehouseId: movement.warehouseId.trim().isEmpty
                    ? Warehouse.defaultId
                    : movement.warehouseId.trim(),
                storeId: appIdentity.storeId,
              );
            }
          }
        }

        await AccountingService.reversePurchaseEntriesForPurchase(
          purchaseId: current.id,
          reason: 'Purchase edited',
          createdBy: _deviceId,
          adjustCashLocationBalance: false,
          notifyChange: false,
          withinExistingTransaction: true,
        );
        await _requireNoActiveJournalInTransaction(
          sqliteDb,
          referenceType: 'purchase',
          referenceId: current.id,
          includePurchaseEditFamily: true,
          failureMessage:
              'Purchase journal reversal did not complete; edit rolled back.',
        );

        final resolvedItems = List<PurchaseItem>.of(updated.items);
        for (var lineIndex = 0;
            lineIndex < updated.items.length;
            lineIndex += 1) {
          final item = updated.items[lineIndex];
          final product = _findProductById(item.productId);
          if (product == null || !product.trackStock) continue;
          final allocation = await _receiveUnifiedPurchaseLineInTransaction(
            sqliteDb,
            batchService: batchService,
            purchase: updated,
            item: item,
            lineIndex: lineIndex,
            product: product,
            warehouseId: updated.warehouseId.isEmpty
                ? Warehouse.defaultId
                : updated.warehouseId,
            receivedAt: originalReceiptAt ?? current.date,
            inventoryUnitCost: _purchaseInventoryUnitCostPerBase(
              item,
              legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
            ),
            ensuredCutovers: ensuredUnifiedCutovers,
          );
          resolvedItems[lineIndex] = _copyPurchaseItemWith(
            item: item,
            batchAllocations: <BatchAllocation>[allocation],
          );
          repostMovements.add(StockMovement(
            id: '${updated.id}-${allocation.batchId}-purchase-edit-v${updated.version}',
            productId: item.productId,
            productName: item.productName,
            type: 'purchase_receive',
            quantity: allocation.quantity,
            date: now,
            referenceId: updated.id,
            referenceNo: updated.purchaseNo,
            reason: 'Purchase edited and reposted',
            unitCost: allocation.unitCost,
            warehouseId: updated.warehouseId.isEmpty
                ? Warehouse.defaultId
                : updated.warehouseId,
            warehouseName: updated.warehouseName.isEmpty
                ? Warehouse.defaultName
                : updated.warehouseName,
            batchId: allocation.batchId,
            movementGroupId: '${updated.id}:purchase_edit:v${updated.version}',
            documentLineId: _stablePurchaseLineId(updated, item, lineIndex),
            idempotencyKey:
                '${updated.id}:purchase_edit:v${updated.version}:$lineIndex',
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
            syncStatus: 'pending',
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            lastModifiedByDeviceId: _deviceId,
          ));
        }
        updated = updated.copyWith(items: resolvedItems);
        Supplier? snapshotSupplier;
        for (final candidate in _suppliers) {
          if (candidate.id == updated.supplierId && !candidate.isDeleted) {
            snapshotSupplier = candidate;
            break;
          }
        }
        updated = updated.copyWith(
          postedSnapshot: PostedDocumentSnapshotService.forPurchase(
            purchase: updated,
            profile: _storeProfile,
            supplier: snapshotSupplier,
            user: _activeUser,
            role: currentUserRole,
            displayedPaidAmount: updated.paidAmount,
            displayedPaymentStatus: updated.paymentStatus,
            taxProfileIdByProductId: taxProfileIdByProductId,
            legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
          ),
        );
        await BusinessSqliteStore.upsertEntityPayloads(
          sqliteDb,
          AppStore._purchasesKey,
          <Map<String, dynamic>>[updated.toJson()],
          sortIndices: <int?>[index < 0 ? 0 : index],
        );
        if (repostMovements.isNotEmpty) {
          await stockService.recordMovementsInTransaction(
            operationType: 'purchase_edit_repost',
            documentType: 'purchase',
            documentId: updated.id,
            movementGroupId: '${updated.id}:purchase_edit:v${updated.version}',
            idempotencyKey: '${updated.id}:purchase_edit:v${updated.version}',
            movements: repostMovements,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            deviceId: _deviceId,
          );
          await _assertUnifiedBatchMovementBalancesInTransaction(
            batchService,
            repostMovements,
          );
        }
        await _rebuildProductCostsFromUnifiedBatchesInTransaction(
          sqliteDb,
          productIds: <String>{
            ...current.items.map((item) => item.productId),
            ...updated.items.map((item) => item.productId),
          },
          now: now,
        );
        final accountingPosted = await AccountingService.recordPurchase(
          updated,
          accountingReferenceId:
              '${updated.id}:purchase_edit:v${updated.version}',
          paymentPostedSeparately: true,
          withinExistingTransaction: true,
        );
        if (!accountingPosted) {
          throw StateError(
              'Purchase edit accounting repost failed; edit rolled back.');
        }
        await _requirePostedJournalInTransaction(
          sqliteDb,
          referenceType: 'purchase',
          referenceId: '${updated.id}:purchase_edit:v${updated.version}',
          failureMessage:
              'Purchase edit journal was not persisted; edit rolled back.',
        );
        if (updated.supplierId.trim().isNotEmpty && updated.subtotal > 0) {
          await _persistAccountTransactionInExistingTransaction(
            sqliteDb,
            AccountTransaction(
              id: '${updated.id}-purchase-invoice',
              accountType: 'supplier',
              accountId: updated.supplierId,
              accountName: updated.supplierName,
              date: updated.date,
              type: 'purchaseInvoice',
              referenceId: updated.id,
              referenceNo: updated.purchaseNo,
              credit: updated.subtotal,
              note: 'Purchase invoice ${updated.purchaseNo}',
              createdAt: updated.createdAt,
              updatedAt: now,
              deviceId: _deviceId,
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              lastModifiedByDeviceId: _deviceId,
            ),
          );
        }
      });
      await _refreshProductStockCompatibilityCache(
        <String>{
          ...current.items.map((item) => item.productId),
          ...updated.items.map((item) => item.productId),
        },
      );
      await refreshAfterDatabaseChange(AppStore._productsKey);
      await refreshAfterDatabaseChange(AppStore._productCostsKey);
      await refreshAfterDatabaseChange(AppStore._stockMovementsKey);
      await refreshAccountTransactionsFromSqlite();
    } else {
      throw StateError('This purchase status cannot be edited.');
    }

    _putPurchaseAtIndex(updated, index < 0 ? _purchases.length : index);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: updated.id,
      operation: current.isReceived ? 'edit_repost' : 'update',
      payload: updated.toJson(),
    );
    await _saveDirty(purchases: true, sync: true);
    await AuditLogger.record(
      entityType: 'purchase',
      entityId: updated.id,
      action: 'update',
      summary: current.isReceived
          ? 'Received purchase reversed and reposted'
          : 'Purchase draft edited',
      oldValue: beforeJson,
      newValue: jsonEncode(updated.toJson()),
      details: current.isReceived
          ? 'Unified Batch guarded reverse + repost.'
          : 'Draft purchase edited with optimistic version check.',
      userId: _activeUser?.id ?? '',
      userName: _actorName(),
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      sessionId: _deviceId,
      traceId: _deviceId,
      deviceId: _deviceId,
      sourceModule: 'purchases',
      isImportant: true,
    );
    _touchPurchasesData();
    notifyListeners();
    return updated;
  }
}
