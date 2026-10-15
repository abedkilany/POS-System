part of 'payment_voucher_phase2_test.dart';

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
    VALUES ('drawer-1', 'DRAWER-1', 'Front Drawer', 'cash_drawer', 'acc_main_drawer',
            100, ?, ?, 'store-1', 'main', 'dev-1')
    ''',
    variables: <Variable<Object>>[
      const Variable<String>(now),
      const Variable<String>(now),
    ],
  );
  await db.customInsert(
    '''
    INSERT INTO cash_drawer_sessions
      (id, drawer_no, cash_location_id, opened_at, status, opening_balance,
       expected_cash, store_id, branch_id)
    VALUES ('shift-1', 'SHIFT-1', 'drawer-1', ?, 'open', 100, 100, 'store-1', 'main')
    ''',
    variables: <Variable<Object>>[const Variable<String>(now)],
  );
}

Future<void> _seedSale(
  VentioDriftDatabase db, {
  required String id,
  required String invoiceNo,
  required String customerId,
  required double total,
  double paid = 0,
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
            ?, ?, 'Customer', ?, 'Paid', 0, 'Credit', 'partial', 'USD', ?, ?)
    ''',
    variables: <Variable<Object>>[
      Variable<String>(id),
      const Variable<String>(now),
      const Variable<String>(now),
      Variable<String>(invoiceNo),
      Variable<String>(customerId),
      const Variable<String>(now),
      Variable<double>(total),
      Variable<double>(paid),
    ],
  );
}

Future<void> _seedPurchase(
  VentioDriftDatabase db, {
  required String id,
  required String purchaseNo,
  required String supplierId,
  required double total,
  double paid = 0,
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
            ?, ?, 'Supplier', ?, 'Received', 'Credit', 'partial', ?)
    ''',
    variables: <Variable<Object>>[
      Variable<String>(id),
      const Variable<String>(now),
      const Variable<String>(now),
      Variable<String>(purchaseNo),
      Variable<String>(supplierId),
      const Variable<String>(now),
      Variable<double>(paid),
    ],
  );
  await db.customInsert(
    '''
    INSERT INTO purchase_items
      (id, purchase_id, line_no, product_id, product_name, quantity, unit_cost,
       purchase_unit_id, purchase_unit_name, conversion_to_base)
    VALUES (?, ?, 0, 'product-1', 'Item', 1, ?, 'base', 'Unit', 1)
    ''',
    variables: <Variable<Object>>[
      Variable<String>('item-$id'),
      Variable<String>(id),
      Variable<double>(total),
    ],
  );
}
