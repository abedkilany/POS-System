part of 'app_store.dart';

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
  double get inventoryRetailValue => _AppStoreCatalogRead(_store)
      ._stockTrackedProductsReadImpl
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
      _AppStorePricingCostingPolicy(_store)
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
      _AppStoreCoreLoadingProjections(_store)
          .stockForWarehouse(productId, warehouseId);
  @override
  Future<double> warehouseStockFromSqlite(
    String productId, {
    String warehouseId = '',
  }) =>
      _AppStoreCoreLoadingProjections(_store)
          .warehouseStockFromSqlite(productId, warehouseId: warehouseId);
  @override
  Future<double> totalStockFromSqlite(String productId) =>
      _AppStoreCoreLoadingProjections(_store)
          .totalWarehouseStockFromSqlite(productId);
  @override
  Future<Map<String, Map<String, double>>> warehouseStockBalancesFromSqlite() =>
      _AppStoreCoreLoadingProjections(_store).warehouseStockBalancesFromSqlite();
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
      _AppStoreInventoryCountReversalBatches(_store)
          .reviewAutoCorrection(movementId, note: note);
  @override
  Future<void> setExpiryBatchStatus(String batchId, String status) =>
      _AppStoreInventoryCountReversalBatches(_store)
          .setExpiryBatchStatus(batchId, status);
  @override
  Future<void> reverseExpiryBatchAdjustment(
    String movementId, {
    String reason = '',
  }) =>
      _AppStoreInventoryBatchReversal(_store)
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
      _AppStoreInventoryCountReversalBatches(_store).adjustExpiryBatchStock(
        productId: productId,
        warehouseId: warehouseId,
        batchId: batchId,
        quantityDelta: quantityDelta,
        reason: reason,
        adjustmentCategory: adjustmentCategory,
      );
  @override
  Future<int> manualStockAdjustmentVersion(String operationReferenceId) =>
      _AppStoreInventoryBatchReversal(_store)
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
      _AppStoreInventoryAdjustmentEdit(_store).editStockAdjustment(
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
      _AppStoreInventoryAdjustmentsWaste(_store).recordWasteLoss(
        productId: productId,
        warehouseId: warehouseId,
        quantity: quantity,
        reason: reason,
        adjustmentCategory: adjustmentCategory,
        notes: notes,
      );
  @override
  Future<void> deleteWasteLoss(String movementId) =>
      _AppStoreInventoryPurchaseMovements(_store).deleteWasteLoss(movementId);
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
      _AppStoreInventoryAdjustmentsWaste(_store).adjustStock(
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
      _AppStoreInventoryCountReversalBatches(_store)
          .reverseInventoryCount(sessionId, reason: reason);
  @override
  Future<void> cancelInventoryCount(String sessionId) =>
      _AppStoreInventoryCountReversalBatches(_store).cancelInventoryCount(sessionId);
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
      _AppStoreManufacturingOrderLifecycle(_store).startManufacturingOrder(
        bomId: bomId,
        quantity: quantity,
        rawMaterialsWarehouseId: rawMaterialsWarehouseId,
        rawMaterialsWarehouseName: rawMaterialsWarehouseName,
        finishedGoodsWarehouseId: finishedGoodsWarehouseId,
        finishedGoodsWarehouseName: finishedGoodsWarehouseName,
        notes: notes,
      );
  @override
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
  }) =>
      _AppStoreManufacturingCompletion(_store).completeManufacturingOrder(
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
        existingOrderId: existingOrderId,
      );
  @override
  Future<ManufacturingOrder> reverseManufacturingOrder({
    required String orderId,
    required String reason,
  }) =>
      _AppStoreManufacturingReversal(_store)
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
      _AppStoreManufacturingOrderLifecycle(_store).updateManufacturingOrder(
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
      _AppStoreManufacturingOrderLifecycle(_store).finishManufacturingOrder(
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
      _AppStoreManufacturingCompletedEdit(_store).editCompletedManufacturingOrder(
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
  Future<void> transferStock({
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required double quantity,
    String notes = '',
  }) =>
      _AppStoreWarehouseCashTransfersRefunds(_store).transferStock(
        productId: productId,
        fromWarehouseId: fromWarehouseId,
        toWarehouseId: toWarehouseId,
        quantity: quantity,
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
      _AppStoreWarehouseCashTransferEdit(_store).editWarehouseTransferOrder(
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
