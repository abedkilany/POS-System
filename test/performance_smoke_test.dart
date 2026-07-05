import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/repositories/auth_repository.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/services/store_bootstrap_service.dart';
import 'package:ventio/core/repositories/business_repositories.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/sale.dart';
import 'package:ventio/models/sale_item.dart';

Map<String, String> _hostIdentitySeed() {
  final now = DateTime(2026, 1, 1).toIso8601String();
  return <String, String>{
    'app_identity_v1': jsonEncode(<String, dynamic>{
      'storeId': 'ST-PERF',
      'branchId': 'BR-PERF',
      'deviceId': 'DV-PERF',
      'deviceName': 'Performance Host',
      'platform': 'windows',
      'deviceRole': 'host',
      'appRole': 'store',
      'syncMode': 'localOnly',
      'createdAt': now,
      'updatedAt': now,
      'hostDeviceId': '',
      'cloudTenantId': '',
      'deviceToken': 'device_perf_host',
      'storeEpoch': 1,
      'recoveryKey': 'RK-PERF-TEST-HOST',
      'activeSyncTransport': 'local',
    }),
  };
}

Product _perfProduct(int index) {
  return Product(
    id: 'perf_product_$index',
    name: 'Performance Product $index',
    nameEn: 'Performance Product $index',
    nameAr: 'منتج اختبار $index',
    code: 'PERF-$index',
    barcode: '978000$index',
    price: 10 + (index % 25),
    cost: 6 + (index % 9),
    stock: index % 50,
    category: index.isEven ? 'Even' : 'Odd',
    brand: index % 3 == 0 ? 'Core' : 'Alt',
    supplier: index % 5 == 0 ? 'Main Supplier' : 'Backup Supplier',
    lowStockThreshold: 5,
  );
}

void main() {
  group('Performance smoke tests', () {
    test('calculates totals for a large invoice within a small budget', () {
      final items = List<SaleItem>.generate(
        1000,
        (index) => SaleItem(
            productId: 'p$index',
            productName: 'Item $index',
            unitPrice: 3.5,
            quantity: 2,
            unitCost: 1.25),
      );
      final sale = Sale(
          id: 's1',
          invoiceNo: 'INV-PERF',
          customerName: 'Customer',
          date: DateTime(2026),
          status: 'Paid',
          discount: 0,
          items: items);

      final stopwatch = Stopwatch()..start();
      final subtotal = sale.subtotal;
      final total = sale.total;
      final grossProfit = sale.grossProfit;
      stopwatch.stop();

      expect(subtotal, 7000);
      expect(total, 7000);
      expect(grossProfit, 4500);
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('filters low stock products at realistic catalog scale', () {
      final products = List<Product>.generate(
        5000,
        (index) => Product(
            id: 'p$index',
            name: 'Product $index',
            code: 'SKU-$index',
            price: 10,
            cost: 6,
            stock: index % 10,
            category: 'General',
            lowStockThreshold: 3),
      );

      final stopwatch = Stopwatch()..start();
      final lowStock = products.where((product) => product.isLowStock).toList();
      stopwatch.stop();

      expect(lowStock.length, 2000);
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('builds and searches a product index at large catalog scale', () {
      final products = List<Product>.generate(10000, _perfProduct);

      final stopwatch = Stopwatch()..start();
      final index = <String, String>{
        for (final product in products)
          product.id:
              '${product.name} ${product.nameEn} ${product.nameAr} ${product.code} ${product.barcode} ${product.category} ${product.brand} ${product.supplier}'
                  .toLowerCase(),
      };
      final matches = products
          .where((product) => index[product.id]?.contains('perf-999') ?? false)
          .toList(growable: false);
      stopwatch.stop();

      expect(matches.map((item) => item.code), contains('PERF-999'));
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });

    test('initializes an in-memory store with realistic seed data', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final seed = _hostIdentitySeed();
      seed['products_v4'] = jsonEncode(
        List<Product>.generate(2500, _perfProduct)
            .map((item) => item.toJson())
            .toList(growable: false),
      );
      LocalDatabaseService.useInMemoryStoreForTesting(seed);
      addTearDown(LocalDatabaseService.clearInMemoryStoreForTesting);

      final store = AppStore();
      final stopwatch = Stopwatch()..start();
      await store.initialize();
      await StoreBootstrapService.completeInitialAdminSetup(
        store,
        fullName: 'Admin',
        username: 'admin',
        password: 'AdminPass123',
      );
      await AuthRepository.login(store, 'admin', 'AdminPass123');
      stopwatch.stop();

      expect(await ProductRepository.countAll(), 2500);
      expect(stopwatch.elapsedMilliseconds, lessThan(3000));
      store.dispose();
    });
  });
}
