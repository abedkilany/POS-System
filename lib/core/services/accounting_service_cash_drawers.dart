part of 'accounting_service_impl.dart';

/// Records the balance that existed at the moment the business started.
/// This is deliberately separate from a transfer or a purchase so the
/// opening amount is visible and cannot be mistaken for operating activity.
Future<void> recordOpeningCashLocationBalance({
  required String cashLocationId,
  required double amount,
  String storeId = '',
  String branchId = '',
  String createdBy = '',
  String notes = '',
}) async {
  if (!isAvailable) return;
  final cleanAmount = _roundMoney(amount);
  if (cleanAmount <= 0) {
    throw ArgumentError('Opening balance must be greater than zero.');
  }
  final location = await _cashLocationSnapshot(cashLocationId);
  final referenceId = 'opening-balance-${location.id}';
  final existing = await _db.customSelect(
    '''
      SELECT id FROM journal_entries
      WHERE reference_type = 'opening_balance' AND reference_id = ?
        AND deleted_at = ''
      LIMIT 1
      ''',
    variables: <Variable<Object>>[Variable<String>(referenceId)],
  ).getSingleOrNull();
  if (existing != null) {
    throw StateError('An opening balance already exists for this location.');
  }
  final equityAccount = await resolveAccountRole('owner_capital');
  final when = DateTime.now();
  await _db.transaction(() async {
    final entryId = await createPostedEntry(
      JournalEntryDraft(
        entryDate: when,
        referenceType: 'opening_balance',
        referenceId: referenceId,
        referenceNo: 'OPEN-${location.id}',
        description: notes.trim().isEmpty
            ? 'Opening balance - ${location.name}'
            : notes.trim(),
        source: 'system',
        createdBy: createdBy,
        storeId: storeId,
        branchId: branchId,
        lines: <JournalLineDraft>[
          JournalLineDraft(
            accountId: location.accountId,
            debit: cleanAmount,
            credit: 0,
            memo: 'Opening balance - ${location.name}',
          ),
          JournalLineDraft(
            accountId: equityAccount,
            debit: 0,
            credit: cleanAmount,
            memo: 'Opening balance source',
          ),
        ],
      ),
      database: _db,
      withinExistingTransaction: true,
    );
    if (entryId.isEmpty) {
      throw StateError('Opening balance journal entry was not created.');
    }
    await _moveCashLocationBalance(location.id, cleanAmount, when);
  });
  _notifyMutation();
}

