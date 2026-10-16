part of 'app_store.dart';

/// Cross-domain orchestration that coordinates focused AppStore modules.
///
/// This layer contains lifecycle, cache hydration and invariants that genuinely
/// span domains. It owns no mutable state and keeps the concrete AppStore facade
/// intentionally small.
mixin _AppStoreOrchestration
    on
        ChangeNotifier,
        _AppStoreStateAccessors,
        _AppStoreForwardingApi,
        _AppStoreForwardingApiPart2,
        _AppStoreForwardingApiPart3,
        _AppStoreForwardingApiPart4,
        _AppStoreForwardingApiPart5 {
  SecurityDomainPort get security;

  Customer get _walkInCustomer => Customer(
        id: AppStore.walkInCustomerId,
        name: AppStore.walkInCustomerName,
        phone: '',
        address: '',
      );

  int get _accountingRevisionReadImpl => _accountingRevision;
  int get _inventoryRevisionReadImpl => _inventoryRevision;
  int get _accountingRevision => Object.hashAll(<Object?>[
        _customersRevision,
        _suppliersRevision,
        _salesRevision,
        _purchasesRevision,
        _expensesRevision,
        _accountTransactionsRevision,
        _storeProfileRevision,
      ]);
  int get _dashboardRevisionReadImpl => Object.hashAll(<Object?>[
        _productsRevision,
        _customersRevision,
        _suppliersRevision,
        _salesRevision,
        _purchasesRevision,
        _expensesRevision,
        _stockMovementsRevision,
        _accountTransactionsRevision,
        _storeProfileRevision,
        _syncSequence,
      ]);
  int get _reportsRevisionReadImpl => Object.hashAll(<Object?>[
        _productsRevision,
        _customersRevision,
        _suppliersRevision,
        _salesRevision,
        _purchasesRevision,
        _expensesRevision,
        _stockMovementsRevision,
        _accountTransactionsRevision,
        _storeProfileRevision,
      ]);
  int get _inventoryRevision => Object.hashAll(<Object?>[
        _productsRevision,
        _stockMovementsRevision,
        _inventoryCountsRevision,
        _warehousesRevision,
      ]);

  Future<void> _ensureSyncDataLoaded() => _requestSyncDataLoad();

  Future<void> _ensureProductsLoaded() => _ensureProductsLoadedImpl();

  Future<void> _ensureProductsLoadedImpl() => _loadDeferredGroup<Product>(
        key: AppStore._productsKey,
        loader: _loadProductsForStartup,
        target: _products,
        afterLoad: () {
          _ensureCatalogDefaults();
          _rebuildProductIndexes();
          _ensureDefaultPriceLists();
          _ensureDefaultProductPriceEntries();
          _ensureProductCostEntries();
          // Costing history is a separate deferred group. Never seed it from
          // product-only hydration because an empty in-memory list does not
          // mean SQLite has no history. Product mutations explicitly load the
          // history before they can persist product-derived data.
          _touchDataRevisions(products: true);
        },
      );

  Future<void> _ensureCustomersLoaded() => _ensureCustomersLoadedImpl();

  Future<void> _ensureCustomersLoadedImpl() => _loadDeferredGroup<Customer>(
        key: AppStore._customersKey,
        loader: _loadCustomersForStartup,
        target: _customers,
        afterLoad: () {
          _normalizeCustomers();
          _rebuildCustomerIndexes();
          _touchDataRevisions(customers: true);
        },
      );

  Future<void> _ensureSalesLoaded() => _loadDeferredGroup<Sale>(
        key: AppStore._salesKey,
        loader: _loadSalesForStartup,
        target: _sales,
        afterLoad: () {
          _invoiceCounter = _loadInvoiceCounter();
          _touchDataRevisions(sales: true);
        },
      );

  Future<void> _ensureSaleQuotationsLoaded() =>
      _loadDeferredGroup<SaleQuotation>(
        key: AppStore._saleQuotationsKey,
        loader: _loadSaleQuotationsForStartup,
        target: _saleQuotations,
      );

  Future<void> _ensureDeliveryNotesLoaded() => _loadDeferredGroup<DeliveryNote>(
        key: AppStore._deliveryNotesKey,
        loader: _loadDeliveryNotesForStartup,
        target: _deliveryNotes,
        afterLoad: () {
          _touchDataRevisions(deliveryNotes: true);
          _invalidateDerivedDataCaches();
        },
      );

  Future<void> _ensureBillsOfMaterialsLoaded() =>
      _loadDeferredGroup<BillOfMaterials>(
        key: AppStore._billsOfMaterialsKey,
        loader: _loadBillsOfMaterialsForStartup,
        target: _billsOfMaterials,
      );

  Future<void> _ensureManufacturingOrdersLoaded() =>
      _loadDeferredGroup<ManufacturingOrder>(
        key: AppStore._manufacturingOrdersKey,
        loader: _loadManufacturingOrdersForStartup,
        target: _manufacturingOrders,
      );

  Future<void> _ensureSuppliersLoaded() => _ensureSuppliersLoadedImpl();

  Future<void> _ensureSuppliersLoadedImpl() => _loadDeferredGroup<Supplier>(
        key: AppStore._suppliersKey,
        loader: _loadSuppliersForStartup,
        target: _suppliers,
        afterLoad: () {
          _rebuildSupplierIndexes();
          _touchDataRevisions(suppliers: true);
        },
      );

  Future<void> _ensureSupplierProductPricesLoaded() =>
      _loadDeferredGroup<SupplierProductPrice>(
        key: AppStore._supplierProductPricesKey,
        loader: _loadSupplierProductPricesForStartup,
        target: _supplierProductPrices,
        afterLoad: () {
          _touchDataRevisions(supplierProductPrices: true);
        },
      );

  Future<void> _ensurePriceListsLoaded() => _loadDeferredGroup<PriceList>(
        key: AppStore._priceListsKey,
        loader: _loadPriceListsForStartup,
        target: _priceLists,
        afterLoad: () {
          _ensureDefaultPriceLists();
          _rebuildProductPricingLookupCaches();
          _ensureDefaultProductPriceEntries();
        },
      );

  Future<void> _ensureProductPricesLoadedImpl() =>
      _loadDeferredGroup<ProductPrice>(
        key: AppStore._productPricesKey,
        loader: _loadProductPricesForStartup,
        target: _productPrices,
        afterLoad: () {
          _rebuildProductPricingLookupCaches();
          _ensureDefaultProductPriceEntries();
        },
      );

  Future<void> _ensureProductPriceOverridesLoaded() =>
      _loadDeferredGroup<ProductPriceOverride>(
        key: AppStore._productPriceOverridesKey,
        loader: _loadProductPriceOverridesForStartup,
        target: _productPriceOverrides,
        afterLoad: () {
          _rebuildProductPricingLookupCaches();
        },
      );

  Future<void> _ensureProductCostsLoaded() => _ensureProductCostsLoadedImpl();

  Future<void> _ensureProductCostsLoadedImpl() =>
      _loadDeferredGroup<ProductCost>(
        key: AppStore._productCostsKey,
        loader: _loadProductCostsForStartup,
        target: _productCosts,
        afterLoad: () {
          _rebuildProductPricingLookupCaches();
          _ensureProductCostEntries();
        },
      );

  Future<void> _ensureCostingMethodHistoryLoaded() =>
      _loadDeferredGroup<CostingMethodHistory>(
        key: AppStore._costingMethodHistoryKey,
        loader: _loadCostingMethodHistoryForStartup,
        target: _costingMethodHistory,
        afterLoad: () {
          _ensureCostingMethodHistory();
        },
      );

  Future<void> _ensureInventoryCostLayersLoaded() =>
      _loadDeferredGroup<InventoryCostLayer>(
        key: AppStore._inventoryCostLayersKey,
        loader: _loadInventoryCostLayersForStartup,
        target: _inventoryCostLayers,
      );

  Future<void> _ensureExpensesLoaded() => _loadDeferredGroup<Expense>(
        key: AppStore._expensesKey,
        loader: _loadExpensesForStartup,
        target: _expenses,
        afterLoad: () {
          _rebuildExpenseIndexes();
          _touchDataRevisions(expenses: true);
        },
      );

  Future<void> _ensurePurchasesLoaded() => _loadDeferredGroup<Purchase>(
        key: AppStore._purchasesKey,
        loader: _loadPurchasesForStartup,
        target: _purchases,
        afterLoad: () {
          _rebuildPurchaseIndexes();
          _touchDataRevisions(purchases: true);
        },
      );

  Future<void> _ensureStockMovementsLoaded() =>
      _loadDeferredGroup<StockMovement>(
        key: AppStore._stockMovementsKey,
        loader: _loadStockMovementsForStartup,
        target: _stockMovements,
        afterLoad: () {
          _rebuildStockMovementIndexes();
          if (!LocalDatabaseService.isSqliteAuthoritative) {
            _rebuildProductInventoryProjectionFromMovements();
          }
          _touchDataRevisions(stockMovements: true);
        },
      );

  Future<void> _ensureInventoryCountsLoaded() =>
      _loadDeferredGroup<InventoryCountSession>(
        key: AppStore._inventoryCountsKey,
        loader: _loadInventoryCountsForStartup,
        target: _inventoryCounts,
        afterLoad: () {
          _touchDataRevisions(inventoryCounts: true);
        },
      );

  Future<void> _ensureWarehousesLoaded() => _ensureWarehousesLoadedImpl();

  Future<void> _ensureWarehousesLoadedImpl() => _loadDeferredGroup<Warehouse>(
        key: AppStore._warehousesKey,
        loader: _loadWarehousesForStartup,
        target: _warehouses,
        afterLoad: () {
          _ensureDefaultWarehouse();
          _touchDataRevisions(warehouses: true);
        },
      );

  Future<void> _ensureAccountTransactionsLoaded() =>
      _ensureAccountTransactionsLoadedImpl();

  Future<void> _ensureAccountTransactionsLoadedImpl() =>
      _loadDeferredGroup<AccountTransaction>(
        key: AppStore._accountTransactionsKey,
        loader: _loadAccountTransactionsForStartup,
        target: _accountTransactions,
        afterLoad: () {
          _rebuildAccountTransactionIndexes();
          _invalidateAccountLedgerCache();
          _touchDataRevisions(accountTransactions: true);
        },
      );

  InventoryCostingMethod get inventoryCostingMethod => _inventoryCostingMethod;

  bool _isDerivedCacheCurrent(int generation) =>
      generation == _derivedListCacheGeneration;

  String _accountLedgerKey(String accountType, String accountId) =>
      const AccountLedgerReadService().accountKey(accountType, accountId);

  String get deviceId => _deviceId;
  int get _pendingSyncCount => _pendingSyncQueue.length;
  StoreProfile get storeProfile => _storeProfile;
  String get currentRole => _currentUserRole?.name ?? _currentRole;
  AppUser? get activeUser => _activeUser;
  AppIdentity get appIdentity =>
      _appIdentity ??
      AppIdentity.defaults(deviceId: _deviceId, platform: _detectPlatform());
  UserRole? get _currentUserRole =>
      _activeUser == null ? null : _roleById(_activeUser!.roleId);
  bool get _isAdmin =>
      _activeUser?.roleId == 'admin' || _currentUserRole?.isAdmin == true;
  bool _hasAnyPermission(Iterable<String> permissions) =>
      permissions.any(hasPermission);

  bool get _isSuspendedByHost =>
      appIdentity.isClient && ClientSuspensionStateStore.isSuspended;

  double get _totalExpensesAmount => _expensesOverview.totalExpensesAmount;

  void _ensurePurchaseInsightsCache() =>
      _AppStorePurchaseInsights(this as AppStore)
          ._ensurePurchaseInsightsCacheImpl();

  double? _lastPurchasePriceForProduct(String productId) =>
      _AppStorePurchaseInsights(this as AppStore)
          ._lastPurchasePriceForProductImpl(productId);

  String _normalizeLegacySupplierName(String value) =>
      value.trim().toLowerCase();

  List<Product> get _stockTrackedProducts =>
      _AppStoreCatalogRead(this as AppStore)._stockTrackedProductsReadImpl;

  Future<List<Product>> _loadProductsForStartup() async =>
      _loadTypedEntityList<Product>(
        AppStore._productsKey,
        LocalDatabaseService.getProductsFromSqlite,
        Product.fromJson,
        batchSize: 100,
      );

  Future<List<Sale>> _loadSalesForStartup() async => _loadTypedEntityList<Sale>(
        AppStore._salesKey,
        LocalDatabaseService.getSalesFromSqlite,
        Sale.fromJson,
        batchSize: 100,
      );

  Future<List<SaleQuotation>> _loadSaleQuotationsForStartup() async =>
      _loadTypedEntityList<SaleQuotation>(
        AppStore._saleQuotationsKey,
        LocalDatabaseService.getSaleQuotationsFromSqlite,
        SaleQuotation.fromJson,
        batchSize: 100,
      );

  Future<List<DeliveryNote>> _loadDeliveryNotesForStartup() async =>
      _loadTypedEntityList<DeliveryNote>(
        AppStore._deliveryNotesKey,
        LocalDatabaseService.getDeliveryNotesFromSqlite,
        DeliveryNote.fromJson,
        batchSize: 100,
      );

  Future<List<Purchase>> _loadPurchasesForStartup() async =>
      _loadTypedEntityList<Purchase>(
        AppStore._purchasesKey,
        LocalDatabaseService.getPurchasesFromSqlite,
        Purchase.fromJson,
        batchSize: 100,
      );

  Future<List<InventoryCountSession>> _loadInventoryCountsForStartup() async =>
      _loadTypedEntityList<InventoryCountSession>(
        AppStore._inventoryCountsKey,
        LocalDatabaseService.getInventoryCountsFromSqlite,
        InventoryCountSession.fromJson,
        batchSize: 100,
      );

  Future<List<BillOfMaterials>> _loadBillsOfMaterialsForStartup() async =>
      _loadTypedEntityList<BillOfMaterials>(
        AppStore._billsOfMaterialsKey,
        LocalDatabaseService.getBillOfMaterialsFromSqlite,
        BillOfMaterials.fromJson,
        batchSize: 100,
      );

  Future<List<ManufacturingOrder>> _loadManufacturingOrdersForStartup() async =>
      _loadTypedEntityList<ManufacturingOrder>(
        AppStore._manufacturingOrdersKey,
        LocalDatabaseService.getManufacturingOrdersFromSqlite,
        ManufacturingOrder.fromJson,
        batchSize: 100,
      );

  Future<List<Customer>> _loadCustomersForStartup() async =>
      _loadTypedEntityList<Customer>(
        AppStore._customersKey,
        LocalDatabaseService.getCustomersFromSqlite,
        Customer.fromJson,
      );

  Future<List<Supplier>> _loadSuppliersForStartup() async =>
      _loadTypedEntityList<Supplier>(
        AppStore._suppliersKey,
        LocalDatabaseService.getSuppliersFromSqlite,
        Supplier.fromJson,
      );

  Future<List<Expense>> _loadExpensesForStartup() async =>
      _loadTypedEntityList<Expense>(
        AppStore._expensesKey,
        LocalDatabaseService.getExpensesFromSqlite,
        Expense.fromJson,
      );

  Future<List<Warehouse>> _loadWarehousesForStartup() async =>
      _loadTypedEntityList<Warehouse>(
        AppStore._warehousesKey,
        LocalDatabaseService.getWarehousesFromSqlite,
        Warehouse.fromJson,
      );

  Future<List<CatalogItem>> _loadCatalogItemsForStartup(String key) async =>
      _loadTypedEntityList<CatalogItem>(
        key,
        () => LocalDatabaseService.getCatalogItemsFromSqlite(key),
        CatalogItem.fromJson,
      );

  Future<List<SupplierProductPrice>>
      _loadSupplierProductPricesForStartup() async =>
          _loadTypedEntityList<SupplierProductPrice>(
            AppStore._supplierProductPricesKey,
            LocalDatabaseService.getSupplierProductPricesFromSqlite,
            SupplierProductPrice.fromJson,
          );

  Future<List<PriceList>> _loadPriceListsForStartup() async =>
      _loadTypedEntityList<PriceList>(
        AppStore._priceListsKey,
        LocalDatabaseService.getPriceListsFromSqlite,
        PriceList.fromJson,
      );

  Future<List<ProductPrice>> _loadProductPricesForStartup() async =>
      _loadTypedEntityList<ProductPrice>(
        AppStore._productPricesKey,
        LocalDatabaseService.getProductPricesFromSqlite,
        ProductPrice.fromJson,
      );

  Future<List<ProductPriceOverride>>
      _loadProductPriceOverridesForStartup() async =>
          _loadTypedEntityList<ProductPriceOverride>(
            AppStore._productPriceOverridesKey,
            LocalDatabaseService.getProductPriceOverridesFromSqlite,
            ProductPriceOverride.fromJson,
          );

  Future<List<ProductCost>> _loadProductCostsForStartup() async =>
      _loadTypedEntityList<ProductCost>(
        AppStore._productCostsKey,
        LocalDatabaseService.getProductCostsFromSqlite,
        ProductCost.fromJson,
      );

  Future<List<CostingMethodHistory>>
      _loadCostingMethodHistoryForStartup() async =>
          _loadTypedEntityList<CostingMethodHistory>(
            AppStore._costingMethodHistoryKey,
            LocalDatabaseService.getCostingMethodHistoryFromSqlite,
            CostingMethodHistory.fromJson,
          );

  Future<List<InventoryCostLayer>> _loadInventoryCostLayersForStartup() async =>
      _loadTypedEntityList<InventoryCostLayer>(
        AppStore._inventoryCostLayersKey,
        LocalDatabaseService.getInventoryCostLayersFromSqlite,
        InventoryCostLayer.fromJson,
      );

  int _stockMovementIndexForId(String id) =>
      _stockMovementIndexById[id.trim()] ?? -1;

  int _purchaseIndexForId(String id) => _purchaseIndexById[id.trim()] ?? -1;

  int _expenseIndexForId(String id) => _expenseIndexById[id.trim()] ?? -1;

  int _accountTransactionIndexForId(String id) =>
      _accountTransactionIndexById[id.trim()] ?? -1;

  Product? _findProductById(String id) =>
      _AppStoreCatalogRead(this as AppStore)._findProductByIdReadImpl(id);

  Product? _findProductForHistoricalSale(String id) =>
      _AppStoreCatalogRead(this as AppStore)
          ._findProductForHistoricalSaleReadImpl(id);

  Product? _findProductForSaleReturn(String id) =>
      _AppStoreCatalogRead(this as AppStore)
          ._findProductForSaleReturnReadImpl(id);

  bool _isHistoricalProduct(String id) =>
      _AppStoreCatalogRead(this as AppStore)._isHistoricalProductReadImpl(id);

  String _operationalProductIdForStorage(String id) =>
      _AppStoreCatalogRead(this as AppStore)._operationalProductIdReadImpl(id);

  // Default import-section selector for internal full-replace/reset paths.
  // The manual Backup Import flow defines a local `wants` function that
  // shadows this method and uses the user-selected section IDs.
  bool _wants(String id) => true;

  double _safeAccountAmount(double value) =>
      value.isFinite && value > 0 ? value : 0;

  Product _markProductForSync(
    Product product,
    DateTime now, {
    bool isCreate = false,
  }) =>
      _withSyncMeta<Product>(product, now, isCreate: isCreate);

  CatalogItem _markCatalogItemForSync(
    CatalogItem item,
    DateTime now, {
    bool isCreate = false,
  }) =>
      _withSyncMeta<CatalogItem>(item, now, isCreate: isCreate);

  String _productPriceLookupKey(
    String productId,
    String priceListId,
    String unitId,
  ) =>
      '$productId|$priceListId|$unitId';

  String _catalogReferenceValue(CatalogItem item) =>
      item.code.trim().isNotEmpty ? item.code.trim() : item.nameEn.trim();

  String get _purchaseDevicePrefix => _deviceId.isEmpty
      ? 'LOCAL'
      : _deviceId
          .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
          .toUpperCase()
          .padRight(4, '0')
          .substring(0, 4);

  String _actorName() => _activeUser?.fullName.trim().isNotEmpty == true
      ? _activeUser!.fullName.trim()
      : (_activeUser?.username ?? currentRole);

  String _conflictKey(String value) => value.trim().toLowerCase();
}
