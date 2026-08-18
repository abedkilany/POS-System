import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/core/services/cash_operation_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/models/expense.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';

Future<VentioDriftDatabase> _openDb() async {
  final db = VentioDriftDatabase(NativeDatabase.memory());
  await db.initializeFoundation();
  return db;
}

Future<void> _seedDrawer(VentioDriftDatabase db, {double balance = 100}) async {
  const now = '2026-08-18T12:00:00.000Z';
  await db.customInsert(
    '''
    INSERT INTO cash_locations
      (id, code, name, type, account_id, current_balance, created_at, updated_at,
       store_id, branch_id, device_id)
    VALUES ('drawer-p5', 'DRAW-P5', 'Phase 5 Drawer', 'cash_drawer', 'acc_cash', ?, ?, ?,
            'store-1', 'main', 'dev-1')
    ''',
    variables: <Variable<Object>>[
      Variable<double>(balance),
      const Variable<String>(now),
      const Variable<String>(now),
    ],
  );
  await db.customInsert(
    '''
    INSERT INTO cash_drawer_sessions
      (id, drawer_no, cash_location_id, opened_at, status, opening_balance,
       expected_cash, store_id, branch_id)
    VALUES ('shift-p5', 'SHIFT-P5', 'drawer-p5', ?, 'open', ?, ?, 'store-1', 'main')
    ''',
    variables: <Variable<Object>>[
      const Variable<String>(now),
      Variable<double>(balance),
      Variable<double>(balance),
    ],
  );
}

Future<double> _locationBalance(VentioDriftDatabase db) async {
  final row = await db.customSelect(
    "SELECT current_balance FROM cash_locations WHERE id = 'drawer-p5'",
  ).getSingle();
  return (row.data['current_balance'] as num).toDouble();
}


