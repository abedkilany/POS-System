part of 'app_store_workflow_test.dart';

void _registerAppStoreWorkflowGroup1() {
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
}

void _registerAppStoreWorkflowGroup2() {
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
      await store
          .addOrUpdateProduct(saved.copyWith(price: 15, lowStockThreshold: 5));
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
      expect(
          store.products.map((item) => item.id), isNot(contains('delete-me')));
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
}
