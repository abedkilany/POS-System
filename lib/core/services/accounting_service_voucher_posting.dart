part of 'accounting_service_impl.dart';

/// Posts the accounting journal for a Phase 2 receipt/payment voucher.
///
/// This deliberately does NOT move cash_locations.current_balance. The Phase 2
/// PaymentVoucherService owns Cash Ledger + cash balance mutation so a voucher
/// has one and only one cash effect. Idempotency is keyed by
/// (reference_type, reference_id) and reinforced by a SQLite unique index.
Future<String> postVoucherPayment({
  required VentioDriftDatabase database,
  required String voucherType,
  required String voucherId,
  required String voucherNo,
  required DateTime date,
  required double amount,
  double discount = 0,
  required String paymentMethod,
  required String partyId,
  required String partyName,
  String cashLocationId = '',
  String createdBy = '',
  String storeId = '',
  String branchId = '',
  String accountingReferenceId = '',
  bool withinExistingTransaction = false,
}) async {
  final normalizedType = voucherType.trim().toLowerCase();
  final isReceipt = normalizedType == 'receipt';
  final isPayment = normalizedType == 'payment';
  if (!isReceipt && !isPayment) {
    throw ArgumentError('نوع السند المحاسبي غير صالح: $voucherType');
  }
  final cleanVoucherId = voucherId.trim();
  if (cleanVoucherId.isEmpty) {
    throw ArgumentError('معرف السند مطلوب للترحيل المحاسبي.');
  }
  final cleanAccountingReferenceId = accountingReferenceId.trim().isEmpty
      ? cleanVoucherId
      : accountingReferenceId.trim();
  final cleanAmount = _cleanAmount(amount);
  final cleanDiscount = _cleanAmount(discount);
  if (cleanDiscount < 0) {
    throw ArgumentError('قيمة الخصم لا يمكن أن تكون سالبة.');
  }
  final settlementAmount = _roundMoney(cleanAmount + cleanDiscount);
  if (cleanAmount < 0 || settlementAmount <= 0) {
    throw ArgumentError('يجب أن يكون المقبوض أو الخصم أكبر من صفر.');
  }

  final referenceType = isReceipt ? 'receipt_voucher' : 'payment_voucher';
  final existing = await database.customSelect(
    """
      SELECT id
      FROM journal_entries
      WHERE reference_type = ? AND reference_id = ?
        AND deleted_at = '' AND status = 'posted'
      LIMIT 1
      """,
    variables: <Variable<Object>>[
      Variable<String>(referenceType),
      Variable<String>(cleanAccountingReferenceId),
    ],
  ).getSingleOrNull();
  if (existing != null) {
    return existing.data['id']?.toString() ?? '';
  }

  final method = paymentMethod.trim().toLowerCase();
  final isCash = method.isEmpty || method == 'cash';
  String paymentAccount;
  if (isCash) {
    final cleanLocationId = cashLocationId.trim();
    if (cleanLocationId.isEmpty) {
      throw StateError('الصندوق مطلوب لترحيل سند نقدي.');
    }
    final location = await database.customSelect(
      """
        SELECT account_id
        FROM cash_locations
        WHERE id = ? AND deleted_at = '' AND is_active = 1
        LIMIT 1
        """,
      variables: <Variable<Object>>[Variable<String>(cleanLocationId)],
    ).getSingleOrNull();
    paymentAccount = location?.data['account_id']?.toString().trim() ?? '';
    if (paymentAccount.isEmpty) {
      throw StateError('الصندوق المحدد غير مرتبط بحساب محاسبي صالح.');
    }
  } else {
    final normalizedPaymentType = switch (method) {
      'card' ||
      'visa' ||
      'mastercard' ||
      'bank' ||
      'bank transfer' ||
      'transfer' =>
        'bank',
      'wish' || 'wallet' || 'online' => 'wallet',
      'check' || 'cheque' => 'cheque',
      _ => 'other',
    };
    final paymentRow = await database.customSelect(
      """
        SELECT account_id
        FROM payment_accounts
        WHERE deleted_at = '' AND is_active = 1 AND type = ?
        ORDER BY is_default DESC, name
        LIMIT 1
        """,
      variables: <Variable<Object>>[
        Variable<String>(normalizedPaymentType),
      ],
    ).getSingleOrNull();
    paymentAccount = paymentRow?.data['account_id']?.toString().trim() ?? '';
    if (paymentAccount.isEmpty) {
      paymentAccount = await _resolveAccountRoleForDatabase(
        database,
        'bank',
      );
    }
  }

  final controlAccount = await _resolveAccountRoleForDatabase(
    database,
    isReceipt ? 'accounts_receivable' : 'accounts_payable',
  );
  final discountAccount = cleanDiscount > 0
      ? await _resolveAccountRoleForDatabase(
          database,
          isReceipt
              ? 'customer_settlement_discount'
              : 'supplier_settlement_discount',
        )
      : '';
  return createPostedEntry(
    JournalEntryDraft(
      entryDate: date,
      referenceType: referenceType,
      referenceId: cleanAccountingReferenceId,
      referenceNo: voucherNo.trim(),
      description: isReceipt
          ? 'سند قبض عميل ${voucherNo.trim()}'
          : 'سند دفع مورد ${voucherNo.trim()}',
      source: 'system',
      createdBy: createdBy.trim(),
      storeId: storeId.trim(),
      branchId: branchId.trim(),
      lines: isReceipt
          ? <JournalLineDraft>[
              if (cleanAmount > 0)
                JournalLineDraft(
                  accountId: paymentAccount,
                  debit: cleanAmount,
                  credit: 0,
                  memo: 'سند قبض عميل',
                  partyType: 'customer',
                  partyId: partyId.trim(),
                  partyName: partyName.trim(),
                ),
              if (cleanDiscount > 0)
                JournalLineDraft(
                  accountId: discountAccount,
                  debit: cleanDiscount,
                  credit: 0,
                  memo: 'خصم تسوية ممنوح للعميل',
                  partyType: 'customer',
                  partyId: partyId.trim(),
                  partyName: partyName.trim(),
                ),
              JournalLineDraft(
                accountId: controlAccount,
                debit: 0,
                credit: settlementAmount,
                memo: 'تخفيض ذمة العميل المدينة',
                partyType: 'customer',
                partyId: partyId.trim(),
                partyName: partyName.trim(),
              ),
            ]
          : <JournalLineDraft>[
              JournalLineDraft(
                accountId: controlAccount,
                debit: settlementAmount,
                credit: 0,
                memo: 'تخفيض ذمة المورد الدائنة',
                partyType: 'supplier',
                partyId: partyId.trim(),
                partyName: partyName.trim(),
              ),
              if (cleanAmount > 0)
                JournalLineDraft(
                  accountId: paymentAccount,
                  debit: 0,
                  credit: cleanAmount,
                  memo: 'سند دفع مورد',
                  partyType: 'supplier',
                  partyId: partyId.trim(),
                  partyName: partyName.trim(),
                ),
              if (cleanDiscount > 0)
                JournalLineDraft(
                  accountId: discountAccount,
                  debit: 0,
                  credit: cleanDiscount,
                  memo: 'خصم تسوية مكتسب من المورد',
                  partyType: 'supplier',
                  partyId: partyId.trim(),
                  partyName: partyName.trim(),
                ),
            ],
    ),
    database: database,
    withinExistingTransaction: withinExistingTransaction,
  );
}

