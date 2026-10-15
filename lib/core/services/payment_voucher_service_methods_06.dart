part of 'payment_voucher_service.dart';

extension PaymentVoucherServiceSplitPart6 on PaymentVoucherService {

  /// Backfills Cash Ledger rows for legacy cash receipt/payment vouchers that
  /// pre-date ledger routing. This is history-only and deliberately does not
  /// mutate cash_locations.current_balance because the legacy voucher already
  /// affected the cash balance when it was originally posted.
  ///
  /// Safe to run repeatedly: existing voucher references are skipped.
  Future<void> backfillLegacyCashLedger() async {
    await _db.transaction(() async {
      await _repairSplitCompatibilityAccountMovements();
      // Repair rows created by the old backfill bug: modern voucher-backed
      // compatibility account movements (notably *-account-payment) were
      // mistaken for pre-voucher legacy payments and copied into Cash Ledger
      // a second time. These historical backfill rows never moved the live
      // cash-location balance, so soft-deleting only the derived duplicate is
      // safe and keeps the authoritative voucher movement intact.
      await _db.customStatement(r'''
        UPDATE cash_ledger_transactions
        SET deleted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
            updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
            sync_status = 'pending',
            version = version + 1
        WHERE cash_ledger_transactions.deleted_at = ''
          AND cash_ledger_transactions.reference_type = 'legacy_account_transaction'
          AND cash_ledger_transactions.id = 'legacy_account_payment_' || cash_ledger_transactions.reference_id
          AND EXISTS (
            SELECT 1
            FROM account_transactions at
            WHERE at.id = cash_ledger_transactions.reference_id
              AND at.deleted_at = ''
              AND (
                (
                  at.transaction_type = 'paymentReceived'
                  AND EXISTS (
                    SELECT 1 FROM receipt_vouchers rv
                    WHERE rv.deleted_at = ''
                      AND (
                        at.id = rv.id || '-customer-payment'
                        OR at.id LIKE rv.id || '-customer-payment-%'
                        OR at.id = rv.id || '-customer-account-payment'
                        OR at.id LIKE rv.id || '-customer-account-payment-%'
                      )
                  )
                )
                OR
                (
                  at.transaction_type = 'paymentPaid'
                  AND EXISTS (
                    SELECT 1 FROM payment_vouchers pv
                    WHERE pv.deleted_at = ''
                      AND (
                        at.id = pv.id || '-supplier-payment'
                        OR at.id LIKE pv.id || '-supplier-payment-%'
                        OR at.id = pv.id || '-supplier-account-payment'
                        OR at.id LIKE pv.id || '-supplier-account-payment-%'
                      )
                  )
                )
              )
          );
      ''');

      await _db.customStatement(r'''
        INSERT OR IGNORE INTO cash_ledger_transactions (
          id, type, direction, amount, currency, cash_location_id,
          cash_drawer_session_id, reference_type, reference_id, reference_number,
          party_type, party_id, party_name, payment_method,
          created_by, created_by_user_id, device_id, branch_id, store_id, notes,
          idempotency_key, occurred_at, created_at, updated_at, deleted_at,
          reversal_of_id, sync_status, version, last_modified_by_device_id
        )
        SELECT
          'legacy_receipt_' || rv.id,
          'receipt',
          'in',
          rv.amount,
          CASE WHEN TRIM(rv.currency) = '' THEN 'USD' ELSE UPPER(rv.currency) END,
          COALESCE(NULLIF(TRIM(rv.cash_location_id), ''), NULLIF(TRIM(cds.cash_location_id), '')),
          rv.cash_drawer_session_id,
          'receipt_voucher',
          rv.id,
          rv.voucher_no,
          'customer',
          rv.customer_id,
          rv.customer_name,
          CASE WHEN TRIM(rv.payment_method) = '' THEN 'Cash' ELSE rv.payment_method END,
          rv.created_by,
          rv.created_by_user_id,
          rv.device_id,
          rv.branch_id,
          rv.store_id,
          rv.notes,
          'receipt:' || rv.id,
          rv.voucher_date,
          rv.created_at,
          rv.updated_at,
          '',
          '',
          'synced',
          rv.version,
          rv.last_modified_by_device_id
        FROM receipt_vouchers rv
        LEFT JOIN cash_drawer_sessions cds ON cds.id = rv.cash_drawer_session_id
        WHERE rv.deleted_at = ''
          AND rv.status = 'posted'
          AND rv.amount > 0
          AND (TRIM(rv.payment_method) = '' OR LOWER(TRIM(rv.payment_method)) = 'cash')
          AND COALESCE(NULLIF(TRIM(rv.cash_location_id), ''), NULLIF(TRIM(cds.cash_location_id), '')) IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM cash_locations cl
            WHERE cl.id = COALESCE(NULLIF(TRIM(rv.cash_location_id), ''), NULLIF(TRIM(cds.cash_location_id), ''))
              AND cl.deleted_at = ''
          )
          AND NOT EXISTS (
            SELECT 1 FROM cash_ledger_transactions tx
            WHERE tx.deleted_at = ''
              AND tx.reference_type = 'receipt_voucher'
              AND tx.reference_id = rv.id
          );
      ''');

      await _db.customStatement(r'''
        INSERT OR IGNORE INTO cash_ledger_transactions (
          id, type, direction, amount, currency, cash_location_id,
          cash_drawer_session_id, reference_type, reference_id, reference_number,
          party_type, party_id, party_name, payment_method,
          created_by, created_by_user_id, device_id, branch_id, store_id, notes,
          idempotency_key, occurred_at, created_at, updated_at, deleted_at,
          reversal_of_id, sync_status, version, last_modified_by_device_id
        )
        SELECT
          'legacy_payment_' || pv.id,
          'supplier_payment',
          'out',
          pv.amount,
          CASE WHEN TRIM(pv.currency) = '' THEN 'USD' ELSE UPPER(pv.currency) END,
          COALESCE(NULLIF(TRIM(pv.cash_location_id), ''), NULLIF(TRIM(cds.cash_location_id), '')),
          pv.cash_drawer_session_id,
          'payment_voucher',
          pv.id,
          pv.voucher_no,
          'supplier',
          pv.supplier_id,
          pv.supplier_name,
          CASE WHEN TRIM(pv.payment_method) = '' THEN 'Cash' ELSE pv.payment_method END,
          pv.created_by,
          pv.created_by_user_id,
          pv.device_id,
          pv.branch_id,
          pv.store_id,
          pv.notes,
          'payment:' || pv.id,
          pv.voucher_date,
          pv.created_at,
          pv.updated_at,
          '',
          '',
          'synced',
          pv.version,
          pv.last_modified_by_device_id
        FROM payment_vouchers pv
        LEFT JOIN cash_drawer_sessions cds ON cds.id = pv.cash_drawer_session_id
        WHERE pv.deleted_at = ''
          AND pv.status = 'posted'
          AND pv.amount > 0
          AND (TRIM(pv.payment_method) = '' OR LOWER(TRIM(pv.payment_method)) = 'cash')
          AND COALESCE(NULLIF(TRIM(pv.cash_location_id), ''), NULLIF(TRIM(cds.cash_location_id), '')) IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM cash_locations cl
            WHERE cl.id = COALESCE(NULLIF(TRIM(pv.cash_location_id), ''), NULLIF(TRIM(cds.cash_location_id), ''))
              AND cl.deleted_at = ''
          )
          AND NOT EXISTS (
            SELECT 1 FROM cash_ledger_transactions tx
            WHERE tx.deleted_at = ''
              AND tx.reference_type = 'payment_voucher'
              AND tx.reference_id = pv.id
          );
      ''');
      // Payments that pre-date Phase 2 do not have receipt_vouchers /
      // payment_vouchers rows at all. They live only in account_transactions.
      // Materialize those historical cash receipts/payments into Cash Ledger as
      // immutable history. Resolve their drawer from the original device/branch
      // when possible, then fall back to the default/main drawer. Never move the
      // live balance here: these transactions already affected legacy balances.
      await _db.customStatement(r'''
        INSERT OR IGNORE INTO cash_ledger_transactions (
          id, type, direction, amount, currency, cash_location_id,
          cash_drawer_session_id, reference_type, reference_id, reference_number,
          party_type, party_id, party_name, payment_method,
          created_by, created_by_user_id, device_id, branch_id, store_id, notes,
          idempotency_key, occurred_at, created_at, updated_at, deleted_at,
          reversal_of_id, sync_status, version, last_modified_by_device_id
        )
        SELECT
          'legacy_account_payment_' || at.id,
          CASE WHEN at.transaction_type = 'paymentReceived' THEN 'receipt' ELSE 'supplier_payment' END,
          CASE WHEN at.transaction_type = 'paymentReceived' THEN 'in' ELSE 'out' END,
          CASE WHEN at.debit > 0 THEN at.debit ELSE at.credit END,
          CASE WHEN TRIM(at.currency) = '' THEN 'USD' ELSE UPPER(at.currency) END,
          COALESCE(
            (SELECT cl.id FROM cash_locations cl
             WHERE cl.deleted_at = '' AND cl.is_active = 1 AND cl.type = 'cash_drawer'
               AND TRIM(at.device_id) <> '' AND cl.device_id = at.device_id
               AND (TRIM(at.branch_id) = '' OR cl.branch_id = at.branch_id OR TRIM(cl.branch_id) = '')
             ORDER BY cl.is_default DESC, cl.id LIMIT 1),
            (SELECT cl.id FROM cash_locations cl
             WHERE cl.deleted_at = '' AND cl.is_active = 1 AND cl.type = 'cash_drawer'
               AND TRIM(at.branch_id) <> '' AND cl.branch_id = at.branch_id
             ORDER BY cl.is_default DESC, cl.id LIMIT 1),
            (SELECT cl.id FROM cash_locations cl
             WHERE cl.id = 'cl_main_drawer' AND cl.deleted_at = '' AND cl.is_active = 1 LIMIT 1),
            (SELECT cl.id FROM cash_locations cl
             WHERE cl.deleted_at = '' AND cl.is_active = 1 AND cl.type = 'cash_drawer'
             ORDER BY cl.is_default DESC, cl.id LIMIT 1)
          ),
          '',
          'legacy_account_transaction',
          at.id,
          at.reference_no,
          CASE WHEN at.transaction_type = 'paymentReceived' THEN 'customer' ELSE 'supplier' END,
          at.account_id,
          at.account_name,
          CASE WHEN TRIM(at.payment_method) = '' THEN 'Cash' ELSE at.payment_method END,
          '', '',
          at.device_id,
          at.branch_id,
          at.store_id,
          at.note,
          'legacy_account_payment:' || at.id,
          CASE WHEN TRIM(at.transaction_date) = '' THEN at.created_at ELSE at.transaction_date END,
          at.created_at,
          at.updated_at,
          '', '', 'synced', at.version, at.last_modified_by_device_id
        FROM account_transactions at
        WHERE at.deleted_at = ''
          AND at.transaction_type IN ('paymentReceived', 'paymentPaid')
          AND ((at.transaction_type = 'paymentReceived' AND LOWER(TRIM(at.account_type)) = 'customer')
            OR (at.transaction_type = 'paymentPaid' AND LOWER(TRIM(at.account_type)) = 'supplier'))
          AND (at.debit > 0 OR at.credit > 0)
          AND (TRIM(at.payment_method) = '' OR LOWER(TRIM(at.payment_method)) = 'cash')
          AND NOT EXISTS (
            SELECT 1 FROM receipt_vouchers rv
            WHERE at.id = rv.id || '-customer-payment'
               OR at.id LIKE rv.id || '-customer-payment-%'
               OR at.id = rv.id || '-customer-account-payment'
               OR at.id LIKE rv.id || '-customer-account-payment-%'
          )
          AND NOT EXISTS (
            SELECT 1 FROM payment_vouchers pv
            WHERE at.id = pv.id || '-supplier-payment'
               OR at.id LIKE pv.id || '-supplier-payment-%'
               OR at.id = pv.id || '-supplier-account-payment'
               OR at.id LIKE pv.id || '-supplier-account-payment-%'
          )
          AND NOT EXISTS (
            SELECT 1 FROM receipt_vouchers rv
            WHERE rv.deleted_at = '' AND rv.id = 'legacy_receipt_' || at.id
          )
          AND NOT EXISTS (
            SELECT 1 FROM payment_vouchers pv
            WHERE pv.deleted_at = '' AND pv.id = 'legacy_payment_' || at.id
          )
          AND NOT EXISTS (
            SELECT 1 FROM expenses e WHERE e.id = at.reference_id
          )
          AND COALESCE(
            (SELECT cl.id FROM cash_locations cl
             WHERE cl.deleted_at = '' AND cl.is_active = 1 AND cl.type = 'cash_drawer'
               AND TRIM(at.device_id) <> '' AND cl.device_id = at.device_id
               AND (TRIM(at.branch_id) = '' OR cl.branch_id = at.branch_id OR TRIM(cl.branch_id) = '')
             ORDER BY cl.is_default DESC, cl.id LIMIT 1),
            (SELECT cl.id FROM cash_locations cl
             WHERE cl.deleted_at = '' AND cl.is_active = 1 AND cl.type = 'cash_drawer'
               AND TRIM(at.branch_id) <> '' AND cl.branch_id = at.branch_id
             ORDER BY cl.is_default DESC, cl.id LIMIT 1),
            (SELECT cl.id FROM cash_locations cl
             WHERE cl.id = 'cl_main_drawer' AND cl.deleted_at = '' AND cl.is_active = 1 LIMIT 1),
            (SELECT cl.id FROM cash_locations cl
             WHERE cl.deleted_at = '' AND cl.is_active = 1 AND cl.type = 'cash_drawer'
             ORDER BY cl.is_default DESC, cl.id LIMIT 1)
          ) IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM cash_ledger_transactions tx
            WHERE tx.deleted_at = ''
              AND tx.reference_type = 'legacy_account_transaction'
              AND tx.reference_id = at.id
          );
      ''');
    });
  }

