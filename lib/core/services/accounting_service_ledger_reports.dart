part of 'accounting_service_impl.dart';

Future<List<JournalEntrySummaryReport>> listJournalEntrySummaries({
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

Future<List<JournalEntryDetailsReport>> journalEntryDetails({
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

Future<List<GeneralLedgerAccountReport>> generalLedgerReport({
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
      totalCredit:
          _roundMoney(lines.fold<double>(0, (sum, line) => sum + line.credit)),
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

Future<List<TrialBalanceRowReport>> _trialBalanceRows({
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

Future<List<TrialBalanceRowReport>> trialBalanceReport({
  DateTime? from,
  DateTime? to,
}) async {
  if (!isAvailable) return const <TrialBalanceRowReport>[];
  return _trialBalanceRows(from: from, to: to);
}

Future<IncomeStatementReport> incomeStatementReport({
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
  final manufacturingVariance =
      accountDebitNet(await resolveAccountRole('manufacturing_cost_variance'));
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

Future<BalanceSheetReport> balanceSheetReport({DateTime? asOf}) async {
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
      .where(
          (row) => row.accountType == 'liability' && isNonCurrentLiability(row))
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
