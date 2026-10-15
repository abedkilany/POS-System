part of 'accounting_service_impl.dart';

Future<CashFlowStatementReport> cashFlowStatementReport(
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
      currentReferenceType = entryRow.data['reference_type']?.toString() ?? '';
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

CashFlowCategory _cashFlowCategory(
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

Future<TaxReport> taxReport({DateTime? from, DateTime? to}) async {
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

  final outputTax = await sumAccount(salesTaxAccountId, 'jl.credit - jl.debit');
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
