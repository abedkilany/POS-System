part of 'payment_voucher_service.dart';

extension PaymentVoucherServiceSplitPart3 on PaymentVoucherService {

  Future<double> refundSaleCash({
    required String saleId,
    required String invoiceNo,
    required String customerId,
    required String customerName,
    required double requestedAmount,
    double? maxRefundAmount,
    required String cashLocationId,
    required String cashDrawerSessionId,
    required String refundKey,
    String currency = 'USD',
    String notes = '',
    String createdBy = '',
    String createdByUserId = '',
    String deviceId = '',
    String branchId = '',
    String storeId = '',
    DateTime? date,
  }) async {
    if (!requestedAmount.isFinite || requestedAmount <= 0) return 0;
    if (cashLocationId.trim().isEmpty || cashDrawerSessionId.trim().isEmpty) {
      throw StateError('Cash refund requires an open cash drawer session.');
    }
    final cleanKey = refundKey.trim();
    if (cleanKey.isEmpty) throw ArgumentError('refundKey is required.');
    final referenceId = '${saleId.trim()}:$cleanKey';
    final existing = await _db.customSelect(
      "SELECT amount FROM cash_ledger_transactions WHERE idempotency_key = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[
        Variable<String>('sale_refund:$referenceId')
      ],
    ).getSingleOrNull();
    if (existing != null) return _number(existing.data['amount']);

    final refundable = await refundableCashForSale(
      saleId,
      maxRefundAmount: maxRefundAmount,
    );
    final amount = _money(min(requestedAmount, refundable));
    if (amount <= 0) return 0;
    final when = (date ?? DateTime.now()).toUtc();

