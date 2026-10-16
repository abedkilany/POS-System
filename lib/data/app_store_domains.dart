part of 'app_store.dart';

/// Stable, typed entry points into AppStore business domains.
///
/// UI/services depend on the narrowest port they need rather than the internal
/// AppStore forwarding implementation. These ports are the supported business
/// API for external callers.
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
  Future<double> totalStockFromSqlite(String productId);
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
  Future<void> transferStock({
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required double quantity,
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
  bool hasOutstandingWorkForTarget(String target);
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
  BackupSummary get currentBackupSummary;
  BackupImportPlan inspectBackupJson(String rawJson);
  BackupValidationResult validateBackupJson(String rawJson);
  bool isEncryptedBackupJson(String rawJson);
  String extractBackupJsonFromLocalBackupArchiveBytes(List<int> bytes);
  String decryptBackupJson(String encryptedBackup, String password);
  Future<String> exportEncryptedBackupJson(String password);
  Future<String> exportBackupJson();
  Future<void> mergeBackupJson(
    String rawJson, {
    bool markSynced = false,
  });
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
