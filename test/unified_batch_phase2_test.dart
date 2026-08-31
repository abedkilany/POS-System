import 'dart:io';

import 'helpers/app_store_source.dart';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/localization/localized_domain_exception.dart';
import 'package:ventio/core/services/batch_inventory_service.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/models/inventory_batch.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/product_costing.dart';
import 'package:ventio/models/sale_item.dart';

Product _phase2Product({
  required String id,
  required bool expiry,
  DateTime? now,
}) {
  final at = now ?? DateTime.utc(2026, 8, 28);
  return Product(
    id: id,
    name: id,
    code: id.toUpperCase(),
    price: 10,
    cost: 2,
    stock: 0,
    category: 'Phase2',
    trackStock: true,
    expiryTrackingEnabled: expiry,
    storeId: 'store-1',
    branchId: 'main',
    createdAt: at,
    updatedAt: at,
  );
}

Future<void> _persistPhase2Product(
  VentioDriftDatabase db,
  Product product,
) async {
  await BusinessSqliteStore.upsertEntityPayloads(
    db,
    BusinessSqliteStore.productsKey,
    <Map<String, dynamic>>[product.toJson()],
  );
}

Future<void> _setPhase2Warehouse(
  VentioDriftDatabase db,
  String productId,
  double quantity,
) async {
  const at = '2026-08-28T10:00:00.000Z';
  await db.customStatement(
    '''
    INSERT INTO warehouse_inventory
      (id, store_id, branch_id, warehouse_id, product_id, quantity,
       created_at, updated_at, device_id, last_modified_by_device_id,
       sync_status, version)
    VALUES (?, 'store-1', 'main', 'main', ?, ?, ?, ?, 'device-1',
            'device-1', 'pending', 1)
    ON CONFLICT(store_id, warehouse_id, product_id) DO UPDATE SET
      quantity = excluded.quantity, updated_at = excluded.updated_at
    ''',
    <Object?>['store-1::main::$productId', productId, quantity, at, at],
  );
}

