import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/cash_phase7_migration_service.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';

Future<VentioDriftDatabase> _openDb() async {
  final db = VentioDriftDatabase(NativeDatabase.memory());
  await db.initializeFoundation();
  return db;
}

Future<void> _seedLegacyReceipt(VentioDriftDatabase db) async {
  const now = '2026-08-01T10:00:00.000Z';
  await db.customInsert(
    '''
    INSERT INTO cash_locations
      (id, code, name, type, account_id, is_default, is_active, current_balance,
       created_at, updated_at, store_id, branch_id, device_id)
    VALUES ('drawer-legacy', 'LEGACY-DRAWER', 'Legacy Drawer', 'cash_drawer',
            'acc_cash', 1, 1, 321, ?, ?, 'store-1', 'main', 'device-1')
    ''',
    variables: const <Variable<Object>>[
      Variable<String>(now),
      Variable<String>(now),
    ],
  );
  await db.customInsert(
    '''
    INSERT INTO account_transactions
      (id, entity_type, created_at, updated_at, deleted_at, device_id, sync_status,
       store_id, branch_id, version, last_modified_by_device_id, sort_index,
       account_type, account_id, account_name, transaction_date, transaction_type,
       reference_id, reference_no, debit, credit, currency, payment_method, note)
    VALUES ('legacy-at-1', 'account_transaction', ?, ?, '', 'device-1', 'synced',
            'store-1', 'main', 1, 'device-1', 1,
            'customer', 'customer-1', 'Legacy Customer', ?, 'paymentReceived',
            '', 'OLD-RC-1', 0, 50, 'USD', 'Cash', 'old receipt')
    ''',
    variables: const <Variable<Object>>[
      Variable<String>(now),
      Variable<String>(now),
      Variable<String>(now),
    ],
  );
}


Future<void> _seedLegacySupplierPayment(VentioDriftDatabase db) async {
  const now = '2026-08-01T11:00:00.000Z';
  await db.customInsert(
    '''
    INSERT INTO cash_locations
      (id, code, name, type, account_id, is_default, is_active, current_balance,
       created_at, updated_at, store_id, branch_id, device_id)
    VALUES ('drawer-supplier', 'SUP-DRAWER', 'Supplier Drawer', 'cash_drawer',
            'acc_cash', 1, 1, 500, ?, ?, 'store-1', 'main', 'device-1')
    ''',
    variables: const <Variable<Object>>[
      Variable<String>(now),
      Variable<String>(now),
    ],
  );
  await db.customInsert(
    '''
    INSERT INTO account_transactions
      (id, entity_type, created_at, updated_at, deleted_at, device_id, sync_status,
       store_id, branch_id, version, last_modified_by_device_id, sort_index,
       account_type, account_id, account_name, transaction_date, transaction_type,
       reference_id, reference_no, debit, credit, currency, payment_method, note)
    VALUES ('legacy-pay-1', 'account_transaction', ?, ?, '', 'device-1', 'synced',
            'store-1', 'main', 1, 'device-1', 1,
            'supplier', 'supplier-1', 'Legacy Supplier', ?, 'paymentPaid',
            '', 'OLD-PAY-1', 75, 0, 'USD', 'Cash', 'old supplier payment')
    ''',
    variables: const <Variable<Object>>[
      Variable<String>(now),
      Variable<String>(now),
      Variable<String>(now),
    ],
  );
}

Future<void> _seedCashReceiptWithoutLocation(VentioDriftDatabase db) async {
  const now = '2026-08-01T12:00:00.000Z';
  await db.customInsert(
    '''
    INSERT INTO account_transactions
      (id, entity_type, created_at, updated_at, deleted_at, device_id, sync_status,
       store_id, branch_id, version, last_modified_by_device_id, sort_index,
       account_type, account_id, account_name, transaction_date, transaction_type,
       reference_id, reference_no, debit, credit, currency, payment_method, note)
    VALUES ('legacy-no-drawer', 'account_transaction', ?, ?, '', 'device-1', 'synced',
            'store-1', 'main', 1, 'device-1', 1,
            'customer', 'customer-2', 'No Drawer Customer', ?, 'paymentReceived',
            '', 'OLD-NO-DRAWER', 0, 25, 'USD', 'Cash', 'missing drawer')
    ''',
    variables: const <Variable<Object>>[
      Variable<String>(now),
      Variable<String>(now),
      Variable<String>(now),
    ],
  );
}

