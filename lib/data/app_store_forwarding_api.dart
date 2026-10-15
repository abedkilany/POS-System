part of 'app_store.dart';

/// Transitional instance API kept for source compatibility while callers
/// migrate to typed domain ports (`store.catalog`, `store.commerce`, etc.).
///
/// The business implementation continues to live in focused split modules;
/// this mixin deliberately contains forwarding only and owns no mutable state.
mixin _AppStoreForwardingApi on ChangeNotifier, _AppStoreStateAccessors {
  Future<T> _traceAsync<T>(
    String section,
    String phase,
    Future<T> Function() action, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) =>
      _AppStoreSplitCoreLoading(this as AppStore)
          ._traceAsync(section, phase, action, metadata: metadata);

  void _traceSync(
    String section,
    String phase,
    void Function() action, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) =>
      _AppStoreSplitCoreLoading(this as AppStore)
          ._traceSync(section, phase, action, metadata: metadata);

  T _traceSyncResult<T>(
    String section,
    String phase,
    T Function() action, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) =>
      _AppStoreSplitCoreLoading(this as AppStore)
          ._traceSyncResult(section, phase, action, metadata: metadata);

  Future<void> warmDeferredPageCaches() =>
      _AppStoreSplitCoreLoading(this as AppStore).warmDeferredPageCaches();

  Future<void> _requestSyncDataLoad() =>
      _AppStoreSplitCoreLoading(this as AppStore)._requestSyncDataLoad();

  Future<void> _loadDeferredGroup<T>({
    required String key,
    required Future<List<T>> Function() loader,
    required List<T> target,
    void Function()? afterLoad,
  }) =>
      _AppStoreSplitCoreLoading(this as AppStore)._loadDeferredGroup(
          key: key, loader: loader, target: target, afterLoad: afterLoad);

  Future<void> ensureProductPricingLoaded() =>
      _AppStoreSplitCoreLoading(this as AppStore).ensureProductPricingLoaded();

  Future<void> ensureProductCostingDataLoaded() =>
      _AppStoreSplitCoreLoading(this as AppStore)
          .ensureProductCostingDataLoaded();

  Future<void> ensureSalesPageDataLoaded() =>
      _AppStoreSplitCoreLoading(this as AppStore).ensureSalesPageDataLoaded();

  Future<void> ensurePurchasesPageDataLoaded() =>
      _AppStoreSplitCoreLoading(this as AppStore)
          .ensurePurchasesPageDataLoaded();

  Future<void> ensureAccountingPageDataLoaded() =>
      _AppStoreSplitCoreLoading(this as AppStore)
          .ensureAccountingPageDataLoaded();

  Future<void> ensureQuotationsPageDataLoaded() =>
      _AppStoreSplitCoreLoading(this as AppStore)
          .ensureQuotationsPageDataLoaded();

  Future<void> ensureDeliveryNotesPageDataLoaded() =>
      _AppStoreSplitCoreLoading(this as AppStore)
          .ensureDeliveryNotesPageDataLoaded();

  Future<void> ensureInventoryPageDataLoaded() =>
      _AppStoreSplitCoreLoading(this as AppStore)
          .ensureInventoryPageDataLoaded();

  Future<void> ensureHeavyDataLoaded({bool failOnError = false}) =>
      _AppStoreSplitCoreLoading(this as AppStore)
          .ensureHeavyDataLoaded(failOnError: failOnError);

  List<Sale> get sales => _AppStoreSplitCoreLoading(this as AppStore).sales;

  Future<void> ensureCreditNotesLoaded() =>
      _AppStoreSplitCoreLoading(this as AppStore).ensureCreditNotesLoaded();

  Future<CreditNote> issueCreditNote({
    required Sale originalSale,
    required List<SaleItem> items,
    required double amount,
    String refundMethod = 'Customer balance',
    String note = '',
  }) =>
      _AppStoreSplitCoreLoading(this as AppStore).issueCreditNote(
          originalSale: originalSale,
          items: items,
          amount: amount,
          refundMethod: refundMethod,
          note: note);

  Future<CreditNote> cancelSaleReturn({
    required String creditNoteId,
    required int expectedVersion,
  }) =>
      _AppStoreSplitSalesReturnsPart7(this as AppStore).cancelSaleReturn(
        creditNoteId: creditNoteId,
        expectedVersion: expectedVersion,
      );

  List<SaleQuotation> get saleQuotations =>
      _AppStoreSplitCoreLoading(this as AppStore).saleQuotations;

  List<DeliveryNote> get deliveryNotes =>
      _AppStoreSplitCoreLoading(this as AppStore).deliveryNotes;

  List<BillOfMaterials> get billsOfMaterials =>
      _AppStoreSplitCoreLoading(this as AppStore).billsOfMaterials;

  List<ManufacturingOrder> get manufacturingOrders =>
      _AppStoreSplitCoreLoading(this as AppStore).manufacturingOrders;

  ProductCost productCostFor(String productId) =>
      _AppStoreSplitCoreLoading(this as AppStore).productCostFor(productId);

  Future<Map<String, ProductCostSnapshot>> productCostSnapshotsForProducts(
    Iterable<Product> products, {
    String warehouseId = '',
  }) =>
      _AppStoreSplitPricingCostingPart2(this as AppStore)
          .productCostSnapshotsForProducts(products, warehouseId: warehouseId);

  Future<ProductCostSnapshot> productCostSnapshotForProduct(
    Product product, {
    String warehouseId = '',
  }) =>
      _AppStoreSplitPricingCostingPart2(this as AppStore)
          .productCostSnapshotForProduct(product, warehouseId: warehouseId);

  Future<double> estimatedUnifiedBatchUnitCostForProduct(
    Product product, {
    String warehouseId = '',
    double requiredQuantity = 0,
  }) =>
      _AppStoreSplitManufacturing(this as AppStore)
          .estimatedUnifiedBatchUnitCostForProduct(
        product,
        warehouseId: warehouseId,
        requiredQuantity: requiredQuantity,
      );

  PriceList get defaultPriceList =>
      _AppStoreSplitCoreLoading(this as AppStore).defaultPriceList;

  ProductPrice? defaultProductPriceFor(String productId,
          {String unitId = 'base'}) =>
      _AppStoreSplitCoreLoading(this as AppStore)
          .defaultProductPriceFor(productId, unitId: unitId);

  ProductPrice? productPriceFor(String productId, String priceListId,
          {String unitId = 'base'}) =>
      _AppStoreSplitCoreLoading(this as AppStore)
          .productPriceFor(productId, priceListId, unitId: unitId);

  ProductPriceOverride? productPriceOverrideFor(
          ProductPrice price, String currencyCode) =>
      _AppStoreSplitCoreLoading(this as AppStore)
          .productPriceOverrideFor(price, currencyCode);

  double productPriceAmountForCurrency(Product product, String currencyCode,
          {String unitId = 'base'}) =>
      _AppStoreSplitCoreLoading(this as AppStore)
          .productPriceAmountForCurrency(product, currencyCode, unitId: unitId);

  double defaultProductUsdPrice(Product product, {String unitId = 'base'}) =>
      _AppStoreSplitCoreLoading(this as AppStore)
          .defaultProductUsdPrice(product, unitId: unitId);

  List<DataConflict> get dataConflicts =>
      _AppStoreSplitCoreLoading(this as AppStore).dataConflicts;

  Future<List<DataConflict>> ensureDataConflictsLoaded() =>
      _AppStoreSplitCoreLoading(this as AppStore).ensureDataConflictsLoaded();

  List<Expense> get expenses =>
      _AppStoreSplitCoreLoading(this as AppStore).expenses;

  List<Purchase> get purchases =>
      _AppStoreSplitCoreLoading(this as AppStore).purchases;

  List<StockMovement> get stockMovements =>
      _AppStoreSplitCoreLoading(this as AppStore).stockMovements;
  List<InventoryCountSession> get inventoryCountSessions =>
      _AppStoreSplitCoreLoading(this as AppStore).inventoryCountSessions;

  InventoryCountSession? get activeInventoryCountSession =>
      _AppStoreSplitCoreLoading(this as AppStore).activeInventoryCountSession;

  List<Warehouse> get warehouses =>
      _AppStoreSplitCoreLoading(this as AppStore).warehouses;

  Warehouse get defaultWarehouse =>
      _AppStoreSplitCoreLoading(this as AppStore).defaultWarehouse;

  Warehouse resolveWarehouseForSale({String warehouseId = ''}) =>
      _AppStoreSplitCoreLoading(this as AppStore)
          .resolveWarehouseForSale(warehouseId: warehouseId);

  String get saleWarehouseId =>
      _AppStoreSplitCoreLoading(this as AppStore).saleWarehouseId;

  Future<void> setSaleWarehouseId(String warehouseId) =>
      _AppStoreSplitCoreLoading(this as AppStore)
          .setSaleWarehouseId(warehouseId);

  Warehouse resolveWarehouseForPurchase({String warehouseId = ''}) =>
      _AppStoreSplitCoreLoading(this as AppStore)
          .resolveWarehouseForPurchase(warehouseId: warehouseId);

  void _ensureDefaultWarehouse() =>
      _AppStoreSplitCoreLoading(this as AppStore)._ensureDefaultWarehouse();

  void _invalidateDerivedDataCaches() =>
      _AppStoreSplitCoreLoading(this as AppStore)
          ._invalidateDerivedDataCaches();

  void _ensureDeliveryNoteLookupCache() =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore)
          ._ensureDeliveryNoteLookupCache();

  void _rebuildInventoryCostLayerLookupCache() =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore)
          ._rebuildInventoryCostLayerLookupCache();

  double stockForWarehouse(String productId, String warehouseId) =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore)
          .stockForWarehouse(productId, warehouseId);

  Future<double> warehouseStockFromSqlite(
    String productId, {
    String warehouseId = '',
  }) =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore)
          .warehouseStockFromSqlite(productId, warehouseId: warehouseId);

  Future<Map<String, Map<String, double>>> warehouseStockBalancesFromSqlite() =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore)
          .warehouseStockBalancesFromSqlite();

  Future<double> totalWarehouseStockFromSqlite(String productId) =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore)
          .totalWarehouseStockFromSqlite(productId);

  Map<String, double> warehouseStockForProduct(String productId) =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore)
          .warehouseStockForProduct(productId);

  List<AccountTransaction> get accountTransactions =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore).accountTransactions;

  void _invalidateAccountLedgerCache() =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore)
          ._invalidateAccountLedgerCache();

  void _replaceAccountTransactionInLedgerCache({
    AccountTransaction? previous,
    required AccountTransaction current,
  }) =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore)
          ._replaceAccountTransactionInLedgerCache(
              previous: previous, current: current);

  List<AccountTransaction> accountTransactionsForAccount(
    String accountType,
    String accountId,
  ) =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore)
          .accountTransactionsForAccount(accountType, accountId);

  double accountBalance(String accountType, String accountId) =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore)
          .accountBalance(accountType, accountId);

  List<Map<String, dynamic>> databaseRows(String entity) =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore).databaseRows(entity);

  Future<void> saveDatabaseRow(String entity, Map<String, dynamic> json) =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore).saveDatabaseRow(entity, json);

  Future<void> deleteDatabaseRow(String entity, String id) =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore).deleteDatabaseRow(entity, id);

  List<SyncChange> get syncChanges =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore).syncChanges;
  List<SyncQueueItem> get syncQueue =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore).syncQueue;

  List<SyncQueueItem> get pendingSyncQueue =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore).pendingSyncQueue;

  List<SyncChange> get pendingSyncChanges =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore).pendingSyncChanges;

  List<SyncQueueItem> pendingSyncQueueForTarget(
    String target, {
    bool readyOnly = true,
  }) =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore)
          .pendingSyncQueueForTarget(target, readyOnly: readyOnly);

  List<SyncChange> pendingSyncChangesForTarget(
    String target, {
    bool readyOnly = true,
  }) =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore)
          .pendingSyncChangesForTarget(target, readyOnly: readyOnly);

  List<SyncChange> submittedSyncChangesForTarget(String target) =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore)
          .submittedSyncChangesForTarget(target);

  int outstandingSyncQueueCountForTarget(String target) =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore)
          .outstandingSyncQueueCountForTarget(target);

  String get activeClientSyncTarget =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore).activeClientSyncTarget;

  int get activeClientPendingSyncCount =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore).activeClientPendingSyncCount;

  DateTime? get latestResetSyncAt =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore).latestResetSyncAt;
  bool canAccessPage(String pageId) =>
      _AppStoreSplitAccessAuth(this as AppStore).canAccessPage(pageId);
  bool get hasLocalStoreData =>
      _AppStoreSplitAccessAuth(this as AppStore).hasLocalStoreData;

  Future<void> markSuspendedByHost({String reason = ''}) =>
      _AppStoreSplitAccessAuth(this as AppStore)
          .markSuspendedByHost(reason: reason);

  Future<void> clearSuspendedByHost() =>
      _AppStoreSplitAccessAuth(this as AppStore).clearSuspendedByHost();

  Future<ThemeMode> loadThemeMode() =>
      _AppStoreSplitAccessAuth(this as AppStore).loadThemeMode();

  Future<void> saveThemeMode(ThemeMode mode) =>
      _AppStoreSplitAccessAuth(this as AppStore).saveThemeMode(mode);

  Future<Locale> loadLocale() =>
      _AppStoreSplitAccessAuth(this as AppStore).loadLocale();

  Future<void> saveLocale(Locale locale) =>
      _AppStoreSplitAccessAuth(this as AppStore).saveLocale(locale);

  bool get _hasOnlyLegacyDefaultAdminUser =>
      _AppStoreSplitAccessAuth(this as AppStore)._hasOnlyLegacyDefaultAdminUser;

  Future<void> completeInitialAdminSetup({
    required String fullName,
    required String username,
    required String password,
  }) =>
      _AppStoreSplitAccessAuth(this as AppStore).completeInitialAdminSetup(
          fullName: fullName, username: username, password: password);

  Future<void> recoverOnlineStoreOwnerIdentity({
    required String storeId,
    required String branchId,
    required String storeName,
    required String username,
    required String password,
    String? hostDeviceId,
    String? deviceToken,
    String? controlPlaneTenantId,
    DeviceRole? deviceRole,
    SyncMode? syncMode,
    bool activateUser = true,
  }) =>
      _AppStoreSplitAccessAuth(this as AppStore)
          .recoverOnlineStoreOwnerIdentity(
              storeId: storeId,
              branchId: branchId,
              storeName: storeName,
              username: username,
              password: password,
              hostDeviceId: hostDeviceId,
              deviceToken: deviceToken,
              controlPlaneTenantId: controlPlaneTenantId,
              deviceRole: deviceRole,
              syncMode: syncMode,
              activateUser: activateUser);

  UserRole? roleById(String id) =>
      _AppStoreSplitAccessAuth(this as AppStore).roleById(id);

  Future<bool> authorizeSensitiveAction({
    required String action,
    required String password,
    Duration validity = const Duration(minutes: 3),
  }) =>
      _AppStoreSplitAccessAuth(this as AppStore).authorizeSensitiveAction(
        action: action,
        password: password,
        validity: validity,
      );

  void clearSensitiveActionAuthorization() =>
      _AppStoreSplitAccessAuth(this as AppStore)
          .clearSensitiveActionAuthorization();

  void requireSensitiveActionAuthorization(String action) =>
      _AppStoreSplitAccessAuth(this as AppStore)
          .requireSensitiveActionAuthorization(action);
  bool hasPermission(String permission) =>
      _AppStoreSplitAccessAuth(this as AppStore).hasPermission(permission);
  void requirePermission(String permission) =>
      _AppStoreSplitAccessAuth(this as AppStore).requirePermission(permission);

  void requireAnyPermission(Iterable<String> permissions) =>
      _AppStoreSplitAccessAuth(this as AppStore)
          .requireAnyPermission(permissions);

  void requireAllPermissions(Iterable<String> permissions) =>
      _AppStoreSplitAccessAuth(this as AppStore)
          .requireAllPermissions(permissions);

  double get totalSalesAmount =>
      _AppStoreSplitAccessAuth(this as AppStore).totalSalesAmount;

  ExpensesOverview get expensesOverview =>
      _AppStoreSplitSupplierInsights(this as AppStore).expensesOverview;

  void _seedSupplierProductPricesFromPurchaseHistory() =>
      _AppStoreSplitSupplierInsights(this as AppStore)
          ._seedSupplierProductPricesFromPurchaseHistory();

  int _seedSupplierProductPricesFromLegacyProductSuppliers({
    bool recordSyncChanges = false,
  }) =>
      _AppStoreSplitSupplierInsights(this as AppStore)
          ._seedSupplierProductPricesFromLegacyProductSuppliers(
              recordSyncChanges: recordSyncChanges);

  void _markSingleSupplierPerProductAsPreferred() =>
      _AppStoreSplitSupplierInsights(this as AppStore)
          ._markSingleSupplierPerProductAsPreferred();

  int supplierCountForProduct(String productId) =>
      _AppStoreSplitSupplierInsights(this as AppStore)
          .supplierCountForProduct(productId);

  List<SupplierProductPrice> supplierProductPricesForProduct(
          String productId) =>
      _AppStoreSplitSupplierInsights(this as AppStore)
          .supplierProductPricesForProduct(productId);

  List<SupplierProductPrice> supplierProductPricesForSupplier(
    String supplierId,
  ) =>
      _AppStoreSplitSupplierInsights(this as AppStore)
          .supplierProductPricesForSupplier(supplierId);

  SupplierProductPrice? supplierProductPriceFor({
    required String productId,
    required String supplierId,
  }) =>
      _AppStoreSplitSupplierInsights(this as AppStore).supplierProductPriceFor(
          productId: productId, supplierId: supplierId);

  SupplierProductPrice? preferredSupplierProductPriceForProduct(
    String productId,
  ) =>
      _AppStoreSplitSupplierInsights(this as AppStore)
          .preferredSupplierProductPriceForProduct(productId);

  SupplierProductPrice? bestPriceSupplierProductPriceForProduct(
    String productId,
  ) =>
      _AppStoreSplitSupplierInsights(this as AppStore)
          .bestPriceSupplierProductPriceForProduct(productId);

  SupplierProductPrice? fastestSupplierProductPriceForProduct(
    String productId,
  ) =>
      _AppStoreSplitSupplierInsights(this as AppStore)
          .fastestSupplierProductPriceForProduct(productId);

  Future<void> addOrUpdateSupplierProductPrice(
    SupplierProductPrice price,
  ) =>
      _AppStoreSplitSupplierInsights(this as AppStore)
          .addOrUpdateSupplierProductPrice(price);

  Future<void> deleteSupplierProductPrice(String id) =>
      _AppStoreSplitSupplierInsights(this as AppStore)
          .deleteSupplierProductPrice(id);

  Future<void> initialize({bool hydrateHeavyData = true}) =>
      _AppStoreSplitStartupMigrations(this as AppStore)
          .initialize(hydrateHeavyData: hydrateHeavyData);

  Future<List<T>> _decodeDeferredList<T>(
          String key, T Function(Map<String, dynamic>) fromJson,
          {int? batchSize}) =>
      _AppStoreSplitStartupMigrations(this as AppStore)
          ._decodeDeferredList(key, fromJson, batchSize: batchSize);

  Future<List<T>> _loadTypedEntityList<T>(
    String key,
    Future<List<T>?> Function() typedLoader,
    T Function(Map<String, dynamic>) fromJson, {
    int? batchSize,
  }) =>
      _AppStoreSplitStartupMigrations(this as AppStore)._loadTypedEntityList(
          key, typedLoader, fromJson,
          batchSize: batchSize);

  Future<List<StockMovement>> _loadStockMovementsForStartup() =>
      _AppStoreSplitStartupMigrations(this as AppStore)
          ._loadStockMovementsForStartup();

  Future<List<AccountTransaction>> _loadAccountTransactionsForStartup() =>
      _AppStoreSplitStartupMigrations(this as AppStore)
          ._loadAccountTransactionsForStartup();

  // ignore: unused_element
  Future<void> _loadDeferredStartupData() =>
      _AppStoreSplitStartupMigrationsPart2(this as AppStore)
          ._loadDeferredStartupData();

  // ignore: unused_element
  Future<void> _loadLedgerDeferredStartupData() =>
      _AppStoreSplitStartupMigrationsPart2(this as AppStore)
          ._loadLedgerDeferredStartupData();

  Future<void> _loadSyncDeferredStartupData() =>
      _AppStoreSplitStartupMigrationsPart2(this as AppStore)
          ._loadSyncDeferredStartupData();

  /// Reloads the in-memory AppStore state after a manual Database Admin change.
  ///
  /// DatabasePage can edit the persistent local database directly. Without this
  /// refresh, screens that already cached products, identity, users, stock, or
  /// reports in AppStore keep showing old values until a full app restart.
  /// Reloads the compatibility customer/supplier ledger after a direct
  /// SQLite financial reversal performed outside AppStore.
  Future<void> refreshAccountTransactionsFromSqlite() =>
      _AppStoreSplitStartupMigrationsPart2(this as AppStore)
          .refreshAccountTransactionsFromSqlite();

  /// Reloads the product catalog and all pricing data used by the sales page.
  Future<void> refreshSalesProductData() =>
      _AppStoreSplitStartupMigrationsPart2(this as AppStore)
          .refreshSalesProductData();
  Future<void> refreshAfterDatabaseChange(String key) =>
      _AppStoreSplitStartupMigrationsPart2(this as AppStore)
          .refreshAfterDatabaseChange(key);

  /// Conservative full refresh used for unknown keys or recovery after a failed
  /// targeted refresh.
  Future<void> reloadAllAfterDatabaseChange() =>
      _AppStoreSplitStartupMigrationsPart2(this as AppStore)
          .reloadAllAfterDatabaseChange();

  String _generatePrefixedId(String prefix) =>
      _AppStoreSplitStartupMigrationsPart2(this as AppStore)
          ._generatePrefixedId(prefix);

  void _ensureCatalogDefaults() =>
      _AppStoreSplitStartupMigrationsPart3(this as AppStore)
          ._ensureCatalogDefaults();

  int _loadSyncSequence() =>
      _AppStoreSplitStartupMigrationsPart3(this as AppStore)._loadSyncSequence();

  int _nextSyncSequence() =>
      _AppStoreSplitStartupMigrationsPart3(this as AppStore)._nextSyncSequence();

  String _newSyncEnvelopeId(DateTime now, String prefix) =>
      _AppStoreSplitStartupMigrationsPart3(this as AppStore)
          ._newSyncEnvelopeId(now, prefix);

  Map<String, dynamic> _syncV2MetaOf(SyncChange change) =>
      _AppStoreSplitStartupMigrationsPart3(this as AppStore)._syncV2MetaOf(change);

  String _syncMetaString(SyncChange change, String key) =>
      _AppStoreSplitStartupMigrationsPart3(this as AppStore)
          ._syncMetaString(change, key);
}
