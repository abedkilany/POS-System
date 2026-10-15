import 'dart:math';

import 'package:drift/drift.dart';

import '../../models/cash_ledger_transaction.dart';
import '../../models/journal_entry.dart';
import '../../models/payment_allocation.dart';
import '../../models/payment_voucher.dart';
import '../../models/receipt_voucher.dart';
import '../storage/sqlite/ventio_drift_database.dart';
import 'accounting_service.dart';
import 'cash_ledger_service.dart';
import 'posted_document_edit_framework.dart';
part 'payment_voucher_service_methods_01.dart';
part 'payment_voucher_service_methods_02.dart';
part 'payment_voucher_service_methods_03.dart';
part 'payment_voucher_service_methods_04.dart';
part 'payment_voucher_service_methods_05.dart';
part 'payment_voucher_service_methods_06.dart';
part 'payment_voucher_service_methods_07.dart';
part 'payment_voucher_service_methods_08.dart';

/// Phase 2 authoritative write/read service for independent receipt/payment
/// vouchers and their allocations.
///
/// Important phase boundary:
/// - New vouchers created through this service are authoritative events.
/// - Allocations update Sale/Purchase paid_amount only as a compatibility cache.
/// - Existing Sales/Purchases UI paths are NOT rerouted here until Phase 3.
/// - Phase 8 registers voucher/accounting mutations with unified sync, snapshot, and backup flows.
class PaymentVoucherService {
  PaymentVoucherService(this._db) : _cashLedger = CashLedgerService(_db);

  final VentioDriftDatabase _db;
  final CashLedgerService _cashLedger;
  static final Random _random = Random.secure();
  static const double _epsilon = 0.000001;
}

class _AllocationTarget {
  const _AllocationTarget({
    required this.id,
    required this.referenceNumber,
    required this.partyId,
    required this.partyName,
    required this.currency,
    required this.total,
    required this.paid,
    required this.status,
  });

  final String id, referenceNumber, partyId, partyName, currency, status;
  final double total, paid;
  double get balanceDue => max(0, total - paid).toDouble();
  bool get isClosedDocument {
    final value = status.trim().toLowerCase();
    return value == 'cancelled' || value == 'returned' || value == 'void';
  }
}
