part of 'app_store.dart';

/// Transitional instance API kept for source compatibility while callers
/// migrate to typed domain ports (`store.catalog`, `store.commerce`, etc.).
///
/// The business implementation continues to live in focused split modules;
/// this mixin deliberately contains forwarding only and owns no mutable state.
mixin _AppStoreForwardingApiInventoryPayments
    on ChangeNotifier, _AppStoreStateAccessors, _AppStoreForwardingApi {
  Future<Sale> _settleSalePaymentInternal({
    required String saleId,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreWarehouseCashSettlement(this as AppStore)
          ._settleSalePaymentInternal(
              saleId: saleId,
              amount: amount,
              discount: discount,
              paymentMethod: paymentMethod,
              notes: notes,
              idempotencyKey: idempotencyKey,
              date: date);

  Future<Purchase> _settlePurchasePayment({
    required String purchaseId,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreWarehouseCashSettlement(this as AppStore).settlePurchasePayment(
          purchaseId: purchaseId,
          amount: amount,
          discount: discount,
          paymentMethod: paymentMethod,
          notes: notes,
          idempotencyKey: idempotencyKey,
          date: date);

  PurchaseItem _copyPurchaseItemWith({
    required PurchaseItem item,
    String? lineId,
    List<BatchAllocation>? batchAllocations,
  }) =>
      _AppStoreWarehouseCashSettlement(this as AppStore)._copyPurchaseItemWith(
          item: item, lineId: lineId, batchAllocations: batchAllocations);

  Future<double> _unifiedOpeningCostForProductInTransaction(
    dynamic sqliteDb, {
    required Product product,
    required String warehouseId,
  }) =>
      _AppStoreSplitPurchases(this as AppStore)
          ._unifiedOpeningCostForProductInTransaction(sqliteDb,
              product: product, warehouseId: warehouseId);

  Future<void> _ensureUnifiedBatchCutoverForProductInTransaction(
    dynamic sqliteDb, {
    required Product product,
    required String warehouseId,
    required DateTime at,
  }) =>
      _AppStoreSplitPurchases(this as AppStore)
          ._ensureUnifiedBatchCutoverForProductInTransaction(sqliteDb,
              product: product, warehouseId: warehouseId, at: at);

  Future<void> _assertUnifiedBatchMovementBalancesInTransaction(
    BatchInventoryService batchService,
    Iterable<StockMovement> movements,
  ) =>
      _AppStoreSplitPurchases(this as AppStore)
          ._assertUnifiedBatchMovementBalancesInTransaction(
              batchService, movements);

  Future<void> _requirePostedJournalInTransaction(
    dynamic sqliteDb, {
    required String referenceType,
    required String referenceId,
    bool includePurchaseEditFamily = false,
    bool includeSaleEditFamily = false,
    required String failureMessage,
  }) =>
      _AppStorePurchasesReceipt(this as AppStore)
          ._requirePostedJournalInTransaction(sqliteDb,
              referenceType: referenceType,
              referenceId: referenceId,
              includePurchaseEditFamily: includePurchaseEditFamily,
              includeSaleEditFamily: includeSaleEditFamily,
              failureMessage: failureMessage);

  Future<void> _requireNoActiveJournalInTransaction(
    dynamic sqliteDb, {
    required String referenceType,
    required String referenceId,
    bool includePurchaseEditFamily = false,
    bool includeSaleEditFamily = false,
    required String failureMessage,
  }) =>
      _AppStorePurchasesReceipt(this as AppStore)
          ._requireNoActiveJournalInTransaction(sqliteDb,
              referenceType: referenceType,
              referenceId: referenceId,
              includePurchaseEditFamily: includePurchaseEditFamily,
              includeSaleEditFamily: includeSaleEditFamily,
              failureMessage: failureMessage);

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
  }) =>
      _AppStoreInventoryCountReversalBatches(this as AppStore)
          ._recordInventoryBatchSyncChanges(
              product: product,
              allocations: allocations,
              sourceType: sourceType,
              sourceId: sourceId,
              now: now,
              unitCost: unitCost,
              sourceLineId: sourceLineId,
              sourceLineIds: sourceLineIds,
              receivedAt: receivedAt);

  /// Reverses every batch movement created by one waste operation atomically.
  Future<void> _reverseWasteLossGroup(String movementId) =>
      _AppStoreInventoryAdjustmentsWaste(this as AppStore)
          .reverseWasteLossGroup(movementId);

  void _applyPurchaseStock(Purchase purchase, DateTime now) =>
      _AppStoreInventoryPurchaseMovements(this as AppStore)
          ._applyPurchaseStock(purchase, now);

  void _addStockMovement(StockMovement movement, {bool recordSync = false}) =>
      _AppStoreInventoryPurchaseMovements(this as AppStore)
          ._addStockMovement(movement, recordSync: recordSync);

  Future<void> _reconcileInventoryAccountsAfterBomChange(
    BillOfMaterials bom, {
    VentioDriftDatabase? database,
    bool withinExistingTransaction = false,
  }) =>
      _AppStoreInventoryPurchaseMovements(this as AppStore)
          ._reconcileInventoryAccountsAfterBomChange(bom,
              database: database,
              withinExistingTransaction: withinExistingTransaction);

  Future<ManufacturingOrder> _completeManufacturingOrder({
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
  }) =>
      _AppStoreManufacturingCompletion(this as AppStore)
          .completeManufacturingOrder(
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
              existingOrderId: existingOrderId);
}
