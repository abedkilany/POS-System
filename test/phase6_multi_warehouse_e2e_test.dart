import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/services/stock_transaction_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/app_identity.dart';
import 'package:ventio/models/customer.dart';
import 'package:ventio/models/manufacturing.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/purchase_item.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/supplier.dart';
import 'package:ventio/models/user_role.dart';

Product _product({
  required String id,
  required String code,
  required String name,
  double stock = 0,
  double cost = 0,
}) {
  return Product(
    id: id,
    code: code,
    name: name,
    price: cost + 5,
    cost: cost,
    stock: stock,
    category: 'Test',
  );
}

Future<AppStore> _readyPhase6SqliteStore({
  DeviceRole deviceRole = DeviceRole.host,
  String storeId = 'ST-PHASE6',
  String branchId = 'BR-PHASE6',
  String storeName = 'Phase 6 Store',
}) async {
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
  await LocalDatabaseService.initialize();
  final db = SqliteMigrationManager.database!;
  await db.initializeFoundation();
  await db.transaction(() async {
    await db.customStatement('DELETE FROM sale_items');
    await db.customStatement('DELETE FROM sales');
    await db.customStatement('DELETE FROM purchase_items');
    await db.customStatement('DELETE FROM purchases');
    await db.customStatement('DELETE FROM stock_movements');
    await db.customStatement('DELETE FROM warehouse_inventory');
    await db.customStatement('DELETE FROM stock_operations');
    await db.customStatement('DELETE FROM inventory_reconciliations');
    await db.customStatement('DELETE FROM inventory_migration_adjustments');
    await db.customStatement('DELETE FROM inventory_count_lines');
    await db.customStatement('DELETE FROM inventory_counts');
    await db.customStatement('DELETE FROM sync_events');
    await db.customStatement('DELETE FROM pending_sync_changes');
    await db.customStatement('DELETE FROM sync_queue');
    await db.customStatement('DELETE FROM products');
    await db.customStatement('DELETE FROM warehouses');
    await db.customStatement('DELETE FROM customers');
    await db.customStatement('DELETE FROM suppliers');
    await db.customStatement('DELETE FROM bill_of_materials_lines');
    await db.customStatement('DELETE FROM bill_of_materials');
    await db.customStatement('DELETE FROM manufacturing_orders');
  });

  final store = AppStore();
  await store.initialize();
  await store.recoverOnlineStoreOwnerIdentity(
    storeId: storeId,
    branchId: branchId,
    storeName: storeName,
    username: 'owner',
    password: 'OwnerPass123',
    deviceRole: deviceRole,
    syncMode: SyncMode.localOnly,
  );
  expect(await store.login('owner', 'OwnerPass123'), isTrue);
  await store.applySessionUser(
    activeUser: store.activeUser!,
    currentRole: 'Admin',
    permissions: Set<String>.from(AppPermission.all),
    rememberLogin: true,
  );
  return store;
}

Future<double> _warehouseQty(String productId, String warehouseId) async {
  final db = SqliteMigrationManager.database!;
  final rows = await db.customSelect(
    '''
    SELECT COALESCE(SUM(quantity), 0) AS quantity
    FROM warehouse_inventory
    WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
    ''',
    variables: <Variable<Object>>[
      Variable<String>('ST-PHASE6'),
      Variable<String>(warehouseId),
      Variable<String>(productId),
    ],
  ).get();
  return (rows.first.data['quantity'] as num? ?? 0).toDouble();
}