Future<void> openCashDrawer({
  required BusinessSessionContext authorization,
  required String drawerNo,
  required double openingBalance,
  String cashLocationId = '',
  String fundingLocationId = '',
  String openedBy = '',
  String openedByUserId = '',
  String storeId = '',
  String branchId = '',
  String deviceId = '',
}) async {
  authorization.requirePermission(AppPermission.cashBoxManage);
  if (!isAvailable) return;
  final nowDate = DateTime.now().toUtc();
  final now = nowDate.toIso8601String();
  final resolvedLocationId = cashLocationId.trim().isEmpty
      ? await _defaultCashLocationId(
          type: 'cash_drawer', branchId: branchId, deviceId: deviceId)
      : cashLocationId.trim();
  if (resolvedLocationId.trim().isEmpty) {
    throw StateError('لا يوجد درج نقد معرف لفتح وردية.');
  }
  final cleanOpening = _roundMoney(openingBalance);
  if (cleanOpening < 0) {
    throw ArgumentError('الرصيد الافتتاحي لا يمكن أن يكون سالباً.');
  }
  final sessionId = _newId('drawer');
  await _db.transaction(() async {
    await _ensureCashDrawerDeviceBinding(
      cashLocationId: resolvedLocationId,
      deviceId: deviceId,
      branchId: branchId,
      updatedAt: now,
    );
    if (await hasOpenCashDrawer(
        branchId: branchId, cashLocationId: resolvedLocationId)) {
      throw StateError('يوجد وردية مفتوحة بالفعل لهذا الدرج.');
    }

    await _db.customInsert(
      '''
        INSERT INTO cash_drawer_sessions
          (id, drawer_no, cash_location_id, opened_at, status, opening_balance, expected_cash,
           notes, opened_by, opened_by_user_id, store_id, branch_id, updated_at, revision)
        VALUES (?, ?, ?, ?, 'open', ?, ?, '', ?, ?, ?, ?, ?, 1)
        ''',
      variables: <Variable<Object>>[
        Variable<String>(sessionId),
        Variable<String>(
            drawerNo.trim().isEmpty ? 'درج النقد' : drawerNo.trim()),
        Variable<String>(resolvedLocationId),
        Variable<String>(now),
        Variable<double>(cleanOpening),
        Variable<double>(cleanOpening),
        Variable<String>(openedBy),
        Variable<String>(openedByUserId),
        Variable<String>(storeId),
        Variable<String>(branchId),
        Variable<String>(now),
      ],
    );

    if (fundingLocationId.trim().isNotEmpty &&
        fundingLocationId.trim() != resolvedLocationId &&
        cleanOpening > 0) {
      await createCashTransfer(
        authorization: authorization,
        fromLocationId: fundingLocationId,
        toLocationId: resolvedLocationId,
        amount: cleanOpening,
        transferDate: nowDate.subtract(const Duration(microseconds: 1)),
        notes:
            'عهدة افتتاح وردية ${drawerNo.trim().isEmpty ? 'درج النقد' : drawerNo.trim()}',
        createdBy: openedBy,
        createdByUserId: openedByUserId,
        deviceId: deviceId,
        storeId: storeId,
        branchId: branchId,
        idempotencyKey: 'shift_open_funding:$sessionId',
        notifyChange: false,
      );
    } else {
      // The opening count is the authoritative physical starting cash for the
      // new shift. Align the location cache even when the opening count is 0
      // so a previous closed shift cannot leak a stale balance forward.
      await _setCashLocationBalance(resolvedLocationId, cleanOpening, now);
    }
  });

  _notifyMutation();
  await _writeAuditLog(
      action: 'open_cash_drawer',
      entityType: 'cash_drawer',
      entityId: sessionId,
      details: drawerNo,
      createdBy: openedBy,
      storeId: storeId,
      branchId: branchId);
}

