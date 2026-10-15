import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/app_identity.dart';
import 'package:ventio/models/customer.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/purchase_item.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/supplier.dart';

Future<AppStore> _readyStore() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final secureStorageChannel =
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureStorage = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async {
    switch (call.method) {
      case 'read':
        return secureStorage[call.arguments['key'] as String];
      case 'write':
        secureStorage[call.arguments['key'] as String] =
            call.arguments['value'] as String? ?? '';
        return null;
      case 'delete':
        secureStorage.remove(call.arguments['key'] as String);
        return null;
      case 'containsKey':
        return secureStorage.containsKey(call.arguments['key'] as String);
      case 'readAll':
        return secureStorage;
      case 'deleteAll':
        secureStorage.clear();
        return null;
      default:
        return null;
    }
  });
  LocalDatabaseService.clearInMemoryStoreForTesting();
  await SqliteMigrationManager.initializeFreshSqlite();
  await LocalDatabaseService.useSqliteDatabaseForTesting(
    SqliteMigrationManager.database!,
  );
  await LocalDatabaseService.initialize();
  final store = AppStore();
  await store.initialize();
  await store.factoryResetLocalDevice(enforcePermission: false);
  await store.recoverOnlineStoreOwnerIdentity(
    storeId: 'ST-INV-TEST',
    branchId: 'BR-INV-TEST',
    storeName: 'Inventory Test Store',
    username: 'admin',
    password: 'AdminPass123',
    deviceRole: DeviceRole.host,
    syncMode: SyncMode.localOnly,
  );
  return store;
}

void main() {
  test('inventory movement references link purchases and sales', () async {
    final store = await _readyStore();

    await store.addOrUpdateProduct(
      Product(
        id: 'inventory_product_1',
        code: 'INV-1',
        name: 'Inventory Test Product',
        price: 20,
        cost: 8,
        stock: 0,
        category: 'Inventory',
        trackStock: true,
      ),
    );
    await store.addOrUpdateCustomer(
      Customer(
        id: 'inventory_customer_1',
        name: 'Inventory Test Customer',
        phone: '111',
        address: 'Main St',
      ),
    );
    await store.addOrUpdateSupplier(
      Supplier(
        id: 'inventory_supplier_1',
        name: 'Inventory Test Supplier',
        phone: '222',
        address: 'Warehouse',
        notes: '',
      ),
    );

    final purchase = await store.createPurchase(
      supplierId: 'inventory_supplier_1',
      supplierName: 'Inventory Test Supplier',
      receiveNow: true,
      paymentStatus: 'paid',
      paymentMethod: 'Card',
      items: const [
        PurchaseItem(
          productId: 'inventory_product_1',
          productName: 'Inventory Test Product',
          quantity: 5,
          unitCost: 8,
          conversionToBase: 1,
        ),
      ],
    );

    final sale = await store.createSale(
      customerId: 'inventory_customer_1',
      customerName: 'Inventory Test Customer',
      paymentMethod: 'Card',
      paymentStatus: 'paid',
      items: const [
        SaleItem(
          productId: 'inventory_product_1',
          productName: 'Inventory Test Product',
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
    expect(
        store.stockForWarehouse('inventory_product_1', 'main'), greaterThan(0));

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
