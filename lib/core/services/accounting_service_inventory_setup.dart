part of 'accounting_service_impl.dart';

bool get isAvailable => SqliteMigrationManager.database != null;

void setMutationListener(void Function()? listener) {
  _mutationListener = listener;
}

void _notifyMutation() {
  _mutationListener?.call();
}

/// Phase 8 hook for services that own a larger SQLite transaction.
/// Call this only after the outer transaction has committed successfully.
void notifyCommittedMutation() {
  _notifyMutation();
}

void _clearAccountingSettingsCache() {
  _settingsCacheDbIdentity = null;
  _defaultAccountMapCache = null;
  _accountRoleMapCache = null;
  _defaultVatRateCache = null;
  _paymentAccountByTypeCache.clear();
}

void configureMoneyPolicy(StoreProfile profile) {
  _moneyProfile = profile;
  CashBalancePolicyService.configure(profile);
}

/// Single store-wide policy for cash outflows. The per-location database
/// flag is legacy compatibility data and is not an authorization source.
bool get allowNegativeCashBalance =>
    CashBalancePolicyService.allowNegativeCashBalance;

Future<void> ensureCashOutflowAllowed({
  required String cashLocationId,
  required double amount,
  VentioDriftDatabase? database,
}) {
  return CashBalancePolicyService.ensureOutflowAllowed(
    cashLocationId: cashLocationId,
    amount: amount,
    database: database,
  );
}

Future<void> applyCashLocationDelta({
  required String cashLocationId,
  required double delta,
  required String updatedAt,
  VentioDriftDatabase? database,
}) {
  return CashBalancePolicyService.applyDelta(
    cashLocationId: cashLocationId,
    delta: delta,
    updatedAt: updatedAt,
    database: database,
  );
}

VentioDriftDatabase get _db {
  final database = SqliteMigrationManager.database;
  if (database == null) {
    throw StateError('قاعدة بيانات SQLite غير مهيأة.');
  }
  return database;
}

/// Resolves the inventory class from the active BOM graph. A product that is
/// produced by a BOM is a finished/intermediate manufactured good; a product
/// that is only consumed by a BOM is raw material; everything else is
/// merchandise purchased for resale. Output classification wins when a
/// product is both the output of one BOM and a component of another.
Future<String> _inventoryRoleKeyForProduct(
  VentioDriftDatabase database,
  String productId,
) async {
  final normalizedId = productId.trim();
  if (normalizedId.isEmpty) return 'inventory_merchandise';
  final row = await database.customSelect(
    r'''
      SELECT CASE
        WHEN EXISTS (
          SELECT 1
          FROM bill_of_materials bom
          WHERE bom.output_product_id = ?
            AND bom.is_active = 1
            AND bom.deleted_at = ''
        ) THEN 'inventory_finished'
        WHEN EXISTS (
          SELECT 1
          FROM bill_of_materials_lines line
          INNER JOIN bill_of_materials bom
            ON bom.id = line.bill_of_material_id
          WHERE line.product_id = ?
            AND bom.is_active = 1
            AND bom.deleted_at = ''
        ) THEN 'inventory_raw'
        ELSE 'inventory_merchandise'
      END AS role_key
      ''',
    variables: <Variable<Object>>[
      Variable<String>(normalizedId),
      Variable<String>(normalizedId),
    ],
  ).getSingle();
  return row.data['role_key']?.toString() ?? 'inventory_merchandise';
}

Future<String> resolveInventoryRoleKeyForProduct(
  String productId,
) async {
  if (!isAvailable) return 'inventory_merchandise';
  return _inventoryRoleKeyForProduct(_db, productId);
}

Future<String> _inventoryAccountForProduct(
  VentioDriftDatabase database,
  String productId,
) async {
  final roleKey = await _inventoryRoleKeyForProduct(database, productId);
  return _resolveAccountRoleForDatabase(database, roleKey);
}

/// Resolves the postable inventory account for a product while keeping the
/// caller's transaction/database context. Purchase and sale reversals must
/// use the same product classification as the original posting.
Future<String> resolveInventoryAccountForProductForDatabase(
  VentioDriftDatabase database,
  String productId,
) =>
    _inventoryAccountForProduct(database, productId);

