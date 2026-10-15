part of 'assistant_read_tool_service.dart';

extension _AssistantReadToolServicePart1
    on _AssistantReadToolServiceImplementation {
  List<AssistantJsonMap> definitionsFor(AppStore store) {
    if (!LocalDatabaseService.canQueryBusinessSqlite ||
        !AccountingService.isAvailable) {
      return const <AssistantJsonMap>[];
    }
    final tools = <AssistantJsonMap>[];
    if (store.security.canViewAccounting) {
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
    if (store.security.canViewSales) {
      tools.add(_tool(
        name: 'sales_invoice_details',
        description:
            'Read saved sales invoices by invoice number, customer name, or product name. Returns invoice status, currency, totals, paid and due amounts, returns, and line details. Does not include deleted invoices.',
        properties: _invoiceSearchProperties,
        required: const <String>['query'],
      ));
    }
    if (store.security.canViewPurchases) {
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
    if (store.security.canViewAccounting &&
        (_canViewCustomerLedger(store) || _canViewSupplierLedger(store))) {
      tools.add(_tool(
        name: 'party_balance_reconciliation',
        description:
            'Compare a named customer or supplier subledger balance with Ventio\'s accounting aging report as of a date. Return both source figures, open documents, currency basis, and a calculated comparison only when the currencies and balance meanings are comparable. Keep gross aging separate from credits or advances.',
        properties: _partyAsOfProperties,
        required: const <String>['party_type', 'party'],
      ));
    }
    if (store.security.canViewSales) {
      tools.add(_tool(
        name: 'sales_summary',
        description:
            'Read non-cancelled sales invoice counts and gross saved base amounts by base currency for an inclusive date range. Use income_statement for accounting revenue and returns.',
        properties: _periodProperties,
        required: const <String>['from', 'to'],
      ));
    }
    if (store.security.canViewPurchases) {
      tools.add(_tool(
        name: 'purchase_summary',
        description:
            'Read received purchase and purchase-return counts and amounts in USD reference value for an inclusive date range. Draft and cancelled purchases are excluded.',
        properties: _periodProperties,
        required: const <String>['from', 'to'],
      ));
    }
    if (store.security.canViewExpenses) {
      tools.add(_tool(
        name: 'expense_summary',
        description:
            'Read posted expense totals and category totals in USD reference value for an inclusive date range. Draft, cancelled, and deleted expenses are excluded.',
        properties: _periodProperties,
        required: const <String>['from', 'to'],
      ));
    }
    if (store.security.canViewCashBox) {
      tools.add(_tool(
        name: 'cash_balances',
        description: 'Read current Ventio cash and bank balances.',
        properties: const <String, Object?>{},
      ));
    }
    if (store.security.canViewAccounting) {
      tools.add(_tool(
        name: 'inventory_cost_valuation',
        description:
            'Read current Ventio inventory quantities and accounting cost valuation for all stored dates. This is cost value, not retail value.',
        properties: const <String, Object?>{},
      ));
    }
    if (store.security.canViewInventory || store.security.canViewAccounting) {
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
    if (store.security.canViewInventory || store.security.canViewAccounting) {
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
}
