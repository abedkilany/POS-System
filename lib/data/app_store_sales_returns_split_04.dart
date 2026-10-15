part of 'app_store.dart';

extension _AppStoreSplitSalesReturnsPart4 on AppStore {
  int _saleOperationalVersion(Sale sale) {
    final raw = sale.postedSnapshot?.extra['postedEditVersion'];
    final parsed =
        raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
    return parsed != null && parsed > 1 ? parsed : 1;
  }

  String _saleStockMovementId({
    required Sale sale,
    required SaleItem item,
    required BatchAllocation allocation,
    required int lineIndex,
    int? operationalVersion,
  }) {
    final effectiveVersion =
        operationalVersion ?? _saleOperationalVersion(sale);
    final versionSuffix =
        effectiveVersion <= 1 ? 'sale' : 'sale-edit-v$effectiveVersion';
    // A legacy sale may receive a synthetic batch only when it is returned.
    // That synthetic batch belongs to the return movement, not to the
    // original sale movement. Keep the source id identical to the original
    // unbatched sale line so reversibility and audit links remain valid.
    final sourceLine = lineIndex >= 0 && lineIndex < sale.items.length
        ? sale.items[lineIndex]
        : null;
    final includeBatch = (sourceLine?.batchAllocations.isNotEmpty ?? false) &&
        allocation.batchId.trim().isNotEmpty;
    return includeBatch
        ? '${sale.id}-${_operationalProductIdForStorage(item.productId)}-${allocation.batchId}-$versionSuffix-$lineIndex'
        : '${sale.id}-${_operationalProductIdForStorage(item.productId)}-$versionSuffix-$lineIndex';
  }

  String _saleStockMovementIdempotencyKey({
    required Sale sale,
    required int lineIndex,
    required int batchIndex,
    required bool hasBatch,
    int? operationalVersion,
  }) {
    final effectiveVersion =
        operationalVersion ?? _saleOperationalVersion(sale);
    final family =
        effectiveVersion <= 1 ? 'sale' : 'sale_edit:v$effectiveVersion';
    return hasBatch
        ? '${sale.id}:$family:$lineIndex:$batchIndex'
        : '${sale.id}:$family:$lineIndex';
  }

  String _saleMovementGroupId(
    Sale sale, {
    int? operationalVersion,
  }) {
    final effectiveVersion =
        operationalVersion ?? _saleOperationalVersion(sale);
    return effectiveVersion <= 1
        ? sale.id
        : '${sale.id}:sale_edit:v$effectiveVersion';
  }

  Future<Map<String, double>> _returnedSaleQuantitiesByProduct(
    String saleId,
  ) async {
    await ensureCreditNotesLoaded();
    final totals = <String, double>{};
    for (final note in _creditNotes) {
      if (note.originalSaleId != saleId) continue;
      final status = note.status.trim().toLowerCase();
      if (status == 'cancelled' || status == 'reversed' || status == 'void') {
        continue;
      }
      for (final item in note.items) {
        totals.update(
          item.productId,
          (value) => value + item.quantity,
          ifAbsent: () => item.quantity,
        );
      }
    }
    return totals;
  }

  Future<double?> _remainingReversibleStockQuantityInTransaction(
    dynamic sqliteDb,
    String movementId,
  ) async {
    final rows = await sqliteDb.customSelect(
      '''
      SELECT
        ABS(sm.quantity) AS original_quantity,
        COALESCE((
          SELECT SUM(ABS(r.quantity))
          FROM stock_movements r
          WHERE r.reversal_of_movement_id = sm.id
            AND r.deleted_at = ''
            AND NOT EXISTS (
              SELECT 1 FROM stock_movements rr
              WHERE rr.reversal_of_movement_id = r.id
                AND rr.deleted_at = ''
            )
        ), 0) AS reversed_quantity
      FROM stock_movements sm
      WHERE sm.id = ?
        AND sm.deleted_at = ''
      LIMIT 1
      ''',
      variables: <Variable<Object>>[Variable<String>(movementId)],
    ).get();
    if (rows.isEmpty) return null;
    final original =
        (rows.first.data['original_quantity'] as num? ?? 0).toDouble();
    final reversed =
        (rows.first.data['reversed_quantity'] as num? ?? 0).toDouble();
    return (original - reversed).clamp(0, double.infinity).toDouble();
  }

  List<BatchAllocation> _sliceBatchAllocationsForReturn(
    List<BatchAllocation> source, {
    required double offset,
    required double quantity,
  }) {
    if (source.isEmpty || quantity <= 0) return const <BatchAllocation>[];
    var skip = offset.clamp(0, double.infinity).toDouble();
    var remaining = quantity;
    final result = <BatchAllocation>[];
    for (final allocation in source) {
      if (remaining <= 0.0000001) break;
      var available = allocation.quantity;
      if (skip >= available - 0.0000001) {
        skip -= available;
        continue;
      }
      if (skip > 0) {
        available -= skip;
        skip = 0;
      }
      final take = min(available, remaining);
      if (take > 0.0000001) {
        result.add(BatchAllocation(
          batchId: allocation.batchId,
          quantity: take,
          unitCost: allocation.unitCost,
          supplierBatchNumber: allocation.supplierBatchNumber,
          manufacturingDate: allocation.manufacturingDate,
          expirationDate: allocation.expirationDate,
        ));
        remaining -= take;
      }
    }
    return result;
  }

  List<InventoryCostLayerConsumption> _sliceCostConsumptionsForReturn(
    List<InventoryCostLayerConsumption> source, {
    required double offset,
    required double quantity,
  }) {
    if (source.isEmpty || quantity <= 0) {
      return const <InventoryCostLayerConsumption>[];
    }
    var skip = offset.clamp(0, double.infinity).toDouble();
    var remaining = quantity;
    final result = <InventoryCostLayerConsumption>[];
    for (final consumption in source) {
      if (remaining <= 0.0000001) break;
      var available = consumption.quantity;
      if (skip >= available - 0.0000001) {
        skip -= available;
        continue;
      }
      if (skip > 0) {
        available -= skip;
        skip = 0;
      }
      final take = min(available, remaining);
      if (take > 0.0000001) {
        result.add(InventoryCostLayerConsumption(
          layerId: consumption.layerId,
          quantity: take,
          unitCost: consumption.unitCost,
          currencyCode: consumption.currencyCode,
        ));
        remaining -= take;
      }
    }
    return result;
  }
}
