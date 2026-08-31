import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'real user scenario uses application write paths, never direct SQL writes',
      () {
    final source =
        File('lib/features/dev_tools/stress_lab_page.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _runRealUserScenarioAudit()');
    final end =
        source.indexOf('Future<void> _runOneButtonSystemAudit()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final body = source.substring(start, end);

    for (final requiredCall in <String>[
      'store.createPurchase(',
      'store.updatePurchaseDraft(',
      'store.receivePurchase(',
      'store.deleteDraftPurchase(',
      'store.settlePurchasePayment(',
      'store.returnPurchase(',
      'store.cancelPurchase(',
      'store.refundPurchaseCash(',
      'store.createSale(',
      'store.settleSalePayment(',
      'store.returnSale(',
      'store.cancelSale(',
      'store.refundSaleCash(',
      'store.addOrUpdateExpense(',
      'store.postExpense(',
      'store.cancelExpense(',
      'store.createWarehouseTransferOrder(',
      'store.createInventoryCountSession(',
      'store.approveInventoryCount(',
      'store.createBillOfMaterials(',
      'store.completeManufacturingOrder(',
      'store.setInventoryCostingMethod(',
      'store.recordWasteLoss(',
      'store.reverseWasteLossGroup(',
      'store.settleAccountPayment(',
      'store.warehouseStockFromSqlite(',
      'store.refreshAfterDatabaseChange(',
      'CashOperationService.current(authorization: store)',
      '_ensureAuditCashDrawerOpen();',
      'AccountingProductionIntegrityService(db).audit()',
      'AccountingService.calculateCashDrawerExpectedCash(sessionId)',
    ]) {
      expect(body, contains(requiredCall), reason: requiredCall);
    }

    for (final forbiddenWrite in <String>[
      '.customInsert(',
      '.customUpdate(',
      '.customDelete(',
      '.customStatement(',
      'INSERT INTO ',
      'UPDATE ',
      'DELETE FROM ',
    ]) {
      expect(body, isNot(contains(forbiddenWrite)), reason: forbiddenWrite);
    }

    for (final scenarioSection in <String>[
      'S01 Core Lifecycle',
      'S02 Partial Returns',
      'S03 Unified Batch',
      'S04 FEFO & Batches',
      'S05 Zero-value Sale',
      'S06 Waste & Count',
      'S07 Multi-Warehouse',
      'S08 Unified Batch Manufacturing',
      'S09 Vouchers & Idempotency',
      'S10 Cash Guards',
      'S11 Overpayment Guards',
      'S12 Persistence',
      'S13 Unified Batch Lock',
      'Unified Batch certification',
      'UNIFIED_BATCH_CERTIFICATION PASS 15/15',
      'UB-001 warehouse=batch quantity',
      'UB-009 manufacturing uses actual batch cost',
      'UB-012 no legacy layer writes after Phase 4',
      'UB-015 Phase 4 marker/cutovers and batch persistence exist',
      'Scenario Coverage',
    ]) {
      expect(body, contains(scenarioSection), reason: scenarioSection);
    }

    // The cash fixture itself is prepared through AccountingService, outside
    // the scenario body, so the lab never seeds physical cash without a GL basis.
    expect(source, contains('AccountingService.recordOpeningCashLocationBalance('));

    // Read-only SQL is allowed strictly for evidence and reconciliation.
    expect(body, contains('.customSelect('));
    expect(body, contains('inventory_batch_balances'));
    expect(body, contains('inventory_batches'));
    expect(body, contains('sale_item_batch_allocations'));
    expect(body, isNot(contains('activeLayers=')));
    expect(body, isNot(contains('layerQty=')));
    expect(body, isNot(contains("'inventory_cost_layers_v1'")));
  });

  test('real user scenario re-authenticates sensitive reversals without bypass', () {
    final source =
        File('lib/features/dev_tools/stress_lab_page.dart').readAsStringSync();
    expect(source, contains('_authorizeRealUserScenarioSensitiveActions'));
    expect(source, contains('SensitiveAction.purchaseReverse'));
    expect(source, contains('SensitiveAction.saleReverse'));
    expect(source, contains('validity: authorizationValidity'));
    expect(source, contains('const Duration(minutes: 30)'));
    expect(source, contains('store.security.clearSensitiveActionAuthorization();'));
    expect(
      source,
      contains('the grant is limited to sale/purchase reversals'),
    );
  });

  test('maintenance exposes guarded real user scenario launcher', () {
    final source = File('lib/features/maintenance/maintenance_page.dart')
        .readAsStringSync();
    expect(source, contains("ValueKey('RealUserScenarioLaunchButton')"));
    expect(source, contains('autoRunRealUserScenario: true'));
    expect(source, contains("tr.text('comprehensive_scenario_lab_desc')"));
    final arabicTranslations =
        File('assets/translations/ar.json').readAsStringSync();
    expect(
        arabicTranslations, contains('استخدم هذه الأداة فقط على قاعدة اختبار'));
  });
}
