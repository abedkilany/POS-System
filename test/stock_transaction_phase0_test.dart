import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/repositories/warehouse_inventory_repository.dart';
import 'package:ventio/core/services/stock_transaction_service.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/models/stock_movement.dart';
import 'package:ventio/models/warehouse_inventory.dart';

Future<VentioDriftDatabase> _openDb() async {
  final db = VentioDriftDatabase(NativeDatabase.memory());
  await db.initializeFoundation();
  return db;
}

Future<VentioDriftDatabase> _openFileDb(String path) async {
  final db = VentioDriftDatabase(NativeDatabase(File(path)));
  await db.initializeFoundation();
  return db;
}

Future<String> _createTempDbPath() async {
  final dir = await Directory.systemTemp.createTemp('ventio_phase0_');
  return '${dir.path}${Platform.pathSeparator}phase0.sqlite';
}

Future<void> _ensureOldStockMovementSchema(VentioDriftDatabase db) async {
  await db.customStatement('''
    CREATE TABLE IF NOT EXISTS stock_movements (
      id TEXT PRIMARY KEY NOT NULL,
      entity_type TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT NOT NULL DEFAULT '',
      device_id TEXT NOT NULL DEFAULT '',
      sync_status TEXT NOT NULL DEFAULT '',
      store_id TEXT NOT NULL DEFAULT '',
      branch_id TEXT NOT NULL DEFAULT '',
      version INTEGER NOT NULL DEFAULT 1,
      sort_index INTEGER NOT NULL DEFAULT 0,
      product_id TEXT NOT NULL DEFAULT '',
      product_name TEXT NOT NULL DEFAULT '',
      movement_type TEXT NOT NULL DEFAULT '',
      quantity REAL NOT NULL DEFAULT 0,
      movement_date TEXT NOT NULL DEFAULT '',
      reference_id TEXT NOT NULL DEFAULT '',
      reference_no TEXT NOT NULL DEFAULT '',
      reason TEXT NOT NULL DEFAULT '',
      adjustment_category TEXT NOT NULL DEFAULT '',
      notes TEXT NOT NULL DEFAULT '',
      evidence_ref TEXT NOT NULL DEFAULT '',
      warehouse_id TEXT NOT NULL DEFAULT 'main',
      warehouse_name TEXT NOT NULL DEFAULT 'Main warehouse',
      unit_cost REAL NOT NULL DEFAULT 0,
      last_modified_by_device_id TEXT NOT NULL DEFAULT ''
    );
  ''');
  await db.customInsert(
    '''
    INSERT INTO stock_movements
      (id, entity_type, created_at, updated_at, deleted_at, device_id,
       sync_status, store_id, branch_id, version, sort_index, product_id,
       product_name, movement_type, quantity, movement_date, reference_id,
       reference_no, reason, adjustment_category, notes, evidence_ref,
       warehouse_id, warehouse_name, unit_cost, last_modified_by_device_id)
    VALUES (?, 'stock_movement', ?, ?, '', '', 'synced', 'store-1', 'main', 1,
            0, ?, ?, ?, ?, ?, '', '', '', '', '', '', 'main',
            'Main warehouse', 0, '')
    ''',
    variables: <Variable<Object>>[
      Variable<String>('legacy-move-1'),
      Variable<String>('2026-01-01T00:00:00.000Z'),
      Variable<String>('2026-01-01T00:00:00.000Z'),
      Variable<String>('p1'),
      Variable<String>('Coffee'),
      Variable<String>('sale'),
      Variable<double>(-2),
      Variable<String>('2026-01-01T10:00:00.000Z'),
    ],
  );
}

Future<void> _ensureSyncQueueSchema(VentioDriftDatabase db) async {
  await db.customStatement('''
    CREATE TABLE IF NOT EXISTS sync_queue (
      id TEXT PRIMARY KEY NOT NULL,
      change_id TEXT NOT NULL,
      target TEXT NOT NULL,
      status TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT NOT NULL DEFAULT '',
      next_retry_at TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
  ''');
}

