import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_store_source.dart';

void main() {
  test('Phase 9 traceability service covers production invariants', () {
    final service = File('lib/core/services/inventory_traceability_service.dart')
        .readAsStringSync();
    final manufacturing =
        File('lib/data/app_store_manufacturing.dart').readAsStringSync();
    final transfers =
        File('lib/data/app_store_warehouse_cash.dart').readAsStringSync();
    final appStore = readAppStoreImplementationSource();
    final database = File('lib/core/storage/sqlite/ventio_drift_database.dart')
        .readAsStringSync();

    expect(service, contains('Future<Map<String, dynamic>> traceBatch'));
    expect(service, contains('manufacturing_input_to_output'));
    expect(service, contains('assertTransferTraceabilityInTransaction'));
    expect(service, contains('assertManufacturingTraceabilityInTransaction'));
    expect(service, contains('warehouse_batch_quantity_mismatch'));
    expect(service, contains('expiry_contract_violation'));
    expect(service, contains('warehouse_transfer_traceability_mismatch'));
    expect(service, contains('manufacturing_traceability_mismatch'));
    expect(manufacturing,
        contains('assertManufacturingTraceabilityInTransaction'));
    expect(transfers, contains('assertTransferTraceabilityInTransaction'));
    expect(appStore, contains('traceInventoryBatch'));
    expect(appStore, contains('verifyInventoryTraceabilityIntegrity'));
    expect(database, contains('schemaVersion => 32'));
    expect(database, contains('idx_stock_movements_reference_type_batch'));
    expect(database, contains('idx_inventory_batches_source_trace'));
  });
}
