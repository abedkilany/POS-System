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

part 'assistant_read_tool_service_impl_01.dart';
part 'assistant_read_tool_service_impl_02.dart';
part 'assistant_read_tool_service_impl_03.dart';
part 'assistant_read_tool_service_impl_04.dart';

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
const int _maxReturnedRows = 100;

const int _maxCustomerStatementRows = 40;

const int _maxInvoiceMatches = 8;

const int _maxInvoiceLines = 20;

const int _maxPaymentHistoryRows = 40;

const int _maxPaymentHistoryPages = 10;

const Set<String> _knownToolNames = <String>{
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

const Map<String, Object?> _periodProperties = <String, Object?>{
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

const Map<String, Object?> _asOfProperties = <String, Object?>{
  'as_of': <String, Object?>{
    'type': 'string',
    'format': 'date',
    'description': 'As-of date in YYYY-MM-DD format. Defaults to today.',
  },
};

const Map<String, Object?> _customerStatementProperties = <String, Object?>{
  'customer': <String, Object?>{
    'type': 'string',
    'description': 'Customer name or ID as recorded in Ventio.',
    'maxLength': 160,
  },
  ..._periodProperties,
};

const Map<String, Object?> _supplierStatementProperties = <String, Object?>{
  'supplier': <String, Object?>{
    'type': 'string',
    'description': 'Supplier name or ID as recorded in Ventio.',
    'maxLength': 160,
  },
  ..._periodProperties,
};

const Map<String, Object?> _invoiceSearchProperties = <String, Object?>{
  'query': <String, Object?>{
    'type': 'string',
    'description': 'Invoice/document number, party name, or product name.',
    'maxLength': 160,
  },
  ..._periodProperties,
};

const Map<String, Object?> _partyPaymentHistoryProperties = <String, Object?>{
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

const Map<String, Object?> _partyAsOfProperties = <String, Object?>{
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

const Map<String, Object?> _stockBalanceProperties = <String, Object?>{
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

const Map<String, Object?> _stockMovementProperties = <String, Object?>{
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

class AssistantReadToolService {
  AssistantReadToolService();
  static final _AssistantReadToolServiceImplementation
      _assistantReadToolServiceImplementation =
      _AssistantReadToolServiceImplementation();

  static List<AssistantJsonMap> definitionsFor(AppStore store) =>
      _assistantReadToolServiceImplementation.definitionsFor(store);

  static Future<AssistantJsonMap> execute({
    required AppStore store,
    required String name,
    required Map<String, Object?> arguments,
    DateTime? now,
  }) =>
      _assistantReadToolServiceImplementation.execute(
          store: store, name: name, arguments: arguments, now: now);
}

class _AssistantReadToolServiceImplementation {}

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
