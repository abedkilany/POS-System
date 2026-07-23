import 'dart:math';

import 'package:drift/drift.dart';

import '../../models/account_transaction.dart';
import '../../models/accounting_account.dart';
import '../../models/expense.dart';
import '../../models/journal_entry.dart';
import '../../models/purchase.dart';
import '../../models/sale.dart';
import '../../models/store_profile.dart';
import '../utils/currency_utils.dart';
import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/ventio_drift_database.dart';

class AccountingService {
  AccountingService._();

  static final Random _random = Random.secure();
  static bool get isAvailable => SqliteMigrationManager.database != null;
  static void Function()? _mutationListener;
  static StoreProfile _moneyProfile = StoreProfile.defaults;
  static int? _entryNoCacheDbIdentity;
  static int? _settingsCacheDbIdentity;
  static Map<String, String>? _defaultAccountMapCache;
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

  static void _clearAccountingSettingsCache() {
    _settingsCacheDbIdentity = null;
    _defaultAccountMapCache = null;
    _defaultVatRateCache = null;
    _paymentAccountByTypeCache.clear();
  }

  static void configureMoneyPolicy(StoreProfile profile) {
    _moneyProfile = profile;
  }

  static VentioDriftDatabase get _db {
    final database = SqliteMigrationManager.database;
    if (database == null) {
      throw StateError('قاعدة بيانات SQLite غير مهيأة.');
    }
    return database;
  }

  static Future<List<AccountingAccount>> listAccounts({
    bool activeOnly = true,
  }) async {
    if (!isAvailable) return const <AccountingAccount>[];
    final rows = await _db.customSelect(
      '''
      SELECT id, code, name, type, subtype, parent_id, normal_balance,
             currency, is_system, is_active, description
      FROM accounts
      WHERE deleted_at = '' ${activeOnly ? 'AND is_active = 1' : ''}
      ORDER BY code
      ''',
    ).get();
    return rows.map((row) => AccountingAccount.fromRow(row.data)).toList();
  }

  static Future<double> readDefaultVatRatePercent() async {
    if (!isAvailable) return 0.0;
    return _defaultVatRatePercent();
  }

  static Future<void> updateDefaultVatRatePercent(double ratePercent) async {
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
    await _accountSnapshot(_db, normalizedAccountId);
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.customInsert(
      r'''
      INSERT INTO accounting_settings (key, account_id, value, description, updated_at)
      VALUES (?, ?, '', '', ?)
      ON CONFLICT(key) DO UPDATE SET
        account_id = excluded.account_id,
        updated_at = excluded.updated_at
      ''',
      variables: <Variable<Object>>[
        Variable<String>(normalizedKey),
        Variable<String>(normalizedAccountId),
        Variable<String>(now),
      ],
    );
    _clearAccountingSettingsCache();
    _notifyMutation();
    await _writeAuditLog(
      action: 'update_setting',
      entityType: 'accounting_setting',
      entityId: normalizedKey,
      details: 'تم ربط $normalizedKey بالحساب $normalizedAccountId',
    );
  }

