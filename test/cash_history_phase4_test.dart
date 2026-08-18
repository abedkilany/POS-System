import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/cash_ledger_service.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';

Future<VentioDriftDatabase> _openDb() async {
  final db = VentioDriftDatabase(NativeDatabase.memory());
  await db.initializeFoundation();
  return db;
}

Future<void> _seed(VentioDriftDatabase db) async {
  const now = '2026-08-18T12:00:00.000Z';
  await db.customInsert(
    '''
    INSERT INTO cash_locations
      (id, code, name, type, account_id, current_balance, created_at, updated_at,
       store_id, branch_id, device_id)
    VALUES ('drawer-1', 'D1', 'Front Drawer', 'cash_drawer', 'acc-cash', 0, ?, ?, 'store-1', 'main', 'dev-1')
    ''',
    variables: const <Variable<Object>>[Variable<String>(now), Variable<String>(now)],
  );
  await db.customInsert(
    '''
    INSERT INTO cash_drawer_sessions
      (id, drawer_no, cash_location_id, opened_at, status, opening_balance,
       expected_cash, store_id, branch_id, opened_by)
    VALUES ('shift-1', 'SHIFT-1', 'drawer-1', ?, 'open', 100, 100, 'store-1', 'main', 'Cashier')
    ''',
    variables: const <Variable<Object>>[Variable<String>(now)],
  );
}