Future<int> _rowCount(
  VentioDriftDatabase db,
  String table, {
  String where = '1=1',
  List<Variable<Object>> variables = const <Variable<Object>>[],
}) async {
  final rows = await db.customSelect(
    'SELECT COUNT(*) AS value FROM $table WHERE $where',
    variables: variables,
  ).getSingle();
  return rows.read<int>('value');
}

void main() {
  test('creates a warehouse balance and reads it back', () async {
    final db = await _openDb();
    addTearDown(db.close);

    final service = StockTransactionService(db, defaultStoreId: 'store-1');
    final inventory = await service.applyDelta(
      storeId: 'store-1',
      warehouseId: 'wh-1',
      productId: 'p1',
      delta: 7,
      branchId: 'main',
      deviceId: 'dev-1',
    );

    expect(inventory.quantity, 7);
    final fetched = await WarehouseInventoryRepository.getByIdentity(
      db,
      storeId: 'store-1',
      warehouseId: 'wh-1',
      productId: 'p1',
    );
    expect(fetched, isNotNull);
    expect(fetched!.quantity, 7);
    expect(fetched.uniqueKey, 'store-1::wh-1::p1');
  });

  test('rejects duplicate store warehouse product rows', () async {
    final db = await _openDb();
    addTearDown(db.close);

    await WarehouseInventoryRepository.upsert(
      db,
      WarehouseInventory(
        id: 'wi-1',
        storeId: 'store-1',
        branchId: 'main',
        warehouseId: 'wh-1',
        productId: 'p1',
        quantity: 1,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    expect(
      () => db.customInsert(
        '''
        INSERT INTO warehouse_inventory
          (id, store_id, branch_id, warehouse_id, product_id, quantity,
           version, created_at, updated_at, device_id, sync_status,
           last_modified_by_device_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>('wi-2'),
          Variable<String>('store-1'),
          Variable<String>('main'),
          Variable<String>('wh-1'),
          Variable<String>('p1'),
          Variable<double>(2),
          Variable<int>(1),
          Variable<String>('2026-01-01T00:00:00.000Z'),
          Variable<String>('2026-01-01T00:00:00.000Z'),
          Variable<String>('dev-1'),
          Variable<String>('pending'),
          Variable<String>('dev-1'),
        ],
      ),
      throwsException,
    );
  });

  test('rolls back the full transaction if sync queue insert fails', () async {
    final db = await _openDb();
    addTearDown(db.close);

    await db.customStatement('DROP TABLE sync_queue;');
    final service = StockTransactionService(db, defaultStoreId: 'store-1');

    final movement = StockMovement(
      id: 'm-rollback',
      productId: 'p1',
      productName: 'Coffee',
      type: 'purchase_receive',
      quantity: 3,
      date: DateTime.utc(2026, 1, 1, 10),
      warehouseId: 'wh-1',
      movementGroupId: 'group-rollback',
      idempotencyKey: 'op-rollback:m-rollback',
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );

    await expectLater(
      service.recordMovementsAtomically(
        operationType: 'purchase_receive',
        documentType: 'purchase',
        documentId: 'po-1',
        movementGroupId: 'group-rollback',
        idempotencyKey: 'op-rollback',
        movements: <StockMovement>[movement],
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'dev-1',
      ),
      throwsException,
    );

    expect(await _rowCount(db, 'warehouse_inventory'), 0);
    expect(await _rowCount(db, 'stock_movements'), 0);
    expect(await _rowCount(db, 'stock_operations'), 1);
    expect(await _rowCount(db, 'sync_events'), 0);

    final statusRow = await db.customSelect(
      'SELECT status, failure_reason FROM stock_operations WHERE id = ?',
      variables: <Variable<Object>>[
        const Variable<String>('op-rollback'),
      ],
    ).getSingle();
    expect(statusRow.read<String>('status'), 'failed');
    expect(statusRow.read<String>('failure_reason'), isNotEmpty);
  });

  test('does not apply the same idempotency key twice', () async {
    final db = await _openDb();
    addTearDown(db.close);

    final service = StockTransactionService(db, defaultStoreId: 'store-1');
    final movement = StockMovement(
      id: 'm-1',
      productId: 'p1',
      productName: 'Coffee',
      type: 'purchase_receive',
      quantity: 5,
      date: DateTime.utc(2026, 1, 1, 10),
      warehouseId: 'wh-1',
      movementGroupId: 'group-1',
      idempotencyKey: 'op-1:m-1',
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );

    final first = await service.recordMovementsAtomically(
      operationType: 'purchase_receive',
      documentType: 'purchase',
      documentId: 'po-1',
      movementGroupId: 'group-1',
      idempotencyKey: 'op-1',
      movements: <StockMovement>[movement],
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );
    final second = await service.recordMovementsAtomically(
      operationType: 'purchase_receive',
      documentType: 'purchase',
      documentId: 'po-1',
      movementGroupId: 'group-1',
      idempotencyKey: 'op-1',
      movements: <StockMovement>[movement],
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );

    expect(first.movementIds, hasLength(1));
    expect(second.movementIds, hasLength(1));
    expect(second.movementIds.single, first.movementIds.single);
    expect(await _rowCount(db, 'warehouse_inventory'), 1);
    expect(await _rowCount(db, 'stock_movements'), 1);
    expect(await _rowCount(db, 'stock_operations'), 1);
    expect(await _rowCount(db, 'sync_events'), 1);
  });

  test('duplicate movement idempotency key does not re-apply balance', () async {
    final db = await _openDb();
    addTearDown(db.close);

    final service = StockTransactionService(db, defaultStoreId: 'store-1');
    final movement = StockMovement(
      id: 'm-dup',
      productId: 'p1',
      productName: 'Coffee',
      type: 'purchase_receive',
      quantity: 4,
      date: DateTime.utc(2026, 1, 1, 10),
      warehouseId: 'wh-1',
      movementGroupId: 'group-dup',
      idempotencyKey: 'movement-key-1',
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );

    await service.recordMovementsAtomically(
      operationType: 'purchase_receive',
      documentType: 'purchase',
      documentId: 'po-1',
      movementGroupId: 'group-dup',
      idempotencyKey: 'op-dup-1',
      movements: <StockMovement>[movement],
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );

    final before = await db.customSelect(
      'SELECT updated_at FROM stock_movements WHERE id = ?',
      variables: <Variable<Object>>[
        const Variable<String>('m-dup'),
      ],
    ).getSingle();

    final receipt = await service.recordMovementsAtomically(
      operationType: 'purchase_receive',
      documentType: 'purchase',
      documentId: 'po-2',
      movementGroupId: 'group-dup-2',
      idempotencyKey: 'op-dup-2',
      movements: <StockMovement>[
        movement.copyWith(
          type: 'purchase_receive',
          idempotencyKey: 'movement-key-1',
          movementGroupId: 'group-dup-2',
        ),
      ],
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );

    final after = await db.customSelect(
      'SELECT updated_at FROM stock_movements WHERE id = ?',
      variables: <Variable<Object>>[
        const Variable<String>('m-dup'),
      ],
    ).getSingle();

    expect(receipt.movementIds, hasLength(1));
    expect(await _rowCount(db, 'stock_movements'), 1);
    expect(await _rowCount(db, 'warehouse_inventory'), 1);
    expect(after.read<String>('updated_at'), before.read<String>('updated_at'));
  });

  test('concurrent duplicate operations do not double-apply stock', () async {
    final db = await _openDb();
    addTearDown(db.close);

    final service = StockTransactionService(db, defaultStoreId: 'store-1');
    final movement = StockMovement(
      id: 'm-concurrent',
      productId: 'p1',
      productName: 'Coffee',
      type: 'purchase_receive',
      quantity: 2,
      date: DateTime.utc(2026, 1, 1, 10),
      warehouseId: 'wh-1',
      movementGroupId: 'group-concurrent',
      idempotencyKey: 'movement-concurrent',
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );

    Future<Object> capture(Future<StockTransactionReceipt> future) async {
      try {
        return await future;
      } catch (error) {
        return error;
      }
    }

    final results = await Future.wait<Object>([
      capture(
        service.recordMovementsAtomically(
          operationType: 'purchase_receive',
          documentType: 'purchase',
          documentId: 'po-concurrent',
          movementGroupId: 'group-concurrent',
          idempotencyKey: 'op-concurrent',
          movements: <StockMovement>[movement],
          storeId: 'store-1',
          branchId: 'main',
          deviceId: 'dev-1',
        ),
      ),
      capture(
        service.recordMovementsAtomically(
          operationType: 'purchase_receive',
          documentType: 'purchase',
          documentId: 'po-concurrent',
          movementGroupId: 'group-concurrent',
          idempotencyKey: 'op-concurrent',
          movements: <StockMovement>[movement],
          storeId: 'store-1',
          branchId: 'main',
          deviceId: 'dev-1',
        ),
      ),
    ]);

    expect(await _rowCount(db, 'warehouse_inventory'), 1);
    expect(await _rowCount(db, 'stock_movements'), 1);
    expect(results.whereType<StockTransactionReceipt>().isNotEmpty, isTrue);
  });

  test('completed operation is replay-safe after reopening the database', () async {
    final path = await _createTempDbPath();
    final db = await _openFileDb(path);

    final service = StockTransactionService(db, defaultStoreId: 'store-1');
    final receipt = await service.recordMovementsAtomically(
      operationType: 'purchase_receive',
      documentType: 'purchase',
      documentId: 'po-file-1',
      movementGroupId: 'group-file-1',
      idempotencyKey: 'op-file-1',
      movements: <StockMovement>[
        StockMovement(
          id: 'm-file-1',
          productId: 'p1',
          productName: 'Coffee',
          type: 'purchase_receive',
          quantity: 3,
          date: DateTime.utc(2026, 1, 1, 10),
          warehouseId: 'wh-1',
          movementGroupId: 'group-file-1',
          idempotencyKey: 'movement-file-1',
          storeId: 'store-1',
          branchId: 'main',
          deviceId: 'dev-1',
        ),
      ],
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );
    await db.close();

    final reopened = await _openFileDb(path);
    final replayService = StockTransactionService(reopened, defaultStoreId: 'store-1');
    final replay = await replayService.recordMovementsAtomically(
      operationType: 'purchase_receive',
      documentType: 'purchase',
      documentId: 'po-file-1',
      movementGroupId: 'group-file-1',
      idempotencyKey: 'op-file-1',
      movements: <StockMovement>[
        StockMovement(
          id: 'm-file-1',
          productId: 'p1',
          productName: 'Coffee',
          type: 'purchase_receive',
          quantity: 3,
          date: DateTime.utc(2026, 1, 1, 10),
          warehouseId: 'wh-1',
          movementGroupId: 'group-file-1',
          idempotencyKey: 'movement-file-1',
          storeId: 'store-1',
          branchId: 'main',
          deviceId: 'dev-1',
        ),
      ],
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );

    expect(replay.movementIds, receipt.movementIds);
    expect(await _rowCount(reopened, 'stock_movements'), 1);
    expect(await _rowCount(reopened, 'stock_operations'), 1);
    await reopened.close();
  });

  test('pending stale operations can be recovered safely', () async {
    final db = await _openDb();
    addTearDown(db.close);

    await db.customInsert(
      '''
      INSERT INTO stock_operations
        (id, store_id, branch_id, operation_type, document_type, document_id,
         movement_group_id, idempotency_key, status, created_at, started_at,
         updated_at, completed_at, failure_reason, attempt_count, device_id,
         last_modified_by_device_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?, '', '', 1, '', '')
      ''',
      variables: <Variable<Object>>[
        const Variable<String>('op-stale'),
        const Variable<String>('store-1'),
        const Variable<String>('main'),
        const Variable<String>('purchase_receive'),
        const Variable<String>('purchase'),
        const Variable<String>('po-stale'),
        const Variable<String>('group-stale'),
        const Variable<String>('op-stale'),
        const Variable<String>('2026-01-01T00:00:00.000Z'),
        const Variable<String>('2026-01-01T00:00:00.000Z'),
        const Variable<String>('2026-01-01T00:00:00.000Z'),
      ],
    );

    final service = StockTransactionService(db, defaultStoreId: 'store-1');
    final receipt = await service.recordMovementsAtomically(
      operationType: 'purchase_receive',
      documentType: 'purchase',
      documentId: 'po-stale',
      movementGroupId: 'group-stale',
      idempotencyKey: 'op-stale',
      movements: <StockMovement>[
        StockMovement(
          id: 'm-stale',
          productId: 'p1',
          productName: 'Coffee',
          type: 'purchase_receive',
          quantity: 5,
          date: DateTime.utc(2026, 1, 1, 10),
          warehouseId: 'wh-1',
          movementGroupId: 'group-stale',
          idempotencyKey: 'movement-stale',
          storeId: 'store-1',
          branchId: 'main',
          deviceId: 'dev-1',
        ),
      ],
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );

    expect(receipt.movementIds, hasLength(1));
    final row = await db.customSelect(
      'SELECT status FROM stock_operations WHERE id = ?',
      variables: <Variable<Object>>[
        const Variable<String>('op-stale'),
      ],
    ).getSingle();
    expect(row.read<String>('status'), 'completed');
  });

  test('failed operations can be retried safely', () async {
    final db = await _openDb();
    addTearDown(db.close);

    final service = StockTransactionService(db, defaultStoreId: 'store-1');
    await service.applyDelta(
      storeId: 'store-1',
      warehouseId: 'wh-1',
      productId: 'p1',
      delta: 10,
      branchId: 'main',
      deviceId: 'dev-1',
    );

    await db.customStatement('DROP TABLE sync_queue;');
    final movement = StockMovement(
      id: 'm-failed',
      productId: 'p1',
      productName: 'Coffee',
      type: 'purchase_receive',
      quantity: 4,
      date: DateTime.utc(2026, 1, 1, 10),
      warehouseId: 'wh-1',
      movementGroupId: 'group-failed',
      idempotencyKey: 'movement-failed',
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );

    await expectLater(
      service.recordMovementsAtomically(
        operationType: 'purchase_receive',
        documentType: 'purchase',
        documentId: 'po-failed',
        movementGroupId: 'group-failed',
        idempotencyKey: 'op-failed',
        movements: <StockMovement>[movement],
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'dev-1',
      ),
      throwsException,
    );

    final failedRow = await db.customSelect(
      'SELECT status, failure_reason FROM stock_operations WHERE id = ?',
      variables: <Variable<Object>>[
        const Variable<String>('op-failed'),
      ],
    ).getSingle();
    expect(failedRow.read<String>('status'), 'failed');
    expect(failedRow.read<String>('failure_reason'), isNotEmpty);

    await _ensureSyncQueueSchema(db);

    final retry = await service.recordMovementsAtomically(
      operationType: 'purchase_receive',
      documentType: 'purchase',
      documentId: 'po-failed',
      movementGroupId: 'group-failed',
      idempotencyKey: 'op-failed',
      movements: <StockMovement>[movement],
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );

    expect(retry.movementIds, hasLength(1));
    final completedRow = await db.customSelect(
      'SELECT status FROM stock_operations WHERE id = ?',
      variables: <Variable<Object>>[
        const Variable<String>('op-failed'),
      ],
    ).getSingle();
    expect(completedRow.read<String>('status'), 'completed');
  });

  test('records multiple movements under one movement group', () async {
    final db = await _openDb();
    addTearDown(db.close);

    final service = StockTransactionService(db, defaultStoreId: 'store-1');
    await service.applyDelta(
      storeId: 'store-1',
      warehouseId: 'wh-source',
      productId: 'p1',
      delta: 10,
      branchId: 'main',
      deviceId: 'dev-1',
    );
    final receipt = await service.recordMovementsAtomically(
      operationType: 'transfer',
      documentType: 'transfer',
      documentId: 'tr-1',
      movementGroupId: 'group-transfer',
      idempotencyKey: 'op-transfer',
      movements: <StockMovement>[
        StockMovement(
          id: 'm-out',
          productId: 'p1',
          productName: 'Coffee',
          type: 'transfer_out',
          quantity: -2,
          date: DateTime.utc(2026, 1, 1, 10),
          warehouseId: 'wh-source',
          movementGroupId: 'group-transfer',
          idempotencyKey: 'op-transfer:m-out',
          storeId: 'store-1',
          branchId: 'main',
          deviceId: 'dev-1',
        ),
        StockMovement(
          id: 'm-in',
          productId: 'p1',
          productName: 'Coffee',
          type: 'transfer_in',
          quantity: 2,
          date: DateTime.utc(2026, 1, 1, 10),
          warehouseId: 'wh-dest',
          movementGroupId: 'group-transfer',
          idempotencyKey: 'op-transfer:m-in',
          storeId: 'store-1',
          branchId: 'main',
          deviceId: 'dev-1',
        ),
      ],
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );

    expect(receipt.movementIds, hasLength(2));

    final groupRows = await db.customSelect(
      'SELECT COUNT(*) AS value FROM stock_movements WHERE movement_group_id = ?',
      variables: <Variable<Object>>[
        Variable<String>('group-transfer'),
      ],
    ).getSingle();
    expect(groupRows.read<int>('value'), 2);
  });

  test('creates reversals linked to the original movement', () async {
    final db = await _openDb();
    addTearDown(db.close);

    final service = StockTransactionService(db, defaultStoreId: 'store-1');
    await service.applyDelta(
      storeId: 'store-1',
      warehouseId: 'wh-1',
      productId: 'p1',
      delta: 10,
      branchId: 'main',
      deviceId: 'dev-1',
    );
    final original = StockMovement(
      id: 'm-original',
      productId: 'p1',
      productName: 'Coffee',
      type: 'sale',
      quantity: -4,
      date: DateTime.utc(2026, 1, 1, 10),
      warehouseId: 'wh-1',
      movementGroupId: 'group-sale',
      idempotencyKey: 'op-sale:m-original',
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );

    await service.recordMovementsAtomically(
      operationType: 'sale',
      documentType: 'sale',
      documentId: 'sale-1',
      movementGroupId: 'group-sale',
      idempotencyKey: 'op-sale',
      movements: <StockMovement>[original],
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );

    final reversal = await service.recordReversal(
      originalMovement: original,
      operationType: 'sale_reversal',
      documentType: 'sale',
      documentId: 'sale-1',
      reason: 'Customer return',
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );

    expect(reversal.movementIds, hasLength(1));

    final rows = await db.customSelect(
      '''
      SELECT id, source_movement_id, reversal_of_movement_id, movement_group_id, quantity
      FROM stock_movements
      WHERE movement_group_id = ?
      ORDER BY id ASC
      ''',
      variables: <Variable<Object>>[
        Variable<String>('reversal-m-original'),
      ],
    ).get();
    expect(rows, hasLength(1));
    expect(rows.single.read<String>('source_movement_id'), 'm-original');
    expect(rows.single.read<String>('reversal_of_movement_id'), 'm-original');
    expect(rows.single.read<double>('quantity'), 4);
  });

  test('supports legacy and new stock movement JSON payloads', () {
    final legacy = StockMovement.fromJson(<String, dynamic>{
      'id': 'legacy-1',
      'productId': 'p1',
      'productName': 'Coffee',
      'type': 'sale',
      'quantity': -2,
      'date': '2026-01-01T10:00:00.000Z',
    });
    expect(legacy.movementGroupId, isEmpty);
    expect(legacy.idempotencyKey, isEmpty);

    final modern = StockMovement(
      id: 'modern-1',
      productId: 'p1',
      productName: 'Coffee',
      type: 'purchase_receive',
      quantity: 2,
      date: DateTime.utc(2026, 1, 1, 10),
      warehouseId: 'wh-1',
      movementGroupId: 'group-modern',
      documentLineId: 'line-1',
      sourceMovementId: 'src-1',
      reversalOfMovementId: 'rev-1',
      idempotencyKey: 'op-modern:1',
      storeId: 'store-1',
      branchId: 'main',
      deviceId: 'dev-1',
    );
    final decoded = StockMovement.fromJson(modern.toJson());

    expect(decoded.movementGroupId, 'group-modern');
    expect(decoded.documentLineId, 'line-1');
    expect(decoded.sourceMovementId, 'src-1');
    expect(decoded.reversalOfMovementId, 'rev-1');
    expect(decoded.idempotencyKey, 'op-modern:1');
  });

  test('initialization is idempotent and keeps existing balances intact', () async {
    final db = await _openDb();
    addTearDown(db.close);

    final service = StockTransactionService(db, defaultStoreId: 'store-1');
    await service.applyDelta(
      storeId: 'store-1',
      warehouseId: 'wh-1',
      productId: 'p1',
      delta: 6,
      branchId: 'main',
      deviceId: 'dev-1',
    );

    await db.initializeFoundation();
    await db.initializeFoundation();

    expect(
      await _rowCount(
        db,
        'warehouse_inventory',
        where: 'store_id = ? AND warehouse_id = ? AND product_id = ?',
        variables: const <Variable<Object>>[
          Variable<String>('store-1'),
          Variable<String>('wh-1'),
          Variable<String>('p1'),
        ],
      ),
      1,
    );
    expect(
      await WarehouseInventoryRepository.getByIdentity(
        db,
        storeId: 'store-1',
        warehouseId: 'wh-1',
        productId: 'p1',
      ),
      isNotNull,
    );
  });

  test('integrity checker reports mismatch without mutating data', () async {
    final db = await _openDb();
    addTearDown(db.close);

    await db.customInsert(
      '''
      INSERT INTO products
        (id, entity_type, created_at, updated_at, deleted_at, device_id,
         sync_status, store_id, branch_id, version, last_modified_by_device_id,
         sort_index, name, stock)
      VALUES (?, 'product', ?, ?, '', '', 'synced', ?, ?, 1, '', 0, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>('p1'),
        Variable<String>('2026-01-01T00:00:00.000Z'),
        Variable<String>('2026-01-01T00:00:00.000Z'),
        Variable<String>('store-1'),
        Variable<String>('main'),
        Variable<String>('Coffee'),
        Variable<double>(5),
      ],
    );

    final service = StockTransactionService(db, defaultStoreId: 'store-1');
    await service.applyDelta(
      storeId: 'store-1',
      warehouseId: 'wh-1',
      productId: 'p1',
      delta: 3,
      branchId: 'main',
      deviceId: 'dev-1',
    );

    final before = await WarehouseInventoryRepository.getByIdentity(
      db,
      storeId: 'store-1',
      warehouseId: 'wh-1',
      productId: 'p1',
    );
    final report = await service.checkIntegrity(storeId: 'store-1');
    final after = await WarehouseInventoryRepository.getByIdentity(
      db,
      storeId: 'store-1',
      warehouseId: 'wh-1',
      productId: 'p1',
    );

    expect(report.ok, isFalse);
    expect(report.issues, isNotEmpty);
    expect(report.issues.first.classification, isNotEmpty);
    expect(before?.quantity, after?.quantity);
  });

  test('migrates an old schema and keeps legacy stock movements readable', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await _ensureOldStockMovementSchema(db);
    await db.initializeFoundation();

    final movementRows = await BusinessSqliteStore.readStockMovements(db);
    expect(movementRows, hasLength(1));
    expect(movementRows.single.idempotencyKey, isEmpty);
    expect(movementRows.single.movementGroupId, isEmpty);

    final warehouseInfo = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'warehouse_inventory'",
        )
        .get();
    expect(warehouseInfo, isNotEmpty);

    final stockOperationsInfo = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'stock_operations'",
        )
        .get();
    expect(stockOperationsInfo, isNotEmpty);
  });
}
