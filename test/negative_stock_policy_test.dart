import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/localization/localized_domain_exception.dart';
import 'package:ventio/core/services/batch_inventory_service.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/inventory_batch.dart';

Product _product(String id) => Product(
      id: id,
      name: id,
      code: id.toUpperCase(),
      price: 10,
      cost: 2,
      stock: 0,
      category: 'Negative stock policy',
      trackStock: true,
      storeId: 'store-1',
      branchId: 'main',
      createdAt: DateTime.utc(2026, 9, 3),
      updatedAt: DateTime.utc(2026, 9, 3),
    );

Future<void> _persistProduct(VentioDriftDatabase db, Product product) =>
    BusinessSqliteStore.upsertEntityPayloads(
      db,
      BusinessSqliteStore.productsKey,
      <Map<String, dynamic>>[product.toJson()],
    );

Future<void> _addBatch(
  BatchInventoryService service,
  Product product, {
  required String batchId,
  required double quantity,
  required double unitCost,
}) =>
    service.addUnifiedBatchStockInTransaction(
      product: product,
      warehouseId: 'main',
      batchId: batchId,
      quantity: quantity,
      unitCost: unitCost,
      sourceType: 'negative_stock_test',
      sourceId: batchId,
      sourceLineId: '$batchId:line',
      receivedAt: DateTime.utc(2026, 9, 3),
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'device-1',
    );

void main() {
  test('DENY keeps Unified Batch strict and rolls shortage back', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final service = BatchInventoryService(db);
    final product = _product('deny-product');
    await _persistProduct(db, product);

    await db.transaction(() => _addBatch(
          service,
          product,
          batchId: 'deny-batch',
          quantity: 2,
          unitCost: 2,
        ));

    await expectLater(
      () => db.transaction(() => service.allocateUnifiedInTransaction(
            product: product,
            warehouseId: 'main',
            quantity: 3,
            movementDate: DateTime.utc(2026, 9, 3, 12),
            storeId: 'store-1',
            branchId: 'main',
            deviceId: 'device-1',
            allowNegativeStock: false,
          )),
      throwsA(isA<LocalizedDomainException>()),
    );

    final balance = await db.customSelect(
      "SELECT quantity FROM inventory_batch_balances WHERE batch_id = 'deny-batch'",
    ).getSingle();
    expect(balance.read<double>('quantity'), 2);
  });

  test('ALLOW consumes real batches then creates a tracked deficit', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final service = BatchInventoryService(db);
    final product = _product('allow-product');
    await _persistProduct(db, product);

    await db.transaction(() => _addBatch(
          service,
          product,
          batchId: 'allow-batch',
          quantity: 2,
          unitCost: 2,
        ));

    late List<BatchAllocation> allocations;
    await db.transaction(() async {
      allocations = await service.allocateUnifiedInTransaction(
        product: product,
        warehouseId: 'main',
        quantity: 5,
        movementDate: DateTime.utc(2026, 9, 3, 12),
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'device-1',
        allowNegativeStock: true,
      );
    });

    expect(allocations.length, 2);
    expect(allocations.first.batchId, 'allow-batch');
    expect(allocations.first.quantity, 2);
    expect(BatchInventoryService.isDeficitBatchId(allocations.last.batchId),
        isTrue);
    expect(allocations.last.quantity, 3);

    final physical = await db.customSelect(
      "SELECT quantity FROM inventory_batch_balances WHERE batch_id = 'allow-batch'",
    ).getSingle();
    expect(physical.read<double>('quantity'), 0);

    final deficit = await db.customSelect(
      "SELECT quantity_open, status FROM inventory_stock_deficits WHERE product_id = 'allow-product'",
    ).getSingle();
    expect(deficit.read<double>('quantity_open'), 3);
    expect(deficit.read<String>('status'), 'open');
  });

  test('incoming stock settles deficit before becoming physical availability',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final service = BatchInventoryService(db);
    final product = _product('settlement-product');
    await _persistProduct(db, product);

    await db.transaction(() async {
      await service.allocateUnifiedInTransaction(
        product: product,
        warehouseId: 'main',
        quantity: 3,
        movementDate: DateTime.utc(2026, 9, 3, 12),
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'device-1',
        allowNegativeStock: true,
      );
      await _addBatch(
        service,
        product,
        batchId: 'incoming-batch',
        quantity: 10,
        unitCost: 2.5,
      );
    });

    final deficit = await db.customSelect(
      "SELECT quantity_open, status FROM inventory_stock_deficits WHERE product_id = 'settlement-product'",
    ).getSingle();
    expect(deficit.read<double>('quantity_open'), 0);
    expect(deficit.read<String>('status'), 'resolved');

    final incoming = await db.customSelect(
      "SELECT quantity FROM inventory_batch_balances WHERE batch_id = 'incoming-batch'",
    ).getSingle();
    expect(incoming.read<double>('quantity'), 7);
  });
}
