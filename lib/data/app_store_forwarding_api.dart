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
  })  => _AppStoreSplitCoreLoading(this as AppStore)._traceAsync(section, phase, action, metadata: metadata);

  void _traceSync(
    String section,
    String phase,
    void Function() action, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) => _AppStoreSplitCoreLoading(this as AppStore)._traceSync(section, phase, action, metadata: metadata);

  T _traceSyncResult<T>(
    String section,
    String phase,
    T Function() action, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) => _AppStoreSplitCoreLoading(this as AppStore)._traceSyncResult(section, phase, action, metadata: metadata);

  Future<void> warmDeferredPageCaches()  => _AppStoreSplitCoreLoading(this as AppStore).warmDeferredPageCaches();

  Future<void> _requestSyncDataLoad() => _AppStoreSplitCoreLoading(this as AppStore)._requestSyncDataLoad();

  Future<void> _loadDeferredGroup<T>({
    required String key,
    required Future<List<T>> Function() loader,
    required List<T> target,
    void Function()? afterLoad,
  }) => _AppStoreSplitCoreLoading(this as AppStore)._loadDeferredGroup(key: key, loader: loader, target: target, afterLoad: afterLoad);

  Future<void> ensureProductPricingLoaded()  => _AppStoreSplitCoreLoading(this as AppStore).ensureProductPricingLoaded();

  Future<void> ensureProductCostingDataLoaded()  => _AppStoreSplitCoreLoading(this as AppStore).ensureProductCostingDataLoaded();

  Future<void> ensureSalesPageDataLoaded()  => _AppStoreSplitCoreLoading(this as AppStore).ensureSalesPageDataLoaded();

  Future<void> ensurePurchasesPageDataLoaded()  => _AppStoreSplitCoreLoading(this as AppStore).ensurePurchasesPageDataLoaded();

  Future<void> ensureAccountingPageDataLoaded()  => _AppStoreSplitCoreLoading(this as AppStore).ensureAccountingPageDataLoaded();

  Future<void> ensureQuotationsPageDataLoaded()  => _AppStoreSplitCoreLoading(this as AppStore).ensureQuotationsPageDataLoaded();

  Future<void> ensureDeliveryNotesPageDataLoaded()  => _AppStoreSplitCoreLoading(this as AppStore).ensureDeliveryNotesPageDataLoaded();

  Future<void> ensureInventoryPageDataLoaded()  => _AppStoreSplitCoreLoading(this as AppStore).ensureInventoryPageDataLoaded();

  Future<void> ensureHeavyDataLoaded({bool failOnError = false})  => _AppStoreSplitCoreLoading(this as AppStore).ensureHeavyDataLoaded(failOnError: failOnError);

  List<Sale> get sales => _AppStoreSplitCoreLoading(this as AppStore).sales;

  Future<void> ensureCreditNotesLoaded()  => _AppStoreSplitCoreLoading(this as AppStore).ensureCreditNotesLoaded();

  Future<CreditNote> issueCreditNote({
    required Sale originalSale,
    required List<SaleItem> items,
    required double amount,
    String refundMethod = 'Customer balance',
    String note = '',
  })  => _AppStoreSplitCoreLoading(this as AppStore).issueCreditNote(originalSale: originalSale, items: items, amount: amount, refundMethod: refundMethod, note: note);

  List<SaleQuotation> get saleQuotations => _AppStoreSplitCoreLoading(this as AppStore).saleQuotations;

  List<DeliveryNote> get deliveryNotes => _AppStoreSplitCoreLoading(this as AppStore).deliveryNotes;

  List<BillOfMaterials> get billsOfMaterials => _AppStoreSplitCoreLoading(this as AppStore).billsOfMaterials;

  List<ManufacturingOrder> get manufacturingOrders => _AppStoreSplitCoreLoading(this as AppStore).manufacturingOrders;

  ProductCost productCostFor(String productId) => _AppStoreSplitCoreLoading(this as AppStore).productCostFor(productId);

  PriceList get defaultPriceList => _AppStoreSplitCoreLoading(this as AppStore).defaultPriceList;

  ProductPrice? defaultProductPriceFor(String productId,
      {String unitId = 'base'}) => _AppStoreSplitCoreLoading(this as AppStore).defaultProductPriceFor(productId, unitId: unitId);

  ProductPrice? productPriceFor(String productId, String priceListId,
      {String unitId = 'base'}) => _AppStoreSplitCoreLoading(this as AppStore).productPriceFor(productId, priceListId, unitId: unitId);

  ProductPriceOverride? productPriceOverrideFor(
      ProductPrice price, String currencyCode) => _AppStoreSplitCoreLoading(this as AppStore).productPriceOverrideFor(price, currencyCode);

  double productPriceAmountForCurrency(Product product, String currencyCode,
      {String unitId = 'base'}) => _AppStoreSplitCoreLoading(this as AppStore).productPriceAmountForCurrency(product, currencyCode, unitId: unitId);

  double defaultProductUsdPrice(Product product, {String unitId = 'base'}) => _AppStoreSplitCoreLoading(this as AppStore).defaultProductUsdPrice(product, unitId: unitId);

  List<DataConflict> get dataConflicts => _AppStoreSplitCoreLoading(this as AppStore).dataConflicts;

  Future<List<DataConflict>> ensureDataConflictsLoaded()  => _AppStoreSplitCoreLoading(this as AppStore).ensureDataConflictsLoaded();

  List<Expense> get expenses => _AppStoreSplitCoreLoading(this as AppStore).expenses;

  List<Purchase> get purchases => _AppStoreSplitCoreLoading(this as AppStore).purchases;

  List<StockMovement> get stockMovements => _AppStoreSplitCoreLoading(this as AppStore).stockMovements;
  List<InventoryCountSession> get inventoryCountSessions => _AppStoreSplitCoreLoading(this as AppStore).inventoryCountSessions;

  InventoryCountSession? get activeInventoryCountSession => _AppStoreSplitCoreLoading(this as AppStore).activeInventoryCountSession;

  List<Warehouse> get warehouses => _AppStoreSplitCoreLoading(this as AppStore).warehouses;

  Warehouse get defaultWarehouse => _AppStoreSplitCoreLoading(this as AppStore).defaultWarehouse;

  Warehouse resolveWarehouseForSale({String warehouseId = ''}) => _AppStoreSplitCoreLoading(this as AppStore).resolveWarehouseForSale(warehouseId: warehouseId);

  String get saleWarehouseId => _AppStoreSplitCoreLoading(this as AppStore).saleWarehouseId;

  Future<void> setSaleWarehouseId(String warehouseId)  => _AppStoreSplitCoreLoading(this as AppStore).setSaleWarehouseId(warehouseId);

  Warehouse resolveWarehouseForPurchase({String warehouseId = ''}) => _AppStoreSplitCoreLoading(this as AppStore).resolveWarehouseForPurchase(warehouseId: warehouseId);

  void _ensureDefaultWarehouse() => _AppStoreSplitCoreLoading(this as AppStore)._ensureDefaultWarehouse();

  void _invalidateDerivedDataCaches() => _AppStoreSplitCoreLoading(this as AppStore)._invalidateDerivedDataCaches();

  void _ensureDeliveryNoteLookupCache() => _AppStoreSplitCoreLoading(this as AppStore)._ensureDeliveryNoteLookupCache();

















  void _rebuildInventoryCostLayerLookupCache() => _AppStoreSplitCoreLoading(this as AppStore)._rebuildInventoryCostLayerLookupCache();

  double stockForWarehouse(String productId, String warehouseId) => _AppStoreSplitCoreLoading(this as AppStore).stockForWarehouse(productId, warehouseId);

  Future<double> warehouseStockFromSqlite(
    String productId, {
    String warehouseId = '',
  })  => _AppStoreSplitCoreLoading(this as AppStore).warehouseStockFromSqlite(productId, warehouseId: warehouseId);

  Future<Map<String, Map<String, double>>>
      warehouseStockBalancesFromSqlite()  => _AppStoreSplitCoreLoading(this as AppStore).warehouseStockBalancesFromSqlite();

  Future<double> totalWarehouseStockFromSqlite(String productId)  => _AppStoreSplitCoreLoading(this as AppStore).totalWarehouseStockFromSqlite(productId);

  Map<String, double> warehouseStockForProduct(String productId) => _AppStoreSplitCoreLoading(this as AppStore).warehouseStockForProduct(productId);

  List<AccountTransaction> get accountTransactions => _AppStoreSplitCoreLoading(this as AppStore).accountTransactions;

  void _invalidateAccountLedgerCache() => _AppStoreSplitCoreLoading(this as AppStore)._invalidateAccountLedgerCache();

  void _replaceAccountTransactionInLedgerCache({
    AccountTransaction? previous,
    required AccountTransaction current,
  }) => _AppStoreSplitCoreLoading(this as AppStore)._replaceAccountTransactionInLedgerCache(previous: previous, current: current);

  List<AccountTransaction> accountTransactionsForAccount(
    String accountType,
    String accountId,
  ) => _AppStoreSplitCoreLoading(this as AppStore).accountTransactionsForAccount(accountType, accountId);

  double accountBalance(String accountType, String accountId) => _AppStoreSplitCoreLoading(this as AppStore).accountBalance(accountType, accountId);

  List<Map<String, dynamic>> databaseRows(String entity) => _AppStoreSplitCoreLoading(this as AppStore).databaseRows(entity);

  Future<void> saveDatabaseRow(String entity, Map<String, dynamic> json)  => _AppStoreSplitCoreLoading(this as AppStore).saveDatabaseRow(entity, json);

  Future<void> deleteDatabaseRow(String entity, String id)  => _AppStoreSplitCoreLoading(this as AppStore).deleteDatabaseRow(entity, id);

  List<SyncChange> get syncChanges => _AppStoreSplitCoreLoading(this as AppStore).syncChanges;
  List<SyncQueueItem> get syncQueue => _AppStoreSplitCoreLoading(this as AppStore).syncQueue;

  List<SyncQueueItem> get pendingSyncQueue => _AppStoreSplitCoreLoading(this as AppStore).pendingSyncQueue;

  List<SyncChange> get pendingSyncChanges => _AppStoreSplitCoreLoading(this as AppStore).pendingSyncChanges;

  List<SyncQueueItem> pendingSyncQueueForTarget(
    String target, {
    bool readyOnly = true,
  }) => _AppStoreSplitCoreLoading(this as AppStore).pendingSyncQueueForTarget(target, readyOnly: readyOnly);

  List<SyncChange> pendingSyncChangesForTarget(
    String target, {
    bool readyOnly = true,
  }) => _AppStoreSplitCoreLoading(this as AppStore).pendingSyncChangesForTarget(target, readyOnly: readyOnly);

  List<SyncChange> submittedSyncChangesForTarget(String target) => _AppStoreSplitCoreLoading(this as AppStore).submittedSyncChangesForTarget(target);

  int outstandingSyncQueueCountForTarget(String target) => _AppStoreSplitCoreLoading(this as AppStore).outstandingSyncQueueCountForTarget(target);

  String get activeClientSyncTarget => _AppStoreSplitCoreLoading(this as AppStore).activeClientSyncTarget;

  int get activeClientPendingSyncCount => _AppStoreSplitCoreLoading(this as AppStore).activeClientPendingSyncCount;

  DateTime? get latestResetSyncAt => _AppStoreSplitCoreLoading(this as AppStore).latestResetSyncAt;
  bool canAccessPage(String pageId) => _AppStoreSplitAccessAuth(this as AppStore).canAccessPage(pageId);
  bool get hasLocalStoreData => _AppStoreSplitAccessAuth(this as AppStore).hasLocalStoreData;

  Future<void> markSuspendedByHost({String reason = ''})  => _AppStoreSplitAccessAuth(this as AppStore).markSuspendedByHost(reason: reason);

  Future<void> clearSuspendedByHost()  => _AppStoreSplitAccessAuth(this as AppStore).clearSuspendedByHost();

  Future<ThemeMode> loadThemeMode()  => _AppStoreSplitAccessAuth(this as AppStore).loadThemeMode();

  Future<void> saveThemeMode(ThemeMode mode)  => _AppStoreSplitAccessAuth(this as AppStore).saveThemeMode(mode);

  Future<Locale> loadLocale()  => _AppStoreSplitAccessAuth(this as AppStore).loadLocale();

  Future<void> saveLocale(Locale locale)  => _AppStoreSplitAccessAuth(this as AppStore).saveLocale(locale);

  bool get isStressLabEnabled => _AppStoreSplitAccessAuth(this as AppStore).isStressLabEnabled;

  Future<void> setStressLabEnabled(bool enabled)  => _AppStoreSplitAccessAuth(this as AppStore).setStressLabEnabled(enabled);

  bool get _hasOnlyLegacyDefaultAdminUser => _AppStoreSplitAccessAuth(this as AppStore)._hasOnlyLegacyDefaultAdminUser;

  Future<void> completeInitialAdminSetup({
    required String fullName,
    required String username,
    required String password,
  })  => _AppStoreSplitAccessAuth(this as AppStore).completeInitialAdminSetup(fullName: fullName, username: username, password: password);

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
  })  => _AppStoreSplitAccessAuth(this as AppStore).recoverOnlineStoreOwnerIdentity(storeId: storeId, branchId: branchId, storeName: storeName, username: username, password: password, hostDeviceId: hostDeviceId, deviceToken: deviceToken, controlPlaneTenantId: controlPlaneTenantId, deviceRole: deviceRole, syncMode: syncMode, activateUser: activateUser);

  UserRole? roleById(String id) => _AppStoreSplitAccessAuth(this as AppStore).roleById(id);

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
      _AppStoreSplitAccessAuth(this as AppStore).clearSensitiveActionAuthorization();

  void requireSensitiveActionAuthorization(String action) =>
      _AppStoreSplitAccessAuth(this as AppStore).requireSensitiveActionAuthorization(action);
  bool hasPermission(String permission) => _AppStoreSplitAccessAuth(this as AppStore).hasPermission(permission);
  void requirePermission(String permission) => _AppStoreSplitAccessAuth(this as AppStore).requirePermission(permission);

  void requireAnyPermission(Iterable<String> permissions) =>
      _AppStoreSplitAccessAuth(this as AppStore).requireAnyPermission(permissions);

  void requireAllPermissions(Iterable<String> permissions) =>
      _AppStoreSplitAccessAuth(this as AppStore).requireAllPermissions(permissions);

  double get totalSalesAmount => _AppStoreSplitAccessAuth(this as AppStore).totalSalesAmount;

  ExpensesOverview get expensesOverview => _AppStoreSplitSupplierInsights(this as AppStore).expensesOverview;

  void _seedSupplierProductPricesFromPurchaseHistory() => _AppStoreSplitSupplierInsights(this as AppStore)._seedSupplierProductPricesFromPurchaseHistory();

  int _seedSupplierProductPricesFromLegacyProductSuppliers({
    bool recordSyncChanges = false,
  }) => _AppStoreSplitSupplierInsights(this as AppStore)._seedSupplierProductPricesFromLegacyProductSuppliers(recordSyncChanges: recordSyncChanges);

  void _markSingleSupplierPerProductAsPreferred() => _AppStoreSplitSupplierInsights(this as AppStore)._markSingleSupplierPerProductAsPreferred();

  int supplierCountForProduct(String productId) => _AppStoreSplitSupplierInsights(this as AppStore).supplierCountForProduct(productId);

  List<SupplierProductPrice> supplierProductPricesForProduct(String productId) => _AppStoreSplitSupplierInsights(this as AppStore).supplierProductPricesForProduct(productId);

  List<SupplierProductPrice> supplierProductPricesForSupplier(
    String supplierId,
  ) => _AppStoreSplitSupplierInsights(this as AppStore).supplierProductPricesForSupplier(supplierId);

  SupplierProductPrice? supplierProductPriceFor({
    required String productId,
    required String supplierId,
  }) => _AppStoreSplitSupplierInsights(this as AppStore).supplierProductPriceFor(productId: productId, supplierId: supplierId);

  SupplierProductPrice? preferredSupplierProductPriceForProduct(
    String productId,
  ) => _AppStoreSplitSupplierInsights(this as AppStore).preferredSupplierProductPriceForProduct(productId);

  SupplierProductPrice? bestPriceSupplierProductPriceForProduct(
    String productId,
  ) => _AppStoreSplitSupplierInsights(this as AppStore).bestPriceSupplierProductPriceForProduct(productId);

  SupplierProductPrice? fastestSupplierProductPriceForProduct(
    String productId,
  ) => _AppStoreSplitSupplierInsights(this as AppStore).fastestSupplierProductPriceForProduct(productId);

  Future<void> addOrUpdateSupplierProductPrice(
    SupplierProductPrice price,
  )  => _AppStoreSplitSupplierInsights(this as AppStore).addOrUpdateSupplierProductPrice(price);

  Future<void> deleteSupplierProductPrice(String id)  => _AppStoreSplitSupplierInsights(this as AppStore).deleteSupplierProductPrice(id);



  Future<void> initialize({bool hydrateHeavyData = true})  => _AppStoreSplitStartupMigrations(this as AppStore).initialize(hydrateHeavyData: hydrateHeavyData);

  Future<List<T>> _decodeDeferredList<T>(
      String key, T Function(Map<String, dynamic>) fromJson,
      {int? batchSize})  => _AppStoreSplitStartupMigrations(this as AppStore)._decodeDeferredList(key, fromJson, batchSize: batchSize);

  Future<List<T>> _loadTypedEntityList<T>(
    String key,
    Future<List<T>?> Function() typedLoader,
    T Function(Map<String, dynamic>) fromJson, {
    int? batchSize,
  })  => _AppStoreSplitStartupMigrations(this as AppStore)._loadTypedEntityList(key, typedLoader, fromJson, batchSize: batchSize);

  Future<List<StockMovement>> _loadStockMovementsForStartup()  => _AppStoreSplitStartupMigrations(this as AppStore)._loadStockMovementsForStartup();

  Future<List<AccountTransaction>> _loadAccountTransactionsForStartup()  => _AppStoreSplitStartupMigrations(this as AppStore)._loadAccountTransactionsForStartup();

  // ignore: unused_element
  Future<void> _loadDeferredStartupData()  => _AppStoreSplitStartupMigrations(this as AppStore)._loadDeferredStartupData();

  // ignore: unused_element
  Future<void> _loadLedgerDeferredStartupData()  => _AppStoreSplitStartupMigrations(this as AppStore)._loadLedgerDeferredStartupData();

  Future<void> _loadSyncDeferredStartupData()  => _AppStoreSplitStartupMigrations(this as AppStore)._loadSyncDeferredStartupData();

  /// Reloads the in-memory AppStore state after a manual Database Admin change.
  ///
  /// DatabasePage can edit the persistent local database directly. Without this
  /// refresh, screens that already cached products, identity, users, stock, or
  /// reports in AppStore keep showing old values until a full app restart.
  /// Reloads the compatibility customer/supplier ledger after a direct
  /// SQLite financial reversal performed outside AppStore.
  Future<void> refreshAccountTransactionsFromSqlite()  => _AppStoreSplitStartupMigrations(this as AppStore).refreshAccountTransactionsFromSqlite();

  /// Reloads the product catalog and all pricing data used by the sales page.
  Future<void> refreshSalesProductData()  => _AppStoreSplitStartupMigrations(this as AppStore).refreshSalesProductData();
  Future<void> refreshAfterDatabaseChange(String key)  => _AppStoreSplitStartupMigrations(this as AppStore).refreshAfterDatabaseChange(key);

  /// Conservative full refresh used for unknown keys or recovery after a failed
  /// targeted refresh.
  Future<void> reloadAllAfterDatabaseChange()  => _AppStoreSplitStartupMigrations(this as AppStore).reloadAllAfterDatabaseChange();

  String _generatePrefixedId(String prefix) => _AppStoreSplitStartupMigrations(this as AppStore)._generatePrefixedId(prefix);

  void _ensureCatalogDefaults() => _AppStoreSplitStartupMigrations(this as AppStore)._ensureCatalogDefaults();

  int _loadSyncSequence() => _AppStoreSplitStartupMigrations(this as AppStore)._loadSyncSequence();

  int _nextSyncSequence() => _AppStoreSplitStartupMigrations(this as AppStore)._nextSyncSequence();

  String _newSyncEnvelopeId(DateTime now, String prefix) => _AppStoreSplitStartupMigrations(this as AppStore)._newSyncEnvelopeId(now, prefix);

  Map<String, dynamic> _syncV2MetaOf(SyncChange change) => _AppStoreSplitStartupMigrations(this as AppStore)._syncV2MetaOf(change);

  String _syncMetaString(SyncChange change, String key) => _AppStoreSplitStartupMigrations(this as AppStore)._syncMetaString(change, key);

  bool _isReplayOrDuplicateSyncEvent(
    SyncChange change, {
    required Set<String> existingEnvelopeIds,
    required Set<String> existingEventIds,
    required Set<String> acceptedSourceCommandIds,
    required int lastAppliedSequence,
  }) => _AppStoreSplitStartupMigrations(this as AppStore)._isReplayOrDuplicateSyncEvent(change, existingEnvelopeIds: existingEnvelopeIds, existingEventIds: existingEventIds, acceptedSourceCommandIds: acceptedSourceCommandIds, lastAppliedSequence: lastAppliedSequence);

  String? validateClientDraftForHostAcceptance(SyncChange change) => _AppStoreSplitStartupMigrations(this as AppStore).validateClientDraftForHostAcceptance(change);

  Future<void> clearPendingSyncQueue({bool notify = true})  => _AppStoreSplitStartupMigrations(this as AppStore).clearPendingSyncQueue(notify: notify);

  int _loadInvoiceCounter() => _AppStoreSplitStartupMigrations(this as AppStore)._loadInvoiceCounter();

  // Legacy migration path retained for controlled recovery of pre-v17 stores.
  // ignore: unused_element
  Future<void> _runDataMigrationsIfNeeded()  => _AppStoreSplitStartupMigrations(this as AppStore)._runDataMigrationsIfNeeded();

  double _safeUsdCost(Product product) => _AppStoreSplitStartupMigrations(this as AppStore)._safeUsdCost(product);

  AppPlatformType _detectPlatform() => _AppStoreSplitIdentityUsers(this as AppStore)._detectPlatform();

  AppIdentity _loadOrCreateAppIdentity() => _AppStoreSplitIdentityUsers(this as AppStore)._loadOrCreateAppIdentity();

  Future<void> updateDeviceName(String deviceName)  => _AppStoreSplitIdentityUsers(this as AppStore).updateDeviceName(deviceName);

  Future<void> recoverExistingStoreIdentity({
    required String storeId,
    String recoveryKey = '',
    String? branchId,
    String? hostDeviceId,
    String? deviceToken,
    String? controlPlaneTenantId,
    DeviceRole? deviceRole,
    SyncMode? syncMode,
  })  => _AppStoreSplitIdentityUsers(this as AppStore).recoverExistingStoreIdentity(storeId: storeId, recoveryKey: recoveryKey, branchId: branchId, hostDeviceId: hostDeviceId, deviceToken: deviceToken, controlPlaneTenantId: controlPlaneTenantId, deviceRole: deviceRole, syncMode: syncMode);

  AppIdentity _identityForLanSnapshotImport(Map<String, dynamic> decoded) => _AppStoreSplitIdentityUsers(this as AppStore)._identityForLanSnapshotImport(decoded);

  AppIdentity _normalizedLocalIdentity(AppIdentity identity) => _AppStoreSplitIdentityUsers(this as AppStore)._normalizedLocalIdentity(identity);

  Map<String, dynamic>? get pendingHostTransferRequest => _AppStoreSplitIdentityUsers(this as AppStore).pendingHostTransferRequest;

  Map<String, dynamic>? get latestHostTransferNotification => _AppStoreSplitIdentityUsers(this as AppStore).latestHostTransferNotification;

  Future<void> clearHostTransferNotification()  => _AppStoreSplitIdentityUsers(this as AppStore).clearHostTransferNotification();

  Future<void> _storeHostTransferNotification(
    Map<String, dynamic> payload,
  )  => _AppStoreSplitIdentityUsers(this as AppStore)._storeHostTransferNotification(payload);

  Future<void> clearLocalHostTransferRequest()  => _AppStoreSplitIdentityUsers(this as AppStore).clearLocalHostTransferRequest();

  Future<void> _forceApplyRoleFromTransfer(AppIdentity next)  => _AppStoreSplitIdentityUsers(this as AppStore)._forceApplyRoleFromTransfer(next);

  void _assertSafeRoleTransition(
    AppIdentity next, {
    required String source,
    bool allowApprovedTransfer = false,
    bool allowInitialHostRegistration = false,
  }) => _AppStoreSplitIdentityUsers(this as AppStore)._assertSafeRoleTransition(next, source: source, allowApprovedTransfer: allowApprovedTransfer, allowInitialHostRegistration: allowInitialHostRegistration);

  void _assertLanDirectRoleRules(AppIdentity next, {required String source}) => _AppStoreSplitIdentityUsers(this as AppStore)._assertLanDirectRoleRules(next, source: source);

  Future<void> updateAppIdentityDuringSetup(AppIdentity identity)  => _AppStoreSplitIdentityUsers(this as AppStore).updateAppIdentityDuringSetup(identity);

  Future<void> updateAppIdentity(AppIdentity identity)  => _AppStoreSplitIdentityUsers(this as AppStore).updateAppIdentity(identity);

  Future<void> updateAppIdentityLocalOnly(
    AppIdentity identity, {
    String source = 'local sync settings',
  })  => _AppStoreSplitIdentityUsers(this as AppStore).updateAppIdentityLocalOnly(identity, source: source);

  Future<void> setActiveSyncTransport(String transport)  => _AppStoreSplitIdentityUsers(this as AppStore).setActiveSyncTransport(transport);

  Future<void> requestHostTransfer({String reason = ''})  => _AppStoreSplitIdentityUsers(this as AppStore).requestHostTransfer(reason: reason);

  Future<void> approveHostTransfer(String requestingDeviceId)  => _AppStoreSplitIdentityUsers(this as AppStore).approveHostTransfer(requestingDeviceId);

  Future<void> activateApprovedHostTransfer()  => _AppStoreSplitIdentityUsers(this as AppStore).activateApprovedHostTransfer();

  @Deprecated('Use users and roles instead. Kept for old code compatibility.')
  Future<void> setCurrentRole(String role)  => _AppStoreSplitIdentityUsers(this as AppStore).setCurrentRole(role);

  Future<List<UserRole>> _loadRoles()  => _AppStoreSplitIdentityUsers(this as AppStore)._loadRoles();

  Future<List<AppUser>> _loadUsers()  => _AppStoreSplitIdentityUsers(this as AppStore)._loadUsers();

  Future<void> _saveRolesAndUsers()  => _AppStoreSplitIdentityUsers(this as AppStore)._saveRolesAndUsers();

  Future<void> _ensureDefaultAdminUser()  => _AppStoreSplitIdentityUsers(this as AppStore)._ensureDefaultAdminUser();

  void _restoreActiveUser() => _AppStoreSplitIdentityUsers(this as AppStore)._restoreActiveUser();

  Future<bool> login(
    String username,
    String password, {
    bool remember = false,
  })  => _AppStoreSplitIdentityUsers(this as AppStore).login(username, password, remember: remember);

  Future<void> logout()  => _AppStoreSplitIdentityUsers(this as AppStore).logout();

  Future<void> applySessionUser({
    required AppUser activeUser,
    required String currentRole,
    required Set<String> permissions,
    required bool rememberLogin,
  })  => _AppStoreSplitIdentityUsers(this as AppStore).applySessionUser(activeUser: activeUser, currentRole: currentRole, permissions: permissions, rememberLogin: rememberLogin);

  Future<void> clearSessionUser()  => _AppStoreSplitIdentityUsers(this as AppStore).clearSessionUser();

  Future<void> _loadSessionPermissionsFromStorage()  => _AppStoreSplitIdentityUsers(this as AppStore)._loadSessionPermissionsFromStorage();

  Future<void> _restoreActiveUserFromStorage()  => _AppStoreSplitIdentityUsers(this as AppStore)._restoreActiveUserFromStorage();

  Future<void> _refreshAuthFlags()  => _AppStoreSplitIdentityUsers(this as AppStore)._refreshAuthFlags();

  void refreshUi() => _AppStoreSplitIdentityUsers(this as AppStore).refreshUi();

  /// Applies a server-approved password reset to the matching local owner.
  /// The server reset is the authority; this only keeps Offline Login in sync
  /// after the support-issued one-time reset has been consumed successfully.
  Future<bool> applySupportPasswordResetToLocalUser({
    required String username,
    required String newPassword,
  })  => _AppStoreSplitIdentityUsers(this as AppStore).applySupportPasswordResetToLocalUser(username: username, newPassword: newPassword);

  Future<bool> verifyAdminPassword(String password)  => _AppStoreSplitIdentityUsers(this as AppStore).verifyAdminPassword(password);

  bool _verifyPassword(String password, String storedHash) => _AppStoreSplitIdentityUsers(this as AppStore)._verifyPassword(password, storedHash);

  Future<void> addOrUpdateRole(UserRole role)  => _AppStoreSplitIdentityUsers(this as AppStore).addOrUpdateRole(role);

  Future<void> deleteRole(String id)  => _AppStoreSplitIdentityUsers(this as AppStore).deleteRole(id);

  AppUser? get storeOwnerUser => _AppStoreSplitIdentityUsers(this as AppStore).storeOwnerUser;

  Future<void> applyStoreOwnerCredentials({
    required String username,
    required String password,
    String? fullName,
  })  => _AppStoreSplitIdentityUsers(this as AppStore).applyStoreOwnerCredentials(username: username, password: password, fullName: fullName);

  Future<void> addOrUpdateUser(AppUser user, {String? password})  => _AppStoreSplitIdentityUsers(this as AppStore).addOrUpdateUser(user, password: password);

  Future<void> deleteUser(String id)  => _AppStoreSplitIdentityUsers(this as AppStore).deleteUser(id);

  Future<String> _hashPasswordAsync(String password)  => _AppStoreSplitIdentityUsers(this as AppStore)._hashPasswordAsync(password);

  String _generateSalt() => _AppStoreSplitIdentityUsers(this as AppStore)._generateSalt();

  StoreProfile _loadStoreProfile() => _AppStoreSplitIdentityUsers(this as AppStore)._loadStoreProfile();

  void _normalizeCustomers() => _AppStoreSplitIdentityUsers(this as AppStore)._normalizeCustomers();

  Future<void> _upsertSqliteBusinessRows(
    String key,
    Iterable<Map<String, dynamic>> rows,
  ) => _AppStoreSplitIdentityUsers(this as AppStore)._upsertSqliteBusinessRows(key, rows);

  void _markProductDerivedDataDirty() => _AppStoreSplitIdentityUsers(this as AppStore)._markProductDerivedDataDirty();

  Future<void> _flushProductDerivedData()  => _AppStoreSplitIdentityUsers(this as AppStore)._flushProductDerivedData();

  Future<bool> _schedulePurchaseAccounting(Purchase purchase)  => _AppStoreSplitIdentityUsers(this as AppStore)._schedulePurchaseAccounting(purchase);

  Future<void> _waitForPendingPurchaseAccounting(String purchaseId)  => _AppStoreSplitIdentityUsers(this as AppStore)._waitForPendingPurchaseAccounting(purchaseId);

  Future<void> waitForPendingAccounting({
    Duration timeout = const Duration(seconds: 45),
  })  => _AppStoreSplitIdentityUsers(this as AppStore).waitForPendingAccounting(timeout: timeout);

  void _rebuildProductIndexes() => _AppStoreSplitIdentityUsers(this as AppStore)._rebuildProductIndexes();





  void _rebuildCustomerIndexes() => _AppStoreSplitIdentityUsers(this as AppStore)._rebuildCustomerIndexes();

  void _rebuildSupplierIndexes() => _AppStoreSplitIdentityUsers(this as AppStore)._rebuildSupplierIndexes();

  void _rebuildMutableEntityIndexes() => _AppStoreSplitIdentityUsers(this as AppStore)._rebuildMutableEntityIndexes();

  void _rebuildProductInventoryProjectionFromMovements() => _AppStoreSplitIdentityUsers(this as AppStore)._rebuildProductInventoryProjectionFromMovements();

  void _rebuildStockMovementIndexes() => _AppStoreSplitIdentityUsers(this as AppStore)._rebuildStockMovementIndexes();

  void _rebuildPurchaseIndexes() => _AppStoreSplitPersistenceSyncCore(this as AppStore)._rebuildPurchaseIndexes();

  Future<Sale?> _saleByIdFromSqlite(String id) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._saleByIdFromSqlite(id);

  Future<Purchase?> _purchaseByIdFromSqlite(String id) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._purchaseByIdFromSqlite(id);

  /// Reads the latest purchase snapshot before opening an edit form. The
  /// creator of a purchase is not relevant to edit access; the caller's
  /// permissions are checked by the mutation method. This refresh only avoids
  /// opening a form from a stale list/details snapshot.
  Future<Purchase?> reloadPurchaseFromSqlite(String id)  => _AppStoreSplitPersistenceSyncCore(this as AppStore).reloadPurchaseFromSqlite(id);

  Future<Expense?> _expenseByIdFromSqlite(String id) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._expenseByIdFromSqlite(id);

  void _putStockMovementAtIndex(StockMovement movement, int index) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._putStockMovementAtIndex(movement, index);

  void _mirrorAuthoritativeStockMovements(Iterable<StockMovement> movements) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._mirrorAuthoritativeStockMovements(movements);

  void _rebuildExpenseIndexes() => _AppStoreSplitPersistenceSyncCore(this as AppStore)._rebuildExpenseIndexes();

  void _rebuildAccountTransactionIndexes() => _AppStoreSplitPersistenceSyncCore(this as AppStore)._rebuildAccountTransactionIndexes();

  void _touchDataRevisions({
    bool products = false,
    bool customers = false,
    bool sales = false,
    bool deliveryNotes = false,
    bool suppliers = false,
    bool supplierProductPrices = false,
    bool expenses = false,
    bool purchases = false,
    bool stockMovements = false,
    bool inventoryCounts = false,
    bool warehouses = false,
    bool accountTransactions = false,
    bool storeProfile = false,
  }) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._touchDataRevisions(products: products, customers: customers, sales: sales, deliveryNotes: deliveryNotes, suppliers: suppliers, supplierProductPrices: supplierProductPrices, expenses: expenses, purchases: purchases, stockMovements: stockMovements, inventoryCounts: inventoryCounts, warehouses: warehouses, accountTransactions: accountTransactions, storeProfile: storeProfile);

  void _touchPurchasesData() => _AppStoreSplitPersistenceSyncCore(this as AppStore)._touchPurchasesData();

  void _touchExpensesData() => _AppStoreSplitPersistenceSyncCore(this as AppStore)._touchExpensesData();

  void _putPurchaseAtIndex(Purchase purchase, int index) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._putPurchaseAtIndex(purchase, index);

  void _removePurchaseAtIndex(int index) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._removePurchaseAtIndex(index);

  void _putExpenseAtIndex(Expense expense, int index) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._putExpenseAtIndex(expense, index);

  void _removeExpenseAtIndex(int index) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._removeExpenseAtIndex(index);

  void _removeAccountTransactionAtIndex(int index) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._removeAccountTransactionAtIndex(index);

  /// Automatic event-log compaction is intentionally not run from normal save
  /// calls. It is async, Host-only, and must be guarded by ACK-based safety
  /// checks, so sync transports call [compactSyncedSyncHistoryForMaintenance]
  /// after a successful sync/ACK cycle.
  int _earliestStoredAuthoritativeSequence() => _AppStoreSplitPersistenceSyncCore(this as AppStore)._earliestStoredAuthoritativeSequence();

  int _latestStoredAuthoritativeSequence() => _AppStoreSplitPersistenceSyncCore(this as AppStore)._latestStoredAuthoritativeSequence();

  int _minimumActivePeerAckSequence({
    Duration activeWindow = const Duration(days: 14),
  }) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._minimumActivePeerAckSequence(activeWindow: activeWindow);

  Future<void> _saveSyncStateOnly()  => _AppStoreSplitPersistenceSyncCore(this as AppStore)._saveSyncStateOnly();

  Future<void> _saveAll()  => _AppStoreSplitPersistenceSyncCore(this as AppStore)._saveAll();

  Future<void> _saveDirty({
    bool products = false,
    bool productDerivedData = true,
    bool customers = false,
    bool sales = false,
    bool saleQuotations = false,
    bool deliveryNotes = false,
    bool billsOfMaterials = false,
    bool manufacturingOrders = false,
    bool suppliers = false,
    bool supplierProductPrices = false,
    bool categories = false,
    bool brands = false,
    bool units = false,
    bool expenses = false,
    bool purchases = false,
    bool stockMovements = false,
    bool inventoryCounts = false,
    bool warehouses = false,
    bool accountTransactions = false,
    bool storeProfile = false,
    bool invoiceCounter = false,
    bool purchaseCounter = false,
    bool sync = false,
  })  => _AppStoreSplitPersistenceSyncCore(this as AppStore)._saveDirty(products: products, productDerivedData: productDerivedData, customers: customers, sales: sales, saleQuotations: saleQuotations, deliveryNotes: deliveryNotes, billsOfMaterials: billsOfMaterials, manufacturingOrders: manufacturingOrders, suppliers: suppliers, supplierProductPrices: supplierProductPrices, categories: categories, brands: brands, units: units, expenses: expenses, purchases: purchases, stockMovements: stockMovements, inventoryCounts: inventoryCounts, warehouses: warehouses, accountTransactions: accountTransactions, storeProfile: storeProfile, invoiceCounter: invoiceCounter, purchaseCounter: purchaseCounter, sync: sync);

  void _resetBusinessDataInMemory({bool keepStoreProfile = true}) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._resetBusinessDataInMemory(keepStoreProfile: keepStoreProfile);

  Future<void> resetBusinessData({bool keepStoreProfile = true})  => _AppStoreSplitPersistenceSyncCore(this as AppStore).resetBusinessData(keepStoreProfile: keepStoreProfile);

  Future<void> clearLocalDeviceBusinessData({
    bool keepStoreProfile = true,
  })  => _AppStoreSplitPersistenceSyncCore(this as AppStore).clearLocalDeviceBusinessData(keepStoreProfile: keepStoreProfile);

  Future<int> clearLocalOnlyPendingSyncChanges()  => _AppStoreSplitPersistenceSyncCore(this as AppStore).clearLocalOnlyPendingSyncChanges();

  Future<void> factoryResetLocalDevice({
    bool enforcePermission = true,
    bool preserveAdminUsers = false,
  })  => _AppStoreSplitPersistenceSyncCore(this as AppStore).factoryResetLocalDevice(enforcePermission: enforcePermission, preserveAdminUsers: preserveAdminUsers);

  Future<int> cleanupSoftDeletedRecords({
    Duration retention = const Duration(days: 30),
  })  => _AppStoreSplitPersistenceSyncCore(this as AppStore).cleanupSoftDeletedRecords(retention: retention);

  Future<BusinessDataIntegrityResult> verifyLocalBusinessDataIntegrity()  => _AppStoreSplitPersistenceSyncCore(this as AppStore).verifyLocalBusinessDataIntegrity();

  /// Repairs only product references that already exist in historical sales,
  /// purchases, or stock movements. Soft-deleted products are restored first.
  /// Creating archival catalog entries is opt-in because it changes the active
  /// data set; the new records are inactive and never track stock.
  Future<BusinessDataIntegrityRepairResult> repairMissingProductReferences({
    bool createArchivedProducts = false,
  })  => _AppStoreSplitPersistenceSyncCore(this as AppStore).repairMissingProductReferences(createArchivedProducts: createArchivedProducts);

  Future<void> updateStoreProfile(StoreProfile profile)  => _AppStoreSplitPersistenceSyncCore(this as AppStore).updateStoreProfile(profile);

  Future<void> updateTaxConfiguration({
    required List<TaxProfile> profiles,
    required String defaultTaxProfileId,
  }) => _AppStoreSplitPersistenceSyncCore(this as AppStore).updateTaxConfiguration(
        profiles: profiles,
        defaultTaxProfileId: defaultTaxProfileId,
      );

  Future<void> updateDefaultTaxRatePercent(double ratePercent) =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)
          .updateDefaultTaxRatePercent(ratePercent);

  void _validateProduct(Product product, {Product? previousProduct}) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._validateProduct(product, previousProduct: previousProduct);

  String _generateUniqueProductCode({
    String? exceptProductId,
    Set<String>? reservedCodes,
  }) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._generateUniqueProductCode(exceptProductId: exceptProductId, reservedCodes: reservedCodes);

  String get _invoiceDevicePrefix => _AppStoreSplitPersistenceSyncCore(this as AppStore)._invoiceDevicePrefix;

  int _invoiceSequenceFromNo(String invoiceNo) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._invoiceSequenceFromNo(invoiceNo);

  void _rememberSqliteDirtyBusinessRow(
    String key,
    Map<String, dynamic> payload,
  ) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._rememberSqliteDirtyBusinessRow(key, payload);

  void _forgetSqliteDirtyBusinessRow(String key, String id) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._forgetSqliteDirtyBusinessRow(key, id);

  void _rememberRemoteSqliteBusinessRows(SyncChange change) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._rememberRemoteSqliteBusinessRows(change);

  void _recordSyncChange({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._recordSyncChange(entityType: entityType, entityId: entityId, operation: operation, payload: payload);

  /// Runs after login before the automatic sync transports start.
  ///
  /// The cursor is persisted through LocalDatabaseService, which means SQLite
  /// owns it on native platforms. On the first Phase 8 launch we establish a
  /// baseline without replaying the entire historical accounting database. On
  /// later launches we capture everything committed after the last durable
  /// cursor, including a transaction that committed immediately before a
  /// process crash.
  Future<void> recoverPhase8AccountingSyncAfterStartup()  => _AppStoreSplitPersistenceSyncCore(this as AppStore).recoverPhase8AccountingSyncAfterStartup();

  Future<void> recordPhase8AccountingMutationForSync()  => _AppStoreSplitPersistenceSyncCore(this as AppStore).recordPhase8AccountingMutationForSync();

  bool get _isLanClientConfigured => _AppStoreSplitPersistenceSyncCore(this as AppStore)._isLanClientConfigured;

  bool get _isDirectClientConfigured => _AppStoreSplitPersistenceSyncCore(this as AppStore)._isDirectClientConfigured;

  bool get _isLanHostConfigured => _AppStoreSplitPersistenceSyncCore(this as AppStore)._isLanHostConfigured;

  String get _stockTransactionSyncTarget => _AppStoreSplitPersistenceSyncCore(this as AppStore)._stockTransactionSyncTarget;

  /// Repairs the split-brain state where a change exists in the sync history
  /// but its outbound queue row is missing. This can be left by older
  /// snapshot/restore flows that persisted the two stores independently.
  ///
  /// Only local Client drafts are reconstructed. Host-authoritative history
  /// received by a Client must never be re-queued as a new draft.
  Future<void> _reconcileUnsyncedChangesWithQueue()  => _AppStoreSplitPersistenceSyncCore(this as AppStore)._reconcileUnsyncedChangesWithQueue();

  Sale _saleSyncMetaPreview(
    Sale item,
    DateTime now, {
    bool isCreate = false,
  }) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._saleSyncMetaPreview(item, now, isCreate: isCreate);

  Purchase _purchaseSyncMetaPreview(
    Purchase item,
    DateTime now, {
    bool isCreate = false,
  }) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._purchaseSyncMetaPreview(item, now, isCreate: isCreate);

  Expense _expenseSyncMetaPreview(
    Expense item,
    DateTime now, {
    bool isCreate = false,
  }) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._expenseSyncMetaPreview(item, now, isCreate: isCreate);

  T _withSyncMeta<T>(
    T item,
    DateTime now, {
    bool isCreate = false,
    bool clearDeletedAt = true,
  }) => _AppStoreSplitPersistenceSyncCore(this as AppStore)._withSyncMeta(item, now, isCreate: isCreate, clearDeletedAt: clearDeletedAt);

  Future<void> _persistAccountTransactionInExistingTransaction(
    dynamic sqliteDb,
    AccountTransaction transaction,
  )  => _AppStoreSplitPersistenceSyncCore(this as AppStore)._persistAccountTransactionInExistingTransaction(sqliteDb, transaction);

  Future<void> addOrUpdateAccountTransaction(
    AccountTransaction transaction,
  )  => _AppStoreSplitPersistenceSyncCore(this as AppStore).addOrUpdateAccountTransaction(transaction);

  Future<void> deleteAccountTransaction(String id)  => _AppStoreSplitPersistenceSyncCore(this as AppStore).deleteAccountTransaction(id);

  Future<void> _recordPurchaseLedger(Purchase purchase, DateTime now)  => _AppStoreSplitPersistenceSyncCore(this as AppStore)._recordPurchaseLedger(purchase, now);

  Future<void> _recordPurchaseCancelLedger(
    Purchase purchase,
    DateTime now, {
    String reason = '',
    bool isReturn = false,
  })  => _AppStoreSplitPersistenceSyncCore(this as AppStore)._recordPurchaseCancelLedger(purchase, now, reason: reason, isReturn: isReturn);

  Future<void> _recordSaleLedger(Sale sale, DateTime now)  => _AppStoreSplitPersistenceSyncCore(this as AppStore)._recordSaleLedger(sale, now);

  Future<void> _recordSaleCancelLedger(
    Sale sale,
    DateTime now, {
    bool isReturn = false,
    String returnReferenceId = '',
  })  => _AppStoreSplitPersistenceSyncCore(this as AppStore)._recordSaleCancelLedger(sale, now, isReturn: isReturn, returnReferenceId: returnReferenceId);

  Future<void> _reverseExpenseLedger(Expense expense, DateTime now,
      {String reason = ''})  => _AppStoreSplitPersistenceSyncCore(this as AppStore)._reverseExpenseLedger(expense, now, reason: reason);

  void _ensureDefaultPriceLists() => _AppStoreSplitPricingCosting(this as AppStore)._ensureDefaultPriceLists();

  void _rebuildProductCostLookupCache() => _AppStoreSplitPricingCosting(this as AppStore)._rebuildProductCostLookupCache();

  void _rebuildProductPricingLookupCaches() => _AppStoreSplitPricingCosting(this as AppStore)._rebuildProductPricingLookupCaches();

  void _ensureProductPricingLookupCaches() => _AppStoreSplitPricingCosting(this as AppStore)._ensureProductPricingLookupCaches();

  void _removeProductPricingLookupEntries(String productId) => _AppStoreSplitPricingCosting(this as AppStore)._removeProductPricingLookupEntries(productId);

  void _ensureDefaultProductPriceEntries({Product? product}) => _AppStoreSplitPricingCosting(this as AppStore)._ensureDefaultProductPriceEntries(product: product);

  Future<void> setDefaultProductBasePrice(
      {required String productId,
      required String unitId,
      required double amount,
      required String currencyCode})  => _AppStoreSplitPricingCosting(this as AppStore).setDefaultProductBasePrice(productId: productId, unitId: unitId, amount: amount, currencyCode: currencyCode);

  Future<void> setProductBasePriceForList({
    required String productId,
    required String priceListId,
    required double amount,
    required String currencyCode,
    String unitId = 'base',
  })  => _AppStoreSplitPricingCosting(this as AppStore).setProductBasePriceForList(productId: productId, priceListId: priceListId, amount: amount, currencyCode: currencyCode, unitId: unitId);

  Future<void> setProductPriceOverride({
    required String productPriceId,
    required String currencyCode,
    required double amount,
    ProductPriceOverrideMode mode = ProductPriceOverrideMode.fixed,
    bool isActive = true,
  })  => _AppStoreSplitPricingCosting(this as AppStore).setProductPriceOverride(productPriceId: productPriceId, currencyCode: currencyCode, amount: amount, mode: mode, isActive: isActive);

  Future<void> removeProductPriceOverride(
      String productPriceId, String currencyCode)  => _AppStoreSplitPricingCosting(this as AppStore).removeProductPriceOverride(productPriceId, currencyCode);

  void _ensureProductCostEntries({Product? product}) => _AppStoreSplitPricingCosting(this as AppStore)._ensureProductCostEntries(product: product);

  InventoryCostingMethod _runtimeInventoryCostingMethod(
      InventoryCostingMethod requested) => _AppStoreSplitPricingCosting(this as AppStore)._runtimeInventoryCostingMethod(requested);

  void _ensureCostingMethodHistory() => _AppStoreSplitPricingCosting(this as AppStore)._ensureCostingMethodHistory();

  DateTime? _currentOpenFifoEffectiveFrom() => _AppStoreSplitPricingCosting(this as AppStore)._currentOpenFifoEffectiveFrom();

  Future<void> setInventoryCostingMethod(InventoryCostingMethod method,
      {String reason = ''})  => _AppStoreSplitPricingCosting(this as AppStore).setInventoryCostingMethod(method, reason: reason);

  ProductCost _upsertProductCostFromPurchase({
    required Product product,
    required double receivedQty,
    required double baseUnitCost,
    required DateTime now,
  }) => _AppStoreSplitPricingCosting(this as AppStore)._upsertProductCostFromPurchase(product: product, receivedQty: receivedQty, baseUnitCost: baseUnitCost, now: now);

  void _addInventoryCostLayerFromPurchase({
    required Purchase purchase,
    required PurchaseItem item,
    required int lineIndex,
    required double quantity,
    required double unitCost,
    required DateTime now,
  }) => _AppStoreSplitPricingCosting(this as AppStore)._addInventoryCostLayerFromPurchase(purchase: purchase, item: item, lineIndex: lineIndex, quantity: quantity, unitCost: unitCost, now: now);

  void _addInventoryCostLayerFromStockIncrease({
    required String id,
    required Product product,
    required double quantity,
    required double unitCost,
    required String sourceType,
    required String sourceId,
    required DateTime now,
  }) => _AppStoreSplitPricingCosting(this as AppStore)._addInventoryCostLayerFromStockIncrease(id: id, product: product, quantity: quantity, unitCost: unitCost, sourceType: sourceType, sourceId: sourceId, now: now);

  bool _purchaseHasConsumedCostLayers(String purchaseId) => _AppStoreSplitPricingCosting(this as AppStore)._purchaseHasConsumedCostLayers(purchaseId);

  InventoryCostResult _resolveCostForSaleItem(SaleItem item, DateTime now) => _AppStoreSplitPricingCosting(this as AppStore)._resolveCostForSaleItem(item, now);

  Future<InventoryCostResult> _resolveCostForSaleItemInTransaction(
    VentioDriftDatabase db,
    SaleItem item,
    DateTime now,
  )  => _AppStoreSplitPricingCosting(this as AppStore)._resolveCostForSaleItemInTransaction(db, item, now);

  Future<void> _restoreInventoryCostLayersFromSaleItemsInTransaction(
    VentioDriftDatabase db,
    Iterable<SaleItem> items,
    DateTime now, {
    required DateTime originalSaleDate,
    required String restorationSourceType,
    required String restorationSourceId,
  })  => _AppStoreSplitPricingCosting(this as AppStore)._restoreInventoryCostLayersFromSaleItemsInTransaction(db, items, now, originalSaleDate: originalSaleDate, restorationSourceType: restorationSourceType, restorationSourceId: restorationSourceId);

  Future<void> _closeInventoryCostLayersForPurchaseInTransaction(
    VentioDriftDatabase db,
    Purchase purchase,
    DateTime now,
  )  => _AppStoreSplitPricingCosting(this as AppStore)._closeInventoryCostLayersForPurchaseInTransaction(db, purchase, now);

  // Legacy FIFO helper retained for historical migration/regression contracts.
  // Phase 4 manufacturing uses Unified Batch directly.
  // ignore: unused_element
  Future<_ManufacturingCostResolution> _consumeManufacturingCostInTransaction(
    VentioDriftDatabase db, {
    required Product product,
    required double quantity,
    required String orderId,
    required DateTime now,
  })  => _AppStoreSplitPricingCosting(this as AppStore)._consumeManufacturingCostInTransaction(db, product: product, quantity: quantity, orderId: orderId, now: now);

  void _restoreInventoryCostLayersFromSaleItem(SaleItem item, DateTime now) => _AppStoreSplitPricingCosting(this as AppStore)._restoreInventoryCostLayersFromSaleItem(item, now);

  void _closeInventoryCostLayersForPurchase(String purchaseId, DateTime now) => _AppStoreSplitPricingCosting(this as AppStore)._closeInventoryCostLayersForPurchase(purchaseId, now);

  Future<void> addOrUpdateProduct(Product product)  => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).addOrUpdateProduct(product);

  Future<void> addOrUpdateProductsBulk(List<Product> products)  => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).addOrUpdateProductsBulk(products);

  bool isProductReferenced(String productId) => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).isProductReferenced(productId);

  Future<void> deleteProduct(String id)  => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).deleteProduct(id);

  Future<void> addOrUpdateCustomer(Customer customer)  => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).addOrUpdateCustomer(customer);

  Future<void> addOrUpdateCustomersBulk(List<Customer> customers)  => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).addOrUpdateCustomersBulk(customers);

  Future<void> deleteCustomer(String id)  => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).deleteCustomer(id);

  Future<void> addOrUpdateSupplier(Supplier supplier)  => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).addOrUpdateSupplier(supplier);

  Future<void> addOrUpdateSuppliersBulk(List<Supplier> suppliers)  => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).addOrUpdateSuppliersBulk(suppliers);

  Future<void> deleteSupplier(String id)  => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).deleteSupplier(id);

  Future<void> addOrUpdateCategory(CatalogItem item)  => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).addOrUpdateCategory(item);

  Future<void> addOrUpdateBrand(CatalogItem item)  => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).addOrUpdateBrand(item);

  Future<void> addOrUpdateUnit(CatalogItem item)  => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).addOrUpdateUnit(item);

  int productsUsingCatalogItem(String type, CatalogItem item) => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).productsUsingCatalogItem(type, item);

  Future<void> replaceAndDeleteCatalogItem({
    required String type,
    required CatalogItem item,
    CatalogItem? replacement,
  })  => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).replaceAndDeleteCatalogItem(type: type, item: item, replacement: replacement);

  Future<Expense> editPostedExpense({
    required String expenseId,
    required int expectedVersion,
    String? title,
    String? category,
    double? amount,
    double? originalAmount,
    String? originalCurrency,
    double? exchangeRateAtEntry,
    DateTime? date,
    String? notes,
  }) => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).editPostedExpense(
        expenseId: expenseId,
        expectedVersion: expectedVersion,
        title: title,
        category: category,
        amount: amount,
        originalAmount: originalAmount,
        originalCurrency: originalCurrency,
        exchangeRateAtEntry: exchangeRateAtEntry,
        date: date,
        notes: notes,
      );

  Future<void> addOrUpdateExpense(Expense expense)  => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).addOrUpdateExpense(expense);

  Future<void> postExpense(String id, {bool paidInCash = true})  => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).postExpense(id, paidInCash: paidInCash);

  Future<void> createAndPostExpensesBulk(List<Expense> expenses)  => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).createAndPostExpensesBulk(expenses);

  Future<void> deleteDraftExpense(String id)  => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).deleteDraftExpense(id);

  Future<void> cancelExpense(String id, {String reason = ''})  => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).cancelExpense(id, reason: reason);

  Future<void> permanentlyDeleteCancelledExpense(String id)  => _AppStoreSplitCatalogPartiesExpenses(this as AppStore).permanentlyDeleteCancelledExpense(id);

  int _loadPurchaseCounter() => _AppStoreSplitWarehouseCash(this as AppStore)._loadPurchaseCounter();

  Future<Warehouse> createWarehouse({
    required String name,
    String code = '',
    String location = '',
  })  => _AppStoreSplitWarehouseCash(this as AppStore).createWarehouse(name: name, code: code, location: location);

  Future<WarehouseTransferOrder> editWarehouseTransferOrder({
    required String orderId,
    required int expectedVersion,
    required String fromWarehouseId,
    required String toWarehouseId,
    required List<WarehouseTransferOrderItem> items,
    String? notes,
    DateTime? date,
  }) => _AppStoreSplitWarehouseCash(this as AppStore).editWarehouseTransferOrder(
        orderId: orderId,
        expectedVersion: expectedVersion,
        fromWarehouseId: fromWarehouseId,
        toWarehouseId: toWarehouseId,
        items: items,
        notes: notes,
        date: date,
      );

  Future<List<WarehouseTransferOrder>> recentWarehouseTransferOrders({
    int limit = 100,
  })  => _AppStoreSplitWarehouseCash(this as AppStore).recentWarehouseTransferOrders(limit: limit);

  Future<WarehouseTransferOrder> createWarehouseTransferOrder({
    required String fromWarehouseId,
    required String toWarehouseId,
    required List<WarehouseTransferOrderItem> items,
    String notes = '',
  })  => _AppStoreSplitWarehouseCash(this as AppStore).createWarehouseTransferOrder(fromWarehouseId: fromWarehouseId, toWarehouseId: toWarehouseId, items: items, notes: notes);

  Future<void> transferStock({
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required double quantity,
    String notes = '',
  })  => _AppStoreSplitWarehouseCash(this as AppStore).transferStock(productId: productId, fromWarehouseId: fromWarehouseId, toWarehouseId: toWarehouseId, quantity: quantity, notes: notes);

  /// Returns the complete trace graph for one Unified Batch, including
  /// warehouse movements, purchase/manufacturing origin and manufacturing
  /// ancestors/descendants.
  Future<Map<String, dynamic>> traceInventoryBatch(
    String batchId, {
    int maxDepth = 8,
  }) async {
    requirePermission(AppPermission.inventoryMovementsView);
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Inventory traceability requires SQLite storage.');
    }
    return InventoryTraceabilityService(sqliteDb).traceBatch(
      batchId: batchId,
      storeId: (this as AppStore).appIdentity.storeId,
      maxDepth: maxDepth,
    );
  }

  /// Phase 9 invariant audit used by the health dashboard/final release gate.
  Future<Map<String, dynamic>> verifyInventoryTraceabilityIntegrity() async {
    requirePermission(AppPermission.inventoryMovementsView);
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Inventory integrity verification requires SQLite storage.');
    }
    return InventoryTraceabilityService(sqliteDb).verifyIntegrity(
      storeId: (this as AppStore).appIdentity.storeId,
    );
  }

  Future<double> refundableSaleCashAmount(String saleId)  => _AppStoreSplitWarehouseCash(this as AppStore).refundableSaleCashAmount(saleId);

  Future<void> normalizeRefundAllocations()  => _AppStoreSplitWarehouseCash(this as AppStore).normalizeRefundAllocations();

  Future<double> refundablePurchaseCashAmount(String purchaseId)  => _AppStoreSplitWarehouseCash(this as AppStore).refundablePurchaseCashAmount(purchaseId);

  Future<double> refundSaleCash({
    required String saleId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  })  => _AppStoreSplitWarehouseCash(this as AppStore).refundSaleCash(saleId: saleId, amount: amount, notes: notes, idempotencyKey: idempotencyKey, date: date);

  Future<double> refundPurchaseCash({
    required String purchaseId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  })  => _AppStoreSplitWarehouseCash(this as AppStore).refundPurchaseCash(purchaseId: purchaseId, amount: amount, notes: notes, idempotencyKey: idempotencyKey, date: date);

  Future<double> refundableExpenseCashAmount(String expenseId)  => _AppStoreSplitWarehouseCash(this as AppStore).refundableExpenseCashAmount(expenseId);

  Future<double> refundExpenseCash({
    required String expenseId,
    double? amount,
    String notes = '',
  })  => _AppStoreSplitWarehouseCash(this as AppStore).refundExpenseCash(expenseId: expenseId, amount: amount, notes: notes);

  /// Records a customer receipt or supplier payment at account level without
  /// allocating it to a specific invoice. Cash payments must always go through
  /// the voucher + open-drawer path so the account ledger, journal and cash
  /// ledger cannot diverge.
  Future<void> settleAccountPayment({
    required String accountType,
    required String accountId,
    required String accountName,
    required double amount,
    String paymentMethod = 'Cash',
    String referenceNo = '',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  })  => _AppStoreSplitWarehouseCash(this as AppStore).settleAccountPayment(accountType: accountType, accountId: accountId, accountName: accountName, amount: amount, paymentMethod: paymentMethod, referenceNo: referenceNo, notes: notes, idempotencyKey: idempotencyKey, date: date);

  Future<ReceiptVoucher> editReceiptVoucher({
    required String voucherId,
    required int expectedVersion,
    String? customerId,
    String? customerName,
    double? amount,
    String? currency,
    String? paymentMethod,
    String? cashLocationId,
    String? cashDrawerSessionId,
    List<PaymentAllocationDraft>? allocations,
    String? notes,
    DateTime? date,
  })  => _AppStoreSplitWarehouseCash(this as AppStore).editReceiptVoucher(
        voucherId: voucherId,
        expectedVersion: expectedVersion,
        customerId: customerId,
        customerName: customerName,
        amount: amount,
        currency: currency,
        paymentMethod: paymentMethod,
        cashLocationId: cashLocationId,
        cashDrawerSessionId: cashDrawerSessionId,
        allocations: allocations,
        notes: notes,
        date: date,
      );

  Future<PaymentVoucher> editPaymentVoucher({
    required String voucherId,
    required int expectedVersion,
    String? supplierId,
    String? supplierName,
    double? amount,
    String? currency,
    String? paymentMethod,
    String? cashLocationId,
    String? cashDrawerSessionId,
    List<PaymentAllocationDraft>? allocations,
    String? notes,
    DateTime? date,
  })  => _AppStoreSplitWarehouseCash(this as AppStore).editPaymentVoucher(
        voucherId: voucherId,
        expectedVersion: expectedVersion,
        supplierId: supplierId,
        supplierName: supplierName,
        amount: amount,
        currency: currency,
        paymentMethod: paymentMethod,
        cashLocationId: cashLocationId,
        cashDrawerSessionId: cashDrawerSessionId,
        allocations: allocations,
        notes: notes,
        date: date,
      );

  Future<Sale> settleSalePayment({
    required String saleId,
    required double amount,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  })  => _AppStoreSplitWarehouseCash(this as AppStore).settleSalePayment(saleId: saleId, amount: amount, paymentMethod: paymentMethod, notes: notes, idempotencyKey: idempotencyKey, date: date);

  Future<Sale> _settleSalePaymentInternal({
    required String saleId,
    required double amount,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  })  => _AppStoreSplitWarehouseCash(this as AppStore)._settleSalePaymentInternal(saleId: saleId, amount: amount, paymentMethod: paymentMethod, notes: notes, idempotencyKey: idempotencyKey, date: date);

  Future<Purchase> settlePurchasePayment({
    required String purchaseId,
    required double amount,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  })  => _AppStoreSplitWarehouseCash(this as AppStore).settlePurchasePayment(purchaseId: purchaseId, amount: amount, paymentMethod: paymentMethod, notes: notes, idempotencyKey: idempotencyKey, date: date);

  PurchaseItem _copyPurchaseItemWith({
    required PurchaseItem item,
    String? lineId,
    List<BatchAllocation>? batchAllocations,
  }) => _AppStoreSplitWarehouseCash(this as AppStore)._copyPurchaseItemWith(item: item, lineId: lineId, batchAllocations: batchAllocations);

  Future<double> _unifiedOpeningCostForProductInTransaction(
    dynamic sqliteDb, {
    required Product product,
    required String warehouseId,
  })  => _AppStoreSplitPurchases(this as AppStore)._unifiedOpeningCostForProductInTransaction(sqliteDb, product: product, warehouseId: warehouseId);

  Future<void> _ensureUnifiedBatchCutoverForProductInTransaction(
    dynamic sqliteDb, {
    required Product product,
    required String warehouseId,
    required DateTime at,
  })  => _AppStoreSplitPurchases(this as AppStore)._ensureUnifiedBatchCutoverForProductInTransaction(sqliteDb, product: product, warehouseId: warehouseId, at: at);

  Future<void> _assertUnifiedBatchMovementBalancesInTransaction(
    BatchInventoryService batchService,
    Iterable<StockMovement> movements,
  )  => _AppStoreSplitPurchases(this as AppStore)._assertUnifiedBatchMovementBalancesInTransaction(batchService, movements);

  Future<Purchase> createPurchase({
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    bool receiveNow = true,
    String note = '',
    String paymentStatus = 'paid',
    String paymentMethod = 'Cash',
    double? paidAmount,
    String warehouseId = '',
    String warehouseName = '',
  })  => _AppStoreSplitPurchases(this as AppStore).createPurchase(supplierId: supplierId, supplierName: supplierName, items: items, receiveNow: receiveNow, note: note, paymentStatus: paymentStatus, paymentMethod: paymentMethod, paidAmount: paidAmount, warehouseId: warehouseId, warehouseName: warehouseName);

  /// Updates a draft directly, or atomically reverses/reposts a received
  /// purchase when none of its inventory batches has a downstream movement.
  /// The version check prevents silently overwriting a concurrent change.
  Future<Purchase> updatePurchaseDraft({
    required String purchaseId,
    required int expectedVersion,
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    String paymentStatus = 'paid',
    String paymentMethod = 'Cash',
    double? paidAmount,
    String warehouseId = '',
    String warehouseName = '',
  })  => _AppStoreSplitPurchases(this as AppStore).updatePurchaseDraft(purchaseId: purchaseId, expectedVersion: expectedVersion, supplierId: supplierId, supplierName: supplierName, items: items, paymentStatus: paymentStatus, paymentMethod: paymentMethod, paidAmount: paidAmount, warehouseId: warehouseId, warehouseName: warehouseName);

  Future<void> receivePurchase(
    String id, {
    bool settleInitialPayment = true,
    bool postAccounting = true,
    Map<int, List<BatchAllocation>> batchAllocationsByLine =
        const <int, List<BatchAllocation>>{},
  })  => _AppStoreSplitPurchases(this as AppStore).receivePurchase(id, settleInitialPayment: settleInitialPayment, postAccounting: postAccounting, batchAllocationsByLine: batchAllocationsByLine);

  Future<void> deleteDraftPurchase(String id)  => _AppStoreSplitPurchases(this as AppStore).deleteDraftPurchase(id);

  Future<void> permanentlyDeleteCancelledPurchase(String id)  => _AppStoreSplitPurchases(this as AppStore).permanentlyDeleteCancelledPurchase(id);

  Future<void> _requirePostedJournalInTransaction(
    dynamic sqliteDb, {
    required String referenceType,
    required String referenceId,
    bool includePurchaseEditFamily = false,
    bool includeSaleEditFamily = false,
    required String failureMessage,
  })  => _AppStoreSplitPurchases(this as AppStore)._requirePostedJournalInTransaction(sqliteDb, referenceType: referenceType, referenceId: referenceId, includePurchaseEditFamily: includePurchaseEditFamily, includeSaleEditFamily: includeSaleEditFamily, failureMessage: failureMessage);

  Future<void> _requireNoActiveJournalInTransaction(
    dynamic sqliteDb, {
    required String referenceType,
    required String referenceId,
    bool includePurchaseEditFamily = false,
    bool includeSaleEditFamily = false,
    required String failureMessage,
  })  => _AppStoreSplitPurchases(this as AppStore)._requireNoActiveJournalInTransaction(sqliteDb, referenceType: referenceType, referenceId: referenceId, includePurchaseEditFamily: includePurchaseEditFamily, includeSaleEditFamily: includeSaleEditFamily, failureMessage: failureMessage);

  Future<Purchase> editPurchaseReturn({
    required String purchaseId,
    required int expectedVersion,
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    String warehouseId = '',
    String warehouseName = '',
  }) => _AppStoreSplitPurchases(this as AppStore).editPurchaseReturn(
        purchaseId: purchaseId,
        expectedVersion: expectedVersion,
        supplierId: supplierId,
        supplierName: supplierName,
        items: items,
        warehouseId: warehouseId,
        warehouseName: warehouseName,
      );

  Future<void> returnPurchase(
    String id, {
    bool reverseStock = true,
    String reason = '',
    bool recordSupplierReturnLedger = true,
  })  => _AppStoreSplitPurchases(this as AppStore).returnPurchase(id, reverseStock: reverseStock, reason: reason, recordSupplierReturnLedger: recordSupplierReturnLedger);

  Future<void> cancelPurchase(
    String id, {
    bool reverseStock = true,
    String reason = '',
  })  => _AppStoreSplitPurchases(this as AppStore).cancelPurchase(id, reverseStock: reverseStock, reason: reason);

  int movementCountAfterInventoryLine(InventoryCountLine line) => _AppStoreSplitInventory(this as AppStore).movementCountAfterInventoryLine(line);

  Future<InventoryCountSession> createInventoryCountSession({
    String notes = '',
    String warehouseId = '',
    String warehouseName = '',
  })  => _AppStoreSplitInventory(this as AppStore).createInventoryCountSession(notes: notes, warehouseId: warehouseId, warehouseName: warehouseName);

  Future<void> countInventoryLine({
    required String sessionId,
    required String productId,
    required double countedQty,
    String note = '',
  })  => _AppStoreSplitInventory(this as AppStore).countInventoryLine(sessionId: sessionId, productId: productId, countedQty: countedQty, note: note);

  Future<void> resetInventoryCountLine({
    required String sessionId,
    required String productId,
  })  => _AppStoreSplitInventory(this as AppStore).resetInventoryCountLine(sessionId: sessionId, productId: productId);

  Future<void> approveInventoryCount(String sessionId)  => _AppStoreSplitInventory(this as AppStore).approveInventoryCount(sessionId);

  Future<void> reverseInventoryCount(
    String sessionId, {
    String reason = '',
  })  => _AppStoreSplitInventory(this as AppStore).reverseInventoryCount(sessionId, reason: reason);

  Future<void> cancelInventoryCount(String sessionId)  => _AppStoreSplitInventory(this as AppStore).cancelInventoryCount(sessionId);

  Future<void> reviewAutoCorrection(
    String movementId, {
    String note = '',
  })  => _AppStoreSplitInventory(this as AppStore).reviewAutoCorrection(movementId, note: note);

  Future<void> setExpiryBatchStatus(String batchId, String status)  => _AppStoreSplitInventory(this as AppStore).setExpiryBatchStatus(batchId, status);

  void _recordInventoryBatchSyncChanges({
    required Product product,
    required List<BatchAllocation> allocations,
    required String sourceType,
    required String sourceId,
    required DateTime now,
    double unitCost = 0,
    String sourceLineId = '',
    List<String> sourceLineIds = const <String>[],
    DateTime? receivedAt,
  }) => _AppStoreSplitInventory(this as AppStore)._recordInventoryBatchSyncChanges(product: product, allocations: allocations, sourceType: sourceType, sourceId: sourceId, now: now, unitCost: unitCost, sourceLineId: sourceLineId, sourceLineIds: sourceLineIds, receivedAt: receivedAt);

  Future<void> adjustExpiryBatchStock({
    required String productId,
    required String warehouseId,
    required String batchId,
    required double quantityDelta,
    required String reason,
    String adjustmentCategory = 'other',
  })  => _AppStoreSplitInventory(this as AppStore).adjustExpiryBatchStock(productId: productId, warehouseId: warehouseId, batchId: batchId, quantityDelta: quantityDelta, reason: reason, adjustmentCategory: adjustmentCategory);

  /// Reverses a posted expiry/batch adjustment using the movement's immutable
  /// historical quantity and unit cost.  This deliberately never re-prices
  /// the batch from today's product cost.
  Future<void> reverseExpiryBatchAdjustment(
    String movementId, {
    String reason = '',
  })  => _AppStoreSplitInventory(this as AppStore).reverseExpiryBatchAdjustment(movementId, reason: reason);

  Future<int> manualStockAdjustmentVersion(String operationReferenceId)
      => _AppStoreSplitInventory(this as AppStore)
          .manualStockAdjustmentVersion(operationReferenceId);

  Future<void> editStockAdjustment({
    required String operationReferenceId,
    required int expectedVersion,
    required double quantityDelta,
    required String reason,
    String adjustmentCategory = 'other',
    String notes = '',
    String evidenceRef = '',
    List<BatchAllocation> batchAllocations = const <BatchAllocation>[],
  }) => _AppStoreSplitInventory(this as AppStore).editStockAdjustment(
        operationReferenceId: operationReferenceId,
        expectedVersion: expectedVersion,
        quantityDelta: quantityDelta,
        reason: reason,
        adjustmentCategory: adjustmentCategory,
        notes: notes,
        evidenceRef: evidenceRef,
        batchAllocations: batchAllocations,
      );

  Future<void> adjustStock({
    required String productId,
    required String warehouseId,
    required double quantityDelta,
    required String reason,
    String adjustmentCategory = 'other',
    String notes = '',
    String evidenceRef = '',
    List<BatchAllocation> batchAllocations = const <BatchAllocation>[],
    String operationReferenceId = '',
  })  => _AppStoreSplitInventory(this as AppStore).adjustStock(productId: productId, warehouseId: warehouseId, quantityDelta: quantityDelta, reason: reason, adjustmentCategory: adjustmentCategory, notes: notes, evidenceRef: evidenceRef, batchAllocations: batchAllocations, operationReferenceId: operationReferenceId);

  Future<void> recordWasteLoss({
    required String productId,
    required String warehouseId,
    required double quantity,
    required String reason,
    String adjustmentCategory = 'other',
    String notes = '',
  })  => _AppStoreSplitInventory(this as AppStore).recordWasteLoss(productId: productId, warehouseId: warehouseId, quantity: quantity, reason: reason, adjustmentCategory: adjustmentCategory, notes: notes);

  /// Reverses every batch movement created by one waste operation atomically.
  Future<void> reverseWasteLossGroup(String movementId)  => _AppStoreSplitInventory(this as AppStore).reverseWasteLossGroup(movementId);

  Future<void> deleteWasteLoss(String movementId)  => _AppStoreSplitInventory(this as AppStore).deleteWasteLoss(movementId);

  void _applyPurchaseStock(Purchase purchase, DateTime now) => _AppStoreSplitInventory(this as AppStore)._applyPurchaseStock(purchase, now);

  void _addStockMovement(StockMovement movement, {bool recordSync = false}) => _AppStoreSplitInventory(this as AppStore)._addStockMovement(movement, recordSync: recordSync);

  Future<void> _reconcileInventoryAccountsAfterBomChange(
    BillOfMaterials bom, {
    VentioDriftDatabase? database,
    bool withinExistingTransaction = false,
  })  => _AppStoreSplitInventory(this as AppStore)._reconcileInventoryAccountsAfterBomChange(bom, database: database, withinExistingTransaction: withinExistingTransaction);

  Future<BillOfMaterials> createBillOfMaterials({
    required String name,
    required String outputProductId,
    required double outputQuantity,
    required List<BillOfMaterialsLine> components,
    String notes = '',
  })  => _AppStoreSplitManufacturing(this as AppStore).createBillOfMaterials(name: name, outputProductId: outputProductId, outputQuantity: outputQuantity, components: components, notes: notes);

  Future<BillOfMaterials> updateBillOfMaterials({
    required String id,
    required String name,
    required String outputProductId,
    required double outputQuantity,
    required List<BillOfMaterialsLine> components,
    String notes = '',
  })  => _AppStoreSplitManufacturing(this as AppStore).updateBillOfMaterials(id: id, name: name, outputProductId: outputProductId, outputQuantity: outputQuantity, components: components, notes: notes);

  Future<void> deleteBillOfMaterials(String id)  => _AppStoreSplitManufacturing(this as AppStore).deleteBillOfMaterials(id);

  Future<void> deleteManufacturingOrder(String id)  => _AppStoreSplitManufacturing(this as AppStore).deleteManufacturingOrder(id);

  Future<ManufacturingOrder> updateManufacturingOrder({
    required String id,
    required String bomId,
    required double quantity,
    required String rawMaterialsWarehouseId,
    required String rawMaterialsWarehouseName,
    required String finishedGoodsWarehouseId,
    required String finishedGoodsWarehouseName,
    String notes = '',
  })  => _AppStoreSplitManufacturing(this as AppStore).updateManufacturingOrder(id: id, bomId: bomId, quantity: quantity, rawMaterialsWarehouseId: rawMaterialsWarehouseId, rawMaterialsWarehouseName: rawMaterialsWarehouseName, finishedGoodsWarehouseId: finishedGoodsWarehouseId, finishedGoodsWarehouseName: finishedGoodsWarehouseName, notes: notes);

  Future<ManufacturingOrder> startManufacturingOrder({
    required String bomId,
    required double quantity,
    String rawMaterialsWarehouseId = '',
    String rawMaterialsWarehouseName = '',
    String finishedGoodsWarehouseId = '',
    String finishedGoodsWarehouseName = '',
    String notes = '',
  })  => _AppStoreSplitManufacturing(this as AppStore).startManufacturingOrder(bomId: bomId, quantity: quantity, rawMaterialsWarehouseId: rawMaterialsWarehouseId, rawMaterialsWarehouseName: rawMaterialsWarehouseName, finishedGoodsWarehouseId: finishedGoodsWarehouseId, finishedGoodsWarehouseName: finishedGoodsWarehouseName, notes: notes);

  Future<ManufacturingOrder> finishManufacturingOrder({
    required String orderId,
    required double actualQuantity,
    List<BatchAllocation> outputBatchAllocations = const <BatchAllocation>[],
    Map<String, double> actualConsumedQuantities = const <String, double>{},
    Map<String, double> wasteQuantities = const <String, double>{},
    Map<String, String> wasteReasons = const <String, String>{},
  })  => _AppStoreSplitManufacturing(this as AppStore).finishManufacturingOrder(orderId: orderId, actualQuantity: actualQuantity, outputBatchAllocations: outputBatchAllocations, actualConsumedQuantities: actualConsumedQuantities, wasteQuantities: wasteQuantities, wasteReasons: wasteReasons);

  Future<ManufacturingOrder> completeManufacturingOrder({
    required String bomId,
    required double quantity,
    String rawMaterialsWarehouseId = '',
    String rawMaterialsWarehouseName = '',
    String finishedGoodsWarehouseId = '',
    String finishedGoodsWarehouseName = '',
    String notes = '',
    List<BatchAllocation> outputBatchAllocations = const <BatchAllocation>[],
    Map<String, double> actualConsumedQuantities = const <String, double>{},
    Map<String, double> wasteQuantities = const <String, double>{},
    Map<String, String> wasteReasons = const <String, String>{},
    String existingOrderId = '',
  })  => _AppStoreSplitManufacturing(this as AppStore).completeManufacturingOrder(bomId: bomId, quantity: quantity, rawMaterialsWarehouseId: rawMaterialsWarehouseId, rawMaterialsWarehouseName: rawMaterialsWarehouseName, finishedGoodsWarehouseId: finishedGoodsWarehouseId, finishedGoodsWarehouseName: finishedGoodsWarehouseName, notes: notes, outputBatchAllocations: outputBatchAllocations, actualConsumedQuantities: actualConsumedQuantities, wasteQuantities: wasteQuantities, wasteReasons: wasteReasons, existingOrderId: existingOrderId);

  Future<ManufacturingOrder> editCompletedManufacturingOrder({
    required String orderId,
    required int expectedVersion,
    required String bomId,
    required double quantity,
    required String rawMaterialsWarehouseId,
    required String rawMaterialsWarehouseName,
    required String finishedGoodsWarehouseId,
    required String finishedGoodsWarehouseName,
    String notes = '',
    List<BatchAllocation> outputBatchAllocations = const <BatchAllocation>[],
    Map<String, double> actualConsumedQuantities = const <String, double>{},
    Map<String, double> wasteQuantities = const <String, double>{},
    Map<String, String> wasteReasons = const <String, String>{},
  }) => _AppStoreSplitManufacturing(this as AppStore)
      .editCompletedManufacturingOrder(
        orderId: orderId,
        expectedVersion: expectedVersion,
        bomId: bomId,
        quantity: quantity,
        rawMaterialsWarehouseId: rawMaterialsWarehouseId,
        rawMaterialsWarehouseName: rawMaterialsWarehouseName,
        finishedGoodsWarehouseId: finishedGoodsWarehouseId,
        finishedGoodsWarehouseName: finishedGoodsWarehouseName,
        notes: notes,
        outputBatchAllocations: outputBatchAllocations,
        actualConsumedQuantities: actualConsumedQuantities,
        wasteQuantities: wasteQuantities,
        wasteReasons: wasteReasons,
      );

  /// Reverses a completed manufacturing order without deleting history.
  /// A conservative downstream-movement guard prevents returning raw material
  /// after any of the produced finished goods have subsequently moved out.
  Future<ManufacturingOrder> reverseManufacturingOrder({
    required String orderId,
    required String reason,
  })  => _AppStoreSplitManufacturing(this as AppStore).reverseManufacturingOrder(orderId: orderId, reason: reason);

  Future<SaleQuotation> createSaleQuotation({
    required String customerName,
    String customerId = '',
    required List<SaleItem> items,
    double discount = 0,
    String invoiceCurrency = 'USD',
    String note = '',
    DateTime? validUntil,
  })  => _AppStoreSplitSalesReturns(this as AppStore).createSaleQuotation(customerName: customerName, customerId: customerId, items: items, discount: discount, invoiceCurrency: invoiceCurrency, note: note, validUntil: validUntil);

  Future<Sale> convertSaleQuotationToSale(
    String quotationId, {
    String paymentMethod = 'Cash',
    String paymentStatus = 'paid',
  })  => _AppStoreSplitSalesReturns(this as AppStore).convertSaleQuotationToSale(quotationId, paymentMethod: paymentMethod, paymentStatus: paymentStatus);

  Future<void> deleteSaleQuotation(String id)  => _AppStoreSplitSalesReturns(this as AppStore).deleteSaleQuotation(id);

  DeliveryNote? deliveryNoteForSale(String saleId) => _AppStoreSplitSalesReturns(this as AppStore).deliveryNoteForSale(saleId);

  Future<DeliveryNote> createDeliveryNoteFromSale(
    String saleId, {
    String note = '',
  })  => _AppStoreSplitSalesReturns(this as AppStore).createDeliveryNoteFromSale(saleId, note: note);

  Future<void> markDeliveryNoteDelivered(String id)  => _AppStoreSplitSalesReturns(this as AppStore).markDeliveryNoteDelivered(id);

  Future<void> deleteDeliveryNote(String id)  => _AppStoreSplitSalesReturns(this as AppStore).deleteDeliveryNote(id);

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
  })  => _AppStoreSplitSalesReturns(this as AppStore).createSale(customerName: customerName, customerId: customerId, items: items, discount: discount, originalDiscount: originalDiscount, discountCurrency: discountCurrency, discountExchangeRateAtEntry: discountExchangeRateAtEntry, paymentMethod: paymentMethod, paymentStatus: paymentStatus, invoiceCurrency: invoiceCurrency, paymentCurrency: paymentCurrency, exchangeRateAtPayment: exchangeRateAtPayment, paidAmount: paidAmount, cashReceivedAmount: cashReceivedAmount, paidAmountInPaymentCurrency: paidAmountInPaymentCurrency, cashReceivedAmountInPaymentCurrency: cashReceivedAmountInPaymentCurrency, warehouseId: warehouseId, warehouseName: warehouseName);

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
  })  => _AppStoreSplitSalesReturns(this as AppStore).editPostedSale(
        saleId: saleId,
        expectedVersion: expectedVersion,
        customerName: customerName,
        customerId: customerId,
        items: items,
        discount: discount,
        originalDiscount: originalDiscount,
        discountCurrency: discountCurrency,
        discountExchangeRateAtEntry: discountExchangeRateAtEntry,
        warehouseId: warehouseId,
        warehouseName: warehouseName,
      );

  Future<CreditNote> returnSale(
    String id, {
    bool restoreStock = true,
    Map<String, double>? returnedQuantities,
  })  => _AppStoreSplitSalesReturns(this as AppStore).returnSale(id, restoreStock: restoreStock, returnedQuantities: returnedQuantities);

  Future<CreditNote> editSaleReturn({
    required String creditNoteId,
    required int expectedVersion,
    required Map<String, double> returnedQuantities,
  }) => _AppStoreSplitSalesReturns(this as AppStore).editSaleReturn(
        creditNoteId: creditNoteId,
        expectedVersion: expectedVersion,
        returnedQuantities: returnedQuantities,
      );

  Future<void> cancelSale(
    String id, {
    String status = 'Cancelled',
    bool restoreStock = true,
  })  => _AppStoreSplitSalesReturns(this as AppStore).cancelSale(id, status: status, restoreStock: restoreStock);

  @Deprecated(
    'Use cancelSale instead. Invoices are cancelled, not physically deleted.',
  )
  Future<void> deleteSale(String id, {bool restoreStock = true})  => _AppStoreSplitSalesReturns(this as AppStore).deleteSale(id, restoreStock: restoreStock);

  double estimateProfit() => _AppStoreSplitSalesReturns(this as AppStore).estimateProfit();

  Future<void> rebuildProductStockCache(String productId)  => _AppStoreSplitBackupRecovery(this as AppStore).rebuildProductStockCache(productId);

  Future<void> rebuildAllProductStockCaches()  => _AppStoreSplitBackupRecovery(this as AppStore).rebuildAllProductStockCaches();

  void _applyProductStockCompatibilityDeltas(
    Iterable<StockMovement> movements,
  ) => _AppStoreSplitBackupRecovery(this as AppStore)._applyProductStockCompatibilityDeltas(movements);

  Future<void> _refreshProductStockCompatibilityCache(
    Iterable<String> productIds,
  )  => _AppStoreSplitBackupRecovery(this as AppStore)._refreshProductStockCompatibilityCache(productIds);

  /// The single snapshot builder used by Direct, LAN, restore, repair, and
  /// pairing flows. The same catalog, manifest, payload shape, and chunk
  /// structure are used by both LAN and Direct transports.
  Future<List<Map<String, dynamic>>> exportUnifiedSnapshotChunks({
    String kind = 'full_store',
    Set<String>? sectionIds,
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  })  => _AppStoreSplitBackupRecovery(this as AppStore).exportUnifiedSnapshotChunks(kind: kind, sectionIds: sectionIds, maxItemsPerChunk: maxItemsPerChunk, maxEncodedPayloadBytes: maxEncodedPayloadBytes);

  Map<String, dynamic> unifiedSnapshotPayloadFromChunks(
    List<Map<String, dynamic>> chunks,
  ) => _AppStoreSplitBackupRecovery(this as AppStore).unifiedSnapshotPayloadFromChunks(chunks);

  Future<List<Map<String, dynamic>>>
      exportDirectLoginBootstrapSnapshotChunks()  => _AppStoreSplitBackupRecovery(this as AppStore).exportDirectLoginBootstrapSnapshotChunks();

  Future<List<Map<String, dynamic>>> exportDirectBootstrapSnapshotChunks({
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  })  => _AppStoreSplitBackupRecovery(this as AppStore).exportDirectBootstrapSnapshotChunks(maxItemsPerChunk: maxItemsPerChunk, maxEncodedPayloadBytes: maxEncodedPayloadBytes);

  String exportRecoveryFileJson({String controlPlaneApiUrl = ''}) => _AppStoreSplitBackupRecovery(this as AppStore).exportRecoveryFileJson(controlPlaneApiUrl: controlPlaneApiUrl);

  Map<String, String> parseRecoveryFileJson(String rawJson) => _AppStoreSplitBackupRecovery(this as AppStore).parseRecoveryFileJson(rawJson);

  Future<String> exportBackupJson()  => _AppStoreSplitBackupRecovery(this as AppStore).exportBackupJson();

  String currentHostSnapshotGeneration() => _AppStoreSplitBackupRecovery(this as AppStore).currentHostSnapshotGeneration();

  String currentHostRestoreCommandId() => _AppStoreSplitBackupRecovery(this as AppStore).currentHostRestoreCommandId();

  Future<Map<String, dynamic>> exportUnifiedSnapshotEnvelope({
    String kind = 'full_store',
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  })  => _AppStoreSplitBackupRecovery(this as AppStore).exportUnifiedSnapshotEnvelope(kind: kind, maxItemsPerChunk: maxItemsPerChunk, maxEncodedPayloadBytes: maxEncodedPayloadBytes);

  Future<String> exportSyncSnapshotJson()  => _AppStoreSplitBackupRecovery(this as AppStore).exportSyncSnapshotJson();

  DateTime syncSnapshotGeneratedAtFromJson(String rawJson) => _AppStoreSplitBackupRecovery(this as AppStore).syncSnapshotGeneratedAtFromJson(rawJson);

  int syncSnapshotGeneratedSequenceFromJson(String rawJson) => _AppStoreSplitBackupRecovery(this as AppStore).syncSnapshotGeneratedSequenceFromJson(rawJson);

  String exportSyncChangesJson({
    DateTime? since,
    int? sinceSequence,
    int? maxEncodedPayloadBytes,
  }) => _AppStoreSplitBackupRecovery(this as AppStore).exportSyncChangesJson(since: since, sinceSequence: sinceSequence, maxEncodedPayloadBytes: maxEncodedPayloadBytes);

  List<int> _deriveBackupKey(String password, String salt) => _AppStoreSplitBackupRecovery(this as AppStore)._deriveBackupKey(password, salt);

  List<int> _deriveBackupKeyV2(String password, String salt) => _AppStoreSplitBackupRecovery(this as AppStore)._deriveBackupKeyV2(password, salt);

  String _generateNonce() => _AppStoreSplitBackupRecovery(this as AppStore)._generateNonce();

  List<int> _aesGcmEncrypt(List<int> plain, List<int> key, List<int> nonce) => _AppStoreSplitBackupRecovery(this as AppStore)._aesGcmEncrypt(plain, key, nonce);

  List<int> _aesGcmDecrypt(
    List<int> encrypted,
    List<int> key,
    List<int> nonce,
  ) => _AppStoreSplitBackupRecovery(this as AppStore)._aesGcmDecrypt(encrypted, key, nonce);

  List<int> _deriveBackupKeyV1(String password, String salt) => _AppStoreSplitBackupRecovery(this as AppStore)._deriveBackupKeyV1(password, salt);

  List<int> _xorWithSha256Stream(List<int> input, List<int> key, String nonce) => _AppStoreSplitBackupRecovery(this as AppStore)._xorWithSha256Stream(input, key, nonce);

  bool _constantTimeEquals(List<int> a, List<int> b) => _AppStoreSplitBackupRecovery(this as AppStore)._constantTimeEquals(a, b);

  Future<void> importBackupJson(String rawJson,
      {Set<String>? selectedSectionIds})  => _AppStoreSplitBackupRecovery(this as AppStore).importBackupJson(rawJson, selectedSectionIds: selectedSectionIds);

  int _readVersion(dynamic item) => _AppStoreSplitBackupRecovery(this as AppStore)._readVersion(item);

  DateTime _readUpdatedAt(dynamic item) => _AppStoreSplitBackupRecovery(this as AppStore)._readUpdatedAt(item);

  void _replaceUsersWithoutDuplicates(List<AppUser> incoming) => _AppStoreSplitBackupRecovery(this as AppStore)._replaceUsersWithoutDuplicates(incoming);

  Future<void> mergeBackupJson(
    String rawJson, {
    bool markSynced = false,
  })  => _AppStoreSplitBackupRecovery(this as AppStore).mergeBackupJson(rawJson, markSynced: markSynced);

  Future<void> markAllSyncChangesSynced()  => _AppStoreSplitSyncApply(this as AppStore).markAllSyncChangesSynced();

  Future<void> importSyncSnapshotJson(String rawJson)  => _AppStoreSplitSyncApply(this as AppStore).importSyncSnapshotJson(rawJson);

  /// Cursor-aware sync log compaction.
  ///
  /// Keeps the latest [keepRecentSyncedChanges] synced authoritative changes and
  /// removes older synced queue rows only when they are at/below the active peer
  /// ACK floor. If a Client later asks for a sequence older than the earliest
  /// retained event, [exportSyncChangesJson] returns needsSnapshot=true so the
  /// Client rebuilds from a full Host snapshot instead of applying a partial log.
  Future<Map<String, int>> compactSyncedSyncHistoryForDiagnostics({
    int keepRecentSyncedChanges = AppStore._syncMaintenanceKeepRecentChanges,
  })  => _AppStoreSplitSyncApply(this as AppStore).compactSyncedSyncHistoryForDiagnostics(keepRecentSyncedChanges: keepRecentSyncedChanges);

  Future<Map<String, int>> compactSyncedSyncHistoryForMaintenance({
    int keepRecentSyncedChanges = AppStore._syncMaintenanceKeepRecentChanges,
    int minChangesBeforeCompact = AppStore._syncMaintenanceMinChangesBeforeCompact,
  })  => _AppStoreSplitSyncApply(this as AppStore).compactSyncedSyncHistoryForMaintenance(keepRecentSyncedChanges: keepRecentSyncedChanges, minChangesBeforeCompact: minChangesBeforeCompact);

  /// Client-side sync log compaction. Clients do not own the ACK floor for
  /// other peers, so they compact only their local, already-synced history up
  /// to the latest authoritative sequence they have applied. The Host remains
  /// responsible for serving old events or returning needsSnapshot=true.
  Future<Map<String, int>> compactClientSyncedSyncHistoryForMaintenance({
    int keepRecentSyncedChanges = AppStore._syncMaintenanceKeepRecentChanges,
  })  => _AppStoreSplitSyncApply(this as AppStore).compactClientSyncedSyncHistoryForMaintenance(keepRecentSyncedChanges: keepRecentSyncedChanges);

  Future<void> applyRemoteSyncChanges(
    List<SyncChange> incoming, {
    bool markAppliedAsSynced = false,
    bool mirrorToDirect = false,
  })  => _AppStoreSplitSyncApply(this as AppStore).applyRemoteSyncChanges(incoming, markAppliedAsSynced: markAppliedAsSynced, mirrorToDirect: mirrorToDirect);

  List<DataConflict> _detectDataConflicts() => _AppStoreSplitSyncApply(this as AppStore)._detectDataConflicts();

  Future<void> assertRemoteSyncChangesApplied(List<SyncChange> changes)  => _AppStoreSplitSyncApply(this as AppStore).assertRemoteSyncChangesApplied(changes);

  Future<void> markSyncChangesSubmittedByIds(Iterable<String> ids)  => _AppStoreSplitSyncApply(this as AppStore).markSyncChangesSubmittedByIds(ids);

  Future<void> markSyncChangesSyncedByIds(Iterable<String> ids)  => _AppStoreSplitSyncApply(this as AppStore).markSyncChangesSyncedByIds(ids);

  /// LAN-only Hosts are already the authority for their local changes. Older
  /// builds incorrectly queued those changes toward `host`, where no client
  /// push loop runs, leaving a permanent pending row on the Host.
  Future<void> settleLegacyLanHostQueue()  => _AppStoreSplitSyncApply(this as AppStore).settleLegacyLanHostQueue();

  /// Marks Host-authored events as complete only after every active peer has
  /// acknowledged the corresponding Host sequence. Direct Host events are
  /// intentionally queued with target="host" so the same queue can be used by
  /// the legacy sync paths, but a Host never runs a Client push loop for that
  /// target. Without this reconciliation those rows remain pending forever
  /// even though the events are already in the authoritative Host timeline.
  Future<int> settleHostQueueThroughPeerAck()  => _AppStoreSplitSyncApply(this as AppStore).settleHostQueueThroughPeerAck();

  Future<void> markSyncQueueChangesInProgress(
    Iterable<String> changeIds,
  )  => _AppStoreSplitSyncApply(this as AppStore).markSyncQueueChangesInProgress(changeIds);

  Future<void> markSyncChangesRejectedByIds(
    Map<String, String> rejected,
  )  => _AppStoreSplitSyncApply(this as AppStore).markSyncChangesRejectedByIds(rejected);

  Future<void> markSyncQueueChangesFailed(
    Iterable<String> changeIds,
    String error,
  )  => _AppStoreSplitSyncApply(this as AppStore).markSyncQueueChangesFailed(changeIds, error);

  Future<void> retryFailedSyncQueue({String? target})  => _AppStoreSplitSyncApply(this as AppStore).retryFailedSyncQueue(target: target);

  Future<void> recoverStaleInProgressSyncQueue({
    String? target,
    Duration staleAfter = const Duration(seconds: 45),
  })  => _AppStoreSplitSyncApply(this as AppStore).recoverStaleInProgressSyncQueue(target: target, staleAfter: staleAfter);

  Future<void> recoverSubmittedSyncQueue({String? target})  => _AppStoreSplitSyncApply(this as AppStore).recoverSubmittedSyncQueue(target: target);

  Future<void> markSyncQueueItemFailed(String queueItemId, String error)  => _AppStoreSplitSyncApply(this as AppStore).markSyncQueueItemFailed(queueItemId, error);

  /// Finishes Ventio-owned buffered work before the SQLite connection is
  /// checkpointed and closed during desktop shutdown.
  Future<void> prepareForShutdown()  => _AppStoreSplitSyncApply(this as AppStore).prepareForShutdown();
}
