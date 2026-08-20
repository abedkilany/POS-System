import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/cash_ledger_service.dart';
import 'package:ventio/core/services/payment_voucher_service.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/models/payment_allocation.dart';

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

void main() {
  test('foundation creates Phase 2 voucher and allocation schema', () async {
    final db = await _openDb();
    addTearDown(db.close);

    for (final table in <String>[
      'receipt_vouchers',
      'payment_vouchers',
      'payment_allocations',
    ]) {
      final row = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        variables: <Variable<Object>>[Variable<String>(table)],
      ).getSingleOrNull();
      expect(row, isNotNull, reason: '$table must exist');
    }
  });

  test('cash receipt supports multi-invoice allocation and unallocated credit', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedDrawer(db);
    await _seedSale(db, id: 'sale-1', invoiceNo: 'INV-1', customerId: 'cust-1', total: 50);
    await _seedSale(db, id: 'sale-2', invoiceNo: 'INV-2', customerId: 'cust-1', total: 100);

    final service = PaymentVoucherService(db);
    final receipt = await service.createReceipt(
      id: 'receipt-1',
      voucherNo: 'RC-1',
      customerId: 'cust-1',
      customerName: 'Customer',
      amount: 80,
      cashLocationId: 'drawer-1',
      cashDrawerSessionId: 'shift-1',
      deviceId: 'dev-1',
      storeId: 'store-1',
      branchId: 'main',
      idempotencyKey: 'receipt-retry-1',
      allocations: const <PaymentAllocationDraft>[
        PaymentAllocationDraft(referenceId: 'sale-1', amount: 30),
        PaymentAllocationDraft(referenceId: 'sale-2', amount: 40),
      ],
    );

    expect(receipt.allocations, hasLength(2));
    expect(receipt.unallocatedAmount, 10);

    final sale1 = await db.customSelect("SELECT paid_amount FROM sales WHERE id = 'sale-1'").getSingle();
    final sale2 = await db.customSelect("SELECT paid_amount FROM sales WHERE id = 'sale-2'").getSingle();
    expect((sale1.data['paid_amount'] as num).toDouble(), 30);
    expect((sale2.data['paid_amount'] as num).toDouble(), 40);

    final ledger = await CashLedgerService(db).list(referenceType: 'receipt_voucher', referenceId: 'receipt-1');
    expect(ledger, hasLength(1));
    expect(ledger.single.amount, 80, reason: 'ledger tracks cash received, not only allocated amount');
    expect(ledger.single.direction, 'in');

    final location = await db.customSelect("SELECT current_balance FROM cash_locations WHERE id = 'drawer-1'").getSingle();
    expect((location.data['current_balance'] as num).toDouble(), 180);

    final journal = await db.customSelect(
      "SELECT id FROM journal_entries WHERE reference_type = 'receipt_voucher' AND reference_id = 'receipt-1' AND status = 'posted' AND deleted_at = ''",
    ).get();
    expect(journal, hasLength(1));
    final lines = await db.customSelect(
      'SELECT account_id, debit, credit FROM journal_lines WHERE entry_id = ? ORDER BY line_no',
      variables: <Variable<Object>>[Variable<String>(journal.single.data['id'].toString())],
    ).get();
    expect(lines, hasLength(2));
    expect(lines[0].data['account_id'], 'acc_main_drawer');
    expect((lines[0].data['debit'] as num).toDouble(), 80);
    expect(lines[1].data['account_id'], 'acc_customers');
    expect((lines[1].data['credit'] as num).toDouble(), 80);
  });

  test('cash supplier payment allocates purchase and writes one cash-out movement', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedDrawer(db);
    await _seedPurchase(db, id: 'purchase-1', purchaseNo: 'PUR-1', supplierId: 'sup-1', total: 100, paid: 10);

    final service = PaymentVoucherService(db);
    final payment = await service.createPayment(
      id: 'payment-1',
      voucherNo: 'PV-1',
      supplierId: 'sup-1',
      supplierName: 'Supplier',
      amount: 40,
      cashLocationId: 'drawer-1',
      cashDrawerSessionId: 'shift-1',
      deviceId: 'dev-1',
      allocations: const <PaymentAllocationDraft>[
        PaymentAllocationDraft(referenceId: 'purchase-1', amount: 40),
      ],
    );

    expect(payment.unallocatedAmount, 0);
    final purchase = await db.customSelect("SELECT paid_amount FROM purchases WHERE id = 'purchase-1'").getSingle();
    expect((purchase.data['paid_amount'] as num).toDouble(), 50);

    final ledger = await CashLedgerService(db).list(referenceType: 'payment_voucher', referenceId: 'payment-1');
    expect(ledger, hasLength(1));
    expect(ledger.single.direction, 'out');
    expect(ledger.single.amount, 40);

    final journal = await db.customSelect(
      "SELECT id FROM journal_entries WHERE reference_type = 'payment_voucher' AND reference_id = 'payment-1' AND status = 'posted' AND deleted_at = ''",
    ).get();
    expect(journal, hasLength(1));
    final lines = await db.customSelect(
      'SELECT account_id, debit, credit FROM journal_lines WHERE entry_id = ? ORDER BY line_no',
      variables: <Variable<Object>>[Variable<String>(journal.single.data['id'].toString())],
    ).get();
    expect(lines, hasLength(2));
    expect(lines[0].data['account_id'], 'acc_suppliers');
    expect((lines[0].data['debit'] as num).toDouble(), 40);
    expect(lines[1].data['account_id'], 'acc_main_drawer');
    expect((lines[1].data['credit'] as num).toDouble(), 40);
  });

  test('voucher idempotency does not duplicate allocations, cache, or ledger', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedDrawer(db);
    await _seedSale(db, id: 'sale-1', invoiceNo: 'INV-1', customerId: 'cust-1', total: 100);
    final service = PaymentVoucherService(db);

    final first = await service.createReceipt(
      id: 'receipt-1', customerId: 'cust-1', customerName: 'Customer', amount: 25,
      cashLocationId: 'drawer-1', cashDrawerSessionId: 'shift-1', idempotencyKey: 'same-receipt',
      allocations: const <PaymentAllocationDraft>[PaymentAllocationDraft(referenceId: 'sale-1', amount: 25)],
    );
    final retry = await service.createReceipt(
      id: 'different-id', customerId: 'cust-1', customerName: 'Customer', amount: 25,
      cashLocationId: 'drawer-1', cashDrawerSessionId: 'shift-1', idempotencyKey: 'same-receipt',
      allocations: const <PaymentAllocationDraft>[PaymentAllocationDraft(referenceId: 'sale-1', amount: 25)],
    );

    expect(retry.id, first.id);
    final allocations = await service.allocationsFor('receipt', first.id);
    expect(allocations, hasLength(1));
    final sale = await db.customSelect("SELECT paid_amount FROM sales WHERE id = 'sale-1'").getSingle();
    expect((sale.data['paid_amount'] as num).toDouble(), 25);
    final ledger = await CashLedgerService(db).list(referenceId: first.id);
    expect(ledger, hasLength(1));
    final journal = await db.customSelect(
      "SELECT id FROM journal_entries WHERE reference_type = 'receipt_voucher' AND reference_id = ? AND status = 'posted' AND deleted_at = ''",
      variables: <Variable<Object>>[Variable<String>(first.id)],
    ).get();
    expect(journal, hasLength(1), reason: 'retry must not duplicate accounting posting');
  });

  test('retry backfills a missing voucher journal without duplicating financial effects', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedDrawer(db);
    await _seedSale(db, id: 'sale-1', invoiceNo: 'INV-1', customerId: 'cust-1', total: 100);
    final service = PaymentVoucherService(db);

    final first = await service.createReceipt(
      id: 'receipt-backfill',
      customerId: 'cust-1',
      customerName: 'Customer',
      amount: 20,
      cashLocationId: 'drawer-1',
      cashDrawerSessionId: 'shift-1',
      idempotencyKey: 'receipt-backfill-key',
      allocations: const <PaymentAllocationDraft>[
        PaymentAllocationDraft(referenceId: 'sale-1', amount: 20),
      ],
    );
    final firstJournal = await db.customSelect(
      "SELECT id FROM journal_entries WHERE reference_type = 'receipt_voucher' AND reference_id = ?",
      variables: <Variable<Object>>[Variable<String>(first.id)],
    ).getSingle();
    await db.customUpdate(
      'DELETE FROM journal_entries WHERE id = ?',
      variables: <Variable<Object>>[Variable<String>(firstJournal.data['id'].toString())],
    );

    final retry = await service.createReceipt(
      id: 'another-id',
      customerId: 'cust-1',
      customerName: 'Customer',
      amount: 20,
      cashLocationId: 'drawer-1',
      cashDrawerSessionId: 'shift-1',
      idempotencyKey: 'receipt-backfill-key',
      allocations: const <PaymentAllocationDraft>[
        PaymentAllocationDraft(referenceId: 'sale-1', amount: 20),
      ],
    );
    expect(retry.id, first.id);
    final journal = await db.customSelect(
      "SELECT id FROM journal_entries WHERE reference_type = 'receipt_voucher' AND reference_id = ? AND status = 'posted' AND deleted_at = ''",
      variables: <Variable<Object>>[Variable<String>(first.id)],
    ).get();
    expect(journal, hasLength(1));
    final sale = await db.customSelect("SELECT paid_amount FROM sales WHERE id = 'sale-1'").getSingle();
    expect((sale.data['paid_amount'] as num).toDouble(), 20);
    final ledger = await CashLedgerService(db).list(referenceId: first.id);
    expect(ledger, hasLength(1));
    final location = await db.customSelect("SELECT current_balance FROM cash_locations WHERE id = 'drawer-1'").getSingle();
    expect((location.data['current_balance'] as num).toDouble(), 120);
  });

  test('rejects over-allocation and allocation to another customer', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedDrawer(db);
    await _seedSale(db, id: 'sale-1', invoiceNo: 'INV-1', customerId: 'cust-2', total: 30);
    final service = PaymentVoucherService(db);

    await expectLater(
      service.createReceipt(
        customerId: 'cust-1', customerName: 'Customer', amount: 20,
        cashLocationId: 'drawer-1', cashDrawerSessionId: 'shift-1',
        allocations: const <PaymentAllocationDraft>[PaymentAllocationDraft(referenceId: 'sale-1', amount: 20)],
      ),
      throwsStateError,
    );

    await expectLater(
      service.createReceipt(
        customerId: 'cust-2', customerName: 'Customer', amount: 40,
        cashLocationId: 'drawer-1', cashDrawerSessionId: 'shift-1',
        allocations: const <PaymentAllocationDraft>[PaymentAllocationDraft(referenceId: 'sale-1', amount: 40)],
      ),
      throwsStateError,
    );
  });

  test('non-cash receipt does not require drawer and does not touch cash ledger', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedSale(db, id: 'sale-1', invoiceNo: 'INV-1', customerId: 'cust-1', total: 100);
    final service = PaymentVoucherService(db);

    await service.createReceipt(
      id: 'bank-receipt', customerId: 'cust-1', customerName: 'Customer', amount: 15,
      paymentMethod: 'Bank Transfer',
      allocations: const <PaymentAllocationDraft>[PaymentAllocationDraft(referenceId: 'sale-1', amount: 15)],
    );

    final ledger = await CashLedgerService(db).list(referenceId: 'bank-receipt');
    expect(ledger, isEmpty);
    final journal = await db.customSelect(
      "SELECT id FROM journal_entries WHERE reference_type = 'receipt_voucher' AND reference_id = 'bank-receipt' AND status = 'posted' AND deleted_at = ''",
    ).get();
    expect(journal, hasLength(1), reason: 'non-cash vouchers still require accounting posting');
    final lines = await db.customSelect(
      'SELECT account_id FROM journal_lines WHERE entry_id = ? ORDER BY line_no',
      variables: <Variable<Object>>[Variable<String>(journal.single.data['id'].toString())],
    ).get();
    expect(lines.first.data['account_id'], 'acc_bank');
  });
  test('legacy cash vouchers are backfilled into Cash Ledger without changing balance', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedDrawer(db);
    const oldDate = '2026-07-01T09:30:00.000Z';

    await db.customInsert(r'''
      INSERT INTO receipt_vouchers
        (id, voucher_no, customer_id, customer_name, voucher_date, amount,
         unallocated_amount, currency, payment_method, cash_location_id,
         cash_drawer_session_id, status, created_at, updated_at, deleted_at,
         version, last_modified_by_device_id)
      VALUES ('legacy-rv-1', 'RC-OLD-1', 'cust-old', 'Old Customer', ?, 25,
              25, 'USD', 'Cash', 'drawer-1', 'shift-1', 'posted', ?, ?, '', 1, 'dev-1')
    ''', variables: const <Variable<Object>>[
      Variable<String>(oldDate), Variable<String>(oldDate), Variable<String>(oldDate),
    ]);
    await db.customInsert(r'''
      INSERT INTO payment_vouchers
        (id, voucher_no, supplier_id, supplier_name, voucher_date, amount,
         unallocated_amount, currency, payment_method, cash_location_id,
         cash_drawer_session_id, status, created_at, updated_at, deleted_at,
         version, last_modified_by_device_id)
      VALUES ('legacy-pv-1', 'PV-OLD-1', 'sup-old', 'Old Supplier', ?, 10,
              10, 'USD', 'Cash', 'drawer-1', 'shift-1', 'posted', ?, ?, '', 1, 'dev-1')
    ''', variables: const <Variable<Object>>[
      Variable<String>(oldDate), Variable<String>(oldDate), Variable<String>(oldDate),
    ]);

    final service = PaymentVoucherService(db);
    await service.backfillLegacyCashLedger();
    await service.backfillLegacyCashLedger();

    final rows = await db.customSelect(
      "SELECT type, direction, amount, reference_type, reference_id, reference_number FROM cash_ledger_transactions WHERE reference_id IN ('legacy-rv-1', 'legacy-pv-1') ORDER BY reference_id",
    ).get();
    expect(rows, hasLength(2), reason: 'backfill must be idempotent');
    expect(rows[0].data['reference_type'], 'payment_voucher');
    expect(rows[0].data['direction'], 'out');
    expect(rows[0].data['reference_number'], 'PV-OLD-1');
    expect(rows[1].data['reference_type'], 'receipt_voucher');
    expect(rows[1].data['direction'], 'in');
    expect(rows[1].data['reference_number'], 'RC-OLD-1');

    final balance = await db.customSelect(
      "SELECT current_balance FROM cash_locations WHERE id = 'drawer-1'",
    ).getSingle();
    expect((balance.data['current_balance'] as num).toDouble(), 100,
        reason: 'historical backfill must not move the live cash balance');
  });

  test('pre-voucher legacy account payments are backfilled into Cash Ledger', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedDrawer(db);
    const oldDate = '2026-05-10T08:15:00.000Z';

    await db.customInsert(r'''
      INSERT INTO account_transactions
        (id, entity_type, created_at, updated_at, deleted_at, device_id, sync_status,
         store_id, branch_id, version, sort_index, account_type, account_id,
         account_name, transaction_date, transaction_type, reference_id,
         reference_no, debit, credit, currency, payment_method, note,
         last_modified_by_device_id)
      VALUES
        ('old-customer-receipt', 'account_transaction', ?, ?, '', 'dev-1', 'synced',
         'store-1', 'main', 1, 0, 'customer', 'cust-old', 'Old Customer', ?,
         'paymentReceived', 'sale-old', 'INV-OLD', 0, 40, 'USD', 'Cash',
         'Legacy receipt before voucher tables', 'dev-1'),
        ('old-supplier-payment', 'account_transaction', ?, ?, '', 'dev-1', 'synced',
         'store-1', 'main', 1, 0, 'supplier', 'sup-old', 'Old Supplier', ?,
         'paymentPaid', 'purchase-old', 'PUR-OLD', 12, 0, 'USD', 'Cash',
         'Legacy payment before voucher tables', 'dev-1')
    ''', variables: const <Variable<Object>>[
      Variable<String>(oldDate), Variable<String>(oldDate), Variable<String>(oldDate),
      Variable<String>(oldDate), Variable<String>(oldDate), Variable<String>(oldDate),
    ]);

    final service = PaymentVoucherService(db);
    await service.backfillLegacyCashLedger();
    await service.backfillLegacyCashLedger();

    final rows = await db.customSelect(
      "SELECT type, direction, amount, cash_location_id, reference_type, reference_id, reference_number "
      "FROM cash_ledger_transactions WHERE reference_type = 'legacy_account_transaction' ORDER BY reference_id",
    ).get();
    expect(rows, hasLength(2), reason: 'pre-voucher backfill must be idempotent');
    expect(rows[0].data['reference_id'], 'old-customer-receipt');
    expect(rows[0].data['type'], 'receipt');
    expect(rows[0].data['direction'], 'in');
    expect((rows[0].data['amount'] as num).toDouble(), 40);
    expect(rows[0].data['cash_location_id'], 'drawer-1');
    expect(rows[1].data['reference_id'], 'old-supplier-payment');
    expect(rows[1].data['direction'], 'out');
    expect((rows[1].data['amount'] as num).toDouble(), 12);

    final balance = await db.customSelect(
      "SELECT current_balance FROM cash_locations WHERE id = 'drawer-1'",
    ).getSingle();
    expect((balance.data['current_balance'] as num).toDouble(), 100,
        reason: 'legacy account-transaction backfill must not change live balance');
  });


  // Phase 9 regression: voucher posting and compatibility account ledger must
  // commit together. These assertions read SQLite directly, not AppStore RAM.
  test('Phase 9 receipt/payment persist account ledger in voucher transaction', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedDrawer(db);
    await _seedSale(db, id: 'sale-p9', invoiceNo: 'INV-P9', customerId: 'cust-p9', total: 50);
    await _seedPurchase(db, id: 'purchase-p9', purchaseNo: 'PUR-P9', supplierId: 'sup-p9', total: 50);
    final service = PaymentVoucherService(db);

    await service.createReceipt(
      id: 'receipt-p9', voucherNo: 'RC-P9', customerId: 'cust-p9', customerName: 'Customer',
      amount: 20, cashLocationId: 'drawer-1', cashDrawerSessionId: 'shift-1',
      deviceId: 'dev-1', storeId: 'store-1', branchId: 'main',
      allocations: const <PaymentAllocationDraft>[
        PaymentAllocationDraft(referenceId: 'sale-p9', referenceNumber: 'INV-P9', amount: 20),
      ],
    );
    final customerMovement = await db.customSelect(
      "SELECT credit FROM account_transactions WHERE id = 'receipt-p9-customer-payment' AND deleted_at = ''",
    ).getSingleOrNull();
    expect(customerMovement, isNotNull);
    expect((customerMovement!.data['credit'] as num).toDouble(), 20);

    await service.createPayment(
      id: 'payment-p9', voucherNo: 'PV-P9', supplierId: 'sup-p9', supplierName: 'Supplier',
      amount: 15, cashLocationId: 'drawer-1', cashDrawerSessionId: 'shift-1',
      deviceId: 'dev-1', storeId: 'store-1', branchId: 'main',
      allocations: const <PaymentAllocationDraft>[
        PaymentAllocationDraft(referenceId: 'purchase-p9', referenceNumber: 'PUR-P9', amount: 15),
      ],
    );
    final supplierMovement = await db.customSelect(
      "SELECT debit FROM account_transactions WHERE id = 'payment-p9-supplier-payment' AND deleted_at = ''",
    ).getSingleOrNull();
    expect(supplierMovement, isNotNull);
    expect((supplierMovement!.data['debit'] as num).toDouble(), 15);
  });

  test('Phase 9 voucher reversal persists matching account-ledger reversal', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedDrawer(db);
    await _seedSale(db, id: 'sale-rev-p9', invoiceNo: 'INV-REV-P9', customerId: 'cust-rev-p9', total: 40);
    final service = PaymentVoucherService(db);
    await service.createReceipt(
      id: 'receipt-rev-p9', voucherNo: 'RC-REV-P9', customerId: 'cust-rev-p9', customerName: 'Customer',
      amount: 10, cashLocationId: 'drawer-1', cashDrawerSessionId: 'shift-1',
      deviceId: 'dev-1', storeId: 'store-1', branchId: 'main',
      allocations: const <PaymentAllocationDraft>[
        PaymentAllocationDraft(referenceId: 'sale-rev-p9', referenceNumber: 'INV-REV-P9', amount: 10),
      ],
    );
    expect(await service.reverseReceiptVoucher(voucherId: 'receipt-rev-p9', deviceId: 'dev-1'), isTrue);
    final reversal = await db.customSelect(
      "SELECT debit, credit FROM account_transactions WHERE id = 'receipt-rev-p9-customer-payment-reversal' AND deleted_at = ''",
    ).getSingleOrNull();
    expect(reversal, isNotNull);
    expect((reversal!.data['debit'] as num).toDouble(), 10);
    expect((reversal.data['credit'] as num).toDouble(), 0);
  });
  test('Phase 9 account-ledger failure rolls back the whole receipt transaction', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seedDrawer(db);
    await _seedSale(db, id: 'sale-fail-p9', invoiceNo: 'INV-FAIL-P9', customerId: 'cust-fail-p9', total: 50);
    await db.customStatement('''
      CREATE TRIGGER p9_fail_account_transaction
      BEFORE INSERT ON account_transactions
      WHEN NEW.id = 'receipt-fail-p9-customer-payment'
      BEGIN
        SELECT RAISE(ABORT, 'forced account ledger failure');
      END;
    ''');
    final service = PaymentVoucherService(db);
    await expectLater(
      service.createReceipt(
        id: 'receipt-fail-p9', voucherNo: 'RC-FAIL-P9',
        customerId: 'cust-fail-p9', customerName: 'Customer', amount: 10,
        cashLocationId: 'drawer-1', cashDrawerSessionId: 'shift-1',
        deviceId: 'dev-1', storeId: 'store-1', branchId: 'main',
        allocations: const <PaymentAllocationDraft>[
          PaymentAllocationDraft(referenceId: 'sale-fail-p9', referenceNumber: 'INV-FAIL-P9', amount: 10),
        ],
      ),
      throwsA(anything),
    );
    expect(await db.customSelect("SELECT id FROM receipt_vouchers WHERE id = 'receipt-fail-p9'").getSingleOrNull(), isNull);
    expect(await db.customSelect("SELECT id FROM journal_entries WHERE reference_type = 'receipt_voucher' AND reference_id = 'receipt-fail-p9'").getSingleOrNull(), isNull);
    expect(await db.customSelect("SELECT id FROM cash_ledger_transactions WHERE reference_type = 'receipt_voucher' AND reference_id = 'receipt-fail-p9'").getSingleOrNull(), isNull);
    final balance = await db.customSelect("SELECT current_balance FROM cash_locations WHERE id = 'drawer-1'").getSingle();
    expect((balance.data['current_balance'] as num).toDouble(), 100);
    final sale = await db.customSelect("SELECT paid_amount FROM sales WHERE id = 'sale-fail-p9'").getSingle();
    expect((sale.data['paid_amount'] as num).toDouble(), 0);
  });

}
