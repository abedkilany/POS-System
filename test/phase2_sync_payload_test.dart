import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/snapshot/unified_snapshot.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/models/stock_movement.dart';

Future<VentioDriftDatabase> _openDb() async {
  final db = VentioDriftDatabase(NativeDatabase.memory());
  await db.initializeFoundation();
  return db;
}

void main() {
  test('warehouse_inventory schema exposes the expected uniqueness guard',
      () async {
    final db = await _openDb();
    addTearDown(db.close);

    final tableInfo = await db.customSelect('PRAGMA table_info(warehouse_inventory);').get();
    final columns = tableInfo.map((row) => row.read<String>('name')).toSet();

    expect(
      columns,
      containsAll(<String>[
        'id',
        'store_id',
        'branch_id',
        'warehouse_id',
        'product_id',
        'quantity',
        'version',
        'created_at',
        'updated_at',
        'device_id',
        'sync_status',
        'last_modified_by_device_id',
      ]),
    );

    final schemaRows = await db.customSelect('''
      SELECT sql
      FROM sqlite_master
      WHERE type = 'table' AND name = 'warehouse_inventory'
      LIMIT 1
    ''').get();
    expect(
      schemaRows.single.read<String>('sql'),
      contains('UNIQUE(store_id, warehouse_id, product_id)'),
    );
  });

  test('StockMovement round trip preserves warehouse-aware replay fields', () {
    final movement = StockMovement(
      id: 'm-1',
      productId: 'p-1',
      productName: 'Coffee',
      type: 'sale',
      quantity: -2,
      date: DateTime.utc(2026, 1, 1, 10),
      warehouseId: 'wh-1',
      warehouseName: 'Main',
      movementGroupId: 'group-1',
      documentLineId: 'line-1',
      sourceMovementId: 'src-1',
      reversalOfMovementId: 'rev-1',
      idempotencyKey: 'idem-1',
    );

    final decoded = StockMovement.fromJson(movement.toJson());

    expect(decoded.warehouseId, 'wh-1');
    expect(decoded.warehouseName, 'Main');
    expect(decoded.movementGroupId, 'group-1');
    expect(decoded.documentLineId, 'line-1');
    expect(decoded.sourceMovementId, 'src-1');
    expect(decoded.reversalOfMovementId, 'rev-1');
    expect(decoded.idempotencyKey, 'idem-1');
  });

  test('unified snapshot inventory section includes warehouse-aware tables', () {
    final collections = UnifiedSnapshotCatalog.inventoryMovements.collections;
    expect(collections, contains('warehouseInventory'));
    expect(collections, contains('stockOperations'));
    expect(collections, contains('inventoryReconciliations'));
    expect(collections, contains('inventoryMigrationAdjustments'));
  });
}