Future<void> closeCashDrawer({
  required BusinessSessionContext authorization,
  required String sessionId,
  required double countedCash,
  String closedBy = '',
  String closedByUserId = '',
  String notes = '',
  String depositToLocationId = '',
}) async {
  authorization.requirePermission(AppPermission.cashBoxManage);
  if (!isAvailable) return;
  final counted = _roundMoney(countedCash);
  if (counted < 0) {
    throw ArgumentError('النقد المعدود لا يمكن أن يكون سالباً.');
  }

  var didClose = false;
  var expected = 0.0;
  var difference = 0.0;
  var storeId = '';
  var branchId = '';
  var cashLocationId = '';
  var drawerNo = '';

  await _db.transaction(() async {
    final row = await _db.customSelect(
      """
        SELECT id, drawer_no, cash_location_id, opened_at, opening_balance,
               expected_cash, store_id, branch_id
        FROM cash_drawer_sessions
        WHERE id = ? AND status = 'open'
        LIMIT 1
        """,
      variables: <Variable<Object>>[Variable<String>(sessionId)],
    ).getSingleOrNull();
    if (row == null) {
      throw StateError('Cash drawer session is not open or no longer exists.');
    }

    final data = row.data;
    storeId = data['store_id']?.toString() ?? '';
    branchId = data['branch_id']?.toString() ?? '';
    cashLocationId = data['cash_location_id']?.toString() ?? '';
    drawerNo = data['drawer_no']?.toString() ?? '';
    expected = _roundMoney(await calculateCashDrawerExpectedCash(sessionId));
    difference = _roundMoney(counted - expected);
    final nowDate = DateTime.now().toUtc();
    final now = nowDate.toIso8601String();

    if (difference.abs() >= 0.01) {
      await _postCashReconciliationDifference(
        sessionId: sessionId,
        drawerNo: drawerNo,
        difference: difference,
        countedCash: counted,
        expectedCash: expected,
        closedBy: closedBy,
        storeId: storeId,
        branchId: branchId,
        cashLocationId: cashLocationId,
      );
    }

    if (depositToLocationId.trim().isNotEmpty &&
        cashLocationId.trim().isNotEmpty &&
        counted > 0 &&
        depositToLocationId.trim() != cashLocationId.trim()) {
      await createCashTransfer(
        authorization: authorization,
        fromLocationId: cashLocationId,
        toLocationId: depositToLocationId,
        amount: counted,
        transferDate: nowDate,
        fromSessionId: sessionId,
        transferKind: 'vault_transfer',
        notes: notes.trim().isEmpty
            ? 'تسليم نقدية عند إغلاق الوردية'
            : notes.trim(),
        createdBy: closedBy,
        createdByUserId: closedByUserId,
        storeId: storeId,
        branchId: branchId,
        idempotencyKey: 'shift_close_transfer:$sessionId',
        notifyChange: false,
        withinExistingTransaction: true,
      );
    }

    final updated = await _db.customUpdate(
      '''
        UPDATE cash_drawer_sessions
        SET status = 'closed', closed_at = ?, expected_cash = ?, counted_cash = ?, difference = ?,
            closed_by = ?, closed_by_user_id = ?, notes = ?, updated_at = ?, revision = revision + 1
        WHERE id = ? AND status = 'open'
        ''',
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<double>(expected),
        Variable<double>(counted),
        Variable<double>(difference),
        Variable<String>(closedBy),
        Variable<String>(closedByUserId),
        Variable<String>(notes),
        Variable<String>(now),
        Variable<String>(sessionId),
      ],
    );
    if (updated != 1) {
      throw StateError(
          'Cash drawer close failed because the session state changed.');
    }
    didClose = true;
  });

  if (!didClose) {
    throw StateError('Cash drawer close did not update the session.');
  }
  final type = difference < 0
      ? 'shortage'
      : difference > 0
          ? 'overage'
          : 'balanced';
  _notifyMutation();
  await _writeAuditLog(
    action: 'close_cash_drawer',
    entityType: 'cash_drawer',
    entityId: sessionId,
    details:
        'تسوية نقدية $type. المتوقع: $expected، المعدود: $counted، الفرق: $difference',
    createdBy: closedBy,
    storeId: storeId,
    branchId: branchId,
  );
}

Future<void> _postCashReconciliationDifference({
  required String sessionId,
  required String drawerNo,
  required double difference,
  required double countedCash,
  required double expectedCash,
  required String closedBy,
  required String storeId,
  required String branchId,
  String cashLocationId = '',
}) async {
  final cashAccountId = await _cashLocationAccountId(cashLocationId);
  final amount = _roundMoney(difference.abs());
  if (amount <= 0) return;

  final isOverage = difference > 0;
  final adjustmentAccountId = await _resolveAccountRoleForDatabase(
    _db,
    isOverage ? 'cash_over' : 'cash_short',
  );
  final occurredAt = DateTime.now().toUtc();
  await createPostedEntry(
      JournalEntryDraft(
        entryDate: occurredAt,
        referenceType: 'cash_reconciliation',
        referenceId: sessionId,
        referenceNo:
            drawerNo.trim().isEmpty ? 'إغلاق درج النقد' : drawerNo.trim(),
        description:
            'تسوية نقدية ${isOverage ? 'زيادة' : 'عجز'}: المتوقع $expectedCash، المعدود $countedCash',
        source: 'system',
        createdBy: closedBy,
        storeId: storeId,
        branchId: branchId,
        lines: isOverage
            ? <JournalLineDraft>[
                JournalLineDraft(
                    accountId: cashAccountId,
                    debit: amount,
                    credit: 0,
                    memo: 'زيادة درج النقد'),
                JournalLineDraft(
                    accountId: adjustmentAccountId,
                    debit: 0,
                    credit: amount,
                    memo: 'مقابل زيادة درج النقد'),
              ]
            : <JournalLineDraft>[
                JournalLineDraft(
                    accountId: adjustmentAccountId,
                    debit: amount,
                    credit: 0,
                    memo: 'عجز درج النقد'),
                JournalLineDraft(
                    accountId: cashAccountId,
                    debit: 0,
                    credit: amount,
                    memo: 'مقابل عجز درج النقد'),
              ],
      ),
      database: _db,
      withinExistingTransaction: true);
  final ledger = CashLedgerService(_db);
  await ledger.appendInExistingTransaction(CashLedgerTransaction(
    id: ledger.generateId(),
    type: isOverage ? 'overage' : 'shortage',
    direction: isOverage ? 'in' : 'out',
    amount: amount,
    currency: 'USD',
    cashLocationId: cashLocationId,
    cashDrawerSessionId: sessionId,
    referenceType: 'cash_reconciliation',
    referenceId: sessionId,
    referenceNumber: drawerNo,
    paymentMethod: 'Cash',
    createdBy: closedBy,
    branchId: branchId,
    storeId: storeId,
    notes: 'Expected $expectedCash • Counted $countedCash',
    idempotencyKey: 'cash_reconciliation:$sessionId',
    occurredAt: occurredAt,
    createdAt: occurredAt,
    updatedAt: occurredAt,
  ));
  await _moveCashLocationBalance(cashLocationId, difference, occurredAt);
}

