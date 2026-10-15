import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/test_business_session_context.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/core/services/cash_operation_service.dart';
import 'package:ventio/core/services/cash_reversal_service.dart';
import 'package:ventio/core/services/payment_voucher_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/models/payment_allocation.dart';

part 'cash_phase6_test_registration_01.dart';
part 'cash_phase6_test_registration_02.dart';

TestBusinessSessionContext get _authorization => TestBusinessSessionContext();

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
  final row = await db
      .customSelect(
        "SELECT current_balance FROM cash_locations WHERE id = 'drawer-p6'",
      )
      .getSingle();
  return (row.data['current_balance'] as num).toDouble();
}

Future<void> _seedSaleP6(
  VentioDriftDatabase db, {
  required String id,
  required String invoiceNo,
  required String customerId,
  required double total,
}) async {
  const now = '2026-08-18T12:00:00.000Z';
  await db.customInsert(
    '''
    INSERT INTO sales
      (id, entity_type, created_at, updated_at, deleted_at, device_id, sync_status,
       store_id, branch_id, version, sort_index, invoice_no, customer_id,
       customer_name, document_date, status, discount, payment_method,
       payment_status, invoice_currency, transaction_amount, paid_amount)
    VALUES (?, 'sale', ?, ?, '', 'dev-1', 'synced', 'store-1', 'main', 1, 0,
            ?, ?, 'Customer P6', ?, 'Paid', 0, 'Credit', 'unpaid', 'USD', ?, 0)
    ''',
    variables: <Variable<Object>>[
      Variable<String>(id),
      const Variable<String>(now),
      const Variable<String>(now),
      Variable<String>(invoiceNo),
      Variable<String>(customerId),
      const Variable<String>(now),
      Variable<double>(total),
    ],
  );
}

Future<void> _seedPurchaseP6(
  VentioDriftDatabase db, {
  required String id,
  required String purchaseNo,
  required String supplierId,
  required double total,
}) async {
  const now = '2026-08-18T12:00:00.000Z';
  await db.customInsert(
    '''
    INSERT INTO purchases
      (id, entity_type, created_at, updated_at, deleted_at, device_id, sync_status,
       store_id, branch_id, version, sort_index, purchase_no, supplier_id,
       supplier_name, document_date, status, payment_method, payment_status,
       paid_amount)
    VALUES (?, 'purchase', ?, ?, '', 'dev-1', 'synced', 'store-1', 'main', 1, 0,
            ?, ?, 'Supplier P6', ?, 'Received', 'Credit', 'unpaid', 0)
    ''',
    variables: <Variable<Object>>[
      Variable<String>(id),
      const Variable<String>(now),
      const Variable<String>(now),
      Variable<String>(purchaseNo),
      Variable<String>(supplierId),
      const Variable<String>(now),
    ],
  );
  await db.customInsert(
    '''
    INSERT INTO purchase_items
      (id, purchase_id, line_no, product_id, product_name, quantity, unit_cost,
       purchase_unit_id, purchase_unit_name, conversion_to_base)
    VALUES (?, ?, 0, 'product-p6', 'Item P6', 1, ?, 'base', 'Unit', 1)
    ''',
    variables: <Variable<Object>>[
      Variable<String>('item-$id'),
      Variable<String>(id),
      Variable<double>(total),
    ],
  );
}

void main() {
  tearDown(SqliteMigrationManager.resetForTesting);

  _registerCashPhase6TestsPart1();
  _registerCashPhase6TestsPart2();
}
