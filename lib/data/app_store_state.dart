part of 'app_store.dart';

/// Mutable runtime state is partitioned by business domain.
///
/// SQLite remains authoritative; these objects only own AppStore's in-memory
/// caches, revisions and short-lived orchestration state. Keeping state outside
/// the facade prevents AppStore from becoming the owner of every concern again.
class _CatalogState {
  final List<Product> _products = [];
  final List<SupplierProductPrice> _supplierProductPrices = [];
  final List<PriceList> _priceLists = [];
  final List<ProductPrice> _productPrices = [];
  final List<ProductPriceOverride> _productPriceOverrides = [];
  final List<ProductCost> _productCosts = [];
  final List<CostingMethodHistory> _costingMethodHistory = [];
  final List<CatalogItem> _categories = [];
  final List<CatalogItem> _brands = [];
  final List<CatalogItem> _units = [];
  final Map<String, int> _productIndexById = <String, int>{};
  final Map<String, String> _productIdByNormalizedCode = <String, String>{};
  final Map<String, String> _productIdByNormalizedBarcode = <String, String>{};
  final Map<String, ProductPrice> _productPriceByLookupKey =
  <String, ProductPrice>{};
  final Map<String, ProductCost> _productCostByProductId =
  <String, ProductCost>{};
  final Map<String, int> _productCostIndexByProductId = <String, int>{};
  List<Product>? _cachedProducts;
  int _cachedProductsGeneration = -1;
  List<Product>? _cachedStockTrackedProducts;
  int _cachedStockTrackedProductsGeneration = -1;
  UnmodifiableListView<SupplierProductPrice>? _cachedSupplierProductPrices;
  UnmodifiableListView<PriceList>? _cachedPriceLists;
  UnmodifiableListView<ProductPrice>? _cachedProductPrices;
  UnmodifiableListView<ProductPriceOverride>? _cachedProductPriceOverrides;
  UnmodifiableListView<ProductCost>? _cachedProductCosts;
  UnmodifiableListView<CostingMethodHistory>? _cachedCostingMethodHistory;
  int _cachedSupplierProductPricesGeneration = -1;
  int _cachedPriceListsGeneration = -1;
  int _cachedProductPricesGeneration = -1;
  int _cachedProductPriceOverridesGeneration = -1;
  int _cachedProductCostsGeneration = -1;
  int _cachedCostingMethodHistoryGeneration = -1;
}

class _CommerceState {
  final List<Customer> _customers = [];
  final List<Sale> _sales = [];
  final List<CreditNote> _creditNotes = [];
  final List<SaleQuotation> _saleQuotations = [];
  final List<DeliveryNote> _deliveryNotes = [];
  final List<Supplier> _suppliers = [];
  final List<Expense> _expenses = [];
  final List<Purchase> _purchases = [];
  final Map<String, int> _purchaseIndexById = <String, int>{};
  final Map<String, int> _expenseIndexById = <String, int>{};
  final Map<String, int> _customerIndexById = <String, int>{};
  final Map<String, String> _customerIdByNormalizedName = <String, String>{};
  final Map<String, int> _supplierIndexById = <String, int>{};
  final Map<String, String> _supplierIdByNormalizedName = <String, String>{};
  final Map<String, List<SupplierPurchasePrice>>
  _purchaseHistoryByProductCache = <String, List<SupplierPurchasePrice>>{};
  final Map<String, _ProductPurchaseMetrics> _purchaseMetricsByProductCache =
  <String, _ProductPurchaseMetrics>{};
  bool _purchaseInsightsCacheDirty = true;
  UnmodifiableListView<Sale>? _cachedSales;
  int _cachedSalesGeneration = -1;
  int _invoiceCounter = 0;
  int _purchaseCounter = 0;
  UnmodifiableListView<SaleQuotation>? _cachedSaleQuotations;
  UnmodifiableListView<DeliveryNote>? _cachedDeliveryNotes;
  Map<String, DeliveryNote>? _cachedDeliveryNoteBySaleId;
  UnmodifiableListView<Supplier>? _cachedSuppliers;
  PurchasesOverview? _cachedPurchasesOverview;
  int _cachedPurchasesOverviewRevision = -1;
  String _cachedPurchasesOverviewMonthKey = '';
  ExpensesOverview? _cachedExpensesOverview;
  int _cachedExpensesOverviewRevision = -1;
  int _cachedSaleQuotationsGeneration = -1;
  int _cachedDeliveryNotesGeneration = -1;
  int _cachedDeliveryNoteBySaleIdGeneration = -1;
  int _cachedSuppliersGeneration = -1;
}