  static Future<void> recordSale(Sale sale) async {
    if (sale.isDeleted || sale.isCancelled || sale.total <= 0) return;
    if (!isAvailable) return;
    final accounts = await readDefaultAccountMap();
    final accountingCurrency = sale.invoiceCurrency.trim().isEmpty
        ? _moneyProfile.baseCurrency
        : sale.invoiceCurrency.trim().toUpperCase();
    final rawInvoiceTotal = _cleanAmount(sale.invoiceTotal);
    final rawSaleTotal = _cleanAmount(sale.total);
    final saleTotal = _roundMoney(rawSaleTotal, currency: accountingCurrency);
    final tax = await _taxBreakdown(saleTotal);
    final paidInInvoiceCurrency =
        _cleanAmount(sale.paidAmount.clamp(0, rawInvoiceTotal).toDouble());
    final rawPaid = rawInvoiceTotal <= 0
        ? 0.0
        : rawSaleTotal * (paidInInvoiceCurrency / rawInvoiceTotal);
    final paid = min(
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
            await _paymentAccountId(accounts, sale.paymentMethod),
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
        accountId: _requiredAccount(accounts, 'default_customers_account_id'),
        debit: balance,
        credit: 0,
        memo: 'مبلغ مستحق على العميل للمبيعة ${sale.invoiceNo}',
        partyType: 'customer',
        partyId: sale.customerId,
        partyName: sale.customerName,
      ));
    }
    lines.add(JournalLineDraft(
      accountId: _requiredAccount(accounts, 'default_sales_account_id'),
      debit: 0,
      credit: tax.netAmount,
      memo: tax.taxAmount > 0
          ? 'إيرادات المبيعات قبل الضريبة ${sale.invoiceNo}'
          : 'إيرادات المبيعات ${sale.invoiceNo}',
    ));
    if (tax.taxAmount > 0) {
      lines.add(JournalLineDraft(
        accountId: _requiredAccount(accounts, 'default_sales_tax_account_id'),
        debit: 0,
        credit: tax.taxAmount,
        memo: 'ضريبة المخرجات / ضريبة المبيعات ${sale.invoiceNo}',
      ));
    }
    if (cogs > 0) {
      lines
        ..add(JournalLineDraft(
          accountId: _requiredAccount(accounts, 'default_cogs_account_id'),
          debit: cogs,
          credit: 0,
          memo: 'تكلفة البضاعة المباعة ${sale.invoiceNo}',
        ))
        ..add(JournalLineDraft(
          accountId: _requiredAccount(accounts, 'default_inventory_account_id'),
          debit: 0,
          credit: cogs,
          memo: 'مخزون صادر للمبيعة ${sale.invoiceNo}',
        ));
    }
    final entryId = await createPostedEntry(JournalEntryDraft(
      entryDate: sale.date,
      referenceType: 'sale',
      referenceId: sale.id,
      referenceNo: sale.invoiceNo,
      description: 'فاتورة مبيعات ${sale.invoiceNo}',
      createdBy: sale.lastModifiedByDeviceId,
      storeId: sale.storeId,
      branchId: sale.branchId,
      lines: lines,
    ));
    if (entryId.isNotEmpty && cashSaleLocation != null && paid > 0) {
      await _moveCashLocationBalance(cashSaleLocation.id, paid, sale.date);
    }
  }

  static Future<void> recordPurchase(Purchase purchase) async {
    if (purchase.isDeleted || purchase.isCancelled || purchase.subtotal <= 0) {
      return;
    }
    if (!isAvailable) return;
    final accounts = await readDefaultAccountMap();
    final accountingCurrency = _moneyProfile.baseCurrency;
    final rawTotal = _cleanAmount(purchase.subtotal);
    final total = _roundMoney(rawTotal, currency: accountingCurrency);
    final tax = await _taxBreakdown(total);
    final paid = min(
      total,
      _roundMoney(
        _cleanAmount(purchase.paidAmount.clamp(0, rawTotal).toDouble()),
        currency: accountingCurrency,
      ),
    );
    final balance =
        _roundMoney(_cleanAmount(total - paid), currency: accountingCurrency);
    final lines = <JournalLineDraft>[
      JournalLineDraft(
        accountId: _requiredAccount(accounts, 'default_inventory_account_id'),
        debit: tax.netAmount,
        credit: 0,
        memo: tax.taxAmount > 0
            ? 'مخزون مستلم قبل الضريبة ${purchase.purchaseNo}'
            : 'مخزون مستلم من المشتريات ${purchase.purchaseNo}',
        partyType: 'supplier',
        partyId: purchase.supplierId,
        partyName: purchase.supplierName,
      ),
    ];
    if (tax.taxAmount > 0) {
      lines.add(JournalLineDraft(
        accountId:
            _requiredAccount(accounts, 'default_purchase_tax_account_id'),
        debit: tax.taxAmount,
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
            await _paymentAccountId(accounts, purchase.paymentMethod),
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
        accountId: _requiredAccount(accounts, 'default_suppliers_account_id'),
        debit: 0,
        credit: balance,
        memo: 'مبلغ مستحق للمورد عن المشتريات ${purchase.purchaseNo}',
        partyType: 'supplier',
        partyId: purchase.supplierId,
        partyName: purchase.supplierName,
      ));
    }
    final entryId = await createPostedEntry(JournalEntryDraft(
      entryDate: purchase.date,
      referenceType: 'purchase',
      referenceId: purchase.id,
      referenceNo: purchase.purchaseNo,
      description: 'فاتورة مشتريات ${purchase.purchaseNo}',
      createdBy: purchase.lastModifiedByDeviceId,
      storeId: purchase.storeId,
      branchId: purchase.branchId,
      lines: lines,
    ));
    if (entryId.isNotEmpty && cashPurchaseLocation != null && paid > 0) {
      await _moveCashLocationBalance(
          cashPurchaseLocation.id, -paid, purchase.date);
    }
  }

  static Future<void> recordExpense(Expense expense) async {
    if (expense.isDeleted || !expense.isPosted || expense.amount <= 0) return;
    if (!isAvailable) return;
    final accounts = await readDefaultAccountMap();
    final cashExpenseLocation = await _openCashDrawerLocationForDevice(
        deviceId: expense.deviceId, branchId: expense.branchId);
    if (cashExpenseLocation == null) {
      throw StateError(
          'لا توجد وردية نقدية مفتوحة لدرج هذا الجهاز. افتح وردية قبل تسجيل مصروف نقدي.');
    }
    final entryId = await createPostedEntry(JournalEntryDraft(
      entryDate: expense.date,
      referenceType: 'expense',
      referenceId: expense.id,
      referenceNo: expense.title,
      description: 'مصروف: ${expense.title}',
      createdBy: expense.lastModifiedByDeviceId,
      storeId: expense.storeId,
      branchId: expense.branchId,
      lines: <JournalLineDraft>[
        JournalLineDraft(
          accountId: _requiredAccount(accounts, 'default_expense_account_id'),
          debit: expense.amount,
          credit: 0,
          memo: expense.category,
        ),
        JournalLineDraft(
          accountId: cashExpenseLocation.accountId,
          debit: 0,
          credit: expense.amount,
          memo: 'دفعة مصروف',
        ),
      ],
    ));
    if (entryId.isNotEmpty) {
      await _moveCashLocationBalance(
          cashExpenseLocation.id, -expense.amount, expense.date);
    }
  }

  static Future<void> recordAccountPayment(
      AccountTransaction transaction) async {
    if (transaction.isDeleted) return;
    if (!isAvailable) return;
    final accounts = await readDefaultAccountMap();
    final isCustomerPayment = transaction.isCustomer && transaction.credit > 0;
    final isSupplierPayment = transaction.isSupplier && transaction.debit > 0;
    if (!isCustomerPayment && !isSupplierPayment) return;
    final amount = _cleanAmount(
        isCustomerPayment ? transaction.credit : transaction.debit);
    if (amount <= 0) return;
    final isCashAccountPayment =
        _isCashPaymentMethod(transaction.paymentMethod);
    final cashPaymentLocation = isCashAccountPayment
        ? await _openCashDrawerLocationForDevice(
            deviceId: transaction.deviceId, branchId: transaction.branchId)
        : null;
    if (isCashAccountPayment && cashPaymentLocation == null) {
      throw StateError(
          'لا توجد وردية نقدية مفتوحة لدرج هذا الجهاز. افتح وردية قبل تسجيل حركة نقدية.');
    }
    final paymentAccount = cashPaymentLocation?.accountId ??
        await _paymentAccountId(accounts, transaction.paymentMethod);
    final controlAccount = _requiredAccount(
      accounts,
      isCustomerPayment
          ? 'default_customers_account_id'
          : 'default_suppliers_account_id',
    );
    final entryId = await createPostedEntry(JournalEntryDraft(
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
    ));
    if (entryId.isNotEmpty && cashPaymentLocation != null) {
      await _moveCashLocationBalance(
        cashPaymentLocation.id,
        isCustomerPayment ? amount : -amount,
        transaction.date,
      );
    }
  }

  static Future<String> createPostedEntry(JournalEntryDraft draft) async {
    if (!isAvailable) return '';
    _validateBalancedDraft(draft);
    await _assertDateNotInClosedPeriod(draft.entryDate, draft.branchId);
    final db = _db;
    if (await _hasActiveEntryForReference(
        db, draft.referenceType, draft.referenceId)) {
      return '';
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final entryId = _newId('je');
    final entryNo = await _nextEntryNo(db, draft.entryDate);

    await db.transaction(() async {
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
    });
    return entryId;
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

  static Future<void> reverseEntryForReference({
    required String referenceType,
    required String referenceId,
    String reason = '',
    String createdBy = '',
  }) async {
    if (!isAvailable) return;
    final db = _db;
    if (referenceType.trim().isEmpty || referenceId.trim().isEmpty) return;
    final entryRow = await db.customSelect(
      '''
      SELECT id, entry_no, entry_date, reference_type, reference_id, reference_no,
             description, created_by, store_id, branch_id
      FROM journal_entries
      WHERE reference_type = ? AND reference_id = ? AND deleted_at = '' AND status = 'posted'
      ORDER BY entry_date DESC
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(referenceType),
        Variable<String>(referenceId),
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

    await db.transaction(() async {
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
      await db.customUpdate(
        '''
        UPDATE journal_entries
        SET status = 'reversed', updated_at = ?
        WHERE id = ? AND status = 'posted'
        ''',
        variables: <Variable<Object>>[
          Variable<String>(now),
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
    });
  }

  static Future<List<GeneralLedgerAccountReport>> generalLedgerReport() async {
    if (!isAvailable) return const <GeneralLedgerAccountReport>[];
    final rows = await _db.customSelect(
      '''
      SELECT a.id AS account_id, a.code AS account_code, a.name AS account_name,
             a.type AS account_type, a.normal_balance,
             jl.entry_id, jl.line_no, jl.debit, jl.credit, jl.memo,
             je.entry_no, je.entry_date, je.reference_type, je.reference_no,
             je.description
      FROM accounts a
      LEFT JOIN journal_lines jl ON jl.account_id = a.id
      LEFT JOIN journal_entries je
        ON je.id = jl.entry_id AND je.deleted_at = '' AND je.status = 'posted'
      WHERE a.deleted_at = '' AND a.is_active = 1
      ORDER BY a.code, je.entry_date, je.entry_no, jl.line_no
      ''',
    ).get();

    final accounts = <GeneralLedgerAccountReport>[];
    var hasCurrent = false;
    String accountId = '';
    String accountCode = '';
    String accountName = '';
    String accountType = '';
    String normalBalance = 'debit';
    var runningBalance = 0.0;
    final lines = <GeneralLedgerLineReport>[];

    void flushCurrentAccount() {
      if (!hasCurrent) return;
      accounts.add(GeneralLedgerAccountReport(
        accountId: accountId,
        accountCode: accountCode,
        accountName: accountName,
        accountType: accountType,
        normalBalance: normalBalance,
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
      if (nextAccountId != accountId) {
        flushCurrentAccount();
        hasCurrent = true;
        accountId = nextAccountId;
        accountCode = row.data['account_code']?.toString() ?? '';
        accountName = row.data['account_name']?.toString() ?? '';
        accountType = row.data['account_type']?.toString() ?? '';
        normalBalance = row.data['normal_balance']?.toString() ?? 'debit';
        runningBalance = 0.0;
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
        referenceNo: row.data['reference_no']?.toString() ?? '',
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

  static Future<List<TrialBalanceRowReport>> _trialBalanceRows() async {
    final rows = await _db.customSelect(
      '''
      SELECT a.id, a.code, a.name, a.type, a.normal_balance,
             COALESCE(SUM(CASE WHEN je.id IS NOT NULL THEN jl.debit ELSE 0 END), 0) AS debit,
             COALESCE(SUM(CASE WHEN je.id IS NOT NULL THEN jl.credit ELSE 0 END), 0) AS credit
      FROM accounts a
      LEFT JOIN journal_lines jl ON jl.account_id = a.id
      LEFT JOIN journal_entries je ON je.id = jl.entry_id AND je.deleted_at = '' AND je.status = 'posted'
      WHERE a.deleted_at = '' AND a.is_active = 1
      GROUP BY a.id, a.code, a.name, a.type, a.normal_balance
      ORDER BY a.code
      ''',
    ).get();
    return rows.map((row) {
      final debit = _num(row.data['debit']);
      final credit = _num(row.data['credit']);
      final normal = row.data['normal_balance']?.toString() ?? 'debit';
      final balance = normal == 'credit' ? credit - debit : debit - credit;
      return TrialBalanceRowReport(
        accountId: row.data['id']?.toString() ?? '',
        accountCode: row.data['code']?.toString() ?? '',
        accountName: row.data['name']?.toString() ?? '',
        accountType: row.data['type']?.toString() ?? '',
        debit: _roundMoney(debit),
        credit: _roundMoney(credit),
        balance: _roundMoney(balance),
      );
    }).toList(growable: false);
  }

  static Future<List<TrialBalanceRowReport>> trialBalanceReport() async {
    if (!isAvailable) return const <TrialBalanceRowReport>[];
    return _trialBalanceRows();
  }

  static Future<IncomeStatementReport> incomeStatementReport() async {
    if (!isAvailable) {
      return const IncomeStatementReport(
        revenue: 0,
        costOfGoodsSold: 0,
        expenses: 0,
        grossProfit: 0,
        netProfit: 0,
      );
    }
    final rows = await _trialBalanceRows();
    double sumByType(String type) => rows
        .where((row) => row.accountType == type)
        .fold<double>(0, (sum, row) => sum + row.balance.abs());
    final revenue = sumByType('revenue');
    final cogs = sumByType('cost_of_sales');
    final expenses = sumByType('expense');
    return IncomeStatementReport(
      revenue: _roundMoney(revenue),
      costOfGoodsSold: _roundMoney(cogs),
      grossProfit: _roundMoney(revenue - cogs),
      expenses: _roundMoney(expenses),
      netProfit: _roundMoney(revenue - cogs - expenses),
    );
  }

  static Future<BalanceSheetReport> balanceSheetReport() async {
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
    final rows = await _trialBalanceRows();
    double sumByType(String type) => rows
        .where((row) => row.accountType == type)
        .fold<double>(0, (sum, row) => sum + row.balance.abs());
    final assets = sumByType('asset');
    final liabilities = sumByType('liability');
    final equity = sumByType('equity');
    final revenue = sumByType('revenue');
    final cogs = sumByType('cost_of_sales');
    final expenses = sumByType('expense');
    final netProfit = revenue - cogs - expenses;
    return BalanceSheetReport(
      assets: _roundMoney(assets),
      liabilities: _roundMoney(liabilities),
      equity: _roundMoney(equity),
      retainedEarnings: _roundMoney(netProfit),
      liabilitiesAndEquity: _roundMoney(liabilities + equity + netProfit),
      difference: _roundMoney(assets - liabilities - equity - netProfit),
    );
  }

  static Future<List<CashBankMovementReport>> cashBankMovementReport() async {
    if (!isAvailable) return const <CashBankMovementReport>[];
    final defaults = await readDefaultAccountMap();
    final accountIds = <String>{
      defaults['default_cash_account_id'] ?? '',
      defaults['default_bank_account_id'] ?? '',
    }..removeWhere((value) => value.trim().isEmpty);
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
        AND je.status = 'posted'
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
    final defaults = await readDefaultAccountMap();
    final cashAccountIds = <String>{
      defaults['default_cash_account_id'] ?? '',
      defaults['default_bank_account_id'] ?? '',
    }..removeWhere((value) => value.trim().isEmpty);
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
      "je.status = 'posted'"
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
        "je.status = 'posted'",
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
        """
        SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
        FROM journal_lines jl
        INNER JOIN journal_entries je ON je.id = jl.entry_id
        WHERE ${conditions.join(' AND ')}
        """,
        variables: variables,
      ).getSingleOrNull();
      return _roundMoney(_num(row?.data['balance']));
    }

    final entryRows = await _db.customSelect(
      """
      SELECT je.id AS entry_id, je.entry_no, je.entry_date, je.reference_type, je.reference_no, je.description,
             jl.account_id, jl.account_code, jl.account_name, jl.debit, jl.credit,
             a.type AS account_type, jl.line_no
      FROM journal_entries je
      INNER JOIN journal_lines jl ON jl.entry_id = je.id
      LEFT JOIN accounts a ON a.id = jl.account_id
      WHERE jl.account_id IN ($placeholders)
        AND ${dateConditions.join(' AND ')}
      ORDER BY je.entry_date, je.entry_no, jl.line_no
      """,
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

    void flushCurrentEntry() {
      if (!hasCurrentEntry || cashMovement.abs() < 0.005) return;
      final category = _cashFlowCategory(currentReferenceType, nonCashTypes);
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
      }
      final accountId = entryRow.data['account_id']?.toString() ?? '';
      final debit = _num(entryRow.data['debit']);
      final credit = _num(entryRow.data['credit']);
      if (cashAccountIds.contains(accountId)) {
        cashMovement += debit - credit;
      } else {
        final type = entryRow.data['account_type']?.toString() ?? '';
        if (type.isNotEmpty) nonCashTypes.add(type);
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
      String referenceType, Set<String> accountTypes) {
    final ref = referenceType.toLowerCase();
    if (ref.contains('asset') ||
        ref.contains('fixed_asset') ||
        ref.contains('investment')) {
      return CashFlowCategory.investing;
    }
    if (ref.contains('capital') ||
        ref.contains('loan') ||
        ref.contains('owner') ||
        ref.contains('equity')) {
      return CashFlowCategory.financing;
    }
    if (accountTypes.any((type) => type == 'equity')) {
      return CashFlowCategory.financing;
    }
    if (accountTypes.any((type) => type == 'liability') &&
        !accountTypes.any((type) =>
            type == 'revenue' ||
            type == 'expense' ||
            type == 'cost_of_sales')) {
      return CashFlowCategory.financing;
    }
    if (accountTypes.any((type) => type == 'asset') &&
        !accountTypes.any((type) =>
            type == 'revenue' ||
            type == 'expense' ||
            type == 'cost_of_sales' ||
            type == 'liability')) {
      return CashFlowCategory.investing;
    }
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
    final accounts = await readDefaultAccountMap();
    final salesTaxAccountId =
        accounts['default_sales_tax_account_id']?.trim() ?? '';
    final purchaseTaxAccountId =
        accounts['default_purchase_tax_account_id']?.trim() ?? '';
    final payableAccountId =
        accounts['default_tax_payable_account_id']?.trim() ?? salesTaxAccountId;
    final conditions = <String>["je.deleted_at = ''", "je.status = 'posted'"];
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
              CASE WHEN cl.allow_negative = 1 THEN ' • يسمح بالسالب' ELSE '' END ||
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
             cds.expected_cash AS credit,
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
      SELECT opened_at, expected_cash, branch_id, cash_location_id
      FROM cash_drawer_sessions
      WHERE id = ? AND status = 'open'
      LIMIT 1
      """,
      variables: <Variable<Object>>[Variable<String>(sessionId)],
    ).getSingleOrNull();
    if (row == null) return 0;
    return _expectedCashForDrawer(
      openedAt: row.data['opened_at']?.toString() ?? '',
      fallbackExpected: _num(row.data['expected_cash']),
      branchId: row.data['branch_id']?.toString() ?? '',
      cashLocationId: row.data['cash_location_id']?.toString() ?? '',
    );
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
    });

    await createPostedEntry(JournalEntryDraft(
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
    ));

    _notifyMutation();
    await _writeAuditLog(
      action: 'create_fixed_asset',
      entityType: 'fixed_asset',
      entityId: assetId,
      referenceType: 'fixed_asset',
      referenceId: assetId,
      details: '$normalizedCode - $normalizedName',
      createdBy: createdBy,
      storeId: storeId,
      branchId: branchId,
    );
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
      final entryId = await createPostedEntry(JournalEntryDraft(
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
      ));
      accumulated = _roundMoney(accumulated + amount);
      await _db.customInsert(
        '''
        INSERT OR IGNORE INTO fixed_asset_depreciation
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
          Variable<double>(accumulated),
          Variable<double>(_roundMoney(purchaseValue - accumulated)),
          Variable<String>(entryId),
          Variable<String>('إهلاك القسط الثابت'),
          Variable<String>(DateTime.now().toUtc().toIso8601String()),
          Variable<String>(asset['store_id']?.toString() ?? ''),
          Variable<String>(asset['branch_id']?.toString() ?? ''),
        ],
      );
      posted++;
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

  static Future<void> openCashDrawer({
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
    if (!isAvailable) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final resolvedLocationId = cashLocationId.trim().isEmpty
        ? await _defaultCashLocationId(
            type: 'cash_drawer', branchId: branchId, deviceId: deviceId)
        : cashLocationId.trim();
    if (resolvedLocationId.trim().isEmpty) {
      throw StateError('لا يوجد درج نقد معرف لفتح وردية.');
    }
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
    final sessionId = _newId('drawer');
    final cleanOpening = _roundMoney(openingBalance);
    await _db.customInsert(
      '''
      INSERT INTO cash_drawer_sessions
        (id, drawer_no, cash_location_id, opened_at, status, opening_balance, expected_cash,
         notes, opened_by, opened_by_user_id, store_id, branch_id)
      VALUES (?, ?, ?, ?, 'open', ?, ?, '', ?, ?, ?, ?)
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
      ],
    );
    if (cleanOpening > 0) {
      if (fundingLocationId.trim().isNotEmpty &&
          fundingLocationId.trim() != resolvedLocationId) {
        await createCashTransfer(
          fromLocationId: fundingLocationId,
          toLocationId: resolvedLocationId,
          amount: cleanOpening,
          transferDate:
              DateTime.parse(now).subtract(const Duration(microseconds: 1)),
          notes:
              'عهدة افتتاح وردية ${drawerNo.trim().isEmpty ? 'درج النقد' : drawerNo.trim()}',
          createdBy: openedBy,
          storeId: storeId,
          branchId: branchId,
          notifyChange: false,
        );
      } else {
        await _setCashLocationBalance(resolvedLocationId, cleanOpening, now);
      }
    }
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
    required String sessionId,
    required double countedCash,
    String closedBy = '',
    String closedByUserId = '',
    String notes = '',
    String depositToLocationId = '',
  }) async {
    if (!isAvailable) return;
    final row = await _db.customSelect(
      """
      SELECT id, drawer_no, cash_location_id, opened_at, expected_cash, store_id, branch_id
      FROM cash_drawer_sessions
      WHERE id = ? AND status = 'open'
      LIMIT 1
      """,
      variables: <Variable<Object>>[Variable<String>(sessionId)],
    ).getSingleOrNull();
    if (row == null) return;

    final data = row.data;
    final storeId = data['store_id']?.toString() ?? '';
    final branchId = data['branch_id']?.toString() ?? '';
    final openedAt = data['opened_at']?.toString() ?? '';
    final storedExpected = _num(data['expected_cash']);
    final expected = _roundMoney(await _expectedCashForDrawer(
      openedAt: openedAt,
      fallbackExpected: storedExpected,
      branchId: branchId,
      cashLocationId: data['cash_location_id']?.toString() ?? '',
    ));
    final counted = _roundMoney(countedCash);
    final difference = _roundMoney(counted - expected);
    final now = DateTime.now().toUtc().toIso8601String();

    await _db.customUpdate(
      '''
      UPDATE cash_drawer_sessions
      SET status = 'closed', closed_at = ?, expected_cash = ?, counted_cash = ?, difference = ?,
          closed_by = ?, closed_by_user_id = ?, notes = ?
      WHERE id = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<double>(expected),
        Variable<double>(counted),
        Variable<double>(difference),
        Variable<String>(closedBy),
        Variable<String>(closedByUserId),
        Variable<String>(notes),
        Variable<String>(sessionId),
      ],
    );

    if (difference.abs() >= 0.01) {
      await _postCashReconciliationDifference(
        sessionId: sessionId,
        drawerNo: data['drawer_no']?.toString() ?? '',
        difference: difference,
        countedCash: counted,
        expectedCash: expected,
        closedBy: closedBy,
        storeId: storeId,
        branchId: branchId,
        cashLocationId: data['cash_location_id']?.toString() ?? '',
      );
    }

    final closedLocationId = data['cash_location_id']?.toString() ?? '';
    if (depositToLocationId.trim().isNotEmpty &&
        closedLocationId.trim().isNotEmpty &&
        counted > 0 &&
        depositToLocationId.trim() != closedLocationId.trim()) {
      await createCashTransfer(
        fromLocationId: closedLocationId,
        toLocationId: depositToLocationId,
        amount: counted,
        notes: notes.trim().isEmpty
            ? 'تسليم نقدية عند إغلاق الوردية'
            : notes.trim(),
        createdBy: closedBy,
        storeId: storeId,
        branchId: branchId,
        notifyChange: false,
      );
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

  static Future<double> _expectedCashForDrawer({
    required String openedAt,
    required double fallbackExpected,
    required String branchId,
    String cashLocationId = '',
  }) async {
    final cashAccountId = await _cashLocationAccountId(cashLocationId);
    final branchFilter = branchId.trim().isEmpty ? '' : 'AND je.branch_id = ?';
    final variables = <Variable<Object>>[
      Variable<String>(cashAccountId),
      Variable<String>(openedAt),
      if (branchId.trim().isNotEmpty) Variable<String>(branchId),
    ];
    final row = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS movement
      FROM journal_lines jl
      INNER JOIN journal_entries je ON je.id = jl.entry_id
      WHERE jl.account_id = ?
        AND je.deleted_at = ''
        AND je.status = 'posted'
        AND je.entry_date >= ?
        $branchFilter
      ''',
      variables: variables,
    ).getSingleOrNull();
    return _roundMoney(fallbackExpected + _num(row?.data['movement']));
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
    final accounts = await readDefaultAccountMap();
    final cashAccountId = await _cashLocationAccountId(cashLocationId);
    final adjustmentAccountId =
        accounts['default_cash_over_short_account_id']?.trim().isNotEmpty ==
                true
            ? accounts['default_cash_over_short_account_id']!.trim()
            : _requiredAccount(accounts, 'default_expense_account_id');
    final amount = _roundMoney(difference.abs());
    if (amount <= 0) return;

    final isOverage = difference > 0;
    await createPostedEntry(JournalEntryDraft(
      entryDate: DateTime.now(),
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
    ));
    await _moveCashLocationBalance(cashLocationId, difference, DateTime.now());
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
    String parentId = '',
    String paymentAccountId = '',
    bool isDefault = false,
    bool allowNegative = false,
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
          Variable<String>(parentId.trim()),
          Variable<String>(paymentAccountId.trim()),
          Variable<int>(isDefault ? 1 : 0),
          Variable<int>(allowNegative ? 1 : 0),
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

  static Future<void> createCashTransfer({
    required String fromLocationId,
    required String toLocationId,
    required double amount,
    DateTime? transferDate,
    String notes = '',
    String createdBy = '',
    String storeId = '',
    String branchId = '',
    bool notifyChange = true,
  }) async {
    if (!isAvailable) return;
    final cleanAmount = _roundMoney(amount);
    if (cleanAmount <= 0) {
      throw ArgumentError('مبلغ التحويل يجب أن يكون أكبر من صفر.');
    }
    final fromLocation = await _cashLocationSnapshot(fromLocationId);
    final toLocation = await _cashLocationSnapshot(toLocationId);
    if (fromLocation.id == toLocation.id) {
      throw ArgumentError('لا يمكن التحويل إلى نفس موقع النقدية.');
    }
    final id = _newId('cashtx');
    final date = transferDate ?? DateTime.now();
    final now = DateTime.now().toUtc().toIso8601String();
    final transferNo = await _nextCashTransferNo(date);
    final entryId = await createPostedEntry(JournalEntryDraft(
      entryDate: date,
      referenceType: 'cash_transfer',
      referenceId: id,
      referenceNo: transferNo,
      description: 'تحويل نقدية من ${fromLocation.name} إلى ${toLocation.name}',
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
    ));
    await _db.transaction(() async {
      await _db.customInsert(
        '''
        INSERT INTO cash_transfers
          (id, transfer_no, transfer_date, from_location_id, to_location_id, amount, status, journal_entry_id,
           reference_type, reference_id, notes, created_by, approved_by, created_at, updated_at, store_id, branch_id)
        VALUES (?, ?, ?, ?, ?, ?, 'posted', ?, 'cash_transfer', ?, ?, ?, ?, ?, ?, ?, ?)
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
        ],
      );
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
    });
    if (notifyChange) _notifyMutation();
    await _writeAuditLog(
      action: 'create_cash_transfer',
      entityType: 'cash_transfer',
      entityId: id,
      details:
          '$transferNo: ${fromLocation.name} -> ${toLocation.name}: $cleanAmount',
      createdBy: createdBy,
      storeId: storeId,
      branchId: branchId,
    );
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
  }) async {
    final cleanDeviceId = deviceId.trim();
    if (cleanDeviceId.isEmpty) {
      return _openCashDrawerLocationFallback(branchId);
    }
    final branchFilter = branchId.trim().isEmpty ? '' : 'AND cds.branch_id = ?';
    final row = await _db.customSelect(
      '''
      SELECT cl.id, cl.name, cl.type, cl.account_id, cl.allow_negative
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
      allowNegative: _num(data['allow_negative']) != 0,
    );
  }

  static Future<_CashLocationSnapshot?> _openCashDrawerLocationFallback(
      String branchId) async {
    final branchFilter = branchId.trim().isEmpty ? '' : 'AND cds.branch_id = ?';
    final row = await _db.customSelect(
      '''
      SELECT cl.id, cl.name, cl.type, cl.account_id, cl.allow_negative
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
      allowNegative: _num(data['allow_negative']) != 0,
    );
  }

  static Future<void> _moveCashLocationBalance(
      String cashLocationId, double delta, DateTime movementDate) async {
    final id = cashLocationId.trim();
    if (id.isEmpty || delta.abs() < 0.01) return;
    await _db.customUpdate(
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
      final accounts = await readDefaultAccountMap();
      return _requiredAccount(accounts, 'default_cash_account_id');
    }
    final location = await _cashLocationSnapshot(id);
    return location.accountId;
  }

  static Future<_CashLocationSnapshot> _cashLocationSnapshot(
      String cashLocationId) async {
    final row = await _db.customSelect(
      '''
      SELECT id, name, type, account_id, allow_negative
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
      allowNegative: _num(data['allow_negative']) != 0,
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
    final accounts = await readDefaultAccountMap();
    if (type == 'bank') {
      return _requiredAccount(accounts, 'default_bank_account_id');
    }
    return _requiredAccount(accounts, 'default_cash_account_id');
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

  static Future<String> _paymentAccountId(
      Map<String, String> accounts, String paymentMethod) async {
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
            ? _requiredAccount(accounts, 'default_cash_account_id')
            : _requiredAccount(accounts, 'default_bank_account_id');
    _paymentAccountByTypeCache[normalizedType] = resolved;
    return resolved;
  }

  static Future<void> _assertDateNotInClosedPeriod(
      DateTime entryDate, String branchId) async {
    final row = await _db.customSelect(
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
             currency, is_system, is_active, description
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

class _CashLocationSnapshot {
  const _CashLocationSnapshot({
    required this.id,
    required this.name,
    required this.type,
    required this.accountId,
    required this.allowNegative,
  });

  final String id;
  final String name;
  final String type;
  final String accountId;
  final bool allowNegative;
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
  });

  final String accountId;
  final String accountCode;
  final String accountName;
  final String accountType;
  final double debit;
  final double credit;
  final double balance;
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
  });

  final String accountId;
  final String accountCode;
  final String accountName;
  final String accountType;
  final String normalBalance;
  final double totalDebit;
  final double totalCredit;
  final double closingBalance;
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
  });

  final String entryNo;
  final DateTime entryDate;
  final String referenceType;
  final String referenceNo;
  final String description;
  final String memo;
  final double debit;
  final double credit;
  final double runningBalance;
}

class IncomeStatementReport {
  const IncomeStatementReport({
    required this.revenue,
    required this.costOfGoodsSold,
    required this.grossProfit,
    required this.expenses,
    required this.netProfit,
  });

  final double revenue;
  final double costOfGoodsSold;
  final double grossProfit;
  final double expenses;
  final double netProfit;
}

class BalanceSheetReport {
  const BalanceSheetReport({
    required this.assets,
    required this.liabilities,
    required this.equity,
    required this.retainedEarnings,
    required this.liabilitiesAndEquity,
    required this.difference,
  });

  final double assets;
  final double liabilities;
  final double equity;
  final double retainedEarnings;
  final double liabilitiesAndEquity;
  final double difference;
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
