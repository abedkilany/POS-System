import 'dart:math';

import 'package:drift/drift.dart';

import '../../models/account_transaction.dart';
import '../../models/accounting_account.dart';
import '../../models/expense.dart';
import '../../models/journal_entry.dart';
import '../../models/purchase.dart';
import '../../models/sale.dart';
import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/ventio_drift_database.dart';

class AccountingService {
  AccountingService._();

  static final Random _random = Random.secure();

  static VentioDriftDatabase get _db {
    final database = SqliteMigrationManager.database;
    if (database == null) {
      throw StateError('SQLite database is not initialized.');
    }
    return database;
  }

  static Future<List<AccountingAccount>> listAccounts({
    bool activeOnly = true,
  }) async {
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

  static Future<Map<String, String>> readDefaultAccountMap() async {
    final rows = await _db.customSelect(
      '''
      SELECT key, account_id
      FROM accounting_settings
      WHERE key LIKE 'default_%_account_id'
      ORDER BY key
      ''',
    ).get();
    return <String, String>{
      for (final row in rows)
        row.data['key'].toString(): row.data['account_id'].toString(),
    };
  }


  static Future<void> updateDefaultAccount({
    required String key,
    required String accountId,
  }) async {
    final normalizedKey = key.trim();
    final normalizedAccountId = accountId.trim();
    if (normalizedKey.isEmpty || !normalizedKey.startsWith('default_') || !normalizedKey.endsWith('_account_id')) {
      throw ArgumentError('Invalid accounting setting key: $key');
    }
    if (normalizedAccountId.isEmpty) {
      throw ArgumentError('Account is required.');
    }
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
    await _writeAuditLog(
      action: 'update_setting',
      entityType: 'accounting_setting',
      entityId: normalizedKey,
      details: 'Mapped $normalizedKey to $normalizedAccountId',
    );
  }

  static Future<void> recordSale(Sale sale) async {
    if (sale.isDeleted || sale.isCancelled || sale.total <= 0) return;
    final accounts = await readDefaultAccountMap();
    final invoiceTotal = _cleanAmount(sale.invoiceTotal);
    final saleTotal = _cleanAmount(sale.total);
    final paidInInvoiceCurrency = _cleanAmount(sale.paidAmount.clamp(0, invoiceTotal).toDouble());
    final paid = invoiceTotal <= 0
        ? 0.0
        : _cleanAmount(saleTotal * (paidInInvoiceCurrency / invoiceTotal));
    final balance = _cleanAmount(saleTotal - paid);
    final cogs = _cleanAmount(sale.items.fold<double>(0, (sum, item) => sum + item.lineCost));
    final lines = <JournalLineDraft>[];

    if (paid > 0) {
      lines.add(JournalLineDraft(
        accountId: await _paymentAccountId(accounts, sale.paymentMethod),
        debit: paid,
        credit: 0,
        memo: 'Payment received for sale ${sale.invoiceNo}',
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
        memo: 'Amount due from customer for sale ${sale.invoiceNo}',
        partyType: 'customer',
        partyId: sale.customerId,
        partyName: sale.customerName,
      ));
    }
    lines.add(JournalLineDraft(
      accountId: _requiredAccount(accounts, 'default_sales_account_id'),
      debit: 0,
      credit: saleTotal,
      memo: 'Sales revenue ${sale.invoiceNo}',
    ));
    if (cogs > 0) {
      lines
        ..add(JournalLineDraft(
          accountId: _requiredAccount(accounts, 'default_cogs_account_id'),
          debit: cogs,
          credit: 0,
          memo: 'Cost of goods sold ${sale.invoiceNo}',
        ))
        ..add(JournalLineDraft(
          accountId: _requiredAccount(accounts, 'default_inventory_account_id'),
          debit: 0,
          credit: cogs,
          memo: 'Inventory issued for sale ${sale.invoiceNo}',
        ));
    }
    await createPostedEntry(JournalEntryDraft(
      entryDate: sale.date,
      referenceType: 'sale',
      referenceId: sale.id,
      referenceNo: sale.invoiceNo,
      description: 'Sale invoice ${sale.invoiceNo}',
      createdBy: sale.lastModifiedByDeviceId,
      storeId: sale.storeId,
      branchId: sale.branchId,
      lines: lines,
    ));
  }

  static Future<void> recordPurchase(Purchase purchase) async {
    if (purchase.isDeleted || purchase.isCancelled || purchase.subtotal <= 0) return;
    final accounts = await readDefaultAccountMap();
    final total = _cleanAmount(purchase.subtotal);
    final paid = _cleanAmount(purchase.paidAmount.clamp(0, total).toDouble());
    final balance = _cleanAmount(total - paid);
    final lines = <JournalLineDraft>[
      JournalLineDraft(
        accountId: _requiredAccount(accounts, 'default_inventory_account_id'),
        debit: total,
        credit: 0,
        memo: 'Inventory received from purchase ${purchase.purchaseNo}',
        partyType: 'supplier',
        partyId: purchase.supplierId,
        partyName: purchase.supplierName,
      ),
    ];
    if (paid > 0) {
      lines.add(JournalLineDraft(
        accountId: await _paymentAccountId(accounts, purchase.paymentMethod),
        debit: 0,
        credit: paid,
        memo: 'Payment paid for purchase ${purchase.purchaseNo}',
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
        memo: 'Amount due to supplier for purchase ${purchase.purchaseNo}',
        partyType: 'supplier',
        partyId: purchase.supplierId,
        partyName: purchase.supplierName,
      ));
    }
    await createPostedEntry(JournalEntryDraft(
      entryDate: purchase.date,
      referenceType: 'purchase',
      referenceId: purchase.id,
      referenceNo: purchase.purchaseNo,
      description: 'Purchase invoice ${purchase.purchaseNo}',
      createdBy: purchase.lastModifiedByDeviceId,
      storeId: purchase.storeId,
      branchId: purchase.branchId,
      lines: lines,
    ));
  }

  static Future<void> recordExpense(Expense expense) async {
    if (expense.isDeleted || !expense.isPosted || expense.amount <= 0) return;
    final accounts = await readDefaultAccountMap();
    await createPostedEntry(JournalEntryDraft(
      entryDate: expense.date,
      referenceType: 'expense',
      referenceId: expense.id,
      referenceNo: expense.title,
      description: 'Expense: ${expense.title}',
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
          accountId: await _paymentAccountId(accounts, 'cash'),
          debit: 0,
          credit: expense.amount,
          memo: 'Expense payment',
        ),
      ],
    ));
  }

  static Future<void> recordAccountPayment(AccountTransaction transaction) async {
    if (transaction.isDeleted) return;
    final accounts = await readDefaultAccountMap();
    final isCustomerPayment = transaction.isCustomer && transaction.credit > 0;
    final isSupplierPayment = transaction.isSupplier && transaction.debit > 0;
    if (!isCustomerPayment && !isSupplierPayment) return;
    final amount = _cleanAmount(isCustomerPayment ? transaction.credit : transaction.debit);
    if (amount <= 0) return;
    final paymentAccount = await _paymentAccountId(accounts, transaction.paymentMethod);
    final controlAccount = _requiredAccount(
      accounts,
      isCustomerPayment ? 'default_customers_account_id' : 'default_suppliers_account_id',
    );
    await createPostedEntry(JournalEntryDraft(
      entryDate: transaction.date,
      referenceType: isCustomerPayment ? 'customer_payment' : 'supplier_payment',
      referenceId: transaction.id,
      referenceNo: transaction.referenceNo,
      description: isCustomerPayment
          ? 'Customer payment ${transaction.referenceNo}'
          : 'Supplier payment ${transaction.referenceNo}',
      createdBy: transaction.lastModifiedByDeviceId,
      storeId: transaction.storeId,
      branchId: transaction.branchId,
      lines: isCustomerPayment
          ? <JournalLineDraft>[
              JournalLineDraft(
                accountId: paymentAccount,
                debit: amount,
                credit: 0,
                memo: 'Customer payment received',
                partyType: 'customer',
                partyId: transaction.accountId,
                partyName: transaction.accountName,
              ),
              JournalLineDraft(
                accountId: controlAccount,
                debit: 0,
                credit: amount,
                memo: 'Reduce customer receivable',
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
                memo: 'Reduce supplier payable',
                partyType: 'supplier',
                partyId: transaction.accountId,
                partyName: transaction.accountName,
              ),
              JournalLineDraft(
                accountId: paymentAccount,
                debit: 0,
                credit: amount,
                memo: 'Supplier payment paid',
                partyType: 'supplier',
                partyId: transaction.accountId,
                partyName: transaction.accountName,
              ),
            ],
    ));
  }

  static Future<void> createPostedEntry(JournalEntryDraft draft) async {
    _validateBalancedDraft(draft);
    await _assertDateNotInClosedPeriod(draft.entryDate, draft.branchId);
    final db = _db;
    if (await _hasActiveEntryForReference(db, draft.referenceType, draft.referenceId)) {
      return;
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
        details: 'Posted balanced journal entry $entryNo',
        createdBy: draft.createdBy,
        storeId: draft.storeId,
        branchId: draft.branchId,
        createdAt: now,
      );
    });
  }

  static Future<void> reverseEntryForReference({
    required String referenceType,
    required String referenceId,
    String reason = '',
    String createdBy = '',
  }) async {
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
        memo: 'Reversal: ${data['memo']?.toString() ?? ''}',
        partyType: data['party_type']?.toString() ?? '',
        partyId: data['party_id']?.toString() ?? '',
        partyName: data['party_name']?.toString() ?? '',
        costCenterId: data['cost_center_id']?.toString() ?? '',
      );
    }).toList();
    _validateBalancedDraft(JournalEntryDraft(
      entryDate: DateTime.now(),
      description: 'Reversal validation',
      lines: reversalLines,
    ));

    final now = DateTime.now().toUtc().toIso8601String();
    final reversalId = _newId('je');
    final entryNo = await _nextEntryNo(db, DateTime.now());
    final storeId = original['store_id']?.toString() ?? '';
    final branchId = original['branch_id']?.toString() ?? '';
    final actor = createdBy.trim().isNotEmpty ? createdBy.trim() : (original['created_by']?.toString() ?? '');
    final originalEntryNo = original['entry_no']?.toString() ?? '';
    final description = reason.trim().isEmpty
        ? 'Reversal of journal entry $originalEntryNo'
        : 'Reversal of journal entry $originalEntryNo: ${reason.trim()}';

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
    final accountRows = await _db.customSelect(
      '''
      SELECT id, code, name, type, normal_balance
      FROM accounts
      WHERE deleted_at = '' AND is_active = 1
      ORDER BY code
      ''',
    ).get();

    final accounts = <GeneralLedgerAccountReport>[];
    for (final accountRow in accountRows) {
      final accountId = accountRow.data['id']?.toString() ?? '';
      final lineRows = await _db.customSelect(
        '''
        SELECT jl.entry_id, jl.line_no, jl.debit, jl.credit, jl.memo,
               je.entry_no, je.entry_date, je.reference_type, je.reference_no,
               je.description
        FROM journal_lines jl
        INNER JOIN journal_entries je ON je.id = jl.entry_id
        WHERE jl.account_id = ?
          AND je.deleted_at = ''
          AND je.status = 'posted'
        ORDER BY je.entry_date, je.entry_no, jl.line_no
        ''',
        variables: <Variable<Object>>[Variable<String>(accountId)],
      ).get();

      var runningBalance = 0.0;
      final normalBalance = accountRow.data['normal_balance']?.toString() ?? 'debit';
      final lines = <GeneralLedgerLineReport>[];
      for (final row in lineRows) {
        final debit = _num(row.data['debit']);
        final credit = _num(row.data['credit']);
        runningBalance += normalBalance == 'credit' ? credit - debit : debit - credit;
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

      accounts.add(GeneralLedgerAccountReport(
        accountId: accountId,
        accountCode: accountRow.data['code']?.toString() ?? '',
        accountName: accountRow.data['name']?.toString() ?? '',
        accountType: accountRow.data['type']?.toString() ?? '',
        normalBalance: normalBalance,
        totalDebit: _roundMoney(lines.fold<double>(0, (sum, line) => sum + line.debit)),
        totalCredit: _roundMoney(lines.fold<double>(0, (sum, line) => sum + line.credit)),
        closingBalance: _roundMoney(runningBalance),
        lines: lines,
      ));
    }
    return accounts;
  }

  static Future<List<TrialBalanceRowReport>> trialBalanceReport() async {
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
    }).toList();
  }

  static Future<IncomeStatementReport> incomeStatementReport() async {
    final rows = await trialBalanceReport();
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
    final rows = await trialBalanceReport();
    double sumByType(String type) => rows
        .where((row) => row.accountType == type)
        .fold<double>(0, (sum, row) => sum + row.balance.abs());
    final assets = sumByType('asset');
    final liabilities = sumByType('liability');
    final equity = sumByType('equity');
    final income = await incomeStatementReport();
    return BalanceSheetReport(
      assets: _roundMoney(assets),
      liabilities: _roundMoney(liabilities),
      equity: _roundMoney(equity),
      retainedEarnings: _roundMoney(income.netProfit),
      liabilitiesAndEquity: _roundMoney(liabilities + equity + income.netProfit),
      difference: _roundMoney(assets - liabilities - equity - income.netProfit),
    );
  }

  static Future<List<CashBankMovementReport>> cashBankMovementReport() async {
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


  static Future<List<AdvancedAccountingItem>> listPaymentAccounts() async {
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

  static Future<List<AdvancedAccountingItem>> listCashDrawers() async {
    final rows = await _db.customSelect(
      '''
      SELECT id, drawer_no AS name, status AS type, status, opened_at AS account_name,
             opening_balance AS debit, expected_cash AS credit,
             difference AS balance, notes
      FROM cash_drawer_sessions
      ORDER BY opened_at DESC
      LIMIT 50
      ''',
    ).get();
    return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
  }

  static Future<List<AdvancedAccountingItem>> listCheques() async {
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

  static Future<void> createManualJournalEntry({
    required DateTime entryDate,
    required String description,
    required List<JournalLineDraft> lines,
    String createdBy = '',
    String storeId = '',
    String branchId = '',
  }) async {
    await createPostedEntry(JournalEntryDraft(
      entryDate: entryDate,
      referenceType: 'manual_journal',
      referenceId: _newId('manual'),
      referenceNo: 'Manual',
      description: description.trim().isEmpty ? 'Manual journal entry' : description.trim(),
      source: 'manual',
      createdBy: createdBy,
      storeId: storeId,
      branchId: branchId,
      lines: lines,
    ));
  }

  static Future<void> openCashDrawer({
    required String drawerNo,
    required double openingBalance,
    String openedBy = '',
    String storeId = '',
    String branchId = '',
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.customInsert(
      '''
      INSERT INTO cash_drawer_sessions
        (id, drawer_no, opened_at, status, opening_balance, expected_cash,
         notes, opened_by, store_id, branch_id)
      VALUES (?, ?, ?, 'open', ?, ?, '', ?, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(_newId('drawer')),
        Variable<String>(drawerNo.trim().isEmpty ? 'Drawer' : drawerNo.trim()),
        Variable<String>(now),
        Variable<double>(_roundMoney(openingBalance)),
        Variable<double>(_roundMoney(openingBalance)),
        Variable<String>(openedBy),
        Variable<String>(storeId),
        Variable<String>(branchId),
      ],
    );
    await _writeAuditLog(action: 'open_cash_drawer', entityType: 'cash_drawer', details: drawerNo, createdBy: openedBy, storeId: storeId, branchId: branchId);
  }

  static Future<void> closeCashDrawer({
    required String sessionId,
    required double countedCash,
    String closedBy = '',
    String notes = '',
  }) async {
    final row = await _db.customSelect(
      "SELECT expected_cash, store_id, branch_id FROM cash_drawer_sessions WHERE id = ? AND status = 'open' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(sessionId)],
    ).getSingleOrNull();
    if (row == null) return;
    final expected = _num(row.data['expected_cash']);
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.customUpdate(
      '''
      UPDATE cash_drawer_sessions
      SET status = 'closed', closed_at = ?, counted_cash = ?, difference = ?,
          closed_by = ?, notes = ?
      WHERE id = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<double>(_roundMoney(countedCash)),
        Variable<double>(_roundMoney(countedCash - expected)),
        Variable<String>(closedBy),
        Variable<String>(notes),
        Variable<String>(sessionId),
      ],
    );
    await _writeAuditLog(action: 'close_cash_drawer', entityType: 'cash_drawer', entityId: sessionId, details: 'Difference: ${_roundMoney(countedCash - expected)}', createdBy: closedBy, storeId: row.data['store_id']?.toString() ?? '', branchId: row.data['branch_id']?.toString() ?? '');
  }

  static Future<void> createAccountingPeriod({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    String createdBy = '',
    String storeId = '',
    String branchId = '',
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.customInsert(
      '''
      INSERT INTO accounting_periods
        (id, name, start_date, end_date, status, created_at, updated_at, store_id, branch_id)
      VALUES (?, ?, ?, ?, 'open', ?, ?, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(_newId('period')),
        Variable<String>(name.trim().isEmpty ? 'Accounting Period' : name.trim()),
        Variable<String>(startDate.toUtc().toIso8601String()),
        Variable<String>(endDate.toUtc().toIso8601String()),
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(storeId),
        Variable<String>(branchId),
      ],
    );
    await _writeAuditLog(action: 'create_period', entityType: 'accounting_period', details: name, createdBy: createdBy, storeId: storeId, branchId: branchId);
  }

  static Future<void> closeAccountingPeriod({required String periodId, String closedBy = ''}) async {
    final row = await _db.customSelect(
      'SELECT start_date, end_date, status, store_id, branch_id FROM accounting_periods WHERE id = ? LIMIT 1',
      variables: <Variable<Object>>[Variable<String>(periodId)],
    ).getSingleOrNull();
    if (row == null || row.data['status']?.toString() == 'closed') return;
    final trialBalance = await trialBalanceReport();
    final totalDebit = trialBalance.fold<double>(0, (sum, row) => sum + row.debit);
    final totalCredit = trialBalance.fold<double>(0, (sum, row) => sum + row.credit);
    if ((totalDebit - totalCredit).abs() > 0.0001) {
      throw StateError('Cannot close period while trial balance is not balanced.');
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
    await _writeAuditLog(action: 'close_period', entityType: 'accounting_period', entityId: periodId, details: 'Closed balanced accounting period', createdBy: closedBy, storeId: row.data['store_id']?.toString() ?? '', branchId: row.data['branch_id']?.toString() ?? '');
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
    await _accountSnapshot(_db, accountId);
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.transaction(() async {
      if (isDefault) {
        await _db.customUpdate(
          "UPDATE payment_accounts SET is_default = 0, updated_at = ? WHERE type = ? AND deleted_at = ''",
          variables: <Variable<Object>>[Variable<String>(now), Variable<String>(type)],
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
    await _writeAuditLog(action: 'create_payment_account', entityType: 'payment_account', details: name, storeId: storeId, branchId: branchId);
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
    if (_cleanAmount(amount) <= 0) throw ArgumentError('Cheque amount is required.');
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
    await _writeAuditLog(action: 'create_cheque', entityType: 'cheque', details: chequeNo, storeId: storeId, branchId: branchId);
  }

  static Future<void> settleCheque({required String chequeId, String settledBy = ''}) async {
    final row = await _db.customSelect(
      "SELECT * FROM cheques WHERE id = ? AND status = 'pending' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(chequeId)],
    ).getSingleOrNull();
    if (row == null) return;
    final data = row.data;
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.customUpdate(
      "UPDATE cheques SET status = 'cleared', updated_at = ? WHERE id = ?",
      variables: <Variable<Object>>[Variable<String>(now), Variable<String>(chequeId)],
    );
    await _writeAuditLog(action: 'clear_cheque', entityType: 'cheque', entityId: chequeId, details: data['cheque_no']?.toString() ?? '', createdBy: settledBy, storeId: data['store_id']?.toString() ?? '', branchId: data['branch_id']?.toString() ?? '');
  }

  static Future<void> bounceCheque({required String chequeId, String reason = '', String actor = ''}) async {
    final row = await _db.customSelect(
      "SELECT cheque_no, store_id, branch_id FROM cheques WHERE id = ? AND status = 'pending' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(chequeId)],
    ).getSingleOrNull();
    if (row == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.customUpdate(
      "UPDATE cheques SET status = 'bounced', notes = notes || ?, updated_at = ? WHERE id = ?",
      variables: <Variable<Object>>[Variable<String>('\nBounced: $reason'), Variable<String>(now), Variable<String>(chequeId)],
    );
    await _writeAuditLog(action: 'bounce_cheque', entityType: 'cheque', entityId: chequeId, details: reason, createdBy: actor, storeId: row.data['store_id']?.toString() ?? '', branchId: row.data['branch_id']?.toString() ?? '');
  }

  static Future<void> createSimpleMasterData({
    required String table,
    required String code,
    required String name,
  }) async {
    if (table != 'cost_centers' && table != 'accounting_branches') {
      throw ArgumentError('Unsupported accounting master data table: $table');
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
    await _writeAuditLog(action: 'create_master_data', entityType: table, details: '$code - $name');
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
    if (referenceType.trim().isEmpty || referenceId.trim().isEmpty) return false;
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
      throw StateError('Missing accounting setting: $key');
    }
    return accountId;
  }

  static Future<String> _paymentAccountId(Map<String, String> accounts, String paymentMethod) async {
    final method = paymentMethod.trim().toLowerCase();
    final normalizedType = switch (method) {
      'cash' || 'credit' || '' => 'cash',
      'card' || 'visa' || 'mastercard' || 'bank' || 'transfer' => 'bank',
      'wish' || 'wallet' || 'online' => 'wallet',
      'check' || 'cheque' => 'cheque',
      _ => 'other',
    };
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
    if (accountId.isNotEmpty) return accountId;
    if (normalizedType == 'cash') return _requiredAccount(accounts, 'default_cash_account_id');
    return _requiredAccount(accounts, 'default_bank_account_id');
  }

  static Future<void> _assertDateNotInClosedPeriod(DateTime entryDate, String branchId) async {
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
      throw StateError('Cannot post accounting entry inside closed period: ${row.data['name']}.');
    }
  }

  static void _validateBalancedDraft(JournalEntryDraft draft) {
    if (draft.lines.length < 2) {
      throw ArgumentError('A journal entry must have at least two lines.');
    }
    final debit = draft.lines.fold<double>(0, (sum, line) => sum + _cleanAmount(line.debit));
    final credit = draft.lines.fold<double>(0, (sum, line) => sum + _cleanAmount(line.credit));
    if ((debit - credit).abs() > 0.0001 || debit <= 0) {
      throw ArgumentError('Journal entry is not balanced.');
    }
    for (final line in draft.lines) {
      final hasDebit = _cleanAmount(line.debit) > 0;
      final hasCredit = _cleanAmount(line.credit) > 0;
      if (line.accountId.trim().isEmpty || hasDebit == hasCredit) {
        throw ArgumentError('Each journal line must have one account and either debit or credit.');
      }
    }
  }

  static Future<AccountingAccount> _accountSnapshot(
    VentioDriftDatabase db,
    String accountId,
  ) async {
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
      throw ArgumentError('Accounting account not found: $accountId');
    }
    return AccountingAccount.fromRow(row.data);
  }

  static Future<String> _nextEntryNo(
    VentioDriftDatabase db,
    DateTime date,
  ) async {
    final prefix = 'JE-${date.toUtc().year}-';
    final row = await db.customSelect(
      'SELECT COUNT(*) AS count FROM journal_entries WHERE entry_no LIKE ?',
      variables: <Variable<Object>>[Variable<String>('$prefix%')],
    ).getSingle();
    final count = (row.data['count'] as int? ?? 0) + 1;
    return '$prefix${count.toString().padLeft(6, '0')}';
  }

  static DateTime _parseDate(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);

  static double _num(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _roundMoney(double value) => (value * 100).roundToDouble() / 100;

  static String _newId(String prefix) =>
      '${prefix}_${DateTime.now().toUtc().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';

  static double _cleanAmount(double value) => value.isFinite && value > 0 ? value : 0;
}



class AdvancedAccountingItem {
  const AdvancedAccountingItem({
    required this.id,
    required this.name,
    this.type = '',
    this.accountCode = '',
    this.accountName = '',
    this.status = '',
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
      return value?.toString() == '1' || value?.toString().toLowerCase() == 'true';
    }
    return AdvancedAccountingItem(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      type: row['type']?.toString() ?? '',
      accountCode: row['account_code']?.toString() ?? '',
      accountName: row['account_name']?.toString() ?? '',
      status: row['status']?.toString() ?? '',
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
