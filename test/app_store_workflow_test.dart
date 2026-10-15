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

part 'app_store_workflow_test_split_01.dart';
part 'app_store_workflow_test_split_02.dart';
part 'app_store_workflow_test_split_03.dart';
part 'app_store_workflow_test_split_04.dart';
part 'app_store_workflow_test_split_05.dart';

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
    await sqliteDb
        .customStatement('DELETE FROM purchase_item_batch_allocations');
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
  // Clear scalar mirrors as well as SQLite so the next store cannot hydrate
  // the prior test's costing method or return history.
  await LocalDatabaseService.deleteString('inventory_costing_method_v1');
  await LocalDatabaseService.deleteString('credit_notes_v1');
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

  _registerAppStoreWorkflowGroup1();

  _registerAppStoreWorkflowGroup2();

  _registerAppStoreWorkflowGroup3();

  _registerAppStoreWorkflowGroup4();

  _registerAppStoreWorkflowGroup5();
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
