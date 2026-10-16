import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_store_source.dart';
import 'helpers/schema_version_contract.dart';
import 'helpers/accounting_page_source.dart';
import 'helpers/sales_page_source.dart';

import 'helpers/dart_library_source.dart';

void main() {
  test('Phase 2 commerce workflows use focused domain services', () {
    final store = readAppStoreImplementationSource();
    final purchaseDraft = File('lib/core/services/purchase_draft_service.dart')
        .readAsStringSync();
    final purchaseReceipt =
        File('lib/core/services/purchase_receipt_service.dart')
            .readAsStringSync();
    final saleWorkflow =
        File('lib/core/services/sale_workflow_service.dart').readAsStringSync();

    expect(store, contains('PurchaseDraftService().validateItems('));
    expect(store, contains('draftService.createPurchase('));
    expect(store, contains('draftService.updateDraft('));
    expect(store, contains('PurchaseDraftService().softDeleteDraft('));
    expect(store, contains('PurchaseReceiptService().prepare('));
    expect(store, contains('saleWorkflow.validateCreate('));
    expect(store, contains('saleWorkflow.prepareItems('));
    expect(store, contains('saleWorkflow.prepareInitialPayment('));
    expect(purchaseDraft, contains('Purchase updateDraft('));
    expect(purchaseDraft, contains('Purchase softDeleteDraft('));
    expect(purchaseReceipt, contains('class PurchaseReceiptService'));
    expect(saleWorkflow, contains('class SaleWorkflowService'));
  });

  test('Phase 12 keeps AppStore as a thin facade with domain state ownership',
      () {
    final appStore = File('lib/data/app_store.dart').readAsStringSync();
    final state = readDartLibrarySource('lib/data/app_store_state.dart');
    final domains = readDartLibrarySource('lib/data/app_store_domains.dart');
    final compatibility =
        readDartLibrarySource('lib/data/app_store_forwarding_api.dart');
    final orchestration =
        readDartLibrarySource('lib/data/app_store_orchestration.dart');
    final accessAuth =
        readDartLibrarySource('lib/data/app_store_access_auth.dart');

    final classStart =
        appStore.indexOf('class AppStore extends ChangeNotifier');
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
      'AppRuntimeDomainPort',
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
    expect(compatibility, isNot(contains('Future<void> _transferStock')));
    expect(
      domains,
      contains('_AppStoreSplitWarehouseCashPart3(_store).transferStock('),
    );
    expect(compatibility, contains('Future<String> _exportBackupJson'));
    expect(
      compatibility,
      isNot(contains('Future<bool> _authorizeSensitiveAction')),
    );
    expect(domains, contains('_store._authorizeSensitiveAction('));
    expect(accessAuth, contains('Future<bool> _authorizeSensitiveAction({'));
    expect(orchestration, contains('mixin _AppStoreOrchestration'));
    expect(orchestration, contains('Future<void> _ensureProductsLoaded()'));
    expect(orchestration, contains('int get _accountingRevision'));
  });

  test('app lifecycle and preferences use the runtime domain port', () {
    final appShell = File('lib/app_split_01.dart').readAsStringSync();
    final domains = readDartLibrarySource('lib/data/app_store_domains.dart');
    for (final operation in <String>[
      'initialize(',
      'prepareForShutdown(',
      'loadLocale(',
      'saveLocale(',
      'loadThemeMode(',
      'saveThemeMode(',
    ]) {
      expect(appShell, contains('_store.runtime.$operation'));
      expect(appShell, isNot(contains('_store.$operation')));
    }
    expect(domains, contains('_AppStoreSplitStartupMigrations(_store)'));
    expect(domains, contains('_AppStoreSplitSyncApplyPart4(_store)'));
    expect(domains, contains('_AppStoreSplitAccessAuth(_store)'));
    expect(
      domains,
      isNot(matches(RegExp(
          r'_store\s*\.\s*(?:initialize|prepareForShutdown|loadLocale|saveLocale|loadThemeMode|saveThemeMode)\b'))),
    );
  });

  test('Phase 12 domain ports are consumed by production UI paths', () {
    final domains = readDartLibrarySource('lib/data/app_store_domains.dart');
    final settings = readDartLibrarySource(
        'lib/features/settings/settings_page_backup.dart');
    final accounting = readAccountingPageImplementationSource();
    final accountingAdvanced =
        readDartLibrarySource('lib/features/accounting/accounting_page.dart');
    final accountingSettings = readDartLibrarySource(
        'lib/features/accounting/accounting_page_settings.dart');
    final accountLedger = readDartLibrarySource(
        'lib/features/accounts/account_ledger_widgets.dart');
    final cash = readDartLibrarySource('lib/features/cash/cash_page.dart');
    final cashHistory =
        readDartLibrarySource('lib/features/cash/cash_history_panel.dart');
    final expenses =
        readDartLibrarySource('lib/features/expenses/expenses_page.dart');
    final guard = File('lib/features/security/sensitive_action_guard.dart')
        .readAsStringSync();
    final dashboard = readDartLibrarySource(
        'lib/features/dashboard/dashboard_snapshot_service.dart');
    final sales = readSalesPageImplementationSource();
    final purchases =
        readDartLibrarySource('lib/features/purchases/purchases_page.dart');
    final purchaseWorkstation = readDartLibrarySource(
        'lib/features/purchases/purchase_workstation_page.dart');
    final inventory =
        readDartLibrarySource('lib/features/inventory/inventory_page.dart');
    final manufacturing =
        readDartLibrarySource('lib/features/inventory/manufacturing_page.dart');
    final transfer = readDartLibrarySource(
        'lib/features/inventory/warehouse_transfer_page.dart');
    final syncCore = File('lib/core/services/unified_sync_core_service.dart')
        .readAsStringSync();

    expect(
      settings,
      matches(RegExp(r'store\s*\.\s*recovery\s*\.\s*importBackupJson\s*\(')),
    );
    expect(
      domains,
      contains('AppStoreRecoveryService(_store).importBackupJson('),
    );
    expect(
      settings,
      matches(
        RegExp(r'store\s*\.\s*recovery\s*\.\s*exportRecoveryFileJson\s*\('),
      ),
    );
    expect(guard, contains('store.security.authorizeSensitiveAction('));
    expect(accounting, contains('widget.store.accounting.revision'));
    expect(
      RegExp(r'store\s*\.\s*accounting\s*\.\s*accountBalance\s*\(')
          .hasMatch(accounting),
      isTrue,
    );
    expect(accounting, contains('store.accounting.transactions'));
    expect(accounting, contains('store.commerce.customers'));
    expect(accounting, contains('store.commerce.suppliers'));
    expect(accountingSettings,
        contains('widget.store.accounting.updateTaxConfiguration('));
    expect(accountingSettings,
        contains('widget.store.accounting.updateDefaultTaxRatePercent('));
    expect(accountLedger, contains('store.accounting.settleAccountPayment('));
    expect(
      accountingAdvanced,
      contains('widget.store.security.requirePermission('),
    );
    expect(accountingAdvanced, contains('widget.store.security.activeUser'));
    expect(accountingAdvanced, contains('widget.store.security.currentRole'));
    expect(cash, contains('widget.store.security.requireAllPermissions('));
    expect(cash, contains('widget.store.security.activeUser'));
    expect(cash, contains('widget.store.security.currentRole'));
    expect(cash, contains('widget.store.commerce.settleSalePayment('));
    expect(cash, contains('widget.store.commerce.settlePurchasePayment('));
    expect(cash, contains('widget.store.commerce.refundableSaleCashAmount('));
    expect(
      cash,
      matches(RegExp(
          r'widget\.store\.commerce\s*\.\s*refundablePurchaseCashAmount\s*\(')),
    );
    expect(cash, contains('widget.store.commerce.refundSaleCash('));
    expect(cash, contains('widget.store.commerce.refundPurchaseCash('));
    expect(cash, contains('widget.store.commerce.refundPurchaseReturnCash('));
    expect(cashHistory, contains('widget.store.accounting.refreshFromSqlite('));
    expect(expenses, contains('widget.store.security.hasAnyPermission('));
    expect(dashboard, contains('store.catalog.products'));
    expect(dashboard, contains('store.commerce.sales'));
    expect(dashboard, contains('store.inventory.stockMovements'));
    expect(dashboard, contains('store.accounting.transactions'));
    expect(dashboard, contains('store.sync.queue'));
    expect(syncCore, contains('store.sync.applyRemoteChanges('));
    expect(syncCore, contains('store.sync.markAcknowledged('));
    expect(syncCore, isNot(contains('store.applyRemoteSyncChanges(')));
    expect(syncCore, isNot(contains('store.markSyncChangesSyncedByIds(')));
    expect(sales, contains('widget.store.commerce.ensureSalesLoaded()'));
    expect(sales, contains('widget.store.commerce.createSale('));
    expect(sales, contains('widget.store.commerce.returnSale('));
    expect(
        purchases, contains('widget.store.commerce.ensurePurchasesLoaded()'));
    expect(purchases, contains('widget.store.commerce.returnPurchase('));
    expect(purchases, contains('widget.store.commerce.createPurchaseReturn('));
    expect(
        purchaseWorkstation, contains('widget.store.commerce.createPurchase('));
    expect(inventory, contains('widget.store.inventory.adjustStock('));
    expect(inventory,
        contains('widget.store.inventory.createInventoryCountSession('));
    expect(transfer,
        contains('widget.store.inventory.createWarehouseTransferOrder('));
    expect(transfer, contains('widget.store.inventory.recentTransferOrders('));
    expect(manufacturing,
        contains('widget.store.inventory.startManufacturingOrder('));
    expect(manufacturing,
        contains('widget.store.inventory.reverseManufacturingOrder('));
    expect(manufacturing,
        contains('widget.store.inventory.createBillOfMaterials('));
    expect(manufacturing,
        contains('widget.store.inventory.finishManufacturingOrder('));
    expect(manufacturing,
        contains('widget.store.inventory.editCompletedManufacturingOrder('));
    expect(inventory, contains('widget.store.catalog.stockTrackedProducts'));
    expect(inventory,
        contains('widget.store.inventory.pendingAutoCorrectionMovements'));
    expect(inventory, contains('widget.store.security.hasPermission('));
    expect(inventory, contains('widget.store.inventory.stockForWarehouse('));
    expect(inventory, contains('widget.store.inventory.createWarehouse('));
    expect(
      inventory,
      contains('widget.store.inventory.adjustExpiryBatchStock('),
    );
    expect(inventory, contains('widget.store.inventory.editStockAdjustment('));
    expect(inventory, contains('store.inventory.recordWasteLoss('));
    expect(inventory, contains('store.inventory.deleteWasteLoss('));
    expect(
      inventory + transfer,
      contains('widget.store.inventory.warehouseStockBalancesFromSqlite()'),
    );
    expect(
      RegExp(r'widget\.store\s*\.inventory\s*\.resolveWarehouseForSale\(')
          .hasMatch(sales),
      isTrue,
    );
    expect(
      RegExp(
        r'widget\.store\s*\.inventory\s*\.resolveWarehouseForPurchase\(',
      ).hasMatch(purchases),
      isTrue,
    );
  });

  test('Phase 12 preserves compatibility API and production schema contract',
      () {
    final source = readAppStoreImplementationSource();
    final database = readDartLibrarySource(
        'lib/core/storage/sqlite/ventio_drift_database.dart');

    for (final api in <String>[
      'createPurchase(',
      'returnPurchase(',
      'cancelPurchase(',
      'createSale(',
      'returnSale(',
      'cancelSale(',
      'createWarehouse(',
      'transferStock(',
      'authorizeSensitiveAction(',
      'exportBackupJson()',
      'importBackupJson(',
      '_applyRemoteSyncChanges(',
    ]) {
      expect(source, contains(api), reason: api);
    }

    expectSchemaVersionAtLeast(database, 33);
    expect(database, contains('idx_stock_movements_reference_type_batch'));
    expect(database, contains('idx_inventory_batches_source_trace'));
  });
}
