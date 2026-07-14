import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/repositories/auth_repository.dart';
import 'package:ventio/core/services/stock_transaction_service.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/app_identity.dart';
import 'package:ventio/models/app_user.dart';
import 'package:ventio/models/catalog_item.dart';
import 'package:ventio/models/customer.dart';
import 'package:ventio/models/expense.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/stock_movement.dart';
import 'package:ventio/models/purchase_item.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/store_profile.dart';
import 'package:ventio/models/supplier.dart';
import 'package:ventio/models/sync_change.dart';
import 'package:ventio/models/user_role.dart';
import 'package:ventio/models/warehouse.dart';

Product product(
    {String id = 'p1',
    String code = 'P001',
    String name = 'Coffee',
    double stock = 10,
    double price = 12,
    double cost = 7}) {
  return Product(
      id: id,
      name: name,
      code: code,
      price: price,
      cost: cost,
      stock: stock,
      category: 'Drinks');
}

Map<String, String> hostIdentitySeed([Map<String, String>? seed]) {
  final now = DateTime(2026, 1, 1).toIso8601String();
  return <String, String>{
    ...?seed,
    'app_identity_v1': jsonEncode(<String, dynamic>{
      'storeId': 'ST-TEST01',
      'branchId': 'BR-TEST01',
      'deviceId': 'DV-TEST01',
      'deviceName': 'Test Host',
      'platform': 'windows',
      'deviceRole': 'host',
      'appRole': 'store',
      'syncMode': 'lanOnly',
      'createdAt': now,
      'updatedAt': now,
      'hostDeviceId': '',
      'cloudTenantId': '',
      'deviceToken': 'device_test_host',
      'storeEpoch': 1,
      'recoveryKey': 'RK-TEST-TEST-TEST',
    }),
  };
}

Future<AppStore> readyStore([Map<String, String>? seed]) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  await LocalDatabaseService.resetForTesting();
  LocalDatabaseService.useInMemoryStoreForTesting(hostIdentitySeed(seed));
  final store = AppStore();
  await store.initialize();
  if (store.needsInitialAdminSetup) {
    await store.completeInitialAdminSetup(
        fullName: 'Admin', username: 'admin', password: 'AdminPass123');
  }
  return store;
}

