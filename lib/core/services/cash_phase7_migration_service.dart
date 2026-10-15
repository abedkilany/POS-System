import 'dart:math';

import 'package:drift/drift.dart';

import '../../models/purchase.dart';
import '../../models/sale.dart';
import '../storage/sqlite/business_sqlite_store.dart';
import '../storage/sqlite/ventio_drift_database.dart';
import 'accounting_service.dart';
import 'payment_voucher_service.dart';
part 'cash_phase7_migration_service_methods_01.dart';
part 'cash_phase7_migration_service_methods_02.dart';

class CashPhase7Issue {
  const CashPhase7Issue({
    required this.type,
    required this.details,
    this.severity = 'warning',
    this.entityType = '',
    this.entityId = '',
    this.referenceNo = '',
  });

  final String severity;
  final String type;
  final String entityType;
  final String entityId;
  final String referenceNo;
  final String details;
}

class CashPhase7Report {
  const CashPhase7Report({
    required this.runId,
    required this.legacyReceiptsFound,
    required this.legacyPaymentsFound,
    required this.vouchersCreated,
    required this.allocationsCreated,
    required this.invoiceEntriesCreated,
    required this.voucherEntriesCreated,
    required this.ledgerRowsCreated,
    required this.paymentCachesRebuilt,
    required this.issues,
  });

  final String runId;
  final int legacyReceiptsFound;
  final int legacyPaymentsFound;
  final int vouchersCreated;
  final int allocationsCreated;
  final int invoiceEntriesCreated;
  final int voucherEntriesCreated;
  final int ledgerRowsCreated;
  final int paymentCachesRebuilt;
  final List<CashPhase7Issue> issues;

  bool get hasErrors => issues.any((issue) => issue.severity == 'error');
}

/// Phase 7 migration/reconciliation for the rebuilt cash module.
///
/// Guarantees:
/// - legacy account_transactions payments become first-class vouchers exactly once;
/// - historical cash is never moved a second time;
/// - invoice paid_amount is rebuilt from active allocations, not trusted as a source;
/// - missing invoice/voucher journal entries and Cash Ledger history are repaired;
/// - unresolved history is reported instead of guessed.
class CashPhase7MigrationService {
  CashPhase7MigrationService(this._db);

  final VentioDriftDatabase _db;
  static const double _epsilon = 0.000001;
  static final Random _random = Random.secure();
}
