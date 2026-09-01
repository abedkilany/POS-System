import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/repositories/auth_repository.dart';
import 'package:ventio/core/localization/localized_domain_exception.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/core/services/cash_reversal_service.dart';
import 'package:ventio/core/services/payment_voucher_service.dart';
import 'package:ventio/core/services/stock_transaction_service.dart';
import 'package:ventio/core/services/direct_sync_settings.dart';
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
import 'package:ventio/models/product_costing.dart';
import 'package:ventio/models/inventory_batch.dart';
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
      usdCost: cost,
      originalCost: cost,
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
      'controlPlaneTenantId': '',
      'deviceToken': 'device_test_host',
      'storeEpoch': 1,
      'recoveryKey': 'RK-TEST-TEST-TEST',
    }),
  };
}

Future<AppStore> readyStore([Map<String, String>? seed]) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  await _shutdownActiveSqliteStoreForTesting();
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

AppStore? _activeSqliteStoreForTesting;

Future<void> _shutdownActiveSqliteStoreForTesting() async {
  final previous = _activeSqliteStoreForTesting;
  if (previous == null) return;
  _activeSqliteStoreForTesting = null;
  await previous.prepareForShutdown();
  previous.dispose();
  // prepareForShutdown() drains Ventio-owned buffered writes. Flush the
  // database facade as a final deterministic boundary before reset closes the
  // Drift isolate used by the previous test.
  await LocalDatabaseService.flushPendingWrites();
  await Future<void>.delayed(Duration.zero);
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
  await _shutdownActiveSqliteStoreForTesting();
  await LocalDatabaseService.resetForTesting();
  await SqliteMigrationManager.initializeFreshSqlite();
  await LocalDatabaseService.useSqliteDatabaseForTesting(
    SqliteMigrationManager.database!,
  );
  await LocalDatabaseService.initialize();
  final sqliteDb = SqliteMigrationManager.database;
  expect(sqliteDb != null, isTrue);
  await sqliteDb!.transaction(() async {
    await sqliteDb.customStatement('DELETE FROM sale_item_batch_allocations');
    await sqliteDb.customStatement('DELETE FROM purchase_item_batch_allocations');
    await sqliteDb.customStatement('DELETE FROM inventory_batch_balances');
    await sqliteDb.customStatement('DELETE FROM inventory_batches');
    await sqliteDb.customStatement('DELETE FROM unified_batch_cutovers');
    await sqliteDb.customStatement('DELETE FROM sale_items');
    await sqliteDb
        .customStatement('DELETE FROM sale_item_cost_layer_consumptions');
    await sqliteDb.customStatement('DELETE FROM sales');
    await sqliteDb.customStatement('DELETE FROM purchase_items');
    await sqliteDb.customStatement('DELETE FROM purchases');
    await sqliteDb.customStatement('DELETE FROM stock_movements');
    await sqliteDb.customStatement('DELETE FROM warehouse_inventory');
    await sqliteDb.customStatement('DELETE FROM stock_operations');
    await sqliteDb.customStatement('DELETE FROM inventory_reconciliations');
    await sqliteDb
        .customStatement('DELETE FROM inventory_migration_adjustments');
    await sqliteDb.customStatement('DELETE FROM inventory_count_lines');
    await sqliteDb.customStatement('DELETE FROM inventory_counts');
    await sqliteDb.customStatement('DELETE FROM sync_events');
    await sqliteDb.customStatement('DELETE FROM pending_sync_changes');
    await sqliteDb.customStatement('DELETE FROM sync_queue');
    await sqliteDb.customStatement(
        "UPDATE products SET deleted_at = '2026-01-01T00:00:00.000Z' WHERE deleted_at = ''");
    await sqliteDb.customStatement(
        "UPDATE product_costs SET deleted_at = '2026-01-01T00:00:00.000Z' WHERE deleted_at = ''");
    await sqliteDb.customStatement(
        "UPDATE inventory_cost_layers SET deleted_at = '2026-01-01T00:00:00.000Z' WHERE deleted_at = ''");
    // Costing method/history are process-persistent in the shared Flutter-test
    // SQLite file. Clear them between workflow tests so a FIFO scenario cannot
    // inherit a prior test's weighted-average/FIFO transition boundary.
    await sqliteDb.customStatement('DELETE FROM costing_method_history');
    await sqliteDb.customStatement('DELETE FROM warehouses');
  });
  // Clear through LocalDatabaseService as well as SQLite so its hydrated scalar
  // mirror cannot retain the prior test's costing method after the DB cleanup.
  await LocalDatabaseService.deleteString('inventory_costing_method_v1');
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
  await store.ensureHeavyDataLoaded(failOnError: true);
  _activeSqliteStoreForTesting = store;
  return store;
}

