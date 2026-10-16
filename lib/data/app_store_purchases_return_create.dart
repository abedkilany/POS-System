part of 'app_store.dart';

extension _AppStorePurchasesReturnCreate on AppStore {
  Future<Purchase> createPurchaseReturn({
    required String sourcePurchaseId,
    required List<PurchaseItem> items,
    String reason = '',
  }) async {
    requirePermission(AppPermission.purchasesManage);
    _requireSensitiveActionAuthorization(SensitiveAction.purchaseReverse);
    if (items.isEmpty) {
      throw ArgumentError('Purchase return must contain at least one item.');
    }
    final sourceIndex = _purchaseIndexForId(sourcePurchaseId);
    final source = sourceIndex == -1
        ? await _purchaseByIdFromSqlite(sourcePurchaseId)
        : _purchases[sourceIndex];
    if (source == null) throw ArgumentError('Source purchase not found.');
    if (!source.isReceived || source.isCancelled || source.isPurchaseReturn) {
      throw StateError('Only received purchase invoices can be returned.');
    }
    final sourceLines = <String, PurchaseItem>{
      for (final item in source.items)
        _stablePurchaseLineId(source, item, source.items.indexOf(item)): item,
    };
    final normalizedItems = <PurchaseItem>[];
    for (final item in items) {
      final sourceLineId = item.sourceLineId.trim();
      final sourceItem = sourceLines[sourceLineId];
      if (sourceItem == null || sourceItem.productId != item.productId) {
        throw StateError('A return line is not linked to the source invoice.');
      }
      if (!item.quantity.isFinite ||
          item.quantity <= 0 ||
          item.conversionToBase <= 0 ||
          item.unitCost < 0) {
        throw ArgumentError('Invalid purchase return item values.');
      }
      if (item.baseQuantity > sourceItem.baseQuantity + 0.000001) {
        throw LocalizedDomainException(
          'error_purchase_return_exceeds_source',
          values: <String, Object?>{
            'product': item.productName,
            'requested': item.quantity.toString(),
            'available': sourceItem.quantity.toString(),
            'unit': item.purchaseUnitName.trim().isEmpty
                ? 'unit'
                : item.purchaseUnitName,
          },
          fallback: 'Return quantity exceeds the source invoice quantity.',
        );
      }
      normalizedItems.add(item);
    }
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw StateError(
          'Purchase returns require the authoritative SQLite store.');
    }
    await _waitForPendingPurchaseAccounting(source.id);
    final now = DateTime.now();
    _purchaseCounter += 1;
    final returnId =
        'purchase_return_${_purchaseDevicePrefix}_${_purchaseCounter.toString().padLeft(6, '0')}';
    final returnNo =
        'PR-$_purchaseDevicePrefix-${_purchaseCounter.toString().padLeft(6, '0')}';
    final returned = Purchase(
      id: returnId,
      purchaseNo: returnNo,
      supplierId: source.supplierId,
      supplierName: source.supplierName,
      date: now,
      status: 'Received',
      items: normalizedItems.indexed.map((entry) {
        final item = entry.$2;
        return PurchaseItem(
          lineId: '$returnId:pl:${entry.$1}',
          sourceLineId: item.sourceLineId,
          productId: item.productId,
          productName: item.productName,
          quantity: item.quantity,
          unitCost: item.unitCost,
          purchaseUnitId: item.purchaseUnitId,
          purchaseUnitName: item.purchaseUnitName,
          conversionToBase: item.conversionToBase,
          originalUnitCost: item.originalUnitCost,
          unitCostCurrency: item.unitCostCurrency,
          exchangeRateAtEntry: item.exchangeRateAtEntry,
          batchAllocations: const <BatchAllocation>[],
        );
      }).toList(growable: false),
      note: reason.trim(),
      paymentStatus: 'credit',
      paidAmount: 0,
      warehouseId: source.warehouseId,
      warehouseName: source.warehouseName,
      documentType: 'purchase_return',
      sourcePurchaseId: source.id,
      sourcePurchaseNo: source.purchaseNo,
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      version: 1,
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
    final batchService = BatchInventoryService(db);
    final movements = <StockMovement>[];
    final affectedProductIds = <String>{};
    await db.transaction(() async {
      // A partial return is a new stock-out transaction. It must not use the
      // full purchase reversal guard, which intentionally blocks legacy
      // invoices whose historical batch identity was already absorbed.
      for (var lineIndex = 0;
          lineIndex < returned.items.length;
          lineIndex += 1) {
        final item = returned.items[lineIndex];
        final sourceItem = sourceLines[item.sourceLineId];
        if (sourceItem == null) throw StateError('Source line not found.');
        final alreadyReturnedRow = await db.customSelect(
          '''
          SELECT COALESCE(SUM(pi.quantity * pi.conversion_to_base), 0) AS qty
          FROM purchases p
          JOIN purchase_items pi ON pi.purchase_id = p.id
          WHERE p.document_type = 'purchase_return'
            AND p.source_purchase_id = ?
            AND pi.source_line_id = ?
            AND p.deleted_at = ''
            AND lower(p.status) NOT IN ('cancelled', 'returned')
          ''',
          variables: <Variable<Object>>[
            Variable<String>(source.id),
            Variable<String>(item.sourceLineId),
          ],
        ).getSingle();
        final alreadyReturned =
            (alreadyReturnedRow.data['qty'] as num? ?? 0).toDouble();
        if (alreadyReturned + item.baseQuantity >
            sourceItem.baseQuantity + 0.000001) {
          final conversion = sourceItem.conversionToBase <= 0
              ? 1
              : sourceItem.conversionToBase;
          final remaining = max(
            0,
            (sourceItem.baseQuantity - alreadyReturned) / conversion,
          );
          throw LocalizedDomainException(
            'error_purchase_return_exceeds_remaining',
            values: <String, Object?>{
              'product': item.productName,
              'requested': item.quantity.toString(),
              'available': remaining.toString(),
              'unit': item.purchaseUnitName.trim().isEmpty
                  ? 'unit'
                  : item.purchaseUnitName,
            },
            fallback: 'Return quantity exceeds the remaining quantity.',
          );
        }
        final product = _findProductById(item.productId);
        if (product == null) {
          throw StateError('Product ${item.productId} was not found.');
        }
        if (!product.trackStock) continue;
        await stockService.validateSufficientStock(
          storeId: appIdentity.storeId,
          warehouseId: source.warehouseId,
          productId: item.productId,
          requestedQuantity: item.baseQuantity,
        );
        var remaining = item.baseQuantity;
        var sourceMovements = await _activePurchaseReceiveMovements(
          db,
          purchaseId: source.id,
          productId: item.productId,
          documentLineId: item.sourceLineId,
        );
        if (sourceMovements.isEmpty) {
          sourceMovements = await _activePurchaseReceiveMovements(
            db,
            purchaseId: source.id,
            productId: item.productId,
            documentLineId:
                '${source.id}-line-${source.items.indexOf(sourceItem)}',
          );
        }
        for (var movementIndex = 0;
            movementIndex < sourceMovements.length && remaining > 0.000001;
            movementIndex += 1) {
          final original = sourceMovements[movementIndex];
          final quantity = min(remaining, original.quantity);
          if (quantity <= 0) continue;
          final allocations = <BatchAllocation>[];
          if (original.batchId.trim().isEmpty) {
            // Legacy receipts have no historical batch identity. Allocate the
            // return from the current Unified Batch balances; if negative
            // stock is enabled, the allocator creates a virtual deficit batch.
            allocations.addAll(
              await batchService.allocateUnifiedInTransaction(
                product: product,
                warehouseId: original.warehouseId,
                quantity: quantity,
                movementDate: now,
                storeId: appIdentity.storeId,
                deviceId: _deviceId,
                branchId: appIdentity.branchId,
                allowNegativeStock: _storeProfile.allowNegativeStock,
              ),
            );
          } else {
            allocations.add(BatchAllocation(
              batchId: original.batchId,
              quantity: quantity,
              unitCost: original.unitCost,
            ));
            await batchService.adjustUnifiedBatchInTransaction(
              product: product,
              warehouseId: original.warehouseId,
              batchId: original.batchId,
              quantityDelta: -quantity,
              adjustedAt: now,
              storeId: appIdentity.storeId,
              deviceId: _deviceId,
            );
          }
          for (var allocationIndex = 0;
              allocationIndex < allocations.length;
              allocationIndex += 1) {
            final allocation = allocations[allocationIndex];
            final partial = original.copyWith(
              id: '$returnId:movement:$lineIndex:$movementIndex:$allocationIndex',
              type: 'purchase_return',
              quantity: -allocation.quantity,
              referenceId: returnId,
              referenceNo: returnNo,
              reason: reason.trim().isEmpty ? 'Purchase return' : reason.trim(),
              movementGroupId: returnId,
              documentLineId: returned.items[lineIndex].lineId,
              sourceMovementId: original.id,
              reversalOfMovementId: '',
              idempotencyKey:
                  '$returnId:$lineIndex:$movementIndex:$allocationIndex',
              batchId: allocation.batchId,
              unitCost: allocation.unitCost > 0
                  ? allocation.unitCost
                  : original.unitCost,
              date: now,
              createdAt: now,
              updatedAt: now,
              deviceId: _deviceId,
              syncStatus: 'pending',
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              lastModifiedByDeviceId: _deviceId,
            );
            movements.add(partial);
          }
          remaining -= quantity;
        }
        if (remaining > 0.000001) {
          throw StateError(
              'Active stock receipt is missing for ${source.purchaseNo}.');
        }
        affectedProductIds.add(item.productId);
      }
      if (movements.isNotEmpty) {
        await stockService.recordMovementsInTransaction(
          operationType: 'purchase_return',
          documentType: 'purchase_return',
          documentId: returned.id,
          movementGroupId: returned.id,
          idempotencyKey: returned.id,
          movements: movements,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          deviceId: _deviceId,
        );
        await _assertUnifiedBatchMovementBalancesInTransaction(
            batchService, movements);
      }
      await BusinessSqliteStore.upsertEntityPayloads(
        db,
        AppStore._purchasesKey,
        <Map<String, dynamic>>[returned.toJson()],
        sortIndices: const <int?>[0],
      );
      if (returned.subtotal > 0) {
        final inventoryAmountsByAccount = <String, double>{};
        for (final item in returned.items) {
          if (item.lineTotal <= 0) continue;
          final inventoryAccount = await AccountingService
              .resolveInventoryAccountForProductForDatabase(db, item.productId);
          inventoryAmountsByAccount.update(
            inventoryAccount,
            (amount) => amount + item.lineTotal,
            ifAbsent: () => item.lineTotal,
          );
        }
        if (inventoryAmountsByAccount.isEmpty) {
          throw StateError('Purchase return has no inventory value to post.');
        }
        final suppliersAccount =
            await AccountingService.resolveAccountRoleForDatabase(
          db,
          'accounts_payable',
        );
        final entryId = await AccountingService.createPostedEntry(
          JournalEntryDraft(
            entryDate: now,
            referenceType: 'purchase_return',
            referenceId: returned.id,
            referenceNo: returned.purchaseNo,
            description: 'Purchase return ${returned.purchaseNo}',
            source: 'system',
            createdBy: _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            lines: <JournalLineDraft>[
              JournalLineDraft(
                accountId: suppliersAccount,
                debit: returned.subtotal,
                credit: 0,
                memo:
                    'Reduction of supplier payable for ${returned.purchaseNo}',
                partyType: 'supplier',
                partyId: returned.supplierId,
                partyName: returned.supplierName,
              ),
              ...inventoryAmountsByAccount.entries.map(
                (inventory) => JournalLineDraft(
                  accountId: inventory.key,
                  debit: 0,
                  credit: inventory.value,
                  memo:
                      'Inventory returned to supplier for ${returned.purchaseNo}',
                  partyType: 'supplier',
                  partyId: returned.supplierId,
                  partyName: returned.supplierName,
                ),
              ),
            ],
          ),
          database: db,
          withinExistingTransaction: true,
        );
        if (entryId.isEmpty) {
          throw StateError('Purchase return journal entry was not created.');
        }
      }
      if (returned.supplierId.trim().isNotEmpty && returned.subtotal > 0) {
        await _persistAccountTransactionInExistingTransaction(
          db,
          AccountTransaction(
            id: '${returned.id}-purchase-return',
            accountType: 'supplier',
            accountId: returned.supplierId,
            accountName: returned.supplierName,
            date: now,
            type: 'purchaseReturn',
            referenceId: returned.id,
            referenceNo: returned.purchaseNo,
            debit: returned.subtotal,
            note: reason.trim().isEmpty
                ? 'Purchase return ${returned.purchaseNo}'
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
    _putPurchaseAtIndex(returned, _purchases.length);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: returned.id,
      operation: 'create_return',
      payload: returned.toJson(),
    );
    await _refreshProductStockCompatibilityCache(affectedProductIds);
    await refreshAfterDatabaseChange(AppStore._stockMovementsKey);
    await _refreshAccountTransactionsFromSqlite();
    await _saveDirty(purchaseCounter: true, sync: true);
    _touchPurchasesData();
    notifyListeners();
    return returned;
  }
}
