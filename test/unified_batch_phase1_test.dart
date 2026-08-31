import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/localization/localized_domain_exception.dart';
import 'package:ventio/core/services/batch_inventory_service.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/models/inventory_batch.dart';
import 'package:ventio/models/product.dart';

Product _product({
  required String id,
  required DateTime now,
  required bool expiryTrackingEnabled,
}) {
  return Product(
    id: id,
    name: id,
    code: id.toUpperCase(),
    price: 10,
    cost: 2,
    stock: 0,
    category: 'Test',
    trackStock: true,
    expiryTrackingEnabled: expiryTrackingEnabled,
    storeId: 'store-1',
    branchId: 'main',
    createdAt: now,
    updatedAt: now,
  );
}

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

Future<void> _setWarehouseQuantity(
  VentioDriftDatabase db, {
  required String productId,
  required double quantity,
  DateTime? now,
}) async {
  final timestamp = (now ?? DateTime.utc(2026, 8, 28)).toIso8601String();
  await db.customStatement(
    '''
    INSERT INTO warehouse_inventory
      (id, store_id, branch_id, warehouse_id, product_id, quantity,
       created_at, updated_at, device_id, last_modified_by_device_id,
       sync_status, version)
    VALUES (?, 'store-1', 'main', 'main', ?, ?, ?, ?, 'device-1',
            'device-1', 'pending', 1)
    ON CONFLICT(store_id, warehouse_id, product_id) DO UPDATE SET
      quantity = excluded.quantity,
      updated_at = excluded.updated_at
    ''',
    <Object?>[
      'store-1::main::$productId',
      productId,
      quantity,
      timestamp,
      timestamp,
    ],
  );
}

