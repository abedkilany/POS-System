import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/sale_item.dart';

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

Map<String, String> _hostIdentitySeed() {
  final now = DateTime(2026, 1, 1).toIso8601String();
  return <String, String>{
    'app_identity_v1': jsonEncode(<String, dynamic>{
      'storeId': 'ST-STRESS',
      'branchId': 'BR-STRESS',
      'deviceId': 'DV-STRESS',
      'deviceName': 'Stress Test Host',
      'platform': 'windows',
      'deviceRole': 'host',
      'appRole': 'store',
      'syncMode': 'lanOnly',
      'createdAt': now,
      'updatedAt': now,
      'hostDeviceId': '',
      'cloudTenantId': '',
      'deviceToken': 'device_stress_host',
      'storeEpoch': 1,
      'recoveryKey': 'RK-STRE-TEST-HOST',
    }),
  };
}

Future<AppStore> _readyStore() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  LocalDatabaseService.useInMemoryStoreForTesting(_hostIdentitySeed());
  final store = AppStore();
  await store.initialize();
  await store.completeInitialAdminSetup(
      fullName: 'Admin', username: 'admin', password: 'AdminPass123');
  return store;
}

void main() {
  group('Enterprise stress and recovery tests', () {
    test(
        'handles realistic catalog and sales volume without corrupting inventory',
        () async {
      final store = await _readyStore();

      for (var i = 0; i < 75; i++) {
        await store.addOrUpdateProduct(_product(i));
      }

      expect(store.products, hasLength(75));
      expect(store.inventoryRetailValue, greaterThan(0));
      expect(store.inventoryCostValue, greaterThan(0));

      for (var i = 0; i < 30; i++) {
        final product = store.products[i % store.products.length];
        await store.createSale(
          customerName: 'Stress Customer $i',
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

      final backup = store.exportBackupJson();
      expect(store.validateBackupJson(backup).isValid, isTrue);

      await store.resetBusinessData();
      expect(store.products, isEmpty);

      await store.importBackupJson(backup);
      expect(store.products, hasLength(20));
      expect(store.products.map((p) => p.code), contains('STRESS-0'));
    });
  });
}
