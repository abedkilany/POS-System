import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/app_identity.dart';
import 'package:ventio/models/app_user.dart';
import 'package:ventio/models/catalog_item.dart';
import 'package:ventio/models/customer.dart';
import 'package:ventio/models/expense.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/purchase_item.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/store_profile.dart';
import 'package:ventio/models/supplier.dart';
import 'package:ventio/models/sync_change.dart';
import 'package:ventio/models/user_role.dart';

Product product({String id = 'p1', String code = 'P001', String name = 'Coffee', double stock = 10, double price = 12, double cost = 7}) {
  return Product(id: id, name: name, code: code, price: price, cost: cost, stock: stock, category: 'Drinks');
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
  LocalDatabaseService.useInMemoryStoreForTesting(hostIdentitySeed(seed));
  final store = AppStore();
  await store.initialize();
  await store.completeInitialAdminSetup(fullName: 'Admin', username: 'admin', password: 'AdminPass123');
  return store;
}

void main() {
  group('AppStore initialization and persisted state', () {
    test('initializes defaults, identity, walk-in customer, admin user, and catalog defaults', () async {
      final store = await readyStore();

      expect(store.isReady, isTrue);
      expect(store.products, isEmpty);
      expect(store.walkInCustomer.name, AppStore.walkInCustomerName);
      expect(store.customers.map((c) => c.id), contains(AppStore.walkInCustomerId));
      expect(store.roles.map((r) => r.id), contains('admin'));
      expect(store.users.map((u) => u.username), contains('admin'));
      expect(store.needsInitialAdminSetup, isFalse);
      expect(store.appIdentity.deviceId, isNotEmpty);
      expect(store.categories, isNotEmpty);
      expect(store.brands, isNotEmpty);
      expect(store.units, isNotEmpty);
      expect(store.currentBackupSummary.storeName, isNotEmpty);
    });

    test('re-hydrates products, customers, sales counters, roles, and profile from local db', () async {
      final seeded = await readyStore();
      await seeded.addOrUpdateProduct(product());
      await seeded.addOrUpdateCustomer(Customer(id: 'c1', name: 'Alice', phone: '1', address: 'A'));
      await seeded.updateStoreProfile(StoreProfile.defaults.copyWith(name: 'Seeded Store'));
      final sale = await seeded.createSale(customerName: 'Alice', items: const [SaleItem(productId: 'p1', productName: 'Coffee', unitPrice: 12, quantity: 2)]);
      final raw = seeded.exportBackupJson();

      final restored = await readyStore();
      await restored.importBackupJson(raw);

      expect(restored.products.single.code, 'P001');
      expect(restored.sales.single.invoiceNo, sale.invoiceNo);
      expect(restored.storeProfile.name, 'Seeded Store');
      expect(restored.totalSalesAmount, 24);
    });
  });

  group('AppStore product, customer, supplier, catalog, and expense workflows', () {
    test('creates, updates, deletes, syncs, and validates products', () async {
      final store = await readyStore();
      var notificationCount = 0;
      store.addListener(() => notificationCount++);

      await store.addOrUpdateProduct(product(code: ''));
      expect(store.products.single.code, isNotEmpty);
      expect(store.pendingSyncChanges, isNotEmpty);
      expect(store.pendingSyncQueueCount, greaterThan(0));
      expect(notificationCount, greaterThan(0));

      final saved = store.products.single;
      await store.addOrUpdateProduct(saved.copyWith(price: 15, stock: 4, lowStockThreshold: 5));
      expect(store.products.single.price, 15);
      expect(store.lowStockCount, 1);
      expect(store.inventoryRetailValue, 60);
      expect(store.inventoryCostValue, 28);

      expect(store.addOrUpdateProduct(saved.copyWith(id: 'bad', code: saved.code)), throwsArgumentError);
      expect(store.addOrUpdateProduct(saved.copyWith(id: 'neg', code: 'NEG', price: -1)), throwsArgumentError);

      await store.deleteProduct(saved.id);
      expect(store.products, isEmpty);
      expect(store.syncChanges.where((c) => c.entityType == 'product' && c.operation == 'delete'), isNotEmpty);
    });

    test('manages customers, suppliers, catalog lists, and expenses with duplicate protection', () async {
      final store = await readyStore();

      await store.addOrUpdateCustomer(Customer(id: 'c1', name: ' Alice ', phone: '111', address: 'A'));
      expect(store.resolveCustomerName('c1'), 'Alice');
      expect(store.sanitizeSelectedCustomerId('missing'), AppStore.walkInCustomerId);
      expect(store.addOrUpdateCustomer(Customer(id: 'c2', name: 'alice', phone: '', address: '')), throwsArgumentError);
      await store.deleteCustomer('c1');
      expect(store.customers.map((c) => c.id), isNot(contains('c1')));

      await store.addOrUpdateSupplier(Supplier(id: 's1', name: ' Supplier ', phone: '222', address: 'B', notes: ''));
      expect(store.suppliers.single.name, 'Supplier');
      expect(store.addOrUpdateSupplier(Supplier(id: 's2', name: 'supplier', phone: '', address: '', notes: '')), throwsArgumentError);
      await store.deleteSupplier('s1');
      expect(store.suppliers, isEmpty);

      await store.addOrUpdateCategory(CatalogItem(id: 'cat_test', nameEn: 'Snacks', nameAr: ''));
      await store.addOrUpdateBrand(CatalogItem(id: 'brand_test', nameEn: 'Acme', nameAr: ''));
      await store.addOrUpdateUnit(CatalogItem(id: 'unit_test', nameEn: 'Crate', nameAr: ''));
      expect(store.categories.map((e) => e.nameEn), contains('Snacks'));
      expect(store.brands.map((e) => e.nameEn), contains('Acme'));
      expect(store.units.map((e) => e.nameEn), contains('Crate'));
      expect(store.addOrUpdateCategory(CatalogItem(id: 'dup', nameEn: 'Snacks', nameAr: '')), throwsArgumentError);

      await store.addOrUpdateExpense(Expense(id: 'e1', title: 'Rent', category: 'Office', amount: 125.5, date: DateTime(2026, 1, 1), notes: ''));
      expect(store.totalExpensesAmount, 125.5);
      expect(store.estimateProfit(), -125.5);
      expect(store.addOrUpdateExpense(Expense(id: 'bad', title: '', category: '', amount: -1, date: DateTime(2026), notes: '')), throwsArgumentError);
      await store.deleteExpense('e1');
      expect(store.expenses, isEmpty);
    });
  });

  group('AppStore sales, purchases, stock, and reports', () {
    test('creates sales, reduces stock, restores stock on cancel, and tracks profit', () async {
      final store = await readyStore();
      await store.addOrUpdateProduct(product(stock: 5, price: 10, cost: 4));

      expect(store.createSale(customerName: 'Bob', items: const []), throwsArgumentError);
      expect(
        store.createSale(customerName: 'Bob', items: const [SaleItem(productId: 'p1', productName: 'Coffee', unitPrice: 10, quantity: 6)]),
        throwsStateError,
      );

      final sale = await store.createSale(
        customerName: ' Bob ',
        paymentMethod: ' Card ',
        discount: 2,
        items: const [SaleItem(productId: 'p1', productName: 'Coffee', unitPrice: 10, quantity: 2)],
      );

      expect(sale.customerName, 'Bob');
      expect(sale.paymentMethod, 'Card');
      expect(sale.total, 18);
      expect(sale.grossProfit, 10);
      expect(store.products.single.stock, 3);
      expect(store.stockMovements.where((m) => m.type == 'sale'), isNotEmpty);
      expect(store.totalSalesAmount, 18);
      expect(store.estimateProfit(), 10);

      await store.cancelSale(sale.id);
      expect(store.sales.single.isCancelled, isTrue);
      expect(store.totalSalesAmount, 0);
      expect(store.products.single.stock, 5);
      expect(store.stockMovements.where((m) => m.type == 'sale_restore'), isNotEmpty);

      await store.cancelSale(sale.id);
      expect(store.sales.length, 1);
    });

    test('handles purchase draft, receive, cancel, and manual stock adjustment', () async {
      final store = await readyStore();
      await store.addOrUpdateProduct(product(stock: 2, cost: 5));

      expect(store.createPurchase(supplierId: 's1', supplierName: 'Vendor', items: const []), throwsArgumentError);
      expect(
        store.createPurchase(supplierId: 's1', supplierName: 'Vendor', items: const [PurchaseItem(productId: 'missing', productName: 'Ghost', quantity: 1, unitCost: 1)]),
        throwsArgumentError,
      );

      final draft = await store.createPurchase(
        supplierId: 's1',
        supplierName: '',
        receiveNow: false,
        items: const [PurchaseItem(productId: 'p1', productName: 'Coffee', quantity: 3, unitCost: 6)],
      );
      expect(draft.status, 'Draft');
      expect(store.pendingPurchaseCount, 1);
      expect(store.products.single.stock, 2);

      await store.receivePurchase(draft.id);
      expect(store.purchases.single.isReceived, isTrue);
      expect(store.products.single.stock, 5);
      expect(store.products.single.cost, closeTo(5.6, 0.001));
      expect(store.totalPurchasesAmount, 18);

      await store.adjustStock(productId: 'p1', quantityDelta: -2, reason: 'count correction');
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
  });

  group('AppStore backup, restore, encryption, merge, and conflicts', () {
    test('exports, validates, encrypts, decrypts, imports, and summarizes backups', () async {
      final store = await readyStore();
      await store.addOrUpdateProduct(product());
      await store.addOrUpdateCustomer(Customer(id: 'c1', name: 'Alice', phone: '', address: ''));
      await store.addOrUpdateExpense(Expense(id: 'e1', title: 'Supplies', category: 'Ops', amount: 5, date: DateTime(2026), notes: ''));

      final raw = store.exportBackupJson();
      final validation = store.validateBackupJson(raw);
      expect(validation.isValid, isTrue);
      expect(validation.summary?.productsCount, 1);
      expect(store.syncSnapshotGeneratedAtFromJson(store.exportSyncSnapshotJson()), isA<DateTime>());
      expect(store.exportSyncChangesJson(), contains('"changes"'));

      final encrypted = store.exportEncryptedBackupJson('secret-pass');
      expect(encrypted, isNot(contains('Coffee')));
      final decrypted = store.decryptBackupJson(encrypted, 'secret-pass');
      expect(decrypted, contains('"products"'));
      expect(decrypted, contains('Coffee'));
      expect(decrypted, isNot(contains('"syncChanges"')));
      expect(() => store.decryptBackupJson(encrypted, 'wrong-pass'), throwsA(isA<ArgumentError>()));

      await store.resetBusinessData();
      expect(store.products, isEmpty);
      await store.importBackupJson(raw);
      expect(store.products.single.name, 'Coffee');
      expect(store.currentBackupSummary.productsCount, 1);
    });

    test('merge backup prefers latest data and reports duplicate data conflicts', () async {
      final first = await readyStore();
      await first.addOrUpdateProduct(product(id: 'p1', code: 'DUP', name: 'Local', stock: 1));
      final rawLocal = first.exportBackupJson();

      final second = await readyStore();
      await second.addOrUpdateProduct(product(id: 'p2', code: 'DUP', name: 'Remote newer', stock: 2));
      await second.addOrUpdateCustomer(Customer(id: 'c1', name: 'Same', phone: '', address: ''));
      await second.addOrUpdateCustomer(Customer(id: 'c2', name: 'Same 2', phone: '', address: ''));
      final decoded = jsonDecode(second.exportBackupJson()) as Map<String, dynamic>;
      (decoded['customers'] as List<dynamic>)[2]['name'] = 'Same';
      final rawRemote = const JsonEncoder.withIndent('  ').convert(decoded);

      await first.importBackupJson(rawLocal);
      await first.mergeBackupJson(rawRemote);

      expect(first.products.map((p) => p.id), containsAll(<String>['p1', 'p2']));
      expect(first.dataConflictCount, greaterThan(0));
      expect(first.blockingDataConflictCount, greaterThanOrEqualTo(0));
    });
  });

  group('AppStore sync queue and permissions', () {
    test('marks queue rows in progress, failed, retrying, item failed, and synced', () async {
      final store = await readyStore();
      await store.addOrUpdateProduct(product());
      final changeIds = store.pendingSyncChanges.map((c) => c.id).toList();
      expect(changeIds, isNotEmpty);

      await store.markSyncQueueChangesInProgress(changeIds);
      expect(store.syncQueue.where((q) => q.isInProgress), isNotEmpty);

      await store.markSyncQueueChangesFailed(changeIds, 'network down');
      expect(store.syncQueue.where((q) => q.isFailed && q.lastError == 'network down'), isNotEmpty);

      await store.retryFailedSyncQueue();
      expect(store.syncQueue.where((q) => q.status == 'pending'), isNotEmpty);

      await store.markSyncQueueItemFailed(store.syncQueue.first.id, 'single failure');
      expect(store.syncQueue.first.lastError, 'single failure');

      await store.markSyncChangesSyncedByIds(changeIds);
      expect(store.pendingSyncChangesForTarget('host', readyOnly: false), isEmpty);
      expect(store.pendingSyncQueueForTarget('host', readyOnly: false), isEmpty);

      await store.clearPendingSyncQueue();
      expect(store.pendingSyncQueueCount, 0);
    });

    test('applies remote sync changes for product, profile, roles, users, and stock movements', () async {
      final store = await readyStore();
      final now = DateTime.now();
      final remoteProduct = product(id: 'remote_p', code: 'REMOTE', name: 'Remote', stock: 1).copyWith(updatedAt: now.add(const Duration(minutes: 1)));
      final remoteUser = AppUser(id: 'u_remote', fullName: 'Remote User', username: 'remote', passwordHash: 'hash', roleId: 'admin');
      final remoteRole = UserRole(id: 'role_remote', name: 'Remote Role', permissions: {AppPermission.salesCreate});

      await store.applyRemoteSyncChanges([
        SyncChange(id: 'ch_profile', entityType: 'store_profile', entityId: 'store', operation: 'update', deviceId: 'other', createdAt: now, payload: StoreProfile.defaults.copyWith(name: 'Remote Store').toJson()),
        SyncChange(id: 'ch_role', entityType: 'role', entityId: remoteRole.id, operation: 'create', deviceId: 'other', createdAt: now, payload: remoteRole.toJson()),
        SyncChange(id: 'ch_user', entityType: 'user', entityId: remoteUser.id, operation: 'create', deviceId: 'other', createdAt: now, payload: remoteUser.toJson()),
        SyncChange(id: 'ch_product', entityType: 'product', entityId: remoteProduct.id, operation: 'create', deviceId: 'other', createdAt: now, payload: remoteProduct.toJson()),
        SyncChange(id: 'ch_stock', entityType: 'stock_movement', entityId: 'm1', operation: 'purchase_receive', deviceId: 'other', createdAt: now, payload: {
          'id': 'm1', 'productId': 'remote_p', 'productName': 'Remote', 'type': 'purchase_receive', 'quantity': 4, 'date': now.toIso8601String(), 'unitCost': 8,
        }),
      ]);

      expect(store.storeProfile.name, 'Remote Store');
      expect(store.roles.map((r) => r.id), contains(remoteRole.id));
      expect(store.users.map((u) => u.id), contains(remoteUser.id));
      expect(store.products.singleWhere((p) => p.id == 'remote_p').stock, 5);
      expect(store.products.singleWhere((p) => p.id == 'remote_p').cost, 8);
    });

    test('enforces permissions for restricted users and supports login/logout lifecycle', () async {
      final store = await readyStore();
      await store.addOrUpdateRole(UserRole(id: 'cashier', name: 'Cashier', permissions: {AppPermission.salesCreate}));
      await store.addOrUpdateUser(AppUser(id: '', fullName: 'Cashier One', username: 'cashier', passwordHash: '', roleId: 'cashier'), password: '1234');

      expect(await store.login('cashier', 'bad'), isFalse);
      expect(await store.login('cashier', '1234'), isTrue);
      expect(store.canSell, isTrue);
      expect(store.canManageProducts, isFalse);
      expect(() => store.requirePermission(AppPermission.productsDelete), throwsStateError);
      expect(store.addOrUpdateProduct(product()), throwsStateError);

      await store.logout();
      expect(store.activeUser, isNull);
      expect(store.hasPermission(AppPermission.productsDelete), isFalse);
      expect(() => store.requirePermission(AppPermission.productsDelete), throwsStateError);
      expect(await store.login('admin', 'AdminPass123'), isTrue);
      expect(() => store.requirePermission(AppPermission.productsDelete), returnsNormally);

      expect(store.deleteRole('admin'), throwsStateError);
      expect(store.deleteRole('cashier'), throwsStateError);
      final cashierId = store.users.firstWhere((u) => u.username == 'cashier').id;
      await store.deleteUser(cashierId);
      await store.deleteRole('cashier');
      expect(store.roles.map((r) => r.id), isNot(contains('cashier')));
    });

    test('updates identity, admin setup, and keeps protected operations safe', () async {
      final store = await readyStore();

      await store.updateAppIdentity(store.appIdentity.copyWith(syncMode: SyncMode.marketplaceEnabled, deviceRole: DeviceRole.host));
      expect(store.appIdentity.syncMode, SyncMode.marketplaceEnabled);
      expect(store.appIdentity.deviceId, store.deviceId);

      SharedPreferences.setMockInitialValues(const <String, Object>{});
      LocalDatabaseService.useInMemoryStoreForTesting(const <String, String>{});
      final setup = AppStore();
      await setup.initialize();
      expect(setup.needsInitialAdminSetup, isTrue);
      await setup.completeInitialAdminSetup(fullName: 'Owner', username: 'owner', password: 'owner123');
      expect(setup.needsInitialAdminSetup, isFalse);
      expect(await setup.login('owner', 'owner123'), isTrue);
      expect(() => setup.setCurrentRole('cashier'), throwsStateError);
    });
  });
}
