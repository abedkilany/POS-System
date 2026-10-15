part of 'accounting_service_impl.dart';

Future<void> createSimpleMasterData({
  required String table,
  required String code,
  required String name,
}) async {
  if (!isAvailable) return;
  if (table != 'cost_centers' && table != 'accounting_branches') {
    throw ArgumentError('جدول بيانات محاسبية أساسية غير مدعوم: $table');
  }
  final now = DateTime.now().toUtc().toIso8601String();
  await _db.customInsert(
    '''
      INSERT INTO $table (id, code, name, is_active, notes, created_at, updated_at)
      VALUES (?, ?, ?, 1, '', ?, ?)
      ''',
    variables: <Variable<Object>>[
      Variable<String>(_newId(table == 'cost_centers' ? 'cc' : 'br')),
      Variable<String>(code.trim().toUpperCase()),
      Variable<String>(name.trim()),
      Variable<String>(now),
      Variable<String>(now),
    ],
  );
  _notifyMutation();
  await _writeAuditLog(
      action: 'create_master_data',
      entityType: table,
      details: '$code - $name');
}

_FrozenAccountingTax? _snapshotTaxBreakdown(
  PostedDocumentSnapshot? snapshot, {
  required String currency,
}) {
  if (snapshot == null ||
      snapshot.legacyBackfill ||
      snapshot.currency.taxSchemaVersion < 2) {
    return null;
  }
  final netAmount = _roundMoney(
    snapshot.lines.fold<double>(0, (sum, line) => sum + line.taxableBase),
    currency: currency,
  );
  final taxAmount = _roundMoney(
    snapshot.lines.fold<double>(0, (sum, line) => sum + line.taxAmount),
    currency: currency,
  );
  final grossNetBeforeDiscount = _roundMoney(
    snapshot.lines.fold<double>(0, (sum, line) {
      final gross = _cleanAmount(line.lineTotal);
      if (line.taxMode == 'standard' && line.taxRate > 0) {
        return sum + (gross / (1 + line.taxRate / 100));
      }
      return sum + gross;
    }),
    currency: currency,
  );
  return _FrozenAccountingTax(
    netAmount: netAmount,
    taxAmount: taxAmount,
    grossNetBeforeDiscount: grossNetBeforeDiscount,
  );
}

Future<double> _defaultVatRatePercent() async {
  final dbIdentity = identityHashCode(_db);
  if (_settingsCacheDbIdentity == dbIdentity && _defaultVatRateCache != null) {
    return _defaultVatRateCache!;
  }
  final row = await _db
      .customSelect(
        "SELECT value FROM accounting_settings WHERE key = 'default_vat_rate_percent' LIMIT 1",
      )
      .getSingleOrNull();
  final value = _num(row?.data['value']);
  final result =
      !value.isFinite || value < 0 ? 0.0 : value.clamp(0, 100).toDouble();
  _settingsCacheDbIdentity = dbIdentity;
  _defaultVatRateCache = result;
  return result;
}

Future<_TaxBreakdown> _taxBreakdown(double grossAmount) async {
  final gross = _roundMoney(_cleanAmount(grossAmount));
  final rate = await _defaultVatRatePercent();
  if (gross <= 0 || rate <= 0) {
    return _TaxBreakdown(
        netAmount: gross, taxAmount: 0, grossAmount: gross, ratePercent: rate);
  }
  final net = _roundMoney(gross / (1 + (rate / 100)));
  final tax = _roundMoney(gross - net);
  return _TaxBreakdown(
      netAmount: net, taxAmount: tax, grossAmount: gross, ratePercent: rate);
}

