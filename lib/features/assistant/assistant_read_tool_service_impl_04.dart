part of 'assistant_read_tool_service.dart';

extension _AssistantReadToolServicePart4
    on _AssistantReadToolServiceImplementation {
  String _requiredPartyType(Map<String, Object?> arguments) {
    final value =
        _optionalStringArgument(arguments, 'party_type', maxLength: 16)
            .toLowerCase();
    if (value != 'customer' && value != 'supplier') {
      throw const AssistantReadToolException(
        'invalid_party_type',
        'Choose customer or supplier for this read request.',
      );
    }
    return value;
  }

  void _requirePartyLedgerPermission(ApplicationSession store, String partyType) {
    final allowed = partyType == 'customer'
        ? _canViewCustomerLedger(store)
        : _canViewSupplierLedger(store);
    if (!allowed) {
      throw const AssistantReadToolException(
        'permission_denied',
        'Your Ventio account does not have permission to read this party ledger.',
      );
    }
  }

  bool _invoiceMatches({
    required String query,
    required String normalizedQuery,
    required String documentId,
    required String documentNumber,
    required String partyName,
    required Iterable<String> productNames,
  }) {
    final normalizedId = documentId.trim().toLowerCase();
    final normalizedNumber = documentNumber.trim().toLowerCase();
    final normalizedRawQuery = query.trim().toLowerCase();
    if (normalizedId == normalizedRawQuery ||
        normalizedNumber == normalizedRawQuery) {
      return true;
    }
    if (normalizedQuery.isEmpty) return false;
    return _normalizePartyName(partyName).contains(normalizedQuery) ||
        productNames.any(
            (name) => _normalizePartyName(name).contains(normalizedQuery)) ||
        normalizedNumber.contains(normalizedRawQuery);
  }

  bool _invoiceNumberIsExact(
    String query,
    String documentId,
    String documentNumber,
  ) {
    final normalizedQuery = query.trim().toLowerCase();
    return documentId.trim().toLowerCase() == normalizedQuery ||
        documentNumber.trim().toLowerCase() == normalizedQuery;
  }

  bool _dateMatches(DateTime date, DateTime? from, DateTime? to) {
    final localDate = _localDateOnly(date);
    if (from != null && localDate.isBefore(_localDateOnly(from))) return false;
    if (to != null && localDate.isAfter(_localDateOnly(to))) return false;
    return true;
  }

  DateTime _localDateOnly(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  AssistantJsonMap _tool({
    required String name,
    required String description,
    required Map<String, Object?> properties,
    List<String> required = const <String>[],
  }) {
    return <String, Object?>{
      'name': name,
      'description': description,
      'parameters': <String, Object?>{
        'type': 'object',
        'properties': properties,
        'required': required,
        'additionalProperties': false,
      },
    };
  }

  bool _canViewAccounting(ApplicationSession store) => store.security.canViewAccounting;

  bool _canViewCustomerLedger(ApplicationSession store) =>
      store.security.hasAnyPermission(<String>{
        AppPermission.customersLedgerView,
        AppPermission.customersManage,
      });

  bool _canViewSupplierLedger(ApplicationSession store) =>
      store.security.hasAnyPermission(<String>{
        AppPermission.suppliersLedgerView,
        AppPermission.suppliersManage,
      });

  void _requireToolPermission(ApplicationSession store, String name) {
    final allowed = switch (name) {
      'income_statement' ||
      'balance_sheet' ||
      'trial_balance' ||
      'cash_flow_statement' ||
      'tax_summary' ||
      'customer_receivables_aging' ||
      'supplier_payables_aging' =>
        _canViewAccounting(store),
      'customer_account_statement' => _canViewCustomerLedger(store),
      'supplier_account_statement' => _canViewSupplierLedger(store),
      'sales_invoice_details' => store.security.canViewSales,
      'purchase_invoice_details' => store.security.canViewPurchases,
      'party_payment_history' =>
        _canViewCustomerLedger(store) || _canViewSupplierLedger(store),
      'party_balance_reconciliation' => _canViewAccounting(store) &&
          (_canViewCustomerLedger(store) || _canViewSupplierLedger(store)),
      'sales_summary' => store.security.canViewSales,
      'purchase_summary' => store.security.canViewPurchases,
      'expense_summary' => store.security.canViewExpenses,
      'current_stock_balances' ||
      'stock_movement_summary' =>
        store.security.canViewInventory || _canViewAccounting(store),
      'cash_balances' => store.security.canViewCashBox,
      'inventory_cost_valuation' ||
      'manufacturing_cost_summary' ||
      'manufacturing_waste' ||
      'inventory_count_variances' =>
        name == 'inventory_cost_valuation'
            ? store.security.canViewAccounting
            : store.security.canViewInventory || _canViewAccounting(store),
      'business_data_analysis' => store.security.canViewSales ||
          store.security.canViewPurchases ||
          store.security.canViewExpenses ||
          store.security.canViewInventory ||
          _canViewAccounting(store),
      'business_schema_catalog' ||
      'business_table_analysis' =>
        AssistantDatabaseExplorerService.canUse(store),
      _ => false,
    };
    if (!allowed) {
      throw const AssistantReadToolException(
        'permission_denied',
        'Your Ventio account does not have permission to read this information.',
      );
    }
  }

  void _requireReadDatabase() {
    if (!LocalDatabaseService.canQueryBusinessSqlite ||
        !AccountingService.isAvailable) {
      _throwBusinessDatabaseUnavailable();
    }
  }

  Never _throwBusinessDatabaseUnavailable() {
    throw const AssistantReadToolException(
      'business_database_unavailable',
      'Ventio business data is not available for a local read right now.',
    );
  }

  void _requireOnlyArguments(
    Map<String, Object?> arguments,
    Set<String> allowed,
  ) {
    final unexpected = arguments.keys.where((key) => !allowed.contains(key));
    if (unexpected.isNotEmpty) {
      throw const AssistantReadToolException(
        'invalid_arguments',
        'The assistant read request contains unsupported arguments.',
      );
    }
  }

  String _optionalStringArgument(
    Map<String, Object?> arguments,
    String key, {
    int maxLength = 120,
  }) {
    final raw = arguments[key];
    if (raw == null) return '';
    if (raw is! String || raw.length > maxLength) {
      throw AssistantReadToolException(
        'invalid_arguments',
        'The $key filter must be text of at most $maxLength characters.',
      );
    }
    return raw.trim();
  }

  String _normalizePartyName(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
      .replaceAll(RegExp(r'[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'\s+'), ' ');

  String _transactionCurrency(
    AccountTransaction transaction,
    ApplicationSession store,
  ) {
    final currency = transaction.currency.trim().toUpperCase();
    return currency.isEmpty ? store.runtime.profile.baseCurrency : currency;
  }

  int _compareAccountTransactions(
    AccountTransaction left,
    AccountTransaction right,
  ) {
    final byDate = left.date.compareTo(right.date);
    return byDate != 0 ? byDate : left.id.compareTo(right.id);
  }

  String _customerTransactionTypeLabel(String type) {
    switch (type) {
      case 'saleInvoice':
        return 'Sales invoice';
      case 'paymentReceived':
        return 'Payment received';
      case 'paymentReversal':
        return 'Payment reversal';
      case 'saleReturn':
      case 'salesReturn':
        return 'Sales return';
      case 'cancel':
        return 'Cancellation or reversal';
      case 'adjustment':
        return 'Account adjustment';
      default:
        return type.trim().isEmpty ? 'Other movement' : type;
    }
  }

  _AssistantDatePeriod _parsePeriod(Map<String, Object?> arguments) {
    final from = _parseOptionalDate(arguments, 'from');
    final to = _parseOptionalDate(arguments, 'to');
    if (from == null || to == null) {
      throw const AssistantReadToolException(
        'invalid_date_range',
        'Both a start date and an end date are required.',
      );
    }
    if (from.isAfter(to)) {
      throw const AssistantReadToolException(
        'invalid_date_range',
        'The start date must be on or before the end date.',
      );
    }
    return _AssistantDatePeriod(
      from: from,
      toInclusive: _endOfDay(to),
      fromLabel: _dateLabel(from),
      toLabel: _dateLabel(to),
    );
  }

  DateTime? _parseOptionalDate(
    Map<String, Object?> arguments,
    String key,
  ) {
    final raw = arguments[key];
    if (raw == null) return null;
    if (raw is! String) {
      throw AssistantReadToolException(
        'invalid_date',
        'The $key value must use YYYY-MM-DD format.',
      );
    }
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw.trim());
    if (match == null) {
      throw AssistantReadToolException(
        'invalid_date',
        'The $key value must use YYYY-MM-DD format.',
      );
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      throw AssistantReadToolException(
        'invalid_date',
        'The $key value is not a valid calendar date.',
      );
    }
    return parsed;
  }

  DateTime _endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day + 1)
          .subtract(const Duration(microseconds: 1));

  String _dateLabel(DateTime date) {
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  List<AssistantJsonMap> _statementLines(
    List<FinancialStatementAccountLine> lines,
  ) {
    return lines.take(_maxReturnedRows).map((line) {
      return <String, Object?>{
        'accountCode': line.accountCode,
        'accountName': line.accountName,
        'accountType': line.accountType,
        'accountSubtype': line.accountSubtype,
        'amount': line.amount,
      };
    }).toList(growable: false);
  }

  AssistantJsonMap _envelope(
    ApplicationSession store,
    String tool,
    DateTime generatedAt, {
    required AssistantJsonMap data,
    required String source,
    _AssistantDatePeriod? period,
    DateTime? asOf,
  }) {
    return <String, Object?>{
      'tool': tool,
      'source': source,
      'generatedAtUtc': generatedAt.toUtc().toIso8601String(),
      'localTimezoneOffsetMinutes': generatedAt.timeZoneOffset.inMinutes,
      'dateBasis': 'device_local_calendar',
      'baseCurrency': store.runtime.profile.baseCurrency,
      'deviceRole': store.runtime.identity.deviceRole.name,
      'branchFilterApplied': false,
      if (store.runtime.identity.isClient) 'dataFreshness': 'client_local_copy',
      if (period != null)
        'period': <String, Object?>{
          'from': period.fromLabel,
          'to': period.toLabel,
        },
      if (asOf != null) 'asOf': _dateLabel(asOf),
      'data': data,
    };
  }
}
