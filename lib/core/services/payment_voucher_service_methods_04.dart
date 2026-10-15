part of 'payment_voucher_service.dart';

extension PaymentVoucherServiceSplitPart4 on PaymentVoucherService {

  Future<double> refundPurchaseCash({
    required String purchaseId,
    required String purchaseNo,
    required String supplierId,
    required String supplierName,
    required String cashLocationId,
    required String cashDrawerSessionId,
    double? requestedAmount,
    double? maxRefundAmount,
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
    final cleanPurchaseId = purchaseId.trim();
    final cleanRefundKey = refundKey.trim();
    final activeRefund = await _db.customSelect(
      '''
      SELECT refund_tx.amount
      FROM cash_ledger_transactions refund_tx
      WHERE refund_tx.type = 'supplier_refund'
        AND refund_tx.direction = 'in'
        AND refund_tx.reference_type = 'purchase_refund'
        AND (refund_tx.reference_id = ? OR refund_tx.reference_id LIKE ?)
        AND refund_tx.reversal_of_id = ''
        AND refund_tx.deleted_at = ''
        AND NOT EXISTS (
          SELECT 1
          FROM cash_ledger_transactions reversal_tx
          WHERE reversal_tx.reversal_of_id = refund_tx.id
            AND reversal_tx.deleted_at = ''
        )
      ORDER BY refund_tx.occurred_at DESC, refund_tx.created_at DESC
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(cleanPurchaseId),
        Variable<String>('$cleanPurchaseId:%'),
      ],
    ).getSingleOrNull();
    // Preserve the original idempotent full-refund API: callers that do not
    // specify an amount get the already-posted active refund back on retry.
    // Explicit amounts represent deliberate partial refund events and may be
    // posted repeatedly until refundableCashForPurchase reaches zero.
    if (activeRefund != null &&
        requestedAmount == null &&
        cleanRefundKey.isEmpty) {
      return _number(activeRefund.data['amount']);
    }

    final priorRefunds = await _db.customSelect(
      '''
      SELECT COUNT(*) AS count
      FROM cash_ledger_transactions
      WHERE type = 'supplier_refund'
        AND direction = 'in'
        AND reference_type = 'purchase_refund'
        AND (reference_id = ? OR reference_id LIKE ?)
        AND reversal_of_id = ''
        AND deleted_at = ''
      ''',
      variables: <Variable<Object>>[
        Variable<String>(cleanPurchaseId),
        Variable<String>('$cleanPurchaseId:%'),
      ],
    ).getSingle();
    final priorCount = (priorRefunds.data['count'] as num?)?.toInt() ?? 0;
    final resolvedRefundKey = cleanRefundKey.isNotEmpty
        ? cleanRefundKey
        : (requestedAmount == null
            ? (priorCount == 0 ? 'full' : 'full-${priorCount + 1}')
            : 'partial-${priorCount + 1}');
    final refundReferenceId = '$cleanPurchaseId:$resolvedRefundKey';
    final refundIdempotencyKey = 'purchase_refund:$refundReferenceId';
    final existingByKey = await _db.customSelect(
      "SELECT amount FROM cash_ledger_transactions WHERE idempotency_key = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(refundIdempotencyKey)],
    ).getSingleOrNull();
    if (existingByKey != null) return _number(existingByKey.data['amount']);
    final refundable = await refundableCashForPurchase(
      cleanPurchaseId,
      maxRefundAmount: maxRefundAmount,
    );
    if (refundable <= 0) return 0;
    final requested = requestedAmount == null || !requestedAmount.isFinite
        ? refundable
        : requestedAmount;
    if (requested <= 0) {
      throw ArgumentError('Refund amount must be greater than zero.');
    }
    final amount = _money(min(requested, refundable));
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
        throw StateError(
            'Cash drawer session is not open for supplier refund.');
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
          referenceType: 'purchase_refund',
          referenceId: refundReferenceId,
          referenceNo: purchaseNo.trim(),
          description:
              'Cash refund from supplier for purchase ${purchaseNo.trim()}',
          source: 'system',
          createdBy: createdBy.trim(),
          storeId: storeId.trim(),
          branchId: branchId.trim(),
          lines: <JournalLineDraft>[
            JournalLineDraft(
              accountId: cashAccount,
              debit: amount,
              credit: 0,
              memo: 'Cash received from supplier',
              partyType: 'supplier',
              partyId: supplierId.trim(),
              partyName: supplierName.trim(),
            ),
            JournalLineDraft(
              accountId: suppliersAccount,
              debit: 0,
              credit: amount,
              memo: 'Supplier payment reversal',
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
        throw StateError('Supplier refund journal entry was not created.');
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
        referenceType: 'purchase_refund',
        referenceId: refundReferenceId,
        referenceNumber: purchaseNo.trim(),
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

      // Keep the compatibility supplier ledger in the SAME SQLite transaction
      // as the journal, Cash Ledger movement and drawer balance. This prevents
      // a committed cash refund from existing without the corresponding
      // supplier account movement after a crash or follow-up save failure.
      final nextSort = await _db
          .customSelect(
            'SELECT COALESCE(MAX(sort_index), 0) + 1 AS next_sort FROM account_transactions',
          )
          .getSingle();
      final sortIndex = (nextSort.data['next_sort'] as num?)?.toInt() ?? 1;
      final isoWhen = when.toIso8601String();
      final compatibilityId = '$ledgerId-supplier-refund';
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
          Variable<String>(cleanPurchaseId),
          Variable<String>(purchaseNo.trim()),
          Variable<double>(amount),
          Variable<String>(_currency(currency)),
          Variable<String>(notes.trim().isEmpty
              ? 'Cash refund from supplier for ${purchaseNo.trim()}'
              : notes.trim()),
          Variable<String>(deviceId.trim()),
        ],
      );
      if (inserted <= 0) {
        throw StateError('Supplier refund account movement was not created.');
      }

      await _allocateRefundCoverage(
        refundId: refundReferenceId,
        voucherType: 'payment',
        referenceType: 'purchase',
        referenceId: cleanPurchaseId,
        amount: amount,
        deviceId: deviceId,
      );
      await _moveCashLocation(cashLocationId.trim(), amount, now);
      await _rebuildAllocationCache(
        referenceType: 'purchase',
        referenceId: cleanPurchaseId,
        deviceId: deviceId,
      );
      return amount;
    });
    AccountingService.notifyCommittedMutation();
    return result;
  }

  Future<double> refundExpenseCash({
    required String expenseId,
    required String expenseTitle,
    required double requestedAmount,
    double? maxRefundAmount,
    required String cashLocationId,
    required String cashDrawerSessionId,
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
    if (!requestedAmount.isFinite || requestedAmount <= 0) return 0;
    final cleanExpenseId = expenseId.trim();
    final cleanKey = refundKey.trim().isEmpty ? 'full' : refundKey.trim();
    final refundReferenceId = '$cleanExpenseId:$cleanKey';
    final idempotencyKey = 'expense_refund:$refundReferenceId';
    final existing = await _db.customSelect(
      "SELECT amount FROM cash_ledger_transactions WHERE idempotency_key = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(idempotencyKey)],
    ).getSingleOrNull();
    if (existing != null) return _number(existing.data['amount']);
    final refundable = await refundableCashForExpense(
      cleanExpenseId,
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
      final expenseAccount = await _db.customSelect(
        '''
        SELECT jl.account_id
        FROM journal_entries je
        INNER JOIN journal_lines jl ON jl.entry_id = je.id
        WHERE je.reference_type = 'expense' AND je.reference_id = ?
          AND je.deleted_at = '' AND jl.debit > 0
        ORDER BY je.created_at DESC, jl.line_no ASC LIMIT 1
        ''',
        variables: <Variable<Object>>[Variable<String>(cleanExpenseId)],
      ).getSingleOrNull();
      final cashAccount = location.data['account_id']?.toString().trim() ?? '';
      final expenseAccountId =
          expenseAccount?.data['account_id']?.toString().trim() ?? '';
      if (cashAccount.isEmpty || expenseAccountId.isEmpty) {
        throw StateError(
            'The original expense accounting entry is unavailable.');
      }
      final entryId = await AccountingService.createPostedEntry(
        JournalEntryDraft(
          entryDate: when,
          referenceType: 'expense_refund',
          referenceId: refundReferenceId,
          referenceNo: expenseTitle.trim(),
          description: 'Cash refund for expense ${expenseTitle.trim()}',
          source: 'system',
          createdBy: createdBy.trim(),
          storeId: storeId.trim(),
          branchId: branchId.trim(),
          lines: <JournalLineDraft>[
            JournalLineDraft(
                accountId: cashAccount,
                debit: amount,
                credit: 0,
                memo: 'Expense overpayment refund'),
            JournalLineDraft(
                accountId: expenseAccountId,
                debit: 0,
                credit: amount,
                memo: 'Expense overpayment refund'),
          ],
        ),
        database: _db,
        withinExistingTransaction: true,
      );
      if (entryId.isEmpty) {
        throw StateError('Expense refund journal entry was not created.');
      }
      final now = DateTime.now().toUtc();
      await _cashLedger.appendInExistingTransaction(CashLedgerTransaction(
        id: _cashLedger.generateId(),
        type: 'expense_refund',
        direction: 'in',
        amount: amount,
        currency: _currency(currency),
        cashLocationId: cashLocationId.trim(),
        cashDrawerSessionId: cashDrawerSessionId.trim(),
        referenceType: 'expense_refund',
        referenceId: refundReferenceId,
        referenceNumber: expenseTitle.trim(),
        paymentMethod: 'Cash',
        createdBy: createdBy.trim(),
        createdByUserId: createdByUserId.trim(),
        deviceId: deviceId.trim(),
        branchId: branchId.trim(),
        storeId: storeId.trim(),
        notes: notes.trim(),
        idempotencyKey: idempotencyKey,
        occurredAt: when,
        createdAt: now,
        updatedAt: now,
        lastModifiedByDeviceId: deviceId.trim(),
      ));
      await _moveCashLocation(cashLocationId.trim(), amount, now);
      return amount;
    });
    AccountingService.notifyCommittedMutation();
    return result;
  }

  /// Phase 6: reverses a posted receipt without deleting its financial history.
  ///
  /// The original voucher, allocation rows, journal entry and Cash Ledger row
  /// remain queryable. Allocations are marked reversed so invoice paid_amount
  /// can be rebuilt from active posted vouchers only.
  Future<bool> reverseReceiptVoucher({
    required String voucherId,
    String reason = '',
    String createdBy = '',
    String createdByUserId = '',
    String deviceId = '',
    DateTime? occurredAt,
  }) {
    return _reverseVoucher(
      voucherType: 'receipt',
      voucherId: voucherId,
      reason: reason,
      createdBy: createdBy,
      createdByUserId: createdByUserId,
      deviceId: deviceId,
      occurredAt: occurredAt,
    );
  }

  /// Phase 6 counterpart for supplier payment vouchers.
  Future<bool> reversePaymentVoucher({
    required String voucherId,
    String reason = '',
    String createdBy = '',
    String createdByUserId = '',
    String deviceId = '',
    DateTime? occurredAt,
  }) {
    return _reverseVoucher(
      voucherType: 'payment',
      voucherId: voucherId,
      reason: reason,
      createdBy: createdBy,
      createdByUserId: createdByUserId,
      deviceId: deviceId,
      occurredAt: occurredAt,
    );
  }

  Future<bool> _reverseVoucher({
    required String voucherType,
    required String voucherId,
    required String reason,
    required String createdBy,
    required String createdByUserId,
    required String deviceId,
    required DateTime? occurredAt,
  }) async {
    final type = voucherType.trim().toLowerCase();
    final id = voucherId.trim();
    if (id.isEmpty || (type != 'receipt' && type != 'payment')) {
      throw ArgumentError('A valid voucher type and voucherId are required.');
    }
    final table = type == 'receipt' ? 'receipt_vouchers' : 'payment_vouchers';
    final referenceType =
        type == 'receipt' ? 'receipt_voucher' : 'payment_voucher';

    final before = await _db.customSelect(
      'SELECT status, payment_method FROM $table WHERE id = ? AND deleted_at = \'\' LIMIT 1',
      variables: <Variable<Object>>[Variable<String>(id)],
    ).getSingleOrNull();
    if (before == null) throw StateError('Voucher $id does not exist.');
    final beforeStatus = before.data['status']?.toString() ?? '';
    if (beforeStatus == 'reversed' || beforeStatus == 'void') return false;
    if (beforeStatus != 'posted') {
      throw StateError('Only posted vouchers can be reversed.');
    }

    final isCashVoucher =
        _isCash(before.data['payment_method']?.toString() ?? '');
    if (isCashVoucher) {
      // This understands both the legacy base reference and versioned
      // receipt_edit/payment_edit Cash Ledger references.
      await _ensureVoucherCashHistoryAvailable(
        voucherType: type,
        voucherId: id,
      );
    }

    final when = (occurredAt ?? DateTime.now()).toUtc();
    final result = await _db.transaction(() async {
      final voucher = await _db.customSelect(
        'SELECT status, payment_method FROM $table WHERE id = ? AND deleted_at = \'\' LIMIT 1',
        variables: <Variable<Object>>[Variable<String>(id)],
      ).getSingleOrNull();
      if (voucher == null) throw StateError('Voucher $id disappeared.');
      final status = voucher.data['status']?.toString() ?? '';
      if (status == 'reversed' || status == 'void') return false;
      if (status != 'posted') {
        throw StateError('Only posted vouchers can be reversed.');
      }

      final allocations = await _db.customSelect(
        '''
        SELECT reference_type, reference_id
        FROM payment_allocations
        WHERE voucher_type = ? AND voucher_id = ?
          AND deleted_at = '' AND status = 'active'
        ''',
        variables: <Variable<Object>>[
          Variable<String>(type),
          Variable<String>(id),
        ],
      ).get();
      final affected = <String, String>{
        for (final row in allocations)
          row.data['reference_id']?.toString() ?? '':
              row.data['reference_type']?.toString() ?? '',
      }..remove('');

      if (_isCash(voucher.data['payment_method']?.toString() ?? '')) {
        await _reverseActiveVoucherCashMovementsInTransaction(
          voucherType: type,
          voucherId: id,
          reason: reason,
          createdBy: createdBy,
          createdByUserId: createdByUserId,
          deviceId: deviceId,
        );
      }

      await AccountingService.reverseEntryForReference(
        referenceType: referenceType,
        referenceId: id,
        reason: reason,
        createdBy: createdBy,
        adjustCashLocationBalance: false,
        notifyChange: false,
        withinExistingTransaction: true,
      );

      final now = DateTime.now().toUtc().toIso8601String();
      await _db.customUpdate(
        '''
        UPDATE payment_allocations
        SET status = 'reversed', reversed_at = ?, reversal_reason = ?,
            reversed_by = ?, reversed_by_user_id = ?, updated_at = ?,
            sync_status = 'pending', version = version + 1,
            last_modified_by_device_id = ?
        WHERE voucher_type = ? AND voucher_id = ?
          AND deleted_at = '' AND status = 'active'
        ''',
        variables: <Variable<Object>>[
          Variable<String>(now),
          Variable<String>(reason.trim()),
          Variable<String>(createdBy.trim()),
          Variable<String>(createdByUserId.trim()),
          Variable<String>(now),
          Variable<String>(deviceId.trim()),
          Variable<String>(type),
          Variable<String>(id),
        ],
      );

      for (final entry in affected.entries) {
        await _rebuildAllocationCache(
          referenceType: entry.value,
          referenceId: entry.key,
          deviceId: deviceId,
        );
      }

      final updatedVoucherRows = await _db.customUpdate(
        '''
        UPDATE $table
        SET status = 'reversed', reversed_at = ?, reversal_reason = ?,
            reversed_by = ?, reversed_by_user_id = ?, updated_at = ?,
            sync_status = 'pending', version = version + 1,
            last_modified_by_device_id = ?
        WHERE id = ? AND deleted_at = '' AND status = 'posted'
        ''',
        variables: <Variable<Object>>[
          Variable<String>(now),
          Variable<String>(reason.trim()),
          Variable<String>(createdBy.trim()),
          Variable<String>(createdByUserId.trim()),
          Variable<String>(now),
          Variable<String>(deviceId.trim()),
          Variable<String>(id),
        ],
      );
      if (updatedVoucherRows != 1) {
        throw StateError(
          'Voucher $id was not reversed because its posted state changed before commit.',
        );
      }
      await _reverseCompatibilityAccountMovements(
        voucherType: type,
        voucherId: id,
        reason: reason,
        deviceId: deviceId,
        occurredAt: when,
      );
      return true;
    });
    AccountingService.notifyCommittedMutation();
    return result;
  }

  Future<void> _insertCompatibilityRefundMovement({
    required String id,
    required String accountType,
    required String accountId,
    required String accountName,
    required String referenceId,
    required String referenceNo,
    required double debit,
    required double credit,
    required String currency,
    required String note,
    required String deviceId,
    required String branchId,
    required String storeId,
    required DateTime occurredAt,
  }) async {
    if (id.trim().isEmpty || accountId.trim().isEmpty) return;
    final existing = await _db.customSelect(
      "SELECT id FROM account_transactions WHERE id = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(id.trim())],
    ).getSingleOrNull();
    if (existing != null) return;
    final nextSort = await _db
        .customSelect(
          'SELECT COALESCE(MAX(sort_index), 0) + 1 AS next_sort FROM account_transactions',
        )
        .getSingle();
    final sortIndex = (nextSort.data['next_sort'] as num?)?.toInt() ?? 1;
    final iso = occurredAt.toUtc().toIso8601String();
    await _db.customInsert(
      '''
      INSERT OR IGNORE INTO account_transactions
        (id, entity_type, created_at, updated_at, deleted_at, device_id,
         sync_status, store_id, branch_id, version, sort_index, account_type,
         account_id, account_name, transaction_date, transaction_type,
         reference_id, reference_no, debit, credit, currency, payment_method,
         note, last_modified_by_device_id)
      VALUES (?, 'accountTransaction', ?, ?, '', ?, 'pending', ?, ?, 1, ?, ?, ?, ?, ?,
              'paymentReversal', ?, ?, ?, ?, ?, 'Cash', ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(id.trim()),
        Variable<String>(iso),
        Variable<String>(iso),
        Variable<String>(deviceId.trim()),
        Variable<String>(storeId.trim()),
        Variable<String>(branchId.trim()),
        Variable<int>(sortIndex),
        Variable<String>(accountType.trim()),
        Variable<String>(accountId.trim()),
        Variable<String>(accountName.trim()),
        Variable<String>(iso),
        Variable<String>(referenceId.trim()),
        Variable<String>(referenceNo.trim()),
        Variable<double>(_money(debit)),
        Variable<double>(_money(credit)),
        Variable<String>(_currency(currency)),
        Variable<String>(note.trim()),
        Variable<String>(deviceId.trim()),
      ],
    );
  }
}
