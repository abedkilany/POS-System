import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/core/services/cash_operation_service.dart';
import 'package:ventio/core/services/payment_voucher_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/core/snapshot/unified_snapshot.dart';
import 'package:ventio/models/payment_allocation.dart';
import 'package:ventio/models/user_role.dart';

Future<VentioDriftDatabase> _phase8Db() async {
  final db = VentioDriftDatabase(NativeDatabase.memory());
  await db.initializeFoundation();
  SqliteMigrationManager.useDatabaseForTesting(db);
  return db;
}

Future<void> _seedPhase8Drawer(VentioDriftDatabase db) async {
  const now = '2026-08-19T12:00:00.000Z';
  await db.customInsert(
    '''
    INSERT INTO cash_locations
      (id, code, name, type, account_id, current_balance, created_at, updated_at,
       store_id, branch_id, device_id)
    VALUES ('drawer-p8', 'DRAW-P8', 'Phase 8 Drawer', 'cash_drawer', 'acc_cash',
            100, ?, ?, 'store-1', 'main', 'dev-1')
    ''',
    variables: const <Variable<Object>>[
      Variable<String>(now),
      Variable<String>(now),
    ],
  );
  await db.customInsert(
    '''
    INSERT INTO cash_drawer_sessions
      (id, drawer_no, cash_location_id, opened_at, status, opening_balance,
       expected_cash, store_id, branch_id)
    VALUES ('shift-p8', 'SHIFT-P8', 'drawer-p8', ?, 'open', 100, 100, 'store-1', 'main')
    ''',
    variables: const <Variable<Object>>[Variable<String>(now)],
  );
}


Future<void> _seedPhase8Sale(VentioDriftDatabase db) async {
  const now = '2026-08-19T12:00:00.000Z';
  await db.customInsert(
    r'''
    INSERT INTO sales
      (id, entity_type, created_at, updated_at, deleted_at, device_id, sync_status,
       store_id, branch_id, version, sort_index, invoice_no, customer_id,
       customer_name, document_date, status, discount, payment_method,
       payment_status, invoice_currency, transaction_amount, paid_amount)
    VALUES ('sale-p8', 'sale', ?, ?, '', 'dev-1', 'synced', 'store-1', 'main', 1, 0,
            'INV-P8', 'cust-p8', 'Customer P8', ?, 'Paid', 0, 'Credit',
            'unpaid', 'USD', 50, 0)
    ''',
    variables: const <Variable<Object>>[
      Variable<String>(now),
      Variable<String>(now),
      Variable<String>(now),
    ],
  );
}

