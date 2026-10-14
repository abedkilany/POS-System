import '../../core/services/accounting_aging_service.dart';
import '../../core/services/accounting_service.dart';
import '../../core/services/local_database_service.dart';
import '../../core/services/payment_voucher_service.dart';
import '../../core/storage/sqlite/sqlite_migration_manager.dart';
import '../../data/app_store.dart';
import '../../models/account_transaction.dart';
import '../../models/payment_allocation.dart';
import '../../models/payment_voucher.dart';
import '../../models/purchase.dart';
import '../../models/receipt_voucher.dart';
import '../../models/sale.dart';
import '../../models/user_role.dart';
import 'assistant_provider.dart';
import 'assistant_business_analysis_service.dart';
import 'assistant_database_explorer_service.dart';

class AssistantReadToolException implements Exception {
  const AssistantReadToolException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Provider-neutral, read-only tools that the assistant may request.
///
/// Provider adapters should translate [definitionsFor] to each provider's
/// function-calling format, then pass returned calls to [execute]. The active
/// user's permissions are checked both when definitions are offered and again
/// immediately before each local database read.
class AssistantReadToolService {
  AssistantReadToolService._();

  static const int _maxReturnedRows = 100;
  static const int _maxCustomerStatementRows = 40;
  static const int _maxInvoiceMatches = 8;
  static const int _maxInvoiceLines = 20;
  static const int _maxPaymentHistoryRows = 40;
  static const int _maxPaymentHistoryPages = 10;
  static const Set<String> _knownToolNames = <String>{
    'income_statement',
    'balance_sheet',
    'trial_balance',
    'cash_flow_statement',
    'tax_summary',
    'sales_summary',
    'purchase_summary',
    'expense_summary',
    'current_stock_balances',
    'stock_movement_summary',
    'customer_receivables_aging',
    'customer_account_statement',
    'supplier_account_statement',
    'sales_invoice_details',
    'purchase_invoice_details',
    'party_payment_history',
    'party_balance_reconciliation',
    'supplier_payables_aging',
    'cash_balances',
    'inventory_cost_valuation',
    'manufacturing_cost_summary',
    'manufacturing_waste',
    'inventory_count_variances',
    'business_data_analysis',
    'business_schema_catalog',
    'business_table_analysis',
  };

  static List<AssistantJsonMap> definitionsFor(AppStore store) {
    if (!LocalDatabaseService.canQueryBusinessSqlite ||
        !AccountingService.isAvailable) {
      return const <AssistantJsonMap>[];
    }
    final tools = <AssistantJsonMap>[];
    if (store.canViewAccounting) {
      tools.addAll(<AssistantJsonMap>[
        _tool(
          name: 'income_statement',
          description:
              'Read Ventio\'s accounting income statement for an inclusive date range.',
          properties: _periodProperties,
          required: const <String>['from', 'to'],
        ),
        _tool(
          name: 'balance_sheet',
          description:
              'Read Ventio\'s accounting balance sheet as of a date. Defaults to today.',
          properties: _asOfProperties,
        ),
        _tool(
          name: 'trial_balance',
          description:
              'Read Ventio\'s accounting trial balance for an inclusive date range.',
          properties: _periodProperties,
          required: const <String>['from', 'to'],
        ),
        _tool(
          name: 'cash_flow_statement',
          description:
              'Read Ventio\'s cash flow statement for an inclusive date range.',
          properties: _periodProperties,
          required: const <String>['from', 'to'],
        ),
        _tool(
          name: 'tax_summary',
          description:
              'Read posted output tax, input tax, and net tax for an inclusive date range.',
          properties: _periodProperties,
          required: const <String>['from', 'to'],
        ),
        _tool(
          name: 'customer_receivables_aging',
          description:
              'Read gross positive open balances customers owe Ventio, grouped by aging bucket, as of a date. Customer credit balances are not netted into this aging total; use the balance sheet or trial balance for a net control-account balance. The top-level total and bucket totals are authoritative. Defaults to today.',
          properties: _asOfProperties,
        ),
        _tool(
          name: 'supplier_payables_aging',
          description:
              'Read gross positive open balances Ventio owes suppliers, grouped by aging bucket, as of a date. Supplier debit balances are not netted into this aging total; use the balance sheet or trial balance for a net control-account balance. The top-level total and bucket totals are authoritative. Defaults to today.',
          properties: _asOfProperties,
        ),
      ]);
    }
    if (_canViewCustomerLedger(store)) {
      tools.add(_tool(
        name: 'customer_account_statement',
        description:
            'Read a named customer\'s account statement from Ventio\'s read-only customer ledger. Use this for requests about a customer statement, account history, invoices, receipts, or movements; do not answer those requests with only an aging balance. The customer name is required; from and to are optional and default to the customer\'s full available history through today. Returns opening balance, movement totals, closing balance, current ledger balance, and dated transaction rows. If multiple currencies occur, keep their summaries separate.',
        properties: _customerStatementProperties,
        required: const <String>['customer'],
      ));
    }
    if (_canViewSupplierLedger(store)) {
      tools.add(_tool(
        name: 'supplier_account_statement',
        description:
            'Read a named supplier\'s account statement from Ventio\'s read-only supplier ledger. Use this for requests about supplier statements, account history, purchase payments, or movements. The supplier name is required; from and to are optional and default to the supplier\'s available history through today. Returns opening balance, movement totals, closing balance, current ledger balance, and dated transaction rows. If multiple currencies occur, keep their summaries separate.',
        properties: _supplierStatementProperties,
        required: const <String>['supplier'],
      ));
    }
    if (store.canViewSales) {
      tools.add(_tool(
        name: 'sales_invoice_details',
        description:
            'Read saved sales invoices by invoice number, customer name, or product name. Returns invoice status, currency, totals, paid and due amounts, returns, and line details. Does not include deleted invoices.',
        properties: _invoiceSearchProperties,
        required: const <String>['query'],
      ));
    }
    if (store.canViewPurchases) {
      tools.add(_tool(
        name: 'purchase_invoice_details',
        description:
            'Read saved purchase documents by purchase number, supplier name, or product name. Returns document status and type, totals, paid and due amounts, source purchase, and line details. Does not include deleted documents.',
        properties: _invoiceSearchProperties,
        required: const <String>['query'],
      ));
    }
    if (_canViewCustomerLedger(store) || _canViewSupplierLedger(store)) {
      tools.add(_tool(
        name: 'party_payment_history',
        description:
            'Read a named customer receipt history or supplier payment history, including active allocations to invoices, unallocated balances, currency, method, and reversal status. Use party_type customer or supplier and the exact or partial party name. Optional date range defaults to all available history through today.',
        properties: _partyPaymentHistoryProperties,
        required: const <String>['party_type', 'party'],
      ));
    }
    if (store.canViewAccounting &&
        (_canViewCustomerLedger(store) || _canViewSupplierLedger(store))) {
      tools.add(_tool(
        name: 'party_balance_reconciliation',
        description:
            'Compare a named customer or supplier subledger balance with Ventio\'s accounting aging report as of a date. Return both source figures, open documents, currency basis, and a calculated comparison only when the currencies and balance meanings are comparable. Keep gross aging separate from credits or advances.',
        properties: _partyAsOfProperties,
        required: const <String>['party_type', 'party'],
      ));
    }
    if (store.canViewSales) {
      tools.add(_tool(
        name: 'sales_summary',
        description:
            'Read non-cancelled sales invoice counts and gross saved base amounts by base currency for an inclusive date range. Use income_statement for accounting revenue and returns.',
        properties: _periodProperties,
        required: const <String>['from', 'to'],
      ));
    }
    if (store.canViewPurchases) {
      tools.add(_tool(
        name: 'purchase_summary',
        description:
            'Read received purchase and purchase-return counts and amounts in USD reference value for an inclusive date range. Draft and cancelled purchases are excluded.',
        properties: _periodProperties,
        required: const <String>['from', 'to'],
      ));
    }
    if (store.canViewExpenses) {
      tools.add(_tool(
        name: 'expense_summary',
        description:
            'Read posted expense totals and category totals in USD reference value for an inclusive date range. Draft, cancelled, and deleted expenses are excluded.',
        properties: _periodProperties,
        required: const <String>['from', 'to'],
      ));
    }
    if (store.canViewCashBox) {
      tools.add(_tool(
        name: 'cash_balances',
        description: 'Read current Ventio cash and bank balances.',
        properties: const <String, Object?>{},
      ));
    }
    if (store.canViewAccounting) {
      tools.add(_tool(
        name: 'inventory_cost_valuation',
        description:
            'Read current Ventio inventory quantities and accounting cost valuation for all stored dates. This is cost value, not retail value.',
        properties: const <String, Object?>{},
      ));
    }
    if (store.canViewInventory || store.canViewAccounting) {
      tools.add(_tool(
        name: 'current_stock_balances',
        description:
            'Read current quantities by product, warehouse, and branch. Optional product and warehouse filters match names or IDs. Quantities are not combined across products.',
        properties: _stockBalanceProperties,
      ));
      tools.add(_tool(
        name: 'stock_movement_summary',
        description:
            'Read stock movement totals for an inclusive date range, grouped by product, warehouse, branch, and movement type. Net quantities stay within each product group; recorded value changes use USD reference unit costs.',
        properties: _stockMovementProperties,
        required: const <String>['from', 'to'],
      ));
    }
    if (store.canViewInventory || store.canViewAccounting) {
      tools.add(_tool(
        name: 'manufacturing_cost_summary',
        description:
            'Read costs from all completed or otherwise reportable Ventio manufacturing orders. No date filter is available yet.',
        properties: const <String, Object?>{},
      ));
      tools.add(_tool(
        name: 'manufacturing_waste',
        description:
            'Read recorded manufacturing waste quantities and values across all stored dates. No date filter is available yet.',
        properties: const <String, Object?>{},
      ));
      tools.add(_tool(
        name: 'inventory_count_variances',
        description:
            'Read recorded inventory count quantity and value variances across all stored dates. No date filter is available yet.',
        properties: const <String, Object?>{},
      ));
    }
    final analysisDefinition =
        AssistantBusinessAnalysisService.definitionFor(store);
    if (analysisDefinition != null) tools.add(analysisDefinition);
    tools.addAll(AssistantDatabaseExplorerService.definitionsFor(store));
    return List<AssistantJsonMap>.unmodifiable(tools);
  }

