part of 'app_store.dart';

/// Transitional instance API kept for source compatibility while callers
/// migrate to typed domain ports (`store.catalog`, `store.commerce`, etc.).
///
/// The business implementation continues to live in focused split modules;
/// this mixin deliberately contains forwarding only and owns no mutable state.
mixin _AppStoreForwardingApiStartupIdentity
    on ChangeNotifier, _AppStoreStateAccessors, _AppStoreForwardingApi {
  bool _isReplayOrDuplicateSyncEvent(
    SyncChange change, {
    required Set<String> existingEnvelopeIds,
    required Set<String> existingEventIds,
    required Set<String> acceptedSourceCommandIds,
    required int lastAppliedSequence,
  }) =>
      _AppStoreStartupMigrationsCatalogSync(this as AppStore)
          ._isReplayOrDuplicateSyncEvent(change,
              existingEnvelopeIds: existingEnvelopeIds,
              existingEventIds: existingEventIds,
              acceptedSourceCommandIds: acceptedSourceCommandIds,
              lastAppliedSequence: lastAppliedSequence);

  int _loadInvoiceCounter() =>
      _AppStoreStartupMigrationsCatalogSync(this as AppStore)
          ._loadInvoiceCounter();

  // Legacy migration path retained for controlled recovery of pre-v17 stores.
  // ignore: unused_element
  Future<void> _runDataMigrationsIfNeeded() =>
      _AppStoreStartupMigrationsCatalogSync(this as AppStore)
          ._runDataMigrationsIfNeeded();

  double _safeUsdCost(Product product) =>
      _AppStoreStartupMigrationsCatalogSync(this as AppStore)
          ._safeUsdCost(product);

  AppPlatformType _detectPlatform() =>
      _AppStoreSplitIdentityUsers(this as AppStore)._detectPlatform();

  AppIdentity _loadOrCreateAppIdentity() =>
      _AppStoreSplitIdentityUsers(this as AppStore)._loadOrCreateAppIdentity();

  AppIdentity _identityForLanSnapshotImport(Map<String, dynamic> decoded) =>
      _AppStoreSplitIdentityUsers(this as AppStore)
          ._identityForLanSnapshotImport(decoded);

  AppIdentity _normalizedLocalIdentity(AppIdentity identity) =>
      _AppStoreSplitIdentityUsers(this as AppStore)
          ._normalizedLocalIdentity(identity);

  Future<void> _storeHostTransferNotification(
    Map<String, dynamic> payload,
  ) =>
      _AppStoreSplitIdentityUsers(this as AppStore)
          ._storeHostTransferNotification(payload);

  Future<void> _forceApplyRoleFromTransfer(AppIdentity next) =>
      _AppStoreSplitIdentityUsers(this as AppStore)
          ._forceApplyRoleFromTransfer(next);

  void _assertSafeRoleTransition(
    AppIdentity next, {
    required String source,
    bool allowApprovedTransfer = false,
    bool allowInitialHostRegistration = false,
  }) =>
      _AppStoreSplitIdentityUsers(this as AppStore)._assertSafeRoleTransition(
          next,
          source: source,
          allowApprovedTransfer: allowApprovedTransfer,
          allowInitialHostRegistration: allowInitialHostRegistration);

  void _assertLanDirectRoleRules(AppIdentity next, {required String source}) =>
      _AppStoreSplitIdentityUsers(this as AppStore)
          ._assertLanDirectRoleRules(next, source: source);

  Future<List<UserRole>> _loadRoles() =>
      _AppStoreSplitIdentityUsers(this as AppStore)._loadRoles();

  Future<List<AppUser>> _loadUsers() =>
      _AppStoreSplitIdentityUsers(this as AppStore)._loadUsers();

  Future<void> _saveRolesAndUsers() =>
      _AppStoreSplitIdentityUsers(this as AppStore)._saveRolesAndUsers();

  Future<void> _ensureDefaultAdminUser() =>
      _AppStoreSplitIdentityUsers(this as AppStore)._ensureDefaultAdminUser();

  void _restoreActiveUser() =>
      _AppStoreIdentityUsersAuthentication(this as AppStore)._restoreActiveUser();

  Future<void> _loadSessionPermissionsFromStorage() =>
      _AppStoreIdentityUsersAuthentication(this as AppStore)
          ._loadSessionPermissionsFromStorage();

  Future<void> _restoreActiveUserFromStorage() =>
      _AppStoreIdentityUsersAuthentication(this as AppStore)
          ._restoreActiveUserFromStorage();

  Future<void> _refreshAuthFlags() =>
      _AppStoreIdentityUsersAuthentication(this as AppStore)._refreshAuthFlags();

  void _refreshUi() =>
      _AppStoreIdentityUsersAuthentication(this as AppStore).refreshUi();

  bool _verifyPassword(String password, String storedHash) =>
      _AppStoreIdentityUsersAuthentication(this as AppStore)
          ._verifyPassword(password, storedHash);

  AppUser? get _storeOwnerUser =>
      _AppStoreIdentityUsersAuthentication(this as AppStore).storeOwnerUser;

  Future<String> _hashPasswordAsync(String password) =>
      _AppStoreIdentityUsersCredentialsPersistence(this as AppStore)
          ._hashPasswordAsync(password);

  String _generateSalt() =>
      _AppStoreIdentityUsersCredentialsPersistence(this as AppStore)._generateSalt();

  StoreProfile _loadStoreProfile() =>
      _AppStoreIdentityUsersCredentialsPersistence(this as AppStore)._loadStoreProfile();

  void _normalizeCustomers() =>
      _AppStoreIdentityUsersCredentialsPersistence(this as AppStore)._normalizeCustomers();

  Future<void> _upsertSqliteBusinessRows(
    String key,
    Iterable<Map<String, dynamic>> rows,
  ) =>
      _AppStoreIdentityUsersCredentialsPersistence(this as AppStore)
          ._upsertSqliteBusinessRows(key, rows);

  void _markProductDerivedDataDirty() =>
      _AppStoreIdentityUsersCredentialsPersistence(this as AppStore)
          ._markProductDerivedDataDirty();

  Future<void> _flushProductDerivedData() =>
      _AppStoreIdentityUsersCredentialsPersistence(this as AppStore)
          ._flushProductDerivedData();

  Future<bool> _schedulePurchaseAccounting(Purchase purchase) =>
      _AppStoreIdentityUsersCredentialsPersistence(this as AppStore)
          ._schedulePurchaseAccounting(purchase);

  Future<void> _waitForPendingPurchaseAccounting(String purchaseId) =>
      _AppStoreIdentityUsersCredentialsPersistence(this as AppStore)
          ._waitForPendingPurchaseAccounting(purchaseId);

  void _rebuildProductIndexes() =>
      _AppStoreIdentityUsersCredentialsPersistence(this as AppStore)
          ._rebuildProductIndexes();

  void _rebuildCustomerIndexes() =>
      _AppStoreIdentityUsersCredentialsPersistence(this as AppStore)
          ._rebuildCustomerIndexes();

  void _rebuildSupplierIndexes() =>
      _AppStoreIdentityUsersCredentialsPersistence(this as AppStore)
          ._rebuildSupplierIndexes();

  void _rebuildMutableEntityIndexes() =>
      _AppStoreIdentityUsersCredentialsPersistence(this as AppStore)
          ._rebuildMutableEntityIndexes();

  void _rebuildProductInventoryProjectionFromMovements() =>
      _AppStoreIdentityUsersCredentialsPersistence(this as AppStore)
          ._rebuildProductInventoryProjectionFromMovements();

  void _rebuildStockMovementIndexes() =>
      _AppStoreIdentityUsersCredentialsPersistence(this as AppStore)
          ._rebuildStockMovementIndexes();

  void _rebuildPurchaseIndexes() =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)
          ._rebuildPurchaseIndexes();

  Future<Sale?> _saleByIdFromSqlite(String id) =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)
          ._saleByIdFromSqlite(id);

  Future<Purchase?> _purchaseByIdFromSqlite(String id) =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)
          ._purchaseByIdFromSqlite(id);

  Future<Expense?> _expenseByIdFromSqlite(String id) =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)
          ._expenseByIdFromSqlite(id);

  void _putStockMovementAtIndex(StockMovement movement, int index) =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)
          ._putStockMovementAtIndex(movement, index);

  void _mirrorAuthoritativeStockMovements(Iterable<StockMovement> movements) =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)
          ._mirrorAuthoritativeStockMovements(movements);

  void _rebuildExpenseIndexes() =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)
          ._rebuildExpenseIndexes();

  void _rebuildAccountTransactionIndexes() =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)
          ._rebuildAccountTransactionIndexes();

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
  }) =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)._touchDataRevisions(
          products: products,
          customers: customers,
          sales: sales,
          deliveryNotes: deliveryNotes,
          suppliers: suppliers,
          supplierProductPrices: supplierProductPrices,
          expenses: expenses,
          purchases: purchases,
          stockMovements: stockMovements,
          inventoryCounts: inventoryCounts,
          warehouses: warehouses,
          accountTransactions: accountTransactions,
          storeProfile: storeProfile);

  void _touchPurchasesData() =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)._touchPurchasesData();

  void _touchExpensesData() =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)._touchExpensesData();

  void _putPurchaseAtIndex(Purchase purchase, int index) =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)
          ._putPurchaseAtIndex(purchase, index);

  void _removePurchaseAtIndex(int index) =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)
          ._removePurchaseAtIndex(index);

  void _putExpenseAtIndex(Expense expense, int index) =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)
          ._putExpenseAtIndex(expense, index);

  void _removeExpenseAtIndex(int index) =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)
          ._removeExpenseAtIndex(index);

  void _removeAccountTransactionAtIndex(int index) =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)
          ._removeAccountTransactionAtIndex(index);

  /// Automatic event-log compaction is intentionally not run from normal save
  /// calls. It is async, Host-only, and must be guarded by ACK-based safety
  /// checks, so sync transports call [compactSyncedSyncHistoryForMaintenance]
  /// after a successful sync/ACK cycle.
  int _earliestStoredAuthoritativeSequence() =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)
          ._earliestStoredAuthoritativeSequence();

  int _latestStoredAuthoritativeSequence() =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)
          ._latestStoredAuthoritativeSequence();

  int _minimumActivePeerAckSequence({
    Duration activeWindow = const Duration(days: 14),
  }) =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)
          ._minimumActivePeerAckSequence(activeWindow: activeWindow);

  Future<void> _saveSyncStateOnly() =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)._saveSyncStateOnly();

  Future<void> _saveAll() =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)._saveAll();

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
  }) =>
      _AppStorePersistenceSyncCoreDirtyWrites(this as AppStore)._saveDirty(
          products: products,
          productDerivedData: productDerivedData,
          customers: customers,
          sales: sales,
          saleQuotations: saleQuotations,
          deliveryNotes: deliveryNotes,
          billsOfMaterials: billsOfMaterials,
          manufacturingOrders: manufacturingOrders,
          suppliers: suppliers,
          supplierProductPrices: supplierProductPrices,
          categories: categories,
          brands: brands,
          units: units,
          expenses: expenses,
          purchases: purchases,
          stockMovements: stockMovements,
          inventoryCounts: inventoryCounts,
          warehouses: warehouses,
          accountTransactions: accountTransactions,
          storeProfile: storeProfile,
          invoiceCounter: invoiceCounter,
          purchaseCounter: purchaseCounter,
          sync: sync);

  void _resetBusinessDataInMemory({bool keepStoreProfile = true}) =>
      _AppStorePersistenceSyncCoreDirtyWrites(this as AppStore)
          ._resetBusinessDataInMemory(keepStoreProfile: keepStoreProfile);

  void _validateProduct(Product product, {Product? previousProduct}) =>
      _AppStorePersistenceSyncCoreMaintenance(this as AppStore)
          ._validateProduct(product, previousProduct: previousProduct);

  String _generateUniqueProductCode({
    String? exceptProductId,
    Set<String>? reservedCodes,
  }) =>
      _AppStorePersistenceSyncCoreMaintenance(this as AppStore)
          ._generateUniqueProductCode(
              exceptProductId: exceptProductId, reservedCodes: reservedCodes);

  String get _invoiceDevicePrefix =>
      _AppStorePersistenceSyncCoreMaintenance(this as AppStore)
          ._invoiceDevicePrefix;

  int _invoiceSequenceFromNo(String invoiceNo) =>
      _AppStorePersistenceSyncCoreMaintenance(this as AppStore)
          ._invoiceSequenceFromNo(invoiceNo);

  void _rememberSqliteDirtyBusinessRow(
    String key,
    Map<String, dynamic> payload,
  ) =>
      _AppStorePersistenceSyncCoreOutbox(this as AppStore)
          ._rememberSqliteDirtyBusinessRow(key, payload);

  void _forgetSqliteDirtyBusinessRow(String key, String id) =>
      _AppStorePersistenceSyncCoreOutbox(this as AppStore)
          ._forgetSqliteDirtyBusinessRow(key, id);

  void _rememberRemoteSqliteBusinessRows(SyncChange change) =>
      _AppStorePersistenceSyncCoreOutbox(this as AppStore)
          ._rememberRemoteSqliteBusinessRows(change);

  void _recordSyncChange({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) =>
      _AppStorePersistenceSyncCoreOutbox(this as AppStore)
          ._recordSyncChange(
              entityType: entityType,
              entityId: entityId,
              operation: operation,
              payload: payload);

  bool get _isLanClientConfigured =>
      _AppStorePersistenceSyncCoreOutbox(this as AppStore)
          ._isLanClientConfigured;
}
