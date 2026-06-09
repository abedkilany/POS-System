import 'dart:convert';

import '../../core/services/local_database_service.dart';
import '../../core/services/maintenance_storage_info.dart';
import '../../core/storage/sqlite/sqlite_migration_manager.dart';
import '../../data/app_store.dart';
import 'maintenance_models.dart';

class MaintenanceService {
  const MaintenanceService(this.store);

  final AppStore store;

  Future<MaintenanceSummary> runHealthCheck({bool deep = false}) async {
    final storage = await getMaintenanceStorageInfo();
    final sqliteCounts = await _sqliteTableCounts();
    final migrationMeta = await _readMigrationMeta();
    final counts = <String, int>{
      'products': sqliteCounts['products'] ?? store.products.length,
      'customers': sqliteCounts['customers'] ?? store.customers.length,
      'suppliers': sqliteCounts['suppliers'] ?? store.suppliers.length,
      'sales': sqliteCounts['sales'] ?? store.sales.length,
      'purchases': sqliteCounts['purchases'] ?? store.purchases.length,
      'expenses': sqliteCounts['expenses'] ?? store.expenses.length,
      'stockMovements': sqliteCounts['stockMovements'] ?? store.stockMovements.length,
      'accountTransactions': sqliteCounts['accountTransactions'] ?? store.accountTransactions.length,
      'users': sqliteCounts['users'] ?? store.users.length,
      'roles': sqliteCounts['roles'] ?? store.roles.length,
      'localDatabaseKeys': sqliteCounts['localDatabaseKeys'] ?? LocalDatabaseService.keys().length,
      'pendingSyncChanges': sqliteCounts['pendingSyncChanges'] ?? store.pendingSyncChanges.length,
      'pendingSyncQueue': sqliteCounts['pendingSyncQueue'] ?? store.pendingSyncQueue.length,
      'dataConflicts': sqliteCounts['dataConflicts'] ?? store.dataConflicts.length,
    };

    final issues = <MaintenanceIssue>[
      _databaseLocationIssue(storage, migrationMeta),
      _migrationIssue(migrationMeta),
      _localKeysIssue(counts['localDatabaseKeys'] ?? 0),
      if (deep) ...[
        ..._duplicateIssues(),
        ..._stockIssues(),
        ..._salesIssues(),
        ..._purchaseIssues(),
      ] else
        const MaintenanceIssue(
          id: 'deep_diagnostics_skipped',
          title: 'Deep diagnostics',
          severity: MaintenanceSeverity.info,
          message: 'Deep data scans are skipped during quick refresh to keep Maintenance fast. Use Run deep diagnostics when needed.',
        ),
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
        'legacyHiveFilePath': storage.legacyHiveFilePath,
        'legacyHiveExists': storage.legacyHiveExists,
        'legacyHiveSizeBytes': storage.legacyHiveSizeBytes,
        'discoveredSqliteFiles': storage.discoveredSqliteFiles,
      },
      migrationMeta: migrationMeta,
      counts: counts,
      issues: issues,
    );
  }

  String buildDiagnosticReport(MaintenanceSummary summary) {
    return const JsonEncoder.withIndent('  ').convert(summary.toJson());
  }

  Future<MaintenanceRepairResult> runRepair(MaintenanceRepairAction action) async {
    switch (action) {
      case MaintenanceRepairAction.refreshOnly:
        await runHealthCheck(deep: false);
        return const MaintenanceRepairResult(
          title: 'Database re-check completed',
          message: 'No data was changed. The health check was refreshed only.',
        );
      case MaintenanceRepairAction.repairMissingCloudQueue:
        final repaired = await store.repairMissingHostCloudQueueForPendingChanges();
        return MaintenanceRepairResult(
          title: 'Cloud sync queue repair completed',
          message: repaired == 0 ? 'No missing Host → Cloud queue rows were found.' : '$repaired missing Host → Cloud queue rows were recreated.',
          changedRecords: repaired,
        );
    }
  }

  MaintenanceIssue _databaseLocationIssue(MaintenanceStorageInfo storage, Map<String, String> migrationMeta) {
    final typedTablesMigrated = migrationMeta['sqlite_phase3_typed_tables_migrated'] == 'true';
    return MaintenanceIssue(
      id: 'database_location',
      title: 'SQLite database location',
      severity: storage.exists ? MaintenanceSeverity.ok : MaintenanceSeverity.warning,
      message: storage.exists
          ? 'SQLite database file found in private Ventio storage. Legacy Hive is ${storage.legacyHiveExists ? 'still present for fallback/migration audit.' : 'not present, which is OK after migration.'}'
          : 'SQLite database file is not visible yet. Open the app once, then run maintenance again.',
      details: {
        'engine': storage.databaseEngine,
        'directoryPath': storage.databaseDirectoryPath,
        'filePath': storage.databaseFilePath,
        'sizeBytes': storage.databaseSizeBytes,
        'legacyHiveFilePath': storage.legacyHiveFilePath,
        'legacyHiveExists': storage.legacyHiveExists,
        'legacyHiveSizeBytes': storage.legacyHiveSizeBytes,
        'discoveredSqliteFiles': storage.discoveredSqliteFiles,
        'hiveMissingIsOk': typedTablesMigrated && !storage.legacyHiveExists,
      },
    );
  }

  MaintenanceIssue _migrationIssue(Map<String, String> migrationMeta) {
    final syncMigrated = migrationMeta['sqlite_phase2_sync_migrated'] == 'true';
    final businessMigrated = migrationMeta['sqlite_phase3_business_migrated'] == 'true';
    final typedTablesMigrated = migrationMeta['sqlite_phase3_typed_tables_migrated'] == 'true';
    final ok = syncMigrated && businessMigrated && typedTablesMigrated;
    return MaintenanceIssue(
      id: 'sqlite_migration_status',
      title: 'SQLite migration status',
      severity: ok ? MaintenanceSeverity.ok : MaintenanceSeverity.warning,
      message: ok
          ? 'SQLite migration is complete: sync data, business data, and typed entity tables are active.'
          : 'SQLite migration metadata is incomplete. Keep Hive available until migration finishes.',
      details: {
        'sqlite_phase2_sync_migrated': syncMigrated,
        'sqlite_phase3_business_migrated': businessMigrated,
        'sqlite_phase3_typed_tables_migrated': typedTablesMigrated,
        'migrationMeta': migrationMeta,
      },
    );
  }

  MaintenanceIssue _localKeysIssue(int localKeys) {
    return MaintenanceIssue(
      id: 'local_database_keys',
      title: 'Local database keys',
      severity: localKeys > 0 ? MaintenanceSeverity.ok : MaintenanceSeverity.warning,
      message: '$localKeys persisted keys found.',
    );
  }

  List<MaintenanceIssue> _duplicateIssues() {
    final duplicateProductNames = _countDuplicates(store.products.map((item) => item.name.trim().toLowerCase()).where((item) => item.isNotEmpty));
    final duplicateCustomerNames = _countDuplicates(store.customers.map((item) => item.name.trim().toLowerCase()).where((item) => item.isNotEmpty));
    final duplicateSupplierNames = _countDuplicates(store.suppliers.map((item) => item.name.trim().toLowerCase()).where((item) => item.isNotEmpty));
    return [
      MaintenanceIssue(
        id: 'duplicate_product_names',
        title: 'Duplicate product names',
        severity: duplicateProductNames == 0 ? MaintenanceSeverity.ok : MaintenanceSeverity.warning,
        message: duplicateProductNames == 0 ? 'No duplicate product names.' : '$duplicateProductNames duplicate product names found.',
      ),
      MaintenanceIssue(
        id: 'duplicate_customer_names',
        title: 'Duplicate customer names',
        severity: duplicateCustomerNames == 0 ? MaintenanceSeverity.ok : MaintenanceSeverity.warning,
        message: duplicateCustomerNames == 0 ? 'No duplicate customer names.' : '$duplicateCustomerNames duplicate customer names found.',
      ),
      MaintenanceIssue(
        id: 'duplicate_supplier_names',
        title: 'Duplicate supplier names',
        severity: duplicateSupplierNames == 0 ? MaintenanceSeverity.ok : MaintenanceSeverity.warning,
        message: duplicateSupplierNames == 0 ? 'No duplicate supplier names.' : '$duplicateSupplierNames duplicate supplier names found.',
      ),
    ];
  }

  List<MaintenanceIssue> _stockIssues() {
    final negativeStockProducts = store.products.where((item) => item.trackStock && item.stock < 0).length;
    final zeroCostProducts = store.products.where((item) => item.isActive && item.cost <= 0).length;
    final zeroPriceProducts = store.products.where((item) => item.isActive && item.price <= 0).length;
    return [
      MaintenanceIssue(
        id: 'negative_stock',
        title: 'Negative stock',
        severity: negativeStockProducts == 0 ? MaintenanceSeverity.ok : MaintenanceSeverity.warning,
        message: negativeStockProducts == 0 ? 'No negative stock tracked products.' : '$negativeStockProducts products have negative stock.',
      ),
      MaintenanceIssue(
        id: 'zero_cost_products',
        title: 'Products with zero cost',
        severity: zeroCostProducts == 0 ? MaintenanceSeverity.ok : MaintenanceSeverity.info,
        message: zeroCostProducts == 0 ? 'No active products with zero cost.' : '$zeroCostProducts active products have zero cost.',
      ),
      MaintenanceIssue(
        id: 'zero_price_products',
        title: 'Products with zero price',
        severity: zeroPriceProducts == 0 ? MaintenanceSeverity.ok : MaintenanceSeverity.warning,
        message: zeroPriceProducts == 0 ? 'No active products with zero price.' : '$zeroPriceProducts active products have zero price.',
      ),
    ];
  }

  List<MaintenanceIssue> _salesIssues() {
    final emptySales = store.sales.where((item) => !item.isDeleted && item.items.isEmpty).length;
    final overpaidSales = store.sales.where((item) => !item.isDeleted && item.paidAmount > item.invoiceTotal + 0.01).length;
    final productIds = store.products.map((product) => product.id).toSet();
    final missingProductRefs = store.sales
        .where((sale) => !sale.isDeleted)
        .expand((sale) => sale.items)
        .where((item) => item.productId.isNotEmpty && !productIds.contains(item.productId))
        .length;
    return [
      MaintenanceIssue(
        id: 'empty_sales',
        title: 'Sales without items',
        severity: emptySales == 0 ? MaintenanceSeverity.ok : MaintenanceSeverity.warning,
        message: emptySales == 0 ? 'No sales without items.' : '$emptySales sales do not contain any items.',
      ),
      MaintenanceIssue(
        id: 'overpaid_sales',
        title: 'Overpaid sales',
        severity: overpaidSales == 0 ? MaintenanceSeverity.ok : MaintenanceSeverity.info,
        message: overpaidSales == 0 ? 'No overpaid sales detected.' : '$overpaidSales sales have paid amount greater than invoice total.',
      ),
      MaintenanceIssue(
        id: 'sale_items_missing_products',
        title: 'Sale items with missing products',
        severity: missingProductRefs == 0 ? MaintenanceSeverity.ok : MaintenanceSeverity.warning,
        message: missingProductRefs == 0 ? 'No sale items reference missing products.' : '$missingProductRefs sale items reference products that are not in the active catalog.',
      ),
    ];
  }

  List<MaintenanceIssue> _purchaseIssues() {
    final emptyPurchases = store.purchases.where((item) => !item.isDeleted && item.items.isEmpty).length;
    return [
      MaintenanceIssue(
        id: 'empty_purchases',
        title: 'Purchases without items',
        severity: emptyPurchases == 0 ? MaintenanceSeverity.ok : MaintenanceSeverity.warning,
        message: emptyPurchases == 0 ? 'No purchases without items.' : '$emptyPurchases purchases do not contain any items.',
      ),
    ];
  }

  List<MaintenanceIssue> _syncIssues(Map<String, int> counts) {
    final pendingSync = (counts['pendingSyncChanges'] ?? store.pendingSyncChanges.length) + (counts['pendingSyncQueue'] ?? store.pendingSyncQueue.length);
    final conflicts = counts['dataConflicts'] ?? store.dataConflicts.length;
    return [
      MaintenanceIssue(
        id: 'data_conflicts',
        title: 'Data conflicts',
        severity: conflicts == 0 ? MaintenanceSeverity.ok : MaintenanceSeverity.warning,
        message: conflicts == 0 ? 'No detected conflicts.' : '$conflicts conflicts need review.',
      ),
      MaintenanceIssue(
        id: 'pending_sync_changes',
        title: 'Pending sync changes',
        severity: pendingSync == 0 ? MaintenanceSeverity.ok : MaintenanceSeverity.info,
        message: pendingSync == 0 ? 'No pending sync changes.' : '$pendingSync changes are waiting for sync.',
        repairAction: MaintenanceRepairAction.repairMissingCloudQueue,
      ),
    ];
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
    };

    final counts = <String, int>{};
    for (final entry in tables.entries) {
      counts[entry.key] = await _countSqliteRows(entry.value);
    }
    return counts;
  }

  Future<int> _countSqliteRows(String tableName) async {
    final db = SqliteMigrationManager.database;
    if (db == null) return 0;
    final row = await db.customSelect(
      'SELECT COUNT(*) AS row_count FROM $tableName'
    ).getSingleOrNull();
    return row?.read<int>('row_count') ?? 0;
  }

  Future<Map<String, String>> _readMigrationMeta() async {
    final db = SqliteMigrationManager.database;
    if (db == null) return const <String, String>{};
    final rows = await db.customSelect(
      'SELECT key, value FROM migration_meta'
    ).get();
    return <String, String>{
      for (final row in rows) row.read<String>('key'): row.read<String>('value'),
    };
  }

  int _countDuplicates(Iterable<String> values) {
    final counts = <String, int>{};
    for (final value in values) {
      counts[value] = (counts[value] ?? 0) + 1;
    }
    return counts.values.where((count) => count > 1).length;
  }
}
