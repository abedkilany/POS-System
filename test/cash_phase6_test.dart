import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/core/services/cash_operation_service.dart';
import 'package:ventio/core/services/cash_reversal_service.dart';
import 'package:ventio/core/services/payment_voucher_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';

Future<VentioDriftDatabase> _db() async {
  final db = VentioDriftDatabase(NativeDatabase.memory());
  await db.initializeFoundation();
  SqliteMigrationManager.useDatabaseForTesting(db);
  return db;
}

Future<void> _seedDrawer(VentioDriftDatabase db) async {
  const now = '2026-08-18T12:00:00.000Z';
  await db.customInsert(
    '''
    INSERT INTO cash_locations
      (id, code, name, type, account_id, current_balance, created_at, updated_at,
       store_id, branch_id, device_id)
    VALUES ('drawer-p6', 'DRAW-P6', 'Phase 6 Drawer', 'cash_drawer', 'acc_cash', 100, ?, ?,
            'store-1', 'main', 'dev-1')
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
    VALUES ('shift-p6', 'SHIFT-P6', 'drawer-p6', ?, 'open', 100, 100, 'store-1', 'main')
    ''',
    variables: const <Variable<Object>>[Variable<String>(now)],
  );
}

Future<double> _balance(VentioDriftDatabase db) async {
  final row = await db.customSelect(
    "SELECT current_balance FROM cash_locations WHERE id = 'drawer-p6'",
  ).getSingle();
  return (row.data['current_balance'] as num).toDouble();
}

