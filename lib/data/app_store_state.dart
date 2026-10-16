part of 'app_store.dart';

/// Mutable runtime state is partitioned by business domain.
///
/// SQLite remains authoritative; these objects only own AppStore's in-memory
/// caches, revisions and short-lived orchestration state. Keeping state outside
/// the facade prevents AppStore from becoming the owner of every concern again.

class _AppStoreState {
  final catalog = CatalogState();
  final commerce = CommerceState();
  final inventory = InventoryState();
  final accounting = AccountingState();
  final security = SecurityState();
  final sync = SyncState();
  final runtime = RuntimeState();
}

mixin _AppStoreStateAccessors on ChangeNotifier {
  final _appStoreState = _AppStoreState();

  // Catalog state compatibility accessors.
  // ignore: unused_element
  List<Product> get _products => _appStoreState.catalog.products;
  // ignore: unused_element
  List<SupplierProductPrice> get _supplierProductPrices =>
      _appStoreState.catalog.supplierProductPrices;
  // ignore: unused_element
  List<PriceList> get _priceLists => _appStoreState.catalog.priceLists;
  // ignore: unused_element
  List<ProductPrice> get _productPrices =>
      _appStoreState.catalog.productPrices;
  // ignore: unused_element
  List<ProductPriceOverride> get _productPriceOverrides =>
      _appStoreState.catalog.productPriceOverrides;
  // ignore: unused_element
  List<ProductCost> get _productCosts => _appStoreState.catalog.productCosts;
  // ignore: unused_element
  List<CostingMethodHistory> get _costingMethodHistory =>
      _appStoreState.catalog.costingMethodHistory;
  // ignore: unused_element
  List<CatalogItem> get _categories => _appStoreState.catalog.categories;
  // ignore: unused_element
  List<CatalogItem> get _brands => _appStoreState.catalog.brands;
  // ignore: unused_element
  List<CatalogItem> get _units => _appStoreState.catalog.units;
  Map<String, int> get _productIndexById =>
      _appStoreState.catalog.productIndexById;
  Map<String, String> get _productIdByNormalizedCode =>
      _appStoreState.catalog.productIdByNormalizedCode;
  Map<String, String> get _productIdByNormalizedBarcode =>
      _appStoreState.catalog.productIdByNormalizedBarcode;
  Map<String, ProductPrice> get _productPriceByLookupKey =>
      _appStoreState.catalog.productPriceByLookupKey;
  Map<String, ProductCost> get _productCostByProductId =>
      _appStoreState.catalog.productCostByProductId;
  Map<String, int> get _productCostIndexByProductId =>
      _appStoreState.catalog.productCostIndexByProductId;
  List<Product>? get _cachedProducts => _appStoreState.catalog.cachedProducts;
  set _cachedProducts(List<Product>? value) =>
      _appStoreState.catalog.cachedProducts = value;
  int get _cachedProductsGeneration =>
      _appStoreState.catalog.cachedProductsGeneration;
  set _cachedProductsGeneration(int value) =>
      _appStoreState.catalog.cachedProductsGeneration = value;
  List<Product>? get _cachedStockTrackedProducts =>
      _appStoreState.catalog.cachedStockTrackedProducts;
  set _cachedStockTrackedProducts(List<Product>? value) =>
      _appStoreState.catalog.cachedStockTrackedProducts = value;
  int get _cachedStockTrackedProductsGeneration =>
      _appStoreState.catalog.cachedStockTrackedProductsGeneration;
  set _cachedStockTrackedProductsGeneration(int value) =>
      _appStoreState.catalog.cachedStockTrackedProductsGeneration = value;
  UnmodifiableListView<ProductPriceOverride>?
      get _cachedProductPriceOverrides =>
          _appStoreState.catalog.cachedProductPriceOverrides;
  set _cachedProductPriceOverrides(
          UnmodifiableListView<ProductPriceOverride>? value) =>
      _appStoreState.catalog.cachedProductPriceOverrides = value;
  UnmodifiableListView<CostingMethodHistory>? get _cachedCostingMethodHistory =>
      _appStoreState.catalog.cachedCostingMethodHistory;
  set _cachedCostingMethodHistory(
          UnmodifiableListView<CostingMethodHistory>? value) =>
      _appStoreState.catalog.cachedCostingMethodHistory = value;
  int get _cachedProductPriceOverridesGeneration =>
      _appStoreState.catalog.cachedProductPriceOverridesGeneration;
  set _cachedProductPriceOverridesGeneration(int value) =>
      _appStoreState.catalog.cachedProductPriceOverridesGeneration = value;
  int get _cachedCostingMethodHistoryGeneration =>
      _appStoreState.catalog.cachedCostingMethodHistoryGeneration;
  set _cachedCostingMethodHistoryGeneration(int value) =>
      _appStoreState.catalog.cachedCostingMethodHistoryGeneration = value;

  // Commerce state compatibility accessors.
  // ignore: unused_element
  List<Customer> get _customers => _appStoreState.commerce.customers;
  List<Sale> get _sales => _appStoreState.commerce.sales;
  List<CreditNote> get _creditNotes => _appStoreState.commerce.creditNotes;
  List<SaleQuotation> get _saleQuotations =>
      _appStoreState.commerce.saleQuotations;
  List<DeliveryNote> get _deliveryNotes =>
      _appStoreState.commerce.deliveryNotes;
  // ignore: unused_element
  List<Supplier> get _suppliers => _appStoreState.commerce.suppliers;
  List<Expense> get _expenses => _appStoreState.commerce.expenses;
  List<Purchase> get _purchases => _appStoreState.commerce.purchases;
  Map<String, int> get _purchaseIndexById =>
      _appStoreState.commerce.purchaseIndexById;
  Map<String, int> get _expenseIndexById =>
      _appStoreState.commerce.expenseIndexById;
  Map<String, int> get _customerIndexById =>
      _appStoreState.commerce.customerIndexById;
  Map<String, String> get _customerIdByNormalizedName =>
      _appStoreState.commerce.customerIdByNormalizedName;
  Map<String, int> get _supplierIndexById =>
      _appStoreState.commerce.supplierIndexById;
  Map<String, String> get _supplierIdByNormalizedName =>
      _appStoreState.commerce.supplierIdByNormalizedName;
  Map<String, List<SupplierPurchasePrice>> get _purchaseHistoryByProductCache =>
      _appStoreState.commerce.purchaseHistoryByProductCache;
  Map<String, ProductPurchaseMetrics> get _purchaseMetricsByProductCache =>
      _appStoreState.commerce.purchaseMetricsByProductCache;
  bool get _purchaseInsightsCacheDirty =>
      _appStoreState.commerce.purchaseInsightsCacheDirty;
  set _purchaseInsightsCacheDirty(bool value) =>
      _appStoreState.commerce.purchaseInsightsCacheDirty = value;
  UnmodifiableListView<Sale>? get _cachedSales =>
      _appStoreState.commerce.cachedSales;
  set _cachedSales(UnmodifiableListView<Sale>? value) =>
      _appStoreState.commerce.cachedSales = value;
  int get _cachedSalesGeneration =>
      _appStoreState.commerce.cachedSalesGeneration;
  set _cachedSalesGeneration(int value) =>
      _appStoreState.commerce.cachedSalesGeneration = value;
  int get _invoiceCounter => _appStoreState.commerce.invoiceCounter;
  set _invoiceCounter(int value) =>
      _appStoreState.commerce.invoiceCounter = value;
  int get _purchaseCounter => _appStoreState.commerce.purchaseCounter;
  set _purchaseCounter(int value) =>
      _appStoreState.commerce.purchaseCounter = value;
  UnmodifiableListView<SaleQuotation>? get _cachedSaleQuotations =>
      _appStoreState.commerce.cachedSaleQuotations;
  set _cachedSaleQuotations(UnmodifiableListView<SaleQuotation>? value) =>
      _appStoreState.commerce.cachedSaleQuotations = value;
  UnmodifiableListView<DeliveryNote>? get _cachedDeliveryNotes =>
      _appStoreState.commerce.cachedDeliveryNotes;
  set _cachedDeliveryNotes(UnmodifiableListView<DeliveryNote>? value) =>
      _appStoreState.commerce.cachedDeliveryNotes = value;
  Map<String, DeliveryNote>? get _cachedDeliveryNoteBySaleId =>
      _appStoreState.commerce.cachedDeliveryNoteBySaleId;
  set _cachedDeliveryNoteBySaleId(Map<String, DeliveryNote>? value) =>
      _appStoreState.commerce.cachedDeliveryNoteBySaleId = value;
  UnmodifiableListView<Supplier>? get _cachedSuppliers =>
      _appStoreState.commerce.cachedSuppliers;
  set _cachedSuppliers(UnmodifiableListView<Supplier>? value) =>
      _appStoreState.commerce.cachedSuppliers = value;
  PurchasesOverview? get _cachedPurchasesOverview =>
      _appStoreState.commerce.cachedPurchasesOverview;
  set _cachedPurchasesOverview(PurchasesOverview? value) =>
      _appStoreState.commerce.cachedPurchasesOverview = value;
  int get _cachedPurchasesOverviewRevision =>
      _appStoreState.commerce.cachedPurchasesOverviewRevision;
  set _cachedPurchasesOverviewRevision(int value) =>
      _appStoreState.commerce.cachedPurchasesOverviewRevision = value;
  String get _cachedPurchasesOverviewMonthKey =>
      _appStoreState.commerce.cachedPurchasesOverviewMonthKey;
  set _cachedPurchasesOverviewMonthKey(String value) =>
      _appStoreState.commerce.cachedPurchasesOverviewMonthKey = value;
  ExpensesOverview? get _cachedExpensesOverview =>
      _appStoreState.commerce.cachedExpensesOverview;
  set _cachedExpensesOverview(ExpensesOverview? value) =>
      _appStoreState.commerce.cachedExpensesOverview = value;
  int get _cachedExpensesOverviewRevision =>
      _appStoreState.commerce.cachedExpensesOverviewRevision;
  set _cachedExpensesOverviewRevision(int value) =>
      _appStoreState.commerce.cachedExpensesOverviewRevision = value;
  int get _cachedSaleQuotationsGeneration =>
      _appStoreState.commerce.cachedSaleQuotationsGeneration;
  set _cachedSaleQuotationsGeneration(int value) =>
      _appStoreState.commerce.cachedSaleQuotationsGeneration = value;
  int get _cachedDeliveryNotesGeneration =>
      _appStoreState.commerce.cachedDeliveryNotesGeneration;
  set _cachedDeliveryNotesGeneration(int value) =>
      _appStoreState.commerce.cachedDeliveryNotesGeneration = value;
  int get _cachedDeliveryNoteBySaleIdGeneration =>
      _appStoreState.commerce.cachedDeliveryNoteBySaleIdGeneration;
  set _cachedDeliveryNoteBySaleIdGeneration(int value) =>
      _appStoreState.commerce.cachedDeliveryNoteBySaleIdGeneration = value;
  int get _cachedSuppliersGeneration =>
      _appStoreState.commerce.cachedSuppliersGeneration;
  set _cachedSuppliersGeneration(int value) =>
      _appStoreState.commerce.cachedSuppliersGeneration = value;

  // Inventory state compatibility accessors.
  List<BillOfMaterials> get _billsOfMaterials =>
      _appStoreState.inventory.billsOfMaterials;
  List<ManufacturingOrder> get _manufacturingOrders =>
      _appStoreState.inventory.manufacturingOrders;
  // ignore: unused_element
  List<InventoryCostLayer> get _inventoryCostLayers =>
      _appStoreState.inventory.inventoryCostLayers;
  List<StockMovement> get _stockMovements =>
      _appStoreState.inventory.stockMovements;
  List<InventoryCountSession> get _inventoryCounts =>
      _appStoreState.inventory.inventoryCounts;
  List<Warehouse> get _warehouses => _appStoreState.inventory.warehouses;
  Map<String, int> get _stockMovementIndexById =>
      _appStoreState.inventory.stockMovementIndexById;
  Map<String, int> get _inventoryCostLayerIndexById =>
      _appStoreState.inventory.inventoryCostLayerIndexById;
  Map<String, Map<String, double>> get _warehouseStockByProductCache =>
      _appStoreState.inventory.warehouseStockByProductCache;
  bool get _warehouseStockCacheDirty =>
      _appStoreState.inventory.warehouseStockCacheDirty;
  set _warehouseStockCacheDirty(bool value) =>
      _appStoreState.inventory.warehouseStockCacheDirty = value;
  InventoryCostingMethod get _inventoryCostingMethod =>
      _appStoreState.inventory.inventoryCostingMethod;
  set _inventoryCostingMethod(InventoryCostingMethod value) =>
      _appStoreState.inventory.inventoryCostingMethod = value;
  UnmodifiableListView<BillOfMaterials>? get _cachedBillsOfMaterials =>
      _appStoreState.inventory.cachedBillsOfMaterials;
  set _cachedBillsOfMaterials(UnmodifiableListView<BillOfMaterials>? value) =>
      _appStoreState.inventory.cachedBillsOfMaterials = value;
  UnmodifiableListView<ManufacturingOrder>? get _cachedManufacturingOrders =>
      _appStoreState.inventory.cachedManufacturingOrders;
  set _cachedManufacturingOrders(
          UnmodifiableListView<ManufacturingOrder>? value) =>
      _appStoreState.inventory.cachedManufacturingOrders = value;
  int get _cachedBillsOfMaterialsGeneration =>
      _appStoreState.inventory.cachedBillsOfMaterialsGeneration;
  set _cachedBillsOfMaterialsGeneration(int value) =>
      _appStoreState.inventory.cachedBillsOfMaterialsGeneration = value;
  int get _cachedManufacturingOrdersGeneration =>
      _appStoreState.inventory.cachedManufacturingOrdersGeneration;
  set _cachedManufacturingOrdersGeneration(int value) =>
      _appStoreState.inventory.cachedManufacturingOrdersGeneration = value;

  // Accounting state compatibility accessors.
  List<AccountTransaction> get _accountTransactions =>
      _appStoreState.accounting.accountTransactions;
  Map<String, int> get _accountTransactionIndexById =>
      _appStoreState.accounting.accountTransactionIndexById;
  Map<String, double> get _accountBalanceCache =>
      _appStoreState.accounting.accountBalanceCache;
  Map<String, List<AccountTransaction>>
      get _accountTransactionsByAccountCache =>
          _appStoreState.accounting.accountTransactionsByAccountCache;
  bool get _accountLedgerCacheDirty =>
      _appStoreState.accounting.accountLedgerCacheDirty;
  set _accountLedgerCacheDirty(bool value) =>
      _appStoreState.accounting.accountLedgerCacheDirty = value;
  Map<String, Future<bool>> get _pendingPurchaseAccountingTasks =>
      _appStoreState.accounting.pendingPurchaseAccountingTasks;
  Future<void> get _purchaseAccountingQueue =>
      _appStoreState.accounting.purchaseAccountingQueue;
  set _purchaseAccountingQueue(Future<void> value) =>
      _appStoreState.accounting.purchaseAccountingQueue = value;
  DateTime? get _phase8AccountingSyncCursor =>
      _appStoreState.accounting.phase8AccountingSyncCursor;
  set _phase8AccountingSyncCursor(DateTime? value) =>
      _appStoreState.accounting.phase8AccountingSyncCursor = value;
  bool get _phase8AccountingSyncCaptureInFlight =>
      _appStoreState.accounting.phase8AccountingSyncCaptureInFlight;
  set _phase8AccountingSyncCaptureInFlight(bool value) =>
      _appStoreState.accounting.phase8AccountingSyncCaptureInFlight = value;
  bool get _phase8AccountingSyncCapturePending =>
      _appStoreState.accounting.phase8AccountingSyncCapturePending;
  set _phase8AccountingSyncCapturePending(bool value) =>
      _appStoreState.accounting.phase8AccountingSyncCapturePending = value;

  // Security state compatibility accessors.
  String get _currentRole => _appStoreState.security.currentRole;
  set _currentRole(String value) =>
      _appStoreState.security.currentRole = value;
  String get _deviceId => _appStoreState.security.deviceId;
  set _deviceId(String value) => _appStoreState.security.deviceId = value;
  List<UserRole> get _roles => _appStoreState.security.roles;
  List<AppUser> get _users => _appStoreState.security.users;
  AppUser? get _activeUser => _appStoreState.security.activeUser;
  set _activeUser(AppUser? value) =>
      _appStoreState.security.activeUser = value;
  bool get _rememberLogin => _appStoreState.security.rememberLogin;
  set _rememberLogin(bool value) =>
      _appStoreState.security.rememberLogin = value;
  DateTime? get _sensitiveAuthorizationExpiresAt =>
      _appStoreState.security.sensitiveAuthorizationExpiresAt;
  set _sensitiveAuthorizationExpiresAt(DateTime? value) =>
      _appStoreState.security.sensitiveAuthorizationExpiresAt = value;
  String get _sensitiveAuthorizationUserId =>
      _appStoreState.security.sensitiveAuthorizationUserId;
  set _sensitiveAuthorizationUserId(String value) =>
      _appStoreState.security.sensitiveAuthorizationUserId = value;
  Set<String> get _sensitiveAuthorizationActions =>
      _appStoreState.security.sensitiveAuthorizationActions;
  Map<String, List<DateTime>> get _failedLoginAttempts =>
      _appStoreState.security.failedLoginAttempts;
  Map<String, DateTime> get _loginBlockedUntil =>
      _appStoreState.security.loginBlockedUntil;
  AppIdentity? get _appIdentity => _appStoreState.security.appIdentity;
  set _appIdentity(AppIdentity? value) =>
      _appStoreState.security.appIdentity = value;

  // Sync state compatibility accessors.
  // ignore: unused_element
  List<SyncChange> get _syncChanges => _appStoreState.sync.syncChanges;
  // ignore: unused_element
  List<SyncQueueItem> get _syncQueue => _appStoreState.sync.syncQueue;
  List<SyncChange> get _sqliteDirtySyncChanges =>
      _appStoreState.sync.sqliteDirtySyncChanges;
  List<SyncQueueItem> get _sqliteDirtySyncQueue =>
      _appStoreState.sync.sqliteDirtySyncQueue;
  Map<String, Map<String, Map<String, dynamic>>> get _sqliteDirtyBusinessRows =>
      _appStoreState.sync.sqliteDirtyBusinessRows;
  int get _syncSequence => _appStoreState.sync.syncSequence;
  set _syncSequence(int value) => _appStoreState.sync.syncSequence = value;

  // Runtime state compatibility accessors.
  int get _storeRevision => _appStoreState.runtime.storeRevision;
  set _storeRevision(int value) =>
      _appStoreState.runtime.storeRevision = value;
  int get _productsRevision => _appStoreState.runtime.productsRevision;
  set _productsRevision(int value) =>
      _appStoreState.runtime.productsRevision = value;
  int get _customersRevision => _appStoreState.runtime.customersRevision;
  set _customersRevision(int value) =>
      _appStoreState.runtime.customersRevision = value;
  int get _salesRevision => _appStoreState.runtime.salesRevision;
  set _salesRevision(int value) =>
      _appStoreState.runtime.salesRevision = value;
  int get _deliveryNotesRevision =>
      _appStoreState.runtime.deliveryNotesRevision;
  set _deliveryNotesRevision(int value) =>
      _appStoreState.runtime.deliveryNotesRevision = value;
  int get _suppliersRevision => _appStoreState.runtime.suppliersRevision;
  set _suppliersRevision(int value) =>
      _appStoreState.runtime.suppliersRevision = value;
  int get _supplierProductPricesRevision =>
      _appStoreState.runtime.supplierProductPricesRevision;
  set _supplierProductPricesRevision(int value) =>
      _appStoreState.runtime.supplierProductPricesRevision = value;
  int get _purchasesRevision => _appStoreState.runtime.purchasesRevision;
  set _purchasesRevision(int value) =>
      _appStoreState.runtime.purchasesRevision = value;
  int get _expensesRevision => _appStoreState.runtime.expensesRevision;
  set _expensesRevision(int value) =>
      _appStoreState.runtime.expensesRevision = value;
  int get _stockMovementsRevision =>
      _appStoreState.runtime.stockMovementsRevision;
  set _stockMovementsRevision(int value) =>
      _appStoreState.runtime.stockMovementsRevision = value;
  int get _inventoryCountsRevision =>
      _appStoreState.runtime.inventoryCountsRevision;
  set _inventoryCountsRevision(int value) =>
      _appStoreState.runtime.inventoryCountsRevision = value;
  int get _warehousesRevision => _appStoreState.runtime.warehousesRevision;
  set _warehousesRevision(int value) =>
      _appStoreState.runtime.warehousesRevision = value;
  int get _accountTransactionsRevision =>
      _appStoreState.runtime.accountTransactionsRevision;
  set _accountTransactionsRevision(int value) =>
      _appStoreState.runtime.accountTransactionsRevision = value;
  int get _storeProfileRevision => _appStoreState.runtime.storeProfileRevision;
  set _storeProfileRevision(int value) =>
      _appStoreState.runtime.storeProfileRevision = value;
  StoreProfile get _storeProfile => _appStoreState.runtime.storeProfile;
  set _storeProfile(StoreProfile value) =>
      _appStoreState.runtime.storeProfile = value;
  bool get _productDerivedDataDirty =>
      _appStoreState.runtime.productDerivedDataDirty;
  set _productDerivedDataDirty(bool value) =>
      _appStoreState.runtime.productDerivedDataDirty = value;
  Timer? get _productDerivedDataFlushTimer =>
      _appStoreState.runtime.productDerivedDataFlushTimer;
  set _productDerivedDataFlushTimer(Timer? value) =>
      _appStoreState.runtime.productDerivedDataFlushTimer = value;
  Future<void>? get _productDerivedDataFlushInFlight =>
      _appStoreState.runtime.productDerivedDataFlushInFlight;
  set _productDerivedDataFlushInFlight(Future<void>? value) =>
      _appStoreState.runtime.productDerivedDataFlushInFlight = value;
  int get _derivedListCacheGeneration =>
      _appStoreState.runtime.derivedListCacheGeneration;
  set _derivedListCacheGeneration(int value) =>
      _appStoreState.runtime.derivedListCacheGeneration = value;
  bool get _isReady => _appStoreState.runtime.isReady;
  set _isReady(bool value) => _appStoreState.runtime.isReady = value;
  // ignore: unused_element
  bool get _heavyDataLoadCompleted =>
      _appStoreState.runtime.heavyDataLoadCompleted;
  set _heavyDataLoadCompleted(bool value) =>
      _appStoreState.runtime.heavyDataLoadCompleted = value;
  bool get _ledgerDataLoadCompleted =>
      _appStoreState.runtime.ledgerDataLoadCompleted;
  set _ledgerDataLoadCompleted(bool value) =>
      _appStoreState.runtime.ledgerDataLoadCompleted = value;
  Future<void>? get _ledgerDataLoadFuture =>
      _appStoreState.runtime.ledgerDataLoadFuture;
  set _ledgerDataLoadFuture(Future<void>? value) =>
      _appStoreState.runtime.ledgerDataLoadFuture = value;
  bool get _syncDataLoadCompleted =>
      _appStoreState.runtime.syncDataLoadCompleted;
  set _syncDataLoadCompleted(bool value) =>
      _appStoreState.runtime.syncDataLoadCompleted = value;
  Future<void>? get _syncDataLoadFuture =>
      _appStoreState.runtime.syncDataLoadFuture;
  set _syncDataLoadFuture(Future<void>? value) =>
      _appStoreState.runtime.syncDataLoadFuture = value;
  Map<String, Future<void>> get _deferredGroupLoadFutures =>
      _appStoreState.runtime.deferredGroupLoadFutures;
  Set<String> get _deferredGroupLoadCompleted =>
      _appStoreState.runtime.deferredGroupLoadCompleted;
  Map<String, Object> get _deferredGroupLoadErrors =>
      _appStoreState.runtime.deferredGroupLoadErrors;
  bool get _shutdownPrepared => _appStoreState.runtime.shutdownPrepared;
  set _shutdownPrepared(bool value) =>
      _appStoreState.runtime.shutdownPrepared = value;
}