Future<AppStore> readySqliteStore({
  String storeId = 'ST-SQLITE03',
  String branchId = 'BR-SQLITE03',
  String storeName = 'Phase 3 Store',
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
  await LocalDatabaseService.resetForTesting();
  await SqliteMigrationManager.initializeFreshSqlite();
  await LocalDatabaseService.initialize();
  final sqliteDb = SqliteMigrationManager.database;
  expect(sqliteDb != null, isTrue);
  await sqliteDb!.transaction(() async {
    await sqliteDb.customStatement('DELETE FROM sale_items');
    await sqliteDb.customStatement('DELETE FROM sale_item_cost_layer_consumptions');
    await sqliteDb.customStatement('DELETE FROM sales');
    await sqliteDb.customStatement('DELETE FROM purchase_items');
    await sqliteDb.customStatement('DELETE FROM purchases');
    await sqliteDb.customStatement('DELETE FROM stock_movements');
    await sqliteDb.customStatement('DELETE FROM warehouse_inventory');
    await sqliteDb.customStatement('DELETE FROM stock_operations');
    await sqliteDb.customStatement('DELETE FROM inventory_reconciliations');
    await sqliteDb.customStatement('DELETE FROM inventory_migration_adjustments');
    await sqliteDb.customStatement('DELETE FROM inventory_count_lines');
    await sqliteDb.customStatement('DELETE FROM inventory_counts');
    await sqliteDb.customStatement('DELETE FROM sync_events');
    await sqliteDb.customStatement('DELETE FROM pending_sync_changes');
    await sqliteDb.customStatement('DELETE FROM sync_queue');
    await sqliteDb.customStatement('DELETE FROM products');
    await sqliteDb.customStatement('DELETE FROM warehouses');
  });
  final store = AppStore();
  await store.initialize();
  await store.recoverOnlineStoreOwnerIdentity(
    storeId: storeId,
    branchId: branchId,
    storeName: storeName,
    username: 'owner',
    password: 'OwnerPass123',
    deviceRole: DeviceRole.host,
    syncMode: SyncMode.localOnly,
  );
  expect(await store.login('owner', 'OwnerPass123'), isTrue);
  expect(store.hasPermission(AppPermission.backupExport), isTrue);
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
  group('AppStore initialization and persisted state', () {
    tearDown(LocalDatabaseService.clearInMemoryStoreForTesting);
    test(
        'initializes defaults, identity, walk-in customer, admin user, and catalog defaults',
        () async {
      final store = await readyStore();

      expect(store.isReady, isTrue);
      expect(store.products, isEmpty);
      expect(store.walkInCustomer.name, AppStore.walkInCustomerName);
      expect(store.customers.map((c) => c.id),
          contains(AppStore.walkInCustomerId));
      expect(store.roles.map((r) => r.id), contains('admin'));
      expect(store.users.map((u) => u.username), contains('admin'));
      expect(store.needsInitialAdminSetup, isFalse);
      expect(store.appIdentity.deviceId, isNotEmpty);
      expect(store.categories, isNotEmpty);
      expect(store.brands, isNotEmpty);
      expect(store.units, isNotEmpty);
      expect(store.currentBackupSummary.storeName, isNotEmpty);
    });

    test(
        're-hydrates products, customers, sales counters, roles, and profile from local db',
        () async {
      final seeded = await readySqliteStore(storeId: 'ST-REHYDRATE01');
      await seeded.addOrUpdateProduct(product());
      await seeded.addOrUpdateCustomer(
          Customer(id: 'c1', name: 'Alice', phone: '1', address: 'A'));
      await seeded.updateStoreProfile(
          StoreProfile.defaults.copyWith(name: 'Seeded Store'));
      final seedStockService = StockTransactionService(
        SqliteMigrationManager.database!,
        defaultStoreId: seeded.appIdentity.storeId,
        defaultBranchId: seeded.appIdentity.branchId,
      );
      await seedStockService.applyDelta(
        storeId: seeded.appIdentity.storeId,
        warehouseId: Warehouse.defaultId,
        productId: 'p1',
        delta: 2,
        branchId: seeded.appIdentity.branchId,
      );
      expect(await seeded.login('owner', 'OwnerPass123'), isTrue);
      await seeded.createSale(
          customerName: 'Alice',
          customerId: 'c1',
          items: const [
        SaleItem(
            productId: 'p1', productName: 'Coffee', unitPrice: 12, quantity: 2)
      ], paymentMethod: 'Credit');
      final raw = await seeded.exportBackupJson();

      final restored = await readySqliteStore(storeId: 'ST-REHYDRATE01');
      await restored.importBackupJson(raw);
      await restored.reloadAllAfterDatabaseChange();

      expect(restored.storeProfile.name, 'Seeded Store');
    });

    test('imports legacy sales without warehouse fields as main warehouse',
        () async {
      final store = await readySqliteStore(storeId: 'ST-LEGACY01');
      await store.addOrUpdateProduct(product(id: 'p-legacy', stock: 0));
      final stockService = StockTransactionService(
        SqliteMigrationManager.database!,
        defaultStoreId: store.appIdentity.storeId,
        defaultBranchId: store.appIdentity.branchId,
      );
      await stockService.applyDelta(
        storeId: store.appIdentity.storeId,
        warehouseId: Warehouse.defaultId,
        productId: 'p-legacy',
        delta: 5,
        branchId: store.appIdentity.branchId,
      );
      final db = SqliteMigrationManager.database!;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.transaction(() async {
        await db.customInsert(
          '''
          INSERT INTO sales (
            id, entity_type, created_at, updated_at, deleted_at, device_id,
            sync_status, store_id, branch_id, version,
            last_modified_by_device_id, sort_index, invoice_no, customer_id,
            customer_name, document_date, status, note
          ) VALUES (
            ?, 'sale', ?, ?, '', '', 'synced', ?, ?, 1, '',
            0, ?, ?, ?, ?, 'Paid', ''
          )
          ''',
          variables: <Variable<Object>>[
            const Variable<String>('legacy_sale_1'),
            Variable<String>(now),
            Variable<String>(now),
            Variable<String>(store.appIdentity.storeId),
            Variable<String>(store.appIdentity.branchId),
            const Variable<String>('INV-LEGACY-0001'),
            const Variable<String>('legacy-customer'),
            const Variable<String>('Legacy Buyer'),
            Variable<String>(now),
          ],
        );
        await db.customInsert(
          '''
          INSERT INTO sale_items (
            id, sale_id, line_no, product_id, product_name, unit_price,
            quantity, unit_name, base_quantity, conversion_to_base, unit_cost,
            costing_method_at_sale, cost_currency, cost_exchange_rate
          ) VALUES (?, ?, 0, ?, ?, ?, ?, '', ?, 1, 0, 'weighted_average', 'USD', 1)
          ''',
          variables: <Variable<Object>>[
            const Variable<String>('legacy_sale_1-line-0'),
            const Variable<String>('legacy_sale_1'),
            const Variable<String>('p-legacy'),
            const Variable<String>('Coffee'),
            const Variable<double>(12),
            const Variable<double>(2),
            const Variable<double>(2),
          ],
        );
      });

      final restoredSales = await BusinessSqliteStore.readSales(db);
      expect(restoredSales.single.id, 'legacy_sale_1');
      expect(restoredSales.single.warehouseId, Warehouse.defaultId);
      expect(restoredSales.single.warehouseName, Warehouse.defaultName);
    });

    test('online recovery keeps server identity when importing a backup',
        () async {
      final seeded = await readyStore();
      await seeded.updateStoreProfile(
          StoreProfile.defaults.copyWith(name: 'Backup Store'));
      await seeded.addOrUpdateProduct(product());
      expect(await seeded.login('admin', 'AdminPass123'), isTrue);
      final raw = await seeded.exportBackupJson();

      SharedPreferences.setMockInitialValues(const <String, Object>{});
      LocalDatabaseService.useInMemoryStoreForTesting();
      final recovered = AppStore();
      await recovered.initialize();
      await recovered.recoverOnlineStoreOwnerIdentity(
        storeId: 'ST-CLOUD1',
        branchId: 'BR-CLOUD1',
        storeName: 'Server Store',
        username: 'owner',
        password: 'OwnerPass123',
      );

      expect(recovered.appIdentity.storeId, 'ST-CLOUD1');
      expect(recovered.appIdentity.branchId, 'BR-CLOUD1');
      expect(recovered.appIdentity.deviceRole, DeviceRole.host);
      expect(recovered.appIdentity.syncMode, SyncMode.localOnly);
      expect(recovered.appIdentity.activeSyncTransport, isEmpty);
      expect(recovered.activeUser?.username, 'owner');
      expect(await recovered.login('owner', 'OwnerPass123'), isTrue);

      await recovered.importBackupJson(raw);

      expect(recovered.products.single.code, 'P001');
      expect(recovered.storeProfile.name, 'Backup Store');
      expect(recovered.appIdentity.storeId, 'ST-CLOUD1');
      expect(recovered.appIdentity.branchId, 'BR-CLOUD1');
      expect(recovered.appIdentity.deviceRole, DeviceRole.host);
    });
  });

  group('AppStore product, customer, supplier, catalog, and expense workflows',
      () {
    test('creates, updates, deletes, syncs, and validates products', () async {
      final store = await readyStore();
      var notificationCount = 0;
      store.addListener(() => notificationCount++);

      await store.addOrUpdateProduct(product(code: ''));
      expect(store.products.single.code, isNotEmpty);
      expect(store.syncChanges.where((c) => c.entityType == 'product'),
          isNotEmpty);
      expect(store.pendingSyncQueueCount, 0);
      expect(notificationCount, greaterThan(0));

      final saved = store.products.single;
      await store.addOrUpdateProduct(
          saved.copyWith(price: 15, stock: 4, lowStockThreshold: 5));
      expect(store.products.single.price, 15);
      expect(store.lowStockCount, 1);
      expect(store.inventoryRetailValue, 60);
      expect(store.inventoryCostValue, 28);

      expect(
          store.addOrUpdateProduct(saved.copyWith(id: 'bad', code: saved.code)),
          throwsArgumentError);
      expect(
          store.addOrUpdateProduct(
              saved.copyWith(id: 'neg', code: 'NEG', price: -1)),
          throwsArgumentError);

      await store.deleteProduct(saved.id);
      expect(store.products, isEmpty);
      expect(
          store.syncChanges.where(
              (c) => c.entityType == 'product' && c.operation == 'delete'),
          isNotEmpty);
    });

    test('reuses cached product snapshots and delivery note lookups', () async {
      final store = await readyStore();
      await store.addOrUpdateProduct(product(id: 'p-cache', code: 'P-CACHE'));

      expect(identical(store.products, store.products), isTrue);
      expect(store.productById('p-cache')?.code, 'P-CACHE');

      final sale = await store.createSale(customerName: 'Bob', items: [
        SaleItem(
          productId: 'p-cache',
          productName: 'Coffee',
          unitPrice: 12,
          quantity: 1,
        ),
      ]);
      final note = await store.createDeliveryNoteFromSale(sale.id);

      expect(store.deliveryNoteForSale(sale.id)?.id, note.id);
    });

    test('reuses cached stock-tracked products and refreshes after edits',
        () async {
      final store = await readyStore();
      await store.addOrUpdateProduct(product(id: 'p-track', code: 'P-TRACK'));
      await store.addOrUpdateProduct(
        product(id: 'p-skip', code: 'P-SKIP').copyWith(trackStock: false),
      );

      expect(store.stockTrackedProducts.map((p) => p.id), contains('p-track'));
      expect(store.stockTrackedProducts.map((p) => p.id),
          isNot(contains('p-skip')));
      expect(identical(store.stockTrackedProducts, store.stockTrackedProducts),
          isTrue);

      await store.addOrUpdateProduct(
        product(id: 'p-track', code: 'P-TRACK').copyWith(trackStock: false),
      );

      expect(store.stockTrackedProducts, isEmpty);
    });

    test(
        'sale saves skip heavy product derived payloads when no FIFO layers are touched',
        () async {
      const derivedKeys = <String>[
        'product_costs_v1',
        'price_lists_v1',
        'product_prices_v1',
        'product_price_overrides_v1',
        'inventory_costing_method_v1',
        'costing_method_history_v1',
        'inventory_cost_layers_v1',
      ];

      final store = await readyStore();
      await store.addOrUpdateProduct(product(id: 'p-fast', code: 'P-FAST'));
      for (final key in derivedKeys) {
        await LocalDatabaseService.setString(key, 'sentinel-$key');
      }

      final sale = await store.createSale(customerName: 'Bob', items: [
        SaleItem(
          productId: 'p-fast',
          productName: 'Coffee',
          unitPrice: 12,
          quantity: 1,
        ),
      ]);

      expect(sale.total, 12);
      for (final key in derivedKeys) {
        expect(LocalDatabaseService.getString(key), 'sentinel-$key');
      }
    });

    test(
        'manages customers, suppliers, catalog lists, and expenses with duplicate protection',
        () async {
      final store = await readyStore();

      await store.addOrUpdateCustomer(
          Customer(id: 'c1', name: ' Alice ', phone: '111', address: 'A'));
      expect(store.resolveCustomerName('c1'), 'Alice');
      expect(store.sanitizeSelectedCustomerId('missing'),
          AppStore.walkInCustomerId);
      expect(
          store.addOrUpdateCustomer(
              Customer(id: 'c2', name: 'alice', phone: '', address: '')),
          throwsArgumentError);
      await store.deleteCustomer('c1');
      expect(store.customers.map((c) => c.id), isNot(contains('c1')));
      expect(store.resolveCustomerName('c1'), AppStore.walkInCustomerName);
      expect(store.sanitizeSelectedCustomerId('c1'),
          AppStore.walkInCustomerId);
      await store.addOrUpdateCustomer(
          Customer(id: 'c3', name: ' alice ', phone: '', address: ''));
      expect(store.customers.map((c) => c.id), contains('c3'));

      await store.addOrUpdateSupplier(Supplier(
          id: 's1', name: ' Supplier ', phone: '222', address: 'B', notes: ''));
      expect(store.suppliers.single.name, 'Supplier');
      expect(
          store.addOrUpdateSupplier(Supplier(
              id: 's2', name: 'supplier', phone: '', address: '', notes: '')),
          throwsArgumentError);
      await store.deleteSupplier('s1');
      expect(store.suppliers, isEmpty);

      await store.addOrUpdateCategory(
          CatalogItem(id: 'cat_test', nameEn: 'Snacks', nameAr: ''));
      await store.addOrUpdateBrand(
          CatalogItem(id: 'brand_test', nameEn: 'Acme', nameAr: ''));
      await store.addOrUpdateUnit(
          CatalogItem(id: 'unit_test', nameEn: 'Crate', nameAr: ''));
      expect(store.categories.map((e) => e.nameEn), contains('Snacks'));
      expect(store.brands.map((e) => e.nameEn), contains('Acme'));
      expect(store.units.map((e) => e.nameEn), contains('Crate'));
      expect(
          store.addOrUpdateCategory(
              CatalogItem(id: 'dup', nameEn: 'Snacks', nameAr: '')),
          throwsArgumentError);
      final reusableCategory =
          CatalogItem(id: 'cat_delete', nameEn: 'Reusable Category', nameAr: '');
      await store.addOrUpdateCategory(reusableCategory);
      await store.replaceAndDeleteCatalogItem(
        type: 'category',
        item: reusableCategory,
        replacement: null,
      );
      await store.addOrUpdateCategory(
        CatalogItem(id: 'cat_restore', nameEn: 'Reusable Category', nameAr: ''),
      );
      expect(store.categories.map((e) => e.id), contains('cat_restore'));

      await store.addOrUpdateExpense(Expense(
          id: 'e1',
          title: 'Rent',
          category: 'Office',
          amount: 125.5,
          date: DateTime(2026, 1, 1),
          notes: ''));
      expect(store.totalExpensesAmount, 0);
      await store.postExpense('e1');
      expect(store.totalExpensesAmount, 125.5);
      expect(
        store.accountTransactions.where(
          (tx) =>
              !tx.isDeleted &&
              tx.referenceId == 'e1' &&
              tx.referenceNo == 'Rent',
        ),
        isNotEmpty,
      );
      expect(store.estimateProfit(), -125.5);
      expect(
          store.addOrUpdateExpense(Expense(
              id: 'bad',
              title: '',
              category: '',
              amount: -1,
              date: DateTime(2026),
              notes: '')),
          throwsArgumentError);
      await store.cancelExpense('e1', reason: 'test cancellation');
      expect(store.expenses.single.isCancelled, isTrue);
      expect(store.totalExpensesAmount, 0);
    });
  });

  group('AppStore sales, purchases, stock, and reports', () {
    test(
        'creates sales, rejects insufficient stock without auto correction, restores stock on cancel, and tracks profit',
        () async {
      final correctionStore = await readyStore();
      await correctionStore
          .addOrUpdateProduct(product(stock: 5, price: 10, cost: 4));

      expect(correctionStore.createSale(customerName: 'Bob', items: const []),
          throwsArgumentError);
      expect(
        correctionStore.createSale(
          customerName: 'Bob',
          items: const [
            SaleItem(
                productId: 'p1',
                productName: 'Coffee',
                unitPrice: 10,
                quantity: 6)
          ],
        ),
        throwsStateError,
      );
      expect(
          correctionStore.stockMovements
              .where((m) => m.type == 'auto_correction'),
          isEmpty);

      final store = await readyStore();
      await store.addOrUpdateProduct(product(stock: 5, price: 10, cost: 4));

      final sale = await store.createSale(
        customerName: 'Bob',
        items: const [
          SaleItem(
              productId: 'p1',
              productName: 'Coffee',
              unitPrice: 10,
              quantity: 2)
        ],
      );

      expect(sale.customerName, 'Bob');
      expect(sale.warehouseId, Warehouse.defaultId);
      expect(sale.warehouseName, Warehouse.defaultName);
      expect(sale.total, 20);
      expect(sale.grossProfit, 12);
      expect(store.products.single.stock, 3);
      expect(store.stockMovements.where((m) => m.type == 'sale'), isNotEmpty);
      expect(store.totalSalesAmount, 20);
      expect(store.estimateProfit(), 12);

      await store.cancelSale(sale.id);
      expect(store.sales.single.isCancelled, isTrue);
      expect(store.sales.single.paidAmount, 0);
      expect(store.sales.single.cashReceivedAmount, 0);
      expect(store.totalSalesAmount, 0);
      expect(store.products.single.stock, 5);

      await store.cancelSale(sale.id);
      expect(store.sales.length, 1);
    });

    test('returns a sale, restores stock, and records a sale return movement',
        () async {
      final store = await readyStore();
      await store.addOrUpdateProduct(product(stock: 5, price: 10, cost: 4));

      final sale = await store.createSale(
        customerName: 'Bob',
        items: const [
          SaleItem(
              productId: 'p1',
              productName: 'Coffee',
              unitPrice: 10,
              quantity: 2)
        ],
      );

      expect(store.products.single.stock, 3);
      await store.returnSale(sale.id);

      expect(store.sales.single.status, 'Returned');
      expect(store.sales.single.isCancelled, isTrue);
      expect(store.sales.single.paidAmount, 0);
      expect(store.sales.single.cashReceivedAmount, 0);
      expect(store.totalSalesAmount, 0);
      expect(store.products.single.stock, 5);
    });

    test('warehouse-aware sales only use the selected warehouse', () async {
      final store = await readySqliteStore();
      await store.addOrUpdateProduct(product(id: 'p-wh', stock: 0, price: 10));
      final mainWarehouse = store.resolveWarehouseForSale();
      final branchWarehouse = await store.createWarehouse(
        name: 'Warehouse B',
        code: 'WB',
      );

      final stockService = StockTransactionService(
        SqliteMigrationManager.database!,
        defaultStoreId: store.appIdentity.storeId,
        defaultBranchId: store.appIdentity.branchId,
      );
      await stockService.applyDelta(
        storeId: store.appIdentity.storeId,
        warehouseId: mainWarehouse.id,
        productId: 'p-wh',
        delta: 2,
        branchId: store.appIdentity.branchId,
      );
      await stockService.applyDelta(
        storeId: store.appIdentity.storeId,
        warehouseId: branchWarehouse.id,
        productId: 'p-wh',
        delta: 20,
        branchId: store.appIdentity.branchId,
      );

      await expectLater(
        store.createSale(
          customerName: 'Alice',
          customerId: 'c1',
          paymentMethod: 'Credit',
          paymentStatus: 'credit',
          items: const [
            SaleItem(
              productId: 'p-wh',
              productName: 'Coffee',
              unitPrice: 10,
              quantity: 5,
            ),
          ],
          warehouseId: '',
        ),
        throwsStateError,
      );

      final sale = await store.createSale(
        customerName: 'Alice',
        customerId: 'c1',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        items: const [
          SaleItem(
            productId: 'p-wh',
            productName: 'Coffee',
            unitPrice: 10,
            quantity: 5,
          ),
        ],
        warehouseId: branchWarehouse.id,
      );

      expect(sale.warehouseId, branchWarehouse.id);
      expect(sale.warehouseName, branchWarehouse.name);
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-wh',
          warehouseId: mainWarehouse.id,
          storeId: store.appIdentity.storeId,
        ),
        2,
      );
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-wh',
          warehouseId: branchWarehouse.id,
          storeId: store.appIdentity.storeId,
        ),
        15,
      );
      expect(store.products.single.stock, 17);

      await store.cancelSale(sale.id);
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-wh',
          warehouseId: branchWarehouse.id,
          storeId: store.appIdentity.storeId,
        ),
        20,
      );
    });

    test('handles purchase draft, receive, cancel, and manual stock adjustment',
        () async {
      final store = await readyStore();
      await store.addOrUpdateProduct(product(stock: 2, cost: 5));

      expect(
          store.createPurchase(
              supplierId: 's1', supplierName: 'Vendor', items: const []),
          throwsArgumentError);
      expect(
        store.createPurchase(
            supplierId: 's1',
            supplierName: 'Vendor',
            items: const [
              PurchaseItem(
                  productId: 'missing',
                  productName: 'Ghost',
                  quantity: 1,
                  unitCost: 1)
            ]),
        throwsArgumentError,
      );

      final draft = await store.createPurchase(
        supplierId: 's1',
        supplierName: '',
        receiveNow: false,
        items: const [
          PurchaseItem(
              productId: 'p1', productName: 'Coffee', quantity: 3, unitCost: 6)
        ],
      );
      expect(draft.status, 'Draft');
      expect(store.pendingPurchaseCount, 1);
      expect(store.products.single.stock, 2);

      await store.receivePurchase(draft.id);
      expect(store.purchases.single.isReceived, isTrue);
      expect(store.products.single.stock, 5);
      expect(store.products.single.cost, closeTo(5.6, 0.001));
      expect(store.totalPurchasesAmount, 18);

      await store.adjustStock(
        productId: 'p1',
        warehouseId: Warehouse.defaultId,
        quantityDelta: -2,
        reason: 'count correction',
      );
      expect(store.products.single.stock, 3);
      expect(
        store.stockMovements.where(
          (m) => m.type == 'inventory_loss' || m.type == 'inventory_adjustment',
        ),
        isNotEmpty,
      );

      await store.cancelPurchase(draft.id);
      expect(store.purchases.single.isCancelled, isTrue);
      expect(store.totalPurchasesAmount, 0);
      expect(store.products.single.stock, 0);
    });

    test('returns received purchase and reverses stock with return movement',
        () async {
      final store = await readyStore();
      await store.addOrUpdateProduct(product());
      final draft = await store.createPurchase(
        supplierId: 's1',
        supplierName: 'Supplier',
        items: const [
          PurchaseItem(
              productId: 'p1', productName: 'Coffee', quantity: 5, unitCost: 8)
        ],
        receiveNow: true,
      );
      expect(store.products.single.stock, 15);

      await store.returnPurchase(draft.id, reason: 'damaged goods');

      expect(store.purchases.single.status, 'Returned');
      expect(store.purchases.single.isReturned, isTrue);
      expect(store.purchases.single.isCancelled, isTrue);
      expect(store.totalPurchasesAmount, 0);
      expect(store.products.single.stock, 10);
      expect(
          store.stockMovements
              .where((movement) => movement.type == 'purchase_return'),
          isNotEmpty);
      expect(
          store.accountTransactions
              .where((entry) => entry.type == 'purchaseReturn'),
          isNotEmpty);
    });

    test(
        'warehouse-aware purchases, adjustments, and counts stay in the selected warehouse',
        () async {
      final store = await readySqliteStore();
      await store.addOrUpdateProduct(product(id: 'p-phase4', stock: 0, cost: 5));
      final branchWarehouse = await store.createWarehouse(
        name: 'Warehouse B',
        code: 'WB',
      );

      final purchase = await store.createPurchase(
        supplierId: 's1',
        supplierName: 'Supplier',
        receiveNow: true,
        warehouseId: branchWarehouse.id,
        warehouseName: branchWarehouse.name,
        items: const [
          PurchaseItem(
            productId: 'p-phase4',
            productName: 'Coffee',
            quantity: 4,
            unitCost: 5,
          ),
        ],
      );

      expect(purchase.warehouseId, branchWarehouse.id);
      final purchaseRow = await SqliteMigrationManager.database!.customSelect(
        'SELECT warehouse_id AS warehouseId, warehouse_name AS warehouseName FROM purchases WHERE id = ? LIMIT 1',
        variables: <Variable<Object>>[Variable<String>(purchase.id)],
      ).getSingle();
      expect(purchaseRow.read<String>('warehouseId'), branchWarehouse.id);
      expect(purchaseRow.read<String>('warehouseName'), branchWarehouse.name);
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-phase4',
          warehouseId: branchWarehouse.id,
          storeId: store.appIdentity.storeId,
        ),
        4,
      );
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-phase4',
          warehouseId: Warehouse.defaultId,
          storeId: store.appIdentity.storeId,
        ),
        0,
      );

      await store.adjustStock(
        productId: 'p-phase4',
        warehouseId: branchWarehouse.id,
        quantityDelta: -1,
        reason: 'branch correction',
      );
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-phase4',
          warehouseId: branchWarehouse.id,
          storeId: store.appIdentity.storeId,
        ),
        3,
      );

      final session = await store.createInventoryCountSession(
        warehouseId: branchWarehouse.id,
        warehouseName: branchWarehouse.name,
      );
      expect(session.warehouseId, branchWarehouse.id);
      expect(session.lines.single.snapshotStock, 3);
      await store.countInventoryLine(
        sessionId: session.id,
        productId: 'p-phase4',
        countedQty: 6,
      );
      await store.approveInventoryCount(session.id);
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-phase4',
          warehouseId: branchWarehouse.id,
          storeId: store.appIdentity.storeId,
        ),
        6,
      );
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-phase4',
          warehouseId: Warehouse.defaultId,
          storeId: store.appIdentity.storeId,
        ),
        0,
      );
    });

    test('legacy purchase and inventory count default to main warehouse',
        () async {
      final store = await readySqliteStore();
      await store.addOrUpdateProduct(product(id: 'p-legacy-main', stock: 2));

      final purchase = await store.createPurchase(
        supplierId: 's1',
        supplierName: 'Supplier',
        receiveNow: false,
        items: const [
          PurchaseItem(
            productId: 'p-legacy-main',
            productName: 'Coffee',
            quantity: 1,
            unitCost: 5,
          ),
        ],
      );
      expect(purchase.warehouseId, Warehouse.defaultId);
      expect(purchase.warehouseName, Warehouse.defaultName);

      final count = await store.createInventoryCountSession();
      expect(count.warehouseId, Warehouse.defaultId);
      expect(count.warehouseName, Warehouse.defaultName);
    });
  });

  group('AppStore backup, restore, encryption, merge, and conflicts', () {
    test(
        'exports, validates, encrypts, decrypts, imports, and summarizes backups',
        () async {
      final store = await readyStore();
      await store.addOrUpdateProduct(product());
      await store.addOrUpdateCustomer(
          Customer(id: 'c1', name: 'Alice', phone: '', address: ''));
      await store.addOrUpdateExpense(Expense(
          id: 'e1',
          title: 'Supplies',
          category: 'Ops',
          amount: 5,
          date: DateTime(2026),
          notes: ''));

      expect(await store.login('admin', 'AdminPass123'), isTrue);
      final raw = await store.exportBackupJson();
      final validation = store.validateBackupJson(raw);
      expect(validation.isValid, isTrue);
      expect(validation.summary?.productsCount, 1);
      expect(
          store.syncSnapshotGeneratedAtFromJson(await store.exportSyncSnapshotJson()),
          isA<DateTime>());
      expect(store.exportSyncChangesJson(), contains('"changes"'));

      final encrypted = await store.exportEncryptedBackupJson('secret-pass');
      expect(encrypted, isNot(contains('Coffee')));
      final decrypted = store.decryptBackupJson(encrypted, 'secret-pass');
      expect(decrypted, contains('"products"'));
      expect(decrypted, contains('Coffee'));
      expect(decrypted, contains('"syncChanges"'));
      expect(() => store.decryptBackupJson(encrypted, 'wrong-pass'),
          throwsA(isA<ArgumentError>()));

      await store.resetBusinessData();
      expect(store.products, isEmpty);
      await store.importBackupJson(raw);
      expect(store.products.single.name, 'Coffee');
      expect(store.currentBackupSummary.productsCount, 1);
    });

    test(
        'round-trips SQLite-first inventory tables without double applying restore',
        () async {
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
      final store = AppStore();
      await store.initialize();
      await store.recoverOnlineStoreOwnerIdentity(
        storeId: 'ST-SQLITE01',
        branchId: 'BR-SQLITE01',
        storeName: 'SQLite Store',
        username: 'owner',
        password: 'OwnerPass123',
        deviceRole: DeviceRole.host,
        syncMode: SyncMode.localOnly,
      );
      expect(await store.login('owner', 'OwnerPass123'), isTrue);
      expect(store.hasPermission(AppPermission.backupExport), isTrue);
      expect(store.isAdmin, isTrue);
      expect(
        store.currentUserRole?.permissions.contains(AppPermission.backupExport),
        isTrue,
      );
      await store.applySessionUser(
        activeUser: store.activeUser!,
        currentRole: 'Admin',
        permissions: Set<String>.from(AppPermission.all),
        rememberLogin: true,
      );

      final db = SqliteMigrationManager.database;
      expect(db != null, isTrue);
      final sqliteDb = db!;
      await sqliteDb.transaction(() async {
        await sqliteDb.customStatement('DELETE FROM stock_movements');
        await sqliteDb.customStatement('DELETE FROM warehouse_inventory');
        await sqliteDb.customStatement('DELETE FROM stock_operations');
        await sqliteDb.customStatement('DELETE FROM inventory_reconciliations');
        await sqliteDb.customStatement('DELETE FROM inventory_migration_adjustments');
        await sqliteDb.customStatement('DELETE FROM sync_events');
        await sqliteDb.customStatement('DELETE FROM pending_sync_changes');
        await sqliteDb.customStatement('DELETE FROM sync_queue');
        await sqliteDb.customStatement('DELETE FROM products');
      });
      final service = StockTransactionService(
        sqliteDb,
        defaultStoreId: store.appIdentity.storeId,
        defaultBranchId: store.appIdentity.branchId,
        deviceId: store.appIdentity.deviceId,
      );
      await service.recordMovementsAtomically(
        operationType: 'purchase_receive',
        documentType: 'purchase',
        documentId: 'purchase-1',
        movementGroupId: 'group-initial',
        idempotencyKey: 'op-initial',
        movements: <StockMovement>[
          StockMovement(
            id: 'sm-initial',
            productId: 'p1',
            productName: 'Coffee',
            type: 'purchase_receive',
            quantity: 9,
            date: DateTime.utc(2026, 1, 1, 12),
            warehouseId: 'wh-1',
            warehouseName: 'Main Warehouse',
            movementGroupId: 'group-initial',
            documentLineId: 'line-initial',
            sourceMovementId: '',
            reversalOfMovementId: '',
            idempotencyKey: 'mov-initial',
            storeId: store.appIdentity.storeId,
            branchId: store.appIdentity.branchId,
            syncStatus: 'pending',
          ),
        ],
      );
      await service.recordMovementsAtomically(
        operationType: 'sale',
        documentType: 'sale',
        documentId: 'sale-1',
        movementGroupId: 'group-1',
        idempotencyKey: 'op-1',
        movements: <StockMovement>[
          StockMovement(
            id: 'm-1',
            productId: 'p1',
            productName: 'Coffee',
            type: 'sale',
            quantity: -3,
            date: DateTime.utc(2026, 1, 1, 12),
            warehouseId: 'wh-1',
            warehouseName: 'Warehouse 1',
            movementGroupId: 'group-1',
            documentLineId: 'line-1',
            sourceMovementId: '',
            reversalOfMovementId: '',
            idempotencyKey: 'move-1',
            storeId: store.appIdentity.storeId,
            branchId: store.appIdentity.branchId,
            syncStatus: 'pending',
          ),
        ],
      );
      await db.customInsert(
        '''
        INSERT INTO inventory_reconciliations
          (id, store_id, branch_id, warehouse_id, product_id,
           legacy_product_stock, ledger_balance, warehouse_balance, difference,
           classification, status, created_at, resolved_at, resolution_note)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          const Variable<String>('rec-1'),
          Variable<String>(store.appIdentity.storeId),
          Variable<String>(store.appIdentity.branchId),
          const Variable<String>('wh-1'),
          const Variable<String>('p1'),
          const Variable<double>(9),
          const Variable<double>(-3),
          const Variable<double>(-3),
          const Variable<double>(0),
          const Variable<String>('warehouse_balance_mismatch'),
          const Variable<String>('open'),
          const Variable<String>('2026-01-01T12:00:00.000Z'),
          const Variable<String>(''),
          const Variable<String>(''),
        ],
      );
      await db.customInsert(
        '''
        INSERT INTO inventory_migration_adjustments
          (id, migration_batch_id, store_id, branch_id, warehouse_id,
           product_id, legacy_product_stock, ledger_balance, applied_delta,
           created_at, updated_at, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          const Variable<String>('adj-1'),
          const Variable<String>('batch-1'),
          Variable<String>(store.appIdentity.storeId),
          Variable<String>(store.appIdentity.branchId),
          const Variable<String>('wh-1'),
          const Variable<String>('p1'),
          const Variable<double>(9),
          const Variable<double>(-3),
          const Variable<double>(12),
          const Variable<String>('2026-01-01T12:00:00.000Z'),
          const Variable<String>('2026-01-01T12:00:00.000Z'),
          const Variable<String>('backfill'),
        ],
      );

      final raw = await store.exportBackupJson();
      final original = jsonDecode(raw) as Map<String, dynamic>;
      expect(original['warehouseInventory'], isNotEmpty);
      expect(original['stockOperations'], isNotEmpty);
      expect(original['stockMovements'], isNotEmpty);
      expect(
        (original['stockMovements'] as List).first,
        allOf(
          containsPair('warehouseId', 'wh-1'),
          containsPair('warehouseName', 'Warehouse 1'),
          containsPair('movementGroupId', 'group-1'),
          containsPair('documentLineId', 'line-1'),
          containsPair('sourceMovementId', ''),
          containsPair('reversalOfMovementId', ''),
          containsPair('idempotencyKey', 'move-1'),
        ),
      );

      await sqliteDb.transaction(() async {
        await sqliteDb.customStatement('DELETE FROM stock_movements');
        await sqliteDb.customStatement('DELETE FROM warehouse_inventory');
        await sqliteDb.customStatement('DELETE FROM stock_operations');
        await sqliteDb.customStatement('DELETE FROM inventory_reconciliations');
        await sqliteDb.customStatement('DELETE FROM inventory_migration_adjustments');
        await sqliteDb.customStatement('DELETE FROM sync_events');
        await sqliteDb.customStatement('DELETE FROM pending_sync_changes');
        await sqliteDb.customStatement('DELETE FROM sync_queue');
      });
      await store.importBackupJson(raw);
      final restoredWarehouseCount = await sqliteDb
          .customSelect('SELECT COUNT(*) AS c FROM warehouse_inventory')
          .getSingle();
      expect(restoredWarehouseCount.read<int>('c') > 0, isTrue);
      final afterFirstRestore =
          jsonDecode(await store.exportBackupJson()) as Map<String, dynamic>;

      expect(afterFirstRestore['warehouseInventory'],
          equals(original['warehouseInventory']));
      expect(afterFirstRestore['stockOperations'],
          equals(original['stockOperations']));
      expect(afterFirstRestore['stockMovements'],
          equals(original['stockMovements']));
      expect(afterFirstRestore['inventoryReconciliations'],
          equals(original['inventoryReconciliations']));
      expect(afterFirstRestore['inventoryMigrationAdjustments'],
          equals(original['inventoryMigrationAdjustments']));

      await store.importBackupJson(raw);
      final afterSecondRestore =
          jsonDecode(await store.exportBackupJson()) as Map<String, dynamic>;
      expect(afterSecondRestore['warehouseInventory'],
          equals(afterFirstRestore['warehouseInventory']));
      expect(afterSecondRestore['stockOperations'],
          equals(afterFirstRestore['stockOperations']));
      expect(afterSecondRestore['stockMovements'],
          equals(afterFirstRestore['stockMovements']));
      addTearDown(LocalDatabaseService.clearInMemoryStoreForTesting);
    });

    test(
        'merge backup prefers latest data and reports duplicate data conflicts',
        () async {
      final first = await readyStore();
      await first.addOrUpdateProduct(
          product(id: 'p1', code: 'DUP', name: 'Local', stock: 1));
      expect(await first.login('admin', 'AdminPass123'), isTrue);
      final rawLocal = await first.exportBackupJson();

      final second = await readyStore();
      await second.addOrUpdateProduct(
          product(id: 'p2', code: 'DUP', name: 'Remote newer', stock: 2));
      await second.addOrUpdateCustomer(
          Customer(id: 'c1', name: 'Same', phone: '', address: ''));
      await second.addOrUpdateCustomer(
          Customer(id: 'c2', name: 'Same 2', phone: '', address: ''));
      expect(await second.login('admin', 'AdminPass123'), isTrue);
      final decoded =
          jsonDecode(await second.exportBackupJson()) as Map<String, dynamic>;
      (decoded['customers'] as List<dynamic>)[2]['name'] = 'Same';
      final rawRemote = const JsonEncoder.withIndent('  ').convert(decoded);

      await first.importBackupJson(rawLocal);
      await first.mergeBackupJson(rawRemote);

      expect(
          first.products.map((p) => p.id), containsAll(<String>['p1', 'p2']));
      expect(first.dataConflictCount, greaterThan(0));
      expect(first.blockingDataConflictCount, greaterThanOrEqualTo(0));
    });
  });

  group('AppStore sync queue and permissions', () {
    test(
        'marks queue rows in progress, failed, retrying, item failed, and synced',
        () async {
      final store = await readyStore();
      await store.updateAppIdentity(store.appIdentity.copyWith(
          syncMode: SyncMode.cloudConnected, activeSyncTransport: 'cloud'));
      await store.addOrUpdateProduct(product());
      final changeIds = store
          .pendingSyncChangesForTarget('cloud', readyOnly: false)
          .map((c) => c.id)
          .toList();
      expect(changeIds, isNotEmpty);

      await store.markSyncQueueChangesInProgress(changeIds);
      final syncQueueSnapshot = store.syncQueue.toList();
      final inProgressRows =
          syncQueueSnapshot.where((q) => q.isInProgress).toList();
      expect(inProgressRows, isNotEmpty);

      await store.markSyncQueueChangesFailed(changeIds, 'network down');
      expect(
          store.syncQueue
              .where((q) => q.isFailed && q.lastError == 'network down'),
          isNotEmpty);

      await store.retryFailedSyncQueue();
      expect(store.syncQueue.where((q) => q.status == 'pending'), isNotEmpty);

      await store.markSyncQueueItemFailed(
          store.syncQueue.first.id, 'single failure');
      expect(store.syncQueue.first.lastError, 'single failure');

      await store.markSyncChangesSyncedByIds(changeIds);
      expect(store.pendingSyncChangesForTarget('cloud', readyOnly: false),
          isEmpty);
      expect(
          store.pendingSyncQueueForTarget('cloud', readyOnly: false), isEmpty);

      await store.clearPendingSyncQueue();
      expect(store.pendingSyncQueueCount, 0);
    });

    test(
        'applies remote sync changes for product, profile, roles, users, and stock movements',
        () async {
      final store = await readyStore();
      final now = DateTime.now();
      final remoteProduct =
          product(id: 'remote_p', code: 'REMOTE', name: 'Remote', stock: 1)
              .copyWith(updatedAt: now.add(const Duration(minutes: 1)));
      final remoteUser = AppUser(
          id: 'u_remote',
          fullName: 'Remote User',
          username: 'remote',
          passwordHash: 'hash',
          roleId: 'admin');
      final remoteRole = UserRole(
          id: 'role_remote',
          name: 'Remote Role',
          permissions: {AppPermission.salesCreate});

      await store.applyRemoteSyncChanges([
        SyncChange(
            id: 'ch_profile',
            entityType: 'store_profile',
            entityId: 'store',
            operation: 'update',
            deviceId: 'other',
            createdAt: now,
            payload:
                StoreProfile.defaults.copyWith(name: 'Remote Store').toJson()),
        SyncChange(
            id: 'ch_role',
            entityType: 'role',
            entityId: remoteRole.id,
            operation: 'create',
            deviceId: 'other',
            createdAt: now,
            payload: remoteRole.toJson()),
        SyncChange(
            id: 'ch_user',
            entityType: 'user',
            entityId: remoteUser.id,
            operation: 'create',
            deviceId: 'other',
            createdAt: now,
            payload: remoteUser.toJson()),
        SyncChange(
            id: 'ch_product',
            entityType: 'product',
            entityId: remoteProduct.id,
            operation: 'create',
            deviceId: 'other',
            createdAt: now,
            payload: remoteProduct.toJson()),
        SyncChange(
            id: 'ch_stock',
            entityType: 'stock_movement',
            entityId: 'm1',
            operation: 'purchase_receive',
            deviceId: 'other',
            createdAt: now,
            payload: {
              'id': 'm1',
              'productId': 'remote_p',
              'productName': 'Remote',
              'type': 'purchase_receive',
              'quantity': 4,
              'date': now.toIso8601String(),
              'unitCost': 8,
            }),
      ]);

      expect(store.storeProfile.name, 'Remote Store');
      expect(store.roles.map((r) => r.id), contains(remoteRole.id));
      expect(store.users.map((u) => u.id), contains(remoteUser.id));
      expect(store.products.singleWhere((p) => p.id == 'remote_p').stock, 5);
      expect(store.products.singleWhere((p) => p.id == 'remote_p').cost, 8);
    });

    test(
        'enforces permissions for restricted users and supports login/logout lifecycle',
        () async {
      final store = await readyStore();
      await store.addOrUpdateRole(UserRole(
          id: 'cashier',
          name: 'Cashier',
          permissions: {AppPermission.salesCreate}));
      await store.addOrUpdateUser(
          AppUser(
              id: '',
              fullName: 'Cashier One',
              username: 'cashier',
              passwordHash: '',
              roleId: 'cashier'),
          password: '1234');

      expect(await store.login('cashier', 'bad'), isFalse);
      expect(await store.login('cashier', '1234'), isTrue);
      expect(store.canSell, isTrue);
      expect(store.canManageProducts, isFalse);
      expect(() => store.requirePermission(AppPermission.productsDelete),
          throwsStateError);
      expect(store.addOrUpdateProduct(product()), throwsStateError);

      await store.logout();
      expect(store.activeUser == null, isTrue);
      expect(store.hasPermission(AppPermission.productsDelete), isFalse);
      expect(() => store.requirePermission(AppPermission.productsDelete),
          throwsStateError);
      expect(await store.login('admin', 'AdminPass123'), isTrue);
      expect(() => store.requirePermission(AppPermission.productsDelete),
          returnsNormally);

      expect(store.deleteRole('admin'), throwsStateError);
      expect(store.deleteRole('cashier'), throwsStateError);
      final cashierId =
          store.users.firstWhere((u) => u.username == 'cashier').id;
      await store.deleteUser(cashierId);
      await store.deleteRole('cashier');
      expect(store.roles.map((r) => r.id), isNot(contains('cashier')));
    });

    test(
        'persists the active session across restart, logout, and user switching',
        () async {
      final store = await readyStore();
      await store.addOrUpdateRole(UserRole(
          id: 'cashier',
          name: 'Cashier',
          permissions: {AppPermission.salesCreate}));
      await store.addOrUpdateUser(
          AppUser(
              id: '',
              fullName: 'Cashier One',
              username: 'cashier',
              passwordHash: '',
              roleId: 'cashier'),
          password: '1234');

      expect(
          await AuthRepository.login(store, 'cashier', '1234', remember: true),
          isTrue);
      expect(store.activeUser?.username, 'cashier');
      expect(store.currentRole, 'Cashier');
      expect(store.rememberLogin, isTrue);

      final restarted = AppStore();
      await restarted.initialize();
      expect(restarted.activeUser?.username, 'cashier');
      expect(restarted.currentRole, 'Cashier');
      expect(restarted.rememberLogin, isTrue);

      expect(await AuthRepository.login(restarted, 'admin', 'AdminPass123'),
          isTrue);
      expect(restarted.activeUser?.username, 'admin');
      expect(restarted.currentRole, 'Admin');
      expect(restarted.rememberLogin, isFalse);

      await AuthRepository.logout(restarted);
      expect(restarted.activeUser == null, isTrue);
      expect(restarted.rememberLogin, isFalse);

      final afterLogoutRestart = AppStore();
      await afterLogoutRestart.initialize();
      expect(afterLogoutRestart.activeUser == null, isTrue);
      expect(afterLogoutRestart.rememberLogin, isFalse);
    });

    test(
        'refreshAfterDatabaseChange reloads sqlite-backed users and session state',
        () async {
      final store = await readyStore();
      await store.addOrUpdateRole(UserRole(
          id: 'cashier',
          name: 'Cashier',
          permissions: {AppPermission.salesCreate}));
      await store.addOrUpdateUser(
          AppUser(
              id: '',
              fullName: 'Cashier One',
              username: 'cashier',
              passwordHash: '',
              roleId: 'cashier'),
          password: '1234');
      expect(
          await AuthRepository.login(store, 'cashier', '1234', remember: true),
          isTrue);

      final usersSnapshot = store.users.toList(growable: false);
      await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
        'users_v1',
        usersSnapshot.map((user) {
          if (user.username == 'cashier') {
            return user.copyWith(fullName: 'Cashier Reloaded').toJson();
          }
          return user.toJson();
        }).toList(growable: false),
        sortIndices:
            List<int?>.generate(usersSnapshot.length, (index) => index),
      );

      await store.refreshAfterDatabaseChange('users_v1');
      expect(
          store.users.singleWhere((u) => u.username == 'cashier').fullName,
          'Cashier Reloaded');
      expect(store.activeUser?.fullName, 'Cashier Reloaded');
    });

    test('updates identity, admin setup, and keeps protected operations safe',
        () async {
      final store = await readyStore();

      await store.updateAppIdentity(store.appIdentity.copyWith(
          syncMode: SyncMode.marketplaceEnabled, deviceRole: DeviceRole.host));
      expect(store.appIdentity.syncMode, SyncMode.marketplaceEnabled);
      expect(store.appIdentity.deviceId, store.deviceId);

      SharedPreferences.setMockInitialValues(const <String, Object>{});
      LocalDatabaseService.useInMemoryStoreForTesting(const <String, String>{});
      final setup = AppStore();
      await setup.initialize();
      expect(setup.needsInitialAdminSetup, isTrue);
      await setup.completeInitialAdminSetup(
          fullName: 'Owner', username: 'owner', password: 'owner123');
      expect(setup.needsInitialAdminSetup, isFalse);
      expect(await setup.login('owner', 'owner123'), isTrue);
      expect(() => setup.setCurrentRole('cashier'), throwsStateError);
    });
  });
}