  static Future<AssistantJsonMap> execute({
    required AppStore store,
    required String name,
    required Map<String, Object?> arguments,
    DateTime? now,
  }) async {
    final toolName = name.trim();
    if (!_knownToolNames.contains(toolName)) {
      throw const AssistantReadToolException(
        'unknown_tool',
        'This assistant read tool is not available.',
      );
    }
    _requireToolPermission(store, toolName);
    _requireReadDatabase();
    final reference = (now ?? DateTime.now()).toLocal();

    switch (toolName) {
      case 'income_statement':
        _requireOnlyArguments(arguments, const <String>{'from', 'to'});
        final period = _parsePeriod(arguments);
        final report = await AccountingService.incomeStatementReport(
          from: period.from,
          to: period.toInclusive,
        );
        return _envelope(
          store,
          toolName,
          reference,
          data: <String, Object?>{
            'grossSales': report.grossSales,
            'salesReturns': report.salesReturns,
            'salesDiscounts': report.salesDiscounts,
            'netSales': report.netSales,
            'otherRevenue': report.otherRevenue,
            'revenue': report.revenue,
            'costOfGoodsSold': report.costOfGoodsSold,
            'grossProfit': report.grossProfit,
            'expenses': report.expenses,
            'netProfit': report.netProfit,
            'inventoryGain': report.inventoryGain,
            'cashOver': report.cashOver,
            'inventoryLoss': report.inventoryLoss,
            'manufacturingWaste': report.manufacturingWaste,
            'manufacturingVariance': report.manufacturingVariance,
            'cashShort': report.cashShort,
            'otherRevenueLines': _statementLines(report.otherRevenueLines),
            'otherRevenueLinesTruncated':
                report.otherRevenueLines.length > _maxReturnedRows,
            'costOfSalesLines': _statementLines(report.costOfSalesLines),
            'costOfSalesLinesTruncated':
                report.costOfSalesLines.length > _maxReturnedRows,
            'expenseLines': _statementLines(report.expenseLines),
            'expenseLinesTruncated':
                report.expenseLines.length > _maxReturnedRows,
          },
          period: period,
          source: 'AccountingService.incomeStatementReport',
        );

      case 'balance_sheet':
        _requireOnlyArguments(arguments, const <String>{'as_of'});
        final asOf = _parseOptionalDate(arguments, 'as_of') ??
            DateTime(reference.year, reference.month, reference.day);
        final report = await AccountingService.balanceSheetReport(
          asOf: _endOfDay(asOf),
        );
        return _envelope(
          store,
          toolName,
          reference,
          asOf: asOf,
          data: <String, Object?>{
            'assets': report.assets,
            'liabilities': report.liabilities,
            'equity': report.equity,
            'retainedEarnings': report.retainedEarnings,
            'liabilitiesAndEquity': report.liabilitiesAndEquity,
            'difference': report.difference,
            'currentAssets': report.currentAssets,
            'nonCurrentAssets': report.nonCurrentAssets,
            'currentLiabilities': report.currentLiabilities,
            'nonCurrentLiabilities': report.nonCurrentLiabilities,
            'currentAssetLines': _statementLines(report.currentAssetLines),
            'currentAssetLinesTruncated':
                report.currentAssetLines.length > _maxReturnedRows,
            'nonCurrentAssetLines':
                _statementLines(report.nonCurrentAssetLines),
            'nonCurrentAssetLinesTruncated':
                report.nonCurrentAssetLines.length > _maxReturnedRows,
            'currentLiabilityLines':
                _statementLines(report.currentLiabilityLines),
            'currentLiabilityLinesTruncated':
                report.currentLiabilityLines.length > _maxReturnedRows,
            'nonCurrentLiabilityLines':
                _statementLines(report.nonCurrentLiabilityLines),
            'nonCurrentLiabilityLinesTruncated':
                report.nonCurrentLiabilityLines.length > _maxReturnedRows,
            'equityLines': _statementLines(report.equityLines),
            'equityLinesTruncated':
                report.equityLines.length > _maxReturnedRows,
          },
          source: 'AccountingService.balanceSheetReport',
        );

      case 'trial_balance':
        _requireOnlyArguments(arguments, const <String>{'from', 'to'});
        final period = _parsePeriod(arguments);
        final rows = await AccountingService.trialBalanceReport(
          from: period.from,
          to: period.toInclusive,
        );
        final debitTotal = rows.fold<double>(0, (sum, row) => sum + row.debit);
        final creditTotal =
            rows.fold<double>(0, (sum, row) => sum + row.credit);
        final visibleRows = rows.take(_maxReturnedRows).map((row) {
          return <String, Object?>{
            'accountCode': row.accountCode,
            'accountName': row.accountName,
            'accountType': row.accountType,
            'accountSubtype': row.accountSubtype,
            'normalBalance': row.normalBalance,
            'debit': row.debit,
            'credit': row.credit,
            'opening': row.opening,
            'closing': row.closing,
          };
        }).toList(growable: false);
        return _envelope(
          store,
          toolName,
          reference,
          data: <String, Object?>{
            'totalDebit': debitTotal,
            'totalCredit': creditTotal,
            'difference': debitTotal - creditTotal,
            'accountCount': rows.length,
            'accounts': visibleRows,
            'accountsTruncated': rows.length > visibleRows.length,
          },
          period: period,
          source: 'AccountingService.trialBalanceReport',
        );

      case 'cash_flow_statement':
        _requireOnlyArguments(arguments, const <String>{'from', 'to'});
        final period = _parsePeriod(arguments);
        final report = await AccountingService.cashFlowStatementReport(
          from: period.from,
          to: period.toInclusive,
        );
        return _envelope(
          store,
          toolName,
          reference,
          data: <String, Object?>{
            'operatingInflows': report.operatingInflows,
            'operatingOutflows': report.operatingOutflows,
            'operatingNet': report.operatingNet,
            'investingInflows': report.investingInflows,
            'investingOutflows': report.investingOutflows,
            'investingNet': report.investingNet,
            'financingInflows': report.financingInflows,
            'financingOutflows': report.financingOutflows,
            'financingNet': report.financingNet,
            'openingCash': report.openingCash,
            'closingCash': report.closingCash,
            'netChangeInCash': report.netChangeInCash,
          },
          period: period,
          source: 'AccountingService.cashFlowStatementReport',
        );

      case 'tax_summary':
        _requireOnlyArguments(arguments, const <String>{'from', 'to'});
        final period = _parsePeriod(arguments);
        final report = await AccountingService.taxReport(
          from: period.from,
          to: period.toInclusive,
        );
        return _envelope(
          store,
          toolName,
          reference,
          data: <String, Object?>{
            'outputTax': report.outputTax,
            'inputTax': report.inputTax,
            'netTaxPayable': report.netTaxPayable,
            'payableAccountMovement': report.payableAccountMovement,
          },
          period: period,
          source: 'AccountingService.taxReport',
        );

      case 'sales_summary':
        _requireOnlyArguments(arguments, const <String>{'from', 'to'});
        final period = _parsePeriod(arguments);
        final data = await LocalDatabaseService.assistantSalesSummaryFromSqlite(
          from: period.from,
          to: period.toCalendarDate,
        );
        if (data == null) _throwBusinessDatabaseUnavailable();
        return _envelope(
          store,
          toolName,
          reference,
          data: data,
          period: period,
          source: 'BusinessSqliteStore.assistantSalesSummary',
        );

      case 'purchase_summary':
        _requireOnlyArguments(arguments, const <String>{'from', 'to'});
        final period = _parsePeriod(arguments);
        final data =
            await LocalDatabaseService.assistantPurchaseSummaryFromSqlite(
          from: period.from,
          to: period.toCalendarDate,
        );
        if (data == null) _throwBusinessDatabaseUnavailable();
        return _envelope(
          store,
          toolName,
          reference,
          data: data,
          period: period,
          source: 'BusinessSqliteStore.assistantPurchaseSummary',
        );

      case 'expense_summary':
        _requireOnlyArguments(arguments, const <String>{'from', 'to'});
        final period = _parsePeriod(arguments);
        final data =
            await LocalDatabaseService.assistantExpenseSummaryFromSqlite(
          from: period.from,
          to: period.toCalendarDate,
        );
        if (data == null) _throwBusinessDatabaseUnavailable();
        return _envelope(
          store,
          toolName,
          reference,
          data: data,
          period: period,
          source: 'BusinessSqliteStore.assistantExpenseSummary',
        );

      case 'customer_receivables_aging':
      case 'supplier_payables_aging':
        _requireOnlyArguments(arguments, const <String>{'as_of'});
        final asOf = _parseOptionalDate(arguments, 'as_of') ??
            DateTime(reference.year, reference.month, reference.day);
        final report = toolName == 'customer_receivables_aging'
            ? await AccountingAgingService.customerAgingReport(asOfDate: asOf)
            : await AccountingAgingService.supplierAgingReport(asOfDate: asOf);
        final parties = report.rows.take(_maxReturnedRows).map((row) {
          return <String, Object?>{
            'partyName': row.partyName,
            'current': row.current,
            'days1To30': row.days1To30,
            'days31To60': row.days31To60,
            'days61To90': row.days61To90,
            'over90': row.over90,
            'total': row.total,
          };
        }).toList(growable: false);
        return _envelope(
          store,
          toolName,
          reference,
          asOf: report.asOfDate,
          data: <String, Object?>{
            'total': report.total,
            'current': report.current,
            'days1To30': report.days1To30,
            'days31To60': report.days31To60,
            'days61To90': report.days61To90,
            'over90': report.over90,
            'partyCount': report.rows.length,
            'parties': parties,
            'partiesTruncated': report.rows.length > parties.length,
          },
          source: toolName == 'customer_receivables_aging'
              ? 'AccountingAgingService.customerAgingReport'
              : 'AccountingAgingService.supplierAgingReport',
        );

      case 'customer_account_statement':
      case 'supplier_account_statement':
        final isCustomer = toolName == 'customer_account_statement';
        final partyArgument = isCustomer ? 'customer' : 'supplier';
        _requireOnlyArguments(
          arguments,
          <String>{partyArgument, 'from', 'to'},
        );
        return _readPartyAccountStatement(
          store: store,
          toolName: toolName,
          partyType: isCustomer ? 'customer' : 'supplier',
          partyArgument: partyArgument,
          arguments: arguments,
          reference: reference,
        );

      case 'sales_invoice_details':
      case 'purchase_invoice_details':
        _requireOnlyArguments(arguments, const <String>{'query', 'from', 'to'});
        return _readInvoiceDetails(
          store: store,
          toolName: toolName,
          arguments: arguments,
          reference: reference,
        );

      case 'party_payment_history':
        _requireOnlyArguments(
          arguments,
          const <String>{'party_type', 'party', 'from', 'to'},
        );
        return _readPartyPaymentHistory(
          store: store,
          arguments: arguments,
          reference: reference,
        );

      case 'party_balance_reconciliation':
        _requireOnlyArguments(
          arguments,
          const <String>{'party_type', 'party', 'as_of'},
        );
        return _readPartyBalanceReconciliation(
          store: store,
          arguments: arguments,
          reference: reference,
        );

      case 'cash_balances':
        _requireOnlyArguments(arguments, const <String>{});
        final balances = await AccountingService.listCashBalancesReport();
        final rows = balances.take(_maxReturnedRows).map((item) {
          return <String, Object?>{
            'name': item.name,
            'type': item.type,
            'balance': item.balance,
          };
        }).toList(growable: false);
        return _envelope(
          store,
          toolName,
          reference,
          data: <String, Object?>{
            'balanceCount': balances.length,
            'balances': rows,
            'balancesTruncated': balances.length > rows.length,
          },
          source: 'AccountingService.listCashBalancesReport',
        );

      case 'inventory_cost_valuation':
        _requireOnlyArguments(arguments, const <String>{});
        final rows = await AccountingService.inventoryValuationReport();
        final sorted = List.of(rows)
          ..sort((left, right) => right.totalValue.compareTo(left.totalValue));
        final visibleRows = sorted.take(_maxReturnedRows).map((row) {
          return <String, Object?>{
            'productName': row.productName,
            'warehouseName': row.warehouseName,
            'quantity': row.quantity,
            'unitCost': row.unitCost,
            'totalValue': row.totalValue,
            'inventoryCategory': row.inventoryCategory,
          };
        }).toList(growable: false);
        return _envelope(
          store,
          toolName,
          reference,
          data: <String, Object?>{
            'totalCostValue': rows.fold<double>(
              0,
              (sum, row) => sum + row.totalValue,
            ),
            'productWarehouseCount': rows.length,
            'rows': visibleRows,
            'rowsTruncated': rows.length > visibleRows.length,
            'valuationBasis': 'Ventio inventory accounting valuation',
          },
          source: 'AccountingService.inventoryValuationReport',
        );

      case 'current_stock_balances':
        _requireOnlyArguments(
          arguments,
          const <String>{'product', 'warehouse'},
        );
        final data =
            await LocalDatabaseService.assistantStockBalancesFromSqlite(
          storeId: store.appIdentity.storeId,
          productQuery: _optionalStringArgument(arguments, 'product'),
          warehouseQuery: _optionalStringArgument(arguments, 'warehouse'),
        );
        if (data == null) _throwBusinessDatabaseUnavailable();
        return _envelope(
          store,
          toolName,
          reference,
          data: data,
          source: 'BusinessSqliteStore.assistantStockBalances',
        );

      case 'stock_movement_summary':
        _requireOnlyArguments(
          arguments,
          const <String>{'from', 'to', 'product', 'warehouse', 'type'},
        );
        final period = _parsePeriod(arguments);
        final data =
            await LocalDatabaseService.assistantStockMovementSummaryFromSqlite(
          storeId: store.appIdentity.storeId,
          from: period.from,
          to: period.toCalendarDate,
          productQuery: _optionalStringArgument(arguments, 'product'),
          warehouseQuery: _optionalStringArgument(arguments, 'warehouse'),
          type: _optionalStringArgument(
            arguments,
            'type',
            maxLength: 80,
          ),
        );
        if (data == null) _throwBusinessDatabaseUnavailable();
        return _envelope(
          store,
          toolName,
          reference,
          data: data,
          period: period,
          source: 'BusinessSqliteStore.assistantStockMovementSummary',
        );

      case 'manufacturing_cost_summary':
        _requireOnlyArguments(arguments, const <String>{});
        final rows = await AccountingService.manufacturingOrderCostReport();
        final visibleRows = rows.take(_maxReturnedRows).map((row) {
          return <String, Object?>{
            'orderNo': row.orderNo,
            'outputProductName': row.outputProductName,
            'outputQuantity': row.outputQuantity,
            'totalMaterialCost': row.totalMaterialCost,
            'wasteValue': row.wasteValue,
            'eligibleCost': row.eligibleCost,
            'actualUnitCost': row.actualUnitCost,
            'status': row.status,
          };
        }).toList(growable: false);
        return _envelope(
          store,
          toolName,
          reference,
          data: <String, Object?>{
            'orderCount': rows.length,
            'totalMaterialCost': rows.fold<double>(
              0,
              (sum, row) => sum + row.totalMaterialCost,
            ),
            'totalWasteValue':
                rows.fold<double>(0, (sum, row) => sum + row.wasteValue),
            'totalEligibleCost':
                rows.fold<double>(0, (sum, row) => sum + row.eligibleCost),
            'orders': visibleRows,
            'ordersTruncated': rows.length > visibleRows.length,
          },
          source: 'AccountingService.manufacturingOrderCostReport',
        );

      case 'manufacturing_waste':
        _requireOnlyArguments(arguments, const <String>{});
        final rows = await AccountingService.manufacturingWasteReport();
        final visibleRows = rows.take(_maxReturnedRows).map((row) {
          return <String, Object?>{
            'orderNo': row.orderNo,
            'productName': row.productName,
            'quantity': row.quantity,
            'unitCost': row.unitCost,
            'value': row.value,
            'reason': row.reason,
            'status': row.status,
          };
        }).toList(growable: false);
        return _envelope(
          store,
          toolName,
          reference,
          data: <String, Object?>{
            'wasteLineCount': rows.length,
            'totalValue': rows.fold<double>(0, (sum, row) => sum + row.value),
            'lines': visibleRows,
            'linesTruncated': rows.length > visibleRows.length,
          },
          source: 'AccountingService.manufacturingWasteReport',
        );

      case 'inventory_count_variances':
        _requireOnlyArguments(arguments, const <String>{});
        final rows = await AccountingService.inventoryCountVarianceReport();
        final visibleRows = rows.take(_maxReturnedRows).map((row) {
          return <String, Object?>{
            'countNo': row.countNo,
            'status': row.status,
            'productName': row.productName,
            'systemQuantity': row.systemQuantity,
            'countedQuantity': row.countedQuantity,
            'differenceQuantity': row.differenceQuantity,
            'unitCost': row.unitCost,
            'differenceValue': row.differenceValue,
          };
        }).toList(growable: false);
        return _envelope(
          store,
          toolName,
          reference,
          data: <String, Object?>{
            'varianceLineCount': rows.length,
            'netDifferenceValue': rows.fold<double>(
              0,
              (sum, row) => sum + row.differenceValue,
            ),
            'grossDifferenceValue': rows.fold<double>(
              0,
              (sum, row) => sum + row.differenceValue.abs(),
            ),
            'lines': visibleRows,
            'linesTruncated': rows.length > visibleRows.length,
          },
          source: 'AccountingService.inventoryCountVarianceReport',
        );

      case 'business_data_analysis':
        _requireOnlyArguments(
          arguments,
          const <String>{
            'dataset',
            'group_by',
            'from',
            'to',
            'search',
            'limit'
          },
        );
        try {
          final data = await AssistantBusinessAnalysisService.execute(
            store: store,
            arguments: arguments,
          );
          return _envelope(
            store,
            toolName,
            reference,
            data: data,
            source: 'Ventio read-only aggregate analysis',
          );
        } on AssistantBusinessAnalysisException catch (error) {
          throw AssistantReadToolException(error.code, error.message);
        }

      case 'business_schema_catalog':
        _requireOnlyArguments(arguments, const <String>{'table'});
        try {
          return _envelope(
            store,
            toolName,
            reference,
            data: await AssistantDatabaseExplorerService.executeCatalog(
              store: store,
              arguments: arguments,
            ),
            source: 'Ventio permitted business schema catalog',
          );
        } on AssistantDatabaseExplorerException catch (error) {
          throw AssistantReadToolException(error.code, error.message);
        }

      case 'business_table_analysis':
        _requireOnlyArguments(
          arguments,
          const <String>{
            'table',
            'group_by',
            'measure',
            'from',
            'to',
            'search',
            'filter_by',
            'filter_value',
            'filter_match',
            'limit',
          },
        );
        try {
          return _envelope(
            store,
            toolName,
            reference,
            data: await AssistantDatabaseExplorerService.executeAnalysis(
              store: store,
              arguments: arguments,
            ),
            source: 'Ventio permission-scoped table aggregate',
          );
        } on AssistantDatabaseExplorerException catch (error) {
          throw AssistantReadToolException(error.code, error.message);
        }

      default:
        throw const AssistantReadToolException(
          'unknown_tool',
          'This assistant read tool is not available.',
        );
    }
  }

