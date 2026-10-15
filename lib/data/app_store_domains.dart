part of 'app_store.dart';

/// Stable, typed entry points into AppStore business domains.
///
/// New UI/services should depend on the narrowest port they need instead of
/// reaching through the complete AppStore compatibility surface. The legacy
/// methods remain available during migration, but these ports are the preferred
/// dependency boundary for new code.
abstract class AppRuntimeDomainPort {
  Future<void> initialize({bool hydrateHeavyData = true});
  Future<void> prepareForShutdown();
  Future<ThemeMode> loadThemeMode();
  Future<void> saveThemeMode(ThemeMode mode);
  Future<Locale> loadLocale();
  Future<void> saveLocale(Locale locale);
  AppIdentity get identity;
  StoreProfile get profile;
  bool get isReady;
  bool get isCoreDataLoaded;
  bool get isLedgerDataLoaded;
  bool get isSyncDataLoaded;
  bool get isSuspendedByHost;
  String get suspendedByHostReason;
  int get dashboardRevision;
  int get reportsRevision;
  Future<void> updateIdentityDuringSetup(AppIdentity identity);
  Future<void> updateIdentity(AppIdentity identity);
  Future<void> updateDeviceName(String deviceName);
  Future<void> updateStoreProfile(StoreProfile profile);
  Future<void> refreshAfterDatabaseChange(String key);
  Future<void> refreshSalesProductData();
  Future<void> reloadAllAfterDatabaseChange();
  Future<void> ensureHeavyDataLoaded({bool failOnError = false});
  Future<void> markSuspendedByHost({String reason = ''});
  Future<void> clearSuspendedByHost();
  Future<void> recoverExistingStoreIdentity({
    required String storeId,
    String recoveryKey = '',
    String? branchId,
    String? hostDeviceId,
    String? deviceToken,
    String? controlPlaneTenantId,
    DeviceRole? deviceRole,
    SyncMode? syncMode,
  });
  void refreshUi();
}

abstract class CatalogDomainPort {
  List<Product> get products;
  int get productsRevision;
  int get productsPageRevision;
  List<Product> get allProductsForDiagnostics;
  List<Product> get stockTrackedProducts;
  List<CatalogItem> get categories;
  List<CatalogItem> get brands;
  List<CatalogItem> get units;
  List<ProductPriceOverride> get productPriceOverrides;
  List<CostingMethodHistory> get costingMethodHistory;
  Product? productById(String id);
  Future<void> ensureLoaded();
  Future<void> ensureProductsLoaded();
  Future<void> ensureProductCostsLoaded();
  Future<void> ensureProductPricesLoaded();
  Future<void> addOrUpdateProduct(Product product);
  Future<void> addOrUpdateCategory(CatalogItem item);
  Future<void> addOrUpdateBrand(CatalogItem item);
  Future<void> addOrUpdateUnit(CatalogItem item);
  int productsUsingCatalogItem(String type, CatalogItem item);
  Future<void> replaceAndDeleteCatalogItem({
    required String type,
    required CatalogItem item,
    CatalogItem? replacement,
  });
  ProductCost productCostFor(String productId);
  Future<ProductCostSnapshot> productCostSnapshotForProduct(
    Product product, {
    String warehouseId = '',
  });
  Future<Map<String, ProductCostSnapshot>> productCostSnapshotsForProducts(
    Iterable<Product> products, {
    String warehouseId = '',
  });
  double defaultProductUsdPrice(Product product, {String unitId = 'base'});
  ProductPrice? defaultProductPriceFor(String productId,
      {String unitId = 'base'});
  ProductPrice? productPriceFor(String productId, String priceListId,
      {String unitId = 'base'});
  ProductPriceOverride? productPriceOverrideFor(
    ProductPrice price,
    String currencyCode,
  );
  Future<List<ProductPriceHistoryEntry>> productPriceHistoryForProduct(
    String productId, {
    int limit = 200,
  });
  Future<void> setDefaultProductBasePrice({
    required String productId,
    required String unitId,
    required double amount,
    required String currencyCode,
  });
  Future<void> setProductBasePriceForList({
    required String productId,
    required String priceListId,
    required double amount,
    required String currencyCode,
    String unitId = 'base',
  });
  Future<BulkPriceAdjustmentResult> bulkAdjustProductPrices({
    required Iterable<String> productIds,
    required String priceListId,
    required double percentage,
    required bool increase,
    String unitId = 'base',
  });
  Future<void> setProductPriceOverride({
    required String productPriceId,
    required String currencyCode,
    required double amount,
    ProductPriceOverrideMode mode = ProductPriceOverrideMode.fixed,
    bool isActive = true,
  });
  Future<void> removeProductPriceOverride(
    String productPriceId,
    String currencyCode,
  );
  Future<void> deleteProduct(String id);
}

abstract class CommerceDomainPort {
  List<Customer> get customers;
  List<Customer> get allCustomersForDiagnostics;
  List<Supplier> get suppliers;
  List<Sale> get sales;
  List<Purchase> get purchases;
  List<Expense> get expenses;
  int get customersRevision;
  int get suppliersRevision;
  int get salesRevision;
  int get salesPageRevision;
  double get totalSalesAmount;
  int get pendingPurchaseCount;
  int get purchasesRevision;
  int get expensesRevision;
  PurchasesOverview get purchasesOverview;
  ExpensesOverview get expensesOverview;
  double get totalPurchasesAmount;
  double get totalExpensesAmount;
  Customer get walkInCustomer;
  List<SaleQuotation> get saleQuotations;
  List<DeliveryNote> get deliveryNotes;
  List<CreditNote> get creditNotes;
  Future<void> ensureCustomersLoaded();
  Future<void> ensureSuppliersLoaded();
  Future<void> ensureSalesLoaded();
  Future<void> ensurePurchasesLoaded();
  Future<void> ensureQuotationsLoaded();
  Future<void> ensureDeliveryNotesLoaded();
  Future<void> ensureCreditNotesLoaded();
  String resolveCustomerName(String? customerId);
  String sanitizeSelectedCustomerId(String? customerId);
  Future<void> addOrUpdateCustomer(Customer customer);
  Future<void> deleteCustomer(String id);
  Future<void> addOrUpdateSupplier(Supplier supplier);
  Future<void> deleteSupplier(String id);
  List<SupplierProductPrice> supplierProductPricesForProduct(
    String productId,
  );
  Future<void> addOrUpdateSupplierProductPrice(SupplierProductPrice price);
  Future<void> deleteSupplierProductPrice(String id);
  Future<void> addOrUpdateExpense(Expense expense);
  Future<void> createAndPostExpensesBulk(List<Expense> expenses);
  Future<void> postExpense(
    String id, {
    bool paidInCash = true,
    double? cashPaidAmount,
  });
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
  });
  Future<void> deleteDraftExpense(String id);
  Future<void> cancelExpense(String id, {String reason = ''});
  Future<Sale> convertSaleQuotationToSale(
    String quotationId, {
    String paymentMethod = 'Cash',
    String paymentStatus = 'paid',
  });
  DeliveryNote? deliveryNoteForSale(String saleId);
  Future<DeliveryNote> createDeliveryNoteFromSale(
    String saleId, {
    String note = '',
  });
  Future<void> markDeliveryNoteDelivered(String id);
  Future<void> deleteDeliveryNote(String id);
  double? lastPurchasePriceFor({
    required String productId,
    required String supplierId,
  });
  double? lastPurchasePriceForProduct(String productId);
  int supplierCountForProduct(String productId);
  SupplierProductPrice? supplierProductPriceFor({
    required String productId,
    required String supplierId,
  });
  Future<Sale> settleSalePayment({
    required String saleId,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  });
  Future<Purchase> settlePurchasePayment({
    required String purchaseId,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  });
  Future<void> normalizeRefundAllocations();
  Future<double> refundableSaleCashAmount(String saleId);
  Future<double> refundablePurchaseCashAmount(String purchaseId);
  Future<double> refundablePurchaseReturnCashAmount(String purchaseReturnId);
  Future<double> refundSaleCash({
    required String saleId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  });
  Future<double> refundPurchaseCash({
    required String purchaseId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  });
  Future<double> refundPurchaseReturnCash({
    required String purchaseReturnId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  });
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
  });
  Future<CreditNote> returnSale(
    String id, {
    bool restoreStock = true,
    Map<String, double>? returnedQuantities,
  });
  Future<void> cancelSale(
    String id, {
    String status = 'Cancelled',
    bool restoreStock = true,
  });
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
  });
  Future<CreditNote> editSaleReturn({
    required String creditNoteId,
    required int expectedVersion,
    required Map<String, double> returnedQuantities,
  });
  Future<SaleQuotation> createSaleQuotation({
    required String customerName,
    String customerId = '',
    required List<SaleItem> items,
    double discount = 0,
    String invoiceCurrency = 'USD',
    String note = '',
    DateTime? validUntil,
  });
  Future<void> deleteSaleQuotation(String id);
  Future<CreditNote> cancelSaleReturn({
    required String creditNoteId,
    required int expectedVersion,
  });
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
  });
  Future<Purchase> createPurchaseReturn({
    required String sourcePurchaseId,
    required List<PurchaseItem> items,
    String reason = '',
  });
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
  });
  Future<void> receivePurchase(
    String id, {
    bool settleInitialPayment = true,
    bool postAccounting = true,
    Map<int, List<BatchAllocation>> batchAllocationsByLine =
        const <int, List<BatchAllocation>>{},
  });
  Future<Purchase> editPurchaseReturn({
    required String purchaseId,
    required int expectedVersion,
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    String warehouseId = '',
    String warehouseName = '',
  });
  Future<void> deleteDraftPurchase(String id);
  Future<void> returnPurchase(
    String id, {
    bool reverseStock = true,
    String reason = '',
    bool recordSupplierReturnLedger = true,
  });
  Future<void> cancelPurchase(
    String id, {
    bool reverseStock = true,
    String reason = '',
  });
  List<SupplierPurchasePrice> purchasePriceHistoryForProduct(
    String productId,
  );
  List<SupplierPurchasePrice> supplierPriceComparisonForProduct(
    String productId,
  );
  PurchaseItem? lastPurchaseItemFor({
    required String productId,
    required String supplierId,
  });
  PurchaseItem? lastPurchaseItemForProduct(String productId);
  double averagePurchaseCostForProduct(String productId);
  double estimateProfit();
  Future<Purchase?> reloadPurchaseFromSqlite(String id);
  Future<double> refundableExpenseCashAmount(String expenseId);
  Future<double> refundExpenseCash({
    required String expenseId,
    double? amount,
    String notes = '',
  });
}

abstract class AccountingDomainPort {
  List<AccountTransaction> get transactions;
  Future<void> ensureLoaded();
  int get revision;
  int get ledgerRevision;
  double accountBalance(String accountType, String accountId);
  List<AccountTransaction> transactionsForAccount(
    String accountType,
    String accountId,
  );
  Future<void> refreshFromSqlite();
  Future<void> settleAccountPayment({
    required String accountType,
    required String accountId,
    required String accountName,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String referenceNo = '',
    String notes = '',
    List<PaymentAllocationDraft> allocations = const <PaymentAllocationDraft>[],
    String idempotencyKey = '',
    DateTime? date,
  });
  Future<void> updateTaxConfiguration({
    required List<TaxProfile> profiles,
    required String defaultTaxProfileId,
  });
  Future<void> updateDefaultTaxRatePercent(double ratePercent);
}

