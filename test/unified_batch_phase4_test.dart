import 'dart:io';

import 'helpers/app_store_source.dart';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/unified_batch_phase4_closure_service.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/models/product.dart';

Product _product({required String id, required bool expiry}) => Product(
      id: id,
      name: id,
      code: id.toUpperCase(),
      price: 10,
      cost: 2.5,
      usdCost: 2.5,
      stock: 0,
      category: 'Phase4',
      trackStock: true,
      expiryTrackingEnabled: expiry,
      storeId: 'store-1',
      branchId: 'main',
      createdAt: DateTime.utc(2026, 8, 29),
      updatedAt: DateTime.utc(2026, 8, 29),
    );

Future<void> _persistProduct(
  VentioDriftDatabase db,
  Product product,
) async {
  await BusinessSqliteStore.upsertEntityPayloads(
    db,
    BusinessSqliteStore.productsKey,
    <Map<String, dynamic>>[product.toJson()],
  );
}

Future<void> _warehouseQty(
  VentioDriftDatabase db,
  Product product,
  double quantity,
) async {
  const at = '2026-08-29T00:00:00.000Z';
  await db.customStatement(
    '''
    INSERT INTO warehouse_inventory
      (id, store_id, branch_id, warehouse_id, product_id, quantity,
       created_at, updated_at, device_id, last_modified_by_device_id,
       sync_status, version)
    VALUES (?, 'store-1', 'main', 'main', ?, ?, ?, ?, 'device-1',
            'device-1', 'pending', 1)
    ''',
    <Object?>['store-1::main::${product.id}', product.id, quantity, at, at],
  );
}

void main() {
  test('phase 4 closes non-expiry inventory into Unified Batch idempotently',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final product = _product(id: 'phase4-plain', expiry: false);
    await _persistProduct(db, product);
    await _warehouseQty(db, product, 7);

    final service = UnifiedBatchPhase4ClosureService(db);
    final first = await service.close(
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'device-1',
      closedAt: DateTime.utc(2026, 8, 29, 1),
    );
    final second = await service.close(
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'device-1',
      closedAt: DateTime.utc(2026, 8, 29, 2),
    );

    expect(first.cutoversCreated, 1);
    expect(second.cutoversCreated, 0);
    final qty = await db.customSelect(
      "SELECT COALESCE(SUM(quantity), 0) AS qty FROM inventory_batch_balances WHERE store_id = 'store-1' AND warehouse_id = 'main' AND product_id = 'phase4-plain'",
    ).getSingle();
    expect((qty.data['qty'] as num).toDouble(), 7);
    final method = await db.customSelect(
      "SELECT value FROM settings WHERE key = 'inventory_costing_method_v1'",
    ).getSingle();
    expect(method.data['value'], 'batch');
    final history = await db.customSelect(
      "SELECT method FROM costing_method_history WHERE deleted_at = '' AND trim(effective_to) = ''",
    ).get();
    expect(history, hasLength(1));
    expect(history.single.data['method'], 'batch');
    final meta = await db.customSelect(
      "SELECT value FROM migration_meta WHERE key = 'unified_batch_phase4_closed_at'",
    ).getSingleOrNull();
    expect(meta, isNotNull);
    expect(meta!.data['value'], '2026-08-29T01:00:00.000Z');
  });

  test('phase 4 refuses anonymous expiry stock', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final product = _product(id: 'phase4-expiry', expiry: true);
    await _persistProduct(db, product);
    await _warehouseQty(db, product, 4);

    await expectLater(
      UnifiedBatchPhase4ClosureService(db).close(
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'device-1',
        closedAt: DateTime.utc(2026, 8, 29, 1),
      ),
      throwsA(anything),
    );
    final meta = await db.customSelect(
      "SELECT value FROM migration_meta WHERE key = 'unified_batch_phase4_closed_at'",
    ).getSingleOrNull();
    expect(meta, isNull);
  });

  test('phase 4 production source locks costing and values inventory by batch',
      () {
    final store = readAppStoreImplementationSource();
    final settings =
        File('lib/features/settings/settings_page.dart').readAsStringSync();
    final integrity = File(
            'lib/core/services/accounting_production_integrity_service.dart')
        .readAsStringSync();
    final dashboard =
        File('lib/core/storage/sqlite/business_sqlite_store.dart')
            .readAsStringSync();
    final snapshot =
        File('lib/core/snapshot/unified_snapshot.dart').readAsStringSync();
    final recovery = File('lib/data/app_store_recovery.dart').readAsStringSync();

    expect(
      store,
      contains('Inventory costing is permanently locked to Unified Batch'),
    );
    expect(settings, contains("title: Text(tr.text('unified_batch'))"));
    expect(
      settings,
      contains("subtitle: Text(tr.text('unified_batch_fixed_desc'))"),
    );
    expect(settings, isNot(contains('SegmentedButton<InventoryCostingMethod>')));
    expect(integrity, contains('unified_batch_quantity_mismatch'));
    expect(integrity, contains('SUM(bb.quantity * b.unit_cost)'));
    expect(dashboard, contains('SUM(bb.quantity * b.unit_cost)'));
    expect(snapshot, contains("'inventoryBatches'"));
    expect(snapshot, contains("'inventoryBatchBalances'"));
    expect(recovery, contains("_snapshotListMaps(decoded, 'inventoryBatches')"));
    expect(
      recovery,
      contains("_snapshotListMaps(decoded, 'inventoryBatchBalances')"),
    );
  });
}