  static Future<AssistantJsonMap> _readPartyAccountStatement({
    required AppStore store,
    required String toolName,
    required String partyType,
    required String partyArgument,
    required Map<String, Object?> arguments,
    required DateTime reference,
  }) async {
    final query = _optionalStringArgument(
      arguments,
      partyArgument,
      maxLength: 160,
    );
    if (query.isEmpty) {
      throw AssistantReadToolException(
        '${partyType}_required',
        'A $partyType name is required to read an account statement.',
      );
    }
    final candidates = await _loadPartyCandidates(store, partyType);
    final matches = _matchPartyCandidates(candidates, query);
    if (matches.length != 1) {
      return _envelope(
        store,
        toolName,
        reference,
        data: <String, Object?>{
          'matchStatus': matches.isEmpty ? 'not_found' : 'ambiguous',
          'partyQuery': query,
          'matchingPartyCount': matches.length,
          'matchingParties': matches
              .take(10)
              .map((party) => <String, Object?>{
                    'partyId': party.id,
                    'partyName': party.name,
                  })
              .toList(growable: false),
        },
        source: 'AppStore.${partyType}_account_statement',
      );
    }

    await store.ensureAccountTransactionsLoaded();
    final party = matches.single;
    final allTransactions = store
        .accountTransactionsForAccount(partyType, party.id)
        .where((transaction) => !transaction.isDeleted)
        .toList(growable: false)
      ..sort(_compareAccountTransactions);
    final today = DateTime(reference.year, reference.month, reference.day);
    final firstDate = allTransactions.isEmpty
        ? today
        : _localDateOnly(allTransactions.first.date);
    final from = _parseOptionalDate(arguments, 'from') ?? firstDate;
    final to = _parseOptionalDate(arguments, 'to') ?? today;
    if (from.isAfter(to)) {
      throw const AssistantReadToolException(
        'invalid_date_range',
        'The start date must be on or before the end date.',
      );
    }
    final toInclusive = _endOfDay(to);
    final currencies = allTransactions
        .map((transaction) => _transactionCurrency(transaction, store))
        .toSet()
        .toList()
      ..sort();
    if (currencies.isEmpty) currencies.add(store.storeProfile.baseCurrency);
    final transactionsByCurrency = <String, List<AccountTransaction>>{
      for (final currency in currencies)
        currency: allTransactions
            .where((transaction) =>
                _transactionCurrency(transaction, store) == currency)
            .toList(growable: false),
    };
    final currencySummaries = <AssistantJsonMap>[];
    final openingByCurrency = <String, double>{};
    final isCustomer = partyType == 'customer';
    final balanceSign = isCustomer ? 1.0 : -1.0;
    for (final currency in currencies) {
      final currencyTransactions = transactionsByCurrency[currency]!;
      final opening = currencyTransactions
          .where((transaction) => transaction.date.isBefore(from))
          .fold<double>(
            0,
            (sum, transaction) => sum + transaction.signedAmount * balanceSign,
          );
      final periodTransactions = currencyTransactions
          .where((transaction) =>
              !transaction.date.isBefore(from) &&
              !transaction.date.isAfter(toInclusive))
          .toList(growable: false);
      final debitTotal = periodTransactions.fold<double>(
        0,
        (sum, transaction) => sum + transaction.debit,
      );
      final creditTotal = periodTransactions.fold<double>(
        0,
        (sum, transaction) => sum + transaction.credit,
      );
      final currentBalance = currencyTransactions.fold<double>(
        0,
        (sum, transaction) => sum + transaction.signedAmount * balanceSign,
      );
      final balanceMovement =
          isCustomer ? debitTotal - creditTotal : creditTotal - debitTotal;
      openingByCurrency[currency] = opening;
      currencySummaries.add(<String, Object?>{
        'currency': currency,
        'openingBalance': opening,
        'debitTotal': debitTotal,
        'creditTotal': creditTotal,
        'closingBalance': opening + balanceMovement,
        'currentBalance': currentBalance,
        'transactionCount': periodTransactions.length,
      });
    }

    final rangeTransactions = allTransactions
        .where((transaction) =>
            !transaction.date.isBefore(from) &&
            !transaction.date.isAfter(toInclusive))
        .toList(growable: false);
    final runningByCurrency = Map<String, double>.of(openingByCurrency);
    final visibleTransactions = <AssistantJsonMap>[];
    for (final transaction
        in rangeTransactions.take(_maxCustomerStatementRows)) {
      final currency = _transactionCurrency(transaction, store);
      final runningBalance = (runningByCurrency[currency] ?? 0) +
          transaction.signedAmount * balanceSign;
      runningByCurrency[currency] = runningBalance;
      visibleTransactions.add(<String, Object?>{
        'date': _dateLabel(transaction.date),
        'type': _customerTransactionTypeLabel(transaction.type),
        'referenceId': transaction.referenceId,
        'reference': transaction.referenceNo.trim().isEmpty
            ? transaction.referenceId
            : transaction.referenceNo,
        'debit': transaction.debit,
        'credit': transaction.credit,
        'currency': currency,
        'runningBalanceInCurrency': runningBalance,
        'details': transaction.note,
        'paymentMethod': transaction.paymentMethod,
      });
    }
    final period = _AssistantDatePeriod(
      from: from,
      toInclusive: toInclusive,
      fromLabel: _dateLabel(from),
      toLabel: _dateLabel(to),
    );
    return _envelope(
      store,
      toolName,
      reference,
      data: <String, Object?>{
        'matchStatus': 'matched',
        'partyType': partyType,
        'partyId': party.id,
        'partyName': party.name,
        'balanceMeaning': isCustomer
            ? 'Within each currency, debit increases the customer amount due and credit reduces it.'
            : 'Within each currency, credit increases the amount Ventio owes the supplier and debit reduces it.',
        'currencyCount': currencies.length,
        if (currencies.length == 1)
          'ventioLedgerBalance': currencySummaries.first['currentBalance'],
        'currencySummaries': currencySummaries,
        'transactionCount': rangeTransactions.length,
        'transactions': visibleTransactions,
        'transactionsTruncated':
            rangeTransactions.length > visibleTransactions.length,
        'returnedTransactionCount': visibleTransactions.length,
      },
      period: period,
      source: 'AppStore.${partyType}_account_statement',
    );
  }

