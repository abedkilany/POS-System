import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/models/app_identity.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/services/stock_transaction_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/manufacturing.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/stock_movement.dart';
import 'package:ventio/models/warehouse.dart';
import 'package:ventio/models/user_role.dart';

Product phase5Product({
  String id = 'p1',
  String code = 'P001',
  String name = 'Coffee',
  double stock = 10,
  double price = 12,
  double cost = 7,
}) {
  return Product(
    id: id,
    name: name,
    code: code,
    price: price,
    cost: cost,
    stock: stock,
    category: 'Drinks',
  );
}

Future<AppStore> readyPhase5SqliteStore() async {
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
    await db.customStatement('DELETE FROM purchase_items');
    await db.customStatement('DELETE FROM purchases');
    await db.customStatement('DELETE FROM manufacturing_orders');
    await db.customStatement('DELETE FROM bill_of_materials_lines');
    await db.customStatement('DELETE FROM bill_of_materials');
    await db.customStatement('DELETE FROM stock_movements');
    await db.customStatement('DELETE FROM warehouse_inventory');
    await db.customStatement('DELETE FROM stock_operations');
    await db.customStatement('DELETE FROM sync_events');
    await db.customStatement('DELETE FROM pending_sync_changes');
    await db.customStatement('DELETE FROM sync_queue');
    await db.customStatement('DELETE FROM products');
    await db.customStatement('DELETE FROM warehouses');
  });

  final store = AppStore();
  await store.initialize();
  await store.recoverOnlineStoreOwnerIdentity(
    storeId: 'ST-PHASE5',
    branchId: 'BR-PHASE5',
    storeName: 'Phase 5 Store',
    username: 'owner',
    password: 'OwnerPass123',
    deviceRole: DeviceRole.host,
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

Future<double> sqliteWarehouseQuantity({
  required String productId,
  required String warehouseId,
  required String storeId,
}) async {
  final db = SqliteMigrationManager.database;
  expect(db != null, isTrue);
  final rows = await db!.customSelect(
    '''
    SELECT COALESCE(SUM(quantity), 0) AS quantity
    FROM warehouse_inventory
    WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
    ''',
    variables: <Variable<Object>>[
      Variable<String>(storeId),
      Variable<String>(warehouseId),
      Variable<String>(productId),
    ],
  ).get();
  return (rows.first.data['quantity'] as num? ?? 0).toDouble();
}

void main() {
  group('Phase 5 manufacturing and warehouse transfers', () {
    test('manufacturing consumes raw stock and produces into target warehouse',
        () async {
      final store = await readyPhase5SqliteStore();
      await store.addOrUpdateProduct(
        phase5Product(id: 'raw-1', code: 'RAW-1', stock: 0, cost: 2),
      );
      await store.addOrUpdateProduct(
        phase5Product(id: 'fg-1', code: 'FG-1', stock: 0, cost: 0),
      );
      final rawWarehouse = await store.createWarehouse(name: 'Raw', code: 'RAW');
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final finishedWarehouse =
          await store.createWarehouse(name: 'Finished', code: 'FIN');
      await store.adjustStock(
        productId: 'raw-1',
        warehouseId: rawWarehouse.id,
        quantityDelta: 10,
        reason: 'seed raw',
      );
      expect(
        await sqliteWarehouseQuantity(
          productId: 'raw-1',
          warehouseId: rawWarehouse.id,
          storeId: store.appIdentity.storeId,
        ),
        10,
      );
      final bom = await store.createBillOfMaterials(
        name: 'BOM FG',
        outputProductId: 'fg-1',
        outputQuantity: 1,
        components: const [
          BillOfMaterialsLine(
            productId: 'raw-1',
            productName: 'Raw',
            quantity: 4,
            unitCost: 2,
          ),
        ],
      );

      final order = await store.completeManufacturingOrder(
        bomId: bom.id,
        quantity: 1,
        rawMaterialsWarehouseId: rawWarehouse.id,
        rawMaterialsWarehouseName: rawWarehouse.name,
        finishedGoodsWarehouseId: finishedWarehouse.id,
        finishedGoodsWarehouseName: finishedWarehouse.name,
      );

      expect(order.rawMaterialsWarehouseId, rawWarehouse.id);
      expect(order.finishedGoodsWarehouseId, finishedWarehouse.id);
      expect(
        await sqliteWarehouseQuantity(
          productId: 'raw-1',
          warehouseId: rawWarehouse.id,
          storeId: store.appIdentity.storeId,
        ),
        6,
      );
      expect(
        await sqliteWarehouseQuantity(
          productId: 'fg-1',
          warehouseId: finishedWarehouse.id,
          storeId: store.appIdentity.storeId,
        ),
        1,
      );
      expect(store.stockForWarehouse('raw-1', rawWarehouse.id), 6);
      expect(store.stockForWarehouse('fg-1', finishedWarehouse.id), 1);
      expect(
        store.stockMovements.where((m) => m.movementGroupId == order.id).length,
        2,
      );
    });

    test('transfer moves stock once and keeps total quantity stable', () async {
      final store = await readyPhase5SqliteStore();
      await store.addOrUpdateProduct(
        phase5Product(id: 'move-1', code: 'MV-1', stock: 0, cost: 3),
      );
      final source = await store.createWarehouse(name: 'Source', code: 'SRC');
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final destination =
          await store.createWarehouse(name: 'Destination', code: 'DST');
      await store.adjustStock(
        productId: 'move-1',
        warehouseId: source.id,
        quantityDelta: 8,
        reason: 'seed transfer stock',
      );

      await store.transferStock(
        productId: 'move-1',
        fromWarehouseId: source.id,
        toWarehouseId: destination.id,
        quantity: 5,
      );

      expect(
        await sqliteWarehouseQuantity(
          productId: 'move-1',
          warehouseId: source.id,
          storeId: store.appIdentity.storeId,
        ),
        3,
      );
      expect(
        await sqliteWarehouseQuantity(
          productId: 'move-1',
          warehouseId: destination.id,
          storeId: store.appIdentity.storeId,
        ),
        5,
      );
      expect(await store.totalWarehouseStockFromSqlite('move-1'), 8);
    });

    test('duplicate transfer replay does not double apply', () async {
      final store = await readyPhase5SqliteStore();
      await store.addOrUpdateProduct(
        phase5Product(id: 'dup-1', code: 'DP-1', stock: 0, cost: 3),
      );
      final source = await store.createWarehouse(name: 'Source', code: 'SRC');
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final destination =
          await store.createWarehouse(name: 'Destination', code: 'DST');
      await store.adjustStock(
        productId: 'dup-1',
        warehouseId: source.id,
        quantityDelta: 6,
        reason: 'seed transfer stock',
      );

      final db = SqliteMigrationManager.database!;
      final service = StockTransactionService(
        db,
        deviceId: store.appIdentity.deviceId,
        defaultStoreId: store.appIdentity.storeId,
        defaultBranchId: store.appIdentity.branchId,
      );
      final now = DateTime.now();
      final transferId = 'transfer-phase5-${now.microsecondsSinceEpoch}';
      final movements = <StockMovement>[
        StockMovement(
          id: '$transferId-dup-1-transfer-out',
          productId: 'dup-1',
          productName: 'Coffee',
          type: 'transfer_out',
          quantity: -4,
          date: now,
          referenceId: transferId,
          referenceNo: 'TR-$transferId',
          reason: 'Transfer out',
          warehouseId: source.id,
          warehouseName: source.name,
          movementGroupId: transferId,
          documentLineId: '$transferId-line-out',
          idempotencyKey: '$transferId:transfer:out',
          unitCost: 3,
          createdAt: now,
          updatedAt: now,
          deviceId: store.appIdentity.deviceId,
          storeId: store.appIdentity.storeId,
          branchId: store.appIdentity.branchId,
          lastModifiedByDeviceId: store.appIdentity.deviceId,
        ),
        StockMovement(
          id: '$transferId-dup-1-transfer-in',
          productId: 'dup-1',
          productName: 'Coffee',
          type: 'transfer_in',
          quantity: 4,
          date: now,
          referenceId: transferId,
          referenceNo: 'TR-$transferId',
          reason: 'Transfer in',
          warehouseId: destination.id,
          warehouseName: destination.name,
          movementGroupId: transferId,
          documentLineId: '$transferId-line-in',
          idempotencyKey: '$transferId:transfer:in',
          unitCost: 3,
          createdAt: now,
          updatedAt: now,
          deviceId: store.appIdentity.deviceId,
          storeId: store.appIdentity.storeId,
          branchId: store.appIdentity.branchId,
          lastModifiedByDeviceId: store.appIdentity.deviceId,
        ),
      ];

      await service.recordMovementsAtomically(
        operationType: 'warehouse_transfer',
        documentType: 'stock_transfer',
        documentId: transferId,
        movementGroupId: transferId,
        idempotencyKey: '$transferId:warehouse_transfer',
        movements: movements,
        storeId: store.appIdentity.storeId,
        branchId: store.appIdentity.branchId,
        deviceId: store.appIdentity.deviceId,
      );
      await service.recordMovementsAtomically(
        operationType: 'warehouse_transfer',
        documentType: 'stock_transfer',
        documentId: transferId,
        movementGroupId: transferId,
        idempotencyKey: '$transferId:warehouse_transfer',
        movements: movements,
        storeId: store.appIdentity.storeId,
        branchId: store.appIdentity.branchId,
        deviceId: store.appIdentity.deviceId,
      );

      expect(
        await sqliteWarehouseQuantity(
          productId: 'dup-1',
          warehouseId: source.id,
          storeId: store.appIdentity.storeId,
        ),
        2,
      );
      expect(
        await sqliteWarehouseQuantity(
          productId: 'dup-1',
          warehouseId: destination.id,
          storeId: store.appIdentity.storeId,
        ),
        4,
      );
    });

    test('legacy manufacturing defaults to main warehouse', () async {
      final store = await readyPhase5SqliteStore();
      await store.addOrUpdateProduct(
        phase5Product(id: 'legacy-raw-1', code: 'LRAW-1', stock: 1, cost: 2),
      );
      await store.addOrUpdateProduct(
        phase5Product(id: 'legacy-mfg-1', code: 'LMFG-1', stock: 0, cost: 2),
      );
      await store.adjustStock(
        productId: 'legacy-raw-1',
        warehouseId: Warehouse.defaultId,
        quantityDelta: 1,
        reason: 'seed main',
      );
      final bom = await store.createBillOfMaterials(
        name: 'Legacy BOM',
        outputProductId: 'legacy-mfg-1',
        outputQuantity: 1,
        components: const [
          BillOfMaterialsLine(
            productId: 'legacy-raw-1',
            productName: 'Raw',
            quantity: 1,
            unitCost: 2,
          ),
        ],
      );
      final order = await store.completeManufacturingOrder(
        bomId: bom.id,
        quantity: 1,
      );

      expect(order.rawMaterialsWarehouseId, Warehouse.defaultId);
      expect(order.finishedGoodsWarehouseId, Warehouse.defaultId);
    });
  });
}
