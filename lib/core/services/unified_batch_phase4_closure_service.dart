import 'dart:math';

import 'package:drift/drift.dart';

import '../../models/product.dart';
import '../../models/product_costing.dart';
import '../storage/sqlite/business_sqlite_store.dart';
import '../storage/sqlite/ventio_drift_database.dart';
import 'batch_inventory_service.dart';

class UnifiedBatchPhase4ClosureResult {
  const UnifiedBatchPhase4ClosureResult({
    required this.closedAt,
    required this.cutoversBefore,
    required this.cutoversAfter,
    required this.productWarehousePairs,
    required this.legacyCostLayersRetained,
  });

  final DateTime closedAt;
  final int cutoversBefore;
  final int cutoversAfter;
  final int productWarehousePairs;
  final int legacyCostLayersRetained;

  int get cutoversCreated => max(0, cutoversAfter - cutoversBefore);
}

/// Phase 4 production cutover for Unified Batch inventory.
///
/// The closure is intentionally current-state based. Pre-cutover documents and
/// legacy FIFO layers remain readable historical evidence, but they are not a
/// second valuation source after this service succeeds.
class UnifiedBatchPhase4ClosureService {
  UnifiedBatchPhase4ClosureService(this._db);

  static const String closureMetaKey = 'unified_batch_phase4_closed_at';
  static const String legacyLayerModeMetaKey =
      'unified_batch_legacy_cost_layers_mode';
  static const String costingSettingKey = 'inventory_costing_method_v1';

  final VentioDriftDatabase _db;

  Future<UnifiedBatchPhase4ClosureResult> close({
    required String storeId,
    required String branchId,
    required String deviceId,
    bool allowNegativeStock = false,
    bool alreadyInTransaction = false,
    DateTime? closedAt,
  }) async {
    final requestedAt = (closedAt ?? DateTime.now()).toUtc();
    final existingClosure = await _readMeta(closureMetaKey);
    final parsedExistingClosure = existingClosure == null
        ? null
        : DateTime.tryParse(existingClosure)?.toUtc();
    // The first successful Phase 4 close is the permanent safety boundary.
    // Never move it forward on later startups, otherwise a legacy write that
    // happened after the original cutover could become invisible to audits.
    final now = parsedExistingClosure ?? requestedAt;
    final nowText = now.toIso8601String();
    final normalizedStoreId = storeId.trim();
    if (normalizedStoreId.isEmpty) {
      throw StateError('Unified Batch Phase 4 requires a store identity.');
    }

    final products = await BusinessSqliteStore.readProducts(_db);
    final productById = <String, Product>{
      for (final product in products)
        if (!product.isDeleted && product.trackStock) product.id: product,
    };
    final costs = <String, ProductCost>{
      for (final cost in await BusinessSqliteStore.readProductCosts(_db))
        cost.productId: cost,
    };
    final cutoversBefore = await _countCutovers(normalizedStoreId);
    final legacyLayers = await _countLegacyLayers(normalizedStoreId);
    var scopedPairs = 0;

    Future<void> closeInTransaction() async {
      final inventoryRows = await _db.customSelect(
        r'''
        SELECT wi.product_id, wi.warehouse_id, wi.quantity
        FROM warehouse_inventory wi
        INNER JOIN products p ON p.id = wi.product_id
          AND p.deleted_at = '' AND p.track_stock = 1
        WHERE wi.store_id = ?
        ORDER BY wi.warehouse_id ASC, wi.product_id ASC
        ''',
        variables: <Variable<Object>>[
          Variable<String>(normalizedStoreId),
        ],
      ).get();

      final batchService = BatchInventoryService(_db);
      for (final row in inventoryRows) {
        final productId = row.data['product_id']?.toString() ?? '';
        final warehouseId = row.data['warehouse_id']?.toString() ?? '';
        final quantity = (row.data['quantity'] as num? ?? 0).toDouble();
        final product = productById[productId];
        if (product == null || warehouseId.trim().isEmpty) continue;
        if (quantity < -0.000001 && !allowNegativeStock) {
          throw StateError(
            'Unified Batch Phase 4 cannot close with negative warehouse stock for ${product.name} while negative stock is disabled.',
          );
        }
        scopedPairs += 1;
        final openingUnitCost = await _openingCost(
          product: product,
          warehouseId: warehouseId,
          storeId: normalizedStoreId,
          productCost: costs[product.id],
        );
        await batchService.ensureUnifiedCutoverInTransaction(
          product: product,
          warehouseId: warehouseId,
          openingUnitCost: openingUnitCost,
          cutoverAt: now,
          storeId: normalizedStoreId,
          branchId: branchId,
          deviceId: deviceId,
        );
      }

      await _assertUnifiedState(normalizedStoreId);
      await _lockRuntimeCostingToBatch(
        storeId: normalizedStoreId,
        branchId: branchId,
        deviceId: deviceId,
        at: now,
      );
      await _writeMeta(closureMetaKey, nowText, nowText);
      await _writeMeta(legacyLayerModeMetaKey, 'read_only', nowText);
    }

    if (alreadyInTransaction) {
      await closeInTransaction();
    } else {
      await _db.transaction(closeInTransaction);
    }

    final cutoversAfter = await _countCutovers(normalizedStoreId);
    return UnifiedBatchPhase4ClosureResult(
      closedAt: now,
      cutoversBefore: cutoversBefore,
      cutoversAfter: cutoversAfter,
      productWarehousePairs: scopedPairs,
      legacyCostLayersRetained: legacyLayers,
    );
  }

