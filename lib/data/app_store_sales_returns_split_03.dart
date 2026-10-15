part of 'app_store.dart';

extension _AppStoreSplitSalesReturnsPart3 on AppStore {
  Future<Sale> editPostedSale({
    required String saleId,
    required int expectedVersion,
    required String customerName,
    String customerId = '',
    required List<SaleItem> items,
    double discount = 0,
    double? originalDiscount,
    String? discountCurrency,
    double? discountExchangeRateAtEntry,
    String warehouseId = '',
    String warehouseName = '',
  }) async {
    requirePermission(AppPermission.salesEdit);
    if (!LocalDatabaseService.isSqliteAuthoritative ||
        SqliteMigrationManager.database == null) {
      throw StateError(
          'Posted sale editing requires the SQLite authoritative store.');
    }
    if (items.isEmpty) {
      throw ArgumentError('Sale must contain at least one item.');
    }
    final cleanedDiscount = discount.isFinite ? discount : 0.0;
    if (cleanedDiscount < 0) {
      throw ArgumentError('Discount cannot be negative.');
    }
    final requestedSubtotal =
        items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    final requestedCustomerId = customerId.trim().isEmpty
        ? AppStore.walkInCustomerId
        : customerId.trim();
    if (cleanedDiscount > requestedSubtotal + 0.000001) {
      throw ArgumentError('Discount cannot be greater than subtotal.');
    }
    for (final item in items) {
      if (item.quantity <= 0 ||
          item.conversionToBase <= 0 ||
          item.unitPrice < 0) {
        throw ArgumentError('Invalid sale item values.');
      }
      if (_findProductById(item.productId) == null) {
        throw ArgumentError('Product not found: ${item.productName}');
      }
    }

    await ensureCreditNotesLoaded();
    await ensureDeliveryNotesLoaded();
    final sqliteDb = SqliteMigrationManager.database!;
    final now = DateTime.now();
    final stockService = StockTransactionService(
      sqliteDb,
      deviceId: _deviceId,
      defaultStoreId: appIdentity.storeId,
      defaultBranchId: appIdentity.branchId,
      defaultSyncTarget: _stockTransactionSyncTarget,
      allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
    );
    final batchService = BatchInventoryService(sqliteDb);
    final legacyDefaultVatRatePercent =
        await AccountingService.readDefaultVatRatePercent();
    final taxProfileIdByProductId = <String, String>{
      for (final product in _products) product.id: product.taxProfileId,
    };
    final before = await _saleByIdFromSqlite(saleId);
    if (before == null) throw ArgumentError('Sale not found.');
    final beforeJson = jsonEncode(before.toJson());
    final editedMovements = <StockMovement>[];

    late Sale updated;
    await sqliteDb.transaction(() async {
      final pipeline = PostedDocumentEditPipeline<Sale>(
        loadAuthoritative: () async {
          final authoritative = await _saleByIdFromSqlite(saleId);
          if (authoritative == null) throw ArgumentError('Sale not found.');
          return authoritative;
        },
        validatePermission: (current) async {
          requirePermission(AppPermission.salesEdit);
          if (current.isCancelled || current.isDeleted) {
            throw StateError(
                'Cancelled/returned/deleted sales cannot be edited.');
          }
        },
        validateVersion: (current) async {
          if (current.version != expectedVersion) {
            throw StateError(
                'Sale changed by another user. Reload it before editing.');
          }
        },
        validateDependencies: (current) async {
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
          final raw = persistedCreditNotesRow?.data['value']?.toString() ?? '';
          if (raw.trim().isNotEmpty) {
            final decoded = jsonDecode(raw);
            if (decoded is List) {
              for (final rawNote in decoded) {
                final note = CreditNote.fromJson(
                  Map<String, dynamic>.from(rawNote as Map),
                );
                if (note.originalSaleId != current.id) continue;
                final status = note.status.trim().toLowerCase();
                if (status != 'cancelled' &&
                    status != 'reversed' &&
                    status != 'void') {
                  throw StateError(
                    'Cannot edit ${current.invoiceNo} after a sale return was posted. Reverse the return first.',
                  );
                }
              }
            }
          }
          final deliveryNote = deliveryNoteForSale(current.id);
          if (deliveryNote != null && !deliveryNote.isDeleted) {
            throw StateError(
              'Cannot edit ${current.invoiceNo} while a delivery note is linked to it. Remove/reverse the delivery note first.',
            );
          }
          if (requestedCustomerId != current.customerId.trim() &&
              requestedCustomerId != AppStore.walkInCustomerId) {
            final requestedCustomerIndex = _customers
                .indexWhere((customer) => customer.id == requestedCustomerId);
            if (requestedCustomerIndex < 0 ||
                _customers[requestedCustomerIndex].isDeleted) {
              throw StateError(
                'Cannot move ${current.invoiceNo} to an unavailable customer.',
              );
            }
          }
          final requestedWarehouseId = warehouseId.trim().isEmpty
              ? current.warehouseId.trim()
              : warehouseId.trim();
          if (requestedWarehouseId.isNotEmpty &&
              requestedWarehouseId != current.warehouseId.trim()) {
            final requestedWarehouseIndex = _warehouses
                .indexWhere((item) => item.id == requestedWarehouseId);
            if (requestedWarehouseIndex < 0 ||
                _warehouses[requestedWarehouseIndex].isDeleted ||
                !_warehouses[requestedWarehouseIndex].isActive) {
              throw StateError(
                'Cannot move ${current.invoiceNo} to an unavailable warehouse.',
              );
            }
          }
          if (current.paidAmount > 0.000001 &&
              requestedCustomerId != current.customerId.trim()) {
            throw StateError(
              'Cannot change the customer of a sale with allocated payments. Reverse the payment first.',
            );
          }
          for (var lineIndex = 0;
              lineIndex < current.items.length;
              lineIndex += 1) {
            final item = current.items[lineIndex];
            final product = _findProductById(item.productId);
            if (product == null) {
              throw StateError('Product ${item.productId} was not found.');
            }
            if (!product.trackStock) continue;
            final allocations = item.batchAllocations.isEmpty
                ? <BatchAllocation>[
                    BatchAllocation(
                      batchId: '',
                      quantity: item.effectiveBaseQuantity,
                    ),
                  ]
                : item.batchAllocations;
            for (final allocation in allocations) {
              final sourceMovementId = _saleStockMovementId(
                sale: current,
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
                throw StateError(
                  'Active stock movement is missing for ${current.invoiceNo}; sale edit was rolled back.',
                );
              }
              if (allocation.quantity > reversible + 0.000001) {
                throw StateError(
                  'Cannot edit ${current.invoiceNo}: some sold stock was already returned or reversed.',
                );
              }
            }
          }
        },
        reverseOperationalEffects: (current) async {
          final legacyCostItems = current.items
              .where((item) =>
                  item.batchAllocations.isEmpty &&
                  (_findProductById(item.productId)?.trackStock ?? false))
              .toList(growable: false);
          if (legacyCostItems.isNotEmpty) {
            await _restoreInventoryCostLayersFromSaleItemsInTransaction(
              sqliteDb,
              legacyCostItems,
              now,
              originalSaleDate: current.date,
              restorationSourceType: 'sale_edit_rebase',
              restorationSourceId:
                  '${current.id}:sale_edit:v${current.version + 1}',
            );
          }
          for (var lineIndex = 0;
              lineIndex < current.items.length;
              lineIndex += 1) {
            final item = current.items[lineIndex];
            final product = _findProductById(item.productId);
            if (product == null || !product.trackStock) continue;
            if (item.batchAllocations.isNotEmpty) {
              await batchService.restoreUnifiedInTransaction(
                product: product,
                warehouseId: current.warehouseId.isEmpty
                    ? Warehouse.defaultId
                    : current.warehouseId,
                allocations: item.batchAllocations,
                restoredAt: now,
                storeId: appIdentity.storeId,
                deviceId: _deviceId,
              );
            }
            final allocations = item.batchAllocations.isEmpty
                ? <BatchAllocation>[
                    BatchAllocation(
                      batchId: '',
                      quantity: item.effectiveBaseQuantity,
                      unitCost: item.unitCostPerBase,
                    ),
                  ]
                : item.batchAllocations;
            for (var batchIndex = 0;
                batchIndex < allocations.length;
                batchIndex += 1) {
              final allocation = allocations[batchIndex];
              final hasBatch = allocation.batchId.trim().isNotEmpty;
              final originalMovement = StockMovement(
                id: _saleStockMovementId(
                  sale: current,
                  item: item,
                  allocation: allocation,
                  lineIndex: lineIndex,
                ),
                productId: item.productId,
                productName: item.productName,
                type: 'sale',
                quantity: -allocation.quantity,
                date: current.version <= 1 ? current.date : current.updatedAt,
                referenceId: current.id,
                referenceNo: current.invoiceNo,
                reason: 'Sale invoice',
                unitCost: hasBatch ? allocation.unitCost : item.unitCostPerBase,
                warehouseId: current.warehouseId.isEmpty
                    ? Warehouse.defaultId
                    : current.warehouseId,
                warehouseName: current.warehouseName.isEmpty
                    ? Warehouse.defaultName
                    : current.warehouseName,
                batchId: allocation.batchId,
                movementGroupId: _saleMovementGroupId(current),
                documentLineId: '${current.id}-line-$lineIndex',
                idempotencyKey: _saleStockMovementIdempotencyKey(
                  sale: current,
                  lineIndex: lineIndex,
                  batchIndex: batchIndex,
                  hasBatch: hasBatch,
                ),
                createdAt: current.version <= 1
                    ? current.createdAt
                    : current.updatedAt,
                updatedAt: current.updatedAt,
                deviceId: current.deviceId,
                syncStatus: current.syncStatus,
                storeId: current.storeId,
                branchId: current.branchId,
                version: current.version,
                lastModifiedByDeviceId: current.lastModifiedByDeviceId,
              );
              await stockService.recordReversalInTransaction(
                originalMovement: originalMovement,
                operationType: 'sale_edit_reverse',
                documentType: 'sale',
                documentId: current.id,
                reason: 'Sale edit reverse v${current.version}',
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                deviceId: _deviceId,
              );
            }
            if (item.batchAllocations.isNotEmpty) {
              await batchService.assertWarehouseBatchBalanceInTransaction(
                productId: item.productId,
                warehouseId: current.warehouseId.isEmpty
                    ? Warehouse.defaultId
                    : current.warehouseId,
                storeId: appIdentity.storeId,
              );
            }
          }
        },
        reverseAccountingEffects: (current) async {
          await _requirePostedJournalInTransaction(
            sqliteDb,
            referenceType: 'sale',
            referenceId: current.id,
            includeSaleEditFamily: true,
            failureMessage:
                'Active sale journal is missing; sale edit was rolled back.',
          );
          await AccountingService.reverseSaleEntriesForSale(
            saleId: current.id,
            reason: 'Sale edited',
            createdBy: _deviceId,
            adjustCashLocationBalance: false,
            notifyChange: false,
            withinExistingTransaction: true,
          );
          await _requireNoActiveJournalInTransaction(
            sqliteDb,
            referenceType: 'sale',
            referenceId: current.id,
            includeSaleEditFamily: true,
            failureMessage:
                'Sale journal reversal did not complete; sale edit was rolled back.',
          );
        },
        applyChanges: (current) async {
          final normalizedCustomerId = requestedCustomerId;
          String normalizedCustomerName;
          if (normalizedCustomerId == AppStore.walkInCustomerId) {
            normalizedCustomerName = AppStore.walkInCustomerName;
          } else if (normalizedCustomerId == current.customerId.trim()) {
            normalizedCustomerName = customerName.trim().isEmpty
                ? current.customerName
                : customerName.trim();
          } else {
            final selectedCustomer = _customers.firstWhere(
              (customer) => customer.id == normalizedCustomerId,
            );
            normalizedCustomerName = selectedCustomer.name;
          }
          final isWalkIn = normalizedCustomerId == AppStore.walkInCustomerId;
          if (isWalkIn &&
              current.paymentMethod.trim().toLowerCase() == 'credit') {
            throw ArgumentError('Walk-in customer sales cannot be credit.');
          }
          final requestedWarehouseId = warehouseId.trim().isEmpty
              ? current.warehouseId.trim()
              : warehouseId.trim();
          final currentWarehouseRequested = requestedWarehouseId.isNotEmpty &&
              requestedWarehouseId == current.warehouseId.trim();
          final resolvedWarehouse = currentWarehouseRequested
              ? _warehouses.firstWhere(
                  (item) => item.id == requestedWarehouseId,
                  orElse: () => Warehouse(
                    id: requestedWarehouseId,
                    name: current.warehouseName.trim().isEmpty
                        ? Warehouse.defaultName
                        : current.warehouseName.trim(),
                  ),
                )
              : resolveWarehouseForSale(warehouseId: requestedWarehouseId);
          final normalizedItems = items
              .map((item) => SaleItem(
                    productId: item.productId,
                    productName: item.productName,
                    unitPrice: item.unitPrice,
                    quantity: item.quantity,
                    unitName: item.unitName,
                    baseQuantity: item.effectiveBaseQuantity,
                    conversionToBase: item.conversionToBase,
                    unitCost: 0,
                    costingMethodAtSale: _inventoryCostingMethod,
                    costCurrency: item.costCurrency,
                    costExchangeRate: 1,
                    costLayerConsumptions: const <InventoryCostLayerConsumption>[],
                    batchAllocations: const <BatchAllocation>[],
                  ))
              .toList(growable: false);
          final baseTotal = (normalizedItems.fold<double>(
                      0, (sum, item) => sum + item.lineTotal) -
                  cleanedDiscount)
              .clamp(0, double.infinity)
              .toDouble();
          final baseCurrency = current.baseCurrency.trim().isEmpty
              ? _storeProfile.baseCurrency.toUpperCase()
              : current.baseCurrency.toUpperCase();
          final invoiceCurrency = current.invoiceCurrency.trim().isEmpty
              ? baseCurrency
              : current.invoiceCurrency.toUpperCase();
          final paymentCurrency = current.paymentCurrency.trim().isEmpty
              ? invoiceCurrency
              : current.paymentCurrency.toUpperCase();
          final invoiceRate = invoiceCurrency == baseCurrency
              ? 1.0
              : (current.exchangeRateAtInvoice > 0
                  ? current.exchangeRateAtInvoice
                  : exchangeRate(
                      baseCurrency,
                      invoiceCurrency,
                      _storeProfile,
                      effectiveAt: current.date,
                    ));
          var invoiceTotal = baseTotal * invoiceRate;
          if (current.paymentMethod.trim().toLowerCase() == 'cash') {
            final paymentToInvoiceRate = paymentCurrency == invoiceCurrency
                ? 1.0
                : (current.exchangeRateAtPayment > 0
                    ? current.exchangeRateAtPayment
                    : exchangeRate(
                        paymentCurrency,
                        invoiceCurrency,
                        _storeProfile,
                        effectiveAt: current.date,
                      ));
            final paymentAmount = paymentToInvoiceRate <= 0
                ? invoiceTotal
                : invoiceTotal / paymentToInvoiceRate;
            final roundedPayment = normalizeCashAmount(
              paymentAmount,
              paymentCurrency,
              _storeProfile,
            );
            invoiceTotal = roundedPayment * paymentToInvoiceRate;
          }
          invoiceTotal = normalizeAccountingAmount(
            invoiceTotal,
            invoiceCurrency,
            _storeProfile,
          );
          if (current.paidAmount > invoiceTotal + 0.000001) {
            throw StateError(
              'Cannot reduce ${current.invoiceNo} below its already allocated payment. Reverse/refund the excess payment first.',
            );
          }
          final normalizedPaymentStatus = invoiceTotal <= 0.000001
              ? 'paid'
              : current.paidAmount <= 0.000001
                  ? 'credit'
                  : current.paidAmount + 0.000001 >= invoiceTotal
                      ? 'paid'
                      : 'partial';
          final baseAmount = invoiceRate <= 0
              ? baseTotal
              : normalizeAccountingAmount(
                  invoiceTotal / invoiceRate,
                  baseCurrency,
                  _storeProfile,
                );
          return current.copyWith(
            customerId: normalizedCustomerId,
            customerName: normalizedCustomerName,
            items: normalizedItems,
            discount: cleanedDiscount,
            originalDiscount: originalDiscount ?? cleanedDiscount,
            discountCurrency:
                (discountCurrency ?? current.discountCurrency).trim().isEmpty
                    ? baseCurrency
                    : (discountCurrency ?? current.discountCurrency)
                        .trim()
                        .toUpperCase(),
            discountExchangeRateAtEntry: discountExchangeRateAtEntry ??
                current.discountExchangeRateAtEntry,
            paymentStatus: normalizedPaymentStatus,
            transactionAmount: invoiceTotal,
            baseAmount: baseAmount,
            warehouseId: resolvedWarehouse.id,
            warehouseName: resolvedWarehouse.name.trim().isEmpty
                ? warehouseName.trim()
                : resolvedWarehouse.name,
            updatedAt: now,
            version: current.version + 1,
            lastModifiedByDeviceId: _deviceId,
            syncStatus: 'pending',
            clearPostedSnapshot: true,
          );
        },
        rebuildOperationalEffects: (candidate) async {
          final ensuredUnifiedCutovers = <String>{};
          final resolvedItems = <SaleItem>[];
          editedMovements.clear();
          for (var lineIndex = 0;
              lineIndex < candidate.items.length;
              lineIndex += 1) {
            final item = candidate.items[lineIndex];
            final product = _findProductById(item.productId);
            if (product == null) {
              throw StateError('Product ${item.productId} was not found.');
            }
            if (!product.trackStock) {
              final resolvedCost = await _resolveCostForSaleItemInTransaction(
                sqliteDb,
                item,
                now,
              );
              resolvedItems.add(SaleItem(
                productId: item.productId,
                productName: item.productName,
                unitPrice: item.unitPrice,
                quantity: item.quantity,
                unitName: item.unitName,
                baseQuantity: item.effectiveBaseQuantity,
                conversionToBase: item.conversionToBase,
                unitCost: resolvedCost.unitCost,
                costingMethodAtSale: resolvedCost.method,
                costCurrency: resolvedCost.currencyCode,
                costExchangeRate: 1,
                costLayerConsumptions: resolvedCost.consumptions,
              ));
              continue;
            }
            final cutoverKey = '${product.id}::${candidate.warehouseId}';
            if (ensuredUnifiedCutovers.add(cutoverKey)) {
              await _ensureUnifiedBatchCutoverForProductInTransaction(
                sqliteDb,
                product: product,
                warehouseId: candidate.warehouseId,
                at: now,
              );
            }
            final allocations = await batchService.allocateUnifiedInTransaction(
              product: product,
              warehouseId: candidate.warehouseId,
              quantity: item.effectiveBaseQuantity,
              movementDate: now,
              storeId: appIdentity.storeId,
              deviceId: _deviceId,
              branchId: appIdentity.branchId,
              allowNegativeStock: _storeProfile.allowNegativeStock,
            );
            final totalBatchCost = allocations.fold<double>(
              0,
              (sum, allocation) =>
                  sum + (allocation.quantity * allocation.unitCost),
            );
            final effectiveUnitCost = item.effectiveBaseQuantity <= 0.000001
                ? 0.0
                : totalBatchCost / item.effectiveBaseQuantity;
            final allocatedItem = SaleItem(
              productId: item.productId,
              productName: item.productName,
              unitPrice: item.unitPrice,
              quantity: item.quantity,
              unitName: item.unitName,
              baseQuantity: item.effectiveBaseQuantity,
              conversionToBase: item.conversionToBase,
              unitCost: effectiveUnitCost,
              costingMethodAtSale: InventoryCostingMethod.batch,
              costCurrency: 'USD',
              costExchangeRate: 1,
              costLayerConsumptions: const <InventoryCostLayerConsumption>[],
              batchAllocations: allocations,
            );
            resolvedItems.add(allocatedItem);
            for (var batchIndex = 0;
                batchIndex < allocations.length;
                batchIndex += 1) {
              final allocation = allocations[batchIndex];
              editedMovements.add(StockMovement(
                id: _saleStockMovementId(
                  sale: candidate,
                  item: allocatedItem,
                  allocation: allocation,
                  lineIndex: lineIndex,
                  operationalVersion: candidate.version,
                ),
                productId: item.productId,
                productName: item.productName,
                type: 'sale',
                quantity: -allocation.quantity,
                date: now,
                referenceId: candidate.id,
                referenceNo: candidate.invoiceNo,
                reason: product.expiryTrackingEnabled
                    ? 'Sale edited/reposted (Unified FEFO)'
                    : 'Sale edited/reposted (Unified oldest batch)',
                unitCost: allocation.unitCost,
                warehouseId: candidate.warehouseId,
                warehouseName: candidate.warehouseName,
                batchId: allocation.batchId,
                movementGroupId: _saleMovementGroupId(
                  candidate,
                  operationalVersion: candidate.version,
                ),
                documentLineId: '${candidate.id}-line-$lineIndex',
                idempotencyKey: _saleStockMovementIdempotencyKey(
                  sale: candidate,
                  lineIndex: lineIndex,
                  batchIndex: batchIndex,
                  hasBatch: true,
                  operationalVersion: candidate.version,
                ),
                createdAt: now,
                updatedAt: now,
                deviceId: _deviceId,
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                syncStatus: 'pending',
                lastModifiedByDeviceId: _deviceId,
              ));
            }
          }
          if (editedMovements.isNotEmpty) {
            await stockService.recordMovementsInTransaction(
              operationType: 'sale_edit_repost',
              documentType: 'sale',
              documentId: candidate.id,
              movementGroupId: _saleMovementGroupId(
                candidate,
                operationalVersion: candidate.version,
              ),
              idempotencyKey: _saleMovementGroupId(
                candidate,
                operationalVersion: candidate.version,
              ),
              movements: editedMovements,
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              deviceId: _deviceId,
            );
            await _assertUnifiedBatchMovementBalancesInTransaction(
              batchService,
              editedMovements,
            );
          }
          return candidate.copyWith(items: resolvedItems);
        },
        buildPostedSnapshot: (candidate) async {
          Customer? snapshotCustomer;
          for (final customer in _customers) {
            if (customer.id == candidate.customerId && !customer.isDeleted) {
              snapshotCustomer = customer;
              break;
            }
          }
          final withSnapshot = candidate.copyWith(
            postedSnapshot: PostedDocumentSnapshotService.forSale(
              sale: candidate,
              profile: _storeProfile,
              customer: snapshotCustomer,
              user: _activeUser,
              role: currentUserRole,
              displayedPaidAmount: candidate.paidAmount
                  .clamp(0, candidate.invoiceTotal)
                  .toDouble(),
              taxProfileIdByProductId: taxProfileIdByProductId,
              legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
              extra: <String, dynamic>{
                'postedEditVersion': candidate.version,
              },
            ),
          );
          await BusinessSqliteStore.upsertEntityPayloads(
            sqliteDb,
            AppStore._salesKey,
            <Map<String, dynamic>>[withSnapshot.toJson()],
            sortIndices: const <int?>[0],
          );
          return withSnapshot;
        },
        repostAccounting: (candidate) async {
          final referenceId = '${candidate.id}:sale_edit:v${candidate.version}';
          await AccountingService.recordSale(
            candidate,
            accountingReferenceId: referenceId,
            paymentPostedSeparately: true,
            withinExistingTransaction: true,
          );
          await _requirePostedJournalInTransaction(
            sqliteDb,
            referenceType: 'sale',
            referenceId: referenceId,
            failureMessage:
                'Sale edit journal was not persisted; sale edit was rolled back.',
          );
        },
        rebuildDerivedState: (candidate) async {
          final saleAccountId = candidate.customerId.trim().isNotEmpty
              ? candidate.customerId.trim()
              : candidate.customerName.trim();
          if (saleAccountId.isNotEmpty) {
            await _persistAccountTransactionInExistingTransaction(
              sqliteDb,
              AccountTransaction(
                id: '${candidate.id}-sale-invoice',
                accountType: 'customer',
                accountId: saleAccountId,
                accountName: candidate.customerName,
                date: candidate.date,
                type: 'saleInvoice',
                referenceId: candidate.id,
                referenceNo: candidate.invoiceNo,
                debit: candidate.invoiceTotal,
                currency: candidate.invoiceCurrency,
                note: 'Sale invoice ${candidate.invoiceNo}',
                createdAt: candidate.createdAt,
                updatedAt: now,
                deviceId: _deviceId,
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                lastModifiedByDeviceId: _deviceId,
              ),
            );
          }
        },
        verifyIntegrity: (candidate) async {
          if (candidate.postedSnapshot == null ||
              candidate.postedSnapshot!.documentId != candidate.id ||
              candidate.postedSnapshot!.lines.length !=
                  candidate.items.length) {
            throw StateError(
                'Sale posted snapshot verification failed; edit was rolled back.');
          }
          await _requirePostedJournalInTransaction(
            sqliteDb,
            referenceType: 'sale',
            referenceId: '${candidate.id}:sale_edit:v${candidate.version}',
            failureMessage:
                'Sale accounting verification failed; edit was rolled back.',
          );
        },
      );
      updated = await pipeline.execute();
    });

    final affectedProductIds = <String>{
      ...before.items.map((item) => item.productId),
      ...updated.items.map((item) => item.productId),
    };
    if (editedMovements.isNotEmpty) {
      _mirrorAuthoritativeStockMovements(editedMovements);
    }
    await _refreshProductStockCompatibilityCache(affectedProductIds);
    await refreshAfterDatabaseChange(AppStore._productsKey);
    await refreshAfterDatabaseChange(AppStore._inventoryCostLayersKey);
    await refreshAfterDatabaseChange(AppStore._stockMovementsKey);
    await refreshAccountTransactionsFromSqlite();

    final index = _sales.indexWhere((sale) => sale.id == updated.id);
    if (index == -1) {
      _sales.add(updated);
    } else {
      _sales[index] = updated;
    }
    _recordSyncChange(
      entityType: 'sale',
      entityId: updated.id,
      operation: 'edit_repost',
      payload: updated.toJson(),
    );
    await _saveDirty(sales: true, sync: true);
    await AuditLogger.record(
      entityType: 'sale',
      entityId: updated.id,
      action: 'update',
      summary: 'Posted sale reversed and reposted',
      oldValue: beforeJson,
      newValue: jsonEncode(updated.toJson()),
      details: 'Posted Document Edit pipeline; sale_edit:v${updated.version}.',
      userId: _activeUser?.id ?? '',
      userName: _actorName(),
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      sessionId: _deviceId,
      traceId: _deviceId,
      deviceId: _deviceId,
      sourceModule: 'sales',
      isImportant: true,
    );
    _touchDataRevisions(sales: true);
    notifyListeners();
    return updated;
  }
}
