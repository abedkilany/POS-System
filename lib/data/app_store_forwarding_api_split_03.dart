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

  bool _isProductReferenced(String productId) =>
      _AppStoreSplitCatalogPartiesExpenses(this as AppStore)
          .isProductReferenced(productId);

  int _loadPurchaseCounter() =>
      _AppStoreSplitWarehouseCash(this as AppStore)._loadPurchaseCounter();

  /// Returns the complete trace graph for one Unified Batch, including
  /// warehouse movements, purchase/manufacturing origin and manufacturing
  /// ancestors/descendants.
  Future<Map<String, dynamic>> _traceInventoryBatchDomainImpl(
    String batchId, {
    int maxDepth = 8,
  }) async {
    (this as AppStore)._requirePermissionReadImpl(
      AppPermission.inventoryMovementsView,
    );
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
  Future<Map<String, dynamic>>
      _verifyInventoryTraceabilityIntegrityDomainImpl() async {
    (this as AppStore)._requirePermissionReadImpl(
      AppPermission.inventoryMovementsView,
    );
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError(
          'Inventory integrity verification requires SQLite storage.');
    }
    return InventoryTraceabilityService(sqliteDb).verifyIntegrity(
      storeId: (this as AppStore).appIdentity.storeId,
    );
  }
}
