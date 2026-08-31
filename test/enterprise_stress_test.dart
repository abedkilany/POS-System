import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/warehouse.dart';

import 'phase5_manufacturing_transfer_test.dart' as support;

Product _product(int index) {
  return Product(
    id: 'stress_product_$index',
    code: 'STRESS-$index',
    name: 'Stress Product $index',
    price: 10 + index.toDouble(),
    cost: 4 + (index / 10),
    stock: 100,
    category: index.isEven ? 'Even' : 'Odd',
  );
}

Future<AppStore> _readyStore() async {
  final store = await support.readyPhase5SqliteStore();
  await store.ensureHeavyDataLoaded(failOnError: true);
  return store;
}

void main() {
  group('Enterprise stress and recovery tests', () {
    tearDown(LocalDatabaseService.clearInMemoryStoreForTesting);
    test(
        'handles realistic catalog and sales volume without corrupting inventory',
        () async {
      final store = await _readyStore();

      for (var i = 0; i < 75; i++) {
        await store.addOrUpdateProduct(_product(i).copyWith(stock: 0));
        await store.adjustStock(
          productId: 'stress_product_$i',
          warehouseId: Warehouse.defaultId,
          quantityDelta: 100,
          reason: 'stress test seed',
        );
      }

      expect(store.products, hasLength(75));
      expect(store.inventoryRetailValue, greaterThan(0));
      expect(store.inventoryCostValue, greaterThan(0));

      for (var i = 0; i < 30; i++) {
        final product = store.products[i % store.products.length];
        await store.createSale(
          customerId: 'stress-customer-$i',
          customerName: 'Stress Customer $i',
          paymentMethod: 'Credit',
          paymentStatus: 'credit',
          items: [
            SaleItem(
              productId: product.id,
              productName: product.name,
              unitPrice: product.price,
              quantity: 1,
            ),
          ],
        );
      }

      expect(store.sales, hasLength(30));
      expect(store.products.where((p) => p.stock < 0), isEmpty);
      expect(store.totalSalesAmount, greaterThan(0));
      expect(store.syncChanges, isNotEmpty);
      expect(store.pendingSyncQueueCount, 0);
    });

    test('backup restore survives a populated store round trip', () async {
      final store = await _readyStore();
      for (var i = 0; i < 20; i++) {
        await store.addOrUpdateProduct(_product(i));
      }

      final backup = await store.exportBackupJson();
      expect(store.validateBackupJson(backup).isValid, isTrue);

      await store.resetBusinessData();
      expect(store.products, isEmpty);

      await store.importBackupJson(backup);
      expect(store.products, hasLength(20));
      expect(store.products.map((p) => p.code), contains('STRESS-0'));
    });
  });
}
