import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/customer.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/purchase_item.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/supplier.dart';

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
      'syncMode': 'localOnly',
      'createdAt': now,
      'updatedAt': now,
      'hostDeviceId': '',
      'cloudTenantId': '',
      'deviceToken': 'device_stress_host',
      'storeEpoch': 1,
      'recoveryKey': 'RK-STRE-TEST-HOST',
      'activeSyncTransport': 'local',
    }),
  };
}

Future<AppStore> _readyStore() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  LocalDatabaseService.clearInMemoryStoreForTesting();
  LocalDatabaseService.useInMemoryStoreForTesting(_hostIdentitySeed());
  final store = AppStore();
  await store.initialize();
  await store.completeInitialAdminSetup(
    fullName: 'Admin',
    username: 'admin',
    password: 'AdminPass123',
  );
  return store;
}

void main() {
  test('direct stress-lab inventory experiment keeps purchase and sale links', () async {
    final store = await _readyStore();
    await store.setStressLabEnabled(true);

    await store.addOrUpdateProduct(
      Product(
        id: 'lab_product_1',
        code: 'LAB-1',
        name: 'Lab Product 1',
        price: 20,
        cost: 8,
        stock: 0,
        category: 'Lab',
        trackStock: true,
      ),
    );
    await store.addOrUpdateCustomer(
      Customer(
        id: 'lab_customer_1',
        name: 'Lab Customer 1',
        phone: '111',
        address: 'Main St',
      ),
    );
    await store.addOrUpdateSupplier(
      Supplier(
        id: 'lab_supplier_1',
        name: 'Lab Supplier 1',
        phone: '222',
        address: 'Warehouse',
        notes: '',
      ),
    );

    final purchase = await store.createPurchase(
      supplierId: 'lab_supplier_1',
      supplierName: 'Lab Supplier 1',
      receiveNow: true,
      paymentStatus: 'paid',
      paymentMethod: 'Card',
      items: const [
        PurchaseItem(
          productId: 'lab_product_1',
          productName: 'Lab Product 1',
          quantity: 5,
          unitCost: 8,
          conversionToBase: 1,
        ),
      ],
    );

    final sale = await store.createSale(
      customerId: 'lab_customer_1',
      customerName: 'Lab Customer 1',
      paymentMethod: 'Card',
      paymentStatus: 'paid',
      items: const [
        SaleItem(
          productId: 'lab_product_1',
          productName: 'Lab Product 1',
          unitPrice: 20,
          quantity: 2,
          unitCost: 8,
          baseQuantity: 2,
          conversionToBase: 1,
        ),
      ],
    );

    final purchaseMovement = store.stockMovements.firstWhere(
      (m) => m.referenceId == purchase.id && m.type == 'purchase_receive',
    );
    final saleMovement = store.stockMovements.firstWhere(
      (m) => m.referenceId == sale.id && m.type == 'sale',
    );

    expect(purchaseMovement.referenceNo, purchase.purchaseNo);
    expect(saleMovement.referenceNo, sale.invoiceNo);
    expect(store.stockForWarehouse('lab_product_1', 'main'), greaterThan(0));

    final missingRefs = store.stockMovements.where((movement) {
      final type = movement.type.toLowerCase();
      if (movement.referenceId.isEmpty) return false;
      if (type.contains('sale')) return movement.referenceId != sale.id;
      if (type.contains('purchase')) return movement.referenceId != purchase.id;
      return false;
    }).toList();
    expect(missingRefs, isEmpty);
  });
}
