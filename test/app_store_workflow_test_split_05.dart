part of 'app_store_workflow_test.dart';

void _registerAppStoreWorkflowGroup4() {
  group('AppStore backup, restore, encryption, merge, and conflicts', () {
    test(
        'exports, validates, encrypts, decrypts, imports, and summarizes backups',
        () async {
      final store = await readyStore();
      await store.catalog.addOrUpdateProduct(product());
      await store.commerce.addOrUpdateCustomer(
          Customer(id: 'c1', name: 'Alice', phone: '', address: ''));
      await store.commerce.addOrUpdateExpense(Expense(
          id: 'e1',
          title: 'Supplies',
          category: 'Ops',
          amount: 5,
          date: DateTime(2026),
          notes: ''));

      expect(await store.security.login('admin', 'AdminPass123'), isTrue);
      final raw = await store.recovery.exportBackupJson();
      final validation = store.validateBackupJson(raw);
      expect(validation.isValid, isTrue);
      expect(validation.summary?.productsCount, 1);
      expect(
        store.validateBackupJson(await store.recovery.exportBackupJson()).isValid,
        isTrue,
      );
      expect(
          store.sync.snapshotGeneratedAtFromJson(
              await store.sync.exportSyncSnapshotJson()),
          isA<DateTime>());
      expect(store.sync.exportChangesJson(), contains('"changes"'));

      final encrypted = await store.exportEncryptedBackupJson('secret-pass');
      expect(encrypted, isNot(contains('Coffee')));
      final decrypted = store.decryptBackupJson(encrypted, 'secret-pass');
      expect(decrypted, contains('"products"'));
      expect(decrypted, contains('Coffee'));
      expect(decrypted, contains('"syncChanges"'));
      expect(() => store.decryptBackupJson(encrypted, 'wrong-pass'),
          throwsA(isA<ArgumentError>()));

      await store.recovery.resetBusinessData();
      expect(store.catalog.products, isEmpty);
      await store.recovery.importBackupJson(raw);
      expect(store.catalog.products.single.name, 'Coffee');
      expect(store.currentBackupSummary.productsCount, 1);
    });

    test('partial backup restore only replaces selected business sections',
        () async {
      final store = await readySqliteStore(
        storeId: 'ST-PARTIAL01',
        branchId: 'BR-PARTIAL01',
        storeName: 'Partial Restore Store',
      );
      await store.catalog.addOrUpdateProduct(
        product(id: 'restore-product', name: 'Backup product'),
      );
      await store.commerce.addOrUpdateCustomer(
        Customer(
          id: 'restore-customer',
          name: 'Backup customer',
          phone: '',
          address: '',
        ),
      );
      final raw = await store.recovery.exportBackupJson();

      await store.catalog.addOrUpdateProduct(
        product(id: 'restore-product', name: 'Current product'),
      );
      await store.commerce.addOrUpdateCustomer(
        Customer(
          id: 'restore-customer',
          name: 'Current customer',
          phone: '',
          address: '',
        ),
      );

      await store.recovery.importBackupJson(
        raw,
        selectedSectionIds: <String>{'products'},
      );

      expect(
        store.catalog.products.singleWhere((item) => item.id == 'restore-product').name,
        'Backup product',
      );
      expect(
        store.commerce.customers
            .singleWhere((item) => item.id == 'restore-customer')
            .name,
        'Current customer',
      );
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
        defaultStoreId: store.runtime.identity.storeId,
        defaultBranchId: store.runtime.identity.branchId,
        deviceId: store.runtime.identity.deviceId,
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
            storeId: store.runtime.identity.storeId,
            branchId: store.runtime.identity.branchId,
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
            storeId: store.runtime.identity.storeId,
            branchId: store.runtime.identity.branchId,
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
          Variable<String>(store.runtime.identity.storeId),
          Variable<String>(store.runtime.identity.branchId),
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
          Variable<String>(store.runtime.identity.storeId),
          Variable<String>(store.runtime.identity.branchId),
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

      final raw = await store.recovery.exportBackupJson();
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
      await store.recovery.importBackupJson(raw);
      final restoredWarehouseCount = await sqliteDb
          .customSelect('SELECT COUNT(*) AS c FROM warehouse_inventory')
          .getSingle();
      expect(restoredWarehouseCount.read<int>('c') > 0, isTrue);
      final afterFirstRestore =
          jsonDecode(await store.recovery.exportBackupJson()) as Map<String, dynamic>;

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

      await store.recovery.importBackupJson(raw);
      final afterSecondRestore =
          jsonDecode(await store.recovery.exportBackupJson()) as Map<String, dynamic>;
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
}

void _registerAppStoreWorkflowGroup5() {
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
      await store.runtime.initialize();
      await store.security.applySessionUser(
        activeUser: hostStore.users.first,
        currentRole: 'Admin',
        permissions: Set<String>.from(AppPermission.all),
        rememberLogin: true,
      );
      await store.catalog.addOrUpdateProduct(product());
      final changeIds = store
          .sync.pendingChangesForTarget('host', readyOnly: false)
          .map((c) => c.id)
          .toList();
      expect(changeIds, isNotEmpty);

      await store.sync.markPushInProgress(changeIds);
      final syncQueueSnapshot = store.sync.queue.toList();
      final inProgressRows =
          syncQueueSnapshot.where((q) => q.isInProgress).toList();
      expect(inProgressRows, isNotEmpty);

      await store.sync.markFailed(changeIds, 'network down');
      expect(
          store.sync.queue
              .where((q) => q.isFailed && q.lastError == 'network down'),
          isNotEmpty);

      await store.sync.retryFailed();
      expect(store.sync.queue.where((q) => q.status == 'pending'), isNotEmpty);

      await store.sync.markSyncQueueItemFailed(
          store.sync.queue.first.id, 'single failure');
      expect(store.sync.queue.first.lastError, 'single failure');

      await store.sync.markAcknowledged(changeIds);
      expect(
          store.sync.pendingChangesForTarget('host', readyOnly: false), isEmpty);
      expect(
          store.sync.pendingSyncQueueForTarget('host', readyOnly: false), isEmpty);

      await store.sync.clearPendingSyncQueue();
      expect(store.sync.pendingQueue.length, 0);
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

      await store.sync.applyRemoteChanges([
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

      expect(store.runtime.profile.name, 'Remote Store');
      expect(store.security.roles.map((r) => r.id), contains(remoteRole.id));
      expect(store.security.users.map((u) => u.id), contains(remoteUser.id));
      expect(store.catalog.products.singleWhere((p) => p.id == 'remote_p').stock, 4);
      // Remote stock movements change quantity, while reference cost remains
      // the value sent with the product record.
      expect(store.catalog.products.singleWhere((p) => p.id == 'remote_p').cost, 7);
    });

    test(
        'enforces permissions for restricted users and supports login/logout lifecycle',
        () async {
      final store = await readyStore();
      await store.security.addOrUpdateRole(UserRole(
          id: 'cashier',
          name: 'Cashier',
          permissions: {AppPermission.salesCreate}));
      await store.security.addOrUpdateUser(
          AppUser(
              id: '',
              fullName: 'Cashier One',
              username: 'cashier',
              passwordHash: '',
              roleId: 'cashier'),
          password: 'Cashier123');

      expect(await store.security.login('cashier', 'bad'), isFalse);
      expect(await store.security.login('cashier', 'Cashier123'), isTrue);
      expect(store.security.canSell, isTrue);
      expect(store.security.canManageProducts, isFalse);
      expect(() => store.security.requirePermission(AppPermission.productsDelete),
          throwsStateError);
      expect(store.catalog.addOrUpdateProduct(product()), throwsStateError);

      await store.security.logout();
      expect(store.security.activeUser == null, isTrue);
      expect(store.security.hasPermission(AppPermission.productsDelete), isFalse);
      expect(() => store.security.requirePermission(AppPermission.productsDelete),
          throwsStateError);
      expect(await store.security.login('admin', 'AdminPass123'), isTrue);
      expect(() => store.security.requirePermission(AppPermission.productsDelete),
          returnsNormally);

      expect(store.security.deleteRole('admin'), throwsStateError);
      expect(store.security.deleteRole('cashier'), throwsStateError);
      final cashierId =
          store.security.users.firstWhere((u) => u.username == 'cashier').id;
      await store.security.deleteUser(cashierId);
      await store.security.deleteRole('cashier');
      expect(store.security.roles.map((r) => r.id), isNot(contains('cashier')));
    });

    test(
        'persists the active session across restart, logout, and user switching',
        () async {
      final store = await readyStore();
      await store.security.addOrUpdateRole(UserRole(
          id: 'cashier',
          name: 'Cashier',
          permissions: {AppPermission.salesCreate}));
      await store.security.addOrUpdateUser(
          AppUser(
              id: '',
              fullName: 'Cashier One',
              username: 'cashier',
              passwordHash: '',
              roleId: 'cashier'),
          password: 'Cashier123');

      expect(
          await AuthRepository.login(store, 'cashier', 'Cashier123',
              remember: true),
          isTrue);
      expect(store.security.activeUser?.username, 'cashier');
      expect(store.security.currentRole, 'Cashier');
      expect(store.security.rememberLogin, isTrue);

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
      await store.security.addOrUpdateRole(UserRole(
          id: 'cashier',
          name: 'Cashier',
          permissions: {AppPermission.salesCreate}));
      await store.security.addOrUpdateUser(
          AppUser(
              id: '',
              fullName: 'Cashier One',
              username: 'cashier',
              passwordHash: '',
              roleId: 'cashier'),
          password: 'Cashier123');
      expect(
          await AuthRepository.login(store, 'cashier', 'Cashier123',
              remember: true),
          isTrue);

      final usersSnapshot = store.security.users.toList(growable: false);
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

      await store.runtime.refreshAfterDatabaseChange('users_v1');
      expect(store.security.users.singleWhere((u) => u.username == 'cashier').fullName,
          'Cashier Reloaded');
      expect(store.security.activeUser?.fullName, 'Cashier Reloaded');
    });

    test('updates identity, admin setup, and keeps protected operations safe',
        () async {
      final store = await readyStore();

      await store.runtime.updateIdentity(store.runtime.identity.copyWith(
          syncMode: SyncMode.marketplaceEnabled, deviceRole: DeviceRole.host));
      expect(store.runtime.identity.syncMode, SyncMode.marketplaceEnabled);
      expect(store.runtime.identity.deviceId, store.sync.deviceId);

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