Future<String> seedOpenCashDrawerForStore(AppStore store) async {
  final db = SqliteMigrationManager.database!;
  final accounts = await AccountingService.readDefaultAccountMap();
  final cashAccount = accounts['default_cash_account_id']?.trim() ?? '';
  expect(cashAccount, isNotEmpty);
  final now = DateTime(2026, 8, 19, 12).toUtc().toIso8601String();
  final drawerId = 'drawer-${store.appIdentity.storeId.toLowerCase()}';
  final sessionId = 'shift-${store.appIdentity.storeId.toLowerCase()}';
  final drawerCode = 'P6-${store.appIdentity.storeId.toUpperCase()}';
  await db.customInsert(
    '''
    INSERT INTO cash_locations
      (id, code, name, type, account_id, current_balance, allow_negative,
       is_active, created_at, updated_at, store_id, branch_id, device_id)
    VALUES (?, ?, 'Phase 6 Cancel Drawer',
            'cash_drawer', ?, 1000, 0, 1, ?, ?, ?, ?, ?)
    ''',
    variables: <Variable<Object>>[
      Variable<String>(drawerId),
      Variable<String>(drawerCode),
      Variable<String>(cashAccount),
      Variable<String>(now),
      Variable<String>(now),
      Variable<String>(store.appIdentity.storeId),
      Variable<String>(store.appIdentity.branchId),
      Variable<String>(store.deviceId),
    ],
  );
  await db.customInsert(
    '''
    INSERT INTO cash_drawer_sessions
      (id, drawer_no, cash_location_id, opened_at, status, opening_balance,
       expected_cash, opened_by, store_id, branch_id, updated_at)
    VALUES (?, ?, ?, ?,
            'open', 1000, 1000, 'tester', ?, ?, ?)
    ''',
    variables: <Variable<Object>>[
      Variable<String>(sessionId),
      Variable<String>(drawerCode),
      Variable<String>(drawerId),
      Variable<String>(now),
      Variable<String>(store.appIdentity.storeId),
      Variable<String>(store.appIdentity.branchId),
      Variable<String>(now),
    ],
  );
  return drawerId;
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
  tearDownAll(() async {
    await _shutdownActiveSqliteStoreForTesting();
    await LocalDatabaseService.resetForTesting();
  });

  group('AppStore initialization and persisted state', () {
    tearDown(LocalDatabaseService.clearInMemoryStoreForTesting);
    test(
        'initializes defaults, identity, walk-in customer, admin user, and catalog defaults',
        () async {
      final store = await readySqliteStore(storeId: 'ST-EXPENSE-WORKFLOW');

      expect(store.isReady, isTrue);
      expect(store.products, isEmpty);
      expect(store.walkInCustomer.name, AppStore.walkInCustomerName);
      expect(store.customers.map((c) => c.id),
          contains(AppStore.walkInCustomerId));
      expect(store.roles.map((r) => r.id), contains('admin'));
      expect(store.users.map((u) => u.username), contains('owner'));
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
                productId: 'p1',
                productName: 'Coffee',
                unitPrice: 12,
                quantity: 2)
          ],
          paymentMethod: 'Credit');
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
        storeId: 'ST-DIRECT1',
        branchId: 'BR-DIRECT1',
        storeName: 'Server Store',
        username: 'owner',
        password: 'OwnerPass123',
      );

      expect(recovered.appIdentity.storeId, 'ST-DIRECT1');
      expect(recovered.appIdentity.branchId, 'BR-DIRECT1');
      expect(recovered.appIdentity.deviceRole, DeviceRole.host);
      expect(recovered.appIdentity.syncMode, SyncMode.localOnly);
      expect(recovered.appIdentity.activeSyncTransport, isEmpty);
      expect(recovered.activeUser?.username, 'owner');
      expect(await recovered.login('owner', 'OwnerPass123'), isTrue);

      await recovered.importBackupJson(raw);

      expect(recovered.products.single.code, 'P001');
      expect(recovered.storeProfile.name, 'Backup Store');
      expect(recovered.appIdentity.storeId, 'ST-DIRECT1');
      expect(recovered.appIdentity.branchId, 'BR-DIRECT1');
      expect(recovered.appIdentity.deviceRole, DeviceRole.host);
    });

    test('registration provisions owner without activating a session',
        () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      LocalDatabaseService.useInMemoryStoreForTesting();
      final store = AppStore();
      await store.initialize();

      await store.recoverOnlineStoreOwnerIdentity(
        storeId: 'ST-REG001',
        branchId: 'BR-REG001',
        storeName: 'Registered Store',
        username: 'owner',
        password: 'OwnerPass123',
        activateUser: false,
      );

      expect(store.hasLocalAdminUser, isTrue);
      expect(store.activeUser, null);
      expect(await store.login('owner', 'OwnerPass123'), isTrue);
    });
  });

  group('AppStore product, customer, supplier, catalog, and expense workflows',
      () {
    test('creates, updates, deletes, syncs, and validates products', () async {
      final store = await readySqliteStore(storeId: 'ST-EXPENSE-WORKFLOW');
      var notificationCount = 0;
      store.addListener(() => notificationCount++);

      await store.addOrUpdateProduct(product(code: '', stock: 0));
      expect(store.products.single.code, isNotEmpty);
      expect(store.syncChanges.where((c) => c.entityType == 'product'),
          isNotEmpty);
      expect(store.pendingSyncQueueCount, 0);
      expect(notificationCount, greaterThan(0));

      final saved = store.products.single;
      await store.addOrUpdateProduct(
          saved.copyWith(price: 15, lowStockThreshold: 5));
      await store.adjustStock(
        productId: saved.id,
        warehouseId: Warehouse.defaultId,
        quantityDelta: 4,
        reason: 'workflow stock seed',
      );
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

      await expectLater(store.deleteProduct(saved.id), throwsStateError);
      await store.addOrUpdateProduct(
        product(id: 'delete-me', code: 'DELETE-ME', stock: 0),
      );
      await store.deleteProduct('delete-me');
      expect(store.products.map((item) => item.id), isNot(contains('delete-me')));
      expect(
          store.syncChanges.where(
              (c) => c.entityType == 'product' && c.operation == 'delete'),
          isNotEmpty);
    });

    test('reuses cached product snapshots and delivery note lookups', () async {
      final store = await readySqliteStore(storeId: 'ST-CACHE01');
      await store.addOrUpdateProduct(
          product(id: 'p-cache', code: 'P-CACHE', stock: 0));
      await store.adjustStock(
          productId: 'p-cache',
          warehouseId: Warehouse.defaultId,
          quantityDelta: 10,
          reason: 'test seed');

      expect(identical(store.products, store.products), isTrue);
      expect(store.productById('p-cache')?.code, 'P-CACHE');

      final sale = await store.createSale(
          customerId: 'customer-bob-cache',
          customerName: 'Bob',
          paymentMethod: 'Credit',
          paymentStatus: 'credit',
          items: [
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

    test('sale saves through typed SQLite without legacy derived payloads',
        () async {
      final store = await readySqliteStore(storeId: 'ST-FAST001');
      await store
          .addOrUpdateProduct(product(id: 'p-fast', code: 'P-FAST', stock: 0));
      await store.adjustStock(
          productId: 'p-fast',
          warehouseId: Warehouse.defaultId,
          quantityDelta: 10,
          reason: 'test seed');
      final sale = await store.createSale(
          customerId: 'customer-bob-fast',
          customerName: 'Bob',
          paymentMethod: 'Credit',
          paymentStatus: 'credit',
          items: [
            SaleItem(
              productId: 'p-fast',
              productName: 'Coffee',
              unitPrice: 12,
              quantity: 1,
            ),
          ]);

      expect(sale.total, 12);
      final persisted = await SqliteMigrationManager.database!.customSelect(
        "SELECT COUNT(*) AS c FROM sales WHERE id = ? AND deleted_at = ''",
        variables: <Variable<Object>>[Variable<String>(sale.id)],
      ).getSingle();
      expect(persisted.read<int>('c'), 1);
    });

    test(
        'manages customers, suppliers, catalog lists, and expenses with duplicate protection',
        () async {
      final store = await readySqliteStore(storeId: 'ST-EXPENSE-WORKFLOW');

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
      expect(store.sanitizeSelectedCustomerId('c1'), AppStore.walkInCustomerId);
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
      final reusableCategory = CatalogItem(
          id: 'cat_delete', nameEn: 'Reusable Category', nameAr: '');
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
      await store.postExpense('e1', paidInCash: false);
      expect(store.totalExpensesAmount, 125.5);
      final expenseJournal = await SqliteMigrationManager.database!
          .customSelect(
            "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'expense' AND reference_id = 'e1' AND status = 'posted'",
          )
          .getSingle();
      expect(expenseJournal.read<int>('c'), 1);
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
      final correctionStore = await readySqliteStore(storeId: 'ST-SALECORR');
      await correctionStore.addOrUpdateProduct(
          product(id: 'p-sale-correction', stock: 0, price: 10, cost: 4));
      await correctionStore.adjustStock(
          productId: 'p-sale-correction',
          warehouseId: Warehouse.defaultId,
          quantityDelta: 5,
          reason: 'test seed');

      await expectLater(
          correctionStore.createSale(customerName: 'Bob', items: const []),
          throwsArgumentError);
      await expectLater(
        correctionStore.createSale(
          customerId: 'customer-bob-correction',
          customerName: 'Bob',
          paymentMethod: 'Credit',
          paymentStatus: 'credit',
          items: const [
            SaleItem(
                productId: 'p-sale-correction',
                productName: 'Coffee',
                unitPrice: 10,
                quantity: 6)
          ],
        ),
        throwsA(isA<LocalizedDomainException>()),
      );
      expect(
          correctionStore.stockMovements
              .where((m) => m.type == 'auto_correction'),
          isEmpty);

      final store = await readySqliteStore(storeId: 'ST-SALEFLOW');
      await store.addOrUpdateProduct(
          product(id: 'p-sale-flow', stock: 0, price: 10, cost: 4));
      await store.adjustStock(
          productId: 'p-sale-flow',
          warehouseId: Warehouse.defaultId,
          quantityDelta: 5,
          reason: 'test seed');

      final sale = await store.createSale(
        customerId: 'customer-bob-flow',
        customerName: 'Bob',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        items: const [
          SaleItem(
              productId: 'p-sale-flow',
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
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-sale-flow',
          warehouseId: Warehouse.defaultId,
          storeId: store.appIdentity.storeId,
        ),
        3,
      );
      expect(
        store.stockMovements.where(
          (m) => m.referenceId == sale.id && m.quantity < 0,
        ),
        isNotEmpty,
      );
      expect(store.totalSalesAmount, 20);
      expect(store.estimateProfit(), 12);

      await store.cancelSale(sale.id);
      final cancelledSale = await SqliteMigrationManager.database!.customSelect(
        'SELECT status FROM sales WHERE id = ?',
        variables: <Variable<Object>>[Variable<String>(sale.id)],
      ).getSingle();
      expect(cancelledSale.read<String>('status'), 'Cancelled');
      expect(store.sales.single.paidAmount, 0);
      expect(store.sales.single.cashReceivedAmount, 0);
      expect(store.totalSalesAmount, 0);
      expect(store.products.single.stock, 5);

      await store.cancelSale(sale.id);
      expect(store.sales.length, 1);
    });

    test('phase 6 cancellation never auto-refunds cash; refund is explicit',
        () async {
      final store = await readySqliteStore(
        storeId: 'ST-P6-CANCEL',
        branchId: 'BR-P6-CANCEL',
      );
      final drawerId = await seedOpenCashDrawerForStore(store);
      await store.addOrUpdateProduct(product(id: 'p-p6-cancel', stock: 0));
      final warehouse = store.resolveWarehouseForSale();
      await StockTransactionService(
        SqliteMigrationManager.database!,
        defaultStoreId: store.appIdentity.storeId,
        defaultBranchId: store.appIdentity.branchId,
      ).applyDelta(
        storeId: store.appIdentity.storeId,
        warehouseId: warehouse.id,
        productId: 'p-p6-cancel',
        delta: 5,
        branchId: store.appIdentity.branchId,
      );

      final sale = await store.createSale(
        customerName: 'Phase 6 Customer',
        customerId: 'customer-p6-cancel',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        items: const <SaleItem>[
          SaleItem(
            productId: 'p-p6-cancel',
            productName: 'Coffee',
            unitPrice: 10,
            quantity: 2,
          ),
        ],
        warehouseId: warehouse.id,
      );
      await store.settleSalePayment(
        saleId: sale.id,
        amount: 20,
        paymentMethod: 'Cash',
        idempotencyKey: 'p6-cancel-payment',
      );

      final db = SqliteMigrationManager.database!;
      final beforeCancel = await db
          .customSelect(
            "SELECT current_balance FROM cash_locations WHERE id = '$drawerId'",
          )
          .getSingle();
      expect((beforeCancel.data['current_balance'] as num).toDouble(), 1020);

      await store.cancelSale(sale.id);

      final autoRefunds = await db
          .customSelect(
            "SELECT COUNT(*) AS c FROM cash_ledger_transactions WHERE reference_type = 'sale_refund' AND deleted_at = ''",
          )
          .getSingle();
      expect(autoRefunds.read<int>('c'), 0);
      expect(
        await PaymentVoucherService(db).refundableCashForSale(sale.id),
        20,
      );
      final afterCancel = await db
          .customSelect(
            "SELECT current_balance FROM cash_locations WHERE id = '$drawerId'",
          )
          .getSingle();
      expect((afterCancel.data['current_balance'] as num).toDouble(), 1020);
      final customerCreditAfterCancel = await db
          .customSelect(
            "SELECT COALESCE(SUM(debit - credit), 0) AS balance FROM account_transactions WHERE deleted_at = '' AND account_type = 'customer' AND account_id = 'customer-p6-cancel'",
          )
          .getSingle();
      expect(
          (customerCreditAfterCancel.data['balance'] as num).toDouble(), -20);

      final refunded = await store.refundSaleCash(
        saleId: sale.id,
        amount: 20,
        idempotencyKey: 'p6-explicit-refund',
      );
      expect(refunded, 20);
      final afterRefund = await db
          .customSelect(
            "SELECT current_balance FROM cash_locations WHERE id = '$drawerId'",
          )
          .getSingle();
      expect((afterRefund.data['current_balance'] as num).toDouble(), 1000);
      final customerBalanceAfterRefund = await db
          .customSelect(
            "SELECT COALESCE(SUM(debit - credit), 0) AS balance FROM account_transactions WHERE deleted_at = '' AND account_type = 'customer' AND account_id = 'customer-p6-cancel'",
          )
          .getSingle();
      expect((customerBalanceAfterRefund.data['balance'] as num).toDouble(), 0);

      final reversedRefund = await CashReversalService(db).reverseReference(
        referenceType: 'sale_refund',
        referenceId: '${sale.id}:p6-explicit-refund',
        reason: 'Customer kept the cash refund',
        createdBy: 'Phase 6 Tester',
        createdByUserId: 'user-p6-test',
        deviceId: store.appIdentity.deviceId,
      );
      expect(reversedRefund, 1);
      final afterRefundReversal = await db
          .customSelect(
            "SELECT current_balance FROM cash_locations WHERE id = '$drawerId'",
          )
          .getSingle();
      expect((afterRefundReversal.data['current_balance'] as num).toDouble(),
          1020);
      final customerCreditAfterRefundReversal = await db
          .customSelect(
            "SELECT COALESCE(SUM(debit - credit), 0) AS balance FROM account_transactions WHERE deleted_at = '' AND account_type = 'customer' AND account_id = 'customer-p6-cancel'",
          )
          .getSingle();
      expect(
          (customerCreditAfterRefundReversal.data['balance'] as num).toDouble(),
          -20);
    });

    test('returns a sale, restores stock, and records a sale return movement',
        () async {
      final store = await readySqliteStore(storeId: 'ST-SALERET1');
      await store.addOrUpdateProduct(product(stock: 0, price: 10, cost: 4));
      await store.adjustStock(
          productId: 'p1',
          warehouseId: Warehouse.defaultId,
          quantityDelta: 5,
          reason: 'test seed');

      final sale = await store.createSale(
        customerId: 'customer-bob-return-one',
        customerName: 'Bob',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
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

    test(
        'partial sale returns are cumulative and cannot return the same units twice',
        () async {
      final store = await readySqliteStore(storeId: 'ST-SALERET2');
      await store.addOrUpdateProduct(product(stock: 0, price: 10, cost: 4));
      await store.adjustStock(
          productId: 'p1',
          warehouseId: Warehouse.defaultId,
          quantityDelta: 20,
          reason: 'test seed');

      final sale = await store.createSale(
        customerId: 'customer-partial-return',
        customerName: 'Partial Return Customer',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        items: const <SaleItem>[
          SaleItem(
            productId: 'p1',
            productName: 'Coffee',
            unitPrice: 10,
            quantity: 10,
          ),
        ],
      );

      final first = await store.returnSale(
        sale.id,
        returnedQuantities: const <String, double>{'p1': 4},
      );
      expect(first.items.single.quantity, 4);
      expect(store.sales.single.status, 'Partially Returned');
      expect(store.sales.single.items.single.quantity, 10);
      expect(store.products.single.stock, 14);

      final second = await store.returnSale(
        sale.id,
        returnedQuantities: const <String, double>{'p1': 4},
      );
      expect(second.items.single.quantity, 4);
      expect(store.sales.single.status, 'Partially Returned');
      expect(store.sales.single.items.single.quantity, 10);
      expect(store.products.single.stock, 18);
      final partialReturnJournals =
          await SqliteMigrationManager.database!.customSelect(
        "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'sale_return' AND reference_no = ? AND status = 'posted'",
        variables: <Variable<Object>>[
          Variable<String>(sale.invoiceNo),
        ],
      ).getSingle();
      expect(partialReturnJournals.read<int>('c'), 2);

      await expectLater(
        store.returnSale(
          sale.id,
          returnedQuantities: const <String, double>{'p1': 3},
        ),
        throwsArgumentError,
      );
      expect(store.products.single.stock, 18);

      final finalReturn = await store.returnSale(
        sale.id,
        returnedQuantities: const <String, double>{'p1': 2},
      );
      expect(finalReturn.items.single.quantity, 2);
      expect(store.sales.single.status, 'Returned');
      expect(store.sales.single.items.single.quantity, 10);
      expect(store.products.single.stock, 20);
      final allReturnJournals =
          await SqliteMigrationManager.database!.customSelect(
        "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'sale_return' AND reference_no = ? AND status = 'posted'",
        variables: <Variable<Object>>[
          Variable<String>(sale.invoiceNo),
        ],
      ).getSingle();
      expect(allReturnJournals.read<int>('c'), 3);

      // Regression: the final partial slice must credit only its own value.
      // A cumulative full-return state must not credit the original invoice
      // total again in the customer subledger.
      await store.refreshAccountTransactionsFromSqlite();
      expect(
        store.accountBalance('customer', 'customer-partial-return'),
        closeTo(0, 0.0001),
      );
      final returnLedger = await SqliteMigrationManager.database!.customSelect(
        "SELECT COUNT(*) AS c, COALESCE(SUM(credit), 0) AS credits FROM account_transactions WHERE deleted_at = '' AND account_type = 'customer' AND account_id = 'customer-partial-return' AND transaction_type = 'saleReturn'",
      ).getSingle();
      expect(returnLedger.read<int>('c'), 3);
      expect(returnLedger.read<double>('credits'), closeTo(100, 0.0001));
    });

    test(
        'partial sale returns preserve FEFO batches and actual batch costs by returned slice',
        () async {
      final store = await readySqliteStore(
        storeId: 'ST-P6-RETURN',
        branchId: 'BR-P6-RETURN',
        storeName: 'Phase 6 Return Store',
      );
      final tracked = Product(
        id: 'p-p6-batch-return',
        name: 'Tracked Product',
        code: 'P6-BATCH',
        price: 10,
        cost: 1,
        stock: 0,
        category: 'Test',
        expiryTrackingEnabled: true,
        expiryEntryRequired: true,
      );
      await store.addOrUpdateProduct(tracked);
      final warehouse = store.resolveWarehouseForSale();

      final firstPurchase = await store.createPurchase(
        supplierId: 'sup-p6-1',
        supplierName: 'Supplier 1',
        items: const <PurchaseItem>[
          PurchaseItem(
            productId: 'p-p6-batch-return',
            productName: 'Tracked Product',
            quantity: 4,
            unitCost: 1,
          ),
        ],
        receiveNow: false,
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        warehouseId: warehouse.id,
        warehouseName: warehouse.name,
      );
      await store.receivePurchase(
        firstPurchase.id,
        batchAllocationsByLine: <int, List<BatchAllocation>>{
          0: <BatchAllocation>[
            BatchAllocation(
              batchId: 'requested-early-p6',
              quantity: 4,
              expirationDate: DateTime.utc(2026, 9, 1),
            ),
          ],
        },
      );

      final secondPurchase = await store.createPurchase(
        supplierId: 'sup-p6-2',
        supplierName: 'Supplier 2',
        items: const <PurchaseItem>[
          PurchaseItem(
            productId: 'p-p6-batch-return',
            productName: 'Tracked Product',
            quantity: 6,
            unitCost: 2,
          ),
        ],
        receiveNow: false,
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        warehouseId: warehouse.id,
        warehouseName: warehouse.name,
      );
      await store.receivePurchase(
        secondPurchase.id,
        batchAllocationsByLine: <int, List<BatchAllocation>>{
          0: <BatchAllocation>[
            BatchAllocation(
              batchId: 'requested-late-p6',
              quantity: 6,
              expirationDate: DateTime.utc(2026, 10, 1),
            ),
          ],
        },
      );

      final db = SqliteMigrationManager.database!;
      Future<String> batchIdForPurchase(String purchaseId) async {
        final row = await db.customSelect(
          "SELECT id FROM inventory_batches WHERE source_type = 'purchase' AND source_id = ? ORDER BY received_at, id LIMIT 1",
          variables: <Variable<Object>>[Variable<String>(purchaseId)],
        ).getSingle();
        return row.read<String>('id');
      }

      Future<double> batchQuantity(String batchId) async {
        final row = await db.customSelect(
          'SELECT COALESCE(SUM(quantity), 0) AS qty FROM inventory_batch_balances WHERE batch_id = ?',
          variables: <Variable<Object>>[Variable<String>(batchId)],
        ).getSingle();
        return (row.data['qty'] as num? ?? 0).toDouble();
      }

      final earlyBatchId = await batchIdForPurchase(firstPurchase.id);
      final lateBatchId = await batchIdForPurchase(secondPurchase.id);

      final sale = await store.createSale(
        customerId: 'cust-p6-return',
        customerName: 'Return Customer',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        warehouseId: warehouse.id,
        warehouseName: warehouse.name,
        items: const <SaleItem>[
          SaleItem(
            productId: 'p-p6-batch-return',
            productName: 'Tracked Product',
            unitPrice: 10,
            quantity: 7,
          ),
        ],
      );
      expect(sale.items.single.batchAllocations, hasLength(2));
      expect(sale.items.single.batchAllocations[0].batchId, earlyBatchId);
      expect(sale.items.single.batchAllocations[0].quantity, 4);
      expect(sale.items.single.batchAllocations[0].unitCost, 1);
      expect(sale.items.single.batchAllocations[1].batchId, lateBatchId);
      expect(sale.items.single.batchAllocations[1].quantity, 3);
      expect(sale.items.single.batchAllocations[1].unitCost, 2);
      expect(await batchQuantity(earlyBatchId), closeTo(0, 0.000001));
      expect(await batchQuantity(lateBatchId), closeTo(3, 0.000001));

      final firstReturn = await store.returnSale(
        sale.id,
        returnedQuantities: const <String, double>{'p-p6-batch-return': 2},
      );
      expect(firstReturn.items.single.batchAllocations, hasLength(1));
      expect(firstReturn.items.single.batchAllocations.single.batchId,
          earlyBatchId);
      expect(firstReturn.items.single.batchAllocations.single.quantity, 2);
      expect(firstReturn.items.single.batchAllocations.single.unitCost, 1);
      expect(await batchQuantity(earlyBatchId), closeTo(2, 0.000001));
      expect(await batchQuantity(lateBatchId), closeTo(3, 0.000001));

      final secondReturn = await store.returnSale(
        sale.id,
        returnedQuantities: const <String, double>{'p-p6-batch-return': 3},
      );
      expect(secondReturn.items.single.batchAllocations, hasLength(2));
      expect(secondReturn.items.single.batchAllocations[0].batchId,
          earlyBatchId);
      expect(secondReturn.items.single.batchAllocations[0].quantity, 2);
      expect(secondReturn.items.single.batchAllocations[0].unitCost, 1);
      expect(secondReturn.items.single.batchAllocations[1].batchId,
          lateBatchId);
      expect(secondReturn.items.single.batchAllocations[1].quantity, 1);
      expect(secondReturn.items.single.batchAllocations[1].unitCost, 2);
      expect(await batchQuantity(earlyBatchId), closeTo(4, 0.000001));
      expect(await batchQuantity(lateBatchId), closeTo(4, 0.000001));
    });

    test('purchase return reverses every received batch atomically', () async {
      final store = await readySqliteStore(
        storeId: 'ST-P1-BATCH-RETURN',
        branchId: 'BR-P1-BATCH-RETURN',
        storeName: 'Atomic Batch Return Store',
      );
      final tracked = Product(
        id: 'p-p1-batch-return',
        name: 'Atomic Batch Product',
        code: 'P1-BATCH-RETURN',
        price: 10,
        cost: 2,
        stock: 0,
        category: 'Test',
        expiryTrackingEnabled: true,
        expiryEntryRequired: true,
      );
      await store.addOrUpdateProduct(tracked);
      final warehouse = store.resolveWarehouseForPurchase();
      final draft = await store.createPurchase(
        supplierId: 'supplier-p1-batch-return',
        supplierName: 'Atomic Batch Supplier',
        receiveNow: false,
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        warehouseId: warehouse.id,
        warehouseName: warehouse.name,
        items: const <PurchaseItem>[
          PurchaseItem(
            productId: 'p-p1-batch-return',
            productName: 'Atomic Batch Product',
            quantity: 2,
            unitCost: 2,
          ),
          PurchaseItem(
            productId: 'p-p1-batch-return',
            productName: 'Atomic Batch Product',
            quantity: 3,
            unitCost: 2,
          ),
        ],
      );
      await store.receivePurchase(
        draft.id,
        batchAllocationsByLine: <int, List<BatchAllocation>>{
          0: <BatchAllocation>[
            BatchAllocation(
              batchId: 'requested-p1-a',
              quantity: 2,
              expirationDate: DateTime.utc(2026, 9, 1),
            ),
          ],
          1: <BatchAllocation>[
            BatchAllocation(
              batchId: 'requested-p1-b',
              quantity: 3,
              expirationDate: DateTime.utc(2026, 10, 1),
            ),
          ],
        },
      );

      final db = SqliteMigrationManager.database!;
      final batchRows = await db.customSelect(
        "SELECT id FROM inventory_batches WHERE source_type = 'purchase' AND source_id = ? ORDER BY expiration_date, id",
        variables: <Variable<Object>>[Variable<String>(draft.id)],
      ).get();
      expect(batchRows, hasLength(2));
      final batchIds = batchRows.map((row) => row.read<String>('id')).toList();
      expect(
        await sqliteWarehouseQuantity(
          productId: tracked.id,
          warehouseId: warehouse.id,
          storeId: store.appIdentity.storeId,
        ),
        closeTo(5, 0.000001),
      );

      await store.returnPurchase(draft.id);

      expect(
        await sqliteWarehouseQuantity(
          productId: tracked.id,
          warehouseId: warehouse.id,
          storeId: store.appIdentity.storeId,
        ),
        closeTo(0, 0.000001),
      );
      for (final batchId in batchIds) {
        final row = await db.customSelect(
          'SELECT COALESCE(SUM(quantity), 0) AS qty FROM inventory_batch_balances WHERE batch_id = ?',
          variables: <Variable<Object>>[Variable<String>(batchId)],
        ).getSingle();
        expect((row.data['qty'] as num? ?? 0).toDouble(), closeTo(0, 0.000001));
      }
      final purchaseRow = await db.customSelect(
        'SELECT status FROM purchases WHERE id = ?',
        variables: <Variable<Object>>[Variable<String>(draft.id)],
      ).getSingle();
      expect(purchaseRow.read<String>('status').toLowerCase(), 'returned');
    });

    test('sale cancel is blocked after a partial return', () async {
      final store = await readySqliteStore(
        storeId: 'ST-P1-CANCEL-GUARD',
        branchId: 'BR-P1-CANCEL-GUARD',
        storeName: 'Sale Cancel Guard Store',
      );
      await store.addOrUpdateProduct(product(
        id: 'p-p1-cancel-guard',
        code: 'P1-CANCEL-GUARD',
        name: 'Sale Cancel Guard Product',
        stock: 0,
        cost: 2,
      ));
      await store.createPurchase(
        supplierId: 'supplier-p1-cancel-guard',
        supplierName: 'Sale Cancel Guard Supplier',
        receiveNow: true,
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        items: const <PurchaseItem>[
          PurchaseItem(
            productId: 'p-p1-cancel-guard',
            productName: 'Sale Cancel Guard Product',
            quantity: 5,
            unitCost: 2,
          ),
        ],
      );
      final sale = await store.createSale(
        customerId: 'customer-p1-cancel-guard',
        customerName: 'Sale Cancel Guard Customer',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        items: const <SaleItem>[
          SaleItem(
            productId: 'p-p1-cancel-guard',
            productName: 'Sale Cancel Guard Product',
            unitPrice: 5,
            quantity: 3,
          ),
        ],
      );
      await store.returnSale(
        sale.id,
        returnedQuantities: const <String, double>{'p-p1-cancel-guard': 1},
      );
      await expectLater(store.cancelSale(sale.id), throwsStateError);
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-p1-cancel-guard',
          warehouseId: sale.warehouseId,
          storeId: store.appIdentity.storeId,
        ),
        closeTo(3, 0.000001),
      );
    });

    test('zero-price sale return still reverses COGS journal atomically',
        () async {
      final store = await readySqliteStore(
        storeId: 'ST-P1-FREE-RETURN',
        branchId: 'BR-P1-FREE-RETURN',
        storeName: 'Free Return Store',
      );
      await store.setInventoryCostingMethod(
        InventoryCostingMethod.fifo,
        reason: 'COGS-only sale return test',
      );
      await store.addOrUpdateProduct(product(
        id: 'p-p1-free-return',
        code: 'P1-FREE-RETURN',
        name: 'Free Return Product',
        stock: 0,
        cost: 3,
      ));
      await store.createPurchase(
        supplierId: 'supplier-p1-free-return',
        supplierName: 'Free Return Supplier',
        receiveNow: true,
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        items: const <PurchaseItem>[
          PurchaseItem(
            productId: 'p-p1-free-return',
            productName: 'Free Return Product',
            quantity: 1,
            unitCost: 3,
          ),
        ],
      );
      final sale = await store.createSale(
        customerId: 'customer-p1-free-return',
        customerName: 'Free Return Customer',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        items: const <SaleItem>[
          SaleItem(
            productId: 'p-p1-free-return',
            productName: 'Free Return Product',
            unitPrice: 0,
            quantity: 1,
          ),
        ],
      );
      final note = await store.returnSale(sale.id);
      expect(note.amount, closeTo(0, 0.000001));
      final db = SqliteMigrationManager.database!;
      final journal = await db.customSelect(
        '''
        SELECT id FROM journal_entries
        WHERE reference_type = 'sale_return'
          AND reference_id = ? AND status = 'posted' AND deleted_at = ''
        LIMIT 1
        ''',
        variables: <Variable<Object>>[Variable<String>(note.id)],
      ).getSingleOrNull();
      expect(journal, isNotNull);
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-p1-free-return',
          warehouseId: sale.warehouseId,
          storeId: store.appIdentity.storeId,
        ),
        closeTo(1, 0.000001),
      );
    });

    test(
        'draft purchase receive rolls back stock, FIFO layer, document and journal when accounting fails',
        () async {
      final store = await readySqliteStore(
        storeId: 'ST-P1-ATOMIC-RECEIVE',
        branchId: 'BR-P1-ATOMIC-RECEIVE',
        storeName: 'Atomic Receive Store',
      );
      await store.addOrUpdateProduct(product(
        id: 'p-atomic-receive',
        code: 'ATOMIC-RECEIVE',
        name: 'Atomic Receive Product',
        stock: 0,
        cost: 4,
      ));
      final draft = await store.createPurchase(
        supplierId: 'supplier-atomic-receive',
        supplierName: 'Atomic Supplier',
        receiveNow: false,
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        items: const <PurchaseItem>[
          PurchaseItem(
            productId: 'p-atomic-receive',
            productName: 'Atomic Receive Product',
            quantity: 5,
            unitCost: 4,
          ),
        ],
      );
      final db = SqliteMigrationManager.database!;
      final merchandiseAccount =
          await AccountingService.resolveAccountRole('inventory_merchandise');
      final merchandiseSnapshot =
          (await AccountingService.listAccounts(activeOnly: false))
              .firstWhere((account) => account.id == merchandiseAccount);
      Future<void> setMerchandisePostable(bool value) =>
          AccountingService.updateAccount(
            accountId: merchandiseSnapshot.id,
            code: merchandiseSnapshot.code,
            name: merchandiseSnapshot.name,
            type: merchandiseSnapshot.type,
            normalBalance: merchandiseSnapshot.normalBalance,
            subtype: merchandiseSnapshot.subtype,
            parentId: merchandiseSnapshot.parentId,
            currency: merchandiseSnapshot.currency,
            description: merchandiseSnapshot.description,
            isPostable: value,
          );

      await setMerchandisePostable(false);
      try {
        await expectLater(
          () async => store.receivePurchase(draft.id),
          throwsA(isA<StateError>()),
        );

        final purchaseRow = await db.customSelect(
          'SELECT status FROM purchases WHERE id = ?',
          variables: <Variable<Object>>[Variable<String>(draft.id)],
        ).getSingle();
        expect(purchaseRow.read<String>('status').toLowerCase(), 'draft');

        expect(
          await sqliteWarehouseQuantity(
            productId: 'p-atomic-receive',
            warehouseId: draft.warehouseId,
            storeId: store.appIdentity.storeId,
          ),
          closeTo(0, 0.000001),
        );
        final layerCount = await db.customSelect(
          "SELECT COUNT(*) AS c FROM inventory_cost_layers WHERE purchase_id = ? AND deleted_at = ''",
          variables: <Variable<Object>>[Variable<String>(draft.id)],
        ).getSingle();
        expect(layerCount.read<int>('c'), 0);
        final movementCount = await db.customSelect(
          "SELECT COUNT(*) AS c FROM stock_movements WHERE reference_id = ? AND deleted_at = ''",
          variables: <Variable<Object>>[Variable<String>(draft.id)],
        ).getSingle();
        expect(movementCount.read<int>('c'), 0);
        final journalCount = await db.customSelect(
          "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'purchase' AND reference_id = ?",
          variables: <Variable<Object>>[Variable<String>(draft.id)],
        ).getSingle();
        expect(journalCount.read<int>('c'), 0);
      } finally {
        await setMerchandisePostable(true);
      }
    });

    test('purchase return is blocked while its Unified Batch is consumed',
        () async {
      final store = await readySqliteStore(
        storeId: 'ST-P1-BATCH-GUARD',
        branchId: 'BR-P1-BATCH-GUARD',
        storeName: 'Unified Batch Guard Store',
      );
      await store.addOrUpdateProduct(product(
        id: 'p-batch-guard',
        code: 'BATCH-GUARD',
        name: 'Batch Guard Product',
        stock: 0,
        cost: 3,
      ));
      final purchase = await store.createPurchase(
        supplierId: 'supplier-batch-guard',
        supplierName: 'Batch Guard Supplier',
        receiveNow: true,
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        items: const <PurchaseItem>[
          PurchaseItem(
            productId: 'p-batch-guard',
            productName: 'Batch Guard Product',
            quantity: 5,
            unitCost: 3,
          ),
        ],
      );
      final sale = await store.createSale(
        customerId: 'customer-batch-guard',
        customerName: 'Batch Guard Customer',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        items: const <SaleItem>[
          SaleItem(
            productId: 'p-batch-guard',
            productName: 'Batch Guard Product',
            unitPrice: 8,
            quantity: 2,
          ),
        ],
      );
      final db = SqliteMigrationManager.database!;
      final batch = await db.customSelect(
        "SELECT id FROM inventory_batches WHERE source_type = 'purchase' AND source_id = ? LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(purchase.id)],
      ).getSingle();
      final batchId = batch.read<String>('id');

      Future<double> qty() async {
        final row = await db.customSelect(
          'SELECT COALESCE(SUM(quantity), 0) AS qty FROM inventory_batch_balances WHERE batch_id = ?',
          variables: <Variable<Object>>[Variable<String>(batchId)],
        ).getSingle();
        return (row.data['qty'] as num? ?? 0).toDouble();
      }

      expect(await qty(), closeTo(3, 0.000001));
      await expectLater(
        () async => store.returnPurchase(purchase.id),
        throwsA(isA<StateError>()),
      );

      await store.returnSale(sale.id);
      expect(await qty(), closeTo(5, 0.000001));
      await store.returnPurchase(purchase.id);
      expect(await qty(), closeTo(0, 0.000001));
      final returnedStatus = await db.customSelect(
        'SELECT status FROM purchases WHERE id = ?',
        variables: <Variable<Object>>[Variable<String>(purchase.id)],
      ).getSingle();
      expect(returnedStatus.read<String>('status').toLowerCase(), 'returned');
    });

    test('sale cancel restores Unified Batch balance in SQLite immediately',
        () async {
      final store = await readySqliteStore(
        storeId: 'ST-P1-SALE-CANCEL',
        branchId: 'BR-P1-SALE-CANCEL',
        storeName: 'Sale Cancel Batch Store',
      );
      await store.addOrUpdateProduct(product(
        id: 'p-sale-cancel-batch',
        code: 'SALE-CANCEL-BATCH',
        name: 'Sale Cancel Batch Product',
        stock: 0,
        cost: 2,
      ));
      final purchase = await store.createPurchase(
        supplierId: 'supplier-sale-cancel-batch',
        supplierName: 'Sale Cancel Batch Supplier',
        receiveNow: true,
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        items: const <PurchaseItem>[
          PurchaseItem(
            productId: 'p-sale-cancel-batch',
            productName: 'Sale Cancel Batch Product',
            quantity: 5,
            unitCost: 2,
          ),
        ],
      );
      final sale = await store.createSale(
        customerId: 'customer-sale-cancel-batch',
        customerName: 'Sale Cancel Batch Customer',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        items: const <SaleItem>[
          SaleItem(
            productId: 'p-sale-cancel-batch',
            productName: 'Sale Cancel Batch Product',
            unitPrice: 7,
            quantity: 2,
          ),
        ],
      );
      final db = SqliteMigrationManager.database!;
      final batch = await db.customSelect(
        "SELECT id FROM inventory_batches WHERE source_type = 'purchase' AND source_id = ? LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(purchase.id)],
      ).getSingle();
      final batchId = batch.read<String>('id');
      Future<double> qty() async {
        final row = await db.customSelect(
          'SELECT COALESCE(SUM(quantity), 0) AS qty FROM inventory_batch_balances WHERE batch_id = ?',
          variables: <Variable<Object>>[Variable<String>(batchId)],
        ).getSingle();
        return (row.data['qty'] as num? ?? 0).toDouble();
      }

      expect(await qty(), closeTo(3, 0.000001));
      await store.cancelSale(sale.id);
      expect(await qty(), closeTo(5, 0.000001));
      final saleRow = await db.customSelect(
        'SELECT status FROM sales WHERE id = ?',
        variables: <Variable<Object>>[Variable<String>(sale.id)],
      ).getSingle();
      expect(saleRow.read<String>('status').toLowerCase(), 'cancelled');
    });

    test('warehouse-aware sales only use the selected warehouse', () async {
      final store = await readySqliteStore();
      await store.addOrUpdateProduct(product(id: 'p-wh', stock: 0, price: 10));
      final mainWarehouse = store.resolveWarehouseForSale();
      final branchWarehouse = await store.createWarehouse(
        name: 'Warehouse B',
        code: 'WB',
      );

      await store.adjustStock(
        productId: 'p-wh',
        warehouseId: mainWarehouse.id,
        quantityDelta: 2,
        reason: 'seed main warehouse',
      );
      await store.adjustStock(
        productId: 'p-wh',
        warehouseId: branchWarehouse.id,
        quantityDelta: 20,
        reason: 'seed branch warehouse',
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
        throwsA(isA<LocalizedDomainException>()),
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

    test(
        'editing received purchase rebuilds frozen snapshot, journal and batch-derived cost',
        () async {
      final store = await readySqliteStore(storeId: 'ST-PUREDIT1');
      await store.addOrUpdateProduct(
          product(id: 'p-edit-cost', stock: 0, cost: 5));

      final received = await store.createPurchase(
        supplierId: 'supplier-edit',
        supplierName: 'Edit Supplier',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        receiveNow: true,
        items: const [
          PurchaseItem(
            productId: 'p-edit-cost',
            productName: 'Editable Product',
            quantity: 2,
            unitCost: 10,
          ),
        ],
      );
      expect(received.postedSnapshot, isNotNull);
      expect(received.postedSnapshot!.totals.grandTotal, closeTo(20, 0.0001));

      final edited = await store.updatePurchaseDraft(
        purchaseId: received.id,
        expectedVersion: received.version,
        supplierId: received.supplierId,
        supplierName: received.supplierName,
        warehouseId: received.warehouseId,
        warehouseName: received.warehouseName,
        items: const [
          PurchaseItem(
            productId: 'p-edit-cost',
            productName: 'Editable Product',
            quantity: 2,
            unitCost: 20,
          ),
        ],
      );

      expect(edited.version, received.version + 1);
      expect(edited.paymentStatus, 'credit');
      expect(edited.postedSnapshot, isNotNull);
      expect(edited.postedSnapshot!.documentId, edited.id);
      expect(edited.postedSnapshot!.lines.single.productId, 'p-edit-cost');
      expect(edited.postedSnapshot!.lines.single.unitPrice, closeTo(20, 0.0001));
      expect(edited.postedSnapshot!.totals.grandTotal, closeTo(40, 0.0001));
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-edit-cost',
          warehouseId: Warehouse.defaultId,
          storeId: store.appIdentity.storeId,
        ),
        closeTo(2, 0.0001),
      );
      expect(
        store.productCostFor('p-edit-cost').averageCost,
        closeTo(20, 0.0001),
      );
      expect(
        store.productCostFor('p-edit-cost').lastCost,
        closeTo(20, 0.0001),
      );

      final db = SqliteMigrationManager.database!;
      final journal = await db.customSelect(
        '''
        SELECT COUNT(*) AS count
        FROM journal_entries je
        WHERE je.reference_type = 'purchase'
          AND je.reference_id = ?
          AND je.status = 'posted'
          AND je.deleted_at = ''
          AND NOT EXISTS (
            SELECT 1 FROM journal_entries reversal
            WHERE reversal.reversed_entry_id = je.id
              AND reversal.status = 'posted'
              AND reversal.deleted_at = ''
          )
        ''',
        variables: <Variable<Object>>[
          Variable<String>('${edited.id}:purchase_edit:v${edited.version}'),
        ],
      ).getSingle();
      expect((journal.data['count'] as num? ?? 0).toInt(), 1);
    });

    test(
        'editing received purchase can replace a product at the same total without reusing the old snapshot or cost',
        () async {
      final store = await readySqliteStore(storeId: 'ST-PUREDIT2');
      await store.addOrUpdateProduct(
          product(id: 'p-edit-old', code: 'P-EDIT-OLD', stock: 0, cost: 4));
      await store.addOrUpdateProduct(
          product(id: 'p-edit-new', code: 'P-EDIT-NEW', stock: 0, cost: 7));

      final received = await store.createPurchase(
        supplierId: 'supplier-edit-same-total',
        supplierName: 'Same Total Supplier',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        receiveNow: true,
        items: const [
          PurchaseItem(
            productId: 'p-edit-old',
            productName: 'Old Product',
            quantity: 1,
            unitCost: 20,
          ),
        ],
      );

      final edited = await store.updatePurchaseDraft(
        purchaseId: received.id,
        expectedVersion: received.version,
        supplierId: received.supplierId,
        supplierName: received.supplierName,
        warehouseId: received.warehouseId,
        warehouseName: received.warehouseName,
        items: const [
          PurchaseItem(
            productId: 'p-edit-new',
            productName: 'New Product',
            quantity: 2,
            unitCost: 10,
          ),
        ],
      );

      expect(edited.subtotal, closeTo(received.subtotal, 0.0001));
      expect(edited.postedSnapshot, isNotNull);
      expect(edited.postedSnapshot!.lines.single.productId, 'p-edit-new');
      expect(edited.postedSnapshot!.lines.single.quantity, closeTo(2, 0.0001));
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-edit-old',
          warehouseId: Warehouse.defaultId,
          storeId: store.appIdentity.storeId,
        ),
        closeTo(0, 0.0001),
      );
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-edit-new',
          warehouseId: Warehouse.defaultId,
          storeId: store.appIdentity.storeId,
        ),
        closeTo(2, 0.0001),
      );
      expect(store.productCostFor('p-edit-old').averageCost, closeTo(0, 0.0001));
      expect(store.productCostFor('p-edit-old').lastCost, closeTo(0, 0.0001));
      expect(store.productCostFor('p-edit-new').averageCost, closeTo(10, 0.0001));
      expect(store.productCostFor('p-edit-new').lastCost, closeTo(10, 0.0001));
    });

    test(
        'editing an older received purchase does not overwrite lastCost from a newer purchase',
        () async {
      final store = await readySqliteStore(storeId: 'ST-PUREDIT3');
      await store.addOrUpdateProduct(
          product(id: 'p-edit-last-cost', stock: 0, cost: 3));

      final older = await store.createPurchase(
        supplierId: 'supplier-old-cost',
        supplierName: 'Older Supplier',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        receiveNow: true,
        items: const [
          PurchaseItem(
            productId: 'p-edit-last-cost',
            productName: 'Last Cost Product',
            quantity: 1,
            unitCost: 5,
          ),
        ],
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await store.createPurchase(
        supplierId: 'supplier-new-cost',
        supplierName: 'Newer Supplier',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        receiveNow: true,
        items: const [
          PurchaseItem(
            productId: 'p-edit-last-cost',
            productName: 'Last Cost Product',
            quantity: 1,
            unitCost: 9,
          ),
        ],
      );
      expect(store.productCostFor('p-edit-last-cost').lastCost, closeTo(9, 0.0001));

      await store.updatePurchaseDraft(
        purchaseId: older.id,
        expectedVersion: older.version,
        supplierId: older.supplierId,
        supplierName: older.supplierName,
        warehouseId: older.warehouseId,
        warehouseName: older.warehouseName,
        items: const [
          PurchaseItem(
            productId: 'p-edit-last-cost',
            productName: 'Last Cost Product',
            quantity: 1,
            unitCost: 7,
          ),
        ],
      );

      expect(
        store.productCostFor('p-edit-last-cost').averageCost,
        closeTo(8, 0.0001),
      );
      expect(store.productCostFor('p-edit-last-cost').lastCost, closeTo(9, 0.0001));
    });

    test('received purchase edit recalculates payment status from allocations',
        () async {
      final store = await readySqliteStore(storeId: 'ST-PUREDIT4');
      await store.addOrUpdateProduct(
          product(id: 'p-edit-payment', stock: 0, cost: 2));
      final received = await store.createPurchase(
        supplierId: 'supplier-edit-payment',
        supplierName: 'Payment Supplier',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        receiveNow: true,
        items: const [
          PurchaseItem(
            productId: 'p-edit-payment',
            productName: 'Payment Product',
            quantity: 10,
            unitCost: 10,
          ),
        ],
      );
      final partiallyPaid = await store.settlePurchasePayment(
        purchaseId: received.id,
        amount: 40,
        paymentMethod: 'Bank',
        idempotencyKey: '${received.id}:payment-status-regression',
      );
      expect(partiallyPaid.paidAmount, closeTo(40, 0.0001));

      final partialEdit = await store.updatePurchaseDraft(
        purchaseId: partiallyPaid.id,
        expectedVersion: partiallyPaid.version,
        supplierId: partiallyPaid.supplierId,
        supplierName: partiallyPaid.supplierName,
        warehouseId: partiallyPaid.warehouseId,
        warehouseName: partiallyPaid.warehouseName,
        items: const [
          PurchaseItem(
            productId: 'p-edit-payment',
            productName: 'Payment Product',
            quantity: 8,
            unitCost: 10,
          ),
        ],
      );
      expect(partialEdit.paymentStatus, 'partial');
      expect(partialEdit.paidAmount, closeTo(40, 0.0001));
      expect(partialEdit.postedSnapshot!.totals.paid, closeTo(40, 0.0001));
      expect(partialEdit.postedSnapshot!.totals.remaining, closeTo(40, 0.0001));

      final paidEdit = await store.updatePurchaseDraft(
        purchaseId: partialEdit.id,
        expectedVersion: partialEdit.version,
        supplierId: partialEdit.supplierId,
        supplierName: partialEdit.supplierName,
        warehouseId: partialEdit.warehouseId,
        warehouseName: partialEdit.warehouseName,
        items: const [
          PurchaseItem(
            productId: 'p-edit-payment',
            productName: 'Payment Product',
            quantity: 4,
            unitCost: 10,
          ),
        ],
      );
      expect(paidEdit.paymentStatus, 'paid');
      expect(paidEdit.paidAmount, closeTo(40, 0.0001));
      expect(paidEdit.postedSnapshot!.totals.remaining, closeTo(0, 0.0001));
    });

    test('handles purchase draft, receive, cancel, and manual stock adjustment',
        () async {
      final store = await readySqliteStore(storeId: 'ST-PURFLOW1');
      await store.addOrUpdateProduct(
          product(id: 'p-purchase-flow', stock: 0, cost: 5));
      await store.adjustStock(
          productId: 'p-purchase-flow',
          warehouseId: Warehouse.defaultId,
          quantityDelta: 2,
          reason: 'test seed');

      await expectLater(
          store.createPurchase(
              supplierId: 's1', supplierName: 'Vendor', items: const []),
          throwsArgumentError);
      await expectLater(
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
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        receiveNow: false,
        items: const [
          PurchaseItem(
              productId: 'p-purchase-flow',
              productName: 'Coffee',
              quantity: 3,
              unitCost: 6)
        ],
      );
      expect(draft.status, 'Draft');
      expect(store.pendingPurchaseCount, 1);
      expect(store.products.single.stock, 2);
      final costBeforeReceipt =
          store.productCostFor('p-purchase-flow').averageCost;

      await store.receivePurchase(draft.id);
      expect(store.purchases.single.isReceived, isTrue);
      expect(store.products.single.stock, 5);
      expect(
        store.productCostFor('p-purchase-flow').averageCost,
        closeTo(((2 * costBeforeReceipt) + 18) / 5, 0.001),
      );
      expect(store.totalPurchasesAmount, 18);

      await store.adjustStock(
        productId: 'p-purchase-flow',
        warehouseId: Warehouse.defaultId,
        quantityDelta: -2,
        reason: 'count correction',
      );
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-purchase-flow',
          warehouseId: Warehouse.defaultId,
          storeId: store.appIdentity.storeId,
        ),
        3,
      );
      expect(
        store.stockMovements.where(
          (m) => m.type == 'inventory_loss' || m.type == 'inventory_adjustment',
        ),
        isNotEmpty,
      );

      await store.cancelPurchase(draft.id);
      expect(store.purchases.single.isCancelled, isTrue);
      expect(store.totalPurchasesAmount, 0);
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-purchase-flow',
          warehouseId: Warehouse.defaultId,
          storeId: store.appIdentity.storeId,
        ),
        0,
      );
    });

    test('SQLite-first purchase ledger is durable immediately after create',
        () async {
      final store = await readySqliteStore(
        storeId: 'ST-P9-ACCOUNT-SOT',
        branchId: 'BR-P9-ACCOUNT-SOT',
      );
      await store.addOrUpdateProduct(product(id: 'p-p9-account-sot', stock: 0));

      final purchase = await store.createPurchase(
        supplierId: 'supplier-p9-account-sot',
        supplierName: 'Phase 9 Supplier',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        items: const <PurchaseItem>[
          PurchaseItem(
            productId: 'p-p9-account-sot',
            productName: 'Coffee',
            quantity: 2,
            unitCost: 10,
          ),
        ],
        receiveNow: true,
      );

      final db = SqliteMigrationManager.database!;
      final row = await db.customSelect(
        'SELECT account_type, account_id, transaction_type, credit '
        "FROM account_transactions WHERE id = ? AND deleted_at = '' LIMIT 1",
        variables: <Variable<Object>>[
          Variable<String>('${purchase.id}-purchase-invoice'),
        ],
      ).getSingle();

      expect(row.read<String>('account_type'), 'supplier');
      expect(row.read<String>('account_id'), 'supplier-p9-account-sot');
      expect(row.read<String>('transaction_type'), 'purchaseInvoice');
      expect((row.data['credit'] as num).toDouble(), 20);
    });

    test('phase 6 purchase cancellation never auto-refunds supplier cash',
        () async {
      final store = await readySqliteStore(
        storeId: 'ST-P6-PURCHASE-CANCEL',
        branchId: 'BR-P6-PURCHASE-CANCEL',
      );
      final drawerId = await seedOpenCashDrawerForStore(store);
      await store.addOrUpdateProduct(product(id: 'p-p6-purchase', stock: 0));
      final purchase = await store.createPurchase(
        supplierId: 'supplier-p6-cancel',
        supplierName: 'Phase 6 Supplier',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        items: const <PurchaseItem>[
          PurchaseItem(
            productId: 'p-p6-purchase',
            productName: 'Coffee',
            quantity: 2,
            unitCost: 10,
          ),
        ],
        receiveNow: true,
      );
      await store.settlePurchasePayment(
        purchaseId: purchase.id,
        amount: 20,
        paymentMethod: 'Cash',
        idempotencyKey: 'p6-purchase-cancel-payment',
      );

      final db = SqliteMigrationManager.database!;
      final beforeCancel = await db
          .customSelect(
            "SELECT current_balance FROM cash_locations WHERE id = '$drawerId'",
          )
          .getSingle();
      expect((beforeCancel.data['current_balance'] as num).toDouble(), 980);

      await store.cancelPurchase(purchase.id);

      final autoRefunds = await db
          .customSelect(
            "SELECT COUNT(*) AS c FROM cash_ledger_transactions WHERE reference_type = 'purchase_refund' AND deleted_at = ''",
          )
          .getSingle();
      expect(autoRefunds.read<int>('c'), 0);
      expect(
        await PaymentVoucherService(db).refundableCashForPurchase(purchase.id),
        20,
      );
      final afterCancel = await db
          .customSelect(
            "SELECT current_balance FROM cash_locations WHERE id = '$drawerId'",
          )
          .getSingle();
      expect((afterCancel.data['current_balance'] as num).toDouble(), 980);
      final supplierAdvanceAfterCancel = await db
          .customSelect(
            "SELECT COALESCE(SUM(debit - credit), 0) AS balance FROM account_transactions WHERE deleted_at = '' AND account_type = 'supplier' AND account_id = 'supplier-p6-cancel'",
          )
          .getSingle();
      expect(
          (supplierAdvanceAfterCancel.data['balance'] as num).toDouble(), 20);

      final refunded = await store.refundPurchaseCash(
        purchaseId: purchase.id,
      );
      expect(refunded, 20);
      final afterRefund = await db
          .customSelect(
            "SELECT current_balance FROM cash_locations WHERE id = '$drawerId'",
          )
          .getSingle();
      expect((afterRefund.data['current_balance'] as num).toDouble(), 1000);
      final supplierBalanceAfterRefund = await db
          .customSelect(
            "SELECT COALESCE(SUM(debit - credit), 0) AS balance FROM account_transactions WHERE deleted_at = '' AND account_type = 'supplier' AND account_id = 'supplier-p6-cancel'",
          )
          .getSingle();
      expect((supplierBalanceAfterRefund.data['balance'] as num).toDouble(), 0);

      final supplierRefundReference = await db.customSelect(
        "SELECT reference_id FROM cash_ledger_transactions WHERE reference_type = 'purchase_refund' AND reference_id LIKE ? AND reversal_of_id = '' ORDER BY created_at DESC LIMIT 1",
        variables: <Variable<Object>>[
          Variable<String>('${purchase.id}:%'),
        ],
      ).getSingle();

      final reversedRefund = await CashReversalService(db).reverseReference(
        referenceType: 'purchase_refund',
        referenceId: supplierRefundReference.read<String>('reference_id'),
        reason: 'Supplier refund reversal',
        createdBy: 'Phase 6 Tester',
        createdByUserId: 'user-p6-test',
        deviceId: store.appIdentity.deviceId,
      );
      expect(reversedRefund, 1);
      final afterRefundReversal = await db
          .customSelect(
            "SELECT current_balance FROM cash_locations WHERE id = '$drawerId'",
          )
          .getSingle();
      expect(
          (afterRefundReversal.data['current_balance'] as num).toDouble(), 980);
      final supplierAdvanceAfterRefundReversal = await db
          .customSelect(
            "SELECT COALESCE(SUM(debit - credit), 0) AS balance FROM account_transactions WHERE deleted_at = '' AND account_type = 'supplier' AND account_id = 'supplier-p6-cancel'",
          )
          .getSingle();
      expect(
          (supplierAdvanceAfterRefundReversal.data['balance'] as num)
              .toDouble(),
          20);
    });

    test('returns received purchase and reverses stock with return movement',
        () async {
      final store = await readySqliteStore(storeId: 'ST-PURRET01');
      await store.addOrUpdateProduct(product(stock: 0));
      await store.adjustStock(
          productId: 'p1',
          warehouseId: Warehouse.defaultId,
          quantityDelta: 10,
          reason: 'test seed');
      final draft = await store.createPurchase(
        supplierId: 's1',
        supplierName: 'Supplier',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
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
      final purchaseReturnMovement =
          await SqliteMigrationManager.database!.customSelect(
        "SELECT COUNT(*) AS c FROM stock_movements WHERE reference_id = ? AND quantity < 0 AND reversal_of_movement_id <> '' AND deleted_at = ''",
        variables: <Variable<Object>>[Variable<String>(draft.id)],
      ).getSingle();
      expect(purchaseReturnMovement.read<int>('c'), greaterThan(0));
      expect(
          store.accountTransactions
              .where((entry) => entry.type == 'purchaseReturn'),
          isNotEmpty);
    });

    test(
        'warehouse-aware purchases, adjustments, and counts stay in the selected warehouse',
        () async {
      final store = await readySqliteStore();
      await store
          .addOrUpdateProduct(product(id: 'p-phase4', stock: 0, cost: 5));
      final branchWarehouse = await store.createWarehouse(
        name: 'Warehouse B',
        code: 'WB',
      );

      final purchase = await store.createPurchase(
        supplierId: 's1',
        supplierName: 'Supplier',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
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

    test('purchase insights preserve derived metrics and cache invalidation',
        () async {
      final store = await readySqliteStore(
        storeId: 'ST-PUR-INSIGHTS',
        branchId: 'BR-PUR-INSIGHTS',
        storeName: 'Purchase Insights Store',
      );
      await store.addOrUpdateProduct(
        product(id: 'p-purchase-insights', stock: 0, cost: 1),
      );

      await store.createPurchase(
        supplierId: 'supplier-insights-a',
        supplierName: 'Supplier A',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        receiveNow: false,
        items: const <PurchaseItem>[
          PurchaseItem(
            productId: 'p-purchase-insights',
            productName: 'Coffee',
            quantity: 2,
            unitCost: 3,
          ),
        ],
      );

      expect(store.lastPurchasePriceForProduct('p-purchase-insights'), 3);
      expect(store.averagePurchaseCostForProduct('p-purchase-insights'), 3);
      expect(
        store.purchasePriceHistoryForProduct('p-purchase-insights'),
        hasLength(1),
      );

      await Future<void>.delayed(const Duration(milliseconds: 2));
      await store.createPurchase(
        supplierId: 'supplier-insights-b',
        supplierName: 'Supplier B',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        receiveNow: false,
        items: const <PurchaseItem>[
          PurchaseItem(
            productId: 'p-purchase-insights',
            productName: 'Coffee',
            quantity: 4,
            unitCost: 5,
          ),
        ],
      );

      final overview = store.purchasesOverview;
      expect(overview.totalCount, 2);
      expect(overview.totalPurchasesAmount, 26);
      expect(overview.monthlyTotal, 26);
      expect(overview.monthlyCount, 2);
      expect(overview.draftTotal, 26);
      expect(overview.draftCount, 2);
      expect(overview.pendingPurchaseCount, 2);
      expect(overview.receivedCount, 0);
      expect(overview.returnedCount, 0);
      expect(overview.cancelledCount, 0);
      expect(store.totalPurchasesAmount, 26);
      expect(store.pendingPurchaseCount, 2);

      final history =
          store.purchasePriceHistoryForProduct('p-purchase-insights');
      expect(history, hasLength(2));
      expect(history.map((row) => row.unitCost).toList(), <double>[5, 3]);
      expect(
        history.map((row) => row.supplierId).toList(),
        <String>['supplier-insights-b', 'supplier-insights-a'],
      );

      final comparison =
          store.supplierPriceComparisonForProduct('p-purchase-insights');
      expect(comparison, hasLength(2));
      expect(comparison.map((row) => row.unitCost).toList(), <double>[3, 5]);
      expect(
        comparison.map((row) => row.supplierId).toList(),
        <String>['supplier-insights-a', 'supplier-insights-b'],
      );

      expect(
        store.lastPurchasePriceFor(
          productId: 'p-purchase-insights',
          supplierId: 'supplier-insights-a',
        ),
        3,
      );
      expect(
        store.lastPurchasePriceFor(
          productId: 'p-purchase-insights',
          supplierId: 'supplier-insights-b',
        ),
        5,
      );
      expect(store.lastPurchasePriceForProduct('p-purchase-insights'), 5);
      expect(
        store.averagePurchaseCostForProduct('p-purchase-insights'),
        closeTo(26 / 6, 0.000001),
      );
      expect(
        store
            .lastPurchaseItemFor(
              productId: 'p-purchase-insights',
              supplierId: 'supplier-insights-a',
            )
            ?.unitCost,
        3,
      );
      expect(
        store.lastPurchaseItemForProduct('p-purchase-insights')?.unitCost,
        5,
      );
    });

    test('legacy purchase and inventory count default to main warehouse',
        () async {
      final store = await readySqliteStore();
      await store.addOrUpdateProduct(product(id: 'p-legacy-main', stock: 2));

      final purchase = await store.createPurchase(
        supplierId: 's1',
        supplierName: 'Supplier',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
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
          store.syncSnapshotGeneratedAtFromJson(
              await store.exportSyncSnapshotJson()),
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
      final store = await readySqliteStore(
        storeId: 'ST-SQLITE01',
        branchId: 'BR-SQLITE01',
        storeName: 'SQLite Store',
      );

      final db = SqliteMigrationManager.database;
      expect(db != null, isTrue);
      final sqliteDb = db!;
      await sqliteDb.transaction(() async {
        await sqliteDb.customStatement('DELETE FROM stock_movements');
        await sqliteDb.customStatement('DELETE FROM warehouse_inventory');
        await sqliteDb.customStatement('DELETE FROM stock_operations');
        await sqliteDb.customStatement('DELETE FROM inventory_reconciliations');
        await sqliteDb
            .customStatement('DELETE FROM inventory_migration_adjustments');
        await sqliteDb.customStatement('DELETE FROM sync_events');
        await sqliteDb.customStatement('DELETE FROM pending_sync_changes');
        await sqliteDb.customStatement('DELETE FROM sync_queue');
        await sqliteDb.customStatement(
            "UPDATE products SET deleted_at = '2026-01-01T00:00:00.000Z' WHERE deleted_at = ''");
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
        await sqliteDb
            .customStatement('DELETE FROM inventory_migration_adjustments');
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
      final hostStore = await readyStore();
      final clientIdentity = hostStore.appIdentity.copyWith(
        deviceRole: DeviceRole.client,
        syncMode: SyncMode.directConnected,
        activeSyncTransport: 'direct',
        hostDeviceId: 'DV-HOST-TEST',
        deviceToken: 'device-token-test',
      );
      await LocalDatabaseService.setString(
        'app_identity_v1',
        jsonEncode(clientIdentity.toJson()),
      );
      await const DirectSyncSettings(
        apiBaseUrl: 'https://example.test',
        peerDeviceId: 'DV-HOST-TEST',
        setupComplete: true,
      ).save();
      final store = AppStore();
      await store.initialize();
      await store.applySessionUser(
        activeUser: hostStore.users.first,
        currentRole: 'Admin',
        permissions: Set<String>.from(AppPermission.all),
        rememberLogin: true,
      );
      await store.addOrUpdateProduct(product());
      final changeIds = store
          .pendingSyncChangesForTarget('host', readyOnly: false)
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
      expect(
          store.pendingSyncChangesForTarget('host', readyOnly: false), isEmpty);
      expect(
          store.pendingSyncQueueForTarget('host', readyOnly: false), isEmpty);

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
      expect(store.products.singleWhere((p) => p.id == 'remote_p').stock, 4);
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
          password: 'Cashier123');

      expect(await store.login('cashier', 'bad'), isFalse);
      expect(await store.login('cashier', 'Cashier123'), isTrue);
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
          password: 'Cashier123');

      expect(
          await AuthRepository.login(store, 'cashier', 'Cashier123', remember: true),
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
          password: 'Cashier123');
      expect(
          await AuthRepository.login(store, 'cashier', 'Cashier123', remember: true),
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
      expect(store.users.singleWhere((u) => u.username == 'cashier').fullName,
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
  _phase3InventoryCountAccountingTests();
  _phase5ExpensePostStateTests();
}

void _phase3InventoryCountAccountingTests() {
  group('Accounting Phase 3 inventory count posting', () {
    test(
        'posts shortages and overages to separate roles and snapshots audit data',
        () async {
      final store = await readySqliteStore(
        storeId: 'ST-ACC-P3-COUNT',
        branchId: 'BR-ACC-P3-COUNT',
        storeName: 'Accounting Phase 3 Count',
      );
      await store.addOrUpdateProduct(
        product(
            id: 'p-count-loss',
            code: 'PCL',
            name: 'Count Loss',
            stock: 0,
            cost: 10),
      );
      await store.addOrUpdateProduct(
        product(
            id: 'p-count-gain',
            code: 'PCG',
            name: 'Count Gain',
            stock: 0,
            cost: 4),
      );
      await store.adjustStock(
        productId: 'p-count-loss',
        warehouseId: Warehouse.defaultId,
        quantityDelta: 10,
        reason: 'seed loss stock',
      );
      await store.adjustStock(
        productId: 'p-count-gain',
        warehouseId: Warehouse.defaultId,
        quantityDelta: 5,
        reason: 'seed gain stock',
      );

      final session = await store.createInventoryCountSession();
      await store.countInventoryLine(
        sessionId: session.id,
        productId: 'p-count-loss',
        countedQty: 8,
      );
      await store.countInventoryLine(
        sessionId: session.id,
        productId: 'p-count-gain',
        countedQty: 6,
      );
      await store.approveInventoryCount(session.id);

      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-count-loss',
          warehouseId: Warehouse.defaultId,
          storeId: store.appIdentity.storeId,
        ),
        8,
      );
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-count-gain',
          warehouseId: Warehouse.defaultId,
          storeId: store.appIdentity.storeId,
        ),
        6,
      );

      final approved = store.inventoryCountSessions
          .firstWhere((item) => item.id == session.id);
      expect(approved.isApproved, isTrue);
      expect(approved.journalEntryId, isNotEmpty);
      final lossLine =
          approved.lines.firstWhere((line) => line.productId == 'p-count-loss');
      final gainLine =
          approved.lines.firstWhere((line) => line.productId == 'p-count-gain');
      expect(lossLine.systemQtyAtApproval, 10);
      expect(lossLine.differenceQty, -2);
      expect(lossLine.unitCost, 10);
      expect(lossLine.differenceValue, 20);
      expect(lossLine.stockMovementId, isNotEmpty);
      expect(gainLine.systemQtyAtApproval, 5);
      expect(gainLine.differenceQty, 1);
      expect(gainLine.unitCost, 4);
      expect(gainLine.differenceValue, 4);

      final db = SqliteMigrationManager.database!;
      final journalCount = await db.customSelect(
        "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'inventory_count' AND reference_id = ? AND status = 'posted'",
        variables: <Variable<Object>>[Variable<String>(session.id)],
      ).getSingle();
      expect(journalCount.read<int>('c'), 1);
      final journalLines = await db.customSelect(
        '''
        SELECT account_id, debit, credit
        FROM journal_lines
        WHERE entry_id = ?
        ORDER BY line_no
        ''',
        variables: <Variable<Object>>[
          Variable<String>(approved.journalEntryId),
        ],
      ).get();
      expect(
        journalLines.any((row) =>
            row.data['account_id'] == 'acc_inventory_count_loss' &&
            (row.data['debit'] as num).toDouble() == 20),
        isTrue,
      );
      expect(
        journalLines.any((row) =>
            row.data['account_id'] == 'acc_inventory_count_gain' &&
            (row.data['credit'] as num).toDouble() == 4),
        isTrue,
      );
      final persisted = await BusinessSqliteStore.readInventoryCounts(db);
      final persistedSession =
          persisted.firstWhere((item) => item.id == session.id);
      expect(persistedSession.status, 'approved');
      expect(persistedSession.journalEntryId, approved.journalEntryId);
      expect(
        persistedSession.lines
            .firstWhere((line) => line.productId == 'p-count-loss')
            .differenceValue,
        20,
      );
    });

    test('rejects approval when a counted product moved after its count',
        () async {
      final store = await readySqliteStore(
        storeId: 'ST-ACC-P3-STALE',
        branchId: 'BR-ACC-P3-STALE',
        storeName: 'Accounting Phase 3 Stale Count',
      );
      await store.addOrUpdateProduct(
        product(
            id: 'p-count-stale',
            code: 'PCS',
            name: 'Count Stale',
            stock: 0,
            cost: 5),
      );
      await store.adjustStock(
        productId: 'p-count-stale',
        warehouseId: Warehouse.defaultId,
        quantityDelta: 10,
        reason: 'seed stale stock',
      );
      final session = await store.createInventoryCountSession();
      await store.countInventoryLine(
        sessionId: session.id,
        productId: 'p-count-stale',
        countedQty: 10,
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await store.adjustStock(
        productId: 'p-count-stale',
        warehouseId: Warehouse.defaultId,
        quantityDelta: 1,
        reason: 'movement after count',
      );

      await expectLater(
          store.approveInventoryCount(session.id), throwsStateError);
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-count-stale',
          warehouseId: Warehouse.defaultId,
          storeId: store.appIdentity.storeId,
        ),
        11,
      );
      final db = SqliteMigrationManager.database!;
      final persisted = await BusinessSqliteStore.readInventoryCounts(db);
      expect(
          persisted.firstWhere((item) => item.id == session.id).status, 'open');
      final journal = await db.customSelect(
        "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'inventory_count' AND reference_id = ?",
        variables: <Variable<Object>>[Variable<String>(session.id)],
      ).getSingle();
      expect(journal.read<int>('c'), 0);
    });

    test('rolls back stock and count status when accounting posting fails',
        () async {
      final store = await readySqliteStore(
        storeId: 'ST-ACC-P3-ROLLBACK',
        branchId: 'BR-ACC-P3-ROLLBACK',
        storeName: 'Accounting Phase 3 Rollback',
      );
      await store.addOrUpdateProduct(
        product(
            id: 'p-count-rollback',
            code: 'PCRB',
            name: 'Count Rollback',
            stock: 0,
            cost: 5),
      );
      await store.adjustStock(
        productId: 'p-count-rollback',
        warehouseId: Warehouse.defaultId,
        quantityDelta: 10,
        reason: 'seed rollback stock',
      );
      final session = await store.createInventoryCountSession();
      await store.countInventoryLine(
        sessionId: session.id,
        productId: 'p-count-rollback',
        countedQty: 8,
      );
      final db = SqliteMigrationManager.database!;
      await db.customUpdate(
        "UPDATE accounting_settings SET account_id = 'acc_inventory_variances' WHERE key = 'role_inventory_count_loss_account_id'",
      );

      await expectLater(
          store.approveInventoryCount(session.id), throwsStateError);
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-count-rollback',
          warehouseId: Warehouse.defaultId,
          storeId: store.appIdentity.storeId,
        ),
        10,
      );
      final movement = await db.customSelect(
        "SELECT COUNT(*) AS c FROM stock_movements WHERE reference_id = ? AND movement_type = 'count_adjustment'",
        variables: <Variable<Object>>[Variable<String>(session.id)],
      ).getSingle();
      expect(movement.read<int>('c'), 0);
      final persisted = await BusinessSqliteStore.readInventoryCounts(db);
      expect(
          persisted.firstWhere((item) => item.id == session.id).status, 'open');
      await db.customUpdate(
        "UPDATE accounting_settings SET account_id = 'acc_inventory_count_loss' WHERE key = 'role_inventory_count_loss_account_id'",
      );
    });

    test(
        'reverses approved inventory count with stock and journal history intact',
        () async {
      final store = await readySqliteStore(
        storeId: 'ST-ACC-P3-REV',
        branchId: 'BR-ACC-P3-REV',
        storeName: 'Accounting Phase 3 Reverse Count',
      );
      await store.addOrUpdateProduct(
        product(
            id: 'p-count-reverse',
            code: 'PCR',
            name: 'Count Reverse',
            stock: 0,
            cost: 6),
      );
      await store.adjustStock(
        productId: 'p-count-reverse',
        warehouseId: Warehouse.defaultId,
        quantityDelta: 10,
        reason: 'seed reverse stock',
      );
      final session = await store.createInventoryCountSession();
      await store.countInventoryLine(
        sessionId: session.id,
        productId: 'p-count-reverse',
        countedQty: 8,
      );
      await store.approveInventoryCount(session.id);
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-count-reverse',
          warehouseId: Warehouse.defaultId,
          storeId: store.appIdentity.storeId,
        ),
        8,
      );

      await store.reverseInventoryCount(
        session.id,
        reason: 'approved by mistake',
      );
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-count-reverse',
          warehouseId: Warehouse.defaultId,
          storeId: store.appIdentity.storeId,
        ),
        10,
      );
      final reversed = store.inventoryCountSessions
          .firstWhere((item) => item.id == session.id);
      expect(reversed.isReversed, isTrue);
      expect(reversed.reversalJournalEntryId, isNotEmpty);
      expect(reversed.reversalReason, 'approved by mistake');

      final db = SqliteMigrationManager.database!;
      final originalJournal = await db.customSelect(
        "SELECT id FROM journal_entries WHERE reference_type = 'inventory_count' AND reference_id = ? AND status = 'posted' LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(session.id)],
      ).getSingleOrNull();
      expect(originalJournal, isNotNull);
      final reversalJournal = await db.customSelect(
        "SELECT reversed_entry_id FROM journal_entries WHERE reference_type = 'inventory_count_reversal' AND reference_id = ? AND status = 'posted' LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(session.id)],
      ).getSingleOrNull();
      expect(reversalJournal, isNotNull);
      expect(reversalJournal!.data['reversed_entry_id'],
          originalJournal!.data['id']);
      final reversalMovement = await db.customSelect(
        '''
        SELECT reversal_of_movement_id, quantity
        FROM stock_movements
        WHERE reference_id = ? AND movement_type = 'count_adjustment_reversal'
        LIMIT 1
        ''',
        variables: <Variable<Object>>[Variable<String>(session.id)],
      ).getSingleOrNull();
      expect(reversalMovement, isNotNull);
      expect(reversalMovement!.data['reversal_of_movement_id']?.toString(),
          isNotEmpty);
      expect((reversalMovement.data['quantity'] as num).toDouble(), 2);
    });
  });
}

