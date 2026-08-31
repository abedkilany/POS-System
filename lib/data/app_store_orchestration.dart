part of 'app_store.dart';

/// Cross-domain orchestration that coordinates focused AppStore modules.
///
/// This layer contains lifecycle, cache hydration and invariants that genuinely
/// span domains. It owns no mutable state and keeps the concrete AppStore facade
/// intentionally small.
mixin _AppStoreOrchestration
    on ChangeNotifier, _AppStoreStateAccessors, _AppStoreForwardingApi {


  bool get sqliteSourceOfTruth => LocalDatabaseService.isSqliteAuthoritative;

  StorageLayerSnapshot get storageLayerSnapshot => StorageLayerSnapshot(
        sqliteAuthoritative: sqliteSourceOfTruth,
        productCacheCount: _cachedProducts?.length ?? 0,
        salesCacheCount: _cachedSales?.length ?? 0,
        supplierCacheCount: _cachedSuppliers?.length ?? 0,
        derivedCacheCount: [
          _cachedSaleQuotations,
          _cachedDeliveryNotes,
          _cachedBillsOfMaterials,
          _cachedManufacturingOrders,
          _cachedSupplierProductPrices,
          _cachedPriceLists,
          _cachedProductPrices,
          _cachedProductPriceOverrides,
          _cachedProductCosts,
          _cachedCostingMethodHistory,
          _cachedInventoryCostLayers,
          _cachedPurchasesOverview,
          _cachedExpensesOverview,
        ].where((item) => item != null).length,
        syncChangeCount: _syncChanges.length,
        syncQueueCount: _syncQueue.length,
      );

  Customer get walkInCustomer => Customer(
        id: AppStore.walkInCustomerId,
        name: AppStore.walkInCustomerName,
        phone: '',
        address: '',
      );

  bool get isReady => _isReady;
  int get productsRevision => _productsRevision;
  int get customersRevision => _customersRevision;
  int get salesRevision => _salesRevision;
  int get deliveryNotesRevision => _deliveryNotesRevision;
  int get suppliersRevision => _suppliersRevision;
  int get supplierProductPricesRevision => _supplierProductPricesRevision;
  int get purchasesRevision => _purchasesRevision;
  int get expensesRevision => _expensesRevision;
  int get stockMovementsRevision => _stockMovementsRevision;
  int get inventoryCountsRevision => _inventoryCountsRevision;
  int get warehousesRevision => _warehousesRevision;
  int get accountTransactionsRevision => _accountTransactionsRevision;
  int get storeProfileRevision => _storeProfileRevision;
  int get accountingRevision => Object.hashAll(<Object?>[
        _customersRevision,
        _suppliersRevision,
        _salesRevision,
        _purchasesRevision,
        _expensesRevision,
        _accountTransactionsRevision,
        _storeProfileRevision,
      ]);
  int get dashboardRevision => Object.hashAll(<Object?>[
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
  int get reportsRevision => Object.hashAll(<Object?>[
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
  int get inventoryRevision => Object.hashAll(<Object?>[
        _productsRevision,
        _stockMovementsRevision,
        _inventoryCountsRevision,
        _warehousesRevision,
      ]);
  int get salesPageRevision => Object.hashAll(<Object?>[
        _productsRevision,
        _customersRevision,
        _salesRevision,
        _deliveryNotesRevision,
        _storeProfileRevision,
      ]);
  int get productsPageRevision => Object.hashAll(<Object?>[
        _productsRevision,
        _purchasesRevision,
        _storeProfileRevision,
      ]);
  bool get isCoreDataLoaded => _isReady;
  bool get isLedgerDataLoaded => _isReady;
  bool get isSyncDataLoaded => _syncDataLoadCompleted;
  bool get isHeavyDataLoaded =>
      _heavyDataLoadCompleted &&
      _ledgerDataLoadCompleted &&
      _syncDataLoadCompleted;

  Future<void> ensureSyncDataLoaded() => _requestSyncDataLoad();

  Future<void> ensureProductsLoaded() => _loadDeferredGroup<Product>(
        key: AppStore._productsKey,
        loader: _loadProductsForStartup,
        target: _products,
        afterLoad: () {
          _ensureCatalogDefaults();
          _rebuildProductIndexes();
          _ensureDefaultPriceLists();
          _ensureDefaultProductPriceEntries();
          _ensureProductCostEntries();
          _ensureCostingMethodHistory();
          _touchDataRevisions(products: true);
        },
      );

  Future<void> ensureCustomersLoaded() => _loadDeferredGroup<Customer>(
        key: AppStore._customersKey,
        loader: _loadCustomersForStartup,
        target: _customers,
        afterLoad: () {
          _normalizeCustomers();
          _rebuildCustomerIndexes();
          _touchDataRevisions(customers: true);
        },
      );

  Future<void> ensureSalesLoaded() => _loadDeferredGroup<Sale>(
        key: AppStore._salesKey,
        loader: _loadSalesForStartup,
        target: _sales,
        afterLoad: () {
          _invoiceCounter = _loadInvoiceCounter();
          _touchDataRevisions(sales: true);
        },
      );

  Future<void> ensureSaleQuotationsLoaded() =>
      _loadDeferredGroup<SaleQuotation>(
        key: AppStore._saleQuotationsKey,
        loader: _loadSaleQuotationsForStartup,
        target: _saleQuotations,
      );

  Future<void> ensureDeliveryNotesLoaded() => _loadDeferredGroup<DeliveryNote>(
        key: AppStore._deliveryNotesKey,
        loader: _loadDeliveryNotesForStartup,
        target: _deliveryNotes,
        afterLoad: () {
          _touchDataRevisions(deliveryNotes: true);
          _invalidateDerivedDataCaches();
        },
      );

  Future<void> ensureBillsOfMaterialsLoaded() =>
      _loadDeferredGroup<BillOfMaterials>(
        key: AppStore._billsOfMaterialsKey,
        loader: _loadBillsOfMaterialsForStartup,
        target: _billsOfMaterials,
      );

  Future<void> ensureManufacturingOrdersLoaded() =>
      _loadDeferredGroup<ManufacturingOrder>(
        key: AppStore._manufacturingOrdersKey,
        loader: _loadManufacturingOrdersForStartup,
        target: _manufacturingOrders,
      );

  Future<void> ensureSuppliersLoaded() => _loadDeferredGroup<Supplier>(
        key: AppStore._suppliersKey,
        loader: _loadSuppliersForStartup,
        target: _suppliers,
        afterLoad: () {
          _rebuildSupplierIndexes();
          _touchDataRevisions(suppliers: true);
        },
      );

  Future<void> ensureSupplierProductPricesLoaded() =>
      _loadDeferredGroup<SupplierProductPrice>(
        key: AppStore._supplierProductPricesKey,
        loader: _loadSupplierProductPricesForStartup,
        target: _supplierProductPrices,
        afterLoad: () {
          _touchDataRevisions(supplierProductPrices: true);
        },
      );

  Future<void> ensurePriceListsLoaded() => _loadDeferredGroup<PriceList>(
        key: AppStore._priceListsKey,
        loader: _loadPriceListsForStartup,
        target: _priceLists,
        afterLoad: () {
          _ensureDefaultPriceLists();
          _rebuildProductPricingLookupCaches();
          _ensureDefaultProductPriceEntries();
        },
      );

  Future<void> ensureProductPricesLoaded() => _loadDeferredGroup<ProductPrice>(
        key: AppStore._productPricesKey,
        loader: _loadProductPricesForStartup,
        target: _productPrices,
        afterLoad: () {
          _rebuildProductPricingLookupCaches();
          _ensureDefaultProductPriceEntries();
        },
      );

  Future<void> ensureProductPriceOverridesLoaded() =>
      _loadDeferredGroup<ProductPriceOverride>(
        key: AppStore._productPriceOverridesKey,
        loader: _loadProductPriceOverridesForStartup,
        target: _productPriceOverrides,
        afterLoad: () {
          _rebuildProductPricingLookupCaches();
        },
      );

  Future<void> ensureProductCostsLoaded() => _loadDeferredGroup<ProductCost>(
        key: AppStore._productCostsKey,
        loader: _loadProductCostsForStartup,
        target: _productCosts,
        afterLoad: () {
          _rebuildProductPricingLookupCaches();
          _ensureProductCostEntries();
        },
      );

  Future<void> ensureCostingMethodHistoryLoaded() =>
      _loadDeferredGroup<CostingMethodHistory>(
        key: AppStore._costingMethodHistoryKey,
        loader: _loadCostingMethodHistoryForStartup,
        target: _costingMethodHistory,
        afterLoad: () {
          _ensureCostingMethodHistory();
        },
      );

  Future<void> ensureInventoryCostLayersLoaded() =>
      _loadDeferredGroup<InventoryCostLayer>(
        key: AppStore._inventoryCostLayersKey,
        loader: _loadInventoryCostLayersForStartup,
        target: _inventoryCostLayers,
      );

  Future<void> ensureExpensesLoaded() => _loadDeferredGroup<Expense>(
        key: AppStore._expensesKey,
        loader: _loadExpensesForStartup,
        target: _expenses,
        afterLoad: () {
          _rebuildExpenseIndexes();
          _touchDataRevisions(expenses: true);
        },
      );

  Future<void> ensurePurchasesLoaded() => _loadDeferredGroup<Purchase>(
        key: AppStore._purchasesKey,
        loader: _loadPurchasesForStartup,
        target: _purchases,
        afterLoad: () {
          _rebuildPurchaseIndexes();
          _touchDataRevisions(purchases: true);
        },
      );

  Future<void> ensureStockMovementsLoaded() =>
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

  Future<void> ensureInventoryCountsLoaded() =>
      _loadDeferredGroup<InventoryCountSession>(
        key: AppStore._inventoryCountsKey,
        loader: _loadInventoryCountsForStartup,
        target: _inventoryCounts,
        afterLoad: () {
          _touchDataRevisions(inventoryCounts: true);
        },
      );

  Future<void> ensureWarehousesLoaded() => _loadDeferredGroup<Warehouse>(
        key: AppStore._warehousesKey,
        loader: _loadWarehousesForStartup,
        target: _warehouses,
        afterLoad: () {
          _ensureDefaultWarehouse();
          _touchDataRevisions(warehouses: true);
        },
      );

  Future<void> ensureAccountTransactionsLoaded() =>
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

  List<Product> get products =>
      _AppStoreCatalogRead(this as AppStore)._productsReadImpl;

  Product? productById(String id) =>
      _AppStoreCatalogRead(this as AppStore)._productByIdReadImpl(id);

  List<Product> get allProductsForDiagnostics =>
      _AppStoreCatalogRead(this as AppStore)._allProductsForDiagnosticsReadImpl;
  List<Customer> get allCustomersForDiagnostics =>
      _AppStorePartyRead(this as AppStore)._allCustomersForDiagnosticsReadImpl;
  List<Supplier> get allSuppliersForDiagnostics =>
      _AppStorePartyRead(this as AppStore)._allSuppliersForDiagnosticsReadImpl;
  List<Customer> get customers =>
      _AppStorePartyRead(this as AppStore)._customersReadImpl;

  List<CreditNote> get creditNotes => List.unmodifiable(_creditNotes);

  List<Supplier> get suppliers =>
      _AppStorePartyRead(this as AppStore)._suppliersReadImpl;

  List<SupplierProductPrice> get supplierProductPrices =>
      _AppStorePartyRead(this as AppStore)._supplierProductPricesReadImpl;

  List<PriceList> get priceLists =>
      _AppStoreCatalogRead(this as AppStore)._priceListsReadImpl;

  List<ProductPrice> get productPrices =>
      _AppStoreCatalogRead(this as AppStore)._productPricesReadImpl;

  List<ProductPriceOverride> get productPriceOverrides =>
      _AppStoreCatalogRead(this as AppStore)._productPriceOverridesReadImpl;

  List<ProductCost> get productCosts =>
      _AppStoreCatalogRead(this as AppStore)._productCostsReadImpl;

  List<CostingMethodHistory> get costingMethodHistory =>
      _AppStoreCatalogRead(this as AppStore)._costingMethodHistoryReadImpl;
  InventoryCostingMethod get inventoryCostingMethod => _inventoryCostingMethod;

  List<InventoryCostLayer> get inventoryCostLayers =>
      _AppStoreCatalogRead(this as AppStore)._inventoryCostLayersReadImpl;

  List<SupplierProductPrice> get allSupplierProductPricesForDiagnostics =>
      _AppStorePartyRead(this as AppStore)._allSupplierProductPricesForDiagnosticsReadImpl;
  List<CatalogItem> get categories =>
      _AppStoreCatalogRead(this as AppStore)._categoriesReadImpl;

  List<CatalogItem> get brands =>
      _AppStoreCatalogRead(this as AppStore)._brandsReadImpl;

  List<CatalogItem> get units =>
      _AppStoreCatalogRead(this as AppStore)._unitsReadImpl;

  int get dataConflictCount => dataConflicts.length;
  int get blockingDataConflictCount =>
      dataConflicts.where((item) => item.blocking).length;

  List<StockMovement> get autoCorrectionMovements => List.unmodifiable(
        _stockMovements
            .where((movement) => movement.type == 'auto_correction')
            .toList()
            .reversed,
      );
  List<StockMovement> get pendingAutoCorrectionMovements => List.unmodifiable(
        _stockMovements
            .where(
              (movement) =>
                  movement.type == 'auto_correction' && !movement.isReviewed,
            )
            .toList()
            .reversed,
      );
  int get pendingAutoCorrectionCount => pendingAutoCorrectionMovements.length;

  int get storeRevision => _storeRevision;

  bool _isDerivedCacheCurrent(int generation) =>
      generation == _derivedListCacheGeneration;

  String _accountLedgerKey(String accountType, String accountId) =>
      '${accountType.trim().toLowerCase()}::${accountId.trim()}';

  int get currentSyncSequence => _syncSequence;
  int get latestStoredAuthoritativeSequence =>
      _latestStoredAuthoritativeSequence();

  bool hasOutstandingSyncWorkForTarget(String target) =>
      outstandingSyncQueueCountForTarget(target) > 0;
  String get deviceId => _deviceId;
  int get pendingSyncCount => pendingSyncQueue.length;
  int get pendingSyncQueueCount => pendingSyncQueue.length;
  StoreProfile get storeProfile => _storeProfile;
  String get currentRole => currentUserRole?.name ?? _currentRole;
  List<UserRole> get roles => List.unmodifiable(_roles);
  List<AppUser> get users => List.unmodifiable(_users);
  AppUser? get activeUser => _activeUser;
  bool get rememberLogin => _rememberLogin;
  AppUser? get currentUser => _activeUser;
  AppIdentity get appIdentity =>
      _appIdentity ??
      AppIdentity.defaults(deviceId: _deviceId, platform: _detectPlatform());
  UserRole? get currentUserRole =>
      _activeUser == null ? null : roleById(_activeUser!.roleId);
  bool get isAdmin =>
      _activeUser?.roleId == 'admin' || currentUserRole?.isAdmin == true;
  bool hasAnyPermission(Iterable<String> permissions) =>
      permissions.any(hasPermission);
  bool hasAllPermissions(Iterable<String> permissions) =>
      permissions.every(hasPermission);

  bool get canViewDashboard => canAccessPage('dashboard');
  bool get canViewProducts => hasAnyPermission(<String>{
        AppPermission.productsView,
        AppPermission.productsManage,
        AppPermission.productsCreate,
        AppPermission.productsEdit,
        AppPermission.productsDelete,
      });
  bool get canManageProducts => hasAnyPermission(<String>{
        AppPermission.productsManage,
        AppPermission.productsCreate,
        AppPermission.productsEdit,
        AppPermission.productsDelete,
      });
  bool get canViewCustomers => hasAnyPermission(<String>{
        AppPermission.customersView,
        AppPermission.customersManage,
      });
  bool get canManageCustomers => hasPermission(AppPermission.customersManage);
  bool get canManageCustomerPayments =>
      hasPermission(AppPermission.customersPaymentManage);
  bool get canViewSuppliers => hasAnyPermission(<String>{
        AppPermission.suppliersView,
        AppPermission.suppliersManage,
      });
  bool get canManageSuppliers => hasPermission(AppPermission.suppliersManage);
  bool get canManageSupplierPayments =>
      hasPermission(AppPermission.suppliersPaymentManage);
  bool get canViewSales => hasAnyPermission(<String>{
        AppPermission.salesView,
        AppPermission.salesCreate,
        AppPermission.salesCancel,
      });
  bool get canSell => hasPermission(AppPermission.salesCreate);

  bool get canViewQuotations => canAccessPage('quotations');
  bool get canManageQuotations => hasPermission(AppPermission.quotationsManage);
  bool get canViewDeliveryNotes => canAccessPage('delivery_notes');
  bool get canManageDeliveryNotes =>
      hasPermission(AppPermission.deliveryNotesManage);
  bool get canViewPurchases => canAccessPage('purchases');
  bool get canManagePurchases =>
      hasPermission(AppPermission.purchasesManage);
  bool get canViewExpenses => canAccessPage('expenses');
  bool get canManageExpenses => hasPermission(AppPermission.expensesManage);
  bool get canViewAccounting => canAccessPage('accounting');
  bool get canManageAccounting => hasPermission(AppPermission.accountingManage);
  bool get canManageCashBox => hasPermission(AppPermission.cashBoxManage);
  bool get canViewInventory => canAccessPage('inventory');
  bool get canManageInventory => hasAnyPermission(<String>{
        AppPermission.inventoryWarehousesManage,
        AppPermission.inventoryCorrectionsManage,
        AppPermission.inventoryCountsManage,
        AppPermission.inventoryWasteManage,
        AppPermission.inventoryManufacturingManage,
      });
  bool get canViewReports => canAccessPage('reports');
  bool get canViewCashBox => canAccessPage('cash_box') || canViewAccounting;
  bool get canViewSettings => canAccessPage('settings');
  bool get canViewDatabase => canAccessPage('database');
  bool get canViewMaintenance => canAccessPage('maintenance');
  bool get canManageMaintenance =>
      hasPermission(AppPermission.maintenanceManage);
  bool get canManageUsers => hasAnyPermission(
      <String>{AppPermission.usersManage, AppPermission.rolesManage});
  bool get canManageUsersPage => hasAnyPermission(
      <String>{AppPermission.usersManage, AppPermission.rolesManage});
  bool get canManageDatabase => hasPermission(AppPermission.databaseManage);
  bool get canDeleteOrCancel => hasPermission(AppPermission.salesCancel);
  bool get needsInitialAdminSetup =>
      _users.isEmpty || _hasOnlyLegacyDefaultAdminUser;
  bool get hasLocalAdminUser =>
      _users.any((item) => item.roleId == 'admin' && item.isActive);

  bool get isSuspendedByHost =>
      appIdentity.isClient && ClientSuspensionStateStore.isSuspended;
  String get suspendedByHostReason => ClientSuspensionStateStore.reason;

  double get totalExpensesAmount => expensesOverview.totalExpensesAmount;
  double get totalPurchasesAmount => purchasesOverview.totalPurchasesAmount;
  int get pendingPurchaseCount => purchasesOverview.pendingPurchaseCount;

  PurchasesOverview get purchasesOverview =>
      _AppStorePurchaseInsights(this as AppStore)._purchasesOverviewImpl;

  void _ensurePurchaseInsightsCache() =>
      _AppStorePurchaseInsights(this as AppStore)._ensurePurchaseInsightsCacheImpl();

  List<SupplierPurchasePrice> purchasePriceHistoryForProduct(
    String productId,
  ) =>
      _AppStorePurchaseInsights(this as AppStore)
          ._purchasePriceHistoryForProductImpl(productId);

  List<SupplierPurchasePrice> supplierPriceComparisonForProduct(
    String productId,
  ) =>
      _AppStorePurchaseInsights(this as AppStore)
          ._supplierPriceComparisonForProductImpl(productId);

  double? lastPurchasePriceFor({
    required String productId,
    required String supplierId,
  }) =>
      _AppStorePurchaseInsights(this as AppStore)._lastPurchasePriceForImpl(
        productId: productId,
        supplierId: supplierId,
      );

  double? lastPurchasePriceForProduct(String productId) =>
      _AppStorePurchaseInsights(this as AppStore)
          ._lastPurchasePriceForProductImpl(productId);

  PurchaseItem? lastPurchaseItemFor({
    required String productId,
    required String supplierId,
  }) =>
      _AppStorePurchaseInsights(this as AppStore)._lastPurchaseItemForImpl(
        productId: productId,
        supplierId: supplierId,
      );

  PurchaseItem? lastPurchaseItemForProduct(String productId) =>
      _AppStorePurchaseInsights(this as AppStore)
          ._lastPurchaseItemForProductImpl(productId);

  double averagePurchaseCostForProduct(String productId) =>
      _AppStorePurchaseInsights(this as AppStore)
          ._averagePurchaseCostForProductImpl(productId);

  String _normalizeLegacySupplierName(String value) =>
      value.trim().toLowerCase();

  int get lowStockCount => products
      .where((product) => product.trackStock && product.isLowStock)
      .length;
  List<Product> get stockTrackedProducts =>
      _AppStoreCatalogRead(this as AppStore)._stockTrackedProductsReadImpl;

  double get totalUnitsInStock =>
      stockTrackedProducts.fold<double>(0, (sum, item) => sum + item.stock);
  double get inventoryRetailValue => stockTrackedProducts.fold<double>(
        0,
        (sum, item) => sum + (item.usdPrice * item.stock),
      );
  double get inventoryCostValue => stockTrackedProducts.fold<double>(
        0,
        (sum, item) => sum + (_safeUsdCost(item) * item.stock),
      );

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

  String get approvedHostTransferDeviceId =>
      LocalDatabaseService.getString(AppStore._hostTransferApprovedDeviceKey)?.trim() ??
      '';

  int _stockMovementIndexForId(String id) =>
      _stockMovementIndexById[id.trim()] ?? -1;

  int _purchaseIndexForId(String id) => _purchaseIndexById[id.trim()] ?? -1;

  int _expenseIndexForId(String id) => _expenseIndexById[id.trim()] ?? -1;

  int _accountTransactionIndexForId(String id) =>
      _accountTransactionIndexById[id.trim()] ?? -1;

  String resolveCustomerName(String? customerId) =>
      _AppStorePartyRead(this as AppStore)._resolveCustomerNameReadImpl(customerId);

  String sanitizeSelectedCustomerId(String? customerId) =>
      _AppStorePartyRead(this as AppStore)._sanitizeSelectedCustomerIdReadImpl(customerId);

  Product? _findProductById(String id) =>
      _AppStoreCatalogRead(this as AppStore)._findProductByIdReadImpl(id);

  // Default import-section selector for internal full-replace/reset paths.
  // The manual Backup Import flow defines a local `wants` function that
  // shadows this method and uses the user-selected section IDs.
  bool wants(String id) => true;

  Product? findProductByCode(String code) =>
      _AppStoreCatalogRead(this as AppStore)._findProductByCodeReadImpl(code);

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

  Future<void> deleteExpense(String id) => deleteDraftExpense(id);

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
