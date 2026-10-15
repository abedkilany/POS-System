import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/inventory_read_service.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/stock_movement.dart';
import 'package:ventio/models/warehouse.dart';

void main() {
  const service = InventoryReadService();
  final date = DateTime(2026, 1, 1);

  test('warehouse projection hides inactive and deleted rows', () {
    final warehouses = <Warehouse>[
      Warehouse(id: 'main', name: 'Main', isDefault: true),
      Warehouse(id: 'inactive', name: 'Inactive', isActive: false),
      Warehouse(
        id: 'deleted',
        name: 'Deleted',
        deletedAt: date,
      ),
    ];

    final active = service.activeWarehouses(warehouses);
    expect(active.map((item) => item.id), <String>['main']);
    expect(() => active.add(warehouses[1]), throwsUnsupportedError);
  });

  test('movement projection preserves the existing newest-first order', () {
    final movements = <StockMovement>[
      StockMovement(
        id: 'older',
        productId: 'p1',
        productName: 'Product',
        type: 'in',
        quantity: 1,
        date: date,
      ),
      StockMovement(
        id: 'newer',
        productId: 'p1',
        productName: 'Product',
        type: 'out',
        quantity: 1,
        date: date.add(const Duration(days: 1)),
      ),
    ];

    final newestFirst = service.newestFirstMovements(movements);
    expect(newestFirst.map((item) => item.id), <String>['newer', 'older']);
    expect(() => newestFirst.add(movements.first), throwsUnsupportedError);
  });

  test('auto-correction projections preserve newest-first and review filters',
      () {
    final movements = <StockMovement>[
      StockMovement(
        id: 'old',
        productId: 'p1',
        productName: 'Product',
        type: 'auto_correction',
        quantity: 1,
        date: date,
      ),
      StockMovement(
        id: 'reviewed',
        productId: 'p1',
        productName: 'Product',
        type: 'auto_correction',
        quantity: 1,
        date: date,
        reviewedAt: date,
      ),
      StockMovement(
        id: 'normal',
        productId: 'p1',
        productName: 'Product',
        type: 'purchase',
        quantity: 1,
        date: date,
      ),
      StockMovement(
        id: 'new',
        productId: 'p1',
        productName: 'Product',
        type: 'auto_correction',
        quantity: 1,
        date: date.add(const Duration(days: 1)),
      ),
    ];

    expect(
      service.autoCorrectionMovements(movements).map((item) => item.id),
      <String>['new', 'reviewed', 'old'],
    );
    expect(
      service.pendingAutoCorrectionMovements(movements).map((item) => item.id),
      <String>['new', 'old'],
    );
  });

  test('warehouse stock projection keeps the existing movement semantics', () {
    final balances = service.warehouseStockBalances(
      products: <Product>[
        Product(
          id: 'p1',
          name: 'Tracked',
          code: 'P1',
          price: 0,
          cost: 0,
          stock: 0,
          category: 'Test',
        ),
        Product(
          id: 'deleted',
          name: 'Deleted',
          code: 'P2',
          price: 0,
          cost: 0,
          stock: 0,
          category: 'Test',
          deletedAt: date,
        ),
      ],
      warehouses: <Warehouse>[
        Warehouse(id: 'main', name: 'Main', isDefault: true),
        Warehouse(id: 'remote', name: 'Remote'),
        Warehouse(id: 'deleted', name: 'Deleted', deletedAt: date),
      ],
      movements: <StockMovement>[
        StockMovement(
          id: 'main-movement',
          productId: 'p1',
          productName: 'Tracked',
          type: 'in',
          quantity: 8,
          date: date,
          warehouseId: '',
        ),
        StockMovement(
          id: 'remote-movement',
          productId: 'p1',
          productName: 'Tracked',
          type: 'out',
          quantity: -3,
          date: date,
          warehouseId: 'remote',
        ),
      ],
    );

    expect(
      service.stockForWarehouse(
        balances,
        productId: 'p1',
        warehouseId: '',
      ),
      8,
    );
    expect(
      service.stockForWarehouse(
        balances,
        productId: 'p1',
        warehouseId: 'remote',
      ),
      -3,
    );
    expect(balances.containsKey('deleted'), isFalse);
    expect(balances['p1']!.containsKey('deleted'), isFalse);
  });
}