class _InventoryState {
  final List<BillOfMaterials> _billsOfMaterials = [];
  final List<ManufacturingOrder> _manufacturingOrders = [];
  final List<InventoryCostLayer> _inventoryCostLayers = [];
  final List<StockMovement> _stockMovements = [];
  final List<InventoryCountSession> _inventoryCounts = [];
  final List<Warehouse> _warehouses = [];
  final Map<String, int> _stockMovementIndexById = <String, int>{};
  final Map<String, int> _inventoryCostLayerIndexById = <String, int>{};
  final Map<String, Map<String, double>> _warehouseStockByProductCache =
  <String, Map<String, double>>{};
  bool _warehouseStockCacheDirty = true;
  InventoryCostingMethod _inventoryCostingMethod =
  InventoryCostingMethod.batch;
  UnmodifiableListView<BillOfMaterials>? _cachedBillsOfMaterials;
  UnmodifiableListView<ManufacturingOrder>? _cachedManufacturingOrders;
  UnmodifiableListView<InventoryCostLayer>? _cachedInventoryCostLayers;
  int _cachedBillsOfMaterialsGeneration = -1;
  int _cachedManufacturingOrdersGeneration = -1;
  int _cachedInventoryCostLayersGeneration = -1;
}

class _AccountingState {
  final List<AccountTransaction> _accountTransactions = [];
  final Map<String, int> _accountTransactionIndexById = <String, int>{};
  final Map<String, double> _accountBalanceCache = <String, double>{};
  final Map<String, List<AccountTransaction>>
  _accountTransactionsByAccountCache = <String, List<AccountTransaction>>{};
  bool _accountLedgerCacheDirty = true;
  final Map<String, Future<bool>> _pendingPurchaseAccountingTasks =
  <String, Future<bool>>{};
  Future<void> _purchaseAccountingQueue = Future<void>.value();
  DateTime? _phase8AccountingSyncCursor;
  bool _phase8AccountingSyncCaptureInFlight = false;
  bool _phase8AccountingSyncCapturePending = false;
}

class _SecurityState {
  String _currentRole = 'admin';
  String _deviceId = '';
  final List<UserRole> _roles = [];
  final List<AppUser> _users = [];
  AppUser? _activeUser;
  bool _rememberLogin = false;
  DateTime? _sensitiveAuthorizationExpiresAt;
  String _sensitiveAuthorizationUserId = '';
  final Set<String> _sensitiveAuthorizationActions = <String>{};
  final Map<String, List<DateTime>> _failedLoginAttempts =
  <String, List<DateTime>>{};
  final Map<String, DateTime> _loginBlockedUntil = <String, DateTime>{};
  AppIdentity? _appIdentity;
}

class _SyncState {
  final List<SyncChange> _syncChanges = [];
  final List<SyncQueueItem> _syncQueue = [];
  final List<SyncChange> _sqliteDirtySyncChanges = [];
  final List<SyncQueueItem> _sqliteDirtySyncQueue = [];
  final Map<String, Map<String, Map<String, dynamic>>>
  _sqliteDirtyBusinessRows = <String, Map<String, Map<String, dynamic>>>{};
  int _syncSequence = 0;
}

class _RuntimeState {
  int _storeRevision = 0;
  int _productsRevision = 0;
  int _customersRevision = 0;
  int _salesRevision = 0;
  int _deliveryNotesRevision = 0;
  int _suppliersRevision = 0;
  int _supplierProductPricesRevision = 0;
  int _purchasesRevision = 0;
  int _expensesRevision = 0;
  int _stockMovementsRevision = 0;
  int _inventoryCountsRevision = 0;
  int _warehousesRevision = 0;
  int _accountTransactionsRevision = 0;
  int _storeProfileRevision = 0;
  StoreProfile _storeProfile = StoreProfile.defaults;
  bool _productDerivedDataDirty = false;
  Timer? _productDerivedDataFlushTimer;
  Future<void>? _productDerivedDataFlushInFlight;
  int _derivedListCacheGeneration = 0;
  bool _isReady = false;
  bool _heavyDataLoadCompleted = false;
  bool _ledgerDataLoadCompleted = false;
  Future<void>? _ledgerDataLoadFuture;
  bool _syncDataLoadCompleted = false;
  Future<void>? _syncDataLoadFuture;
  final Map<String, Future<void>> _deferredGroupLoadFutures =
  <String, Future<void>>{};
  final Set<String> _deferredGroupLoadCompleted = <String>{};
  final Map<String, Object> _deferredGroupLoadErrors = <String, Object>{};
  bool _shutdownPrepared = false;
}

