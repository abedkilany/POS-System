part of 'accounting_service_impl.dart';

/// Atomically posts a batch of legacy expenses through the Phase 5 cash path.
/// If any expense fails validation/accounting, the whole cash/accounting batch
/// is rolled back so callers can keep every Expense in its pre-post state.
Future<void> recordExpensesBulk(List<Expense> expenses) async {
  final candidates = expenses
      .where((expense) =>
          !expense.isDeleted && expense.isPosted && expense.amount > 0)
      .toList(growable: false);
  if (candidates.isEmpty || !isAvailable) return;
  await _db.transaction(() async {
    for (final expense in candidates) {
      await _upsertExpenseRowInExistingTransaction(expense);
      await _recordExpenseInExistingTransaction(expense);
      await _recordExpenseCompatibilityLedgerInExistingTransaction(expense);
    }
  });
  _notifyMutation();
}

Future<void> _upsertExpenseRowInExistingTransaction(Expense expense) async {
  final createdAt = expense.createdAt.toUtc().toIso8601String();
  final updatedAt = expense.updatedAt.toUtc().toIso8601String();
  final deletedAt = expense.deletedAt?.toUtc().toIso8601String() ?? '';
  final cancelledAt = expense.cancelledAt?.toUtc().toIso8601String() ?? '';
  final existingSort = await _db.customSelect(
    'SELECT sort_index FROM expenses WHERE id = ? LIMIT 1',
    variables: <Variable<Object>>[Variable<String>(expense.id)],
  ).getSingleOrNull();
  final nextSort = existingSort == null
      ? await _db
          .customSelect(
            'SELECT COALESCE(MAX(sort_index), 0) + 1 AS next_sort FROM expenses',
          )
          .getSingle()
      : null;
  final sortIndex = existingSort != null
      ? (existingSort.data['sort_index'] as num?)?.toInt() ?? 0
      : (nextSort?.data['next_sort'] as num?)?.toInt() ?? 1;
  await _db.customInsert(
    '''
      INSERT INTO expenses
        (id, entity_type, created_at, updated_at, deleted_at,
         device_id, sync_status, store_id, branch_id, version,
         last_modified_by_device_id, sort_index, title, category, amount,
         original_amount, original_currency, exchange_rate_at_entry,
         expense_date, notes, expense_status, cancel_reason,
         cancelled_by_device_id, cancelled_at)
      VALUES (?, 'expense', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        updated_at = excluded.updated_at,
        deleted_at = excluded.deleted_at,
        device_id = excluded.device_id,
        sync_status = excluded.sync_status,
        store_id = excluded.store_id,
        branch_id = excluded.branch_id,
        version = excluded.version,
        last_modified_by_device_id = excluded.last_modified_by_device_id,
        title = excluded.title,
        category = excluded.category,
        amount = excluded.amount,
        original_amount = excluded.original_amount,
        original_currency = excluded.original_currency,
        exchange_rate_at_entry = excluded.exchange_rate_at_entry,
        expense_date = excluded.expense_date,
        notes = excluded.notes,
        expense_status = excluded.expense_status,
        cancel_reason = excluded.cancel_reason,
        cancelled_by_device_id = excluded.cancelled_by_device_id,
        cancelled_at = excluded.cancelled_at
      ''',
    variables: <Variable<Object>>[
      Variable<String>(expense.id),
      Variable<String>(createdAt),
      Variable<String>(updatedAt),
      Variable<String>(deletedAt),
      Variable<String>(expense.deviceId),
      Variable<String>(expense.syncStatus),
      Variable<String>(expense.storeId),
      Variable<String>(expense.branchId),
      Variable<int>(expense.version),
      Variable<String>(expense.lastModifiedByDeviceId),
      Variable<int>(sortIndex),
      Variable<String>(expense.title),
      Variable<String>(expense.category),
      Variable<double>(expense.amount),
      Variable<double>(expense.originalAmount ?? expense.amount),
      Variable<String>(expense.originalCurrency.trim().isEmpty
          ? 'USD'
          : expense.originalCurrency.trim().toUpperCase()),
      Variable<double>(expense.exchangeRateAtEntry),
      Variable<String>(expense.date.toUtc().toIso8601String()),
      Variable<String>(expense.notes),
      Variable<String>(expense.status),
      Variable<String>(expense.cancelReason),
      Variable<String>(expense.cancelledByDeviceId),
      Variable<String>(cancelledAt),
    ],
  );
}