/// Groups inventory value by semantic inventory account and makes the final
/// rounded allocation equal [targetAmount]. This avoids one-cent imbalances
/// when VAT-inclusive purchase values are split across product classes.
Future<Map<String, double>> _inventoryAmountsByAccount(
  VentioDriftDatabase database,
  List<_InventoryAmount> items, {
  double? targetAmount,
}) async {
  final rawByAccount = <String, double>{};
  for (final item in items) {
    if (item.amount <= 0) continue;
    final accountId =
        await _inventoryAccountForProduct(database, item.productId);
    rawByAccount.update(
      accountId,
      (value) => value + item.amount,
      ifAbsent: () => item.amount,
    );
  }
  if (rawByAccount.isEmpty) return <String, double>{};
  final rawTotal = rawByAccount.values.fold<double>(0, (a, b) => a + b);
  final target = _roundMoney(targetAmount ?? rawTotal);
  if (rawTotal <= 0 || target <= 0) return <String, double>{};

  final entries = rawByAccount.entries.toList(growable: false);
  final result = <String, double>{};
  var allocated = 0.0;
  for (var index = 0; index < entries.length; index += 1) {
    final entry = entries[index];
    final amount = index == entries.length - 1
        ? _roundMoney(target - allocated)
        : _roundMoney(target * (entry.value / rawTotal));
    if (amount <= 0) continue;
    result[entry.key] = amount;
    allocated = _roundMoney(allocated + amount);
  }
  return result;
}

Future<Set<String>> _cashAndBankAccountIds(VentioDriftDatabase database) async {
  final accountIds = <String>{
    await _resolveAccountRoleForDatabase(database, 'cash'),
    await _resolveAccountRoleForDatabase(database, 'bank'),
  }..removeWhere((value) => value.trim().isEmpty);
  final locationRows = await database.customSelect(r'''
      SELECT DISTINCT account_id
      FROM cash_locations
      WHERE deleted_at = '' AND is_active = 1 AND account_id != ''
    ''').get();
  for (final row in locationRows) {
    final accountId = row.data['account_id']?.toString().trim() ?? '';
    if (accountId.isNotEmpty) accountIds.add(accountId);
  }
  return accountIds;
}

