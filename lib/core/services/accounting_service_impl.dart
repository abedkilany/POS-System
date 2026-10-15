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
import '../localization/localized_domain_exception.dart';
import '../utils/currency_utils.dart';
import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/ventio_drift_database.dart';
import '../storage/sqlite/business_sqlite_store.dart';
import 'cash_balance_policy_service.dart';
import 'cash_ledger_service.dart';
import 'posted_document_edit_framework.dart';
import 'unified_batch_phase4_closure_service.dart';
import 'accounting_service_models.dart';

part 'accounting_service_inventory_setup.dart';
part 'accounting_service_accounts_settings.dart';
part 'accounting_service_sales_purchases.dart';
part 'accounting_service_expenses.dart';
part 'accounting_service_expense_posting.dart';
part 'accounting_service_voucher_posting.dart';
part 'accounting_service_journal_reversals.dart';
part 'accounting_service_ledger_reports.dart';
part 'accounting_service_inventory_reports.dart';
part 'accounting_service_cash_tax_reports.dart';
part 'accounting_service_cash_operations.dart';
part 'accounting_service_fixed_assets.dart';
part 'accounting_service_manual_journals.dart';
part 'accounting_service_inventory_mutations.dart';
part 'accounting_service_cash_drawers.dart';
part 'accounting_service_cash_transfers.dart';
part 'accounting_service_accounting_helpers.dart';
part 'accounting_service_internal_types.dart';

/// Set when a BOM change was saved while the inventory account
/// classification check was deferred because the Unified Batch valuation
/// did not yet reconcile to the inventory GL. The marker is intentionally
/// local and persistent so a later successful reconciliation can clear it.
const String deferredBomInventoryReconciliationKey =
    'inventory_bom_account_reconciliation_pending_v1';

final Random _random = Random.secure();

StoreProfile _moneyProfile = StoreProfile.defaults;

void Function()? _mutationListener;

int? _entryNoCacheDbIdentity;

int? _settingsCacheDbIdentity;

Map<String, String>? _defaultAccountMapCache;

Map<String, String>? _accountRoleMapCache;

double? _defaultVatRateCache;

final Map<String, String> _paymentAccountByTypeCache = <String, String>{};

int? _accountSnapshotCacheDbIdentity;

final Map<String, AccountingAccount> _accountSnapshotByIdCache =
    <String, AccountingAccount>{};

final Map<int, int> _entryNoSequenceByYear = <int, int>{};

Future<void> _entryNoQueue = Future<void>.value();

const Set<String> supportedAccountTypes = <String>{
  'asset',
  'liability',
  'equity',
  'revenue',
  'cost_of_sales',
  'expense',
};

const Set<String> supportedNormalBalances = <String>{'debit', 'credit'};