abstract class InventoryDomainPort {
  List<Warehouse> get warehouses;
  InventoryCostingMethod get inventoryCostingMethod;
  List<StockMovement> get stockMovements;
  List<StockMovement> get autoCorrectionMovements;
  List<StockMovement> get pendingAutoCorrectionMovements;
  List<BillOfMaterials> get billsOfMaterials;
  List<ManufacturingOrder> get manufacturingOrders;
  List<InventoryCountSession> get inventoryCountSessions;
  InventoryCountSession? get activeInventoryCountSession;
  int get revision;
  double get inventoryRetailValue;
  int get lowStockCount;
  double get inventoryCostValue;
  String get saleWarehouseId;
  Future<void> setSaleWarehouseId(String warehouseId);
  Future<void> setInventoryCostingMethod(
    InventoryCostingMethod method, {
    String reason = '',
  });
  Future<void> ensureLoaded();
  Future<void> ensureWarehousesLoaded();
  Warehouse resolveWarehouseForSale({String warehouseId = ''});
  Warehouse resolveWarehouseForPurchase({String warehouseId = ''});
  double stockForWarehouse(String productId, String warehouseId);
  Future<double> warehouseStockFromSqlite(
    String productId, {
    String warehouseId = '',
  });
  Future<Map<String, Map<String, double>>> warehouseStockBalancesFromSqlite();
  Future<Warehouse> createWarehouse({
    required String name,
    String code = '',
    String location = '',
  });
  Future<void> reviewAutoCorrection(String movementId, {String note = ''});
  Future<void> setExpiryBatchStatus(String batchId, String status);
  Future<void> reverseExpiryBatchAdjustment(
    String movementId, {
    String reason = '',
  });
  Future<void> adjustExpiryBatchStock({
    required String productId,
    required String warehouseId,
    required String batchId,
    required double quantityDelta,
    required String reason,
    String adjustmentCategory = 'other',
  });
  Future<int> manualStockAdjustmentVersion(String operationReferenceId);
  Future<void> editStockAdjustment({
    required String operationReferenceId,
    required int expectedVersion,
    required double quantityDelta,
    required String reason,
    String adjustmentCategory = 'other',
    String notes = '',
    String evidenceRef = '',
    List<BatchAllocation> batchAllocations = const <BatchAllocation>[],
  });
  Future<void> recordWasteLoss({
    required String productId,
    required String warehouseId,
    required double quantity,
    required String reason,
    String adjustmentCategory = 'other',
    String notes = '',
  });
  Future<void> deleteWasteLoss(String movementId);
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
  });
  Future<InventoryCountSession> createInventoryCountSession({
    String notes = '',
    String warehouseId = '',
    String warehouseName = '',
  });
  Future<void> countInventoryLine({
    required String sessionId,
    required String productId,
    required double countedQty,
    String note = '',
  });
  Future<void> resetInventoryCountLine({
    required String sessionId,
    required String productId,
  });
  Future<void> approveInventoryCount(String sessionId);
  Future<void> reverseInventoryCount(String sessionId, {String reason = ''});
  Future<void> cancelInventoryCount(String sessionId);
  Future<ManufacturingOrder> startManufacturingOrder({
    required String bomId,
    required double quantity,
    String rawMaterialsWarehouseId = '',
    String rawMaterialsWarehouseName = '',
    String finishedGoodsWarehouseId = '',
    String finishedGoodsWarehouseName = '',
    String notes = '',
  });
  Future<ManufacturingOrder> reverseManufacturingOrder({
    required String orderId,
    required String reason,
  });
  Future<BillOfMaterials> estimateBillOfMaterialsSnapshot(
    BillOfMaterials bom, {
    String warehouseId = '',
  });
  Future<double> estimateBillOfMaterialsUnitCost(
    BillOfMaterials bom, {
    String warehouseId = '',
  });
  Future<BillOfMaterials> createBillOfMaterials({
    required String name,
    required String outputProductId,
    required double outputQuantity,
    required List<BillOfMaterialsLine> components,
    String notes = '',
  });
  Future<BillOfMaterials> updateBillOfMaterials({
    required String id,
    required String name,
    required String outputProductId,
    required double outputQuantity,
    required List<BillOfMaterialsLine> components,
    String notes = '',
  });
  Future<void> deleteBillOfMaterials(String id);
  Future<void> deleteManufacturingOrder(String id);
  Future<ManufacturingOrder> updateManufacturingOrder({
    required String id,
    required String bomId,
    required double quantity,
    required String rawMaterialsWarehouseId,
    required String rawMaterialsWarehouseName,
    required String finishedGoodsWarehouseId,
    required String finishedGoodsWarehouseName,
    String notes = '',
  });
  Future<ManufacturingOrder> finishManufacturingOrder({
    required String orderId,
    required double actualQuantity,
    List<BatchAllocation> outputBatchAllocations = const <BatchAllocation>[],
    Map<String, double> actualConsumedQuantities = const <String, double>{},
    Map<String, double> wasteQuantities = const <String, double>{},
    Map<String, String> wasteReasons = const <String, String>{},
  });
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
  });
  Future<double> estimatedUnifiedBatchUnitCostForProduct(
    Product product, {
    String warehouseId = '',
    double requiredQuantity = 0,
  });
  Future<WarehouseTransferOrder> createWarehouseTransferOrder({
    required String fromWarehouseId,
    required String toWarehouseId,
    required List<WarehouseTransferOrderItem> items,
    String notes = '',
  });
  Future<WarehouseTransferOrder> editWarehouseTransferOrder({
    required String orderId,
    required int expectedVersion,
    required String fromWarehouseId,
    required String toWarehouseId,
    required List<WarehouseTransferOrderItem> items,
    String? notes,
    DateTime? date,
  });
  Future<List<WarehouseTransferOrder>> recentTransferOrders({int limit = 100});
  Future<Map<String, dynamic>> traceBatch(String batchId, {int maxDepth = 8});
  Future<Map<String, dynamic>> verifyTraceabilityIntegrity();
}

abstract class SecurityDomainPort {
  AppUser? get activeUser;
  AppUser? get currentUser;
  String get currentRole;
  List<AppUser> get users;
  List<UserRole> get roles;
  UserRole? roleById(String id);
  bool get rememberLogin;
  bool get hasLocalAdminUser;
  AppUser? get storeOwnerUser;
  bool canAccessPage(String pageId);
  bool hasPermission(String permission);
  bool hasAnyPermission(Iterable<String> permissions);
  bool get canViewDashboard;
  bool get canViewProducts;
  bool get canManageProducts;
  bool get canViewCustomers;
  bool get canManageCustomers;
  bool get canManageCustomerPayments;
  bool get canViewSuppliers;
  bool get canManageSuppliers;
  bool get canManageSupplierPayments;
  bool get canViewSales;
  bool get canSell;
  bool get canViewQuotations;
  bool get canManageQuotations;
  bool get canViewDeliveryNotes;
  bool get canManageDeliveryNotes;
  bool get canViewPurchases;
  bool get canManagePurchases;
  bool get canViewExpenses;
  bool get canManageExpenses;
  bool get canViewAccounting;
  bool get canManageAccounting;
  bool get canManageCashBox;
  bool get canViewInventory;
  bool get canManageInventory;
  bool get canViewReports;
  bool get canViewCashBox;
  bool get canViewSettings;
  bool get canViewDatabase;
  bool get canViewMaintenance;
  bool get canManageMaintenance;
  bool get canManageUsers;
  bool get canManageUsersPage;
  bool get canManageDatabase;
  bool get canDeleteOrCancel;
  Future<void> applySessionUser({
    required AppUser activeUser,
    required String currentRole,
    required Set<String> permissions,
    required bool rememberLogin,
  });
  Future<void> clearSessionUser();
  Future<void> addOrUpdateRole(UserRole role);
  Future<void> deleteRole(String id);
  Future<void> addOrUpdateUser(AppUser user, {String? password});
  Future<void> deleteUser(String id);
  Future<bool> verifyAdminPassword(String password);
  Future<void> applyStoreOwnerCredentials({
    required String username,
    required String password,
    String? fullName,
  });
  Future<void> completeInitialAdminSetup({
    required String fullName,
    required String username,
    required String password,
  });
  void requirePermission(String permission);
  void requireAnyPermission(Iterable<String> permissions);
  void requireAllPermissions(Iterable<String> permissions);
  Future<bool> authorizeSensitiveAction({
    required String action,
    required String password,
    Duration validity = const Duration(minutes: 3),
  });
  void requireSensitiveActionAuthorization(String action);
  void clearSensitiveActionAuthorization();
  bool get needsInitialAdminSetup;
  Future<bool> login(
    String username,
    String password, {
    bool remember = false,
  });
  Future<void> logout();
  Future<bool> applySupportPasswordResetToLocalUser({
    required String username,
    required String newPassword,
  });
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
  });
}

abstract class SyncDomainPort {
  String get deviceId;
  List<SyncChange> get changes;
  List<SyncQueueItem> get queue;
  List<SyncChange> get pendingChanges;
  List<SyncQueueItem> get pendingQueue;
  int get sequence;
  int get pendingCount;
  int get activeClientPendingCount;
  int get latestStoredAuthoritativeSequence;
  List<DataConflict> get dataConflicts;
  int get blockingDataConflictCount;
  Map<String, dynamic>? get latestHostTransferNotification;
  DateTime? get latestResetAt;
  Future<void> ensureLoaded();
  List<SyncChange> pendingChangesForTarget(
    String target, {
    bool readyOnly = true,
  });
  List<SyncChange> submittedChangesForTarget(String target);
  String? validateClientDraftForHostAcceptance(SyncChange change);
  Future<void> markPushInProgress(Iterable<String> changeIds);
  Future<void> markSubmitted(Iterable<String> ids);
  Future<void> markAcknowledged(Iterable<String> ids);
  Future<void> markFailed(Iterable<String> changeIds, String message);
  Future<void> markRejected(Map<String, String> rejected);
  Future<void> applyRemoteChanges(
    Iterable<SyncChange> changes, {
    bool markAppliedAsSynced = false,
    bool mirrorToDirect = false,
  });
  Future<void> assertRemoteChangesApplied(List<SyncChange> changes);
  Future<void> retryFailed({String? target});
  Future<void> recoverSubmitted({String? target});
  Future<void> recoverStale({
    String? target,
    Duration staleAfter = const Duration(seconds: 45),
  });
  Future<List<DataConflict>> ensureDataConflictsLoaded();
  Future<BusinessDataIntegrityResult> verifyLocalBusinessDataIntegrity();
  Future<int> cleanupSoftDeletedRecords({
    Duration retention = const Duration(days: 30),
  });
  Future<void> recordPhase8AccountingMutationForSync();
  Future<void> recoverPhase8AccountingSyncAfterStartup();
  Future<Map<String, int>> compactSyncedHistoryForMaintenance({
    int keepRecentSyncedChanges = AppStore._syncMaintenanceKeepRecentChanges,
    int minChangesBeforeCompact =
        AppStore._syncMaintenanceMinChangesBeforeCompact,
  });
  Future<Map<String, int>> compactClientSyncedHistoryForMaintenance({
    int keepRecentSyncedChanges = AppStore._syncMaintenanceKeepRecentChanges,
  });
  Future<int> settleHostQueueThroughPeerAck();
  Future<void> settleLegacyLanHostQueue();
  Future<void> importSnapshotJson(String rawJson);
  Future<void> markAllChangesSynced();
  Future<List<Map<String, dynamic>>> exportSnapshotChunks({
    String kind = 'full_store',
    Set<String>? sectionIds,
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  });
  Map<String, dynamic> snapshotPayloadFromChunks(
    List<Map<String, dynamic>> chunks,
  );
  DateTime snapshotGeneratedAtFromJson(String rawJson);
  int snapshotGeneratedSequenceFromJson(String rawJson);
  String exportChangesJson({
    DateTime? since,
    int? sinceSequence,
    int? maxEncodedPayloadBytes,
  });
  String get approvedHostTransferDeviceId;
  Map<String, dynamic>? get pendingHostTransferRequest;
  Future<void> updateAppIdentityLocalOnly(
    AppIdentity identity, {
    String source = 'local sync settings',
  });
  Future<void> setActiveSyncTransport(String transport);
  Future<void> requestHostTransfer({String reason = ''});
  Future<void> approveHostTransfer(String requestingDeviceId);
  Future<void> activateApprovedHostTransfer();
  Future<void> clearHostTransferNotification();
  Future<int> clearLocalOnlyPendingSyncChanges();
  List<SyncQueueItem> pendingSyncQueueForTarget(
    String target, {
    bool readyOnly = true,
  });
  Future<void> clearPendingSyncQueue({bool notify = true});
  Future<void> markSyncQueueItemFailed(String queueItemId, String error);
  Future<String> exportSyncSnapshotJson();
}

