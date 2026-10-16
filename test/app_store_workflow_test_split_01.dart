part of 'app_store_workflow_test.dart';

void _registerAppStoreWorkflowGroup1() {
  group('AppStore initialization and persisted state', () {
    tearDown(LocalDatabaseService.clearInMemoryStoreForTesting);
    test(
        'initializes defaults, identity, walk-in customer, admin user, and catalog defaults',
        () async {
      final store = await readySqliteStore(storeId: 'ST-EXPENSE-WORKFLOW');

      expect(store.runtime.isReady, isTrue);
      expect(store.catalog.products, isEmpty);
      expect(store.commerce.walkInCustomer.name, AppStore.walkInCustomerName);
      expect(store.commerce.customers.map((c) => c.id),
          contains(AppStore.walkInCustomerId));
      expect(store.commerce.customers.map((c) => c.id),
          contains(AppStore.walkInCustomerId));
      expect(store.security.roles.map((r) => r.id), contains('admin'));
      expect(store.security.users.map((u) => u.username), contains('owner'));
      expect(store.security.needsInitialAdminSetup, isFalse);
      expect(store.runtime.identity.deviceId, isNotEmpty);
      expect(store.catalog.categories, isNotEmpty);
      expect(store.catalog.brands, isNotEmpty);
      expect(store.catalog.units, isNotEmpty);
      expect(store.recovery.currentBackupSummary.storeName, isNotEmpty);
      expect(store.security.activeUser, store.security.activeUser);
      expect(store.security.currentRole, store.security.currentRole);
      expect(
        store.security.hasPermission(AppPermission.settingsManage),
        store.security.hasPermission(AppPermission.settingsManage),
      );
      expect(store.accounting.transactions, store.accounting.transactions);
      expect(
        store.accounting.accountBalance('customer', AppStore.walkInCustomerId),
        store.accounting.accountBalance('customer', AppStore.walkInCustomerId),
      );
      expect(store.inventory.warehouses, store.inventory.warehouses);
      expect(store.inventory.stockMovements, store.inventory.stockMovements);
      expect(store.inventory.revision, store.inventory.revision);
      expect(store.sync.changes, store.sync.changes);
      expect(store.sync.queue, store.sync.queue);
      expect(store.sync.sequence, store.sync.sequence);
    });

    test(
        're-hydrates products, customers, sales counters, roles, and profile from local db',
        () async {
      final seeded = await readySqliteStore(storeId: 'ST-REHYDRATE01');
      await seeded.catalog.addOrUpdateProduct(product());
      await seeded.commerce.addOrUpdateCustomer(
          Customer(id: 'c1', name: 'Alice', phone: '1', address: 'A'));
      await seeded.runtime.updateStoreProfile(
          StoreProfile.defaults.copyWith(name: 'Seeded Store'));
      final seedStockService = StockTransactionService(
        SqliteMigrationManager.database!,
        defaultStoreId: seeded.runtime.identity.storeId,
        defaultBranchId: seeded.runtime.identity.branchId,
      );
      await seedStockService.applyDelta(
        storeId: seeded.runtime.identity.storeId,
        warehouseId: Warehouse.defaultId,
        productId: 'p1',
        delta: 2,
        branchId: seeded.runtime.identity.branchId,
      );
      expect(await seeded.security.login('owner', 'OwnerPass123'), isTrue);
      await seeded.commerce.createSale(
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
      final raw = await seeded.recovery.exportBackupJson();

      final restored = await readySqliteStore(storeId: 'ST-REHYDRATE01');
      await restored.recovery.importBackupJson(raw);
      await restored.runtime.reloadAllAfterDatabaseChange();

      expect(restored.runtime.profile.name, 'Seeded Store');
    });

    test('imports legacy sales without warehouse fields as main warehouse',
        () async {
      final store = await readySqliteStore(storeId: 'ST-LEGACY01');
      await store.catalog.addOrUpdateProduct(product(id: 'p-legacy', stock: 0));
      final stockService = StockTransactionService(
        SqliteMigrationManager.database!,
        defaultStoreId: store.runtime.identity.storeId,
        defaultBranchId: store.runtime.identity.branchId,
      );
      await stockService.applyDelta(
        storeId: store.runtime.identity.storeId,
        warehouseId: Warehouse.defaultId,
        productId: 'p-legacy',
        delta: 5,
        branchId: store.runtime.identity.branchId,
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
            Variable<String>(store.runtime.identity.storeId),
            Variable<String>(store.runtime.identity.branchId),
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
      await seeded.runtime.updateStoreProfile(
          StoreProfile.defaults.copyWith(name: 'Backup Store'));
      await seeded.catalog.addOrUpdateProduct(product());
      expect(await seeded.security.login('admin', 'AdminPass123'), isTrue);
      final raw = await seeded.recovery.exportBackupJson();

      SharedPreferences.setMockInitialValues(const <String, Object>{});
      LocalDatabaseService.useInMemoryStoreForTesting();
      final recovered = AppStore();
      await recovered.runtime.initialize();
      await recovered.security.recoverOnlineStoreOwnerIdentity(
        storeId: 'ST-DIRECT1',
        branchId: 'BR-DIRECT1',
        storeName: 'Server Store',
        username: 'owner',
        password: 'OwnerPass123',
      );

      expect(recovered.runtime.identity.storeId, 'ST-DIRECT1');
      expect(recovered.runtime.identity.branchId, 'BR-DIRECT1');
      expect(recovered.runtime.identity.deviceRole, DeviceRole.host);
      expect(recovered.runtime.identity.syncMode, SyncMode.localOnly);
      expect(recovered.runtime.identity.activeSyncTransport, isEmpty);
      expect(recovered.security.activeUser?.username, 'owner');
      expect(await recovered.security.login('owner', 'OwnerPass123'), isTrue);

      await recovered.recovery.importBackupJson(raw);

      expect(recovered.catalog.products.single.code, 'P001');
      expect(recovered.runtime.profile.name, 'Backup Store');
      expect(recovered.runtime.identity.storeId, 'ST-DIRECT1');
      expect(recovered.runtime.identity.branchId, 'BR-DIRECT1');
      expect(recovered.runtime.identity.deviceRole, DeviceRole.host);
    });

    test('registration provisions owner without activating a session',
        () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      LocalDatabaseService.useInMemoryStoreForTesting();
      final store = AppStore();
      await store.runtime.initialize();

      await store.security.recoverOnlineStoreOwnerIdentity(
        storeId: 'ST-REG001',
        branchId: 'BR-REG001',
        storeName: 'Registered Store',
        username: 'owner',
        password: 'OwnerPass123',
        activateUser: false,
      );

      expect(store.security.hasLocalAdminUser, isTrue);
      expect(store.security.activeUser, null);
      expect(await store.security.login('owner', 'OwnerPass123'), isTrue);
    });
  });
}

void _registerAppStoreWorkflowGroup2() {
  group('AppStore product, customer, supplier, catalog, and expense workflows',
      () {
    test('creates, updates, deletes, syncs, and validates products', () async {
      final store = await readySqliteStore(storeId: 'ST-EXPENSE-WORKFLOW');
      var notificationCount = 0;
      store.addListener(() => notificationCount++);

      await store.catalog.addOrUpdateProduct(product(code: '', stock: 0));
      expect(store.catalog.products.single.code, isNotEmpty);
      expect(store.sync.changes.where((c) => c.entityType == 'product'),
          isNotEmpty);
      expect(store.sync.pendingQueue.length, 0);
      expect(notificationCount, greaterThan(0));

      final saved = store.catalog.products.single;
      await store.catalog
          .addOrUpdateProduct(saved.copyWith(price: 15, lowStockThreshold: 5));
      await store.inventory.adjustStock(
        productId: saved.id,
        warehouseId: Warehouse.defaultId,
        quantityDelta: 4,
        reason: 'workflow stock seed',
      );
      expect(store.catalog.products.single.price, 15);
      expect(store.inventory.lowStockCount, 1);
      expect(store.inventory.inventoryRetailValue, 60);
      expect(store.inventory.inventoryCostValue, 28);

      expect(
          store.catalog
              .addOrUpdateProduct(saved.copyWith(id: 'bad', code: saved.code)),
          throwsArgumentError);
      expect(
          store.catalog.addOrUpdateProduct(
              saved.copyWith(id: 'neg', code: 'NEG', price: -1)),
          throwsArgumentError);

      await expectLater(
          store.catalog.deleteProduct(saved.id), throwsStateError);
      await store.catalog.addOrUpdateProduct(
        product(id: 'delete-me', code: 'DELETE-ME', stock: 0),
      );
      await store.catalog.deleteProduct('delete-me');
      expect(store.catalog.products.map((item) => item.id),
          isNot(contains('delete-me')));
      expect(
          store.sync.changes.where(
              (c) => c.entityType == 'product' && c.operation == 'delete'),
          isNotEmpty);
    });

    test('reuses cached product snapshots and delivery note lookups', () async {
      final store = await readySqliteStore(storeId: 'ST-CACHE01');
      await store.catalog.addOrUpdateProduct(
          product(id: 'p-cache', code: 'P-CACHE', stock: 0));
      await store.inventory.adjustStock(
          productId: 'p-cache',
          warehouseId: Warehouse.defaultId,
          quantityDelta: 10,
          reason: 'test seed');

      expect(identical(store.catalog.products, store.catalog.products), isTrue);
      expect(store.catalog.productById('p-cache')?.code, 'P-CACHE');
      expect(identical(store.catalog.products, store.catalog.products), isTrue);
      expect(store.catalog.productById('p-cache')?.code, 'P-CACHE');
      expect(store.catalog.categories, store.catalog.categories);
      expect(store.catalog.brands, store.catalog.brands);
      expect(store.catalog.units, store.catalog.units);

      final sale = await store.commerce.createSale(
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
      final note = await store.commerce.createDeliveryNoteFromSale(sale.id);

      expect(store.commerce.deliveryNoteForSale(sale.id)?.id, note.id);
    });

    test('reuses cached stock-tracked products and refreshes after edits',
        () async {
      final store = await readyStore();
      await store.catalog
          .addOrUpdateProduct(product(id: 'p-track', code: 'P-TRACK'));
      await store.catalog.addOrUpdateProduct(
        product(id: 'p-skip', code: 'P-SKIP').copyWith(trackStock: false),
      );

      expect(store.catalog.stockTrackedProducts.map((p) => p.id),
          contains('p-track'));
      expect(store.catalog.stockTrackedProducts.map((p) => p.id),
          isNot(contains('p-skip')));
      expect(
          identical(store.catalog.stockTrackedProducts,
              store.catalog.stockTrackedProducts),
          isTrue);

      await store.catalog.addOrUpdateProduct(
        product(id: 'p-track', code: 'P-TRACK').copyWith(trackStock: false),
      );

      expect(store.catalog.stockTrackedProducts, isEmpty);
    });

    test('sale saves through typed SQLite without legacy derived payloads',
        () async {
      final store = await readySqliteStore(storeId: 'ST-FAST001');
      await store.catalog
          .addOrUpdateProduct(product(id: 'p-fast', code: 'P-FAST', stock: 0));
      await store.inventory.adjustStock(
          productId: 'p-fast',
          warehouseId: Warehouse.defaultId,
          quantityDelta: 10,
          reason: 'test seed');
      final sale = await store.commerce.createSale(
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

      await store.commerce.addOrUpdateCustomer(
          Customer(id: 'c1', name: ' Alice ', phone: '111', address: 'A'));
      expect(store.commerce.resolveCustomerName('c1'), 'Alice');
      expect(store.commerce.sanitizeSelectedCustomerId('missing'),
          AppStore.walkInCustomerId);
      expect(
          store.commerce.addOrUpdateCustomer(
              Customer(id: 'c2', name: 'alice', phone: '', address: '')),
          throwsArgumentError);
      await store.commerce.deleteCustomer('c1');
      expect(store.commerce.customers.map((c) => c.id), isNot(contains('c1')));
      expect(store.commerce.customers, store.commerce.customers);
      expect(store.commerce.resolveCustomerName('c1'),
          AppStore.walkInCustomerName);
      expect(store.commerce.sanitizeSelectedCustomerId('c1'),
          AppStore.walkInCustomerId);
      await store.commerce.addOrUpdateCustomer(
          Customer(id: 'c3', name: ' alice ', phone: '', address: ''));
      expect(store.commerce.customers.map((c) => c.id), contains('c3'));

      await store.commerce.addOrUpdateSupplier(Supplier(
          id: 's1', name: ' Supplier ', phone: '222', address: 'B', notes: ''));
      expect(store.commerce.suppliers.single.name, 'Supplier');
      expect(
          store.commerce.addOrUpdateSupplier(Supplier(
              id: 's2', name: 'supplier', phone: '', address: '', notes: '')),
          throwsArgumentError);
      await store.commerce.deleteSupplier('s1');
      expect(store.commerce.suppliers, isEmpty);
      expect(store.commerce.suppliers, store.commerce.suppliers);

      await store.catalog.addOrUpdateCategory(
          CatalogItem(id: 'cat_test', nameEn: 'Snacks', nameAr: ''));
      await store.catalog.addOrUpdateBrand(
          CatalogItem(id: 'brand_test', nameEn: 'Acme', nameAr: ''));
      await store.catalog.addOrUpdateUnit(
          CatalogItem(id: 'unit_test', nameEn: 'Crate', nameAr: ''));
      expect(store.catalog.categories.map((e) => e.nameEn), contains('Snacks'));
      expect(store.catalog.brands.map((e) => e.nameEn), contains('Acme'));
      expect(store.catalog.units.map((e) => e.nameEn), contains('Crate'));
      expect(
          store.catalog.addOrUpdateCategory(
              CatalogItem(id: 'dup', nameEn: 'Snacks', nameAr: '')),
          throwsArgumentError);
      final reusableCategory = CatalogItem(
          id: 'cat_delete', nameEn: 'Reusable Category', nameAr: '');
      await store.catalog.addOrUpdateCategory(reusableCategory);
      await store.catalog.replaceAndDeleteCatalogItem(
        type: 'category',
        item: reusableCategory,
        replacement: null,
      );
      await store.catalog.addOrUpdateCategory(
        CatalogItem(id: 'cat_restore', nameEn: 'Reusable Category', nameAr: ''),
      );
      expect(
          store.catalog.categories.map((e) => e.id), contains('cat_restore'));

      await store.commerce.addOrUpdateExpense(Expense(
          id: 'e1',
          title: 'Rent',
          category: 'Office',
          amount: 125.5,
          date: DateTime(2026, 1, 1),
          notes: ''));
      expect(store.commerce.totalExpensesAmount, 0);
      await store.commerce.postExpense('e1', paidInCash: false);
      expect(store.commerce.totalExpensesAmount, 125.5);
      final expenseJournal = await SqliteMigrationManager.database!
          .customSelect(
            "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'expense' AND reference_id = 'e1' AND status = 'posted'",
          )
          .getSingle();
      expect(expenseJournal.read<int>('c'), 1);
      expect(store.commerce.estimateProfit(), -125.5);
      expect(
          store.commerce.addOrUpdateExpense(Expense(
              id: 'bad',
              title: '',
              category: '',
              amount: -1,
              date: DateTime(2026),
              notes: '')),
          throwsArgumentError);
      await store.commerce.cancelExpense('e1', reason: 'test cancellation');
      expect(store.commerce.expenses.single.isCancelled, isTrue);
      expect(store.commerce.expenses, store.commerce.expenses);
      expect(store.commerce.totalExpensesAmount, 0);
    });
  });
}
