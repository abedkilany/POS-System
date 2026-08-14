import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/batch_inventory_service.dart';
import 'package:ventio/core/localization/localized_domain_exception.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/models/inventory_batch.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/purchase.dart';
import 'package:ventio/models/purchase_item.dart';
import 'package:ventio/models/sale.dart';
import 'package:ventio/models/sale_item.dart';

void main() {
  test('receives multiple expiry batches and allocates them using FEFO',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);

    final now = DateTime.utc(2026, 8, 14);
    final product = Product(
      id: 'milk',
      name: 'Milk',
      code: 'MILK',
      price: 2,
      cost: 1,
      stock: 0,
      category: 'Food',
      expiryTrackingEnabled: true,
      expiryEntryRequired: true,
      storeId: 'store-1',
      branchId: 'main',
      createdAt: now,
      updatedAt: now,
    );
    await BusinessSqliteStore.upsertEntityPayloads(
      db,
      BusinessSqliteStore.productsKey,
      <Map<String, dynamic>>[product.toJson()],
    );
    final purchase = Purchase(
      id: 'purchase-1',
      purchaseNo: 'PO-1',
      supplierId: 'supplier-1',
      supplierName: 'Supplier',
      date: now,
      status: 'Draft',
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'milk',
          productName: 'Milk',
          quantity: 10,
          unitCost: 1,
        ),
      ],
      warehouseId: 'main',
      warehouseName: 'Main warehouse',
      storeId: 'store-1',
      branchId: 'main',
      createdAt: now,
      updatedAt: now,
    );
    await BusinessSqliteStore.upsertEntityPayloads(
      db,
      BusinessSqliteStore.purchasesKey,
      <Map<String, dynamic>>[purchase.toJson()],
    );

    final service = BatchInventoryService(db);
    await db.transaction(() async {
      await service.receiveInTransaction(
        product: product,
        warehouseId: 'main',
        purchaseId: purchase.id,
        purchaseLineIndex: 0,
        expectedQuantity: 10,
        allocations: <BatchAllocation>[
          BatchAllocation(
            batchId: 'late',
            quantity: 6,
            expirationDate: DateTime.utc(2026, 10, 1),
          ),
          BatchAllocation(
            batchId: 'early',
            quantity: 4,
            expirationDate: DateTime.utc(2026, 9, 1),
          ),
        ],
        receivedAt: now,
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'device-1',
      );
    });
    final restoredPurchases = await BusinessSqliteStore.readPurchases(db);
    expect(
        restoredPurchases.single.items.single.batchAllocations, hasLength(2));

    late List<BatchAllocation> saleAllocations;
    await db.transaction(() async {
      saleAllocations = await service.allocateFefoInTransaction(
        product: product,
        warehouseId: 'main',
        quantity: 7,
        saleDate: now,
        storeId: 'store-1',
        deviceId: 'device-1',
      );
    });

    expect(saleAllocations, hasLength(2));
    expect(saleAllocations.first.batchId, 'early');
    expect(saleAllocations.first.quantity, 4);
    expect(saleAllocations.last.batchId, 'late');
    expect(saleAllocations.last.quantity, 3);
    final sale = Sale(
      id: 'sale-1',
      invoiceNo: 'INV-1',
      customerName: 'Customer',
      date: now,
      status: 'Paid',
      discount: 0,
      items: <SaleItem>[
        SaleItem(
          productId: product.id,
          productName: product.name,
          unitPrice: 2,
          quantity: 7,
          batchAllocations: saleAllocations,
        ),
      ],
      storeId: 'store-1',
      branchId: 'main',
      createdAt: now,
      updatedAt: now,
    );
    await BusinessSqliteStore.upsertEntityPayloads(
      db,
      BusinessSqliteStore.salesKey,
      <Map<String, dynamic>>[sale.toJson()],
    );
    final restoredSales = await BusinessSqliteStore.readSales(db);
    expect(restoredSales.single.items.single.batchAllocations, hasLength(2));
    expect(restoredSales.single.items.single.batchAllocations.first.batchId,
        'early');
    final rows = await db.customSelect('''
      SELECT batch_id, quantity
      FROM inventory_batch_balances
      ORDER BY batch_id
    ''').get();
    expect(
        rows
            .singleWhere((row) => row.read<String>('batch_id') == 'early')
            .read<double>('quantity'),
        0);
    expect(
        rows
            .singleWhere((row) => row.read<String>('batch_id') == 'late')
            .read<double>('quantity'),
        3);
  });

  test('rejects an expired batch at receipt', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 8, 14);
    final product = Product(
      id: 'food',
      name: 'Food',
      code: 'FOOD',
      price: 2,
      cost: 1,
      stock: 0,
      category: 'Food',
      expiryTrackingEnabled: true,
      storeId: 'store-1',
      createdAt: now,
      updatedAt: now,
    );
    await BusinessSqliteStore.upsertEntityPayloads(
        db,
        BusinessSqliteStore.productsKey,
        <Map<String, dynamic>>[product.toJson()]);
    final purchase = Purchase(
      id: 'purchase-expired',
      purchaseNo: 'PO-2',
      supplierId: '',
      supplierName: 'Supplier',
      date: now,
      status: 'Draft',
      items: const <PurchaseItem>[
        PurchaseItem(
            productId: 'food', productName: 'Food', quantity: 1, unitCost: 1)
      ],
      storeId: 'store-1',
      createdAt: now,
      updatedAt: now,
    );
    await BusinessSqliteStore.upsertEntityPayloads(
        db,
        BusinessSqliteStore.purchasesKey,
        <Map<String, dynamic>>[purchase.toJson()]);
    final service = BatchInventoryService(db);
    expect(
      () => db.transaction(() => service.receiveInTransaction(
            product: product,
            warehouseId: 'main',
            purchaseId: purchase.id,
            purchaseLineIndex: 0,
            expectedQuantity: 1,
            allocations: <BatchAllocation>[
              BatchAllocation(
                batchId: 'expired',
                quantity: 1,
                expirationDate: DateTime.utc(2026, 8, 13),
              )
            ],
            receivedAt: now,
            storeId: 'store-1',
            branchId: 'main',
            deviceId: 'device-1',
          )),
      throwsA(isA<LocalizedDomainException>()),
    );
  });

  test('creates non-purchase batches and supports exact count and disposal',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 8, 14);
    final product = Product(
      id: 'made-food',
      name: 'Made food',
      code: 'MADE',
      price: 3,
      cost: 1,
      stock: 0,
      category: 'Food',
      expiryTrackingEnabled: true,
      storeId: 'store-1',
      branchId: 'main',
      createdAt: now,
      updatedAt: now,
    );
    await BusinessSqliteStore.upsertEntityPayloads(
      db,
      BusinessSqliteStore.productsKey,
      <Map<String, dynamic>>[product.toJson()],
    );
    final service = BatchInventoryService(db);
    await db.transaction(() async {
      await service.addStockInTransaction(
        product: product,
        warehouseId: 'main',
        sourceType: 'manufacturing_output',
        sourceId: 'mfg-1',
        expectedQuantity: 5,
        allocations: <BatchAllocation>[
          BatchAllocation(
            batchId: 'made-batch',
            quantity: 5,
            expirationDate: DateTime.utc(2026, 9, 14),
          ),
        ],
        receivedAt: now,
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'device-1',
      );
      await service.adjustSpecificBatchInTransaction(
        product: product,
        warehouseId: 'main',
        batchId: 'made-batch',
        quantityDelta: -2,
        adjustedAt: now,
        storeId: 'store-1',
        deviceId: 'device-1',
      );
      await service.setBatchStatusInTransaction(
        batchId: 'made-batch',
        status: 'blocked',
        updatedAt: now,
        storeId: 'store-1',
        deviceId: 'device-1',
      );
    });
    final row = await db.customSelect('''
      SELECT b.status, bb.quantity
      FROM inventory_batches b
      JOIN inventory_batch_balances bb ON bb.batch_id = b.id
      WHERE b.id = 'made-batch'
    ''').getSingle();
    expect(row.read<String>('status'), 'blocked');
    expect(row.read<double>('quantity'), 3);
    expect(
      () => db.transaction(() => service.allocateFefoInTransaction(
            product: product,
            warehouseId: 'main',
            quantity: 1,
            saleDate: now,
            storeId: 'store-1',
            deviceId: 'device-1',
          )),
      throwsA(isA<LocalizedDomainException>()),
    );
  });
}