void main() {
  tearDown(SqliteMigrationManager.resetForTesting);

  test('expected cash is opening balance plus current-session Cash Ledger only', () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);
    final operations = CashOperationService(db);

    await operations.deposit(
      cashLocationId: 'drawer-p6',
      cashDrawerSessionId: 'shift-p6',
      amount: 20,
      idempotencyKey: 'p6-deposit',
    );
    await operations.withdrawal(
      cashLocationId: 'drawer-p6',
      cashDrawerSessionId: 'shift-p6',
      amount: 5,
      idempotencyKey: 'p6-withdraw',
    );

    expect(await AccountingService.calculateCashDrawerExpectedCash('shift-p6'), 115);
  });

  test('shortage close writes immutable ledger, journal and reconciles balance', () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);
    final operations = CashOperationService(db);
    await operations.deposit(
      cashLocationId: 'drawer-p6',
      cashDrawerSessionId: 'shift-p6',
      amount: 20,
      idempotencyKey: 'p6-close-deposit',
    );

    await AccountingService.closeCashDrawer(
      sessionId: 'shift-p6',
      countedCash: 115,
      closedBy: 'tester',
    );

    final session = await db.customSelect(
      "SELECT status, expected_cash, counted_cash, difference FROM cash_drawer_sessions WHERE id = 'shift-p6'",
    ).getSingle();
    expect(session.read<String>('status'), 'closed');
    expect(session.read<double>('expected_cash'), 120);
    expect(session.read<double>('counted_cash'), 115);
    expect(session.read<double>('difference'), -5);
    expect(await _balance(db), 115);

    final ledger = await db.customSelect(
      "SELECT type, direction, amount FROM cash_ledger_transactions WHERE reference_type = 'cash_reconciliation' AND reference_id = 'shift-p6'",
    ).getSingle();
    expect(ledger.read<String>('type'), 'shortage');
    expect(ledger.read<String>('direction'), 'out');
    expect(ledger.read<double>('amount'), 5);

    final journal = await db.customSelect(
      "SELECT status FROM journal_entries WHERE reference_type = 'cash_reconciliation' AND reference_id = 'shift-p6'",
    ).getSingle();
    expect(journal.read<String>('status'), 'posted');
  });

  test('overage close writes cash-in ledger and counted balance', () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);

    await AccountingService.closeCashDrawer(
      sessionId: 'shift-p6',
      countedCash: 108,
      closedBy: 'tester',
    );

    expect(await _balance(db), 108);
    final ledger = await db.customSelect(
      "SELECT type, direction, amount FROM cash_ledger_transactions WHERE reference_id = 'shift-p6' AND type = 'overage'",
    ).getSingle();
    expect(ledger.read<String>('direction'), 'in');
    expect(ledger.read<double>('amount'), 8);
  });

  test('true cash reversal appends opposite ledger row and never deletes original', () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);
    final operation = await CashOperationService(db).deposit(
      cashLocationId: 'drawer-p6',
      cashDrawerSessionId: 'shift-p6',
      amount: 25,
      idempotencyKey: 'p6-reversal-deposit',
    );
    expect(await _balance(db), 125);

    final reversed = await CashReversalService(db).reverseReference(
      referenceType: 'cash_deposit',
      referenceId: operation.id,
      reason: 'Operator correction',
      createdBy: 'tester',
    );
    expect(reversed, 1);
    expect(await _balance(db), 100);

    final rows = await db.customSelect(
      "SELECT type, direction, reversal_of_id FROM cash_ledger_transactions WHERE reference_id = ? OR reversal_of_id <> '' ORDER BY created_at",
      variables: <Variable<Object>>[Variable<String>(operation.id)],
    ).get();
    expect(rows.length, 2);
    expect(rows.last.read<String>('type'), 'reversal');
    expect(rows.last.read<String>('direction'), 'out');
    expect(rows.last.read<String>('reversal_of_id'), isNotEmpty);

    final op = await db.customSelect(
      'SELECT status FROM cash_operations WHERE id = ?',
      variables: <Variable<Object>>[Variable<String>(operation.id)],
    ).getSingle();
    expect(op.read<String>('status'), 'reversed');

    final journals = await db.customSelect(
      "SELECT status, source FROM journal_entries WHERE reference_id = ? ORDER BY created_at",
      variables: <Variable<Object>>[Variable<String>(operation.id)],
    ).get();
    expect(journals.any((row) => row.read<String>('status') == 'reversed'), isTrue);
    expect(journals.any((row) => row.read<String>('source') == 'reversal'), isTrue);
  });
  test('cash sale refund posts journal, ledger out and is idempotent', () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);
    const now = '2026-08-18T12:30:00.000Z';
    await db.customInsert(
      '''
      INSERT INTO receipt_vouchers
        (id, voucher_no, customer_id, customer_name, voucher_date, amount,
         unallocated_amount, currency, payment_method, cash_location_id,
         cash_drawer_session_id, status, created_at, updated_at)
      VALUES ('receipt-p6', 'RC-P6', 'cust-p6', 'Customer P6', ?, 40, 0,
              'USD', 'Cash', 'drawer-p6', 'shift-p6', 'posted', ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(now),
      ],
    );
    await db.customInsert(
      '''
      INSERT INTO payment_allocations
        (id, voucher_type, voucher_id, reference_type, reference_id,
         reference_number, amount, reference_amount, currency,
         reference_currency, exchange_rate, created_at, updated_at)
      VALUES ('alloc-p6', 'receipt', 'receipt-p6', 'sale', 'sale-p6',
              'INV-P6', 40, 40, 'USD', 'USD', 1, ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
      ],
    );

    final service = PaymentVoucherService(db);
    final first = await service.refundSaleCash(
      saleId: 'sale-p6', invoiceNo: 'INV-P6', customerId: 'cust-p6',
      customerName: 'Customer P6', requestedAmount: 25,
      cashLocationId: 'drawer-p6', cashDrawerSessionId: 'shift-p6',
      refundKey: 'return-1', storeId: 'store-1', branchId: 'main', deviceId: 'dev-1',
    );
    final retry = await service.refundSaleCash(
      saleId: 'sale-p6', invoiceNo: 'INV-P6', customerId: 'cust-p6',
      customerName: 'Customer P6', requestedAmount: 25,
      cashLocationId: 'drawer-p6', cashDrawerSessionId: 'shift-p6',
      refundKey: 'return-1', storeId: 'store-1', branchId: 'main', deviceId: 'dev-1',
    );
    expect(first, 25);
    expect(retry, 25);
    expect(await _balance(db), 75);
    final ledger = await db.customSelect(
      "SELECT direction, amount FROM cash_ledger_transactions WHERE type = 'refund' AND reference_id = 'sale-p6:return-1'",
    ).getSingle();
    expect(ledger.read<String>('direction'), 'out');
    expect(ledger.read<double>('amount'), 25);
    final journalCount = await db.customSelect(
      "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'sale_refund' AND reference_id = 'sale-p6:return-1'",
    ).getSingle();
    expect(journalCount.read<int>('c'), 1);
  });

  test('supplier cash refund posts cash-in ledger and is idempotent', () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);
    const now = '2026-08-18T13:00:00.000Z';
    await db.customInsert(
      '''
      INSERT INTO payment_vouchers
        (id, voucher_no, supplier_id, supplier_name, voucher_date, amount,
         unallocated_amount, currency, payment_method, cash_location_id,
         cash_drawer_session_id, status, created_at, updated_at)
      VALUES ('payment-p6', 'PV-P6', 'sup-p6', 'Supplier P6', ?, 30, 0,
              'USD', 'Cash', 'drawer-p6', 'shift-p6', 'posted', ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(now),
      ],
    );
    await db.customInsert(
      '''
      INSERT INTO payment_allocations
        (id, voucher_type, voucher_id, reference_type, reference_id,
         reference_number, amount, reference_amount, currency,
         reference_currency, exchange_rate, created_at, updated_at)
      VALUES ('purchase-alloc-p6', 'payment', 'payment-p6', 'purchase', 'purchase-p6',
              'PO-P6', 30, 30, 'USD', 'USD', 1, ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
      ],
    );

    final service = PaymentVoucherService(db);
    final first = await service.refundPurchaseCash(
      purchaseId: 'purchase-p6',
      purchaseNo: 'PO-P6',
      supplierId: 'sup-p6',
      supplierName: 'Supplier P6',
      cashLocationId: 'drawer-p6',
      cashDrawerSessionId: 'shift-p6',
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );
    final retry = await service.refundPurchaseCash(
      purchaseId: 'purchase-p6',
      purchaseNo: 'PO-P6',
      supplierId: 'sup-p6',
      supplierName: 'Supplier P6',
      cashLocationId: 'drawer-p6',
      cashDrawerSessionId: 'shift-p6',
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );

    expect(first, 30);
    expect(retry, 30);
    expect(await _balance(db), 130);
    final ledger = await db.customSelect(
      "SELECT direction, amount FROM cash_ledger_transactions WHERE type = 'supplier_refund' AND reference_id = 'purchase-p6'",
    ).getSingle();
    expect(ledger.read<String>('direction'), 'in');
    expect(ledger.read<double>('amount'), 30);
    final journalCount = await db.customSelect(
      "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'purchase_refund' AND reference_id = 'purchase-p6'",
    ).getSingle();
    expect(journalCount.read<int>('c'), 1);
  });

}
