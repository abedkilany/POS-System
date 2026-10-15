part of 'app_store.dart';

extension _AppStoreSplitSalesReturnsPart6 on AppStore {
  Future<CreditNote> editSaleReturn({
    required String creditNoteId,
    required int expectedVersion,
    required Map<String, double> returnedQuantities,
  }) async {
    requirePermission(AppPermission.salesEdit);
    requirePermission(AppPermission.salesCancel);
    requireSensitiveActionAuthorization(SensitiveAction.saleReverse);
    await ensureCreditNotesLoaded();
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw StateError(
        'Editing a posted sale return requires the authoritative SQLite store.',
      );
    }
    const epsilon = 0.000001;
    final normalizedCreditNoteId = creditNoteId.trim();
    if (normalizedCreditNoteId.isEmpty) {
      throw ArgumentError('Credit note id is required.');
    }

    late CreditNote currentNote;
    late CreditNote updatedNote;
    late Sale sale;
    late Sale updatedSale;
    late int persistedNoteIndex;
    late List<CreditNote> authoritativeNotes;
    late List<SaleItem> selectedItems;
    late List<int> selectedOriginalLineIndexes;
    late String currentOperationReferenceId;
    late String newOperationReferenceId;
    late String currentJournalReferenceId;
    late String newJournalReferenceId;
    late int nextVersion;
    var newReturnCogs = 0.0;
    var newReturnLedgerAmount = 0.0;
    var oldReturnLedgerAmount = 0.0;
    var newReturnAmount = 0.0;
    var committedNewMovements = const <StockMovement>[];

    final stockService = StockTransactionService(
      db,
      deviceId: _deviceId,
      defaultStoreId: appIdentity.storeId,
      defaultBranchId: appIdentity.branchId,
      defaultSyncTarget: _stockTransactionSyncTarget,
      allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
    );
    final batchService = BatchInventoryService(db);

