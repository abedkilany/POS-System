import 'helpers/app_store_source.dart';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/localization/localized_domain_exception.dart';
import 'package:ventio/core/services/batch_inventory_service.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/models/product.dart';

Product _product(String id, {bool expiry = false}) => Product(
      id: id,
      name: id,
      code: id.toUpperCase(),
      price: 10,
      cost: 1,
      stock: 0,
      category: 'Phase3',
      trackStock: true,
      expiryTrackingEnabled: expiry,
      storeId: 'store-1',
      branchId: 'main',
      createdAt: DateTime.utc(2026, 8, 28),
      updatedAt: DateTime.utc(2026, 8, 28),
    );


Future<void> _persistProduct(VentioDriftDatabase db, Product product) async {
  await BusinessSqliteStore.upsertEntityPayloads(
    db,
    BusinessSqliteStore.productsKey,
    <Map<String, dynamic>>[product.toJson()],
  );
}

Future<void> _add(
  BatchInventoryService service, {
  required Product product,
  required String batchId,
  required double qty,
  required double cost,
  required DateTime at,
  String warehouse = 'main',
}) async {
  await service.addUnifiedBatchStockInTransaction(
    product: product,
    warehouseId: warehouse,
    batchId: batchId,
    quantity: qty,
    unitCost: cost,
    sourceType: 'phase3_test',
    sourceId: batchId,
    sourceLineId: '$batchId:line',
    receivedAt: at,
    storeId: 'store-1',
    branchId: 'main',
    deviceId: 'device-1',
  );
}

