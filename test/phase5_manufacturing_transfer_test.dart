import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/models/app_identity.dart';
import 'package:ventio/core/localization/localized_domain_exception.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/services/stock_transaction_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/manufacturing.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/stock_movement.dart';
import 'package:ventio/models/warehouse.dart';
import 'package:ventio/models/warehouse_transfer_order.dart';
import 'package:ventio/models/user_role.dart';

AppStore? _activePhase5SqliteStoreForTesting;

Future<void> _shutdownActivePhase5SqliteStoreForTesting() async {
  final previous = _activePhase5SqliteStoreForTesting;
  if (previous == null) return;
  _activePhase5SqliteStoreForTesting = null;
  await previous.prepareForShutdown();
  previous.dispose();
  await LocalDatabaseService.flushPendingWrites();
  await Future<void>.delayed(Duration.zero);
}

Future<void> shutdownPhase5SqliteStoreForTesting() async {
  await _shutdownActivePhase5SqliteStoreForTesting();
  await LocalDatabaseService.resetForTesting();
}

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
  await _shutdownActivePhase5SqliteStoreForTesting();
  await LocalDatabaseService.resetForTesting();
  await SqliteMigrationManager.initializeFreshSqlite();
  await LocalDatabaseService.useSqliteDatabaseForTesting(
    SqliteMigrationManager.database!,
  );
  await LocalDatabaseService.initialize();
  final db = SqliteMigrationManager.database!;
  await db.initializeFoundation();
  await db.transaction(() async {
    // The Phase 5 helper intentionally starts each test from a financially
    // clean fixture. Unified Batch semantic-account reconciliation compares
    // physical valuation to the inventory GL, so retaining journal rows while
    // deleting inventory would manufacture a false mismatch between tests.
    await db.customStatement('DELETE FROM journal_lines');
    await db.customStatement('DELETE FROM journal_entries');
    await db.customStatement('DELETE FROM account_transactions');
    await db.customStatement(
      "UPDATE accounts SET is_postable = 1 "
      "WHERE id IN ('acc_inventory', 'acc_inventory_raw', "
      "'acc_inventory_wip', 'acc_inventory_finished', "
      "'acc_inventory_merchandise')",
    );
    await db.customStatement('DELETE FROM sale_item_batch_allocations');
    await db.customStatement('DELETE FROM purchase_item_batch_allocations');
    await db.customStatement('DELETE FROM inventory_batch_balances');
    await db.customStatement('DELETE FROM inventory_batches');
    await db.customStatement('DELETE FROM unified_batch_cutovers');
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
  await store.ensureHeavyDataLoaded(failOnError: true);
  _activePhase5SqliteStoreForTesting = store;
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
      final rawWarehouse =
          await store.createWarehouse(name: 'Raw', code: 'RAW');
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

    test(
        'multi-product transfer order moves all lines atomically and persists order',
        () async {
      final store = await readyPhase5SqliteStore();
      await store.addOrUpdateProduct(
        phase5Product(id: 'bulk-1', code: 'BLK-1', stock: 0, cost: 2),
      );
      await store.addOrUpdateProduct(
        phase5Product(id: 'bulk-2', code: 'BLK-2', stock: 0, cost: 4),
      );
      final source =
          await store.createWarehouse(name: 'Bulk Source', code: 'BS');
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final destination =
          await store.createWarehouse(name: 'Bulk Destination', code: 'BD');
      await store.adjustStock(
        productId: 'bulk-1',
        warehouseId: source.id,
        quantityDelta: 10,
        reason: 'seed bulk 1',
      );
      await store.adjustStock(
        productId: 'bulk-2',
        warehouseId: source.id,
        quantityDelta: 20,
        reason: 'seed bulk 2',
      );

      final order = await store.createWarehouseTransferOrder(
        fromWarehouseId: source.id,
        toWarehouseId: destination.id,
        notes: 'truck load',
        items: const <WarehouseTransferOrderItem>[
          WarehouseTransferOrderItem(
            productId: 'bulk-1',
            productName: 'Coffee',
            quantity: 3,
          ),
          WarehouseTransferOrderItem(
            productId: 'bulk-2',
            productName: 'Coffee',
            quantity: 7,
          ),
        ],
      );

      expect(order.items.length, 2);
      expect(order.totalUnits, 10);
      expect(
          await sqliteWarehouseQuantity(
            productId: 'bulk-1',
            warehouseId: source.id,
            storeId: store.appIdentity.storeId,
          ),
          7);
      expect(
          await sqliteWarehouseQuantity(
            productId: 'bulk-1',
            warehouseId: destination.id,
            storeId: store.appIdentity.storeId,
          ),
          3);
      expect(
          await sqliteWarehouseQuantity(
            productId: 'bulk-2',
            warehouseId: source.id,
            storeId: store.appIdentity.storeId,
          ),
          13);
      expect(
          await sqliteWarehouseQuantity(
            productId: 'bulk-2',
            warehouseId: destination.id,
            storeId: store.appIdentity.storeId,
          ),
          7);
      final persisted = await store.recentWarehouseTransferOrders();
      expect(persisted.any((item) => item.id == order.id), isTrue);
      final movements = store.stockMovements
          .where((movement) => movement.movementGroupId == order.id)
          .toList();
      expect(movements.length, 4);
    });

    test(
        'multi-product transfer order rolls back every line when one item is insufficient',
        () async {
      final store = await readyPhase5SqliteStore();
      await store.addOrUpdateProduct(
        phase5Product(id: 'rollback-1', code: 'RB-1', stock: 0, cost: 2),
      );
      await store.addOrUpdateProduct(
        phase5Product(id: 'rollback-2', code: 'RB-2', stock: 0, cost: 4),
      );
      final source =
          await store.createWarehouse(name: 'Rollback Source', code: 'RS');
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final destination =
          await store.createWarehouse(name: 'Rollback Destination', code: 'RD');
      await store.adjustStock(
        productId: 'rollback-1',
        warehouseId: source.id,
        quantityDelta: 10,
        reason: 'seed rollback 1',
      );
      await store.adjustStock(
        productId: 'rollback-2',
        warehouseId: source.id,
        quantityDelta: 2,
        reason: 'seed rollback 2',
      );

      await expectLater(
        store.createWarehouseTransferOrder(
          fromWarehouseId: source.id,
          toWarehouseId: destination.id,
          items: const <WarehouseTransferOrderItem>[
            WarehouseTransferOrderItem(
              productId: 'rollback-1',
              productName: 'Coffee',
              quantity: 3,
            ),
            WarehouseTransferOrderItem(
              productId: 'rollback-2',
              productName: 'Coffee',
              quantity: 5,
            ),
          ],
        ),
        throwsA(isA<LocalizedDomainException>()),
      );

      expect(
          await sqliteWarehouseQuantity(
            productId: 'rollback-1',
            warehouseId: source.id,
            storeId: store.appIdentity.storeId,
          ),
          10);
      expect(
          await sqliteWarehouseQuantity(
            productId: 'rollback-1',
            warehouseId: destination.id,
            storeId: store.appIdentity.storeId,
          ),
          0);
      expect(
          await sqliteWarehouseQuantity(
            productId: 'rollback-2',
            warehouseId: source.id,
            storeId: store.appIdentity.storeId,
          ),
          2);
      expect(
          await sqliteWarehouseQuantity(
            productId: 'rollback-2',
            warehouseId: destination.id,
            storeId: store.appIdentity.storeId,
          ),
          0);
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
      final db = SqliteMigrationManager.database!;
      final service = StockTransactionService(
        db,
        deviceId: store.appIdentity.deviceId,
        defaultStoreId: store.appIdentity.storeId,
        defaultBranchId: store.appIdentity.branchId,
      );
      // This is a StockTransactionService idempotency contract. Seed the same
      // low-level warehouse ledger that the service owns instead of using
      // AppStore.adjustStock(), which also creates Unified Batch balances.
      await service.applyDelta(
        storeId: store.appIdentity.storeId,
        warehouseId: source.id,
        productId: 'dup-1',
        delta: 6,
        branchId: store.appIdentity.branchId,
        deviceId: store.appIdentity.deviceId,
        lastModifiedByDeviceId: store.appIdentity.deviceId,
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
        phase5Product(id: 'legacy-raw-1', code: 'LRAW-1', stock: 0, cost: 2),
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

    test('deleting an in-progress manufacturing order persists the delete',
        () async {
      final store = await readyPhase5SqliteStore();
      await store.addOrUpdateProduct(
        phase5Product(id: 'delete-mfg-1', code: 'DMFG-1', stock: 0, cost: 2),
      );
      await store.addOrUpdateProduct(
        phase5Product(id: 'delete-raw-1', code: 'DRAW-1', stock: 0, cost: 1),
      );
      final bom = await store.createBillOfMaterials(
        name: 'Delete BOM',
        outputProductId: 'delete-mfg-1',
        outputQuantity: 1,
        components: const <BillOfMaterialsLine>[
          BillOfMaterialsLine(
            productId: 'delete-raw-1',
            productName: 'Raw',
            quantity: 1,
            unitCost: 1,
          ),
        ],
      );
      final order = await store.startManufacturingOrder(
        bomId: bom.id,
        quantity: 1,
      );

      await store.deleteManufacturingOrder(order.id);

      expect(store.manufacturingOrders.any((item) => item.id == order.id),
          isFalse);
      final db = SqliteMigrationManager.database;
      expect(db, isNotNull);
      final rows = await db!.customSelect(
        'SELECT deleted_at FROM manufacturing_orders WHERE id = ?',
        variables: <Variable<Object>>[Variable<String>(order.id)],
      ).get();
      expect(rows.single.read<String>('deleted_at'), isNotEmpty);
    });
  });
}
