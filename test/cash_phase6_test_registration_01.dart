part of 'cash_phase6_test.dart';

void _registerCashPhase6TestsPart1() {
  test('expected cash is opening balance plus current-session Cash Ledger only',
      () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);
    final operations = CashOperationService(db, authorization: _authorization);

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

    expect(await AccountingService.calculateCashDrawerExpectedCash('shift-p6'),
        115);
  });

  test('shortage close writes immutable ledger, journal and reconciles balance',
      () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);
    final operations = CashOperationService(db, authorization: _authorization);
    await operations.deposit(
      cashLocationId: 'drawer-p6',
      cashDrawerSessionId: 'shift-p6',
      counterpartAccountId: 'acc_owner_capital',
      amount: 20,
      idempotencyKey: 'p6-close-deposit',
    );

    await AccountingService.closeCashDrawer(
      authorization: _authorization,
      sessionId: 'shift-p6',
      countedCash: 115,
      closedBy: 'tester',
    );

    final session = await db
        .customSelect(
          "SELECT status, expected_cash, counted_cash, difference FROM cash_drawer_sessions WHERE id = 'shift-p6'",
        )
        .getSingle();
    expect(session.read<String>('status'), 'closed');
    expect(session.read<double>('expected_cash'), 120);
    expect(session.read<double>('counted_cash'), 115);
    expect(session.read<double>('difference'), -5);
    expect(await _balance(db), 115);

    final ledger = await db
        .customSelect(
          "SELECT type, direction, amount FROM cash_ledger_transactions WHERE reference_type = 'cash_reconciliation' AND reference_id = 'shift-p6'",
        )
        .getSingle();
    expect(ledger.read<String>('type'), 'shortage');
    expect(ledger.read<String>('direction'), 'out');
    expect(ledger.read<double>('amount'), 5);

    final journal = await db
        .customSelect(
          "SELECT status FROM journal_entries WHERE reference_type = 'cash_reconciliation' AND reference_id = 'shift-p6'",
        )
        .getSingle();
    expect(journal.read<String>('status'), 'posted');
  });

  test('overage close writes cash-in ledger and counted balance', () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);

    await AccountingService.closeCashDrawer(
      authorization: _authorization,
      sessionId: 'shift-p6',
      countedCash: 108,
      closedBy: 'tester',
    );

    expect(await _balance(db), 108);
    final ledger = await db
        .customSelect(
          "SELECT type, direction, amount FROM cash_ledger_transactions WHERE reference_id = 'shift-p6' AND type = 'overage'",
        )
        .getSingle();
    expect(ledger.read<String>('direction'), 'in');
    expect(ledger.read<double>('amount'), 8);
  });

  test(
      'true cash reversal appends opposite ledger row and never deletes original',
      () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);
    final operation =
        await CashOperationService(db, authorization: _authorization).deposit(
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
    expect(journals.any((row) => row.read<String>('status') == 'reversed'),
        isTrue);
    expect(journals.any((row) => row.read<String>('source') == 'reversal'),
        isTrue);

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

  test('cash sale refund posts journal, ledger out and is idempotent',
      () async {
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
      saleId: 'sale-p6',
      invoiceNo: 'INV-P6',
      customerId: 'cust-p6',
      customerName: 'Customer P6',
      requestedAmount: 25,
      cashLocationId: 'drawer-p6',
      cashDrawerSessionId: 'shift-p6',
      refundKey: 'return-1',
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );
    final retry = await service.refundSaleCash(
      saleId: 'sale-p6',
      invoiceNo: 'INV-P6',
      customerId: 'cust-p6',
      customerName: 'Customer P6',
      requestedAmount: 25,
      cashLocationId: 'drawer-p6',
      cashDrawerSessionId: 'shift-p6',
      refundKey: 'return-1',
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );
    expect(first, 25);
    expect(retry, 25);
    expect(await _balance(db), 75);
    final ledger = await db
        .customSelect(
          "SELECT direction, amount FROM cash_ledger_transactions WHERE type = 'refund' AND reference_id = 'sale-p6:return-1'",
        )
        .getSingle();
    expect(ledger.read<String>('direction'), 'out');
    expect(ledger.read<double>('amount'), 25);
    final journalCount = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'sale_refund' AND reference_id = 'sale-p6:return-1'",
        )
        .getSingle();
    expect(journalCount.read<int>('c'), 1);
  });

  test('purchase refund keeps new edit overpayment after prior refund',
      () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);
    await _seedPurchaseP6(
      db,
      id: 'purchase-edit-refund-p6',
      purchaseNo: 'PO-EDIT-P6',
      supplierId: 'sup-edit-p6',
      total: 2515.50,
    );
    const now = '2026-08-18T13:00:00.000Z';
    await db.customInsert(
      '''
      INSERT INTO payment_vouchers
        (id, voucher_no, supplier_id, supplier_name, voucher_date, amount,
         unallocated_amount, currency, payment_method, cash_location_id,
         cash_drawer_session_id, status, created_at, updated_at)
      VALUES ('payment-edit-p6', 'PV-EDIT-P6', 'sup-edit-p6', 'Supplier P6', ?,
              3000, 18, 'USD', 'Cash', 'drawer-p6', 'shift-p6', 'posted', ?, ?)
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
      VALUES ('purchase-edit-alloc-p6', 'payment', 'payment-edit-p6', 'purchase',
              'purchase-edit-refund-p6', 'PO-EDIT-P6', 3000, 3000,
              'USD', 'USD', 1, ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
      ],
    );
    await db.customInsert(
      '''
      INSERT INTO payment_allocations
        (id, voucher_type, voucher_id, reference_type, reference_id,
         reference_number, amount, reference_amount, currency,
         reference_currency, exchange_rate, allocation_kind, reversal_of_id,
         created_at, updated_at)
      VALUES ('purchase-edit-reversal-p6', 'payment', 'payment-edit-p6',
              'purchase', 'purchase-edit-refund-p6', 'PO-EDIT-P6', 484.50,
              484.50, 'USD', 'USD', 1, 'reversal', 'purchase-edit-alloc-p6', ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
      ],
    );
    await db.customInsert(
      '''
      INSERT INTO cash_ledger_transactions
        (id, type, direction, amount, cash_location_id, cash_drawer_session_id,
         reference_type, reference_id, reference_number, occurred_at,
         created_at, updated_at)
      VALUES ('supplier-refund-edit-p6', 'supplier_refund', 'in', 466.50,
              'drawer-p6', 'shift-p6', 'purchase_refund',
              'purchase-edit-refund-p6:first', 'PO-EDIT-P6', ?, ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(now),
      ],
    );

    final service = PaymentVoucherService(db);
    expect(
      await service.refundableCashForPurchase(
        'purchase-edit-refund-p6',
        maxRefundAmount: 18,
      ),
      18,
    );
  });

  test(
      'supplier refund grows an existing allocation reversal instead of duplicating it',
      () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);
    await _seedPurchaseP6(
      db,
      id: 'purchase-cumulative-refund-p6',
      purchaseNo: 'PO-CUM-P6',
      supplierId: 'sup-cum-p6',
      total: 2393.50,
    );
    const now = '2026-08-18T13:00:00.000Z';
    await db.customInsert(
      '''
      INSERT INTO payment_vouchers
        (id, voucher_no, supplier_id, supplier_name, voucher_date, amount,
         unallocated_amount, currency, payment_method, cash_location_id,
         cash_drawer_session_id, status, created_at, updated_at)
      VALUES ('payment-cum-p6', 'PV-CUM-P6', 'sup-cum-p6', 'Supplier P6', ?,
              3000, 0, 'USD', 'Cash', 'drawer-p6', 'shift-p6', 'posted', ?, ?)
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
      VALUES ('cum-original-alloc-p6', 'payment', 'payment-cum-p6', 'purchase',
              'purchase-cumulative-refund-p6', 'PO-CUM-P6', 3000, 3000,
              'USD', 'USD', 1, ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
      ],
    );
    await db.customInsert(
      '''
      INSERT INTO payment_allocations
        (id, voucher_type, voucher_id, reference_type, reference_id,
         reference_number, amount, reference_amount, currency,
         reference_currency, exchange_rate, allocation_kind, reversal_of_id,
         created_at, updated_at)
      VALUES ('cum-existing-reversal-p6', 'payment', 'payment-cum-p6',
              'purchase', 'purchase-cumulative-refund-p6', 'PO-CUM-P6',
              536.50, 536.50, 'USD', 'USD', 1, 'reversal',
              'cum-original-alloc-p6', ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
      ],
    );
    await db.customInsert(
      '''
      INSERT INTO cash_ledger_transactions
        (id, type, direction, amount, cash_location_id, cash_drawer_session_id,
         reference_type, reference_id, reference_number, occurred_at,
         created_at, updated_at)
      VALUES ('cum-prior-refund-p6', 'supplier_refund', 'in', 466.50,
              'drawer-p6', 'shift-p6', 'purchase_refund',
              'purchase-cumulative-refund-p6:prior', 'PO-CUM-P6', ?, ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(now),
      ],
    );

    final refunded = await PaymentVoucherService(db).refundPurchaseCash(
      purchaseId: 'purchase-cumulative-refund-p6',
      purchaseNo: 'PO-CUM-P6',
      supplierId: 'sup-cum-p6',
      supplierName: 'Supplier P6',
      cashLocationId: 'drawer-p6',
      cashDrawerSessionId: 'shift-p6',
      requestedAmount: 70,
      maxRefundAmount: 70,
      refundKey: 'second-70',
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );
    expect(refunded, 70);

    final reversals = await db.customSelect(
      '''
      SELECT COUNT(*) AS c, COALESCE(SUM(amount), 0) AS total
      FROM payment_allocations
      WHERE allocation_kind = 'reversal'
        AND reversal_of_id = 'cum-original-alloc-p6'
        AND status = 'active' AND deleted_at = ''
      ''',
    ).getSingle();
    expect(reversals.read<int>('c'), 1);
    expect(reversals.read<double>('total'), 606.50);

    final coverage = await db.customSelect(
      '''
      SELECT allocation_id, amount
      FROM cash_refund_allocations
      WHERE refund_id = 'purchase-cumulative-refund-p6:second-70'
        AND deleted_at = ''
      ''',
    ).getSingle();
    expect(coverage.read<String>('allocation_id'), 'cum-existing-reversal-p6');
    expect(coverage.read<double>('amount'), 70);
  });

  test(
      'supplier refund covers newest allocation before older cumulative reversal',
      () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);
    await _seedPurchaseP6(
      db,
      id: 'purchase-repeat-refund-p6',
      purchaseNo: 'PO-REPEAT-P6',
      supplierId: 'sup-repeat-p6',
      total: 2533.50,
    );
    const oldAt = '2026-08-18T13:00:00.000Z';
    const newAt = '2026-08-20T13:00:00.000Z';

    await db.customInsert(
      '''
      INSERT INTO payment_vouchers
        (id, voucher_no, supplier_id, supplier_name, voucher_date, amount,
         unallocated_amount, currency, payment_method, cash_location_id,
         cash_drawer_session_id, status, created_at, updated_at)
      VALUES ('payment-repeat-old-p6', 'PV-REPEAT-OLD-P6', 'sup-repeat-p6',
              'Supplier P6', ?, 3000, 0, 'USD', 'Cash', 'drawer-p6', 'shift-p6',
              'posted', ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(oldAt),
        Variable<String>(oldAt),
        Variable<String>(oldAt),
      ],
    );
    await db.customInsert(
      '''
      INSERT INTO payment_allocations
        (id, voucher_type, voucher_id, reference_type, reference_id,
         reference_number, amount, reference_amount, currency,
         reference_currency, exchange_rate, created_at, updated_at)
      VALUES ('repeat-old-alloc-p6', 'payment', 'payment-repeat-old-p6',
              'purchase', 'purchase-repeat-refund-p6', 'PO-REPEAT-P6',
              3000, 3000, 'USD', 'USD', 1, ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(oldAt),
        Variable<String>(oldAt),
      ],
    );
    await db.customInsert(
      '''
      INSERT INTO payment_allocations
        (id, voucher_type, voucher_id, reference_type, reference_id,
         reference_number, amount, reference_amount, currency,
         reference_currency, exchange_rate, allocation_kind, reversal_of_id,
         created_at, updated_at)
      VALUES ('repeat-old-reversal-p6', 'payment', 'payment-repeat-old-p6',
              'purchase', 'purchase-repeat-refund-p6', 'PO-REPEAT-P6',
              536.50, 536.50, 'USD', 'USD', 1, 'reversal',
              'repeat-old-alloc-p6', ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(oldAt),
        Variable<String>(oldAt),
      ],
    );
    await db.customInsert(
      '''
      INSERT INTO cash_ledger_transactions
        (id, type, direction, amount, cash_location_id, cash_drawer_session_id,
         reference_type, reference_id, reference_number, occurred_at,
         created_at, updated_at)
      VALUES ('repeat-prior-refund-p6', 'supplier_refund', 'in', 536.50,
              'drawer-p6', 'shift-p6', 'purchase_refund',
              'purchase-repeat-refund-p6:prior', 'PO-REPEAT-P6', ?, ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(oldAt),
        Variable<String>(oldAt),
        Variable<String>(oldAt),
      ],
    );

    await db.customInsert(
      '''
      INSERT INTO payment_vouchers
        (id, voucher_no, supplier_id, supplier_name, voucher_date, amount,
         unallocated_amount, currency, payment_method, cash_location_id,
         cash_drawer_session_id, status, created_at, updated_at)
      VALUES ('payment-repeat-new-p6', 'PV-REPEAT-NEW-P6', 'sup-repeat-p6',
              'Supplier P6', ?, 140, 0, 'USD', 'Cash', 'drawer-p6', 'shift-p6',
              'posted', ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(newAt),
        Variable<String>(newAt),
        Variable<String>(newAt),
      ],
    );
    await db.customInsert(
      '''
      INSERT INTO payment_allocations
        (id, voucher_type, voucher_id, reference_type, reference_id,
         reference_number, amount, reference_amount, currency,
         reference_currency, exchange_rate, created_at, updated_at)
      VALUES ('repeat-new-alloc-p6', 'payment', 'payment-repeat-new-p6',
              'purchase', 'purchase-repeat-refund-p6', 'PO-REPEAT-P6',
              140, 140, 'USD', 'USD', 1, ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(newAt),
        Variable<String>(newAt),
      ],
    );

    final service = PaymentVoucherService(db);
    final refunded = await service.refundPurchaseCash(
      purchaseId: 'purchase-repeat-refund-p6',
      purchaseNo: 'PO-REPEAT-P6',
      supplierId: 'sup-repeat-p6',
      supplierName: 'Supplier P6',
      cashLocationId: 'drawer-p6',
      cashDrawerSessionId: 'shift-p6',
      requestedAmount: 70,
      maxRefundAmount: 70,
      refundKey: 'after-edit-70',
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );
    expect(refunded, 70);

    final newReversal = await db.customSelect(
      '''
      SELECT id, amount, reference_amount
      FROM payment_allocations
      WHERE allocation_kind = 'reversal'
        AND reversal_of_id = 'repeat-new-alloc-p6'
        AND status = 'active' AND deleted_at = ''
      ''',
    ).getSingle();
    expect(newReversal.read<double>('amount'), 70);
    expect(newReversal.read<double>('reference_amount'), 70);

    final oldReversal = await db.customSelect(
      '''
      SELECT COUNT(*) AS c, COALESCE(SUM(amount), 0) AS total
      FROM payment_allocations
      WHERE allocation_kind = 'reversal'
        AND reversal_of_id = 'repeat-old-alloc-p6'
        AND deleted_at = ''
      ''',
    ).getSingle();
    expect(oldReversal.read<int>('c'), 1);
    expect(oldReversal.read<double>('total'), 536.50);

    final coverage = await db.customSelect(
      '''
      SELECT voucher_id, allocation_id, amount
      FROM cash_refund_allocations
      WHERE refund_id = 'purchase-repeat-refund-p6:after-edit-70'
        AND deleted_at = ''
      ''',
    ).getSingle();
    expect(coverage.read<String>('voucher_id'), 'payment-repeat-new-p6');
    expect(
      coverage.read<String>('allocation_id'),
      newReversal.read<String>('id'),
    );
    expect(coverage.read<double>('amount'), 70);

    final purchaseCache = await db
        .customSelect(
          "SELECT paid_amount, payment_status FROM purchases WHERE id = 'purchase-repeat-refund-p6'",
        )
        .getSingle();
    expect(purchaseCache.read<double>('paid_amount'), 2533.50);
    expect(purchaseCache.read<String>('payment_status'), 'paid');
  });
}