  Future<ReceiptVoucher?> findReceiptById(String id) async {
    if (id.trim().isEmpty) return null;
    final row = await _db.customSelect(
      "SELECT * FROM receipt_vouchers WHERE id = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(id.trim())],
    ).getSingleOrNull();
    return row == null
        ? null
        : _receiptFromRow(row.data, await allocationsFor('receipt', id));
  }

  Future<PaymentVoucher?> findPaymentById(String id) async {
    if (id.trim().isEmpty) return null;
    final row = await _db.customSelect(
      "SELECT * FROM payment_vouchers WHERE id = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(id.trim())],
    ).getSingleOrNull();
    return row == null
        ? null
        : _paymentFromRow(row.data, await allocationsFor('payment', id));
  }

  Future<List<PaymentAllocation>> allocationsFor(
      String voucherType, String voucherId) async {
    final rows = await _db.customSelect(
      "SELECT * FROM payment_allocations WHERE voucher_type = ? AND voucher_id = ? AND deleted_at = '' AND status = 'active' ORDER BY created_at, id",
      variables: <Variable<Object>>[
        Variable<String>(voucherType.trim().toLowerCase()),
        Variable<String>(voucherId.trim()),
      ],
    ).get();
    return rows
        .map((row) => _allocationFromRow(row.data))
        .toList(growable: false);
  }

