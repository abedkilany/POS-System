part of 'accounting_service_impl.dart';

Future<void> createFixedAsset({
  required String code,
  required String name,
  required String category,
  required DateTime acquisitionDate,
  required double purchaseValue,
  int usefulLifeMonths = 0,
  String assetAccountId = '',
  String paymentAccountId = '',
  bool paidFromCashDrawer = false,
  String currency = 'USD',
  String notes = '',
  String createdBy = '',
  String createdByUserId = '',
  String deviceId = '',
  String storeId = '',
  String branchId = '',
}) async {
  if (!isAvailable) return;
  final amount = _cleanAmount(purchaseValue);
  if (amount <= 0) throw ArgumentError('قيمة شراء الأصل الثابت مطلوبة.');
  final accounts = await readDefaultAccountMap();
  final fixedAssetAccountId = assetAccountId.trim().isNotEmpty
      ? assetAccountId.trim()
      : _requiredAccount(accounts, 'default_fixed_assets_account_id');
  final legacyPaymentAccount = paidFromCashDrawer
      ? ''
      : (paymentAccountId.trim().isNotEmpty
          ? paymentAccountId.trim()
          : _requiredAccount(accounts, 'default_cash_account_id'));
  final fixedAssetAccount = await _accountSnapshot(_db, fixedAssetAccountId);
  if (fixedAssetAccount.type != 'asset' ||
      !fixedAssetAccount.isPostable ||
      !fixedAssetAccount.subtype.startsWith('fixed_') ||
      fixedAssetAccount.subtype == 'fixed_assets') {
    throw StateError(
      'يجب تسجيل الأصل الثابت في حساب تفصيلي مثل السيارات أو المعدات، وليس في حساب الأصول الثابتة الرئيسي.',
    );
  }
  if (!paidFromCashDrawer) {
    await _accountSnapshot(_db, legacyPaymentAccount);
  }

  final nowDate = DateTime.now().toUtc();
  final now = nowDate.toIso8601String();
  final assetId = _newId('asset');
  final normalizedCode = code.trim().isEmpty
      ? 'FA-${DateTime.now().toUtc().microsecondsSinceEpoch}'
      : code.trim().toUpperCase();
  final normalizedName = name.trim().isEmpty ? 'أصل ثابت' : name.trim();
  final normalizedCurrency =
      currency.trim().isEmpty ? 'USD' : currency.trim().toUpperCase();

  await _db.transaction(() async {
    _CashLocationSnapshot? cashDrawer;
    var cashDrawerSessionId = '';
    var creditAccountId = legacyPaymentAccount;

    if (paidFromCashDrawer) {
      cashDrawer = await _openCashDrawerLocationForDevice(
        deviceId: deviceId,
        branchId: branchId,
        database: _db,
      );
      if (cashDrawer == null || cashDrawer.accountId.trim().isEmpty) {
        throw StateError(
          'لا توجد وردية نقدية مفتوحة لدرج هذا الجهاز. افتح وردية قبل شراء أصل نقداً.',
        );
      }
      final sessionRow = await _db.customSelect(
        "SELECT id FROM cash_drawer_sessions WHERE cash_location_id = ? AND status = 'open' ORDER BY opened_at DESC LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(cashDrawer.id)],
      ).getSingleOrNull();
      cashDrawerSessionId = sessionRow?.data['id']?.toString().trim() ?? '';
      if (cashDrawerSessionId.isEmpty) {
        throw StateError(
          'لا توجد وردية نقدية مفتوحة لدرج هذا الجهاز. افتح وردية قبل شراء أصل نقداً.',
        );
      }
      await ensureCashOutflowAllowed(
        cashLocationId: cashDrawer.id,
        amount: amount,
        database: _db,
      );
      creditAccountId = cashDrawer.accountId.trim();
      await _accountSnapshot(_db, creditAccountId);
    }
    if (creditAccountId == fixedAssetAccountId) {
      throw StateError('حساب الدفع لا يمكن أن يكون نفس حساب الأصل الثابت.');
    }

    await _db.customInsert(
      '''
        INSERT INTO fixed_assets
          (id, code, name, category, acquisition_date, purchase_value, useful_life_months,
           asset_account_id, status, notes, created_at, updated_at, store_id, branch_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, ?)
        ''',
      variables: <Variable<Object>>[
        Variable<String>(assetId),
        Variable<String>(normalizedCode),
        Variable<String>(normalizedName),
        Variable<String>(category.trim()),
        Variable<String>(acquisitionDate.toUtc().toIso8601String()),
        Variable<double>(_roundMoney(amount)),
        Variable<int>(usefulLifeMonths < 0 ? 0 : usefulLifeMonths),
        Variable<String>(fixedAssetAccountId),
        Variable<String>(notes.trim()),
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(storeId),
        Variable<String>(branchId),
      ],
    );
    final entryId = await createPostedEntry(
      JournalEntryDraft(
        entryDate: acquisitionDate,
        referenceType: 'fixed_asset',
        referenceId: assetId,
        referenceNo: normalizedCode,
        description: 'اقتناء أصل ثابت: $normalizedName',
        source: 'system',
        createdBy: createdBy,
        storeId: storeId,
        branchId: branchId,
        lines: <JournalLineDraft>[
          JournalLineDraft(
            accountId: fixedAssetAccountId,
            debit: amount,
            credit: 0,
            memo: 'اقتناء أصل ثابت $normalizedCode',
          ),
          JournalLineDraft(
            accountId: creditAccountId,
            debit: 0,
            credit: amount,
            memo: paidFromCashDrawer
                ? 'دفعة نقدية لشراء أصل ثابت $normalizedCode'
                : 'دفعة أصل ثابت $normalizedCode',
          ),
        ],
      ),
      database: _db,
      withinExistingTransaction: true,
    );
    if (entryId.isEmpty) {
      throw StateError('Fixed asset journal entry was not persisted.');
    }

    if (paidFromCashDrawer && cashDrawer != null) {
      final idempotencyKey = 'fixed-asset-cash:$assetId';
      final operationId = 'cashop_fixed_asset_$assetId';
      final operationNo = 'FA-CW-${nowDate.microsecondsSinceEpoch}';
      final cashNotes = notes.trim().isEmpty
          ? 'شراء أصل ثابت: $normalizedCode - $normalizedName'
          : 'شراء أصل ثابت: $normalizedCode - $normalizedName • ${notes.trim()}';
      await _db.customInsert(
        '''
          INSERT INTO cash_operations
            (id, operation_no, operation_type, operation_date, cash_location_id,
             cash_drawer_session_id, amount, currency, journal_entry_id, notes,
             created_by, created_by_user_id, device_id, store_id, branch_id,
             idempotency_key, created_at, updated_at, last_modified_by_device_id)
          VALUES (?, ?, 'cash_withdrawal', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
        variables: <Variable<Object>>[
          Variable<String>(operationId),
          Variable<String>(operationNo),
          Variable<String>(acquisitionDate.toUtc().toIso8601String()),
          Variable<String>(cashDrawer.id),
          Variable<String>(cashDrawerSessionId),
          Variable<double>(_roundMoney(amount)),
          Variable<String>(normalizedCurrency),
          Variable<String>(entryId),
          Variable<String>(cashNotes),
          Variable<String>(createdBy.trim()),
          Variable<String>(createdByUserId.trim()),
          Variable<String>(deviceId.trim()),
          Variable<String>(storeId.trim()),
          Variable<String>(branchId.trim()),
          Variable<String>(idempotencyKey),
          Variable<String>(now),
          Variable<String>(now),
          Variable<String>(deviceId.trim()),
        ],
      );

      final ledger = CashLedgerService(_db);
      await ledger.appendInExistingTransaction(CashLedgerTransaction(
        id: 'cashledger_fixed_asset_$assetId',
        type: 'cash_withdrawal',
        direction: 'out',
        amount: _roundMoney(amount),
        currency: normalizedCurrency,
        cashLocationId: cashDrawer.id,
        cashDrawerSessionId: cashDrawerSessionId,
        referenceType: 'fixed_asset',
        referenceId: assetId,
        referenceNumber: normalizedCode,
        paymentMethod: 'Cash',
        createdBy: createdBy.trim(),
        createdByUserId: createdByUserId.trim(),
        deviceId: deviceId.trim(),
        branchId: branchId.trim(),
        storeId: storeId.trim(),
        notes: cashNotes,
        idempotencyKey: '$idempotencyKey:ledger',
        occurredAt: acquisitionDate.toUtc(),
        createdAt: nowDate,
        updatedAt: nowDate,
        lastModifiedByDeviceId: deviceId.trim(),
      ));

      await applyCashLocationDelta(
        cashLocationId: cashDrawer.id,
        delta: -_roundMoney(amount),
        updatedAt: now,
        database: _db,
      );

      final expectedCash = _roundMoney(
        await calculateCashDrawerExpectedCash(cashDrawerSessionId),
      );
      await _db.customUpdate(
        '''
          UPDATE cash_drawer_sessions
          SET expected_cash = ?, updated_at = ?, revision = revision + 1
          WHERE id = ? AND status = 'open'
          ''',
        variables: <Variable<Object>>[
          Variable<double>(expectedCash),
          Variable<String>(now),
          Variable<String>(cashDrawerSessionId),
        ],
      );
    }

    await _writeAuditLogInTransaction(
      _db,
      action: 'create_fixed_asset',
      entityType: 'fixed_asset',
      entityId: assetId,
      referenceType: 'fixed_asset',
      referenceId: assetId,
      details: paidFromCashDrawer
          ? '$normalizedCode - $normalizedName - cash drawer purchase'
          : '$normalizedCode - $normalizedName',
      createdBy: createdBy,
      storeId: storeId,
      branchId: branchId,
      createdAt: now,
    );
  });

  _notifyMutation();
}

Future<int> runDepreciationForAsset({
  required String assetId,
  DateTime? throughDate,
  String createdBy = '',
}) async {
  if (!isAvailable) return 0;
  final row = await _db.customSelect(
    '''
      SELECT *
      FROM fixed_assets
      WHERE id = ? AND deleted_at = '' AND status = 'active'
      LIMIT 1
      ''',
    variables: <Variable<Object>>[Variable<String>(assetId)],
  ).getSingleOrNull();
  if (row == null) throw ArgumentError('الأصل الثابت غير موجود: $assetId');
  final posted = await _runDepreciationForAssetRow(row.data,
      throughDate: throughDate, createdBy: createdBy);
  if (posted > 0) _notifyMutation();
  return posted;
}

Future<int> runDepreciationForAllAssets({
  DateTime? throughDate,
  String createdBy = '',
}) async {
  if (!isAvailable) return 0;
  final rows = await _db.customSelect(
    '''
      SELECT *
      FROM fixed_assets
      WHERE deleted_at = '' AND status = 'active' AND useful_life_months > 0 AND purchase_value > 0
      ORDER BY acquisition_date, code
      ''',
  ).get();
  var posted = 0;
  for (final row in rows) {
    posted += await _runDepreciationForAssetRow(row.data,
        throughDate: throughDate, createdBy: createdBy);
  }
  if (posted > 0) _notifyMutation();
  return posted;
}

Future<int> _runDepreciationForAssetRow(
  Map<String, Object?> asset, {
  DateTime? throughDate,
  String createdBy = '',
}) async {
  final id = asset['id']?.toString() ?? '';
  final code = asset['code']?.toString() ?? '';
  final name = asset['name']?.toString() ?? '';
  final purchaseValue = _roundMoney(_num(asset['purchase_value']));
  final usefulLifeMonths = (asset['useful_life_months'] as int?) ??
      int.tryParse(asset['useful_life_months']?.toString() ?? '') ??
      0;
  final acquisitionDate =
      DateTime.tryParse(asset['acquisition_date']?.toString() ?? '')?.toLocal();
  if (id.isEmpty ||
      acquisitionDate == null ||
      purchaseValue <= 0 ||
      usefulLifeMonths <= 0) {
    return 0;
  }

  final end = throughDate ?? DateTime.now();
  final endMonth = DateTime(end.year, end.month, 1);
  final firstMonth = DateTime(acquisitionDate.year, acquisitionDate.month, 1);
  var elapsedMonths = ((endMonth.year - firstMonth.year) * 12) +
      (endMonth.month - firstMonth.month) +
      1;
  if (elapsedMonths < 1) return 0;
  if (elapsedMonths > usefulLifeMonths) elapsedMonths = usefulLifeMonths;

  final existingRows = await _db.customSelect(
    '''
      SELECT period_key, COALESCE(SUM(amount), 0) AS amount
      FROM fixed_asset_depreciation
      WHERE asset_id = ? AND deleted_at = ''
      GROUP BY period_key
      ''',
    variables: <Variable<Object>>[Variable<String>(id)],
  ).get();
  final existing = <String, double>{
    for (final row in existingRows)
      row.data['period_key'].toString(): _num(row.data['amount']),
  };
  final accumulatedBefore =
      existing.values.fold<double>(0, (sum, amount) => sum + amount);
  var accumulated = _roundMoney(accumulatedBefore);
  var posted = 0;
  final monthly = _roundMoney(purchaseValue / usefulLifeMonths);
  final accounts = await readDefaultAccountMap();
  final expenseAccount =
      _requiredAccount(accounts, 'default_depreciation_expense_account_id');
  final accumulatedAccount =
      _requiredAccount(accounts, 'default_accumulated_depreciation_account_id');
  await _accountSnapshot(_db, expenseAccount);
  await _accountSnapshot(_db, accumulatedAccount);

  for (var i = 0; i < elapsedMonths; i++) {
    final period = DateTime(firstMonth.year, firstMonth.month + i, 1);
    final periodKey =
        '${period.year.toString().padLeft(4, '0')}-${period.month.toString().padLeft(2, '0')}';
    if (existing.containsKey(periodKey)) continue;
    final remaining = _roundMoney(purchaseValue - accumulated);
    if (remaining <= 0) break;
    final amount = _roundMoney(
        remaining < monthly || i == usefulLifeMonths - 1 ? remaining : monthly);
    if (amount <= 0) continue;
    final depreciationId = _newId('dep');
    final depreciationDate =
        DateTime(period.year, period.month + 1, 0, 23, 59, 59);
    final nextAccumulated = _roundMoney(accumulated + amount);
    final inserted = await _db.transaction(() async {
      final duplicate = await _db.customSelect(
        '''
          SELECT id
          FROM fixed_asset_depreciation
          WHERE asset_id = ? AND period_key = ? AND deleted_at = ''
          LIMIT 1
          ''',
        variables: <Variable<Object>>[
          Variable<String>(id),
          Variable<String>(periodKey),
        ],
      ).getSingleOrNull();
      if (duplicate != null) return false;

      final entryId = await createPostedEntry(
        JournalEntryDraft(
          entryDate: depreciationDate,
          referenceType: 'fixed_asset_depreciation',
          referenceId: depreciationId,
          referenceNo: '$code-$periodKey',
          description: 'إهلاك الأصل الثابت $code - $name ($periodKey)',
          createdBy: createdBy,
          storeId: asset['store_id']?.toString() ?? '',
          branchId: asset['branch_id']?.toString() ?? '',
          lines: <JournalLineDraft>[
            JournalLineDraft(
              accountId: expenseAccount,
              debit: amount,
              credit: 0,
              memo: 'مصروف إهلاك $code ($periodKey)',
            ),
            JournalLineDraft(
              accountId: accumulatedAccount,
              debit: 0,
              credit: amount,
              memo: 'مجمع إهلاك $code ($periodKey)',
            ),
          ],
        ),
        database: _db,
        withinExistingTransaction: true,
      );
      if (entryId.isEmpty) {
        throw StateError(
            'Fixed asset depreciation journal entry was not persisted.');
      }
      await _db.customInsert(
        '''
          INSERT INTO fixed_asset_depreciation
            (id, asset_id, period_key, depreciation_date, amount, accumulated_after, book_value_after,
             journal_entry_id, notes, created_at, store_id, branch_id)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
        variables: <Variable<Object>>[
          Variable<String>(depreciationId),
          Variable<String>(id),
          Variable<String>(periodKey),
          Variable<String>(depreciationDate.toUtc().toIso8601String()),
          Variable<double>(amount),
          Variable<double>(nextAccumulated),
          Variable<double>(_roundMoney(purchaseValue - nextAccumulated)),
          Variable<String>(entryId),
          Variable<String>('إهلاك القسط الثابت'),
          Variable<String>(DateTime.now().toUtc().toIso8601String()),
          Variable<String>(asset['store_id']?.toString() ?? ''),
          Variable<String>(asset['branch_id']?.toString() ?? ''),
        ],
      );
      return true;
    });
    if (inserted) {
      accumulated = nextAccumulated;
      posted++;
    }
  }
  return posted;
}
