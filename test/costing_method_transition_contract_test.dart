import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_store_source.dart';

void main() {
  final store = readAppStoreImplementationSource();
  final model = File('lib/models/product_costing.dart').readAsStringSync();
  final integrity = File(
          'lib/core/services/accounting_production_integrity_service.dart')
      .readAsStringSync();
  final closure = File(
          'lib/core/services/unified_batch_phase4_closure_service.dart')
      .readAsStringSync();
  final lab = File('lib/features/dev_tools/stress_lab_page.dart')
      .readAsStringSync();

  test('Phase 4 locks production costing to Unified Batch', () {
    expect(store, contains('InventoryCostingMethod.batch;'));
    expect(store,
        contains('Inventory costing is permanently locked to Unified Batch'));
    expect(closure, contains("VALUES (?, 'batch', ?)"));
    expect(integrity, contains('inventory_costing_not_unified_batch'));
  });

  test('legacy costing codes remain readable for historical documents', () {
    expect(model, contains("case 'fifo':"));
    expect(model, contains("case 'weighted_average':"));
    expect(model, contains("case 'last_purchase_cost':"));
    expect(model, contains("case 'unified_batch':"));
  });

  test('legacy cost layers are historical evidence, not valuation truth', () {
    expect(closure, contains("'unified_batch_legacy_cost_layers_mode'"));
    expect(closure, contains("'read_only'"));
    expect(integrity, contains('legacy_cost_layer_post_phase4_write'));
    expect(integrity, contains('SUM(bb.quantity * b.unit_cost)'));
  });

  test('scenario lab verifies the permanent Phase 4 lock', () {
    expect(lab, contains('S13 Unified Batch Lock'));
    expect(lab, contains('legacySwitchBlocked=true'));
    expect(lab, contains("openHistory=batch:1"));
  });
}
