import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pure db-first contract is documented and startup is db-first', () {
    final readme = File('README.md').readAsStringSync();
    final contract = File('PURE_DB_FIRST_CONTRACT.md').readAsStringSync();
    final appStore = File('lib/data/app_store.dart').readAsStringSync();
    final appStoreRecovery =
        File('lib/data/app_store_recovery.dart').readAsStringSync();
    final localDatabaseService =
        File('lib/core/services/local_database_service.dart')
            .readAsStringSync();
    final dashboardSnapshot =
        File('lib/features/dashboard/dashboard_snapshot_service.dart')
            .readAsStringSync();
    final reportsSnapshot =
        File('lib/features/reports/reports_snapshot_service.dart')
            .readAsStringSync();
    final accountingSnapshot =
        File('lib/features/accounting/accounting_snapshot_service.dart')
            .readAsStringSync();

    expect(readme, contains('Pure DB-First Contract'));
    expect(contract, contains('SQLite is the only source of truth'));
    expect(contract, contains('SharedPreferences'));
    expect(contract, contains('legacy JSON blobs'));
    expect(appStore, contains("details: 'db_first'"));
    expect(appStore, isNot(contains('_migrateBootstrapSharedPreferencesIfNeeded')));
    expect(appStore, isNot(contains('SharedPreferences.getInstance')));
    expect(appStore, isNot(contains('LocalDatabaseService.getBusinessEntityListJson(')));
    expect(appStore, isNot(contains('LocalDatabaseService.getBusinessEntityListJsonBatches(')));
    expect(appStoreRecovery, isNot(contains('LocalDatabaseService.getBusinessEntityListJson(')));
    expect(dashboardSnapshot, isNot(contains('getBusinessEntityListJson(')));
    expect(dashboardSnapshot, isNot(contains('_loadRawData')));
    expect(reportsSnapshot, isNot(contains('getBusinessEntityListJson(')));
    expect(reportsSnapshot, isNot(contains('_loadRawData')));
    expect(accountingSnapshot, isNot(contains('getBusinessEntityListJson(')));
    expect(accountingSnapshot, isNot(contains('_loadRawData')));
    expect(localDatabaseService, isNot(contains('getBusinessEntityListJson(')));
    expect(localDatabaseService, isNot(contains('getBusinessEntityListJsonBatches(')));
    expect(localDatabaseService, contains('sqlite_bootstrap'));
  });
}