  static Future<AssistantJsonMap> _readInvoiceDetails({
    required AppStore store,
    required String toolName,
    required Map<String, Object?> arguments,
    required DateTime reference,
  }) async {
    final query = _optionalStringArgument(arguments, 'query', maxLength: 160);
    if (query.isEmpty) {
      throw const AssistantReadToolException(
        'query_required',
        'Enter an invoice number, customer or supplier name, or product name.',
      );
    }
    final from = _parseOptionalDate(arguments, 'from');
    final to = _parseOptionalDate(arguments, 'to') ??
        DateTime(reference.year, reference.month, reference.day);
    if (from != null && from.isAfter(to)) {
      throw const AssistantReadToolException(
        'invalid_date_range',
        'The start date must be on or before the end date.',
      );
    }
    final isSales = toolName == 'sales_invoice_details';
    final normalized = _normalizePartyName(query);
    final matches = <Object>[];
    if (isSales) {
      await store.ensureSalesLoaded();
      final documents = store.sales.where((sale) {
        if (sale.isDeleted || !_dateMatches(sale.date, from, to)) return false;
        return _invoiceMatches(
          query: query,
          normalizedQuery: normalized,
          documentId: sale.id,
          documentNumber: sale.invoiceNo,
          partyName: sale.customerName,
          productNames: sale.items.map((item) => item.productName),
        );
      }).toList(growable: false)
        ..sort((left, right) => right.date.compareTo(left.date));
      final exact = documents
          .where(
              (sale) => _invoiceNumberIsExact(query, sale.id, sale.invoiceNo))
          .toList(growable: false);
      matches.addAll(exact.isEmpty ? documents : exact);
    } else {
      await store.ensurePurchasesLoaded();
      final documents = store.purchases.where((purchase) {
        if (purchase.isDeleted || !_dateMatches(purchase.date, from, to)) {
          return false;
        }
        return _invoiceMatches(
          query: query,
          normalizedQuery: normalized,
          documentId: purchase.id,
          documentNumber: purchase.purchaseNo,
          partyName: purchase.supplierName,
          productNames: purchase.items.map((item) => item.productName),
        );
      }).toList(growable: false)
        ..sort((left, right) => right.date.compareTo(left.date));
      final exact = documents
          .where((purchase) =>
              _invoiceNumberIsExact(query, purchase.id, purchase.purchaseNo))
          .toList(growable: false);
      matches.addAll(exact.isEmpty ? documents : exact);
    }
    final invoices = <AssistantJsonMap>[];
    for (final document in matches.take(_maxInvoiceMatches)) {
      if (document is Sale) {
        invoices.add(_saleInvoiceData(document));
      } else if (document is Purchase) {
        invoices.add(_purchaseInvoiceData(document));
      }
    }
    final filterFrom = from == null ? null : _dateLabel(from);
    return _envelope(
      store,
      toolName,
      reference,
      data: <String, Object?>{
        'query': query,
        'matchStatus': matches.isEmpty ? 'not_found' : 'matched',
        'matchCount': matches.length,
        'returnedInvoiceCount': invoices.length,
        'invoices': invoices,
        'invoicesTruncated': matches.length > invoices.length,
        'dateFilterFrom': filterFrom,
        'dateFilterTo': _dateLabel(to),
        if (isSales)
          'amountBasis':
              'Invoice total and paid/due/return amounts use each invoice currency. Sales line prices and line totals use the invoice base currency, which is shown separately.'
        else
          'amountBasis':
              'Purchase line totals and document subtotal are USD reference values; original unit costs retain their recorded currency and exchange rate.',
      },
      source: isSales ? 'AppStore.sales' : 'AppStore.purchases',
    );
  }