void main() {
  test('phase 8 snapshot catalog includes authoritative cash/accounting data', () {
    final collections = UnifiedSnapshotCatalog.cashAndAccounting.collections;
    for (final name in <String>[
      'accountingAccounts',
      'cashLocations',
      'cashDrawerSessions',
      'cashTransfers',
      'receiptVouchers',
      'paymentVouchers',
      'paymentAllocations',
      'cashOperations',
      'cashLedgerTransactions',
      'journalEntries',
      'journalLines',
      'accountingAuditLog',
    ]) {
      expect(collections, contains(name));
      expect(LocalDatabaseService.phase8AccountingSnapshotTables, contains(name));
    }
  });

  test('cash box permissions expose separate view and manage capabilities', () {
    expect(AppPermission.all, contains(AppPermission.cashBoxView));
    expect(AppPermission.all, contains(AppPermission.cashBoxManage));
    expect(AppPermission.cashBoxView, isNot(AppPermission.cashBoxManage));
  });

  test('cash operation emits Phase 8 mutation only after successful commit', () async {
    final db = await _phase8Db();
    addTearDown(db.close);
    addTearDown(() {
      AccountingService.setMutationListener(null);
      SqliteMigrationManager.resetForTesting();
    });
    await _seedPhase8Drawer(db);

    var mutations = 0;
    AccountingService.setMutationListener(() => mutations++);
    final result = await CashOperationService(db).deposit(
      cashLocationId: 'drawer-p8',
      cashDrawerSessionId: 'shift-p8',
      counterpartAccountId: 'acc_owner_capital',
      amount: 25,
      deviceId: 'dev-1',
      storeId: 'store-1',
      branchId: 'main',
      idempotencyKey: 'phase8-deposit',
    );

    expect(result.id, isNotEmpty);
    expect(mutations, 1);
    final operation = await db.customSelect(
      "SELECT id FROM cash_operations WHERE id = ? AND deleted_at = ''",
      variables: <Variable<Object>>[Variable<String>(result.id)],
    ).getSingleOrNull();
    expect(operation, isNotNull);
  });

  test('failed cash transaction does not emit Phase 8 mutation', () async {
    final db = await _phase8Db();
    addTearDown(db.close);
    addTearDown(() {
      AccountingService.setMutationListener(null);
      SqliteMigrationManager.resetForTesting();
    });
    await _seedPhase8Drawer(db);

    var mutations = 0;
    AccountingService.setMutationListener(() => mutations++);
    await expectLater(
      CashOperationService(db).withdrawal(
        cashLocationId: 'drawer-p8',
        cashDrawerSessionId: 'shift-p8',
        counterpartAccountId: 'acc_owner_capital',
        amount: 1000,
        deviceId: 'dev-1',
        storeId: 'store-1',
        branchId: 'main',
        idempotencyKey: 'phase8-failed-withdrawal',
      ),
      throwsA(isA<StateError>()),
    );
    expect(mutations, 0);
  });


  test('receipt voucher emits one committed Phase 8 mutation', () async {
    final db = await _phase8Db();
    addTearDown(db.close);
    addTearDown(() {
      AccountingService.setMutationListener(null);
      SqliteMigrationManager.resetForTesting();
    });
    await _seedPhase8Drawer(db);
    await _seedPhase8Sale(db);

    var mutations = 0;
    AccountingService.setMutationListener(() => mutations++);
    final receipt = await PaymentVoucherService(db).createReceipt(
      id: 'receipt-p8',
      voucherNo: 'RC-P8',
      customerId: 'cust-p8',
      customerName: 'Customer P8',
      amount: 20,
      cashLocationId: 'drawer-p8',
      cashDrawerSessionId: 'shift-p8',
      deviceId: 'dev-1',
      storeId: 'store-1',
      branchId: 'main',
      idempotencyKey: 'phase8-receipt',
      allocations: const <PaymentAllocationDraft>[
        PaymentAllocationDraft(referenceId: 'sale-p8', amount: 20),
      ],
    );

    expect(receipt.id, 'receipt-p8');
    expect(mutations, 1);
    final ledger = await db.customSelect(
      "SELECT id FROM cash_ledger_transactions WHERE reference_type = 'receipt_voucher' AND reference_id = 'receipt-p8'",
    ).get();
    expect(ledger, hasLength(1));
  });

  test(
      'startup recovery re-queues accounting rows committed after durable cursor',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    await LocalDatabaseService.useSqliteDatabaseForTesting(db);
    addTearDown(() async {
      AccountingService.setMutationListener(null);
      await LocalDatabaseService.resetForTesting();
    });

    final cursor = DateTime.now().toUtc().subtract(const Duration(minutes: 2));
    final committedAt = cursor.add(const Duration(minutes: 1));
    await LocalDatabaseService.setString(
      'phase8_accounting_sync_cursor_v1',
      cursor.toIso8601String(),
    );
    await LocalDatabaseService.setString(
      'app_identity_v1',
      jsonEncode(<String, dynamic>{
        'storeId': 'store-1',
        'branchId': 'main',
        'deviceId': 'dev-p8-client',
        'deviceName': 'Phase 8 Client',
        'platform': 'windows',
        'deviceRole': 'client',
        'appRole': 'store',
        'syncMode': 'directConnected',
        'hostDeviceId': 'host-p8',
        'controlPlaneTenantId': '',
        'deviceToken': 'phase8-token',
        'storeEpoch': 1,
        'activeSyncTransport': 'direct',
      }),
    );

    await db.customInsert(
      '''
      INSERT INTO cash_locations
        (id, code, name, type, account_id, current_balance, created_at, updated_at,
         store_id, branch_id, device_id)
      VALUES ('drawer-recovery', 'DRAW-REC', 'Recovery Drawer', 'cash_drawer',
              'acc_cash', 125, ?, ?, 'store-1', 'main', 'dev-p8-client')
      ''',
      variables: <Variable<Object>>[
        Variable<String>(committedAt.toIso8601String()),
        Variable<String>(committedAt.toIso8601String()),
      ],
    );

    final store = AppStore();
    await store.initialize(hydrateHeavyData: false);
    await store.recoverPhase8AccountingSyncAfterStartup();

    final deltas = store.syncChanges
        .where((change) => change.entityType == 'cash_accounting_delta')
        .toList(growable: false);
    expect(deltas, hasLength(1));
    final collections = Map<String, dynamic>.from(
      deltas.single.payload['collections'] as Map,
    );
    final cashLocations = (collections['cashLocations'] as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    expect(
      cashLocations.any((row) => row['id'] == 'drawer-recovery'),
      isTrue,
    );
    expect(store.syncQueue.any((item) => item.status == 'pending'), isTrue);

    final persistedCursor = DateTime.parse(
      LocalDatabaseService.getString('phase8_accounting_sync_cursor_v1')!,
    ).toUtc();
    expect(persistedCursor.isAfter(cursor), isTrue);
    store.dispose();
  });

  test('closing a cash drawer is strict and cannot silently succeed twice', () async {
    final db = await _phase8Db();
    addTearDown(db.close);
    addTearDown(() {
      AccountingService.setMutationListener(null);
      SqliteMigrationManager.resetForTesting();
    });
    await _seedPhase8Drawer(db);

    await AccountingService.closeCashDrawer(
      sessionId: 'shift-p8',
      countedCash: 100,
      closedBy: 'tester',
    );

    final row = await db.customSelect(
      "SELECT status, closed_at, updated_at, revision FROM cash_drawer_sessions WHERE id = 'shift-p8'",
    ).getSingle();
    expect(row.read<String>('status'), 'closed');
    expect(row.read<String>('closed_at'), isNotEmpty);
    expect(row.read<String>('updated_at'), isNotEmpty);
    expect(row.read<int>('revision'), greaterThanOrEqualTo(2));

    await expectLater(
      AccountingService.closeCashDrawer(
        sessionId: 'shift-p8',
        countedCash: 100,
        closedBy: 'tester',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('older or reopened sync session cannot overwrite a closed local shift', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    await LocalDatabaseService.useSqliteDatabaseForTesting(db);
    addTearDown(() async {
      await LocalDatabaseService.resetForTesting();
      await db.close();
    });

    await db.customInsert(
      '''
      INSERT INTO cash_drawer_sessions
        (id, drawer_no, cash_location_id, opened_at, closed_at, status,
         opening_balance, expected_cash, counted_cash, difference,
         store_id, branch_id, updated_at, revision)
      VALUES ('sync-shift', 'SYNC', 'drawer-sync', '2026-08-19T10:00:00.000Z',
              '2026-08-19T12:00:00.000Z', 'closed', 100, 100, 100, 0,
              'store-1', 'main', '2026-08-19T12:00:00.000Z', 2)
      ''',
    );

    await LocalDatabaseService.upsertPhase8AccountingSnapshotRowsImmediate(
      <String, List<Map<String, dynamic>>>{
        'cashDrawerSessions': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'sync-shift',
            'drawer_no': 'SYNC',
            'cash_location_id': 'drawer-sync',
            'opened_at': '2026-08-19T10:00:00.000Z',
            'closed_at': '',
            'status': 'open',
            'opening_balance': 100.0,
            'expected_cash': 100.0,
            'counted_cash': 0.0,
            'difference': 0.0,
            'notes': '',
            'opened_by': '',
            'opened_by_user_id': '',
            'closed_by': '',
            'closed_by_user_id': '',
            'store_id': 'store-1',
            'branch_id': 'main',
            // Deliberately later wall clock to prove terminal-state protection
            // is not defeated by clock skew on a stale peer.
            'updated_at': '2026-08-19T13:00:00.000Z',
            'revision': 1,
          },
        ],
      },
    );

    final row = await db.customSelect(
      "SELECT status, closed_at, revision FROM cash_drawer_sessions WHERE id = 'sync-shift'",
    ).getSingle();
    expect(row.read<String>('status'), 'closed');
    expect(row.read<String>('closed_at'), '2026-08-19T12:00:00.000Z');
    expect(row.read<int>('revision'), 2);
  });

  test('assigned cash drawer remains discoverable after its shift is closed', () async {
    final db = await _phase8Db();
    addTearDown(db.close);
    addTearDown(() {
      SqliteMigrationManager.resetForTesting();
    });
    await _seedPhase8Drawer(db);
    await db.customUpdate(
      "UPDATE cash_drawer_sessions SET status = 'closed', closed_at = '2026-08-19T13:00:00.000Z' WHERE id = 'shift-p8'",
    );

    final drawer = await AccountingService.currentCashDrawerForDevice(
      deviceId: 'dev-1',
      branchId: 'main',
    );
    expect(drawer, isNotNull);
    expect(drawer!.id, 'drawer-p8');
    expect(
      await AccountingService.hasOpenCashDrawerForDevice(
        deviceId: 'dev-1',
        branchId: 'main',
      ),
      isFalse,
    );
  });

  test('unallocated account receipt still posts voucher and cash ledger', () async {
    final db = await _phase8Db();
    addTearDown(db.close);
    addTearDown(() {
      AccountingService.setMutationListener(null);
      SqliteMigrationManager.resetForTesting();
    });
    await _seedPhase8Drawer(db);

    final receipt = await PaymentVoucherService(db).createReceipt(
      id: 'receipt-account-level',
      voucherNo: 'RC-ACCOUNT',
      customerId: 'cust-account',
      customerName: 'Account Customer',
      amount: 30,
      cashLocationId: 'drawer-p8',
      cashDrawerSessionId: 'shift-p8',
      allocations: const <PaymentAllocationDraft>[],
      deviceId: 'dev-1',
      storeId: 'store-1',
      branchId: 'main',
      idempotencyKey: 'account-level-receipt',
    );

    expect(receipt.unallocatedAmount, 30);
    final ledger = await db.customSelect(
      "SELECT amount, direction FROM cash_ledger_transactions WHERE reference_type = 'receipt_voucher' AND reference_id = 'receipt-account-level'",
    ).getSingleOrNull();
    expect(ledger, isNotNull);
    expect(ledger!.read<double>('amount'), 30);
    expect(ledger.read<String>('direction'), 'in');
  });

}