Future<void> _seedTransferLocations(VentioDriftDatabase db) async {
  const now = '2026-08-18T12:00:00.000Z';
  for (final row in <List<Object>>[
    <Object>['drawer-from', 'FROM', 'Source Drawer', 'cash_drawer', 'acc_cash', 100.0, 'dev-from'],
    <Object>['drawer-to', 'TO', 'Target Drawer', 'cash_drawer', 'acc_cash', 20.0, 'dev-to'],
    <Object>['vault-p5', 'VAULT', 'Phase 5 Vault', 'vault', 'acc_cash', 50.0, ''],
  ]) {
    await db.customInsert(
      '''
      INSERT INTO cash_locations
        (id, code, name, type, account_id, current_balance, created_at, updated_at,
         store_id, branch_id, device_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'store-1', 'main', ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(row[0] as String),
        Variable<String>(row[1] as String),
        Variable<String>(row[2] as String),
        Variable<String>(row[3] as String),
        Variable<String>(row[4] as String),
        Variable<double>(row[5] as double),
        const Variable<String>(now),
        const Variable<String>(now),
        Variable<String>(row[6] as String),
      ],
    );
  }
  await db.customInsert(
    '''
    INSERT INTO cash_drawer_sessions
      (id, drawer_no, cash_location_id, opened_at, status, opening_balance,
       expected_cash, store_id, branch_id)
    VALUES ('shift-from', 'SHIFT-FROM', 'drawer-from', ?, 'open', 100, 100, 'store-1', 'main')
    ''',
    variables: const <Variable<Object>>[Variable<String>(now)],
  );
  await db.customInsert(
    '''
    INSERT INTO cash_drawer_sessions
      (id, drawer_no, cash_location_id, opened_at, status, opening_balance,
       expected_cash, store_id, branch_id)
    VALUES ('shift-to', 'SHIFT-TO', 'drawer-to', ?, 'open', 20, 20, 'store-1', 'main')
    ''',
    variables: const <Variable<Object>>[Variable<String>(now)],
  );
}

Future<double> _balanceOf(VentioDriftDatabase db, String id) async {
  final row = await db.customSelect(
    'SELECT current_balance FROM cash_locations WHERE id = ?',
    variables: <Variable<Object>>[Variable<String>(id)],
  ).getSingle();
  return (row.data['current_balance'] as num).toDouble();
}

Future<VentioDriftDatabase> _openAccountingDb() async {
  final db = await _openDb();
  SqliteMigrationManager.useDatabaseForTesting(db);
  return db;
}

void main() {
  test('foundation creates Phase 5 cash operations schema', () async {
    final db = await _openDb();
    addTearDown(db.close);

    final table = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'cash_operations'",
    ).getSingleOrNull();
    expect(table, isNotNull);

    final transferColumns = await db.customSelect("PRAGMA table_info('cash_transfers')").get();
    final names = transferColumns.map((row) => row.data['name']?.toString()).toSet();
    expect(names, containsAll(<String>[
      'transfer_kind',
      'from_session_id',
      'to_session_id',
      'idempotency_key',
    ]));
  });

  test('deposit writes operation, journal, ledger and balance exactly once', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedDrawer(db);
    final service = CashOperationService(db);

    final first = await service.deposit(
      cashLocationId: 'drawer-p5',
      cashDrawerSessionId: 'shift-p5',
      amount: 25,
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
      idempotencyKey: 'deposit-once',
    );
    final retry = await service.deposit(
      cashLocationId: 'drawer-p5',
      cashDrawerSessionId: 'shift-p5',
      amount: 25,
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
      idempotencyKey: 'deposit-once',
    );

    expect(retry.id, first.id);
    expect(await _locationBalance(db), 125);
    final operations = await db.customSelect(
      "SELECT COUNT(*) AS c FROM cash_operations WHERE operation_type = 'cash_deposit'",
    ).getSingle();
    expect(operations.read<int>('c'), 1);
    final ledger = await db.customSelect(
      "SELECT direction, amount, reference_id FROM cash_ledger_transactions WHERE type = 'cash_deposit'",
    ).getSingle();
    expect(ledger.read<String>('direction'), 'in');
    expect(ledger.read<double>('amount'), 25);
    expect(ledger.read<String>('reference_id'), first.id);
    final journal = await db.customSelect(
      "SELECT id FROM journal_entries WHERE reference_type = 'cash_deposit' AND reference_id = ?",
      variables: <Variable<Object>>[Variable<String>(first.id)],
    ).getSingleOrNull();
    expect(journal, isNotNull);
  });

  test('withdrawal and expense reduce balance and are visible in ledger', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedDrawer(db, balance: 100);
    final service = CashOperationService(db);

    await service.withdrawal(
      cashLocationId: 'drawer-p5',
      cashDrawerSessionId: 'shift-p5',
      amount: 20,
      idempotencyKey: 'withdraw-1',
    );
    await service.expense(
      cashLocationId: 'drawer-p5',
      cashDrawerSessionId: 'shift-p5',
      amount: 15,
      idempotencyKey: 'expense-1',
    );

    expect(await _locationBalance(db), 65);
    final rows = await db.customSelect(
      "SELECT type, direction, amount FROM cash_ledger_transactions WHERE cash_drawer_session_id = 'shift-p5' ORDER BY occurred_at",
    ).get();
    expect(rows, hasLength(2));
    expect(rows.every((row) => row.read<String>('direction') == 'out'), isTrue);
    expect(rows.map((row) => row.read<String>('type')).toSet(), containsAll(<String>['cash_withdrawal', 'expense']));
  });

  test('cash out rejects insufficient balance when negative cash is disabled', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedDrawer(db, balance: 10);
    final service = CashOperationService(db);

    await expectLater(
      service.withdrawal(
        cashLocationId: 'drawer-p5',
        cashDrawerSessionId: 'shift-p5',
        amount: 11,
      ),
      throwsStateError,
    );
    expect(await _locationBalance(db), 10);
  });

  test('legacy posted expense uses journal + cash operation + ledger + balance exactly once', () async {
    final db = await _openAccountingDb();
    addTearDown(SqliteMigrationManager.resetForTesting);
    await _seedDrawer(db, balance: 100);
    final when = DateTime.utc(2026, 8, 18, 13);
    final expense = Expense(
      id: 'expense-legacy-p5',
      title: 'Office supplies',
      category: 'General',
      amount: 15,
      date: when,
      notes: 'Phase 5 legacy expense route',
      status: 'Posted',
      deviceId: 'dev-1',
      storeId: 'store-1',
      branchId: 'main',
      lastModifiedByDeviceId: 'dev-1',
    );

    await AccountingService.recordExpense(expense);
    await AccountingService.recordExpense(expense);

    expect(await _locationBalance(db), 85);
    final operation = await db.customSelect(
      "SELECT COUNT(*) AS c FROM cash_operations WHERE operation_type = 'expense' AND idempotency_key = 'expense:expense-legacy-p5'",
    ).getSingle();
    expect(operation.read<int>('c'), 1);
    final ledger = await db.customSelect(
      "SELECT direction, amount, cash_drawer_session_id FROM cash_ledger_transactions WHERE reference_type = 'expense' AND reference_id = 'expense-legacy-p5'",
    ).getSingle();
    expect(ledger.read<String>('direction'), 'out');
    expect(ledger.read<double>('amount'), 15);
    expect(ledger.read<String>('cash_drawer_session_id'), 'shift-p5');
    final journals = await db.customSelect(
      "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'expense' AND reference_id = 'expense-legacy-p5' AND status = 'posted'",
    ).getSingle();
    expect(journals.read<int>('c'), 1);
  });

  test('vault transfer posts one journal, two ledger legs, both balances and is idempotent', () async {
    final db = await _openAccountingDb();
    addTearDown(SqliteMigrationManager.resetForTesting);
    await _seedTransferLocations(db);

    final first = await AccountingService.createCashTransfer(
      fromLocationId: 'drawer-from',
      toLocationId: 'vault-p5',
      amount: 30,
      transferKind: 'vault_transfer',
      fromSessionId: 'shift-from',
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-from',
      idempotencyKey: 'vault-transfer-once',
      notifyChange: false,
    );
    final retry = await AccountingService.createCashTransfer(
      fromLocationId: 'drawer-from',
      toLocationId: 'vault-p5',
      amount: 30,
      transferKind: 'vault_transfer',
      fromSessionId: 'shift-from',
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-from',
      idempotencyKey: 'vault-transfer-once',
      notifyChange: false,
    );

    expect(retry, first);
    expect(await _balanceOf(db, 'drawer-from'), 70);
    expect(await _balanceOf(db, 'vault-p5'), 80);
    final transfers = await db.customSelect(
      "SELECT COUNT(*) AS c FROM cash_transfers WHERE transfer_kind = 'vault_transfer' AND idempotency_key = 'vault-transfer-once'",
    ).getSingle();
    expect(transfers.read<int>('c'), 1);
    final ledger = await db.customSelect(
      'SELECT direction, amount, cash_location_id FROM cash_ledger_transactions WHERE reference_type = ? AND reference_id = ? ORDER BY direction',
      variables: <Variable<Object>>[
        const Variable<String>('cash_transfer'),
        Variable<String>(first),
      ],
    ).get();
    expect(ledger, hasLength(2));
    expect(ledger.map((r) => r.read<String>('direction')).toSet(), <String>{'in', 'out'});
    expect(ledger.every((r) => r.read<double>('amount') == 30), isTrue);
    final journal = await db.customSelect(
      "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'cash_transfer' AND reference_id = ? AND status = 'posted'",
      variables: <Variable<Object>>[Variable<String>(first)],
    ).getSingle();
    expect(journal.read<int>('c'), 1);
  });

  test('vault transfer also supports vault to drawer with mirrored ledger directions', () async {
    final db = await _openAccountingDb();
    addTearDown(SqliteMigrationManager.resetForTesting);
    await _seedTransferLocations(db);

    final id = await AccountingService.createCashTransfer(
      fromLocationId: 'vault-p5',
      toLocationId: 'drawer-to',
      amount: 15,
      transferKind: 'vault_transfer',
      toSessionId: 'shift-to',
      storeId: 'store-1',
      branchId: 'main',
      idempotencyKey: 'vault-to-drawer',
      notifyChange: false,
    );

    expect(await _balanceOf(db, 'vault-p5'), 35);
    expect(await _balanceOf(db, 'drawer-to'), 35);
    final legs = await db.customSelect(
      'SELECT direction, cash_location_id, cash_drawer_session_id FROM cash_ledger_transactions WHERE reference_id = ?',
      variables: <Variable<Object>>[Variable<String>(id)],
    ).get();
    expect(legs, hasLength(2));
    expect(
      legs.map((r) => "${r.read<String>('direction')}:${r.read<String>('cash_location_id')}:${r.read<String>('cash_drawer_session_id')}").toSet(),
      <String>{'out:vault-p5:', 'in:drawer-to:shift-to'},
    );
  });

  test('vault transfer rejects insufficient source balance', () async {
    final db = await _openAccountingDb();
    addTearDown(SqliteMigrationManager.resetForTesting);
    await _seedTransferLocations(db);

    await expectLater(
      AccountingService.createCashTransfer(
        fromLocationId: 'drawer-from',
        toLocationId: 'vault-p5',
        amount: 101,
        transferKind: 'vault_transfer',
        idempotencyKey: 'vault-too-much',
        notifyChange: false,
      ),
      throwsStateError,
    );
    expect(await _balanceOf(db, 'drawer-from'), 100);
    expect(await _balanceOf(db, 'vault-p5'), 50);
  });

  test('shift transfer requires matching open sessions and posts both session ledger legs', () async {
    final db = await _openAccountingDb();
    addTearDown(SqliteMigrationManager.resetForTesting);
    await _seedTransferLocations(db);

    final id = await AccountingService.createCashTransfer(
      fromLocationId: 'drawer-from',
      toLocationId: 'drawer-to',
      amount: 25,
      transferKind: 'shift_transfer',
      fromSessionId: 'shift-from',
      toSessionId: 'shift-to',
      storeId: 'store-1',
      branchId: 'main',
      idempotencyKey: 'shift-transfer-once',
      notifyChange: false,
    );
    final retry = await AccountingService.createCashTransfer(
      fromLocationId: 'drawer-from',
      toLocationId: 'drawer-to',
      amount: 25,
      transferKind: 'shift_transfer',
      fromSessionId: 'shift-from',
      toSessionId: 'shift-to',
      storeId: 'store-1',
      branchId: 'main',
      idempotencyKey: 'shift-transfer-once',
      notifyChange: false,
    );

    expect(retry, id);
    expect(await _balanceOf(db, 'drawer-from'), 75);
    expect(await _balanceOf(db, 'drawer-to'), 45);
    final transfer = await db.customSelect(
      'SELECT transfer_kind, from_session_id, to_session_id FROM cash_transfers WHERE id = ?',
      variables: <Variable<Object>>[Variable<String>(id)],
    ).getSingle();
    expect(transfer.read<String>('transfer_kind'), 'shift_transfer');
    expect(transfer.read<String>('from_session_id'), 'shift-from');
    expect(transfer.read<String>('to_session_id'), 'shift-to');
    final ledger = await db.customSelect(
      'SELECT direction, cash_location_id, cash_drawer_session_id FROM cash_ledger_transactions WHERE reference_id = ? ORDER BY direction',
      variables: <Variable<Object>>[Variable<String>(id)],
    ).get();
    expect(ledger, hasLength(2));
    expect(
      ledger.map((r) => "${r.read<String>('direction')}:${r.read<String>('cash_location_id')}:${r.read<String>('cash_drawer_session_id')}").toSet(),
      <String>{'out:drawer-from:shift-from', 'in:drawer-to:shift-to'},
    );
  });

  test('shift transfer rejects missing, closed or mismatched sessions inside service layer', () async {
    final db = await _openAccountingDb();
    addTearDown(SqliteMigrationManager.resetForTesting);
    await _seedTransferLocations(db);

    await expectLater(
      AccountingService.createCashTransfer(
        fromLocationId: 'drawer-from',
        toLocationId: 'drawer-to',
        amount: 10,
        transferKind: 'shift_transfer',
        fromSessionId: '',
        toSessionId: 'shift-to',
        notifyChange: false,
      ),
      throwsStateError,
    );

    await expectLater(
      AccountingService.createCashTransfer(
        fromLocationId: 'drawer-from',
        toLocationId: 'drawer-to',
        amount: 10,
        transferKind: 'shift_transfer',
        fromSessionId: 'shift-to',
        toSessionId: 'shift-from',
        notifyChange: false,
      ),
      throwsStateError,
    );

    await db.customUpdate(
      "UPDATE cash_drawer_sessions SET status = 'closed' WHERE id = 'shift-to'",
    );
    await expectLater(
      AccountingService.createCashTransfer(
        fromLocationId: 'drawer-from',
        toLocationId: 'drawer-to',
        amount: 10,
        transferKind: 'shift_transfer',
        fromSessionId: 'shift-from',
        toSessionId: 'shift-to',
        notifyChange: false,
      ),
      throwsStateError,
    );

    expect(await _balanceOf(db, 'drawer-from'), 100);
    expect(await _balanceOf(db, 'drawer-to'), 20);
  });

  _phase5ExpensePostingIntegrityTests();
}

// Phase 5 posting-integrity regression coverage.
void _phase5ExpensePostingIntegrityTests() {
  test('bulk legacy expenses roll back all cash/accounting when one item cannot be funded', () async {
    final db = await _openAccountingDb();
    addTearDown(SqliteMigrationManager.resetForTesting);
    await _seedDrawer(db, balance: 10);
    final when = DateTime.utc(2026, 8, 18, 14);
    final expenses = <Expense>[
      Expense(
        id: 'expense-bulk-ok-first',
        title: 'First',
        category: 'General',
        amount: 6,
        date: when,
        notes: '',
        status: 'Posted',
        deviceId: 'dev-1',
        storeId: 'store-1',
        branchId: 'main',
        lastModifiedByDeviceId: 'dev-1',
      ),
      Expense(
        id: 'expense-bulk-fails-second',
        title: 'Second',
        category: 'General',
        amount: 6,
        date: when,
        notes: '',
        status: 'Posted',
        deviceId: 'dev-1',
        storeId: 'store-1',
        branchId: 'main',
        lastModifiedByDeviceId: 'dev-1',
      ),
    ];

    await expectLater(
      AccountingService.recordExpensesBulk(expenses),
      throwsStateError,
    );

    expect(await _locationBalance(db), 10);
    final operations = await db.customSelect(
      "SELECT COUNT(*) AS c FROM cash_operations WHERE idempotency_key IN ('expense:expense-bulk-ok-first', 'expense:expense-bulk-fails-second')",
    ).getSingle();
    expect(operations.read<int>('c'), 0);
    final ledgerRows = await db.customSelect(
      "SELECT COUNT(*) AS c FROM cash_ledger_transactions WHERE reference_type = 'expense' AND reference_id IN ('expense-bulk-ok-first', 'expense-bulk-fails-second')",
    ).getSingle();
    expect(ledgerRows.read<int>('c'), 0);
    final journals = await db.customSelect(
      "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'expense' AND reference_id IN ('expense-bulk-ok-first', 'expense-bulk-fails-second')",
    ).getSingle();
    expect(journals.read<int>('c'), 0);
  });
}