Future<void> recordInventoryCountAuditInTransaction({
  required VentioDriftDatabase database,
  required String action,
  required String inventoryCountId,
  required String details,
  String createdBy = '',
  String storeId = '',
  String branchId = '',
  DateTime? createdAt,
}) async {
  await _writeAuditLogInTransaction(
    database,
    action: action,
    entityType: 'inventory_count',
    entityId: inventoryCountId,
    referenceType: 'inventory_count',
    referenceId: inventoryCountId,
    details: details,
    createdBy: createdBy,
    storeId: storeId,
    branchId: branchId,
    createdAt: (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
  );
}

Future<void> _writeAuditLog({
  required String action,
  required String entityType,
  String entityId = '',
  String referenceType = '',
  String referenceId = '',
  String details = '',
  String createdBy = '',
  String storeId = '',
  String branchId = '',
}) async {
  await _writeAuditLogInTransaction(
    _db,
    action: action,
    entityType: entityType,
    entityId: entityId,
    referenceType: referenceType,
    referenceId: referenceId,
    details: details,
    createdBy: createdBy,
    storeId: storeId,
    branchId: branchId,
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
}

Future<void> _writeAuditLogInTransaction(
  VentioDriftDatabase db, {
  required String action,
  required String entityType,
  String entityId = '',
  String referenceType = '',
  String referenceId = '',
  String details = '',
  String createdBy = '',
  String storeId = '',
  String branchId = '',
  required String createdAt,
}) async {
  await db.customInsert(
    '''
      INSERT INTO accounting_audit_log
        (id, action, entity_type, entity_id, reference_type, reference_id,
         details, created_by, created_at, store_id, branch_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
    variables: <Variable<Object>>[
      Variable<String>(_newId('aal')),
      Variable<String>(action),
      Variable<String>(entityType),
      Variable<String>(entityId),
      Variable<String>(referenceType),
      Variable<String>(referenceId),
      Variable<String>(details),
      Variable<String>(createdBy),
      Variable<String>(createdAt),
      Variable<String>(storeId),
      Variable<String>(branchId),
    ],
  );
}

Future<bool> _hasActiveEntryForReference(
  VentioDriftDatabase db,
  String referenceType,
  String referenceId,
) async {
  if (referenceType.trim().isEmpty || referenceId.trim().isEmpty) {
    return false;
  }
  final row = await db.customSelect(
    '''
      SELECT id
      FROM journal_entries
      WHERE reference_type = ? AND reference_id = ? AND deleted_at = ''
      LIMIT 1
      ''',
    variables: <Variable<Object>>[
      Variable<String>(referenceType),
      Variable<String>(referenceId),
    ],
  ).getSingleOrNull();
  return row != null;
}

String _requiredAccount(Map<String, String> accounts, String key) {
  final accountId = accounts[key]?.trim() ?? '';
  if (accountId.isEmpty) {
    throw StateError('إعداد محاسبي مفقود: $key');
  }
  return accountId;
}

bool _isCashPaymentMethod(String paymentMethod) {
  final method = paymentMethod.trim().toLowerCase();
  return method.isEmpty || method == 'cash';
}

Future<void> _ensureCashDrawerDeviceBinding({
  required String cashLocationId,
  required String deviceId,
  required String branchId,
  required String updatedAt,
}) async {
  final cleanDeviceId = deviceId.trim();
  if (cleanDeviceId.isEmpty) return;
  final row = await _db.customSelect(
    '''
      SELECT id, type, device_id
      FROM cash_locations
      WHERE id = ? AND deleted_at = '' AND is_active = 1
      LIMIT 1
      ''',
    variables: <Variable<Object>>[Variable<String>(cashLocationId.trim())],
  ).getSingleOrNull();
  if (row == null) throw StateError('درج النقد غير موجود.');
  final type = row.data['type']?.toString() ?? '';
  if (type != 'cash_drawer') return;
  final existingDeviceId = row.data['device_id']?.toString().trim() ?? '';
  if (existingDeviceId.isNotEmpty && existingDeviceId != cleanDeviceId) {
    throw StateError(
        'هذا الدرج مربوط بجهاز آخر ولا يمكن فتحه من الجهاز الحالي.');
  }
  if (existingDeviceId.isEmpty) {
    await _db.customUpdate(
      "UPDATE cash_locations SET device_id = ?, branch_id = CASE WHEN branch_id = '' THEN ? ELSE branch_id END, updated_at = ? WHERE id = ?",
      variables: <Variable<Object>>[
        Variable<String>(cleanDeviceId),
        Variable<String>(branchId.trim()),
        Variable<String>(updatedAt),
        Variable<String>(cashLocationId.trim()),
      ],
    );
  }
}

Future<_CashLocationSnapshot?> _openCashDrawerLocationForDevice({
  required String deviceId,
  String branchId = '',
  VentioDriftDatabase? database,
}) async {
  final db = database ?? _db;
  final cleanDeviceId = deviceId.trim();
  if (cleanDeviceId.isEmpty) {
    return _openCashDrawerLocationFallback(branchId, database: db);
  }
  final branchFilter = branchId.trim().isEmpty ? '' : 'AND cds.branch_id = ?';
  final row = await db.customSelect(
    '''
      SELECT cl.id, cl.name, cl.type, cl.account_id
      FROM cash_drawer_sessions cds
      INNER JOIN cash_locations cl ON cl.id = cds.cash_location_id
      WHERE cds.status = 'open'
        AND cl.deleted_at = ''
        AND cl.is_active = 1
        AND cl.type = 'cash_drawer'
        AND cl.device_id = ?
        $branchFilter
      ORDER BY cds.opened_at DESC
      LIMIT 1
      ''',
    variables: <Variable<Object>>[
      Variable<String>(cleanDeviceId),
      if (branchId.trim().isNotEmpty) Variable<String>(branchId.trim()),
    ],
  ).getSingleOrNull();
  if (row == null) return null;
  final data = row.data;
  return _CashLocationSnapshot(
    id: data['id']?.toString() ?? '',
    name: data['name']?.toString() ?? '',
    type: data['type']?.toString() ?? '',
    accountId: data['account_id']?.toString() ?? '',
  );
}

Future<_CashLocationSnapshot?> _openCashDrawerLocationFallback(
  String branchId, {
  VentioDriftDatabase? database,
}) async {
  final db = database ?? _db;
  final branchFilter = branchId.trim().isEmpty ? '' : 'AND cds.branch_id = ?';
  final row = await db.customSelect(
    '''
      SELECT cl.id, cl.name, cl.type, cl.account_id
      FROM cash_drawer_sessions cds
      INNER JOIN cash_locations cl ON cl.id = cds.cash_location_id
      WHERE cds.status = 'open'
        AND cl.deleted_at = ''
        AND cl.is_active = 1
        $branchFilter
      ORDER BY cds.opened_at DESC
      LIMIT 1
      ''',
    variables: <Variable<Object>>[
      if (branchId.trim().isNotEmpty) Variable<String>(branchId.trim()),
    ],
  ).getSingleOrNull();
  if (row == null) return null;
  final data = row.data;
  return _CashLocationSnapshot(
    id: data['id']?.toString() ?? '',
    name: data['name']?.toString() ?? '',
    type: data['type']?.toString() ?? '',
    accountId: data['account_id']?.toString() ?? '',
  );
}

Future<void> _moveCashLocationBalance(
  String cashLocationId,
  double delta,
  DateTime movementDate, {
  VentioDriftDatabase? database,
}) async {
  final db = database ?? _db;
  final id = cashLocationId.trim();
  if (id.isEmpty || delta.abs() < 0.01) return;
  await applyCashLocationDelta(
    cashLocationId: id,
    delta: _roundMoney(delta),
    updatedAt: movementDate.toUtc().toIso8601String(),
    database: db,
  );
}

Future<void> _setCashLocationBalance(
    String cashLocationId, double balance, String updatedAt) async {
  final id = cashLocationId.trim();
  if (id.isEmpty) return;
  if (!balance.isFinite || balance < 0) {
    throw ArgumentError(
        'Direct cash balance reset requires a finite non-negative value.');
  }
  await _db.customUpdate(
    'UPDATE cash_locations SET current_balance = ?, updated_at = ? WHERE id = ?',
    variables: <Variable<Object>>[
      Variable<double>(_roundMoney(balance)),
      Variable<String>(updatedAt),
      Variable<String>(id),
    ],
  );
}

Future<String> _cashLocationAccountId(String cashLocationId) async {
  final id = cashLocationId.trim();
  if (id.isEmpty) {
    return resolveAccountRole('cash');
  }
  final location = await _cashLocationSnapshot(id);
  return location.accountId;
}

Future<_CashLocationSnapshot> _cashLocationSnapshot(
    String cashLocationId) async {
  final row = await _db.customSelect(
    '''
      SELECT id, name, type, account_id
      FROM cash_locations
      WHERE id = ? AND deleted_at = '' AND is_active = 1
      LIMIT 1
      ''',
    variables: <Variable<Object>>[Variable<String>(cashLocationId.trim())],
  ).getSingleOrNull();
  if (row == null) {
    throw ArgumentError('موقع النقدية غير موجود: $cashLocationId');
  }
  final data = row.data;
  return _CashLocationSnapshot(
    id: data['id']?.toString() ?? '',
    name: data['name']?.toString() ?? '',
    type: data['type']?.toString() ?? '',
    accountId: data['account_id']?.toString() ?? '',
  );
}

Future<String> _defaultCashLocationId(
    {required String type, String branchId = '', String deviceId = ''}) async {
  final normalizedType = _normalizeCashLocationType(type);
  final cleanBranchId = branchId.trim();
  final cleanDeviceId = deviceId.trim();
  if (cleanDeviceId.isNotEmpty) {
    final branchFilter = cleanBranchId.isEmpty ? '' : 'AND branch_id = ?';
    final deviceRow = await _db.customSelect(
      '''
        SELECT id
        FROM cash_locations
        WHERE deleted_at = '' AND is_active = 1 AND type = ? AND device_id = ? $branchFilter
        ORDER BY is_default DESC, code ASC
        LIMIT 1
        ''',
      variables: <Variable<Object>>[
        Variable<String>(normalizedType),
        Variable<String>(cleanDeviceId),
        if (cleanBranchId.isNotEmpty) Variable<String>(cleanBranchId),
      ],
    ).getSingleOrNull();
    final deviceIdResult = deviceRow?.data['id']?.toString() ?? '';
    if (deviceIdResult.isNotEmpty) return deviceIdResult;
  }
  final branchFilter = cleanBranchId.isEmpty ? '' : 'AND branch_id = ?';
  final row = await _db.customSelect(
    '''
      SELECT id
      FROM cash_locations
      WHERE deleted_at = '' AND is_active = 1 AND type = ? $branchFilter
      ORDER BY is_default DESC, code ASC
      LIMIT 1
      ''',
    variables: <Variable<Object>>[
      Variable<String>(normalizedType),
      if (cleanBranchId.isNotEmpty) Variable<String>(cleanBranchId),
    ],
  ).getSingleOrNull();
  final branchResult = row?.data['id']?.toString() ?? '';
  if (branchResult.isNotEmpty) return branchResult;
  final fallback = await _db.customSelect(
    '''
      SELECT id
      FROM cash_locations
      WHERE deleted_at = '' AND is_active = 1 AND type = ?
      ORDER BY is_default DESC, code ASC
      LIMIT 1
      ''',
    variables: <Variable<Object>>[Variable<String>(normalizedType)],
  ).getSingleOrNull();
  return fallback?.data['id']?.toString() ?? '';
}

Future<String> _createCashLocationAccount({
  required String locationId,
  required String name,
  required String type,
  required String code,
  String storeId = '',
  String branchId = '',
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  final isBank = type == 'bank';
  final parentAccountId = await _accountForCashLocationType(type);
  final accountId = 'acc_$locationId';
  final accountCodePrefix = isBank ? '12' : '11';
  final codeDigits = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
  final accountCode =
      '$accountCodePrefix${codeDigits.substring(codeDigits.length - 6)}';
  await _db.customInsert(
    '''
      INSERT OR IGNORE INTO accounts
        (id, code, name, type, subtype, parent_id, normal_balance, currency, is_system, is_active,
         description, created_at, updated_at, store_id, branch_id)
      VALUES (?, ?, ?, 'asset', ?, ?, 'debit', 'USD', 0, 1, ?, ?, ?, ?, ?)
      ''',
    variables: <Variable<Object>>[
      Variable<String>(accountId),
      Variable<String>(accountCode),
      Variable<String>(name),
      Variable<String>(isBank ? 'bank_location' : 'cash_location'),
      Variable<String>(parentAccountId),
      Variable<String>('حساب تلقائي لموقع نقدية: $code'),
      Variable<String>(now),
      Variable<String>(now),
      Variable<String>(storeId),
      Variable<String>(branchId),
    ],
  );
  return accountId;
}

Future<String> _accountForCashLocationType(String type) async {
  if (type == 'bank') {
    return resolveAccountRole('bank');
  }
  return resolveAccountRole('cash');
}

String _normalizeCashLocationType(String type) {
  final normalized = type.trim().toLowerCase();
  const allowed = <String>{
    'main_vault',
    'branch_vault',
    'cash_drawer',
    'bank',
    'wallet',
    'other'
  };
  if (allowed.contains(normalized)) return normalized;
  if (normalized == 'cash' || normalized == 'drawer') return 'cash_drawer';
  if (normalized == 'vault') return 'main_vault';
  return 'other';
}

Future<String> _nextCashTransferNo(DateTime date) async {
  final prefix = 'CT-${date.toUtc().year}-';
  final row = await _db.customSelect(
    'SELECT COUNT(*) AS count FROM cash_transfers WHERE transfer_no LIKE ?',
    variables: <Variable<Object>>[Variable<String>('$prefix%')],
  ).getSingle();
  final count = (row.data['count'] as int? ?? 0) + 1;
  return '$prefix${count.toString().padLeft(6, '0')}';
}

Future<String> _paymentAccountIdForDatabase(
  VentioDriftDatabase database,
  String paymentMethod,
) async {
  final method = paymentMethod.trim().toLowerCase();
  final normalizedType = switch (method) {
    'cash' || 'credit' || '' => 'cash',
    'card' || 'visa' || 'mastercard' || 'bank' || 'transfer' => 'bank',
    'wish' || 'wallet' || 'online' => 'wallet',
    'check' || 'cheque' => 'cheque',
    _ => 'other',
  };
  final row = await database.customSelect(
    '''
      SELECT account_id
      FROM payment_accounts
      WHERE deleted_at = '' AND is_active = 1 AND type = ?
      ORDER BY is_default DESC, name
      LIMIT 1
      ''',
    variables: <Variable<Object>>[Variable<String>(normalizedType)],
  ).getSingleOrNull();
  final accountId = row?.data['account_id']?.toString().trim() ?? '';
  if (accountId.isNotEmpty) return accountId;
  return _resolveAccountRoleForDatabase(
    database,
    normalizedType == 'cash' ? 'cash' : 'bank',
  );
}

Future<String> _paymentAccountId(String paymentMethod) async {
  final method = paymentMethod.trim().toLowerCase();
  final normalizedType = switch (method) {
    'cash' || 'credit' || '' => 'cash',
    'card' || 'visa' || 'mastercard' || 'bank' || 'transfer' => 'bank',
    'wish' || 'wallet' || 'online' => 'wallet',
    'check' || 'cheque' => 'cheque',
    _ => 'other',
  };
  final cached = _paymentAccountByTypeCache[normalizedType];
  if (cached != null) return cached;
  final row = await _db.customSelect(
    '''
      SELECT account_id
      FROM payment_accounts
      WHERE deleted_at = '' AND is_active = 1 AND type = ?
      ORDER BY is_default DESC, name
      LIMIT 1
      ''',
    variables: <Variable<Object>>[Variable<String>(normalizedType)],
  ).getSingleOrNull();
  final accountId = row?.data['account_id']?.toString().trim() ?? '';
  final resolved = accountId.isNotEmpty
      ? accountId
      : normalizedType == 'cash'
          ? await resolveAccountRole('cash')
          : await resolveAccountRole('bank');
  _paymentAccountByTypeCache[normalizedType] = resolved;
  return resolved;
}

Future<void> _assertDateNotInClosedPeriod(
  DateTime entryDate,
  String branchId, {
  VentioDriftDatabase? database,
}) async {
  final db = database ?? _db;
  final row = await db.customSelect(
    '''
      SELECT name
      FROM accounting_periods
      WHERE status IN ('closed', 'locked')
        AND datetime(?) BETWEEN datetime(start_date) AND datetime(end_date)
        AND (branch_id = '' OR branch_id = ?)
      ORDER BY start_date DESC
      LIMIT 1
      ''',
    variables: <Variable<Object>>[
      Variable<String>(entryDate.toUtc().toIso8601String()),
      Variable<String>(branchId),
    ],
  ).getSingleOrNull();
  if (row != null) {
    throw StateError(
        'لا يمكن ترحيل قيد محاسبي داخل فترة مغلقة: ${row.data['name']}.');
  }
}

void _validateBalancedDraft(JournalEntryDraft draft) {
  if (draft.lines.length < 2) {
    throw ArgumentError('يجب أن يحتوي قيد اليومية على سطرين على الأقل.');
  }
  final debit = draft.lines
      .fold<double>(0, (sum, line) => sum + _cleanAmount(line.debit));
  final credit = draft.lines
      .fold<double>(0, (sum, line) => sum + _cleanAmount(line.credit));
  if ((debit - credit).abs() > 0.0001 || debit <= 0) {
    throw ArgumentError('قيد اليومية غير متوازن.');
  }
  for (final line in draft.lines) {
    final hasDebit = _cleanAmount(line.debit) > 0;
    final hasCredit = _cleanAmount(line.credit) > 0;
    if (line.accountId.trim().isEmpty || hasDebit == hasCredit) {
      throw ArgumentError(
          'يجب أن يحتوي كل سطر في القيد على حساب واحد ومبلغ مدين أو دائن.');
    }
  }
}

Future<AccountingAccount> _accountSnapshot(
  VentioDriftDatabase db,
  String accountId,
) async {
  final dbIdentity = identityHashCode(db);
  if (_accountSnapshotCacheDbIdentity != dbIdentity) {
    _accountSnapshotCacheDbIdentity = dbIdentity;
    _accountSnapshotByIdCache.clear();
  }
  final normalizedAccountId = accountId.trim();
  final cached = _accountSnapshotByIdCache[normalizedAccountId];
  if (cached != null) return cached;
  final row = await db.customSelect(
    '''
      SELECT id, code, name, type, subtype, parent_id, normal_balance,
             currency, is_system, is_postable, is_active, description, created_at, updated_at
      FROM accounts
      WHERE id = ? AND deleted_at = '' AND is_active = 1
      LIMIT 1
      ''',
    variables: <Variable<Object>>[Variable<String>(accountId)],
  ).getSingleOrNull();
  if (row == null) {
    throw ArgumentError('الحساب المحاسبي غير موجود: $accountId');
  }
  final account = AccountingAccount.fromRow(row.data);
  _accountSnapshotByIdCache[normalizedAccountId] = account;
  return account;
}

Future<AccountingAccount> _accountSnapshotIncludingInactive(
  VentioDriftDatabase db,
  String accountId,
) async {
  final row = await db.customSelect(
    '''
      SELECT id, code, name, type, subtype, parent_id, normal_balance,
             currency, is_system, is_postable, is_active, description, created_at, updated_at
      FROM accounts
      WHERE id = ? AND deleted_at = ''
      LIMIT 1
      ''',
    variables: <Variable<Object>>[Variable<String>(accountId.trim())],
  ).getSingleOrNull();
  if (row == null) {
    throw ArgumentError('الحساب المحاسبي غير موجود: $accountId');
  }
  return AccountingAccount.fromRow(row.data);
}

Future<String> _nextEntryNo(
  VentioDriftDatabase db,
  DateTime date,
) async {
  final pending = _entryNoQueue.then((_) => _nextEntryNoUnlocked(db, date));
  _entryNoQueue = pending.then((_) {}, onError: (_) {});
  return pending;
}

Future<String> _nextEntryNoUnlocked(
  VentioDriftDatabase db,
  DateTime date,
) async {
  final year = date.toUtc().year;
  _ensureEntryNoCache(db);
  final sequence = await _nextEntrySequenceForYear(db, year);
  _entryNoSequenceByYear[year] = sequence + 1;
  return 'JE-$year-${sequence.toString().padLeft(6, '0')}';
}

Future<int> _nextEntrySequenceForYear(
  VentioDriftDatabase db,
  int year,
) async {
  final cached = _entryNoSequenceByYear[year];
  if (cached != null) {
    return cached;
  }
  final prefix = 'JE-$year-';
  final row = await db.customSelect(
    '''
      SELECT entry_no
      FROM journal_entries
      WHERE deleted_at = '' AND entry_no LIKE ?
      ORDER BY entry_no DESC
      LIMIT 1
      ''',
    variables: <Variable<Object>>[
      Variable<String>('$prefix%'),
    ],
  ).getSingleOrNull();
  final entryNo = row?.read<String>('entry_no') ?? '';
  final sequence = entryNo.length <= prefix.length
      ? 1
      : (int.tryParse(entryNo.substring(prefix.length)) ?? 0) + 1;
  _entryNoSequenceByYear[year] = sequence;
  return sequence;
}

void _ensureEntryNoCache(VentioDriftDatabase db) {
  final dbIdentity = identityHashCode(db);
  if (_entryNoCacheDbIdentity == dbIdentity) {
    return;
  }
  _entryNoCacheDbIdentity = dbIdentity;
  _entryNoSequenceByYear.clear();
}

DateTime _parseDate(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '')?.toLocal() ??
    DateTime.fromMillisecondsSinceEpoch(0);

double _num(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double _roundMoney(double value, {String? currency}) =>
    normalizeAccountingAmount(
      value,
      currency ?? _moneyProfile.baseCurrency,
      _moneyProfile,
    );

double _normalizedExpenseCashAmount({
  required double total,
  required double? requested,
  required bool requireCash,
}) {
  final normalizedTotal = _roundMoney(total);
  final value = _roundMoney(requested ?? normalizedTotal);
  if (!value.isFinite || value < 0 || value > normalizedTotal + 0.005) {
    throw ArgumentError(
        'مبلغ الدفع النقدي يجب أن يكون بين صفر وإجمالي المصروف.');
  }
  if (requireCash && value <= 0) {
    throw ArgumentError('مبلغ الدفع النقدي يجب أن يكون أكبر من صفر.');
  }
  return value > normalizedTotal ? normalizedTotal : value;
}

String _newId(String prefix) =>
    '${prefix}_${DateTime.now().toUtc().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';

double _cleanAmount(double value) => value.isFinite && value > 0 ? value : 0;
