part of 'app_store.dart';

/// Internal forwarding operations used by AppStore's split library modules.
///
/// The business implementation continues to live in focused split modules;
/// these members stay library-private and own no mutable state. External
/// callers use the typed domain ports on AppStore.
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

  Future<void> _ensureHeavyDataLoaded({bool failOnError = false}) =>
      _AppStoreSplitCoreLoading(this as AppStore)
          .ensureHeavyDataLoaded(failOnError: failOnError);

  Future<void> _ensureCreditNotesLoaded() =>
      _AppStoreSplitCoreLoading(this as AppStore).ensureCreditNotesLoaded();

  Future<CreditNote> _issueCreditNote({
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

  ProductCost _productCostFor(String productId) =>
      _AppStoreSplitCoreLoading(this as AppStore).productCostFor(productId);

  PriceList get _defaultPriceList =>
      _AppStoreSplitCoreLoading(this as AppStore).defaultPriceList;

  ProductPrice? _productPriceFor(String productId, String priceListId,
          {String unitId = 'base'}) =>
      _AppStoreSplitCoreLoading(this as AppStore)
          .productPriceFor(productId, priceListId, unitId: unitId);

  InventoryCountSession? get _activeInventoryCountSession =>
      _AppStoreSplitCoreLoading(this as AppStore).activeInventoryCountSession;

  Warehouse _resolveWarehouseForSale({String warehouseId = ''}) =>
      _AppStoreSplitCoreLoading(this as AppStore)
          .resolveWarehouseForSale(warehouseId: warehouseId);

  Warehouse _resolveWarehouseForPurchase({String warehouseId = ''}) =>
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

  double _stockForWarehouse(String productId, String warehouseId) =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore)
          .stockForWarehouse(productId, warehouseId);

  Future<double> _warehouseStockFromSqlite(
    String productId, {
    String warehouseId = '',
  }) =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore)
          .warehouseStockFromSqlite(productId, warehouseId: warehouseId);

  Future<double> _totalWarehouseStockFromSqlite(String productId) =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore)
          .totalWarehouseStockFromSqlite(productId);

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

  List<SyncQueueItem> get _pendingSyncQueue =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore).pendingSyncQueue;

  List<SyncChange> get _pendingSyncChanges =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore).pendingSyncChanges;

  String get _activeClientSyncTarget =>
      _AppStoreSplitCoreLoadingPart2(this as AppStore).activeClientSyncTarget;

  bool get _hasOnlyLegacyDefaultAdminUser =>
      _AppStoreSplitAccessAuth(this as AppStore)._hasOnlyLegacyDefaultAdminUser;

  UserRole? _roleById(String id) =>
      _AppStoreSplitAccessAuth(this as AppStore).roleById(id);

  void _clearSensitiveActionAuthorization() =>
      _AppStoreSplitAccessAuth(this as AppStore)
          .clearSensitiveActionAuthorization();

  void _requireSensitiveActionAuthorization(String action) =>
      _AppStoreSplitAccessAuth(this as AppStore)
          .requireSensitiveActionAuthorization(action);
  bool hasPermission(String permission) =>
      _AppStoreSplitAccessAuth(this as AppStore).hasPermission(permission);
  void requirePermission(String permission) =>
      _AppStoreSplitAccessAuth(this as AppStore).requirePermission(permission);

  void _requireAnyPermission(Iterable<String> permissions) =>
      _AppStoreSplitAccessAuth(this as AppStore)
          .requireAnyPermission(permissions);

  void _requireAllPermissions(Iterable<String> permissions) =>
      _AppStoreSplitAccessAuth(this as AppStore)
          .requireAllPermissions(permissions);

  ExpensesOverview get _expensesOverview =>
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
  Future<void> _refreshAccountTransactionsFromSqlite() =>
      _AppStoreSplitStartupMigrationsPart2(this as AppStore)
          .refreshAccountTransactionsFromSqlite();

  Future<void> refreshAfterDatabaseChange(String key) =>
      _AppStoreSplitStartupMigrationsPart2(this as AppStore)
          .refreshAfterDatabaseChange(key);

  /// Conservative full refresh used for unknown keys or recovery after a failed
  /// targeted refresh.
  Future<void> _reloadAllAfterDatabaseChange() =>
      _AppStoreSplitStartupMigrationsPart2(this as AppStore)
          .reloadAllAfterDatabaseChange();

  String _generatePrefixedId(String prefix) =>
      _AppStoreSplitStartupMigrationsPart2(this as AppStore)
          ._generatePrefixedId(prefix);

  void _ensureCatalogDefaults() =>
      _AppStoreSplitStartupMigrationsPart3(this as AppStore)
          ._ensureCatalogDefaults();

  int _loadSyncSequence() =>
      _AppStoreSplitStartupMigrationsPart3(this as AppStore)
          ._loadSyncSequence();

  int _nextSyncSequence() =>
      _AppStoreSplitStartupMigrationsPart3(this as AppStore)
          ._nextSyncSequence();

  String _newSyncEnvelopeId(DateTime now, String prefix) =>
      _AppStoreSplitStartupMigrationsPart3(this as AppStore)
          ._newSyncEnvelopeId(now, prefix);

  Map<String, dynamic> _syncV2MetaOf(SyncChange change) =>
      _AppStoreSplitStartupMigrationsPart3(this as AppStore)
          ._syncV2MetaOf(change);

  String _syncMetaString(SyncChange change, String key) =>
      _AppStoreSplitStartupMigrationsPart3(this as AppStore)
          ._syncMetaString(change, key);
}
