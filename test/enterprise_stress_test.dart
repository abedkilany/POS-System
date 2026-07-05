import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/repositories/auth_repository.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/services/store_bootstrap_service.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/core/repositories/business_repositories.dart';
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
  await StoreBootstrapService.completeInitialAdminSetup(
      store,
      fullName: 'Admin', username: 'admin', password: 'AdminPass123');
  await AuthRepository.login(store, 'admin', 'AdminPass123');
  return store;
}

void main() {
  group('Enterprise stress and recovery tests', () {
    test(
        'handles realistic catalog and sales volume without corrupting inventory',
        () async {
      final store = await _readyStore();

      for (var i = 0; i < 75; i++) {
        await ProductRepository.addOrUpdateProduct(store, _product(i));
      }

      final seededProductsPage =
          await ProductRepository.queryPage(limit: 100, offset: 0);
      final seededProducts = seededProductsPage?.items ?? const <Product>[];
      expect(seededProducts, hasLength(75));
      expect(await BusinessSummaryRepository.inventoryRetailValue(), greaterThan(0));
      expect(await BusinessSummaryRepository.inventoryCostValue(), greaterThan(0));

      for (var i = 0; i < 30; i++) {
        final product = seededProducts[i % seededProducts.length];
        await SaleRepository.createSale(context: store, 
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

      expect(await SaleRepository.countAll(), 30);
      final refreshedProductsPage =
          await ProductRepository.queryPage(limit: 100, offset: 0);
      expect(refreshedProductsPage?.items.where((p) => p.stock < 0), isEmpty);
      expect(await BusinessSummaryRepository.totalSalesAmount(), greaterThan(0));
      expect(store.syncChanges, isNotEmpty);
      expect(await store.syncState.pendingSyncQueueCount(store), 0);
    });

    test('backup restore survives a populated store round trip', () async {
      final store = await _readyStore();
      for (var i = 0; i < 20; i++) {
        await ProductRepository.addOrUpdateProduct(store, _product(i));
      }

      final backup = await store.exportBackupJson();
      expect(store.validateBackupJson(backup).isValid, isTrue);

      await store.resetBusinessData();
      expect(await ProductRepository.countAll(), 0);

      await store.recovery.importBackupJson(backup);
      final restoredProductsPage =
          await ProductRepository.queryPage(limit: 50, offset: 0);
      final restoredProducts = restoredProductsPage?.items ?? const <Product>[];
      expect(restoredProducts, hasLength(20));
      expect(restoredProducts.map((p) => p.code), contains('STRESS-0'));
    });
  });
}
