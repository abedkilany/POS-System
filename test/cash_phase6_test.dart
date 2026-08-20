import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/core/services/cash_operation_service.dart';
import 'package:ventio/core/services/cash_reversal_service.dart';
import 'package:ventio/core/services/payment_voucher_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/models/payment_allocation.dart';

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

  test('expected cash is opening balance plus current-session Cash Ledger only', () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);
    final operations = CashOperationService(db);

    await operations.deposit(
      cashLocationId: 'drawer-p6',
      cashDrawerSessionId: 'shift-p6',
      counterpartAccountId: 'acc_owner_capital',
      amount: 20,
      idempotencyKey: 'p6-deposit',
    );
    await operations.withdrawal(
      cashLocationId: 'drawer-p6',
      cashDrawerSessionId: 'shift-p6',
      counterpartAccountId: 'acc_owner_capital',
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
      counterpartAccountId: 'acc_owner_capital',
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
      counterpartAccountId: 'acc_owner_capital',
      amount: 25,
      idempotencyKey: 'p6-reversal-deposit',
    );
    expect(await _balance(db), 125);

    final reversed = await CashReversalService(db).reverseReference(
      referenceType: 'cash_deposit',
      referenceId: operation.id,
      reason: 'Operator correction',
      createdBy: 'Test Operator',
      createdByUserId: 'user-p6',
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
      'SELECT status, reversed_at, reversal_reason, reversed_by, reversed_by_user_id FROM cash_operations WHERE id = ?',
      variables: <Variable<Object>>[Variable<String>(operation.id)],
    ).getSingle();
    expect(op.read<String>('status'), 'reversed');
    expect(op.read<String>('reversed_at'), isNotEmpty);
    expect(op.read<String>('reversal_reason'), 'Operator correction');
    expect(op.read<String>('reversed_by'), 'Test Operator');
    expect(op.read<String>('reversed_by_user_id'), 'user-p6');

    final journals = await db.customSelect(
      "SELECT status, source FROM journal_entries WHERE reference_id = ? ORDER BY created_at",
      variables: <Variable<Object>>[Variable<String>(operation.id)],
    ).get();
    expect(journals.any((row) => row.read<String>('status') == 'reversed'), isTrue);
    expect(journals.any((row) => row.read<String>('source') == 'reversal'), isTrue);

    final retry = await CashReversalService(db).reverseReference(
      referenceType: 'cash_deposit',
      referenceId: operation.id,
      reason: 'Retry should be ignored',
      createdBy: 'Another Operator',
      createdByUserId: 'other-user',
    );
    expect(retry, 0);
    expect(await _balance(db), 100);
    final opAfterRetry = await db.customSelect(
      'SELECT reversal_reason, reversed_by, reversed_by_user_id FROM cash_operations WHERE id = ?',
      variables: <Variable<Object>>[Variable<String>(operation.id)],
    ).getSingle();
    expect(opAfterRetry.read<String>('reversal_reason'), 'Operator correction');
    expect(opAfterRetry.read<String>('reversed_by'), 'Test Operator');
    expect(opAfterRetry.read<String>('reversed_by_user_id'), 'user-p6');
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
    final supplierRefundLedger = await db.customSelect(
      "SELECT id FROM cash_ledger_transactions WHERE type = 'supplier_refund' AND reference_id = 'purchase-p6' AND reversal_of_id = ''",
    ).getSingle();
    final supplierRefundLedgerId = supplierRefundLedger.read<String>('id');
    final supplierRefundAccount = await db.customSelect(
      "SELECT transaction_type, debit, credit FROM account_transactions WHERE id = ? AND deleted_at = ''",
      variables: <Variable<Object>>[
        Variable<String>('$supplierRefundLedgerId-supplier-refund'),
      ],
    ).getSingle();
    expect(supplierRefundAccount.read<String>('transaction_type'), 'paymentReversal');
    expect(supplierRefundAccount.read<double>('debit'), 0);
    expect(supplierRefundAccount.read<double>('credit'), 30);

    final reversed = await CashReversalService(db).reverseReference(
      referenceType: 'purchase_refund',
      referenceId: 'purchase-p6',
      reason: 'Supplier refund cancelled',
      createdBy: 'tester',
      createdByUserId: 'user-p6',
      deviceId: 'dev-1',
    );
    expect(reversed, 1);
    expect(await _balance(db), 100);
    expect(await service.refundableCashForPurchase('purchase-p6'), 30);
    final accountReversalCount = await db.customSelect(
      "SELECT COUNT(*) AS c FROM account_transactions WHERE id = ? AND deleted_at = ''",
      variables: <Variable<Object>>[
        Variable<String>('$supplierRefundLedgerId-supplier-refund-reversal'),
      ],
    ).getSingle();
    expect(accountReversalCount.read<int>('c'), 1);

    final refundedAgain = await service.refundPurchaseCash(
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
    expect(refundedAgain, 30);
    expect(await _balance(db), 130);
    final originalRefundCount = await db.customSelect(
      "SELECT COUNT(*) AS c FROM cash_ledger_transactions WHERE type = 'supplier_refund' AND reference_type = 'purchase_refund' AND reference_id = 'purchase-p6' AND reversal_of_id = ''",
    ).getSingle();
    expect(originalRefundCount.read<int>('c'), 2);
  });

  test('receipt voucher reversal restores cash and invoice allocation cache exactly once', () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);
    await _seedSaleP6(
      db,
      id: 'sale-voucher-p6',
      invoiceNo: 'INV-VOUCHER-P6',
      customerId: 'cust-voucher-p6',
      total: 100,
    );

    final service = PaymentVoucherService(db);
    await service.createReceipt(
      id: 'receipt-reverse-p6',
      voucherNo: 'RC-REVERSE-P6',
      customerId: 'cust-voucher-p6',
      customerName: 'Customer P6',
      amount: 40,
      cashLocationId: 'drawer-p6',
      cashDrawerSessionId: 'shift-p6',
      deviceId: 'dev-1',
      storeId: 'store-1',
      branchId: 'main',
      allocations: const <PaymentAllocationDraft>[
        PaymentAllocationDraft(referenceId: 'sale-voucher-p6', amount: 40),
      ],
    );
    expect(await _balance(db), 140);

    final reversed = await CashReversalService(db).reverseReference(
      referenceType: 'receipt_voucher',
      referenceId: 'receipt-reverse-p6',
      reason: 'Wrong receipt',
      createdBy: 'tester',
      createdByUserId: 'user-p6',
      deviceId: 'dev-1',
    );
    expect(reversed, 1);
    expect(await _balance(db), 100);

    final voucher = await db.customSelect(
      "SELECT status, reversal_reason FROM receipt_vouchers WHERE id = 'receipt-reverse-p6'",
    ).getSingle();
    expect(voucher.read<String>('status'), 'reversed');
    expect(voucher.read<String>('reversal_reason'), 'Wrong receipt');

    final allocation = await db.customSelect(
      "SELECT status FROM payment_allocations WHERE voucher_id = 'receipt-reverse-p6'",
    ).getSingle();
    expect(allocation.read<String>('status'), 'reversed');

    final sale = await db.customSelect(
      "SELECT paid_amount, payment_status FROM sales WHERE id = 'sale-voucher-p6'",
    ).getSingle();
    expect(sale.read<double>('paid_amount'), 0);
    expect(sale.read<String>('payment_status'), 'unpaid');

    final ledgerCount = await db.customSelect(
      "SELECT COUNT(*) AS c FROM cash_ledger_transactions WHERE reference_id = 'receipt-reverse-p6' OR reversal_of_id <> ''",
    ).getSingle();
    expect(ledgerCount.read<int>('c'), 2);

    final retry = await CashReversalService(db).reverseReference(
      referenceType: 'receipt_voucher',
      referenceId: 'receipt-reverse-p6',
      reason: 'Retry',
      createdBy: 'tester',
    );
    expect(retry, 0);
    final ledgerCountAfterRetry = await db.customSelect(
      "SELECT COUNT(*) AS c FROM cash_ledger_transactions WHERE reference_id = 'receipt-reverse-p6' OR reversal_of_id <> ''",
    ).getSingle();
    expect(ledgerCountAfterRetry.read<int>('c'), 2);
  });

  test('payment voucher reversal restores supplier allocation and drawer cash', () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);
    await _seedPurchaseP6(
      db,
      id: 'purchase-voucher-p6',
      purchaseNo: 'PO-VOUCHER-P6',
      supplierId: 'sup-voucher-p6',
      total: 90,
    );

    final service = PaymentVoucherService(db);
    await service.createPayment(
      id: 'payment-reverse-p6',
      voucherNo: 'PV-REVERSE-P6',
      supplierId: 'sup-voucher-p6',
      supplierName: 'Supplier P6',
      amount: 30,
      cashLocationId: 'drawer-p6',
      cashDrawerSessionId: 'shift-p6',
      deviceId: 'dev-1',
      storeId: 'store-1',
      branchId: 'main',
      allocations: const <PaymentAllocationDraft>[
        PaymentAllocationDraft(referenceId: 'purchase-voucher-p6', amount: 30),
      ],
    );
    expect(await _balance(db), 70);

    expect(
      await service.reversePaymentVoucher(
        voucherId: 'payment-reverse-p6',
        reason: 'Wrong supplier payment',
        createdBy: 'tester',
        deviceId: 'dev-1',
      ),
      isTrue,
    );
    expect(await _balance(db), 100);

    final purchase = await db.customSelect(
      "SELECT paid_amount, payment_status FROM purchases WHERE id = 'purchase-voucher-p6'",
    ).getSingle();
    expect(purchase.read<double>('paid_amount'), 0);
    expect(purchase.read<String>('payment_status'), 'unpaid');
    final allocation = await db.customSelect(
      "SELECT status FROM payment_allocations WHERE voucher_id = 'payment-reverse-p6'",
    ).getSingle();
    expect(allocation.read<String>('status'), 'reversed');
  });

  test('cash transfer reversal restores both locations and uses valid void status', () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);
    const now = '2026-08-18T12:00:00.000Z';
    await db.customInsert(
      '''
      INSERT INTO cash_locations
        (id, code, name, type, account_id, current_balance, created_at, updated_at,
         store_id, branch_id, device_id)
      VALUES ('vault-p6', 'VAULT-P6', 'Phase 6 Vault', 'main_vault', 'acc_cash', 200, ?, ?,
              'store-1', 'main', 'dev-1')
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
      ],
    );

    final transferId = await AccountingService.createCashTransfer(
      fromLocationId: 'drawer-p6',
      toLocationId: 'vault-p6',
      amount: 25,
      createdBy: 'tester',
      storeId: 'store-1',
      branchId: 'main',
      idempotencyKey: 'p6-transfer-reverse',
    );
    expect(await _balance(db), 75);

    expect(
      await CashReversalService(db).reverseReference(
        referenceType: 'cash_transfer',
        referenceId: transferId,
        reason: 'Transfer entered by mistake',
        createdBy: 'Test Operator',
        createdByUserId: 'user-p6',
      ),
      2,
    );
    expect(await _balance(db), 100);
    final vault = await db.customSelect(
      "SELECT current_balance FROM cash_locations WHERE id = 'vault-p6'",
    ).getSingle();
    expect(vault.read<double>('current_balance'), 200);
    final transfer = await db.customSelect(
      'SELECT status, reversed_at, reversal_reason, reversed_by, reversed_by_user_id FROM cash_transfers WHERE id = ?',
      variables: <Variable<Object>>[Variable<String>(transferId)],
    ).getSingle();
    expect(transfer.read<String>('status'), 'void');
    expect(transfer.read<String>('reversed_at'), isNotEmpty);
    expect(transfer.read<String>('reversal_reason'), 'Transfer entered by mistake');
    expect(transfer.read<String>('reversed_by'), 'Test Operator');
    expect(transfer.read<String>('reversed_by_user_id'), 'user-p6');
  });

  test('failed funded shift opening rolls back the new session', () async {
    final db = await _db();
    addTearDown(db.close);
    const now = '2026-08-18T12:00:00.000Z';
    await db.customInsert(
      '''
      INSERT INTO cash_locations
        (id, code, name, type, account_id, current_balance, created_at, updated_at,
         store_id, branch_id, device_id)
      VALUES ('drawer-open-p6', 'DRAW-OPEN-P6', 'Open Drawer', 'cash_drawer', 'acc_cash', 0, ?, ?,
              'store-1', 'main', 'dev-open')
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
      ],
    );
    await db.customInsert(
      '''
      INSERT INTO cash_locations
        (id, code, name, type, account_id, current_balance, created_at, updated_at,
         store_id, branch_id, device_id)
      VALUES ('vault-open-p6', 'VAULT-OPEN-P6', 'Open Vault', 'main_vault', 'acc_cash', 10, ?, ?,
              'store-1', 'main', '')
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
      ],
    );

    await expectLater(
      AccountingService.openCashDrawer(
        drawerNo: 'OPEN-P6',
        openingBalance: 50,
        cashLocationId: 'drawer-open-p6',
        fundingLocationId: 'vault-open-p6',
        openedBy: 'tester',
        deviceId: 'dev-open',
        storeId: 'store-1',
        branchId: 'main',
      ),
      throwsStateError,
    );
    final sessions = await db.customSelect(
      "SELECT COUNT(*) AS c FROM cash_drawer_sessions WHERE cash_location_id = 'drawer-open-p6'",
    ).getSingle();
    expect(sessions.read<int>('c'), 0);
  });

  test('reversing a cash sale refund makes the amount refundable again', () async {
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
      VALUES ('receipt-refund-reverse-p6', 'RC-RR-P6', 'cust-rr-p6', 'Customer P6', ?, 40, 0,
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
      VALUES ('alloc-rr-p6', 'receipt', 'receipt-refund-reverse-p6', 'sale', 'sale-rr-p6',
              'INV-RR-P6', 40, 40, 'USD', 'USD', 1, ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
      ],
    );
    final service = PaymentVoucherService(db);
    expect(await service.refundableCashForSale('sale-rr-p6'), 40);
    await service.refundSaleCash(
      saleId: 'sale-rr-p6',
      invoiceNo: 'INV-RR-P6',
      customerId: 'cust-rr-p6',
      customerName: 'Customer P6',
      requestedAmount: 25,
      cashLocationId: 'drawer-p6',
      cashDrawerSessionId: 'shift-p6',
      refundKey: 'rr-1',
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );
    expect(await service.refundableCashForSale('sale-rr-p6'), 15);

    await CashReversalService(db).reverseReference(
      referenceType: 'sale_refund',
      referenceId: 'sale-rr-p6:rr-1',
      reason: 'Refund cancelled',
      createdBy: 'tester',
    );
    expect(await service.refundableCashForSale('sale-rr-p6'), 40);
  });

  test('partial sale return caps cash refund at returned entitlement', () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);
    const now = '2026-08-18T15:00:00.000Z';
    await db.customInsert(
      '''
      INSERT INTO receipt_vouchers
        (id, voucher_no, customer_id, customer_name, voucher_date, amount,
         unallocated_amount, currency, payment_method, cash_location_id,
         cash_drawer_session_id, status, created_at, updated_at)
      VALUES ('receipt-partial-p6', 'RC-PART-P6', 'cust-partial', 'Customer Partial', ?, 100, 0,
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
      VALUES ('alloc-partial-p6', 'receipt', 'receipt-partial-p6', 'sale', 'sale-partial-p6',
              'INV-PART-P6', 100, 100, 'USD', 'USD', 1, ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
      ],
    );

    final service = PaymentVoucherService(db);
    expect(
      await service.refundableCashForSale(
        'sale-partial-p6',
        maxRefundAmount: 20,
      ),
      20,
    );
    final refunded = await service.refundSaleCash(
      saleId: 'sale-partial-p6',
      invoiceNo: 'INV-PART-P6',
      customerId: 'cust-partial',
      customerName: 'Customer Partial',
      requestedAmount: 100,
      maxRefundAmount: 20,
      cashLocationId: 'drawer-p6',
      cashDrawerSessionId: 'shift-p6',
      refundKey: 'partial-return-1',
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );
    expect(refunded, 20);
    expect(await _balance(db), 80);
    expect(
      await service.refundableCashForSale(
        'sale-partial-p6',
        maxRefundAmount: 20,
      ),
      0,
    );
  });

}