void main() {
  test('phase 7 schema is created by the foundation', () async {
    final db = await _openDb();
    addTearDown(db.close);

    for (final table in <String>['cash_phase7_runs', 'cash_phase7_issues']) {
      final row = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        variables: <Variable<Object>>[Variable<String>(table)],
      ).getSingleOrNull();
      expect(row, isNotNull, reason: '$table should exist');
    }
  });

  test('legacy receipt becomes voucher + journal + ledger without moving cash twice', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedLegacyReceipt(db);

    final first = await CashPhase7MigrationService(db).run();
    expect(first.legacyReceiptsFound, 1);
    expect(first.vouchersCreated, 1);
    expect(first.voucherEntriesCreated, 1);
    expect(first.ledgerRowsCreated, 1);

    final voucher = await db.customSelect(
      "SELECT amount, unallocated_amount FROM receipt_vouchers WHERE id = 'legacy_receipt_legacy-at-1'",
    ).getSingle();
    expect(voucher.read<double>('amount'), 50);
    expect(voucher.read<double>('unallocated_amount'), 50);

    final journalCount = await db.customSelect(
      "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'receipt_voucher' AND reference_id = 'legacy_receipt_legacy-at-1' AND status = 'posted' AND deleted_at = ''",
    ).getSingle();
    expect(journalCount.read<int>('c'), 1);

    final ledgerCount = await db.customSelect(
      "SELECT COUNT(*) AS c FROM cash_ledger_transactions WHERE reference_type = 'receipt_voucher' AND reference_id = 'legacy_receipt_legacy-at-1' AND deleted_at = ''",
    ).getSingle();
    expect(ledgerCount.read<int>('c'), 1);

    final balance = await db.customSelect(
      "SELECT current_balance FROM cash_locations WHERE id = 'drawer-legacy'",
    ).getSingle();
    expect(balance.read<double>('current_balance'), 321,
        reason: 'historical migration must not move live cash');

    final second = await CashPhase7MigrationService(db).run();
    expect(second.legacyReceiptsFound, 0);
    expect(second.vouchersCreated, 0);
    expect(second.voucherEntriesCreated, 0);
    expect(second.ledgerRowsCreated, 0);

    final finalBalance = await db.customSelect(
      "SELECT current_balance FROM cash_locations WHERE id = 'drawer-legacy'",
    ).getSingle();
    expect(finalBalance.read<double>('current_balance'), 321);
  });

  test('legacy supplier cash payment becomes payment voucher without moving cash twice', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedLegacySupplierPayment(db);
    final report = await CashPhase7MigrationService(db).run();
    expect(report.legacyPaymentsFound, 1);
    expect(report.vouchersCreated, 1);
    final voucher = await db.customSelect("SELECT amount, unallocated_amount FROM payment_vouchers WHERE id = 'legacy_payment_legacy-pay-1'").getSingle();
    expect(voucher.read<double>('amount'), 75);
    expect(voucher.read<double>('unallocated_amount'), 75);
    final ledgerCount = await db.customSelect("SELECT COUNT(*) AS c FROM cash_ledger_transactions WHERE reference_type = 'payment_voucher' AND reference_id = 'legacy_payment_legacy-pay-1' AND deleted_at = ''").getSingle();
    expect(ledgerCount.read<int>('c'), 1);
    final balance = await db.customSelect("SELECT current_balance FROM cash_locations WHERE id = 'drawer-supplier'").getSingle();
    expect(balance.read<double>('current_balance'), 500);
  });

  test('cash voucher without resolvable Cash Location blocks Phase 7', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedCashReceiptWithoutLocation(db);
    final report = await CashPhase7MigrationService(db).run();
    expect(report.hasErrors, isTrue);
    expect(report.issues.any((issue) => issue.type == 'missing_cash_location' || issue.type == 'missing_receipt_cash_ledger'), isTrue);
    final run = await db.customSelect('SELECT status FROM cash_phase7_runs WHERE id = ?', variables: <Variable<Object>>[Variable<String>(report.runId)]).getSingle();
    expect(run.read<String>('status'), 'blocked');
  });

  test('allocation/voucher mismatch is reported as blocking', () async {
    final db = await _openDb();
    addTearDown(db.close);
    const now = '2026-08-01T13:00:00.000Z';
    await db.customInsert('''
      INSERT INTO receipt_vouchers
        (id, voucher_no, customer_id, voucher_date, amount, unallocated_amount, payment_method, created_at, updated_at)
      VALUES ('bad-voucher', 'BAD-1', 'customer-x', ?, 100, 100, 'Card', ?, ?)
    ''', variables: const <Variable<Object>>[Variable<String>(now), Variable<String>(now), Variable<String>(now)]);
    await db.customInsert('''
      INSERT INTO payment_allocations
        (id, voucher_type, voucher_id, reference_type, reference_id, reference_number, amount, reference_amount, created_at, updated_at)
      VALUES ('bad-allocation', 'receipt', 'bad-voucher', 'sale', 'missing-sale', 'MISSING', 30, 30, ?, ?)
    ''', variables: const <Variable<Object>>[Variable<String>(now), Variable<String>(now)]);
    final report = await CashPhase7MigrationService(db).run();
    expect(report.hasErrors, isTrue);
    expect(report.issues.any((issue) => issue.type == 'voucher_allocation_mismatch'), isTrue);
    expect(report.issues.any((issue) => issue.type == 'invalid_payment_allocation'), isTrue);
  });

}