abstract class RecoveryDomainPort {
  bool get hasLocalStoreData;
  Future<String> exportBackupJson();
  Future<void> importBackupJson(
    String rawJson, {
    Set<String>? selectedSectionIds,
  });
  String exportRecoveryFileJson({String controlPlaneApiUrl = ''});
  Future<Map<String, dynamic>> exportUnifiedSnapshotEnvelope({
    String kind = 'full_store',
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  });
  Map<String, String> parseRecoveryFileJson(String rawJson);
  Future<void> factoryResetLocalDevice({
    bool enforcePermission = true,
    bool preserveAdminUsers = false,
  });
  Future<void> resetBusinessData({bool keepStoreProfile = true});
}

final class _AppRuntimeDomain implements AppRuntimeDomainPort {
  _AppRuntimeDomain(this._store);
  final AppStore _store;

  @override
  Future<void> initialize({bool hydrateHeavyData = true}) =>
      _AppStoreSplitStartupMigrations(_store)
          .initialize(hydrateHeavyData: hydrateHeavyData);

  @override
  Future<void> prepareForShutdown() =>
      _AppStoreSplitSyncApplyPart4(_store).prepareForShutdown();

  @override
  Future<ThemeMode> loadThemeMode() =>
      _AppStoreSplitAccessAuth(_store).loadThemeMode();

  @override
  Future<void> saveThemeMode(ThemeMode mode) =>
      _AppStoreSplitAccessAuth(_store).saveThemeMode(mode);

  @override
  Future<Locale> loadLocale() => _AppStoreSplitAccessAuth(_store).loadLocale();

  @override
  Future<void> saveLocale(Locale locale) =>
      _AppStoreSplitAccessAuth(_store).saveLocale(locale);

  @override
  AppIdentity get identity =>
      _store._appIdentity ??
      AppIdentity.defaults(
        deviceId: _store._deviceId,
        platform: _store._detectPlatform(),
      );

  @override
  StoreProfile get profile => _store._storeProfile;

  @override
  bool get isReady => _store._isReady;

  @override
  bool get isCoreDataLoaded => _store._isReady;

  @override
  bool get isLedgerDataLoaded => _store._isReady;

  @override
  bool get isSyncDataLoaded => _store._syncDataLoadCompleted;

  @override
  bool get isSuspendedByHost =>
      identity.isClient && ClientSuspensionStateStore.isSuspended;

  @override
  String get suspendedByHostReason => ClientSuspensionStateStore.reason;

  @override
  int get dashboardRevision => _store._dashboardRevisionReadImpl;

  @override
  int get reportsRevision => _store._reportsRevisionReadImpl;

  @override
  Future<void> updateIdentityDuringSetup(AppIdentity identity) =>
      _AppStoreSplitIdentityUsers(_store)
          .updateAppIdentityDuringSetup(identity);

  @override
  Future<void> updateIdentity(AppIdentity identity) =>
      _AppStoreSplitIdentityUsers(_store).updateAppIdentity(identity);

  @override
  Future<void> updateDeviceName(String deviceName) =>
      _AppStoreSplitIdentityUsers(_store).updateDeviceName(deviceName);

  @override
  Future<void> updateStoreProfile(StoreProfile profile) =>
      _AppStoreSplitPersistenceSyncCorePart3(_store)
          .updateStoreProfile(profile);

  @override
  Future<void> refreshAfterDatabaseChange(String key) =>
      _AppStoreSplitStartupMigrationsPart2(_store)
          .refreshAfterDatabaseChange(key);

  @override
  Future<void> refreshSalesProductData() =>
      _AppStoreSplitStartupMigrationsPart2(_store).refreshSalesProductData();

  @override
  Future<void> reloadAllAfterDatabaseChange() =>
      _AppStoreSplitStartupMigrationsPart2(_store)
          .reloadAllAfterDatabaseChange();

  @override
  Future<void> ensureHeavyDataLoaded({bool failOnError = false}) =>
      _AppStoreSplitCoreLoading(_store)
          .ensureHeavyDataLoaded(failOnError: failOnError);

  @override
  Future<void> markSuspendedByHost({String reason = ''}) =>
      _AppStoreSplitAccessAuth(_store).markSuspendedByHost(reason: reason);

  @override
  Future<void> clearSuspendedByHost() =>
      _AppStoreSplitAccessAuth(_store).clearSuspendedByHost();

  @override
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
      _AppStoreSplitIdentityUsers(_store).recoverExistingStoreIdentity(
        storeId: storeId,
        recoveryKey: recoveryKey,
        branchId: branchId,
        hostDeviceId: hostDeviceId,
        deviceToken: deviceToken,
        controlPlaneTenantId: controlPlaneTenantId,
        deviceRole: deviceRole,
        syncMode: syncMode,
      );

  @override
  void refreshUi() => _store.notifyListeners();
}

final class _CatalogDomain implements CatalogDomainPort {
  _CatalogDomain(this._store);
  final AppStore _store;

  @override
  List<Product> get products => _AppStoreCatalogRead(_store)._productsReadImpl;
  @override
  int get productsRevision => _store._productsRevision;
  @override
  int get productsPageRevision => Object.hashAll(<Object?>[
        _store._productsRevision,
        _store._purchasesRevision,
        _store._storeProfileRevision,
      ]);
  @override
  List<Product> get allProductsForDiagnostics =>
      _AppStoreCatalogRead(_store)._allProductsForDiagnosticsReadImpl;
  @override
  List<Product> get stockTrackedProducts =>
      _AppStoreCatalogRead(_store)._stockTrackedProductsReadImpl;
  @override
  List<CatalogItem> get categories =>
      _AppStoreCatalogRead(_store)._categoriesReadImpl;
  @override
  List<CatalogItem> get brands => _AppStoreCatalogRead(_store)._brandsReadImpl;
  @override
  List<CatalogItem> get units => _AppStoreCatalogRead(_store)._unitsReadImpl;
  @override
  List<ProductPriceOverride> get productPriceOverrides =>
      _AppStoreCatalogRead(_store)._productPriceOverridesReadImpl;
  @override
  List<CostingMethodHistory> get costingMethodHistory =>
      _AppStoreCatalogRead(_store)._costingMethodHistoryReadImpl;
  @override
  Product? productById(String id) =>
      _AppStoreCatalogRead(_store)._productByIdReadImpl(id);
  @override
  Future<void> ensureLoaded() => _store._ensureProductsLoadedImpl();
  @override
  Future<void> ensureProductsLoaded() => _store._ensureProductsLoadedImpl();
  @override
  Future<void> ensureProductCostsLoaded() =>
      _store._ensureProductCostsLoadedImpl();
  @override
  Future<void> ensureProductPricesLoaded() =>
      _store._ensureProductPricesLoadedImpl();
  @override
  Future<void> addOrUpdateProduct(Product product) =>
      _AppStoreSplitCatalogPartiesExpenses(_store).addOrUpdateProduct(product);
  @override
  Future<void> addOrUpdateCategory(CatalogItem item) =>
      _AppStoreSplitCatalogPartiesExpensesPart2(_store)
          .addOrUpdateCategory(item);
  @override
  Future<void> addOrUpdateBrand(CatalogItem item) =>
      _AppStoreSplitCatalogPartiesExpensesPart2(_store).addOrUpdateBrand(item);
  @override
  Future<void> addOrUpdateUnit(CatalogItem item) =>
      _AppStoreSplitCatalogPartiesExpensesPart2(_store).addOrUpdateUnit(item);
  @override
  int productsUsingCatalogItem(String type, CatalogItem item) =>
      _AppStoreSplitCatalogPartiesExpensesPart2(_store)
          .productsUsingCatalogItem(type, item);
  @override
  Future<void> replaceAndDeleteCatalogItem({
    required String type,
    required CatalogItem item,
    CatalogItem? replacement,
  }) =>
      _AppStoreSplitCatalogPartiesExpensesPart2(_store)
          .replaceAndDeleteCatalogItem(
        type: type,
        item: item,
        replacement: replacement,
      );
  @override
  ProductCost productCostFor(String productId) =>
      _AppStoreSplitCoreLoading(_store).productCostFor(productId);
  @override
  Future<ProductCostSnapshot> productCostSnapshotForProduct(
    Product product, {
    String warehouseId = '',
  }) =>
      _AppStoreSplitPricingCostingPart2(_store)
          .productCostSnapshotForProduct(product, warehouseId: warehouseId);
  @override
  Future<Map<String, ProductCostSnapshot>> productCostSnapshotsForProducts(
    Iterable<Product> products, {
    String warehouseId = '',
  }) =>
      _AppStoreSplitPricingCostingPart2(_store).productCostSnapshotsForProducts(
        products,
        warehouseId: warehouseId,
      );
  @override
  double defaultProductUsdPrice(Product product, {String unitId = 'base'}) =>
      _AppStoreSplitCoreLoading(_store)
          .defaultProductUsdPrice(product, unitId: unitId);
  @override
  ProductPrice? defaultProductPriceFor(String productId,
          {String unitId = 'base'}) =>
      _AppStoreSplitCoreLoading(_store)
          .defaultProductPriceFor(productId, unitId: unitId);
  @override
  ProductPrice? productPriceFor(String productId, String priceListId,
          {String unitId = 'base'}) =>
      _AppStoreSplitCoreLoading(_store)
          .productPriceFor(productId, priceListId, unitId: unitId);
  @override
  ProductPriceOverride? productPriceOverrideFor(
    ProductPrice price,
    String currencyCode,
  ) =>
      _AppStoreSplitCoreLoading(_store)
          .productPriceOverrideFor(price, currencyCode);
  @override
  Future<List<ProductPriceHistoryEntry>> productPriceHistoryForProduct(
    String productId, {
    int limit = 200,
  }) =>
      _AppStoreSplitPricingCosting(_store)
          .productPriceHistoryForProduct(productId, limit: limit);
  @override
  Future<void> setDefaultProductBasePrice({
    required String productId,
    required String unitId,
    required double amount,
    required String currencyCode,
  }) =>
      _AppStoreSplitPricingCosting(_store).setDefaultProductBasePrice(
        productId: productId,
        unitId: unitId,
        amount: amount,
        currencyCode: currencyCode,
      );
  @override
  Future<void> setProductBasePriceForList({
    required String productId,
    required String priceListId,
    required double amount,
    required String currencyCode,
    String unitId = 'base',
  }) =>
      _AppStoreSplitPricingCosting(_store).setProductBasePriceForList(
        productId: productId,
        priceListId: priceListId,
        amount: amount,
        currencyCode: currencyCode,
        unitId: unitId,
      );
  @override
  Future<BulkPriceAdjustmentResult> bulkAdjustProductPrices({
    required Iterable<String> productIds,
    required String priceListId,
    required double percentage,
    required bool increase,
    String unitId = 'base',
  }) =>
      _AppStoreSplitPricingCosting(_store).bulkAdjustProductPrices(
        productIds: productIds,
        priceListId: priceListId,
        percentage: percentage,
        increase: increase,
        unitId: unitId,
      );
  @override
  Future<void> setProductPriceOverride({
    required String productPriceId,
    required String currencyCode,
    required double amount,
    ProductPriceOverrideMode mode = ProductPriceOverrideMode.fixed,
    bool isActive = true,
  }) =>
      _AppStoreSplitPricingCosting(_store).setProductPriceOverride(
        productPriceId: productPriceId,
        currencyCode: currencyCode,
        amount: amount,
        mode: mode,
        isActive: isActive,
      );
  @override
  Future<void> removeProductPriceOverride(
    String productPriceId,
    String currencyCode,
  ) =>
      _AppStoreSplitPricingCosting(_store)
          .removeProductPriceOverride(productPriceId, currencyCode);
  @override
  Future<void> deleteProduct(String id) =>
      _AppStoreSplitCatalogPartiesExpenses(_store).deleteProduct(id);
}

