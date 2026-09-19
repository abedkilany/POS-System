import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../core/services/accounting_service.dart';
import '../../core/storage/sqlite/business_sqlite_store.dart';
import '../../core/storage/sqlite/sqlite_migration_manager.dart';
import '../../data/app_store.dart';
import '../../models/product.dart';

class ProductCostRepairResult {
  const ProductCostRepairResult({
    required this.repairedBatches,
    required this.rebuiltProducts,
    required this.postedRevaluations,
    required this.unresolvedBatches,
  });

  final int repairedBatches;
  final int rebuiltProducts;
  final int postedRevaluations;
  final int unresolvedBatches;

  int get changedRecords => repairedBatches + rebuiltProducts;
}

/// Repairs only cost data that can be proven from authoritative inventory data.
///
/// Purchase batches are rebuilt from their purchase-line cost. Manufacturing
/// output batches are rebuilt from the corrected costs of their consumed
/// material batches and the manufacturing waste lines. ProductCost and the
/// product reference cost are then rebuilt from the remaining physical batches.
class ProductCostRepairService {
  const ProductCostRepairService(this.store);

  final AppStore store;

  Future<ProductCostRepairResult> repair() async {
    final db = SqliteMigrationManager.database;
    if (db == null) {
      throw StateError('SQLite database is not initialized.');
    }
    await store.ensureProductsLoaded();
    await store.ensureProductCostsLoaded();

    final products = <String, Product>{
      for (final product in store.products)
        if (!product.isDeleted && product.id.trim().isNotEmpty)
          product.id: product,
    };
    final now = DateTime.now().toUtc();
    var repairedBatches = 0;
    var postedRevaluations = 0;
    var unresolvedBatches = 0;
    var rebuiltProducts = 0;

    await db.transaction(() async {
      final purchaseRepair = await _repairPurchaseBatches(
        db,
        products: products,
        now: now,
      );
      repairedBatches += purchaseRepair.changed;
      unresolvedBatches += purchaseRepair.unresolved;
      postedRevaluations += purchaseRepair.revaluations;

      final manufacturingRepair =
          await _repairManufacturingBatches(db, products, now);
      repairedBatches += manufacturingRepair.changed;
      unresolvedBatches += manufacturingRepair.unresolved;
      postedRevaluations += manufacturingRepair.revaluations;

      final aggregateRows = await db.customSelect('''
        SELECT b.product_id AS productId,
               COALESCE(SUM(bb.quantity), 0) AS quantity,
               COALESCE(SUM(bb.quantity * b.unit_cost), 0) AS carryingValue
        FROM inventory_batches b
        INNER JOIN inventory_batch_balances bb
          ON bb.batch_id = b.id
         AND bb.product_id = b.product_id
         AND bb.store_id = b.store_id
        WHERE b.store_id = ?
          AND bb.quantity > 0.000001
        GROUP BY b.product_id
        HAVING COALESCE(SUM(bb.quantity), 0) > 0.000001
      ''', variables: <Variable<Object>>[
        Variable<String>(store.appIdentity.storeId),
      ]).get();

      final productUpdates = <Map<String, dynamic>>[];
      final costUpdates = <Map<String, dynamic>>[];
      for (final row in aggregateRows) {
        final productId = row.data['productId']?.toString() ?? '';
        final product = products[productId];
        if (product == null) continue;
        final quantity = (row.data['quantity'] as num? ?? 0).toDouble();
        final carryingValue =
            (row.data['carryingValue'] as num? ?? 0).toDouble();
        if (quantity <= 0 || !carryingValue.isFinite) continue;
        final averageCost = math.max(0, carryingValue / quantity).toDouble();
        if (!averageCost.isFinite || averageCost <= 0) continue;
        final lastCost = await _latestPositiveBatchCost(
          db,
          productId: productId,
          fallback: averageCost,
        );
        final updated = product.copyWith(
          cost:
              product.costCurrency.toUpperCase() == 'USD' ? averageCost : null,
          originalCost:
              product.costCurrency.toUpperCase() == 'USD' ? averageCost : null,
          usdCost: averageCost,
          updatedAt: now,
          version: product.version + 1,
          deviceId: store.appIdentity.deviceId,
          lastModifiedByDeviceId: store.appIdentity.deviceId,
          syncStatus: 'pending',
        );
        productUpdates.add(updated.toJson());
        costUpdates.add(<String, dynamic>{
          'productId': productId,
          'averageCost': averageCost,
          'lastCost': lastCost,
          'currencyCode': 'USD',
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        });
      }

      if (productUpdates.isNotEmpty) {
        await BusinessSqliteStore.upsertEntityPayloads(
          db,
          'products_v4',
          productUpdates,
        );
      }
      if (costUpdates.isNotEmpty) {
        await BusinessSqliteStore.upsertEntityPayloads(
          db,
          'product_costs_v1',
          costUpdates,
        );
      }

      rebuiltProducts = productUpdates.length;
    });

    await store.refreshAfterDatabaseChange('products_v4');
    await store.refreshAfterDatabaseChange('product_costs_v1');
    await store.refreshAfterDatabaseChange('account_transactions_v1');
    return ProductCostRepairResult(
      repairedBatches: repairedBatches,
      rebuiltProducts: rebuiltProducts,
      postedRevaluations: postedRevaluations,
      unresolvedBatches: unresolvedBatches,
    );
  }