/// Persists the accounting side of a compatibility account payment.
///
/// Phase 7 transaction-integrity rule: the journal entry and any cash
/// location balance mutation are one SQLite unit. Callers that also persist
/// the [AccountTransaction] row can pass [withinExistingTransaction] so all
/// three artifacts commit or roll back together.
Future<void> recordAccountPayment(
  AccountTransaction transaction, {
  VentioDriftDatabase? database,
  bool withinExistingTransaction = false,
  bool notifyChange = true,
}) async {
  if (transaction.isDeleted) return;
  if (database == null && !isAvailable) return;
  final db = database ?? _db;

  Future<bool> persistPayment() async {
    final accountsReceivable =
        await _resolveAccountRoleForDatabase(db, 'accounts_receivable');
    final accountsPayable =
        await _resolveAccountRoleForDatabase(db, 'accounts_payable');
    final isCustomerPayment = transaction.isCustomer && transaction.credit > 0;
    final isSupplierPayment = transaction.isSupplier && transaction.debit > 0;
    if (!isCustomerPayment && !isSupplierPayment) return false;
    final amount = _cleanAmount(
        isCustomerPayment ? transaction.credit : transaction.debit);
    if (amount <= 0) return false;
    final isCashAccountPayment =
        _isCashPaymentMethod(transaction.paymentMethod);
    final cashPaymentLocation = isCashAccountPayment
        ? await _openCashDrawerLocationForDevice(
            deviceId: transaction.deviceId,
            branchId: transaction.branchId,
            database: db,
          )
        : null;
    if (isCashAccountPayment && cashPaymentLocation == null) {
      throw StateError(
          'لا توجد وردية نقدية مفتوحة لدرج هذا الجهاز. افتح وردية قبل تسجيل حركة نقدية.');
    }
    final paymentAccount = cashPaymentLocation?.accountId ??
        await _paymentAccountIdForDatabase(db, transaction.paymentMethod);
    final controlAccount =
        isCustomerPayment ? accountsReceivable : accountsPayable;
    final entryId = await createPostedEntry(
      JournalEntryDraft(
        entryDate: transaction.date,
        referenceType:
            isCustomerPayment ? 'customer_payment' : 'supplier_payment',
        referenceId: transaction.id,
        referenceNo: transaction.referenceNo,
        description: isCustomerPayment
            ? 'دفعة عميل ${transaction.referenceNo}'
            : 'دفعة مورد ${transaction.referenceNo}',
        createdBy: transaction.lastModifiedByDeviceId,
        storeId: transaction.storeId,
        branchId: transaction.branchId,
        lines: isCustomerPayment
            ? <JournalLineDraft>[
                JournalLineDraft(
                  accountId: paymentAccount,
                  debit: amount,
                  credit: 0,
                  memo: 'دفعة عميل مستلمة',
                  partyType: 'customer',
                  partyId: transaction.accountId,
                  partyName: transaction.accountName,
                ),
                JournalLineDraft(
                  accountId: controlAccount,
                  debit: 0,
                  credit: amount,
                  memo: 'تخفيض ذمة العميل المدينة',
                  partyType: 'customer',
                  partyId: transaction.accountId,
                  partyName: transaction.accountName,
                ),
              ]
            : <JournalLineDraft>[
                JournalLineDraft(
                  accountId: controlAccount,
                  debit: amount,
                  credit: 0,
                  memo: 'تخفيض ذمة المورد الدائنة',
                  partyType: 'supplier',
                  partyId: transaction.accountId,
                  partyName: transaction.accountName,
                ),
                JournalLineDraft(
                  accountId: paymentAccount,
                  debit: 0,
                  credit: amount,
                  memo: 'دفعة مورد مدفوعة',
                  partyType: 'supplier',
                  partyId: transaction.accountId,
                  partyName: transaction.accountName,
                ),
              ],
      ),
      database: db,
      withinExistingTransaction: true,
    );
    if (entryId.isNotEmpty && cashPaymentLocation != null) {
      await _moveCashLocationBalance(
        cashPaymentLocation.id,
        isCustomerPayment ? amount : -amount,
        transaction.date,
        database: db,
      );
    }
    return entryId.isNotEmpty;
  }

  final posted = withinExistingTransaction
      ? await persistPayment()
      : await db.transaction(persistPayment);
  if (posted && notifyChange) _notifyMutation();
}

