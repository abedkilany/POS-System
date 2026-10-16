part of 'app_store.dart';

extension _AppStoreSalesReturnsCreateSale on AppStore {
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
    const saleWorkflow = SaleWorkflowService();
    late final double cleanedDiscount;
    _traceSync('sales.createSale', 'validate_input', () {
      cleanedDiscount = saleWorkflow.validateCreate(
        items: items,
        discount: discount,
        productExists: (productId) => _findProductById(productId) != null,
      );
    });
    if (!LocalDatabaseService.isSqliteAuthoritative ||
        SqliteMigrationManager.database == null) {
      throw StateError('Sale posting requires the SQLite authoritative store.');
    }

    final now = DateTime.now();
    final saleItems = _traceSyncResult<List<SaleItem>>(
      'sales.createSale',
      'prepare_sale_items',
      () => saleWorkflow.prepareItems(
        items,
        costingMethod: _inventoryCostingMethod,
      ),
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
        final paymentPlan = saleWorkflow.prepareInitialPayment(
          customerId: customerId,
          customerName: customerName,
          paymentMethod: paymentMethodForRounding,
          paymentStatus: paymentStatus,
          saleTotalInInvoiceCurrency: saleTotalInInvoiceCurrency,
          cashReceivedAmount: cashReceivedAmount,
          walkInCustomerId: AppStore.walkInCustomerId,
          walkInCustomerName: AppStore.walkInCustomerName,
        );
        final normalizedCustomerId = paymentPlan.customerId;
        final normalizedCustomerName = paymentPlan.customerName;
        final normalizedPaymentMethod = paymentPlan.paymentMethod;
        final normalizedPaymentStatus = paymentPlan.paymentStatus;
        requestedInitialPaidAmount = paymentPlan.paidAmount;
        requestedInitialCashAmount = paymentPlan.cashReceivedAmount;
        requestedInitialPaymentMethod = paymentPlan.initialPaymentMethod;
        if (requestedInitialPaymentMethod.toLowerCase() == 'cash' &&
            paymentPlan.paidAmount > 0) {
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
        resolvedWarehouse = _resolveWarehouseForSale(
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
    final stockMovements = <StockMovement>[];
    await _traceAsync<void>('sales.createSale', 'stock_persist', () async {
      final sqliteDb = SqliteMigrationManager.database!;
      final result = await SalePostingService(
        sqliteDb: sqliteDb,
        session: this,
        syncTarget: _stockTransactionSyncTarget,
        productsById: {for (final product in _products) product.id: product},
        costsByProductId: {
          for (final item in saleItems)
            item.productId: _productCostFor(item.productId)
        },
      ).post(
        sale,
        displayedPaidAmount: requestedInitialPaidAmount,
        legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
        customer: _customers
            .where((customer) =>
                customer.id == sale.customerId && !customer.isDeleted)
            .firstOrNull,
        role: _currentUserRole,
      );
      sale = result.sale;
      stockMovements.addAll(result.stockMovements);
      _mirrorAuthoritativeStockMovements(stockMovements);
      await refreshAfterDatabaseChange(AppStore._inventoryCostLayersKey);
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
}