/// One-time engine-v13 migration for installations that posted historical
/// purchases and sales to the legacy general inventory account. It only
/// reclassifies value between inventory asset accounts; it never creates a
/// gain/loss and refuses to post when GL does not reconcile to valuation.
Future<bool> ensureInventoryAccountClassificationMigration() async {
  if (!isAvailable) return false;
  const migrationKey = 'inventory_account_reclass_v13';
  final database = _db;
  final existing = await database.customSelect(
    'SELECT value FROM accounting_settings WHERE key = ? LIMIT 1',
    variables: const <Variable<Object>>[
      Variable<String>(migrationKey),
    ],
  ).getSingleOrNull();
  if ((existing?.data['value']?.toString() ?? '') == 'completed') {
    return true;
  }

  final general =
      await _resolveAccountRoleForDatabase(database, 'inventory_asset');
  final raw = await _resolveAccountRoleForDatabase(database, 'inventory_raw');
  final wip = await _resolveAccountRoleForDatabase(database, 'inventory_wip');
  final finished =
      await _resolveAccountRoleForDatabase(database, 'inventory_finished');
  final merchandise =
      await _resolveAccountRoleForDatabase(database, 'inventory_merchandise');
  final specialized = <String>{raw, wip, finished, merchandise};
  if (general.isEmpty || specialized.contains(general)) {
    return false;
  }

  final accountIds = <String>{general, ...specialized}.toList(growable: false);
  final placeholders = List.filled(accountIds.length, '?').join(',');
  final balanceRows = await database.customSelect(
    '''
      SELECT jl.account_id,
             COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
      FROM journal_lines jl
      INNER JOIN journal_entries je ON je.id = jl.entry_id
      WHERE jl.account_id IN ($placeholders)
        AND je.deleted_at = ''
        AND je.status IN ('posted', 'reversed')
      GROUP BY jl.account_id
      ''',
    variables: <Variable<Object>>[
      for (final accountId in accountIds) Variable<String>(accountId),
    ],
  ).get();
  final current = <String, double>{
    for (final accountId in accountIds) accountId: 0.0,
    for (final row in balanceRows)
      row.data['account_id']?.toString() ?? '':
          _roundMoney(_num(row.data['balance'])),
  }..remove('');
  final currentTotal = _roundMoney(
    accountIds.fold<double>(0, (sum, id) => sum + (current[id] ?? 0)),
  );

  final valuation = await inventoryValuationReport();
  final physicalByAccount = <String, double>{};
  for (final row in valuation) {
    physicalByAccount.update(
      row.inventoryAccountId,
      (value) => value + row.totalValue,
      ifAbsent: () => row.totalValue,
    );
  }
  final physicalTotal = _roundMoney(
    physicalByAccount.values.fold<double>(0, (sum, value) => sum + value),
  );
  final difference = _roundMoney(currentTotal - physicalTotal).abs();
  if (difference > 0.05) {
    final now = DateTime.now().toUtc().toIso8601String();
    await database.customInsert(
      '''
        INSERT INTO accounting_settings
          (key, account_id, value, description, updated_at)
        VALUES (?, '', ?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET
          value = excluded.value,
          description = excluded.description,
          updated_at = excluded.updated_at
        ''',
      variables: <Variable<Object>>[
        const Variable<String>(migrationKey),
        Variable<String>('blocked:${difference.toStringAsFixed(2)}'),
        Variable<String>(
          'Inventory reclassification blocked: GL ${currentTotal.toStringAsFixed(2)} vs valuation ${physicalTotal.toStringAsFixed(2)}',
        ),
        Variable<String>(now),
      ],
    );
    return false;
  }

  if (currentTotal.abs() <= 0.005 && physicalTotal.abs() <= 0.005) {
    final now = DateTime.now().toUtc().toIso8601String();
    await database.customInsert(
      '''
        INSERT INTO accounting_settings
          (key, account_id, value, description, updated_at)
        VALUES (?, '', 'completed', ?, ?)
        ON CONFLICT(key) DO UPDATE SET
          value = 'completed', description = excluded.description,
          updated_at = excluded.updated_at
        ''',
      variables: <Variable<Object>>[
        const Variable<String>(migrationKey),
        const Variable<String>(
          'Inventory classification migration v13: no balance to reclassify.',
        ),
        Variable<String>(now),
      ],
    );
    return true;
  }

  // Preserve the existing total GL value exactly. Physical valuation is used
  // only to determine class proportions, so the migration can never conceal
  // a valuation discrepancy as income or expense.
  final desired = <String, double>{
    raw: physicalTotal <= 0
        ? 0
        : _roundMoney(
            currentTotal * ((physicalByAccount[raw] ?? 0) / physicalTotal),
          ),
    wip: 0,
    finished: physicalTotal <= 0
        ? 0
        : _roundMoney(
            currentTotal * ((physicalByAccount[finished] ?? 0) / physicalTotal),
          ),
    merchandise: 0,
  };
  desired[merchandise] = _roundMoney(
    currentTotal -
        (desired[raw] ?? 0) -
        (desired[wip] ?? 0) -
        (desired[finished] ?? 0),
  );

  final lines = <JournalLineDraft>[];
  var specializedNetAdjustment = 0.0;
  for (final accountId in <String>[raw, wip, finished, merchandise]) {
    final adjustment = _roundMoney(
      (desired[accountId] ?? 0) - (current[accountId] ?? 0),
    );
    if (adjustment.abs() <= 0.005) continue;
    specializedNetAdjustment =
        _roundMoney(specializedNetAdjustment + adjustment);
    lines.add(JournalLineDraft(
      accountId: accountId,
      debit: adjustment > 0 ? adjustment : 0,
      credit: adjustment < 0 ? adjustment.abs() : 0,
      memo: 'Inventory account classification migration v13',
    ));
  }
  if (specializedNetAdjustment.abs() > 0.005) {
    lines.add(JournalLineDraft(
      accountId: general,
      debit: specializedNetAdjustment < 0 ? specializedNetAdjustment.abs() : 0,
      credit: specializedNetAdjustment > 0 ? specializedNetAdjustment : 0,
      memo: 'Clear legacy general inventory into semantic classes',
    ));
  }

  if (lines.length >= 2) {
    await createPostedEntry(
      JournalEntryDraft(
        entryDate: DateTime.now(),
        referenceType: 'inventory_account_reclass',
        referenceId: migrationKey,
        referenceNo: 'INV-RECLASS-V13',
        description:
            'Reclassify legacy inventory into raw/finished/merchandise accounts',
        source: 'migration',
        lines: lines,
      ),
      database: database,
    );
  }
  final now = DateTime.now().toUtc().toIso8601String();
  await database.customInsert(
    '''
      INSERT INTO accounting_settings
        (key, account_id, value, description, updated_at)
      VALUES (?, '', 'completed', ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        value = 'completed', description = excluded.description,
        updated_at = excluded.updated_at
      ''',
    variables: <Variable<Object>>[
      const Variable<String>(migrationKey),
      const Variable<String>(
        'Inventory classification migration v13 completed without changing total inventory assets.',
      ),
      Variable<String>(now),
    ],
  );
  _clearAccountingSettingsCache();
  return true;
}

