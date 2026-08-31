import '../../core/services/accounting_production_integrity_service.dart';
import '../../core/services/app_logging_service.dart';
import '../../core/services/inventory_traceability_service.dart';
import '../../core/storage/sqlite/sqlite_migration_manager.dart';
import '../../core/storage/sqlite/ventio_drift_database.dart';
import '../../data/app_store.dart';

enum Phase10HealthLevel { healthy, warning, critical }

class Phase10HealthCheck {
  const Phase10HealthCheck({
    required this.id,
    required this.title,
    required this.level,
    required this.message,
    this.details = const <String, dynamic>{},
  });

  final String id;
  final String title;
  final Phase10HealthLevel level;
  final String message;
  final Map<String, dynamic> details;
}

class Phase10HealthReport {
  const Phase10HealthReport({
    required this.generatedAt,
    required this.checks,
  });

  final DateTime generatedAt;
  final List<Phase10HealthCheck> checks;

  int get criticalCount =>
      checks.where((item) => item.level == Phase10HealthLevel.critical).length;
  int get warningCount =>
      checks.where((item) => item.level == Phase10HealthLevel.warning).length;
  bool get productionHealthy => criticalCount == 0;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'generatedAt': generatedAt.toIso8601String(),
        'productionHealthy': productionHealthy,
        'criticalCount': criticalCount,
        'warningCount': warningCount,
        'checks': <Map<String, dynamic>>[
          for (final check in checks)
            <String, dynamic>{
              'id': check.id,
              'title': check.title,
              'level': check.level.name,
              'message': check.message,
              'details': check.details,
            },
        ],
      };
}

/// Phase 10 read-only production health gate.
///
/// This deliberately composes the authoritative integrity auditors introduced
/// by earlier phases instead of creating a second source of truth. It never
/// repairs business data. Critical findings must be resolved through the
/// original workflow or a verified backup restore.
class Phase10HealthService {
  const Phase10HealthService(this.store);

  final AppStore store;

  Future<Phase10HealthReport> run({bool deep = true}) async {
    final checks = <Phase10HealthCheck>[];
    final db = SqliteMigrationManager.database;
    if (db == null) {
      checks.add(const Phase10HealthCheck(
        id: 'phase10_sqlite_unavailable',
        title: 'SQLite database',
        level: Phase10HealthLevel.critical,
        message: 'The authoritative SQLite database is not initialized.',
      ));
      return Phase10HealthReport(
        generatedAt: DateTime.now().toUtc(),
        checks: List<Phase10HealthCheck>.unmodifiable(checks),
      );
    }

    await _checkSqlite(db, checks, deep: deep);
    await _guardedCheck(
      checks,
      id: 'phase10_audit_chain',
      title: 'Append-only audit chain',
      run: () => _checkAudit(checks),
    );
    await _guardedCheck(
      checks,
      id: 'phase10_business_data',
      title: 'Business data references',
      run: () => _checkBusinessData(checks),
    );
    await _guardedCheck(
      checks,
      id: 'phase10_inventory_traceability',
      title: 'Inventory / batch traceability',
      run: () => _checkInventory(db, checks),
    );
    await _guardedCheck(
      checks,
      id: 'phase10_accounting_integrity',
      title: 'Accounting production integrity',
      run: () => _checkAccounting(db, checks),
    );
    _checkRecoveryIdentity(checks);

    return Phase10HealthReport(
      generatedAt: DateTime.now().toUtc(),
      checks: List<Phase10HealthCheck>.unmodifiable(checks),
    );
  }

  Future<void> _guardedCheck(
    List<Phase10HealthCheck> checks, {
    required String id,
    required String title,
    required Future<void> Function() run,
  }) async {
    try {
      await run();
    } catch (error) {
      checks.removeWhere((item) => item.id == id);
      checks.add(Phase10HealthCheck(
        id: id,
        title: title,
        level: Phase10HealthLevel.critical,
        message: '$title could not complete: $error',
      ));
    }
  }

