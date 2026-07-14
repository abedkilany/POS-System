import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/repositories/inventory_reconciliation_repository.dart';
import 'package:ventio/core/repositories/warehouse_inventory_repository.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/core/services/stock_transaction_service.dart';
import 'package:ventio/models/warehouse_inventory.dart';

Future<VentioDriftDatabase> _openDb() async {
  final db = VentioDriftDatabase(NativeDatabase.memory());
  await db.initializeFoundation();
  return db;
}

Future<int> _countRows(
  VentioDriftDatabase db,
  String table, {
  String where = '1=1',
  List<Variable<Object>> variables = const <Variable<Object>>[],
}) async {
  final row = await db.customSelect(
    'SELECT COUNT(*) AS value FROM $table WHERE $where',
    variables: variables,
  ).getSingle();
  return row.read<int>('value');
}

void main() {
  test('backfill migrates legacy balances into warehouse_inventory', () async {
    final db = await _openDb();
    addTearDown(db.close);

    await db.customInsert(
      '''
      INSERT INTO products
        (id, entity_type, created_at, updated_at, deleted_at, device_id,
         sync_status, store_id, branch_id, version, last_modified_by_device_id,
         sort_index, name, stock)
      VALUES (?, 'product', ?, ?, '', '', 'synced', ?, 'main', 1, '', 0, ?, ?)
      ''',
      variables: <Variable<Object>>[
        const Variable<String>('p1'),
        const Variable<String>('2026-01-01T00:00:00.000Z'),
        const Variable<String>('2026-01-01T00:00:00.000Z'),
        const Variable<String>('store-1'),
        const Variable<String>('Coffee'),
        const Variable<double>(10),
      ],
    );
    await db.customInsert(
      '''
      INSERT INTO products
        (id, entity_type, created_at, updated_at, deleted_at, device_id,
         sync_status, store_id, branch_id, version, last_modified_by_device_id,
         sort_index, name, stock)
      VALUES (?, 'product', ?, ?, '', '', 'synced', ?, 'main', 1, '', 1, ?, ?)
      ''',
      variables: <Variable<Object>>[
        const Variable<String>('p2'),
        const Variable<String>('2026-01-01T00:00:00.000Z'),
        const Variable<String>('2026-01-01T00:00:00.000Z'),
        const Variable<String>('store-1'),
        const Variable<String>('Tea'),
        const Variable<double>(5),
      ],
    );
    await db.customInsert(
      '''
      INSERT INTO stock_movements
        (id, entity_type, created_at, updated_at, deleted_at, device_id,
         sync_status, store_id, branch_id, version, sort_index, product_id,
         product_name, movement_type, quantity, movement_date, reference_id,
         reference_no, reason, adjustment_category, notes, evidence_ref,
         warehouse_id, warehouse_name, movement_group_id, document_line_id,
         source_movement_id, reversal_of_movement_id, idempotency_key, unit_cost,
         last_modified_by_device_id, reviewed_at, reviewed_by, review_note)
      VALUES (?, 'stock_movement', ?, ?, '', '', 'synced', ?, 'main', 1, 0, ?,
              ?, 'purchase_receive', 4, ?, '', '', '', '', '', '', 'wh-1',
              'Warehouse 1', 'group-1', '', '', '', '', 0, '', '', '', '')
      ''',
      variables: <Variable<Object>>[
        const Variable<String>('m-1'),
        const Variable<String>('2026-01-02T00:00:00.000Z'),
        const Variable<String>('2026-01-02T00:00:00.000Z'),
        const Variable<String>('store-1'),
        const Variable<String>('p1'),
        const Variable<String>('Coffee'),
        const Variable<String>('2026-01-02T10:00:00.000Z'),
      ],
    );
    await db.customInsert(
      '''
      INSERT INTO stock_movements
        (id, entity_type, created_at, updated_at, deleted_at, device_id,
         sync_status, store_id, branch_id, version, sort_index, product_id,
         product_name, movement_type, quantity, movement_date, reference_id,
         reference_no, reason, adjustment_category, notes, evidence_ref,
         warehouse_id, warehouse_name, movement_group_id, document_line_id,
         source_movement_id, reversal_of_movement_id, idempotency_key, unit_cost,
         last_modified_by_device_id, reviewed_at, reviewed_by, review_note)
      VALUES (?, 'stock_movement', ?, ?, '', '', 'synced', ?, 'main', 1, 1, ?,
              ?, 'sale', -2, ?, '', '', '', '', '', '', '',
              'Main warehouse', 'group-2', '', '', '', '', 0, '', '', '', '')
      ''',
      variables: <Variable<Object>>[
        const Variable<String>('m-2'),
        const Variable<String>('2026-01-03T00:00:00.000Z'),
        const Variable<String>('2026-01-03T00:00:00.000Z'),
        const Variable<String>('store-1'),
        const Variable<String>('p1'),
        const Variable<String>('Coffee'),
        const Variable<String>('2026-01-03T10:00:00.000Z'),
      ],
    );

    await InventoryReconciliationRepository.backfillFromLegacyData(db);
    await InventoryReconciliationRepository.backfillFromLegacyData(db);

    final p1 = await WarehouseInventoryRepository.getByIdentity(
      db,
      storeId: 'store-1',
      warehouseId: 'wh-1',
      productId: 'p1',
    );
    final p1Main = await WarehouseInventoryRepository.getByIdentity(
      db,
      storeId: 'store-1',
      warehouseId: 'main',
      productId: 'p1',
    );
    final p2Main = await WarehouseInventoryRepository.getByIdentity(
      db,
      storeId: 'store-1',
      warehouseId: 'main',
      productId: 'p2',
    );
    final products = await BusinessSqliteStore.readProducts(db);
    final reconciliations = await InventoryReconciliationRepository.listAll(db);

    expect(p1?.quantity, 4);
    expect(p1Main?.quantity, 6);
    expect(p2Main?.quantity, 5);
    expect(products.firstWhere((item) => item.id == 'p1').stock, 10);
    expect(products.firstWhere((item) => item.id == 'p2').stock, 5);
    expect(reconciliations, hasLength(2));
    expect(
      reconciliations.map((item) => item.classification),
      containsAll(<String>['missing_warehouse', 'legacy_unassigned']),
    );
    expect(await _countRows(db, 'warehouse_inventory'), 3);
  });

  test('backfill skips an already-applied migration adjustment on rerun', () async {
    final db = await _openDb();
    addTearDown(db.close);

    await db.customInsert(
      '''
      INSERT INTO products
        (id, entity_type, created_at, updated_at, deleted_at, device_id,
         sync_status, store_id, branch_id, version, last_modified_by_device_id,
         sort_index, name, stock)
      VALUES (?, 'product', ?, ?, '', '', 'synced', ?, 'main', 1, '', 0, ?, ?)
      ''',
      variables: <Variable<Object>>[
        const Variable<String>('p1'),
        const Variable<String>('2026-01-01T00:00:00.000Z'),
        const Variable<String>('2026-01-01T00:00:00.000Z'),
        const Variable<String>('store-1'),
        const Variable<String>('Coffee'),
        const Variable<double>(10),
      ],
    );
    await db.customInsert(
      '''
      INSERT INTO stock_movements
        (id, entity_type, created_at, updated_at, deleted_at, device_id,
         sync_status, store_id, branch_id, version, sort_index, product_id,
         product_name, movement_type, quantity, movement_date, reference_id,
         reference_no, reason, adjustment_category, notes, evidence_ref,
         warehouse_id, warehouse_name, movement_group_id, document_line_id,
         source_movement_id, reversal_of_movement_id, idempotency_key, unit_cost,
         last_modified_by_device_id, reviewed_at, reviewed_by, review_note)
      VALUES (?, 'stock_movement', ?, ?, '', '', 'synced', ?, 'main', 1, 0, ?,
              ?, 'purchase_receive', 4, ?, '', '', '', '', '', '', 'wh-1',
              'Warehouse 1', 'group-1', '', '', '', '', 0, '', '', '', '')
      ''',
      variables: <Variable<Object>>[
        const Variable<String>('m-1'),
        const Variable<String>('2026-01-02T00:00:00.000Z'),
        const Variable<String>('2026-01-02T00:00:00.000Z'),
        const Variable<String>('store-1'),
        const Variable<String>('p1'),
        const Variable<String>('Coffee'),
        const Variable<String>('2026-01-02T10:00:00.000Z'),
      ],
    );

    final timestamp = DateTime.utc(2026, 1, 3);
    await WarehouseInventoryRepository.upsert(
      db,
      WarehouseInventory(
        id: 'wi_store-1_wh-1_p1',
        storeId: 'store-1',
        branchId: 'main',
        warehouseId: 'wh-1',
        productId: 'p1',
        quantity: 4,
        createdAt: timestamp,
        updatedAt: timestamp,
        deviceId: '',
        syncStatus: 'synced',
        lastModifiedByDeviceId: '',
      ),
    );
    await WarehouseInventoryRepository.upsert(
      db,
      WarehouseInventory(
        id: 'wi_store-1_main_p1',
        storeId: 'store-1',
        branchId: 'main',
        warehouseId: 'main',
        productId: 'p1',
        quantity: 6,
        createdAt: timestamp,
        updatedAt: timestamp,
        deviceId: '',
        syncStatus: 'synced',
        lastModifiedByDeviceId: '',
      ),
    );
    await db.customInsert(
      '''
      INSERT INTO inventory_migration_adjustments
        (id, migration_batch_id, store_id, branch_id, warehouse_id,
         product_id, legacy_product_stock, ledger_balance, applied_delta,
         created_at, updated_at, notes)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: <Variable<Object>>[
        const Variable<String>(
          'adj_warehouse_inventory_backfill_adjustment_v1_store-1_main_p1',
        ),
        Variable<String>(InventoryReconciliationRepository.backfillBatchId),
        const Variable<String>('store-1'),
        const Variable<String>('main'),
        const Variable<String>('main'),
        const Variable<String>('p1'),
        const Variable<double>(10),
        const Variable<double>(4),
        const Variable<double>(6),
        const Variable<String>('2026-01-03T00:00:00.000Z'),
        const Variable<String>('2026-01-03T00:00:00.000Z'),
        const Variable<String>('backfill_adjustment'),
      ],
    );

    await InventoryReconciliationRepository.backfillFromLegacyData(db);

    final main = await WarehouseInventoryRepository.getByIdentity(
      db,
      storeId: 'store-1',
      warehouseId: 'main',
      productId: 'p1',
    );
    expect(main?.quantity, 6);
    expect(await _countRows(db, 'inventory_migration_adjustments'), 1);
  });

  test('read model stops falling back to legacy stock after backfill completes', () async {
    final db = await _openDb();
    addTearDown(db.close);

    await db.customInsert(
      '''
      INSERT INTO products
        (id, entity_type, created_at, updated_at, deleted_at, device_id,
         sync_status, store_id, branch_id, version, last_modified_by_device_id,
         sort_index, name, stock)
      VALUES (?, 'product', ?, ?, '', '', 'synced', ?, 'main', 1, '', 0, ?, ?)
      ''',
      variables: <Variable<Object>>[
        const Variable<String>('p2'),
        const Variable<String>('2026-01-01T00:00:00.000Z'),
        const Variable<String>('2026-01-01T00:00:00.000Z'),
        const Variable<String>('store-1'),
        const Variable<String>('Tea'),
        const Variable<double>(12),
      ],
    );

    await InventoryReconciliationRepository.backfillFromLegacyData(db);
    await db.customStatement(
      'DELETE FROM warehouse_inventory WHERE store_id = ? AND warehouse_id = ? AND product_id = ?',
      <Object?>['store-1', 'main', 'p2'],
    );

    final product = await BusinessSqliteStore.readProductById(db, 'p2');
    final integrity = await StockTransactionService(db).checkIntegrity(
      storeId: 'store-1',
    );

    expect(product?.stock, 0);
    expect(
      integrity.issues.any((issue) =>
          issue.productId == 'p2' &&
          issue.classification == 'legacy_unassigned'),
      isTrue,
    );
  });
}
