import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/core/services/cash_reversal_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/models/expense.dart';

Future<VentioDriftDatabase> _openDb() async {
  final db = VentioDriftDatabase(NativeDatabase.memory());
  await db.initializeFoundation();
  SqliteMigrationManager.useDatabaseForTesting(db);
  return db;
}

Future<void> _seedExpenseDrawer(VentioDriftDatabase db) async {
  const now = '2026-08-20T00:00:00.000Z';
  await db.customInsert(
    '''
    INSERT INTO cash_locations
      (id, code, name, type, account_id, current_balance, created_at, updated_at,
       store_id, branch_id, device_id)
    VALUES ('drawer-exp-p9', 'DRAW-EXP-P9', 'Expense Drawer', 'cash_drawer',
            'acc_cash', 100, ?, ?, 'store-1', 'main', 'dev-1')
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
    VALUES ('shift-exp-p9', 'SHIFT-EXP-P9', 'drawer-exp-p9', ?, 'open',
            100, 100, 'store-1', 'main')
    ''',
    variables: const <Variable<Object>>[Variable<String>(now)],
  );
}

Expense _expense(String id) {
  final at = DateTime.utc(2026, 8, 20, 0, 5);
  return Expense(
    id: id,
    title: 'Atomic expense',
    category: 'General',
    amount: 20,
    date: at,
    notes: 'phase9',
    status: 'Posted',
    createdAt: at,
    updatedAt: at,
    deviceId: 'dev-1',
    syncStatus: 'pending',
    storeId: 'store-1',
    branchId: 'main',
    version: 1,
    lastModifiedByDeviceId: 'dev-1',
  );
}

Future<double> _balance(VentioDriftDatabase db) async {
  final row = await db.customSelect(
    "SELECT current_balance FROM cash_locations WHERE id = 'drawer-exp-p9'",
  ).getSingle();
  return (row.data['current_balance'] as num).toDouble();
}

void main() {
  tearDown(SqliteMigrationManager.resetForTesting);

  test('expense post commits document, accounting, cash and compatibility ledger together', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedExpenseDrawer(db);

    await AccountingService.recordExpense(_expense('expense-atomic-ok'));

    final expenseRow = await db.customSelect(
      "SELECT expense_status FROM expenses WHERE id = 'expense-atomic-ok'",
    ).getSingle();
    expect(expenseRow.read<String>('expense_status'), 'Posted');
    expect(await _balance(db), 80);

    final cashOps = await db.customSelect(
      "SELECT COUNT(*) AS c FROM cash_operations WHERE idempotency_key = 'expense:expense-atomic-ok'",
    ).getSingle();
    expect((cashOps.data['c'] as num).toInt(), 1);

    final ledger = await db.customSelect(
      "SELECT COUNT(*) AS c FROM cash_ledger_transactions WHERE reference_type = 'expense' AND reference_id = 'expense-atomic-ok' AND reversal_of_id = ''",
    ).getSingle();
    expect((ledger.data['c'] as num).toInt(), 1);

    final accountRows = await db.customSelect(
      "SELECT COUNT(*) AS c FROM account_transactions WHERE reference_id = 'expense-atomic-ok' AND deleted_at = ''",
    ).getSingle();
    expect((accountRows.data['c'] as num).toInt(), 2);
  });

  test('expense post rolls back every side effect when compatibility ledger insert fails', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedExpenseDrawer(db);
    await db.customStatement('''
      CREATE TRIGGER fail_expense_account_tx
      BEFORE INSERT ON account_transactions
      WHEN NEW.id = 'expense-atomic-fail-expense-debit'
      BEGIN
        SELECT RAISE(ABORT, 'forced expense ledger failure');
      END;
    ''');

    await expectLater(
      AccountingService.recordExpense(_expense('expense-atomic-fail')),
      throwsA(anything),
    );

    final expenseRows = await db.customSelect(
      "SELECT COUNT(*) AS c FROM expenses WHERE id = 'expense-atomic-fail'",
    ).getSingle();
    expect((expenseRows.data['c'] as num).toInt(), 0);
    expect(await _balance(db), 100);

    for (final table in <String>[
      'cash_operations',
      'cash_ledger_transactions',
      'journal_entries',
      'account_transactions',
    ]) {
      final row = await db.customSelect(
        "SELECT COUNT(*) AS c FROM $table WHERE id LIKE '%expense-atomic-fail%' OR "
        "${table == 'journal_entries' ? "reference_id = 'expense-atomic-fail'" : "1 = 0"}",
      ).getSingle();
      expect((row.data['c'] as num).toInt(), 0, reason: table);
    }
  });

  test('expense cancel reverses cash and ledger and marks expense cancelled atomically', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedExpenseDrawer(db);
    await AccountingService.recordExpense(_expense('expense-atomic-cancel'));

    final reversed = await CashReversalService(db).reverseReference(
      referenceType: 'expense',
      referenceId: 'expense-atomic-cancel',
      reason: 'cancel test',
      createdBy: 'tester',
      createdByUserId: 'user-1',
      deviceId: 'dev-1',
      occurredAt: DateTime.utc(2026, 8, 20, 0, 10),
    );
    expect(reversed, greaterThan(0));
    expect(await _balance(db), 100);

    final expenseRow = await db.customSelect(
      "SELECT expense_status, cancel_reason FROM expenses WHERE id = 'expense-atomic-cancel'",
    ).getSingle();
    expect(expenseRow.read<String>('expense_status'), 'Cancelled');
    expect(expenseRow.read<String>('cancel_reason'), 'cancel test');

    final reversals = await db.customSelect(
      "SELECT COUNT(*) AS c FROM account_transactions WHERE id IN ('expense-atomic-cancel-expense-debit-reversal', 'expense-atomic-cancel-expense-credit-reversal')",
    ).getSingle();
    expect((reversals.data['c'] as num).toInt(), 2);
  });
}