  Future<void> _checkSqlite(
    VentioDriftDatabase db,
    List<Phase10HealthCheck> checks, {
    required bool deep,
  }) async {
    try {
      final pragma = deep ? 'integrity_check' : 'quick_check';
      final rows = await db.customSelect('PRAGMA $pragma;').get();
      final messages = rows
          .expand((row) => row.data.values)
          .map((value) => value?.toString() ?? '')
          .where((value) => value.trim().isNotEmpty)
          .toList(growable: false);
      final ok = messages.isNotEmpty &&
          messages.every((value) => value.trim().toLowerCase() == 'ok');
      checks.add(Phase10HealthCheck(
        id: 'phase10_sqlite_integrity',
        title: 'SQLite integrity',
        level: ok ? Phase10HealthLevel.healthy : Phase10HealthLevel.critical,
        message: ok
            ? 'SQLite $pragma passed.'
            : 'SQLite $pragma reported a database integrity problem.',
        details: <String, dynamic>{'pragma': pragma, 'result': messages},
      ));
    } catch (error) {
      checks.add(Phase10HealthCheck(
        id: 'phase10_sqlite_integrity',
        title: 'SQLite integrity',
        level: Phase10HealthLevel.critical,
        message: 'SQLite integrity check failed to run: $error',
      ));
    }

    try {
      final rows = await db.customSelect('PRAGMA foreign_key_check;').get();
      checks.add(Phase10HealthCheck(
        id: 'phase10_foreign_keys',
        title: 'Foreign-key integrity',
        level: rows.isEmpty
            ? Phase10HealthLevel.healthy
            : Phase10HealthLevel.critical,
        message: rows.isEmpty
            ? 'No SQLite foreign-key violations detected.'
            : '${rows.length} SQLite foreign-key violation(s) detected.',
        details: <String, dynamic>{
          'violationCount': rows.length,
          if (rows.isNotEmpty)
            'sample': rows.take(20).map((row) => row.data).toList(),
        },
      ));
    } catch (error) {
      checks.add(Phase10HealthCheck(
        id: 'phase10_foreign_keys',
        title: 'Foreign-key integrity',
        level: Phase10HealthLevel.critical,
        message: 'Foreign-key integrity check failed to run: $error',
      ));
    }

    try {
      Future<String> scalarPragma(String name) async {
        final rows = await db.customSelect('PRAGMA $name;').get();
        if (rows.isEmpty || rows.first.data.values.isEmpty) return '';
        return rows.first.data.values.first?.toString() ?? '';
      }

      final journalMode = (await scalarPragma('journal_mode')).toLowerCase();
      final synchronous = await scalarPragma('synchronous');
      final foreignKeys = await scalarPragma('foreign_keys');
      final safeJournal = journalMode == 'wal';
      final fullSync = synchronous == '2' || synchronous == '3' ||
          synchronous.toLowerCase() == 'full' ||
          synchronous.toLowerCase() == 'extra';
      final fkEnabled = foreignKeys == '1' || foreignKeys.toLowerCase() == 'on';
      final healthy = safeJournal && fullSync && fkEnabled;
      checks.add(Phase10HealthCheck(
        id: 'phase10_sqlite_durability',
        title: 'SQLite durability policy',
        level: healthy
            ? Phase10HealthLevel.healthy
            : Phase10HealthLevel.warning,
        message: healthy
            ? 'SQLite durability settings match the production policy.'
            : 'SQLite durability settings differ from the production policy.',
        details: <String, dynamic>{
          'journalMode': journalMode,
          'synchronous': synchronous,
          'foreignKeys': foreignKeys,
        },
      ));
    } catch (error) {
      checks.add(Phase10HealthCheck(
        id: 'phase10_sqlite_durability',
        title: 'SQLite durability policy',
        level: Phase10HealthLevel.warning,
        message: 'Could not read SQLite durability settings: $error',
      ));
    }
  }

  Future<void> _checkAudit(List<Phase10HealthCheck> checks) async {
    final result = await AuditLogger.verifyIntegrity();
    checks.add(Phase10HealthCheck(
      id: 'phase10_audit_chain',
      title: 'Append-only audit chain',
      level: result.ok
          ? Phase10HealthLevel.healthy
          : Phase10HealthLevel.critical,
      message: result.ok
          ? 'Audit hash chain verified (${result.checkedRows} rows).'
          : 'Audit hash chain failed at ${result.firstInvalidId}.',
      details: <String, dynamic>{
        'checkedRows': result.checkedRows,
        'firstInvalidId': result.firstInvalidId,
        'resultMessage': result.message,
      },
    ));
  }