  Future<List<ReceiptVoucher>> listReceipts(
      {String customerId = '', int limit = 100, int offset = 0}) async {
    final where = customerId.trim().isEmpty
        ? "deleted_at = ''"
        : "deleted_at = '' AND customer_id = ?";
    final variables = <Variable<Object>>[
      if (customerId.trim().isNotEmpty) Variable<String>(customerId.trim()),
      Variable<int>(limit.clamp(1, 500).toInt()),
      Variable<int>(offset < 0 ? 0 : offset),
    ];
    final rows = await _db
        .customSelect(
          'SELECT * FROM receipt_vouchers WHERE $where ORDER BY voucher_date DESC, created_at DESC LIMIT ? OFFSET ?',
          variables: variables,
        )
        .get();
    final result = <ReceiptVoucher>[];
    for (final row in rows) {
      final id = row.data['id']?.toString() ?? '';
      result
          .add(_receiptFromRow(row.data, await allocationsFor('receipt', id)));
    }
    return result;
  }

  Future<List<PaymentVoucher>> listPayments(
      {String supplierId = '', int limit = 100, int offset = 0}) async {
    final where = supplierId.trim().isEmpty
        ? "deleted_at = ''"
        : "deleted_at = '' AND supplier_id = ?";
    final variables = <Variable<Object>>[
      if (supplierId.trim().isNotEmpty) Variable<String>(supplierId.trim()),
      Variable<int>(limit.clamp(1, 500).toInt()),
      Variable<int>(offset < 0 ? 0 : offset),
    ];
    final rows = await _db
        .customSelect(
          'SELECT * FROM payment_vouchers WHERE $where ORDER BY voucher_date DESC, created_at DESC LIMIT ? OFFSET ?',
          variables: variables,
        )
        .get();
    final result = <PaymentVoucher>[];
    for (final row in rows) {
      final id = row.data['id']?.toString() ?? '';
      result
          .add(_paymentFromRow(row.data, await allocationsFor('payment', id)));
    }
    return result;
  }