Future<void> createAccountingPeriod({
  required String name,
  required DateTime startDate,
  required DateTime endDate,
  String createdBy = '',
  String storeId = '',
  String branchId = '',
}) async {
  if (!isAvailable) return;
  final now = DateTime.now().toUtc().toIso8601String();
  await _db.customInsert(
    '''
      INSERT INTO accounting_periods
        (id, name, start_date, end_date, status, created_at, updated_at, store_id, branch_id)
      VALUES (?, ?, ?, ?, 'open', ?, ?, ?, ?)
      ''',
    variables: <Variable<Object>>[
      Variable<String>(_newId('period')),
      Variable<String>(name.trim().isEmpty ? 'فترة محاسبية' : name.trim()),
      Variable<String>(startDate.toUtc().toIso8601String()),
      Variable<String>(endDate.toUtc().toIso8601String()),
      Variable<String>(now),
      Variable<String>(now),
      Variable<String>(storeId),
      Variable<String>(branchId),
    ],
  );
  _notifyMutation();
  await _writeAuditLog(
      action: 'create_period',
      entityType: 'accounting_period',
      details: name,
      createdBy: createdBy,
      storeId: storeId,
      branchId: branchId);
}

Future<void> closeAccountingPeriod(
    {required String periodId, String closedBy = ''}) async {
  if (!isAvailable) return;
  final row = await _db.customSelect(
    'SELECT start_date, end_date, status, store_id, branch_id FROM accounting_periods WHERE id = ? LIMIT 1',
    variables: <Variable<Object>>[Variable<String>(periodId)],
  ).getSingleOrNull();
  if (row == null || row.data['status']?.toString() == 'closed') return;
  final trialBalance = await trialBalanceReport();
  final totalDebit =
      trialBalance.fold<double>(0, (sum, row) => sum + row.debit);
  final totalCredit =
      trialBalance.fold<double>(0, (sum, row) => sum + row.credit);
  if ((totalDebit - totalCredit).abs() > 0.0001) {
    throw StateError('لا يمكن إغلاق الفترة لأن ميزان المراجعة غير متوازن.');
  }
  final now = DateTime.now().toUtc().toIso8601String();
  await _db.customUpdate(
    '''
      UPDATE accounting_periods
      SET status = 'closed', closed_at = ?, closed_by = ?, updated_at = ?
      WHERE id = ?
      ''',
    variables: <Variable<Object>>[
      Variable<String>(now),
      Variable<String>(closedBy),
      Variable<String>(now),
      Variable<String>(periodId),
    ],
  );
  _notifyMutation();
  await _writeAuditLog(
      action: 'close_period',
      entityType: 'accounting_period',
      entityId: periodId,
      details: 'تم إغلاق فترة محاسبية متوازنة',
      createdBy: closedBy,
      storeId: row.data['store_id']?.toString() ?? '',
      branchId: row.data['branch_id']?.toString() ?? '');
}