  static AssistantJsonMap _saleInvoiceData(Sale sale) {
    final visibleItems = sale.items.take(_maxInvoiceLines).map((item) {
      return <String, Object?>{
        'productId': item.productId,
        'productName': item.productName,
        'quantity': item.quantity,
        'unitName': item.unitName,
        'unitPrice': item.unitPrice,
        'unitPriceCurrency': sale.baseCurrency,
        'lineTotal': item.lineTotal,
        'lineTotalCurrency': sale.baseCurrency,
      };
    }).toList(growable: false);
    return <String, Object?>{
      'id': sale.id,
      'invoiceNumber': sale.invoiceNo,
      'date': _dateLabel(sale.date),
      'status': sale.status,
      'customerId': sale.customerId,
      'customerName': sale.customerName,
      'currency': sale.invoiceCurrency,
      'invoiceTotal': sale.invoiceTotal,
      'paidAmount': sale.paidAmount,
      'balanceDue': sale.balanceDue,
      'returnedAmount': sale.returnedAmount,
      'baseAmount': sale.effectiveBaseAmount,
      'baseCurrency': sale.baseCurrency,
      'discount': sale.discount,
      'discountCurrency': sale.discountCurrency,
      'paymentStatus': sale.paymentStatus,
      'paymentMethod': sale.paymentMethod,
      'warehouse': sale.warehouseName,
      'items': visibleItems,
      'itemCount': sale.items.length,
      'itemsTruncated': sale.items.length > visibleItems.length,
    };
  }