void main() {
  test('phase 1 schema stores batch cost, source line and receipt date',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);

    final columns = await db
        .customSelect('PRAGMA table_info(inventory_batches);')
        .get();
    final names = columns
        .map((row) => row.data['name']?.toString() ?? '')
        .toSet();

    expect(names, contains('source_line_id'));
    expect(names, contains('unit_cost'));
    expect(names, contains('initial_quantity'));
    expect(names, contains('cost_currency'));
    expect(names, contains('exchange_rate'));
    expect(names, contains('received_at'));
  });

  test('non-expiry product uses batches and allocates oldest receipt first',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final service = BatchInventoryService(db);
    final firstDate = DateTime.utc(2026, 8, 1);
    final secondDate = DateTime.utc(2026, 8, 10);
    final product = _product(
      id: 'no-expiry',
      now: firstDate,
      expiryTrackingEnabled: false,
    );
    await _persistProduct(db, product);

    await db.transaction(() async {
      await service.addUnifiedBatchStockInTransaction(
        product: product,
        warehouseId: 'main',
        batchId: 'batch-old',
        quantity: 10,
        unitCost: 1,
        sourceType: 'purchase',
        sourceId: 'purchase-1',
        sourceLineId: 'line-1',
        receivedAt: firstDate,
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'device-1',
      );
      await service.addUnifiedBatchStockInTransaction(
        product: product,
        warehouseId: 'main',
        batchId: 'batch-new',
        quantity: 10,
        unitCost: 2,
        sourceType: 'purchase',
        sourceId: 'purchase-2',
        sourceLineId: 'line-1',
        receivedAt: secondDate,
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'device-1',
      );
    });

    final allocations = await db.transaction(
      () => service.allocateUnifiedInTransaction(
        product: product,
        warehouseId: 'main',
        quantity: 12,
        movementDate: DateTime.utc(2026, 8, 20),
        storeId: 'store-1',
        deviceId: 'device-1',
      ),
    );

    expect(allocations, hasLength(2));
    expect(allocations.first.batchId, 'batch-old');
    expect(allocations.first.quantity, 10);
    expect(allocations.first.unitCost, 1);
    expect(allocations.last.batchId, 'batch-new');
    expect(allocations.last.quantity, 2);
    expect(allocations.last.unitCost, 2);
  });

  test('expiry contract is controlled by product data', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final service = BatchInventoryService(db);
    final now = DateTime.utc(2026, 8, 28);
    final expiring = _product(
      id: 'expiring',
      now: now,
      expiryTrackingEnabled: true,
    );
    final nonExpiring = _product(
      id: 'plain',
      now: now,
      expiryTrackingEnabled: false,
    );
    await _persistProduct(db, expiring);
    await _persistProduct(db, nonExpiring);

    await expectLater(
      () => db.transaction(
        () => service.addUnifiedBatchStockInTransaction(
          product: expiring,
          warehouseId: 'main',
          batchId: 'missing-expiry',
          quantity: 1,
          unitCost: 1,
          sourceType: 'purchase',
          sourceId: 'p1',
          sourceLineId: 'l1',
          receivedAt: now,
          storeId: 'store-1',
          branchId: 'main',
          deviceId: 'device-1',
        ),
      ),
      throwsA(
        isA<LocalizedDomainException>().having(
          (error) => error.key,
          'key',
          'error_expiration_date_required',
        ),
      ),
    );

    await expectLater(
      () => db.transaction(
        () => service.addUnifiedBatchStockInTransaction(
          product: nonExpiring,
          warehouseId: 'main',
          batchId: 'forbidden-expiry',
          quantity: 1,
          unitCost: 1,
          sourceType: 'purchase',
          sourceId: 'p2',
          sourceLineId: 'l1',
          receivedAt: now,
          expirationDate: DateTime.utc(2027, 1, 1),
          storeId: 'store-1',
          branchId: 'main',
          deviceId: 'device-1',
        ),
      ),
      throwsA(
        isA<LocalizedDomainException>().having(
          (error) => error.key,
          'key',
          'error_expiration_not_allowed',
        ),
      ),
    );
  });

  test('expiry product uses FEFO while preserving actual batch cost', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final service = BatchInventoryService(db);
    final now = DateTime.utc(2026, 8, 28);
    final product = _product(
      id: 'expiry-fefo',
      now: now,
      expiryTrackingEnabled: true,
    );
    await _persistProduct(db, product);

    await db.transaction(() async {
      await service.addUnifiedBatchStockInTransaction(
        product: product,
        warehouseId: 'main',
        batchId: 'later-expiry',
        quantity: 10,
        unitCost: 1,
        sourceType: 'purchase',
        sourceId: 'p1',
        sourceLineId: 'l1',
        receivedAt: DateTime.utc(2026, 8, 1),
        expirationDate: DateTime.utc(2026, 12, 1),
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'device-1',
      );
      await service.addUnifiedBatchStockInTransaction(
        product: product,
        warehouseId: 'main',
        batchId: 'earlier-expiry',
        quantity: 10,
        unitCost: 3,
        sourceType: 'purchase',
        sourceId: 'p2',
        sourceLineId: 'l1',
        receivedAt: DateTime.utc(2026, 8, 20),
        expirationDate: DateTime.utc(2026, 10, 1),
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'device-1',
      );
    });

    final allocations = await db.transaction(
      () => service.allocateUnifiedInTransaction(
        product: product,
        warehouseId: 'main',
        quantity: 5,
        movementDate: now,
        storeId: 'store-1',
        deviceId: 'device-1',
      ),
    );

    expect(allocations.single.batchId, 'earlier-expiry');
    expect(allocations.single.unitCost, 3);
  });

  test('source line identity is idempotent and balance invariant is auditable',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final service = BatchInventoryService(db);
    final now = DateTime.utc(2026, 8, 28);
    final product = _product(
      id: 'idempotent',
      now: now,
      expiryTrackingEnabled: false,
    );
    await _persistProduct(db, product);

    await db.transaction(() async {
      for (var attempt = 0; attempt < 2; attempt += 1) {
        await service.addUnifiedBatchStockInTransaction(
          product: product,
          warehouseId: 'main',
          batchId: 'batch-1',
          quantity: 8,
          unitCost: 2.5,
          sourceType: 'purchase',
          sourceId: 'purchase-1',
          sourceLineId: 'line-stable',
          receivedAt: now,
          storeId: 'store-1',
          branchId: 'main',
          deviceId: 'device-1',
        );
      }
    });

    await expectLater(
      () => db.transaction(
        () => service.addUnifiedBatchStockInTransaction(
          product: product,
          warehouseId: 'main',
          batchId: 'batch-1',
          quantity: 8,
          unitCost: 3,
          sourceType: 'purchase',
          sourceId: 'purchase-1',
          sourceLineId: 'line-stable',
          receivedAt: now,
          storeId: 'store-1',
          branchId: 'main',
          deviceId: 'device-1',
        ),
      ),
      throwsA(
        isA<LocalizedDomainException>().having(
          (error) => error.key,
          'key',
          'error_batch_source_line_conflict',
        ),
      ),
    );

    final balance = await db.customSelect(
      '''
      SELECT quantity
      FROM inventory_batch_balances
      WHERE batch_id = 'batch-1'
      ''',
    ).getSingle();
    expect(balance.read<double>('quantity'), 8);

    await _setWarehouseQuantity(
      db,
      productId: product.id,
      quantity: 8,
      now: now,
    );
    final check = await service.checkWarehouseBatchBalanceInTransaction(
      productId: product.id,
      warehouseId: 'main',
      storeId: 'store-1',
    );
    expect(check.isConsistent, isTrue);
    expect(check.batchCarryingValue, 20);

    await _setWarehouseQuantity(
      db,
      productId: product.id,
      quantity: 7,
      now: now,
    );
    final mismatch = await service.checkWarehouseBatchBalanceInTransaction(
      productId: product.id,
      warehouseId: 'main',
      storeId: 'store-1',
    );
    expect(mismatch.isConsistent, isFalse);
  });

  test('unified expiry is persisted as a calendar date without timezone shift',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final service = BatchInventoryService(db);
    final receivedAt = DateTime(2026, 8, 28, 14, 30);
    final expirationDate = DateTime(2027, 1, 15);
    final product = _product(
      id: 'calendar-expiry',
      now: receivedAt,
      expiryTrackingEnabled: true,
    );
    await _persistProduct(db, product);

    await db.transaction(
      () => service.addUnifiedBatchStockInTransaction(
        product: product,
        warehouseId: 'main',
        batchId: 'calendar-batch',
        quantity: 4,
        unitCost: 2,
        sourceType: 'purchase',
        sourceId: 'calendar-purchase',
        sourceLineId: 'calendar-line',
        receivedAt: receivedAt,
        expirationDate: expirationDate,
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'device-1',
      ),
    );

    final row = await db.customSelect(
      "SELECT expiration_date FROM inventory_batches WHERE id = 'calendar-batch'",
    ).getSingle();
    expect(row.read<String>('expiration_date'), '2027-01-15');
  });

  test('unified restore adjust and transfer preserve batch identity and cost',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final service = BatchInventoryService(db);
    final now = DateTime.utc(2026, 8, 28);
    final product = _product(
      id: 'unified-lifecycle',
      now: now,
      expiryTrackingEnabled: false,
    );
    await _persistProduct(db, product);

    await db.transaction(
      () => service.addUnifiedBatchStockInTransaction(
        product: product,
        warehouseId: 'main',
        batchId: 'lifecycle-batch',
        quantity: 10,
        unitCost: 2.5,
        sourceType: 'purchase',
        sourceId: 'lifecycle-purchase',
        sourceLineId: 'lifecycle-line',
        receivedAt: now,
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'device-1',
      ),
    );

    final sold = await db.transaction(
      () => service.allocateUnifiedInTransaction(
        product: product,
        warehouseId: 'main',
        quantity: 4,
        movementDate: now.add(const Duration(hours: 1)),
        storeId: 'store-1',
        deviceId: 'device-1',
      ),
    );
    expect(sold.single.batchId, 'lifecycle-batch');
    expect(sold.single.unitCost, 2.5);

    await db.transaction(
      () => service.restoreUnifiedInTransaction(
        product: product,
        warehouseId: 'main',
        allocations: const <BatchAllocation>[
          BatchAllocation(
            batchId: 'lifecycle-batch',
            quantity: 2,
            unitCost: 2.5,
          ),
        ],
        restoredAt: now.add(const Duration(hours: 2)),
        storeId: 'store-1',
        deviceId: 'device-1',
      ),
    );

    await db.transaction(
      () => service.adjustUnifiedBatchInTransaction(
        product: product,
        warehouseId: 'main',
        batchId: 'lifecycle-batch',
        quantityDelta: -3,
        adjustedAt: now.add(const Duration(hours: 3)),
        storeId: 'store-1',
        deviceId: 'device-1',
      ),
    );

    await expectLater(
      () => db.transaction(
        () => service.adjustUnifiedBatchInTransaction(
          product: product,
          warehouseId: 'main',
          batchId: 'lifecycle-batch',
          quantityDelta: -6,
          adjustedAt: now.add(const Duration(hours: 4)),
          storeId: 'store-1',
          deviceId: 'device-1',
        ),
      ),
      throwsA(isA<LocalizedDomainException>()),
    );

    final transferred = await db.transaction(
      () => service.transferUnifiedInTransaction(
        product: product,
        fromWarehouseId: 'main',
        toWarehouseId: 'secondary',
        quantity: 2,
        transferredAt: now.add(const Duration(hours: 5)),
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'device-1',
      ),
    );
    expect(transferred.single.batchId, 'lifecycle-batch');
    expect(transferred.single.unitCost, 2.5);

    await expectLater(
      () => db.transaction(
        () => service.allocateUnifiedInTransaction(
          product: product,
          warehouseId: 'main',
          quantity: 99,
          movementDate: now.add(const Duration(hours: 6)),
          storeId: 'store-1',
          deviceId: 'device-1',
        ),
      ),
      throwsA(isA<LocalizedDomainException>()),
    );

    final rows = await db.customSelect(
      '''
      SELECT warehouse_id, quantity
      FROM inventory_batch_balances
      WHERE batch_id = 'lifecycle-batch'
      ORDER BY warehouse_id
      ''',
    ).get();
    final quantities = <String, double>{
      for (final row in rows)
        row.read<String>('warehouse_id'): row.read<double>('quantity'),
    };
    expect(quantities['main'], 3);
    expect(quantities['secondary'], 2);
  });

  test('new batch balance schema rejects negative quantities', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);

    final schema = await db.customSelect(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'inventory_batch_balances'",
    ).getSingle();
    expect(
      schema.read<String>('sql').replaceAll(RegExp(r'\s+'), ' '),
      contains('CHECK (quantity >= 0)'),
    );
  });

}
