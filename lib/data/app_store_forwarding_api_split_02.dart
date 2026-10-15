part of 'app_store.dart';

/// Transitional instance API kept for source compatibility while callers
/// migrate to typed domain ports (`store.catalog`, `store.commerce`, etc.).
///
/// The business implementation continues to live in focused split modules;
/// this mixin deliberately contains forwarding only and owns no mutable state.
mixin _AppStoreForwardingApiPart2
    on ChangeNotifier, _AppStoreStateAccessors, _AppStoreForwardingApi {
  bool _isReplayOrDuplicateSyncEvent(
    SyncChange change, {
    required Set<String> existingEnvelopeIds,
    required Set<String> existingEventIds,
    required Set<String> acceptedSourceCommandIds,
    required int lastAppliedSequence,
  }) =>
      _AppStoreSplitStartupMigrationsPart3(this as AppStore)
          ._isReplayOrDuplicateSyncEvent(change,
              existingEnvelopeIds: existingEnvelopeIds,
              existingEventIds: existingEventIds,
              acceptedSourceCommandIds: acceptedSourceCommandIds,
              lastAppliedSequence: lastAppliedSequence);

  String? validateClientDraftForHostAcceptance(SyncChange change) =>
      _AppStoreSplitStartupMigrationsPart3(this as AppStore)
          .validateClientDraftForHostAcceptance(change);

  Future<void> clearPendingSyncQueue({bool notify = true}) =>
      _AppStoreSplitStartupMigrationsPart3(this as AppStore)
          .clearPendingSyncQueue(notify: notify);

  int _loadInvoiceCounter() =>
      _AppStoreSplitStartupMigrationsPart3(this as AppStore)
          ._loadInvoiceCounter();

  // Legacy migration path retained for controlled recovery of pre-v17 stores.
  // ignore: unused_element
  Future<void> _runDataMigrationsIfNeeded() =>
      _AppStoreSplitStartupMigrationsPart3(this as AppStore)
          ._runDataMigrationsIfNeeded();

  double _safeUsdCost(Product product) =>
      _AppStoreSplitStartupMigrationsPart3(this as AppStore)
          ._safeUsdCost(product);

  AppPlatformType _detectPlatform() =>
      _AppStoreSplitIdentityUsers(this as AppStore)._detectPlatform();

  AppIdentity _loadOrCreateAppIdentity() =>
      _AppStoreSplitIdentityUsers(this as AppStore)._loadOrCreateAppIdentity();

  Future<void> updateDeviceName(String deviceName) =>
      _AppStoreSplitIdentityUsers(this as AppStore)
          .updateDeviceName(deviceName);

  Future<void> recoverExistingStoreIdentity({
    required String storeId,
    String recoveryKey = '',
    String? branchId,
    String? hostDeviceId,
    String? deviceToken,
    String? controlPlaneTenantId,
    DeviceRole? deviceRole,
    SyncMode? syncMode,
  }) =>
      _AppStoreSplitIdentityUsers(this as AppStore)
          .recoverExistingStoreIdentity(
              storeId: storeId,
              recoveryKey: recoveryKey,
              branchId: branchId,
              hostDeviceId: hostDeviceId,
              deviceToken: deviceToken,
              controlPlaneTenantId: controlPlaneTenantId,
              deviceRole: deviceRole,
              syncMode: syncMode);

  AppIdentity _identityForLanSnapshotImport(Map<String, dynamic> decoded) =>
      _AppStoreSplitIdentityUsers(this as AppStore)
          ._identityForLanSnapshotImport(decoded);

  AppIdentity _normalizedLocalIdentity(AppIdentity identity) =>
      _AppStoreSplitIdentityUsers(this as AppStore)
          ._normalizedLocalIdentity(identity);

  Map<String, dynamic>? get pendingHostTransferRequest =>
      _AppStoreSplitIdentityUsers(this as AppStore).pendingHostTransferRequest;

  Map<String, dynamic>? get latestHostTransferNotification =>
      _AppStoreSplitIdentityUsers(this as AppStore)
          .latestHostTransferNotification;

  Future<void> clearHostTransferNotification() =>
      _AppStoreSplitIdentityUsers(this as AppStore)
          .clearHostTransferNotification();

  Future<void> _storeHostTransferNotification(
    Map<String, dynamic> payload,
  ) =>
      _AppStoreSplitIdentityUsers(this as AppStore)
          ._storeHostTransferNotification(payload);

  Future<void> clearLocalHostTransferRequest() =>
      _AppStoreSplitIdentityUsers(this as AppStore)
          .clearLocalHostTransferRequest();

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

  Future<void> updateAppIdentityDuringSetup(AppIdentity identity) =>
      _AppStoreSplitIdentityUsers(this as AppStore)
          .updateAppIdentityDuringSetup(identity);

  Future<void> updateAppIdentity(AppIdentity identity) =>
      _AppStoreSplitIdentityUsers(this as AppStore).updateAppIdentity(identity);

  Future<void> updateAppIdentityLocalOnly(
    AppIdentity identity, {
    String source = 'local sync settings',
  }) =>
      _AppStoreSplitIdentityUsers(this as AppStore)
          .updateAppIdentityLocalOnly(identity, source: source);

  Future<void> setActiveSyncTransport(String transport) =>
      _AppStoreSplitIdentityUsers(this as AppStore)
          .setActiveSyncTransport(transport);

  Future<void> requestHostTransfer({String reason = ''}) =>
      _AppStoreSplitIdentityUsers(this as AppStore)
          .requestHostTransfer(reason: reason);

  Future<void> approveHostTransfer(String requestingDeviceId) =>
      _AppStoreSplitIdentityUsers(this as AppStore)
          .approveHostTransfer(requestingDeviceId);

  Future<void> activateApprovedHostTransfer() =>
      _AppStoreSplitIdentityUsers(this as AppStore)
          .activateApprovedHostTransfer();

  @Deprecated('Use users and roles instead. Kept for old code compatibility.')
  Future<void> setCurrentRole(String role) =>
      _AppStoreSplitIdentityUsers(this as AppStore).setCurrentRole(role);

  Future<List<UserRole>> _loadRoles() =>
      _AppStoreSplitIdentityUsers(this as AppStore)._loadRoles();

  Future<List<AppUser>> _loadUsers() =>
      _AppStoreSplitIdentityUsers(this as AppStore)._loadUsers();

  Future<void> _saveRolesAndUsers() =>
      _AppStoreSplitIdentityUsers(this as AppStore)._saveRolesAndUsers();

  Future<void> _ensureDefaultAdminUser() =>
      _AppStoreSplitIdentityUsers(this as AppStore)._ensureDefaultAdminUser();

  void _restoreActiveUser() =>
      _AppStoreSplitIdentityUsersPart2(this as AppStore)._restoreActiveUser();

  Future<bool> login(
    String username,
    String password, {
    bool remember = false,
  }) =>
      _AppStoreSplitIdentityUsersPart2(this as AppStore)
          .login(username, password, remember: remember);

  Future<void> logout() =>
      _AppStoreSplitIdentityUsersPart2(this as AppStore).logout();

  Future<void> applySessionUser({
    required AppUser activeUser,
    required String currentRole,
    required Set<String> permissions,
    required bool rememberLogin,
  }) =>
      _AppStoreSplitIdentityUsersPart2(this as AppStore).applySessionUser(
          activeUser: activeUser,
          currentRole: currentRole,
          permissions: permissions,
          rememberLogin: rememberLogin);

  Future<void> clearSessionUser() =>
      _AppStoreSplitIdentityUsersPart2(this as AppStore).clearSessionUser();

  Future<void> _loadSessionPermissionsFromStorage() =>
      _AppStoreSplitIdentityUsersPart2(this as AppStore)
          ._loadSessionPermissionsFromStorage();

  Future<void> _restoreActiveUserFromStorage() =>
      _AppStoreSplitIdentityUsersPart2(this as AppStore)
          ._restoreActiveUserFromStorage();

  Future<void> _refreshAuthFlags() =>
      _AppStoreSplitIdentityUsersPart2(this as AppStore)._refreshAuthFlags();

  void refreshUi() =>
      _AppStoreSplitIdentityUsersPart2(this as AppStore).refreshUi();

  /// Applies a server-approved password reset to the matching local owner.
  /// The server reset is the authority; this only keeps Offline Login in sync
  /// after the support-issued one-time reset has been consumed successfully.
  Future<bool> applySupportPasswordResetToLocalUser({
    required String username,
    required String newPassword,
  }) =>
      _AppStoreSplitIdentityUsersPart2(this as AppStore)
          .applySupportPasswordResetToLocalUser(
              username: username, newPassword: newPassword);

  Future<bool> verifyAdminPassword(String password) =>
      _AppStoreSplitIdentityUsersPart2(this as AppStore)
          .verifyAdminPassword(password);

  bool _verifyPassword(String password, String storedHash) =>
      _AppStoreSplitIdentityUsersPart2(this as AppStore)
          ._verifyPassword(password, storedHash);

  Future<void> addOrUpdateRole(UserRole role) =>
      _AppStoreSplitIdentityUsersPart2(this as AppStore).addOrUpdateRole(role);

  Future<void> deleteRole(String id) =>
      _AppStoreSplitIdentityUsersPart2(this as AppStore).deleteRole(id);

  AppUser? get storeOwnerUser =>
      _AppStoreSplitIdentityUsersPart2(this as AppStore).storeOwnerUser;

  Future<void> applyStoreOwnerCredentials({
    required String username,
    required String password,
    String? fullName,
  }) =>
      _AppStoreSplitIdentityUsersPart3(this as AppStore)
          .applyStoreOwnerCredentials(
              username: username, password: password, fullName: fullName);

  Future<void> addOrUpdateUser(AppUser user, {String? password}) =>
      _AppStoreSplitIdentityUsersPart3(this as AppStore)
          .addOrUpdateUser(user, password: password);

  Future<void> deleteUser(String id) =>
      _AppStoreSplitIdentityUsersPart3(this as AppStore).deleteUser(id);

  Future<String> _hashPasswordAsync(String password) =>
      _AppStoreSplitIdentityUsersPart3(this as AppStore)
          ._hashPasswordAsync(password);

  String _generateSalt() =>
      _AppStoreSplitIdentityUsersPart3(this as AppStore)._generateSalt();

  StoreProfile _loadStoreProfile() =>
      _AppStoreSplitIdentityUsersPart3(this as AppStore)._loadStoreProfile();

  void _normalizeCustomers() =>
      _AppStoreSplitIdentityUsersPart3(this as AppStore)._normalizeCustomers();

  Future<void> _upsertSqliteBusinessRows(
    String key,
    Iterable<Map<String, dynamic>> rows,
  ) =>
      _AppStoreSplitIdentityUsersPart3(this as AppStore)
          ._upsertSqliteBusinessRows(key, rows);

  void _markProductDerivedDataDirty() =>
      _AppStoreSplitIdentityUsersPart3(this as AppStore)
          ._markProductDerivedDataDirty();

  Future<void> _flushProductDerivedData() =>
      _AppStoreSplitIdentityUsersPart3(this as AppStore)
          ._flushProductDerivedData();

  Future<bool> _schedulePurchaseAccounting(Purchase purchase) =>
      _AppStoreSplitIdentityUsersPart3(this as AppStore)
          ._schedulePurchaseAccounting(purchase);

  Future<void> _waitForPendingPurchaseAccounting(String purchaseId) =>
      _AppStoreSplitIdentityUsersPart3(this as AppStore)
          ._waitForPendingPurchaseAccounting(purchaseId);

  Future<void> waitForPendingAccounting({
    Duration timeout = const Duration(seconds: 45),
  }) =>
      _AppStoreSplitIdentityUsersPart3(this as AppStore)
          .waitForPendingAccounting(timeout: timeout);

  void _rebuildProductIndexes() =>
      _AppStoreSplitIdentityUsersPart3(this as AppStore)
          ._rebuildProductIndexes();

  void _rebuildCustomerIndexes() =>
      _AppStoreSplitIdentityUsersPart3(this as AppStore)
          ._rebuildCustomerIndexes();

  void _rebuildSupplierIndexes() =>
      _AppStoreSplitIdentityUsersPart3(this as AppStore)
          ._rebuildSupplierIndexes();

  void _rebuildMutableEntityIndexes() =>
      _AppStoreSplitIdentityUsersPart3(this as AppStore)
          ._rebuildMutableEntityIndexes();

  void _rebuildProductInventoryProjectionFromMovements() =>
      _AppStoreSplitIdentityUsersPart3(this as AppStore)
          ._rebuildProductInventoryProjectionFromMovements();

  void _rebuildStockMovementIndexes() =>
      _AppStoreSplitIdentityUsersPart3(this as AppStore)
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

  /// Reads the latest purchase snapshot before opening an edit form. The
  /// creator of a purchase is not relevant to edit access; the caller's
  /// permissions are checked by the mutation method. This refresh only avoids
  /// opening a form from a stale list/details snapshot.
  Future<Purchase?> reloadPurchaseFromSqlite(String id) =>
      _AppStoreSplitPersistenceSyncCore(this as AppStore)
          .reloadPurchaseFromSqlite(id);

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
      _AppStoreSplitPersistenceSyncCorePart2(this as AppStore)._saveDirty(
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
      _AppStoreSplitPersistenceSyncCorePart2(this as AppStore)
          ._resetBusinessDataInMemory(keepStoreProfile: keepStoreProfile);

  Future<void> resetBusinessData({bool keepStoreProfile = true}) =>
      _AppStoreSplitPersistenceSyncCorePart2(this as AppStore)
          .resetBusinessData(keepStoreProfile: keepStoreProfile);

  Future<void> clearLocalDeviceBusinessData({
    bool keepStoreProfile = true,
  }) =>
      _AppStoreSplitPersistenceSyncCorePart2(this as AppStore)
          .clearLocalDeviceBusinessData(keepStoreProfile: keepStoreProfile);

  Future<int> clearLocalOnlyPendingSyncChanges() =>
      _AppStoreSplitPersistenceSyncCorePart2(this as AppStore)
          .clearLocalOnlyPendingSyncChanges();

  Future<void> factoryResetLocalDevice({
    bool enforcePermission = true,
    bool preserveAdminUsers = false,
  }) =>
      _AppStoreSplitPersistenceSyncCorePart3(this as AppStore)
          .factoryResetLocalDevice(
              enforcePermission: enforcePermission,
              preserveAdminUsers: preserveAdminUsers);

  Future<int> cleanupSoftDeletedRecords({
    Duration retention = const Duration(days: 30),
  }) =>
      _AppStoreSplitPersistenceSyncCorePart3(this as AppStore)
          .cleanupSoftDeletedRecords(retention: retention);

  Future<BusinessDataIntegrityResult> verifyLocalBusinessDataIntegrity() =>
      _AppStoreSplitPersistenceSyncCorePart3(this as AppStore)
          .verifyLocalBusinessDataIntegrity();

  /// Repairs only product references that already exist in historical sales,
  /// purchases, or stock movements. Soft-deleted products are restored first.
  /// Creating archival catalog entries is opt-in because it changes the active
  /// data set; the new records are inactive and never track stock.
  Future<BusinessDataIntegrityRepairResult> repairMissingProductReferences({
    bool createArchivedProducts = false,
  }) =>
      _AppStoreSplitPersistenceSyncCorePart3(this as AppStore)
          .repairMissingProductReferences(
              createArchivedProducts: createArchivedProducts);

  Future<void> updateStoreProfile(StoreProfile profile) =>
      _AppStoreSplitPersistenceSyncCorePart3(this as AppStore)
          .updateStoreProfile(profile);

  Future<void> updateTaxConfiguration({
    required List<TaxProfile> profiles,
    required String defaultTaxProfileId,
  }) =>
      _AppStoreSplitPersistenceSyncCorePart3(this as AppStore)
          .updateTaxConfiguration(
        profiles: profiles,
        defaultTaxProfileId: defaultTaxProfileId,
      );

  Future<void> updateDefaultTaxRatePercent(double ratePercent) =>
      _AppStoreSplitPersistenceSyncCorePart3(this as AppStore)
          .updateDefaultTaxRatePercent(ratePercent);

  void _validateProduct(Product product, {Product? previousProduct}) =>
      _AppStoreSplitPersistenceSyncCorePart3(this as AppStore)
          ._validateProduct(product, previousProduct: previousProduct);

  String _generateUniqueProductCode({
    String? exceptProductId,
    Set<String>? reservedCodes,
  }) =>
      _AppStoreSplitPersistenceSyncCorePart3(this as AppStore)
          ._generateUniqueProductCode(
              exceptProductId: exceptProductId, reservedCodes: reservedCodes);

  String get _invoiceDevicePrefix =>
      _AppStoreSplitPersistenceSyncCorePart3(this as AppStore)
          ._invoiceDevicePrefix;

  int _invoiceSequenceFromNo(String invoiceNo) =>
      _AppStoreSplitPersistenceSyncCorePart3(this as AppStore)
          ._invoiceSequenceFromNo(invoiceNo);

  void _rememberSqliteDirtyBusinessRow(
    String key,
    Map<String, dynamic> payload,
  ) =>
      _AppStoreSplitPersistenceSyncCorePart4(this as AppStore)
          ._rememberSqliteDirtyBusinessRow(key, payload);

  void _forgetSqliteDirtyBusinessRow(String key, String id) =>
      _AppStoreSplitPersistenceSyncCorePart4(this as AppStore)
          ._forgetSqliteDirtyBusinessRow(key, id);

  void _rememberRemoteSqliteBusinessRows(SyncChange change) =>
      _AppStoreSplitPersistenceSyncCorePart4(this as AppStore)
          ._rememberRemoteSqliteBusinessRows(change);

  void _recordSyncChange({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) =>
      _AppStoreSplitPersistenceSyncCorePart4(this as AppStore)
          ._recordSyncChange(
              entityType: entityType,
              entityId: entityId,
              operation: operation,
              payload: payload);

  /// Runs after login before the automatic sync transports start.
  ///
  /// The cursor is persisted through LocalDatabaseService, which means SQLite
  /// owns it on native platforms. On the first Phase 8 launch we establish a
  /// baseline without replaying the entire historical accounting database. On
  /// later launches we capture everything committed after the last durable
  /// cursor, including a transaction that committed immediately before a
  /// process crash.
  Future<void> recoverPhase8AccountingSyncAfterStartup() =>
      _AppStoreSplitPersistenceSyncCorePart4(this as AppStore)
          .recoverPhase8AccountingSyncAfterStartup();

  Future<void> recordPhase8AccountingMutationForSync() =>
      _AppStoreSplitPersistenceSyncCorePart4(this as AppStore)
          .recordPhase8AccountingMutationForSync();

  bool get _isLanClientConfigured =>
      _AppStoreSplitPersistenceSyncCorePart4(this as AppStore)
          ._isLanClientConfigured;
}
