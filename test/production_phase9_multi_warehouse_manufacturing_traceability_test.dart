import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/models/inventory_batch.dart';
import 'package:ventio/models/manufacturing.dart';

import 'phase5_manufacturing_transfer_test.dart' as support;

void main() {
  tearDown(support.shutdownPhase5SqliteStoreForTesting);

  test(
      'production Phase 9 preserves FEFO batch identity across transfer, manufacturing and trace graph',
      () async {
    final store = await support.readyPhase5SqliteStore();
    final now = DateTime.now();
    final raw = support.phase5Product(
      id: 'p9-raw',
      code: 'P9-RAW',
      name: 'Phase 9 Raw',
      stock: 0,
      cost: 2,
    ).copyWith(
      expiryTrackingEnabled: true,
      expiryEntryRequired: true,
    );
    final finished = support.phase5Product(
      id: 'p9-finished',
      code: 'P9-FG',
      name: 'Phase 9 Finished',
      stock: 0,
      cost: 0,
    ).copyWith(
      expiryTrackingEnabled: true,
      expiryEntryRequired: true,
    );
    await store.addOrUpdateProduct(raw);
    await store.addOrUpdateProduct(finished);

    final receiving =
        await store.createWarehouse(name: 'P9 Receiving', code: 'P9-RCV');
    final production =
        await store.createWarehouse(name: 'P9 Production', code: 'P9-PRD');
    final retail =
        await store.createWarehouse(name: 'P9 Retail', code: 'P9-RTL');

    await store.adjustStock(
      productId: raw.id,
      warehouseId: receiving.id,
      quantityDelta: 10,
      reason: 'Phase 9 seed traceable raw batches',
      operationReferenceId: 'p9-seed-raw',
      batchAllocations: <BatchAllocation>[
        BatchAllocation(
          batchId: 'p9-raw-early',
          quantity: 5,
          supplierBatchNumber: 'SUP-EARLY',
          expirationDate: now.add(const Duration(days: 30)),
        ),
        BatchAllocation(
          batchId: 'p9-raw-late',
          quantity: 5,
          supplierBatchNumber: 'SUP-LATE',
          expirationDate: now.add(const Duration(days: 60)),
        ),
      ],
    );

    await store.transferStock(
      productId: raw.id,
      fromWarehouseId: receiving.id,
      toWarehouseId: production.id,
      quantity: 4,
      notes: 'FEFO raw transfer for production',
    );

    final db = SqliteMigrationManager.database!;
    final productionRawBatches = await db.customSelect(
      '''
      SELECT batch_id AS batchId, quantity
      FROM inventory_batch_balances
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
        AND quantity > 0.000001
      ORDER BY batch_id
      ''',
      variables: <Variable<Object>>[
        Variable<String>(store.appIdentity.storeId),
        Variable<String>(production.id),
        Variable<String>(raw.id),
      ],
    ).get();
    expect(productionRawBatches.length, 1);
    expect(productionRawBatches.single.read<String>('batchId'), 'p9-raw-early');
    expect(productionRawBatches.single.read<double>('quantity'), 4);

    final bom = await store.createBillOfMaterials(
      name: 'Phase 9 Traceable BOM',
      outputProductId: finished.id,
      outputQuantity: 1,
      components: const <BillOfMaterialsLine>[
        BillOfMaterialsLine(
          productId: 'p9-raw',
          productName: 'Phase 9 Raw',
          quantity: 3,
          unitCost: 2,
        ),
      ],
    );
    final order = await store.completeManufacturingOrder(
      bomId: bom.id,
      quantity: 1,
      rawMaterialsWarehouseId: production.id,
      rawMaterialsWarehouseName: production.name,
      finishedGoodsWarehouseId: production.id,
      finishedGoodsWarehouseName: production.name,
      outputBatchAllocations: <BatchAllocation>[
        BatchAllocation(
          batchId: 'p9-finished-batch',
          quantity: 1,
          manufacturingDate: now,
          expirationDate: now.add(const Duration(days: 90)),
        ),
      ],
    );

    expect(order.actualUnitCost, closeTo(6, 0.000001));
    final consumed = await db.customSelect(
      '''
      SELECT batch_id AS batchId, ABS(quantity) AS quantity
      FROM stock_movements
      WHERE reference_id = ? AND movement_type = 'manufacturing_consume'
        AND deleted_at = ''
      ORDER BY id
      ''',
      variables: <Variable<Object>>[Variable<String>(order.id)],
    ).get();
    expect(consumed.length, 1);
    expect(consumed.single.read<String>('batchId'), 'p9-raw-early');
    expect(consumed.single.read<double>('quantity'), 3);

    await store.transferStock(
      productId: finished.id,
      fromWarehouseId: production.id,
      toWarehouseId: retail.id,
      quantity: 1,
      notes: 'Finished batch to retail',
    );

    final trace = await store.traceInventoryBatch('p9-finished-batch');
    final edges = (trace['manufacturingEdges'] as List<dynamic>)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    expect(
      edges.any((edge) =>
          edge['fromBatchId'] == 'p9-raw-early' &&
          edge['toBatchId'] == 'p9-finished-batch' &&
          edge['referenceId'] == order.id),
      isTrue,
    );
    final movements = (trace['movements'] as List<dynamic>)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    final finishedBatchMovements = movements
        .where((item) => item['batchId'] == 'p9-finished-batch')
        .toList(growable: false);
    expect(
      finishedBatchMovements
          .where((item) => item['movementType'] == 'transfer_out')
          .length,
      1,
    );
    expect(
      finishedBatchMovements
          .where((item) => item['movementType'] == 'transfer_in')
          .length,
      1,
    );

    final retailBatch = await db.customSelect(
      '''
      SELECT quantity
      FROM inventory_batch_balances
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ? AND batch_id = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(store.appIdentity.storeId),
        Variable<String>(retail.id),
        Variable<String>(finished.id),
        const Variable<String>('p9-finished-batch'),
      ],
    ).getSingle();
    expect(retailBatch.read<double>('quantity'), 1);

    final integrity = await store.verifyInventoryTraceabilityIntegrity();
    expect(integrity['healthy'], isTrue, reason: integrity['issues'].toString());
    expect(integrity['issueCount'], 0);
  });
}
