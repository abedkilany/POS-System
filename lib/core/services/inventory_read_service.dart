import '../../models/product.dart';
import '../../models/stock_movement.dart';
import '../../models/warehouse.dart';

/// Read-only projections used by inventory screens and the typed port.
class InventoryReadService {
  const InventoryReadService();

  List<Warehouse> activeWarehouses(Iterable<Warehouse> warehouses) =>
      List<Warehouse>.unmodifiable(
        warehouses.where((item) => !item.isDeleted && item.isActive),
      );

  List<StockMovement> newestFirstMovements(
    Iterable<StockMovement> movements,
  ) =>
      List<StockMovement>.unmodifiable(
        movements.toList(growable: false).reversed,
      );

  List<StockMovement> autoCorrectionMovements(
    Iterable<StockMovement> movements,
  ) =>
      newestFirstMovements(
        movements.where((movement) => movement.type == 'auto_correction'),
      );

  List<StockMovement> pendingAutoCorrectionMovements(
    Iterable<StockMovement> movements,
  ) =>
      newestFirstMovements(movements.where(
        (movement) =>
            movement.type == 'auto_correction' && !movement.isReviewed,
      ));

  Map<String, Map<String, double>> warehouseStockBalances({
    required Iterable<Product> products,
    required Iterable<Warehouse> warehouses,
    required Iterable<StockMovement> movements,
  }) {
    final warehouseIds = warehouses
        .where((item) => !item.isDeleted)
        .map((item) => item.id)
        .toList(growable: false);
    final balances = <String, Map<String, double>>{
      for (final product in products.where((item) => !item.isDeleted))
        product.id: <String, double>{for (final id in warehouseIds) id: 0},
    };

    for (final movement in movements) {
      final productId = movement.productId.trim();
      if (productId.isEmpty) continue;
      final warehouseId = movement.warehouseId.trim().isEmpty
          ? Warehouse.defaultId
          : movement.warehouseId.trim();
      final productBalances = balances.putIfAbsent(
        productId,
        () => <String, double>{for (final id in warehouseIds) id: 0},
      );
      productBalances[warehouseId] =
          (productBalances[warehouseId] ?? 0) + movement.quantity;
    }
    return balances;
  }

  double stockForWarehouse(
    Map<String, Map<String, double>> balances, {
    required String productId,
    required String warehouseId,
  }) {
    final normalizedWarehouseId =
        warehouseId.trim().isEmpty ? Warehouse.defaultId : warehouseId.trim();
    return balances[productId]?[normalizedWarehouseId] ?? 0;
  }
}