/// Reconciles the semantic inventory asset accounts against the current
/// Unified Batch valuation and active BOM graph without changing total
/// inventory assets. Unlike the one-time v13 migration, this is safe to run
/// repeatedly after BOM changes and during startup.
///
/// A reconciliation is posted only when the total inventory GL already
/// agrees with the physical Unified Batch valuation (within rounding
/// tolerance). This prevents classification repair from hiding a genuine
/// valuation discrepancy as a reclassification entry.
Future<bool> reconcileInventoryAccountClassification({
  String referenceContext = 'runtime',
  VentioDriftDatabase? database,
  bool withinExistingTransaction = false,
}) async {
  if (database == null && !isAvailable) return false;
  final db = database ?? _db;
  final general = await _resolveAccountRoleForDatabase(db, 'inventory_asset');
  final raw = await _resolveAccountRoleForDatabase(db, 'inventory_raw');
  final wip = await _resolveAccountRoleForDatabase(db, 'inventory_wip');
  final finished =
      await _resolveAccountRoleForDatabase(db, 'inventory_finished');
  final merchandise = await _resolveAccountRoleForDatabase(
    db,
    'inventory_merchandise',
  );
  final accountIds = <String>{general, raw, wip, finished, merchandise}
      .where((id) => id.trim().isNotEmpty)
      .toList(growable: false);
  if (accountIds.isEmpty) return false;

  final placeholders = List.filled(accountIds.length, '?').join(',');
  final balanceRows = await db.customSelect(
    '''
      SELECT jl.account_id,
             COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
      FROM journal_lines jl
      INNER JOIN journal_entries je ON je.id = jl.entry_id
      WHERE jl.account_id IN ($placeholders)
        AND je.deleted_at = ''
        AND je.status IN ('posted', 'reversed')
      GROUP BY jl.account_id
      ''',
    variables: <Variable<Object>>[
      for (final accountId in accountIds) Variable<String>(accountId),
    ],
  ).get();
  final current = <String, double>{
    for (final accountId in accountIds) accountId: 0.0,
    for (final row in balanceRows)
      row.data['account_id']?.toString() ?? '':
          _roundMoney(_num(row.data['balance'])),
  }..remove('');
  final currentTotal = _roundMoney(
    accountIds.fold<double>(0, (sum, id) => sum + (current[id] ?? 0)),
  );

  final valuation = await inventoryValuationReport(database: db);
  final physicalByAccount = <String, double>{};
  for (final row in valuation) {
    physicalByAccount.update(
      row.inventoryAccountId,
      (value) => value + row.totalValue,
      ifAbsent: () => row.totalValue,
    );
  }
  final physicalTotal = _roundMoney(
    physicalByAccount.values.fold<double>(0, (sum, value) => sum + value),
  );
  if (_roundMoney(currentTotal - physicalTotal).abs() > 0.05) {
    return false;
  }

  if (currentTotal.abs() <= 0.005 && physicalTotal.abs() <= 0.005) {
    await _clearDeferredBomInventoryReconciliation(database: db);
    return true;
  }

  // Preserve the already reconciled total GL value exactly and use the
  // Unified Batch valuation only to determine the semantic account split.
  final desired = <String, double>{
    raw: physicalTotal <= 0
        ? 0
        : _roundMoney(
            currentTotal * ((physicalByAccount[raw] ?? 0) / physicalTotal),
          ),
    wip: 0,
    finished: physicalTotal <= 0
        ? 0
        : _roundMoney(
            currentTotal * ((physicalByAccount[finished] ?? 0) / physicalTotal),
          ),
    merchandise: 0,
  };
  desired[merchandise] = _roundMoney(
    currentTotal -
        (desired[raw] ?? 0) -
        (desired[wip] ?? 0) -
        (desired[finished] ?? 0),
  );

  final lines = <JournalLineDraft>[];
  var specializedNetAdjustment = 0.0;
  for (final accountId in <String>[raw, wip, finished, merchandise]) {
    if (accountId.trim().isEmpty) continue;
    final adjustment = _roundMoney(
      (desired[accountId] ?? 0) - (current[accountId] ?? 0),
    );
    if (adjustment.abs() <= 0.005) continue;
    specializedNetAdjustment =
        _roundMoney(specializedNetAdjustment + adjustment);
    lines.add(JournalLineDraft(
      accountId: accountId,
      debit: adjustment > 0 ? adjustment : 0,
      credit: adjustment < 0 ? adjustment.abs() : 0,
      memo: 'Unified Batch inventory account classification reconciliation',
    ));
  }
  if (general.trim().isNotEmpty && specializedNetAdjustment.abs() > 0.005) {
    lines.add(JournalLineDraft(
      accountId: general,
      debit: specializedNetAdjustment < 0 ? specializedNetAdjustment.abs() : 0,
      credit: specializedNetAdjustment > 0 ? specializedNetAdjustment : 0,
      memo: 'Clear general inventory into semantic inventory accounts',
    ));
  }
  if (lines.isEmpty) {
    await _clearDeferredBomInventoryReconciliation(database: db);
    return true;
  }

  final sortedAccountIds = <String>[...accountIds]..sort();
  final fingerprintParts = <String>[
    for (final accountId in sortedAccountIds)
      '${accountId}_${(current[accountId] ?? 0).toStringAsFixed(2)}_${(desired[accountId] ?? 0).toStringAsFixed(2)}',
  ];
  final context = referenceContext.trim().isEmpty
      ? 'runtime'
      : referenceContext.trim().replaceAll(RegExp(r'[^A-Za-z0-9_.:-]'), '_');
  await createPostedEntry(
    JournalEntryDraft(
      entryDate: DateTime.now(),
      referenceType: 'inventory_account_reconcile',
      referenceId: '$context:${fingerprintParts.join('|')}',
      referenceNo: 'INV-CLASS-RECON',
      description:
          'Reconcile Unified Batch inventory value across semantic inventory accounts',
      source: 'system',
      lines: lines,
    ),
    database: db,
    withinExistingTransaction: withinExistingTransaction,
  );
  await _clearDeferredBomInventoryReconciliation(database: db);
  return true;
}