class _AppStoreState {
  final catalog = _CatalogState();
  final commerce = _CommerceState();
  final inventory = _InventoryState();
  final accounting = _AccountingState();
  final security = _SecurityState();
  final sync = _SyncState();
  final runtime = _RuntimeState();
}

mixin _AppStoreStateAccessors on ChangeNotifier {
  final _appStoreState = _AppStoreState();

  // Catalog state compatibility accessors.
  List<Product> get _products => _appStoreState.catalog._products;
  List<SupplierProductPrice> get _supplierProductPrices => _appStoreState.catalog._supplierProductPrices;
  List<PriceList> get _priceLists => _appStoreState.catalog._priceLists;
  List<ProductPrice> get _productPrices => _appStoreState.catalog._productPrices;
  List<ProductPriceOverride> get _productPriceOverrides => _appStoreState.catalog._productPriceOverrides;
  List<ProductCost> get _productCosts => _appStoreState.catalog._productCosts;
  List<CostingMethodHistory> get _costingMethodHistory => _appStoreState.catalog._costingMethodHistory;
  List<CatalogItem> get _categories => _appStoreState.catalog._categories;
  List<CatalogItem> get _brands => _appStoreState.catalog._brands;
  List<CatalogItem> get _units => _appStoreState.catalog._units;
  Map<String, int> get _productIndexById => _appStoreState.catalog._productIndexById;
  Map<String, String> get _productIdByNormalizedCode => _appStoreState.catalog._productIdByNormalizedCode;
  Map<String, String> get _productIdByNormalizedBarcode => _appStoreState.catalog._productIdByNormalizedBarcode;
  Map<String, ProductPrice> get _productPriceByLookupKey => _appStoreState.catalog._productPriceByLookupKey;
  Map<String, ProductCost> get _productCostByProductId => _appStoreState.catalog._productCostByProductId;
  Map<String, int> get _productCostIndexByProductId => _appStoreState.catalog._productCostIndexByProductId;
  List<Product>? get _cachedProducts => _appStoreState.catalog._cachedProducts;
  set _cachedProducts(List<Product>? value) => _appStoreState.catalog._cachedProducts = value;
  int get _cachedProductsGeneration => _appStoreState.catalog._cachedProductsGeneration;
  set _cachedProductsGeneration(int value) => _appStoreState.catalog._cachedProductsGeneration = value;
  List<Product>? get _cachedStockTrackedProducts => _appStoreState.catalog._cachedStockTrackedProducts;
  set _cachedStockTrackedProducts(List<Product>? value) => _appStoreState.catalog._cachedStockTrackedProducts = value;
  int get _cachedStockTrackedProductsGeneration => _appStoreState.catalog._cachedStockTrackedProductsGeneration;
  set _cachedStockTrackedProductsGeneration(int value) => _appStoreState.catalog._cachedStockTrackedProductsGeneration = value;
  UnmodifiableListView<SupplierProductPrice>? get _cachedSupplierProductPrices => _appStoreState.catalog._cachedSupplierProductPrices;
  set _cachedSupplierProductPrices(UnmodifiableListView<SupplierProductPrice>? value) => _appStoreState.catalog._cachedSupplierProductPrices = value;
  UnmodifiableListView<PriceList>? get _cachedPriceLists => _appStoreState.catalog._cachedPriceLists;
  set _cachedPriceLists(UnmodifiableListView<PriceList>? value) => _appStoreState.catalog._cachedPriceLists = value;
  UnmodifiableListView<ProductPrice>? get _cachedProductPrices => _appStoreState.catalog._cachedProductPrices;
  set _cachedProductPrices(UnmodifiableListView<ProductPrice>? value) => _appStoreState.catalog._cachedProductPrices = value;
  UnmodifiableListView<ProductPriceOverride>? get _cachedProductPriceOverrides => _appStoreState.catalog._cachedProductPriceOverrides;
  set _cachedProductPriceOverrides(UnmodifiableListView<ProductPriceOverride>? value) => _appStoreState.catalog._cachedProductPriceOverrides = value;
  UnmodifiableListView<ProductCost>? get _cachedProductCosts => _appStoreState.catalog._cachedProductCosts;
  set _cachedProductCosts(UnmodifiableListView<ProductCost>? value) => _appStoreState.catalog._cachedProductCosts = value;
  UnmodifiableListView<CostingMethodHistory>? get _cachedCostingMethodHistory => _appStoreState.catalog._cachedCostingMethodHistory;
  set _cachedCostingMethodHistory(UnmodifiableListView<CostingMethodHistory>? value) => _appStoreState.catalog._cachedCostingMethodHistory = value;
  int get _cachedSupplierProductPricesGeneration => _appStoreState.catalog._cachedSupplierProductPricesGeneration;
  set _cachedSupplierProductPricesGeneration(int value) => _appStoreState.catalog._cachedSupplierProductPricesGeneration = value;
  int get _cachedPriceListsGeneration => _appStoreState.catalog._cachedPriceListsGeneration;
  set _cachedPriceListsGeneration(int value) => _appStoreState.catalog._cachedPriceListsGeneration = value;
  int get _cachedProductPricesGeneration => _appStoreState.catalog._cachedProductPricesGeneration;
  set _cachedProductPricesGeneration(int value) => _appStoreState.catalog._cachedProductPricesGeneration = value;
  int get _cachedProductPriceOverridesGeneration => _appStoreState.catalog._cachedProductPriceOverridesGeneration;
  set _cachedProductPriceOverridesGeneration(int value) => _appStoreState.catalog._cachedProductPriceOverridesGeneration = value;
  int get _cachedProductCostsGeneration => _appStoreState.catalog._cachedProductCostsGeneration;
  set _cachedProductCostsGeneration(int value) => _appStoreState.catalog._cachedProductCostsGeneration = value;
  int get _cachedCostingMethodHistoryGeneration => _appStoreState.catalog._cachedCostingMethodHistoryGeneration;
  set _cachedCostingMethodHistoryGeneration(int value) => _appStoreState.catalog._cachedCostingMethodHistoryGeneration = value;

  // Commerce state compatibility accessors.
  List<Customer> get _customers => _appStoreState.commerce._customers;
  List<Sale> get _sales => _appStoreState.commerce._sales;
  List<CreditNote> get _creditNotes => _appStoreState.commerce._creditNotes;
  List<SaleQuotation> get _saleQuotations => _appStoreState.commerce._saleQuotations;
  List<DeliveryNote> get _deliveryNotes => _appStoreState.commerce._deliveryNotes;
  List<Supplier> get _suppliers => _appStoreState.commerce._suppliers;
  List<Expense> get _expenses => _appStoreState.commerce._expenses;
  List<Purchase> get _purchases => _appStoreState.commerce._purchases;
  Map<String, int> get _purchaseIndexById => _appStoreState.commerce._purchaseIndexById;
  Map<String, int> get _expenseIndexById => _appStoreState.commerce._expenseIndexById;
  Map<String, int> get _customerIndexById => _appStoreState.commerce._customerIndexById;
  Map<String, String> get _customerIdByNormalizedName => _appStoreState.commerce._customerIdByNormalizedName;
  Map<String, int> get _supplierIndexById => _appStoreState.commerce._supplierIndexById;
  Map<String, String> get _supplierIdByNormalizedName => _appStoreState.commerce._supplierIdByNormalizedName;
  Map<String, List<SupplierPurchasePrice>> get _purchaseHistoryByProductCache => _appStoreState.commerce._purchaseHistoryByProductCache;
  Map<String, _ProductPurchaseMetrics> get _purchaseMetricsByProductCache => _appStoreState.commerce._purchaseMetricsByProductCache;
  bool get _purchaseInsightsCacheDirty => _appStoreState.commerce._purchaseInsightsCacheDirty;
  set _purchaseInsightsCacheDirty(bool value) => _appStoreState.commerce._purchaseInsightsCacheDirty = value;
  UnmodifiableListView<Sale>? get _cachedSales => _appStoreState.commerce._cachedSales;
  set _cachedSales(UnmodifiableListView<Sale>? value) => _appStoreState.commerce._cachedSales = value;
  int get _cachedSalesGeneration => _appStoreState.commerce._cachedSalesGeneration;
  set _cachedSalesGeneration(int value) => _appStoreState.commerce._cachedSalesGeneration = value;
  int get _invoiceCounter => _appStoreState.commerce._invoiceCounter;
  set _invoiceCounter(int value) => _appStoreState.commerce._invoiceCounter = value;
  int get _purchaseCounter => _appStoreState.commerce._purchaseCounter;
  set _purchaseCounter(int value) => _appStoreState.commerce._purchaseCounter = value;
  UnmodifiableListView<SaleQuotation>? get _cachedSaleQuotations => _appStoreState.commerce._cachedSaleQuotations;
  set _cachedSaleQuotations(UnmodifiableListView<SaleQuotation>? value) => _appStoreState.commerce._cachedSaleQuotations = value;
  UnmodifiableListView<DeliveryNote>? get _cachedDeliveryNotes => _appStoreState.commerce._cachedDeliveryNotes;
  set _cachedDeliveryNotes(UnmodifiableListView<DeliveryNote>? value) => _appStoreState.commerce._cachedDeliveryNotes = value;
  Map<String, DeliveryNote>? get _cachedDeliveryNoteBySaleId => _appStoreState.commerce._cachedDeliveryNoteBySaleId;
  set _cachedDeliveryNoteBySaleId(Map<String, DeliveryNote>? value) => _appStoreState.commerce._cachedDeliveryNoteBySaleId = value;
  UnmodifiableListView<Supplier>? get _cachedSuppliers => _appStoreState.commerce._cachedSuppliers;
  set _cachedSuppliers(UnmodifiableListView<Supplier>? value) => _appStoreState.commerce._cachedSuppliers = value;
  PurchasesOverview? get _cachedPurchasesOverview => _appStoreState.commerce._cachedPurchasesOverview;
  set _cachedPurchasesOverview(PurchasesOverview? value) => _appStoreState.commerce._cachedPurchasesOverview = value;
  int get _cachedPurchasesOverviewRevision => _appStoreState.commerce._cachedPurchasesOverviewRevision;
  set _cachedPurchasesOverviewRevision(int value) => _appStoreState.commerce._cachedPurchasesOverviewRevision = value;
  String get _cachedPurchasesOverviewMonthKey => _appStoreState.commerce._cachedPurchasesOverviewMonthKey;
  set _cachedPurchasesOverviewMonthKey(String value) => _appStoreState.commerce._cachedPurchasesOverviewMonthKey = value;
  ExpensesOverview? get _cachedExpensesOverview => _appStoreState.commerce._cachedExpensesOverview;
  set _cachedExpensesOverview(ExpensesOverview? value) => _appStoreState.commerce._cachedExpensesOverview = value;
  int get _cachedExpensesOverviewRevision => _appStoreState.commerce._cachedExpensesOverviewRevision;
  set _cachedExpensesOverviewRevision(int value) => _appStoreState.commerce._cachedExpensesOverviewRevision = value;
  int get _cachedSaleQuotationsGeneration => _appStoreState.commerce._cachedSaleQuotationsGeneration;
  set _cachedSaleQuotationsGeneration(int value) => _appStoreState.commerce._cachedSaleQuotationsGeneration = value;
  int get _cachedDeliveryNotesGeneration => _appStoreState.commerce._cachedDeliveryNotesGeneration;
  set _cachedDeliveryNotesGeneration(int value) => _appStoreState.commerce._cachedDeliveryNotesGeneration = value;
  int get _cachedDeliveryNoteBySaleIdGeneration => _appStoreState.commerce._cachedDeliveryNoteBySaleIdGeneration;
  set _cachedDeliveryNoteBySaleIdGeneration(int value) => _appStoreState.commerce._cachedDeliveryNoteBySaleIdGeneration = value;
  int get _cachedSuppliersGeneration => _appStoreState.commerce._cachedSuppliersGeneration;
  set _cachedSuppliersGeneration(int value) => _appStoreState.commerce._cachedSuppliersGeneration = value;

  // Inventory state compatibility accessors.
  List<BillOfMaterials> get _billsOfMaterials => _appStoreState.inventory._billsOfMaterials;
  List<ManufacturingOrder> get _manufacturingOrders => _appStoreState.inventory._manufacturingOrders;
  List<InventoryCostLayer> get _inventoryCostLayers => _appStoreState.inventory._inventoryCostLayers;
  List<StockMovement> get _stockMovements => _appStoreState.inventory._stockMovements;
  List<InventoryCountSession> get _inventoryCounts => _appStoreState.inventory._inventoryCounts;
  List<Warehouse> get _warehouses => _appStoreState.inventory._warehouses;
  Map<String, int> get _stockMovementIndexById => _appStoreState.inventory._stockMovementIndexById;
  Map<String, int> get _inventoryCostLayerIndexById => _appStoreState.inventory._inventoryCostLayerIndexById;
  Map<String, Map<String, double>> get _warehouseStockByProductCache => _appStoreState.inventory._warehouseStockByProductCache;
  bool get _warehouseStockCacheDirty => _appStoreState.inventory._warehouseStockCacheDirty;
  set _warehouseStockCacheDirty(bool value) => _appStoreState.inventory._warehouseStockCacheDirty = value;
  InventoryCostingMethod get _inventoryCostingMethod => _appStoreState.inventory._inventoryCostingMethod;
  set _inventoryCostingMethod(InventoryCostingMethod value) => _appStoreState.inventory._inventoryCostingMethod = value;
  UnmodifiableListView<BillOfMaterials>? get _cachedBillsOfMaterials => _appStoreState.inventory._cachedBillsOfMaterials;
  set _cachedBillsOfMaterials(UnmodifiableListView<BillOfMaterials>? value) => _appStoreState.inventory._cachedBillsOfMaterials = value;
  UnmodifiableListView<ManufacturingOrder>? get _cachedManufacturingOrders => _appStoreState.inventory._cachedManufacturingOrders;
  set _cachedManufacturingOrders(UnmodifiableListView<ManufacturingOrder>? value) => _appStoreState.inventory._cachedManufacturingOrders = value;
  UnmodifiableListView<InventoryCostLayer>? get _cachedInventoryCostLayers => _appStoreState.inventory._cachedInventoryCostLayers;
  set _cachedInventoryCostLayers(UnmodifiableListView<InventoryCostLayer>? value) => _appStoreState.inventory._cachedInventoryCostLayers = value;
  int get _cachedBillsOfMaterialsGeneration => _appStoreState.inventory._cachedBillsOfMaterialsGeneration;
  set _cachedBillsOfMaterialsGeneration(int value) => _appStoreState.inventory._cachedBillsOfMaterialsGeneration = value;
  int get _cachedManufacturingOrdersGeneration => _appStoreState.inventory._cachedManufacturingOrdersGeneration;
  set _cachedManufacturingOrdersGeneration(int value) => _appStoreState.inventory._cachedManufacturingOrdersGeneration = value;
  int get _cachedInventoryCostLayersGeneration => _appStoreState.inventory._cachedInventoryCostLayersGeneration;
  set _cachedInventoryCostLayersGeneration(int value) => _appStoreState.inventory._cachedInventoryCostLayersGeneration = value;

  // Accounting state compatibility accessors.
  List<AccountTransaction> get _accountTransactions => _appStoreState.accounting._accountTransactions;
  Map<String, int> get _accountTransactionIndexById => _appStoreState.accounting._accountTransactionIndexById;
  Map<String, double> get _accountBalanceCache => _appStoreState.accounting._accountBalanceCache;
  Map<String, List<AccountTransaction>> get _accountTransactionsByAccountCache => _appStoreState.accounting._accountTransactionsByAccountCache;
  bool get _accountLedgerCacheDirty => _appStoreState.accounting._accountLedgerCacheDirty;
  set _accountLedgerCacheDirty(bool value) => _appStoreState.accounting._accountLedgerCacheDirty = value;
  Map<String, Future<bool>> get _pendingPurchaseAccountingTasks => _appStoreState.accounting._pendingPurchaseAccountingTasks;
  Future<void> get _purchaseAccountingQueue => _appStoreState.accounting._purchaseAccountingQueue;
  set _purchaseAccountingQueue(Future<void> value) => _appStoreState.accounting._purchaseAccountingQueue = value;
  DateTime? get _phase8AccountingSyncCursor => _appStoreState.accounting._phase8AccountingSyncCursor;
  set _phase8AccountingSyncCursor(DateTime? value) => _appStoreState.accounting._phase8AccountingSyncCursor = value;
  bool get _phase8AccountingSyncCaptureInFlight => _appStoreState.accounting._phase8AccountingSyncCaptureInFlight;
  set _phase8AccountingSyncCaptureInFlight(bool value) => _appStoreState.accounting._phase8AccountingSyncCaptureInFlight = value;
  bool get _phase8AccountingSyncCapturePending => _appStoreState.accounting._phase8AccountingSyncCapturePending;
  set _phase8AccountingSyncCapturePending(bool value) => _appStoreState.accounting._phase8AccountingSyncCapturePending = value;

  // Security state compatibility accessors.
  String get _currentRole => _appStoreState.security._currentRole;
  set _currentRole(String value) => _appStoreState.security._currentRole = value;
  String get _deviceId => _appStoreState.security._deviceId;
  set _deviceId(String value) => _appStoreState.security._deviceId = value;
  List<UserRole> get _roles => _appStoreState.security._roles;
  List<AppUser> get _users => _appStoreState.security._users;
  AppUser? get _activeUser => _appStoreState.security._activeUser;
  set _activeUser(AppUser? value) => _appStoreState.security._activeUser = value;
  bool get _rememberLogin => _appStoreState.security._rememberLogin;
  set _rememberLogin(bool value) => _appStoreState.security._rememberLogin = value;
  DateTime? get _sensitiveAuthorizationExpiresAt => _appStoreState.security._sensitiveAuthorizationExpiresAt;
  set _sensitiveAuthorizationExpiresAt(DateTime? value) => _appStoreState.security._sensitiveAuthorizationExpiresAt = value;
  String get _sensitiveAuthorizationUserId => _appStoreState.security._sensitiveAuthorizationUserId;
  set _sensitiveAuthorizationUserId(String value) => _appStoreState.security._sensitiveAuthorizationUserId = value;
  Set<String> get _sensitiveAuthorizationActions => _appStoreState.security._sensitiveAuthorizationActions;
  Map<String, List<DateTime>> get _failedLoginAttempts => _appStoreState.security._failedLoginAttempts;
  Map<String, DateTime> get _loginBlockedUntil => _appStoreState.security._loginBlockedUntil;
  AppIdentity? get _appIdentity => _appStoreState.security._appIdentity;
  set _appIdentity(AppIdentity? value) => _appStoreState.security._appIdentity = value;

  // Sync state compatibility accessors.
  List<SyncChange> get _syncChanges => _appStoreState.sync._syncChanges;
  List<SyncQueueItem> get _syncQueue => _appStoreState.sync._syncQueue;
  List<SyncChange> get _sqliteDirtySyncChanges => _appStoreState.sync._sqliteDirtySyncChanges;
  List<SyncQueueItem> get _sqliteDirtySyncQueue => _appStoreState.sync._sqliteDirtySyncQueue;
  Map<String, Map<String, Map<String, dynamic>>> get _sqliteDirtyBusinessRows => _appStoreState.sync._sqliteDirtyBusinessRows;
  int get _syncSequence => _appStoreState.sync._syncSequence;
  set _syncSequence(int value) => _appStoreState.sync._syncSequence = value;

  // Runtime state compatibility accessors.
  int get _storeRevision => _appStoreState.runtime._storeRevision;
  set _storeRevision(int value) => _appStoreState.runtime._storeRevision = value;
  int get _productsRevision => _appStoreState.runtime._productsRevision;
  set _productsRevision(int value) => _appStoreState.runtime._productsRevision = value;
  int get _customersRevision => _appStoreState.runtime._customersRevision;
  set _customersRevision(int value) => _appStoreState.runtime._customersRevision = value;
  int get _salesRevision => _appStoreState.runtime._salesRevision;
  set _salesRevision(int value) => _appStoreState.runtime._salesRevision = value;
  int get _deliveryNotesRevision => _appStoreState.runtime._deliveryNotesRevision;
  set _deliveryNotesRevision(int value) => _appStoreState.runtime._deliveryNotesRevision = value;
  int get _suppliersRevision => _appStoreState.runtime._suppliersRevision;
  set _suppliersRevision(int value) => _appStoreState.runtime._suppliersRevision = value;
  int get _supplierProductPricesRevision => _appStoreState.runtime._supplierProductPricesRevision;
  set _supplierProductPricesRevision(int value) => _appStoreState.runtime._supplierProductPricesRevision = value;
  int get _purchasesRevision => _appStoreState.runtime._purchasesRevision;
  set _purchasesRevision(int value) => _appStoreState.runtime._purchasesRevision = value;
  int get _expensesRevision => _appStoreState.runtime._expensesRevision;
  set _expensesRevision(int value) => _appStoreState.runtime._expensesRevision = value;
  int get _stockMovementsRevision => _appStoreState.runtime._stockMovementsRevision;
  set _stockMovementsRevision(int value) => _appStoreState.runtime._stockMovementsRevision = value;
  int get _inventoryCountsRevision => _appStoreState.runtime._inventoryCountsRevision;
  set _inventoryCountsRevision(int value) => _appStoreState.runtime._inventoryCountsRevision = value;
  int get _warehousesRevision => _appStoreState.runtime._warehousesRevision;
  set _warehousesRevision(int value) => _appStoreState.runtime._warehousesRevision = value;
  int get _accountTransactionsRevision => _appStoreState.runtime._accountTransactionsRevision;
  set _accountTransactionsRevision(int value) => _appStoreState.runtime._accountTransactionsRevision = value;
  int get _storeProfileRevision => _appStoreState.runtime._storeProfileRevision;
  set _storeProfileRevision(int value) => _appStoreState.runtime._storeProfileRevision = value;
  StoreProfile get _storeProfile => _appStoreState.runtime._storeProfile;
  set _storeProfile(StoreProfile value) => _appStoreState.runtime._storeProfile = value;
  bool get _productDerivedDataDirty => _appStoreState.runtime._productDerivedDataDirty;
  set _productDerivedDataDirty(bool value) => _appStoreState.runtime._productDerivedDataDirty = value;
  Timer? get _productDerivedDataFlushTimer => _appStoreState.runtime._productDerivedDataFlushTimer;
  set _productDerivedDataFlushTimer(Timer? value) => _appStoreState.runtime._productDerivedDataFlushTimer = value;
  Future<void>? get _productDerivedDataFlushInFlight => _appStoreState.runtime._productDerivedDataFlushInFlight;
  set _productDerivedDataFlushInFlight(Future<void>? value) => _appStoreState.runtime._productDerivedDataFlushInFlight = value;
  int get _derivedListCacheGeneration => _appStoreState.runtime._derivedListCacheGeneration;
  set _derivedListCacheGeneration(int value) => _appStoreState.runtime._derivedListCacheGeneration = value;
  bool get _isReady => _appStoreState.runtime._isReady;
  set _isReady(bool value) => _appStoreState.runtime._isReady = value;
  bool get _heavyDataLoadCompleted => _appStoreState.runtime._heavyDataLoadCompleted;
  set _heavyDataLoadCompleted(bool value) => _appStoreState.runtime._heavyDataLoadCompleted = value;
  bool get _ledgerDataLoadCompleted => _appStoreState.runtime._ledgerDataLoadCompleted;
  set _ledgerDataLoadCompleted(bool value) => _appStoreState.runtime._ledgerDataLoadCompleted = value;
  Future<void>? get _ledgerDataLoadFuture => _appStoreState.runtime._ledgerDataLoadFuture;
  set _ledgerDataLoadFuture(Future<void>? value) => _appStoreState.runtime._ledgerDataLoadFuture = value;
  bool get _syncDataLoadCompleted => _appStoreState.runtime._syncDataLoadCompleted;
  set _syncDataLoadCompleted(bool value) => _appStoreState.runtime._syncDataLoadCompleted = value;
  Future<void>? get _syncDataLoadFuture => _appStoreState.runtime._syncDataLoadFuture;
  set _syncDataLoadFuture(Future<void>? value) => _appStoreState.runtime._syncDataLoadFuture = value;
  Map<String, Future<void>> get _deferredGroupLoadFutures => _appStoreState.runtime._deferredGroupLoadFutures;
  Set<String> get _deferredGroupLoadCompleted => _appStoreState.runtime._deferredGroupLoadCompleted;
  Map<String, Object> get _deferredGroupLoadErrors => _appStoreState.runtime._deferredGroupLoadErrors;
  bool get _shutdownPrepared => _appStoreState.runtime._shutdownPrepared;
  set _shutdownPrepared(bool value) => _appStoreState.runtime._shutdownPrepared = value;

}
