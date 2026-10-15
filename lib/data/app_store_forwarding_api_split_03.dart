part of 'app_store.dart';

/// Transitional instance API kept for source compatibility while callers
/// migrate to typed domain ports (`store.catalog`, `store.commerce`, etc.).
///
/// The business implementation continues to live in focused split modules;
/// this mixin deliberately contains forwarding only and owns no mutable state.
mixin _AppStoreForwardingApiPart3
    on ChangeNotifier, _AppStoreStateAccessors, _AppStoreForwardingApi {
  bool get _isDirectClientConfigured =>
      _AppStoreSplitPersistenceSyncCorePart4(this as AppStore)
          ._isDirectClientConfigured;

  bool get _isLanHostConfigured =>
      _AppStoreSplitPersistenceSyncCorePart4(this as AppStore)
          ._isLanHostConfigured;

  String get _stockTransactionSyncTarget =>
      _AppStoreSplitPersistenceSyncCorePart4(this as AppStore)
          ._stockTransactionSyncTarget;

  /// Repairs the split-brain state where a change exists in the sync history
  /// but its outbound queue row is missing. This can be left by older
  /// snapshot/restore flows that persisted the two stores independently.
  ///
  /// Only local Client drafts are reconstructed. Host-authoritative history
  /// received by a Client must never be re-queued as a new draft.
  Future<void> _reconcileUnsyncedChangesWithQueue() =>
      _AppStoreSplitPersistenceSyncCorePart4(this as AppStore)
          ._reconcileUnsyncedChangesWithQueue();

  Sale _saleSyncMetaPreview(
    Sale item,
    DateTime now, {
    bool isCreate = false,
  }) =>
      _AppStoreSplitPersistenceSyncCorePart4(this as AppStore)
          ._saleSyncMetaPreview(item, now, isCreate: isCreate);

  Purchase _purchaseSyncMetaPreview(
    Purchase item,
    DateTime now, {
    bool isCreate = false,
  }) =>
      _AppStoreSplitPersistenceSyncCorePart4(this as AppStore)
          ._purchaseSyncMetaPreview(item, now, isCreate: isCreate);

  Expense _expenseSyncMetaPreview(
    Expense item,
    DateTime now, {
    bool isCreate = false,
  }) =>
      _AppStoreSplitPersistenceSyncCorePart4(this as AppStore)
          ._expenseSyncMetaPreview(item, now, isCreate: isCreate);

  T _withSyncMeta<T>(
    T item,
    DateTime now, {
    bool isCreate = false,
    bool clearDeletedAt = true,
  }) =>
      _AppStoreSplitPersistenceSyncCorePart4(this as AppStore)._withSyncMeta(
          item, now,
          isCreate: isCreate, clearDeletedAt: clearDeletedAt);

  Future<void> _persistAccountTransactionInExistingTransaction(
    dynamic sqliteDb,
    AccountTransaction transaction,
  ) =>
      _AppStoreSplitPersistenceSyncCorePart4(this as AppStore)
          ._persistAccountTransactionInExistingTransaction(
              sqliteDb, transaction);

  Future<void> addOrUpdateAccountTransaction(
    AccountTransaction transaction,
  ) =>
      _AppStoreSplitPersistenceSyncCorePart5(this as AppStore)
          .addOrUpdateAccountTransaction(transaction);

  Future<void> deleteAccountTransaction(String id) =>
      _AppStoreSplitPersistenceSyncCorePart5(this as AppStore)
          .deleteAccountTransaction(id);

  Future<void> _recordPurchaseLedger(Purchase purchase, DateTime now) =>
      _AppStoreSplitPersistenceSyncCorePart5(this as AppStore)
          ._recordPurchaseLedger(purchase, now);

  Future<void> _recordPurchaseCancelLedger(
    Purchase purchase,
    DateTime now, {
    String reason = '',
    bool isReturn = false,
  }) =>
      _AppStoreSplitPersistenceSyncCorePart5(this as AppStore)
          ._recordPurchaseCancelLedger(purchase, now,
              reason: reason, isReturn: isReturn);

  Future<void> _recordSaleLedger(Sale sale, DateTime now) =>
      _AppStoreSplitPersistenceSyncCorePart5(this as AppStore)
          ._recordSaleLedger(sale, now);

  Future<void> _recordSaleCancelLedger(
    Sale sale,
    DateTime now, {
    bool isReturn = false,
    String returnReferenceId = '',
  }) =>
      _AppStoreSplitPersistenceSyncCorePart5(this as AppStore)
          ._recordSaleCancelLedger(sale, now,
              isReturn: isReturn, returnReferenceId: returnReferenceId);

  Future<void> _reverseExpenseLedger(Expense expense, DateTime now,
          {String reason = ''}) =>
      _AppStoreSplitPersistenceSyncCorePart5(this as AppStore)
          ._reverseExpenseLedger(expense, now, reason: reason);

  void _ensureDefaultPriceLists() =>
      _AppStoreSplitPricingCosting(this as AppStore)._ensureDefaultPriceLists();

  void _rebuildProductCostLookupCache() =>
      _AppStoreSplitPricingCosting(this as AppStore)
          ._rebuildProductCostLookupCache();

  void _rebuildProductPricingLookupCaches() =>
      _AppStoreSplitPricingCosting(this as AppStore)
          ._rebuildProductPricingLookupCaches();

  void _ensureProductPricingLookupCaches() =>
      _AppStoreSplitPricingCosting(this as AppStore)
          ._ensureProductPricingLookupCaches();

  void _removeProductPricingLookupEntries(String productId) =>
      _AppStoreSplitPricingCosting(this as AppStore)
          ._removeProductPricingLookupEntries(productId);

  void _ensureDefaultProductPriceEntries({Product? product}) =>
      _AppStoreSplitPricingCosting(this as AppStore)
          ._ensureDefaultProductPriceEntries(product: product);

  Future<void> setDefaultProductBasePrice(
          {required String productId,
          required String unitId,
          required double amount,
          required String currencyCode}) =>
      _AppStoreSplitPricingCosting(this as AppStore).setDefaultProductBasePrice(
          productId: productId,
          unitId: unitId,
          amount: amount,
          currencyCode: currencyCode);

  Future<void> setProductBasePriceForList({
    required String productId,
    required String priceListId,
    required double amount,
    required String currencyCode,
    String unitId = 'base',
  }) =>
      _AppStoreSplitPricingCosting(this as AppStore).setProductBasePriceForList(
          productId: productId,
          priceListId: priceListId,
          amount: amount,
          currencyCode: currencyCode,
          unitId: unitId);

  Future<BulkPriceAdjustmentResult> bulkAdjustProductPrices({
    required Iterable<String> productIds,
    required String priceListId,
    required double percentage,
    required bool increase,
    String unitId = 'base',
  }) =>
      _AppStoreSplitPricingCosting(this as AppStore).bulkAdjustProductPrices(
        productIds: productIds,
        priceListId: priceListId,
        percentage: percentage,
        increase: increase,
        unitId: unitId,
      );

  Future<List<ProductPriceHistoryEntry>> productPriceHistoryForProduct(
    String productId, {
    int limit = 200,
  }) =>
      _AppStoreSplitPricingCosting(this as AppStore)
          .productPriceHistoryForProduct(productId, limit: limit);

  Future<void> setProductPriceOverride({
    required String productPriceId,
    required String currencyCode,
    required double amount,
    ProductPriceOverrideMode mode = ProductPriceOverrideMode.fixed,
    bool isActive = true,
  }) =>
      _AppStoreSplitPricingCosting(this as AppStore).setProductPriceOverride(
          productPriceId: productPriceId,
          currencyCode: currencyCode,
          amount: amount,
          mode: mode,
          isActive: isActive);

  Future<void> removeProductPriceOverride(
          String productPriceId, String currencyCode) =>
      _AppStoreSplitPricingCosting(this as AppStore)
          .removeProductPriceOverride(productPriceId, currencyCode);

  void _ensureProductCostEntries({Product? product}) =>
      _AppStoreSplitPricingCostingPart2(this as AppStore)
          ._ensureProductCostEntries(product: product);

  InventoryCostingMethod _runtimeInventoryCostingMethod(
          InventoryCostingMethod requested) =>
      _AppStoreSplitPricingCostingPart2(this as AppStore)
          ._runtimeInventoryCostingMethod(requested);

  void _ensureCostingMethodHistory() =>
      _AppStoreSplitPricingCostingPart2(this as AppStore)
          ._ensureCostingMethodHistory();

  DateTime? _currentOpenFifoEffectiveFrom() =>
      _AppStoreSplitPricingCostingPart2(this as AppStore)
          ._currentOpenFifoEffectiveFrom();

  Future<void> setInventoryCostingMethod(InventoryCostingMethod method,
          {String reason = ''}) =>
      _AppStoreSplitPricingCostingPart2(this as AppStore)
          .setInventoryCostingMethod(method, reason: reason);

  ProductCost _upsertProductCostFromPurchase({
    required Product product,
    required double receivedQty,
    required double baseUnitCost,
    required DateTime now,
  }) =>
      _AppStoreSplitPricingCostingPart2(this as AppStore)
          ._upsertProductCostFromPurchase(
              product: product,
              receivedQty: receivedQty,
              baseUnitCost: baseUnitCost,
              now: now);

  void _addInventoryCostLayerFromPurchase({
    required Purchase purchase,
    required PurchaseItem item,
    required int lineIndex,
    required double quantity,
    required double unitCost,
    required DateTime now,
  }) =>
      _AppStoreSplitPricingCostingPart2(this as AppStore)
          ._addInventoryCostLayerFromPurchase(
              purchase: purchase,
              item: item,
              lineIndex: lineIndex,
              quantity: quantity,
              unitCost: unitCost,
              now: now);

  void _addInventoryCostLayerFromStockIncrease({
    required String id,
    required Product product,
    required double quantity,
    required double unitCost,
    required String sourceType,
    required String sourceId,
    required DateTime now,
  }) =>
      _AppStoreSplitPricingCostingPart2(this as AppStore)
          ._addInventoryCostLayerFromStockIncrease(
              id: id,
              product: product,
              quantity: quantity,
              unitCost: unitCost,
              sourceType: sourceType,
              sourceId: sourceId,
              now: now);

  bool _purchaseHasConsumedCostLayers(String purchaseId) =>
      _AppStoreSplitPricingCostingPart2(this as AppStore)
          ._purchaseHasConsumedCostLayers(purchaseId);

  InventoryCostResult _resolveCostForSaleItem(SaleItem item, DateTime now) =>
      _AppStoreSplitPricingCostingPart3(this as AppStore)
          ._resolveCostForSaleItem(item, now);

  Future<InventoryCostResult> _resolveCostForSaleItemInTransaction(
    VentioDriftDatabase db,
    SaleItem item,
    DateTime now,
  ) =>
      _AppStoreSplitPricingCostingPart3(this as AppStore)
          ._resolveCostForSaleItemInTransaction(db, item, now);

  Future<void> _restoreInventoryCostLayersFromSaleItemsInTransaction(
    VentioDriftDatabase db,
    Iterable<SaleItem> items,
    DateTime now, {
    required DateTime originalSaleDate,
    required String restorationSourceType,
    required String restorationSourceId,
    bool preserveSaleProductIds = false,
  }) =>
      _AppStoreSplitPricingCostingPart3(this as AppStore)
          ._restoreInventoryCostLayersFromSaleItemsInTransaction(db, items, now,
              originalSaleDate: originalSaleDate,
              restorationSourceType: restorationSourceType,
              restorationSourceId: restorationSourceId,
              preserveSaleProductIds: preserveSaleProductIds);

  Future<void> _closeInventoryCostLayersForPurchaseInTransaction(
    VentioDriftDatabase db,
    Purchase purchase,
    DateTime now,
  ) =>
      _AppStoreSplitPricingCostingPart3(this as AppStore)
          ._closeInventoryCostLayersForPurchaseInTransaction(db, purchase, now);

  // Legacy FIFO helper retained for historical migration/regression contracts.
  // Phase 4 manufacturing uses Unified Batch directly.
  // ignore: unused_element
  Future<_ManufacturingCostResolution> _consumeManufacturingCostInTransaction(
    VentioDriftDatabase db, {
    required Product product,
    required double quantity,
    required String orderId,
    required DateTime now,
  }) =>
      _AppStoreSplitPricingCostingPart3(this as AppStore)
          ._consumeManufacturingCostInTransaction(db,
              product: product, quantity: quantity, orderId: orderId, now: now);

  void _restoreInventoryCostLayersFromSaleItem(SaleItem item, DateTime now) =>
      _AppStoreSplitPricingCostingPart3(this as AppStore)
          ._restoreInventoryCostLayersFromSaleItem(item, now);

  void _closeInventoryCostLayersForPurchase(String purchaseId, DateTime now) =>
      _AppStoreSplitPricingCostingPart3(this as AppStore)
          ._closeInventoryCostLayersForPurchase(purchaseId, now);

  Future<void> addOrUpdateProduct(Product product) =>
      _AppStoreSplitCatalogPartiesExpenses(this as AppStore)
          .addOrUpdateProduct(product);

  Future<void> addOrUpdateProductsBulk(List<Product> products) =>
      _AppStoreSplitCatalogPartiesExpenses(this as AppStore)
          .addOrUpdateProductsBulk(products);

  bool isProductReferenced(String productId) =>
      _AppStoreSplitCatalogPartiesExpenses(this as AppStore)
          .isProductReferenced(productId);

  Future<void> deleteProduct(String id) =>
      _AppStoreSplitCatalogPartiesExpenses(this as AppStore).deleteProduct(id);

  Future<void> addOrUpdateCustomer(Customer customer) =>
      _AppStoreSplitCatalogPartiesExpenses(this as AppStore)
          .addOrUpdateCustomer(customer);

  Future<void> addOrUpdateCustomersBulk(List<Customer> customers) =>
      _AppStoreSplitCatalogPartiesExpensesPart2(this as AppStore)
          .addOrUpdateCustomersBulk(customers);

  Future<void> deleteCustomer(String id) =>
      _AppStoreSplitCatalogPartiesExpensesPart2(this as AppStore)
          .deleteCustomer(id);

  Future<void> addOrUpdateSupplier(Supplier supplier) =>
      _AppStoreSplitCatalogPartiesExpensesPart2(this as AppStore)
          .addOrUpdateSupplier(supplier);

  Future<void> addOrUpdateSuppliersBulk(List<Supplier> suppliers) =>
      _AppStoreSplitCatalogPartiesExpensesPart2(this as AppStore)
          .addOrUpdateSuppliersBulk(suppliers);

  Future<void> deleteSupplier(String id) =>
      _AppStoreSplitCatalogPartiesExpensesPart2(this as AppStore)
          .deleteSupplier(id);

  Future<void> addOrUpdateCategory(CatalogItem item) =>
      _AppStoreSplitCatalogPartiesExpensesPart2(this as AppStore)
          .addOrUpdateCategory(item);

  Future<void> addOrUpdateBrand(CatalogItem item) =>
      _AppStoreSplitCatalogPartiesExpensesPart2(this as AppStore)
          .addOrUpdateBrand(item);

  Future<void> addOrUpdateUnit(CatalogItem item) =>
      _AppStoreSplitCatalogPartiesExpensesPart2(this as AppStore)
          .addOrUpdateUnit(item);

  int productsUsingCatalogItem(String type, CatalogItem item) =>
      _AppStoreSplitCatalogPartiesExpensesPart2(this as AppStore)
          .productsUsingCatalogItem(type, item);

  Future<void> replaceAndDeleteCatalogItem({
    required String type,
    required CatalogItem item,
    CatalogItem? replacement,
  }) =>
      _AppStoreSplitCatalogPartiesExpensesPart2(this as AppStore)
          .replaceAndDeleteCatalogItem(
              type: type, item: item, replacement: replacement);

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
      _AppStoreSplitCatalogPartiesExpensesPart3(this as AppStore)
          .editPostedExpense(
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

  Future<void> addOrUpdateExpense(Expense expense) =>
      _AppStoreSplitCatalogPartiesExpensesPart3(this as AppStore)
          .addOrUpdateExpense(expense);

  Future<void> postExpense(
    String id, {
    bool paidInCash = true,
    double? cashPaidAmount,
  }) =>
      _AppStoreSplitCatalogPartiesExpensesPart3(this as AppStore).postExpense(
        id,
        paidInCash: paidInCash,
        cashPaidAmount: cashPaidAmount,
      );

  Future<void> createAndPostExpensesBulk(List<Expense> expenses) =>
      _AppStoreSplitCatalogPartiesExpensesPart3(this as AppStore)
          .createAndPostExpensesBulk(expenses);

  Future<void> deleteDraftExpense(String id) =>
      _AppStoreSplitCatalogPartiesExpensesPart3(this as AppStore)
          .deleteDraftExpense(id);

  Future<void> cancelExpense(String id, {String reason = ''}) =>
      _AppStoreSplitCatalogPartiesExpensesPart3(this as AppStore)
          .cancelExpense(id, reason: reason);

  Future<void> permanentlyDeleteCancelledExpense(String id) =>
      _AppStoreSplitCatalogPartiesExpensesPart4(this as AppStore)
          .permanentlyDeleteCancelledExpense(id);

  int _loadPurchaseCounter() =>
      _AppStoreSplitWarehouseCash(this as AppStore)._loadPurchaseCounter();

  Future<Warehouse> createWarehouse({
    required String name,
    String code = '',
    String location = '',
  }) =>
      _AppStoreSplitWarehouseCash(this as AppStore)
          .createWarehouse(name: name, code: code, location: location);

  Future<WarehouseTransferOrder> editWarehouseTransferOrder({
    required String orderId,
    required int expectedVersion,
    required String fromWarehouseId,
    required String toWarehouseId,
    required List<WarehouseTransferOrderItem> items,
    String? notes,
    DateTime? date,
  }) =>
      _AppStoreSplitWarehouseCashPart2(this as AppStore)
          .editWarehouseTransferOrder(
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
  }) =>
      _AppStoreSplitWarehouseCash(this as AppStore)
          .recentWarehouseTransferOrders(limit: limit);

  Future<WarehouseTransferOrder> createWarehouseTransferOrder({
    required String fromWarehouseId,
    required String toWarehouseId,
    required List<WarehouseTransferOrderItem> items,
    String notes = '',
  }) =>
      _AppStoreSplitWarehouseCash(this as AppStore)
          .createWarehouseTransferOrder(
              fromWarehouseId: fromWarehouseId,
              toWarehouseId: toWarehouseId,
              items: items,
              notes: notes);

  Future<void> transferStock({
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required double quantity,
    String notes = '',
  }) =>
      _AppStoreSplitWarehouseCashPart3(this as AppStore).transferStock(
          productId: productId,
          fromWarehouseId: fromWarehouseId,
          toWarehouseId: toWarehouseId,
          quantity: quantity,
          notes: notes);

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
      throw StateError(
          'Inventory integrity verification requires SQLite storage.');
    }
    return InventoryTraceabilityService(sqliteDb).verifyIntegrity(
      storeId: (this as AppStore).appIdentity.storeId,
    );
  }

  Future<double> refundableSaleCashAmount(String saleId) =>
      _AppStoreSplitWarehouseCashPart3(this as AppStore)
          .refundableSaleCashAmount(saleId);

  Future<void> normalizeRefundAllocations() =>
      _AppStoreSplitWarehouseCashPart3(this as AppStore)
          .normalizeRefundAllocations();

  Future<double> refundablePurchaseCashAmount(String purchaseId) =>
      _AppStoreSplitWarehouseCashPart3(this as AppStore)
          .refundablePurchaseCashAmount(purchaseId);

  Future<double> refundablePurchaseReturnCashAmount(String purchaseReturnId) =>
      _AppStoreSplitWarehouseCashPart3(this as AppStore)
          .refundablePurchaseReturnCashAmount(purchaseReturnId);

  Future<double> refundSaleCash({
    required String saleId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreSplitWarehouseCashPart3(this as AppStore).refundSaleCash(
          saleId: saleId,
          amount: amount,
          notes: notes,
          idempotencyKey: idempotencyKey,
          date: date);

  Future<double> refundPurchaseCash({
    required String purchaseId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreSplitWarehouseCashPart3(this as AppStore).refundPurchaseCash(
          purchaseId: purchaseId,
          amount: amount,
          notes: notes,
          idempotencyKey: idempotencyKey,
          date: date);

  Future<double> refundPurchaseReturnCash({
    required String purchaseReturnId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreSplitWarehouseCashPart3(this as AppStore)
          .refundPurchaseReturnCash(
              purchaseReturnId: purchaseReturnId,
              amount: amount,
              notes: notes,
              idempotencyKey: idempotencyKey,
              date: date);

  Future<double> refundableExpenseCashAmount(String expenseId) =>
      _AppStoreSplitWarehouseCashPart4(this as AppStore)
          .refundableExpenseCashAmount(expenseId);

  Future<double> refundExpenseCash({
    required String expenseId,
    double? amount,
    String notes = '',
  }) =>
      _AppStoreSplitWarehouseCashPart4(this as AppStore).refundExpenseCash(
          expenseId: expenseId, amount: amount, notes: notes);
}