    final result = await _db.transaction(() async {
      final session = await _db.customSelect(
        "SELECT id FROM cash_drawer_sessions WHERE id = ? AND cash_location_id = ? AND status = 'open' LIMIT 1",
        variables: <Variable<Object>>[
          Variable<String>(cashDrawerSessionId.trim()),
          Variable<String>(cashLocationId.trim()),
        ],
      ).getSingleOrNull();
      if (session == null) {
        throw StateError('Cash drawer session is not open for this refund.');
      }
      final location = await _db.customSelect(
        "SELECT account_id FROM cash_locations WHERE id = ? AND deleted_at = '' AND is_active = 1 LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(cashLocationId.trim())],
      ).getSingleOrNull();
      if (location == null) throw StateError('Cash location is unavailable.');
      await AccountingService.ensureCashOutflowAllowed(
        cashLocationId: cashLocationId,
        amount: amount,
        database: _db,
      );
      final customersAccount =
          await AccountingService.resolveAccountRoleForDatabase(
        _db,
        'accounts_receivable',
      );
      final cashAccount = location.data['account_id']?.toString().trim() ?? '';
      if (cashAccount.isEmpty) {
        throw StateError('Cash location is not linked to a valid account.');
      }
      final entryId = await AccountingService.createPostedEntry(
        JournalEntryDraft(
          entryDate: when,
          referenceType: 'sale_refund',
          referenceId: referenceId,
          referenceNo: invoiceNo.trim(),
          description: 'Cash refund for sale ${invoiceNo.trim()}',
          source: 'system',
          createdBy: createdBy.trim(),
          storeId: storeId.trim(),
          branchId: branchId.trim(),
          lines: <JournalLineDraft>[
            JournalLineDraft(
              accountId: customersAccount,
              debit: amount,
              credit: 0,
              memo: 'Customer refund',
              partyType: 'customer',
              partyId: customerId.trim(),
              partyName: customerName.trim(),
            ),
            JournalLineDraft(
              accountId: cashAccount,
              debit: 0,
              credit: amount,
              memo: 'Cash paid to customer',
              partyType: 'customer',
              partyId: customerId.trim(),
              partyName: customerName.trim(),
            ),
          ],
        ),
        database: _db,
        withinExistingTransaction: true,
      );
      if (entryId.isEmpty) {
        throw StateError('Refund journal entry was not created.');
      }
      final now = DateTime.now().toUtc();
      await _cashLedger.appendInExistingTransaction(CashLedgerTransaction(
        id: _cashLedger.generateId(),
        type: 'refund',
        direction: 'out',
        amount: amount,
        currency: _currency(currency),
        cashLocationId: cashLocationId.trim(),
        cashDrawerSessionId: cashDrawerSessionId.trim(),
        referenceType: 'sale_refund',
        referenceId: referenceId,
        referenceNumber: invoiceNo.trim(),
        partyType: 'customer',
        partyId: customerId.trim(),
        partyName: customerName.trim(),
        paymentMethod: 'Cash',
        createdBy: createdBy.trim(),
        createdByUserId: createdByUserId.trim(),
        deviceId: deviceId.trim(),
        branchId: branchId.trim(),
        storeId: storeId.trim(),
        notes: notes.trim(),
        idempotencyKey: 'sale_refund:$referenceId',
        occurredAt: when,
        createdAt: now,
        updatedAt: now,
        lastModifiedByDeviceId: deviceId.trim(),
      ));
      await _insertCompatibilityRefundMovement(
        id: '$referenceId-customer-refund',
        accountType: 'customer',
        accountId: customerId.trim(),
        accountName: customerName.trim(),
        referenceId: referenceId,
        referenceNo: invoiceNo.trim(),
        debit: amount,
        credit: 0,
        currency: currency,
        note: notes.trim().isEmpty
            ? 'Cash refund for ${invoiceNo.trim()}'
            : notes.trim(),
        deviceId: deviceId,
        branchId: branchId,
        storeId: storeId,
        occurredAt: when,
      );
      await _allocateRefundCoverage(
        refundId: referenceId,
        voucherType: 'receipt',
        referenceType: 'sale',
        referenceId: saleId.trim(),
        amount: amount,
        deviceId: deviceId,
      );
      await _moveCashLocation(cashLocationId.trim(), -amount, now);
      await _rebuildAllocationCache(
        referenceType: 'sale',
        referenceId: saleId.trim(),
        deviceId: deviceId,
      );
      return amount;
    });
    AccountingService.notifyCommittedMutation();
    return result;
  }

  Future<double> refundableCashForPurchase(String purchaseId,
      {double? maxRefundAmount}) async {
    final totalRow = await _db.customSelect(
      '''
       SELECT COALESCE(SUM(pa.reference_amount), 0) AS total
      FROM payment_allocations pa
      INNER JOIN payment_vouchers pv ON pv.id = pa.voucher_id
      WHERE pa.voucher_type = 'payment'
        AND pa.reference_type = 'purchase'
        AND pa.reference_id = ?
        AND pa.deleted_at = ''
         AND pa.status = 'active'
         AND pa.allocation_kind = 'allocation'
        AND pv.deleted_at = ''
        AND pv.status = 'posted'
        AND LOWER(pv.payment_method) = 'cash'
      ''',
      variables: <Variable<Object>>[Variable<String>(purchaseId.trim())],
    ).getSingle();
    final refundedRow = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM cash_ledger_transactions refund_tx
      WHERE refund_tx.type = 'supplier_refund'
        AND refund_tx.direction = 'in'
        AND refund_tx.reference_type = 'purchase_refund'
        AND (refund_tx.reference_id = ? OR refund_tx.reference_id LIKE ?)
        AND refund_tx.deleted_at = ''
        AND NOT EXISTS (
          SELECT 1
          FROM cash_ledger_transactions reversal_tx
          WHERE reversal_tx.reversal_of_id = refund_tx.id
            AND reversal_tx.deleted_at = ''
        )
      ''',
      variables: <Variable<Object>>[
        Variable<String>(purchaseId.trim()),
        Variable<String>('${purchaseId.trim()}:%'),
      ],
    ).getSingle();
    final unallocated = await unallocatedCashForPurchase(purchaseId);
    final remaining = _money(_number(totalRow.data['total']) +
            unallocated -
            _number(refundedRow.data['total']))
        .clamp(0, double.infinity)
        .toDouble();
    if (maxRefundAmount == null || !maxRefundAmount.isFinite) {
      return remaining;
    }
    // maxRefundAmount is the caller's CURRENT refund entitlement (for
    // example, a new overpayment created by editing the purchase). Historical
    // supplier refunds are already reflected in voucher allocation reversals /
    // unallocated balances, so subtracting them again here would consume the
    // new entitlement twice.
    final currentEntitlement =
        _money(maxRefundAmount).clamp(0, double.infinity).toDouble();
    return min(remaining, currentEntitlement);
  }

  Future<double> unallocatedCashForPurchase(String purchaseId) async {
    final row = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(pv.unallocated_amount), 0) AS total
      FROM payment_vouchers pv
      INNER JOIN purchases p ON p.supplier_id = pv.supplier_id
      WHERE p.id = ? AND pv.deleted_at = '' AND pv.status = 'posted'
        AND LOWER(pv.payment_method) = 'cash'
        AND pv.unallocated_amount > 0
        AND EXISTS (
          SELECT 1
          FROM payment_allocations pa
          WHERE pa.voucher_type = 'payment'
            AND pa.voucher_id = pv.id
            AND pa.reference_type = 'purchase'
            AND pa.reference_id = p.id
            AND pa.allocation_kind = 'allocation'
            AND pa.status = 'active'
            AND pa.deleted_at = ''
        )
      ''',
      variables: <Variable<Object>>[Variable<String>(purchaseId.trim())],
    ).getSingle();
    return _money(_number(row.data['total']));
  }

  Future<double> refundableCashForExpense(String expenseId,
      {double? maxRefundAmount}) async {
    final totalRow = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM cash_ledger_transactions
      WHERE type = 'expense' AND direction = 'out'
        AND reference_type = 'expense' AND reference_id = ?
        AND deleted_at = ''
      ''',
      variables: <Variable<Object>>[Variable<String>(expenseId.trim())],
    ).getSingle();
    final refundedRow = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM cash_ledger_transactions refund_tx
      WHERE refund_tx.type = 'expense_refund'
        AND refund_tx.direction = 'in'
        AND refund_tx.reference_type = 'expense_refund'
        AND (refund_tx.reference_id = ? OR refund_tx.reference_id LIKE ?)
        AND refund_tx.deleted_at = ''
        AND NOT EXISTS (
          SELECT 1 FROM cash_ledger_transactions reversal_tx
          WHERE reversal_tx.reversal_of_id = refund_tx.id
            AND reversal_tx.deleted_at = ''
        )
      ''',
      variables: <Variable<Object>>[
        Variable<String>(expenseId.trim()),
        Variable<String>('${expenseId.trim()}:%'),
      ],
    ).getSingle();
    final paid = _number(totalRow.data['total']);
    final refunded = _number(refundedRow.data['total']);
    final remaining =
        _money(paid - refunded).clamp(0, double.infinity).toDouble();
    if (maxRefundAmount == null || !maxRefundAmount.isFinite) return remaining;
    return min(
        remaining,
        _money(maxRefundAmount - refunded)
            .clamp(0, double.infinity)
            .toDouble());
  }

  Future<double> cashPaidForExpense(String expenseId) async {
    final row = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM cash_ledger_transactions
      WHERE type = 'expense' AND direction = 'out'
        AND reference_type = 'expense' AND reference_id = ?
        AND deleted_at = ''
      ''',
      variables: <Variable<Object>>[Variable<String>(expenseId.trim())],
    ).getSingle();
    return _number(row.data['total']);
  }

  Future<double> refundableCashForPurchaseReturn(
    String purchaseReturnId,
  ) async {
    final cleanId = purchaseReturnId.trim();
    if (cleanId.isEmpty) return 0;
    final totalRow = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(pi.quantity * pi.unit_cost), 0) AS total
      FROM purchases p
      INNER JOIN purchase_items pi ON pi.purchase_id = p.id
      WHERE p.id = ? AND p.document_type = 'purchase_return'
        AND p.deleted_at = ''
      ''',
      variables: <Variable<Object>>[Variable<String>(cleanId)],
    ).getSingle();
    final refundedRow = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM cash_ledger_transactions
      WHERE type = 'supplier_refund' AND direction = 'in'
        AND reference_type = 'purchase_return_refund'
        AND (reference_id = ? OR reference_id LIKE ?)
        AND reversal_of_id = '' AND deleted_at = ''
        AND NOT EXISTS (
          SELECT 1
          FROM cash_ledger_transactions reversal_tx
          WHERE reversal_tx.reversal_of_id = cash_ledger_transactions.id
            AND reversal_tx.deleted_at = ''
        )
      ''',
      variables: <Variable<Object>>[
        Variable<String>(cleanId),
        Variable<String>('$cleanId:%'),
      ],
    ).getSingle();
    final total = _number(totalRow.data['total']);
    final refunded = _number(refundedRow.data['total']);
    return _money(max(0, total - refunded));
  }

  Future<void> ensurePurchaseReturnJournal({
    required String purchaseReturnId,
    required String purchaseReturnNo,
    required String supplierId,
    required String supplierName,
    required DateTime returnDate,
    required String storeId,
    required String branchId,
    required String deviceId,
  }) async {
    final cleanId = purchaseReturnId.trim();
    if (cleanId.isEmpty) return;
    final existing = await _db.customSelect(
      '''
      SELECT id
      FROM journal_entries
      WHERE reference_type = 'purchase_return'
        AND reference_id = ? AND deleted_at = ''
      LIMIT 1
      ''',
      variables: <Variable<Object>>[Variable<String>(cleanId)],
    ).getSingleOrNull();
    if (existing != null) return;
    final totalRow = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(quantity * unit_cost), 0) AS total
      FROM purchase_items
      WHERE purchase_id = ?
      ''',
      variables: <Variable<Object>>[Variable<String>(cleanId)],
    ).getSingle();
    final total = _money(_number(totalRow.data['total']));
    if (total <= 0.000001) return;
    await _db.transaction(() async {
      final recheck = await _db.customSelect(
        '''
        SELECT id
        FROM journal_entries
        WHERE reference_type = 'purchase_return'
          AND reference_id = ? AND deleted_at = ''
        LIMIT 1
        ''',
        variables: <Variable<Object>>[Variable<String>(cleanId)],
      ).getSingleOrNull();
      if (recheck != null) return;
      final inventoryRows = await _db.customSelect(
        '''
        SELECT product_id, COALESCE(SUM(quantity * unit_cost), 0) AS total
        FROM purchase_items
        WHERE purchase_id = ?
        GROUP BY product_id
        ''',
        variables: <Variable<Object>>[Variable<String>(cleanId)],
      ).get();
      final inventoryAmountsByAccount = <String, double>{};
      for (final row in inventoryRows) {
        final productId = row.data['product_id']?.toString().trim() ?? '';
        final amount = _money(_number(row.data['total']));
        if (productId.isEmpty || amount <= 0) continue;
        final inventoryAccount = await AccountingService
            .resolveInventoryAccountForProductForDatabase(_db, productId);
        inventoryAmountsByAccount.update(
          inventoryAccount,
          (value) => value + amount,
          ifAbsent: () => amount,
        );
      }
      if (inventoryAmountsByAccount.isEmpty) {
        throw StateError('Purchase return has no inventory value to post.');
      }
      final suppliersAccount =
          await AccountingService.resolveAccountRoleForDatabase(
        _db,
        'accounts_payable',
      );
      final entryId = await AccountingService.createPostedEntry(
        JournalEntryDraft(
          entryDate: returnDate,
          referenceType: 'purchase_return',
          referenceId: cleanId,
          referenceNo: purchaseReturnNo.trim(),
          description: 'Purchase return ${purchaseReturnNo.trim()}',
          source: 'system',
          createdBy: deviceId.trim(),
          storeId: storeId.trim(),
          branchId: branchId.trim(),
          lines: <JournalLineDraft>[
            JournalLineDraft(
              accountId: suppliersAccount,
              debit: total,
              credit: 0,
              memo:
                  'Reduction of supplier payable for ${purchaseReturnNo.trim()}',
              partyType: 'supplier',
              partyId: supplierId.trim(),
              partyName: supplierName.trim(),
            ),
            ...inventoryAmountsByAccount.entries.map(
              (inventory) => JournalLineDraft(
                accountId: inventory.key,
                debit: 0,
                credit: inventory.value,
                memo:
                    'Inventory returned to supplier for ${purchaseReturnNo.trim()}',
                partyType: 'supplier',
                partyId: supplierId.trim(),
                partyName: supplierName.trim(),
              ),
            ),
          ],
        ),
        database: _db,
        withinExistingTransaction: true,
      );
      if (entryId.isEmpty) {
        throw StateError('Purchase return journal entry was not created.');
      }
    });
    AccountingService.notifyCommittedMutation();
  }

  Future<double> refundPurchaseReturnCash({
    required String purchaseReturnId,
    required String purchaseReturnNo,
    required String supplierId,
    required String supplierName,
    required String cashLocationId,
    required String cashDrawerSessionId,
    double? requestedAmount,
    String currency = 'USD',
    String notes = '',
    String createdBy = '',
    String createdByUserId = '',
    String deviceId = '',
    String branchId = '',
    String storeId = '',
    String refundKey = '',
    DateTime? date,
  }) async {
    final cleanReturnId = purchaseReturnId.trim();
    if (cleanReturnId.isEmpty) {
      throw ArgumentError('Purchase return is required.');
    }
    final refundable = await refundableCashForPurchaseReturn(cleanReturnId);
    if (refundable <= 0.000001) return 0;
    final requested = requestedAmount == null || !requestedAmount.isFinite
        ? refundable
        : requestedAmount;
    if (requested <= 0) {
      throw ArgumentError('Refund amount must be greater than zero.');
    }
    final amount = _money(min(requested, refundable));
    if (amount <= 0) return 0;
    final cleanKey = refundKey.trim().isEmpty
        ? 'manual:${DateTime.now().microsecondsSinceEpoch}:$deviceId'
        : refundKey.trim();
    final refundReferenceId = '$cleanReturnId:$cleanKey';
    final refundIdempotencyKey = 'purchase_return_refund:$refundReferenceId';
    final existingByKey = await _db.customSelect(
      "SELECT amount FROM cash_ledger_transactions WHERE idempotency_key = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(refundIdempotencyKey)],
    ).getSingleOrNull();
    if (existingByKey != null) return _number(existingByKey.data['amount']);

    final when = (date ?? DateTime.now()).toUtc();
    final result = await _db.transaction(() async {
      final session = await _db.customSelect(
        "SELECT id FROM cash_drawer_sessions WHERE id = ? AND cash_location_id = ? AND status = 'open' LIMIT 1",
        variables: <Variable<Object>>[
          Variable<String>(cashDrawerSessionId.trim()),
          Variable<String>(cashLocationId.trim()),
        ],
      ).getSingleOrNull();
      if (session == null) {
        throw StateError(
            'Cash drawer session is not open for purchase return refund.');
      }
      final location = await _db.customSelect(
        "SELECT account_id FROM cash_locations WHERE id = ? AND deleted_at = '' AND is_active = 1 LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(cashLocationId.trim())],
      ).getSingleOrNull();
      if (location == null) throw StateError('Cash location is unavailable.');
      final suppliersAccount =
          await AccountingService.resolveAccountRoleForDatabase(
        _db,
        'accounts_payable',
      );
      final cashAccount = location.data['account_id']?.toString().trim() ?? '';
      if (cashAccount.isEmpty) {
        throw StateError('Cash location is not linked to a valid account.');
      }
      final entryId = await AccountingService.createPostedEntry(
        JournalEntryDraft(
          entryDate: when,
          referenceType: 'purchase_return_refund',
          referenceId: refundReferenceId,
          referenceNo: purchaseReturnNo.trim(),
          description:
              'Cash refund from supplier for purchase return ${purchaseReturnNo.trim()}',
          source: 'system',
          createdBy: createdBy.trim(),
          storeId: storeId.trim(),
          branchId: branchId.trim(),
          lines: <JournalLineDraft>[
            JournalLineDraft(
              accountId: cashAccount,
              debit: amount,
              credit: 0,
              memo: 'Cash received from supplier for purchase return',
              partyType: 'supplier',
              partyId: supplierId.trim(),
              partyName: supplierName.trim(),
            ),
            JournalLineDraft(
              accountId: suppliersAccount,
              debit: 0,
              credit: amount,
              memo: 'Settlement of purchase return credit',
              partyType: 'supplier',
              partyId: supplierId.trim(),
              partyName: supplierName.trim(),
            ),
          ],
        ),
        database: _db,
        withinExistingTransaction: true,
      );
      if (entryId.isEmpty) {
        throw StateError(
            'Purchase return refund journal entry was not created.');
      }
      final now = DateTime.now().toUtc();
      final ledgerId = _cashLedger.generateId();
      await _cashLedger.appendInExistingTransaction(CashLedgerTransaction(
        id: ledgerId,
        type: 'supplier_refund',
        direction: 'in',
        amount: amount,
        currency: _currency(currency),
        cashLocationId: cashLocationId.trim(),
        cashDrawerSessionId: cashDrawerSessionId.trim(),
        referenceType: 'purchase_return_refund',
        referenceId: refundReferenceId,
        referenceNumber: purchaseReturnNo.trim(),
        partyType: 'supplier',
        partyId: supplierId.trim(),
        partyName: supplierName.trim(),
        paymentMethod: 'Cash',
        createdBy: createdBy.trim(),
        createdByUserId: createdByUserId.trim(),
        deviceId: deviceId.trim(),
        branchId: branchId.trim(),
        storeId: storeId.trim(),
        notes: notes.trim(),
        idempotencyKey: refundIdempotencyKey,
        occurredAt: when,
        createdAt: now,
        updatedAt: now,
        lastModifiedByDeviceId: deviceId.trim(),
      ));
      final nextSort = await _db
          .customSelect(
            'SELECT COALESCE(MAX(sort_index), 0) + 1 AS next_sort FROM account_transactions',
          )
          .getSingle();
      final sortIndex = (nextSort.data['next_sort'] as num?)?.toInt() ?? 1;
      final isoWhen = when.toIso8601String();
      final compatibilityId = '$ledgerId-supplier-return-refund';
      final inserted = await _db.customInsert(
        '''
        INSERT OR IGNORE INTO account_transactions
          (id, entity_type, created_at, updated_at, deleted_at,
           device_id, sync_status, store_id, branch_id, version, sort_index,
           account_type, account_id, account_name, transaction_date,
           transaction_type, reference_id, reference_no, debit, credit,
           currency, payment_method, note, last_modified_by_device_id)
        VALUES (?, 'accountTransaction', ?, ?, '', ?, 'pending', ?, ?, 1, ?,
                'supplier', ?, ?, ?, 'paymentReversal', ?, ?, 0, ?, ?, 'Cash', ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(compatibilityId),
          Variable<String>(isoWhen),
          Variable<String>(isoWhen),
          Variable<String>(deviceId.trim()),
          Variable<String>(storeId.trim()),
          Variable<String>(branchId.trim()),
          Variable<int>(sortIndex),
          Variable<String>(supplierId.trim()),
          Variable<String>(supplierName.trim()),
          Variable<String>(isoWhen),
          Variable<String>(cleanReturnId),
          Variable<String>(purchaseReturnNo.trim()),
          Variable<double>(amount),
          Variable<String>(_currency(currency)),
          Variable<String>(notes.trim().isEmpty
              ? 'Cash refund for purchase return ${purchaseReturnNo.trim()}'
              : notes.trim()),
          Variable<String>(deviceId.trim()),
        ],
      );
      if (inserted <= 0) {
        throw StateError(
            'Purchase return refund account movement was not created.');
      }
      await _moveCashLocation(cashLocationId.trim(), amount, now);
      return amount;
    });
    AccountingService.notifyCommittedMutation();
    return result;
  }
}
