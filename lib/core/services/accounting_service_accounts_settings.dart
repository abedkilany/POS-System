part of 'accounting_service_impl.dart';

Future<List<AccountingAccount>> listAccounts({
  bool activeOnly = true,
}) async {
  if (!isAvailable) return const <AccountingAccount>[];
  final rows = await _db.customSelect(
    '''
      SELECT id, code, name, type, subtype, parent_id, normal_balance,
             currency, is_system, is_postable, is_active, description, created_at, updated_at
      FROM accounts
      WHERE deleted_at = '' ${activeOnly ? 'AND is_active = 1' : ''}
      ORDER BY code
      ''',
  ).get();
  return rows.map((row) => AccountingAccount.fromRow(row.data)).toList();
}

Future<AccountingAccount> createAccount({
  required String code,
  required String name,
  required String type,
  required String normalBalance,
  String subtype = '',
  String parentId = '',
  String currency = 'USD',
  String description = '',
  bool isPostable = true,
  String storeId = '',
  String branchId = '',
}) async {
  if (!isAvailable) throw StateError('قاعدة بيانات SQLite غير مهيأة.');
  final normalizedCode = code.trim();
  final normalizedName = name.trim();
  final normalizedType = type.trim().toLowerCase();
  final normalizedBalance = normalBalance.trim().toLowerCase();
  final normalizedParentId = parentId.trim();
  final normalizedCurrency =
      currency.trim().isEmpty ? 'USD' : currency.trim().toUpperCase();
  if (normalizedCode.isEmpty || normalizedName.isEmpty) {
    throw ArgumentError('رقم الحساب واسمه مطلوبان.');
  }
  if (!supportedAccountTypes.contains(normalizedType)) {
    throw ArgumentError('نوع الحساب غير صالح: $type');
  }
  if (!supportedNormalBalances.contains(normalizedBalance)) {
    throw ArgumentError('الطبيعة المحاسبية غير صالحة: $normalBalance');
  }
  final duplicate = await _db.customSelect(
    "SELECT id FROM accounts WHERE code = ? AND deleted_at = '' LIMIT 1",
    variables: <Variable<Object>>[Variable<String>(normalizedCode)],
  ).getSingleOrNull();
  if (duplicate != null) {
    throw StateError('رقم الحساب مستخدم مسبقًا: $normalizedCode');
  }
  if (normalizedParentId.isNotEmpty) {
    await _accountSnapshot(_db, normalizedParentId);
  }
  final now = DateTime.now().toUtc().toIso8601String();
  final id = _newId('acc');
  await _db.customInsert(
    '''
      INSERT INTO accounts
        (id, code, name, type, subtype, parent_id, normal_balance, currency,
         is_system, is_postable, is_active, description, created_at, updated_at,
         store_id, branch_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, 1, ?, ?, ?, ?, ?)
      ''',
    variables: <Variable<Object>>[
      Variable<String>(id),
      Variable<String>(normalizedCode),
      Variable<String>(normalizedName),
      Variable<String>(normalizedType),
      Variable<String>(subtype.trim()),
      Variable<String>(normalizedParentId),
      Variable<String>(normalizedBalance),
      Variable<String>(normalizedCurrency),
      Variable<int>(isPostable ? 1 : 0),
      Variable<String>(description.trim()),
      Variable<String>(now),
      Variable<String>(now),
      Variable<String>(storeId.trim()),
      Variable<String>(branchId.trim()),
    ],
  );
  _clearAccountSnapshotCache();
  _notifyMutation();
  await _writeAuditLog(
    action: 'create_account',
    entityType: 'account',
    entityId: id,
    details: 'تم إنشاء الحساب $normalizedCode - $normalizedName',
    storeId: storeId,
    branchId: branchId,
  );
  return _accountSnapshot(_db, id);
}