  Future<double> _openingCost({
    required Product product,
    required String warehouseId,
    required String storeId,
    required ProductCost? productCost,
  }) async {
    final row = await _db.customSelect(
      r'''
      SELECT
        COALESCE((
          SELECT wi.quantity
          FROM warehouse_inventory wi
          WHERE wi.store_id = ? AND wi.warehouse_id = ? AND wi.product_id = ?
          LIMIT 1
        ), 0) AS warehouse_quantity,
        COUNT(sm.id) AS movement_count,
        COALESCE(SUM(sm.quantity), 0) AS movement_quantity,
        COALESCE(SUM(sm.quantity * sm.unit_cost), 0) AS carrying_value
      FROM stock_movements sm
      WHERE sm.store_id = ? AND sm.warehouse_id = ? AND sm.product_id = ?
        AND sm.deleted_at = ''
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
      ],
    ).getSingle();
    final warehouseQuantity =
        (row.data['warehouse_quantity'] as num? ?? 0).toDouble();
    final movementCount = (row.data['movement_count'] as num? ?? 0).toInt();
    final movementQuantity =
        (row.data['movement_quantity'] as num? ?? 0).toDouble();
    final carryingValue =
        (row.data['carrying_value'] as num? ?? 0).toDouble();
    if (warehouseQuantity > 0.000001 &&
        movementCount > 0 &&
        (movementQuantity - warehouseQuantity).abs() <= 0.000001 &&
        carryingValue >= -0.000001) {
      return max(0.0, carryingValue) / warehouseQuantity;
    }
    if ((productCost?.averageCost ?? 0) > 0) {
      return productCost!.averageCost;
    }
    if ((productCost?.lastCost ?? 0) > 0) return productCost!.lastCost;
    if (product.usdCost > 0) return product.usdCost;
    if (product.cost > 0) return product.cost;
    return 0;
  }

  Future<void> _assertUnifiedState(String storeId) async {
    final negative = await _db.customSelect(
      r'''
      SELECT bb.id, bb.product_id, bb.warehouse_id, bb.quantity
      FROM inventory_batch_balances bb
      WHERE bb.store_id = ? AND bb.quantity < -0.000001
      LIMIT 1
      ''',
      variables: <Variable<Object>>[Variable<String>(storeId)],
    ).getSingleOrNull();
    if (negative != null) {
      throw StateError(
        'Unified Batch Phase 4 found a negative batch balance for ${negative.data['product_id'] ?? ''}.',
      );
    }

    final drift = await _db.customSelect(
      r'''
      WITH scoped AS (
        SELECT store_id, warehouse_id, product_id FROM warehouse_inventory
        WHERE store_id = ?
        UNION
        SELECT store_id, warehouse_id, product_id FROM inventory_batch_balances
        WHERE store_id = ?
        UNION
        SELECT store_id, warehouse_id, product_id FROM inventory_stock_deficits
        WHERE store_id = ? AND status = 'open' AND quantity_open > 0.000001
      ), warehouse AS (
        SELECT store_id, warehouse_id, product_id, SUM(quantity) AS qty
        FROM warehouse_inventory
        WHERE store_id = ?
        GROUP BY store_id, warehouse_id, product_id
      ), batches AS (
        SELECT store_id, warehouse_id, product_id, SUM(quantity) AS qty
        FROM inventory_batch_balances
        WHERE store_id = ?
        GROUP BY store_id, warehouse_id, product_id
      ), deficits AS (
        SELECT store_id, warehouse_id, product_id, SUM(quantity_open) AS qty
        FROM inventory_stock_deficits
        WHERE store_id = ? AND status = 'open' AND quantity_open > 0.000001
        GROUP BY store_id, warehouse_id, product_id
      )
      SELECT s.product_id, s.warehouse_id,
             COALESCE(w.qty, 0) AS warehouse_qty,
             COALESCE(b.qty, 0) - COALESCE(d.qty, 0) AS batch_qty
      FROM scoped s
      LEFT JOIN warehouse w ON w.store_id = s.store_id
        AND w.warehouse_id = s.warehouse_id AND w.product_id = s.product_id
      LEFT JOIN batches b ON b.store_id = s.store_id
        AND b.warehouse_id = s.warehouse_id AND b.product_id = s.product_id
      LEFT JOIN deficits d ON d.store_id = s.store_id
        AND d.warehouse_id = s.warehouse_id AND d.product_id = s.product_id
      WHERE ABS(COALESCE(w.qty, 0)
        - (COALESCE(b.qty, 0) - COALESCE(d.qty, 0))) > 0.000001
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(storeId),
        Variable<String>(storeId),
        Variable<String>(storeId),
        Variable<String>(storeId),
        Variable<String>(storeId),
      ],
    ).getSingleOrNull();
    if (drift != null) {
      throw StateError(
        'Unified Batch Phase 4 reconciliation failed for product ${drift.data['product_id'] ?? ''} in warehouse ${drift.data['warehouse_id'] ?? ''}: warehouse=${drift.data['warehouse_qty'] ?? 0}, batches=${drift.data['batch_qty'] ?? 0}.',
      );
    }