  Future<({int changed, int unresolved, int revaluations})>
      _repairPurchaseBatches(
    dynamic db, {
    required Map<String, Product> products,
    required DateTime now,
  }) async {
    var changed = 0;
    var unresolved = 0;
    var revaluations = 0;
    final rows = await db.customSelect('''
      SELECT b.id, b.product_id AS productId, b.unit_cost AS unitCost,
             COALESCE(SUM(bb.quantity), 0) AS quantity
      FROM inventory_batches b
      LEFT JOIN inventory_batch_balances bb
        ON bb.batch_id = b.id
       AND bb.product_id = b.product_id
       AND bb.store_id = b.store_id
      WHERE b.store_id = ? AND b.source_type = 'purchase'
      GROUP BY b.id, b.product_id, b.unit_cost
    ''', variables: <Variable<Object>>[
      Variable<String>(store.appIdentity.storeId),
    ]).get();
    for (final row in rows) {
      final batchId = row.data['id']?.toString() ?? '';
      final productId = row.data['productId']?.toString() ?? '';
      final product = products[productId];
      final quantity = (row.data['quantity'] as num? ?? 0).toDouble();
      final currentCost = (row.data['unitCost'] as num? ?? 0).toDouble();
      final sourceCost = await _purchaseSourceCost(
        db,
        batchId: batchId,
        productId: productId,
      );
      if (sourceCost == null || product == null) {
        if (quantity > 0.000001) unresolved += 1;
        continue;
      }
      if ((sourceCost - currentCost).abs() <= 0.000001) continue;
      final result = await _updateBatchCost(
        db,
        batchId: batchId,
        product: product,
        currentCost: currentCost,
        nextCost: sourceCost,
        remainingQuantity: quantity,
        now: now,
        reason: 'Automatic repair from purchase-line cost',
      );
      if (result.changed) changed += 1;
      if (result.revalued) revaluations += 1;
    }
    return (
      changed: changed,
      unresolved: unresolved,
      revaluations: revaluations,
    );
  }