Future<void> updateAccount({
  required String accountId,
  required String code,
  required String name,
  required String type,
  required String normalBalance,
  String subtype = '',
  String parentId = '',
  String currency = 'USD',
  String description = '',
  bool isPostable = true,
}) async {
  if (!isAvailable) return;
  final current = await _accountSnapshot(_db, accountId);
  final normalizedCode = code.trim();
  final normalizedName = name.trim();
  final normalizedType = type.trim().toLowerCase();
  final normalizedBalance = normalBalance.trim().toLowerCase();
  final normalizedParentId = parentId.trim();
  if (normalizedCode.isEmpty || normalizedName.isEmpty) {
    throw ArgumentError('رقم الحساب واسمه مطلوبان.');
  }
  if (!supportedAccountTypes.contains(normalizedType) ||
      !supportedNormalBalances.contains(normalizedBalance)) {
    throw ArgumentError('بيانات الحساب غير صالحة.');
  }
  if (normalizedParentId == current.id) {
    throw StateError('لا يمكن جعل الحساب أبًا لنفسه.');
  }
  if (normalizedParentId.isNotEmpty) {
    await _assertNoAccountCycle(current.id, normalizedParentId);
  }
  final duplicate = await _db.customSelect(
    "SELECT id FROM accounts WHERE code = ? AND id <> ? AND deleted_at = '' LIMIT 1",
    variables: <Variable<Object>>[
      Variable<String>(normalizedCode),
      Variable<String>(current.id),
    ],
  ).getSingleOrNull();
  if (duplicate != null) {
    throw StateError('رقم الحساب مستخدم مسبقًا: $normalizedCode');
  }
  if (current.isSystem &&
      (normalizedCode != current.code ||
          normalizedType != current.type ||
          normalizedParentId != current.parentId ||
          subtype.trim() != current.subtype)) {
    throw StateError('لا يمكن تغيير بنية حساب نظام أساسي.');
  }
  final now = DateTime.now().toUtc().toIso8601String();
  await _db.customUpdate(
    '''
      UPDATE accounts
      SET code = ?, name = ?, type = ?, subtype = ?, parent_id = ?,
          normal_balance = ?, currency = ?, is_postable = ?, description = ?,
          updated_at = ?, version = version + 1
      WHERE id = ? AND deleted_at = ''
      ''',
    variables: <Variable<Object>>[
      Variable<String>(normalizedCode),
      Variable<String>(normalizedName),
      Variable<String>(normalizedType),
      Variable<String>(subtype.trim()),
      Variable<String>(normalizedParentId),
      Variable<String>(normalizedBalance),
      Variable<String>(
          currency.trim().isEmpty ? 'USD' : currency.trim().toUpperCase()),
      Variable<int>(isPostable ? 1 : 0),
      Variable<String>(description.trim()),
      Variable<String>(now),
      Variable<String>(current.id),
    ],
  );
  _clearAccountSnapshotCache();
  _notifyMutation();
  await _writeAuditLog(
    action: 'update_account',
    entityType: 'account',
    entityId: current.id,
    details: 'تم تعديل الحساب $normalizedCode - $normalizedName',
  );
}

Future<void> setAccountActive({
  required String accountId,
  required bool active,
}) async {
  if (!isAvailable) return;
  final account = await _accountSnapshotIncludingInactive(_db, accountId);
  if (account.isSystem && !active) {
    throw StateError('لا يمكن تعطيل حساب نظام أساسي.');
  }
  if (!active) await _assertAccountCanBeDisabled(account.id);
  final now = DateTime.now().toUtc().toIso8601String();
  await _db.customUpdate(
    "UPDATE accounts SET is_active = ?, updated_at = ?, version = version + 1 WHERE id = ? AND deleted_at = ''",
    variables: <Variable<Object>>[
      Variable<int>(active ? 1 : 0),
      Variable<String>(now),
      Variable<String>(account.id),
    ],
  );
  _clearAccountSnapshotCache();
  _notifyMutation();
  await _writeAuditLog(
    action: active ? 'activate_account' : 'deactivate_account',
    entityType: 'account',
    entityId: account.id,
    details: active
        ? 'تم تفعيل الحساب ${account.code}'
        : 'تم تعطيل الحساب ${account.code}',
  );
}

Future<void> deleteAccount(String accountId) async {
  if (!isAvailable) return;
  final account = await _accountSnapshotIncludingInactive(_db, accountId);
  if (account.isSystem) throw StateError('لا يمكن حذف حساب نظام أساسي.');
  await _assertAccountCanBeDeleted(account.id);
  final now = DateTime.now().toUtc().toIso8601String();
  await _db.customUpdate(
    "UPDATE accounts SET deleted_at = ?, is_active = 0, updated_at = ?, version = version + 1 WHERE id = ? AND deleted_at = ''",
    variables: <Variable<Object>>[
      Variable<String>(now),
      Variable<String>(now),
      Variable<String>(account.id),
    ],
  );
  _clearAccountSnapshotCache();
  _notifyMutation();
  await _writeAuditLog(
    action: 'delete_account',
    entityType: 'account',
    entityId: account.id,
    details: 'تم حذف الحساب غير المستخدم ${account.code} - ${account.name}',
  );
}

