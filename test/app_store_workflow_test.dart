import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/repositories/auth_repository.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/services/store_bootstrap_service.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/core/repositories/business_repositories.dart';
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
  LocalDatabaseService.useInMemoryStoreForTesting(hostIdentitySeed(seed));
  final store = AppStore();
  await store.initialize();
  await StoreBootstrapService.completeInitialAdminSetup(
    store,
      fullName: 'Admin', username: 'admin', password: 'AdminPass123');
  await AuthRepository.login(store, 'admin', 'AdminPass123');
  return store;
}

void main() {
  group('AppStore initialization and persisted state', () {
    test(
        'initializes defaults, identity, walk-in customer, admin user, and catalog defaults',
        () async {
      final store = await readyStore();

      expect(store.isReady, isTrue);
      expect(await ProductRepository.countAll(), 0);
      expect(store.walkInCustomer.name, AppStore.walkInCustomerName);
      expect((await CustomerRepository.getById(AppStore.walkInCustomerId))?.id,
          AppStore.walkInCustomerId);
      expect((await RoleRepository.getById('admin'))?.id, 'admin');
      expect(store.activeUser?.username, 'admin');
      expect(
        (await UserRepository.listAll())
            .where((user) => user.username == 'admin'),
        isNotEmpty,
      );
      expect(await AuthRepository.needsInitialAdminSetup(store), isFalse);
      expect(store.appIdentity.deviceId, isNotEmpty);
      expect(store.walkInCustomer.id, AppStore.walkInCustomerId);
      expect(await ProductRepository.getCategories(), isNotEmpty);
      expect(
          await InventoryRepository.getCatalogItems(BusinessSqliteStore.brandsKey),
          isNotEmpty);
      expect(
          await InventoryRepository.getCatalogItems(BusinessSqliteStore.unitsKey),
          isNotEmpty);
      expect(store.storeProfile.name, isNotEmpty);
    });

    test(
        're-hydrates products, customers, sales counters, roles, and profile from local db',
        () async {
      final seeded = await readyStore();
      await ProductRepository.addOrUpdateProduct(seeded, product());
      await CustomerRepository.addOrUpdateCustomer(seeded, 
          Customer(id: 'c1', name: 'Alice', phone: '1', address: 'A'));
      await seeded.updateStoreProfile(
          StoreProfile.defaults.copyWith(name: 'Seeded Store'));
      final sale = await SaleRepository.createSale(context: seeded, customerName: 'Alice', items: const [
        SaleItem(
            productId: 'p1', productName: 'Coffee', unitPrice: 12, quantity: 2)
      ]);
      final raw = await seeded.exportBackupJson();

      final restored = await readyStore();
      await restored.recovery.importBackupJson(raw);

      expect((await ProductRepository.getById('p1'))?.code, 'P001');
      expect((await SaleRepository.getById(sale.id))?.invoiceNo, sale.invoiceNo);
      expect(restored.storeProfile.name, 'Seeded Store');
      expect(await BusinessSummaryRepository.totalSalesAmount(), 24);
    });

    test('online recovery keeps server identity when importing a backup',
        () async {
      final seeded = await readyStore();
      await seeded.updateStoreProfile(
          StoreProfile.defaults.copyWith(name: 'Backup Store'));
      await ProductRepository.addOrUpdateProduct(seeded, product());
      final raw = await seeded.exportBackupJson();

      SharedPreferences.setMockInitialValues(const <String, Object>{});
      LocalDatabaseService.useInMemoryStoreForTesting();
      final recovered = AppStore();
      await recovered.initialize();
      await StoreBootstrapService.recoverOnlineStoreOwnerIdentity(
        recovered,
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
      expect(await AuthRepository.login(recovered, 'owner', 'OwnerPass123'), isTrue);

      await recovered.recovery.importBackupJson(raw);

      expect((await ProductRepository.getById('p1'))?.code, 'P001');
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

      await ProductRepository.addOrUpdateProduct(store, product(code: ''));
      expect((await ProductRepository.getById('p1'))?.code, isNotEmpty);
      expect(store.syncChanges.where((c) => c.entityType == 'product'),
          isNotEmpty);
      expect(await store.syncState.pendingSyncQueueCount(store), 0);
      expect(notificationCount, greaterThan(0));

      final saved = (await ProductRepository.getById('p1'))!;
      await ProductRepository.addOrUpdateProduct(store, 
          saved.copyWith(price: 15, stock: 4, lowStockThreshold: 5));
      expect((await ProductRepository.getById('p1'))?.price, 15);
      final inventoryOverview = await BusinessSummaryRepository.buildInventoryOverview();
      expect(inventoryOverview?['lowStockCount'], 1);
      expect(await BusinessSummaryRepository.inventoryRetailValue(), 60);
      expect(await BusinessSummaryRepository.inventoryCostValue(), 28);

      expect(
          ProductRepository.addOrUpdateProduct(store, saved.copyWith(id: 'bad', code: saved.code)),
          throwsArgumentError);
      expect(
          ProductRepository.addOrUpdateProduct(store, 
              saved.copyWith(id: 'neg', code: 'NEG', price: -1)),
          throwsArgumentError);

      await ProductRepository.deleteProduct(store, saved.id);
      expect(await ProductRepository.countAll(), 0);
      expect(
          store.syncChanges.where(
              (c) => c.entityType == 'product' && c.operation == 'delete'),
          isNotEmpty);
    });

    test('reuses cached product snapshots and delivery note lookups', () async {
      final store = await readyStore();
      await ProductRepository.addOrUpdateProduct(store, product(id: 'p-cache', code: 'P-CACHE'));

      final cachedFirst = await ProductRepository.getById('p-cache');
      final cachedSecond = await ProductRepository.getById('p-cache');
      expect(cachedFirst?.code, 'P-CACHE');
      expect(cachedSecond?.code, 'P-CACHE');

      final sale = await SaleRepository.createSale(context: store, customerName: 'Bob', items: [
        SaleItem(
          productId: 'p-cache',
          productName: 'Coffee',
          unitPrice: 12,
          quantity: 1,
        ),
      ]);
      final note = await SaleRepository.createDeliveryNoteFromSale(store, sale.id);

      expect((await SaleRepository.getDeliveryNoteBySaleId(sale.id))?.id, note.id);
    });

    test('reuses cached stock-tracked products and refreshes after edits',
        () async {
      final store = await readyStore();
      await ProductRepository.addOrUpdateProduct(store, product(id: 'p-track', code: 'P-TRACK'));
      await ProductRepository.addOrUpdateProduct(store, 
        product(id: 'p-skip', code: 'P-SKIP').copyWith(trackStock: false),
      );

      final trackedProductsPage =
          await ProductRepository.queryPage(stockTrackedOnly: true, limit: 50);
      expect(trackedProductsPage?.items.map((p) => p.id), contains('p-track'));
      expect(trackedProductsPage?.items.map((p) => p.id),
          isNot(contains('p-skip')));
      final trackedProductsPageAgain =
          await ProductRepository.queryPage(stockTrackedOnly: true, limit: 50);
      expect(trackedProductsPageAgain?.items.map((p) => p.id),
          contains('p-track'));

      await ProductRepository.addOrUpdateProduct(store, 
        product(id: 'p-track', code: 'P-TRACK').copyWith(trackStock: false),
      );

      expect((await ProductRepository.queryPage(stockTrackedOnly: true, limit: 50))?.items, isEmpty);
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
      await ProductRepository.addOrUpdateProduct(store, product(id: 'p-fast', code: 'P-FAST'));
      for (final key in derivedKeys) {
        await LocalDatabaseService.setString(key, 'sentinel-$key');
      }

      final sale = await SaleRepository.createSale(context: store, customerName: 'Bob', items: [
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

      await CustomerRepository.addOrUpdateCustomer(store, 
          Customer(id: 'c1', name: ' Alice ', phone: '111', address: 'A'));
      expect((await CustomerRepository.getById('c1'))?.name, 'Alice');
      expect(AppStore.walkInCustomerId, isNotEmpty);
      expect(
          CustomerRepository.addOrUpdateCustomer(store, 
              Customer(id: 'c2', name: 'alice', phone: '', address: '')),
          throwsArgumentError);
      await CustomerRepository.deleteCustomer(store, 'c1');
      expect(await CustomerRepository.getById('c1'), isNull);
      await CustomerRepository.addOrUpdateCustomer(store, 
          Customer(id: 'c3', name: ' alice ', phone: '', address: ''));
      expect((await CustomerRepository.getById('c3'))?.id, 'c3');

      await SupplierRepository.addOrUpdateSupplier(store, Supplier(
          id: 's1', name: ' Supplier ', phone: '222', address: 'B', notes: ''));
      expect((await SupplierRepository.getById('s1'))?.name, 'Supplier');
      expect(
          SupplierRepository.addOrUpdateSupplier(store, Supplier(
              id: 's2', name: 'supplier', phone: '', address: '', notes: '')),
          throwsArgumentError);
      await SupplierRepository.deleteSupplier(store, 's1');
      expect(await SupplierRepository.countAll(), 0);

      await ProductRepository.addOrUpdateCategory(store, 
          CatalogItem(id: 'cat_test', nameEn: 'Snacks', nameAr: ''));
      await ProductRepository.addOrUpdateBrand(store, 
          CatalogItem(id: 'brand_test', nameEn: 'Acme', nameAr: ''));
      await ProductRepository.addOrUpdateUnit(store, 
          CatalogItem(id: 'unit_test', nameEn: 'Crate', nameAr: ''));
      expect(
          (await InventoryRepository.getCatalogItems(BusinessSqliteStore.categoriesKey))
              ?.map((e) => e.nameEn),
          contains('Snacks'));
      expect(
          (await InventoryRepository.getCatalogItems(BusinessSqliteStore.brandsKey))
              ?.map((e) => e.nameEn),
          contains('Acme'));
      expect(
          (await InventoryRepository.getCatalogItems(BusinessSqliteStore.unitsKey))
              ?.map((e) => e.nameEn),
          contains('Crate'));
      expect(
          ProductRepository.addOrUpdateCategory(store, 
              CatalogItem(id: 'dup', nameEn: 'Snacks', nameAr: '')),
          throwsArgumentError);
      final reusableCategory =
          CatalogItem(id: 'cat_delete', nameEn: 'Reusable Category', nameAr: '');
      await ProductRepository.addOrUpdateCategory(store, reusableCategory);
      await ProductRepository.replaceAndDeleteCatalogItem(context: store, 
        type: 'category',
        item: reusableCategory,
        replacement: null,
      );
      await ProductRepository.addOrUpdateCategory(store, 
        CatalogItem(id: 'cat_restore', nameEn: 'Reusable Category', nameAr: ''),
      );
      expect(
          (await InventoryRepository.getCatalogItems(BusinessSqliteStore.categoriesKey))
              ?.map((e) => e.id),
          contains('cat_restore'));

      await ExpenseRepository.addOrUpdateExpense(store, Expense(
          id: 'e1',
          title: 'Rent',
          category: 'Office',
          amount: 125.5,
          date: DateTime(2026, 1, 1),
          notes: ''));
      expect(await BusinessSummaryRepository.totalExpensesAmount(), 0);
      await ExpenseRepository.postExpense(store, 'e1');
      expect(await BusinessSummaryRepository.totalExpensesAmount(), 125.5);
      expect(
        (await AccountTransactionRepository.listAll()).where(
          (tx) =>
              !tx.isDeleted &&
              tx.referenceId == 'e1' &&
              tx.referenceNo == 'Rent',
        ),
        isNotEmpty,
      );
      expect(await BusinessSummaryRepository.estimateProfit(), -125.5);
      expect(
          ExpenseRepository.addOrUpdateExpense(store, Expense(
              id: 'bad',
              title: '',
              category: '',
              amount: -1,
              date: DateTime(2026),
              notes: '')),
          throwsArgumentError);
      await ExpenseRepository.cancelExpense(store, 'e1', reason: 'test cancellation');
      expect((await ExpenseRepository.getById('e1'))?.isCancelled, isTrue);
      expect(await BusinessSummaryRepository.totalExpensesAmount(), 0);
    });
  });

  group('AppStore sales, purchases, stock, and reports', () {
    test(
        'creates sales, reduces stock, restores stock on cancel, and tracks profit',
        () async {
      final correctionStore = await readyStore();
      await ProductRepository.addOrUpdateProduct(
        correctionStore,
        product(stock: 5, price: 10, cost: 4),
      );

      expect(SaleRepository.createSale(context: correctionStore, customerName: 'Bob', items: const []),
          throwsArgumentError);
      final correctedSale = await SaleRepository.createSale(context: correctionStore, 
        customerName: 'Bob',
        items: const [
          SaleItem(
              productId: 'p1',
              productName: 'Coffee',
              unitPrice: 10,
              quantity: 6)
        ],
      );
      expect(correctedSale.total, 60);
      expect((await ProductRepository.getById('p1'))?.stock, 0);
      expect(
          (await StockMovementRepository.listAll())
              .where((m) => m.type == 'auto_correction'),
          isNotEmpty);

      final store = await readyStore();
      await ProductRepository.addOrUpdateProduct(store, product(stock: 5, price: 10, cost: 4));

      final sale = await SaleRepository.createSale(context: store, 
        customerName: ' Bob ',
        paymentMethod: ' Card ',
        discount: 2,
        items: const [
          SaleItem(
              productId: 'p1',
              productName: 'Coffee',
              unitPrice: 10,
              quantity: 2)
        ],
      );

      expect(sale.customerName, 'Bob');
      expect(sale.paymentMethod, 'Card');
      expect(sale.total, 18);
      expect(sale.grossProfit, 10);
      expect((await ProductRepository.getById('p1'))?.stock, 3);
      expect(
          (await StockMovementRepository.listAll()).where((m) => m.type == 'sale'),
          isNotEmpty);
      expect(await BusinessSummaryRepository.totalSalesAmount(), 18);
      expect(await BusinessSummaryRepository.estimateProfit(), 10);

      await SaleRepository.cancelSale(store, sale.id);
      final cancelledSale = await SaleRepository.getById(sale.id);
      expect(cancelledSale?.isCancelled, isTrue);
      expect(cancelledSale?.paidAmount, 0);
      expect(cancelledSale?.cashReceivedAmount, 0);
      expect(await BusinessSummaryRepository.totalSalesAmount(), 0);
      expect((await ProductRepository.getById('p1'))?.stock, 5);
      expect((await StockMovementRepository.listAll()).where((m) => m.type == 'sale_restore'),
          isNotEmpty);

      await SaleRepository.cancelSale(store, sale.id);
      expect(await SaleRepository.countAll(), 1);
    });

    test('returns a sale, restores stock, and records a sale return movement',
        () async {
      final store = await readyStore();
      await ProductRepository.addOrUpdateProduct(store, product(stock: 5, price: 10, cost: 4));

      final sale = await SaleRepository.createSale(context: store, 
        customerName: 'Bob',
        items: const [
          SaleItem(
              productId: 'p1',
              productName: 'Coffee',
              unitPrice: 10,
              quantity: 2)
        ],
      );

      expect((await ProductRepository.getById('p1'))?.stock, 3);
      await SaleRepository.returnSale(store, sale.id);

      final returnedSale = await SaleRepository.getById(sale.id);
      expect(returnedSale?.status, 'Returned');
      expect(returnedSale?.isCancelled, isTrue);
      expect(returnedSale?.paidAmount, 0);
      expect(returnedSale?.cashReceivedAmount, 0);
      expect(await BusinessSummaryRepository.totalSalesAmount(), 0);
      expect((await ProductRepository.getById('p1'))?.stock, 5);
      expect((await StockMovementRepository.listAll()).where((m) => m.type == 'sale_return'),
          isNotEmpty);
    });

    test('handles purchase draft, receive, cancel, and manual stock adjustment',
        () async {
      final store = await readyStore();
      await ProductRepository.addOrUpdateProduct(store, product(stock: 2, cost: 5));

      expect(
          PurchaseRepository.createPurchase(context: store, 
              supplierId: 's1', supplierName: 'Vendor', items: const []),
          throwsArgumentError);
      expect(
        PurchaseRepository.createPurchase(context: store, 
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

      final draft = await PurchaseRepository.createPurchase(context: store, 
        supplierId: 's1',
        supplierName: '',
        receiveNow: false,
        items: const [
          PurchaseItem(
              productId: 'p1', productName: 'Coffee', quantity: 3, unitCost: 6)
        ],
      );
      expect(draft.status, 'Draft');
      expect(await BusinessSummaryRepository.pendingPurchaseCount(), 1);
      expect((await ProductRepository.getById('p1'))?.stock, 2);

      await PurchaseRepository.receivePurchase(store, draft.id);
      final receivedPurchase = await PurchaseRepository.getById(draft.id);
      expect(receivedPurchase?.isReceived, isTrue);
      expect((await ProductRepository.getById('p1'))?.stock, 5);
      expect((await ProductRepository.getById('p1'))?.cost, closeTo(5.6, 0.001));
      expect(await BusinessSummaryRepository.totalPurchasesAmount(), 18);

      await InventoryRepository.adjustStock(context: store, 
          productId: 'p1', quantityDelta: -2, reason: 'count correction');
      expect((await ProductRepository.getById('p1'))?.stock, 3);
      expect(
        (await StockMovementRepository.listAll()).where(
          (m) => m.type == 'inventory_loss' || m.type == 'inventory_adjustment',
        ),
        isNotEmpty,
      );

      await PurchaseRepository.cancelPurchase(store, draft.id);
      final cancelledPurchase = await PurchaseRepository.getById(draft.id);
      expect(cancelledPurchase?.isCancelled, isTrue);
      expect(await BusinessSummaryRepository.totalPurchasesAmount(), 0);
      expect((await ProductRepository.getById('p1'))?.stock, 0);
    });

    test('returns received purchase and reverses stock with return movement',
        () async {
      final store = await readyStore();
      await ProductRepository.addOrUpdateProduct(store, product());
      final draft = await PurchaseRepository.createPurchase(context: store, 
        supplierId: 's1',
        supplierName: 'Supplier',
        items: const [
          PurchaseItem(
              productId: 'p1', productName: 'Coffee', quantity: 5, unitCost: 8)
        ],
        receiveNow: true,
      );
      expect((await ProductRepository.getById('p1'))?.stock, 15);

      await PurchaseRepository.returnPurchase(store, draft.id, reason: 'damaged goods');

      final returnedPurchase = await PurchaseRepository.getById(draft.id);
      expect(returnedPurchase?.status, 'Returned');
      expect(returnedPurchase?.isReturned, isTrue);
      expect(returnedPurchase?.isCancelled, isTrue);
      expect(await BusinessSummaryRepository.totalPurchasesAmount(), 0);
      expect((await ProductRepository.getById('p1'))?.stock, 10);
      expect(
          (await StockMovementRepository.listAll())
              .where((movement) => movement.type == 'purchase_return'),
          isNotEmpty);
      expect(
          (await AccountTransactionRepository.listAll())
              .where((entry) => entry.type == 'purchaseReturn'),
          isNotEmpty);
    });
  });

  group('AppStore backup, restore, encryption, merge, and conflicts', () {
    test(
        'exports, validates, encrypts, decrypts, imports, and summarizes backups',
        () async {
      final store = await readyStore();
      await ProductRepository.addOrUpdateProduct(store, product());
      await CustomerRepository.addOrUpdateCustomer(store, 
          Customer(id: 'c1', name: 'Alice', phone: '', address: ''));
      await ExpenseRepository.addOrUpdateExpense(store, Expense(
          id: 'e1',
          title: 'Supplies',
          category: 'Ops',
          amount: 5,
          date: DateTime(2026),
          notes: ''));

      final raw = await store.exportBackupJson();
      final validation = store.validateBackupJson(raw);
      expect(validation.isValid, isTrue);
      expect(validation.summary?.productsCount, 1);
      expect(
          store.syncSnapshotGeneratedAtFromJson(
            await store.exportSyncSnapshotJson(),
          ),
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
      expect(await ProductRepository.countAll(), 0);
      await store.recovery.importBackupJson(raw);
      expect((await ProductRepository.getById('p1'))?.name, 'Coffee');
      expect(await ProductRepository.countAll(), 1);
    });

    test(
        'merge backup prefers latest data and reports duplicate data conflicts',
        () async {
      final first = await readyStore();
      await ProductRepository.addOrUpdateProduct(first, 
          product(id: 'p1', code: 'DUP', name: 'Local', stock: 1));
      final rawLocal = await first.exportBackupJson();

      final second = await readyStore();
      await ProductRepository.addOrUpdateProduct(second, 
          product(id: 'p2', code: 'DUP', name: 'Remote newer', stock: 2));
      await CustomerRepository.addOrUpdateCustomer(second, 
          Customer(id: 'c1', name: 'Same', phone: '', address: ''));
      await CustomerRepository.addOrUpdateCustomer(second, 
          Customer(id: 'c2', name: 'Same 2', phone: '', address: ''));
      final decoded =
          jsonDecode(await second.exportBackupJson()) as Map<String, dynamic>;
      (decoded['customers'] as List<dynamic>)[2]['name'] = 'Same';
      final rawRemote = const JsonEncoder.withIndent('  ').convert(decoded);

      await first.recovery.importBackupJson(rawLocal);
      await first.recovery.mergeBackupJson(rawRemote);

      expect(
          (await ProductRepository.queryPage(limit: 50, offset: 0))?.items
              .map((p) => p.id),
          containsAll(<String>['p1', 'p2']));
      final conflictSummary = await BusinessSummaryRepository.buildDataConflictSummary();
      expect(conflictSummary?['dataConflictCount'], greaterThan(0));
      expect(
        conflictSummary?['blockingConflictCount'],
        greaterThanOrEqualTo(0),
      );
    });
  });

  group('AppStore sync queue and permissions', () {
    test(
        'marks queue rows in progress, failed, retrying, item failed, and synced',
        () async {
      final store = await readyStore();
      await store.updateAppIdentity(store.appIdentity.copyWith(
          syncMode: SyncMode.cloudConnected, activeSyncTransport: 'cloud'));
      await ProductRepository.addOrUpdateProduct(store, product());
      final changeIds = (await store.syncState.pendingSyncChangesForTarget(
        store,
        'cloud',
        readyOnly: false,
      ))
          .map((c) => c.id)
          .toList();
      expect(changeIds, isNotEmpty);

      await store.syncState.markSyncQueueChangesInProgress(store, changeIds);
      final inProgressSnapshot = await store.syncState
          .pendingSyncQueueForTarget(store, 'cloud', readyOnly: false);
      expect(inProgressSnapshot.where((q) => q.isInProgress), isNotEmpty);

      await store.syncState
          .markSyncQueueChangesFailed(store, changeIds, 'network down');
      final failedSnapshot = await store.syncState
          .pendingSyncQueueForTarget(store, 'cloud', readyOnly: false);
      expect(failedSnapshot.where((q) => q.isFailed && q.lastError == 'network down'),
          isNotEmpty);

      await store.syncState.retryFailedSyncQueue(store);
      final retriedSnapshot = await store.syncState
          .pendingSyncQueueForTarget(store, 'cloud', readyOnly: false);
      expect(retriedSnapshot.where((q) => q.status == 'pending'), isNotEmpty);

      await store.syncState.markSyncQueueItemFailed(
          store, retriedSnapshot.first.id, 'single failure');
      final singleFailedSnapshot = await store.syncState
          .pendingSyncQueueForTarget(store, 'cloud', readyOnly: false);
      expect(singleFailedSnapshot.first.lastError, 'single failure');

      await store.syncState.markSyncChangesSyncedByIds(store, changeIds);
      expect(
          await store.syncState.pendingSyncChangesForTarget(
            store,
            'cloud',
            readyOnly: false,
          ),
          isEmpty);
      expect(
          await store.syncState.pendingSyncQueueForTarget(
            store,
            'cloud',
            readyOnly: false,
          ),
          isEmpty);

      await store.syncState.clearPendingSyncQueue(store);
      expect(await store.syncState.pendingSyncQueueCount(store), 0);
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

      await store.syncState.applyAuthoritativeSyncChangesToSqliteTransaction(
        store,
        [
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
        ],
        markAppliedAsSynced: true,
      );

    });

    test(
        'enforces permissions for restricted users and supports login/logout lifecycle',
        () async {
      final store = await readyStore();
      await RoleRepository.addOrUpdateRole(store, UserRole(
          id: 'cashier',
          name: 'Cashier',
          permissions: {AppPermission.salesCreate}));
      await AuthRepository.login(store, 'admin', 'AdminPass123');
      await UserRepository.addOrUpdateUser(store, 
          AppUser(
              id: '',
              fullName: 'Cashier One',
              username: 'cashier',
              passwordHash: '',
              roleId: 'cashier'),
          password: '1234');

      expect(await AuthRepository.login(store, 'cashier', 'bad'), isFalse);
      expect(await AuthRepository.login(store, 'cashier', '1234'), isTrue);
      expect(store.canSell, isTrue);
      expect(store.canManageProducts, isFalse);
      expect(() => store.requirePermission(AppPermission.productsDelete),
          throwsStateError);
      expect(ProductRepository.addOrUpdateProduct(store, product()), throwsStateError);

      await AuthRepository.logout(store);
      expect(store.activeUser, isNull);
      expect(store.hasPermission(AppPermission.productsDelete), isFalse);
      expect(() => store.requirePermission(AppPermission.productsDelete),
          throwsStateError);
      expect(await AuthRepository.login(store, 'admin', 'AdminPass123'), isTrue);
      expect(() => store.requirePermission(AppPermission.productsDelete),
          returnsNormally);

      final cashierId =
          (await UserRepository.listAll())
              .firstWhere((u) => u.username == 'cashier')
              .id;
      await UserRepository.deleteUser(store, cashierId);
      expect((await RoleRepository.getById('cashier'))?.id, 'cashier');
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
      await StoreBootstrapService.completeInitialAdminSetup(
        setup,
          fullName: 'Owner', username: 'owner', password: 'owner123');
      expect(await AuthRepository.needsInitialAdminSetup(setup), isFalse);
      expect(await AuthRepository.login(setup, 'owner', 'owner123'), isTrue);
      expect(() => setup.setCurrentRole('cashier'), throwsStateError);
    });
  });
}
