import 'dart:math';
import 'package:drift/drift.dart';
import '../../models/product.dart';
import '../../models/product_costing.dart';
import '../../models/inventory_cost_layer.dart';
import '../../models/sale_item.dart';
import '../storage/sqlite/business_sqlite_store.dart';
import '../storage/sqlite/ventio_drift_database.dart';

/// Resolves sale cost using explicit catalog inputs and the active transaction.
class SaleCostService {
  const SaleCostService(
      {required this.db,
      required this.costingMethod,
      required this.productById,
      required this.productCostFor,
      required this.allowNegativeStock});
  final VentioDriftDatabase db;
  final InventoryCostingMethod costingMethod;
  final Product? Function(String) productById;
  final ProductCost Function(String) productCostFor;
  final bool allowNegativeStock;

  Future<InventoryCostResult> resolve(
    SaleItem item,
    DateTime now,
  ) async {
    final product = productById(item.productId);
    final cost = productCostFor(item.productId);
    final providedUnitCost = item.unitCost > 0 ? item.unitCost : 0.0;

    double fallbackCost() {
      if (providedUnitCost > 0) return providedUnitCost;
      if (costingMethod == InventoryCostingMethod.lastPurchaseCost &&
          cost.lastCost > 0) {
        return cost.lastCost;
      }
      if (cost.averageCost > 0) return cost.averageCost;
      if (cost.lastCost > 0) return cost.lastCost;
      return product?.usdCost ?? 0.0;
    }

    if (product == null || !product.trackStock) {
      return InventoryCostResult(
        method: costingMethod,
        unitCost: fallbackCost(),
      );
    }

    if (costingMethod != InventoryCostingMethod.fifo) {
      return InventoryCostResult(
        method: costingMethod,
        unitCost: fallbackCost(),
      );
    }

    var qtyToConsume = item.effectiveBaseQuantity;
    final consumptions = <InventoryCostLayerConsumption>[];
    final layers = (await BusinessSqliteStore.readInventoryCostLayers(db))
        .where((layer) =>
            layer.productId == item.productId &&
            layer.quantityRemaining > 0.000001)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final layer in layers) {
      if (qtyToConsume <= 0.000001) break;
      final consumed = min(qtyToConsume, layer.quantityRemaining);
      if (consumed <= 0.000001) continue;
      consumptions.add(InventoryCostLayerConsumption(
        layerId: layer.id,
        quantity: consumed,
        unitCost: layer.unitCost,
        currencyCode: layer.currencyCode,
      ));
      final remaining = max(0.0, layer.quantityRemaining - consumed);
      // inventory_cost_layers is the authoritative FIFO valuation table. Consume
      // the exact layer directly inside the outer sale transaction instead of
      // round-tripping through the generic entity upsert path. Besides being
      // atomic with stock/batch/accounting posting, the optimistic quantity
      // predicate prevents a stale layer snapshot from overwriting a concurrent
      // change.
      final changed = await db.customUpdate(
        r'''
        UPDATE inventory_cost_layers
        SET quantity_remaining = ?,
            is_closed = ?,
            updated_at = ?
        WHERE id = ?
          AND deleted_at = ''
          AND ABS(quantity_remaining - ?) <= 0.000001
        ''',
        variables: <Variable<Object>>[
          Variable<double>(remaining),
          Variable<int>(remaining <= 0.000001 ? 1 : 0),
          Variable<String>(now.toUtc().toIso8601String()),
          Variable<String>(layer.id),
          Variable<double>(layer.quantityRemaining),
        ],
      );
      if (changed != 1) {
        throw StateError(
          'FIFO layer ${layer.id} changed before sale consumption could be committed safely.',
        );
      }
      final persisted = await db.customSelect(
        r'''
        SELECT quantity_remaining
        FROM inventory_cost_layers
        WHERE id = ? AND deleted_at = ''
        LIMIT 1
        ''',
        variables: <Variable<Object>>[Variable<String>(layer.id)],
      ).getSingleOrNull();
      final persistedRemaining =
          (persisted?.data['quantity_remaining'] as num? ?? double.nan)
              .toDouble();
      if (!persistedRemaining.isFinite ||
          (persistedRemaining - remaining).abs() > 0.000001) {
        throw StateError(
          'FIFO layer ${layer.id} consumption was not persisted atomically.',
        );
      }
      qtyToConsume -= consumed;
    }

    if (qtyToConsume > 0.000001) {
      if (!allowNegativeStock) {
        throw StateError(
          'FIFO cost layers are insufficient for ${product.name}. Reconcile inventory costing before completing the sale.',
        );
      }
      final fallback = fallbackCost();
      consumptions.add(InventoryCostLayerConsumption(
        layerId:
            'negative_stock_${item.productId}_${now.microsecondsSinceEpoch}',
        quantity: qtyToConsume,
        unitCost: fallback,
        currencyCode: 'USD',
      ));
    }

    final totalQty = item.effectiveBaseQuantity;
    final totalCost =
        consumptions.fold<double>(0, (sum, entry) => sum + entry.totalCost);
    return InventoryCostResult(
      method: costingMethod,
      unitCost: totalQty <= 0 ? 0.0 : totalCost / totalQty,
      consumptions: consumptions,
    );
  }
}
