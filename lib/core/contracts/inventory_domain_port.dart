import '../../models/inventory_batch.dart';
import '../../models/inventory_count.dart';
import '../../models/manufacturing.dart';
import '../../models/product.dart';
import '../../models/product_costing.dart';
import '../../models/stock_movement.dart';
import '../../models/warehouse.dart';
import '../../models/warehouse_transfer_order.dart';

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