void _clearAccountSnapshotCache() {
  _accountSnapshotCacheDbIdentity = null;
  _accountSnapshotByIdCache.clear();
}

Future<void> _assertNoAccountCycle(
    String accountId, String candidateParentId) async {
  var cursor = candidateParentId.trim();
  final visited = <String>{};
  while (cursor.isNotEmpty) {
    if (cursor == accountId) {
      throw StateError('لا يمكن إنشاء حلقة في شجرة دليل الحسابات.');
    }
    if (!visited.add(cursor)) {
      throw StateError('شجرة دليل الحسابات تحتوي على حلقة غير صالحة.');
    }
    final row = await _db.customSelect(
      "SELECT parent_id FROM accounts WHERE id = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(cursor)],
    ).getSingleOrNull();
    if (row == null) throw StateError('الحساب الأب غير موجود.');
    cursor = row.data['parent_id']?.toString() ?? '';
  }
}

Future<void> _assertAccountCanBeDisabled(String accountId) async {
  final setting = await _db.customSelect(
    'SELECT key FROM accounting_settings WHERE account_id = ? LIMIT 1',
    variables: <Variable<Object>>[Variable<String>(accountId)],
  ).getSingleOrNull();
  if (setting != null) {
    throw StateError(
        'الحساب مرتبط بإعداد محاسبي ولا يمكن تعطيله قبل تغيير الربط.');
  }
}

Future<void> _assertAccountCanBeDeleted(String accountId) async {
  final child = await _db.customSelect(
    "SELECT id FROM accounts WHERE parent_id = ? AND deleted_at = '' LIMIT 1",
    variables: <Variable<Object>>[Variable<String>(accountId)],
  ).getSingleOrNull();
  if (child != null) throw StateError('لا يمكن حذف حساب لديه حسابات فرعية.');
  final line = await _db.customSelect(
    'SELECT id FROM journal_lines WHERE account_id = ? LIMIT 1',
    variables: <Variable<Object>>[Variable<String>(accountId)],
  ).getSingleOrNull();
  if (line != null) {
    throw StateError(
        'لا يمكن حذف حساب مستخدم في قيود محاسبية. يمكن تعطيله بدلًا من ذلك.');
  }
  final setting = await _db.customSelect(
    'SELECT key FROM accounting_settings WHERE account_id = ? LIMIT 1',
    variables: <Variable<Object>>[Variable<String>(accountId)],
  ).getSingleOrNull();
  if (setting != null) {
    throw StateError('لا يمكن حذف حساب مرتبط بإعدادات المحاسبة.');
  }
  final payment = await _db.customSelect(
    "SELECT id FROM payment_accounts WHERE account_id = ? AND deleted_at = '' LIMIT 1",
    variables: <Variable<Object>>[Variable<String>(accountId)],
  ).getSingleOrNull();
  if (payment != null) throw StateError('لا يمكن حذف حساب مرتبط بطريقة دفع.');
  final cashLocation = await _db.customSelect(
    "SELECT id FROM cash_locations WHERE account_id = ? AND deleted_at = '' LIMIT 1",
    variables: <Variable<Object>>[Variable<String>(accountId)],
  ).getSingleOrNull();
  if (cashLocation != null) {
    throw StateError('لا يمكن حذف حساب مرتبط بموقع نقدي.');
  }
}

Future<double> readDefaultVatRatePercent() async {
  if (!isAvailable) return 0.0;
  return _defaultVatRatePercent();
}

Future<void> updateDefaultVatRatePercent(
  double ratePercent, {
  required BusinessSessionContext authorization,
}) async {
  authorization.requirePermission(AppPermission.accountingManage);
  final normalized =
      ratePercent.isFinite ? ratePercent.clamp(0, 100).toDouble() : 0.0;
  if (!isAvailable) return;
  final now = DateTime.now().toUtc().toIso8601String();
  await _db.customInsert(
    r'''
      INSERT INTO accounting_settings (key, account_id, value, description, updated_at)
      VALUES ('default_vat_rate_percent', '', ?, 'نسبة ضريبة القيمة المضافة الافتراضية للترحيل المحاسبي التلقائي', ?)
      ON CONFLICT(key) DO UPDATE SET
        value = excluded.value,
        updated_at = excluded.updated_at
      ''',
    variables: <Variable<Object>>[
      Variable<String>(_roundMoney(normalized).toString()),
      Variable<String>(now),
    ],
  );
  _clearAccountingSettingsCache();
  _notifyMutation();
  await _writeAuditLog(
    action: 'update_setting',
    entityType: 'accounting_setting',
    entityId: 'default_vat_rate_percent',
    details:
        'تم ضبط نسبة ضريبة القيمة المضافة الافتراضية إلى ${_roundMoney(normalized)}%',
  );
}

