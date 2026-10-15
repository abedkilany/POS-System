part of 'cash_phase6_test.dart';

void _registerCashPhase6TestsPart2() {
  test(
      'normalization repairs stale purchase paid amount when allocations already match total',
      () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);
    await _seedPurchaseP6(
      db,
      id: 'purchase-stale-cache-p6',
      purchaseNo: 'PO-STALE-CACHE-P6',
      supplierId: 'sup-stale-cache-p6',
      total: 100,
    );
    const now = '2026-08-20T13:00:00.000Z';
    await db.customUpdate(
      "UPDATE purchases SET paid_amount = 140, payment_status = 'paid' WHERE id = 'purchase-stale-cache-p6'",
    );
    await db.customInsert(
      '''
      INSERT INTO payment_vouchers
        (id, voucher_no, supplier_id, supplier_name, voucher_date, amount,
         unallocated_amount, currency, payment_method, cash_location_id,
         cash_drawer_session_id, status, created_at, updated_at)
      VALUES ('payment-stale-cache-p6', 'PV-STALE-CACHE-P6',
              'sup-stale-cache-p6', 'Supplier P6', ?, 100, 0, 'USD', 'Cash',
              'drawer-p6', 'shift-p6', 'posted', ?, ?)
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
      VALUES ('stale-cache-alloc-p6', 'payment', 'payment-stale-cache-p6',
              'purchase', 'purchase-stale-cache-p6', 'PO-STALE-CACHE-P6',
              100, 100, 'USD', 'USD', 1, ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
      ],
    );

    await PaymentVoucherService(db)
        .normalizeOverAllocatedVouchers(deviceId: 'dev-1');

    final repaired = await db
        .customSelect(
          "SELECT paid_amount, payment_status FROM purchases WHERE id = 'purchase-stale-cache-p6'",
        )
        .getSingle();
    expect(repaired.read<double>('paid_amount'), 100);
    expect(repaired.read<String>('payment_status'), 'paid');
  });

  test(
      'purchase refund preflight sync repairs stale paid cache from allocations',
      () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);
    await _seedPurchaseP6(
      db,
      id: 'purchase-preflight-cache-p6',
      purchaseNo: 'PO-PREFLIGHT-CACHE-P6',
      supplierId: 'sup-preflight-cache-p6',
      total: 100,
    );
    const now = '2026-08-20T14:00:00.000Z';
    await db.customUpdate(
      "UPDATE purchases SET paid_amount = 170, payment_status = 'paid' WHERE id = 'purchase-preflight-cache-p6'",
    );
    await db.customInsert(
      '''
      INSERT INTO payment_vouchers
        (id, voucher_no, supplier_id, supplier_name, voucher_date, amount,
         unallocated_amount, currency, payment_method, cash_location_id,
         cash_drawer_session_id, status, created_at, updated_at)
      VALUES ('payment-preflight-cache-p6', 'PV-PREFLIGHT-CACHE-P6',
              'sup-preflight-cache-p6', 'Supplier P6', ?, 100, 0, 'USD',
              'Cash', 'drawer-p6', 'shift-p6', 'posted', ?, ?)
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
      VALUES ('preflight-cache-alloc-p6', 'payment',
              'payment-preflight-cache-p6', 'purchase',
              'purchase-preflight-cache-p6', 'PO-PREFLIGHT-CACHE-P6',
              100, 100, 'USD', 'USD', 1, ?, ?)
      ''',
      variables: const <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
      ],
    );

    final service = PaymentVoucherService(db);
    final synced = await service.syncPurchasePaymentCacheFromAllocations(
      purchaseId: 'purchase-preflight-cache-p6',
      deviceId: 'dev-1',
    );
    expect(synced, 100);
    final first = await db
        .customSelect(
          "SELECT paid_amount, payment_status, version FROM purchases WHERE id = 'purchase-preflight-cache-p6'",
        )
        .getSingle();
    expect(first.read<double>('paid_amount'), 100);
    expect(first.read<String>('payment_status'), 'paid');
    final versionAfterRepair = first.read<int>('version');

    final syncedAgain = await service.syncPurchasePaymentCacheFromAllocations(
      purchaseId: 'purchase-preflight-cache-p6',
      deviceId: 'dev-1',
    );
    expect(syncedAgain, 100);
    final second = await db
        .customSelect(
          "SELECT version FROM purchases WHERE id = 'purchase-preflight-cache-p6'",
        )
        .getSingle();
    expect(second.read<int>('version'), versionAfterRepair);
  });

  test('supplier cash refund posts cash-in ledger and is idempotent', () async {
    final db = await _db();
    addTearDown(db.close);
    await _seedDrawer(db);
    await _seedPurchaseP6(
      db,
      id: 'purchase-p6',
      purchaseNo: 'PO-P6',
      supplierId: 'sup-p6',
      total: 30,
    );
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
    final ledger = await db
        .customSelect(
          "SELECT direction, amount FROM cash_ledger_transactions WHERE type = 'supplier_refund' AND reference_id = 'purchase-p6:full'",
        )
        .getSingle();
    expect(ledger.read<String>('direction'), 'in');
    expect(ledger.read<double>('amount'), 30);
    final journalCount = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'purchase_refund' AND reference_id = 'purchase-p6:full'",
        )
        .getSingle();
    expect(journalCount.read<int>('c'), 1);
    final supplierRefundLedger = await db
        .customSelect(
          "SELECT id FROM cash_ledger_transactions WHERE type = 'supplier_refund' AND reference_id = 'purchase-p6:full' AND reversal_of_id = ''",
        )
        .getSingle();
    final supplierRefundLedgerId = supplierRefundLedger.read<String>('id');
    final supplierRefundAccount = await db.customSelect(
      "SELECT transaction_type, debit, credit FROM account_transactions WHERE id = ? AND deleted_at = ''",
      variables: <Variable<Object>>[
        Variable<String>('$supplierRefundLedgerId-supplier-refund'),
      ],
    ).getSingle();
    expect(supplierRefundAccount.read<String>('transaction_type'),
        'paymentReversal');
    expect(supplierRefundAccount.read<double>('debit'), 0);
    expect(supplierRefundAccount.read<double>('credit'), 30);

    final reversed = await CashReversalService(db).reverseReference(
      referenceType: 'purchase_refund',
      referenceId: 'purchase-p6:full',
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
    final originalRefundCount = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM cash_ledger_transactions WHERE type = 'supplier_refund' AND reference_type = 'purchase_refund' AND reference_id LIKE 'purchase-p6:%' AND reversal_of_id = ''",
        )
        .getSingle();
    expect(originalRefundCount.read<int>('c'), 2);
  });

  test(
      'receipt voucher reversal restores cash and invoice allocation cache exactly once',
      () async {
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

    final voucher = await db
        .customSelect(
          "SELECT status, reversal_reason FROM receipt_vouchers WHERE id = 'receipt-reverse-p6'",
        )
        .getSingle();
    expect(voucher.read<String>('status'), 'reversed');
    expect(voucher.read<String>('reversal_reason'), 'Wrong receipt');

    final allocation = await db
        .customSelect(
          "SELECT status FROM payment_allocations WHERE voucher_id = 'receipt-reverse-p6'",
        )
        .getSingle();
    expect(allocation.read<String>('status'), 'reversed');

    final sale = await db
        .customSelect(
          "SELECT paid_amount, payment_status FROM sales WHERE id = 'sale-voucher-p6'",
        )
        .getSingle();
    expect(sale.read<double>('paid_amount'), 0);
    expect(sale.read<String>('payment_status'), 'unpaid');

    final ledgerCount = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM cash_ledger_transactions WHERE reference_id = 'receipt-reverse-p6' OR reversal_of_id <> ''",
        )
        .getSingle();
    expect(ledgerCount.read<int>('c'), 2);

    final retry = await CashReversalService(db).reverseReference(
      referenceType: 'receipt_voucher',
      referenceId: 'receipt-reverse-p6',
      reason: 'Retry',
      createdBy: 'tester',
    );
    expect(retry, 0);
    final ledgerCountAfterRetry = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM cash_ledger_transactions WHERE reference_id = 'receipt-reverse-p6' OR reversal_of_id <> ''",
        )
        .getSingle();
    expect(ledgerCountAfterRetry.read<int>('c'), 2);
  });

  test('payment voucher reversal restores supplier allocation and drawer cash',
      () async {
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

    final purchase = await db
        .customSelect(
          "SELECT paid_amount, payment_status FROM purchases WHERE id = 'purchase-voucher-p6'",
        )
        .getSingle();
    expect(purchase.read<double>('paid_amount'), 0);
    expect(purchase.read<String>('payment_status'), 'unpaid');
    final allocation = await db
        .customSelect(
          "SELECT status FROM payment_allocations WHERE voucher_id = 'payment-reverse-p6'",
        )
        .getSingle();
    expect(allocation.read<String>('status'), 'reversed');
  });

  test(
      'cash transfer reversal restores both locations and uses valid void status',
      () async {
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
      authorization: _authorization,
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
    final vault = await db
        .customSelect(
          "SELECT current_balance FROM cash_locations WHERE id = 'vault-p6'",
        )
        .getSingle();
    expect(vault.read<double>('current_balance'), 200);
    final transfer = await db.customSelect(
      'SELECT status, reversed_at, reversal_reason, reversed_by, reversed_by_user_id FROM cash_transfers WHERE id = ?',
      variables: <Variable<Object>>[Variable<String>(transferId)],
    ).getSingle();
    expect(transfer.read<String>('status'), 'void');
    expect(transfer.read<String>('reversed_at'), isNotEmpty);
    expect(transfer.read<String>('reversal_reason'),
        'Transfer entered by mistake');
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
        authorization: _authorization,
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
    final sessions = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM cash_drawer_sessions WHERE cash_location_id = 'drawer-open-p6'",
        )
        .getSingle();
    expect(sessions.read<int>('c'), 0);
  });

  test('reversing a cash sale refund makes the amount refundable again',
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

  test('partial sale return caps cash refund at returned entitlement',
      () async {
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
