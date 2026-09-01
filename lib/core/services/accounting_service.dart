import 'dart:math';

import 'package:drift/drift.dart';

import '../../models/account_transaction.dart';
import '../../models/cash_ledger_transaction.dart';
import '../../models/accounting_account.dart';
import '../../models/expense.dart';
import '../../models/journal_entry.dart';
import '../../models/manufacturing.dart';
import '../../models/purchase.dart';
import '../../models/posted_document_snapshot.dart';
import '../../models/sale.dart';
import '../../models/sale_item.dart';
import '../../models/store_profile.dart';
import '../../models/user_role.dart';
import '../repositories/business_session_context.dart';
import '../accounting/accounting_account_role.dart';
import '../utils/currency_utils.dart';
import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/ventio_drift_database.dart';
import '../storage/sqlite/business_sqlite_store.dart';
import 'cash_ledger_service.dart';
import 'posted_document_edit_framework.dart';

class AccountingService {
  AccountingService._();

  static final Random _random = Random.secure();
  static bool get isAvailable => SqliteMigrationManager.database != null;
  static void Function()? _mutationListener;
  static StoreProfile _moneyProfile = StoreProfile.defaults;
  static int? _entryNoCacheDbIdentity;
  static int? _settingsCacheDbIdentity;
  static Map<String, String>? _defaultAccountMapCache;
  static Map<String, String>? _accountRoleMapCache;
  static double? _defaultVatRateCache;
  static final Map<String, String> _paymentAccountByTypeCache =
      <String, String>{};
  static int? _accountSnapshotCacheDbIdentity;
  static final Map<String, AccountingAccount> _accountSnapshotByIdCache =
      <String, AccountingAccount>{};
  static final Map<int, int> _entryNoSequenceByYear = <int, int>{};
  static Future<void> _entryNoQueue = Future<void>.value();

  static void setMutationListener(void Function()? listener) {
    _mutationListener = listener;
  }

  static void _notifyMutation() {
    _mutationListener?.call();
  }

  /// Phase 8 hook for services that own a larger SQLite transaction.
  /// Call this only after the outer transaction has committed successfully.
  static void notifyCommittedMutation() {
    _notifyMutation();
  }

  static void _clearAccountingSettingsCache() {
    _settingsCacheDbIdentity = null;
    _defaultAccountMapCache = null;
    _accountRoleMapCache = null;
    _defaultVatRateCache = null;
    _paymentAccountByTypeCache.clear();
  }

  static void configureMoneyPolicy(StoreProfile profile) {
    _moneyProfile = profile;
  }

  /// Single store-wide policy for cash outflows. The per-location database
  /// flag is legacy compatibility data and is not an authorization source.
  static bool get allowNegativeCashBalance =>
      _moneyProfile.allowNegativeCashBalance;

  static Future<void> ensureCashOutflowAllowed({
    required String cashLocationId,
    required double amount,
    VentioDriftDatabase? database,
  }) async {
    if (allowNegativeCashBalance || amount <= 0) return;
    final db = database ?? _db;
    final row = await db.customSelect(
      'SELECT current_balance FROM cash_locations WHERE id = ? AND deleted_at = \'\' AND is_active = 1 LIMIT 1',
      variables: <Variable<Object>>[Variable<String>(cashLocationId.trim())],
    ).getSingleOrNull();
    if (row == null) throw StateError('Cash location is unavailable.');
    final balance = _num(row.data['current_balance']);
    if (balance + 0.000001 < amount) {
      throw StateError('Insufficient cash balance.');
    }
  }