final class _CommerceDomain implements CommerceDomainPort {
  _CommerceDomain(this._store);
  final AppStore _store;

  @override
  List<Customer> get customers => _AppStorePartyRead(_store)._customersReadImpl;
  @override
  List<Customer> get allCustomersForDiagnostics =>
      List<Customer>.unmodifiable(_store._customers);
  @override
  List<Supplier> get suppliers => _AppStorePartyRead(_store)._suppliersReadImpl;
  @override
  List<Sale> get sales => _AppStoreSplitCoreLoading(_store)._salesReadImpl;
  @override
  List<Purchase> get purchases =>
      _AppStoreSplitCoreLoading(_store)._purchasesReadImpl;
  @override
  List<Expense> get expenses =>
      _AppStoreSplitCoreLoading(_store)._expensesReadImpl;
  @override
  int get customersRevision => _store._customersRevision;
  @override
  int get suppliersRevision => _store._suppliersRevision;
  @override
  int get salesRevision => _store._salesRevision;
  @override
  int get salesPageRevision => Object.hashAll(<Object?>[
        _store._productsRevision,
        _store._customersRevision,
        _store._salesRevision,
        _store._deliveryNotesRevision,
        _store._storeProfileRevision,
      ]);
  @override
  double get totalSalesAmount =>
      _AppStoreSplitAccessAuth(_store).totalSalesAmount;
  @override
  int get pendingPurchaseCount => purchasesOverview.pendingPurchaseCount;
  @override
  int get purchasesRevision => _store._purchasesRevision;
  @override
  int get expensesRevision => _store._expensesRevision;
  @override
  PurchasesOverview get purchasesOverview =>
      _AppStorePurchaseInsights(_store)._purchasesOverviewImpl;
  @override
  ExpensesOverview get expensesOverview =>
      _AppStoreSplitSupplierInsights(_store).expensesOverview;
  @override
  double get totalPurchasesAmount => purchasesOverview.totalPurchasesAmount;
  @override
  double get totalExpensesAmount => expensesOverview.totalExpensesAmount;
  @override
  Customer get walkInCustomer => Customer(
        id: AppStore.walkInCustomerId,
        name: AppStore.walkInCustomerName,
        phone: '',
        address: '',
      );
  @override
  List<SaleQuotation> get saleQuotations =>
      _AppStoreSplitCoreLoading(_store).saleQuotations;
  @override
  List<DeliveryNote> get deliveryNotes =>
      _AppStoreSplitCoreLoading(_store).deliveryNotes;
  @override
  List<CreditNote> get creditNotes =>
      List<CreditNote>.unmodifiable(_store._creditNotes);
  @override
  Future<void> ensureCustomersLoaded() => _store._ensureCustomersLoadedImpl();
  @override
  Future<void> ensureSuppliersLoaded() => _store._ensureSuppliersLoadedImpl();
  @override
  Future<void> ensureSalesLoaded() =>
      _AppStoreSplitCoreLoading(_store).ensureSalesPageDataLoaded();
  @override
  Future<void> ensurePurchasesLoaded() =>
      _AppStoreSplitCoreLoading(_store).ensurePurchasesPageDataLoaded();
  @override
  Future<void> ensureQuotationsLoaded() =>
      _AppStoreSplitCoreLoading(_store).ensureQuotationsPageDataLoaded();
  @override
  Future<void> ensureDeliveryNotesLoaded() =>
      _AppStoreSplitCoreLoading(_store).ensureDeliveryNotesPageDataLoaded();
  @override
  Future<void> ensureCreditNotesLoaded() =>
      _AppStoreSplitCoreLoading(_store).ensureCreditNotesLoaded();
  @override
  String resolveCustomerName(String? customerId) =>
      _AppStorePartyRead(_store)._resolveCustomerNameReadImpl(customerId);
  @override
  String sanitizeSelectedCustomerId(String? customerId) =>
      _AppStorePartyRead(_store)._sanitizeSelectedCustomerIdReadImpl(
        customerId,
      );
  @override
  Future<void> addOrUpdateCustomer(Customer customer) =>
      _AppStoreSplitCatalogPartiesExpenses(_store)
          .addOrUpdateCustomer(customer);
  @override
  Future<void> deleteCustomer(String id) =>
      _AppStoreSplitCatalogPartiesExpensesPart2(_store).deleteCustomer(id);
  @override
  Future<void> addOrUpdateSupplier(Supplier supplier) =>
      _AppStoreSplitCatalogPartiesExpensesPart2(_store)
          .addOrUpdateSupplier(supplier);
  @override
  Future<void> deleteSupplier(String id) =>
      _AppStoreSplitCatalogPartiesExpensesPart2(_store).deleteSupplier(id);
  @override
  List<SupplierProductPrice> supplierProductPricesForProduct(
    String productId,
  ) =>
      _AppStoreSplitSupplierInsights(_store)
          .supplierProductPricesForProduct(productId);
  @override
  Future<void> addOrUpdateSupplierProductPrice(SupplierProductPrice price) =>
      _AppStoreSplitSupplierInsights(_store)
          .addOrUpdateSupplierProductPrice(price);
  @override
  Future<void> deleteSupplierProductPrice(String id) =>
      _AppStoreSplitSupplierInsights(_store).deleteSupplierProductPrice(id);
  @override
  Future<void> addOrUpdateExpense(Expense expense) =>
      _AppStoreSplitCatalogPartiesExpensesPart3(_store)
          .addOrUpdateExpense(expense);
  @override
  Future<void> createAndPostExpensesBulk(List<Expense> expenses) =>
      _AppStoreSplitCatalogPartiesExpensesPart3(_store)
          .createAndPostExpensesBulk(expenses);
  @override
  Future<void> postExpense(
    String id, {
    bool paidInCash = true,
    double? cashPaidAmount,
  }) =>
      _AppStoreSplitCatalogPartiesExpensesPart3(_store).postExpense(
        id,
        paidInCash: paidInCash,
        cashPaidAmount: cashPaidAmount,
      );
  @override
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
  }) =>
      _AppStoreSplitCatalogPartiesExpensesPart3(_store).editPostedExpense(
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
  @override
  Future<void> deleteDraftExpense(String id) =>
      _AppStoreSplitCatalogPartiesExpensesPart3(_store).deleteDraftExpense(id);
  @override
  Future<void> cancelExpense(String id, {String reason = ''}) =>
      _AppStoreSplitCatalogPartiesExpensesPart3(_store)
          .cancelExpense(id, reason: reason);
  @override
  Future<Sale> convertSaleQuotationToSale(
    String quotationId, {
    String paymentMethod = 'Cash',
    String paymentStatus = 'paid',
  }) =>
      _AppStoreSplitSalesReturns(_store).convertSaleQuotationToSale(
        quotationId,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
      );
  @override
  DeliveryNote? deliveryNoteForSale(String saleId) =>
      _AppStoreSplitSalesReturns(_store).deliveryNoteForSale(saleId);
  @override
  Future<DeliveryNote> createDeliveryNoteFromSale(
    String saleId, {
    String note = '',
  }) =>
      _AppStoreSplitSalesReturns(_store)
          .createDeliveryNoteFromSale(saleId, note: note);
  @override
  Future<void> markDeliveryNoteDelivered(String id) =>
      _AppStoreSplitSalesReturns(_store).markDeliveryNoteDelivered(id);
  @override
  Future<void> deleteDeliveryNote(String id) =>
      _AppStoreSplitSalesReturns(_store).deleteDeliveryNote(id);
  @override
  double? lastPurchasePriceFor({
    required String productId,
    required String supplierId,
  }) =>
      _AppStorePurchaseInsights(_store)._lastPurchasePriceForImpl(
        productId: productId,
        supplierId: supplierId,
      );
  @override
  double? lastPurchasePriceForProduct(String productId) =>
      _AppStorePurchaseInsights(_store)
          ._lastPurchasePriceForProductImpl(productId);
  @override
  SupplierProductPrice? supplierProductPriceFor({
    required String productId,
    required String supplierId,
  }) =>
      _AppStoreSplitSupplierInsights(_store).supplierProductPriceFor(
        productId: productId,
        supplierId: supplierId,
      );
  @override
  int supplierCountForProduct(String productId) =>
      _AppStoreSplitSupplierInsights(_store).supplierCountForProduct(productId);

  @override
  Future<Sale> settleSalePayment({
    required String saleId,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreSplitWarehouseCashPart4(_store).settleSalePayment(
        saleId: saleId,
        amount: amount,
        discount: discount,
        paymentMethod: paymentMethod,
        notes: notes,
        idempotencyKey: idempotencyKey,
        date: date,
      );

  @override
  Future<Purchase> settlePurchasePayment({
    required String purchaseId,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreSplitWarehouseCashPart4(_store).settlePurchasePayment(
        purchaseId: purchaseId,
        amount: amount,
        discount: discount,
        paymentMethod: paymentMethod,
        notes: notes,
        idempotencyKey: idempotencyKey,
        date: date,
      );

  @override
  Future<void> normalizeRefundAllocations() =>
      _AppStoreSplitWarehouseCashPart3(_store).normalizeRefundAllocations();

  @override
  Future<double> refundableSaleCashAmount(String saleId) =>
      _AppStoreSplitWarehouseCashPart3(_store).refundableSaleCashAmount(saleId);

  @override
  Future<double> refundablePurchaseCashAmount(String purchaseId) =>
      _AppStoreSplitWarehouseCashPart3(_store)
          .refundablePurchaseCashAmount(purchaseId);

  @override
  Future<double> refundablePurchaseReturnCashAmount(String purchaseReturnId) =>
      _AppStoreSplitWarehouseCashPart3(_store)
          .refundablePurchaseReturnCashAmount(purchaseReturnId);

  @override
  Future<double> refundSaleCash({
    required String saleId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreSplitWarehouseCashPart3(_store).refundSaleCash(
        saleId: saleId,
        amount: amount,
        notes: notes,
        idempotencyKey: idempotencyKey,
        date: date,
      );

  @override
  Future<double> refundPurchaseCash({
    required String purchaseId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreSplitWarehouseCashPart3(_store).refundPurchaseCash(
        purchaseId: purchaseId,
        amount: amount,
        notes: notes,
        idempotencyKey: idempotencyKey,
        date: date,
      );

  @override
  Future<double> refundPurchaseReturnCash({
    required String purchaseReturnId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreSplitWarehouseCashPart3(_store).refundPurchaseReturnCash(
        purchaseReturnId: purchaseReturnId,
        amount: amount,
        notes: notes,
        idempotencyKey: idempotencyKey,
        date: date,
      );

  @override
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
  }) =>
      _AppStoreSplitSalesReturnsPart2(_store).createSale(
        customerName: customerName,
        customerId: customerId,
        items: items,
        discount: discount,
        originalDiscount: originalDiscount,
        discountCurrency: discountCurrency,
        discountExchangeRateAtEntry: discountExchangeRateAtEntry,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        invoiceCurrency: invoiceCurrency,
        paymentCurrency: paymentCurrency,
        exchangeRateAtPayment: exchangeRateAtPayment,
        paidAmount: paidAmount,
        cashReceivedAmount: cashReceivedAmount,
        paidAmountInPaymentCurrency: paidAmountInPaymentCurrency,
        cashReceivedAmountInPaymentCurrency:
            cashReceivedAmountInPaymentCurrency,
        warehouseId: warehouseId,
        warehouseName: warehouseName,
      );

  @override
  Future<CreditNote> returnSale(
    String id, {
    bool restoreStock = true,
    Map<String, double>? returnedQuantities,
  }) =>
      _AppStoreSplitSalesReturnsPart5(_store).returnSale(
        id,
        restoreStock: restoreStock,
        returnedQuantities: returnedQuantities,
      );

  @override
  Future<void> cancelSale(
    String id, {
    String status = 'Cancelled',
    bool restoreStock = true,
  }) =>
      _AppStoreSplitSalesReturnsPart8(_store).cancelSale(
        id,
        status: status,
        restoreStock: restoreStock,
      );

  @override
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
  }) =>
      _AppStoreSplitSalesReturnsPart3(_store).editPostedSale(
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

  @override
  Future<CreditNote> editSaleReturn({
    required String creditNoteId,
    required int expectedVersion,
    required Map<String, double> returnedQuantities,
  }) =>
      _AppStoreSplitSalesReturnsPart6(_store).editSaleReturn(
        creditNoteId: creditNoteId,
        expectedVersion: expectedVersion,
        returnedQuantities: returnedQuantities,
      );

  @override
  Future<SaleQuotation> createSaleQuotation({
    required String customerName,
    String customerId = '',
    required List<SaleItem> items,
    double discount = 0,
    String invoiceCurrency = 'USD',
    String note = '',
    DateTime? validUntil,
  }) =>
      _AppStoreSplitSalesReturns(_store).createSaleQuotation(
        customerName: customerName,
        customerId: customerId,
        items: items,
        discount: discount,
        invoiceCurrency: invoiceCurrency,
        note: note,
        validUntil: validUntil,
      );

  @override
  Future<void> deleteSaleQuotation(String id) =>
      _AppStoreSplitSalesReturns(_store).deleteSaleQuotation(id);

  @override
  Future<CreditNote> cancelSaleReturn({
    required String creditNoteId,
    required int expectedVersion,
  }) =>
      _AppStoreSplitSalesReturnsPart7(_store).cancelSaleReturn(
        creditNoteId: creditNoteId,
        expectedVersion: expectedVersion,
      );

  @override
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
  }) =>
      _AppStoreSplitPurchasesPart2(_store).createPurchase(
        supplierId: supplierId,
        supplierName: supplierName,
        items: items,
        receiveNow: receiveNow,
        note: note,
        paymentStatus: paymentStatus,
        paymentMethod: paymentMethod,
        paidAmount: paidAmount,
        warehouseId: warehouseId,
        warehouseName: warehouseName,
      );

  @override
  Future<Purchase> createPurchaseReturn({
    required String sourcePurchaseId,
    required List<PurchaseItem> items,
    String reason = '',
  }) =>
      _AppStoreSplitPurchasesPart6(_store).createPurchaseReturn(
        sourcePurchaseId: sourcePurchaseId,
        items: items,
        reason: reason,
      );

  @override
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
  }) =>
      _AppStoreSplitPurchasesPart3(_store).updatePurchaseDraft(
        purchaseId: purchaseId,
        expectedVersion: expectedVersion,
        supplierId: supplierId,
        supplierName: supplierName,
        items: items,
        paymentStatus: paymentStatus,
        paymentMethod: paymentMethod,
        paidAmount: paidAmount,
        warehouseId: warehouseId,
        warehouseName: warehouseName,
      );

  @override
  Future<void> receivePurchase(
    String id, {
    bool settleInitialPayment = true,
    bool postAccounting = true,
    Map<int, List<BatchAllocation>> batchAllocationsByLine =
        const <int, List<BatchAllocation>>{},
  }) =>
      _AppStoreSplitPurchasesPart4(_store).receivePurchase(
        id,
        settleInitialPayment: settleInitialPayment,
        postAccounting: postAccounting,
        batchAllocationsByLine: batchAllocationsByLine,
      );

  @override
  Future<Purchase> editPurchaseReturn({
    required String purchaseId,
    required int expectedVersion,
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    String warehouseId = '',
    String warehouseName = '',
  }) =>
      _AppStoreSplitPurchasesPart5(_store).editPurchaseReturn(
        purchaseId: purchaseId,
        expectedVersion: expectedVersion,
        supplierId: supplierId,
        supplierName: supplierName,
        items: items,
        warehouseId: warehouseId,
        warehouseName: warehouseName,
      );

  @override
  Future<void> deleteDraftPurchase(String id) =>
      _AppStoreSplitPurchasesPart4(_store).deleteDraftPurchase(id);

  @override
  Future<void> returnPurchase(
    String id, {
    bool reverseStock = true,
    String reason = '',
    bool recordSupplierReturnLedger = true,
  }) =>
      _AppStoreSplitPurchasesPart7(_store).returnPurchase(
        id,
        reverseStock: reverseStock,
        reason: reason,
        recordSupplierReturnLedger: recordSupplierReturnLedger,
      );

  @override
  Future<void> cancelPurchase(
    String id, {
    bool reverseStock = true,
    String reason = '',
  }) =>
      _AppStoreSplitPurchasesPart7(_store).cancelPurchase(
        id,
        reverseStock: reverseStock,
        reason: reason,
      );

  @override
  List<SupplierPurchasePrice> purchasePriceHistoryForProduct(
    String productId,
  ) =>
      _AppStorePurchaseInsights(_store)
          ._purchasePriceHistoryForProductImpl(productId);

  @override
  List<SupplierPurchasePrice> supplierPriceComparisonForProduct(
    String productId,
  ) =>
      _AppStorePurchaseInsights(_store)
          ._supplierPriceComparisonForProductImpl(productId);

  @override
  PurchaseItem? lastPurchaseItemFor({
    required String productId,
    required String supplierId,
  }) =>
      _AppStorePurchaseInsights(_store)._lastPurchaseItemForImpl(
        productId: productId,
        supplierId: supplierId,
      );

  @override
  PurchaseItem? lastPurchaseItemForProduct(String productId) =>
      _AppStorePurchaseInsights(_store)
          ._lastPurchaseItemForProductImpl(productId);

  @override
  double averagePurchaseCostForProduct(String productId) =>
      _AppStorePurchaseInsights(_store)
          ._averagePurchaseCostForProductImpl(productId);

  @override
  double estimateProfit() =>
      _AppStoreSplitSalesReturnsPart8(_store).estimateProfit();

  @override
  Future<Purchase?> reloadPurchaseFromSqlite(String id) =>
      _AppStoreSplitPersistenceSyncCore(_store).reloadPurchaseFromSqlite(id);

  @override
  Future<double> refundableExpenseCashAmount(String expenseId) =>
      _AppStoreSplitWarehouseCashPart4(_store)
          .refundableExpenseCashAmount(expenseId);

  @override
  Future<double> refundExpenseCash({
    required String expenseId,
    double? amount,
    String notes = '',
  }) =>
      _AppStoreSplitWarehouseCashPart4(_store).refundExpenseCash(
        expenseId: expenseId,
        amount: amount,
        notes: notes,
      );
}

final class _AccountingDomain implements AccountingDomainPort {
  _AccountingDomain(this._store);
  final AppStore _store;

  @override
  List<AccountTransaction> get transactions =>
      _store._accountTransactionsReadImpl;
  @override
  Future<void> ensureLoaded() => _store._ensureAccountTransactionsLoadedImpl();
  @override
  int get revision => _store._accountingRevisionReadImpl;
  @override
  int get ledgerRevision => _store._accountTransactionsRevision;
  @override
  double accountBalance(String accountType, String accountId) =>
      _store._accountBalanceReadImpl(accountType, accountId);
  @override
  List<AccountTransaction> transactionsForAccount(
    String accountType,
    String accountId,
  ) =>
      _store._accountTransactionsForAccountReadImpl(accountType, accountId);
  @override
  Future<void> refreshFromSqlite() =>
      _AppStoreSplitStartupMigrationsPart2(_store)
          .refreshAccountTransactionsFromSqlite();
  @override
  Future<void> settleAccountPayment({
    required String accountType,
    required String accountId,
    required String accountName,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String referenceNo = '',
    String notes = '',
    List<PaymentAllocationDraft> allocations = const <PaymentAllocationDraft>[],
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreSplitWarehouseCashPart4(_store).settleAccountPayment(
        accountType: accountType,
        accountId: accountId,
        accountName: accountName,
        amount: amount,
        discount: discount,
        paymentMethod: paymentMethod,
        referenceNo: referenceNo,
        notes: notes,
        allocations: allocations,
        idempotencyKey: idempotencyKey,
        date: date,
      );
  @override
  Future<void> updateTaxConfiguration({
    required List<TaxProfile> profiles,
    required String defaultTaxProfileId,
  }) =>
      _AppStoreSplitPersistenceSyncCorePart3(_store).updateTaxConfiguration(
        profiles: profiles,
        defaultTaxProfileId: defaultTaxProfileId,
      );
  @override
  Future<void> updateDefaultTaxRatePercent(double ratePercent) =>
      _AppStoreSplitPersistenceSyncCorePart3(_store)
          .updateDefaultTaxRatePercent(ratePercent);
}

final class _InventoryDomain implements InventoryDomainPort {
  _InventoryDomain(this._store);
  final AppStore _store;

  @override
  List<Warehouse> get warehouses => _store._warehousesReadImpl;
  @override
  InventoryCostingMethod get inventoryCostingMethod =>
      _store._inventoryCostingMethod;
  @override
  List<StockMovement> get stockMovements => _store._stockMovementsReadImpl;
  @override
  List<StockMovement> get autoCorrectionMovements =>
      const InventoryReadService()
          .autoCorrectionMovements(_store._stockMovementsReadImpl);
  @override
  List<StockMovement> get pendingAutoCorrectionMovements =>
      const InventoryReadService()
          .pendingAutoCorrectionMovements(_store._stockMovementsReadImpl);
  @override
  List<BillOfMaterials> get billsOfMaterials =>
      _AppStoreSplitCoreLoading(_store).billsOfMaterials;
  @override
  List<ManufacturingOrder> get manufacturingOrders =>
      _AppStoreSplitCoreLoading(_store).manufacturingOrders;
  @override
  List<InventoryCountSession> get inventoryCountSessions =>
      _AppStoreSplitCoreLoading(_store).inventoryCountSessions;
  @override
  InventoryCountSession? get activeInventoryCountSession =>
      _AppStoreSplitCoreLoading(_store).activeInventoryCountSession;
  @override
  int get revision => _store._inventoryRevisionReadImpl;
  @override
  double get inventoryRetailValue =>
      _AppStoreCatalogRead(_store)._stockTrackedProductsReadImpl
          .fold<double>(0, (sum, item) => sum + (item.usdPrice * item.stock));
  @override
  int get lowStockCount => _store._productsReadImpl
      .where((product) => product.trackStock && product.isLowStock)
      .length;
  @override
  double get inventoryCostValue =>
      _AppStoreCatalogRead(_store)._stockTrackedProductsReadImpl.fold<double>(
            0,
            (sum, product) =>
                sum + (_store._safeUsdCost(product) * product.stock),
          );
  @override
  String get saleWarehouseId =>
      _AppStoreSplitCoreLoading(_store).saleWarehouseId;
  @override
  Future<void> setSaleWarehouseId(String warehouseId) =>
      _AppStoreSplitCoreLoading(_store).setSaleWarehouseId(warehouseId);
  @override
  Future<void> setInventoryCostingMethod(
    InventoryCostingMethod method, {
    String reason = '',
  }) =>
      _AppStoreSplitPricingCostingPart2(_store)
          .setInventoryCostingMethod(method, reason: reason);
  @override
  Future<void> ensureLoaded() => _store._ensureInventoryPageDataLoadedImpl();
  @override
  Future<void> ensureWarehousesLoaded() => _store._ensureWarehousesLoadedImpl();
  @override
  Warehouse resolveWarehouseForSale({String warehouseId = ''}) =>
      _AppStoreSplitCoreLoading(_store)
          .resolveWarehouseForSale(warehouseId: warehouseId);
  @override
  Warehouse resolveWarehouseForPurchase({String warehouseId = ''}) =>
      _AppStoreSplitCoreLoading(_store)
          .resolveWarehouseForPurchase(warehouseId: warehouseId);
  @override
  double stockForWarehouse(String productId, String warehouseId) =>
      _AppStoreSplitCoreLoadingPart2(_store)
          .stockForWarehouse(productId, warehouseId);
  @override
  Future<double> warehouseStockFromSqlite(
    String productId, {
    String warehouseId = '',
  }) =>
      _AppStoreSplitCoreLoadingPart2(_store)
          .warehouseStockFromSqlite(productId, warehouseId: warehouseId);
  @override
  Future<Map<String, Map<String, double>>> warehouseStockBalancesFromSqlite() =>
      _AppStoreSplitCoreLoadingPart2(_store).warehouseStockBalancesFromSqlite();
  @override
  Future<Warehouse> createWarehouse({
    required String name,
    String code = '',
    String location = '',
  }) =>
      _AppStoreSplitWarehouseCash(_store).createWarehouse(
        name: name,
        code: code,
        location: location,
      );
  @override
  Future<void> reviewAutoCorrection(String movementId, {String note = ''}) =>
      _AppStoreSplitInventoryPart2(_store)
          .reviewAutoCorrection(movementId, note: note);
  @override
  Future<void> setExpiryBatchStatus(String batchId, String status) =>
      _AppStoreSplitInventoryPart2(_store)
          .setExpiryBatchStatus(batchId, status);
  @override
  Future<void> reverseExpiryBatchAdjustment(
    String movementId, {
    String reason = '',
  }) =>
      _AppStoreSplitInventoryPart3(_store)
          .reverseExpiryBatchAdjustment(movementId, reason: reason);
  @override
  Future<void> adjustExpiryBatchStock({
    required String productId,
    required String warehouseId,
    required String batchId,
    required double quantityDelta,
    required String reason,
    String adjustmentCategory = 'other',
  }) =>
      _AppStoreSplitInventoryPart2(_store).adjustExpiryBatchStock(
        productId: productId,
        warehouseId: warehouseId,
        batchId: batchId,
        quantityDelta: quantityDelta,
        reason: reason,
        adjustmentCategory: adjustmentCategory,
      );
  @override
  Future<int> manualStockAdjustmentVersion(String operationReferenceId) =>
      _AppStoreSplitInventoryPart3(_store)
          .manualStockAdjustmentVersion(operationReferenceId);
  @override
  Future<void> editStockAdjustment({
    required String operationReferenceId,
    required int expectedVersion,
    required double quantityDelta,
    required String reason,
    String adjustmentCategory = 'other',
    String notes = '',
    String evidenceRef = '',
    List<BatchAllocation> batchAllocations = const <BatchAllocation>[],
  }) =>
      _AppStoreSplitInventoryPart4(_store).editStockAdjustment(
        operationReferenceId: operationReferenceId,
        expectedVersion: expectedVersion,
        quantityDelta: quantityDelta,
        reason: reason,
        adjustmentCategory: adjustmentCategory,
        notes: notes,
        evidenceRef: evidenceRef,
        batchAllocations: batchAllocations,
      );
  @override
  Future<void> recordWasteLoss({
    required String productId,
    required String warehouseId,
    required double quantity,
    required String reason,
    String adjustmentCategory = 'other',
    String notes = '',
  }) =>
      _AppStoreSplitInventoryPart5(_store).recordWasteLoss(
        productId: productId,
        warehouseId: warehouseId,
        quantity: quantity,
        reason: reason,
        adjustmentCategory: adjustmentCategory,
        notes: notes,
      );
  @override
  Future<void> deleteWasteLoss(String movementId) =>
      _AppStoreSplitInventoryPart6(_store).deleteWasteLoss(movementId);
  @override
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
  }) =>
      _AppStoreSplitInventoryPart5(_store).adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantityDelta: quantityDelta,
        reason: reason,
        adjustmentCategory: adjustmentCategory,
        notes: notes,
        evidenceRef: evidenceRef,
        batchAllocations: batchAllocations,
        operationReferenceId: operationReferenceId,
      );
  @override
  Future<InventoryCountSession> createInventoryCountSession({
    String notes = '',
    String warehouseId = '',
    String warehouseName = '',
  }) =>
      _AppStoreSplitInventory(_store).createInventoryCountSession(
        notes: notes,
        warehouseId: warehouseId,
        warehouseName: warehouseName,
      );
  @override
  Future<void> countInventoryLine({
    required String sessionId,
    required String productId,
    required double countedQty,
    String note = '',
  }) =>
      _AppStoreSplitInventory(_store).countInventoryLine(
        sessionId: sessionId,
        productId: productId,
        countedQty: countedQty,
        note: note,
      );
  @override
  Future<void> resetInventoryCountLine({
    required String sessionId,
    required String productId,
  }) =>
      _AppStoreSplitInventory(_store).resetInventoryCountLine(
        sessionId: sessionId,
        productId: productId,
      );
  @override
  Future<void> approveInventoryCount(String sessionId) =>
      _AppStoreSplitInventory(_store).approveInventoryCount(sessionId);
  @override
  Future<void> reverseInventoryCount(String sessionId, {String reason = ''}) =>
      _AppStoreSplitInventoryPart2(_store)
          .reverseInventoryCount(sessionId, reason: reason);
  @override
  Future<void> cancelInventoryCount(String sessionId) =>
      _AppStoreSplitInventoryPart2(_store).cancelInventoryCount(sessionId);
  @override
  Future<ManufacturingOrder> startManufacturingOrder({
    required String bomId,
    required double quantity,
    String rawMaterialsWarehouseId = '',
    String rawMaterialsWarehouseName = '',
    String finishedGoodsWarehouseId = '',
    String finishedGoodsWarehouseName = '',
    String notes = '',
  }) =>
      _AppStoreSplitManufacturingPart2(_store).startManufacturingOrder(
        bomId: bomId,
        quantity: quantity,
        rawMaterialsWarehouseId: rawMaterialsWarehouseId,
        rawMaterialsWarehouseName: rawMaterialsWarehouseName,
        finishedGoodsWarehouseId: finishedGoodsWarehouseId,
        finishedGoodsWarehouseName: finishedGoodsWarehouseName,
        notes: notes,
      );
  @override
  Future<ManufacturingOrder> reverseManufacturingOrder({
    required String orderId,
    required String reason,
  }) =>
      _AppStoreSplitManufacturingPart5(_store)
          .reverseManufacturingOrder(orderId: orderId, reason: reason);

  @override
  Future<BillOfMaterials> estimateBillOfMaterialsSnapshot(
    BillOfMaterials bom, {
    String warehouseId = '',
  }) =>
      _AppStoreSplitManufacturing(_store)
          .estimateBillOfMaterialsSnapshot(bom, warehouseId: warehouseId);

  @override
  Future<double> estimateBillOfMaterialsUnitCost(
    BillOfMaterials bom, {
    String warehouseId = '',
  }) =>
      _AppStoreSplitManufacturing(_store)
          .estimateBillOfMaterialsUnitCost(bom, warehouseId: warehouseId);

  @override
  Future<BillOfMaterials> createBillOfMaterials({
    required String name,
    required String outputProductId,
    required double outputQuantity,
    required List<BillOfMaterialsLine> components,
    String notes = '',
  }) =>
      _AppStoreSplitManufacturing(_store).createBillOfMaterials(
        name: name,
        outputProductId: outputProductId,
        outputQuantity: outputQuantity,
        components: components,
        notes: notes,
      );

  @override
  Future<BillOfMaterials> updateBillOfMaterials({
    required String id,
    required String name,
    required String outputProductId,
    required double outputQuantity,
    required List<BillOfMaterialsLine> components,
    String notes = '',
  }) =>
      _AppStoreSplitManufacturing(_store).updateBillOfMaterials(
        id: id,
        name: name,
        outputProductId: outputProductId,
        outputQuantity: outputQuantity,
        components: components,
        notes: notes,
      );

  @override
  Future<void> deleteBillOfMaterials(String id) =>
      _AppStoreSplitManufacturing(_store).deleteBillOfMaterials(id);

  @override
  Future<void> deleteManufacturingOrder(String id) =>
      _AppStoreSplitManufacturing(_store).deleteManufacturingOrder(id);

  @override
  Future<ManufacturingOrder> updateManufacturingOrder({
    required String id,
    required String bomId,
    required double quantity,
    required String rawMaterialsWarehouseId,
    required String rawMaterialsWarehouseName,
    required String finishedGoodsWarehouseId,
    required String finishedGoodsWarehouseName,
    String notes = '',
  }) =>
      _AppStoreSplitManufacturingPart2(_store).updateManufacturingOrder(
        id: id,
        bomId: bomId,
        quantity: quantity,
        rawMaterialsWarehouseId: rawMaterialsWarehouseId,
        rawMaterialsWarehouseName: rawMaterialsWarehouseName,
        finishedGoodsWarehouseId: finishedGoodsWarehouseId,
        finishedGoodsWarehouseName: finishedGoodsWarehouseName,
        notes: notes,
      );

  @override
  Future<ManufacturingOrder> finishManufacturingOrder({
    required String orderId,
    required double actualQuantity,
    List<BatchAllocation> outputBatchAllocations = const <BatchAllocation>[],
    Map<String, double> actualConsumedQuantities = const <String, double>{},
    Map<String, double> wasteQuantities = const <String, double>{},
    Map<String, String> wasteReasons = const <String, String>{},
  }) =>
      _AppStoreSplitManufacturingPart2(_store).finishManufacturingOrder(
        orderId: orderId,
        actualQuantity: actualQuantity,
        outputBatchAllocations: outputBatchAllocations,
        actualConsumedQuantities: actualConsumedQuantities,
        wasteQuantities: wasteQuantities,
        wasteReasons: wasteReasons,
      );

  @override
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
  }) =>
      _AppStoreSplitManufacturingPart4(_store).editCompletedManufacturingOrder(
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

  @override
  Future<double> estimatedUnifiedBatchUnitCostForProduct(
    Product product, {
    String warehouseId = '',
    double requiredQuantity = 0,
  }) =>
      _AppStoreSplitManufacturing(_store)
          .estimatedUnifiedBatchUnitCostForProduct(
        product,
        warehouseId: warehouseId,
        requiredQuantity: requiredQuantity,
      );
  @override
  Future<WarehouseTransferOrder> createWarehouseTransferOrder({
    required String fromWarehouseId,
    required String toWarehouseId,
    required List<WarehouseTransferOrderItem> items,
    String notes = '',
  }) =>
      _AppStoreSplitWarehouseCash(_store).createWarehouseTransferOrder(
        fromWarehouseId: fromWarehouseId,
        toWarehouseId: toWarehouseId,
        items: items,
        notes: notes,
      );
  @override
  Future<WarehouseTransferOrder> editWarehouseTransferOrder({
    required String orderId,
    required int expectedVersion,
    required String fromWarehouseId,
    required String toWarehouseId,
    required List<WarehouseTransferOrderItem> items,
    String? notes,
    DateTime? date,
  }) =>
      _AppStoreSplitWarehouseCashPart2(_store).editWarehouseTransferOrder(
        orderId: orderId,
        expectedVersion: expectedVersion,
        fromWarehouseId: fromWarehouseId,
        toWarehouseId: toWarehouseId,
        items: items,
        notes: notes,
        date: date,
      );

  @override
  Future<List<WarehouseTransferOrder>> recentTransferOrders(
          {int limit = 100}) =>
      _AppStoreSplitWarehouseCash(_store)
          .recentWarehouseTransferOrders(limit: limit);
  @override
  Future<Map<String, dynamic>> traceBatch(
    String batchId, {
    int maxDepth = 8,
  }) =>
      _store._traceInventoryBatchDomainImpl(batchId, maxDepth: maxDepth);
  @override
  Future<Map<String, dynamic>> verifyTraceabilityIntegrity() =>
      _store._verifyInventoryTraceabilityIntegrityDomainImpl();
}

final class _SecurityDomain implements SecurityDomainPort {
  _SecurityDomain(this._store);
  final AppStore _store;

  @override
  AppUser? get activeUser => _store._activeUserReadImpl;
  @override
  AppUser? get currentUser => _store._activeUserReadImpl;
  @override
  String get currentRole => _store._currentRoleReadImpl;
  @override
  List<AppUser> get users => List<AppUser>.unmodifiable(_store._users);
  @override
  List<UserRole> get roles => List<UserRole>.unmodifiable(_store._roles);
  @override
  UserRole? roleById(String id) {
    for (final role in _store._roles) {
      if (role.id == id) return role;
    }
    return null;
  }

  @override
  bool get rememberLogin => _store._rememberLogin;
  @override
  bool get hasLocalAdminUser =>
      _store._users.any((item) => item.roleId == 'admin' && item.isActive);
  @override
  AppUser? get storeOwnerUser =>
      _AppStoreSplitIdentityUsersPart2(_store).storeOwnerUser;
  @override
  bool canAccessPage(String pageId) => _store._canAccessPageReadImpl(pageId);
  @override
  bool hasPermission(String permission) =>
      _store._hasPermissionReadImpl(permission);
  @override
  bool hasAnyPermission(Iterable<String> permissions) =>
      permissions.any(_store._hasPermissionReadImpl);
  @override
  bool get canViewDashboard => canAccessPage('dashboard');
  @override
  bool get canViewProducts => hasAnyPermission(const <String>{
        AppPermission.productsView,
        AppPermission.productsManage,
        AppPermission.productsCreate,
        AppPermission.productsEdit,
        AppPermission.productsDelete,
      });
  @override
  bool get canManageProducts => hasAnyPermission(const <String>{
        AppPermission.productsManage,
        AppPermission.productsCreate,
        AppPermission.productsEdit,
        AppPermission.productsDelete,
      });
  @override
  bool get canViewCustomers => hasAnyPermission(const <String>{
        AppPermission.customersView,
        AppPermission.customersManage,
      });
  @override
  bool get canManageCustomers => hasPermission(AppPermission.customersManage);
  @override
  bool get canManageCustomerPayments =>
      hasPermission(AppPermission.customersPaymentManage);
  @override
  bool get canViewSuppliers => hasAnyPermission(const <String>{
        AppPermission.suppliersView,
        AppPermission.suppliersManage,
      });
  @override
  bool get canManageSuppliers => hasPermission(AppPermission.suppliersManage);
  @override
  bool get canManageSupplierPayments =>
      hasPermission(AppPermission.suppliersPaymentManage);
  @override
  bool get canViewSales => hasAnyPermission(const <String>{
        AppPermission.salesView,
        AppPermission.salesCreate,
        AppPermission.salesEdit,
        AppPermission.salesCancel,
      });
  @override
  bool get canSell => hasPermission(AppPermission.salesCreate);
  @override
  bool get canViewQuotations => canAccessPage('quotations');
  @override
  bool get canManageQuotations => hasPermission(AppPermission.quotationsManage);
  @override
  bool get canViewDeliveryNotes => canAccessPage('delivery_notes');
  @override
  bool get canManageDeliveryNotes =>
      hasPermission(AppPermission.deliveryNotesManage);
  @override
  bool get canViewPurchases => canAccessPage('purchases');
  @override
  bool get canManagePurchases => hasPermission(AppPermission.purchasesManage);
  @override
  bool get canViewExpenses => canAccessPage('expenses');
  @override
  bool get canManageExpenses => hasPermission(AppPermission.expensesManage);
  @override
  bool get canViewAccounting => canAccessPage('accounting');
  @override
  bool get canManageAccounting => hasPermission(AppPermission.accountingManage);
  @override
  bool get canManageCashBox => hasPermission(AppPermission.cashBoxManage);
  @override
  bool get canViewInventory => canAccessPage('inventory');
  @override
  bool get canManageInventory => hasAnyPermission(const <String>{
        AppPermission.inventoryWarehousesManage,
        AppPermission.inventoryCorrectionsManage,
        AppPermission.inventoryCountsManage,
        AppPermission.inventoryWasteManage,
        AppPermission.inventoryManufacturingManage,
      });
  @override
  bool get canViewReports => canAccessPage('reports');
  @override
  bool get canViewCashBox => canAccessPage('cash_box') || canViewAccounting;
  @override
  bool get canViewSettings => canAccessPage('settings');
  @override
  bool get canViewDatabase => canAccessPage('database');
  @override
  bool get canViewMaintenance => canAccessPage('maintenance');
  @override
  bool get canManageMaintenance =>
      hasPermission(AppPermission.maintenanceManage);
  @override
  bool get canManageUsers => hasAnyPermission(
        const <String>{AppPermission.usersManage, AppPermission.rolesManage},
      );
  @override
  bool get canManageUsersPage => canManageUsers;
  @override
  bool get canManageDatabase => hasPermission(AppPermission.databaseManage);
  @override
  bool get canDeleteOrCancel => hasPermission(AppPermission.salesCancel);
  @override
  void requirePermission(String permission) =>
      _store._requirePermissionReadImpl(permission);
  @override
  void requireAnyPermission(Iterable<String> permissions) {
    final required = permissions.toList(growable: false);
    if (required.isEmpty || !hasAnyPermission(required)) {
      throw StateError(
        'You do not have any required permission: ${required.join(', ')}',
      );
    }
  }

  @override
  void requireAllPermissions(Iterable<String> permissions) {
    for (final permission in permissions) {
      requirePermission(permission);
    }
  }

  @override
  Future<bool> authorizeSensitiveAction({
    required String action,
    required String password,
    Duration validity = const Duration(minutes: 3),
  }) =>
      _store._authorizeSensitiveActionDomainImpl(
        action: action,
        password: password,
        validity: validity,
      );
  @override
  void requireSensitiveActionAuthorization(String action) =>
      _store._requireSensitiveActionAuthorizationDomainImpl(action);
  @override
  void clearSensitiveActionAuthorization() =>
      _store._clearSensitiveActionAuthorizationDomainImpl();

  @override
  bool get needsInitialAdminSetup =>
      _store._users.isEmpty || _store._hasOnlyLegacyDefaultAdminUser;

  @override
  Future<bool> login(
    String username,
    String password, {
    bool remember = false,
  }) =>
      _AppStoreSplitIdentityUsersPart2(_store)
          .login(username, password, remember: remember);

  @override
  Future<void> logout() => _AppStoreSplitIdentityUsersPart2(_store).logout();

  @override
  Future<bool> applySupportPasswordResetToLocalUser({
    required String username,
    required String newPassword,
  }) =>
      _AppStoreSplitIdentityUsersPart2(_store)
          .applySupportPasswordResetToLocalUser(
        username: username,
        newPassword: newPassword,
      );

  @override
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
      _AppStoreSplitAccessAuth(_store).recoverOnlineStoreOwnerIdentity(
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
        activateUser: activateUser,
      );

  @override
  Future<void> applySessionUser({
    required AppUser activeUser,
    required String currentRole,
    required Set<String> permissions,
    required bool rememberLogin,
  }) =>
      _AppStoreSplitIdentityUsersPart2(_store).applySessionUser(
        activeUser: activeUser,
        currentRole: currentRole,
        permissions: permissions,
        rememberLogin: rememberLogin,
      );

  @override
  Future<void> clearSessionUser() =>
      _AppStoreSplitIdentityUsersPart2(_store).clearSessionUser();

  @override
  Future<void> addOrUpdateRole(UserRole role) =>
      _AppStoreSplitIdentityUsersPart2(_store).addOrUpdateRole(role);

  @override
  Future<void> deleteRole(String id) =>
      _AppStoreSplitIdentityUsersPart2(_store).deleteRole(id);

  @override
  Future<void> addOrUpdateUser(AppUser user, {String? password}) =>
      _AppStoreSplitIdentityUsersPart3(_store)
          .addOrUpdateUser(user, password: password);

  @override
  Future<void> deleteUser(String id) =>
      _AppStoreSplitIdentityUsersPart3(_store).deleteUser(id);

  @override
  Future<bool> verifyAdminPassword(String password) =>
      _AppStoreSplitIdentityUsersPart2(_store).verifyAdminPassword(password);

  @override
  Future<void> applyStoreOwnerCredentials({
    required String username,
    required String password,
    String? fullName,
  }) =>
      _AppStoreSplitIdentityUsersPart3(_store).applyStoreOwnerCredentials(
        username: username,
        password: password,
        fullName: fullName,
      );

  @override
  Future<void> completeInitialAdminSetup({
    required String fullName,
    required String username,
    required String password,
  }) =>
      _AppStoreSplitAccessAuth(_store).completeInitialAdminSetup(
        fullName: fullName,
        username: username,
        password: password,
      );
}

final class _SyncDomain implements SyncDomainPort {
  _SyncDomain(this._store);
  final AppStore _store;

  @override
  String get deviceId => _store._deviceId;

  @override
  List<SyncChange> get changes => _store._syncChangesReadImpl;
  @override
  List<SyncQueueItem> get queue => _store._syncQueueReadImpl;
  @override
  List<SyncChange> get pendingChanges =>
      _AppStoreSplitCoreLoadingPart2(_store).pendingSyncChanges;
  @override
  List<SyncQueueItem> get pendingQueue =>
      _AppStoreSplitCoreLoadingPart2(_store).pendingSyncQueue;
  @override
  int get sequence => _store._syncSequence;
  @override
  int get pendingCount => pendingQueue.length;
  @override
  int get activeClientPendingCount =>
      _AppStoreSplitCoreLoadingPart2(_store).activeClientPendingSyncCount;
  @override
  int get latestStoredAuthoritativeSequence =>
      _store._latestStoredAuthoritativeSequence();
  @override
  List<DataConflict> get dataConflicts =>
      _AppStoreSplitCoreLoading(_store).dataConflicts;
  @override
  int get blockingDataConflictCount =>
      dataConflicts.where((item) => item.blocking).length;
  @override
  Map<String, dynamic>? get latestHostTransferNotification =>
      _AppStoreSplitIdentityUsers(_store).latestHostTransferNotification;

  @override
  DateTime? get latestResetAt =>
      _AppStoreSplitCoreLoadingPart2(_store).latestResetSyncAt;

  @override
  Future<void> ensureLoaded() => _store._requestSyncDataLoad();

  @override
  List<SyncChange> pendingChangesForTarget(
    String target, {
    bool readyOnly = true,
  }) =>
      _AppStoreSplitCoreLoadingPart2(_store)
          .pendingSyncChangesForTarget(target, readyOnly: readyOnly);

  @override
  List<SyncChange> submittedChangesForTarget(String target) =>
      _AppStoreSplitCoreLoadingPart2(_store)
          .submittedSyncChangesForTarget(target);

  @override
  String? validateClientDraftForHostAcceptance(SyncChange change) =>
      _AppStoreSplitStartupMigrationsPart3(_store)
          .validateClientDraftForHostAcceptance(change);

  @override
  Future<void> markPushInProgress(Iterable<String> changeIds) =>
      _AppStoreSplitSyncApplyPart4(_store)
          .markSyncQueueChangesInProgress(changeIds);

  @override
  Future<void> markSubmitted(Iterable<String> ids) =>
      _AppStoreSplitSyncApplyPart3(_store).markSyncChangesSubmittedByIds(ids);

  @override
  Future<void> markAcknowledged(Iterable<String> ids) =>
      _AppStoreSplitSyncApplyPart3(_store).markSyncChangesSyncedByIds(ids);

  @override
  Future<void> markFailed(Iterable<String> changeIds, String message) =>
      _AppStoreSplitSyncApplyPart4(_store)
          .markSyncQueueChangesFailed(changeIds, message);

  @override
  Future<void> markRejected(Map<String, String> rejected) =>
      _AppStoreSplitSyncApplyPart4(_store)
          .markSyncChangesRejectedByIds(rejected);

  @override
  Future<void> applyRemoteChanges(
    Iterable<SyncChange> changes, {
    bool markAppliedAsSynced = false,
    bool mirrorToDirect = false,
  }) =>
      _AppStoreSplitSyncApplyPart2(_store).applyRemoteSyncChanges(
        changes.toList(),
        markAppliedAsSynced: markAppliedAsSynced,
        mirrorToDirect: mirrorToDirect,
      );

  @override
  Future<void> assertRemoteChangesApplied(List<SyncChange> changes) =>
      _AppStoreSplitSyncApplyPart3(_store)
          .assertRemoteSyncChangesApplied(changes);

  @override
  Future<void> retryFailed({String? target}) =>
      _store._retryFailedSyncQueueDomainImpl(target: target);
  @override
  Future<void> recoverSubmitted({String? target}) =>
      _store._recoverSubmittedSyncQueueDomainImpl(target: target);
  @override
  Future<void> recoverStale({
    String? target,
    Duration staleAfter = const Duration(seconds: 45),
  }) =>
      _store._recoverStaleInProgressSyncQueueDomainImpl(
        target: target,
        staleAfter: staleAfter,
      );

  @override
  Future<List<DataConflict>> ensureDataConflictsLoaded() =>
      _AppStoreSplitCoreLoading(_store).ensureDataConflictsLoaded();

  @override
  Future<BusinessDataIntegrityResult> verifyLocalBusinessDataIntegrity() =>
      _AppStoreSplitPersistenceSyncCorePart3(_store)
          .verifyLocalBusinessDataIntegrity();

  @override
  Future<int> cleanupSoftDeletedRecords({
    Duration retention = const Duration(days: 30),
  }) =>
      _AppStoreSplitPersistenceSyncCorePart3(_store)
          .cleanupSoftDeletedRecords(retention: retention);

  @override
  Future<void> recordPhase8AccountingMutationForSync() =>
      _AppStoreSplitPersistenceSyncCorePart4(_store)
          .recordPhase8AccountingMutationForSync();

  @override
  Future<void> recoverPhase8AccountingSyncAfterStartup() =>
      _AppStoreSplitPersistenceSyncCorePart4(_store)
          .recoverPhase8AccountingSyncAfterStartup();

  @override
  Future<Map<String, int>> compactSyncedHistoryForMaintenance({
    int keepRecentSyncedChanges = AppStore._syncMaintenanceKeepRecentChanges,
    int minChangesBeforeCompact =
        AppStore._syncMaintenanceMinChangesBeforeCompact,
  }) =>
      _AppStoreSplitSyncApply(_store).compactSyncedSyncHistoryForMaintenance(
        keepRecentSyncedChanges: keepRecentSyncedChanges,
        minChangesBeforeCompact: minChangesBeforeCompact,
      );

  @override
  Future<Map<String, int>> compactClientSyncedHistoryForMaintenance({
    int keepRecentSyncedChanges = AppStore._syncMaintenanceKeepRecentChanges,
  }) =>
      _AppStoreSplitSyncApply(_store)
          .compactClientSyncedSyncHistoryForMaintenance(
        keepRecentSyncedChanges: keepRecentSyncedChanges,
      );

  @override
  Future<int> settleHostQueueThroughPeerAck() =>
      _AppStoreSplitSyncApplyPart3(_store).settleHostQueueThroughPeerAck();

  @override
  Future<void> settleLegacyLanHostQueue() =>
      _AppStoreSplitSyncApplyPart3(_store).settleLegacyLanHostQueue();

  @override
  Future<void> importSnapshotJson(String rawJson) =>
      _AppStoreSplitSyncApply(_store).importSyncSnapshotJson(rawJson);

  @override
  Future<void> markAllChangesSynced() =>
      _AppStoreSplitSyncApply(_store).markAllSyncChangesSynced();

  @override
  Future<List<Map<String, dynamic>>> exportSnapshotChunks({
    String kind = 'full_store',
    Set<String>? sectionIds,
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  }) =>
      _AppStoreSplitBackupRecovery(_store).exportUnifiedSnapshotChunks(
        kind: kind,
        sectionIds: sectionIds,
        maxItemsPerChunk: maxItemsPerChunk,
        maxEncodedPayloadBytes: maxEncodedPayloadBytes,
      );

  @override
  Map<String, dynamic> snapshotPayloadFromChunks(
    List<Map<String, dynamic>> chunks,
  ) =>
      _AppStoreSplitBackupRecovery(_store)
          .unifiedSnapshotPayloadFromChunks(chunks);

  @override
  DateTime snapshotGeneratedAtFromJson(String rawJson) =>
      _AppStoreSplitBackupRecoveryPart2(_store)
          .syncSnapshotGeneratedAtFromJson(rawJson);

  @override
  int snapshotGeneratedSequenceFromJson(String rawJson) =>
      _AppStoreSplitBackupRecoveryPart2(_store)
          .syncSnapshotGeneratedSequenceFromJson(rawJson);

  @override
  String exportChangesJson({
    DateTime? since,
    int? sinceSequence,
    int? maxEncodedPayloadBytes,
  }) =>
      _AppStoreSplitBackupRecoveryPart2(_store).exportSyncChangesJson(
        since: since,
        sinceSequence: sinceSequence,
        maxEncodedPayloadBytes: maxEncodedPayloadBytes,
      );

  @override
  String get approvedHostTransferDeviceId =>
      LocalDatabaseService.getString(AppStore._hostTransferApprovedDeviceKey)
          ?.trim() ??
      '';

  @override
  Map<String, dynamic>? get pendingHostTransferRequest =>
      _AppStoreSplitIdentityUsers(_store).pendingHostTransferRequest;

  @override
  Future<void> updateAppIdentityLocalOnly(
    AppIdentity identity, {
    String source = 'local sync settings',
  }) =>
      _AppStoreSplitIdentityUsers(_store)
          .updateAppIdentityLocalOnly(identity, source: source);

  @override
  Future<void> setActiveSyncTransport(String transport) =>
      _AppStoreSplitIdentityUsers(_store).setActiveSyncTransport(transport);

  @override
  Future<void> requestHostTransfer({String reason = ''}) =>
      _AppStoreSplitIdentityUsers(_store).requestHostTransfer(reason: reason);

  @override
  Future<void> approveHostTransfer(String requestingDeviceId) =>
      _AppStoreSplitIdentityUsers(_store)
          .approveHostTransfer(requestingDeviceId);

  @override
  Future<void> activateApprovedHostTransfer() =>
      _AppStoreSplitIdentityUsers(_store).activateApprovedHostTransfer();

  @override
  Future<void> clearHostTransferNotification() =>
      _AppStoreSplitIdentityUsers(_store).clearHostTransferNotification();

  @override
  Future<int> clearLocalOnlyPendingSyncChanges() =>
      _AppStoreSplitPersistenceSyncCorePart2(_store)
          .clearLocalOnlyPendingSyncChanges();

  @override
  List<SyncQueueItem> pendingSyncQueueForTarget(
    String target, {
    bool readyOnly = true,
  }) =>
      _AppStoreSplitCoreLoadingPart2(_store)
          .pendingSyncQueueForTarget(target, readyOnly: readyOnly);

  @override
  Future<void> clearPendingSyncQueue({bool notify = true}) =>
      _AppStoreSplitStartupMigrationsPart3(_store)
          .clearPendingSyncQueue(notify: notify);

  @override
  Future<void> markSyncQueueItemFailed(String queueItemId, String error) =>
      _AppStoreSplitSyncApplyPart4(_store)
          .markSyncQueueItemFailed(queueItemId, error);

  @override
  Future<String> exportSyncSnapshotJson() =>
      _AppStoreSplitBackupRecoveryPart2(_store).exportSyncSnapshotJson();
}

final class _RecoveryDomain implements RecoveryDomainPort {
  _RecoveryDomain(this._store)
      : _recoveryFiles = RecoveryFileService(
          identityProvider: () => _store.runtime.identity,
        );
  final AppStore _store;
  final RecoveryFileService _recoveryFiles;

  @override
  bool get hasLocalStoreData =>
      _AppStoreSplitAccessAuth(_store).hasLocalStoreData;

  @override
  Future<String> exportBackupJson() =>
      AppStoreRecoveryService(_store).exportBackupJson();
  @override
  Future<void> importBackupJson(
    String rawJson, {
    Set<String>? selectedSectionIds,
  }) =>
      AppStoreRecoveryService(_store).importBackupJson(
        rawJson,
        selectedSectionIds: selectedSectionIds,
      );
  @override
  String exportRecoveryFileJson({String controlPlaneApiUrl = ''}) {
    _store.security.requirePermission(AppPermission.backupExport);
    return _recoveryFiles.exportRecoveryFileJson(
      controlPlaneApiUrl: controlPlaneApiUrl,
    );
  }

  @override
  Future<Map<String, dynamic>> exportUnifiedSnapshotEnvelope({
    String kind = 'full_store',
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  }) =>
      _AppStoreSplitBackupRecoveryPart2(_store).exportUnifiedSnapshotEnvelope(
        kind: kind,
        maxItemsPerChunk: maxItemsPerChunk,
        maxEncodedPayloadBytes: maxEncodedPayloadBytes,
      );

  @override
  Map<String, String> parseRecoveryFileJson(String rawJson) =>
      _recoveryFiles.parseRecoveryFileJson(rawJson);

  @override
  Future<void> factoryResetLocalDevice({
    bool enforcePermission = true,
    bool preserveAdminUsers = false,
  }) =>
      _AppStoreSplitPersistenceSyncCorePart3(_store).factoryResetLocalDevice(
        enforcePermission: enforcePermission,
        preserveAdminUsers: preserveAdminUsers,
      );

  @override
  Future<void> resetBusinessData({bool keepStoreProfile = true}) =>
      _AppStoreSplitPersistenceSyncCorePart2(_store)
          .resetBusinessData(keepStoreProfile: keepStoreProfile);
}
