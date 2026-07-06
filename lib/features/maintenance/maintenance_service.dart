import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/services/local_database_service.dart';
import '../../core/services/google_drive_backup_service.dart';
import '../../core/services/local_auto_backup_service.dart';
import '../../core/services/maintenance_storage_info.dart';
import '../../core/repositories/business_repositories.dart';
import '../../core/services/startup_timing_service.dart';
import '../../core/storage/sqlite/sqlite_migration_manager.dart';
import '../../data/app_store.dart';
import 'maintenance_models.dart';

class MaintenanceService {
  const MaintenanceService(this.store);

  final AppStore store;

  Future<MaintenanceSummary> runHealthCheck({bool deep = false}) async {
    final storage = await getMaintenanceStorageInfo();
    final sqliteCounts = await _sqliteTableCounts();
    final backupSnapshot = await _backupSnapshot();
    final counts = <String, int>{
      'products': sqliteCounts['products'] ?? 0,
      'customers': sqliteCounts['customers'] ?? 0,
      'suppliers': sqliteCounts['suppliers'] ?? 0,
      'sales': sqliteCounts['sales'] ?? 0,
      'purchases': sqliteCounts['purchases'] ?? 0,
      'expenses': sqliteCounts['expenses'] ?? 0,
      'stockMovements': sqliteCounts['stockMovements'] ?? 0,
      'accountTransactions': sqliteCounts['accountTransactions'] ?? 0,
      'users': sqliteCounts['users'] ?? await UserRepository.countAll(),
      'roles': sqliteCounts['roles'] ?? await RoleRepository.countAll(),
      'localDatabaseKeys': sqliteCounts['localDatabaseKeys'] ??
          LocalDatabaseService.keys().length,
      'pendingSyncChanges':
          sqliteCounts['pendingSyncChanges'] ?? store.pendingSyncChanges.length,
      'pendingSyncQueue':
          sqliteCounts['pendingSyncQueue'] ?? store.pendingSyncCount,
      'dataConflicts': sqliteCounts['dataConflicts'] ?? 0,
      'appLogs': sqliteCounts['appLogs'] ?? 0,
      'auditLogs': sqliteCounts['auditLogs'] ?? 0,
      ...backupSnapshot.counts,
    };

    final deepIssues = deep
        ? await Future.wait([
            _duplicateIssues(),
            _stockIssues(),
            _salesIssues(),
            _purchaseIssues(),
          ])
        : const <List<MaintenanceIssue>>[];

    final issues = <MaintenanceIssue>[
      _databaseLocationIssue(storage),
      _localKeysIssue(counts['localDatabaseKeys'] ?? 0),
      ...backupSnapshot.issues,
      if (deep) ...deepIssues.expand((items) => items),
      ..._syncIssues(counts),
    ];

    return MaintenanceSummary(
      generatedAt: DateTime.now(),
      platformLabel: storage.platformLabel,
      databaseDirectoryPath: storage.databaseDirectoryPath,
      databaseFilePath: storage.databaseFilePath,
      databaseExists: storage.exists,
      databaseSizeBytes: storage.databaseSizeBytes,
      databaseEngine: storage.databaseEngine,
      databaseDetails: <String, dynamic>{
        'discoveredSqliteFiles': storage.discoveredSqliteFiles,
      },
      counts: counts,
      issues: issues,
    );
  }

