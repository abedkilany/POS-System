import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/models/stock_movement.dart';
import 'package:ventio/models/warehouse.dart';

void main() {
  test('warehouse serializes and stock movements keep warehouse identity', () {
    final now = DateTime(2026, 1, 1);
    final warehouse = Warehouse(id: 'w1', name: 'Back store', code: 'BACK', location: 'B1', createdAt: now, updatedAt: now);
    final decodedWarehouse = Warehouse.fromJson(warehouse.toJson());
    expect(decodedWarehouse.id, 'w1');
    expect(decodedWarehouse.name, 'Back store');

    final movement = StockMovement(id: 'm1', productId: 'p1', productName: 'Coffee', type: 'warehouse_transfer_in', quantity: 5, date: now, warehouseId: 'w1', warehouseName: 'Back store');
    final decodedMovement = StockMovement.fromJson(movement.toJson());
    expect(decodedMovement.warehouseId, 'w1');
    expect(decodedMovement.warehouseName, 'Back store');
  });
}