Future<void> _seedPhase5PostingDrawer(
  AppStore store, {
  required double balance,
}) async {
  final db = SqliteMigrationManager.database;
  expect(db, isNotNull);
  final now = DateTime.utc(2026, 8, 18, 12).toIso8601String();
  await db!.customStatement(
      "DELETE FROM cash_drawer_sessions WHERE id = 'shift-post-integrity'");
  await db.customStatement(
      "DELETE FROM cash_locations WHERE id = 'drawer-post-integrity'");
  await db.customInsert(
    '''
    INSERT INTO cash_locations
      (id, code, name, type, account_id, current_balance, allow_negative,
       is_active, created_at, updated_at, store_id, branch_id, device_id)
    VALUES ('drawer-post-integrity', 'DRAW-POST-INTEGRITY', 'Posting Integrity Drawer',
            'cash_drawer', 'acc_cash', ?, 0, 1, ?, ?, ?, ?, ?)
    ''',
    variables: <Variable<Object>>[
      Variable<double>(balance),
      Variable<String>(now),
      Variable<String>(now),
      Variable<String>(store.appIdentity.storeId),
      Variable<String>(store.appIdentity.branchId),
      Variable<String>(store.appIdentity.deviceId),
    ],
  );
  await db.customInsert(
    '''
    INSERT INTO cash_drawer_sessions
      (id, drawer_no, cash_location_id, opened_at, status, opening_balance,
       expected_cash, store_id, branch_id)
    VALUES ('shift-post-integrity', 'SHIFT-POST-INTEGRITY',
            'drawer-post-integrity', ?, 'open', ?, ?, ?, ?)
    ''',
    variables: <Variable<Object>>[
      Variable<String>(now),
      Variable<double>(balance),
      Variable<double>(balance),
      Variable<String>(store.appIdentity.storeId),
      Variable<String>(store.appIdentity.branchId),
    ],
  );
}

