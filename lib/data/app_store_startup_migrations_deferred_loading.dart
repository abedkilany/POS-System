part of 'app_store.dart';

extension _AppStoreStartupMigrationsDeferredLoading on AppStore {
  Future<void> _loadDeferredStartupData() async {
    try {
      await StartupTimingService.measure(
        'app_store.core_deferred_startup',
        () async {
          await Future<void>.delayed(Duration.zero);
          final products = await _loadProductsForStartup();
          _products
            ..clear()
            ..addAll(products);
          await Future<void>.delayed(Duration.zero);

          final customers = await _loadCustomersForStartup();
          _customers
            ..clear()
            ..addAll(customers);
          await Future<void>.delayed(Duration.zero);

          final sales = await _loadSalesForStartup();
          _sales
            ..clear()
            ..addAll(sales);
          await Future<void>.delayed(Duration.zero);

          final saleQuotations = await _loadSaleQuotationsForStartup();
          _saleQuotations
            ..clear()
            ..addAll(saleQuotations);
          await Future<void>.delayed(Duration.zero);

          final deliveryNotes = await _loadDeliveryNotesForStartup();
          _deliveryNotes
            ..clear()
            ..addAll(deliveryNotes);
          await Future<void>.delayed(Duration.zero);

          final billsOfMaterials = await _loadBillsOfMaterialsForStartup();
          _billsOfMaterials
            ..clear()
            ..addAll(billsOfMaterials);
          await Future<void>.delayed(Duration.zero);

          final manufacturingOrders =
              await _loadManufacturingOrdersForStartup();
          _manufacturingOrders
            ..clear()
            ..addAll(manufacturingOrders);
          await Future<void>.delayed(Duration.zero);

          final suppliers = await _loadSuppliersForStartup();
          _suppliers
            ..clear()
            ..addAll(suppliers);
          await Future<void>.delayed(Duration.zero);

          final supplierProductPrices =
              await _loadSupplierProductPricesForStartup();
          _supplierProductPrices
            ..clear()
            ..addAll(supplierProductPrices);
          await Future<void>.delayed(Duration.zero);

          final priceLists = await _loadPriceListsForStartup();
          _priceLists
            ..clear()
            ..addAll(priceLists);
          await Future<void>.delayed(Duration.zero);

          final productPrices = await _loadProductPricesForStartup();
          _productPrices
            ..clear()
            ..addAll(productPrices);
          await Future<void>.delayed(Duration.zero);

          final productPriceOverrides =
              await _loadProductPriceOverridesForStartup();
          _productPriceOverrides
            ..clear()
            ..addAll(productPriceOverrides);
          await Future<void>.delayed(Duration.zero);

          final productCosts = await _loadProductCostsForStartup();
          _productCosts
            ..clear()
            ..addAll(productCosts);
          _rebuildProductPricingLookupCaches();
          await Future<void>.delayed(Duration.zero);

          final costingMethodHistory =
              await _loadCostingMethodHistoryForStartup();
          _costingMethodHistory
            ..clear()
            ..addAll(costingMethodHistory);
          await Future<void>.delayed(Duration.zero);

          final inventoryCostLayers =
              await _loadInventoryCostLayersForStartup();
          _inventoryCostLayers
            ..clear()
            ..addAll(inventoryCostLayers);
          _rebuildInventoryCostLayerLookupCache();
          _inventoryCostingMethod = _runtimeInventoryCostingMethod(
            InventoryCostingMethodJson.fromCode(
              LocalDatabaseService.getString(
                  AppStore._inventoryCostingMethodKey),
            ),
          );
          await Future<void>.delayed(Duration.zero);

          final expenses = await _loadExpensesForStartup();
          _expenses
            ..clear()
            ..addAll(expenses);
          await Future<void>.delayed(Duration.zero);

          final purchases = await _loadPurchasesForStartup();
          _purchases
            ..clear()
            ..addAll(purchases);
          await _backfillPostedDocumentSnapshotsIfNeeded();
          await Future<void>.delayed(Duration.zero);

          final stockMovements = await _loadStockMovementsForStartup();
          _stockMovements
            ..clear()
            ..addAll(stockMovements);
          await Future<void>.delayed(Duration.zero);

          final inventoryCounts = await _loadInventoryCountsForStartup();
          _inventoryCounts
            ..clear()
            ..addAll(inventoryCounts);
          await Future<void>.delayed(Duration.zero);

          final warehouses = await _loadWarehousesForStartup();
          _warehouses
            ..clear()
            ..addAll(warehouses);
          await Future<void>.delayed(Duration.zero);

          _ensureDefaultPriceLists();
          _ensureDefaultProductPriceEntries();
          _ensureProductCostEntries();
          _ensureCostingMethodHistory();
          _ensureDefaultWarehouse();

          _normalizeCustomers();
          _ensureCatalogDefaults();
          _rebuildMutableEntityIndexes();
          _touchPurchasesData();
          _touchExpensesData();
          _invoiceCounter = _loadInvoiceCounter();
          _purchaseCounter = _loadPurchaseCounter();
          notifyListeners();
        },
        category: 'app_store',
      );
    } catch (error, stackTrace) {
      debugPrint('Deferred startup data load failed: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _loadLedgerDeferredStartupData() async {
    try {
      await StartupTimingService.measure(
        'app_store.ledger_deferred_startup',
        () async {
          await Future<void>.delayed(Duration.zero);
          final accountTransactions =
              await _loadAccountTransactionsForStartup();
          _accountTransactions
            ..clear()
            ..addAll(accountTransactions);
          _invalidateAccountLedgerCache();
          _touchDataRevisions(accountTransactions: true);
          notifyListeners();
        },
        category: 'app_store',
      );
    } catch (error, stackTrace) {
      debugPrint('Ledger startup data load failed: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _loadSyncDeferredStartupData() async {
    try {
      await StartupTimingService.measure(
        'app_store.sync_deferred_startup',
        () async {
          if (!LocalDatabaseService.isInMemoryStoreForTesting) {
            await Future<void>.delayed(Duration.zero);
          }
          final syncChanges = await _decodeDeferredList<SyncChange>(
            AppStore._syncChangesKey,
            SyncChange.fromJson,
            batchSize: 100,
          );
          _syncChanges
            ..clear()
            ..addAll(syncChanges);
          if (!LocalDatabaseService.isInMemoryStoreForTesting) {
            await Future<void>.delayed(Duration.zero);
          }

          final syncQueue = await _decodeDeferredList<SyncQueueItem>(
            AppStore._syncQueueKey,
            SyncQueueItem.fromJson,
            batchSize: 100,
          );
          _syncQueue
            ..clear()
            ..addAll(syncQueue);
          await _reconcileUnsyncedChangesWithQueue();
          notifyListeners();
        },
        category: 'app_store',
      );
    } catch (error, stackTrace) {
      debugPrint('Sync startup data load failed: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> refreshAccountTransactionsFromSqlite() async {
    await refreshAfterDatabaseChange(AppStore._accountTransactionsKey);
  }

  Future<void> refreshSalesProductData() async {
    await refreshAfterDatabaseChange(AppStore._productsKey);
    await refreshAfterDatabaseChange(AppStore._priceListsKey);
    await refreshAfterDatabaseChange(AppStore._productPricesKey);
    await refreshAfterDatabaseChange(AppStore._productPriceOverridesKey);
  }

  Future<void> refreshAfterDatabaseChange(String key) async {
    try {
      switch (key) {
        case AppStore._appIdentityKey:
          _appIdentity = _loadOrCreateAppIdentity();
          break;

        case AppStore._storeProfileKey:
          _storeProfile = _loadStoreProfile();
          AccountingService.configureMoneyPolicy(_storeProfile);
          _touchDataRevisions(storeProfile: true);
          break;

        case AppStore._productsKey:
          _products
            ..clear()
            ..addAll(await _loadProductsForStartup());
          _ensureCatalogDefaults();
          _touchDataRevisions(products: true);
          break;

        case AppStore._customersKey:
          _customers
            ..clear()
            ..addAll(await _loadCustomersForStartup());
          _normalizeCustomers();
          _touchDataRevisions(customers: true);
          break;

        case AppStore._salesKey:
          _sales
            ..clear()
            ..addAll(await _loadSalesForStartup());
          _invoiceCounter = _loadInvoiceCounter();
          _touchDataRevisions(sales: true);
          break;

        case AppStore._saleQuotationsKey:
          _saleQuotations
            ..clear()
            ..addAll(await _loadSaleQuotationsForStartup());
          break;

        case AppStore._deliveryNotesKey:
          _deliveryNotes
            ..clear()
            ..addAll(await _loadDeliveryNotesForStartup());
          _touchDataRevisions(deliveryNotes: true);
          break;

        case AppStore._billsOfMaterialsKey:
          _billsOfMaterials
            ..clear()
            ..addAll(await _loadBillsOfMaterialsForStartup());
          break;

        case AppStore._manufacturingOrdersKey:
          _manufacturingOrders
            ..clear()
            ..addAll(await _loadManufacturingOrdersForStartup());
          break;

        case AppStore._suppliersKey:
          _suppliers
            ..clear()
            ..addAll(await _loadSuppliersForStartup());
          _touchDataRevisions(suppliers: true);
          break;

        case AppStore._supplierProductPricesKey:
          _supplierProductPrices
            ..clear()
            ..addAll(await _loadSupplierProductPricesForStartup());
          _touchDataRevisions(supplierProductPrices: true);
          break;

        case AppStore._priceListsKey:
          _priceLists
            ..clear()
            ..addAll(await _loadPriceListsForStartup());
          _ensureDefaultPriceLists();
          _rebuildProductPricingLookupCaches();
          _touchDataRevisions(products: true);
          break;

        case AppStore._productPricesKey:
          _productPrices
            ..clear()
            ..addAll(await _loadProductPricesForStartup());
          _ensureDefaultProductPriceEntries();
          _rebuildProductPricingLookupCaches();
          _touchDataRevisions(products: true);
          break;

        case AppStore._productPriceOverridesKey:
          _productPriceOverrides
            ..clear()
            ..addAll(await _loadProductPriceOverridesForStartup());
          _rebuildProductPricingLookupCaches();
          _touchDataRevisions(products: true);
          break;

        case AppStore._productCostsKey:
          _productCosts
            ..clear()
            ..addAll(await _loadProductCostsForStartup());
          _rebuildProductPricingLookupCaches();
          _touchDataRevisions(products: true);
          break;

        case AppStore._costingMethodHistoryKey:
          _costingMethodHistory
            ..clear()
            ..addAll(await _loadCostingMethodHistoryForStartup());
          _touchDataRevisions(products: true);
          break;

        case AppStore._inventoryCostLayersKey:
          _inventoryCostLayers
            ..clear()
            ..addAll(await _loadInventoryCostLayersForStartup());
          _rebuildInventoryCostLayerLookupCache();
          _touchDataRevisions(products: true);
          break;

        case AppStore._expensesKey:
          _expenses
            ..clear()
            ..addAll(await _loadExpensesForStartup());
          _rebuildExpenseIndexes();
          _touchExpensesData();
          break;

        case AppStore._purchasesKey:
          _purchases
            ..clear()
            ..addAll(await _loadPurchasesForStartup());
          _rebuildPurchaseIndexes();
          _touchPurchasesData();
          _purchaseCounter = _loadPurchaseCounter();
          break;

        case AppStore._stockMovementsKey:
          _stockMovements
            ..clear()
            ..addAll(await _loadStockMovementsForStartup());
          _touchDataRevisions(stockMovements: true);
          break;

        case AppStore._inventoryCountsKey:
          _inventoryCounts
            ..clear()
            ..addAll(await _loadInventoryCountsForStartup());
          _touchDataRevisions(inventoryCounts: true);
          break;

        case AppStore._warehousesKey:
          _warehouses
            ..clear()
            ..addAll(await _loadWarehousesForStartup());
          _ensureDefaultWarehouse();
          _touchDataRevisions(warehouses: true);
          break;

        case AppStore._accountTransactionsKey:
          _accountTransactions
            ..clear()
            ..addAll(await _loadAccountTransactionsForStartup());
          _invalidateAccountLedgerCache();
          _touchDataRevisions(accountTransactions: true);
          break;

        case AppStore._categoriesKey:
          _categories
            ..clear()
            ..addAll(
                await _loadCatalogItemsForStartup(AppStore._categoriesKey));
          _ensureCatalogDefaults();
          _touchDataRevisions(products: true);
          break;

        case AppStore._brandsKey:
          _brands
            ..clear()
            ..addAll(await _loadCatalogItemsForStartup(AppStore._brandsKey));
          _ensureCatalogDefaults();
          _touchDataRevisions(products: true);
          break;

        case AppStore._unitsKey:
          _units
            ..clear()
            ..addAll(await _loadCatalogItemsForStartup(AppStore._unitsKey));
          _ensureCatalogDefaults();
          _touchDataRevisions(products: true);
          break;

        case AppStore._rolesKey:
        case AppStore._usersKey:
        case AppStore._activeUserKey:
        case AppStore._rememberLoginKey:
          _roles
            ..clear()
            ..addAll(await _loadRoles());
          _users
            ..clear()
            ..addAll(await _loadUsers());
          _rememberLogin =
              LocalDatabaseService.getString(AppStore._rememberLoginKey) ==
                  'true';
          _activeUser = null;
          _restoreActiveUser();
          break;

        case AppStore._syncChangesKey:
          _syncChanges
            ..clear()
            ..addAll(await _loadSyncChanges());
          _syncSequence = _loadSyncSequence();
          break;

        case AppStore._syncQueueKey:
          _syncQueue
            ..clear()
            ..addAll(_loadSyncQueue());
          break;

        case AppStore._invoiceCounterKey:
          _invoiceCounter = _loadInvoiceCounter();
          break;

        case AppStore._purchaseCounterKey:
          _purchaseCounter = _loadPurchaseCounter();
          break;

        case AppStore._syncSequenceKey:
          _syncSequence = _loadSyncSequence();
          break;

        default:
          await reloadAllAfterDatabaseChange();
          return;
      }

      _rebuildMutableEntityIndexes();
      _rebuildProductPricingLookupCaches();
      _invalidateDerivedDataCaches();
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('Database admin refresh failed for $key: $error');
      debugPrint('$stackTrace');
      await reloadAllAfterDatabaseChange();
    }
  }

  Future<void> reloadAllAfterDatabaseChange() async {
    final sessionBeforeReload = _activeUser;
    _appIdentity = _loadOrCreateAppIdentity();
    _storeProfile = _loadStoreProfile();
    AccountingService.configureMoneyPolicy(_storeProfile);
    _products
      ..clear()
      ..addAll(await _loadProductsForStartup());
    _customers
      ..clear()
      ..addAll(await _loadCustomersForStartup());
    _sales
      ..clear()
      ..addAll(await _loadSalesForStartup());
    _saleQuotations
      ..clear()
      ..addAll(await _loadSaleQuotationsForStartup());
    _deliveryNotes
      ..clear()
      ..addAll(await _loadDeliveryNotesForStartup());
    _billsOfMaterials
      ..clear()
      ..addAll(await _loadBillsOfMaterialsForStartup());
    _manufacturingOrders
      ..clear()
      ..addAll(await _loadManufacturingOrdersForStartup());
    _suppliers
      ..clear()
      ..addAll(await _loadSuppliersForStartup());
    _supplierProductPrices
      ..clear()
      ..addAll(await _loadSupplierProductPricesForStartup());
    _expenses
      ..clear()
      ..addAll(await _loadExpensesForStartup());
    _purchases
      ..clear()
      ..addAll(await _loadPurchasesForStartup());
    _stockMovements
      ..clear()
      ..addAll(await _loadStockMovementsForStartup());
    _inventoryCounts
      ..clear()
      ..addAll(await _loadInventoryCountsForStartup());
    _warehouses
      ..clear()
      ..addAll(await _loadWarehousesForStartup());
    _priceLists
      ..clear()
      ..addAll(await _loadPriceListsForStartup());
    _productPrices
      ..clear()
      ..addAll(await _loadProductPricesForStartup());
    _productPriceOverrides
      ..clear()
      ..addAll(await _loadProductPriceOverridesForStartup());
    _productCosts
      ..clear()
      ..addAll(await _loadProductCostsForStartup());
    _costingMethodHistory
      ..clear()
      ..addAll(await _loadCostingMethodHistoryForStartup());
    _inventoryCostLayers
      ..clear()
      ..addAll(await _loadInventoryCostLayersForStartup());
    _rebuildInventoryCostLayerLookupCache();
    _accountTransactions
      ..clear()
      ..addAll(await _loadAccountTransactionsForStartup());
    _categories
      ..clear()
      ..addAll(await _loadCatalogItemsForStartup(AppStore._categoriesKey));
    _brands
      ..clear()
      ..addAll(await _loadCatalogItemsForStartup(AppStore._brandsKey));
    _units
      ..clear()
      ..addAll(await _loadCatalogItemsForStartup(AppStore._unitsKey));
    _roles
      ..clear()
      ..addAll(await _loadRoles());
    _users
      ..clear()
      ..addAll(await _loadUsers());
    _syncChanges
      ..clear()
      ..addAll(await _loadSyncChanges());
    _syncQueue
      ..clear()
      ..addAll(_loadSyncQueue());
    await _reconcileUnsyncedChangesWithQueue();

    _rememberLogin =
        LocalDatabaseService.getString(AppStore._rememberLoginKey) == 'true';
    _activeUser = null;
    _restoreActiveUser();
    if (_activeUser == null && sessionBeforeReload != null) {
      for (final user in _users) {
        if (user.id == sessionBeforeReload.id && user.isActive) {
          _activeUser = user;
          break;
        }
      }
    }
    _normalizeCustomers();
    _ensureCatalogDefaults();
    _ensureDefaultWarehouse();
    _invoiceCounter = _loadInvoiceCounter();
    _purchaseCounter = _loadPurchaseCounter();
    _syncSequence = _loadSyncSequence();
    _rebuildMutableEntityIndexes();
    _rebuildProductPricingLookupCaches();
    _touchDataRevisions(
      products: true,
      customers: true,
      sales: true,
      deliveryNotes: true,
      suppliers: true,
      supplierProductPrices: true,
      expenses: true,
      purchases: true,
      stockMovements: true,
      inventoryCounts: true,
      warehouses: true,
      accountTransactions: true,
      storeProfile: true,
    );
    _invalidateAccountLedgerCache();
    _invalidateDerivedDataCaches();
    notifyListeners();
  }

  Future<void> _ensureDeviceId() async {
    final existing = LocalDatabaseService.getString(AppStore._deviceIdKey);
    if (existing != null && existing.trim().isNotEmpty) {
      _deviceId = _normalizeGeneratedId(existing.trim(), fallbackPrefix: 'DV');
      if (_deviceId != existing.trim()) {
        await LocalDatabaseService.setString(AppStore._deviceIdKey, _deviceId);
      }
      return;
    }
    _deviceId = _generatePrefixedId('DV');
    await LocalDatabaseService.setString(AppStore._deviceIdKey, _deviceId);
  }

  String _generatePrefixedId(String prefix) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final body = List<String>.generate(
      6,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
    return '${prefix.toUpperCase()}-$body';
  }

  String _normalizeGeneratedId(String value, {required String fallbackPrefix}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return _generatePrefixedId(fallbackPrefix);
    final parts = trimmed.split('-');
    if (parts.length == 2) {
      final rawPrefix = parts.first.toUpperCase();
      final prefix = rawPrefix == 'DEV' || rawPrefix == 'Dev'.toUpperCase()
          ? 'DV'
          : rawPrefix;
      final body = parts.last.toUpperCase();
      return '$prefix-$body';
    }
    return trimmed.toUpperCase();
  }
}