  String buildDiagnosticReport(MaintenanceSummary summary) {
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'maintenance': summary.toJson(),
      'startupTiming': StartupTimingService.snapshotJson(),
    });
  }

  Future<MaintenanceRepairResult> runRepair(
      MaintenanceRepairAction action) async {
    switch (action) {
      case MaintenanceRepairAction.refreshOnly:
        await runHealthCheck(deep: false);
        return const MaintenanceRepairResult(
          title: 'Database re-check completed',
          message: 'No data was changed. The health check was refreshed only.',
        );
      case MaintenanceRepairAction.repairMissingCloudQueue:
        final repaired = await store.syncState
            .repairMissingHostCloudQueueForPendingChanges(store);
        return MaintenanceRepairResult(
          title: 'Cloud sync queue repair completed',
          message: repaired == 0
              ? 'No missing Host → Cloud queue rows were found.'
              : '$repaired missing Host → Cloud queue rows were recreated.',
          changedRecords: repaired,
        );
    }
  }

  MaintenanceIssue _databaseLocationIssue(MaintenanceStorageInfo storage) {
    return MaintenanceIssue(
      id: 'database_location',
      title: 'SQLite database location',
      severity:
          storage.exists ? MaintenanceSeverity.ok : MaintenanceSeverity.warning,
      message: storage.exists
          ? 'SQLite database file found in private Ventio storage.'
          : 'SQLite database file is not visible yet. Open the app once, then run maintenance again.',
      details: {
        'engine': storage.databaseEngine,
        'directoryPath': storage.databaseDirectoryPath,
        'filePath': storage.databaseFilePath,
        'sizeBytes': storage.databaseSizeBytes,
        'discoveredSqliteFiles': storage.discoveredSqliteFiles,
      },
    );
  }

  MaintenanceIssue _localKeysIssue(int localKeys) {
    final isExpectedEmpty = kIsWeb || store.appIdentity.isClient;
    return MaintenanceIssue(
      id: 'local_database_keys',
      title: 'Local database keys',
      severity: localKeys > 0 || isExpectedEmpty
          ? MaintenanceSeverity.ok
          : MaintenanceSeverity.warning,
      message: '$localKeys persisted keys found.',
    );
  }

  Future<List<MaintenanceIssue>> _duplicateIssues() async {
    final duplicateProductNames = await _countSqliteDuplicates(
      'products',
      "deleted_at = '' AND trim(name) <> ''",
      'name',
    );
    final duplicateCustomerNames = await _countSqliteDuplicates(
      'customers',
      "deleted_at = '' AND trim(name) <> ''",
      'name',
    );
    final duplicateSupplierNames = await _countSqliteDuplicates(
      'suppliers',
      "deleted_at = '' AND trim(name) <> ''",
      'name',
    );
    return [
      MaintenanceIssue(
        id: 'duplicate_product_names',
        title: 'Duplicate product names',
        severity: duplicateProductNames == 0
            ? MaintenanceSeverity.ok
            : MaintenanceSeverity.warning,
        message: duplicateProductNames == 0
            ? 'No duplicate product names.'
            : '$duplicateProductNames duplicate product names found.',
      ),
      MaintenanceIssue(
        id: 'duplicate_customer_names',
        title: 'Duplicate customer names',
        severity: duplicateCustomerNames == 0
            ? MaintenanceSeverity.ok
            : MaintenanceSeverity.warning,
        message: duplicateCustomerNames == 0
            ? 'No duplicate customer names.'
            : '$duplicateCustomerNames duplicate customer names found.',
      ),
      MaintenanceIssue(
        id: 'duplicate_supplier_names',
        title: 'Duplicate supplier names',
        severity: duplicateSupplierNames == 0
            ? MaintenanceSeverity.ok
            : MaintenanceSeverity.warning,
        message: duplicateSupplierNames == 0
            ? 'No duplicate supplier names.'
            : '$duplicateSupplierNames duplicate supplier names found.',
      ),
    ];
  }

  Future<List<MaintenanceIssue>> _stockIssues() async {
    final negativeStockProducts = await _countSqliteRows(
      "products",
      "deleted_at = '' AND track_stock = 1 AND stock < 0",
    );
    final zeroCostProducts = await _countSqliteRows(
      "products",
      "deleted_at = '' AND is_active = 1 AND cost <= 0",
    );
    final zeroPriceProducts = await _countSqliteRows(
      "products",
      "deleted_at = '' AND is_active = 1 AND price <= 0",
    );
    return [
      MaintenanceIssue(
        id: 'negative_stock',
        title: 'Negative stock',
        severity: negativeStockProducts == 0
            ? MaintenanceSeverity.ok
            : MaintenanceSeverity.warning,
        message: negativeStockProducts == 0
            ? 'No negative stock tracked products.'
            : '$negativeStockProducts products have negative stock.',
      ),
      MaintenanceIssue(
        id: 'zero_cost_products',
        title: 'Products with zero cost',
        severity: zeroCostProducts == 0
            ? MaintenanceSeverity.ok
            : MaintenanceSeverity.info,
        message: zeroCostProducts == 0
            ? 'No active products with zero cost.'
            : '$zeroCostProducts active products have zero cost.',
      ),
      MaintenanceIssue(
        id: 'zero_price_products',
        title: 'Products with zero price',
        severity: zeroPriceProducts == 0
            ? MaintenanceSeverity.ok
            : MaintenanceSeverity.warning,
        message: zeroPriceProducts == 0
            ? 'No active products with zero price.'
            : '$zeroPriceProducts active products have zero price.',
      ),
    ];
  }

  Future<List<MaintenanceIssue>> _salesIssues() async {
    final emptySales = await _countSqliteRows(
      "sales",
      "deleted_at = '' AND NOT EXISTS (SELECT 1 FROM sale_items si WHERE si.sale_id = sales.id)",
    );
    final overpaidSales = await _countSqliteRows(
      "sales",
      "deleted_at = '' AND lower(status) NOT IN ('cancelled', 'returned') AND paid_amount > transaction_amount + 0.01",
    );
    final missingProductRefs = await _countSqliteRows(
      "sale_items",
      "trim(product_id) <> '' AND NOT EXISTS (SELECT 1 FROM products p WHERE p.id = sale_items.product_id AND p.deleted_at = '')",
    );
    return [
      MaintenanceIssue(
        id: 'empty_sales',
        title: 'Sales without items',
        severity: emptySales == 0
            ? MaintenanceSeverity.ok
            : MaintenanceSeverity.warning,
        message: emptySales == 0
            ? 'No sales without items.'
            : '$emptySales sales do not contain any items.',
      ),
      MaintenanceIssue(
        id: 'overpaid_sales',
        title: 'Overpaid sales',
        severity: overpaidSales == 0
            ? MaintenanceSeverity.ok
            : MaintenanceSeverity.info,
        message: overpaidSales == 0
            ? 'No active overpaid sales detected.'
            : '$overpaidSales active sales have paid amount greater than invoice total.',
      ),
      MaintenanceIssue(
        id: 'sale_items_missing_products',
        title: 'Sale items with missing products',
        severity: missingProductRefs == 0
            ? MaintenanceSeverity.ok
            : MaintenanceSeverity.warning,
        message: missingProductRefs == 0
            ? 'No sale items reference missing products.'
            : '$missingProductRefs sale items reference products that are not in the active catalog.',
      ),
    ];
  }

  Future<List<MaintenanceIssue>> _purchaseIssues() async {
    final emptyPurchases = await _countSqliteRows(
      "purchases",
      "deleted_at = '' AND NOT EXISTS (SELECT 1 FROM purchase_items pi WHERE pi.purchase_id = purchases.id)",
    );
    return [
      MaintenanceIssue(
        id: 'empty_purchases',
        title: 'Purchases without items',
        severity: emptyPurchases == 0
            ? MaintenanceSeverity.ok
            : MaintenanceSeverity.warning,
        message: emptyPurchases == 0
            ? 'No purchases without items.'
            : '$emptyPurchases purchases do not contain any items.',
      ),
    ];
  }

  List<MaintenanceIssue> _syncIssues(Map<String, int> counts) {
    final pendingSync =
        (counts['pendingSyncChanges'] ?? store.pendingSyncChanges.length) +
        (counts['pendingSyncQueue'] ?? store.pendingSyncCount);
    final conflicts = counts['dataConflicts'] ?? 0;
    final canRepairCloudQueue = store.appIdentity.isHost &&
        store.appIdentity.isCloudEnabled &&
        pendingSync > 0;
    return [
      MaintenanceIssue(
        id: 'data_conflicts',
        title: 'Data conflicts',
        severity: conflicts == 0
            ? MaintenanceSeverity.ok
            : MaintenanceSeverity.warning,
        message: conflicts == 0
            ? 'No detected conflicts.'
            : '$conflicts conflicts need review.',
      ),
      MaintenanceIssue(
        id: 'pending_sync_changes',
        title: 'Pending sync changes',
        severity: pendingSync == 0
            ? MaintenanceSeverity.ok
            : MaintenanceSeverity.info,
        message: pendingSync == 0
            ? 'No pending sync changes.'
            : '$pendingSync changes are waiting for sync.',
        repairAction: canRepairCloudQueue
            ? MaintenanceRepairAction.repairMissingCloudQueue
            : null,
      ),
    ];
  }

  Future<_BackupSnapshot> _backupSnapshot() async {
    if (store.appIdentity.isClient) {
      return const _BackupSnapshot(
        counts: {
          'localBackupEnabled': 0,
          'localBackupHealthy': 0,
          'googleDriveConnected': 0,
          'googleDriveBackupEnabled': 0,
          'googleDriveBackupHealthy': 0,
        },
        issues: [
          MaintenanceIssue(
            id: 'local_backup_status',
            title: 'Local backup',
            severity: MaintenanceSeverity.ok,
            message: 'Backups are managed by the Host device.',
          ),
          MaintenanceIssue(
            id: 'google_drive_backup_status',
            title: 'Google Drive backup',
            severity: MaintenanceSeverity.ok,
            message: 'Backups are managed by the Host device.',
          ),
        ],
      );
    }

    final localSettings = await LocalAutoBackupService.loadSettings();
    final googleSettings = await GoogleDriveBackupService.loadSettings();
    final localLastSuccess = LocalAutoBackupService.lastSuccessAt();
    final googleLastSuccess = GoogleDriveBackupService.lastSuccessAt();
    final localHealthy =
        localSettings.enabled && _isRecentBackup(localLastSuccess);
    final googleHealthy = googleSettings.enabled &&
        googleSettings.isAuthorized &&
        _isRecentBackup(googleLastSuccess);

    return _BackupSnapshot(
      counts: {
        'localBackupEnabled': localSettings.enabled ? 1 : 0,
        'localBackupHealthy': localHealthy ? 1 : 0,
        'googleDriveConnected': googleSettings.isAuthorized ? 1 : 0,
        'googleDriveBackupEnabled': googleSettings.enabled ? 1 : 0,
        'googleDriveBackupHealthy': googleHealthy ? 1 : 0,
      },
      issues: [
        _localBackupIssue(localSettings.enabled, localLastSuccess),
        _googleDriveBackupIssue(googleSettings.enabled,
            googleSettings.isAuthorized, googleLastSuccess),
      ],
    );
  }

  MaintenanceIssue _localBackupIssue(bool enabled, DateTime? lastSuccessAt) {
    if (!enabled) {
      return const MaintenanceIssue(
        id: 'local_backup_status',
        title: 'Local backup',
        severity: MaintenanceSeverity.warning,
        message: 'Automatic local backup is disabled.',
      );
    }
    if (lastSuccessAt == null) {
      return const MaintenanceIssue(
        id: 'local_backup_status',
        title: 'Local backup',
        severity: MaintenanceSeverity.warning,
        message:
            'Automatic local backup is enabled, but no successful backup was recorded yet.',
      );
    }
    if (!_isRecentBackup(lastSuccessAt)) {
      return MaintenanceIssue(
        id: 'local_backup_status',
        title: 'Local backup',
        severity: MaintenanceSeverity.warning,
        message: 'Automatic local backup is older than the recommended window.',
        details: {'lastSuccessAt': lastSuccessAt.toIso8601String()},
      );
    }
    return MaintenanceIssue(
      id: 'local_backup_status',
      title: 'Local backup',
      severity: MaintenanceSeverity.ok,
      message: 'Automatic local backup is healthy.',
      details: {'lastSuccessAt': lastSuccessAt.toIso8601String()},
    );
  }

  MaintenanceIssue _googleDriveBackupIssue(
      bool enabled, bool connected, DateTime? lastSuccessAt) {
    if (!connected) {
      return const MaintenanceIssue(
        id: 'google_drive_backup_status',
        title: 'Google Drive backup',
        severity: MaintenanceSeverity.info,
        message: 'Google Drive backup is not connected.',
      );
    }
    if (!enabled) {
      return const MaintenanceIssue(
        id: 'google_drive_backup_status',
        title: 'Google Drive backup',
        severity: MaintenanceSeverity.info,
        message:
            'Google Drive backup is connected but automatic backup is disabled.',
      );
    }
    if (lastSuccessAt == null) {
      return const MaintenanceIssue(
        id: 'google_drive_backup_status',
        title: 'Google Drive backup',
        severity: MaintenanceSeverity.warning,
        message:
            'Google Drive backup is enabled, but no successful backup was recorded yet.',
      );
    }
    if (!_isRecentBackup(lastSuccessAt)) {
      return MaintenanceIssue(
        id: 'google_drive_backup_status',
        title: 'Google Drive backup',
        severity: MaintenanceSeverity.warning,
        message: 'Google Drive backup is older than the recommended window.',
        details: {'lastSuccessAt': lastSuccessAt.toIso8601String()},
      );
    }
    return MaintenanceIssue(
      id: 'google_drive_backup_status',
      title: 'Google Drive backup',
      severity: MaintenanceSeverity.ok,
      message: 'Google Drive backup is healthy.',
      details: {'lastSuccessAt': lastSuccessAt.toIso8601String()},
    );
  }

  bool _isRecentBackup(DateTime? lastSuccessAt) {
    if (lastSuccessAt == null) return false;
    return DateTime.now().difference(lastSuccessAt).inHours <= 48;
  }

  Future<Map<String, int>> _sqliteTableCounts() async {
    final db = SqliteMigrationManager.database;
    if (db == null) return const <String, int>{};

    const tables = <String, String>{
      'products': 'products',
      'customers': 'customers',
      'suppliers': 'suppliers',
      'sales': 'sales',
      'purchases': 'purchases',
      'expenses': 'expenses',
      'stockMovements': 'stock_movements',
      'accountTransactions': 'account_transactions',
      'users': 'app_users',
      'roles': 'user_roles',
      'pendingSyncChanges': 'pending_sync_changes',
      'pendingSyncQueue': 'sync_queue',
      'dataConflicts': 'sync_conflicts',
      'localDatabaseKeys': 'local_key_values',
      'appLogs': 'app_logs',
      'auditLogs': 'audit_logs',
    };

    final counts = <String, int>{};
    for (final entry in tables.entries) {
      counts[entry.key] = await _countSqliteRows(entry.value);
    }
    return counts;
  }

  Future<int> _countSqliteRows(
    String tableName, [
    String whereSql = '1=1',
  ]) async {
    final db = SqliteMigrationManager.database;
    if (db == null) return 0;
    final row = await db
        .customSelect('SELECT COUNT(*) AS row_count FROM $tableName WHERE $whereSql')
        .getSingleOrNull();
    return row?.read<int>('row_count') ?? 0;
  }

  Future<int> _countSqliteDuplicates(
    String tableName,
    String whereSql,
    String columnName,
  ) {
    final db = SqliteMigrationManager.database;
    if (db == null) return Future.value(0);
    final row = db.customSelect('''
      SELECT COUNT(*) AS row_count
      FROM (
        SELECT lower(trim($columnName)) AS value
        FROM $tableName
        WHERE $whereSql
        GROUP BY lower(trim($columnName))
        HAVING COUNT(*) > 1
      )
    ''').getSingleOrNull();
    return row.then((value) => value?.read<int>('row_count') ?? 0);
  }
}

class _BackupSnapshot {
  const _BackupSnapshot({
    required this.counts,
    required this.issues,
  });

  final Map<String, int> counts;
  final List<MaintenanceIssue> issues;
}