void main() {
  test('warehouse transfer preserves exact batch identity and cost', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final service = BatchInventoryService(db);
    final product = _product('transfer-product');
    await _persistProduct(db, product);

    await db.transaction(() async {
      await _add(
        service,
        product: product,
        batchId: 'old-batch',
        qty: 3,
        cost: 1.25,
        at: DateTime.utc(2026, 8, 1),
      );
      await _add(
        service,
        product: product,
        batchId: 'new-batch',
        qty: 4,
        cost: 2.5,
        at: DateTime.utc(2026, 8, 10),
      );
      final allocations = await service.transferUnifiedInTransaction(
        product: product,
        fromWarehouseId: 'main',
        toWarehouseId: 'secondary',
        quantity: 5,
        transferredAt: DateTime.utc(2026, 8, 28),
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'device-1',
      );
      expect(allocations.length, 2);
      expect(allocations[0].batchId, 'old-batch');
      expect(allocations[0].quantity, 3);
      expect(allocations[0].unitCost, 1.25);
      expect(allocations[1].batchId, 'new-batch');
      expect(allocations[1].quantity, 2);
      expect(allocations[1].unitCost, 2.5);
    });

    final rows = await db.customSelect(
      '''
      SELECT warehouse_id, batch_id, quantity
      FROM inventory_batch_balances
      WHERE product_id = 'transfer-product'
      ORDER BY warehouse_id, batch_id
      ''',
    ).get();
    final balances = <String, double>{
      for (final row in rows)
        '${row.read<String>('warehouse_id')}:${row.read<String>('batch_id')}':
            row.read<double>('quantity'),
    };
    expect(balances['main:old-batch'], 0);
    expect(balances['main:new-batch'], 2);
    expect(balances['secondary:old-batch'], 3);
    expect(balances['secondary:new-batch'], 2);
  });

  test('unified batch adjustment never allows a negative balance', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final service = BatchInventoryService(db);
    final product = _product('adjust-product');
    await _persistProduct(db, product);

    await db.transaction(() => _add(
          service,
          product: product,
          batchId: 'adjust-batch',
          qty: 2,
          cost: 4,
          at: DateTime.utc(2026, 8, 1),
        ));

    await expectLater(
      () => db.transaction(() => service.adjustUnifiedBatchInTransaction(
            product: product,
            warehouseId: 'main',
            batchId: 'adjust-batch',
            quantityDelta: -3,
            adjustedAt: DateTime.utc(2026, 8, 28),
            storeId: 'store-1',
            deviceId: 'device-1',
          )),
      throwsA(isA<LocalizedDomainException>()),
    );

    final row = await db.customSelect(
      "SELECT quantity FROM inventory_batch_balances WHERE batch_id = 'adjust-batch'",
    ).getSingle();
    expect(row.read<double>('quantity'), 2);
  });

  test('manufacturing primitives retain exact consumed cost and output cost',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final service = BatchInventoryService(db);
    final raw = _product('raw');
    final finished = _product('finished');
    await _persistProduct(db, raw);
    await _persistProduct(db, finished);

    await db.transaction(() async {
      await _add(
        service,
        product: raw,
        batchId: 'raw-1',
        qty: 2,
        cost: 1,
        at: DateTime.utc(2026, 8, 1),
      );
      await _add(
        service,
        product: raw,
        batchId: 'raw-2',
        qty: 2,
        cost: 3,
        at: DateTime.utc(2026, 8, 2),
      );
      final consumed = await service.allocateUnifiedInTransaction(
        product: raw,
        warehouseId: 'main',
        quantity: 3,
        movementDate: DateTime.utc(2026, 8, 28),
        storeId: 'store-1',
        deviceId: 'device-1',
      );
      final totalCost = consumed.fold<double>(
        0,
        (sum, allocation) => sum + allocation.quantity * allocation.unitCost,
      );
      expect(totalCost, 5);

      final output = await service.addUnifiedBatchStockInTransaction(
        product: finished,
        warehouseId: 'main',
        batchId: 'mfg-output',
        quantity: 2,
        unitCost: totalCost / 2,
        sourceType: 'manufacturing_output',
        sourceId: 'mfg-1',
        sourceLineId: 'mfg-1:output:0',
        receivedAt: DateTime.utc(2026, 8, 28),
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'device-1',
      );
      expect(output.unitCost, 2.5);
    });
  });

  test('phase 3 app-store paths use unified batches for all stock mutations', () {
    final source = readAppStoreImplementationSource();

    expect(source, contains('transferUnifiedInTransaction'));
    expect(source, contains("costingMethod: 'unified_batch'"));
    expect(source, contains("sourceType: 'manufacturing_output'"));
    expect(source, contains("sourceType: 'manual_adjustment'"));
    expect(source, contains("sourceType: 'inventory_count'"));
    expect(source, contains('recordWasteLoss'));
    expect(source, contains('restoreUnifiedInTransaction'));
    expect(source, contains('adjustUnifiedBatchInTransaction'));
    expect(source, contains(r'Opening stock for ${product.name} requires an expiry batch'));

    // Authoritative AppStore paths no longer call the expiry-only legacy API.
    expect(source, isNot(contains('allocateFefoInTransaction(')));
    expect(source, isNot(contains('transferFefoInTransaction(')));
    expect(source, isNot(contains('addStockInTransaction(')));
    expect(source, isNot(contains('adjustSpecificBatchInTransaction(')));
    expect(source, isNot(contains('restoreInTransaction(')));
  });

test('expiry batch count uses inventory adjustment accounting and unified reversal', () {
  final source = readAppStoreImplementationSource();

  // Batch-count shortages are inventory-count losses, not automatic expiry
  // disposal. Only an explicit expired/expiry category posts inventory_waste.
  expect(source, contains('isExplicitExpiryDisposal'));
  expect(source, contains('recordManualInventoryAdjustmentInTransaction'));

  // Reversal follows the journal actually posted and does not create a new
  // legacy valuation layer for post-cutover Unified movements.
  expect(source, contains('accountingReferenceType'));
  expect(source, contains('isHistoricalPreUnified'));
  expect(source, contains('creating a parallel layer here would re-introduce'));
});

}