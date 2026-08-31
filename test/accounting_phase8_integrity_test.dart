import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/models/manufacturing.dart';
import 'package:ventio/models/purchase_item.dart';
import 'package:ventio/models/supplier.dart';

import 'phase5_manufacturing_transfer_test.dart' as support;

void main() {
  test('received purchase commits stock, Unified Batch, and journal together',
      () async {
    final store = await support.readyPhase5SqliteStore();
    await store.addOrUpdateProduct(support.phase5Product(
      id: 'raw-purchase-atomic',
      code: 'RAW-PA',
      stock: 0,
      cost: 0,
    ));
    await store.addOrUpdateSupplier(Supplier(
      id: 'supplier-purchase-atomic',
      name: 'Atomic Supplier',
      phone: '',
      address: '',
      notes: '',
    ));
    final warehouse =
        await store.createWarehouse(name: 'Atomic raw', code: 'AR');
    final purchase = await store.createPurchase(
      supplierId: 'supplier-purchase-atomic',
      supplierName: 'Atomic Supplier',
      receiveNow: true,
      paymentStatus: 'credit',
      paymentMethod: 'Credit',
      warehouseId: warehouse.id,
      warehouseName: warehouse.name,
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'raw-purchase-atomic',
          productName: 'Atomic Raw',
          quantity: 5,
          unitCost: 3,
        ),
      ],
    );

    final db = SqliteMigrationManager.database!;
    expect(
      await support.sqliteWarehouseQuantity(
        productId: 'raw-purchase-atomic',
        warehouseId: warehouse.id,
        storeId: store.appIdentity.storeId,
      ),
      closeTo(5, 0.0001),
    );
    final persisted = await db.customSelect('''
      SELECT
        (SELECT COUNT(*) FROM journal_entries
          WHERE reference_type = 'purchase' AND reference_id = ?) AS journals,
        (SELECT COALESCE(SUM(bb.quantity), 0)
          FROM inventory_batch_balances bb
          JOIN inventory_batches b ON b.id = bb.batch_id
          WHERE b.source_type = 'purchase' AND b.source_id = ?) AS batch_qty,
        (SELECT COALESCE(MIN(unit_cost), 0)
          FROM inventory_batches
          WHERE source_type = 'purchase' AND source_id = ?) AS batch_cost,
        (SELECT average_cost FROM product_costs
          WHERE product_id = ? AND deleted_at = '' LIMIT 1) AS average_cost
    ''', variables: <Variable<Object>>[
      Variable<String>(purchase.id),
      Variable<String>(purchase.id),
      Variable<String>(purchase.id),
      const Variable<String>('raw-purchase-atomic'),
    ]).getSingle();
    expect(persisted.read<int>('journals'), 1);
    expect((persisted.data['batch_qty'] as num).toDouble(), closeTo(5, 0.0001));
    expect((persisted.data['batch_cost'] as num).toDouble(), closeTo(3, 0.0001));
    expect(
      (persisted.data['average_cost'] as num).toDouble(),
      closeTo(3, 0.0001),
    );
  });

  test('failed manufacturing journal rolls back stock, order, and movements',
      () async {
    final store = await support.readyPhase5SqliteStore();
    await store.addOrUpdateProduct(support.phase5Product(
        id: 'raw-rollback', code: 'RAW-X', stock: 0, cost: 4));
    await store.addOrUpdateProduct(support.phase5Product(
        id: 'fg-rollback', code: 'FG-X', stock: 0, cost: 0));
    final raw = await store.createWarehouse(name: 'Raw rollback', code: 'RX');
    final finished =
        await store.createWarehouse(name: 'Finished rollback', code: 'FX');
    await store.adjustStock(
      productId: 'raw-rollback',
      warehouseId: raw.id,
      quantityDelta: 5,
      reason: 'Opening',
    );
    final bom = await store.createBillOfMaterials(
      name: 'Rollback BOM',
      outputProductId: 'fg-rollback',
      outputQuantity: 1,
      components: const <BillOfMaterialsLine>[
        BillOfMaterialsLine(
            productId: 'raw-rollback',
            productName: 'Raw rollback',
            quantity: 2),
      ],
    );
    final db = SqliteMigrationManager.database!;
    await db.customStatement('''
      CREATE TRIGGER fail_manufacturing_journal
      BEFORE INSERT ON journal_entries
      WHEN NEW.reference_type = 'manufacturing_order'
      BEGIN
        SELECT RAISE(ABORT, 'forced manufacturing journal failure');
      END;
    ''');

    await expectLater(
      store.completeManufacturingOrder(
        bomId: bom.id,
        quantity: 1,
        rawMaterialsWarehouseId: raw.id,
        finishedGoodsWarehouseId: finished.id,
      ),
      throwsA(anything),
    );
    await db
        .customStatement('DROP TRIGGER IF EXISTS fail_manufacturing_journal');
    expect(
      await support.sqliteWarehouseQuantity(
        productId: 'raw-rollback',
        warehouseId: raw.id,
        storeId: store.appIdentity.storeId,
      ),
      closeTo(5, 0.0001),
    );
    expect(
      await support.sqliteWarehouseQuantity(
        productId: 'fg-rollback',
        warehouseId: finished.id,
        storeId: store.appIdentity.storeId,
      ),
      closeTo(0, 0.0001),
    );
    expect(
      (await BusinessSqliteStore.readManufacturingOrders(db))
          .where((order) => order.bomId == bom.id),
      isEmpty,
    );
    final orphanMovements = await db.customSelect('''
      SELECT COUNT(*) AS count FROM stock_movements
      WHERE reference_id IN (
        SELECT id FROM manufacturing_orders WHERE bom_id = ?
      )
    ''', variables: <Variable<Object>>[
      Variable<String>(bom.id),
    ]).getSingle();
    expect(orphanMovements.read<int>('count'), 0);
  });

  test('schema 31 preserves manufacturing and reversal audit indexes', () async {
    await support.readyPhase5SqliteStore();
    final db = SqliteMigrationManager.database!;
    expect(db.schemaVersion, 31);
    final columns =
        await db.customSelect('PRAGMA table_info(manufacturing_orders)').get();
    final names = columns.map((row) => row.data['name']).toSet();
    expect(
        names,
        containsAll(<String>{
          'total_material_cost',
          'total_waste_cost',
          'actual_unit_cost',
          'material_costs_json',
          'journal_entry_id',
          'reversal_journal_entry_id',
          'reversal_reason',
        }));
    final journalColumns =
        await db.customSelect('PRAGMA table_info(journal_entries)').get();
    expect(
      journalColumns.map((row) => row.data['name']).toSet(),
      containsAll(<String>{
        'reversal_reason',
        'reversed_at',
        'reversed_by',
        'reversed_by_entry_id',
      }),
    );
  });
}