  static AssistantJsonMap _purchaseInvoiceData(Purchase purchase) {
    final visibleItems = purchase.items.take(_maxInvoiceLines).map((item) {
      return <String, Object?>{
        'productId': item.productId,
        'productName': item.productName,
        'quantity': item.quantity,
        'purchaseUnitName': item.purchaseUnitName,
        'unitCostUsdReference': item.unitCost,
        'lineTotalUsdReference': item.lineTotal,
        'originalUnitCost': item.originalUnitCost,
        'originalCurrency': item.unitCostCurrency,
        'exchangeRateAtEntry': item.exchangeRateAtEntry,
      };
    }).toList(growable: false);
    return <String, Object?>{
      'id': purchase.id,
      'documentNumber': purchase.purchaseNo,
      'date': _dateLabel(purchase.date),
      'status': purchase.status,
      'documentType': purchase.documentType,
      'sourcePurchaseNumber': purchase.sourcePurchaseNo,
      'supplierId': purchase.supplierId,
      'supplierName': purchase.supplierName,
      'subtotalUsdReference': purchase.subtotal,
      'paidAmountUsdReference': purchase.paidAmount,
      'balanceDueUsdReference': purchase.balanceDue,
      'paymentStatus': purchase.paymentStatus,
      'paymentMethod': purchase.paymentMethod,
      'warehouse': purchase.warehouseName,
      'items': visibleItems,
      'itemCount': purchase.items.length,
      'itemsTruncated': purchase.items.length > visibleItems.length,
    };
  }

  static Future<AssistantJsonMap> _readPartyPaymentHistory({
    required AppStore store,
    required Map<String, Object?> arguments,
    required DateTime reference,
  }) async {
    final partyType = _requiredPartyType(arguments);
    _requirePartyLedgerPermission(store, partyType);
    final query = _optionalStringArgument(arguments, 'party', maxLength: 160);
    if (query.isEmpty) {
      throw const AssistantReadToolException(
        'party_required',
        'A customer or supplier name is required to read payment history.',
      );
    }
    final candidates = await _loadPartyCandidates(store, partyType);
    final matches = _matchPartyCandidates(candidates, query);
    if (matches.length != 1) {
      return _envelope(
        store,
        'party_payment_history',
        reference,
        data: <String, Object?>{
          'matchStatus': matches.isEmpty ? 'not_found' : 'ambiguous',
          'partyType': partyType,
          'partyQuery': query,
          'matchingPartyCount': matches.length,
          'matchingParties': matches
              .take(10)
              .map((party) => <String, Object?>{
                    'partyId': party.id,
                    'partyName': party.name,
                  })
              .toList(growable: false),
        },
        source: 'PaymentVoucherService',
      );
    }
    final party = matches.single;
    final from = _parseOptionalDate(arguments, 'from');
    final to = _parseOptionalDate(arguments, 'to') ??
        DateTime(reference.year, reference.month, reference.day);
    if (from != null && from.isAfter(to)) {
      throw const AssistantReadToolException(
        'invalid_date_range',
        'The start date must be on or before the end date.',
      );
    }
    final database = SqliteMigrationManager.database;
    if (database == null) _throwBusinessDatabaseUnavailable();
    final service = PaymentVoucherService(database);
    final vouchers = <Object>[];
    var offset = 0;
    var historyMayBeIncomplete = false;
    for (var pageIndex = 0; pageIndex < _maxPaymentHistoryPages; pageIndex++) {
      final page = partyType == 'customer'
          ? await service.listReceipts(
              customerId: party.id,
              limit: 500,
              offset: offset,
            )
          : await service.listPayments(
              supplierId: party.id,
              limit: 500,
              offset: offset,
            );
      vouchers.addAll(page);
      if (page.length < 500) break;
      offset += page.length;
      if (pageIndex == _maxPaymentHistoryPages - 1) {
        historyMayBeIncomplete = true;
      }
    }
    final filtered = vouchers.where((voucher) {
      final date = voucher is ReceiptVoucher
          ? voucher.date
          : (voucher as PaymentVoucher).date;
      return _dateMatches(date, from, to);
    }).toList(growable: false);
    final rows = filtered.take(_maxPaymentHistoryRows).map((voucher) {
      if (voucher is ReceiptVoucher) return _receiptVoucherData(voucher);
      return _paymentVoucherData(voucher as PaymentVoucher);
    }).toList(growable: false);
    final visibleFrom = from == null ? null : _dateLabel(from);
    return _envelope(
      store,
      'party_payment_history',
      reference,
      data: <String, Object?>{
        'matchStatus': 'matched',
        'partyType': partyType,
        'partyId': party.id,
        'partyName': party.name,
        'historyCount': filtered.length,
        'history': rows,
        'historyTruncated': filtered.length > rows.length,
        'historyMayBeIncomplete': historyMayBeIncomplete,
        'dateFilterFrom': visibleFrom,
        'dateFilterTo': _dateLabel(to),
        'allocationBasis':
            'Only non-deleted active allocations are included by the local voucher service.',
      },
      source: 'PaymentVoucherService.listReceipts/listPayments',
    );
  }

  static AssistantJsonMap _receiptVoucherData(ReceiptVoucher voucher) =>
      _voucherData(
        id: voucher.id,
        number: voucher.voucherNo,
        date: voucher.date,
        status: voucher.status,
        amount: voucher.amount,
        discount: voucher.discount,
        unallocatedAmount: voucher.unallocatedAmount,
        currency: voucher.currency,
        method: voucher.paymentMethod,
        notes: voucher.notes,
        reversalReason: voucher.reversalReason,
        reversedAt: voucher.reversedAt,
        allocations: voucher.allocations,
      );

  static AssistantJsonMap _paymentVoucherData(PaymentVoucher voucher) =>
      _voucherData(
        id: voucher.id,
        number: voucher.voucherNo,
        date: voucher.date,
        status: voucher.status,
        amount: voucher.amount,
        discount: voucher.discount,
        unallocatedAmount: voucher.unallocatedAmount,
        currency: voucher.currency,
        method: voucher.paymentMethod,
        notes: voucher.notes,
        reversalReason: voucher.reversalReason,
        reversedAt: voucher.reversedAt,
        allocations: voucher.allocations,
      );

  static AssistantJsonMap _voucherData({
    required String id,
    required String number,
    required DateTime date,
    required String status,
    required double amount,
    required double discount,
    required double unallocatedAmount,
    required String currency,
    required String method,
    required String notes,
    required String reversalReason,
    required DateTime? reversedAt,
    required List<PaymentAllocation> allocations,
  }) {
    final visibleAllocations = allocations.take(10).map((allocation) {
      return <String, Object?>{
        'documentType': allocation.referenceType,
        'documentId': allocation.referenceId,
        'documentNumber': allocation.referenceNumber,
        'voucherAmount': allocation.amount,
        'voucherCurrency': allocation.currency,
        'documentAmount': allocation.effectiveReferenceAmount,
        'documentCurrency': allocation.referenceCurrency,
        'exchangeRate': allocation.exchangeRate,
        'status': allocation.status,
      };
    }).toList(growable: false);
    return <String, Object?>{
      'id': id,
      'number': number,
      'date': _dateLabel(date),
      'status': status,
      'amount': amount,
      'discount': discount,
      'unallocatedAmount': unallocatedAmount,
      'currency': currency,
      'paymentMethod': method,
      'notes': notes,
      'reversalReason': reversalReason,
      'reversedAt': reversedAt?.toLocal().toIso8601String(),
      'allocations': visibleAllocations,
      'allocationCount': allocations.length,
      'allocationsTruncated': allocations.length > visibleAllocations.length,
    };
  }