Future<Map<String, String>> readDefaultAccountMap() async {
  if (!isAvailable) return const <String, String>{};
  final dbIdentity = identityHashCode(_db);
  if (_settingsCacheDbIdentity == dbIdentity &&
      _defaultAccountMapCache != null) {
    return _defaultAccountMapCache!;
  }
  final rows = await _db.customSelect(
    '''
      SELECT key, account_id
      FROM accounting_settings
      WHERE key LIKE 'default_%_account_id'
      ORDER BY key
      ''',
  ).get();
  final result = <String, String>{
    for (final row in rows)
      row.data['key'].toString(): row.data['account_id'].toString(),
  };
  _settingsCacheDbIdentity = dbIdentity;
  _defaultAccountMapCache = result;
  return result;
}

Future<Map<String, String>> readAccountRoleMap() async {
  if (!isAvailable) return const <String, String>{};
  final dbIdentity = identityHashCode(_db);
  if (_settingsCacheDbIdentity == dbIdentity && _accountRoleMapCache != null) {
    return _accountRoleMapCache!;
  }
  final rows = await _db.customSelect(
    '''
      SELECT key, account_id
      FROM accounting_settings
      WHERE key LIKE 'role_%_account_id'
      ORDER BY key
      ''',
  ).get();
  final result = <String, String>{
    for (final row in rows)
      row.data['key'].toString(): row.data['account_id'].toString(),
  };
  _settingsCacheDbIdentity = dbIdentity;
  _accountRoleMapCache = result;
  return result;
}

Future<String> resolveAccountRole(String roleKey) async {
  final role = AccountingAccountRole.byKey(roleKey);
  if (role == null) {
    throw ArgumentError('دور محاسبي غير معروف: $roleKey');
  }
  if (!isAvailable) return '';
  final roles = await readAccountRoleMap();
  var accountId = roles[role.settingKey]?.trim() ?? '';
  if (accountId.isEmpty && role.syncsLegacySetting) {
    final defaults = await readDefaultAccountMap();
    accountId = defaults[role.legacySettingKey]?.trim() ?? '';
  }
  if (accountId.isEmpty) accountId = role.defaultAccountId;
  final account = await _accountSnapshot(_db, accountId);
  if (!account.isPostable) {
    throw StateError(
        'الحساب المرتبط بالدور ${role.titleAr} تجميعي وغير قابل للترحيل.');
  }
  return account.id;
}

Future<String> _resolveAccountRoleForDatabase(
  VentioDriftDatabase db,
  String roleKey,
) async {
  final role = AccountingAccountRole.byKey(roleKey);
  if (role == null) {
    throw ArgumentError('دور محاسبي غير معروف: $roleKey');
  }
  var row = await db.customSelect(
    'SELECT account_id FROM accounting_settings WHERE key = ? LIMIT 1',
    variables: <Variable<Object>>[Variable<String>(role.settingKey)],
  ).getSingleOrNull();
  var accountId = row?.data['account_id']?.toString().trim() ?? '';
  if (accountId.isEmpty && role.syncsLegacySetting) {
    row = await db.customSelect(
      'SELECT account_id FROM accounting_settings WHERE key = ? LIMIT 1',
      variables: <Variable<Object>>[Variable<String>(role.legacySettingKey)],
    ).getSingleOrNull();
    accountId = row?.data['account_id']?.toString().trim() ?? '';
  }
  if (accountId.isEmpty) accountId = role.defaultAccountId;
  final account = await _accountSnapshot(db, accountId);
  if (!account.isPostable) {
    throw StateError(
        'الحساب المرتبط بالدور ${role.titleAr} تجميعي وغير قابل للترحيل.');
  }
  return account.id;
}

/// Resolves a semantic account role against a specific database.
///
/// Operational services that already own a SQLite transaction should use
/// this helper so posting never falls back to hard-coded/default account ids.
Future<String> resolveAccountRoleForDatabase(
  VentioDriftDatabase database,
  String roleKey,
) =>
    _resolveAccountRoleForDatabase(database, roleKey);

