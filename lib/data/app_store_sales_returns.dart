part of 'app_store.dart';

extension _AppStoreSplitSalesReturns on AppStore {
Future<SaleQuotation> createSaleQuotation({
    required String customerName,
    String customerId = '',
    required List<SaleItem> items,
    double discount = 0,
    String invoiceCurrency = 'USD',
    String note = '',
    DateTime? validUntil,
  }) async {
    requirePermission(AppPermission.quotationsManage);
    if (items.isEmpty) {
      throw ArgumentError('Quotation must contain at least one item.');
    }
    final cleanedDiscount =
        discount.isFinite ? discount.clamp(0, double.infinity).toDouble() : 0.0;
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    if (cleanedDiscount > subtotal) {
      throw ArgumentError('Discount cannot be greater than subtotal.');
    }
    for (final item in items) {
      if (item.quantity <= 0 || item.unitPrice < 0) {
        throw ArgumentError('Invalid quotation item values.');
      }
      if (_findProductById(item.productId) == null) {
        throw ArgumentError('Product not found: ${item.productName}');
      }
    }
    final now = DateTime.now();
    final quotation = SaleQuotation(
      id: now.microsecondsSinceEpoch.toString(),
      quotationNo:
          'QTN-$_invoiceDevicePrefix-${(saleQuotations.length + 1).toString().padLeft(6, '0')}',
      customerName: customerName.trim().isEmpty
          ? AppStore.walkInCustomerName
          : customerName.trim(),
      customerId:
          customerId.trim().isEmpty ? AppStore.walkInCustomerId : customerId.trim(),
      date: now,
      validUntil: validUntil,
      status: 'Draft',
      items: items,
      discount: cleanedDiscount,
      invoiceCurrency: invoiceCurrency.toUpperCase() == 'LBP' ? 'LBP' : 'USD',
      note: note.trim(),
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: _deviceId,
    );
    _saleQuotations.add(quotation);
    _recordSyncChange(
      entityType: 'sale_quotation',
      entityId: quotation.id,
      operation: 'create',
      payload: quotation.toJson(),
    );
    await _saveDirty(saleQuotations: true, sync: true);
    notifyListeners();
    return quotation;
  }

Future<Sale> convertSaleQuotationToSale(
    String quotationId, {
    String paymentMethod = 'Cash',
    String paymentStatus = 'paid',
  }) async {
    requireAllPermissions(<String>{
      AppPermission.quotationsManage,
      AppPermission.salesCreate,
    });
    final index = _saleQuotations.indexWhere((item) => item.id == quotationId);
    if (index == -1) throw ArgumentError('Quotation not found.');
    final quotation = _saleQuotations[index];
    if (quotation.isDeleted) throw StateError('Quotation is deleted.');
    if (quotation.isConverted) {
      throw StateError('Quotation is already converted.');
    }
    final sale = await createSale(
      customerName: quotation.customerName,
      customerId: quotation.customerId,
      items: quotation.items,
      discount: quotation.discount,
      originalDiscount: quotation.discount,
      invoiceCurrency: quotation.invoiceCurrency,
      paymentCurrency: quotation.invoiceCurrency,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
    );
    final now = DateTime.now();
    final updated = _withSyncMeta<SaleQuotation>(
      quotation.copyWith(
        status: 'Converted',
        convertedSaleId: sale.id,
        updatedAt: now,
      ),
      now,
    );
    _saleQuotations[index] = updated;
    _recordSyncChange(
      entityType: 'sale_quotation',
      entityId: updated.id,
      operation: 'convert',
      payload: updated.toJson(),
    );
    await _saveDirty(saleQuotations: true, sync: true);
    notifyListeners();
    return sale;
  }

Future<void> deleteSaleQuotation(String id) async {
    requirePermission(AppPermission.quotationsManage);
    final index = _saleQuotations.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final now = DateTime.now();
    final deleted = _withSyncMeta<SaleQuotation>(
      _saleQuotations[index].copyWith(deletedAt: now, updatedAt: now),
      now,
    );
    _saleQuotations[index] = deleted;
    _recordSyncChange(
      entityType: 'sale_quotation',
      entityId: id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _saveDirty(saleQuotations: true, sync: true);
    notifyListeners();
  }

DeliveryNote? deliveryNoteForSale(String saleId) {
    _ensureDeliveryNoteLookupCache();
    return _cachedDeliveryNoteBySaleId?[saleId];
  }

Future<DeliveryNote> createDeliveryNoteFromSale(
    String saleId, {
    String note = '',
  }) async {
    requirePermission(AppPermission.deliveryNotesManage);
    final saleIndex = _sales.indexWhere((item) => item.id == saleId);
    final sale =
        saleIndex == -1 ? await _saleByIdFromSqlite(saleId) : _sales[saleIndex];
    if (sale == null) throw ArgumentError('Sale not found.');
    if (sale.isDeleted) throw StateError('Sale is deleted.');
    if (sale.isCancelled) {
      throw StateError(
        'Cannot create a delivery note for a cancelled or returned sale.',
      );
    }
    final existing = deliveryNoteForSale(saleId);
    if (existing != null) return existing;
    final now = DateTime.now();
    final deliveryNote = DeliveryNote(
      id: '${now.microsecondsSinceEpoch}-delivery',
      deliveryNo:
          'DLV-$_invoiceDevicePrefix-${(_deliveryNotes.where((item) => !item.isDeleted).length + 1).toString().padLeft(6, '0')}',
      saleId: sale.id,
      invoiceNo: sale.invoiceNo,
      customerName: sale.customerName,
      customerId: sale.customerId,
      date: now,
      status: 'Draft',
      items: sale.items,
      note: note.trim(),
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: _deviceId,
    );
    _deliveryNotes.add(deliveryNote);
    _recordSyncChange(
      entityType: 'delivery_note',
      entityId: deliveryNote.id,
      operation: 'create',
      payload: deliveryNote.toJson(),
    );
    await _saveDirty(deliveryNotes: true, sync: true);
    _touchDataRevisions(deliveryNotes: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
    return deliveryNote;
  }

Future<void> markDeliveryNoteDelivered(String id) async {
    requirePermission(AppPermission.deliveryNotesManage);
    final index = _deliveryNotes.indexWhere((item) => item.id == id);
    if (index == -1) throw ArgumentError('Delivery note not found.');
    final current = _deliveryNotes[index];
    if (current.isDeleted || current.isDelivered) return;
    final now = DateTime.now();
    final updated = _withSyncMeta<DeliveryNote>(
      current.copyWith(status: 'Delivered', deliveredAt: now, updatedAt: now),
      now,
    );
    _deliveryNotes[index] = updated;
    _recordSyncChange(
      entityType: 'delivery_note',
      entityId: id,
      operation: 'deliver',
      payload: updated.toJson(),
    );
    await _saveDirty(deliveryNotes: true, sync: true);
    _touchDataRevisions(deliveryNotes: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
  }

Future<void> deleteDeliveryNote(String id) async {
    requirePermission(AppPermission.deliveryNotesManage);
    final index = _deliveryNotes.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final now = DateTime.now();
    final deleted = _withSyncMeta<DeliveryNote>(
      _deliveryNotes[index].copyWith(deletedAt: now, updatedAt: now),
      now,
    );
    _deliveryNotes[index] = deleted;
    _recordSyncChange(
      entityType: 'delivery_note',
      entityId: id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _saveDirty(deliveryNotes: true, sync: true);
    _touchDataRevisions(deliveryNotes: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
  }

Future<Sale> createSale({
    required String customerName,
    String customerId = '',
    required List<SaleItem> items,
    double discount = 0,
    double? originalDiscount,
    String discountCurrency = 'USD',
    double discountExchangeRateAtEntry = 0,
    String paymentMethod = 'Cash',
    String paymentStatus = 'paid',
    String invoiceCurrency = 'USD',
    String paymentCurrency = 'USD',
    double? exchangeRateAtPayment,
    double? paidAmount,
    double? cashReceivedAmount,
    double? paidAmountInPaymentCurrency,
    double? cashReceivedAmountInPaymentCurrency,
    String warehouseId = '',
    String warehouseName = '',
  }) async {
    requirePermission(AppPermission.salesCreate);
    _traceSync('sales.createSale', 'validate_input', () {
      if (items.isEmpty) {
        throw ArgumentError('Sale must contain at least one item.');
      }

      final double cleanedDiscount = discount.isFinite ? discount : 0.0;
      if (cleanedDiscount < 0) {
        throw ArgumentError('Discount cannot be negative.');
      }

      final subtotal =
          items.fold<double>(0, (sum, item) => sum + item.lineTotal);
      if (cleanedDiscount > subtotal) {
        throw ArgumentError('Discount cannot be greater than subtotal.');
      }

      for (final item in items) {
        if (item.quantity <= 0 || item.unitPrice < 0) {
          throw ArgumentError('Invalid sale item values.');
        }
        final product = _findProductById(item.productId);
        if (product == null) {
          throw ArgumentError('Product not found: ${item.productName}');
        }
      }
    });
    if (!LocalDatabaseService.isSqliteAuthoritative ||
        SqliteMigrationManager.database == null) {
      throw StateError('Sale posting requires the SQLite authoritative store.');
    }

    final double cleanedDiscount = discount.isFinite ? discount : 0.0;
    final now = DateTime.now();
    final saleItems = _traceSyncResult<List<SaleItem>>(
      'sales.createSale',
      'prepare_sale_items',
      () => items.map((item) {
        return SaleItem(
          productId: item.productId,
          productName: item.productName,
          unitPrice: item.unitPrice,
          quantity: item.quantity,
          unitName: item.unitName,
          baseQuantity: item.effectiveBaseQuantity,
          conversionToBase: item.conversionToBase,
          // Cost is finalized inside the authoritative SQLite transaction.
          // Keeping this preparation phase side-effect free prevents FIFO
          // layers from being consumed before the sale can be committed.
          unitCost: item.unitCost,
          costingMethodAtSale: _inventoryCostingMethod,
          costCurrency: item.costCurrency,
          costExchangeRate: 1,
          costLayerConsumptions: const <InventoryCostLayerConsumption>[],
        );
      }).toList(),
    );

    late Sale sale;
    late double requestedInitialPaidAmount;
    late double requestedInitialCashAmount;
    late String requestedInitialPaymentMethod;
    late Warehouse resolvedWarehouse;
    late String normalizedWarehouseName;

    await _traceAsync<void>(
      'sales.createSale',
      'pricing_and_customer',
      () async {
        final saleTotalValue =
            (saleItems.fold<double>(0, (sum, item) => sum + item.lineTotal) -
                    cleanedDiscount)
                .clamp(0, double.infinity)
                .toDouble();
        String normalizeConfiguredCurrency(String value, [String? fallback]) {
          final normalized = value.trim().toUpperCase();
          final fallbackCurrency =
              (fallback ?? storeProfile.baseCurrency).toUpperCase();
          if (normalized.isEmpty) return fallbackCurrency;
          return storeProfile.currencies.any((item) =>
                  item.isActive && item.code.toUpperCase() == normalized)
              ? normalized
              : fallbackCurrency;
        }

        final baseCurrency =
            normalizeConfiguredCurrency(storeProfile.baseCurrency, 'USD');
        final normalizedInvoiceCurrency =
            normalizeConfiguredCurrency(invoiceCurrency, baseCurrency);
        final normalizedPaymentCurrency = normalizeConfiguredCurrency(
            paymentCurrency, normalizedInvoiceCurrency);
        final invoiceRate = normalizedInvoiceCurrency == baseCurrency
            ? 1.0
            : exchangeRate(
                baseCurrency, normalizedInvoiceCurrency, storeProfile,
                effectiveAt: now);
        final exchangeRateAtPaymentValue = exchangeRateAtPayment;
        final safePaymentRate =
            exchangeRateAtPaymentValue != null && exchangeRateAtPaymentValue > 0
                ? exchangeRateAtPaymentValue
                : exchangeRate(normalizedPaymentCurrency,
                    normalizedInvoiceCurrency, storeProfile,
                    effectiveAt: now);
        final rawSaleTotalInInvoiceCurrency = convertCurrency(
          saleTotalValue,
          baseCurrency,
          normalizedInvoiceCurrency,
          storeProfile,
          effectiveAt: now,
        );
        final paymentMethodForRounding =
            paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim();
        final rawSaleTotalInPaymentCurrency = convertCurrency(
          rawSaleTotalInInvoiceCurrency,
          normalizedInvoiceCurrency,
          normalizedPaymentCurrency,
          storeProfile,
          effectiveAt: now,
        );
        final roundedSaleTotalInPaymentCurrency =
            paymentMethodForRounding.toLowerCase() == 'cash'
                ? normalizeCashAmount(
                    rawSaleTotalInPaymentCurrency,
                    normalizedPaymentCurrency,
                    storeProfile,
                  )
                : rawSaleTotalInPaymentCurrency;
        final saleTotalInInvoiceCurrency = convertCurrency(
          roundedSaleTotalInPaymentCurrency,
          normalizedPaymentCurrency,
          normalizedInvoiceCurrency,
          storeProfile,
          effectiveAt: now,
        );
        final saleTotalInBaseCurrency = toBaseCurrencyAmount(
          saleTotalInInvoiceCurrency,
          normalizedInvoiceCurrency,
          storeProfile,
          effectiveAt: now,
        );
        final normalizedCustomerId =
            customerId.trim().isEmpty ? AppStore.walkInCustomerId : customerId.trim();
        final normalizedCustomerName = customerName.trim().isEmpty
            ? AppStore.walkInCustomerName
            : customerName.trim();
        final normalizedPaymentMethod = paymentMethodForRounding;
        final isWalkInSale = normalizedCustomerId == AppStore.walkInCustomerId ||
            normalizedCustomerName.toLowerCase() ==
                AppStore.walkInCustomerName.toLowerCase();
        if (isWalkInSale && normalizedPaymentMethod == 'Credit') {
          throw ArgumentError('Walk-in customer sales cannot be credit.');
        }
        final normalizedCashReceived = (cashReceivedAmount ??
                (normalizedPaymentMethod == 'Cash'
                    ? saleTotalInInvoiceCurrency
                    : 0.0))
            .clamp(0, saleTotalInInvoiceCurrency)
            .toDouble();
        final requestedStatus = paymentStatus.trim().toLowerCase();
        final normalizedPaymentStatus = normalizedPaymentMethod == 'Credit'
            ? (normalizedCashReceived > 0 ? 'partial' : 'credit')
            : (requestedStatus == 'credit'
                ? 'credit'
                : requestedStatus == 'partial'
                    ? 'partial'
                    : 'paid');
        final normalizedPaidAmount = normalizedPaymentMethod == 'Credit'
            ? normalizedCashReceived
            : saleTotalInInvoiceCurrency;
        requestedInitialPaidAmount = normalizedPaidAmount;
        requestedInitialCashAmount = normalizedCashReceived;
        requestedInitialPaymentMethod =
            normalizedPaymentMethod == 'Credit' && normalizedCashReceived > 0
                ? 'Cash'
                : normalizedPaymentMethod;
        if (requestedInitialPaymentMethod.toLowerCase() == 'cash' &&
            normalizedPaidAmount > 0) {
          final hasOpenDrawer =
              await AccountingService.hasOpenCashDrawerForDevice(
            deviceId: _deviceId,
            branchId: appIdentity.branchId,
          );
          if (!hasOpenDrawer) {
            throw StateError(
                'لا توجد وردية نقدية مفتوحة لهذا الجهاز. افتح وردية قبل قبول الدفع النقدي.');
          }
        }
        resolvedWarehouse = resolveWarehouseForSale(
          warehouseId: warehouseId,
        );
        normalizedWarehouseName = warehouseName.trim().isEmpty
            ? resolvedWarehouse.name
            : warehouseName.trim();
        _invoiceCounter += 1;
        sale = Sale(
          id: 'sale_${_invoiceDevicePrefix}_${_invoiceCounter.toString().padLeft(6, '0')}',
          invoiceNo:
              'INV-$_invoiceDevicePrefix-${_invoiceCounter.toString().padLeft(6, '0')}',
          customerName: normalizedCustomerName,
          customerId: normalizedCustomerId,
          date: now,
          status: 'Paid',
          paymentMethod: normalizedPaymentMethod,
          paymentStatus: normalizedPaymentStatus,
          invoiceCurrency: normalizedInvoiceCurrency,
          paymentCurrency: normalizedPaymentCurrency,
          exchangeRateAtPayment: safePaymentRate,
          baseCurrency: baseCurrency,
          exchangeRateAtInvoice: invoiceRate,
          transactionAmount: saleTotalInInvoiceCurrency,
          baseAmount: saleTotalInBaseCurrency,
          paidBaseAmount: 0,
          paidAmount: 0,
          cashReceivedAmount: 0,
          paidAmountInPaymentCurrency: 0,
          cashReceivedAmountInPaymentCurrency: 0,
          warehouseId: resolvedWarehouse.id,
          warehouseName: normalizedWarehouseName,
          items: saleItems,
          discount: cleanedDiscount,
          originalDiscount: originalDiscount ?? cleanedDiscount,
          discountCurrency:
              normalizeConfiguredCurrency(discountCurrency, baseCurrency),
          discountExchangeRateAtEntry: discountExchangeRateAtEntry,
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          syncStatus: 'pending',
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          version: 1,
          lastModifiedByDeviceId: _deviceId,
        );
      },
    );

    final legacyDefaultVatRatePercent =
        await AccountingService.readDefaultVatRatePercent();
    final taxProfileIdByProductId = <String, String>{
      for (final product in _products) product.id: product.taxProfileId,
    };
    final stockMovements = <StockMovement>[];
    await _traceAsync<void>('sales.createSale', 'stock_persist', () async {
      final sqliteDb = SqliteMigrationManager.database;
      if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
        final stockService = StockTransactionService(
          sqliteDb,
          deviceId: _deviceId,
          defaultStoreId: appIdentity.storeId,
          defaultBranchId: appIdentity.branchId,
          defaultSyncTarget: _stockTransactionSyncTarget,
          allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
        );
        final batchService = BatchInventoryService(sqliteDb);
        await sqliteDb.transaction(() async {
          final ensuredUnifiedCutovers = <String>{};
          final allocatedItems = <SaleItem>[];
          for (var lineIndex = 0;
              lineIndex < saleItems.length;
              lineIndex += 1) {
            final item = saleItems[lineIndex];
            final product = _findProductById(item.productId);
            if (product == null || !product.trackStock) {
              final resolvedCost = await _resolveCostForSaleItemInTransaction(
                sqliteDb,
                item,
                now,
              );
              allocatedItems.add(SaleItem(
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

            final cutoverKey = '${product.id}::${resolvedWarehouse.id}';
            if (ensuredUnifiedCutovers.add(cutoverKey)) {
              await _ensureUnifiedBatchCutoverForProductInTransaction(
                sqliteDb,
                product: product,
                warehouseId: resolvedWarehouse.id,
                at: now,
              );
            }
            final allocations = await batchService.allocateUnifiedInTransaction(
              product: product,
              warehouseId: resolvedWarehouse.id,
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
            allocatedItems.add(allocatedItem);
            for (var batchIndex = 0;
                batchIndex < allocations.length;
                batchIndex += 1) {
              final allocation = allocations[batchIndex];
              stockMovements.add(StockMovement(
                id: '${sale.id}-${item.productId}-${allocation.batchId}-sale-$lineIndex',
                productId: item.productId,
                productName: item.productName,
                type: 'sale',
                quantity: -allocation.quantity,
                date: now,
                referenceId: sale.id,
                referenceNo: sale.invoiceNo,
                reason: product.expiryTrackingEnabled
                    ? 'Sale invoice (Unified FEFO)'
                    : 'Sale invoice (Unified oldest batch)',
                unitCost: allocation.unitCost,
                warehouseId: resolvedWarehouse.id,
                warehouseName: normalizedWarehouseName,
                batchId: allocation.batchId,
                movementGroupId: _saleMovementGroupId(sale),
                documentLineId: '${sale.id}-line-$lineIndex',
                idempotencyKey: '${sale.id}:sale:$lineIndex:$batchIndex',
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
          sale = sale.copyWith(items: allocatedItems);
          Customer? snapshotCustomer;
          for (final candidate in _customers) {
            if (candidate.id == sale.customerId && !candidate.isDeleted) {
              snapshotCustomer = candidate;
              break;
            }
          }
          sale = sale.copyWith(
            postedSnapshot: PostedDocumentSnapshotService.forSale(
              sale: sale,
              profile: _storeProfile,
              customer: snapshotCustomer,
              user: _activeUser,
              role: currentUserRole,
              displayedPaidAmount: requestedInitialPaidAmount,
              taxProfileIdByProductId: taxProfileIdByProductId,
              legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
            ),
          );
          await BusinessSqliteStore.upsertEntityPayloads(
            sqliteDb,
            AppStore._salesKey,
            <Map<String, dynamic>>[sale.toJson()],
            sortIndices: <int?>[0],
          );
          await stockService.recordMovementsInTransaction(
            operationType: 'sale',
            documentType: 'sale',
            documentId: sale.id,
            movementGroupId: sale.id,
            idempotencyKey: sale.id,
            movements: stockMovements,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            deviceId: _deviceId,
          );
          await _assertUnifiedBatchMovementBalancesInTransaction(
            batchService,
            stockMovements,
          );
          await AccountingService.recordSale(
            sale,
            paymentPostedSeparately: true,
            withinExistingTransaction: true,
          );
          await _requirePostedJournalInTransaction(
            sqliteDb,
            referenceType: 'sale',
            referenceId: sale.id,
            failureMessage:
                'Sale journal was not persisted; the sale transaction was rolled back.',
          );
          final saleAccountId = sale.customerId.trim().isNotEmpty
              ? sale.customerId.trim()
              : sale.customerName.trim();
          if (saleAccountId.isNotEmpty) {
            await _persistAccountTransactionInExistingTransaction(
              sqliteDb,
              AccountTransaction(
                id: '${sale.id}-sale-invoice',
                accountType: 'customer',
                accountId: saleAccountId,
                accountName: sale.customerName,
                date: sale.date,
                type: 'saleInvoice',
                referenceId: sale.id,
                referenceNo: sale.invoiceNo,
                debit: sale.invoiceTotal,
                currency: sale.invoiceCurrency,
                note: 'Sale invoice ${sale.invoiceNo}',
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
        _mirrorAuthoritativeStockMovements(stockMovements);
        await refreshAfterDatabaseChange(AppStore._inventoryCostLayersKey);
      } else {
        for (var lineIndex = 0; lineIndex < saleItems.length; lineIndex += 1) {
          final item = saleItems[lineIndex];
          final index = _productIndexById[item.productId];
          if (index == null) continue;
          final product = _products[index];
          if (!product.trackStock) continue;
          final shortage = item.effectiveBaseQuantity - product.stock;
          if (!_storeProfile.allowNegativeStock && shortage > 0) {
            throw StateError(
              'Insufficient stock in warehouse ${resolvedWarehouse.id} for product ${item.productId}.',
            );
          }
          final movement = StockMovement(
            id: '${sale.id}-${item.productId}-sale-$lineIndex',
            productId: item.productId,
            productName: item.productName,
            type: 'sale',
            quantity: -item.effectiveBaseQuantity,
            date: now,
            referenceId: sale.id,
            referenceNo: sale.invoiceNo,
            reason: 'Sale invoice',
            unitCost: item.unitCostPerBase,
            warehouseId: resolvedWarehouse.id,
            warehouseName: normalizedWarehouseName,
            movementGroupId: sale.id,
            documentLineId: '${sale.id}-line-$lineIndex',
            sourceMovementId: '',
            reversalOfMovementId: '',
            idempotencyKey: '${sale.id}:sale:$lineIndex',
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            syncStatus: 'pending',
            lastModifiedByDeviceId: _deviceId,
          );
          stockMovements.add(movement);
          _addStockMovement(
            movement,
            recordSync: true,
          );
        }
      }
    });

    await _traceAsync<void>(
      'sales.createSale',
      'refresh_product_stock_cache',
      () async {
        if (LocalDatabaseService.isSqliteAuthoritative &&
            SqliteMigrationManager.database != null) {
          await _refreshProductStockCompatibilityCache(
            stockMovements.map((movement) => movement.productId),
          );
        } else {
          _applyProductStockCompatibilityDeltas(stockMovements);
        }
      },
    );
    if (requestedInitialPaidAmount > 0) {
      if (!LocalDatabaseService.isSqliteAuthoritative ||
          SqliteMigrationManager.database == null) {
        throw StateError(
            'Sale payments require the SQLite authoritative store.');
      }
      sale = await _settleSalePaymentInternal(
        saleId: sale.id,
        amount: requestedInitialPaidAmount,
        paymentMethod: requestedInitialPaymentMethod,
        notes: 'Initial payment for ${sale.invoiceNo}',
        idempotencyKey: '${sale.id}:initial-payment:v1',
        date: now,
      );
      if (requestedInitialPaymentMethod.toLowerCase() == 'cash' &&
          requestedInitialCashAmount > 0) {
        final sqliteDb = SqliteMigrationManager.database!;
        await sqliteDb.customUpdate(
          'UPDATE sales SET cash_received_amount = ? WHERE id = ?',
          variables: <Variable<Object>>[
            Variable<double>(sale.paidAmount),
            Variable<String>(sale.id),
          ],
        );
        sale = (await _saleByIdFromSqlite(sale.id)) ?? sale;
      }
    }
    _traceSync('sales.createSale', 'record_sale_ledger', () {
      _sales.add(sale);
    });
    final saleCreateWasAtomic = LocalDatabaseService.isSqliteAuthoritative &&
        SqliteMigrationManager.database != null;
    if (!saleCreateWasAtomic) {
      await _recordSaleLedger(sale, now);
    }
    _traceSync('sales.createSale', 'record_sync_change', () {
      _recordSyncChange(
        entityType: 'sale',
        entityId: sale.id,
        operation: 'create',
        payload: sale.toJson(),
      );
    });
    await _traceAsync<void>('sales.createSale', 'save_dirty', () async {
      await _saveDirty(
        products: true,
        // FIFO layers are already committed with the sale transaction above.
        // Never schedule the legacy delayed derived-data flush for this path.
        productDerivedData: false,
        sales: false,
        stockMovements: false,
        accountTransactions: !saleCreateWasAtomic,
        invoiceCounter: true,
        sync: true,
      );
    });
    unawaited(
      AppLogger.info(
        area: 'sales',
        action: 'create_invoice',
        message: 'Sale invoice created successfully.',
        details:
            'saleId=${sale.id} invoiceNo=${sale.invoiceNo} total=${sale.invoiceTotal}',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'sale',
        entityId: sale.id,
        action: 'create',
        summary: 'Sale invoice created',
        details: jsonEncode(sale.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _activeUser?.fullName ?? _activeUser?.username ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'sales',
        isImportant: true,
      ),
    );
    notifyListeners();
    return sale;
  }

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
    if (item.quantity <= 0 || item.conversionToBase <= 0 || item.unitPrice < 0) {
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
          throw StateError('Cancelled/returned/deleted sales cannot be edited.');
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
          final requestedCustomerIndex =
              _customers.indexWhere((customer) => customer.id == requestedCustomerId);
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
          final requestedWarehouseIndex =
              _warehouses.indexWhere((item) => item.id == requestedWarehouseId);
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
              createdAt:
                  current.version <= 1 ? current.createdAt : current.updatedAt,
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
        if (isWalkIn && current.paymentMethod.trim().toLowerCase() == 'credit') {
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
                  costLayerConsumptions:
                      const <InventoryCostLayerConsumption>[],
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
            displayedPaidAmount:
                candidate.paidAmount.clamp(0, candidate.invoiceTotal).toDouble(),
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
        final referenceId =
            '${candidate.id}:sale_edit:v${candidate.version}';
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
            candidate.postedSnapshot!.lines.length != candidate.items.length) {
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

int _saleOperationalVersion(Sale sale) {
  final raw = sale.postedSnapshot?.extra['postedEditVersion'];
  final parsed = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
  return parsed != null && parsed > 1 ? parsed : 1;
}

String _saleStockMovementId({
  required Sale sale,
  required SaleItem item,
  required BatchAllocation allocation,
  required int lineIndex,
  int? operationalVersion,
}) {
  final effectiveVersion =
      operationalVersion ?? _saleOperationalVersion(sale);
  final versionSuffix =
      effectiveVersion <= 1 ? 'sale' : 'sale-edit-v$effectiveVersion';
  return allocation.batchId.trim().isNotEmpty
      ? '${sale.id}-${item.productId}-${allocation.batchId}-$versionSuffix-$lineIndex'
      : '${sale.id}-${item.productId}-$versionSuffix-$lineIndex';
}

String _saleStockMovementIdempotencyKey({
  required Sale sale,
  required int lineIndex,
  required int batchIndex,
  required bool hasBatch,
  int? operationalVersion,
}) {
  final effectiveVersion =
      operationalVersion ?? _saleOperationalVersion(sale);
  final family =
      effectiveVersion <= 1 ? 'sale' : 'sale_edit:v$effectiveVersion';
  return hasBatch
      ? '${sale.id}:$family:$lineIndex:$batchIndex'
      : '${sale.id}:$family:$lineIndex';
}

String _saleMovementGroupId(
  Sale sale, {
  int? operationalVersion,
}) {
  final effectiveVersion =
      operationalVersion ?? _saleOperationalVersion(sale);
  return effectiveVersion <= 1
      ? sale.id
      : '${sale.id}:sale_edit:v$effectiveVersion';
}

Future<Map<String, double>> _returnedSaleQuantitiesByProduct(
    String saleId,
  ) async {
    await ensureCreditNotesLoaded();
    final totals = <String, double>{};
    for (final note in _creditNotes) {
      if (note.originalSaleId != saleId) continue;
      final status = note.status.trim().toLowerCase();
      if (status == 'cancelled' || status == 'reversed' || status == 'void') {
        continue;
      }
      for (final item in note.items) {
        totals.update(
          item.productId,
          (value) => value + item.quantity,
          ifAbsent: () => item.quantity,
        );
      }
    }
    return totals;
  }

Future<double?> _remainingReversibleStockQuantityInTransaction(
    dynamic sqliteDb,
    String movementId,
  ) async {
    final rows = await sqliteDb.customSelect(
      '''
      SELECT
        ABS(sm.quantity) AS original_quantity,
        COALESCE((
          SELECT SUM(ABS(r.quantity))
          FROM stock_movements r
          WHERE r.reversal_of_movement_id = sm.id
            AND r.deleted_at = ''
            AND NOT EXISTS (
              SELECT 1 FROM stock_movements rr
              WHERE rr.reversal_of_movement_id = r.id
                AND rr.deleted_at = ''
            )
        ), 0) AS reversed_quantity
      FROM stock_movements sm
      WHERE sm.id = ?
        AND sm.deleted_at = ''
      LIMIT 1
      ''',
      variables: <Variable<Object>>[Variable<String>(movementId)],
    ).get();
    if (rows.isEmpty) return null;
    final original =
        (rows.first.data['original_quantity'] as num? ?? 0).toDouble();
    final reversed =
        (rows.first.data['reversed_quantity'] as num? ?? 0).toDouble();
    return (original - reversed).clamp(0, double.infinity).toDouble();
  }

List<BatchAllocation> _sliceBatchAllocationsForReturn(
    List<BatchAllocation> source, {
    required double offset,
    required double quantity,
  }) {
    if (source.isEmpty || quantity <= 0) return const <BatchAllocation>[];
    var skip = offset.clamp(0, double.infinity).toDouble();
    var remaining = quantity;
    final result = <BatchAllocation>[];
    for (final allocation in source) {
      if (remaining <= 0.0000001) break;
      var available = allocation.quantity;
      if (skip >= available - 0.0000001) {
        skip -= available;
        continue;
      }
      if (skip > 0) {
        available -= skip;
        skip = 0;
      }
      final take = min(available, remaining);
      if (take > 0.0000001) {
        result.add(BatchAllocation(
          batchId: allocation.batchId,
          quantity: take,
          unitCost: allocation.unitCost,
          supplierBatchNumber: allocation.supplierBatchNumber,
          manufacturingDate: allocation.manufacturingDate,
          expirationDate: allocation.expirationDate,
        ));
        remaining -= take;
      }
    }
    return result;
  }

List<InventoryCostLayerConsumption> _sliceCostConsumptionsForReturn(
    List<InventoryCostLayerConsumption> source, {
    required double offset,
    required double quantity,
  }) {
    if (source.isEmpty || quantity <= 0) {
      return const <InventoryCostLayerConsumption>[];
    }
    var skip = offset.clamp(0, double.infinity).toDouble();
    var remaining = quantity;
    final result = <InventoryCostLayerConsumption>[];
    for (final consumption in source) {
      if (remaining <= 0.0000001) break;
      var available = consumption.quantity;
      if (skip >= available - 0.0000001) {
        skip -= available;
        continue;
      }
      if (skip > 0) {
        available -= skip;
        skip = 0;
      }
      final take = min(available, remaining);
      if (take > 0.0000001) {
        result.add(InventoryCostLayerConsumption(
          layerId: consumption.layerId,
          quantity: take,
          unitCost: consumption.unitCost,
          currencyCode: consumption.currencyCode,
        ));
        remaining -= take;
      }
    }
    return result;
  }

Future<CreditNote> returnSale(
    String id, {
    bool restoreStock = true,
    Map<String, double>? returnedQuantities,
  }) async {
    requirePermission(AppPermission.salesCancel);
    requireSensitiveActionAuthorization(SensitiveAction.saleReverse);
    final index = _sales.indexWhere((sale) => sale.id == id);
    final sale = index == -1 ? await _saleByIdFromSqlite(id) : _sales[index];
    if (sale == null) {
      throw ArgumentError('Sale not found.');
    }
    if (sale.isCancelled) {
      throw StateError('Sale is already cancelled or fully returned.');
    }
    await ensureCreditNotesLoaded();

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
    final creditAmount = (returnedSubtotal -
            (sale.subtotal <= 0
                ? 0
                : sale.discount * (returnedSubtotal / sale.subtotal)))
        .clamp(0, double.infinity)
        .toDouble();
    final now = DateTime.now();
    final returnOperationKey =
        '${sale.id}:sale_return:${now.microsecondsSinceEpoch}';
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
      returnedAmount: sale.returnedAmount + creditAmount,
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
        role: currentUserRole,
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
    final returnLedgerTotal = ledgerSale.invoiceTotal > 0
        ? ledgerSale.invoiceTotal
        : ((ledgerSale.items
                    .fold<double>(0, (sum, item) => sum + item.lineTotal) -
                ledgerSale.discount)
            .clamp(0, double.infinity)
            .toDouble());
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
            final product = _findProductById(item.productId);
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
                  (_findProductById(item.productId)?.trackStock ?? false))
              .toList(growable: false);
          if (legacyCostItems.isNotEmpty) {
            await _restoreInventoryCostLayersFromSaleItemsInTransaction(
              sqliteDb,
              legacyCostItems,
              now,
              originalSaleDate: sale.date,
              restorationSourceType: 'sale_return_rebase',
              restorationSourceId: returnOperationKey,
            );
          }
          for (var selectedIndex = 0;
              selectedIndex < selectedItems.length;
              selectedIndex += 1) {
            final item = selectedItems[selectedIndex];
            final originalLineIndex =
                selectedOriginalLineIndexes[selectedIndex];
            final product = _findProductById(item.productId);
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
                  '${sale.id}-${item.productId}-sale-$originalLineIndex',
              reversalOfMovementId:
                  '${sale.id}-${item.productId}-sale-$originalLineIndex',
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
      creditNote = await issueCreditNote(
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
      await refreshAccountTransactionsFromSqlite();
    }
    notifyListeners();
    return creditNote;
  }

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
      allowNegativeStockResolver: (_, __) =>
          _storeProfile.allowNegativeStock,
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
          currentOperationReferenceId =
              currentNote.operationReferenceId.trim().isNotEmpty
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
          newJournalReferenceId =
              '${note.id}:sale_return_edit:v$nextVersion';
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
            final available =
                (original - (priorByProduct[entry.key] ?? 0)).clamp(0, double.infinity).toDouble();
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
            priorRemaining[item.productId] =
                (priorForProduct - priorOnLine)
                    .clamp(0, double.infinity)
                    .toDouble();
            final lineRemaining =
                (item.quantity - priorOnLine)
                    .clamp(0, double.infinity)
                    .toDouble();
            final requestedForProduct =
                requestRemaining[item.productId] ?? 0;
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
            final selected = SaleItem(
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
            final product = _findProductById(selected.productId);
            if (product != null &&
                product.trackStock &&
                selected.batchAllocations.isEmpty) {
              throw StateError(
                'Historical non-batch sale returns cannot be edited safely. Reverse and recreate the return instead.',
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

          final activeMovements = (await BusinessSqliteStore.readStockMovements(db))
              .where(
                (movement) =>
                    movement.movementGroupId == currentOperationReferenceId &&
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
          if (stillActive.isEmpty && note.items.any((item) {
            final product = _findProductById(item.productId);
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
          newReturnAmount = (returnedSubtotal -
                  (sale.subtotal <= 0
                      ? 0
                      : sale.discount *
                          (returnedSubtotal / sale.subtotal)))
              .clamp(0, double.infinity)
              .toDouble();
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
            final product = _findProductById(item.productId);
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
            await batchService.assertWarehouseBatchBalanceInTransaction(
              productId: item.productId,
              warehouseId: sale.warehouseId.isEmpty
                  ? Warehouse.defaultId
                  : sale.warehouseId,
              storeId: appIdentity.storeId,
            );
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
          committedNewMovements =
              List<StockMovement>.unmodifiable(movements);
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
          final restoredCashInPaymentCurrency =
              (originalSnapshot?.extra['cashReceivedAmountInPaymentCurrency']
                          as num?)
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
              paymentStatus:
                  isFullReturn ? 'returned' : restoredPaymentStatus,
              paidAmount: isFullReturn ? 0 : restoredPaid,
              cashReceivedAmount:
                  isFullReturn ? 0 : restoredCashReceived,
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
          final decoded = raw.trim().isEmpty ? const <dynamic>[] : jsonDecode(raw);
          final persisted = decoded is List
              ? decoded
                  .whereType<Map>()
                  .map((item) => CreditNote.fromJson(
                      Map<String, dynamic>.from(item)))
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
            final product = _findProductById(item.productId);
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

Future<void> cancelSale(
    String id, {
    String status = 'Cancelled',
    bool restoreStock = true,
  }) async {
    requirePermission(AppPermission.salesCancel);
    requireSensitiveActionAuthorization(SensitiveAction.saleReverse);
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
            final product = _findProductById(item.productId);
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
                  (_findProductById(item.productId)?.trackStock ?? false))
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
            final product = _findProductById(item.productId);
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
                productId: item.productId,
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
                productId: item.productId,
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

Future<void> deleteSale(String id, {bool restoreStock = true}) async {
    // Compatibility wrapper for older call sites. Business flow cancels invoices instead of deleting them.
    await cancelSale(id, status: 'Cancelled', restoreStock: restoreStock);
  }

double estimateProfit() {
    final grossProfit = sales.fold<double>(
      0,
      (sum, sale) => sum + sale.grossProfit,
    );
    return grossProfit - totalExpensesAmount;
  }

}