Future<String> createPostedEntry(
  JournalEntryDraft draft, {
  VentioDriftDatabase? database,
  bool withinExistingTransaction = false,
}) async {
  if (database == null && !isAvailable) return '';
  final db = database ?? _db;
  _validateBalancedDraft(draft);
  await _assertDateNotInClosedPeriod(
    draft.entryDate,
    draft.branchId,
    database: db,
  );
  final now = DateTime.now().toUtc().toIso8601String();
  final entryId = _newId('je');

  Future<bool> persistEntry() async {
    // Phase 7: idempotency is checked inside the owning write transaction.
    // This closes the read-before-transaction race that could otherwise let
    // two retries both decide that the reference was not posted yet.
    if (await _hasActiveEntryForReference(
        db, draft.referenceType, draft.referenceId)) {
      return false;
    }
    final entryNo = await _nextEntryNo(db, draft.entryDate);
    await db.customInsert(
      '''
        INSERT INTO journal_entries
          (id, entry_no, entry_date, reference_type, reference_id, reference_no,
           description, status, source, created_by, posted_at, created_at,
           updated_at, store_id, branch_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'posted', ?, ?, ?, ?, ?, ?, ?)
        ''',
      variables: <Variable<Object>>[
        Variable<String>(entryId),
        Variable<String>(entryNo),
        Variable<String>(draft.entryDate.toUtc().toIso8601String()),
        Variable<String>(draft.referenceType),
        Variable<String>(draft.referenceId),
        Variable<String>(draft.referenceNo),
        Variable<String>(draft.description),
        Variable<String>(draft.source),
        Variable<String>(draft.createdBy),
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(draft.storeId),
        Variable<String>(draft.branchId),
      ],
    );

    for (var index = 0; index < draft.lines.length; index++) {
      final line = draft.lines[index];
      final account = await _accountSnapshot(db, line.accountId);
      if (!account.isPostable) {
        throw StateError(
            'لا يمكن الترحيل على الحساب التجميعي ${account.code} - ${account.name}.');
      }
      await db.customInsert(
        '''
          INSERT INTO journal_lines
            (id, entry_id, line_no, account_id, account_code, account_name,
             debit, credit, memo, party_type, party_id, party_name, cost_center_id, created_at,
             updated_at, store_id, branch_id)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
        variables: <Variable<Object>>[
          Variable<String>(_newId('jl')),
          Variable<String>(entryId),
          Variable<int>(index + 1),
          Variable<String>(line.accountId),
          Variable<String>(account.code),
          Variable<String>(account.name),
          Variable<double>(_cleanAmount(line.debit)),
          Variable<double>(_cleanAmount(line.credit)),
          Variable<String>(line.memo),
          Variable<String>(line.partyType),
          Variable<String>(line.partyId),
          Variable<String>(line.partyName),
          Variable<String>(line.costCenterId),
          Variable<String>(now),
          Variable<String>(now),
          Variable<String>(draft.storeId),
          Variable<String>(draft.branchId),
        ],
      );
    }
    final persisted = await db.customSelect(
      '''
        SELECT je.status,
               COUNT(jl.id) AS line_count,
               COALESCE(SUM(jl.debit), 0) AS total_debit,
               COALESCE(SUM(jl.credit), 0) AS total_credit
        FROM journal_entries je
        LEFT JOIN journal_lines jl ON jl.entry_id = je.id
        WHERE je.id = ? AND je.deleted_at = ''
        GROUP BY je.id, je.status
        ''',
      variables: <Variable<Object>>[Variable<String>(entryId)],
    ).getSingleOrNull();
    final lineCount = (persisted?.data['line_count'] as num?)?.toInt() ?? 0;
    final debit = _num(persisted?.data['total_debit']);
    final credit = _num(persisted?.data['total_credit']);
    if (persisted == null ||
        persisted.data['status']?.toString() != 'posted' ||
        lineCount != draft.lines.length ||
        (debit - credit).abs() > 0.005) {
      throw StateError(
        'Journal entry failed its Phase 7 persistence post-condition.',
      );
    }
    await _writeAuditLogInTransaction(
      db,
      action: 'post_entry',
      entityType: 'journal_entry',
      entityId: entryId,
      referenceType: draft.referenceType,
      referenceId: draft.referenceId,
      details: 'تم ترحيل قيد يومية متوازن $entryNo',
      createdBy: draft.createdBy,
      storeId: draft.storeId,
      branchId: draft.branchId,
      createdAt: now,
    );
    return true;
  }

  final inserted = withinExistingTransaction
      ? await persistEntry()
      : await db.transaction(persistEntry);
  return inserted ? entryId : '';
}
