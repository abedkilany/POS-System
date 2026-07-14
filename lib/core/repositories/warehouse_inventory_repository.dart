import 'package:drift/drift.dart';

import '../../models/warehouse_inventory.dart';
import '../storage/sqlite/ventio_drift_database.dart';

class WarehouseInventoryRepository {
  WarehouseInventoryRepository._();

  static Future<WarehouseInventory?> getByIdentity(
    VentioDriftDatabase db, {
    required String storeId,
    required String warehouseId,
    required String productId,
  }) async {
    final rows = await db.customSelect(
      '''
      SELECT id, store_id AS storeId, branch_id AS branchId,
             warehouse_id AS warehouseId, product_id AS productId,
             quantity, version, created_at AS createdAt,
             updated_at AS updatedAt, device_id AS deviceId,
             sync_status AS syncStatus,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM warehouse_inventory
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(productId),
      ],
    ).get();
    if (rows.isEmpty) return null;
    return WarehouseInventory.fromJson(Map<String, dynamic>.from(rows.first.data));
  }

  static Future<List<WarehouseInventory>> listBalances(
    VentioDriftDatabase db, {
    String storeId = '',
    String branchId = '',
    String warehouseId = '',
    String productId = '',
  }) async {
    final conditions = <String>[];
    final variables = <Variable<Object>>[];
    if (storeId.trim().isNotEmpty) {
      conditions.add('store_id = ?');
      variables.add(Variable<String>(storeId.trim()));
    }
    if (branchId.trim().isNotEmpty) {
      conditions.add('branch_id = ?');
      variables.add(Variable<String>(branchId.trim()));
    }
    if (warehouseId.trim().isNotEmpty) {
      conditions.add('warehouse_id = ?');
      variables.add(Variable<String>(warehouseId.trim()));
    }
    if (productId.trim().isNotEmpty) {
      conditions.add('product_id = ?');
      variables.add(Variable<String>(productId.trim()));
    }
    final whereSql = conditions.isEmpty ? '1=1' : conditions.join(' AND ');
    final rows = await db.customSelect('''
      SELECT id, store_id AS storeId, branch_id AS branchId,
             warehouse_id AS warehouseId, product_id AS productId,
             quantity, version, created_at AS createdAt,
             updated_at AS updatedAt, device_id AS deviceId,
             sync_status AS syncStatus,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM warehouse_inventory
      WHERE $whereSql
      ORDER BY store_id ASC, warehouse_id ASC, product_id ASC
    ''', variables: variables).get();
    return rows
        .map((row) => WarehouseInventory.fromJson(Map<String, dynamic>.from(row.data)))
        .toList(growable: false);
  }

  static Future<void> upsert(
    VentioDriftDatabase db,
    WarehouseInventory inventory,
  ) async {
    await db.customInsert(
      '''
      INSERT INTO warehouse_inventory
        (id, store_id, branch_id, warehouse_id, product_id, quantity,
         version, created_at, updated_at, device_id, sync_status,
         last_modified_by_device_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(store_id, warehouse_id, product_id) DO UPDATE SET
        branch_id = excluded.branch_id,
        quantity = excluded.quantity,
        version = excluded.version,
        updated_at = excluded.updated_at,
        device_id = excluded.device_id,
        sync_status = excluded.sync_status,
        last_modified_by_device_id = excluded.last_modified_by_device_id
      ''',
      variables: <Variable<Object>>[
        Variable<String>(inventory.id),
        Variable<String>(inventory.storeId),
        Variable<String>(inventory.branchId),
        Variable<String>(inventory.warehouseId),
        Variable<String>(inventory.productId),
        Variable<double>(inventory.quantity),
        Variable<int>(inventory.version),
        Variable<String>(inventory.createdAt.toIso8601String()),
        Variable<String>(inventory.updatedAt.toIso8601String()),
        Variable<String>(inventory.deviceId),
        Variable<String>(inventory.syncStatus),
        Variable<String>(inventory.lastModifiedByDeviceId),
      ],
    );
  }

  static Future<void> deleteByIdentity(
    VentioDriftDatabase db, {
    required String storeId,
    required String warehouseId,
    required String productId,
  }) async {
    await db.customStatement(
      '''
      DELETE FROM warehouse_inventory
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
      ''',
      <Object?>[storeId, warehouseId, productId],
    );
  }
}
