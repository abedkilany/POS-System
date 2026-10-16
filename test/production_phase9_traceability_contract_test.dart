import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/schema_version_contract.dart';
import 'helpers/dart_library_source.dart';

void main() {
  test('Phase 9 traceability service covers production invariants', () {
    final service =
        File('lib/core/services/inventory_traceability_service.dart')
            .readAsStringSync();
    final manufacturing =
        readDartLibrarySource('lib/data/app_store_manufacturing.dart');
    final transfers =
        readDartLibrarySource('lib/data/app_store_warehouse_cash.dart');
    final database = readDartLibrarySource(
        'lib/core/storage/sqlite/ventio_drift_database.dart');

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
    final inventoryPort =
        readDartLibrarySource('lib/data/app_store_domains_inventory.dart');
    expect(inventoryPort, contains('Future<Map<String, dynamic>> traceBatch'));
    expect(inventoryPort, contains('verifyTraceabilityIntegrity'));
    expect(inventoryPort, contains('_traceInventoryBatchDomainImpl'));
    expect(inventoryPort,
        contains('_verifyInventoryTraceabilityIntegrityDomainImpl'));
    expectSchemaVersionAtLeast(database, 33);
    expect(database, contains('idx_stock_movements_reference_type_batch'));
    expect(database, contains('idx_inventory_batches_source_trace'));
  });
}