    await db.transaction(() async {
      updatedNote = await PostedDocumentEditPipeline<CreditNote>(
        loadAuthoritative: () async {
          final persistedCreditNotesRow = await db.customSelect(
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
          final raw = persistedCreditNotesRow?.data['value']?.toString() ?? '';
          authoritativeNotes = <CreditNote>[];
          if (raw.trim().isNotEmpty) {
            final decoded = jsonDecode(raw);
            if (decoded is List) {
              authoritativeNotes = decoded
                  .whereType<Map>()
                  .map(
                    (item) => CreditNote.fromJson(
                      Map<String, dynamic>.from(item),
                    ),
                  )
                  .toList();
            }
          }
          persistedNoteIndex = authoritativeNotes.indexWhere(
            (note) => note.id == normalizedCreditNoteId,
          );
          if (persistedNoteIndex == -1) {
            throw StateError('Sale return credit note was not found.');
          }
          currentNote = authoritativeNotes[persistedNoteIndex];
          final saleIndex = _sales.indexWhere(
            (item) => item.id == currentNote.originalSaleId,
          );
          final loadedSale = saleIndex == -1
              ? await _saleByIdFromSqlite(currentNote.originalSaleId)
              : _sales[saleIndex];
          if (loadedSale == null) {
            throw StateError('Original sale for this return was not found.');
          }
          sale = loadedSale;
          currentOperationReferenceId = currentNote.operationReferenceId
                  .trim()
                  .isNotEmpty
              ? currentNote.operationReferenceId.trim()
              : '${sale.id}:sale_return:${currentNote.date.microsecondsSinceEpoch}';
          return currentNote;
        },
        validatePermission: (_) async {
          requirePermission(AppPermission.salesEdit);
          requirePermission(AppPermission.salesCancel);
        },
        validateVersion: (note) async {
          if (note.version != expectedVersion) {
            throw StateError(
              'Sale return changed concurrently. Reload it before editing.',
            );
          }
          nextVersion = note.version + 1;
          currentJournalReferenceId = note.version <= 1
              ? note.id
              : '${note.id}:sale_return_edit:v${note.version}';
          newJournalReferenceId = '${note.id}:sale_return_edit:v$nextVersion';
          newOperationReferenceId =
              '${sale.id}:sale_return_edit:${note.id}:v$nextVersion';
        },
        validateDependencies: (note) async {
          final status = note.status.trim().toLowerCase();
          if (status == 'cancelled' ||
              status == 'reversed' ||
              status == 'void') {
            throw StateError('Only an active sale return can be edited.');
          }
          final activeForSale = authoritativeNotes
              .where(
                (candidate) =>
                    candidate.originalSaleId == sale.id &&
                    !<String>{'cancelled', 'reversed', 'void'}
                        .contains(candidate.status.trim().toLowerCase()),
              )
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));
          if (activeForSale.isEmpty || activeForSale.last.id != note.id) {
            throw StateError(
              'Only the latest active return for a sale can be edited safely. Reverse newer returns first.',
            );
          }
          if (returnedQuantities.isEmpty ||
              returnedQuantities.values.every((value) => value <= epsilon)) {
            throw ArgumentError(
              'At least one returned quantity must be greater than zero.',
            );
          }
          final originalByProduct = <String, double>{};
          for (final item in sale.items) {
            originalByProduct.update(
              item.productId,
              (value) => value + item.quantity,
              ifAbsent: () => item.quantity,
            );
          }
          final priorByProduct = <String, double>{};
          for (final candidate in activeForSale) {
            if (candidate.id == note.id) continue;
            for (final item in candidate.items) {
              priorByProduct.update(
                item.productId,
                (value) => value + item.quantity,
                ifAbsent: () => item.quantity,
              );
            }
          }
          for (final entry in returnedQuantities.entries) {
            final original = originalByProduct[entry.key];
            if (original == null) {
              throw ArgumentError(
                'Returned product ${entry.key} is not on the original sale.',
              );
            }
            final requested = entry.value;
            final available = (original - (priorByProduct[entry.key] ?? 0))
                .clamp(0, double.infinity)
                .toDouble();
            if (!requested.isFinite ||
                requested < 0 ||
                requested > available + epsilon) {
              throw ArgumentError(
                'Edited return quantity for ${entry.key} exceeds the remaining invoice quantity ($available).',
              );
            }
          }

          final priorRemaining = <String, double>{...priorByProduct};
          final requestRemaining = <String, double>{
            for (final entry in returnedQuantities.entries)
              if (entry.value > epsilon) entry.key: entry.value,
          };
          selectedItems = <SaleItem>[];
          selectedOriginalLineIndexes = <int>[];
          for (var originalLineIndex = 0;
              originalLineIndex < sale.items.length;
              originalLineIndex += 1) {
            final item = sale.items[originalLineIndex];
            var priorForProduct = priorRemaining[item.productId] ?? 0;
            final priorOnLine = min(item.quantity, priorForProduct);
            priorRemaining[item.productId] = (priorForProduct - priorOnLine)
                .clamp(0, double.infinity)
                .toDouble();
            final lineRemaining = (item.quantity - priorOnLine)
                .clamp(0, double.infinity)
                .toDouble();
            final requestedForProduct = requestRemaining[item.productId] ?? 0;
            final requestedOnLine = min(lineRemaining, requestedForProduct);
            requestRemaining[item.productId] =
                (requestedForProduct - requestedOnLine)
                    .clamp(0, double.infinity)
                    .toDouble();
            if (requestedOnLine <= epsilon) continue;
            final basePerSaleUnit = item.quantity <= epsilon
                ? item.conversionToBase
                : item.effectiveBaseQuantity / item.quantity;
            final priorBaseOnLine = priorOnLine * basePerSaleUnit;
            final requestedBase = requestedOnLine * basePerSaleUnit;
            var selected = SaleItem(
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
            );
            final product = _findProductForSaleReturn(selected.productId);
            if (product != null &&
                product.trackStock &&
                selected.batchAllocations.isEmpty) {
              final returnUnitCost = selected.effectiveBaseQuantity > epsilon
                  ? selected.lineCost / selected.effectiveBaseQuantity
                  : selected.unitCostPerBase;
              selected = SaleItem(
                productId: selected.productId,
                productName: selected.productName,
                unitPrice: selected.unitPrice,
                quantity: selected.quantity,
                unitCost: selected.unitCost,
                costingMethodAtSale: selected.costingMethodAtSale,
                costCurrency: selected.costCurrency,
                costExchangeRate: selected.costExchangeRate,
                costLayerConsumptions: selected.costLayerConsumptions,
                unitName: selected.unitName,
                baseQuantity: selected.baseQuantity,
                conversionToBase: selected.conversionToBase,
                batchAllocations: <BatchAllocation>[
                  BatchAllocation(
                    batchId:
                        '$newOperationReferenceId:legacy-batch:$originalLineIndex',
                    quantity: selected.effectiveBaseQuantity,
                    unitCost: returnUnitCost,
                  ),
                ],
              );
            }
            selectedItems.add(selected);
            selectedOriginalLineIndexes.add(originalLineIndex);
          }
          if (selectedItems.isEmpty ||
              requestRemaining.values.any((value) => value > epsilon)) {
            throw StateError(
              'Edited return quantity cannot exceed the remaining invoice quantity.',
            );
          }

          final activeMovements =
              (await BusinessSqliteStore.readStockMovements(db))
                  .where(
                    (movement) =>
                        movement.movementGroupId ==
                            currentOperationReferenceId &&
                        movement.type == 'sale_return' &&
                        movement.reversalOfMovementId.isNotEmpty,
                  )
                  .toList(growable: false);
          final allMovements = await BusinessSqliteStore.readStockMovements(db);
          final reversedIds = <String>{
            for (final movement in allMovements)
              if (movement.reversalOfMovementId.trim().isNotEmpty)
                movement.reversalOfMovementId.trim(),
          };
          final stillActive = activeMovements
              .where((movement) => !reversedIds.contains(movement.id))
              .toList(growable: false);
          if (stillActive.isEmpty &&
              note.items.any((item) {
                final product = _findProductForSaleReturn(item.productId);
                return product?.trackStock ?? false;
              })) {
            throw StateError(
              'Active stock movements for this sale return are missing.',
            );
          }
          for (final movement in stillActive) {
            if (movement.batchId.trim().isEmpty) {
              throw StateError(
                'Historical non-batch sale returns cannot be edited safely.',
              );
            }
            final balanceRow = await db.customSelect(
              '''
              SELECT COALESCE(quantity, 0) AS quantity
              FROM inventory_batch_balances
              WHERE store_id = ? AND warehouse_id = ?
                AND product_id = ? AND batch_id = ?
              LIMIT 1
              ''',
              variables: <Variable<Object>>[
                Variable<String>(appIdentity.storeId),
                Variable<String>(movement.warehouseId),
                Variable<String>(movement.productId),
                Variable<String>(movement.batchId),
              ],
            ).getSingleOrNull();
            final available =
                (balanceRow?.data['quantity'] as num? ?? 0).toDouble();
            if (available + epsilon < movement.quantity) {
              throw StateError(
                'Returned stock has moved downstream and this return cannot be edited until the downstream movement is reversed.',
              );
            }
          }
          final journal = await db.customSelect(
            '''
            SELECT id
            FROM journal_entries je
            WHERE je.reference_type = 'sale_return'
              AND je.reference_id = ?
              AND je.deleted_at = '' AND je.status = 'posted'
              AND NOT EXISTS (
                SELECT 1 FROM journal_entries rev
                WHERE rev.reversed_entry_id = je.id
                  AND rev.deleted_at = '' AND rev.status = 'posted'
              )
            LIMIT 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>(currentJournalReferenceId),
            ],
          ).getSingleOrNull();
          if (journal == null) {
            throw StateError(
              'Active accounting journal for this sale return is missing.',
            );
          }
          final returnAccountId = sale.customerId.trim().isNotEmpty
              ? sale.customerId.trim()
              : sale.customerName.trim();
          if (returnAccountId.isNotEmpty) {
            final currentLedgerId = note.version <= 1
                ? '${sale.id}-sale-return-${note.id}'
                : '${sale.id}-sale-return-${note.id}-edit-v${note.version}';
            final ledgerRow = await db.customSelect(
              '''
              SELECT debit, credit
              FROM account_transactions
              WHERE id = ? AND deleted_at = ''
              LIMIT 1
              ''',
              variables: <Variable<Object>>[
                Variable<String>(currentLedgerId),
              ],
            ).getSingleOrNull();
            if (ledgerRow == null) {
              throw StateError(
                'Customer ledger entry for this sale return is missing.',
              );
            }
            oldReturnLedgerAmount =
                ((ledgerRow.data['credit'] as num? ?? 0).toDouble() -
                        (ledgerRow.data['debit'] as num? ?? 0).toDouble())
                    .abs();
          }
        },
        reverseOperationalEffects: (_) async {
          final all = await BusinessSqliteStore.readStockMovements(db);
          final reversedIds = <String>{
            for (final movement in all)
              if (movement.reversalOfMovementId.trim().isNotEmpty)
                movement.reversalOfMovementId.trim(),
          };
          final active = all
              .where(
                (movement) =>
                    movement.movementGroupId == currentOperationReferenceId &&
                    movement.type == 'sale_return' &&
                    !reversedIds.contains(movement.id),
              )
              .toList(growable: false);
          final now = DateTime.now();
          for (final movement in active) {
            final product = _findProductById(movement.productId);
            if (product == null) {
              throw StateError('Returned product no longer exists.');
            }
            await batchService.reverseUnifiedMovementEffectInTransaction(
              product: product,
              warehouseId: movement.warehouseId,
              batchId: movement.batchId,
              movementQuantity: movement.quantity,
              unitCost: movement.unitCost,
              reversedAt: now,
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              deviceId: _deviceId,
            );
            await stockService.recordReversalInTransaction(
              originalMovement: movement,
              operationType: 'sale_return_edit_reversal',
              documentType: 'sale_return',
              documentId: currentNote.id,
              reason: 'Sale return edited',
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              deviceId: _deviceId,
              syncTarget: _stockTransactionSyncTarget,
            );
            await batchService.assertWarehouseBatchBalanceInTransaction(
              productId: movement.productId,
              warehouseId: movement.warehouseId,
              storeId: appIdentity.storeId,
            );
          }
        },
        reverseAccountingEffects: (_) async {
          await AccountingService.reverseEntryForReference(
            referenceType: 'sale_return',
            referenceId: currentNote.id,
            reason: 'Sale return edited',
            createdBy: _deviceId,
            adjustCashLocationBalance: false,
            notifyChange: false,
            withinExistingTransaction: true,
          );
          final returnAccountId = sale.customerId.trim().isNotEmpty
              ? sale.customerId.trim()
              : sale.customerName.trim();
          if (returnAccountId.isNotEmpty && oldReturnLedgerAmount > epsilon) {
            final now = DateTime.now();
            await _persistAccountTransactionInExistingTransaction(
              db,
              AccountTransaction(
                id: '${sale.id}-sale-return-${currentNote.id}-edit-reversal-v$nextVersion',
                accountType: 'customer',
                accountId: returnAccountId,
                accountName: sale.customerName,
                date: now,
                type: 'saleReturnEditReversal',
                referenceId: sale.id,
                referenceNo: sale.invoiceNo,
                debit: oldReturnLedgerAmount,
                currency: sale.invoiceCurrency,
                note: 'Reversal before editing ${currentNote.creditNoteNo}',
                createdAt: now,
                updatedAt: now,
                deviceId: _deviceId,
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                lastModifiedByDeviceId: _deviceId,
              ),
            );
          }
        },
        applyChanges: (note) async {
          final returnedSubtotal = selectedItems.fold<double>(
            0,
            (sum, item) => sum + item.lineTotal,
          );
          final rawReturnAmount = (returnedSubtotal -
                  (sale.subtotal <= 0
                      ? 0
                      : sale.discount * (returnedSubtotal / sale.subtotal)))
              .clamp(0, double.infinity)
              .toDouble();
          newReturnAmount = normalizeAccountingAmount(
            rawReturnAmount,
            sale.invoiceCurrency,
            _storeProfile,
          );
          newReturnCogs = selectedItems.fold<double>(
            0,
            (sum, item) => sum + item.lineCost,
          );
          newReturnLedgerAmount = newReturnAmount;
          final now = DateTime.now();
          return note.copyWith(
            date: now,
            items: selectedItems,
            amount: newReturnAmount,
            note: 'Edited return for invoice ${sale.invoiceNo}',
            version: nextVersion,
            operationReferenceId: newOperationReferenceId,
            updatedAt: now,
            clearPostedSnapshot: true,
          );
        },
        rebuildOperationalEffects: (note) async {
          final now = DateTime.now();
          final movements = <StockMovement>[];
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
            for (final allocation in item.batchAllocations) {
              final sourceMovementId = _saleStockMovementId(
                sale: sale,
                item: item,
                allocation: allocation,
                lineIndex: originalLineIndex,
              );
              final reversible =
                  await _remainingReversibleStockQuantityInTransaction(
                db,
                sourceMovementId,
              );
              if (reversible == null ||
                  allocation.quantity > reversible + epsilon) {
                throw StateError(
                  'Original sale stock movement is no longer reversible for the edited return.',
                );
              }
            }
            final warehouseId = sale.warehouseId.isEmpty
                ? Warehouse.defaultId
                : sale.warehouseId;
            final sourceHasBatch =
                sale.items[originalLineIndex].batchAllocations.isNotEmpty;
            if (sourceHasBatch) {
              await batchService.restoreUnifiedInTransaction(
                product: product,
                warehouseId: warehouseId,
                allocations: item.batchAllocations,
                restoredAt: now,
                storeId: appIdentity.storeId,
                deviceId: _deviceId,
              );
            } else {
              for (final allocation in item.batchAllocations) {
                await batchService.addUnifiedBatchStockInTransaction(
                  product: product,
                  warehouseId: warehouseId,
                  batchId: allocation.batchId,
                  quantity: allocation.quantity,
                  unitCost: allocation.unitCost,
                  sourceType: 'sale_return_legacy_batch',
                  sourceId: newOperationReferenceId,
                  sourceLineId:
                      '${sale.id}:line:$originalLineIndex:legacy-batch',
                  receivedAt: now,
                  storeId: appIdentity.storeId,
                  branchId: appIdentity.branchId,
                  deviceId: _deviceId,
                );
              }
            }
            for (var batchIndex = 0;
                batchIndex < item.batchAllocations.length;
                batchIndex += 1) {
              final allocation = item.batchAllocations[batchIndex];
              final sourceMovementId = _saleStockMovementId(
                sale: sale,
                item: item,
                allocation: allocation,
                lineIndex: originalLineIndex,
              );
              movements.add(
                StockMovement(
                  id: '$newOperationReferenceId:$originalLineIndex:$batchIndex',
                  productId: item.productId,
                  productName: item.productName,
                  type: 'sale_return',
                  quantity: allocation.quantity,
                  date: now,
                  referenceId: sale.id,
                  referenceNo: sale.invoiceNo,
                  reason: 'Sale return edited',
                  unitCost: allocation.unitCost,
                  warehouseId: sale.warehouseId.isEmpty
                      ? Warehouse.defaultId
                      : sale.warehouseId,
                  warehouseName: sale.warehouseName.isEmpty
                      ? Warehouse.defaultName
                      : sale.warehouseName,
                  batchId: allocation.batchId,
                  movementGroupId: newOperationReferenceId,
                  documentLineId: '${sale.id}-line-$originalLineIndex',
                  sourceMovementId: sourceMovementId,
                  reversalOfMovementId: sourceMovementId,
                  idempotencyKey:
                      '$newOperationReferenceId:$originalLineIndex:$batchIndex',
                  createdAt: now,
                  updatedAt: now,
                  deviceId: _deviceId,
                  syncStatus: 'pending',
                  storeId: appIdentity.storeId,
                  branchId: appIdentity.branchId,
                  lastModifiedByDeviceId: _deviceId,
                ),
              );
            }
          }
          if (movements.isNotEmpty) {
            await stockService.recordMovementsInTransaction(
              operationType: 'sale_return_edit',
              documentType: 'sale_return',
              documentId: note.id,
              movementGroupId: newOperationReferenceId,
              idempotencyKey: newOperationReferenceId,
              movements: movements,
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              deviceId: _deviceId,
              skipExistingMovementLookup: true,
            );
          }
          final assertedProductWarehouses = <String>{};
          for (final item in selectedItems) {
            final product = _findProductForSaleReturn(item.productId);
            if (product == null || !product.trackStock) continue;
            final warehouseId = sale.warehouseId.isEmpty
                ? Warehouse.defaultId
                : sale.warehouseId;
            if (!assertedProductWarehouses.add('${product.id}::$warehouseId')) {
              continue;
            }
            await batchService.assertWarehouseBatchBalanceInTransaction(
              productId: product.id,
              warehouseId: warehouseId,
              storeId: appIdentity.storeId,
            );
          }
          committedNewMovements = List<StockMovement>.unmodifiable(movements);
          return note;
        },
        buildPostedSnapshot: (note) async {
          Customer? snapshotCustomer;
          for (final candidate in _customers) {
            if (candidate.id == sale.customerId && !candidate.isDeleted) {
              snapshotCustomer = candidate;
              break;
            }
          }
          final defaultVat =
              await AccountingService.readDefaultVatRatePercent();
          final taxProfileIdByProductId = <String, String>{
            for (final product in _products) product.id: product.taxProfileId,
          };
          return note.copyWith(
            postedSnapshot: PostedDocumentSnapshotService.forSaleReturn(
              creditNote: note,
              originalSale: sale,
              profile: _storeProfile,
              customer: snapshotCustomer,
              user: _activeUser,
              role: currentUserRole,
              originalLineIndexes: selectedOriginalLineIndexes,
              taxProfileIdByProductId: taxProfileIdByProductId,
              legacyDefaultVatRatePercent: defaultVat,
            ),
          );
        },
        repostAccounting: (note) async {
          final journalId = await AccountingService.recordSaleReturn(
            sale: sale,
            returnReferenceId: newJournalReferenceId,
            date: note.date,
            returnAmount: newReturnAmount,
            returnCogs: newReturnCogs,
            returnedItems: selectedItems,
            returnSnapshot: note.postedSnapshot,
            createdBy: _deviceId,
            withinExistingTransaction: true,
          );
          if ((newReturnAmount > epsilon || newReturnCogs > epsilon) &&
              journalId.trim().isEmpty) {
            throw StateError(
              'Edited sale return accounting journal was not persisted.',
            );
          }
        },
        rebuildDerivedState: (note) async {
          authoritativeNotes[persistedNoteIndex] = note;
          final activeNotes = authoritativeNotes.where(
            (candidate) =>
                candidate.originalSaleId == sale.id &&
                !<String>{'cancelled', 'reversed', 'void'}
                    .contains(candidate.status.trim().toLowerCase()),
          );
          final returnedByProduct = <String, double>{};
          var totalReturnedAmount = 0.0;
          for (final candidate in activeNotes) {
            totalReturnedAmount += candidate.amount;
            for (final item in candidate.items) {
              returnedByProduct.update(
                item.productId,
                (value) => value + item.quantity,
                ifAbsent: () => item.quantity,
              );
            }
          }
          final originalByProduct = <String, double>{};
          for (final item in sale.items) {
            originalByProduct.update(
              item.productId,
              (value) => value + item.quantity,
              ifAbsent: () => item.quantity,
            );
          }
          final isFullReturn = originalByProduct.entries.every(
            (entry) =>
                (entry.value - (returnedByProduct[entry.key] ?? 0)).abs() <=
                epsilon,
          );
          final originalSnapshot = sale.postedSnapshot;
          if (!isFullReturn &&
              sale.status.trim().toLowerCase() == 'returned' &&
              originalSnapshot == null) {
            throw StateError(
              'The original posted sale snapshot is required to restore payment state when changing a full return to a partial return.',
            );
          }
          final restoredPaid = originalSnapshot?.totals.paid ?? sale.paidAmount;
          final restoredPaymentStatus =
              originalSnapshot?.paymentStatus ?? sale.paymentStatus;
          final restoredCashReceived =
              (originalSnapshot?.extra['cashReceivedAmount'] as num?)
                      ?.toDouble() ??
                  sale.cashReceivedAmount;
          final restoredPaidInPaymentCurrency =
              (originalSnapshot?.extra['paidAmountInPaymentCurrency'] as num?)
                      ?.toDouble() ??
                  sale.paidAmountInPaymentCurrency;
          final restoredCashInPaymentCurrency = (originalSnapshot
                      ?.extra['cashReceivedAmountInPaymentCurrency'] as num?)
                  ?.toDouble() ??
              sale.cashReceivedAmountInPaymentCurrency;
          final restoredPaidBase =
              (originalSnapshot?.extra['paidBaseAmount'] as num?)?.toDouble() ??
                  sale.paidBaseAmount;
          final restoredExchangeDifference =
              (originalSnapshot?.extra['exchangeDifferenceAmount'] as num?)
                      ?.toDouble() ??
                  sale.exchangeDifferenceAmount;
          final now = DateTime.now();
          updatedSale = _saleSyncMetaPreview(
            sale.copyWith(
              status: isFullReturn ? 'Returned' : 'Partially Returned',
              paymentStatus: isFullReturn ? 'returned' : restoredPaymentStatus,
              paidAmount: isFullReturn ? 0 : restoredPaid,
              cashReceivedAmount: isFullReturn ? 0 : restoredCashReceived,
              paidAmountInPaymentCurrency:
                  isFullReturn ? 0 : restoredPaidInPaymentCurrency,
              cashReceivedAmountInPaymentCurrency:
                  isFullReturn ? 0 : restoredCashInPaymentCurrency,
              paidBaseAmount: isFullReturn ? 0 : restoredPaidBase,
              exchangeDifferenceAmount:
                  isFullReturn ? 0 : restoredExchangeDifference,
              returnedAmount: totalReturnedAmount,
              note: 'Return edited on ${now.toIso8601String()}',
            ),
            now,
          );
          await BusinessSqliteStore.upsertEntityPayloads(
            db,
            AppStore._salesKey,
            <Map<String, dynamic>>[updatedSale.toJson()],
            sortIndices: const <int?>[0],
          );
          await BusinessSqliteStore.saveKeyJson(
            db,
            AppStore._creditNotesKey,
            jsonEncode(
              authoritativeNotes.map((item) => item.toJson()).toList(),
            ),
          );
          final returnAccountId = sale.customerId.trim().isNotEmpty
              ? sale.customerId.trim()
              : sale.customerName.trim();
          if (returnAccountId.isNotEmpty && newReturnLedgerAmount > epsilon) {
            await _persistAccountTransactionInExistingTransaction(
              db,
              AccountTransaction(
                id: '${sale.id}-sale-return-${currentNote.id}-edit-v$nextVersion',
                accountType: 'customer',
                accountId: returnAccountId,
                accountName: sale.customerName,
                date: note.date,
                type: 'saleReturn',
                referenceId: sale.id,
                referenceNo: sale.invoiceNo,
                credit: newReturnLedgerAmount,
                currency: sale.invoiceCurrency,
                note: 'Edited sale return ${note.creditNoteNo}',
                createdAt: note.date,
                updatedAt: note.date,
                deviceId: _deviceId,
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                lastModifiedByDeviceId: _deviceId,
              ),
            );
          }
        },
        verifyIntegrity: (note) async {
          final persistedRow = await db.customSelect(
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
          final raw = persistedRow?.data['value']?.toString() ?? '';
          final decoded =
              raw.trim().isEmpty ? const <dynamic>[] : jsonDecode(raw);
          final persisted = decoded is List
              ? decoded
                  .whereType<Map>()
                  .map((item) =>
                      CreditNote.fromJson(Map<String, dynamic>.from(item)))
                  .where((item) => item.id == note.id)
                  .firstOrNull
              : null;
          if (persisted == null ||
              persisted.version != nextVersion ||
              persisted.operationReferenceId != newOperationReferenceId) {
            throw StateError(
              'Edited sale return failed document integrity verification.',
            );
          }
          if (newReturnAmount > epsilon || newReturnCogs > epsilon) {
            final journal = await db.customSelect(
              '''
              SELECT id
              FROM journal_entries je
              WHERE je.reference_type = 'sale_return'
                AND je.reference_id = ?
                AND je.deleted_at = '' AND je.status = 'posted'
                AND NOT EXISTS (
                  SELECT 1 FROM journal_entries rev
                  WHERE rev.reversed_entry_id = je.id
                    AND rev.deleted_at = '' AND rev.status = 'posted'
                )
              LIMIT 1
              ''',
              variables: <Variable<Object>>[
                Variable<String>(newJournalReferenceId),
              ],
            ).getSingleOrNull();
            if (journal == null) {
              throw StateError(
                'Edited sale return failed accounting integrity verification.',
              );
            }
          }
          for (final item in selectedItems) {
            final product = _findProductForSaleReturn(item.productId);
            if (product == null || !product.trackStock) continue;
            final expectedBase = item.effectiveBaseQuantity;
            final movementRow = await db.customSelect(
              '''
              SELECT COALESCE(SUM(quantity), 0) AS quantity
              FROM stock_movements sm
              WHERE sm.movement_group_id = ?
                AND sm.product_id = ?
                AND sm.movement_type = 'sale_return'
                AND sm.deleted_at = ''
                AND NOT EXISTS (
                  SELECT 1 FROM stock_movements rev
                  WHERE rev.reversal_of_movement_id = sm.id
                    AND rev.deleted_at = ''
                )
              ''',
              variables: <Variable<Object>>[
                Variable<String>(newOperationReferenceId),
                Variable<String>(item.productId),
              ],
            ).getSingle();
            final actual =
                (movementRow.data['quantity'] as num? ?? 0).toDouble();
            if ((actual - expectedBase).abs() > epsilon) {
              throw StateError(
                'Edited sale return failed stock integrity verification for ${item.productName}.',
              );
            }
          }
        },
      ).execute();
    });

    final noteIndex = _creditNotes.indexWhere(
      (note) => note.id == normalizedCreditNoteId,
    );
    if (noteIndex == -1) {
      _creditNotes.add(updatedNote);
    } else {
      _creditNotes[noteIndex] = updatedNote;
    }
    final saleIndex = _sales.indexWhere((item) => item.id == sale.id);
    if (saleIndex != -1) {
      _sales[saleIndex] = updatedSale;
      _touchDataRevisions(sales: true);
    }
    _recordSyncChange(
      entityType: 'sale',
      entityId: sale.id,
      operation: 'edit_return',
      payload: updatedSale.toJson(),
    );
    for (final movement in committedNewMovements) {
      _recordSyncChange(
        entityType: 'stock_movement',
        entityId: movement.id,
        operation: 'sale_return_edit',
        payload: movement.toJson(),
      );
    }
    await refreshAfterDatabaseChange(AppStore._stockMovementsKey);
    await _refreshProductStockCompatibilityCache(
      selectedItems.map((item) => item.productId),
    );
    await refreshAccountTransactionsFromSqlite();
    await _saveDirty(sync: true);
    AccountingService.notifyCommittedMutation();
    notifyListeners();
    return updatedNote;
  }
}