  void _validateCommon({
    required String partyId,
    required double amount,
    bool allowZeroAmount = false,
    required String paymentMethod,
    required String cashLocationId,
    required String cashDrawerSessionId,
  }) {
    if (partyId.trim().isEmpty) {
      throw ArgumentError.value(partyId, 'partyId', 'Must not be empty.');
    }
    if (!amount.isFinite || amount < 0 || (!allowZeroAmount && amount <= 0)) {
      throw ArgumentError.value(amount, 'amount', 'Must be greater than zero.');
    }
    if (_isCash(paymentMethod)) {
      if (cashLocationId.trim().isEmpty || cashDrawerSessionId.trim().isEmpty) {
        throw StateError(
            'Cash vouchers require an open cash drawer location and session.');
      }
    }
  }

  Future<List<PaymentAllocation>> _prepareAllocations({
    required String voucherType,
    required String voucherId,
    required String expectedReferenceType,
    required String partyId,
    required double voucherAmount,
    required String voucherCurrency,
    required List<PaymentAllocationDraft> drafts,
    required String deviceId,
  }) async {
    final prepared = <PaymentAllocation>[];
    final seenTargets = <String>{};
    double allocatedVoucherAmount = 0;
    for (final draft in drafts) {
      if (draft.referenceId.trim().isEmpty ||
          !draft.amount.isFinite ||
          draft.amount < 0 ||
          (draft.amount == 0 && draft.referenceAmount <= 0)) {
        throw ArgumentError('Allocation reference and amount must be valid.');
      }
      if (!seenTargets.add(draft.referenceId.trim())) {
        throw StateError(
            'A voucher cannot allocate the same document more than once.');
      }
      allocatedVoucherAmount += draft.amount;
      if (allocatedVoucherAmount - voucherAmount > PaymentVoucherService._epsilon) {
        throw StateError('Allocated amount cannot exceed voucher amount.');
      }

      final target = expectedReferenceType == 'sale'
          ? await _saleTarget(draft.referenceId.trim())
          : await _purchaseTarget(draft.referenceId.trim(), voucherCurrency);
      if (target == null) {
        throw StateError(
            '${expectedReferenceType == 'sale' ? 'Sale' : 'Purchase'} ${draft.referenceId} does not exist.');
      }
      if (target.partyId.isNotEmpty && target.partyId != partyId) {
        throw StateError(
            'Allocation target belongs to a different ${voucherType == 'receipt' ? 'customer' : 'supplier'}.');
      }
      if (target.isClosedDocument) {
        throw StateError('Cannot allocate a cancelled/returned document.');
      }

      final requestedReferenceCurrency = draft.referenceCurrency.trim().isEmpty
          ? target.currency
          : _currency(draft.referenceCurrency);
      if (requestedReferenceCurrency != target.currency) {
        throw StateError(
            'Allocation reference currency does not match the target document currency.');
      }
      final sameCurrency = voucherCurrency == target.currency;
      final referenceAmount = draft.referenceAmount > 0
          ? draft.referenceAmount
          : (sameCurrency ? draft.amount : 0.0);
      if (!referenceAmount.isFinite || referenceAmount <= 0) {
        throw StateError(
            'Cross-currency allocations require a positive referenceAmount.');
      }
      final exchangeRate = draft.exchangeRate;
      if (!sameCurrency && (!exchangeRate.isFinite || exchangeRate <= 0)) {
        throw StateError(
            'Cross-currency allocations require a positive exchangeRate.');
      }
      if (referenceAmount - target.balanceDue > PaymentVoucherService._epsilon) {
        throw StateError(
            'Allocation exceeds remaining balance of ${target.referenceNumber}.');
      }

      final now = DateTime.now().toUtc();
      prepared.add(PaymentAllocation(
        id: _newId('alloc'),
        voucherType: voucherType,
        voucherId: voucherId,
        referenceType: expectedReferenceType,
        referenceId: target.id,
        referenceNumber: draft.referenceNumber.trim().isEmpty
            ? target.referenceNumber
            : draft.referenceNumber.trim(),
        amount: _money(draft.amount),
        referenceAmount: _money(referenceAmount),
        currency: voucherCurrency,
        referenceCurrency: target.currency,
        exchangeRate: sameCurrency ? 1.0 : exchangeRate,
        createdAt: now,
        updatedAt: now,
        lastModifiedByDeviceId: deviceId.trim(),
      ));
    }
    return prepared;
  }