  static Future<AssistantJsonMap> _readPartyBalanceReconciliation({
    required AppStore store,
    required Map<String, Object?> arguments,
    required DateTime reference,
  }) async {
    final partyType = _requiredPartyType(arguments);
    _requirePartyLedgerPermission(store, partyType);
    final query = _optionalStringArgument(arguments, 'party', maxLength: 160);
    if (query.isEmpty) {
      throw const AssistantReadToolException(
        'party_required',
        'A customer or supplier name is required for balance reconciliation.',
      );
    }
    final asOf = _parseOptionalDate(arguments, 'as_of') ??
        DateTime(reference.year, reference.month, reference.day);
    final candidates = await _loadPartyCandidates(store, partyType);
    final matches = _matchPartyCandidates(candidates, query);
    if (matches.length != 1) {
      return _envelope(
        store,
        'party_balance_reconciliation',
        reference,
        asOf: asOf,
        data: <String, Object?>{
          'matchStatus': matches.isEmpty ? 'not_found' : 'ambiguous',
          'partyType': partyType,
          'partyQuery': query,
          'matchingPartyCount': matches.length,
          'matchingParties': matches
              .take(10)
              .map((party) => <String, Object?>{
                    'partyId': party.id,
                    'partyName': party.name,
                  })
              .toList(growable: false),
        },
        source: 'AppStore and AccountingAgingService',
      );
    }
    final party = matches.single;
    await store.ensureAccountTransactionsLoaded();
    final asOfInclusive = _endOfDay(asOf);
    final transactions = store
        .accountTransactionsForAccount(partyType, party.id)
        .where((transaction) =>
            !transaction.isDeleted && !transaction.date.isAfter(asOfInclusive))
        .toList(growable: false);
    final amountsByCurrency = <String, _PartyLedgerTotals>{};
    for (final transaction in transactions) {
      final currency = _transactionCurrency(transaction, store);
      amountsByCurrency.putIfAbsent(currency, _PartyLedgerTotals.new).add(
            transaction,
          );
    }
    final accountingReport = partyType == 'customer'
        ? await AccountingAgingService.customerAgingReport(asOfDate: asOf)
        : await AccountingAgingService.supplierAgingReport(asOfDate: asOf);
    bool belongsToParty(String rowId, String rowName) =>
        rowId.trim() == party.id ||
        _normalizePartyName(rowName) == _normalizePartyName(party.name);
    final agingMatches = accountingReport.rows
        .where((row) => belongsToParty(row.partyId, row.partyName))
        .toList(growable: false);
    final agingRow = agingMatches.isEmpty ? null : agingMatches.first;
    final agingDocuments = accountingReport.openDocuments
        .where(
            (document) => belongsToParty(document.partyId, document.partyName))
        .toList(growable: false);
    final baseCurrency = store.storeProfile.baseCurrency.toUpperCase();
    final onlyCurrency =
        amountsByCurrency.length == 1 ? amountsByCurrency.keys.single : null;
    final ledgerTotals =
        onlyCurrency == null ? null : amountsByCurrency[onlyCurrency];
    final signedLedgerBalance = ledgerTotals?.signedBalance;
    final netOwed = signedLedgerBalance == null
        ? null
        : partyType == 'customer'
            ? signedLedgerBalance
            : -signedLedgerBalance;
    final compatibleCurrency = onlyCurrency == baseCurrency;
    final compatibleDirection = netOwed != null && netOwed >= -0.005;
    final comparable =
        transactions.isNotEmpty && compatibleCurrency && compatibleDirection;
    final agingTotal = agingRow?.total ?? 0.0;
    final status = transactions.isEmpty
        ? 'subledger_empty'
        : !compatibleCurrency
            ? (onlyCurrency == null
                ? 'multiple_subledger_currencies'
                : 'currency_mismatch')
            : !compatibleDirection
                ? 'subledger_credit_balance'
                : 'comparable';
    final visibleDocuments = agingDocuments.take(25).map((document) {
      return <String, Object?>{
        'documentNumber': document.number,
        'date': _dateLabel(document.date),
        'originalAmount': document.originalAmount,
        'openAmount': document.openAmount,
        'bucket': document.bucketLabel,
        'ageDays': document.ageDays,
      };
    }).toList(growable: false);
    final ledgerCurrencies = amountsByCurrency.entries.map((entry) {
      return <String, Object?>{
        'currency': entry.key,
        'debitTotal': entry.value.debit,
        'creditTotal': entry.value.credit,
        'signedBalanceDebitMinusCredit': entry.value.signedBalance,
        'transactionCount': entry.value.count,
      };
    }).toList(growable: false);
    return _envelope(
      store,
      'party_balance_reconciliation',
      reference,
      asOf: asOf,
      data: <String, Object?>{
        'matchStatus': 'matched',
        'partyType': partyType,
        'partyId': party.id,
        'partyName': party.name,
        'accountingAgingSource': partyType == 'customer'
            ? 'AccountingAgingService.customerAgingReport'
            : 'AccountingAgingService.supplierAgingReport',
        'agingCurrency': baseCurrency,
        'grossAgingOpenBalance': agingTotal,
        'agingBuckets': <String, Object?>{
          'current': agingRow?.current ?? 0,
          'days1To30': agingRow?.days1To30 ?? 0,
          'days31To60': agingRow?.days31To60 ?? 0,
          'days61To90': agingRow?.days61To90 ?? 0,
          'over90': agingRow?.over90 ?? 0,
        },
        'openDocumentCount': agingDocuments.length,
        'openDocuments': visibleDocuments,
        'openDocumentsTruncated':
            agingDocuments.length > visibleDocuments.length,
        'subledgerCurrencySummaries': ledgerCurrencies,
        'subledgerCurrentNetAmountInOneCurrency': netOwed,
        'subledgerNetMeaning': partyType == 'customer'
            ? 'Debit minus credit; a positive amount is due from the customer.'
            : 'Credit minus debit; a positive amount is due to the supplier.',
        'comparisonStatus': status,
        'comparisonIsValid': comparable,
        if (comparable) 'differenceAgingMinusSubledger': agingTotal - netOwed!,
        'comparisonNote': comparable
            ? 'Both figures are in the base currency and have a non-credit net balance. Aging shows open documents; the subledger value is its signed net balance.'
            : 'The comparison is withheld because the subledger is empty, has multiple currencies, uses a different currency, or has a net credit/advance balance. Source values are shown separately.',
      },
      source: 'AccountingAgingService and AppStore account transactions',
    );
  }

  static Future<List<_AssistantParty>> _loadPartyCandidates(
    AppStore store,
    String partyType,
  ) async {
    if (partyType == 'customer') {
      await store.ensureCustomersLoaded();
      return store.customers
          .where((customer) => !customer.isDeleted)
          .map((customer) => _AssistantParty(customer.id, customer.name))
          .toList(growable: false);
    }
    await store.ensureSuppliersLoaded();
    return store.suppliers
        .where((supplier) => !supplier.isDeleted)
        .map((supplier) => _AssistantParty(supplier.id, supplier.name))
        .toList(growable: false);
  }

  static List<_AssistantParty> _matchPartyCandidates(
    List<_AssistantParty> candidates,
    String query,
  ) {
    final normalizedQuery = _normalizePartyName(query);
    final exact = candidates
        .where((party) =>
            _normalizePartyName(party.name) == normalizedQuery ||
            party.id.trim().toLowerCase() == query.trim().toLowerCase())
        .toList(growable: false);
    return exact.isNotEmpty
        ? exact
        : candidates
            .where((party) =>
                _normalizePartyName(party.name).contains(normalizedQuery))
            .toList(growable: false);
  }