Future<void> _recordExpenseCompatibilityLedgerInExistingTransaction(
  Expense expense, {
  double? cashPaidAmount,
  String movementVersionSuffix = '',
}) async {
  final accountId = expense.id.trim();
  if (accountId.isEmpty || expense.amount <= 0) return;
  final accountName =
      expense.title.trim().isEmpty ? 'Expense' : expense.title.trim();
  final currency = expense.originalCurrency.trim().isEmpty
      ? 'USD'
      : expense.originalCurrency.trim().toUpperCase();
  final when = expense.date.toUtc().toIso8601String();
  final updated = expense.updatedAt.toUtc().toIso8601String();

  Future<void> insertMovement(String id, String type, double debit,
      double credit, String method, String note) async {
    final existing = await _db.customSelect(
      "SELECT id FROM account_transactions WHERE id = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(id)],
    ).getSingleOrNull();
    if (existing != null) return;
    final nextSort = await _db
        .customSelect(
          'SELECT COALESCE(MAX(sort_index), 0) + 1 AS next_sort FROM account_transactions',
        )
        .getSingle();
    final sortIndex = (nextSort.data['next_sort'] as num?)?.toInt() ?? 1;
    await _db.customInsert(
      '''
        INSERT INTO account_transactions
          (id, entity_type, created_at, updated_at, deleted_at,
           device_id, sync_status, store_id, branch_id, version, sort_index,
           account_type, account_id, account_name, transaction_date,
           transaction_type, reference_id, reference_no, debit, credit,
           currency, payment_method, note, last_modified_by_device_id)
        VALUES (?, 'accountTransaction', ?, ?, '', ?, 'pending', ?, ?, 1, ?,
                'supplier', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
      variables: <Variable<Object>>[
        Variable<String>(id),
        Variable<String>(updated),
        Variable<String>(updated),
        Variable<String>(expense.deviceId),
        Variable<String>(expense.storeId),
        Variable<String>(expense.branchId),
        Variable<int>(sortIndex),
        Variable<String>(accountId),
        Variable<String>(accountName),
        Variable<String>(when),
        Variable<String>(type),
        Variable<String>(expense.id),
        Variable<String>(accountName),
        Variable<double>(debit),
        Variable<double>(credit),
        Variable<String>(currency),
        Variable<String>(method),
        Variable<String>(note),
        Variable<String>(expense.lastModifiedByDeviceId),
      ],
    );
  }

  final suffix = movementVersionSuffix.trim().isEmpty
      ? ''
      : '-${movementVersionSuffix.trim()}';
  final total = _roundMoney(expense.amount);
  final paid = _normalizedExpenseCashAmount(
    total: total,
    requested: cashPaidAmount,
    requireCash: true,
  );
  final payable = _roundMoney(total - paid);
  await insertMovement('${expense.id}-expense-debit$suffix', 'expense', total,
      0, '', 'Expense ${expense.title}');
  if (paid > 0) {
    await insertMovement('${expense.id}-expense-credit$suffix', 'paymentPaid',
        0, paid, 'Cash', 'Expense settlement ${expense.title}');
  }
  if (payable > 0) {
    await insertMovement('${expense.id}-expense-credit-payable$suffix',
        'expense', 0, payable, 'Credit', 'Expense payable ${expense.title}');
  }
}

Future<void> _recordCreditExpenseCompatibilityLedgerInExistingTransaction(
  Expense expense, {
  String movementVersionSuffix = '',
}) async {
  final accountId = expense.id.trim();
  if (accountId.isEmpty || expense.amount <= 0) return;
  final accountName =
      expense.title.trim().isEmpty ? 'Expense' : expense.title.trim();
  final currency = expense.originalCurrency.trim().isEmpty
      ? 'USD'
      : expense.originalCurrency.trim().toUpperCase();
  final when = expense.date.toUtc().toIso8601String();
  final updated = expense.updatedAt.toUtc().toIso8601String();
  final suffix = movementVersionSuffix.trim().isEmpty
      ? ''
      : '-${movementVersionSuffix.trim()}';
  final id = '${expense.id}-expense-debit$suffix';
  final existing = await _db.customSelect(
    "SELECT id FROM account_transactions WHERE id = ? AND deleted_at = '' LIMIT 1",
    variables: <Variable<Object>>[Variable<String>(id)],
  ).getSingleOrNull();
  if (existing != null) return;
  final nextSort = await _db
      .customSelect(
        'SELECT COALESCE(MAX(sort_index), 0) + 1 AS next_sort FROM account_transactions',
      )
      .getSingle();
  final sortIndex = (nextSort.data['next_sort'] as num?)?.toInt() ?? 1;
  await _db.customInsert(
    '''
      INSERT INTO account_transactions
        (id, entity_type, created_at, updated_at, deleted_at,
         device_id, sync_status, store_id, branch_id, version, sort_index,
         account_type, account_id, account_name, transaction_date,
         transaction_type, reference_id, reference_no, debit, credit,
         currency, payment_method, note, last_modified_by_device_id)
      VALUES (?, 'accountTransaction', ?, ?, '', ?, 'pending', ?, ?, 1, ?,
              'supplier', ?, ?, ?, 'expense', ?, ?, ?, 0, ?, 'Credit', ?, ?)
      ''',
    variables: <Variable<Object>>[
      Variable<String>(id),
      Variable<String>(updated),
      Variable<String>(updated),
      Variable<String>(expense.deviceId),
      Variable<String>(expense.storeId),
      Variable<String>(expense.branchId),
      Variable<int>(sortIndex),
      Variable<String>(accountId),
      Variable<String>(accountName),
      Variable<String>(when),
      Variable<String>(expense.id),
      Variable<String>(accountName),
      Variable<double>(expense.amount),
      Variable<String>(currency),
      Variable<String>('Expense on credit ${expense.title}'),
      Variable<String>(expense.lastModifiedByDeviceId),
    ],
  );
}

Future<void> _recordCreditExpenseInExistingTransaction(
  Expense expense, {
  String accountingReferenceId = '',
}) async {
  final expenseAccount = await _resolveExpenseAccountForDatabase(
    _db,
    expense,
  );
  final accountsPayable = await _resolveAccountRoleForDatabase(
    _db,
    'accounts_payable',
  );
  final amount = _roundMoney(expense.amount);
  final referenceId = accountingReferenceId.trim().isEmpty
      ? expense.id
      : accountingReferenceId.trim();
  final entryId = await createPostedEntry(
    JournalEntryDraft(
      entryDate: expense.date,
      referenceType: 'expense',
      referenceId: referenceId,
      referenceNo: expense.title,
      description: 'مصروف آجل: ${expense.title}',
      source: 'system',
      createdBy: expense.lastModifiedByDeviceId,
      storeId: expense.storeId,
      branchId: expense.branchId,
      lines: <JournalLineDraft>[
        JournalLineDraft(
          accountId: expenseAccount,
          debit: amount,
          credit: 0,
          memo: expense.category,
        ),
        JournalLineDraft(
          accountId: accountsPayable,
          debit: 0,
          credit: amount,
          memo: 'مصروف مستحق الدفع',
        ),
      ],
    ),
    database: _db,
    withinExistingTransaction: true,
  );
  if (entryId.isEmpty) {
    throw StateError('تعذر إنشاء القيد المحاسبي للمصروف الآجل.');
  }
}

Future<void> _recordExpenseInExistingTransaction(
  Expense expense, {
  double? cashPaidAmount,
  String accountingReferenceId = '',
}) async {
  final cashExpenseLocation = await _openCashDrawerLocationForDevice(
      deviceId: expense.deviceId, branchId: expense.branchId);
  if (cashExpenseLocation == null) {
    throw StateError(
        'لا توجد وردية نقدية مفتوحة لدرج هذا الجهاز. افتح وردية قبل تسجيل مصروف نقدي.');
  }
  final sessionRow = await _db.customSelect(
    "SELECT id FROM cash_drawer_sessions WHERE cash_location_id = ? AND status = 'open' ORDER BY opened_at DESC LIMIT 1",
    variables: <Variable<Object>>[Variable<String>(cashExpenseLocation.id)],
  ).getSingleOrNull();
  final sessionId = sessionRow?.data['id']?.toString().trim() ?? '';
  if (sessionId.isEmpty) {
    throw StateError(
        'لا توجد وردية نقدية مفتوحة لدرج هذا الجهاز. افتح وردية قبل تسجيل مصروف نقدي.');
  }

  final expenseAccount = await _resolveExpenseAccountForDatabase(
    _db,
    expense,
  );
  final amount = _roundMoney(expense.amount);
  final paidAmount = _normalizedExpenseCashAmount(
    total: amount,
    requested: cashPaidAmount,
    requireCash: true,
  );
  final payableAmount = _roundMoney(amount - paidAmount);
  final referenceId = accountingReferenceId.trim().isEmpty
      ? expense.id.trim()
      : accountingReferenceId.trim();
  final idempotencyKey = 'expense:$referenceId';
  final operationId = 'cashop_expense_$referenceId';
  final nowDate = DateTime.now().toUtc();
  final now = nowDate.toIso8601String();
  final ledger = CashLedgerService(_db);

  final existing = await _db.customSelect(
    "SELECT id FROM cash_operations WHERE idempotency_key = ? AND deleted_at = '' LIMIT 1",
    variables: <Variable<Object>>[Variable<String>(idempotencyKey)],
  ).getSingleOrNull();
  if (existing != null) return;

  if (paidAmount > 0) {
    await ensureCashOutflowAllowed(
      cashLocationId: cashExpenseLocation.id,
      amount: paidAmount,
      database: _db,
    );
  }

  final entryId = await createPostedEntry(
    JournalEntryDraft(
      entryDate: expense.date,
      referenceType: 'expense',
      referenceId: referenceId,
      referenceNo: expense.title,
      description: 'مصروف: ${expense.title}',
      source: 'system',
      createdBy: expense.lastModifiedByDeviceId,
      storeId: expense.storeId,
      branchId: expense.branchId,
      lines: <JournalLineDraft>[
        JournalLineDraft(
          accountId: expenseAccount,
          debit: amount,
          credit: 0,
          memo: expense.category,
        ),
        JournalLineDraft(
          accountId: cashExpenseLocation.accountId,
          debit: 0,
          credit: paidAmount,
          memo: 'دفعة مصروف نقدية',
        ),
        if (payableAmount > 0)
          JournalLineDraft(
            accountId: await _resolveAccountRoleForDatabase(
              _db,
              'accounts_payable',
            ),
            debit: 0,
            credit: payableAmount,
            memo: 'الجزء المتبقي من المصروف مستحق الدفع',
          ),
      ].where((line) => line.debit > 0 || line.credit > 0).toList(),
    ),
    database: _db,
    withinExistingTransaction: true,
  );
  if (entryId.isEmpty) {
    throw StateError('تعذر إنشاء القيد المحاسبي للمصروف النقدي.');
  }

  await _db.customInsert(
    '''
      INSERT INTO cash_operations
        (id, operation_no, operation_type, operation_date, cash_location_id,
         cash_drawer_session_id, amount, currency, journal_entry_id, notes,
         created_by, created_by_user_id, device_id, store_id, branch_id,
         idempotency_key, created_at, updated_at, last_modified_by_device_id)
      VALUES (?, ?, 'expense', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
    variables: <Variable<Object>>[
      Variable<String>(operationId),
      Variable<String>(
          expense.title.trim().isEmpty ? expense.id : expense.title),
      Variable<String>(now),
      Variable<String>(cashExpenseLocation.id),
      Variable<String>(sessionId),
      Variable<double>(paidAmount),
      const Variable<String>('USD'),
      Variable<String>(entryId),
      Variable<String>(expense.notes),
      Variable<String>(expense.lastModifiedByDeviceId),
      Variable<String>(expense.lastModifiedByDeviceId),
      Variable<String>(expense.deviceId),
      Variable<String>(expense.storeId),
      Variable<String>(expense.branchId),
      Variable<String>(idempotencyKey),
      Variable<String>(now),
      Variable<String>(now),
      Variable<String>(expense.lastModifiedByDeviceId),
    ],
  );

  await ledger.appendInExistingTransaction(CashLedgerTransaction(
    id: 'cashledger_expense_$referenceId',
    type: 'expense',
    direction: 'out',
    amount: paidAmount,
    currency: 'USD',
    cashLocationId: cashExpenseLocation.id,
    cashDrawerSessionId: sessionId,
    referenceType: 'expense',
    referenceId: referenceId,
    referenceNumber: expense.title,
    paymentMethod: 'Cash',
    createdBy: expense.lastModifiedByDeviceId,
    createdByUserId: expense.lastModifiedByDeviceId,
    deviceId: expense.deviceId,
    branchId: expense.branchId,
    storeId: expense.storeId,
    notes: expense.notes,
    idempotencyKey: '$idempotencyKey:ledger',
    // Cash leaves the drawer when the expense is posted/paid, not on the
    // document's historical expense date. This keeps current-shift history
    // and reports aligned with the actual cash event.
    occurredAt: nowDate,
    createdAt: nowDate,
    updatedAt: nowDate,
    lastModifiedByDeviceId: expense.lastModifiedByDeviceId,
  ));

  await applyCashLocationDelta(
    cashLocationId: cashExpenseLocation.id,
    delta: -paidAmount,
    updatedAt: now,
    database: _db,
  );

  // expected_cash is a persisted shift cache used by the open-shift UI.
  // Rebuild it from the authoritative Cash Ledger after appending the
  // expense movement so the shift reflects the payment immediately.
  final expectedCash =
      _roundMoney(await calculateCashDrawerExpectedCash(sessionId));
  await _db.customUpdate(
    '''
      UPDATE cash_drawer_sessions
      SET expected_cash = ?, updated_at = ?, revision = revision + 1
      WHERE id = ? AND status = 'open'
      ''',
    variables: <Variable<Object>>[
      Variable<double>(expectedCash),
      Variable<String>(now),
      Variable<String>(sessionId),
    ],
  );
}
