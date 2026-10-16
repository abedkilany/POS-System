part of 'app_store.dart';

extension _AppStoreSalesReturnsCreateReturn on AppStore {
  Future<CreditNote> returnSale(
    String id, {
    bool restoreStock = true,
    Map<String, double>? returnedQuantities,
  }) async {
    requirePermission(AppPermission.salesCancel);
    _requireSensitiveActionAuthorization(SensitiveAction.saleReverse);
    final index = _sales.indexWhere((sale) => sale.id == id);
    final sale = index == -1 ? await _saleByIdFromSqlite(id) : _sales[index];
    if (sale == null) {
      throw ArgumentError('Sale not found.');
    }
    if (sale.isCancelled) {
      throw StateError('Sale is already cancelled or fully returned.');
    }
    await _ensureCreditNotesLoaded();

    const epsilon = 0.000001;
    final previouslyReturned = await _returnedSaleQuantitiesByProduct(sale.id);
    final originalByProduct = <String, double>{};
    for (final item in sale.items) {
      originalByProduct.update(
        item.productId,
        (value) => value + item.quantity,
        ifAbsent: () => item.quantity,
      );
    }

    final requestedByProduct = <String, double>{};
    if (returnedQuantities == null) {
      for (final entry in originalByProduct.entries) {
        final remaining = (entry.value - (previouslyReturned[entry.key] ?? 0))
            .clamp(0, double.infinity)
            .toDouble();
        if (remaining > epsilon) requestedByProduct[entry.key] = remaining;
      }
    } else {
      for (final entry in returnedQuantities.entries) {
        final original = originalByProduct[entry.key];
        if (original == null) {
          throw ArgumentError(
              'Returned product ${entry.key} is not on this sale.');
        }
        final requested = entry.value;
        final alreadyReturned = previouslyReturned[entry.key] ?? 0;
        final remaining =
            (original - alreadyReturned).clamp(0, double.infinity).toDouble();
        if (!requested.isFinite ||
            requested < 0 ||
            requested > remaining + epsilon) {
          throw ArgumentError(
            'Return quantity for ${entry.key} exceeds the remaining invoice quantity ($remaining).',
          );
        }
        if (requested > epsilon) requestedByProduct[entry.key] = requested;
      }
    }
    if (requestedByProduct.isEmpty) {
      throw ArgumentError('Return quantity must be greater than zero.');
    }

    // Distribute previous and requested return quantities across the original
    // sale lines. This also handles the same product appearing on more than one
    // line while keeping the original line index for stock-ledger traceability.
    final priorRemaining = <String, double>{...previouslyReturned};
    final requestRemaining = <String, double>{...requestedByProduct};
    final selectedItems = <SaleItem>[];
    final selectedOriginalLineIndexes = <int>[];
    for (var originalLineIndex = 0;
        originalLineIndex < sale.items.length;
        originalLineIndex += 1) {
      final item = sale.items[originalLineIndex];
      var priorForProduct = priorRemaining[item.productId] ?? 0;
      final priorOnLine = min(item.quantity, priorForProduct);
      priorForProduct =
          (priorForProduct - priorOnLine).clamp(0, double.infinity).toDouble();
      priorRemaining[item.productId] = priorForProduct;

      final lineRemaining =
          (item.quantity - priorOnLine).clamp(0, double.infinity).toDouble();
      var requestedForProduct = requestRemaining[item.productId] ?? 0;
      final requestedOnLine = min(lineRemaining, requestedForProduct);
      requestRemaining[item.productId] = (requestedForProduct - requestedOnLine)
          .clamp(0, double.infinity)
          .toDouble();
      if (requestedOnLine <= epsilon) continue;

      final basePerSaleUnit = item.quantity <= epsilon
          ? item.conversionToBase
          : item.effectiveBaseQuantity / item.quantity;
      final priorBaseOnLine = priorOnLine * basePerSaleUnit;
      final requestedBase = requestedOnLine * basePerSaleUnit;
      selectedItems.add(SaleItem(
        productId: item.productId,
        productName: item.productName,
        unitPrice: item.unitPrice,
        quantity: requestedOnLine,
        unitCost: item.unitCost,
        costingMethodAtSale: item.costingMethodAtSale,
        costCurrency: item.costCurrency,
        costExchangeRate: item.costExchangeRate,
        costLayerConsumptions: _sliceCostConsumptionsForReturn(
          item.costLayerConsumptions,
          offset: priorBaseOnLine,
          quantity: requestedBase,
        ),
        unitName: item.unitName,
        conversionToBase: item.conversionToBase,
        baseQuantity: requestedBase,
        batchAllocations: _sliceBatchAllocationsForReturn(
          item.batchAllocations,
          offset: priorBaseOnLine,
          quantity: requestedBase,
        ),
      ));
      selectedOriginalLineIndexes.add(originalLineIndex);
    }
    if (selectedItems.isEmpty ||
        requestRemaining.values.any((value) => value > epsilon)) {
      throw StateError(
          'Return quantity cannot exceed the remaining invoice quantity.');
    }

    final cumulativeReturned = <String, double>{...previouslyReturned};
    for (final entry in requestedByProduct.entries) {
      cumulativeReturned.update(
        entry.key,
        (value) => value + entry.value,
        ifAbsent: () => entry.value,
      );
    }
    final isFullReturn = originalByProduct.entries.every((entry) =>
        (entry.value - (cumulativeReturned[entry.key] ?? 0)).abs() <= epsilon);

    final returnedSubtotal =
        selectedItems.fold<double>(0, (sum, item) => sum + item.lineTotal);
    final rawCreditAmount = (returnedSubtotal -
            (sale.subtotal <= 0
                ? 0
                : sale.discount * (returnedSubtotal / sale.subtotal)))
        .clamp(0, double.infinity)
        .toDouble();
    // Keep the credit note, sale aggregate, customer subledger, and journal
    // on the same currency precision. Previously the note/subledger kept a
    // fractional-cent value while the journal rounded it, leaving a small
    // reconciliation difference.
    final creditAmount = normalizeAccountingAmount(
      rawCreditAmount,
      sale.invoiceCurrency,
      _storeProfile,
    );
    final now = DateTime.now();
    final returnOperationKey =
        '${sale.id}:sale_return:${now.microsecondsSinceEpoch}';
    final usesAuthoritativeSqlite =
        LocalDatabaseService.isSqliteAuthoritative &&
            SqliteMigrationManager.database != null;
    final historicalProductsToReactivate = <Product>[];
    final historicalProductIds = <String>{};
    for (final item in selectedItems) {
      if (!_isHistoricalProduct(item.productId) ||
          !historicalProductIds.add(item.productId)) {
        continue;
      }
      final product = _findProductForSaleReturn(item.productId);
      if (product == null) continue;
      if (!product.isDeleted && product.isActive) continue;
      historicalProductsToReactivate.add(
        _withSyncMeta<Product>(
          product.copyWith(
            isActive: true,
            updatedAt: now,
            clearDeletedAt: true,
          ),
          now,
        ),
      );
    }
    // Legacy sales created before Unified Batch do not carry batch
    // allocations. A return is a new post-cutover stock movement, so give
    // each legacy stock line a deterministic return batch. This keeps the
    // historical product independent while satisfying the post-cutover batch
    // invariant.
    if (restoreStock && usesAuthoritativeSqlite) {
      for (var selectedIndex = 0;
          selectedIndex < selectedItems.length;
          selectedIndex += 1) {
        final item = selectedItems[selectedIndex];
        if (item.batchAllocations.isNotEmpty) continue;
        final product = _findProductForSaleReturn(item.productId);
        if (product == null || !product.trackStock) continue;
        final originalLineIndex = selectedOriginalLineIndexes[selectedIndex];
        final returnUnitCost = item.effectiveBaseQuantity > 0.000001
            ? item.lineCost / item.effectiveBaseQuantity
            : item.unitCostPerBase;
        selectedItems[selectedIndex] = SaleItem(
          productId: item.productId,
          productName: item.productName,
          unitPrice: item.unitPrice,
          quantity: item.quantity,
          unitCost: item.unitCost,
          costingMethodAtSale: item.costingMethodAtSale,
          costCurrency: item.costCurrency,
          costExchangeRate: item.costExchangeRate,
          costLayerConsumptions: item.costLayerConsumptions,
          unitName: item.unitName,
          baseQuantity: item.baseQuantity,
          conversionToBase: item.conversionToBase,
          batchAllocations: <BatchAllocation>[
            BatchAllocation(
              batchId: '$returnOperationKey:legacy-batch:$originalLineIndex',
              quantity: item.effectiveBaseQuantity,
              unitCost: returnUnitCost,
            ),
          ],
        );
      }
    }
    final returnedSaleBase = sale.copyWith(
      status: isFullReturn ? 'Returned' : 'Partially Returned',
      // Keep the original invoice lines. Returned quantities are represented by
      // immutable credit notes, so a second partial return can be validated
      // against the original quantities instead of a truncated sale payload.
      items: sale.items,
      paymentStatus: isFullReturn ? 'returned' : sale.paymentStatus,
      paidAmount: isFullReturn ? 0 : sale.paidAmount,
      cashReceivedAmount: isFullReturn ? 0 : sale.cashReceivedAmount,
      paidAmountInPaymentCurrency:
          isFullReturn ? 0 : sale.paidAmountInPaymentCurrency,
      cashReceivedAmountInPaymentCurrency:
          isFullReturn ? 0 : sale.cashReceivedAmountInPaymentCurrency,
      paidBaseAmount: isFullReturn ? 0 : sale.paidBaseAmount,
      exchangeDifferenceAmount:
          isFullReturn ? 0 : sale.exchangeDifferenceAmount,
      returnedAmount: normalizeAccountingAmount(
        sale.returnedAmount + creditAmount,
        sale.invoiceCurrency,
        _storeProfile,
      ),
      note: 'Returned on ${now.toIso8601String()}',
    );
    final returnedSale = _saleSyncMetaPreview(returnedSaleBase, now);
    final creditNoteNumber =
        (_creditNotes.length + 1).toString().padLeft(6, '0');
    var preparedCreditNote = CreditNote(
      id: 'credit_note_${now.microsecondsSinceEpoch}',
      creditNoteNo: 'CN-$creditNoteNumber',
      originalSaleId: sale.id,
      originalInvoiceNo: sale.invoiceNo,
      customerName: sale.customerName,
      customerId: sale.customerId,
      date: now,
      items: selectedItems,
      amount: creditAmount,
      currency: sale.invoiceCurrency,
      refundMethod: 'Customer balance',
      note: 'مرتجع مرتبط بالفاتورة ${sale.invoiceNo}',
      operationReferenceId: returnOperationKey,
      createdAt: now,
      updatedAt: now,
    );
    Customer? snapshotCustomer;
    for (final candidate in _customers) {
      if (candidate.id == sale.customerId && !candidate.isDeleted) {
        snapshotCustomer = candidate;
        break;
      }
    }
    final returnLegacyDefaultVatRatePercent =
        await AccountingService.readDefaultVatRatePercent();
    final returnTaxProfileIdByProductId = <String, String>{
      for (final product in _products) product.id: product.taxProfileId,
    };
    preparedCreditNote = preparedCreditNote.copyWith(
      postedSnapshot: PostedDocumentSnapshotService.forSaleReturn(
        creditNote: preparedCreditNote,
        originalSale: sale,
        profile: _storeProfile,
        customer: snapshotCustomer,
        user: _activeUser,
        role: _currentUserRole,
        originalLineIndexes: selectedOriginalLineIndexes,
        taxProfileIdByProductId: returnTaxProfileIdByProductId,
        legacyDefaultVatRatePercent: returnLegacyDefaultVatRatePercent,
      ),
    );
    final returnCogs = selectedItems.fold<double>(
      0,
      (sum, item) => sum + item.lineCost,
    );
    // The customer subledger must reverse only the slice returned by this
    // operation. `isFullReturn` describes the cumulative state after applying
    // previous credit notes plus this one; using the original sale when the
    // final partial slice completes the invoice would credit the full invoice
    // a second time and break the customer control-account reconciliation.
    final ledgerSale = sale.copyWith(
      items: selectedItems,
      discount: sale.subtotal <= 0
          ? 0
          : sale.discount * (returnedSubtotal / sale.subtotal),
      transactionAmount: 0,
      baseAmount: 0,
      paidAmount: sale.paidAmount *
          (sale.subtotal <= 0 ? 0 : returnedSubtotal / sale.subtotal),
    );
    final returnAccountId = sale.customerId.trim().isNotEmpty
        ? sale.customerId.trim()
        : sale.customerName.trim();
    final rawReturnLedgerTotal = ledgerSale.invoiceTotal > 0
        ? ledgerSale.invoiceTotal
        : ((ledgerSale.items
                    .fold<double>(0, (sum, item) => sum + item.lineTotal) -
                ledgerSale.discount)
            .clamp(0, double.infinity)
            .toDouble());
    final returnLedgerTotal = normalizeAccountingAmount(
      rawReturnLedgerTotal,
      sale.invoiceCurrency,
      _storeProfile,
    );
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
          if (historicalProductsToReactivate.isNotEmpty) {
            await BusinessSqliteStore.upsertEntityPayloads(
              sqliteDb,
              AppStore._productsKey,
              historicalProductsToReactivate
                  .map((product) => product.toJson())
                  .toList(growable: false),
              sortIndices: historicalProductsToReactivate
                  .map((product) => _productIndexById[product.id])
                  .toList(growable: false),
            );
          }
          // Revalidate the credit-note snapshot inside the same transaction.
          // This protects service/non-stock returns too: two concurrent return
          // requests must not overwrite each other's scalar credit-note list or
          // post the same logical return twice.
          final persistedCreditNotesRow = await sqliteDb.customSelect(
            '''
            SELECT value FROM settings WHERE key = ?
            UNION ALL
            SELECT value FROM local_key_values WHERE key = ?
            LIMIT 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>(AppStore._creditNotesKey),
              Variable<String>(AppStore._creditNotesKey),
            ],
          ).getSingleOrNull();
          final persistedCreditNotesRaw =
              persistedCreditNotesRow?.data['value']?.toString();
          final persistedReturned = <String, double>{};
          final persistedCreditNoteIds = <String>{};
          if (persistedCreditNotesRaw != null &&
              persistedCreditNotesRaw.trim().isNotEmpty) {
            final decoded = jsonDecode(persistedCreditNotesRaw);
            if (decoded is List) {
              for (final rawNote in decoded) {
                final note = CreditNote.fromJson(
                  Map<String, dynamic>.from(rawNote as Map),
                );
                persistedCreditNoteIds.add(note.id);
                if (note.originalSaleId != sale.id) continue;
                final noteStatus = note.status.trim().toLowerCase();
                if (noteStatus == 'cancelled' ||
                    noteStatus == 'reversed' ||
                    noteStatus == 'void') {
                  continue;
                }
                for (final noteItem in note.items) {
                  persistedReturned.update(
                    noteItem.productId,
                    (value) => value + noteItem.quantity,
                    ifAbsent: () => noteItem.quantity,
                  );
                }
              }
            }
          }
          final inMemoryCreditNoteIds =
              _creditNotes.map((note) => note.id).toSet();
          if (persistedCreditNoteIds.length != inMemoryCreditNoteIds.length ||
              persistedCreditNoteIds
                  .any((id) => !inMemoryCreditNoteIds.contains(id))) {
            throw StateError(
              'Credit-note history changed concurrently; reload the sale and retry.',
            );
          }
          final returnSnapshotKeys = <String>{
            ...previouslyReturned.keys,
            ...persistedReturned.keys,
          };
          for (final productId in returnSnapshotKeys) {
            if (((persistedReturned[productId] ?? 0) -
                        (previouslyReturned[productId] ?? 0))
                    .abs() >
                epsilon) {
              throw StateError(
                'Sale return changed concurrently; reload the sale and retry.',
              );
            }
          }

          // Re-check the reversible stock quantity inside the same SQLite
          // transaction before restoring any batch/cost state. This closes the
          // double-submit/concurrent-return window: a second transaction sees
          // the first return movement and fails before it can restore stock.
          for (var selectedIndex = 0;
              selectedIndex < selectedItems.length;
              selectedIndex += 1) {
            final item = selectedItems[selectedIndex];
            final originalLineIndex =
                selectedOriginalLineIndexes[selectedIndex];
            final product = _findProductForSaleReturn(item.productId);
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
              final sourceHasBatch =
                  sale.items[originalLineIndex].batchAllocations.isNotEmpty;
              final hasBatch = sourceHasBatch && allocation.batchId.isNotEmpty;
              final sourceMovementId = _saleStockMovementId(
                sale: sale,
                item: item,
                allocation: allocation,
                lineIndex: originalLineIndex,
              );
              final reversible =
                  await _remainingReversibleStockQuantityInTransaction(
                sqliteDb,
                sourceMovementId,
              );
              if (reversible == null) {
                if (hasBatch) {
                  throw StateError(
                    'Original unified-batch sale movement is missing; sale return was rolled back.',
                  );
                }
                continue;
              }
              if (allocation.quantity > reversible + epsilon) {
                throw StateError(
                  'Sale return quantity changed concurrently; reload the sale and retry.',
                );
              }
            }
          }

          final legacyCostItems = selectedItems
              .where((item) =>
                  item.batchAllocations.isEmpty &&
                  (_findProductForSaleReturn(item.productId)?.trackStock ??
                      false))
              .toList(growable: false);
          if (legacyCostItems.isNotEmpty) {
            await _restoreInventoryCostLayersFromSaleItemsInTransaction(
              sqliteDb,
              legacyCostItems,
              now,
              originalSaleDate: sale.date,
              restorationSourceType: 'sale_return_rebase',
              restorationSourceId: returnOperationKey,
              preserveSaleProductIds: true,
            );
          }
          for (var selectedIndex = 0;
              selectedIndex < selectedItems.length;
              selectedIndex += 1) {
            final item = selectedItems[selectedIndex];
            final originalLineIndex =
                selectedOriginalLineIndexes[selectedIndex];
            final product = _findProductForSaleReturn(item.productId);
            if (product == null) {
              throw StateError('Product ${item.productId} was not found.');
            }
            if (!product.trackStock) continue;
            if (item.batchAllocations.isNotEmpty) {
              final sourceHasBatch =
                  sale.items[originalLineIndex].batchAllocations.isNotEmpty;
              if (sourceHasBatch) {
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
              } else {
                for (final allocation in item.batchAllocations) {
                  await batchService.addUnifiedBatchStockInTransaction(
                    product: product,
                    warehouseId: sale.warehouseId.isEmpty
                        ? Warehouse.defaultId
                        : sale.warehouseId,
                    batchId: allocation.batchId,
                    quantity: allocation.quantity,
                    unitCost: allocation.unitCost,
                    sourceType: 'sale_return_legacy_batch',
                    sourceId: returnOperationKey,
                    sourceLineId:
                        '${sale.id}:line:$originalLineIndex:legacy-batch',
                    receivedAt: now,
                    storeId: appIdentity.storeId,
                    branchId: appIdentity.branchId,
                    deviceId: _deviceId,
                  );
                }
              }
            }
            final movementAllocations = item.batchAllocations.isEmpty
                ? <BatchAllocation>[
                    BatchAllocation(
                      batchId: '',
                      quantity: item.effectiveBaseQuantity,
                    )
                  ]
                : item.batchAllocations;
            final returnedUnitCost = item.effectiveBaseQuantity > 0.000001
                ? item.lineCost / item.effectiveBaseQuantity
                : item.unitCostPerBase;
            for (var batchIndex = 0;
                batchIndex < movementAllocations.length;
                batchIndex += 1) {
              final allocation = movementAllocations[batchIndex];
              final hasBatch = allocation.batchId.isNotEmpty;
              final sourceMovementId = _saleStockMovementId(
                sale: sale,
                item: item,
                allocation: allocation,
                lineIndex: originalLineIndex,
              );
              if (!hasBatch) {
                final reversible =
                    await _remainingReversibleStockQuantityInTransaction(
                  sqliteDb,
                  sourceMovementId,
                );
                if (reversible == null) continue;
              }
              final movementId =
                  '$returnOperationKey:$originalLineIndex:$batchIndex';
              final returnMovement = StockMovement(
                id: movementId,
                productId: item.productId,
                productName: item.productName,
                type: 'sale_return',
                quantity: allocation.quantity,
                date: now,
                referenceId: sale.id,
                referenceNo: sale.invoiceNo,
                reason: 'Sale returned',
                unitCost: hasBatch ? allocation.unitCost : returnedUnitCost,
                warehouseId: sale.warehouseId.isEmpty
                    ? Warehouse.defaultId
                    : sale.warehouseId,
                warehouseName: sale.warehouseName.isEmpty
                    ? Warehouse.defaultName
                    : sale.warehouseName,
                batchId: allocation.batchId,
                movementGroupId: returnOperationKey,
                documentLineId: '${sale.id}-line-$originalLineIndex',
                sourceMovementId: sourceMovementId,
                reversalOfMovementId: sourceMovementId,
                idempotencyKey: movementId,
                createdAt: now,
                updatedAt: now,
                deviceId: _deviceId,
                syncStatus: 'pending',
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                lastModifiedByDeviceId: _deviceId,
              );
              await stockService.recordMovementsInTransaction(
                operationType: 'sale_return',
                documentType: 'sale',
                documentId: sale.id,
                movementGroupId: returnOperationKey,
                idempotencyKey: movementId,
                movements: <StockMovement>[returnMovement],
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                deviceId: _deviceId,
              );
            }
            if (item.batchAllocations.isNotEmpty) {
              await batchService.assertWarehouseBatchBalanceInTransaction(
                productId: item.productId,
                warehouseId: sale.warehouseId.isEmpty
                    ? Warehouse.defaultId
                    : sale.warehouseId,
                storeId: appIdentity.storeId,
              );
            }
          }
          await BusinessSqliteStore.upsertEntityPayloads(
            sqliteDb,
            AppStore._salesKey,
            <Map<String, dynamic>>[returnedSale.toJson()],
            sortIndices: <int?>[index == -1 ? 0 : index],
          );
          await BusinessSqliteStore.saveKeyJson(
            sqliteDb,
            AppStore._creditNotesKey,
            jsonEncode(<CreditNote>[..._creditNotes, preparedCreditNote]
                .map((item) => item.toJson())
                .toList()),
          );
          final returnJournalId = await AccountingService.recordSaleReturn(
            sale: sale,
            returnReferenceId: preparedCreditNote.id,
            date: now,
            returnAmount: creditAmount,
            returnCogs: returnCogs,
            returnedItems: selectedItems,
            returnSnapshot: preparedCreditNote.postedSnapshot,
            createdBy: _deviceId,
            withinExistingTransaction: true,
          );
          if ((creditAmount > 0 || returnCogs > 0) &&
              returnJournalId.trim().isEmpty) {
            throw StateError(
              'Sale return journal was not persisted; the return transaction was rolled back.',
            );
          }
          if (creditAmount > 0 || returnCogs > 0) {
            await _requirePostedJournalInTransaction(
              sqliteDb,
              referenceType: 'sale_return',
              referenceId: preparedCreditNote.id,
              failureMessage:
                  'Sale return journal is missing; the return transaction was rolled back.',
            );
          }
          if (returnAccountId.isNotEmpty && returnLedgerTotal > 0) {
            await _persistAccountTransactionInExistingTransaction(
              sqliteDb,
              AccountTransaction(
                id: '${sale.id}-sale-return-${preparedCreditNote.id}',
                accountType: 'customer',
                accountId: returnAccountId,
                accountName: sale.customerName,
                date: now,
                type: 'saleReturn',
                referenceId: sale.id,
                referenceNo: sale.invoiceNo,
                credit: returnLedgerTotal,
                currency: sale.invoiceCurrency,
                note: 'Sale return ${sale.invoiceNo}',
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
        for (final product in historicalProductsToReactivate) {
          final productIndex = _productIndexById[product.id];
          if (productIndex != null) {
            _products[productIndex] = product;
          }
        }
        for (final item in selectedItems) {
          _restoreInventoryCostLayersFromSaleItem(item, now);
        }
        for (var selectedIndex = 0;
            selectedIndex < selectedItems.length;
            selectedIndex += 1) {
          final item = selectedItems[selectedIndex];
          final originalLineIndex = selectedOriginalLineIndexes[selectedIndex];
          final productIndex = _productIndexById[item.productId];
          if (productIndex == null) continue;
          final product = _products[productIndex];
          if (!product.trackStock) continue;
          _products[productIndex] = _withSyncMeta<Product>(
            product.copyWith(
              stock: product.stock + item.effectiveBaseQuantity,
            ),
            now,
          );
          _addStockMovement(
            StockMovement(
              id: '$returnOperationKey:$originalLineIndex',
              productId: item.productId,
              productName: item.productName,
              type: 'sale_return',
              quantity: item.effectiveBaseQuantity,
              date: now,
              referenceId: sale.id,
              referenceNo: sale.invoiceNo,
              reason: 'Sale returned',
              unitCost: item.unitCostPerBase,
              warehouseId: sale.warehouseId.isEmpty
                  ? Warehouse.defaultId
                  : sale.warehouseId,
              warehouseName: sale.warehouseName.isEmpty
                  ? Warehouse.defaultName
                  : sale.warehouseName,
              movementGroupId: returnOperationKey,
              documentLineId: '${sale.id}-line-$originalLineIndex',
              sourceMovementId:
                  '${sale.id}-${_operationalProductIdForStorage(item.productId)}-sale-$originalLineIndex',
              reversalOfMovementId:
                  '${sale.id}-${_operationalProductIdForStorage(item.productId)}-sale-$originalLineIndex',
              idempotencyKey: '$returnOperationKey:$originalLineIndex',
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
        selectedItems.map((item) => item.productId),
      );
    }
    _recordSyncChange(
      entityType: 'sale',
      entityId: id,
      operation: 'return',
      payload: returnedSale.toJson(),
    );
    if (index != -1) {
      _sales[index] = returnedSale;
      _touchDataRevisions(sales: true);
    }
    late CreditNote creditNote;
    final authoritativeSqlite = LocalDatabaseService.isSqliteAuthoritative &&
        SqliteMigrationManager.database != null;
    if (authoritativeSqlite) {
      if (!restoreStock) {
        final sqliteDb = SqliteMigrationManager.database!;
        await sqliteDb.transaction(() async {
          if (historicalProductsToReactivate.isNotEmpty) {
            await BusinessSqliteStore.upsertEntityPayloads(
              sqliteDb,
              AppStore._productsKey,
              historicalProductsToReactivate
                  .map((product) => product.toJson())
                  .toList(growable: false),
              sortIndices: historicalProductsToReactivate
                  .map((product) => _productIndexById[product.id])
                  .toList(growable: false),
            );
          }
          await BusinessSqliteStore.upsertEntityPayloads(
            sqliteDb,
            AppStore._salesKey,
            <Map<String, dynamic>>[returnedSale.toJson()],
            sortIndices: <int?>[index == -1 ? 0 : index],
          );
          await BusinessSqliteStore.saveKeyJson(
            sqliteDb,
            AppStore._creditNotesKey,
            jsonEncode(<CreditNote>[..._creditNotes, preparedCreditNote]
                .map((item) => item.toJson())
                .toList()),
          );
          final returnJournalId = await AccountingService.recordSaleReturn(
            sale: sale,
            returnReferenceId: preparedCreditNote.id,
            date: now,
            returnAmount: creditAmount,
            returnCogs: returnCogs,
            returnedItems: selectedItems,
            returnSnapshot: preparedCreditNote.postedSnapshot,
            createdBy: _deviceId,
            withinExistingTransaction: true,
          );
          if ((creditAmount > 0 || returnCogs > 0) &&
              returnJournalId.trim().isEmpty) {
            throw StateError(
              'Sale return journal was not persisted; the return transaction was rolled back.',
            );
          }
          if (creditAmount > 0 || returnCogs > 0) {
            await _requirePostedJournalInTransaction(
              sqliteDb,
              referenceType: 'sale_return',
              referenceId: preparedCreditNote.id,
              failureMessage:
                  'Sale return journal is missing; the return transaction was rolled back.',
            );
          }
          if (returnAccountId.isNotEmpty && returnLedgerTotal > 0) {
            await _persistAccountTransactionInExistingTransaction(
              sqliteDb,
              AccountTransaction(
                id: '${sale.id}-sale-return-${preparedCreditNote.id}',
                accountType: 'customer',
                accountId: returnAccountId,
                accountName: sale.customerName,
                date: now,
                type: 'saleReturn',
                referenceId: sale.id,
                referenceNo: sale.invoiceNo,
                credit: returnLedgerTotal,
                currency: sale.invoiceCurrency,
                note: 'Sale return ${sale.invoiceNo}',
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
      creditNote = preparedCreditNote;
      _creditNotes.add(creditNote);
      // Sale-return ledger was committed inside the authoritative SQLite transaction.
    } else {
      creditNote = await _issueCreditNote(
        originalSale: sale,
        items: selectedItems,
        amount: creditAmount,
        refundMethod: 'Customer balance',
        note: 'مرتجع مرتبط بالفاتورة ${sale.invoiceNo}',
      );
      await AccountingService.recordSaleReturn(
        sale: sale,
        returnReferenceId: creditNote.id,
        date: now,
        returnAmount: creditAmount,
        returnCogs: returnCogs,
        returnedItems: selectedItems,
        returnSnapshot: preparedCreditNote.postedSnapshot,
        createdBy: _deviceId,
      );
      await _recordSaleCancelLedger(
        ledgerSale,
        now,
        isReturn: true,
        returnReferenceId: creditNote.id,
      );
    }
    final productDerivedData = !authoritativeSqlite &&
        restoreStock &&
        selectedItems.any((item) => item.costLayerConsumptions.isNotEmpty);
    await _saveDirty(
      products: restoreStock,
      productDerivedData: productDerivedData,
      sales: !authoritativeSqlite,
      stockMovements: false,
      accountTransactions: !authoritativeSqlite,
      sync: true,
    );
    if (authoritativeSqlite) {
      await refreshAfterDatabaseChange(AppStore._stockMovementsKey);
      await _refreshAccountTransactionsFromSqlite();
    }
    if (historicalProductsToReactivate.isNotEmpty) {
      if (authoritativeSqlite) {
        await refreshAfterDatabaseChange(AppStore._productsKey);
        if (restoreStock) {
          await _refreshProductStockCompatibilityCache(
            selectedItems.map((item) => item.productId),
          );
        }
      } else {
        _touchDataRevisions(products: true);
      }
      for (final product in historicalProductsToReactivate) {
        _recordSyncChange(
          entityType: 'product',
          entityId: product.id,
          operation: 'restore_for_sale_return',
          payload: product.toJson(),
        );
      }
    }
    notifyListeners();
    return creditNote;
  }
}