/// Records that a BOM save intentionally deferred inventory account
/// reclassification. This does not change any GL or inventory value.
Future<void> deferBomInventoryAccountReconciliation({
  required String referenceContext,
  VentioDriftDatabase? database,
}) async {
  if (database == null && !isAvailable) return;
  final db = database ?? _db;
  final now = DateTime.now().toUtc().toIso8601String();
  await db.customInsert(
    '''
      INSERT INTO accounting_settings
        (key, account_id, value, description, updated_at)
      VALUES (?, '', ?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        value = excluded.value,
        description = excluded.description,
        updated_at = excluded.updated_at
      ''',
    variables: <Variable<Object>>[
      const Variable<String>(deferredBomInventoryReconciliationKey),
      Variable<String>(referenceContext.trim()),
      Variable<String>(
        'BOM inventory account reclassification is deferred until inventory GL and Unified Batch valuation are reconciled.',
      ),
      Variable<String>(now),
    ],
  );
}

Future<void> _clearDeferredBomInventoryReconciliation({
  required VentioDriftDatabase database,
}) async {
  await database.customUpdate(
    'DELETE FROM accounting_settings WHERE key = ?',
    variables: const <Variable<Object>>[
      Variable<String>(deferredBomInventoryReconciliationKey),
    ],
  );
}