    final invalidBatch = await _db.customSelect(
      r'''
      SELECT b.id, b.product_id, b.unit_cost, b.expiration_date,
             p.expiry_tracking_enabled, COALESCE(SUM(bb.quantity), 0) AS qty
      FROM inventory_batches b
      INNER JOIN products p ON p.id = b.product_id
      LEFT JOIN inventory_batch_balances bb ON bb.batch_id = b.id
        AND bb.store_id = b.store_id
      WHERE b.store_id = ? AND p.deleted_at = '' AND p.track_stock = 1
      GROUP BY b.id, b.product_id, b.unit_cost, b.expiration_date,
               p.expiry_tracking_enabled
      HAVING b.unit_cost < -0.000001
        OR (qty > 0.000001 AND p.expiry_tracking_enabled = 1
            AND trim(b.expiration_date) = '')
        OR (qty > 0.000001 AND p.expiry_tracking_enabled = 0
            AND trim(b.expiration_date) <> '')
      LIMIT 1
      ''',
      variables: <Variable<Object>>[Variable<String>(storeId)],
    ).getSingleOrNull();
    if (invalidBatch != null) {
      throw StateError(
        'Unified Batch Phase 4 found invalid batch metadata for ${invalidBatch.data['product_id'] ?? ''}.',
      );
    }

    final missingCutover = await _db.customSelect(
      r'''
      SELECT wi.product_id, wi.warehouse_id, wi.quantity
      FROM warehouse_inventory wi
      INNER JOIN products p ON p.id = wi.product_id
        AND p.deleted_at = '' AND p.track_stock = 1
      LEFT JOIN unified_batch_cutovers uc
        ON uc.store_id = wi.store_id AND uc.warehouse_id = wi.warehouse_id
        AND uc.product_id = wi.product_id
      WHERE wi.store_id = ? AND uc.id IS NULL
      LIMIT 1
      ''',
      variables: <Variable<Object>>[Variable<String>(storeId)],
    ).getSingleOrNull();
    if (missingCutover != null) {
      throw StateError(
        'Unified Batch Phase 4 is missing a cutover marker for product ${missingCutover.data['product_id'] ?? ''}.',
      );
    }