Future<Map<String, String>> readResolvedAccountRoleMap() async {
  if (!isAvailable) return const <String, String>{};
  final result = <String, String>{};
  for (final role in AccountingAccountRole.all) {
    result[role.key] = await resolveAccountRole(role.key);
  }
  return result;
}

Future<List<String>> validateAccountRoleConfiguration() async {
  if (!isAvailable) return const <String>[];
  final errors = <String>[];
  for (final role in AccountingAccountRole.all) {
    try {
      await resolveAccountRole(role.key);
    } catch (error) {
      errors.add('${role.titleAr}: $error');
    }
  }
  return errors;
}

Future<void> updateAccountRole({
  required String roleKey,
  required String accountId,
}) async {
  final role = AccountingAccountRole.byKey(roleKey);
  if (role == null) {
    throw ArgumentError('دور محاسبي غير معروف: $roleKey');
  }
  final normalizedAccountId = accountId.trim();
  if (normalizedAccountId.isEmpty) {
    throw ArgumentError('الحساب مطلوب.');
  }
  if (!isAvailable) return;
  final selectedAccount = await _accountSnapshot(_db, normalizedAccountId);
  if (!selectedAccount.isPostable) {
    throw StateError('لا يمكن ربط دور محاسبي بحساب تجميعي غير قابل للترحيل.');
  }
  final now = DateTime.now().toUtc().toIso8601String();
  await _db.transaction(() async {
    await _upsertAccountSetting(
      key: role.settingKey,
      accountId: normalizedAccountId,
      description: 'Phase 2 account role: ${role.titleAr}',
      updatedAt: now,
    );
    if (role.syncsLegacySetting) {
      await _upsertAccountSetting(
        key: role.legacySettingKey,
        accountId: normalizedAccountId,
        description: 'متزامن مع الدور المحاسبي ${role.titleAr}',
        updatedAt: now,
      );
    }
  });
  _clearAccountingSettingsCache();
  _notifyMutation();
  await _writeAuditLog(
    action: 'update_account_role',
    entityType: 'accounting_setting',
    entityId: role.settingKey,
    details:
        'تم ربط الدور ${role.titleAr} بالحساب ${selectedAccount.code} - ${selectedAccount.name}',
  );
}

Future<void> updateDefaultAccount({
  required String key,
  required String accountId,
}) async {
  final normalizedKey = key.trim();
  final normalizedAccountId = accountId.trim();
  if (normalizedKey.isEmpty ||
      !normalizedKey.startsWith('default_') ||
      !normalizedKey.endsWith('_account_id')) {
    throw ArgumentError('مفتاح إعداد محاسبي غير صالح: $key');
  }
  if (normalizedAccountId.isEmpty) {
    throw ArgumentError('الحساب مطلوب.');
  }
  if (!isAvailable) return;
  final selectedAccount = await _accountSnapshot(_db, normalizedAccountId);
  if (!selectedAccount.isPostable) {
    throw StateError('لا يمكن ربط إعداد محاسبي بحساب تجميعي غير قابل للترحيل.');
  }
  final linkedRole = AccountingAccountRole.byLegacySettingKey(normalizedKey);
  final now = DateTime.now().toUtc().toIso8601String();
  await _db.transaction(() async {
    await _upsertAccountSetting(
      key: normalizedKey,
      accountId: normalizedAccountId,
      description: '',
      updatedAt: now,
    );
    if (linkedRole != null) {
      await _upsertAccountSetting(
        key: linkedRole.settingKey,
        accountId: normalizedAccountId,
        description: 'Phase 2 account role: ${linkedRole.titleAr}',
        updatedAt: now,
      );
    }
  });
  _clearAccountingSettingsCache();
  _notifyMutation();
  await _writeAuditLog(
    action: 'update_setting',
    entityType: 'accounting_setting',
    entityId: normalizedKey,
    details: 'تم ربط $normalizedKey بالحساب $normalizedAccountId',
  );
}

Future<void> _upsertAccountSetting({
  required String key,
  required String accountId,
  required String description,
  required String updatedAt,
}) async {
  await _db.customInsert(
    r'''
      INSERT INTO accounting_settings (key, account_id, value, description, updated_at)
      VALUES (?, ?, '', ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        account_id = excluded.account_id,
        description = CASE
          WHEN excluded.description = '' THEN accounting_settings.description
          ELSE excluded.description
        END,
        updated_at = excluded.updated_at
      ''',
    variables: <Variable<Object>>[
      Variable<String>(key),
      Variable<String>(accountId),
      Variable<String>(description),
      Variable<String>(updatedAt),
    ],
  );
}