void main() {
  group('Phase 6 end-to-end warehouse scenario', () {
    tearDown(LocalDatabaseService.clearInMemoryStoreForTesting);

    test('covers purchase, transfer, sale, return, manufacturing, count, backup and replay', () async {
      final store = await _readyPhase6SqliteStore();
      await store.addOrUpdateProduct(_product(id: 'raw-1', code: 'RAW-1', name: 'Raw Product', cost: 2));
      await store.addOrUpdateProduct(_product(id: 'fg-1', code: 'FG-1', name: 'Finished Product', cost: 0));
      await store.addOrUpdateCustomer(Customer(id: 'c1', name: 'Alice', phone: '1', address: 'A'));
      await store.addOrUpdateSupplier(Supplier(id: 's1', name: 'Supplier', phone: '2', address: 'B', notes: ''));
      final warehouseA = await store.createWarehouse(name: 'Warehouse A', code: 'WA');
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final warehouseB = await store.createWarehouse(name: 'Warehouse B', code: 'WB');

      final purchase = await store.createPurchase(
        supplierId: 's1',
        supplierName: 'Supplier',
        items: const [
          PurchaseItem(
            productId: 'raw-1',
            productName: 'Raw Product',
            quantity: 10,
            unitCost: 2,
          ),
        ],
        receiveNow: true,
        warehouseId: warehouseA.id,
        warehouseName: warehouseA.name,
      );
      await store.transferStock(
        productId: 'raw-1',
        fromWarehouseId: warehouseA.id,
        toWarehouseId: warehouseB.id,
        quantity: 4,
      );
      final sale = await store.createSale(
        customerId: 'c1',
        customerName: 'Alice',
        warehouseId: warehouseB.id,
        warehouseName: warehouseB.name,
        paymentStatus: 'credit',
        paymentMethod: 'Credit',
        items: const [
          SaleItem(
            productId: 'raw-1',
            productName: 'Raw Product',
            unitPrice: 5,
            quantity: 2,
          ),
        ],
      );
      await store.returnSale(sale.id);

      final bom = await store.createBillOfMaterials(
        name: 'Finished Product BOM',
        outputProductId: 'fg-1',
        outputQuantity: 1,
        components: const [
          BillOfMaterialsLine(
            productId: 'raw-1',
            productName: 'Raw Product',
            quantity: 3,
            unitCost: 2,
          ),
        ],
      );
      await store.completeManufacturingOrder(
        bomId: bom.id,
        quantity: 1,
        rawMaterialsWarehouseId: warehouseA.id,
        rawMaterialsWarehouseName: warehouseA.name,
        finishedGoodsWarehouseId: warehouseB.id,
        finishedGoodsWarehouseName: warehouseB.name,
      );

      final countSession = await store.createInventoryCountSession(
        warehouseId: warehouseB.id,
        warehouseName: warehouseB.name,
      );
      final countedFg = await _warehouseQty('fg-1', warehouseB.id);
      await store.countInventoryLine(
        sessionId: countSession.id,
        productId: 'fg-1',
        countedQty: countedFg,
      );
      await store.approveInventoryCount(countSession.id);

      final backupJson = await store.exportBackupJson();

      final restored = await _readyPhase6SqliteStore();
      await restored.importBackupJson(backupJson);
      await restored.importBackupJson(backupJson);

      expect(await _warehouseQty('raw-1', warehouseA.id), greaterThanOrEqualTo(0));
      expect(await _warehouseQty('raw-1', warehouseB.id), greaterThanOrEqualTo(0));
      expect(await _warehouseQty('fg-1', warehouseB.id), greaterThanOrEqualTo(0));
      expect(await restored.totalWarehouseStockFromSqlite('raw-1'),
          await store.totalWarehouseStockFromSqlite('raw-1'));
      expect(await restored.totalWarehouseStockFromSqlite('fg-1'),
          await store.totalWarehouseStockFromSqlite('fg-1'));
      final db = SqliteMigrationManager.database!;
      final movementCount = await db.customSelect(
        'SELECT COUNT(*) AS c FROM stock_movements WHERE store_id = ?',
        variables: <Variable<Object>>[Variable<String>('ST-PHASE6')],
      ).get();
      final emptyWarehouseCount = await db.customSelect(
        '''
        SELECT COUNT(*) AS c
        FROM stock_movements
        WHERE store_id = ? AND (warehouse_id IS NULL OR TRIM(warehouse_id) = '')
        ''',
        variables: <Variable<Object>>[Variable<String>('ST-PHASE6')],
      ).get();
      expect(movementCount.first.read<int>('c'), greaterThanOrEqualTo(1));
      expect(emptyWarehouseCount.first.read<int>('c'), 0);
      expect(
        await StockTransactionService(
          db,
          defaultStoreId: restored.appIdentity.storeId,
          defaultBranchId: restored.appIdentity.branchId,
          deviceId: restored.appIdentity.deviceId,
        ).checkIntegrity(storeId: restored.appIdentity.storeId),
        isA<StockIntegrityReport>(),
      );

      expect(purchase.warehouseId, warehouseA.id);
      expect(sale.warehouseId, warehouseB.id);
    });
  });
}
