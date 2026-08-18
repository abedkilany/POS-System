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

Future<void> _seedDrawer(VentioDriftDatabase db) async {
  const now = '2026-08-18T12:00:00.000Z';
  await db.customInsert(
    '''
    INSERT INTO cash_locations
      (id, code, name, type, account_id, current_balance, created_at, updated_at,
       store_id, branch_id, device_id)
    VALUES (?, ?, ?, 'cash_drawer', ?, 0, ?, ?, ?, ?, ?)
    ''',
    variables: <Variable<Object>>[
      const Variable<String>('drawer-1'),
      const Variable<String>('DRAWER-1'),
      const Variable<String>('Front Drawer'),
      const Variable<String>('acc_main_drawer'),
      const Variable<String>(now),
      const Variable<String>(now),
      const Variable<String>('store-1'),
      const Variable<String>('main'),
      const Variable<String>('dev-1'),
    ],
  );
  await db.customInsert(
    '''
    INSERT INTO cash_drawer_sessions
      (id, drawer_no, cash_location_id, opened_at, status, opening_balance,
       expected_cash, store_id, branch_id)
    VALUES (?, ?, ?, ?, 'open', 100, 100, ?, ?)
    ''',
    variables: <Variable<Object>>[
      const Variable<String>('shift-1'),
      const Variable<String>('SHIFT-1'),
      const Variable<String>('drawer-1'),
      const Variable<String>(now),
      const Variable<String>('store-1'),
      const Variable<String>('main'),
    ],
  );
}

void main() {
  test('foundation creates phase 1 cash ledger schema and indexes', () async {
    final db = await _openDb();
    addTearDown(db.close);

    final table = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'cash_ledger_transactions'",
    ).getSingleOrNull();
    expect(table, isNotNull);

    final indexes = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'cash_ledger_transactions'",
    ).get();
    final names = indexes.map((row) => row.read<String>('name')).toSet();
    expect(names, contains('idx_cash_ledger_session_time'));
    expect(names, contains('idx_cash_ledger_idempotency'));
  });

  test('append writes immutable ledger row linked to open drawer session', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedDrawer(db);
    final service = CashLedgerService(db);

    final movement = await service.append(
      id: 'cash-1',
      type: 'sale_payment',
      direction: 'in',
      amount: 25,
      cashLocationId: 'drawer-1',
      cashDrawerSessionId: 'shift-1',
      referenceType: 'sale',
      referenceId: 'sale-1',
      referenceNumber: 'INV-1',
      deviceId: 'dev-1',
      branchId: 'main',
      storeId: 'store-1',
      idempotencyKey: 'sale-1-payment-1',
    );

    expect(movement.signedAmount, 25);
    final fetched = await service.findById('cash-1');
    expect(fetched, isNotNull);
    expect(fetched!.referenceNumber, 'INV-1');
    expect(await service.movementTotalForSession('shift-1'), 25);
    expect(await service.balanceForLocation('drawer-1'), 25);
  });

  test('idempotency key returns original row instead of duplicating money', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedDrawer(db);
    final service = CashLedgerService(db);

    final first = await service.append(
      id: 'cash-1',
      type: 'cash_in',
      direction: 'in',
      amount: 10,
      cashLocationId: 'drawer-1',
      cashDrawerSessionId: 'shift-1',
      idempotencyKey: 'retry-key-1',
    );
    final retry = await service.append(
      id: 'cash-2',
      type: 'cash_in',
      direction: 'in',
      amount: 10,
      cashLocationId: 'drawer-1',
      cashDrawerSessionId: 'shift-1',
      idempotencyKey: 'retry-key-1',
    );

    expect(retry.id, first.id);
    final rows = await service.list(cashDrawerSessionId: 'shift-1');
    expect(rows, hasLength(1));
  });

  test('rejects invalid drawer/session links and invalid amounts', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedDrawer(db);
    final service = CashLedgerService(db);

    await expectLater(
      service.append(
        type: 'cash_in',
        direction: 'in',
        amount: 5,
        cashLocationId: 'missing',
      ),
      throwsStateError,
    );
    expect(
      () => service.append(
        type: 'cash_in',
        direction: 'in',
        amount: 0,
        cashLocationId: 'drawer-1',
      ),
      throwsArgumentError,
    );
  });
}