  Future<_AllocationTarget?> _saleTarget(String id) async {
    final row = await _db.customSelect(
      '''
      SELECT s.id, s.invoice_no, s.customer_id, s.customer_name, s.invoice_currency,
             s.paid_amount, s.transaction_amount, s.discount, s.status,
             COALESCE((SELECT SUM(si.unit_price * si.quantity)
                       FROM sale_items si WHERE si.sale_id = s.id), 0) AS item_total
      FROM sales s
      WHERE s.id = ? AND s.deleted_at = ''
      LIMIT 1
      ''',
      variables: <Variable<Object>>[Variable<String>(id)],
    ).getSingleOrNull();
    if (row == null) return null;
    final data = row.data;
    final txTotal = _number(data['transaction_amount']);
    final itemTotal = _number(data['item_total']);
    final discount = _number(data['discount']);
    final total =
        txTotal > 0 ? txTotal : max(0, itemTotal - discount).toDouble();
    return _AllocationTarget(
      id: id,
      referenceNumber: data['invoice_no']?.toString() ?? '',
      partyId: data['customer_id']?.toString() ?? '',
      partyName: data['customer_name']?.toString() ?? '',
      currency: _currency(data['invoice_currency']?.toString() ?? 'USD'),
      total: total,
      paid: _number(data['paid_amount']),
      status: data['status']?.toString() ?? '',
    );
  }