  static String _requiredPartyType(Map<String, Object?> arguments) {
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

  static void _requirePartyLedgerPermission(AppStore store, String partyType) {
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

  static bool _invoiceMatches({
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

  static bool _invoiceNumberIsExact(
    String query,
    String documentId,
    String documentNumber,
  ) {
    final normalizedQuery = query.trim().toLowerCase();
    return documentId.trim().toLowerCase() == normalizedQuery ||
        documentNumber.trim().toLowerCase() == normalizedQuery;
  }

  static bool _dateMatches(DateTime date, DateTime? from, DateTime? to) {
    final localDate = _localDateOnly(date);
    if (from != null && localDate.isBefore(_localDateOnly(from))) return false;
    if (to != null && localDate.isAfter(_localDateOnly(to))) return false;
    return true;
  }

  static DateTime _localDateOnly(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static const Map<String, Object?> _periodProperties = <String, Object?>{
    'from': <String, Object?>{
      'type': 'string',
      'format': 'date',
      'description': 'Inclusive start date in YYYY-MM-DD format.',
    },
    'to': <String, Object?>{
      'type': 'string',
      'format': 'date',
      'description': 'Inclusive end date in YYYY-MM-DD format.',
    },
  };

  static const Map<String, Object?> _asOfProperties = <String, Object?>{
    'as_of': <String, Object?>{
      'type': 'string',
      'format': 'date',
      'description': 'As-of date in YYYY-MM-DD format. Defaults to today.',
    },
  };

  static const Map<String, Object?> _customerStatementProperties =
      <String, Object?>{
    'customer': <String, Object?>{
      'type': 'string',
      'description': 'Customer name or ID as recorded in Ventio.',
      'maxLength': 160,
    },
    ..._periodProperties,
  };

  static const Map<String, Object?> _supplierStatementProperties =
      <String, Object?>{
    'supplier': <String, Object?>{
      'type': 'string',
      'description': 'Supplier name or ID as recorded in Ventio.',
      'maxLength': 160,
    },
    ..._periodProperties,
  };

  static const Map<String, Object?> _invoiceSearchProperties =
      <String, Object?>{
    'query': <String, Object?>{
      'type': 'string',
      'description': 'Invoice/document number, party name, or product name.',
      'maxLength': 160,
    },
    ..._periodProperties,
  };

  static const Map<String, Object?> _partyPaymentHistoryProperties =
      <String, Object?>{
    'party_type': <String, Object?>{
      'type': 'string',
      'enum': <String>['customer', 'supplier'],
      'description': 'Use customer for receipts or supplier for payments.',
    },
    'party': <String, Object?>{
      'type': 'string',
      'description': 'Customer or supplier name or ID as recorded in Ventio.',
      'maxLength': 160,
    },
    ..._periodProperties,
  };

  static const Map<String, Object?> _partyAsOfProperties = <String, Object?>{
    'party_type': <String, Object?>{
      'type': 'string',
      'enum': <String>['customer', 'supplier'],
      'description': 'Choose customer receivables or supplier payables.',
    },
    'party': <String, Object?>{
      'type': 'string',
      'description': 'Customer or supplier name or ID as recorded in Ventio.',
      'maxLength': 160,
    },
    ..._asOfProperties,
  };

  static const Map<String, Object?> _stockBalanceProperties = <String, Object?>{
    'product': <String, Object?>{
      'type': 'string',
      'description': 'Optional product name or ID filter.',
      'maxLength': 120,
    },
    'warehouse': <String, Object?>{
      'type': 'string',
      'description': 'Optional warehouse name or ID filter.',
      'maxLength': 120,
    },
  };

  static const Map<String, Object?> _stockMovementProperties =
      <String, Object?>{
    ..._periodProperties,
    'product': <String, Object?>{
      'type': 'string',
      'description': 'Optional product name filter.',
      'maxLength': 120,
    },
    'warehouse': <String, Object?>{
      'type': 'string',
      'description': 'Optional warehouse name filter.',
      'maxLength': 120,
    },
    'type': <String, Object?>{
      'type': 'string',
      'description': 'Optional exact stock movement type filter.',
      'maxLength': 80,
    },
  };

  static AssistantJsonMap _tool({
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

  static bool _canViewAccounting(AppStore store) => store.canViewAccounting;

  static bool _canViewCustomerLedger(AppStore store) =>
      store.hasAnyPermission(<String>{
        AppPermission.customersLedgerView,
        AppPermission.customersManage,
      });

  static bool _canViewSupplierLedger(AppStore store) =>
      store.hasAnyPermission(<String>{
        AppPermission.suppliersLedgerView,
        AppPermission.suppliersManage,
      });

  static void _requireToolPermission(AppStore store, String name) {
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
      'sales_invoice_details' => store.canViewSales,
      'purchase_invoice_details' => store.canViewPurchases,
      'party_payment_history' =>
        _canViewCustomerLedger(store) || _canViewSupplierLedger(store),
      'party_balance_reconciliation' => _canViewAccounting(store) &&
          (_canViewCustomerLedger(store) || _canViewSupplierLedger(store)),
      'sales_summary' => store.canViewSales,
      'purchase_summary' => store.canViewPurchases,
      'expense_summary' => store.canViewExpenses,
      'current_stock_balances' ||
      'stock_movement_summary' =>
        store.canViewInventory || _canViewAccounting(store),
      'cash_balances' => store.canViewCashBox,
      'inventory_cost_valuation' ||
      'manufacturing_cost_summary' ||
      'manufacturing_waste' ||
      'inventory_count_variances' =>
        name == 'inventory_cost_valuation'
            ? store.canViewAccounting
            : store.canViewInventory || _canViewAccounting(store),
      'business_data_analysis' => store.canViewSales ||
          store.canViewPurchases ||
          store.canViewExpenses ||
          store.canViewInventory ||
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

  static void _requireReadDatabase() {
    if (!LocalDatabaseService.canQueryBusinessSqlite ||
        !AccountingService.isAvailable) {
      _throwBusinessDatabaseUnavailable();
    }
  }

  static Never _throwBusinessDatabaseUnavailable() {
    throw const AssistantReadToolException(
      'business_database_unavailable',
      'Ventio business data is not available for a local read right now.',
    );
  }

  static void _requireOnlyArguments(
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

  static String _optionalStringArgument(
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

  static String _normalizePartyName(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
      .replaceAll(RegExp(r'[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'\s+'), ' ');

  static String _transactionCurrency(
    AccountTransaction transaction,
    AppStore store,
  ) {
    final currency = transaction.currency.trim().toUpperCase();
    return currency.isEmpty ? store.storeProfile.baseCurrency : currency;
  }

  static int _compareAccountTransactions(
    AccountTransaction left,
    AccountTransaction right,
  ) {
    final byDate = left.date.compareTo(right.date);
    return byDate != 0 ? byDate : left.id.compareTo(right.id);
  }

  static String _customerTransactionTypeLabel(String type) {
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

  static _AssistantDatePeriod _parsePeriod(Map<String, Object?> arguments) {
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

  static DateTime? _parseOptionalDate(
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

  static DateTime _endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day + 1)
          .subtract(const Duration(microseconds: 1));

  static String _dateLabel(DateTime date) {
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  static List<AssistantJsonMap> _statementLines(
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

  static AssistantJsonMap _envelope(
    AppStore store,
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
      'baseCurrency': store.storeProfile.baseCurrency,
      'deviceRole': store.appIdentity.deviceRole.name,
      'branchFilterApplied': false,
      if (store.appIdentity.isClient) 'dataFreshness': 'client_local_copy',
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

class _AssistantDatePeriod {
  const _AssistantDatePeriod({
    required this.from,
    required this.toInclusive,
    required this.fromLabel,
    required this.toLabel,
  });

  final DateTime from;
  final DateTime toInclusive;
  final String fromLabel;
  final String toLabel;

  DateTime get toCalendarDate =>
      DateTime(toInclusive.year, toInclusive.month, toInclusive.day);
}

class _AssistantParty {
  const _AssistantParty(this.id, this.name);

  final String id;
  final String name;
}

class _PartyLedgerTotals {
  double debit = 0;
  double credit = 0;
  int count = 0;

  double get signedBalance => debit - credit;

  void add(AccountTransaction transaction) {
    debit += transaction.debit;
    credit += transaction.credit;
    count++;
  }
}