  Future<({int changed, int unresolved, int revaluations})>
      _repairManufacturingBatches(
    dynamic db,
    Map<String, Product> products,
    DateTime now,
  ) async {
    var changed = 0;
    var unresolved = 0;
    var revaluations = 0;
    final rows = await db.customSelect('''
      SELECT b.id, b.product_id AS productId, b.product_name AS productName,
             b.source_id AS sourceId, b.unit_cost AS unitCost,
             b.initial_quantity AS initialQuantity,
             COALESCE(SUM(bb.quantity), 0) AS quantity
      FROM inventory_batches b
      LEFT JOIN inventory_batch_balances bb
        ON bb.batch_id = b.id
       AND bb.product_id = b.product_id
       AND bb.store_id = b.store_id
      WHERE b.store_id = ? AND b.source_type = 'manufacturing_output'
      GROUP BY b.id, b.product_id, b.product_name, b.source_id,
               b.unit_cost, b.initial_quantity
      ORDER BY b.source_id, b.id
    ''', variables: <Variable<Object>>[
      Variable<String>(store.appIdentity.storeId),
    ]).get();
    final bySource = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final sourceId = row.data['sourceId']?.toString().trim() ?? '';
      if (sourceId.isEmpty) continue;
      bySource.putIfAbsent(sourceId, () => <Map<String, dynamic>>[]).add(
            Map<String, dynamic>.from(row.data),
          );
    }
    for (final entry in bySource.entries) {
      final first = entry.value.first;
      final productId = first['productId']?.toString() ?? '';
      final product = products[productId];
      if (product == null) {
        unresolved += entry.value.length;
        continue;
      }
      final manufacturingCost = await _manufacturingSourceCost(
        db,
        sourceId: entry.key,
        productId: productId,
      );
      if (manufacturingCost == null || manufacturingCost.unitCost <= 0) {
        if (entry.value.any(
            (row) => (row['quantity'] as num? ?? 0).toDouble() > 0.000001)) {
          unresolved += entry.value.length;
        }
        continue;
      }
      final nextCost = manufacturingCost.unitCost;
      for (final row in entry.value) {
        final currentCost = (row['unitCost'] as num? ?? 0).toDouble();
        if ((nextCost - currentCost).abs() <= 0.000001) continue;
        final result = await _updateBatchCost(
          db,
          batchId: row['id']?.toString() ?? '',
          product: product,
          currentCost: currentCost,
          nextCost: nextCost,
          remainingQuantity: (row['quantity'] as num? ?? 0).toDouble(),
          now: now,
          reason: 'Automatic repair from manufacturing material cost',
        );
        if (result.changed) changed += 1;
        if (result.revalued) revaluations += 1;
      }
      await db.customStatement('''
        UPDATE stock_movements
        SET unit_cost = ?, updated_at = ?, sync_status = 'pending',
            last_modified_by_device_id = ?
        WHERE store_id = ? AND movement_group_id = ?
          AND movement_type = 'manufacturing_produce'
          AND product_id = ? AND deleted_at = ''
      ''', <Object?>[
        nextCost,
        now.toIso8601String(),
        store.appIdentity.deviceId,
        store.appIdentity.storeId,
        entry.key,
        productId,
      ]);
      await db.customStatement('''
        UPDATE manufacturing_orders
        SET total_material_cost = ?, total_waste_cost = ?,
            total_eligible_cost = ?, actual_unit_cost = ?,
            updated_at = ?, sync_status = 'pending',
            last_modified_by_device_id = ?, version = version + 1
        WHERE id = ? AND store_id = ?
      ''', <Object?>[
        manufacturingCost.materialCost,
        manufacturingCost.wasteCost,
        manufacturingCost.eligibleCost,
        nextCost,
        now.toIso8601String(),
        store.appIdentity.deviceId,
        entry.key,
        store.appIdentity.storeId,
      ]);
    }
    return (
      changed: changed,
      unresolved: unresolved,
      revaluations: revaluations,
    );
  }

  Future<double?> _purchaseSourceCost(
    dynamic db, {
    required String batchId,
    required String productId,
  }) async {
    final purchaseRow = await db.customSelect('''
      SELECT CASE
               WHEN pi.conversion_to_base > 0
                 THEN pi.unit_cost / pi.conversion_to_base
               ELSE pi.unit_cost
             END AS unitCost
      FROM purchase_item_batch_allocations pba
      INNER JOIN purchase_items pi ON pi.id = pba.purchase_item_id
      WHERE pba.batch_id = ?
        AND pi.product_id = ?
        AND pi.unit_cost > 0
      ORDER BY pba.line_no ASC
      LIMIT 1
    ''', variables: <Variable<Object>>[
      Variable<String>(batchId),
      Variable<String>(productId),
    ]).getSingleOrNull();
    final purchaseCost = (purchaseRow?.data['unitCost'] as num?)?.toDouble();
    if (purchaseCost != null && purchaseCost.isFinite && purchaseCost > 0) {
      return purchaseCost;
    }
    return null;
  }

  Future<
      ({
        double materialCost,
        double wasteCost,
        double eligibleCost,
        double unitCost
      })?> _manufacturingSourceCost(
    dynamic db, {
    required String sourceId,
    required String productId,
  }) async {
    final materialRows = await db.customSelect('''
      SELECT sm.product_id AS productId,
             COALESCE(SUM(ABS(sm.quantity)), 0) AS quantity,
             COALESCE(SUM(ABS(sm.quantity) * b.unit_cost), 0) AS value
      FROM stock_movements sm
      INNER JOIN inventory_batches b
        ON b.id = sm.batch_id AND b.store_id = sm.store_id
      WHERE sm.store_id = ? AND sm.movement_group_id = ?
        AND sm.movement_type = 'manufacturing_consume'
        AND sm.deleted_at = '' AND trim(sm.batch_id) <> ''
      GROUP BY sm.product_id
    ''', variables: <Variable<Object>>[
      Variable<String>(store.appIdentity.storeId),
      Variable<String>(sourceId),
    ]).get();
    var materialCost = 0.0;
    for (final row in materialRows) {
      materialCost += (row.data['value'] as num? ?? 0).toDouble();
    }
    final outputRow = await db.customSelect('''
      SELECT COALESCE(SUM(initial_quantity), 0) AS quantity
      FROM inventory_batches
      WHERE store_id = ? AND source_type = 'manufacturing_output'
        AND source_id = ? AND product_id = ?
    ''', variables: <Variable<Object>>[
      Variable<String>(store.appIdentity.storeId),
      Variable<String>(sourceId),
      Variable<String>(productId),
    ]).getSingle();
    final outputQuantity = (outputRow.data['quantity'] as num? ?? 0).toDouble();
    if (materialCost <= 0 || outputQuantity <= 0) return null;

    var wasteCost = 0.0;
    final orderRow = await db.customSelect('''
      SELECT waste_lines_json AS wasteLinesJson
      FROM manufacturing_orders
      WHERE id = ? AND store_id = ?
      LIMIT 1
    ''', variables: <Variable<Object>>[
      Variable<String>(sourceId),
      Variable<String>(store.appIdentity.storeId),
    ]).getSingleOrNull();
    final encodedWaste = orderRow?.data['wasteLinesJson']?.toString() ?? '';
    if (encodedWaste.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(encodedWaste);
        if (decoded is List) {
          final unitCostByProduct = <String, double>{};
          for (final row in materialRows) {
            final id = row.data['productId']?.toString() ?? '';
            final quantity = (row.data['quantity'] as num? ?? 0).toDouble();
            final value = (row.data['value'] as num? ?? 0).toDouble();
            if (id.isNotEmpty && quantity > 0) {
              unitCostByProduct[id] = value / quantity;
            }
          }
          for (final item in decoded.whereType<Map>()) {
            final map = Map<String, dynamic>.from(item);
            final id = map['productId']?.toString() ?? '';
            final quantity = (map['quantity'] as num? ?? 0).toDouble();
            final unitCost = unitCostByProduct[id] ?? 0;
            wasteCost += math.max<double>(0, quantity) * unitCost;
          }
        }
      } catch (_) {
        // An unreadable waste snapshot cannot prove a corrected cost.
        return null;
      }
    }
    final eligibleCost = math.max<double>(0, materialCost - wasteCost);
    return (
      materialCost: materialCost,
      wasteCost: wasteCost,
      eligibleCost: eligibleCost,
      unitCost: eligibleCost / outputQuantity,
    );
  }

  Future<({bool changed, bool revalued})> _updateBatchCost(
    dynamic db, {
    required String batchId,
    required Product product,
    required double currentCost,
    required double nextCost,
    required double remainingQuantity,
    required DateTime now,
    required String reason,
  }) async {
    if (batchId.trim().isEmpty || nextCost <= 0) {
      return (changed: false, revalued: false);
    }
    await db.customStatement('''
      UPDATE inventory_batches
      SET unit_cost = ?, cost_currency = 'USD', exchange_rate = 1,
          updated_at = ?, device_id = ?, last_modified_by_device_id = ?,
          sync_status = 'pending', version = version + 1
      WHERE id = ? AND store_id = ?
    ''', <Object?>[
      nextCost,
      now.toIso8601String(),
      store.appIdentity.deviceId,
      store.appIdentity.deviceId,
      batchId,
      store.appIdentity.storeId,
    ]);
    final delta = remainingQuantity * (nextCost - currentCost);
    if (delta.abs() <= 0.000001) return (changed: true, revalued: false);
    final journalId =
        await AccountingService.recordInventoryBatchRevaluationInTransaction(
      database: db,
      entryDate: now,
      referenceId: 'cost-repair-$batchId',
      referenceNo: 'COST-REPAIR-$batchId',
      productId: product.id,
      productName: product.name,
      batchId: batchId,
      valueDelta: delta,
      createdBy: store.appIdentity.deviceId,
      storeId: store.appIdentity.storeId,
      branchId: store.appIdentity.branchId,
      reason: reason,
    );
    return (changed: true, revalued: journalId.isNotEmpty);
  }

  Future<double> _latestPositiveBatchCost(
    dynamic db, {
    required String productId,
    required double fallback,
  }) async {
    final row = await db.customSelect('''
      SELECT b.unit_cost AS unitCost
      FROM inventory_batches b
      WHERE b.store_id = ?
        AND b.product_id = ?
        AND b.unit_cost > 0
      ORDER BY COALESCE(NULLIF(trim(b.received_at), ''), b.created_at) DESC,
               b.updated_at DESC, b.id DESC
      LIMIT 1
    ''', variables: <Variable<Object>>[
      Variable<String>(store.appIdentity.storeId),
      Variable<String>(productId),
    ]).getSingleOrNull();
    final value = (row?.data['unitCost'] as num?)?.toDouble();
    return value != null && value.isFinite && value > 0 ? value : fallback;
  }
}
