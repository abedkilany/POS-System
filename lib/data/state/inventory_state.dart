import '../../models/inventory_cost_layer.dart';
import '../../models/inventory_count.dart';
import '../../models/manufacturing.dart';
import '../../models/product_costing.dart';
import '../../models/stock_movement.dart';
import '../../models/warehouse.dart';
import 'dart:collection';

/// Session-local cache state. SQLite remains authoritative.
class InventoryState {
  final List<BillOfMaterials> billsOfMaterials = [];
  final List<ManufacturingOrder> manufacturingOrders = [];
  final List<InventoryCostLayer> inventoryCostLayers = [];
  final List<StockMovement> stockMovements = [];
  final List<InventoryCountSession> inventoryCounts = [];
  final List<Warehouse> warehouses = [];
  final Map<String, int> stockMovementIndexById = <String, int>{};
  final Map<String, int> inventoryCostLayerIndexById = <String, int>{};
  final Map<String, Map<String, double>> warehouseStockByProductCache =
      <String, Map<String, double>>{};
  bool warehouseStockCacheDirty = true;
  InventoryCostingMethod inventoryCostingMethod = InventoryCostingMethod.batch;
  UnmodifiableListView<BillOfMaterials>? cachedBillsOfMaterials;
  UnmodifiableListView<ManufacturingOrder>? cachedManufacturingOrders;
  int cachedBillsOfMaterialsGeneration = -1;
  int cachedManufacturingOrdersGeneration = -1;
}