  static VentioDriftDatabase get _db {
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
  static Future<String> _inventoryRoleKeyForProduct(
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

  static Future<String> resolveInventoryRoleKeyForProduct(
    String productId,
  ) async {
    if (!isAvailable) return 'inventory_merchandise';
    return _inventoryRoleKeyForProduct(_db, productId);
  }

  static Future<String> _inventoryAccountForProduct(
    VentioDriftDatabase database,
    String productId,
  ) async {
    final roleKey = await _inventoryRoleKeyForProduct(database, productId);
    return _resolveAccountRoleForDatabase(database, roleKey);
  }

  /// Groups inventory value by semantic inventory account and makes the final
  /// rounded allocation equal [targetAmount]. This avoids one-cent imbalances
  /// when VAT-inclusive purchase values are split across product classes.
  static Future<Map<String, double>> _inventoryAmountsByAccount(
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

  static Future<Set<String>> _cashAndBankAccountIds(
      VentioDriftDatabase database) async {
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
  static Future<bool> ensureInventoryAccountClassificationMigration() async {
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
    final merchandise = await _resolveAccountRoleForDatabase(
        database, 'inventory_merchandise');
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
              currentTotal *
                  ((physicalByAccount[finished] ?? 0) / physicalTotal),
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
        debit: specializedNetAdjustment < 0
            ? specializedNetAdjustment.abs()
            : 0,
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
  static Future<bool> reconcileInventoryAccountClassification({
    String referenceContext = 'runtime',
    VentioDriftDatabase? database,
    bool withinExistingTransaction = false,
  }) async {
    if (database == null && !isAvailable) return false;
    final db = database ?? _db;
    final general =
        await _resolveAccountRoleForDatabase(db, 'inventory_asset');
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
              currentTotal *
                  ((physicalByAccount[finished] ?? 0) / physicalTotal),
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
    if (general.trim().isNotEmpty &&
        specializedNetAdjustment.abs() > 0.005) {
      lines.add(JournalLineDraft(
        accountId: general,
        debit: specializedNetAdjustment < 0
            ? specializedNetAdjustment.abs()
            : 0,
        credit: specializedNetAdjustment > 0
            ? specializedNetAdjustment
            : 0,
        memo: 'Clear general inventory into semantic inventory accounts',
      ));
    }
    if (lines.isEmpty) return true;

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
    return true;
  }

  static Future<List<AccountingAccount>> listAccounts({
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

  static const Set<String> supportedAccountTypes = <String>{
    'asset',
    'liability',
    'equity',
    'revenue',
    'cost_of_sales',
    'expense',
  };

  static const Set<String> supportedNormalBalances = <String>{
    'debit',
    'credit'
  };

  static Future<AccountingAccount> createAccount({
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

  static Future<void> updateAccount({
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

  static Future<void> setAccountActive({
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

  static Future<void> deleteAccount(String accountId) async {
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

  static void _clearAccountSnapshotCache() {
    _accountSnapshotCacheDbIdentity = null;
    _accountSnapshotByIdCache.clear();
  }

  static Future<void> _assertNoAccountCycle(
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

  static Future<void> _assertAccountCanBeDisabled(String accountId) async {
    final setting = await _db.customSelect(
      'SELECT key FROM accounting_settings WHERE account_id = ? LIMIT 1',
      variables: <Variable<Object>>[Variable<String>(accountId)],
    ).getSingleOrNull();
    if (setting != null) {
      throw StateError(
          'الحساب مرتبط بإعداد محاسبي ولا يمكن تعطيله قبل تغيير الربط.');
    }
  }

  static Future<void> _assertAccountCanBeDeleted(String accountId) async {
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

  static Future<double> readDefaultVatRatePercent() async {
    if (!isAvailable) return 0.0;
    return _defaultVatRatePercent();
  }

  static Future<void> updateDefaultVatRatePercent(
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

  static Future<Map<String, String>> readDefaultAccountMap() async {
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

  static Future<Map<String, String>> readAccountRoleMap() async {
    if (!isAvailable) return const <String, String>{};
    final dbIdentity = identityHashCode(_db);
    if (_settingsCacheDbIdentity == dbIdentity &&
        _accountRoleMapCache != null) {
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

  static Future<String> resolveAccountRole(String roleKey) async {
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

  static Future<String> _resolveAccountRoleForDatabase(
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
  static Future<String> resolveAccountRoleForDatabase(
    VentioDriftDatabase database,
    String roleKey,
  ) =>
      _resolveAccountRoleForDatabase(database, roleKey);

  static Future<Map<String, String>> readResolvedAccountRoleMap() async {
    if (!isAvailable) return const <String, String>{};
    final result = <String, String>{};
    for (final role in AccountingAccountRole.all) {
      result[role.key] = await resolveAccountRole(role.key);
    }
    return result;
  }

  static Future<List<String>> validateAccountRoleConfiguration() async {
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

  static Future<void> updateAccountRole({
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

  static Future<void> updateDefaultAccount({
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
      throw StateError(
          'لا يمكن ربط إعداد محاسبي بحساب تجميعي غير قابل للترحيل.');
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

  static Future<void> _upsertAccountSetting({
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

  static Future<void> recordSale(
    Sale sale, {
    String? accountingReferenceId,
    bool paymentPostedSeparately = false,
    bool withinExistingTransaction = false,
  }) async {
    if (sale.isDeleted || sale.isCancelled) return;
    if (!isAvailable) return;
    _requireSalePostedSnapshotMatches(
      sale,
      validatePaymentTotals: !paymentPostedSeparately,
    );
    final accountsReceivable = await resolveAccountRole('accounts_receivable');
    final salesRevenue = await resolveAccountRole('sales_revenue');
    final salesDiscounts = await resolveAccountRole('sales_discounts');
    final salesTax = await resolveAccountRole('sales_tax');
    final cogsAccount = await resolveAccountRole('cogs');
    final accountingCurrency = sale.invoiceCurrency.trim().isEmpty
        ? _moneyProfile.baseCurrency
        : sale.invoiceCurrency.trim().toUpperCase();
    final rawInvoiceTotal = _cleanAmount(sale.invoiceTotal);
    final rawSaleTotal = _cleanAmount(sale.total);
    final rawGrossSubtotal = _cleanAmount(sale.subtotal);
    final rawDiscount = min(
      rawGrossSubtotal,
      _cleanAmount(sale.discount),
    );
    final saleTotal = _roundMoney(rawSaleTotal, currency: accountingCurrency);
    final grossSubtotal =
        _roundMoney(rawGrossSubtotal, currency: accountingCurrency);
    final discountGross =
        _roundMoney(rawDiscount, currency: accountingCurrency);
    final frozenTax = _snapshotTaxBreakdown(
      sale.postedSnapshot,
      currency: accountingCurrency,
    );
    final legacyGrossTax = frozenTax == null
        ? await _taxBreakdown(grossSubtotal)
        : null;
    final legacyNetSaleTax = frozenTax == null
        ? await _taxBreakdown(saleTotal)
        : null;
    final revenueBeforeDiscount = frozenTax?.grossNetBeforeDiscount ??
        legacyGrossTax!.netAmount;
    final finalNetRevenue = frozenTax?.netAmount ?? legacyNetSaleTax!.netAmount;
    final salesDiscountNet = discountGross <= 0
        ? 0.0
        : max(
            0.0,
            _roundMoney(
              revenueBeforeDiscount - finalNetRevenue,
              currency: accountingCurrency,
            ),
          );
    // Phase 2: posted documents own their frozen, line-level VAT facts. This
    // prevents a later tax-profile/rate change from rewriting the accounting
    // meaning of an already-posted invoice. Legacy documents without the v2
    // tax snapshot keep the historical global-rate fallback.
    final outputTax = frozenTax?.taxAmount ?? legacyNetSaleTax!.taxAmount;
    final paidInInvoiceCurrency =
        _cleanAmount(sale.paidAmount.clamp(0, rawInvoiceTotal).toDouble());
    final rawPaid = rawInvoiceTotal <= 0
        ? 0.0
        : rawSaleTotal * (paidInInvoiceCurrency / rawInvoiceTotal);
    final paid = paymentPostedSeparately
        ? 0.0
        : min(
            saleTotal,
            _roundMoney(_cleanAmount(rawPaid), currency: accountingCurrency),
          );
    final balance = _roundMoney(_cleanAmount(saleTotal - paid),
        currency: accountingCurrency);
    final cogs = _roundMoney(
      _cleanAmount(
          sale.items.fold<double>(0, (sum, item) => sum + item.lineCost)),
      currency: accountingCurrency,
    );
    // A free/sample sale can have zero revenue but still carry inventory cost.
    // In that case the COGS/Inventory journal is mandatory. Only skip when
    // there is neither a financial sale amount nor an inventory cost effect.
    if (grossSubtotal <= 0 && cogs <= 0) return;
    final lines = <JournalLineDraft>[];

    final isCashSalePayment =
        paid > 0 && _isCashPaymentMethod(sale.paymentMethod);
    final cashSaleLocation = isCashSalePayment
        ? await _openCashDrawerLocationForDevice(
            deviceId: sale.deviceId, branchId: sale.branchId)
        : null;
    if (isCashSalePayment && cashSaleLocation == null) {
      throw StateError(
          'لا توجد وردية نقدية مفتوحة لدرج هذا الجهاز. افتح وردية قبل قبول الدفع النقدي.');
    }
    if (paid > 0) {
      lines.add(JournalLineDraft(
        accountId: cashSaleLocation?.accountId ??
            await _paymentAccountId(sale.paymentMethod),
        debit: paid,
        credit: 0,
        memo: 'دفعة مستلمة للمبيعة ${sale.invoiceNo}',
        partyType: 'customer',
        partyId: sale.customerId,
        partyName: sale.customerName,
      ));
    }
    if (balance > 0) {
      lines.add(JournalLineDraft(
        accountId: accountsReceivable,
        debit: balance,
        credit: 0,
        memo: 'مبلغ مستحق على العميل للمبيعة ${sale.invoiceNo}',
        partyType: 'customer',
        partyId: sale.customerId,
        partyName: sale.customerName,
      ));
    }
    if (revenueBeforeDiscount > 0) {
      lines.add(JournalLineDraft(
        accountId: salesRevenue,
        debit: 0,
        credit: revenueBeforeDiscount,
        memo: outputTax > 0
            ? 'إيرادات المبيعات قبل الخصم والضريبة ${sale.invoiceNo}'
            : 'إيرادات المبيعات قبل الخصم ${sale.invoiceNo}',
      ));
    }
    if (salesDiscountNet > 0) {
      lines.add(JournalLineDraft(
        accountId: salesDiscounts,
        debit: salesDiscountNet,
        credit: 0,
        memo: 'خصم مبيعات ${sale.invoiceNo}',
      ));
    }
    if (outputTax > 0) {
      lines.add(JournalLineDraft(
        accountId: salesTax,
        debit: 0,
        credit: outputTax,
        memo: 'ضريبة المخرجات بعد الخصم ${sale.invoiceNo}',
      ));
    }
    if (cogs > 0) {
      final inventoryCredits = await _inventoryAmountsByAccount(
        _db,
        <_InventoryAmount>[
          for (final item in sale.items)
            _InventoryAmount(item.productId, item.lineCost),
        ],
        targetAmount: cogs,
      );
      lines.add(JournalLineDraft(
        accountId: cogsAccount,
        debit: cogs,
        credit: 0,
        memo: 'تكلفة البضاعة المباعة ${sale.invoiceNo}',
      ));
      for (final inventory in inventoryCredits.entries) {
        lines.add(JournalLineDraft(
          accountId: inventory.key,
          debit: 0,
          credit: inventory.value,
          memo: 'مخزون صادر للمبيعة ${sale.invoiceNo}',
        ));
      }
    }
    final entryId = await createPostedEntry(
      JournalEntryDraft(
        entryDate: sale.date,
        referenceType: 'sale',
        referenceId: accountingReferenceId?.trim().isNotEmpty == true
            ? accountingReferenceId!.trim()
            : sale.id,
        referenceNo: sale.invoiceNo,
        description: 'فاتورة مبيعات ${sale.invoiceNo}',
        createdBy: sale.lastModifiedByDeviceId,
        storeId: sale.storeId,
        branchId: sale.branchId,
        lines: lines,
      ),
      database: _db,
      withinExistingTransaction: withinExistingTransaction,
    );
    if (entryId.isNotEmpty && cashSaleLocation != null && paid > 0) {
      await _moveCashLocationBalance(cashSaleLocation.id, paid, sale.date);
    }
  }

  static Future<String> recordSaleReturn({
    required Sale sale,
    required String returnReferenceId,
    required DateTime date,
    required double returnAmount,
    required double returnCogs,
    List<SaleItem> returnedItems = const <SaleItem>[],
    PostedDocumentSnapshot? returnSnapshot,
    String createdBy = '',
    bool withinExistingTransaction = false,
  }) async {
    if (!isAvailable ||
        returnReferenceId.trim().isEmpty ||
        (returnAmount <= 0 && returnCogs <= 0)) {
      return '';
    }
    final salesReturns = await resolveAccountRole('sales_returns');
    final salesTax = await resolveAccountRole('sales_tax');
    final accountsReceivable = await resolveAccountRole('accounts_receivable');
    final cogsAccount = await resolveAccountRole('cogs');
    final accountingCurrency = sale.invoiceCurrency.trim().isEmpty
        ? _moneyProfile.baseCurrency
        : sale.invoiceCurrency.trim().toUpperCase();
    final gross = _roundMoney(
      _cleanAmount(returnAmount),
      currency: accountingCurrency,
    );
    final cogs = _roundMoney(
      _cleanAmount(returnCogs),
      currency: accountingCurrency,
    );
    final frozenReturnTax = _snapshotTaxBreakdown(
      returnSnapshot,
      currency: accountingCurrency,
    );
    final tax = frozenReturnTax == null ? await _taxBreakdown(gross) : null;
    final returnNet = frozenReturnTax?.netAmount ?? tax!.netAmount;
    final returnTaxAmount = frozenReturnTax?.taxAmount ?? tax!.taxAmount;
    final lines = <JournalLineDraft>[];
    if (gross > 0) {
      lines.add(JournalLineDraft(
        accountId: salesReturns,
        debit: returnNet,
        credit: 0,
        memo: 'مرتجع مبيعات ${sale.invoiceNo}',
      ));
      if (returnTaxAmount > 0) {
        lines.add(JournalLineDraft(
          accountId: salesTax,
          debit: returnTaxAmount,
          credit: 0,
          memo: 'عكس ضريبة مبيعات ${sale.invoiceNo}',
        ));
      }
      lines.add(JournalLineDraft(
        accountId: accountsReceivable,
        debit: 0,
        credit: gross,
        memo: 'رصيد دائن للعميل عن مرتجع ${sale.invoiceNo}',
        partyType: 'customer',
        partyId: sale.customerId,
        partyName: sale.customerName,
      ));
    }
    if (cogs > 0) {
      final sourceItems = returnedItems.isEmpty ? sale.items : returnedItems;
      final inventoryDebits = await _inventoryAmountsByAccount(
        _db,
        <_InventoryAmount>[
          for (final item in sourceItems)
            _InventoryAmount(item.productId, item.lineCost),
        ],
        targetAmount: cogs,
      );
      for (final inventory in inventoryDebits.entries) {
        lines.add(JournalLineDraft(
          accountId: inventory.key,
          debit: inventory.value,
          credit: 0,
          memo: 'إعادة مخزون مرتجع ${sale.invoiceNo}',
        ));
      }
      lines.add(JournalLineDraft(
        accountId: cogsAccount,
        debit: 0,
        credit: cogs,
        memo: 'عكس تكلفة بضاعة مباعة ${sale.invoiceNo}',
      ));
    }
    return createPostedEntry(
      JournalEntryDraft(
        entryDate: date,
        referenceType: 'sale_return',
        referenceId: returnReferenceId.trim(),
        referenceNo: sale.invoiceNo,
        description: 'مرتجع مبيعات ${sale.invoiceNo}',
        source: 'system',
        createdBy: createdBy.trim().isEmpty
            ? sale.lastModifiedByDeviceId
            : createdBy.trim(),
        storeId: sale.storeId,
        branchId: sale.branchId,
        lines: lines,
      ),
      database: _db,
      withinExistingTransaction: withinExistingTransaction,
    );
  }

  static Future<bool> recordPurchase(Purchase purchase,
      {String accountingReferenceId = '',
      bool paymentPostedSeparately = false,
      bool withinExistingTransaction = false}) async {
    if (purchase.isDeleted || purchase.isCancelled || purchase.subtotal <= 0) {
      return true;
    }
    if (!isAvailable) return true;
    _requirePurchasePostedSnapshotMatches(
      purchase,
      validatePaymentTotals: !paymentPostedSeparately,
    );
    final purchaseTax = await resolveAccountRole('purchase_tax');
    final accountsPayable = await resolveAccountRole('accounts_payable');
    final accountingCurrency = _moneyProfile.baseCurrency;
    final rawTotal = _cleanAmount(purchase.subtotal);
    final total = _roundMoney(rawTotal, currency: accountingCurrency);
    final frozenPurchaseTax = _snapshotTaxBreakdown(
      purchase.postedSnapshot,
      currency: accountingCurrency,
    );
    final legacyPurchaseTax = frozenPurchaseTax == null
        ? await _taxBreakdown(total)
        : null;
    final purchaseNet = frozenPurchaseTax?.netAmount ?? legacyPurchaseTax!.netAmount;
    final inputTax = frozenPurchaseTax?.taxAmount ?? legacyPurchaseTax!.taxAmount;
    final paid = paymentPostedSeparately
        ? 0.0
        : min(
            total,
            _roundMoney(
              _cleanAmount(purchase.paidAmount.clamp(0, rawTotal).toDouble()),
              currency: accountingCurrency,
            ),
          );
    final balance =
        _roundMoney(_cleanAmount(total - paid), currency: accountingCurrency);
    final lines = <JournalLineDraft>[];
    final purchaseSnapshot = purchase.postedSnapshot;
    final hasFrozenPurchaseTax = purchaseSnapshot != null &&
        !purchaseSnapshot.legacyBackfill &&
        purchaseSnapshot.currency.taxSchemaVersion >= 2 &&
        purchaseSnapshot.lines.length == purchase.items.length;
    final inventoryDebits = await _inventoryAmountsByAccount(
      _db,
      <_InventoryAmount>[
        for (var index = 0; index < purchase.items.length; index += 1)
          _InventoryAmount(
            purchase.items[index].productId,
            hasFrozenPurchaseTax
                ? purchaseSnapshot.lines[index].taxableBase
                : purchase.items[index].lineTotal,
          ),
      ],
      targetAmount: purchaseNet,
    );
    for (final inventory in inventoryDebits.entries) {
      lines.add(JournalLineDraft(
        accountId: inventory.key,
        debit: inventory.value,
        credit: 0,
        memo: inputTax > 0
            ? 'مخزون مستلم قبل الضريبة ${purchase.purchaseNo}'
            : 'مخزون مستلم من المشتريات ${purchase.purchaseNo}',
        partyType: 'supplier',
        partyId: purchase.supplierId,
        partyName: purchase.supplierName,
      ));
    }
    if (inputTax > 0) {
      lines.add(JournalLineDraft(
        accountId: purchaseTax,
        debit: inputTax,
        credit: 0,
        memo: 'ضريبة المدخلات / ضريبة المشتريات ${purchase.purchaseNo}',
        partyType: 'supplier',
        partyId: purchase.supplierId,
        partyName: purchase.supplierName,
      ));
    }
    final isCashPurchasePayment =
        paid > 0 && _isCashPaymentMethod(purchase.paymentMethod);
    final cashPurchaseLocation = isCashPurchasePayment
        ? await _openCashDrawerLocationForDevice(
            deviceId: purchase.deviceId, branchId: purchase.branchId)
        : null;
    if (isCashPurchasePayment && cashPurchaseLocation == null) {
      throw StateError(
          'لا توجد وردية نقدية مفتوحة لدرج هذا الجهاز. افتح وردية قبل تسجيل دفع نقدي.');
    }
    if (paid > 0) {
      lines.add(JournalLineDraft(
        accountId: cashPurchaseLocation?.accountId ??
            await _paymentAccountId(purchase.paymentMethod),
        debit: 0,
        credit: paid,
        memo: 'دفعة مدفوعة للمشتريات ${purchase.purchaseNo}',
        partyType: 'supplier',
        partyId: purchase.supplierId,
        partyName: purchase.supplierName,
      ));
    }
    if (balance > 0) {
      lines.add(JournalLineDraft(
        accountId: accountsPayable,
        debit: 0,
        credit: balance,
        memo: 'مبلغ مستحق للمورد عن المشتريات ${purchase.purchaseNo}',
        partyType: 'supplier',
        partyId: purchase.supplierId,
        partyName: purchase.supplierName,
      ));
    }
    final referenceId = accountingReferenceId.trim().isEmpty
        ? purchase.id
        : accountingReferenceId.trim();
    final entryId = await createPostedEntry(
      JournalEntryDraft(
        entryDate: purchase.date,
        referenceType: 'purchase',
        referenceId: referenceId,
        referenceNo: purchase.purchaseNo,
        description: 'فاتورة مشتريات ${purchase.purchaseNo}',
        createdBy: purchase.lastModifiedByDeviceId,
        storeId: purchase.storeId,
        branchId: purchase.branchId,
        lines: lines,
      ),
      database: _db,
      withinExistingTransaction: withinExistingTransaction,
    );
    if (entryId.isNotEmpty && cashPurchaseLocation != null && paid > 0) {
      await _moveCashLocationBalance(
          cashPurchaseLocation.id, -paid, purchase.date);
    }
    return entryId.isNotEmpty;
  }

  /// Validates cash prerequisites before a purchase is persisted. Cash
  /// purchases must not be allowed to create stock or supplier-ledger rows
  /// when there is no open drawer to receive the matching cash movement.
  static Future<void> validatePurchasePayment({
    required String paymentMethod,
    required double paidAmount,
    required String deviceId,
    required String branchId,
  }) async {
    if (!isAvailable ||
        paidAmount <= 0 ||
        !_isCashPaymentMethod(paymentMethod)) {
      return;
    }
    final drawer = await _openCashDrawerLocationForDevice(
      deviceId: deviceId,
      branchId: branchId,
    );
    if (drawer == null) {
      throw StateError(
          'لا توجد وردية نقدية مفتوحة لدرج هذا الجهاز. افتح وردية قبل تسجيل دفع نقدي.');
    }
    final location = await _db.customSelect(
      "SELECT current_balance FROM cash_locations WHERE id = ? AND deleted_at = '' AND is_active = 1 LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(drawer.id)],
    ).getSingleOrNull();
    if (location == null) {
      throw StateError('درج النقد غير متاح.');
    }
    final balance = _num(location.data['current_balance']);
    if (!allowNegativeCashBalance && balance + 0.000001 < paidAmount) {
      throw StateError(
          'رصيد الصندوق غير كافٍ لتسجيل الشراء النقدي. الرصيد الحالي: ${_roundMoney(balance)}، المطلوب: ${_roundMoney(paidAmount)}.');
    }
  }

  static String _expenseAccountRoleKey(Expense expense) {
    String normalize(String value) => value.trim().toLowerCase();

    final type = normalize(expense.title);
    final category = normalize(expense.category);

    const aliases = <String, String>{
      'rent': 'rent_expense',
      'إيجار': 'rent_expense',
      'ايجار': 'rent_expense',
      'electricity': 'electricity_expense',
      'كهرباء': 'electricity_expense',
      'water': 'water_expense',
      'مياه': 'water_expense',
      'internet': 'telecom_expense',
      'phone': 'telecom_expense',
      'telephone': 'telecom_expense',
      'telecom': 'telecom_expense',
      'إنترنت': 'telecom_expense',
      'انترنت': 'telecom_expense',
      'هاتف': 'telecom_expense',
      'salaries': 'payroll_expense',
      'salary': 'payroll_expense',
      'wages': 'payroll_expense',
      'bonuses': 'payroll_expense',
      'bonus': 'payroll_expense',
      'رواتب': 'payroll_expense',
      'أجور': 'payroll_expense',
      'اجور': 'payroll_expense',
      'مكافآت': 'payroll_expense',
      'مكافات': 'payroll_expense',
      'fuel': 'transport_expense',
      'transportation': 'transport_expense',
      'transport': 'transport_expense',
      'delivery': 'transport_expense',
      'وقود': 'transport_expense',
      'مواصلات': 'transport_expense',
      'نقل': 'transport_expense',
      'توصيل': 'transport_expense',
      'maintenance': 'maintenance_expense',
      'صيانة': 'maintenance_expense',
      'advertising': 'marketing_expense',
      'design': 'marketing_expense',
      'social media': 'marketing_expense',
      'promotions': 'marketing_expense',
      'marketing': 'marketing_expense',
      'إعلانات': 'marketing_expense',
      'اعلانات': 'marketing_expense',
      'تصميم': 'marketing_expense',
      'تواصل اجتماعي': 'marketing_expense',
      'عروض ترويجية': 'marketing_expense',
      'تسويق': 'marketing_expense',
      'stationery': 'office_expense',
      'printing': 'office_expense',
      'cleaning': 'office_expense',
      'supplies': 'office_expense',
      'packaging': 'office_expense',
      'furniture': 'office_expense',
      'قرطاسية': 'office_expense',
      'طباعة': 'office_expense',
      'تنظيف': 'office_expense',
      'مستلزمات': 'office_expense',
      'تغليف': 'office_expense',
      'أثاث': 'office_expense',
      'اثاث': 'office_expense',
      'bank fees': 'bank_fees',
      'bank fee': 'bank_fees',
      'رسوم بنكية': 'bank_fees',
    };

    final direct = aliases[type];
    if (direct != null) return direct;

    // Category fallbacks intentionally remain conservative. Only categories
    // where every custom subtype belongs to the same accounting family are
    // routed automatically. Unknown/legacy values stay on general_expense.
    if (category == 'marketing' || category == 'تسويق') {
      return 'marketing_expense';
    }
    if (category == 'vehicles' || category == 'مركبات') {
      return 'transport_expense';
    }
    if (category == 'office' || category == 'مكتب') {
      return 'office_expense';
    }
    return 'general_expense';
  }

  static Future<String> _resolveExpenseAccountForDatabase(
    VentioDriftDatabase db,
    Expense expense,
  ) =>
      _resolveAccountRoleForDatabase(db, _expenseAccountRoleKey(expense));

  /// Posts a legacy Expense through the Phase 5 authoritative cash path.
  ///
  /// A posted expense is committed atomically as journal + cash_operations +
  /// Cash Ledger + cash_locations balance. No expense caller is allowed to
  /// mutate the drawer balance separately from its immutable ledger movement.
  static Future<void> recordExpense(Expense expense) async {
    if (expense.isDeleted || !expense.isPosted || expense.amount <= 0) return;
    if (!isAvailable) return;
    await _db.transaction(() async {
      // Phase 4: Expense status and all financial effects commit together.
      await _upsertExpenseRowInExistingTransaction(expense);
      await _recordExpenseInExistingTransaction(expense);
      await _recordExpenseCompatibilityLedgerInExistingTransaction(expense);
    });
    _notifyMutation();
  }

  /// Posts an expense on credit without touching the cash drawer or shift.
  /// The journal recognizes the expense immediately and carries the amount in
  /// the default suppliers/payables account until it is settled later.
  static Future<void> recordExpenseOnCredit(Expense expense) async {
    if (expense.isDeleted || !expense.isPosted || expense.amount <= 0) return;
    if (!isAvailable) return;
    await _db.transaction(() async {
      await _upsertExpenseRowInExistingTransaction(expense);
      await _recordCreditExpenseInExistingTransaction(expense);
      await _recordCreditExpenseCompatibilityLedgerInExistingTransaction(
          expense);
    });
    _notifyMutation();
  }

  /// Reposts an edited posted expense inside the caller's authoritative
  /// transaction using a versioned technical reference. The original journal,
  /// cash operation, Cash Ledger row and compatibility rows remain immutable.
  static Future<void> repostEditedExpenseInExistingTransaction(
    Expense expense, {
    required bool paidInCash,
    required String technicalReferenceId,
  }) async {
    if (expense.isDeleted || !expense.isPosted || expense.amount <= 0) {
      throw StateError('Only a valid posted expense can be reposted.');
    }
    final ref = technicalReferenceId.trim();
    if (ref.isEmpty) {
      throw ArgumentError('technicalReferenceId is required.');
    }
    await _upsertExpenseRowInExistingTransaction(expense);
    if (paidInCash) {
      await _recordExpenseInExistingTransaction(
        expense,
        accountingReferenceId: ref,
      );
      await _recordExpenseCompatibilityLedgerInExistingTransaction(
        expense,
        movementVersionSuffix: 'edit-v${expense.version}',
      );
    } else {
      await _recordCreditExpenseInExistingTransaction(
        expense,
        accountingReferenceId: ref,
      );
      await _recordCreditExpenseCompatibilityLedgerInExistingTransaction(
        expense,
        movementVersionSuffix: 'edit-v${expense.version}',
      );
    }
  }

  /// Returns posted credit-expense ids that have not yet been settled from cash.
  /// Credit approval is identified by the compatibility ledger row written by
  /// [recordExpenseOnCredit]. A successful cash settlement is identified by the
  /// stable cash-operation idempotency key used by the Cash page.
  static Future<Set<String>> readOutstandingCreditExpenseIds() async {
    if (!isAvailable) return <String>{};
    final rows = await _db.customSelect(
      '''
      SELECT DISTINCT at.reference_id AS expense_id
      FROM account_transactions at
      WHERE at.deleted_at = ''
        AND LOWER(at.transaction_type) = 'expense'
        AND LOWER(at.payment_method) = 'credit'
        AND TRIM(at.reference_id) <> ''
        AND NOT EXISTS (
          SELECT 1
          FROM cash_operations co
          WHERE co.deleted_at = ''
            AND LOWER(co.status) = 'posted'
            AND co.idempotency_key = ('expense-credit-settlement:' || at.reference_id)
        )
      ''',
    ).get();
    return rows
        .map((row) => row.data['expense_id']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  /// Atomically posts a batch of legacy expenses through the Phase 5 cash path.
  /// If any expense fails validation/accounting, the whole cash/accounting batch
  /// is rolled back so callers can keep every Expense in its pre-post state.
  static Future<void> recordExpensesBulk(List<Expense> expenses) async {
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

  static Future<void> _upsertExpenseRowInExistingTransaction(
      Expense expense) async {
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

  static Future<void> _recordExpenseCompatibilityLedgerInExistingTransaction(
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
    await insertMovement('${expense.id}-expense-debit$suffix', 'expense',
        expense.amount, 0, '', 'Expense ${expense.title}');
    await insertMovement('${expense.id}-expense-credit$suffix', 'paymentPaid', 0,
        expense.amount, 'Cash', 'Expense settlement ${expense.title}');
  }

  static Future<void>
      _recordCreditExpenseCompatibilityLedgerInExistingTransaction(
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

  static Future<void> _recordCreditExpenseInExistingTransaction(
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

  static Future<void> _recordExpenseInExistingTransaction(
    Expense expense, {
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

    final balanceRow = await _db.customSelect(
      "SELECT current_balance FROM cash_locations WHERE id = ? AND deleted_at = '' AND is_active = 1 LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(cashExpenseLocation.id)],
    ).getSingleOrNull();
    if (balanceRow == null) {
      throw StateError('موقع النقدية الخاص بالمصروف غير موجود أو غير فعال.');
    }
    final currentBalance = _num(balanceRow.data['current_balance']);
    if (!allowNegativeCashBalance && currentBalance + 0.000001 < amount) {
      throw StateError('الرصيد النقدي في الدرج غير كافٍ لتسجيل المصروف.');
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
            credit: amount,
            memo: 'دفعة مصروف',
          ),
        ],
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
        Variable<double>(amount),
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
      amount: amount,
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

    await _db.customUpdate(
      'UPDATE cash_locations SET current_balance = current_balance - ?, updated_at = ? WHERE id = ?',
      variables: <Variable<Object>>[
        Variable<double>(amount),
        Variable<String>(now),
        Variable<String>(cashExpenseLocation.id),
      ],
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

  /// Posts the accounting journal for a Phase 2 receipt/payment voucher.
  ///
  /// This deliberately does NOT move cash_locations.current_balance. The Phase 2
  /// PaymentVoucherService owns Cash Ledger + cash balance mutation so a voucher
  /// has one and only one cash effect. Idempotency is keyed by
  /// (reference_type, reference_id) and reinforced by a SQLite unique index.
  static Future<String> postVoucherPayment({
    required VentioDriftDatabase database,
    required String voucherType,
    required String voucherId,
    required String voucherNo,
    required DateTime date,
    required double amount,
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
    if (cleanAmount <= 0) {
      throw ArgumentError('مبلغ السند يجب أن يكون أكبر من صفر.');
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
                JournalLineDraft(
                  accountId: paymentAccount,
                  debit: cleanAmount,
                  credit: 0,
                  memo: 'سند قبض عميل',
                  partyType: 'customer',
                  partyId: partyId.trim(),
                  partyName: partyName.trim(),
                ),
                JournalLineDraft(
                  accountId: controlAccount,
                  debit: 0,
                  credit: cleanAmount,
                  memo: 'تخفيض ذمة العميل المدينة',
                  partyType: 'customer',
                  partyId: partyId.trim(),
                  partyName: partyName.trim(),
                ),
              ]
            : <JournalLineDraft>[
                JournalLineDraft(
                  accountId: controlAccount,
                  debit: cleanAmount,
                  credit: 0,
                  memo: 'تخفيض ذمة المورد الدائنة',
                  partyType: 'supplier',
                  partyId: partyId.trim(),
                  partyName: partyName.trim(),
                ),
                JournalLineDraft(
                  accountId: paymentAccount,
                  debit: 0,
                  credit: cleanAmount,
                  memo: 'سند دفع مورد',
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
  static Future<void> recordAccountPayment(
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
      final isCustomerPayment =
          transaction.isCustomer && transaction.credit > 0;
      final isSupplierPayment =
          transaction.isSupplier && transaction.debit > 0;
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

  static Future<String> createPostedEntry(
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
      final lineCount =
          (persisted?.data['line_count'] as num?)?.toInt() ?? 0;
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

  static void _requireSalePostedSnapshotMatches(
    Sale sale, {
    required bool validatePaymentTotals,
  }) {
    final snapshot = sale.postedSnapshot;
    if (snapshot == null) return;
    const tolerance = 0.000001;
    bool sameNumber(double left, double right) =>
        (left - right).abs() <= tolerance;
    Never mismatch(String reason) => throw StateError(
          'Sale posted snapshot does not match the current document ($reason). Rebuild the snapshot before accounting posting.',
        );

    if (snapshot.documentType != 'sale_invoice') mismatch('document type');
    if (snapshot.documentId.trim() != sale.id.trim()) mismatch('document id');
    if (snapshot.documentNumber.trim() != sale.invoiceNo.trim()) {
      mismatch('document number');
    }
    if (snapshot.party.id.trim() != sale.customerId.trim()) mismatch('customer');
    if (snapshot.warehouseId.trim() != sale.warehouseId.trim()) {
      mismatch('warehouse');
    }
    if (snapshot.lines.length != sale.items.length) mismatch('line count');
    for (var index = 0; index < sale.items.length; index += 1) {
      final item = sale.items[index];
      final line = snapshot.lines[index];
      if (line.lineId.trim() != '${sale.id}-line-$index' ||
          line.productId.trim() != item.productId.trim()) {
        mismatch('line identity at index $index');
      }
      if (!sameNumber(line.quantity, item.quantity) ||
          !sameNumber(line.baseQuantity, item.effectiveBaseQuantity) ||
          !sameNumber(line.conversionToBase, item.conversionToBase) ||
          !sameNumber(line.unitPrice, item.unitPrice) ||
          !sameNumber(line.lineTotal, item.lineTotal)) {
        mismatch('line values at index $index');
      }
    }
    if (!sameNumber(snapshot.totals.subtotal, sale.subtotal) ||
        !sameNumber(snapshot.totals.discount, sale.discount) ||
        !sameNumber(snapshot.totals.grandTotal, sale.total) ||
        !sameNumber(snapshot.totals.baseAmount, sale.baseAmount)) {
      mismatch('totals');
    }
    if (validatePaymentTotals) {
      final expectedPaid =
          sale.paidAmount.clamp(0, sale.invoiceTotal).toDouble();
      if (!sameNumber(snapshot.totals.paid, expectedPaid) ||
          !sameNumber(
            snapshot.totals.remaining,
            (sale.invoiceTotal - expectedPaid)
                .clamp(0, double.infinity)
                .toDouble(),
          )) {
        mismatch('payment totals');
      }
    }
  }

  static void _requirePurchasePostedSnapshotMatches(
    Purchase purchase, {
    required bool validatePaymentTotals,
  }) {
    final snapshot = purchase.postedSnapshot;
    if (snapshot == null) return;
    const tolerance = 0.000001;
    bool sameNumber(double left, double right) =>
        (left - right).abs() <= tolerance;
    Never mismatch(String reason) => throw StateError(
          'Purchase posted snapshot does not match the current document ($reason). Rebuild the snapshot before accounting posting.',
        );

    if (snapshot.documentType != 'purchase_invoice') {
      mismatch('document type');
    }
    if (snapshot.documentId.trim() != purchase.id.trim()) {
      mismatch('document id');
    }
    if (snapshot.documentNumber.trim() != purchase.purchaseNo.trim()) {
      mismatch('document number');
    }
    if (snapshot.party.id.trim() != purchase.supplierId.trim()) {
      mismatch('supplier');
    }
    if (snapshot.warehouseId.trim() != purchase.warehouseId.trim()) {
      mismatch('warehouse');
    }
    if (snapshot.lines.length != purchase.items.length) {
      mismatch('line count');
    }
    for (var index = 0; index < purchase.items.length; index += 1) {
      final item = purchase.items[index];
      final line = snapshot.lines[index];
      final expectedLineId = item.lineId.trim().isEmpty
          ? '${purchase.id}-line-$index'
          : item.lineId.trim();
      if (line.lineId.trim() != expectedLineId ||
          line.productId.trim() != item.productId.trim()) {
        mismatch('line identity at index $index');
      }
      if (!sameNumber(line.quantity, item.quantity) ||
          !sameNumber(line.baseQuantity, item.baseQuantity) ||
          !sameNumber(line.conversionToBase, item.conversionToBase) ||
          !sameNumber(line.unitPrice, item.unitCost) ||
          !sameNumber(line.lineTotal, item.lineTotal)) {
        mismatch('line values at index $index');
      }
    }
    if (!sameNumber(snapshot.totals.subtotal, purchase.subtotal) ||
        !sameNumber(snapshot.totals.grandTotal, purchase.subtotal) ||
        !sameNumber(snapshot.totals.baseAmount, purchase.subtotal)) {
      mismatch('totals');
    }
    if (validatePaymentTotals) {
      final expectedPaid =
          purchase.paidAmount.clamp(0, purchase.subtotal).toDouble();
      if (!sameNumber(snapshot.totals.paid, expectedPaid) ||
          !sameNumber(
            snapshot.totals.remaining,
            (purchase.subtotal - expectedPaid)
                .clamp(0, double.infinity)
                .toDouble(),
          )) {
        mismatch('payment totals');
      }
    }
  }


  static Future<int> countPostedJournalEntriesForReferences({
    required String referenceType,
    required Iterable<String> referenceIds,
  }) async {
    if (!isAvailable) return 0;
    final ids = referenceIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final normalizedReferenceType = referenceType.trim();
    if (normalizedReferenceType.isEmpty || ids.isEmpty) return 0;
    final db = _db;
    final placeholders = List<String>.filled(ids.length, '?').join(', ');
    final row = await db.customSelect(
      '''
      SELECT COUNT(*) AS count
      FROM journal_entries
      WHERE deleted_at = '' AND status = 'posted'
        AND reference_type = ?
        AND reference_id IN ($placeholders)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(normalizedReferenceType),
        ...ids.map((id) => Variable<String>(id)),
      ],
    ).getSingleOrNull();
    return row?.read<int>('count') ?? 0;
  }

  static Future<int> countPostedSaleEntriesForSale(
    String saleId,
  ) async {
    if (!isAvailable) return 0;
    final normalizedSaleId = saleId.trim();
    if (normalizedSaleId.isEmpty) return 0;
    final row = await _db.customSelect(
      '''
      SELECT COUNT(*) AS count
      FROM journal_entries je
      WHERE reference_type = 'sale'
        AND (reference_id = ? OR instr(reference_id, ?) = 1)
        AND deleted_at = '' AND status = 'posted'
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries rev
          WHERE rev.reversed_entry_id = je.id
            AND rev.deleted_at = '' AND rev.status = 'posted'
        )
      ''',
      variables: <Variable<Object>>[
        Variable<String>(normalizedSaleId),
        Variable<String>('$normalizedSaleId:sale_edit:'),
      ],
    ).getSingleOrNull();
    return row?.read<int>('count') ?? 0;
  }

  static Future<void> reverseSaleEntriesForSale({
    required String saleId,
    String reason = '',
    String createdBy = '',
    bool adjustCashLocationBalance = true,
    bool notifyChange = true,
    bool withinExistingTransaction = false,
  }) async {
    if (!isAvailable) return;
    final normalizedSaleId = saleId.trim();
    if (normalizedSaleId.isEmpty) return;
    var remaining = await countPostedSaleEntriesForSale(normalizedSaleId);
    var reversedAny = false;
    var safetyCounter = 0;
    while (remaining > 0) {
      if (safetyCounter++ >= 100) {
        throw StateError(
            'Too many active sale journal entries for $normalizedSaleId.');
      }
      await reverseEntryForReference(
        referenceType: 'sale',
        referenceId: normalizedSaleId,
        reason: reason,
        createdBy: createdBy,
        adjustCashLocationBalance: adjustCashLocationBalance,
        notifyChange: false,
        withinExistingTransaction: withinExistingTransaction,
      );
      final next = await countPostedSaleEntriesForSale(normalizedSaleId);
      if (next >= remaining) {
        throw StateError(
            'Failed to reverse active sale journal for $normalizedSaleId.');
      }
      reversedAny = true;
      remaining = next;
    }
    if (notifyChange && reversedAny) _notifyMutation();
  }

  static Future<int> countPostedPurchaseEntriesForPurchase(
    String purchaseId,
  ) async {
    if (!isAvailable) return 0;
    final normalizedPurchaseId = purchaseId.trim();
    if (normalizedPurchaseId.isEmpty) return 0;
    final row = await _db.customSelect(
      '''
      SELECT COUNT(*) AS count
      FROM journal_entries je
      WHERE reference_type = 'purchase'
        AND (reference_id = ? OR instr(reference_id, ?) = 1)
        AND deleted_at = '' AND status = 'posted'
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries rev
          WHERE rev.reversed_entry_id = je.id
            AND rev.deleted_at = '' AND rev.status = 'posted'
        )
      ''',
      variables: <Variable<Object>>[
        Variable<String>(normalizedPurchaseId),
        Variable<String>('$normalizedPurchaseId:purchase_edit:'),
      ],
    ).getSingleOrNull();
    return row?.read<int>('count') ?? 0;
  }

  static Future<void> reversePurchaseEntriesForPurchase({
    required String purchaseId,
    String reason = '',
    String createdBy = '',
    bool adjustCashLocationBalance = true,
    bool notifyChange = true,
    bool withinExistingTransaction = false,
  }) async {
    if (!isAvailable) return;
    final normalizedPurchaseId = purchaseId.trim();
    if (normalizedPurchaseId.isEmpty) return;
    var remaining =
        await countPostedPurchaseEntriesForPurchase(normalizedPurchaseId);
    var reversedAny = false;
    var safetyCounter = 0;
    while (remaining > 0) {
      if (safetyCounter++ >= 100) {
        throw StateError(
            'Too many active purchase journal entries for $normalizedPurchaseId.');
      }
      await reverseEntryForReference(
        referenceType: 'purchase',
        referenceId: normalizedPurchaseId,
        reason: reason,
        createdBy: createdBy,
        adjustCashLocationBalance: adjustCashLocationBalance,
        notifyChange: false,
        withinExistingTransaction: withinExistingTransaction,
      );
      final next =
          await countPostedPurchaseEntriesForPurchase(normalizedPurchaseId);
      if (next >= remaining) {
        throw StateError(
            'Failed to reverse active purchase journal for $normalizedPurchaseId.');
      }
      reversedAny = true;
      remaining = next;
    }
    if (notifyChange && reversedAny) _notifyMutation();
  }

  static Future<void> reverseEntryForReference({
    required String referenceType,
    required String referenceId,
    String reason = '',
    String createdBy = '',
    bool adjustCashLocationBalance = true,
    bool notifyChange = true,
    bool withinExistingTransaction = false,
  }) async {
    if (!isAvailable) return;
    final db = _db;
    if (referenceType.trim().isEmpty || referenceId.trim().isEmpty) return;
    final normalizedReferenceType = referenceType.trim();
    final normalizedReferenceId = referenceId.trim();
    // Posted document edits use versioned technical references. A later
    // edit/return/cancel must reverse the latest active member of that family.
    final editFamilyPrefix = normalizedReferenceType == 'purchase'
        ? '$normalizedReferenceId:purchase_edit:'
        : normalizedReferenceType == 'sale'
            ? '$normalizedReferenceId:sale_edit:'
            : normalizedReferenceType == 'receipt_voucher'
                ? '$normalizedReferenceId:receipt_edit:'
                : normalizedReferenceType == 'payment_voucher'
                    ? '$normalizedReferenceId:payment_edit:'
                    : normalizedReferenceType == 'expense'
                        ? '$normalizedReferenceId:expense_edit:'
                        : normalizedReferenceType == 'manual_journal'
                            ? '$normalizedReferenceId:manual_edit:'
                            : normalizedReferenceType == 'inventory_adjustment'
                                ? '$normalizedReferenceId:inventory_adjustment_edit:'
                                : normalizedReferenceType == 'sale_return'
                                    ? '$normalizedReferenceId:sale_return_edit:'
                                    : normalizedReferenceType == 'manufacturing_order'
                                        ? '$normalizedReferenceId:manufacturing_edit:'
                                        : '';
    final hasEditFamily = editFamilyPrefix.isNotEmpty;
    final entryRow = await db.customSelect(
      hasEditFamily
          ? '''
      SELECT id, entry_no, entry_date, reference_type, reference_id, reference_no,
             description, created_by, store_id, branch_id
      FROM journal_entries je
      WHERE reference_type = ?
        AND (reference_id = ? OR instr(reference_id, ?) = 1)
        AND deleted_at = '' AND status = 'posted'
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries rev
          WHERE rev.reversed_entry_id = je.id
            AND rev.deleted_at = '' AND rev.status = 'posted'
        )
      ORDER BY created_at DESC, entry_date DESC
      LIMIT 1
      '''
          : '''
      SELECT id, entry_no, entry_date, reference_type, reference_id, reference_no,
             description, created_by, store_id, branch_id
      FROM journal_entries je
      WHERE reference_type = ? AND reference_id = ?
        AND deleted_at = '' AND status = 'posted'
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries rev
          WHERE rev.reversed_entry_id = je.id
            AND rev.deleted_at = '' AND rev.status = 'posted'
        )
      ORDER BY created_at DESC, entry_date DESC
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(normalizedReferenceType),
        Variable<String>(normalizedReferenceId),
        if (hasEditFamily) Variable<String>(editFamilyPrefix),
      ],
    ).getSingleOrNull();
    if (entryRow == null) return;

    final original = entryRow.data;
    final originalId = original['id']?.toString() ?? '';
    final alreadyReversed = await db.customSelect(
      '''
      SELECT id FROM journal_entries
      WHERE reversed_entry_id = ? AND deleted_at = '' AND status = 'posted'
      LIMIT 1
      ''',
      variables: <Variable<Object>>[Variable<String>(originalId)],
    ).getSingleOrNull();
    if (alreadyReversed != null) return;

    final lineRows = await db.customSelect(
      '''
      SELECT account_id, debit, credit, memo, party_type, party_id, party_name, cost_center_id
      FROM journal_lines
      WHERE entry_id = ?
      ORDER BY line_no
      ''',
      variables: <Variable<Object>>[Variable<String>(originalId)],
    ).get();
    if (lineRows.isEmpty) return;

    final reversalLines = lineRows.map((row) {
      final data = row.data;
      return JournalLineDraft(
        accountId: data['account_id']?.toString() ?? '',
        debit: _cleanAmount(_num(data['credit'])),
        credit: _cleanAmount(_num(data['debit'])),
        memo: 'عكس: ${data['memo']?.toString() ?? ''}',
        partyType: data['party_type']?.toString() ?? '',
        partyId: data['party_id']?.toString() ?? '',
        partyName: data['party_name']?.toString() ?? '',
        costCenterId: data['cost_center_id']?.toString() ?? '',
      );
    }).toList();
    _validateBalancedDraft(JournalEntryDraft(
      entryDate: DateTime.now(),
      description: 'تحقق العكس',
      lines: reversalLines,
    ));

    final now = DateTime.now().toUtc().toIso8601String();
    final reversalId = _newId('je');
    final entryNo = await _nextEntryNo(db, DateTime.now());
    final storeId = original['store_id']?.toString() ?? '';
    final branchId = original['branch_id']?.toString() ?? '';
    final actor = createdBy.trim().isNotEmpty
        ? createdBy.trim()
        : (original['created_by']?.toString() ?? '');
    final originalEntryNo = original['entry_no']?.toString() ?? '';
    final description = reason.trim().isEmpty
        ? 'عكس قيد اليومية $originalEntryNo'
        : 'عكس قيد اليومية $originalEntryNo: ${reason.trim()}';

    Future<void> persistReversal() async {
      await db.customInsert(
        '''
        INSERT INTO journal_entries
          (id, entry_no, entry_date, reference_type, reference_id, reference_no,
           description, status, source, created_by, posted_at, reversed_entry_id,
           created_at, updated_at, store_id, branch_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'posted', 'reversal', ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(reversalId),
          Variable<String>(entryNo),
          Variable<String>(DateTime.now().toUtc().toIso8601String()),
          Variable<String>('${referenceType}_reversal'),
          Variable<String>(referenceId),
          Variable<String>(original['reference_no']?.toString() ?? ''),
          Variable<String>(description),
          Variable<String>(actor),
          Variable<String>(now),
          Variable<String>(originalId),
          Variable<String>(now),
          Variable<String>(now),
          Variable<String>(storeId),
          Variable<String>(branchId),
        ],
      );

      for (var index = 0; index < reversalLines.length; index++) {
        final line = reversalLines[index];
        final account = await _accountSnapshot(db, line.accountId);
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
            Variable<String>(reversalId),
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
            Variable<String>(storeId),
            Variable<String>(branchId),
          ],
        );
      }
      // Legacy callers may still ask the journal reversal to repair the
      // operational cash balance. Phase 6 cash-event reversals set this to
      // false and let the immutable Cash Ledger reversal own that balance.
      if (adjustCashLocationBalance) {
        for (final line in reversalLines) {
          final delta = _cleanAmount(line.debit - line.credit);
          if (delta.abs() < 0.01) continue;
          final cashLocations = await db.customSelect(
            '''
            SELECT id
            FROM cash_locations
            WHERE account_id = ? AND type = 'cash_drawer'
              AND deleted_at = '' AND is_active = 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>(line.accountId),
            ],
          ).get();
          for (final location in cashLocations) {
            await db.customUpdate(
              'UPDATE cash_locations SET current_balance = current_balance + ?, updated_at = ? WHERE id = ?',
              variables: <Variable<Object>>[
                Variable<double>(delta),
                Variable<String>(now),
                Variable<String>(location.data['id']?.toString() ?? ''),
              ],
            );
          }
        }
      }
      await db.customUpdate(
        '''
        UPDATE journal_entries
        SET status = 'reversed', updated_at = ?, reversal_reason = ?,
            reversed_at = ?, reversed_by = ?, reversed_by_entry_id = ?
        WHERE id = ? AND status = 'posted'
        ''',
        variables: <Variable<Object>>[
          Variable<String>(now),
          Variable<String>(reason.trim()),
          Variable<String>(now),
          Variable<String>(actor),
          Variable<String>(reversalId),
          Variable<String>(originalId),
        ],
      );
      await _writeAuditLogInTransaction(
        db,
        action: 'reverse_entry',
        entityType: 'journal_entry',
        entityId: originalId,
        referenceType: referenceType,
        referenceId: referenceId,
        details: description,
        createdBy: actor,
        storeId: storeId,
        branchId: branchId,
        createdAt: now,
      );
    }

    if (withinExistingTransaction) {
      await persistReversal();
    } else {
      await db.transaction(persistReversal);
    }
    if (notifyChange) _notifyMutation();
  }

  static Future<List<JournalEntrySummaryReport>> listJournalEntrySummaries({
    DateTime? from,
    DateTime? to,
    String status = '',
    String source = '',
    String search = '',
    int limit = 500,
  }) async {
    if (!isAvailable) return const <JournalEntrySummaryReport>[];
    final normalizedStatus = status.trim().toLowerCase();
    final normalizedSource = source.trim().toLowerCase();
    final normalizedSearch = search.trim().toLowerCase();
    final conditions = <String>["je.deleted_at = ''"];
    final variables = <Variable<Object>>[];
    if (from != null) {
      conditions.add('datetime(je.entry_date) >= datetime(?)');
      variables.add(Variable<String>(from.toUtc().toIso8601String()));
    }
    if (to != null) {
      conditions.add('datetime(je.entry_date) <= datetime(?)');
      variables.add(Variable<String>(to.toUtc().toIso8601String()));
    }
    if (normalizedStatus.isNotEmpty) {
      conditions.add('LOWER(je.status) = ?');
      variables.add(Variable<String>(normalizedStatus));
    }
    if (normalizedSource.isNotEmpty) {
      conditions.add('LOWER(je.source) = ?');
      variables.add(Variable<String>(normalizedSource));
    }
    if (normalizedSearch.isNotEmpty) {
      conditions.add('''(
        LOWER(je.entry_no) LIKE ? OR LOWER(je.reference_type) LIKE ? OR
        LOWER(je.reference_no) LIKE ? OR LOWER(je.reference_id) LIKE ? OR
        LOWER(je.description) LIKE ? OR LOWER(je.created_by) LIKE ? OR
        EXISTS (
          SELECT 1 FROM journal_lines search_line
          WHERE search_line.entry_id = je.id AND (
            LOWER(search_line.account_code) LIKE ? OR
            LOWER(search_line.account_name) LIKE ? OR
            LOWER(search_line.party_name) LIKE ? OR
            LOWER(search_line.memo) LIKE ?
          )
        )
      )''');
      final like = '%$normalizedSearch%';
      for (var i = 0; i < 10; i++) {
        variables.add(Variable<String>(like));
      }
    }
    variables.add(Variable<int>(limit.clamp(1, 500).toInt()));
    final rows = await _db.customSelect(
      '''
      SELECT je.id, je.entry_no, je.entry_date, je.reference_type,
             je.reference_id, je.reference_no, je.description, je.status,
             je.source, je.created_by, je.branch_id, je.reversed_entry_id,
             je.reversed_by_entry_id, je.reversal_reason,
             COALESCE(SUM(jl.debit), 0) AS total_debit,
             COALESCE(SUM(jl.credit), 0) AS total_credit,
             COUNT(jl.id) AS line_count
      FROM journal_entries je
      LEFT JOIN journal_lines jl ON jl.entry_id = je.id
      WHERE ${conditions.join(' AND ')}
      GROUP BY je.id, je.entry_no, je.entry_date, je.reference_type,
               je.reference_id, je.reference_no, je.description, je.status,
               je.source, je.created_by, je.store_id, je.branch_id, je.reversed_entry_id,
               je.reversed_by_entry_id, je.reversal_reason
      ORDER BY datetime(je.entry_date) DESC, je.entry_no DESC
      LIMIT ?
      ''',
      variables: variables,
    ).get();
    return rows
        .map((row) => JournalEntrySummaryReport.fromRow(row.data))
        .toList(growable: false);
  }

  static Future<List<JournalEntryDetailsReport>> journalEntryDetails({
    String entryId = '',
    String entryNo = '',
    String referenceType = '',
    String referenceId = '',
    String referenceNo = '',
  }) async {
    if (!isAvailable) return const <JournalEntryDetailsReport>[];
    final normalizedEntryId = entryId.trim();
    final normalizedEntryNo = entryNo.trim();
    final normalizedReferenceType = referenceType.trim();
    final normalizedReferenceId = referenceId.trim();
    final normalizedReferenceNo = referenceNo.trim();
    if (normalizedEntryId.isEmpty &&
        normalizedEntryNo.isEmpty &&
        normalizedReferenceId.isEmpty &&
        normalizedReferenceNo.isEmpty) {
      return const <JournalEntryDetailsReport>[];
    }

    final conditions = <String>["je.deleted_at = ''"];
    final variables = <Variable<Object>>[];
    if (normalizedEntryId.isNotEmpty) {
      conditions.add('je.id = ?');
      variables.add(Variable<String>(normalizedEntryId));
    } else if (normalizedEntryNo.isNotEmpty) {
      conditions.add('je.entry_no = ?');
      variables.add(Variable<String>(normalizedEntryNo));
    } else {
      if (normalizedReferenceType.isNotEmpty) {
        conditions.add('(je.reference_type = ? OR je.reference_type = ?)');
        variables.add(Variable<String>(normalizedReferenceType));
        variables.add(Variable<String>('${normalizedReferenceType}_reversal'));
      }
      if (normalizedReferenceId.isNotEmpty) {
        conditions.add('(je.reference_id = ? OR instr(je.reference_id, ?) = 1)');
        variables.add(Variable<String>(normalizedReferenceId));
        variables.add(Variable<String>('$normalizedReferenceId:'));
      }
      if (normalizedReferenceNo.isNotEmpty) {
        conditions.add('je.reference_no = ?');
        variables.add(Variable<String>(normalizedReferenceNo));
      }
    }

    final entryRows = await _db.customSelect(
      '''
      SELECT je.id, je.entry_no, je.entry_date, je.reference_type,
             je.reference_id, je.reference_no, je.description, je.status,
             je.source, je.created_by, je.branch_id, je.reversed_entry_id,
             je.reversed_by_entry_id, je.reversal_reason, je.posted_at,
             je.reversed_at, je.reversed_by
      FROM journal_entries je
      WHERE ${conditions.join(' AND ')}
      ORDER BY datetime(je.entry_date) DESC, je.entry_no DESC
      LIMIT 20
      ''',
      variables: variables,
    ).get();

    final result = <JournalEntryDetailsReport>[];
    for (final entryRow in entryRows) {
      final data = entryRow.data;
      final id = data['id']?.toString() ?? '';
      final lineRows = await _db.customSelect(
        '''
        SELECT line_no, account_id, account_code, account_name, debit, credit,
               memo, party_type, party_id, party_name, cost_center_id
        FROM journal_lines
        WHERE entry_id = ?
        ORDER BY line_no
        ''',
        variables: <Variable<Object>>[Variable<String>(id)],
      ).get();
      final lines = lineRows
          .map((row) => JournalEntryDetailLineReport.fromRow(row.data))
          .toList(growable: false);
      result.add(JournalEntryDetailsReport(
        id: id,
        entryNo: data['entry_no']?.toString() ?? '',
        entryDate: _parseDate(data['entry_date']),
        referenceType: data['reference_type']?.toString() ?? '',
        referenceId: data['reference_id']?.toString() ?? '',
        referenceNo: data['reference_no']?.toString() ?? '',
        description: data['description']?.toString() ?? '',
        status: data['status']?.toString() ?? '',
        source: data['source']?.toString() ?? '',
        createdBy: data['created_by']?.toString() ?? '',
        branchId: data['branch_id']?.toString() ?? '',
        reversedEntryId: data['reversed_entry_id']?.toString() ?? '',
        reversedByEntryId: data['reversed_by_entry_id']?.toString() ?? '',
        reversalReason: data['reversal_reason']?.toString() ?? '',
        postedAt: DateTime.tryParse(data['posted_at']?.toString() ?? ''),
        reversedAt: DateTime.tryParse(data['reversed_at']?.toString() ?? ''),
        reversedBy: data['reversed_by']?.toString() ?? '',
        lines: lines,
      ));
    }
    return result;
  }

  static Future<List<GeneralLedgerAccountReport>> generalLedgerReport({
    String accountId = '',
    DateTime? from,
    DateTime? to,
    String branchId = '',
    String costCenterId = '',
  }) async {
    if (!isAvailable) return const <GeneralLedgerAccountReport>[];
    final normalizedAccountId = accountId.trim();
    final normalizedBranchId = branchId.trim();
    final normalizedCostCenterId = costCenterId.trim();
    final fromText = from?.toUtc().toIso8601String() ?? '';
    final toText = to?.toUtc().toIso8601String() ?? '';
    final openingRows = from == null
        ? const <QueryRow>[]
        : await _db.customSelect(
            '''
            SELECT jl.account_id,
                   COALESCE(SUM(jl.debit), 0) AS debit,
                   COALESCE(SUM(jl.credit), 0) AS credit
            FROM journal_lines jl
            INNER JOIN journal_entries je ON je.id = jl.entry_id
            WHERE je.deleted_at = '' AND je.status IN ('posted', 'reversed')
              AND datetime(je.entry_date) < datetime(?)
              AND (? = '' OR jl.account_id = ?)
              AND (? = '' OR je.branch_id = ?)
              AND (? = '' OR jl.cost_center_id = ?)
            GROUP BY jl.account_id
            ''',
            variables: <Variable<Object>>[
              Variable<String>(fromText),
              Variable<String>(normalizedAccountId),
              Variable<String>(normalizedAccountId),
              Variable<String>(normalizedBranchId),
              Variable<String>(normalizedBranchId),
              Variable<String>(normalizedCostCenterId),
              Variable<String>(normalizedCostCenterId),
            ],
          ).get();
    final openingByAccount = <String, (double, double)>{
      for (final row in openingRows)
        row.data['account_id']?.toString() ?? '': (
          _num(row.data['debit']),
          _num(row.data['credit'])
        ),
    };
    final rows = await _db.customSelect(
      '''
      SELECT a.id AS account_id, a.code AS account_code, a.name AS account_name,
             a.type AS account_type, a.subtype AS account_subtype, a.normal_balance,
             je.id AS entry_id, jl.line_no, jl.debit, jl.credit, jl.memo,
             je.entry_no, je.entry_date, je.reference_type, je.reference_no,
             je.reference_id, je.source, je.description
      FROM accounts a
      LEFT JOIN journal_lines jl
        ON jl.account_id = a.id
        AND (? = '' OR jl.cost_center_id = ?)
      LEFT JOIN journal_entries je
        ON je.id = jl.entry_id AND je.deleted_at = ''
        AND je.status IN ('posted', 'reversed')
        AND (? = '' OR datetime(je.entry_date) >= datetime(?))
        AND (? = '' OR datetime(je.entry_date) <= datetime(?))
        AND (? = '' OR je.branch_id = ?)
      WHERE a.deleted_at = '' AND a.is_active = 1
        AND (? = '' OR a.id = ?)
      ORDER BY a.code, je.entry_date, je.entry_no, jl.line_no
      ''',
      variables: <Variable<Object>>[
        Variable<String>(normalizedCostCenterId),
        Variable<String>(normalizedCostCenterId),
        Variable<String>(fromText),
        Variable<String>(fromText),
        Variable<String>(toText),
        Variable<String>(toText),
        Variable<String>(normalizedBranchId),
        Variable<String>(normalizedBranchId),
        Variable<String>(normalizedAccountId),
        Variable<String>(normalizedAccountId),
      ],
    ).get();

    final accounts = <GeneralLedgerAccountReport>[];
    var hasCurrent = false;
    String currentAccountId = '';
    String accountCode = '';
    String accountName = '';
    String accountType = '';
    String accountSubtype = '';
    String normalBalance = 'debit';
    var openingBalance = 0.0;
    var runningBalance = 0.0;
    final lines = <GeneralLedgerLineReport>[];

    void flushCurrentAccount() {
      if (!hasCurrent) return;
      accounts.add(GeneralLedgerAccountReport(
        accountId: currentAccountId,
        accountCode: accountCode,
        accountName: accountName,
        accountType: accountType,
        accountSubtype: accountSubtype,
        normalBalance: normalBalance,
        openingBalance: _roundMoney(openingBalance),
        totalDebit:
            _roundMoney(lines.fold<double>(0, (sum, line) => sum + line.debit)),
        totalCredit: _roundMoney(
            lines.fold<double>(0, (sum, line) => sum + line.credit)),
        closingBalance: _roundMoney(runningBalance),
        lines: List<GeneralLedgerLineReport>.unmodifiable(lines),
      ));
    }

    for (final row in rows) {
      final nextAccountId = row.data['account_id']?.toString() ?? '';
      if (nextAccountId != currentAccountId) {
        flushCurrentAccount();
        hasCurrent = true;
        currentAccountId = nextAccountId;
        accountCode = row.data['account_code']?.toString() ?? '';
        accountName = row.data['account_name']?.toString() ?? '';
        accountType = row.data['account_type']?.toString() ?? '';
        accountSubtype = row.data['account_subtype']?.toString() ?? '';
        normalBalance = row.data['normal_balance']?.toString() ?? 'debit';
        final opening = openingByAccount[currentAccountId] ?? (0.0, 0.0);
        openingBalance = normalBalance == 'credit'
            ? opening.$2 - opening.$1
            : opening.$1 - opening.$2;
        runningBalance = openingBalance;
        lines.clear();
      }

      final entryId = row.data['entry_id']?.toString() ?? '';
      if (entryId.isEmpty) continue;

      final debit = _num(row.data['debit']);
      final credit = _num(row.data['credit']);
      runningBalance +=
          normalBalance == 'credit' ? credit - debit : debit - credit;
      lines.add(GeneralLedgerLineReport(
        entryNo: row.data['entry_no']?.toString() ?? '',
        entryDate: _parseDate(row.data['entry_date']),
        referenceType: row.data['reference_type']?.toString() ?? '',
        referenceId: row.data['reference_id']?.toString() ?? '',
        referenceNo: row.data['reference_no']?.toString() ?? '',
        source: row.data['source']?.toString() ?? '',
        description: row.data['description']?.toString() ?? '',
        memo: row.data['memo']?.toString() ?? '',
        debit: debit,
        credit: credit,
        runningBalance: _roundMoney(runningBalance),
      ));
    }

    flushCurrentAccount();
    return accounts;
  }

  static Future<List<TrialBalanceRowReport>> _trialBalanceRows({
    DateTime? from,
    DateTime? to,
  }) async {
    final accounts = await generalLedgerReport(from: from, to: to);
    return accounts.map((account) {
      return TrialBalanceRowReport(
        accountId: account.accountId,
        accountCode: account.accountCode,
        accountName: account.accountName,
        accountType: account.accountType,
        accountSubtype: account.accountSubtype,
        normalBalance: account.normalBalance,
        opening: account.openingBalance,
        debit: account.totalDebit,
        credit: account.totalCredit,
        balance: account.closingBalance,
        closing: account.closingBalance,
      );
    }).toList(growable: false);
  }

  static Future<List<TrialBalanceRowReport>> trialBalanceReport({
    DateTime? from,
    DateTime? to,
  }) async {
    if (!isAvailable) return const <TrialBalanceRowReport>[];
    return _trialBalanceRows(from: from, to: to);
  }

  static Future<IncomeStatementReport> incomeStatementReport({
    DateTime? from,
    DateTime? to,
  }) async {
    if (!isAvailable) {
      return const IncomeStatementReport(
        revenue: 0,
        costOfGoodsSold: 0,
        expenses: 0,
        grossProfit: 0,
        netProfit: 0,
      );
    }
    final rows = await _trialBalanceRows(from: from, to: to);
    double creditNet(String type) => rows
        .where((row) => row.accountType == type)
        .fold<double>(0, (sum, row) => sum + row.credit - row.debit);
    double debitNet(String type) => rows
        .where((row) => row.accountType == type)
        .fold<double>(0, (sum, row) => sum + row.debit - row.credit);
    final revenue = creditNet('revenue');
    final cogs = debitNet('cost_of_sales');
    final expenses = debitNet('expense');
    double accountCreditNet(String id) => rows
        .where((row) => row.accountId == id)
        .fold<double>(0, (sum, row) => sum + row.credit - row.debit);
    double accountDebitNet(String id) => rows
        .where((row) => row.accountId == id)
        .fold<double>(0, (sum, row) => sum + row.debit - row.credit);
    final salesRevenueId = await resolveAccountRole('sales_revenue');
    final salesReturnsId = await resolveAccountRole('sales_returns');
    final salesDiscountsId = await resolveAccountRole('sales_discounts');
    final grossSales = accountCreditNet(salesRevenueId);
    final salesReturns = accountDebitNet(salesReturnsId);
    final salesDiscounts = accountDebitNet(salesDiscountsId);
    final netSales = grossSales - salesReturns - salesDiscounts;
    final inventoryGain =
        accountCreditNet(await resolveAccountRole('inventory_count_gain'));
    final cashOver = accountCreditNet(await resolveAccountRole('cash_over'));
    final inventoryLoss =
        accountDebitNet(await resolveAccountRole('inventory_count_loss'));
    final manufacturingWaste =
        accountDebitNet(await resolveAccountRole('manufacturing_waste'));
    final manufacturingVariance = accountDebitNet(
        await resolveAccountRole('manufacturing_cost_variance'));
    final cashShort = accountDebitNet(await resolveAccountRole('cash_short'));
    FinancialStatementAccountLine statementLine(
      TrialBalanceRowReport row,
      double amount,
    ) =>
        FinancialStatementAccountLine(
          accountId: row.accountId,
          accountCode: row.accountCode,
          accountName: row.accountName,
          accountType: row.accountType,
          accountSubtype: row.accountSubtype,
          amount: _roundMoney(amount),
        );
    final primarySalesAccountIds = <String>{
      salesRevenueId,
      salesReturnsId,
      salesDiscountsId,
    }..removeWhere((id) => id.trim().isEmpty);
    final otherRevenueLines = rows
        .where((row) =>
            row.accountType == 'revenue' &&
            !primarySalesAccountIds.contains(row.accountId))
        .map((row) => statementLine(row, row.credit - row.debit))
        .where((line) => line.amount.abs() > 0.0001)
        .toList(growable: false);
    final costOfSalesLines = rows
        .where((row) => row.accountType == 'cost_of_sales')
        .map((row) => statementLine(row, row.debit - row.credit))
        .where((line) => line.amount.abs() > 0.0001)
        .toList(growable: false);
    final expenseLines = rows
        .where((row) => row.accountType == 'expense')
        .map((row) => statementLine(row, row.debit - row.credit))
        .where((line) => line.amount.abs() > 0.0001)
        .toList(growable: false);
    return IncomeStatementReport(
      revenue: _roundMoney(revenue),
      grossSales: _roundMoney(grossSales),
      salesReturns: _roundMoney(salesReturns),
      salesDiscounts: _roundMoney(salesDiscounts),
      netSales: _roundMoney(netSales),
      otherRevenue: _roundMoney(revenue - netSales),
      inventoryGain: _roundMoney(inventoryGain),
      cashOver: _roundMoney(cashOver),
      costOfGoodsSold: _roundMoney(cogs),
      inventoryLoss: _roundMoney(inventoryLoss),
      manufacturingWaste: _roundMoney(manufacturingWaste),
      manufacturingVariance: _roundMoney(manufacturingVariance),
      cashShort: _roundMoney(cashShort),
      grossProfit: _roundMoney(netSales - cogs),
      expenses: _roundMoney(expenses),
      netProfit: _roundMoney(revenue - cogs - expenses),
      otherRevenueLines: otherRevenueLines,
      costOfSalesLines: costOfSalesLines,
      expenseLines: expenseLines,
    );
  }

  static Future<BalanceSheetReport> balanceSheetReport({DateTime? asOf}) async {
    if (!isAvailable) {
      return const BalanceSheetReport(
        assets: 0,
        liabilities: 0,
        equity: 0,
        retainedEarnings: 0,
        liabilitiesAndEquity: 0,
        difference: 0,
      );
    }
    final rows = await _trialBalanceRows(to: asOf);
    double debitNet(String type) => rows
        .where((row) => row.accountType == type)
        .fold<double>(0, (sum, row) => sum + row.debit - row.credit);
    double creditNet(String type) => rows
        .where((row) => row.accountType == type)
        .fold<double>(0, (sum, row) => sum + row.credit - row.debit);
    final assets = debitNet('asset');
    final liabilities = creditNet('liability');
    final equity = creditNet('equity');
    final revenue = creditNet('revenue');
    final cogs = debitNet('cost_of_sales');
    final expenses = debitNet('expense');
    final netProfit = revenue - cogs - expenses;
    FinancialStatementAccountLine statementLine(
      TrialBalanceRowReport row,
      double amount,
    ) =>
        FinancialStatementAccountLine(
          accountId: row.accountId,
          accountCode: row.accountCode,
          accountName: row.accountName,
          accountType: row.accountType,
          accountSubtype: row.accountSubtype,
          amount: _roundMoney(amount),
        );
    bool isNonCurrentAsset(TrialBalanceRowReport row) {
      final subtype = row.accountSubtype.trim().toLowerCase();
      return subtype == 'fixed_assets' ||
          subtype.startsWith('fixed_') ||
          subtype == 'accumulated_depreciation';
    }
    bool isNonCurrentLiability(TrialBalanceRowReport row) {
      final subtype = row.accountSubtype.trim().toLowerCase();
      return subtype == 'long_term_loans' || subtype.startsWith('long_term_');
    }
    final currentAssetLines = rows
        .where((row) => row.accountType == 'asset' && !isNonCurrentAsset(row))
        .map((row) => statementLine(row, row.debit - row.credit))
        .where((line) => line.amount.abs() > 0.0001)
        .toList(growable: false);
    final nonCurrentAssetLines = rows
        .where((row) => row.accountType == 'asset' && isNonCurrentAsset(row))
        .map((row) => statementLine(row, row.debit - row.credit))
        .where((line) => line.amount.abs() > 0.0001)
        .toList(growable: false);
    final currentLiabilityLines = rows
        .where((row) =>
            row.accountType == 'liability' && !isNonCurrentLiability(row))
        .map((row) => statementLine(row, row.credit - row.debit))
        .where((line) => line.amount.abs() > 0.0001)
        .toList(growable: false);
    final nonCurrentLiabilityLines = rows
        .where((row) =>
            row.accountType == 'liability' && isNonCurrentLiability(row))
        .map((row) => statementLine(row, row.credit - row.debit))
        .where((line) => line.amount.abs() > 0.0001)
        .toList(growable: false);
    final equityLines = rows
        .where((row) => row.accountType == 'equity')
        .map((row) => statementLine(row, row.credit - row.debit))
        .where((line) => line.amount.abs() > 0.0001)
        .toList(growable: false);
    double sumLines(List<FinancialStatementAccountLine> lines) =>
        lines.fold<double>(0, (sum, line) => sum + line.amount);
    return BalanceSheetReport(
      assets: _roundMoney(assets),
      liabilities: _roundMoney(liabilities),
      equity: _roundMoney(equity),
      retainedEarnings: _roundMoney(netProfit),
      liabilitiesAndEquity: _roundMoney(liabilities + equity + netProfit),
      difference: _roundMoney(assets - liabilities - equity - netProfit),
      currentAssets: _roundMoney(sumLines(currentAssetLines)),
      nonCurrentAssets: _roundMoney(sumLines(nonCurrentAssetLines)),
      currentLiabilities: _roundMoney(sumLines(currentLiabilityLines)),
      nonCurrentLiabilities: _roundMoney(sumLines(nonCurrentLiabilityLines)),
      currentAssetLines: currentAssetLines,
      nonCurrentAssetLines: nonCurrentAssetLines,
      currentLiabilityLines: currentLiabilityLines,
      nonCurrentLiabilityLines: nonCurrentLiabilityLines,
      equityLines: equityLines,
    );
  }

  static Future<List<InventoryValuationRowReport>> inventoryValuationReport({
    VentioDriftDatabase? database,
  }) async {
    if (database == null && !isAvailable) {
      return const <InventoryValuationRowReport>[];
    }
    final db = database ?? _db;
    final rawAccount =
        await _resolveAccountRoleForDatabase(db, 'inventory_raw');
    final finishedAccount =
        await _resolveAccountRoleForDatabase(db, 'inventory_finished');
    final tradingAccount =
        await _resolveAccountRoleForDatabase(db, 'inventory_merchandise');
    final methodRow = await db.customSelect(
      "SELECT value FROM settings WHERE key = 'inventory_costing_method_v1' LIMIT 1",
    ).getSingleOrNull();
    final costingMethod =
        methodRow?.data['value']?.toString().trim().toLowerCase() ?? 'batch';
    final useBatch =
        costingMethod == 'batch' || costingMethod == 'unified_batch';

    if (useBatch) {
      final rows = await db.customSelect(r'''
        SELECT wi.product_id, p.name AS product_name, wi.warehouse_id,
               COALESCE(w.name, wi.warehouse_id) AS warehouse_name,
               wi.quantity,
               COALESCE(batch.batch_qty, 0) AS batch_qty,
               COALESCE(batch.batch_value, 0) AS batch_value,
               CASE
                 WHEN EXISTS (
                   SELECT 1 FROM bill_of_materials bom
                   WHERE bom.output_product_id = wi.product_id
                     AND bom.is_active = 1 AND bom.deleted_at = ''
                 ) THEN 'finished_goods'
                 WHEN EXISTS (
                   SELECT 1
                   FROM bill_of_materials_lines line
                   INNER JOIN bill_of_materials bom
                     ON bom.id = line.bill_of_material_id
                   WHERE line.product_id = wi.product_id
                     AND bom.is_active = 1 AND bom.deleted_at = ''
                 ) THEN 'raw_materials'
                 ELSE 'merchandise'
               END AS inventory_category
        FROM warehouse_inventory wi
        INNER JOIN products p ON p.id = wi.product_id AND p.deleted_at = ''
        LEFT JOIN warehouses w ON w.id = wi.warehouse_id AND w.deleted_at = ''
        LEFT JOIN (
          SELECT bb.store_id, bb.product_id, bb.warehouse_id,
                 SUM(bb.quantity) AS batch_qty,
                 SUM(bb.quantity * b.unit_cost) AS batch_value
          FROM inventory_batch_balances bb
          INNER JOIN inventory_batches b ON b.id = bb.batch_id
            AND b.product_id = bb.product_id AND b.store_id = bb.store_id
          GROUP BY bb.store_id, bb.product_id, bb.warehouse_id
        ) batch ON batch.store_id = wi.store_id
          AND batch.product_id = wi.product_id
          AND batch.warehouse_id = wi.warehouse_id
        WHERE ABS(wi.quantity) > 0.000001
        ORDER BY p.name, warehouse_name
      ''').get();
      return rows.map((row) {
        final quantity = _num(row.data['quantity']);
        final batchQuantity = _num(row.data['batch_qty']);
        final batchValue = _num(row.data['batch_value']);
        final unitCost = batchQuantity <= 0.000001
            ? 0.0
            : batchValue / batchQuantity;
        final category = row.data['inventory_category']?.toString() ??
            'merchandise';
        final accountId = switch (category) {
          'finished_goods' => finishedAccount,
          'raw_materials' => rawAccount,
          _ => tradingAccount,
        };
        return InventoryValuationRowReport(
          productId: row.data['product_id']?.toString() ?? '',
          productName: row.data['product_name']?.toString() ?? '',
          warehouseId: row.data['warehouse_id']?.toString() ?? '',
          warehouseName: row.data['warehouse_name']?.toString() ?? '',
          quantity: quantity,
          unitCost: _roundMoney(unitCost),
          totalValue: _roundMoney(batchValue),
          inventoryAccountId: accountId,
          inventoryCategory: category,
          fallbackInventoryAccountId: tradingAccount,
        );
      }).toList(growable: false);
    }

    // Legacy costing branches remain available only for explicit historical
    // regression/migration test stores. Production Phase 4 is locked to Batch.
    final useFifo = costingMethod == 'fifo';
    final rows = await db.customSelect(r'''
      SELECT wi.product_id, p.name AS product_name, wi.warehouse_id,
             COALESCE(w.name, wi.warehouse_id) AS warehouse_name, wi.quantity,
             CASE
               WHEN ? = 1 AND COALESCE(fifo.remaining_qty, 0) > 0
                 THEN fifo.remaining_value / fifo.remaining_qty
               WHEN COALESCE(pc.average_cost, 0) > 0 THEN pc.average_cost
               WHEN COALESCE(p.usd_cost, 0) > 0 THEN p.usd_cost
               ELSE COALESCE(p.cost, 0)
             END AS unit_cost,
             CASE
               WHEN EXISTS (
                 SELECT 1 FROM bill_of_materials bom
                 WHERE bom.output_product_id = wi.product_id
                   AND bom.is_active = 1 AND bom.deleted_at = ''
               ) THEN 'finished_goods'
               WHEN EXISTS (
                 SELECT 1
                 FROM bill_of_materials_lines line
                 INNER JOIN bill_of_materials bom
                   ON bom.id = line.bill_of_material_id
                 WHERE line.product_id = wi.product_id
                   AND bom.is_active = 1 AND bom.deleted_at = ''
               ) THEN 'raw_materials'
               ELSE 'merchandise'
             END AS inventory_category
      FROM warehouse_inventory wi
      INNER JOIN products p ON p.id = wi.product_id AND p.deleted_at = ''
      LEFT JOIN warehouses w ON w.id = wi.warehouse_id AND w.deleted_at = ''
      LEFT JOIN product_costs pc ON pc.product_id = wi.product_id
      LEFT JOIN (
        SELECT product_id,
               SUM(quantity_remaining) AS remaining_qty,
               SUM(quantity_remaining * unit_cost) AS remaining_value
        FROM inventory_cost_layers
        WHERE deleted_at = '' AND is_closed = 0 AND quantity_remaining > 0
        GROUP BY product_id
      ) fifo ON fifo.product_id = wi.product_id
      WHERE ABS(wi.quantity) > 0.000001
      ORDER BY p.name, warehouse_name
    ''', variables: <Variable<Object>>[
      Variable<int>(useFifo ? 1 : 0),
    ]).get();
    return rows.map((row) {
      final quantity = _num(row.data['quantity']);
      final unitCost = _num(row.data['unit_cost']);
      final category = row.data['inventory_category']?.toString() ??
          'merchandise';
      final accountId = switch (category) {
        'finished_goods' => finishedAccount,
        'raw_materials' => rawAccount,
        _ => tradingAccount,
      };
      return InventoryValuationRowReport(
        productId: row.data['product_id']?.toString() ?? '',
        productName: row.data['product_name']?.toString() ?? '',
        warehouseId: row.data['warehouse_id']?.toString() ?? '',
        warehouseName: row.data['warehouse_name']?.toString() ?? '',
        quantity: quantity,
        unitCost: _roundMoney(unitCost),
        totalValue: _roundMoney(quantity * unitCost),
        inventoryAccountId: accountId,
        inventoryCategory: category,
        fallbackInventoryAccountId: tradingAccount,
      );
    }).toList(growable: false);
  }

  static Future<List<ManufacturingOrderCostReport>>
      manufacturingOrderCostReport() async {
    if (!isAvailable) return const <ManufacturingOrderCostReport>[];
    final orders = await BusinessSqliteStore.readManufacturingOrders(_db);
    return orders
        .where((order) => !order.isDeleted && order.status != 'in_progress')
        .map((order) => ManufacturingOrderCostReport(
              orderId: order.id,
              orderNo: order.orderNo,
              outputProductId: order.outputProductId,
              outputProductName: order.outputProductName,
              outputQuantity: order.actualOutputQuantity > 0
                  ? order.actualOutputQuantity
                  : order.quantity,
              totalMaterialCost: order.totalMaterialCost,
              wasteValue: order.totalWasteCost,
              eligibleCost: order.totalEligibleCost,
              actualUnitCost: order.actualUnitCost,
              status: order.status,
              journalEntryId: order.journalEntryId,
              materialCosts: order.materialCosts,
            ))
        .toList(growable: false);
  }

  static Future<List<ManufacturingWasteReportRow>>
      manufacturingWasteReport() async {
    if (!isAvailable) return const <ManufacturingWasteReportRow>[];
    final orders = await BusinessSqliteStore.readManufacturingOrders(_db);
    return <ManufacturingWasteReportRow>[
      for (final order in orders)
        if (!order.isDeleted)
          for (final waste in order.wasteLines)
            ManufacturingWasteReportRow(
              orderId: order.id,
              orderNo: order.orderNo,
              productId: waste.productId,
              productName: waste.productName,
              quantity: waste.quantity,
              unitCost: waste.unitCost,
              value: waste.value,
              reason: waste.reason,
              status: order.status,
            ),
    ];
  }

  static Future<List<InventoryCountVarianceReportRow>>
      inventoryCountVarianceReport() async {
    if (!isAvailable) return const <InventoryCountVarianceReportRow>[];
    final rows = await _db.customSelect('''
      SELECT ic.id AS session_id, ic.count_no, ic.status,
             ic.journal_entry_id, ic.reversal_journal_entry_id,
             l.product_id, l.product_name, l.system_qty_at_approval,
             l.counted_qty, l.difference_qty, l.unit_cost,
             l.difference_value, l.stock_movement_id
      FROM inventory_counts ic
      INNER JOIN inventory_count_lines l ON l.inventory_count_id = ic.id
      WHERE ic.deleted_at = '' AND COALESCE(l.difference_qty, 0) != 0
      ORDER BY ic.document_date, ic.count_no, l.line_no
    ''').get();
    return rows
        .map((row) => InventoryCountVarianceReportRow.fromRow(row.data))
        .toList(growable: false);
  }

  static Future<List<CashBankMovementReport>> cashBankMovementReport() async {
    if (!isAvailable) return const <CashBankMovementReport>[];
    final accountIds = await _cashAndBankAccountIds(_db);
    if (accountIds.isEmpty) return <CashBankMovementReport>[];
    final placeholders = List.filled(accountIds.length, '?').join(',');
    final rows = await _db.customSelect(
      '''
      SELECT jl.account_id, jl.account_code, jl.account_name,
             COALESCE(SUM(jl.debit), 0) AS money_in,
             COALESCE(SUM(jl.credit), 0) AS money_out
      FROM journal_lines jl
      INNER JOIN journal_entries je ON je.id = jl.entry_id
      WHERE jl.account_id IN ($placeholders)
        AND je.deleted_at = ''
        AND je.status IN ('posted', 'reversed')
      GROUP BY jl.account_id, jl.account_code, jl.account_name
      ORDER BY jl.account_code
      ''',
      variables: <Variable<Object>>[
        for (final accountId in accountIds) Variable<String>(accountId),
      ],
    ).get();
    return rows.map((row) {
      final moneyIn = _num(row.data['money_in']);
      final moneyOut = _num(row.data['money_out']);
      return CashBankMovementReport(
        accountId: row.data['account_id']?.toString() ?? '',
        accountCode: row.data['account_code']?.toString() ?? '',
        accountName: row.data['account_name']?.toString() ?? '',
        moneyIn: _roundMoney(moneyIn),
        moneyOut: _roundMoney(moneyOut),
        closingBalance: _roundMoney(moneyIn - moneyOut),
      );
    }).toList();
  }

  static Future<CashFlowStatementReport> cashFlowStatementReport(
      {DateTime? from, DateTime? to}) async {
    if (!isAvailable) {
      final start = from ?? DateTime.now();
      return CashFlowStatementReport(
        operatingInflows: 0,
        operatingOutflows: 0,
        investingInflows: 0,
        investingOutflows: 0,
        financingInflows: 0,
        financingOutflows: 0,
        openingCash: 0,
        closingCash: 0,
        from: start,
        to: to ?? start,
      );
    }
    final cashAccountIds = await _cashAndBankAccountIds(_db);
    if (cashAccountIds.isEmpty) {
      return const CashFlowStatementReport(
        operatingInflows: 0,
        operatingOutflows: 0,
        investingInflows: 0,
        investingOutflows: 0,
        financingInflows: 0,
        financingOutflows: 0,
        openingCash: 0,
        closingCash: 0,
      );
    }

    final placeholders = List.filled(cashAccountIds.length, '?').join(',');
    final dateConditions = <String>[
      "je.deleted_at = ''",
      "je.status IN ('posted', 'reversed')"
    ];
    final dateVariables = <Variable<Object>>[];
    if (from != null) {
      dateConditions.add('datetime(je.entry_date) >= datetime(?)');
      dateVariables.add(Variable<String>(from.toUtc().toIso8601String()));
    }
    if (to != null) {
      dateConditions.add('datetime(je.entry_date) <= datetime(?)');
      dateVariables.add(Variable<String>(to.toUtc().toIso8601String()));
    }

    Future<double> cashBalanceBefore(DateTime? date) async {
      final conditions = <String>[
        "je.deleted_at = ''",
        "je.status IN ('posted', 'reversed')",
        'jl.account_id IN ($placeholders)'
      ];
      final variables = <Variable<Object>>[
        for (final id in cashAccountIds) Variable<String>(id),
      ];
      if (date != null) {
        conditions.add('datetime(je.entry_date) < datetime(?)');
        variables.add(Variable<String>(date.toUtc().toIso8601String()));
      }
      final row = await _db.customSelect(
        '''
        SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
        FROM journal_lines jl
        INNER JOIN journal_entries je ON je.id = jl.entry_id
        WHERE ${conditions.join(' AND ')}
        ''',
        variables: variables,
      ).getSingleOrNull();
      return _roundMoney(_num(row?.data['balance']));
    }

    // Fetch every line of an entry that touched cash. Fetching only the cash
    // line makes it impossible to classify the flow by the counterpart account.
    final entryRows = await _db.customSelect(
      '''
      SELECT je.id AS entry_id, je.entry_no, je.entry_date,
             je.reference_type, je.reference_no, je.description,
             jl.account_id, jl.account_code, jl.account_name,
             jl.debit, jl.credit, a.type AS account_type,
             a.subtype AS account_subtype, jl.line_no
      FROM journal_entries je
      INNER JOIN journal_lines jl ON jl.entry_id = je.id
      LEFT JOIN accounts a ON a.id = jl.account_id
      WHERE je.id IN (
        SELECT DISTINCT cash_line.entry_id
        FROM journal_lines cash_line
        WHERE cash_line.account_id IN ($placeholders)
      )
        AND ${dateConditions.join(' AND ')}
      ORDER BY je.entry_date, je.entry_no, jl.line_no
      ''',
      variables: <Variable<Object>>[
        for (final id in cashAccountIds) Variable<String>(id),
        ...dateVariables,
      ],
    ).get();

    final rows = <CashFlowStatementLineReport>[];
    var operatingInflows = 0.0;
    var operatingOutflows = 0.0;
    var investingInflows = 0.0;
    var investingOutflows = 0.0;
    var financingInflows = 0.0;
    var financingOutflows = 0.0;
    var hasCurrentEntry = false;
    String currentEntryId = '';
    String currentEntryNo = '';
    DateTime currentEntryDate = DateTime.fromMillisecondsSinceEpoch(0);
    String currentReferenceType = '';
    String currentReferenceNo = '';
    String currentDescription = '';
    double cashMovement = 0.0;
    final nonCashTypes = <String>{};
    final nonCashSubtypes = <String>{};

    void flushCurrentEntry() {
      if (!hasCurrentEntry || cashMovement.abs() < 0.005) return;
      final category = _cashFlowCategory(
        currentReferenceType,
        nonCashTypes,
        nonCashSubtypes,
      );
      final amount = _roundMoney(cashMovement.abs());
      if (category == CashFlowCategory.investing) {
        if (cashMovement >= 0) {
          investingInflows += amount;
        } else {
          investingOutflows += amount;
        }
      } else if (category == CashFlowCategory.financing) {
        if (cashMovement >= 0) {
          financingInflows += amount;
        } else {
          financingOutflows += amount;
        }
      } else {
        if (cashMovement >= 0) {
          operatingInflows += amount;
        } else {
          operatingOutflows += amount;
        }
      }
      rows.add(CashFlowStatementLineReport(
        entryNo: currentEntryNo,
        entryDate: currentEntryDate,
        referenceType: currentReferenceType,
        referenceNo: currentReferenceNo,
        description: currentDescription,
        category: category,
        inflow: cashMovement >= 0 ? amount : 0,
        outflow: cashMovement < 0 ? amount : 0,
        netCashFlow: _roundMoney(cashMovement),
      ));
    }

    for (final entryRow in entryRows) {
      final nextEntryId = entryRow.data['entry_id']?.toString() ?? '';
      if (nextEntryId != currentEntryId) {
        flushCurrentEntry();
        hasCurrentEntry = true;
        currentEntryId = nextEntryId;
        currentEntryNo = entryRow.data['entry_no']?.toString() ?? '';
        currentEntryDate = _parseDate(entryRow.data['entry_date']);
        currentReferenceType =
            entryRow.data['reference_type']?.toString() ?? '';
        currentReferenceNo = entryRow.data['reference_no']?.toString() ?? '';
        currentDescription = entryRow.data['description']?.toString() ?? '';
        cashMovement = 0;
        nonCashTypes.clear();
        nonCashSubtypes.clear();
      }
      final accountId = entryRow.data['account_id']?.toString() ?? '';
      final debit = _num(entryRow.data['debit']);
      final credit = _num(entryRow.data['credit']);
      if (cashAccountIds.contains(accountId)) {
        cashMovement += debit - credit;
      } else {
        final type = entryRow.data['account_type']?.toString() ?? '';
        final subtype = entryRow.data['account_subtype']?.toString() ?? '';
        if (type.isNotEmpty) nonCashTypes.add(type);
        if (subtype.isNotEmpty) nonCashSubtypes.add(subtype);
      }
    }

    flushCurrentEntry();

    final openingCash = from == null ? 0.0 : await cashBalanceBefore(from);
    final netChange = operatingInflows -
        operatingOutflows +
        investingInflows -
        investingOutflows +
        financingInflows -
        financingOutflows;
    return CashFlowStatementReport(
      operatingInflows: _roundMoney(operatingInflows),
      operatingOutflows: _roundMoney(operatingOutflows),
      investingInflows: _roundMoney(investingInflows),
      investingOutflows: _roundMoney(investingOutflows),
      financingInflows: _roundMoney(financingInflows),
      financingOutflows: _roundMoney(financingOutflows),
      openingCash: _roundMoney(openingCash),
      closingCash: _roundMoney(openingCash + netChange),
      from: from,
      to: to,
      lines: rows,
    );
  }

  static CashFlowCategory _cashFlowCategory(
    String referenceType,
    Set<String> accountTypes,
    Set<String> accountSubtypes,
  ) {
    final ref = referenceType.toLowerCase();
    if (ref.contains('fixed_asset') || ref.contains('investment')) {
      return CashFlowCategory.investing;
    }
    if (ref.contains('capital') ||
        ref.contains('loan') ||
        ref.contains('owner') ||
        ref.contains('equity')) {
      return CashFlowCategory.financing;
    }

    const investingSubtypes = <String>{
      'fixed_assets',
      'fixed_equipment',
      'fixed_furniture',
      'fixed_computers',
      'fixed_vehicles',
      'fixed_other',
      'investment',
      'investments',
    };
    const financingSubtypes = <String>{
      'capital',
      'owner_current',
      'owner_drawings',
      'short_term_loans',
      'long_term_loans',
    };
    if (accountSubtypes.any(investingSubtypes.contains)) {
      return CashFlowCategory.investing;
    }
    if (accountSubtypes.any(financingSubtypes.contains)) {
      return CashFlowCategory.financing;
    }
    if (accountTypes.contains('equity')) {
      return CashFlowCategory.financing;
    }

    // Receivables/payables, inventory, taxes, revenue and expenses are
    // operating even though some are asset/liability accounts.
    return CashFlowCategory.operating;
  }

  static Future<TaxReport> taxReport({DateTime? from, DateTime? to}) async {
    if (!isAvailable) {
      return const TaxReport(
        outputTax: 0,
        inputTax: 0,
        netTaxPayable: 0,
        payableAccountMovement: 0,
      );
    }
    final salesTaxAccountId = await resolveAccountRole('sales_tax');
    final purchaseTaxAccountId = await resolveAccountRole('purchase_tax');
    final payableAccountId = await resolveAccountRole('tax_payable');
    final conditions = <String>[
      "je.deleted_at = ''",
      "je.status IN ('posted', 'reversed')"
    ];
    final variables = <Variable<Object>>[];
    if (from != null) {
      conditions.add('datetime(je.entry_date) >= datetime(?)');
      variables.add(Variable<String>(from.toUtc().toIso8601String()));
    }
    if (to != null) {
      conditions.add('datetime(je.entry_date) <= datetime(?)');
      variables.add(Variable<String>(to.toUtc().toIso8601String()));
    }
    Future<double> sumAccount(String accountId, String expression) async {
      if (accountId.trim().isEmpty) return 0;
      final row = await _db.customSelect(
        '''
        SELECT COALESCE(SUM($expression), 0) AS amount
        FROM journal_lines jl
        INNER JOIN journal_entries je ON je.id = jl.entry_id
        WHERE jl.account_id = ? AND ${conditions.join(' AND ')}
        ''',
        variables: <Variable<Object>>[
          Variable<String>(accountId),
          ...variables,
        ],
      ).getSingleOrNull();
      return _roundMoney(_num(row?.data['amount']));
    }

    final outputTax =
        await sumAccount(salesTaxAccountId, 'jl.credit - jl.debit');
    final inputTax =
        await sumAccount(purchaseTaxAccountId, 'jl.debit - jl.credit');
    final payableMovement = payableAccountId.trim().isEmpty
        ? outputTax - inputTax
        : await sumAccount(payableAccountId, 'jl.credit - jl.debit');
    return TaxReport(
      outputTax: _roundMoney(outputTax),
      inputTax: _roundMoney(inputTax),
      netTaxPayable: _roundMoney(outputTax - inputTax),
      payableAccountMovement: _roundMoney(payableMovement),
      from: from,
      to: to,
    );
  }

  static Future<List<AdvancedAccountingItem>> listPaymentAccounts() async {
    if (!isAvailable) return const <AdvancedAccountingItem>[];
    final rows = await _db.customSelect(
      '''
      SELECT pa.id, pa.name, pa.type, pa.account_id, a.code AS account_code,
             a.name AS account_name, pa.is_default, pa.is_active, pa.notes
      FROM payment_accounts pa
      LEFT JOIN accounts a ON a.id = pa.account_id
      WHERE pa.deleted_at = ''
      ORDER BY pa.type, pa.name
      ''',
    ).get();
    return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
  }

  static Future<List<AdvancedAccountingItem>> listActiveCashLocations({
    bool includeBank = true,
  }) async {
    if (!isAvailable) return const <AdvancedAccountingItem>[];
    final typeFilter = includeBank ? '' : "AND cl.type <> 'bank'";
    final rows = await _db.customSelect(
      '''
      SELECT cl.id, cl.name, cl.type, cl.is_default, cl.is_active, cl.current_balance AS balance,
             cl.notes, a.code AS account_code, a.name AS account_name,
             parent.name AS status, cl.device_id AS reference_id
      FROM cash_locations cl
      LEFT JOIN accounts a ON a.id = cl.account_id
      LEFT JOIN cash_locations parent ON parent.id = cl.parent_id
      WHERE cl.deleted_at = '' AND cl.is_active = 1 $typeFilter
      ORDER BY cl.type, cl.code, cl.name
      ''',
    ).get();
    return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
  }

  static Future<bool> hasOpenCashDrawerForDevice(
      {required String deviceId, String branchId = ''}) async {
    if (!isAvailable) return true;
    final drawer = await _openCashDrawerLocationForDevice(
        deviceId: deviceId, branchId: branchId);
    return drawer != null;
  }

  /// Returns the cash drawer assigned to [deviceId] regardless of whether a
  /// drawer session is currently open. Session state is queried separately.
  ///
  /// This distinction is important after closing a shift: the physical drawer
  /// remains assigned to the device and must still be available to open the
  /// next shift.
  static Future<AdvancedAccountingItem?> currentCashDrawerForDevice({
    required String deviceId,
    String branchId = '',
  }) async {
    if (!isAvailable) return null;
    final cleanDeviceId = deviceId.trim();
    if (cleanDeviceId.isEmpty) return null;
    final branchFilter = branchId.trim().isEmpty
        ? ''
        : "AND (cl.branch_id = ? OR cl.branch_id = '')";
    final row = await _db.customSelect(
      '''
      SELECT cl.id, cl.name, cl.type, cl.is_default, cl.is_active,
             cl.current_balance AS balance, cl.notes,
             a.code AS account_code, a.name AS account_name,
             parent.name AS status, cl.device_id AS reference_id
      FROM cash_locations cl
      LEFT JOIN accounts a ON a.id = cl.account_id
      LEFT JOIN cash_locations parent ON parent.id = cl.parent_id
      WHERE cl.deleted_at = ''
        AND cl.is_active = 1
        AND cl.type = 'cash_drawer'
        AND cl.device_id = ?
        $branchFilter
      ORDER BY cl.is_default DESC, cl.code, cl.name
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(cleanDeviceId),
        if (branchId.trim().isNotEmpty) Variable<String>(branchId.trim()),
      ],
    ).getSingleOrNull();
    return row == null ? null : AdvancedAccountingItem.fromRow(row.data);
  }

  static Future<bool> hasOpenCashDrawer(
      {String branchId = '', String cashLocationId = ''}) async {
    if (!isAvailable) return false;
    final locationFilter =
        cashLocationId.trim().isEmpty ? '' : 'AND cash_location_id = ?';
    final branchFilter = branchId.trim().isEmpty ? '' : 'AND branch_id = ?';
    final row = await _db.customSelect(
      '''
      SELECT id
      FROM cash_drawer_sessions
      WHERE status = 'open' $locationFilter $branchFilter
      ORDER BY opened_at DESC
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        if (cashLocationId.trim().isNotEmpty)
          Variable<String>(cashLocationId.trim()),
        if (branchId.trim().isNotEmpty) Variable<String>(branchId.trim()),
      ],
    ).getSingleOrNull();
    return row != null;
  }

  static Future<String> currentOpenCashDrawerSessionId(
      {String branchId = '', String cashLocationId = ''}) async {
    if (!isAvailable) return '';
    final locationFilter =
        cashLocationId.trim().isEmpty ? '' : 'AND cash_location_id = ?';
    final branchFilter = branchId.trim().isEmpty ? '' : 'AND branch_id = ?';
    final row = await _db.customSelect(
      '''
      SELECT id
      FROM cash_drawer_sessions
      WHERE status = 'open' $locationFilter $branchFilter
      ORDER BY opened_at DESC
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        if (cashLocationId.trim().isNotEmpty)
          Variable<String>(cashLocationId.trim()),
        if (branchId.trim().isNotEmpty) Variable<String>(branchId.trim()),
      ],
    ).getSingleOrNull();
    return row?.data['id']?.toString() ?? '';
  }

  static Future<List<AdvancedAccountingItem>> listCashLocations() async {
    if (!isAvailable) return const <AdvancedAccountingItem>[];
    final rows = await _db.customSelect(
      '''
      SELECT cl.id, cl.name, cl.type, cl.is_default, cl.is_active, cl.current_balance AS balance,
             cl.notes, a.code AS account_code, a.name AS account_name,
             parent.name AS status, cl.device_id AS reference_id
      FROM cash_locations cl
      LEFT JOIN accounts a ON a.id = cl.account_id
      LEFT JOIN cash_locations parent ON parent.id = cl.parent_id
      WHERE cl.deleted_at = ''
      ORDER BY cl.type, cl.code, cl.name
      ''',
    ).get();
    return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
  }

  static Future<List<AdvancedAccountingItem>> listCashTransfers() async {
    if (!isAvailable) return const <AdvancedAccountingItem>[];
    final rows = await _db.customSelect(
      '''
      SELECT ct.id, ct.transfer_no AS name, ct.status AS type, ct.status,
             from_loc.name AS account_code, to_loc.name AS account_name,
             ct.amount AS balance, ct.notes
      FROM cash_transfers ct
      LEFT JOIN cash_locations from_loc ON from_loc.id = ct.from_location_id
      LEFT JOIN cash_locations to_loc ON to_loc.id = ct.to_location_id
      WHERE ct.deleted_at = ''
      ORDER BY ct.transfer_date DESC
      LIMIT 50
      ''',
    ).get();
    return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
  }

  static Future<List<CashShiftReportSession>> listClosedCashDrawerSessions(
      {int limit = 200}) async {
    if (!isAvailable) return const <CashShiftReportSession>[];
    final rows = await _db.customSelect(
      '''
      SELECT cds.id, cds.drawer_no, cds.cash_location_id,
             COALESCE(cl.name, '') AS cash_location_name,
             cds.opened_at, cds.closed_at, cds.opening_balance,
             cds.expected_cash, cds.counted_cash, cds.difference,
             cds.notes, cds.opened_by, cds.closed_by, cds.branch_id
      FROM cash_drawer_sessions cds
      LEFT JOIN cash_locations cl ON cl.id = cds.cash_location_id
      WHERE cds.status = 'closed'
      ORDER BY cds.closed_at DESC, cds.opened_at DESC
      LIMIT ?
      ''',
      variables: <Variable<Object>>[
        Variable<int>(limit.clamp(1, 1000).toInt())
      ],
    ).get();
    return rows
        .map((row) => CashShiftReportSession.fromRow(row.data))
        .toList(growable: false);
  }

  static Future<List<AdvancedAccountingItem>> listCashDrawers() async {
    if (!isAvailable) return const <AdvancedAccountingItem>[];
    final rows = await _db.customSelect(
      '''
      SELECT cds.id, cds.drawer_no AS name, cds.status AS type, cds.status,
             COALESCE(cl.name, cds.opened_at) AS account_name,
             cds.cash_location_id AS reference_id,
             opening_balance AS debit, expected_cash AS credit,
             difference AS balance,
             (CASE WHEN cds.opened_by <> '' THEN 'فتحها: ' || cds.opened_by ELSE '' END ||
              CASE WHEN cds.closed_by <> '' THEN CASE WHEN cds.opened_by <> '' THEN ' • ' ELSE '' END || 'أغلقها: ' || cds.closed_by ELSE '' END ||
              CASE WHEN cds.notes <> '' THEN CASE WHEN cds.opened_by <> '' OR cds.closed_by <> '' THEN ' • ' ELSE '' END || cds.notes ELSE '' END) AS notes
      FROM cash_drawer_sessions cds
      LEFT JOIN cash_locations cl ON cl.id = cds.cash_location_id
      ORDER BY opened_at DESC
      LIMIT 50
      ''',
    ).get();
    return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
  }

  static Future<List<AdvancedAccountingItem>> listCashBalancesReport() async {
    if (!isAvailable) return const <AdvancedAccountingItem>[];
    final rows = await _db.customSelect(
      '''
      SELECT cl.id, cl.name, cl.type, cl.is_default, cl.is_active,
             cl.current_balance AS balance,
             a.code AS account_code, a.name AS account_name,
             parent.name AS status,
             ('الكود: ' || cl.code ||
              CASE WHEN cl.branch_id <> '' THEN ' • الفرع: ' || cl.branch_id ELSE '' END ||
              CASE WHEN parent.name IS NOT NULL THEN ' • تابع لـ: ' || parent.name ELSE '' END ||
              CASE WHEN cl.notes <> '' THEN ' • ' || cl.notes ELSE '' END) AS notes
      FROM cash_locations cl
      LEFT JOIN accounts a ON a.id = cl.account_id
      LEFT JOIN cash_locations parent ON parent.id = cl.parent_id
      WHERE cl.deleted_at = ''
      ORDER BY cl.type, cl.code, cl.name
      ''',
    ).get();
    return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
  }

  static Future<List<AdvancedAccountingItem>>
      listOpenCashDrawersReport() async {
    if (!isAvailable) return const <AdvancedAccountingItem>[];
    final rows = await _db.customSelect(
      '''
      SELECT cds.id,
             cds.drawer_no AS name,
             'open' AS type,
             cds.status,
             cl.name AS account_name,
             cds.cash_location_id AS reference_id,
             cds.opening_balance AS debit,
             ROUND(
               cds.opening_balance + COALESCE((
                 SELECT SUM(CASE WHEN clt.direction = 'in' THEN clt.amount ELSE -clt.amount END)
                 FROM cash_ledger_transactions clt
                 WHERE clt.cash_drawer_session_id = cds.id AND clt.deleted_at = ''
               ), 0),
               2
             ) AS credit,
             COALESCE(cl.current_balance, cds.expected_cash) AS balance,
             ('افتتحت: ' || cds.opened_at ||
              CASE WHEN cds.opened_by <> '' THEN ' • بواسطة: ' || cds.opened_by ELSE '' END ||
              CASE WHEN cds.opened_by_user_id <> '' THEN ' • معرف المستخدم: ' || cds.opened_by_user_id ELSE '' END ||
              CASE WHEN cds.branch_id <> '' THEN ' • الفرع: ' || cds.branch_id ELSE '' END ||
              CASE WHEN cds.notes <> '' THEN ' • ' || cds.notes ELSE '' END) AS notes
      FROM cash_drawer_sessions cds
      LEFT JOIN cash_locations cl ON cl.id = cds.cash_location_id
      WHERE cds.status = 'open'
      ORDER BY cds.opened_at DESC
      ''',
    ).get();
    return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
  }

  static Future<List<AdvancedAccountingItem>> listCashDrawerVarianceReport(
      {int limit = 100}) async {
    if (!isAvailable) return const <AdvancedAccountingItem>[];
    final rows = await _db.customSelect(
      '''
      SELECT cds.id,
             cds.drawer_no AS name,
             CASE
               WHEN ROUND(cds.difference, 2) > 0 THEN 'overage'
               WHEN ROUND(cds.difference, 2) < 0 THEN 'shortage'
               ELSE 'balanced'
             END AS type,
             cds.status,
             cl.name AS account_name,
             cds.expected_cash AS debit,
             cds.counted_cash AS credit,
             cds.difference AS balance,
             ('افتتحت: ' || cds.opened_at ||
              CASE WHEN cds.closed_at <> '' THEN ' • أغلقت: ' || cds.closed_at ELSE '' END ||
              CASE WHEN cds.opened_by <> '' THEN ' • فتحها: ' || cds.opened_by ELSE '' END ||
              CASE WHEN cds.closed_by <> '' THEN ' • أغلقها: ' || cds.closed_by ELSE '' END ||
              CASE WHEN cds.opened_by_user_id <> '' THEN ' • مستخدم الفتح: ' || cds.opened_by_user_id ELSE '' END ||
              CASE WHEN cds.closed_by_user_id <> '' THEN ' • مستخدم الإغلاق: ' || cds.closed_by_user_id ELSE '' END ||
              CASE WHEN cds.notes <> '' THEN ' • ' || cds.notes ELSE '' END) AS notes
      FROM cash_drawer_sessions cds
      LEFT JOIN cash_locations cl ON cl.id = cds.cash_location_id
      WHERE cds.status = 'closed'
      ORDER BY ABS(cds.difference) DESC, cds.closed_at DESC
      LIMIT ?
      ''',
      variables: <Variable<Object>>[Variable<int>(limit)],
    ).get();
    return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
  }

  static Future<List<AdvancedAccountingItem>> listCashTransferAuditReport(
      {int limit = 100}) async {
    if (!isAvailable) return const <AdvancedAccountingItem>[];
    final rows = await _db.customSelect(
      '''
      SELECT ct.id,
             ct.transfer_no AS name,
             ct.status AS type,
             ct.status,
             from_loc.name AS account_code,
             to_loc.name AS account_name,
             ct.amount AS balance,
             ct.journal_entry_id AS reference_id,
             ('التاريخ: ' || ct.transfer_date ||
              CASE WHEN ct.created_by <> '' THEN ' • أنشأها: ' || ct.created_by ELSE '' END ||
              CASE WHEN ct.approved_by <> '' THEN ' • اعتمدها: ' || ct.approved_by ELSE '' END ||
              CASE WHEN ct.journal_entry_id <> '' THEN ' • قيد: ' || ct.journal_entry_id ELSE '' END ||
              CASE WHEN ct.notes <> '' THEN ' • ' || ct.notes ELSE '' END) AS notes
      FROM cash_transfers ct
      LEFT JOIN cash_locations from_loc ON from_loc.id = ct.from_location_id
      LEFT JOIN cash_locations to_loc ON to_loc.id = ct.to_location_id
      WHERE ct.deleted_at = ''
      ORDER BY ct.transfer_date DESC
      LIMIT ?
      ''',
      variables: <Variable<Object>>[Variable<int>(limit)],
    ).get();
    return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
  }

  static Future<double> calculateCashDrawerExpectedCash(
      String sessionId) async {
    if (!isAvailable) return 0.0;
    final row = await _db.customSelect(
      """
      SELECT opening_balance
      FROM cash_drawer_sessions
      WHERE id = ? AND status = 'open'
      LIMIT 1
      """,
      variables: <Variable<Object>>[Variable<String>(sessionId)],
    ).getSingleOrNull();
    if (row == null) return 0;
    final openingBalance = _roundMoney(_num(row.data['opening_balance']));
    final movement =
        await CashLedgerService(_db).movementTotalForSession(sessionId);
    return _roundMoney(openingBalance + movement);
  }

  static Future<List<AdvancedAccountingItem>> listCheques() async {
    if (!isAvailable) return const <AdvancedAccountingItem>[];
    final rows = await _db.customSelect(
      '''
      SELECT id, cheque_no AS name, direction AS type, party_name AS account_name,
             amount AS balance, status, due_date AS notes
      FROM cheques
      ORDER BY due_date ASC, created_at DESC
      LIMIT 100
      ''',
    ).get();
    return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
  }

  static Future<List<AdvancedAccountingItem>> listAccountingPeriods() async {
    if (!isAvailable) return const <AdvancedAccountingItem>[];
    final rows = await _db.customSelect(
      '''
      SELECT id, name, status AS type, start_date AS account_code,
             end_date AS account_name, notes
      FROM accounting_periods
      ORDER BY start_date DESC
      LIMIT 50
      ''',
    ).get();
    return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
  }

  static Future<List<AdvancedAccountingItem>> listCostCenters() async {
    if (!isAvailable) return const <AdvancedAccountingItem>[];
    final rows = await _db.customSelect(
      '''
      SELECT id, name, code AS account_code, is_active, notes
      FROM cost_centers
      WHERE deleted_at = ''
      ORDER BY code
      ''',
    ).get();
    return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
  }

  static Future<List<AdvancedAccountingItem>> listAccountingBranches() async {
    if (!isAvailable) return const <AdvancedAccountingItem>[];
    final rows = await _db.customSelect(
      '''
      SELECT id, name, code AS account_code, is_active, notes
      FROM accounting_branches
      WHERE deleted_at = ''
      ORDER BY code
      ''',
    ).get();
    return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
  }

  static Future<List<AdvancedAccountingItem>> listGeneralLedgerBranches() async {
    if (!isAvailable) return const <AdvancedAccountingItem>[];
    final rows = await _db.customSelect(
      r'''
      SELECT DISTINCT
             je.branch_id AS id,
             COALESCE(
               (SELECT ab.name
                FROM accounting_branches ab
                WHERE ab.deleted_at = ''
                  AND (ab.id = je.branch_id OR UPPER(ab.code) = UPPER(je.branch_id))
                LIMIT 1),
               je.branch_id
             ) AS name,
             COALESCE(
               (SELECT ab.code
                FROM accounting_branches ab
                WHERE ab.deleted_at = ''
                  AND (ab.id = je.branch_id OR UPPER(ab.code) = UPPER(je.branch_id))
                LIMIT 1),
               je.branch_id
             ) AS account_code,
             1 AS is_active,
             '' AS notes
      FROM journal_entries je
      WHERE je.deleted_at = '' AND je.branch_id <> ''
      ORDER BY account_code
      ''',
    ).get();
    return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
  }

  static Future<List<AdvancedAccountingItem>> listFixedAssets() async {
    if (!isAvailable) return const <AdvancedAccountingItem>[];
    final rows = await _db.customSelect(
      '''
      SELECT fa.id, fa.name, fa.category AS type, fa.status,
             fa.code AS account_code, a.name AS account_name,
             ROUND(fa.purchase_value - COALESCE(dep.accumulated, 0), 2) AS balance,
             ('التكلفة: ' || ROUND(fa.purchase_value, 2) ||
              ' • مجمع الإهلاك: ' || ROUND(COALESCE(dep.accumulated, 0), 2) ||
              ' • القيمة الدفترية: ' || ROUND(fa.purchase_value - COALESCE(dep.accumulated, 0), 2) ||
              ' • تاريخ الاقتناء: ' || fa.acquisition_date ||
              CASE WHEN fa.useful_life_months > 0 THEN ' • العمر الإنتاجي: ' || fa.useful_life_months || ' شهر' ELSE '' END ||
              CASE WHEN fa.useful_life_months > 0 THEN ' • الإهلاك الشهري: ' || ROUND(fa.purchase_value / fa.useful_life_months, 2) ELSE '' END ||
              CASE WHEN fa.notes <> '' THEN ' • ' || fa.notes ELSE '' END) AS notes
      FROM fixed_assets fa
      LEFT JOIN accounts a ON a.id = fa.asset_account_id
      LEFT JOIN (
        SELECT asset_id, SUM(amount) AS accumulated
        FROM fixed_asset_depreciation
        WHERE deleted_at = ''
        GROUP BY asset_id
      ) dep ON dep.asset_id = fa.id
      WHERE fa.deleted_at = ''
      ORDER BY fa.acquisition_date DESC, fa.code
      LIMIT 200
      ''',
    ).get();
    return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
  }

  static Future<void> createFixedAsset({
    required String code,
    required String name,
    required String category,
    required DateTime acquisitionDate,
    required double purchaseValue,
    int usefulLifeMonths = 0,
    String assetAccountId = '',
    String paymentAccountId = '',
    String notes = '',
    String createdBy = '',
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
    final paymentAccount = paymentAccountId.trim().isNotEmpty
        ? paymentAccountId.trim()
        : _requiredAccount(accounts, 'default_cash_account_id');
    await _accountSnapshot(_db, fixedAssetAccountId);
    await _accountSnapshot(_db, paymentAccount);

    final now = DateTime.now().toUtc().toIso8601String();
    final assetId = _newId('asset');
    final normalizedCode = code.trim().isEmpty
        ? 'FA-${DateTime.now().millisecondsSinceEpoch}'
        : code.trim().toUpperCase();
    final normalizedName = name.trim().isEmpty ? 'أصل ثابت' : name.trim();

    await _db.transaction(() async {
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
              accountId: paymentAccount,
              debit: 0,
              credit: amount,
              memo: 'دفعة أصل ثابت $normalizedCode',
            ),
          ],
        ),
        database: _db,
        withinExistingTransaction: true,
      );
      if (entryId.isEmpty) {
        throw StateError('Fixed asset journal entry was not persisted.');
      }
      await _writeAuditLogInTransaction(
        _db,
        action: 'create_fixed_asset',
        entityType: 'fixed_asset',
        entityId: assetId,
        referenceType: 'fixed_asset',
        referenceId: assetId,
        details: '$normalizedCode - $normalizedName',
        createdBy: createdBy,
        storeId: storeId,
        branchId: branchId,
        createdAt: now,
      );
    });

    _notifyMutation();
  }

  static Future<int> runDepreciationForAsset({
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

  static Future<int> runDepreciationForAllAssets({
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

  static Future<int> _runDepreciationForAssetRow(
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
        DateTime.tryParse(asset['acquisition_date']?.toString() ?? '')
            ?.toLocal();
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
    final accumulatedAccount = _requiredAccount(
        accounts, 'default_accumulated_depreciation_account_id');
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
          remaining < monthly || i == usefulLifeMonths - 1
              ? remaining
              : monthly);
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

  static Future<void> createManualJournalEntry({
    required DateTime entryDate,
    required String description,
    required List<JournalLineDraft> lines,
    String createdBy = '',
    String storeId = '',
    String branchId = '',
  }) async {
    if (!isAvailable) return;
    await createPostedEntry(JournalEntryDraft(
      entryDate: entryDate,
      referenceType: 'manual_journal',
      referenceId: _newId('manual'),
      referenceNo: 'يدوي',
      description:
          description.trim().isEmpty ? 'قيد يومية يدوي' : description.trim(),
      source: 'manual',
      createdBy: createdBy,
      storeId: storeId,
      branchId: branchId,
      lines: lines,
    ));
    _notifyMutation();
  }


  /// Safely edits an already-posted manual journal. System-generated journal
  /// entries are intentionally excluded: they must be edited from their
  /// owning business document so operational and accounting state stay aligned.
  ///
  /// Manual journals do not have a separate document table/version column, so
  /// the currently-active journal entry id is the optimistic concurrency token.
  /// Each successful edit reverses the active family member and posts a new
  /// append-only member using `<base>:manual_edit:vN`.
  static Future<String> editManualJournalEntry({
    required String activeEntryId,
    required DateTime entryDate,
    required String description,
    required List<JournalLineDraft> lines,
    String createdBy = '',
    String branchId = '',
  }) async {
    if (!isAvailable) return '';
    final normalizedEntryId = activeEntryId.trim();
    if (normalizedEntryId.isEmpty) {
      throw ArgumentError.value(activeEntryId, 'activeEntryId');
    }
    _validateBalancedDraft(JournalEntryDraft(
      entryDate: entryDate,
      description: description,
      lines: lines,
    ));

    final db = _db;
    var nextReferenceId = '';
    var createdEntryId = '';
    var selectedStoreId = '';

    Future<JournalEntryDetailsReport> loadSelected() async {
      final entryRow = await db.customSelect(
        '''
        SELECT je.id, je.entry_no, je.entry_date, je.reference_type,
               je.reference_id, je.reference_no, je.description, je.status,
               je.source, je.created_by, je.store_id, je.branch_id, je.reversed_entry_id,
               je.reversed_by_entry_id, je.reversal_reason, je.posted_at,
               je.reversed_at, je.reversed_by
        FROM journal_entries je
        WHERE je.id = ? AND je.deleted_at = ''
        LIMIT 1
        ''',
        variables: <Variable<Object>>[Variable<String>(normalizedEntryId)],
      ).getSingleOrNull();
      if (entryRow == null) {
        throw StateError('Manual journal entry was not found.');
      }
      final data = entryRow.data;
      selectedStoreId = data['store_id']?.toString() ?? '';
      final lineRows = await db.customSelect(
        '''
        SELECT line_no, account_id, account_code, account_name, debit, credit,
               memo, party_type, party_id, party_name, cost_center_id
        FROM journal_lines
        WHERE entry_id = ?
        ORDER BY line_no
        ''',
        variables: <Variable<Object>>[Variable<String>(normalizedEntryId)],
      ).get();
      return JournalEntryDetailsReport(
        id: normalizedEntryId,
        entryNo: data['entry_no']?.toString() ?? '',
        entryDate: _parseDate(data['entry_date']),
        referenceType: data['reference_type']?.toString() ?? '',
        referenceId: data['reference_id']?.toString() ?? '',
        referenceNo: data['reference_no']?.toString() ?? '',
        description: data['description']?.toString() ?? '',
        status: data['status']?.toString() ?? '',
        source: data['source']?.toString() ?? '',
        createdBy: data['created_by']?.toString() ?? '',
        branchId: data['branch_id']?.toString() ?? '',
        reversedEntryId: data['reversed_entry_id']?.toString() ?? '',
        reversedByEntryId: data['reversed_by_entry_id']?.toString() ?? '',
        reversalReason: data['reversal_reason']?.toString() ?? '',
        postedAt: DateTime.tryParse(data['posted_at']?.toString() ?? ''),
        reversedAt: DateTime.tryParse(data['reversed_at']?.toString() ?? ''),
        reversedBy: data['reversed_by']?.toString() ?? '',
        lines: lineRows
            .map((row) => JournalEntryDetailLineReport.fromRow(row.data))
            .toList(growable: false),
      );
    }

    String baseReference(String referenceId) {
      return referenceId.trim().replaceFirst(
            RegExp(r':manual_edit:v\d+$'),
            '',
          );
    }

    final selected = await db.transaction(() async {
      return PostedDocumentEditPipeline<JournalEntryDetailsReport>(
        loadAuthoritative: loadSelected,
        validatePermission: (current) async {
          if (current.referenceType != 'manual_journal' ||
              current.source != 'manual') {
            throw StateError(
              'Only manual journal entries can be edited directly. Edit system journals from their source document.',
            );
          }
          if (current.status != 'posted' || current.reversedByEntryId.isNotEmpty) {
            throw StateError('Only an active posted manual journal can be edited.');
          }
        },
        validateVersion: (current) async {
          final base = baseReference(current.referenceId);
          if (base.isEmpty) {
            throw StateError('Manual journal reference is invalid.');
          }
          final active = await db.customSelect(
            '''
            SELECT je.id, je.reference_id
            FROM journal_entries je
            WHERE je.reference_type = 'manual_journal'
              AND (je.reference_id = ? OR instr(je.reference_id, ?) = 1)
              AND je.deleted_at = '' AND je.status = 'posted'
              AND NOT EXISTS (
                SELECT 1 FROM journal_entries rev
                WHERE rev.reversed_entry_id = je.id
                  AND rev.deleted_at = '' AND rev.status = 'posted'
              )
            ORDER BY datetime(je.created_at) DESC, datetime(je.entry_date) DESC
            LIMIT 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>(base),
              Variable<String>('$base:manual_edit:'),
            ],
          ).getSingleOrNull();
          if (active == null ||
              active.data['id']?.toString() != normalizedEntryId) {
            throw StateError(
              'Manual journal changed after it was opened. Reload it before editing.',
            );
          }

          final familyRows = await db.customSelect(
            '''
            SELECT reference_id
            FROM journal_entries
            WHERE reference_type = 'manual_journal'
              AND (reference_id = ? OR instr(reference_id, ?) = 1)
              AND deleted_at = ''
            ''',
            variables: <Variable<Object>>[
              Variable<String>(base),
              Variable<String>('$base:manual_edit:'),
            ],
          ).get();
          var maxVersion = 1;
          final matcher = RegExp(r':manual_edit:v(\d+)$');
          for (final row in familyRows) {
            final reference = row.data['reference_id']?.toString() ?? '';
            final match = matcher.firstMatch(reference);
            final version = int.tryParse(match?.group(1) ?? '') ?? 1;
            if (version > maxVersion) maxVersion = version;
          }
          nextReferenceId = '$base:manual_edit:v${maxVersion + 1}';
        },
        validateDependencies: (current) async {
          if (lines.length < 2) {
            throw StateError('Manual journal must contain at least two lines.');
          }
          await _assertDateNotInClosedPeriod(
            entryDate,
            branchId.trim().isNotEmpty ? branchId.trim() : current.branchId,
            database: db,
          );
        },
        reverseOperationalEffects: (current) async {},
        reverseAccountingEffects: (current) async {
          await reverseEntryForReference(
            referenceType: 'manual_journal',
            referenceId: baseReference(current.referenceId),
            reason: 'Manual journal edit',
            createdBy: createdBy,
            adjustCashLocationBalance: false,
            notifyChange: false,
            withinExistingTransaction: true,
          );
          final reversed = await db.customSelect(
            'SELECT status, reversed_by_entry_id FROM journal_entries WHERE id = ? LIMIT 1',
            variables: <Variable<Object>>[Variable<String>(current.id)],
          ).getSingleOrNull();
          if (reversed?.data['status']?.toString() != 'reversed' ||
              (reversed?.data['reversed_by_entry_id']?.toString() ?? '').isEmpty) {
            throw StateError('Previous manual journal version was not reversed.');
          }
        },
        applyChanges: (current) async => current,
        rebuildOperationalEffects: (current) async => current,
        buildPostedSnapshot: (current) async => current,
        repostAccounting: (current) async {
          createdEntryId = await createPostedEntry(
            JournalEntryDraft(
              entryDate: entryDate,
              referenceType: 'manual_journal',
              referenceId: nextReferenceId,
              referenceNo: current.referenceNo.trim().isEmpty
                  ? 'يدوي'
                  : current.referenceNo,
              description: description.trim().isEmpty
                  ? 'قيد يومية يدوي'
                  : description.trim(),
              source: 'manual',
              createdBy: createdBy.trim().isNotEmpty
                  ? createdBy.trim()
                  : current.createdBy,
              storeId: selectedStoreId,
              branchId: branchId.trim().isNotEmpty
                  ? branchId.trim()
                  : current.branchId,
              lines: lines,
            ),
            database: db,
            withinExistingTransaction: true,
          );
          if (createdEntryId.isEmpty) {
            throw StateError('Edited manual journal was not posted.');
          }
        },
        rebuildDerivedState: (current) async {},
        verifyIntegrity: (current) async {
          final row = await db.customSelect(
            '''
            SELECT je.status, je.reference_id, COUNT(jl.id) AS line_count,
                   COALESCE(SUM(jl.debit), 0) AS total_debit,
                   COALESCE(SUM(jl.credit), 0) AS total_credit
            FROM journal_entries je
            LEFT JOIN journal_lines jl ON jl.entry_id = je.id
            WHERE je.id = ? AND je.deleted_at = ''
            GROUP BY je.id, je.status, je.reference_id
            ''',
            variables: <Variable<Object>>[Variable<String>(createdEntryId)],
          ).getSingleOrNull();
          if (row == null ||
              row.data['status']?.toString() != 'posted' ||
              row.data['reference_id']?.toString() != nextReferenceId ||
              ((row.data['line_count'] as num?)?.toInt() ?? 0) != lines.length ||
              (_num(row.data['total_debit']) - _num(row.data['total_credit'])).abs() > 0.005) {
            throw StateError('Edited manual journal failed integrity verification.');
          }
        },
      ).execute();
    });

    if (selected.id.isNotEmpty && createdEntryId.isNotEmpty) {
      _notifyMutation();
    }
    return createdEntryId;
  }

  /// Posts the financial side of a manual stock adjustment. The caller owns
  /// the SQLite transaction together with stock/cost-layer mutations.
  static Future<String> recordManualInventoryAdjustmentInTransaction({
    required VentioDriftDatabase database,
    required DateTime entryDate,
    required String referenceId,
    required String referenceNo,
    required String productId,
    required String productName,
    required double quantityDelta,
    required double value,
    String adjustmentCategory = 'other',
    String reason = '',
    String createdBy = '',
    String storeId = '',
    String branchId = '',
  }) async {
    final amount = _roundMoney(value.abs());
    if (amount <= 0 || quantityDelta == 0) return '';
    final inventoryAccount =
        await _inventoryAccountForProduct(database, productId);
    final category = adjustmentCategory.trim().toLowerCase();
    final lines = <JournalLineDraft>[];
    if (quantityDelta > 0) {
      final gainAccount =
          await _resolveAccountRoleForDatabase(database, 'inventory_count_gain');
      lines
        ..add(JournalLineDraft(
          accountId: inventoryAccount,
          debit: amount,
          credit: 0,
          memo: 'Manual inventory increase - $productName',
        ))
        ..add(JournalLineDraft(
          accountId: gainAccount,
          debit: 0,
          credit: amount,
          memo: 'Manual inventory increase - $productName',
        ));
    } else {
      final lossRole = switch (category) {
        'expired' || 'expiry' => 'inventory_expiry',
        'damage' => 'inventory_damage',
        'weight' || 'weight_variance' => 'inventory_weight_variance',
        'free_sample' => 'marketing_expense',
        'internal_consumption' => 'general_expense',
        _ => 'inventory_count_loss',
      };
      final lossAccount =
          await _resolveAccountRoleForDatabase(database, lossRole);
      lines
        ..add(JournalLineDraft(
          accountId: lossAccount,
          debit: amount,
          credit: 0,
          memo: 'Manual inventory decrease - $productName',
        ))
        ..add(JournalLineDraft(
          accountId: inventoryAccount,
          debit: 0,
          credit: amount,
          memo: 'Manual inventory decrease - $productName',
        ));
    }
    return createPostedEntry(
      JournalEntryDraft(
        entryDate: entryDate,
        referenceType: 'inventory_adjustment',
        referenceId: referenceId,
        referenceNo: referenceNo,
        description: reason.trim().isEmpty
            ? 'Manual inventory adjustment - $productName'
            : reason.trim(),
        source: 'system',
        createdBy: createdBy,
        storeId: storeId,
        branchId: branchId,
        lines: lines,
      ),
      database: database,
      withinExistingTransaction: true,
    );
  }

  static Future<String> recordInventoryWaste({
    required DateTime entryDate,
    required String referenceId,
    required String referenceNo,
    required double amount,
    required String productName,
    String productId = '',
    String createdBy = '',
    String storeId = '',
    String branchId = '',
    String notes = '',
    String expenseRoleKey = 'inventory_damage',
    VentioDriftDatabase? database,
    bool withinExistingTransaction = false,
  }) async {
    if (database == null && !isAvailable) return '';
    final db = database ?? _db;
    final cleanAmount = _roundMoney(amount);
    if (cleanAmount <= 0) return '';
    final wasteAccount =
        await _resolveAccountRoleForDatabase(db, expenseRoleKey);
    final inventoryAccount = productId.trim().isEmpty
        ? await _resolveAccountRoleForDatabase(db, 'inventory_asset')
        : await _inventoryAccountForProduct(db, productId);
    final entryId = await createPostedEntry(
        JournalEntryDraft(
          entryDate: entryDate,
          referenceType: 'inventory_waste',
          referenceId: referenceId,
          referenceNo: referenceNo,
          description: notes.trim().isEmpty
              ? 'هدر وخسارة مخزون - $productName'
              : notes.trim(),
          // journal_entries.source is constrained to system/manual/import/reversal.
          // Keep the business meaning in referenceType and use the valid system source.
          source: 'system',
          createdBy: createdBy,
          storeId: storeId,
          branchId: branchId,
          lines: <JournalLineDraft>[
            JournalLineDraft(
              accountId: wasteAccount,
              debit: cleanAmount,
              credit: 0,
              memo: 'مصروف هدر وخسارة - $productName',
            ),
            JournalLineDraft(
              accountId: inventoryAccount,
              debit: 0,
              credit: cleanAmount,
              memo: 'إخراج مخزون بسبب هدر - $productName',
            ),
          ],
        ),
        database: db,
        withinExistingTransaction: withinExistingTransaction);
    if (entryId.isNotEmpty) _notifyMutation();
    return entryId;
  }

  /// Posts the complete Raw Materials -> WIP -> Finished Goods flow using the
  /// immutable costs captured on [order]. This must be called from the same
  /// SQLite transaction as the manufacturing stock movements and order row.
  static Future<String> recordManufacturingCompletionInTransaction({
    required VentioDriftDatabase database,
    required ManufacturingOrder order,
    String technicalReferenceId = '',
  }) async {
    if (order.totalMaterialCost <= 0 || order.totalEligibleCost < 0) {
      throw ArgumentError('Manufacturing cost snapshot is invalid.');
    }
    final rawInventory =
        await _resolveAccountRoleForDatabase(database, 'inventory_raw');
    final wipInventory =
        await _resolveAccountRoleForDatabase(database, 'inventory_wip');
    final finishedInventory =
        await _resolveAccountRoleForDatabase(database, 'inventory_finished');
    final wasteAccount = order.totalWasteCost > 0
        ? await _resolveAccountRoleForDatabase(database, 'manufacturing_waste')
        : '';
    final materialCost = _roundMoney(order.totalMaterialCost);
    final wasteCost = _roundMoney(order.totalWasteCost);
    final eligibleCost = _roundMoney(order.totalEligibleCost);
    if ((materialCost - wasteCost - eligibleCost).abs() > 0.0001) {
      throw ArgumentError(
          'Manufacturing material, waste, and eligible costs do not reconcile.');
    }
    // A manufactured intermediate (mix/sub-assembly) carries its historic
    // finished-goods cost into the next order. Only genuine raw inputs credit
    // Raw Materials; this keeps chained BOMs from expensing or counting the
    // same cost twice.
    var rawMaterialCost = 0.0;
    var intermediateMaterialCost = 0.0;
    for (final material in order.materialCosts) {
      final manufactured = await database.customSelect('''
        SELECT 1
        FROM bill_of_materials
        WHERE output_product_id = ?
          AND is_active = 1
          AND deleted_at = ''
        LIMIT 1
      ''', variables: <Variable<Object>>[
        Variable<String>(material.productId),
      ]).getSingleOrNull();
      if (manufactured == null) {
        rawMaterialCost += material.totalCost;
      } else {
        intermediateMaterialCost += material.totalCost;
      }
    }
    rawMaterialCost = _roundMoney(rawMaterialCost);
    intermediateMaterialCost = _roundMoney(intermediateMaterialCost);
    if ((rawMaterialCost + intermediateMaterialCost - materialCost).abs() >
        0.0001) {
      throw ArgumentError(
          'Manufacturing component account allocation does not reconcile.');
    }
    final lines = <JournalLineDraft>[
      JournalLineDraft(
        accountId: wipInventory,
        debit: materialCost,
        credit: 0,
        memo: 'Actual materials consumed by ${order.orderNo}',
      ),
      if (rawMaterialCost > 0)
        JournalLineDraft(
          accountId: rawInventory,
          debit: 0,
          credit: rawMaterialCost,
          memo: 'Raw materials issued to ${order.orderNo}',
        ),
      if (intermediateMaterialCost > 0)
        JournalLineDraft(
          accountId: finishedInventory,
          debit: 0,
          credit: intermediateMaterialCost,
          memo: 'Intermediate goods issued to ${order.orderNo}',
        ),
      if (wasteCost > 0) ...<JournalLineDraft>[
        JournalLineDraft(
          accountId: wasteAccount,
          debit: wasteCost,
          credit: 0,
          memo: 'Manufacturing waste for ${order.orderNo}',
        ),
        JournalLineDraft(
          accountId: wipInventory,
          debit: 0,
          credit: wasteCost,
          memo: 'WIP released as waste for ${order.orderNo}',
        ),
      ],
      if (eligibleCost > 0) ...<JournalLineDraft>[
        JournalLineDraft(
          accountId: finishedInventory,
          debit: eligibleCost,
          credit: 0,
          memo: 'Finished goods accepted from ${order.orderNo}',
        ),
        JournalLineDraft(
          accountId: wipInventory,
          debit: 0,
          credit: eligibleCost,
          memo: 'WIP completed by ${order.orderNo}',
        ),
      ],
    ];
    final postedReferenceId = technicalReferenceId.trim().isEmpty
        ? order.id
        : technicalReferenceId.trim();
    return createPostedEntry(
      JournalEntryDraft(
        entryDate: order.completedAt ?? order.date,
        referenceType: 'manufacturing_order',
        referenceId: postedReferenceId,
        referenceNo: order.orderNo,
        description: 'Manufacturing completion ${order.orderNo}',
        source: 'system',
        createdBy: order.completedBy,
        storeId: order.storeId,
        branchId: order.branchId,
        lines: lines,
      ),
      database: database,
      withinExistingTransaction: true,
    );
  }

  /// Posts the accounting effect of an approved stock count.
  ///
  /// A shortage debits the dedicated inventory-count loss account and credits
  /// inventory. An overage debits inventory and credits the dedicated gain
  /// account. Keeping the whole count in one journal preserves both sides of
  /// the count instead of netting away the audit detail.
  static Future<String> recordInventoryCountAdjustment({
    required DateTime entryDate,
    required String referenceId,
    required String referenceNo,
    required List<InventoryCountVariance> variances,
    String createdBy = '',
    String storeId = '',
    String branchId = '',
    String notes = '',
    VentioDriftDatabase? database,
    bool withinExistingTransaction = false,
  }) async {
    if (variances.isEmpty || (database == null && !isAvailable)) return '';
    final db = database ?? _db;
    final lossAccount =
        await _resolveAccountRoleForDatabase(db, 'inventory_count_loss');
    final gainAccount =
        await _resolveAccountRoleForDatabase(db, 'inventory_count_gain');

    final lines = <JournalLineDraft>[];
    var totalVariance = 0.0;
    for (final variance in variances) {
      final amount = _roundMoney(variance.amount.abs());
      if (amount <= 0) continue;
      final inventoryAccount = variance.productId.trim().isEmpty
          ? await _resolveAccountRoleForDatabase(db, 'inventory_asset')
          : await _inventoryAccountForProduct(db, variance.productId);
      totalVariance += amount;
      final isShortage = variance.delta < 0;
      final memo = isShortage
          ? 'عجز جرد مخزون ${variance.productName}'
          : 'زيادة جرد مخزون ${variance.productName}';
      if (isShortage) {
        lines
          ..add(JournalLineDraft(
            accountId: lossAccount,
            debit: amount,
            credit: 0,
            memo: memo,
          ))
          ..add(JournalLineDraft(
            accountId: inventoryAccount,
            debit: 0,
            credit: amount,
            memo: memo,
          ));
      } else {
        lines
          ..add(JournalLineDraft(
            accountId: inventoryAccount,
            debit: amount,
            credit: 0,
            memo: memo,
          ))
          ..add(JournalLineDraft(
            accountId: gainAccount,
            debit: 0,
            credit: amount,
            memo: memo,
          ));
      }
    }
    if (totalVariance <= 0 || lines.isEmpty) return '';

    final entryId = await createPostedEntry(
      JournalEntryDraft(
        entryDate: entryDate,
        referenceType: 'inventory_count',
        referenceId: referenceId,
        referenceNo: referenceNo,
        description: notes.trim().isEmpty
            ? 'تسوية فروقات جرد المخزون $referenceNo'
            : notes.trim(),
        source: 'system',
        createdBy: createdBy,
        storeId: storeId,
        branchId: branchId,
        lines: lines,
      ),
      database: db,
      withinExistingTransaction: withinExistingTransaction,
    );
    if (entryId.isNotEmpty && !withinExistingTransaction) _notifyMutation();
    return entryId;
  }

  /// Reverses the posted journal for an approved inventory count. The caller
  /// owns the SQLite transaction so accounting, stock and count status are
  /// reversed atomically.
  static Future<String> reverseInventoryCountAdjustmentInTransaction({
    required VentioDriftDatabase database,
    required String referenceId,
    String reason = '',
    String createdBy = '',
  }) async {
    final normalizedReferenceId = referenceId.trim();
    if (normalizedReferenceId.isEmpty) return '';
    final originalRow = await database.customSelect(
      '''
      SELECT id, entry_no, reference_no, created_by, store_id, branch_id
      FROM journal_entries je
      WHERE reference_type = 'inventory_count' AND reference_id = ?
        AND deleted_at = '' AND status = 'posted'
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries rev
          WHERE rev.reversed_entry_id = je.id
            AND rev.deleted_at = '' AND rev.status = 'posted'
        )
      ORDER BY created_at DESC, entry_date DESC
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(normalizedReferenceId),
      ],
    ).getSingleOrNull();
    if (originalRow == null) {
      final existing = await database.customSelect(
        '''
        SELECT rev.id
        FROM journal_entries rev
        JOIN journal_entries orig ON orig.id = rev.reversed_entry_id
        WHERE orig.reference_type = 'inventory_count'
          AND orig.reference_id = ?
          AND rev.deleted_at = '' AND rev.status = 'posted'
        ORDER BY rev.created_at DESC
        LIMIT 1
        ''',
        variables: <Variable<Object>>[
          Variable<String>(normalizedReferenceId),
        ],
      ).getSingleOrNull();
      return existing?.data['id']?.toString() ?? '';
    }

    final original = originalRow.data;
    final originalId = original['id']?.toString() ?? '';
    final lineRows = await database.customSelect(
      '''
      SELECT account_id, debit, credit, memo, party_type, party_id,
             party_name, cost_center_id
      FROM journal_lines
      WHERE entry_id = ?
      ORDER BY line_no
      ''',
      variables: <Variable<Object>>[Variable<String>(originalId)],
    ).get();
    if (lineRows.isEmpty) return '';
    final reversalLines = lineRows.map((row) {
      final data = row.data;
      return JournalLineDraft(
        accountId: data['account_id']?.toString() ?? '',
        debit: _cleanAmount(_num(data['credit'])),
        credit: _cleanAmount(_num(data['debit'])),
        memo: 'عكس: ${data['memo']?.toString() ?? ''}',
        partyType: data['party_type']?.toString() ?? '',
        partyId: data['party_id']?.toString() ?? '',
        partyName: data['party_name']?.toString() ?? '',
        costCenterId: data['cost_center_id']?.toString() ?? '',
      );
    }).toList(growable: false);
    _validateBalancedDraft(JournalEntryDraft(
      entryDate: DateTime.now(),
      description: 'تحقق عكس الجرد',
      lines: reversalLines,
    ));

    final nowDate = DateTime.now().toUtc();
    final now = nowDate.toIso8601String();
    await _assertDateNotInClosedPeriod(
      nowDate,
      original['branch_id']?.toString() ?? '',
      database: database,
    );
    final reversalId = _newId('je');
    final entryNo = await _nextEntryNo(database, nowDate);
    final actor = createdBy.trim().isNotEmpty
        ? createdBy.trim()
        : (original['created_by']?.toString() ?? '');
    final originalEntryNo = original['entry_no']?.toString() ?? '';
    final description = reason.trim().isEmpty
        ? 'عكس جرد المخزون $originalEntryNo'
        : 'عكس جرد المخزون $originalEntryNo: ${reason.trim()}';

    await database.customInsert(
      '''
      INSERT INTO journal_entries
        (id, entry_no, entry_date, reference_type, reference_id, reference_no,
         description, status, source, created_by, posted_at, reversed_entry_id,
         created_at, updated_at, store_id, branch_id)
      VALUES (?, ?, ?, 'inventory_count_reversal', ?, ?, ?, 'posted',
              'reversal', ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(reversalId),
        Variable<String>(entryNo),
        Variable<String>(now),
        Variable<String>(normalizedReferenceId),
        Variable<String>(original['reference_no']?.toString() ?? ''),
        Variable<String>(description),
        Variable<String>(actor),
        Variable<String>(now),
        Variable<String>(originalId),
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(original['store_id']?.toString() ?? ''),
        Variable<String>(original['branch_id']?.toString() ?? ''),
      ],
    );
    for (var index = 0; index < reversalLines.length; index++) {
      final line = reversalLines[index];
      final account = await _accountSnapshot(database, line.accountId);
      await database.customInsert(
        '''
        INSERT INTO journal_lines
          (id, entry_id, line_no, account_id, account_code, account_name,
           debit, credit, memo, party_type, party_id, party_name,
           cost_center_id, created_at, updated_at, store_id, branch_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(_newId('jl')),
          Variable<String>(reversalId),
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
          Variable<String>(original['store_id']?.toString() ?? ''),
          Variable<String>(original['branch_id']?.toString() ?? ''),
        ],
      );
    }
    await _writeAuditLogInTransaction(
      database,
      action: 'reverse_inventory_count',
      entityType: 'journal_entry',
      entityId: reversalId,
      referenceType: 'inventory_count',
      referenceId: normalizedReferenceId,
      details: description,
      createdBy: actor,
      storeId: original['store_id']?.toString() ?? '',
      branchId: original['branch_id']?.toString() ?? '',
      createdAt: now,
    );
    return reversalId;
  }

  /// Records the balance that existed at the moment the business started.
  /// This is deliberately separate from a transfer or a purchase so the
  /// opening amount is visible and cannot be mistaken for operating activity.
  static Future<void> recordOpeningCashLocationBalance({
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

  static Future<void> openCashDrawer({
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

  static Future<void> closeCashDrawer({
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
        throw StateError(
            'Cash drawer session is not open or no longer exists.');
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

  static Future<void> _postCashReconciliationDifference({
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

  static Future<void> createAccountingPeriod({
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

  static Future<void> closeAccountingPeriod(
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

  static Future<void> createCashLocation({
    required String name,
    required String type,
    String code = '',
    String accountId = '',
    String paymentAccountId = '',
    bool isDefault = false,
    String notes = '',
    String storeId = '',
    String branchId = '',
    String deviceId = '',
    String createdBy = '',
  }) async {
    if (!isAvailable) return;
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) throw ArgumentError('اسم موقع النقدية مطلوب.');
    final normalizedType = _normalizeCashLocationType(type);
    final now = DateTime.now().toUtc().toIso8601String();
    final locationId = _newId('cashloc');
    final normalizedCode = code.trim().isEmpty
        ? 'CASH-${DateTime.now().millisecondsSinceEpoch}'
        : code.trim().toUpperCase();
    final resolvedAccountId = accountId.trim().isEmpty
        ? await _createCashLocationAccount(
            locationId: locationId,
            name: normalizedName,
            type: normalizedType,
            code: normalizedCode,
            storeId: storeId,
            branchId: branchId,
          )
        : accountId.trim();
    await _accountSnapshot(_db, resolvedAccountId);
    await _db.transaction(() async {
      if (isDefault) {
        await _db.customUpdate(
          "UPDATE cash_locations SET is_default = 0, updated_at = ? WHERE type = ? AND deleted_at = ''",
          variables: <Variable<Object>>[
            Variable<String>(now),
            Variable<String>(normalizedType)
          ],
        );
      }
      await _db.customInsert(
        '''
        INSERT INTO cash_locations
          (id, code, name, type, account_id, parent_id, payment_account_id, is_default, is_active,
           allow_negative, current_balance, notes, created_at, updated_at, store_id, branch_id, device_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, 0, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(locationId),
          Variable<String>(normalizedCode),
          Variable<String>(normalizedName),
          Variable<String>(normalizedType),
          Variable<String>(resolvedAccountId),
          Variable<String>(''),
          Variable<String>(paymentAccountId.trim()),
          Variable<int>(isDefault ? 1 : 0),
          Variable<int>(0),
          Variable<String>(notes.trim()),
          Variable<String>(now),
          Variable<String>(now),
          Variable<String>(storeId),
          Variable<String>(branchId),
          Variable<String>(deviceId.trim()),
        ],
      );
    });
    _notifyMutation();
    await _writeAuditLog(
      action: 'create_cash_location',
      entityType: 'cash_location',
      entityId: locationId,
      details: normalizedName,
      createdBy: createdBy,
      storeId: storeId,
      branchId: branchId,
    );
  }

  static Future<void> linkCashDrawerToDevice({
    required String cashLocationId,
    required String deviceId,
    String branchId = '',
  }) async {
    if (!isAvailable) return;
    final cleanLocationId = cashLocationId.trim();
    final cleanDeviceId = deviceId.trim();
    final cleanBranchId = branchId.trim();
    if (cleanLocationId.isEmpty) {
      throw ArgumentError('درج النقدية مطلوب.');
    }
    if (cleanDeviceId.isEmpty) {
      throw ArgumentError('معرّف الجهاز مطلوب.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final row = await _db.customSelect(
      """
      SELECT id, type, name
      FROM cash_locations
      WHERE id = ? AND deleted_at = '' AND is_active = 1
      LIMIT 1
      """,
      variables: <Variable<Object>>[Variable<String>(cleanLocationId)],
    ).getSingleOrNull();
    if (row == null) throw StateError('درج النقدية غير موجود.');
    if ((row.data['type']?.toString() ?? '') != 'cash_drawer') {
      throw StateError('يمكن ربط أدراج النقد فقط بالأجهزة.');
    }
    await _db.transaction(() async {
      await _db.customUpdate(
        """
        UPDATE cash_locations
        SET device_id = '', updated_at = ?
        WHERE device_id = ? AND id <> ? AND type = 'cash_drawer' AND deleted_at = ''
        """,
        variables: <Variable<Object>>[
          Variable<String>(now),
          Variable<String>(cleanDeviceId),
          Variable<String>(cleanLocationId),
        ],
      );
      await _db.customUpdate(
        """
        UPDATE cash_locations
        SET device_id = ?,
            branch_id = CASE WHEN ? <> '' THEN ? ELSE branch_id END,
            updated_at = ?
        WHERE id = ?
        """,
        variables: <Variable<Object>>[
          Variable<String>(cleanDeviceId),
          Variable<String>(cleanBranchId),
          Variable<String>(cleanBranchId),
          Variable<String>(now),
          Variable<String>(cleanLocationId),
        ],
      );
    });
    _notifyMutation();
  }

  static Future<void> unlinkCashDrawerFromDevice(
      {required String deviceId}) async {
    if (!isAvailable) return;
    final cleanDeviceId = deviceId.trim();
    if (cleanDeviceId.isEmpty) return;
    await _db.customUpdate(
      "UPDATE cash_locations SET device_id = '', updated_at = ? WHERE device_id = ? AND type = 'cash_drawer' AND deleted_at = ''",
      variables: <Variable<Object>>[
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
        Variable<String>(cleanDeviceId),
      ],
    );
    _notifyMutation();
  }

  static Future<String> createCashTransfer({
    required BusinessSessionContext authorization,
    required String fromLocationId,
    required String toLocationId,
    required double amount,
    DateTime? transferDate,
    String notes = '',
    String createdBy = '',
    String createdByUserId = '',
    String storeId = '',
    String branchId = '',
    String deviceId = '',
    String fromSessionId = '',
    String toSessionId = '',
    String transferKind = 'vault_transfer',
    String idempotencyKey = '',
    bool notifyChange = true,
    bool withinExistingTransaction = false,
  }) async {
    authorization.requirePermission(AppPermission.cashBoxManage);
    if (!isAvailable) return '';
    final cleanAmount = _roundMoney(amount);
    if (cleanAmount <= 0) {
      throw ArgumentError('مبلغ التحويل يجب أن يكون أكبر من صفر.');
    }
    final normalizedKind = transferKind.trim() == 'shift_transfer'
        ? 'shift_transfer'
        : 'vault_transfer';
    final cleanKey = idempotencyKey.trim();
    if (cleanKey.isNotEmpty) {
      final existing = await _db.customSelect(
        "SELECT id FROM cash_transfers WHERE idempotency_key = ? AND deleted_at = '' LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(cleanKey)],
      ).getSingleOrNull();
      if (existing != null) return existing.data['id']?.toString() ?? '';
    }

    final fromLocation = await _cashLocationSnapshot(fromLocationId);
    final toLocation = await _cashLocationSnapshot(toLocationId);
    if (fromLocation.id == toLocation.id) {
      throw ArgumentError('لا يمكن التحويل إلى نفس موقع النقدية.');
    }

    if (normalizedKind == 'shift_transfer') {
      final cleanFromSessionId = fromSessionId.trim();
      final cleanToSessionId = toSessionId.trim();
      if (fromLocation.type != 'cash_drawer' ||
          toLocation.type != 'cash_drawer') {
        throw StateError('تحويل الوردية يجب أن يكون بين درجَي نقدية.');
      }
      if (cleanFromSessionId.isEmpty || cleanToSessionId.isEmpty) {
        throw StateError('تحويل الوردية يتطلب وردية مفتوحة للمصدر والوجهة.');
      }
      final sessions = await _db.customSelect(
        '''
        SELECT id, cash_location_id
        FROM cash_drawer_sessions
        WHERE id IN (?, ?) AND status = 'open'
        ''',
        variables: <Variable<Object>>[
          Variable<String>(cleanFromSessionId),
          Variable<String>(cleanToSessionId),
        ],
      ).get();
      final openById = <String, String>{
        for (final row in sessions)
          row.data['id']?.toString() ?? '':
              row.data['cash_location_id']?.toString() ?? '',
      };
      if (openById[cleanFromSessionId] != fromLocation.id ||
          openById[cleanToSessionId] != toLocation.id) {
        throw StateError(
            'تحويل الوردية يتطلب ورديتين مفتوحتين ومطابقتين لدرجَي المصدر والوجهة.');
      }
    }
    final sourceRow = await _db.customSelect(
      "SELECT current_balance FROM cash_locations WHERE id = ? AND deleted_at = '' AND is_active = 1 LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(fromLocation.id)],
    ).getSingleOrNull();
    final sourceBalance = _num(sourceRow?.data['current_balance']);
    if (!allowNegativeCashBalance && sourceBalance + 0.000001 < cleanAmount) {
      throw StateError('الرصيد النقدي في الموقع المصدر غير كافٍ للتحويل.');
    }

    final id = _newId('cashtx');
    final date = transferDate ?? DateTime.now();
    final nowDate = DateTime.now().toUtc();
    final now = nowDate.toIso8601String();
    final transferNo = await _nextCashTransferNo(date);
    final ledger = CashLedgerService(_db);
    String entryId = '';

    Future<void> persistTransfer() async {
      entryId = await createPostedEntry(
        JournalEntryDraft(
          entryDate: date,
          referenceType: 'cash_transfer',
          referenceId: id,
          referenceNo: transferNo,
          description:
              'تحويل نقدية من ${fromLocation.name} إلى ${toLocation.name}',
          source: 'system',
          createdBy: createdBy,
          storeId: storeId,
          branchId: branchId,
          lines: <JournalLineDraft>[
            JournalLineDraft(
                accountId: toLocation.accountId,
                debit: cleanAmount,
                credit: 0,
                memo: 'استلام تحويل نقدية'),
            JournalLineDraft(
                accountId: fromLocation.accountId,
                debit: 0,
                credit: cleanAmount,
                memo: 'إرسال تحويل نقدية'),
          ],
        ),
        database: _db,
        withinExistingTransaction: true,
      );
      if (entryId.isEmpty) {
        throw StateError('تعذر إنشاء القيد المحاسبي لتحويل النقدية.');
      }

      await _db.customInsert(
        '''
        INSERT INTO cash_transfers
          (id, transfer_no, transfer_date, from_location_id, to_location_id, amount, status, journal_entry_id,
           reference_type, reference_id, notes, created_by, approved_by, created_at, updated_at, store_id, branch_id,
           transfer_kind, from_session_id, to_session_id, created_by_user_id, device_id, idempotency_key)
        VALUES (?, ?, ?, ?, ?, ?, 'posted', ?, 'cash_transfer', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(id),
          Variable<String>(transferNo),
          Variable<String>(date.toUtc().toIso8601String()),
          Variable<String>(fromLocation.id),
          Variable<String>(toLocation.id),
          Variable<double>(cleanAmount),
          Variable<String>(entryId),
          Variable<String>(id),
          Variable<String>(notes.trim()),
          Variable<String>(createdBy),
          Variable<String>(createdBy),
          Variable<String>(now),
          Variable<String>(now),
          Variable<String>(storeId),
          Variable<String>(branchId),
          Variable<String>(normalizedKind),
          Variable<String>(fromSessionId.trim()),
          Variable<String>(toSessionId.trim()),
          Variable<String>(createdByUserId.trim()),
          Variable<String>(deviceId.trim()),
          Variable<String>(cleanKey),
        ],
      );

      await ledger.appendInExistingTransaction(CashLedgerTransaction(
        id: '${id}_out',
        type: normalizedKind,
        direction: 'out',
        amount: cleanAmount,
        cashLocationId: fromLocation.id,
        cashDrawerSessionId: fromSessionId.trim(),
        referenceType: 'cash_transfer',
        referenceId: id,
        referenceNumber: transferNo,
        paymentMethod: 'Cash',
        createdBy: createdBy.trim(),
        createdByUserId: createdByUserId.trim(),
        deviceId: deviceId.trim(),
        branchId: branchId.trim(),
        storeId: storeId.trim(),
        notes: notes.trim(),
        idempotencyKey: cleanKey.isEmpty ? '' : '$cleanKey:out',
        occurredAt: date.toUtc(),
        createdAt: nowDate,
        updatedAt: nowDate,
        lastModifiedByDeviceId: deviceId.trim(),
      ));
      await ledger.appendInExistingTransaction(CashLedgerTransaction(
        id: '${id}_in',
        type: normalizedKind,
        direction: 'in',
        amount: cleanAmount,
        cashLocationId: toLocation.id,
        cashDrawerSessionId: toSessionId.trim(),
        referenceType: 'cash_transfer',
        referenceId: id,
        referenceNumber: transferNo,
        paymentMethod: 'Cash',
        createdBy: createdBy.trim(),
        createdByUserId: createdByUserId.trim(),
        deviceId: deviceId.trim(),
        branchId: branchId.trim(),
        storeId: storeId.trim(),
        notes: notes.trim(),
        idempotencyKey: cleanKey.isEmpty ? '' : '$cleanKey:in',
        occurredAt: date.toUtc(),
        createdAt: nowDate,
        updatedAt: nowDate,
        lastModifiedByDeviceId: deviceId.trim(),
      ));

      await _db.customUpdate(
        'UPDATE cash_locations SET current_balance = current_balance - ?, updated_at = ? WHERE id = ?',
        variables: <Variable<Object>>[
          Variable<double>(cleanAmount),
          Variable<String>(now),
          Variable<String>(fromLocation.id)
        ],
      );
      await _db.customUpdate(
        'UPDATE cash_locations SET current_balance = current_balance + ?, updated_at = ? WHERE id = ?',
        variables: <Variable<Object>>[
          Variable<double>(cleanAmount),
          Variable<String>(now),
          Variable<String>(toLocation.id)
        ],
      );
    }

    if (withinExistingTransaction) {
      await persistTransfer();
    } else {
      await _db.transaction(persistTransfer);
    }
    if (notifyChange) _notifyMutation();
    await _writeAuditLog(
      action: normalizedKind == 'shift_transfer'
          ? 'create_shift_transfer'
          : 'create_vault_transfer',
      entityType: 'cash_transfer',
      entityId: id,
      details:
          '$transferNo: ${fromLocation.name} -> ${toLocation.name}: $cleanAmount',
      createdBy: createdBy,
      storeId: storeId,
      branchId: branchId,
    );
    return id;
  }

  static Future<void> createPaymentAccount({
    required String name,
    required String type,
    required String accountId,
    bool isDefault = false,
    String notes = '',
    String storeId = '',
    String branchId = '',
  }) async {
    if (!isAvailable) return;
    await _accountSnapshot(_db, accountId);
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.transaction(() async {
      if (isDefault) {
        await _db.customUpdate(
          "UPDATE payment_accounts SET is_default = 0, updated_at = ? WHERE type = ? AND deleted_at = ''",
          variables: <Variable<Object>>[
            Variable<String>(now),
            Variable<String>(type)
          ],
        );
      }
      await _db.customInsert(
        '''
        INSERT INTO payment_accounts
          (id, name, type, account_id, is_default, is_active, notes, created_at, updated_at, store_id, branch_id)
        VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(_newId('payacc')),
          Variable<String>(name.trim().isEmpty ? type : name.trim()),
          Variable<String>(type.trim().isEmpty ? 'other' : type.trim()),
          Variable<String>(accountId),
          Variable<int>(isDefault ? 1 : 0),
          Variable<String>(notes),
          Variable<String>(now),
          Variable<String>(now),
          Variable<String>(storeId),
          Variable<String>(branchId),
        ],
      );
    });
    _notifyMutation();
    await _writeAuditLog(
        action: 'create_payment_account',
        entityType: 'payment_account',
        details: name,
        storeId: storeId,
        branchId: branchId);
  }

  static Future<void> createCheque({
    required String chequeNo,
    required String direction,
    required String partyType,
    required String partyId,
    required String partyName,
    required String bankName,
    required DateTime dueDate,
    required double amount,
    String notes = '',
    String storeId = '',
    String branchId = '',
  }) async {
    if (!isAvailable) return;
    if (_cleanAmount(amount) <= 0) throw ArgumentError('قيمة الشيك مطلوبة.');
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.customInsert(
      '''
      INSERT INTO cheques
        (id, cheque_no, direction, party_type, party_id, party_name, bank_name, due_date,
         amount, status, notes, created_at, updated_at, store_id, branch_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(_newId('chq')),
        Variable<String>(chequeNo.trim()),
        Variable<String>(direction == 'issued' ? 'issued' : 'received'),
        Variable<String>(partyType),
        Variable<String>(partyId),
        Variable<String>(partyName),
        Variable<String>(bankName),
        Variable<String>(dueDate.toUtc().toIso8601String()),
        Variable<double>(_roundMoney(amount)),
        Variable<String>(notes),
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(storeId),
        Variable<String>(branchId),
      ],
    );
    _notifyMutation();
    await _writeAuditLog(
        action: 'create_cheque',
        entityType: 'cheque',
        details: chequeNo,
        storeId: storeId,
        branchId: branchId);
  }

  static Future<void> settleCheque(
      {required String chequeId, String settledBy = ''}) async {
    if (!isAvailable) return;
    final row = await _db.customSelect(
      "SELECT * FROM cheques WHERE id = ? AND status = 'pending' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(chequeId)],
    ).getSingleOrNull();
    if (row == null) return;
    final data = row.data;
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.customUpdate(
      "UPDATE cheques SET status = 'cleared', updated_at = ? WHERE id = ?",
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(chequeId)
      ],
    );
    _notifyMutation();
    await _writeAuditLog(
        action: 'clear_cheque',
        entityType: 'cheque',
        entityId: chequeId,
        details: data['cheque_no']?.toString() ?? '',
        createdBy: settledBy,
        storeId: data['store_id']?.toString() ?? '',
        branchId: data['branch_id']?.toString() ?? '');
  }

  static Future<void> bounceCheque(
      {required String chequeId, String reason = '', String actor = ''}) async {
    if (!isAvailable) return;
    final row = await _db.customSelect(
      "SELECT cheque_no, store_id, branch_id FROM cheques WHERE id = ? AND status = 'pending' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(chequeId)],
    ).getSingleOrNull();
    if (row == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.customUpdate(
      "UPDATE cheques SET status = 'bounced', notes = notes || ?, updated_at = ? WHERE id = ?",
      variables: <Variable<Object>>[
        Variable<String>('\nBounced: $reason'),
        Variable<String>(now),
        Variable<String>(chequeId)
      ],
    );
    _notifyMutation();
    await _writeAuditLog(
        action: 'bounce_cheque',
        entityType: 'cheque',
        entityId: chequeId,
        details: reason,
        createdBy: actor,
        storeId: row.data['store_id']?.toString() ?? '',
        branchId: row.data['branch_id']?.toString() ?? '');
  }

  static Future<void> createSimpleMasterData({
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

  static _FrozenAccountingTax? _snapshotTaxBreakdown(
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

  static Future<double> _defaultVatRatePercent() async {
    final dbIdentity = identityHashCode(_db);
    if (_settingsCacheDbIdentity == dbIdentity &&
        _defaultVatRateCache != null) {
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

  static Future<_TaxBreakdown> _taxBreakdown(double grossAmount) async {
    final gross = _roundMoney(_cleanAmount(grossAmount));
    final rate = await _defaultVatRatePercent();
    if (gross <= 0 || rate <= 0) {
      return _TaxBreakdown(
          netAmount: gross,
          taxAmount: 0,
          grossAmount: gross,
          ratePercent: rate);
    }
    final net = _roundMoney(gross / (1 + (rate / 100)));
    final tax = _roundMoney(gross - net);
    return _TaxBreakdown(
        netAmount: net, taxAmount: tax, grossAmount: gross, ratePercent: rate);
  }

  static Future<void> recordInventoryCountAuditInTransaction({
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

  static Future<void> _writeAuditLog({
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

  static Future<void> _writeAuditLogInTransaction(
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

  static Future<bool> _hasActiveEntryForReference(
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

  static String _requiredAccount(Map<String, String> accounts, String key) {
    final accountId = accounts[key]?.trim() ?? '';
    if (accountId.isEmpty) {
      throw StateError('إعداد محاسبي مفقود: $key');
    }
    return accountId;
  }

  static bool _isCashPaymentMethod(String paymentMethod) {
    final method = paymentMethod.trim().toLowerCase();
    return method.isEmpty || method == 'cash';
  }

  static Future<void> _ensureCashDrawerDeviceBinding({
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

  static Future<_CashLocationSnapshot?> _openCashDrawerLocationForDevice({
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

  static Future<_CashLocationSnapshot?> _openCashDrawerLocationFallback(
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

  static Future<void> _moveCashLocationBalance(
    String cashLocationId,
    double delta,
    DateTime movementDate, {
    VentioDriftDatabase? database,
  }) async {
    final db = database ?? _db;
    final id = cashLocationId.trim();
    if (id.isEmpty || delta.abs() < 0.01) return;
    if (delta < 0) {
      await ensureCashOutflowAllowed(
        cashLocationId: id,
        amount: -delta,
        database: db,
      );
    }
    await db.customUpdate(
      'UPDATE cash_locations SET current_balance = current_balance + ?, updated_at = ? WHERE id = ?',
      variables: <Variable<Object>>[
        Variable<double>(_roundMoney(delta)),
        Variable<String>(movementDate.toUtc().toIso8601String()),
        Variable<String>(id),
      ],
    );
  }

  static Future<void> _setCashLocationBalance(
      String cashLocationId, double balance, String updatedAt) async {
    final id = cashLocationId.trim();
    if (id.isEmpty) return;
    await _db.customUpdate(
      'UPDATE cash_locations SET current_balance = ?, updated_at = ? WHERE id = ?',
      variables: <Variable<Object>>[
        Variable<double>(_roundMoney(balance)),
        Variable<String>(updatedAt),
        Variable<String>(id),
      ],
    );
  }

  static Future<String> _cashLocationAccountId(String cashLocationId) async {
    final id = cashLocationId.trim();
    if (id.isEmpty) {
      return resolveAccountRole('cash');
    }
    final location = await _cashLocationSnapshot(id);
    return location.accountId;
  }

  static Future<_CashLocationSnapshot> _cashLocationSnapshot(
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

  static Future<String> _defaultCashLocationId(
      {required String type,
      String branchId = '',
      String deviceId = ''}) async {
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

  static Future<String> _createCashLocationAccount({
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

  static Future<String> _accountForCashLocationType(String type) async {
    if (type == 'bank') {
      return resolveAccountRole('bank');
    }
    return resolveAccountRole('cash');
  }

  static String _normalizeCashLocationType(String type) {
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

  static Future<String> _nextCashTransferNo(DateTime date) async {
    final prefix = 'CT-${date.toUtc().year}-';
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS count FROM cash_transfers WHERE transfer_no LIKE ?',
      variables: <Variable<Object>>[Variable<String>('$prefix%')],
    ).getSingle();
    final count = (row.data['count'] as int? ?? 0) + 1;
    return '$prefix${count.toString().padLeft(6, '0')}';
  }

  static Future<String> _paymentAccountIdForDatabase(
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

  static Future<String> _paymentAccountId(String paymentMethod) async {
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

  static Future<void> _assertDateNotInClosedPeriod(
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

  static void _validateBalancedDraft(JournalEntryDraft draft) {
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

  static Future<AccountingAccount> _accountSnapshot(
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

  static Future<AccountingAccount> _accountSnapshotIncludingInactive(
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

  static Future<String> _nextEntryNo(
    VentioDriftDatabase db,
    DateTime date,
  ) async {
    final pending = _entryNoQueue.then((_) => _nextEntryNoUnlocked(db, date));
    _entryNoQueue = pending.then((_) {}, onError: (_) {});
    return pending;
  }

  static Future<String> _nextEntryNoUnlocked(
    VentioDriftDatabase db,
    DateTime date,
  ) async {
    final year = date.toUtc().year;
    _ensureEntryNoCache(db);
    final sequence = await _nextEntrySequenceForYear(db, year);
    _entryNoSequenceByYear[year] = sequence + 1;
    return 'JE-$year-${sequence.toString().padLeft(6, '0')}';
  }

  static Future<int> _nextEntrySequenceForYear(
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

  static void _ensureEntryNoCache(VentioDriftDatabase db) {
    final dbIdentity = identityHashCode(db);
    if (_entryNoCacheDbIdentity == dbIdentity) {
      return;
    }
    _entryNoCacheDbIdentity = dbIdentity;
    _entryNoSequenceByYear.clear();
  }

  static DateTime _parseDate(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toLocal() ??
      DateTime.fromMillisecondsSinceEpoch(0);

  static double _num(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _roundMoney(double value, {String? currency}) =>
      normalizeAccountingAmount(
        value,
        currency ?? _moneyProfile.baseCurrency,
        _moneyProfile,
      );

  static String _newId(String prefix) =>
      '${prefix}_${DateTime.now().toUtc().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';

  static double _cleanAmount(double value) =>
      value.isFinite && value > 0 ? value : 0;
}

class _InventoryAmount {
  const _InventoryAmount(this.productId, this.amount);

  final String productId;
  final double amount;
}

class InventoryCountVariance {
  const InventoryCountVariance({
    this.productId = '',
    required this.productName,
    required this.delta,
    required this.amount,
  });

  final String productId;
  final String productName;
  final double delta;
  final double amount;
}

class _CashLocationSnapshot {
  const _CashLocationSnapshot({
    required this.id,
    required this.name,
    required this.type,
    required this.accountId,
  });

  final String id;
  final String name;
  final String type;
  final String accountId;
}

class JournalEntrySummaryReport {
  const JournalEntrySummaryReport({
    required this.id,
    required this.entryNo,
    required this.entryDate,
    required this.referenceType,
    required this.referenceId,
    required this.referenceNo,
    required this.description,
    required this.status,
    required this.source,
    required this.createdBy,
    required this.branchId,
    required this.reversedEntryId,
    required this.reversedByEntryId,
    required this.reversalReason,
    required this.totalDebit,
    required this.totalCredit,
    required this.lineCount,
  });

  final String id;
  final String entryNo;
  final DateTime entryDate;
  final String referenceType;
  final String referenceId;
  final String referenceNo;
  final String description;
  final String status;
  final String source;
  final String createdBy;
  final String branchId;
  final String reversedEntryId;
  final String reversedByEntryId;
  final String reversalReason;
  final double totalDebit;
  final double totalCredit;
  final int lineCount;

  factory JournalEntrySummaryReport.fromRow(Map<String, Object?> row) {
    double number(String key) =>
        (row[key] as num?)?.toDouble() ??
        double.tryParse(row[key]?.toString() ?? '') ??
        0;
    int integer(String key) =>
        (row[key] as num?)?.toInt() ??
        int.tryParse(row[key]?.toString() ?? '') ??
        0;
    return JournalEntrySummaryReport(
      id: row['id']?.toString() ?? '',
      entryNo: row['entry_no']?.toString() ?? '',
      entryDate: DateTime.tryParse(row['entry_date']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      referenceType: row['reference_type']?.toString() ?? '',
      referenceId: row['reference_id']?.toString() ?? '',
      referenceNo: row['reference_no']?.toString() ?? '',
      description: row['description']?.toString() ?? '',
      status: row['status']?.toString() ?? '',
      source: row['source']?.toString() ?? '',
      createdBy: row['created_by']?.toString() ?? '',
      branchId: row['branch_id']?.toString() ?? '',
      reversedEntryId: row['reversed_entry_id']?.toString() ?? '',
      reversedByEntryId: row['reversed_by_entry_id']?.toString() ?? '',
      reversalReason: row['reversal_reason']?.toString() ?? '',
      totalDebit: number('total_debit'),
      totalCredit: number('total_credit'),
      lineCount: integer('line_count'),
    );
  }
}

class JournalEntryDetailsReport {
  const JournalEntryDetailsReport({
    required this.id,
    required this.entryNo,
    required this.entryDate,
    required this.referenceType,
    required this.referenceId,
    required this.referenceNo,
    required this.description,
    required this.status,
    required this.source,
    required this.createdBy,
    required this.branchId,
    required this.reversedEntryId,
    required this.reversedByEntryId,
    required this.reversalReason,
    required this.postedAt,
    required this.reversedAt,
    required this.reversedBy,
    required this.lines,
  });

  final String id;
  final String entryNo;
  final DateTime entryDate;
  final String referenceType;
  final String referenceId;
  final String referenceNo;
  final String description;
  final String status;
  final String source;
  final String createdBy;
  final String branchId;
  final String reversedEntryId;
  final String reversedByEntryId;
  final String reversalReason;
  final DateTime? postedAt;
  final DateTime? reversedAt;
  final String reversedBy;
  final List<JournalEntryDetailLineReport> lines;

  double get totalDebit =>
      lines.fold<double>(0, (sum, line) => sum + line.debit);
  double get totalCredit =>
      lines.fold<double>(0, (sum, line) => sum + line.credit);
}

class JournalEntryDetailLineReport {
  const JournalEntryDetailLineReport({
    required this.lineNo,
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.debit,
    required this.credit,
    required this.memo,
    required this.partyType,
    required this.partyId,
    required this.partyName,
    required this.costCenterId,
  });

  final int lineNo;
  final String accountId;
  final String accountCode;
  final String accountName;
  final double debit;
  final double credit;
  final String memo;
  final String partyType;
  final String partyId;
  final String partyName;
  final String costCenterId;

  factory JournalEntryDetailLineReport.fromRow(Map<String, Object?> row) {
    double number(String key) =>
        (row[key] as num?)?.toDouble() ??
        double.tryParse(row[key]?.toString() ?? '') ??
        0;
    return JournalEntryDetailLineReport(
      lineNo: (row['line_no'] as num?)?.toInt() ??
          int.tryParse(row['line_no']?.toString() ?? '') ??
          0,
      accountId: row['account_id']?.toString() ?? '',
      accountCode: row['account_code']?.toString() ?? '',
      accountName: row['account_name']?.toString() ?? '',
      debit: number('debit'),
      credit: number('credit'),
      memo: row['memo']?.toString() ?? '',
      partyType: row['party_type']?.toString() ?? '',
      partyId: row['party_id']?.toString() ?? '',
      partyName: row['party_name']?.toString() ?? '',
      costCenterId: row['cost_center_id']?.toString() ?? '',
    );
  }
}

class AdvancedAccountingItem {
  const AdvancedAccountingItem({
    required this.id,
    required this.name,
    this.type = '',
    this.accountCode = '',
    this.accountName = '',
    this.status = '',
    this.referenceId = '',
    this.notes = '',
    this.debit = 0,
    this.credit = 0,
    this.balance = 0,
    this.isActive = true,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final String type;
  final String accountCode;
  final String accountName;
  final String status;
  final String referenceId;
  final String notes;
  final double debit;
  final double credit;
  final double balance;
  final bool isActive;
  final bool isDefault;

  factory AdvancedAccountingItem.fromRow(Map<String, Object?> row) {
    double toDouble(Object? value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    bool toBool(Object? value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      return value?.toString() == '1' ||
          value?.toString().toLowerCase() == 'true';
    }

    return AdvancedAccountingItem(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      type: row['type']?.toString() ?? '',
      accountCode: row['account_code']?.toString() ?? '',
      accountName: row['account_name']?.toString() ?? '',
      status: row['status']?.toString() ?? '',
      referenceId: row['reference_id']?.toString() ?? '',
      notes: row['notes']?.toString() ?? '',
      debit: toDouble(row['debit']),
      credit: toDouble(row['credit']),
      balance: toDouble(row['balance']),
      isActive: !row.containsKey('is_active') || toBool(row['is_active']),
      isDefault: toBool(row['is_default']),
    );
  }
}

class TrialBalanceRowReport {
  const TrialBalanceRowReport({
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.accountType,
    required this.debit,
    required this.credit,
    required this.balance,
    this.accountSubtype = '',
    this.normalBalance = 'debit',
    this.opening = 0,
    this.closing = 0,
  });

  final String accountId;
  final String accountCode;
  final String accountName;
  final String accountType;
  final String accountSubtype;
  final String normalBalance;
  final double debit;
  final double credit;
  final double balance;
  final double opening;
  final double closing;

  double get debitBalance {
    if (normalBalance == 'credit') {
      return closing < 0 ? -closing : 0;
    }
    return closing > 0 ? closing : 0;
  }

  double get creditBalance {
    if (normalBalance == 'credit') {
      return closing > 0 ? closing : 0;
    }
    return closing < 0 ? -closing : 0;
  }
}

class GeneralLedgerAccountReport {
  const GeneralLedgerAccountReport({
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.accountType,
    required this.normalBalance,
    required this.totalDebit,
    required this.totalCredit,
    required this.closingBalance,
    required this.lines,
    this.accountSubtype = '',
    this.openingBalance = 0,
  });

  final String accountId;
  final String accountCode;
  final String accountName;
  final String accountType;
  final String accountSubtype;
  final String normalBalance;
  final double totalDebit;
  final double totalCredit;
  final double closingBalance;
  final double openingBalance;
  final List<GeneralLedgerLineReport> lines;
}

class GeneralLedgerLineReport {
  const GeneralLedgerLineReport({
    required this.entryNo,
    required this.entryDate,
    required this.referenceType,
    required this.referenceNo,
    required this.description,
    required this.memo,
    required this.debit,
    required this.credit,
    required this.runningBalance,
    this.referenceId = '',
    this.source = '',
  });

  final String entryNo;
  final DateTime entryDate;
  final String referenceType;
  final String referenceId;
  final String referenceNo;
  final String source;
  final String description;
  final String memo;
  final double debit;
  final double credit;
  final double runningBalance;
}

class FinancialStatementAccountLine {
  const FinancialStatementAccountLine({
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.accountType,
    required this.amount,
    this.accountSubtype = '',
  });

  final String accountId;
  final String accountCode;
  final String accountName;
  final String accountType;
  final String accountSubtype;
  final double amount;
}

class IncomeStatementReport {
  const IncomeStatementReport({
    required this.revenue,
    required this.costOfGoodsSold,
    required this.grossProfit,
    required this.expenses,
    required this.netProfit,
    this.grossSales = 0,
    this.salesReturns = 0,
    this.salesDiscounts = 0,
    this.netSales = 0,
    this.otherRevenue = 0,
    this.inventoryGain = 0,
    this.cashOver = 0,
    this.inventoryLoss = 0,
    this.manufacturingWaste = 0,
    this.manufacturingVariance = 0,
    this.cashShort = 0,
    this.otherRevenueLines = const <FinancialStatementAccountLine>[],
    this.costOfSalesLines = const <FinancialStatementAccountLine>[],
    this.expenseLines = const <FinancialStatementAccountLine>[],
  });

  final double revenue;
  final double costOfGoodsSold;
  final double grossProfit;
  final double expenses;
  final double netProfit;
  final double grossSales,
      salesReturns,
      salesDiscounts,
      netSales,
      otherRevenue,
      inventoryGain,
      cashOver,
      inventoryLoss,
      manufacturingWaste,
      manufacturingVariance,
      cashShort;
  final List<FinancialStatementAccountLine> otherRevenueLines;
  final List<FinancialStatementAccountLine> costOfSalesLines;
  final List<FinancialStatementAccountLine> expenseLines;
}

class BalanceSheetReport {
  const BalanceSheetReport({
    required this.assets,
    required this.liabilities,
    required this.equity,
    required this.retainedEarnings,
    required this.liabilitiesAndEquity,
    required this.difference,
    this.currentAssets = 0,
    this.nonCurrentAssets = 0,
    this.currentLiabilities = 0,
    this.nonCurrentLiabilities = 0,
    this.currentAssetLines = const <FinancialStatementAccountLine>[],
    this.nonCurrentAssetLines = const <FinancialStatementAccountLine>[],
    this.currentLiabilityLines = const <FinancialStatementAccountLine>[],
    this.nonCurrentLiabilityLines = const <FinancialStatementAccountLine>[],
    this.equityLines = const <FinancialStatementAccountLine>[],
  });

  final double assets;
  final double liabilities;
  final double equity;
  final double retainedEarnings;
  final double liabilitiesAndEquity;
  final double difference;
  final double currentAssets;
  final double nonCurrentAssets;
  final double currentLiabilities;
  final double nonCurrentLiabilities;
  final List<FinancialStatementAccountLine> currentAssetLines;
  final List<FinancialStatementAccountLine> nonCurrentAssetLines;
  final List<FinancialStatementAccountLine> currentLiabilityLines;
  final List<FinancialStatementAccountLine> nonCurrentLiabilityLines;
  final List<FinancialStatementAccountLine> equityLines;
}

enum CashFlowCategory { operating, investing, financing }

class CashFlowStatementReport {
  const CashFlowStatementReport({
    required this.operatingInflows,
    required this.operatingOutflows,
    required this.investingInflows,
    required this.investingOutflows,
    required this.financingInflows,
    required this.financingOutflows,
    required this.openingCash,
    required this.closingCash,
    this.from,
    this.to,
    this.lines = const <CashFlowStatementLineReport>[],
  });

  final double operatingInflows;
  final double operatingOutflows;
  final double investingInflows;
  final double investingOutflows;
  final double financingInflows;
  final double financingOutflows;
  final double openingCash;
  final double closingCash;
  final DateTime? from;
  final DateTime? to;
  final List<CashFlowStatementLineReport> lines;

  double get operatingNet => operatingInflows - operatingOutflows;
  double get investingNet => investingInflows - investingOutflows;
  double get financingNet => financingInflows - financingOutflows;
  double get netChangeInCash => operatingNet + investingNet + financingNet;
}

class CashFlowStatementLineReport {
  const CashFlowStatementLineReport({
    required this.entryNo,
    required this.entryDate,
    required this.referenceType,
    required this.referenceNo,
    required this.description,
    required this.category,
    required this.inflow,
    required this.outflow,
    required this.netCashFlow,
  });

  final String entryNo;
  final DateTime entryDate;
  final String referenceType;
  final String referenceNo;
  final String description;
  final CashFlowCategory category;
  final double inflow;
  final double outflow;
  final double netCashFlow;
}

class TaxReport {
  const TaxReport({
    required this.outputTax,
    required this.inputTax,
    required this.netTaxPayable,
    required this.payableAccountMovement,
    this.from,
    this.to,
  });

  final double outputTax;
  final double inputTax;
  final double netTaxPayable;
  final double payableAccountMovement;
  final DateTime? from;
  final DateTime? to;
}

class _FrozenAccountingTax {
  const _FrozenAccountingTax({
    required this.netAmount,
    required this.taxAmount,
    required this.grossNetBeforeDiscount,
  });

  final double netAmount;
  final double taxAmount;
  final double grossNetBeforeDiscount;
}

class _TaxBreakdown {
  const _TaxBreakdown(
      {required this.netAmount,
      required this.taxAmount,
      required this.grossAmount,
      required this.ratePercent});

  final double netAmount;
  final double taxAmount;
  final double grossAmount;
  final double ratePercent;
}

class CashBankMovementReport {
  const CashBankMovementReport({
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.moneyIn,
    required this.moneyOut,
    required this.closingBalance,
  });

  final String accountId;
  final String accountCode;
  final String accountName;
  final double moneyIn;
  final double moneyOut;
  final double closingBalance;
}

class InventoryValuationRowReport {
  const InventoryValuationRowReport({
    required this.productId,
    required this.productName,
    required this.warehouseId,
    required this.warehouseName,
    required this.quantity,
    required this.unitCost,
    required this.totalValue,
    required this.inventoryAccountId,
    required this.inventoryCategory,
    this.fallbackInventoryAccountId = '',
  });

  final String productId,
      productName,
      warehouseId,
      warehouseName,
      inventoryAccountId,
      inventoryCategory,
      fallbackInventoryAccountId;
  final double quantity, unitCost, totalValue;
}

class ManufacturingOrderCostReport {
  const ManufacturingOrderCostReport({
    required this.orderId,
    required this.orderNo,
    required this.outputProductId,
    required this.outputProductName,
    required this.outputQuantity,
    required this.totalMaterialCost,
    required this.wasteValue,
    required this.eligibleCost,
    required this.actualUnitCost,
    required this.status,
    required this.journalEntryId,
    required this.materialCosts,
  });

  final String orderId,
      orderNo,
      outputProductId,
      outputProductName,
      status,
      journalEntryId;
  final double outputQuantity,
      totalMaterialCost,
      wasteValue,
      eligibleCost,
      actualUnitCost;
  final List<ManufacturingMaterialCost> materialCosts;
}

class ManufacturingWasteReportRow {
  const ManufacturingWasteReportRow({
    required this.orderId,
    required this.orderNo,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCost,
    required this.value,
    required this.reason,
    required this.status,
  });

  final String orderId, orderNo, productId, productName, reason, status;
  final double quantity, unitCost, value;
}

class InventoryCountVarianceReportRow {
  const InventoryCountVarianceReportRow({
    required this.sessionId,
    required this.countNo,
    required this.status,
    required this.journalEntryId,
    required this.reversalJournalEntryId,
    required this.productId,
    required this.productName,
    required this.systemQuantity,
    required this.countedQuantity,
    required this.differenceQuantity,
    required this.unitCost,
    required this.differenceValue,
    required this.stockMovementId,
  });

  final String sessionId,
      countNo,
      status,
      journalEntryId,
      reversalJournalEntryId,
      productId,
      productName,
      stockMovementId;
  final double systemQuantity,
      countedQuantity,
      differenceQuantity,
      unitCost,
      differenceValue;

  factory InventoryCountVarianceReportRow.fromRow(Map<String, Object?> row) {
    double number(String key) =>
        (row[key] as num?)?.toDouble() ??
        double.tryParse(row[key]?.toString() ?? '') ??
        0;
    return InventoryCountVarianceReportRow(
      sessionId: row['session_id']?.toString() ?? '',
      countNo: row['count_no']?.toString() ?? '',
      status: row['status']?.toString() ?? '',
      journalEntryId: row['journal_entry_id']?.toString() ?? '',
      reversalJournalEntryId:
          row['reversal_journal_entry_id']?.toString() ?? '',
      productId: row['product_id']?.toString() ?? '',
      productName: row['product_name']?.toString() ?? '',
      systemQuantity: number('system_qty_at_approval'),
      countedQuantity: number('counted_qty'),
      differenceQuantity: number('difference_qty'),
      unitCost: number('unit_cost'),
      differenceValue: number('difference_value'),
      stockMovementId: row['stock_movement_id']?.toString() ?? '',
    );
  }
}

class CashShiftReportSession {
  const CashShiftReportSession({
    required this.id,
    required this.drawerNo,
    required this.cashLocationId,
    required this.cashLocationName,
    required this.openedAt,
    required this.closedAt,
    required this.openingBalance,
    required this.expectedCash,
    required this.countedCash,
    required this.difference,
    required this.notes,
    required this.openedBy,
    required this.closedBy,
    required this.branchId,
  });

  final String id;
  final String drawerNo;
  final String cashLocationId;
  final String cashLocationName;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final double openingBalance;
  final double expectedCash;
  final double countedCash;
  final double difference;
  final String notes;
  final String openedBy;
  final String closedBy;
  final String branchId;

  factory CashShiftReportSession.fromRow(Map<String, Object?> row) {
    double number(String key) =>
        (row[key] as num?)?.toDouble() ??
        double.tryParse(row[key]?.toString() ?? '') ??
        0.0;
    return CashShiftReportSession(
      id: row['id']?.toString() ?? '',
      drawerNo: row['drawer_no']?.toString() ?? '',
      cashLocationId: row['cash_location_id']?.toString() ?? '',
      cashLocationName: row['cash_location_name']?.toString() ?? '',
      openedAt: DateTime.tryParse(row['opened_at']?.toString() ?? ''),
      closedAt: DateTime.tryParse(row['closed_at']?.toString() ?? ''),
      openingBalance: number('opening_balance'),
      expectedCash: number('expected_cash'),
      countedCash: number('counted_cash'),
      difference: number('difference'),
      notes: row['notes']?.toString() ?? '',
      openedBy: row['opened_by']?.toString() ?? '',
      closedBy: row['closed_by']?.toString() ?? '',
      branchId: row['branch_id']?.toString() ?? '',
    );
  }
}