  Future<_AllocationTarget?> _purchaseTarget(String id, String currency) async {
    final row = await _db.customSelect(
      '''
      SELECT p.id, p.purchase_no, p.supplier_id, p.supplier_name,
             p.paid_amount, p.status,
             COALESCE((SELECT SUM(pi.quantity * pi.unit_cost)
                       FROM purchase_items pi WHERE pi.purchase_id = p.id), 0) AS item_total
      FROM purchases p
      WHERE p.id = ? AND p.deleted_at = ''
      LIMIT 1
      ''',
      variables: <Variable<Object>>[Variable<String>(id)],
    ).getSingleOrNull();
    if (row == null) return null;
    final data = row.data;
    return _AllocationTarget(
      id: id,
      referenceNumber: data['purchase_no']?.toString() ?? '',
      partyId: data['supplier_id']?.toString() ?? '',
      partyName: data['supplier_name']?.toString() ?? '',
      currency: currency,
      total: _number(data['item_total']),
      paid: _number(data['paid_amount']),
      status: data['status']?.toString() ?? '',
    );
  }

  Future<void> _insertReceipt(ReceiptVoucher item) async {
    await _db.customInsert(
      '''
      INSERT INTO receipt_vouchers
        (id, voucher_no, customer_id, customer_name, voucher_date, amount,
         discount, unallocated_amount, currency, payment_method, cash_location_id,
         cash_drawer_session_id, status, notes, created_by, created_by_user_id,
         device_id, branch_id, store_id, idempotency_key, created_at, updated_at,
         deleted_at, sync_status, version, last_modified_by_device_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'posted', ?, ?, ?, ?, ?, ?, ?, ?, ?, '', 'pending', 1, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(item.id),
        Variable<String>(item.voucherNo),
        Variable<String>(item.customerId),
        Variable<String>(item.customerName),
        Variable<String>(item.date.toIso8601String()),
        Variable<double>(item.amount),
        Variable<double>(item.discount),
        Variable<double>(item.unallocatedAmount),
        Variable<String>(item.currency),
        Variable<String>(item.paymentMethod),
        Variable<String>(item.cashLocationId),
        Variable<String>(item.cashDrawerSessionId),
        Variable<String>(item.notes),
        Variable<String>(item.createdBy),
        Variable<String>(item.createdByUserId),
        Variable<String>(item.deviceId),
        Variable<String>(item.branchId),
        Variable<String>(item.storeId),
        Variable<String>(item.idempotencyKey),
        Variable<String>(item.createdAt.toIso8601String()),
        Variable<String>(item.updatedAt.toIso8601String()),
        Variable<String>(item.lastModifiedByDeviceId),
      ],
    );
  }

  Future<void> _insertPayment(PaymentVoucher item) async {
    await _db.customInsert(
      '''
      INSERT INTO payment_vouchers
        (id, voucher_no, supplier_id, supplier_name, voucher_date, amount,
         discount, unallocated_amount, currency, payment_method, cash_location_id,
         cash_drawer_session_id, status, notes, created_by, created_by_user_id,
         device_id, branch_id, store_id, idempotency_key, created_at, updated_at,
         deleted_at, sync_status, version, last_modified_by_device_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'posted', ?, ?, ?, ?, ?, ?, ?, ?, ?, '', 'pending', 1, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(item.id),
        Variable<String>(item.voucherNo),
        Variable<String>(item.supplierId),
        Variable<String>(item.supplierName),
        Variable<String>(item.date.toIso8601String()),
        Variable<double>(item.amount),
        Variable<double>(item.discount),
        Variable<double>(item.unallocatedAmount),
        Variable<String>(item.currency),
        Variable<String>(item.paymentMethod),
        Variable<String>(item.cashLocationId),
        Variable<String>(item.cashDrawerSessionId),
        Variable<String>(item.notes),
        Variable<String>(item.createdBy),
        Variable<String>(item.createdByUserId),
        Variable<String>(item.deviceId),
        Variable<String>(item.branchId),
        Variable<String>(item.storeId),
        Variable<String>(item.idempotencyKey),
        Variable<String>(item.createdAt.toIso8601String()),
        Variable<String>(item.updatedAt.toIso8601String()),
        Variable<String>(item.lastModifiedByDeviceId),
      ],
    );
  }

  Future<void> _insertAllocations(List<PaymentAllocation> items) async {
    for (final item in items) {
      await _db.customInsert(
        '''
        INSERT INTO payment_allocations
          (id, voucher_type, voucher_id, reference_type, reference_id,
           reference_number, amount, reference_amount, currency,
           reference_currency, exchange_rate, allocation_kind, reversal_of_id,
           created_at, updated_at, deleted_at,
           sync_status, version, last_modified_by_device_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', 'pending', 1, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(item.id),
          Variable<String>(item.voucherType),
          Variable<String>(item.voucherId),
          Variable<String>(item.referenceType),
          Variable<String>(item.referenceId),
          Variable<String>(item.referenceNumber),
          Variable<double>(item.amount),
          Variable<double>(item.effectiveReferenceAmount),
          Variable<String>(item.currency),
          Variable<String>(item.referenceCurrency),
          Variable<double>(item.exchangeRate),
          Variable<String>(item.allocationKind),
          Variable<String>(item.reversalOfId),
          Variable<String>(item.createdAt.toIso8601String()),
          Variable<String>(item.updatedAt.toIso8601String()),
          Variable<String>(item.lastModifiedByDeviceId),
        ],
      );
    }
  }
}
