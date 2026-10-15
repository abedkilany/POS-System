part of 'assistant_database_explorer_service.dart';

const Map<String, _TableSpec> _assistantDatabaseExplorerSpecsPart03 =
    <String, _TableSpec>{
  'journal_lines': _TableSpec(
    domain: _Domain.accounting,
    title: 'Journal lines',
    description:
        'Posted debit and credit lines. Monetary totals are separated by the line currency; use accounting reports for official statement totals.',
    baseTable: 'journal_lines',
    source: 'journal_lines jl JOIN journal_entries je ON je.id = jl.entry_id',
    scope: 'jl.store_id = ?',
    softDelete: "je.deleted_at = ''",
    dateExpression: 'je.entry_date',
    searchExpressions: <String>[
      'jl.account_name',
      'jl.account_code',
      'jl.party_name',
      'jl.memo'
    ],
    dimensions: <String, _DimensionSpec>{
      'account_name': _DimensionSpec('jl.account_name', 'Account', 'text'),
      'account_code': _DimensionSpec('jl.account_code', 'Account code', 'text'),
      'party_name': _DimensionSpec('jl.party_name', 'Party', 'text'),
      'party_type': _DimensionSpec('jl.party_type', 'Party type', 'text'),
      'entry_date': _DimensionSpec('je.entry_date', 'Entry date', 'date'),
      'reference_type':
          _DimensionSpec('je.reference_type', 'Reference type', 'text'),
      'currency': _DimensionSpec('jl.currency', 'Currency', 'currency'),
      'branch_id': _DimensionSpec('jl.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'line_count': _MeasureSpec('COUNT(*)', 'Journal line count', 'lines'),
      'debit': _MeasureSpec('SUM(jl.debit)', 'Debit', 'money',
          currencyExpression: 'jl.currency'),
      'credit': _MeasureSpec('SUM(jl.credit)', 'Credit', 'money',
          currencyExpression: 'jl.currency'),
    },
    defaultFilter: "lower(je.status) = 'posted'",
    relationships: <String>[
      'journal_lines.entry_id = journal_entries.id',
      'journal_lines.account_id = accounts.id',
      'journal_lines.party_id references customers or suppliers according to party_type',
    ],
  ),
  'accounts': _TableSpec(
    domain: _Domain.accounting,
    title: 'Chart of accounts',
    description: 'Accounting account definitions and their classification.',
    baseTable: 'accounts',
    source: 'accounts a',
    scope: 'a.store_id = ?',
    softDelete: "a.deleted_at = ''",
    searchExpressions: <String>['a.code', 'a.name', 'a.type', 'a.subtype'],
    dimensions: <String, _DimensionSpec>{
      'code': _DimensionSpec('a.code', 'Account code', 'text'),
      'name': _DimensionSpec('a.name', 'Account name', 'text'),
      'type': _DimensionSpec('a.type', 'Account type', 'text'),
      'subtype': _DimensionSpec('a.subtype', 'Account subtype', 'text'),
      'normal_balance':
          _DimensionSpec('a.normal_balance', 'Normal balance', 'text'),
      'is_active': _DimensionSpec('a.is_active', 'Active status', 'boolean'),
      'branch_id': _DimensionSpec('a.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'account_count': _MeasureSpec('COUNT(*)', 'Account count', 'records'),
    },
    relationships: <String>['accounts.id = journal_lines.account_id'],
  ),
  'accounting_periods': _TableSpec(
    domain: _Domain.accounting,
    title: 'Accounting periods',
    description: 'Accounting period ranges and their open or closed status.',
    baseTable: 'accounting_periods',
    source: 'accounting_periods ap',
    scope: 'ap.store_id = ?',
    searchExpressions: <String>['ap.name', 'ap.status'],
    dimensions: <String, _DimensionSpec>{
      'name': _DimensionSpec('ap.name', 'Period name', 'text'),
      'start_date': _DimensionSpec('ap.start_date', 'Start date', 'date'),
      'end_date': _DimensionSpec('ap.end_date', 'End date', 'date'),
      'status': _DimensionSpec('ap.status', 'Period status', 'text'),
      'branch_id': _DimensionSpec('ap.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'period_count':
          _MeasureSpec('COUNT(*)', 'Accounting period count', 'records'),
    },
    relationships: <String>[
      'accounting_periods.status determines whether a period is open or closed',
      'accounting_periods.branch_id = accounting_branches.id',
    ],
  ),
  'accounting_branches': _TableSpec(
    domain: _Domain.accounting,
    title: 'Accounting branches',
    description: 'Branch directory used by accounting and business records.',
    baseTable: 'accounting_branches',
    source: 'accounting_branches ab',
    scope: 'ab.store_id = ?',
    softDelete: "ab.deleted_at = ''",
    searchExpressions: <String>['ab.code', 'ab.name'],
    dimensions: <String, _DimensionSpec>{
      'code': _DimensionSpec('ab.code', 'Branch code', 'text'),
      'name': _DimensionSpec('ab.name', 'Branch name', 'text'),
      'is_active': _DimensionSpec('ab.is_active', 'Active status', 'boolean'),
    },
    measures: <String, _MeasureSpec>{
      'branch_count': _MeasureSpec('COUNT(*)', 'Branch count', 'records'),
    },
    relationships: <String>[
      'accounting_branches.id = business record branch_id values',
    ],
  ),
  'costing_method_history': _TableSpec(
    domain: _Domain.accounting,
    title: 'Costing method history',
    description:
        'Historical inventory costing method changes and their effective periods.',
    baseTable: 'costing_method_history',
    source: 'costing_method_history cmh',
    scope: 'cmh.store_id = ?',
    softDelete: "cmh.deleted_at = ''",
    dateExpression: 'cmh.effective_from',
    searchExpressions: <String>['cmh.method', 'cmh.reason'],
    dimensions: <String, _DimensionSpec>{
      'method': _DimensionSpec('cmh.method', 'Costing method', 'text'),
      'effective_from':
          _DimensionSpec('cmh.effective_from', 'Effective from', 'date'),
      'effective_to':
          _DimensionSpec('cmh.effective_to', 'Effective to', 'date'),
      'branch_id': _DimensionSpec('cmh.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'change_count':
          _MeasureSpec('COUNT(*)', 'Costing method history rows', 'records'),
    },
    relationships: <String>[
      'The method applies to inventory cost layers and stock movements from its effective date.',
    ],
  ),
  'cost_centers': _TableSpec(
    domain: _Domain.accounting,
    title: 'Cost centers',
    description: 'Cost center definitions used to classify accounting lines.',
    baseTable: 'cost_centers',
    source: 'cost_centers cc',
    scope: 'cc.store_id = ?',
    softDelete: "cc.deleted_at = ''",
    searchExpressions: <String>['cc.code', 'cc.name'],
    dimensions: <String, _DimensionSpec>{
      'code': _DimensionSpec('cc.code', 'Cost center code', 'text'),
      'name': _DimensionSpec('cc.name', 'Cost center name', 'text'),
      'is_active': _DimensionSpec('cc.is_active', 'Active status', 'boolean'),
      'branch_id': _DimensionSpec('cc.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'cost_center_count':
          _MeasureSpec('COUNT(*)', 'Cost center count', 'records'),
    },
    relationships: <String>['cost_centers.id = journal_lines.cost_center_id'],
  ),
  'account_transactions': _TableSpec(
    domain: _Domain.accounting,
    title: 'Party account transactions',
    description:
        'Stored customer and supplier account movements. Debits and credits are returned separately; use the dedicated party statement for a signed running balance.',
    baseTable: 'account_transactions',
    source: 'account_transactions at',
    scope: 'at.store_id = ?',
    softDelete: "at.deleted_at = ''",
    dateExpression: 'at.transaction_date',
    searchExpressions: <String>[
      'at.account_name',
      'at.reference_no',
      'at.transaction_type',
    ],
    dimensions: <String, _DimensionSpec>{
      'account_type': _DimensionSpec('at.account_type', 'Party type', 'text'),
      'account_name': _DimensionSpec('at.account_name', 'Party', 'text'),
      'transaction_type':
          _DimensionSpec('at.transaction_type', 'Transaction type', 'text'),
      'transaction_date':
          _DimensionSpec('at.transaction_date', 'Transaction date', 'date'),
      'currency': _DimensionSpec('at.currency', 'Currency', 'currency'),
      'branch_id': _DimensionSpec('at.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'transaction_count':
          _MeasureSpec('COUNT(*)', 'Transaction count', 'records'),
      'debit': _MeasureSpec('SUM(at.debit)', 'Debit', 'money',
          currencyExpression: 'at.currency'),
      'credit': _MeasureSpec('SUM(at.credit)', 'Credit', 'money',
          currencyExpression: 'at.currency'),
    },
    relationships: <String>[
      'account_transactions.account_id and account_type identify the party account',
      'account_transactions.reference_id references the source invoice or payment',
    ],
  ),
  'cash_ledger_transactions': _TableSpec(
    domain: _Domain.cash,
    title: 'Cash ledger transactions',
    description:
        'Recorded cash and bank movement events. Amounts are separated by currency and direction; use the cash balance report for current balances.',
    baseTable: 'cash_ledger_transactions',
    source: 'cash_ledger_transactions cl',
    scope: 'cl.store_id = ?',
    softDelete: "cl.deleted_at = ''",
    dateExpression: 'cl.occurred_at',
    searchExpressions: <String>[
      'cl.type',
      'cl.party_name',
      'cl.reference_number',
      'cl.payment_method'
    ],
    dimensions: <String, _DimensionSpec>{
      'type': _DimensionSpec('cl.type', 'Transaction type', 'text'),
      'direction': _DimensionSpec('cl.direction', 'Direction', 'text'),
      'currency': _DimensionSpec('cl.currency', 'Currency', 'currency'),
      'party_name': _DimensionSpec('cl.party_name', 'Party', 'text'),
      'party_type': _DimensionSpec('cl.party_type', 'Party type', 'text'),
      'payment_method':
          _DimensionSpec('cl.payment_method', 'Payment method', 'text'),
      'occurred_at':
          _DimensionSpec('cl.occurred_at', 'Transaction date', 'date'),
      'branch_id': _DimensionSpec('cl.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'transaction_count':
          _MeasureSpec('COUNT(*)', 'Transaction count', 'records'),
      'amount': _MeasureSpec('SUM(cl.amount)', 'Transaction amount', 'money',
          currencyExpression: 'cl.currency',
          contextExpression: 'cl.direction',
          contextLabel: 'direction'),
    },
    defaultFilter: "COALESCE(cl.reversal_of_id, '') = ''",
    defaultFilterDescription: 'Reversal rows are excluded.',
    relationships: <String>[
      'cash_ledger_transactions.cash_location_id = cash_locations.id',
      'cash_ledger_transactions.cash_drawer_session_id = cash_drawer_sessions.id',
      'cash_ledger_transactions.reference_id references its source document by reference_type',
    ],
  ),
  'cash_operations': _TableSpec(
    domain: _Domain.cash,
    title: 'Cash operations',
    description: 'Cash operations and their posting or reversal status.',
    baseTable: 'cash_operations',
    source: 'cash_operations co',
    scope: 'co.store_id = ?',
    softDelete: "co.deleted_at = ''",
    dateExpression: 'co.operation_date',
    searchExpressions: <String>[
      'co.operation_no',
      'co.operation_type',
      'co.status'
    ],
    dimensions: <String, _DimensionSpec>{
      'operation_no':
          _DimensionSpec('co.operation_no', 'Operation number', 'text'),
      'operation_type':
          _DimensionSpec('co.operation_type', 'Operation type', 'text'),
      'operation_date':
          _DimensionSpec('co.operation_date', 'Operation date', 'date'),
      'status': _DimensionSpec('co.status', 'Status', 'text'),
      'branch_id': _DimensionSpec('co.branch_id', 'Branch', 'text'),
      'currency': _DimensionSpec('co.currency', 'Currency', 'currency'),
    },
    measures: <String, _MeasureSpec>{
      'operation_count': _MeasureSpec('COUNT(*)', 'Operation count', 'records'),
      'amount': _MeasureSpec('SUM(co.amount)', 'Operation amount', 'money',
          currencyExpression: 'co.currency',
          contextExpression: 'co.operation_type',
          contextLabel: 'operation type',
          additionalContextExpression: 'co.status',
          additionalContextLabel: 'operation status'),
    },
    relationships: <String>[
      'cash_operations.cash_location_id = cash_locations.id'
    ],
  ),
  'receipt_vouchers': _TableSpec(
    domain: _Domain.cash,
    title: 'Receipt vouchers',
    description:
        'Customer receipt vouchers; amounts are grouped by voucher currency.',
    baseTable: 'receipt_vouchers',
    source: 'receipt_vouchers rv',
    scope: 'rv.store_id = ?',
    softDelete: "rv.deleted_at = ''",
    dateExpression: 'rv.voucher_date',
    searchExpressions: <String>[
      'rv.voucher_no',
      'rv.customer_name',
      'rv.status'
    ],
    dimensions: <String, _DimensionSpec>{
      'voucher_no': _DimensionSpec('rv.voucher_no', 'Voucher number', 'text'),
      'customer_name': _DimensionSpec('rv.customer_name', 'Customer', 'text'),
      'voucher_date': _DimensionSpec('rv.voucher_date', 'Voucher date', 'date'),
      'status': _DimensionSpec('rv.status', 'Status', 'text'),
      'currency': _DimensionSpec('rv.currency', 'Currency', 'currency'),
      'branch_id': _DimensionSpec('rv.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'voucher_count': _MeasureSpec('COUNT(*)', 'Voucher count', 'records'),
      'amount': _MeasureSpec('SUM(rv.amount)', 'Receipt amount', 'money',
          currencyExpression: 'rv.currency',
          contextExpression: 'rv.status',
          contextLabel: 'voucher status'),
    },
    relationships: <String>[
      'receipt_vouchers.customer_id = customers.id',
      'payment_allocations.voucher_id references receipt_vouchers.id when voucher_type is receipt',
    ],
  ),
  'payment_vouchers': _TableSpec(
    domain: _Domain.cash,
    title: 'Payment vouchers',
    description:
        'Supplier payment vouchers; amounts are grouped by voucher currency.',
    baseTable: 'payment_vouchers',
    source: 'payment_vouchers pv',
    scope: 'pv.store_id = ?',
    softDelete: "pv.deleted_at = ''",
    dateExpression: 'pv.voucher_date',
    searchExpressions: <String>[
      'pv.voucher_no',
      'pv.supplier_name',
      'pv.status'
    ],
    dimensions: <String, _DimensionSpec>{
      'voucher_no': _DimensionSpec('pv.voucher_no', 'Voucher number', 'text'),
      'supplier_name': _DimensionSpec('pv.supplier_name', 'Supplier', 'text'),
      'voucher_date': _DimensionSpec('pv.voucher_date', 'Voucher date', 'date'),
      'status': _DimensionSpec('pv.status', 'Status', 'text'),
      'currency': _DimensionSpec('pv.currency', 'Currency', 'currency'),
      'branch_id': _DimensionSpec('pv.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'voucher_count': _MeasureSpec('COUNT(*)', 'Voucher count', 'records'),
      'amount': _MeasureSpec('SUM(pv.amount)', 'Payment amount', 'money',
          currencyExpression: 'pv.currency',
          contextExpression: 'pv.status',
          contextLabel: 'voucher status'),
    },
    relationships: <String>[
      'payment_vouchers.supplier_id = suppliers.id',
      'payment_allocations.voucher_id references payment_vouchers.id when voucher_type is payment',
    ],
  ),
  'payment_allocations': _TableSpec(
    domain: _Domain.cash,
    title: 'Voucher allocations',
    description:
        'Amounts allocated from receipt or payment vouchers to sales or purchase documents. The query scopes each allocation through its parent voucher and keeps voucher and reference currencies separate.',
    baseTable: 'payment_allocations',
    source: '''payment_allocations pa
        LEFT JOIN receipt_vouchers rv
          ON pa.voucher_type = 'receipt' AND rv.id = pa.voucher_id AND rv.deleted_at = ''
        LEFT JOIN payment_vouchers pv
          ON pa.voucher_type = 'payment' AND pv.id = pa.voucher_id AND pv.deleted_at = '''
        '',
    scope: 'COALESCE(rv.store_id, pv.store_id) = ?',
    softDelete: "COALESCE(pa.deleted_at, '') = ''",
    dateExpression: 'COALESCE(rv.voucher_date, pv.voucher_date)',
    searchExpressions: <String>[
      'pa.reference_number',
      'rv.customer_name',
      'pv.supplier_name',
    ],
    dimensions: <String, _DimensionSpec>{
      'voucher_type': _DimensionSpec('pa.voucher_type', 'Voucher type', 'text'),
      'reference_type':
          _DimensionSpec('pa.reference_type', 'Applied document type', 'text'),
      'reference_number': _DimensionSpec(
          'pa.reference_number', 'Applied document number', 'text'),
      'status': _DimensionSpec('pa.status', 'Allocation status', 'text'),
      'allocation_kind':
          _DimensionSpec('pa.allocation_kind', 'Allocation kind', 'text'),
      'currency': _DimensionSpec('pa.currency', 'Voucher currency', 'currency'),
      'reference_currency': _DimensionSpec(
          'pa.reference_currency', 'Document currency', 'currency'),
      'voucher_date': _DimensionSpec(
          'COALESCE(rv.voucher_date, pv.voucher_date)', 'Voucher date', 'date'),
      'branch_id': _DimensionSpec(
          'COALESCE(rv.branch_id, pv.branch_id)', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'allocation_count':
          _MeasureSpec('COUNT(*)', 'Allocation count', 'records'),
      'voucher_amount': _MeasureSpec(
          'SUM(pa.amount)', 'Amount applied in voucher currency', 'money',
          currencyExpression: 'pa.currency',
          contextExpression: 'pa.voucher_type',
          contextLabel: 'voucher type',
          additionalContextExpression: 'pa.status',
          additionalContextLabel: 'allocation status'),
      'reference_amount': _MeasureSpec('SUM(pa.reference_amount)',
          'Amount applied in document currency', 'money',
          currencyExpression: 'pa.reference_currency',
          contextExpression: 'pa.reference_type',
          contextLabel: 'document type',
          additionalContextExpression: 'pa.status',
          additionalContextLabel: 'allocation status'),
    },
    relationships: <String>[
      'payment_allocations.voucher_type receipt joins receipt_vouchers.id',
      'payment_allocations.voucher_type payment joins payment_vouchers.id',
      'payment_allocations.reference_id identifies a sales or purchase document by reference_type',
    ],
  ),
  'cash_locations': _TableSpec(
    domain: _Domain.cash,
    title: 'Cash and bank locations',
    description:
        'Cash drawers, bank accounts, and other configured payment locations.',
    baseTable: 'cash_locations',
    source: 'cash_locations loc',
    scope: 'loc.store_id = ?',
    softDelete: "loc.deleted_at = ''",
    searchExpressions: <String>['loc.name', 'loc.code', 'loc.type'],
    dimensions: <String, _DimensionSpec>{
      'name': _DimensionSpec('loc.name', 'Location name', 'text'),
      'type': _DimensionSpec('loc.type', 'Location type', 'text'),
      'is_active': _DimensionSpec('loc.is_active', 'Active status', 'boolean'),
      'branch_id': _DimensionSpec('loc.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'location_count': _MeasureSpec('COUNT(*)', 'Location count', 'records'),
    },
    relationships: <String>[
      'cash_locations.id = cash_ledger_transactions.cash_location_id',
      'cash_locations.id = cash_operations.cash_location_id',
    ],
  ),
  'payment_accounts': _TableSpec(
    domain: _Domain.cash,
    title: 'Payment accounts',
    description:
        'Configured payment accounts and their active or default status. Account credentials are not exposed by this tool.',
    baseTable: 'payment_accounts',
    source: 'payment_accounts pac',
    scope: 'pac.store_id = ?',
    softDelete: "pac.deleted_at = ''",
    searchExpressions: <String>['pac.name', 'pac.type'],
    dimensions: <String, _DimensionSpec>{
      'name': _DimensionSpec('pac.name', 'Payment account name', 'text'),
      'type': _DimensionSpec('pac.type', 'Payment account type', 'text'),
      'is_default':
          _DimensionSpec('pac.is_default', 'Default status', 'boolean'),
      'is_active': _DimensionSpec('pac.is_active', 'Active status', 'boolean'),
      'branch_id': _DimensionSpec('pac.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'account_count':
          _MeasureSpec('COUNT(*)', 'Payment account count', 'records'),
    },
    relationships: <String>[
      'payment_accounts.account_id = accounts.id',
      'cash_locations.payment_account_id = payment_accounts.id',
    ],
  ),
  'cash_drawer_sessions': _TableSpec(
    domain: _Domain.cash,
    title: 'Cash drawer sessions',
    description:
        'Cashier shift sessions and open or closed status. Session totals are not combined because the table does not contain a currency column.',
    baseTable: 'cash_drawer_sessions',
    source: 'cash_drawer_sessions cds',
    scope: 'cds.store_id = ?',
    dateExpression: 'cds.opened_at',
    searchExpressions: <String>['cds.drawer_no', 'cds.status', 'cds.opened_by'],
    dimensions: <String, _DimensionSpec>{
      'drawer_no': _DimensionSpec('cds.drawer_no', 'Drawer number', 'text'),
      'status': _DimensionSpec('cds.status', 'Session status', 'text'),
      'branch_id': _DimensionSpec('cds.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'session_count':
          _MeasureSpec('COUNT(*)', 'Drawer session count', 'records'),
    },
    relationships: <String>[
      'cash_drawer_sessions.cash_location_id = cash_locations.id',
      'cash_drawer_sessions.id = receipt_vouchers.cash_drawer_session_id',
      'cash_drawer_sessions.id = payment_vouchers.cash_drawer_session_id',
    ],
  ),
  'cash_transfers': _TableSpec(
    domain: _Domain.cash,
    title: 'Cash transfers',
    description:
        'Transfers between cash or bank locations. Only document counts are aggregated because this table does not store a currency per amount.',
    baseTable: 'cash_transfers',
    source: 'cash_transfers ct',
    scope: 'ct.store_id = ?',
    softDelete: "ct.deleted_at = ''",
    dateExpression: 'ct.transfer_date',
    searchExpressions: <String>[
      'ct.transfer_no',
      'ct.status',
      'ct.transfer_kind'
    ],
    dimensions: <String, _DimensionSpec>{
      'transfer_no':
          _DimensionSpec('ct.transfer_no', 'Transfer number', 'text'),
      'transfer_date':
          _DimensionSpec('ct.transfer_date', 'Transfer date', 'date'),
      'status': _DimensionSpec('ct.status', 'Status', 'text'),
      'transfer_kind':
          _DimensionSpec('ct.transfer_kind', 'Transfer kind', 'text'),
      'branch_id': _DimensionSpec('ct.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'transfer_count':
          _MeasureSpec('COUNT(*)', 'Cash transfer count', 'documents'),
    },
    relationships: <String>[
      'cash_transfers.from_location_id = cash_locations.id',
      'cash_transfers.to_location_id = cash_locations.id',
    ],
  ),
  'cheques': _TableSpec(
    domain: _Domain.cash,
    title: 'Cheques',
    description:
        'Cheque records by direction, party, due date, and settlement status. Amounts are not aggregated because the table has no currency column.',
    baseTable: 'cheques',
    source: 'cheques ch',
    scope: 'ch.store_id = ?',
    dateExpression: 'ch.due_date',
    searchExpressions: <String>[
      'ch.cheque_no',
      'ch.party_name',
      'ch.status',
      'ch.bank_name'
    ],
    dimensions: <String, _DimensionSpec>{
      'direction': _DimensionSpec('ch.direction', 'Cheque direction', 'text'),
      'party_name': _DimensionSpec('ch.party_name', 'Party', 'text'),
      'party_type': _DimensionSpec('ch.party_type', 'Party type', 'text'),
      'status': _DimensionSpec('ch.status', 'Status', 'text'),
      'due_date': _DimensionSpec('ch.due_date', 'Due date', 'date'),
      'branch_id': _DimensionSpec('ch.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'cheque_count': _MeasureSpec('COUNT(*)', 'Cheque count', 'records'),
    },
    relationships: <String>[
      'cheques.party_id refers to a customer or supplier according to party_type',
      'cheques.journal_entry_id = journal_entries.id',
    ],
  ),
  'fixed_assets': _TableSpec(
    domain: _Domain.accounting,
    title: 'Fixed assets',
    description: 'Fixed asset register and acquisition values.',
    baseTable: 'fixed_assets',
    source: 'fixed_assets fa',
    scope: 'fa.store_id = ?',
    softDelete: "fa.deleted_at = ''",
    dateExpression: 'fa.acquisition_date',
    searchExpressions: <String>[
      'fa.code',
      'fa.name',
      'fa.category',
      'fa.status'
    ],
    dimensions: <String, _DimensionSpec>{
      'code': _DimensionSpec('fa.code', 'Asset code', 'text'),
      'name': _DimensionSpec('fa.name', 'Asset name', 'text'),
      'category': _DimensionSpec('fa.category', 'Category', 'text'),
      'acquisition_date':
          _DimensionSpec('fa.acquisition_date', 'Acquisition date', 'date'),
      'status': _DimensionSpec('fa.status', 'Status', 'text'),
      'branch_id': _DimensionSpec('fa.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'asset_count': _MeasureSpec('COUNT(*)', 'Asset count', 'records'),
      'purchase_value': _MeasureSpec(
          'SUM(fa.purchase_value)', 'Recorded purchase value', 'recorded_value',
          currencyLabel: 'Ventio base currency',
          contextExpression: 'fa.status',
          contextLabel: 'asset status'),
    },
    relationships: <String>[
      'fixed_assets.id = fixed_asset_depreciation.asset_id',
      'fixed_assets.asset_account_id = accounts.id',
    ],
  ),
  'fixed_asset_depreciation': _TableSpec(
    domain: _Domain.accounting,
    title: 'Fixed asset depreciation',
    description: 'Recorded fixed asset depreciation entries and book values.',
    baseTable: 'fixed_asset_depreciation',
    source: 'fixed_asset_depreciation fad',
    scope: 'fad.store_id = ?',
    softDelete: "fad.deleted_at = ''",
    dateExpression: 'fad.depreciation_date',
    searchExpressions: <String>['fad.period_key'],
    dimensions: <String, _DimensionSpec>{
      'period_key':
          _DimensionSpec('fad.period_key', 'Depreciation period', 'text'),
      'depreciation_date':
          _DimensionSpec('fad.depreciation_date', 'Depreciation date', 'date'),
      'branch_id': _DimensionSpec('fad.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'entry_count':
          _MeasureSpec('COUNT(*)', 'Depreciation entry count', 'records'),
      'amount': _MeasureSpec(
          'SUM(fad.amount)', 'Depreciation amount', 'recorded_value',
          currencyLabel: 'Ventio base currency'),
    },
    relationships: <String>[
      'fixed_asset_depreciation.asset_id = fixed_assets.id'
    ],
  ),
  'sale_quotations': _TableSpec(
    domain: _Domain.sales,
    title: 'Sales quotations',
    description: 'Sales quotation headers and conversion status.',
    baseTable: 'sale_quotations',
    source: 'sale_quotations sq',
    scope: 'sq.store_id = ?',
    softDelete: "sq.deleted_at = ''",
    dateExpression: 'sq.document_date',
    searchExpressions: <String>[
      'sq.quotation_no',
      'sq.customer_name',
      'sq.status'
    ],
    dimensions: <String, _DimensionSpec>{
      'quotation_no':
          _DimensionSpec('sq.quotation_no', 'Quotation number', 'text'),
      'customer_name': _DimensionSpec('sq.customer_name', 'Customer', 'text'),
      'document_date':
          _DimensionSpec('sq.document_date', 'Quotation date', 'date'),
      'valid_until': _DimensionSpec('sq.valid_until', 'Valid until', 'date'),
      'status': _DimensionSpec('sq.status', 'Status', 'text'),
      'invoice_currency':
          _DimensionSpec('sq.invoice_currency', 'Currency', 'currency'),
      'branch_id': _DimensionSpec('sq.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'quotation_count':
          _MeasureSpec('COUNT(*)', 'Quotation count', 'documents'),
    },
    relationships: <String>[
      'sale_quotations.id = sale_quotation_items.sale_quotation_id',
      'sale_quotations.converted_sale_id = sales.id',
    ],
  ),
};