  Future<void> _checkBusinessData(List<Phase10HealthCheck> checks) async {
    final result = await store.verifyLocalBusinessDataIntegrity();
    checks.add(Phase10HealthCheck(
      id: 'phase10_business_data',
      title: 'Business data references',
      // This legacy/business-reference scan is intentionally advisory.
      // Authoritative SQLite FK, accounting and Unified Batch auditors above
      // carry the critical production gate; this broader scan can flag valid
      // non-stock document shapes and therefore must not block recovery.
      level: result.ok
          ? Phase10HealthLevel.healthy
          : Phase10HealthLevel.warning,
      message: result.ok
          ? 'Business data reference integrity passed.'
          : result.message,
      details: <String, dynamic>{'problemCount': result.problemCount},
    ));
  }

  Future<void> _checkInventory(
    VentioDriftDatabase db,
    List<Phase10HealthCheck> checks,
  ) async {
    final storeId = store.appIdentity.storeId.trim();
    if (storeId.isEmpty) {
      checks.add(const Phase10HealthCheck(
        id: 'phase10_inventory_traceability',
        title: 'Inventory traceability',
        level: Phase10HealthLevel.critical,
        message: 'Store identity is missing; inventory integrity cannot be scoped.',
      ));
      return;
    }
    final result = await InventoryTraceabilityService(db).verifyIntegrity(
      storeId: storeId,
    );
    final healthy = result['healthy'] == true;
    final issueCount = (result['issueCount'] as num? ?? 0).toInt();
    checks.add(Phase10HealthCheck(
      id: 'phase10_inventory_traceability',
      title: 'Inventory / batch traceability',
      level: healthy
          ? Phase10HealthLevel.healthy
          : Phase10HealthLevel.critical,
      message: healthy
          ? 'Warehouse, batch, transfer and manufacturing traceability passed.'
          : '$issueCount inventory traceability issue(s) detected.',
      details: result,
    ));
  }

  Future<void> _checkAccounting(
    VentioDriftDatabase db,
    List<Phase10HealthCheck> checks,
  ) async {
    final result = await AccountingProductionIntegrityService(db).audit();
    final level = result.criticalCount > 0
        ? Phase10HealthLevel.critical
        : result.warningCount > 0
            ? Phase10HealthLevel.warning
            : Phase10HealthLevel.healthy;
    checks.add(Phase10HealthCheck(
      id: 'phase10_accounting_integrity',
      title: 'Accounting production integrity',
      level: level,
      message: result.criticalCount > 0
          ? '${result.criticalCount} critical accounting integrity issue(s) detected.'
          : result.warningCount > 0
              ? '${result.warningCount} accounting warning(s) detected.'
              : 'Accounting journals, control accounts, cash and inventory valuation reconcile.',
      details: <String, dynamic>{
        'criticalCount': result.criticalCount,
        'warningCount': result.warningCount,
        'inventoryGlBalance': result.inventoryGlBalance,
        'inventoryValuation': result.inventoryValuation,
        'issues': <Map<String, dynamic>>[
          for (final issue in result.issues.take(100))
            <String, dynamic>{
              'code': issue.code,
              'severity': issue.severity.name,
              'message': issue.message,
              'entityType': issue.entityType,
              'entityId': issue.entityId,
              'difference': issue.difference,
            },
        ],
      },
    ));
  }

  void _checkRecoveryIdentity(List<Phase10HealthCheck> checks) {
    if (store.appIdentity.isClient) {
      checks.add(const Phase10HealthCheck(
        id: 'phase10_recovery_identity',
        title: 'Disaster-recovery identity',
        level: Phase10HealthLevel.healthy,
        message: 'Recovery checkpoints are managed by the Host device.',
      ));
      return;
    }
    final recoveryKey = store.appIdentity.recoveryKey.trim();
    final storeId = store.appIdentity.storeId.trim();
    final healthy = recoveryKey.length >= 8 && storeId.isNotEmpty;
    checks.add(Phase10HealthCheck(
      id: 'phase10_recovery_identity',
      title: 'Disaster-recovery identity',
      level: healthy
          ? Phase10HealthLevel.healthy
          : Phase10HealthLevel.critical,
      message: healthy
          ? 'Store identity and recovery key are available.'
          : 'Store identity or recovery key is missing; encrypted disaster recovery is not ready.',
      details: <String, dynamic>{
        'storeIdPresent': storeId.isNotEmpty,
        'recoveryKeyPresent': recoveryKey.length >= 8,
      },
    ));
  }
}