void main() {
  test('phase 4 history supports SQL filters, search, paging summary and invoice search', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seed(db);
    final service = CashLedgerService(db);

    await service.append(
      id: 'cash-in-1',
      type: 'receipt',
      direction: 'in',
      amount: 30,
      cashLocationId: 'drawer-1',
      cashDrawerSessionId: 'shift-1',
      referenceType: 'receipt_voucher',
      referenceId: 'rv-1',
      referenceNumber: 'RC-1',
      partyName: 'Ahmad',
      createdBy: 'Cashier',
      createdByUserId: 'u-1',
      notes: 'debt payment',
      occurredAt: DateTime.utc(2026, 8, 18, 12, 30),
    );
    await service.append(
      id: 'cash-out-1',
      type: 'supplier_payment',
      direction: 'out',
      amount: 10,
      cashLocationId: 'drawer-1',
      cashDrawerSessionId: 'shift-1',
      referenceType: 'payment_voucher',
      referenceId: 'pv-1',
      referenceNumber: 'PV-1',
      partyName: 'Supplier',
      createdBy: 'Cashier',
      createdByUserId: 'u-1',
      occurredAt: DateTime.utc(2026, 8, 18, 13),
    );
    await db.customInsert(
      '''
      INSERT INTO payment_allocations
        (id, voucher_type, voucher_id, reference_type, reference_id, reference_number,
         amount, reference_amount, currency, reference_currency, exchange_rate,
         created_at, updated_at, last_modified_by_device_id)
      VALUES ('alloc-1', 'receipt', 'rv-1', 'sale', 'sale-1', 'INV-900',
              30, 30, 'USD', 'USD', 1, ?, ?, 'dev-1')
      ''',
      variables: const <Variable<Object>>[
        Variable<String>('2026-08-18T12:30:00.000Z'),
        Variable<String>('2026-08-18T12:30:00.000Z'),
      ],
    );

    final invoiceSearch = await service.list(cashLocationId: 'drawer-1', search: 'INV-900');
    expect(invoiceSearch, hasLength(1));
    expect(invoiceSearch.single.id, 'cash-in-1');

    final incoming = await service.list(cashLocationId: 'drawer-1', direction: 'in');
    expect(incoming.map((item) => item.id), contains('cash-in-1'));
    expect(incoming.map((item) => item.id), isNot(contains('cash-out-1')));

    final summary = await service.summary(cashDrawerSessionId: 'shift-1');
    expect(summary.movementCount, 2);
    expect(summary.cashIn, 30);
    expect(summary.cashOut, 10);
    expect(summary.net, 20);
    expect(await service.count(cashDrawerSessionId: 'shift-1'), 2);
  });

  test('phase 4 details resolve drawer, shift, allocations and journal reference', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seed(db);
    final service = CashLedgerService(db);

    final movement = await service.append(
      id: 'cash-in-1',
      type: 'receipt',
      direction: 'in',
      amount: 25,
      cashLocationId: 'drawer-1',
      cashDrawerSessionId: 'shift-1',
      referenceType: 'receipt_voucher',
      referenceId: 'rv-1',
      referenceNumber: 'RC-1',
    );
    await db.customInsert(
      '''
      INSERT INTO payment_allocations
        (id, voucher_type, voucher_id, reference_type, reference_id, reference_number,
         amount, reference_amount, currency, reference_currency, exchange_rate,
         created_at, updated_at, last_modified_by_device_id)
      VALUES ('alloc-1', 'receipt', 'rv-1', 'sale', 'sale-1', 'INV-1',
              25, 25, 'USD', 'USD', 1, ?, ?, 'dev-1')
      ''',
      variables: const <Variable<Object>>[
        Variable<String>('2026-08-18T12:30:00.000Z'),
        Variable<String>('2026-08-18T12:30:00.000Z'),
      ],
    );
    await db.customInsert(
      '''
      INSERT INTO journal_entries
        (id, entry_no, entry_date, reference_type, reference_id, reference_no,
         description, status, source, created_at, updated_at)
      VALUES ('je-1', 'JE-1', ?, 'receipt_voucher', 'rv-1', 'RC-1',
              'Receipt posting', 'posted', 'system', ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>('2026-08-18T12:30:00.000Z'),
        Variable<String>('2026-08-18T12:30:00.000Z'),
        Variable<String>('2026-08-18T12:30:00.000Z'),
      ],
    );

    final details = await service.detailsFor(movement);
    expect(details.cashLocationName, 'Front Drawer');
    expect(details.sessionNumber, 'SHIFT-1');
    expect(details.journalEntryNo, 'JE-1');
    expect(details.allocationReferences, hasLength(1));
    expect(details.allocationReferences.single.referenceNumber, 'INV-1');
  });

  test('current shift range starts at session opened_at instead of start of today', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await db.customInsert(
      '''
      INSERT INTO cash_locations
        (id, code, name, type, account_id, current_balance, created_at, updated_at,
         store_id, branch_id, device_id)
      VALUES ('drawer-night', 'DN', 'Night Drawer', 'cash_drawer', 'acc-cash', 0, ?, ?, 'store-1', 'main', 'dev-1')
      ''',
      variables: const <Variable<Object>>[
        Variable<String>('2026-08-18T22:00:00.000Z'),
        Variable<String>('2026-08-18T22:00:00.000Z'),
      ],
    );
    await db.customInsert(
      '''
      INSERT INTO cash_drawer_sessions
        (id, drawer_no, cash_location_id, opened_at, status, opening_balance,
         expected_cash, store_id, branch_id, opened_by)
      VALUES ('shift-night', 'SHIFT-NIGHT', 'drawer-night', ?, 'open', 100, 100, 'store-1', 'main', 'Cashier')
      ''',
      variables: const <Variable<Object>>[
        Variable<String>('2026-08-18T22:00:00.000Z'),
      ],
    );
    final service = CashLedgerService(db);
    expect(
      await service.sessionOpenedAt('shift-night'),
      DateTime.parse('2026-08-18T22:00:00.000Z'),
    );
  });

  test('cash page uses phase 4 ledger history instead of accountTransactions history', () {
    final cashPage = File('lib/features/cash/cash_page.dart').readAsStringSync();
    final historyPanel = File('lib/features/cash/cash_history_panel.dart').readAsStringSync();
    expect(cashPage, contains('CashHistoryPanel('));
    expect(historyPanel, contains('CashLedgerService.current()'));
    expect(historyPanel, isNot(contains('accountTransactions')));
  });
}
