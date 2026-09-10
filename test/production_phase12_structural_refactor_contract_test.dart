import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_store_source.dart';

void main() {
  test('Phase 12 keeps AppStore as a thin facade with domain state ownership', () {
    final appStore = File('lib/data/app_store.dart').readAsStringSync();
    final state = File('lib/data/app_store_state.dart').readAsStringSync();
    final domains = File('lib/data/app_store_domains.dart').readAsStringSync();
    final compatibility =
        File('lib/data/app_store_forwarding_api.dart').readAsStringSync();
    final orchestration =
        File('lib/data/app_store_orchestration.dart').readAsStringSync();

    final classStart = appStore.indexOf('class AppStore extends ChangeNotifier');
    expect(classStart, greaterThanOrEqualTo(0));
    final concreteFacade = appStore.substring(classStart);
    expect(concreteFacade.split('\n').length, lessThan(220));

    for (final stateClass in <String>[
      '_CatalogState',
      '_CommerceState',
      '_InventoryState',
      '_AccountingState',
      '_SecurityState',
      '_SyncState',
      '_RuntimeState',
    ]) {
      expect(state, contains('class $stateClass'));
    }

    for (final port in <String>[
      'CatalogDomainPort',
      'CommerceDomainPort',
      'AccountingDomainPort',
      'InventoryDomainPort',
      'SecurityDomainPort',
      'SyncDomainPort',
      'RecoveryDomainPort',
    ]) {
      expect(domains, contains('abstract class $port'));
      expect(appStore, contains('late final $port'));
    }

    expect(concreteFacade, isNot(contains('final List<Product> _products')));
    expect(concreteFacade, isNot(contains('final List<Sale> _sales')));
    expect(concreteFacade, isNot(contains('final List<Purchase> _purchases')));
    expect(
      concreteFacade,
      isNot(contains('final List<AccountTransaction> _accountTransactions')),
    );

    expect(compatibility, contains('mixin _AppStoreForwardingApi'));
    expect(compatibility, contains('Future<void> transferStock'));
    expect(compatibility, contains('Future<String> exportBackupJson'));
    expect(compatibility, contains('Future<bool> authorizeSensitiveAction'));
    expect(orchestration, contains('mixin _AppStoreOrchestration'));
    expect(orchestration, contains('Future<void> ensureProductsLoaded()'));
    expect(orchestration, contains('int get accountingRevision'));
  });

  test('Phase 12 domain ports are consumed by production UI paths', () {
    final stress =
        File('lib/features/dev_tools/stress_lab_page.dart').readAsStringSync();
    final settings =
        File('lib/features/settings/settings_page_backup.dart').readAsStringSync();
    final accounting =
        File('lib/features/accounting/accounting_page.dart').readAsStringSync();
    final guard = File('lib/features/security/sensitive_action_guard.dart')
        .readAsStringSync();
    final dashboard = File('lib/features/dashboard/dashboard_snapshot_service.dart')
        .readAsStringSync();
    final sales = File('lib/features/sales/sales_page.dart').readAsStringSync();
    final purchases =
        File('lib/features/purchases/purchases_page.dart').readAsStringSync();

    expect(stress, contains('store.security.authorizeSensitiveAction('));
    expect(stress, contains('store.security.clearSensitiveActionAuthorization()'));
    expect(stress, contains('store.recovery.exportBackupJson()'));
    expect(settings, contains('store.recovery.importBackupJson('));
    expect(settings, contains('store.recovery.exportRecoveryFileJson('));
    expect(guard, contains('store.security.authorizeSensitiveAction('));
    expect(accounting, contains('widget.store.accounting.revision'));
    expect(accounting, contains('store.accounting.accountBalance('));
    expect(accounting, contains('store.accounting.transactions'));
    expect(dashboard, contains('store.catalog.products'));
    expect(dashboard, contains('store.commerce.sales'));
    expect(dashboard, contains('store.inventory.stockMovements'));
    expect(dashboard, contains('store.accounting.transactions'));
    expect(dashboard, contains('store.sync.queue'));
    expect(sales, contains('widget.store.commerce.ensureSalesLoaded()'));
    expect(purchases, contains('widget.store.commerce.ensurePurchasesLoaded()'));
  });

  test('Phase 12 preserves compatibility API and production schema contract', () {
    final source = readAppStoreImplementationSource();
    final database = File('lib/core/storage/sqlite/ventio_drift_database.dart')
        .readAsStringSync();

    for (final api in <String>[
      'createPurchase(',
      'returnPurchase(',
      'cancelPurchase(',
      'createSale(',
      'returnSale(',
      'cancelSale(',
      'createWarehouse(',
      'transferStock(',
      'traceInventoryBatch(',
      'verifyInventoryTraceabilityIntegrity()',
      'authorizeSensitiveAction(',
      'exportBackupJson()',
      'importBackupJson(',
      'applyRemoteSyncChanges(',
    ]) {
      expect(source, contains(api), reason: api);
    }

    expect(database, contains('schemaVersion => 33'));
    expect(database, contains('idx_stock_movements_reference_type_batch'));
    expect(database, contains('idx_inventory_batches_source_trace'));
  });
}