void main() {
  test('phase 2 schema carries cutover, draft expiry and sale batch cost',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);

    final cutover = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='unified_batch_cutovers'",
    ).getSingleOrNull();
    expect(cutover, isNotNull);

    final purchaseColumns = await db
        .customSelect('PRAGMA table_info(purchase_items);')
        .get();
    expect(
      purchaseColumns.map((row) => row.data['name']),
      contains('requested_expiration_date'),
    );

    final saleAllocationColumns = await db
        .customSelect('PRAGMA table_info(sale_item_batch_allocations);')
        .get();
    expect(
      saleAllocationColumns.map((row) => row.data['name']),
      contains('unit_cost'),
    );
  });

  test('non-expiry cutover creates one idempotent opening batch', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final product = _phase2Product(id: 'legacy-plain', expiry: false);
    await _persistPhase2Product(db, product);
    await _setPhase2Warehouse(db, product.id, 9);
    final service = BatchInventoryService(db);

    for (var attempt = 0; attempt < 2; attempt += 1) {
      await db.transaction(
        () => service.ensureUnifiedCutoverInTransaction(
          product: product,
          warehouseId: 'main',
          openingUnitCost: 2.25,
          cutoverAt: DateTime.utc(2026, 8, 28, 10),
          storeId: 'store-1',
          branchId: 'main',
          deviceId: 'device-1',
        ),
      );
    }

    final batches = await db.customSelect(
      "SELECT COUNT(*) AS count, COALESCE(SUM(quantity), 0) AS qty FROM inventory_batch_balances WHERE product_id = 'legacy-plain'",
    ).getSingle();
    expect((batches.data['count'] as num).toInt(), 1);
    expect((batches.data['qty'] as num).toDouble(), 9);

    final marker = await db.customSelect(
      "SELECT opening_quantity, opening_unit_cost FROM unified_batch_cutovers WHERE product_id = 'legacy-plain'",
    ).getSingle();
    expect(marker.read<double>('opening_quantity'), 9);
    expect(marker.read<double>('opening_unit_cost'), 2.25);
  });

  test('existing cutover refuses warehouse/batch drift', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final product = _phase2Product(id: 'cutover-drift', expiry: false);
    await _persistPhase2Product(db, product);
    await _setPhase2Warehouse(db, product.id, 5);
    final service = BatchInventoryService(db);

    await db.transaction(
      () => service.ensureUnifiedCutoverInTransaction(
        product: product,
        warehouseId: 'main',
        openingUnitCost: 2,
        cutoverAt: DateTime.utc(2026, 8, 28, 10),
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'device-1',
      ),
    );
    await _setPhase2Warehouse(db, product.id, 6);

    await expectLater(
      () => db.transaction(
        () => service.ensureUnifiedCutoverInTransaction(
          product: product,
          warehouseId: 'main',
          openingUnitCost: 2,
          cutoverAt: DateTime.utc(2026, 8, 28, 11),
          storeId: 'store-1',
          branchId: 'main',
          deviceId: 'device-1',
        ),
      ),
      throwsA(
        isA<LocalizedDomainException>().having(
          (error) => error.key,
          'key',
          'error_batch_cutover_mismatch',
        ),
      ),
    );
  });

  test('expiry cutover backfills legacy batch cost before activation', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final product = _phase2Product(id: 'legacy-expiry-cost', expiry: true);
    await _persistPhase2Product(db, product);
    await _setPhase2Warehouse(db, product.id, 3);
    const at = '2026-08-01T10:00:00.000Z';
    await db.customStatement(
      '''
      INSERT INTO inventory_batches
        (id, product_id, product_name, expiration_date, status, source_type,
         source_id, unit_cost, store_id, branch_id, created_at, updated_at,
         device_id, last_modified_by_device_id, sync_status, version)
      VALUES ('old-exp-b1', ?, ?, '2027-01-01', 'active', 'legacy',
              'legacy-1', 0, 'store-1', 'main', ?, ?, 'device-1', 'device-1',
              'pending', 1)
      ''',
      <Object?>[product.id, product.name, at, at],
    );
    await db.customStatement(
      '''
      INSERT INTO inventory_batch_balances
        (id, batch_id, product_id, warehouse_id, store_id, branch_id,
         quantity, reserved_quantity, version, created_at, updated_at,
         device_id, last_modified_by_device_id, sync_status)
      VALUES ('old-exp-bal', 'old-exp-b1', ?, 'main', 'store-1', 'main',
              3, 0, 1, ?, ?, 'device-1', 'device-1', 'pending')
      ''',
      <Object?>[product.id, at, at],
    );
    final service = BatchInventoryService(db);
    await db.transaction(
      () => service.ensureUnifiedCutoverInTransaction(
        product: product,
        warehouseId: 'main',
        openingUnitCost: 2.5,
        cutoverAt: DateTime.utc(2026, 8, 28, 10),
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'device-1',
      ),
    );

    final row = await db.customSelect(
      "SELECT unit_cost FROM inventory_batches WHERE id = 'old-exp-b1'",
    ).getSingle();
    expect(row.read<double>('unit_cost'), 2.5);
  });

  test('expiry cutover refuses untracked legacy quantity', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final product = _phase2Product(id: 'legacy-expiry', expiry: true);
    await _persistPhase2Product(db, product);
    await _setPhase2Warehouse(db, product.id, 3);
    final service = BatchInventoryService(db);

    await expectLater(
      () => db.transaction(
        () => service.ensureUnifiedCutoverInTransaction(
          product: product,
          warehouseId: 'main',
          openingUnitCost: 1,
          cutoverAt: DateTime.utc(2026, 8, 28),
          storeId: 'store-1',
          branchId: 'main',
          deviceId: 'device-1',
        ),
      ),
      throwsA(
        isA<LocalizedDomainException>().having(
          (error) => error.key,
          'key',
          'error_batch_cutover_expiry_missing',
        ),
      ),
    );
  });

  test('insufficient unified allocation rolls back all batch deductions',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final product = _phase2Product(id: 'rollback-sale', expiry: false);
    await _persistPhase2Product(db, product);
    final service = BatchInventoryService(db);
    await db.transaction(
      () => service.addUnifiedBatchStockInTransaction(
        product: product,
        warehouseId: 'main',
        batchId: 'rb-1',
        quantity: 5,
        unitCost: 3,
        sourceType: 'purchase',
        sourceId: 'p1',
        sourceLineId: 'l1',
        receivedAt: DateTime.utc(2026, 8, 1),
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'device-1',
      ),
    );

    await expectLater(
      () => db.transaction(
        () => service.allocateUnifiedInTransaction(
          product: product,
          warehouseId: 'main',
          quantity: 6,
          movementDate: DateTime.utc(2026, 8, 28),
          storeId: 'store-1',
          deviceId: 'device-1',
        ),
      ),
      throwsA(isA<LocalizedDomainException>()),
    );
    final row = await db.customSelect(
      "SELECT quantity FROM inventory_batch_balances WHERE batch_id = 'rb-1'",
    ).getSingle();
    expect(row.read<double>('quantity'), 5);
  });

  test('batch sale line cost is the exact allocation cost', () {
    const item = SaleItem(
      productId: 'A',
      productName: 'A',
      unitPrice: 5,
      quantity: 15,
      baseQuantity: 15,
      unitCost: 99,
      costingMethodAtSale: InventoryCostingMethod.batch,
      batchAllocations: <BatchAllocation>[
        BatchAllocation(batchId: 'b1', quantity: 10, unitCost: 1),
        BatchAllocation(batchId: 'b2', quantity: 5, unitCost: 1.3),
      ],
    );
    expect(item.lineCost, closeTo(16.5, 0.000001));
  });

  test('draft purchase expiry request survives typed sqlite persistence',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    await BusinessSqliteStore.upsertEntityPayloads(
      db,
      BusinessSqliteStore.purchasesKey,
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'draft-p1',
          'purchaseNo': 'P-1',
          'supplierId': 's1',
          'supplierName': 'Supplier',
          'date': '2026-08-28T10:00:00.000Z',
          'status': 'Draft',
          'paymentStatus': 'credit',
          'paymentMethod': 'Cash',
          'warehouseId': 'main',
          'warehouseName': 'Main',
          'createdAt': '2026-08-28T10:00:00.000Z',
          'updatedAt': '2026-08-28T10:00:00.000Z',
          'storeId': 'store-1',
          'branchId': 'main',
          'version': 1,
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'lineId': 'draft-line-1',
              'productId': 'A',
              'productName': 'A',
              'quantity': 4,
              'unitCost': 2,
              'conversionToBase': 1,
              'batchAllocations': <Map<String, dynamic>>[
                <String, dynamic>{
                  'batchId': '',
                  'quantity': 4,
                  'expirationDate': '2027-01-15T00:00:00.000',
                }
              ],
            }
          ],
        }
      ],
    );

    final row = await db.customSelect(
      "SELECT requested_expiration_date FROM purchase_items WHERE id = 'draft-line-1'",
    ).getSingle();
    expect(row.read<String>('requested_expiration_date').substring(0, 10),
        '2027-01-15');
  });

  test('phase 2 app-store paths are wired to unified batch contracts', () {
    final source = readAppStoreImplementationSource();
    expect(source, contains('_receiveUnifiedPurchaseLineInTransaction'));
    expect(source, contains('allocateUnifiedInTransaction'));
    expect(source, contains('InventoryCostingMethod.batch'));
    expect(source, contains('_requirePurchaseBatchesUnusedInTransaction'));
    expect(source, contains('purchase_edit_reverse'));
    expect(source, contains('purchase_edit_repost'));
    expect(source, contains('restoreUnifiedInTransaction'));
    expect(source, contains('ensuredUnifiedCutovers'));
    expect(source, contains('_assertUnifiedBatchMovementBalancesInTransaction'));
    expect(source, contains('_remainingReversibleStockQuantityInTransaction'));
  });

  test('phase 2 audit hardens legacy, service-item and edit guards', () {
    final source = readAppStoreImplementationSource();
    final purchasesUi =
        File('lib/features/purchases/purchases_page.dart').readAsStringSync();
    expect(source, contains('_unifiedOpeningCostForProductInTransaction'));
    expect(source, contains('SUM(sm.quantity * sm.unit_cost)'));
    expect(source,
        contains('was already absorbed into the Unified Batch opening balance'));
    expect(source, contains('if (!product.trackStock) continue;'));
    expect(source, contains('Sale return changed concurrently'));
    expect(source, contains('assertWarehouseBatchBalanceInTransaction'));
    expect(purchasesUi, contains('(purchase.isDraft || purchase.isReceived)'));
  });

}
