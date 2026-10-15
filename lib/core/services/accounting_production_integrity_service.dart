import 'package:drift/drift.dart';

import '../storage/sqlite/ventio_drift_database.dart';
import 'accounting_service.dart';
part 'accounting_production_integrity_service_methods_01.dart';
part 'accounting_production_integrity_service_methods_02.dart';

enum AccountingIntegritySeverity { critical, warning }

class AccountingIntegrityIssue {
  const AccountingIntegrityIssue({
    required this.code,
    required this.severity,
    required this.message,
    this.entityType = '',
    this.entityId = '',
    this.difference = 0,
  });

  final String code;
  final AccountingIntegritySeverity severity;
  final String message;
  final String entityType;
  final String entityId;
  final double difference;
}

class AccountingProductionIntegrityReport {
  const AccountingProductionIntegrityReport({
    required this.generatedAt,
    required this.issues,
    required this.inventoryGlBalance,
    required this.inventoryValuation,
  });

  final DateTime generatedAt;
  final List<AccountingIntegrityIssue> issues;
  final double inventoryGlBalance;
  final double inventoryValuation;

  int get criticalCount => issues
      .where((issue) => issue.severity == AccountingIntegritySeverity.critical)
      .length;
  int get warningCount => issues
      .where((issue) => issue.severity == AccountingIntegritySeverity.warning)
      .length;
  bool get isProductionReady => criticalCount == 0;
}

/// Read-only accounting closure gate.
///
/// This service intentionally never repairs data. It verifies the invariants
/// that must remain true after the operational workflows have committed. A
/// production deployment can therefore run the audit repeatedly without
/// changing accounting, inventory, cash, or document state.
class AccountingProductionIntegrityService {
  AccountingProductionIntegrityService(this._db);

  final VentioDriftDatabase _db;

  static double _num(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0.0;

  static double _round(double value) => (value * 100).roundToDouble() / 100;
}
