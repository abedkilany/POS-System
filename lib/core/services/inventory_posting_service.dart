import 'dart:math';
import '../../models/product_costing.dart';
import 'package:drift/drift.dart';
import '../../models/app_identity.dart';
import '../../models/product.dart';
import '../../models/stock_movement.dart';
import '../../models/warehouse.dart';
import '../localization/localized_domain_exception.dart';
import '../storage/sqlite/ventio_drift_database.dart';
import 'batch_inventory_service.dart';

/// Shared batch preparation and reconciliation inside an existing transaction.
/// This service never reads or mutates application caches.
class InventoryPostingService {
  const InventoryPostingService(this.sqliteDb, this.identity,
      {required this.productCostFor});
  final VentioDriftDatabase sqliteDb;
  final AppIdentity identity;
  final ProductCost Function(String) productCostFor;

  Future<double> openingUnitCost({
    required Product product,
    required String warehouseId,
  }) async {
    final row = await sqliteDb.customSelect(
      '''
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
        Variable<String>(identity.storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
        Variable<String>(identity.storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
      ],
    ).getSingle();
    final warehouseQuantity =
        (row.data['warehouse_quantity'] as num? ?? 0).toDouble();
    final movementCount = (row.data['movement_count'] as num? ?? 0).toInt();
    final movementQuantity =
        (row.data['movement_quantity'] as num? ?? 0).toDouble();
    final carryingValue = (row.data['carrying_value'] as num? ?? 0).toDouble();
    const tolerance = 0.000001;
    if (warehouseQuantity > tolerance &&
        movementCount > 0 &&
        (movementQuantity - warehouseQuantity).abs() <= tolerance &&
        carryingValue >= -tolerance) {
      final movementUnitCost = max(0.0, carryingValue) / warehouseQuantity;
      if (movementUnitCost > tolerance) return movementUnitCost;
    }

    // A stock count can add quantity after the current warehouse reached zero.
    // In that case the movement aggregate above can legitimately be zero even
    // though this product has a reliable historical Unified Batch cost. Prefer
    // that real carrying-cost history before falling back to editable Product
    // reference fields so new count-overage batches never become zero-cost just
    // because ProductCost was empty at the moment of counting.
    final batchReferenceCost = await BatchInventoryService(sqliteDb)
        .resolveReferenceUnitCostInTransaction(
      product: product,
      warehouseId: warehouseId,
      storeId: identity.storeId,
    );
    if (batchReferenceCost > tolerance) return batchReferenceCost;

    final cost = productCostFor(product.id);
    if (cost.averageCost > 0) return cost.averageCost;
    if (product.usdCost > 0) return product.usdCost;
    if (product.cost > 0) return product.cost;
    return 0;
  }

  Future<void> ensureCutover({
    required Product product,
    required String warehouseId,
    required DateTime at,
  }) async {
    final phaseStateRow = await sqliteDb.customSelect(
      '''
      SELECT value FROM migration_meta
      WHERE key = 'unified_batch_phase4_state'
      LIMIT 1
      ''',
    ).getSingleOrNull();
    final phaseState =
        phaseStateRow?.data['value']?.toString().trim().toLowerCase() ?? '';
    if (phaseState == 'blocked') {
      throw LocalizedDomainException(
        'error_unified_batch_phase4_blocked',
        values: <String, Object?>{'product': product.name},
        fallback:
            'Unified Batch migration is blocked by an inventory reconciliation error. Repair inventory before posting new stock movements.',
      );
    }
    final resolvedOpeningCost = await openingUnitCost(
      product: product,
      warehouseId: warehouseId,
    );
    await BatchInventoryService(sqliteDb).ensureUnifiedCutoverInTransaction(
      product: product,
      warehouseId: warehouseId,
      openingUnitCost: resolvedOpeningCost,
      cutoverAt: at,
      storeId: identity.storeId,
      branchId: identity.branchId,
      deviceId: identity.deviceId,
    );
  }

  Future<void> assertMovementBalances(
    BatchInventoryService batchService,
    Iterable<StockMovement> movements,
  ) async {
    final unique = <String, StockMovement>{};
    for (final movement in movements) {
      if (movement.batchId.trim().isEmpty) continue;
      final storeId = movement.storeId.trim().isEmpty
          ? identity.storeId
          : movement.storeId.trim();
      final warehouseId = movement.warehouseId.trim().isEmpty
          ? Warehouse.defaultId
          : movement.warehouseId.trim();
      unique['$storeId::$warehouseId::${movement.productId}'] = movement;
    }
    for (final movement in unique.values) {
      await batchService.assertWarehouseBatchBalanceInTransaction(
        productId: movement.productId,
        warehouseId: movement.warehouseId.trim().isEmpty
            ? Warehouse.defaultId
            : movement.warehouseId.trim(),
        storeId: movement.storeId.trim().isEmpty
            ? identity.storeId
            : movement.storeId.trim(),
      );
    }
  }
}