void _phase5ExpensePostStateTests() {
  test(
      'postExpense keeps expense unposted when authoritative cash posting fails',
      () async {
    final store = await readySqliteStore(
      storeId: 'ST-P5-POST-ONE',
      branchId: 'BR-P5-POST-ONE',
      storeName: 'Phase 5 Posting One',
    );
    await _seedPhase5PostingDrawer(store, balance: 5);
    await store.addOrUpdateExpense(Expense(
      id: 'expense-post-fail',
      title: 'Too large',
      category: 'General',
      amount: 20,
      date: DateTime.utc(2026, 8, 18, 15),
      notes: '',
    ));

    await expectLater(store.postExpense('expense-post-fail'), throwsStateError);

    final expense =
        store.expenses.firstWhere((e) => e.id == 'expense-post-fail');
    expect(expense.isPosted, isFalse);
    final db = SqliteMigrationManager.database!;
    final operation = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM cash_operations WHERE idempotency_key = 'expense:expense-post-fail'",
        )
        .getSingle();
    expect(operation.read<int>('c'), 0);
    final balance = await db
        .customSelect(
          "SELECT current_balance FROM cash_locations WHERE id = 'drawer-post-integrity'",
        )
        .getSingle();
    expect((balance.data['current_balance'] as num).toDouble(), 5);
  });

  test(
      'bulk posting failure leaves all expenses unposted and rolls back cash batch',
      () async {
    final store = await readySqliteStore(
      storeId: 'ST-P5-POST-BULK',
      branchId: 'BR-P5-POST-BULK',
      storeName: 'Phase 5 Posting Bulk',
    );
    await _seedPhase5PostingDrawer(store, balance: 10);
    final expenses = <Expense>[
      Expense(
        id: 'expense-bulk-post-1',
        title: 'Bulk one',
        category: 'General',
        amount: 6,
        date: DateTime.utc(2026, 8, 18, 15),
        notes: '',
      ),
      Expense(
        id: 'expense-bulk-post-2',
        title: 'Bulk two',
        category: 'General',
        amount: 6,
        date: DateTime.utc(2026, 8, 18, 15),
        notes: '',
      ),
    ];

    await expectLater(
        store.createAndPostExpensesBulk(expenses), throwsStateError);

    expect(
      store.expenses.where((e) =>
          e.id == 'expense-bulk-post-1' || e.id == 'expense-bulk-post-2'),
      isEmpty,
    );
    final db = SqliteMigrationManager.database!;
    final operations = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM cash_operations WHERE idempotency_key IN ('expense:expense-bulk-post-1', 'expense:expense-bulk-post-2')",
        )
        .getSingle();
    expect(operations.read<int>('c'), 0);
    final balance = await db
        .customSelect(
          "SELECT current_balance FROM cash_locations WHERE id = 'drawer-post-integrity'",
        )
        .getSingle();
    expect((balance.data['current_balance'] as num).toDouble(), 10);
  });
}