    final unbatchedOutbound = await _db.customSelect(
      r'''
      SELECT sm.id, sm.product_id, sm.warehouse_id, sm.movement_type
      FROM stock_movements sm
      INNER JOIN unified_batch_cutovers uc
        ON uc.store_id = sm.store_id AND uc.warehouse_id = sm.warehouse_id
        AND uc.product_id = sm.product_id
      INNER JOIN products p ON p.id = sm.product_id
        AND p.deleted_at = '' AND p.track_stock = 1
      WHERE sm.store_id = ? AND sm.deleted_at = ''
        AND sm.quantity < -0.000001 AND trim(sm.batch_id) = ''
        AND datetime(sm.movement_date) >= datetime(uc.cutover_at)
      LIMIT 1
      ''',
      variables: <Variable<Object>>[Variable<String>(storeId)],
    ).getSingleOrNull();
    if (unbatchedOutbound != null) {
      throw StateError(
        'Unified Batch Phase 4 found a post-cutover stock-out without batch identity: ${unbatchedOutbound.data['id'] ?? ''}.',
      );
    }
  }

  Future<void> _lockRuntimeCostingToBatch({
    required String storeId,
    required String branchId,
    required String deviceId,
    required DateTime at,
  }) async {
    final atText = at.toUtc().toIso8601String();
    await _db.customStatement(
      '''
      INSERT OR REPLACE INTO settings (key, value, updated_at)
      VALUES (?, 'batch', ?)
      ''',
      <Object?>[costingSettingKey, atText],
    );

    final openRows = await _db.customSelect(
      r'''
      SELECT id, method
      FROM costing_method_history
      WHERE deleted_at = '' AND trim(effective_to) = ''
      ORDER BY effective_from DESC, id DESC
      ''',
    ).get();
    final alreadyLocked = openRows.length == 1 &&
        const <String>{'batch', 'unified_batch'}.contains(
          openRows.single.data['method']?.toString().trim().toLowerCase() ?? '',
        );
    if (alreadyLocked) return;

    await _db.customStatement(
      '''
      UPDATE costing_method_history
      SET effective_to = ?, updated_at = ?, sync_status = 'pending',
          last_modified_by_device_id = ?
      WHERE deleted_at = '' AND trim(effective_to) = ''
      ''',
      <Object?>[atText, atText, deviceId],
    );
    final id = 'unified_batch_phase4_${at.microsecondsSinceEpoch}';
    await _db.customStatement(
      '''
      INSERT INTO costing_method_history
        (id, entity_type, created_at, updated_at, deleted_at, device_id,
         sync_status, store_id, branch_id, version, last_modified_by_device_id,
         sort_index, method, effective_from, effective_to, reason)
      VALUES (?, 'costing_method_history', ?, ?, '', ?, 'pending', ?, ?, 1, ?,
              0, 'batch', ?, '', 'Unified Batch Phase 4 production cutover')
      ''',
      <Object?>[
        id,
        atText,
        atText,
        deviceId,
        storeId,
        branchId,
        deviceId,
        atText,
      ],
    );
  }

  Future<int> _countCutovers(String storeId) async {
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS count FROM unified_batch_cutovers WHERE store_id = ?',
      variables: <Variable<Object>>[Variable<String>(storeId)],
    ).getSingle();
    return (row.data['count'] as num? ?? 0).toInt();
  }

  Future<int> _countLegacyLayers(String storeId) async {
    final row = await _db.customSelect(
      r'''
      SELECT COUNT(*) AS count
      FROM inventory_cost_layers
      WHERE deleted_at = '' AND (store_id = ? OR trim(store_id) = '')
      ''',
      variables: <Variable<Object>>[Variable<String>(storeId)],
    ).getSingle();
    return (row.data['count'] as num? ?? 0).toInt();
  }

  Future<String?> _readMeta(String key) async {
    final row = await _db.customSelect(
      'SELECT value FROM migration_meta WHERE key = ?',
      variables: <Variable<Object>>[Variable<String>(key)],
    ).getSingleOrNull();
    final value = row?.data['value']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<void> _writeMeta(String key, String value, String updatedAt) async {
    await _db.customStatement(
      '''
      INSERT OR REPLACE INTO migration_meta (key, value, updated_at)
      VALUES (?, ?, ?)
      ''',
      <Object?>[key, value, updatedAt],
    );
  }
}
