part of 'batch_inventory_service.dart';

extension BatchInventoryServiceSplitPart2 on BatchInventoryService {

  /// Phase 1 unified batch entry point.
  ///
  /// Unlike the legacy expiry-only helpers above, this method is valid for
  /// every stock-tracked product. Expiry-tracked products must carry an expiry
  /// date; non-expiry products are forbidden from carrying one. A stable
  /// [sourceLineId] makes the operation idempotent at the document-line level.
  Future<BatchAllocation> addUnifiedBatchStockInTransaction({
    required Product product,
    required String warehouseId,
    required String batchId,
    required double quantity,
    required double unitCost,
    required String sourceType,
    required String sourceId,
    required String sourceLineId,
    required DateTime receivedAt,
    required String storeId,
    required String branchId,
    required String deviceId,
    String supplierBatchNumber = '',
    DateTime? manufacturingDate,
    DateTime? expirationDate,
    String costCurrency = 'USD',
    double exchangeRate = 1,
  }) async {
    if (!product.trackStock) {
      throw LocalizedDomainException(
        'error_batch_requires_stock_tracking',
        values: {'product': product.name},
        fallback: 'Batch inventory requires stock tracking for ${product.name}.',
      );
    }
    final normalizedBatchId = batchId.trim();
    final normalizedSourceType = sourceType.trim();
    final normalizedSourceId = sourceId.trim();
    final normalizedSourceLineId = sourceLineId.trim();
    if (normalizedBatchId.isEmpty ||
        normalizedSourceType.isEmpty ||
        normalizedSourceId.isEmpty ||
        normalizedSourceLineId.isEmpty) {
      throw const LocalizedDomainException(
        'error_batch_identity_required',
        fallback: 'Batch and source line identity are required.',
      );
    }
    if (quantity <= 0) {
      throw const LocalizedDomainException(
        'error_batch_quantity_positive',
        fallback: 'Batch quantity must be greater than zero.',
      );
    }
    if (unitCost < 0 || exchangeRate <= 0) {
      throw const LocalizedDomainException(
        'error_batch_cost_invalid',
        fallback: 'Batch unit cost and exchange rate must be valid.',
      );
    }
    _validateUnifiedExpiryContract(
      product: product,
      expirationDate: expirationDate,
      receivedAt: receivedAt,
    );

    final existing = await db.customSelect(
      '''
      SELECT id, product_id, unit_cost, initial_quantity, expiration_date
      FROM inventory_batches
      WHERE store_id = ? AND source_type = ? AND source_id = ?
        AND source_line_id = ?
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(normalizedSourceType),
        Variable<String>(normalizedSourceId),
        Variable<String>(normalizedSourceLineId),
      ],
    ).getSingleOrNull();
    if (existing != null) {
      final existingId = existing.read<String>('id');
      final existingProductId = existing.read<String>('product_id');
      final existingCost = existing.read<double>('unit_cost');
      final existingInitialQuantity =
          existing.read<double>('initial_quantity');
      final existingExpiry =
          DateTime.tryParse(existing.read<String>('expiration_date'));
      if (existingId != normalizedBatchId ||
          existingProductId != product.id ||
          (existingCost - unitCost).abs() > 0.000001 ||
          (existingInitialQuantity - quantity).abs() > 0.000001 ||
          !_sameCalendarDate(existingExpiry, expirationDate)) {
        throw const LocalizedDomainException(
          'error_batch_source_line_conflict',
          fallback:
              'This document line is already linked to a different batch definition.',
        );
      }
      return BatchAllocation(
        batchId: existingId,
        quantity: quantity,
        supplierBatchNumber: supplierBatchNumber.trim(),
        manufacturingDate: manufacturingDate,
        expirationDate: expirationDate,
        unitCost: existingCost,
      );
    }

    final nowText = receivedAt.toUtc().toIso8601String();
    final normalizedCurrency = costCurrency.trim().isEmpty
        ? 'USD'
        : costCurrency.trim().toUpperCase();
    await db.customStatement(
      '''
      INSERT INTO inventory_batches
        (id, product_id, product_name, supplier_batch_number,
         manufacturing_date, expiration_date, status, source_type, source_id,
         source_line_id, unit_cost, initial_quantity, cost_currency,
         exchange_rate, received_at, store_id, branch_id, created_at,
         updated_at, device_id,
         last_modified_by_device_id, sync_status, version)
      VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 1)
      ''',
      <Object?>[
        normalizedBatchId,
        product.id,
        product.name,
        supplierBatchNumber.trim(),
        manufacturingDate?.toUtc().toIso8601String() ?? '',
        expirationDate == null ? '' : _calendarDateText(expirationDate),
        normalizedSourceType,
        normalizedSourceId,
        normalizedSourceLineId,
        unitCost,
        quantity,
        normalizedCurrency,
        exchangeRate,
        nowText,
        storeId,
        branchId,
        nowText,
        nowText,
        deviceId,
        deviceId,
      ],
    );

    final settledDeficitQuantity = normalizedSourceType == 'inventory_deficit'
        ? 0.0
        : await _settleOpenDeficitsWithIncomingBatchInTransaction(
            productId: product.id,
            productName: product.name,
            warehouseId: warehouseId,
            incomingBatchId: normalizedBatchId,
            incomingQuantity: quantity,
            actualUnitCost: unitCost,
            settledAt: receivedAt,
            storeId: storeId,
            branchId: branchId,
            deviceId: deviceId,
            postAccountingAdjustments: true,
          );
    final balanceQuantity = (quantity - settledDeficitQuantity) < 0.000001
        ? 0.0
        : quantity - settledDeficitQuantity;
    final balanceId =
        '$storeId::$warehouseId::${product.id}::$normalizedBatchId';
    await db.customStatement(
      '''
      INSERT INTO inventory_batch_balances
        (id, batch_id, product_id, warehouse_id, store_id, branch_id,
         quantity, reserved_quantity, version, created_at, updated_at,
         device_id, last_modified_by_device_id, sync_status)
      VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1, ?, ?, ?, ?, 'pending')
      ''',
      <Object?>[
        balanceId,
        normalizedBatchId,
        product.id,
        warehouseId,
        storeId,
        branchId,
        balanceQuantity,
        nowText,
        nowText,
        deviceId,
        deviceId,
      ],
    );
    return BatchAllocation(
      batchId: normalizedBatchId,
      quantity: quantity,
      supplierBatchNumber: supplierBatchNumber.trim(),
      manufacturingDate: manufacturingDate,
      expirationDate: expirationDate,
      unitCost: unitCost,
    );
  }

  /// Idempotent Phase-2 cutover for one product/warehouse.
  ///
  /// Non-expiry legacy stock can be represented by one opening batch because
  /// no historical lot identity existed before Unified Batch. Expiry-tracked
  /// stock must already be fully represented by real expiry batches.
  Future<void> ensureUnifiedCutoverInTransaction({
    required Product product,
    required String warehouseId,
    required double openingUnitCost,
    required DateTime cutoverAt,
    required String storeId,
    required String branchId,
    required String deviceId,
  }) async {
    if (!product.trackStock) return;
    final markerId = '$storeId::$warehouseId::${product.id}';
    final existingMarker = await db.customSelect(
      '''
      SELECT id FROM unified_batch_cutovers
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
      ],
    ).getSingleOrNull();
    if (existingMarker != null) {
      final check = await checkWarehouseBatchBalanceInTransaction(
        productId: product.id,
        warehouseId: warehouseId,
        storeId: storeId,
      );
      if (!check.isConsistent) {
        throw LocalizedDomainException(
          'error_batch_cutover_mismatch',
          values: {'product': product.name},
          fallback:
              'رصيد الدُفعات لا يطابق رصيد المستودع للمنتج ${product.name}.',
        );
      }
      return;
    }

    // Legacy expiry batches predate unit-cost persistence. Before the first
    // Unified cutover, recover an exact purchase-line cost when that relation
    // exists; otherwise use the current documented carrying/opening cost as a
    // cutover snapshot. This prevents old expiry lots from producing zero COGS
    // merely because their batch rows were created before Phase 1.
    final safeOpeningCost = openingUnitCost < 0 ? 0.0 : openingUnitCost;
    await db.customStatement(
      '''
      UPDATE inventory_batches
      SET unit_cost = COALESCE((
            SELECT CASE
              WHEN pi.conversion_to_base > 0
                THEN pi.unit_cost / pi.conversion_to_base
              ELSE pi.unit_cost
            END
            FROM purchase_item_batch_allocations pba
            JOIN purchase_items pi ON pi.id = pba.purchase_item_id
            WHERE pba.batch_id = inventory_batches.id
              AND pi.product_id = inventory_batches.product_id
              AND pi.unit_cost > 0
            ORDER BY pba.line_no ASC
            LIMIT 1
          ), CASE WHEN ? > 0 THEN ? ELSE inventory_batches.unit_cost END),
          cost_currency = CASE
            WHEN unit_cost <= 0 AND ? > 0 THEN 'USD'
            ELSE cost_currency
          END,
          updated_at = ?,
          device_id = ?,
          last_modified_by_device_id = ?,
          sync_status = 'pending'
      WHERE store_id = ? AND product_id = ? AND unit_cost <= 0
        AND EXISTS (
          SELECT 1
          FROM inventory_batch_balances bb
          WHERE bb.batch_id = inventory_batches.id
            AND bb.store_id = inventory_batches.store_id
            AND bb.product_id = inventory_batches.product_id
            AND bb.warehouse_id = ?
        )
      ''',
      <Object?>[
        safeOpeningCost,
        safeOpeningCost,
        safeOpeningCost,
        cutoverAt.toUtc().toIso8601String(),
        deviceId,
        deviceId,
        storeId,
        product.id,
        warehouseId,
      ],
    );

    final warehouseRow = await db.customSelect(
      '''
      SELECT COALESCE(quantity, 0) AS quantity
      FROM warehouse_inventory
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
      ],
    ).getSingleOrNull();
    final warehouseQuantity =
        (warehouseRow?.data['quantity'] as num?)?.toDouble() ?? 0.0;
    final batchRow = await db.customSelect(
      '''
      SELECT COALESCE(SUM(bb.quantity), 0) AS quantity
      FROM inventory_batch_balances bb
      JOIN inventory_batches b ON b.id = bb.batch_id
        AND b.product_id = bb.product_id AND b.store_id = bb.store_id
      WHERE bb.store_id = ? AND bb.warehouse_id = ? AND bb.product_id = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
      ],
    ).getSingle();
    final physicalBatchQuantity =
        (batchRow.data['quantity'] as num?)?.toDouble() ?? 0.0;
    final deficitRow = await db.customSelect(
      '''
      SELECT COALESCE(SUM(quantity_open), 0) AS quantity
      FROM inventory_stock_deficits
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
        AND status = 'open' AND quantity_open > 0.000001
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
      ],
    ).getSingle();
    final deficitQuantity =
        (deficitRow.data['quantity'] as num?)?.toDouble() ?? 0.0;
    final batchQuantity = physicalBatchQuantity - deficitQuantity;
    final difference = warehouseQuantity - batchQuantity;
    const tolerance = 0.000001;

    String openingBatchId = '';
    double openingQuantity = 0;

    // Legacy warehouse stock may already be negative before Unified Batch is
    // activated. Preserve that valid historical state by converting the
    // missing quantity into a tracked deficit during cutover. Positive stock
    // with excess batch quantity remains a hard integrity error.
    if (difference < -tolerance) {
      if (warehouseQuantity < -tolerance) {
        final legacyDeficitQuantity = -difference;
        final legacyDeficitBatchId =
            'deficit:cutover:$storeId:$warehouseId:${product.id}'
                .replaceAll(' ', '_');
        final provisionalUnitCost =
            await _provisionalDeficitUnitCostInTransaction(
          product: product,
          warehouseId: warehouseId,
          storeId: storeId,
        );
        await _ensureDeficitBatchAndRecordInTransaction(
          productId: product.id,
          productName: product.name,
          warehouseId: warehouseId,
          deficitBatchId: legacyDeficitBatchId,
          quantity: legacyDeficitQuantity,
          provisionalUnitCost: provisionalUnitCost,
          createdAt: cutoverAt,
          storeId: storeId,
          branchId: branchId,
          deviceId: deviceId,
          expiryTracked: product.expiryTrackingEnabled,
          syncStatus: 'pending',
        );
      } else {
        throw LocalizedDomainException(
          'error_batch_cutover_overstated',
          values: {'product': product.name},
          fallback:
              'Batch stock exceeds warehouse stock for ${product.name}; cutover was stopped.',
        );
      }
    } else if (difference > tolerance) {
      if (product.expiryTrackingEnabled) {
        throw LocalizedDomainException(
          'error_batch_cutover_expiry_missing',
          values: {'product': product.name},
          fallback:
              'Expiry-tracked stock for ${product.name} is not fully represented by batches.',
        );
      }
      openingBatchId =
          'opening_${storeId}_${warehouseId}_${product.id}'.replaceAll(' ', '_');
      openingQuantity = difference;
      await addUnifiedBatchStockInTransaction(
        product: product,
        warehouseId: warehouseId,
        batchId: openingBatchId,
        quantity: difference,
        unitCost: openingUnitCost < 0 ? 0 : openingUnitCost,
        sourceType: 'unified_batch_opening',
        sourceId: warehouseId,
        sourceLineId: 'cutover:${product.id}:$warehouseId',
        receivedAt: cutoverAt,
        storeId: storeId,
        branchId: branchId,
        deviceId: deviceId,
        costCurrency: 'USD',
        exchangeRate: 1,
      );
    }

    final check = await checkWarehouseBatchBalanceInTransaction(
      productId: product.id,
      warehouseId: warehouseId,
      storeId: storeId,
    );
    if (!check.isConsistent) {
      throw LocalizedDomainException(
        'error_batch_cutover_mismatch',
        values: {'product': product.name},
        fallback:
            'تعذر مطابقة رصيد الدُفعات مع رصيد المستودع للمنتج ${product.name} أثناء الترحيل.',
      );
    }
    final nowText = cutoverAt.toUtc().toIso8601String();
    await db.customStatement(
      '''
      INSERT INTO unified_batch_cutovers
        (id, store_id, warehouse_id, product_id, cutover_at,
         opening_batch_id, opening_quantity, opening_unit_cost,
         created_at, device_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        markerId,
        storeId,
        warehouseId,
        product.id,
        nowText,
        openingBatchId,
        openingQuantity,
        openingUnitCost < 0 ? 0 : openingUnitCost,
        nowText,
        deviceId,
      ],
    );
  }

  /// Resolves the best known positive reference cost for a stock-tracked
  /// product without changing inventory. The resolution order intentionally
  /// mirrors negative-stock provisional costing: latest real Batch cost first,
  /// then ProductCost, then the user-maintained Product reference cost.
  ///
  /// Manufacturing and inventory-count repair use this when a legacy/current
  /// physical Batch exists with a zero carrying cost. Keeping the resolver in
  /// one place prevents those flows from inventing a different valuation rule.
  Future<double> resolveReferenceUnitCostInTransaction({
    required Product product,
    required String warehouseId,
    required String storeId,
  }) =>
      _provisionalDeficitUnitCostInTransaction(
        product: product,
        warehouseId: warehouseId,
        storeId: storeId,
      );

  Future<double> _provisionalDeficitUnitCostInTransaction({
    required Product product,
    required String warehouseId,
    required String storeId,
  }) async {
    final row = await db.customSelect(
      '''
      SELECT b.unit_cost
      FROM inventory_batches b
      LEFT JOIN inventory_batch_balances bb ON bb.batch_id = b.id
        AND bb.store_id = b.store_id AND bb.product_id = b.product_id
        AND bb.warehouse_id = ?
      WHERE b.store_id = ? AND b.product_id = ?
        AND b.source_type <> 'inventory_deficit'
        AND b.id NOT LIKE 'deficit:%'
        AND b.unit_cost > 0
      ORDER BY CASE WHEN bb.batch_id IS NULL THEN 1 ELSE 0 END ASC,
               CASE WHEN trim(b.received_at) = '' THEN b.created_at ELSE b.received_at END DESC,
               b.id DESC
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(warehouseId),
        Variable<String>(storeId),
        Variable<String>(product.id),
      ],
    ).getSingleOrNull();
    final batchCost = (row?.data['unit_cost'] as num?)?.toDouble() ?? 0.0;
    if (batchCost > 0) return batchCost;

    // ProductCost is the authoritative current reference-cost snapshot used by
    // the rest of Ventio. Negative-stock flows need the same fallback so a
    // temporary shortage does not silently become a zero-cost deficit merely
    // because Product.usdCost was not populated.
    final productCostRow = await db.customSelect(
      '''
      SELECT average_cost, last_cost
      FROM product_costs
      WHERE product_id = ? AND deleted_at = ''
      ORDER BY updated_at DESC, id DESC
      LIMIT 1
      ''',
      variables: <Variable<Object>>[Variable<String>(product.id)],
    ).getSingleOrNull();
    final averageCost =
        (productCostRow?.data['average_cost'] as num?)?.toDouble() ?? 0.0;
    if (averageCost > 0) return averageCost;
    final lastCost =
        (productCostRow?.data['last_cost'] as num?)?.toDouble() ?? 0.0;
    if (lastCost > 0) return lastCost;
    if (product.usdCost > 0) return product.usdCost;
    if (product.cost > 0) return product.cost;
    return 0.0;
  }

  Future<UnifiedBatchCostPreview> previewUnifiedAllocationInTransaction({
    required Product product,
    required String warehouseId,
    required double quantity,
    required DateTime movementDate,
    required String storeId,
    bool includeProvisionalShortage = false,
  }) async {
    if (!product.trackStock || quantity <= 0) {
      return UnifiedBatchCostPreview(
        requestedQuantity: quantity < 0 ? 0 : quantity,
        physicalQuantity: 0,
        shortageQuantity: 0,
        totalCost: 0,
        unitCost: 0,
        usesProvisionalCost: false,
        provisionalUnitCost: 0,
      );
    }
    final startOfMovementDay = _calendarDateText(movementDate);
    final expiryPredicate = product.expiryTrackingEnabled
        ? "trim(b.expiration_date) <> '' AND substr(b.expiration_date, 1, 10) >= ?"
        : "trim(b.expiration_date) = ''";
    final ordering = product.expiryTrackingEnabled
        ? '''substr(b.expiration_date, 1, 10) ASC,
             CASE WHEN trim(b.received_at) = '' THEN b.created_at ELSE b.received_at END ASC,
             b.id ASC'''
        : '''CASE WHEN trim(b.received_at) = '' THEN b.created_at ELSE b.received_at END ASC,
             b.id ASC''';
    final rows = await db.customSelect(
      '''
      SELECT b.id AS batch_id, b.unit_cost,
             bb.quantity, bb.reserved_quantity
      FROM inventory_batch_balances bb
      JOIN inventory_batches b ON b.id = bb.batch_id
        AND b.product_id = bb.product_id AND b.store_id = bb.store_id
      WHERE bb.store_id = ? AND bb.warehouse_id = ? AND bb.product_id = ?
        AND b.status = 'active'
        AND b.source_type <> 'inventory_deficit'
        AND b.id NOT LIKE 'deficit:%'
        AND (bb.quantity - bb.reserved_quantity) > 0.000001
        AND $expiryPredicate
      ORDER BY $ordering
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
        if (product.expiryTrackingEnabled)
          Variable<String>(startOfMovementDay),
      ],
    ).get();

    var remaining = quantity;
    var physicalQuantity = 0.0;
    var totalCost = 0.0;
    for (final row in rows) {
      if (remaining <= 0.000001) break;
      final available =
          row.read<double>('quantity') - row.read<double>('reserved_quantity');
      final used = available < remaining ? available : remaining;
      if (used <= 0) continue;
      physicalQuantity += used;
      totalCost += used * row.read<double>('unit_cost');
      remaining -= used;
    }
    var usesProvisionalCost = false;
    var provisionalUnitCost = 0.0;
    if (remaining > 0.000001 && includeProvisionalShortage) {
      provisionalUnitCost = await _provisionalDeficitUnitCostInTransaction(
        product: product,
        warehouseId: warehouseId,
        storeId: storeId,
      );
      totalCost += remaining * provisionalUnitCost;
      usesProvisionalCost = true;
    }
    final unitCost = quantity <= 0.000001 ? 0.0 : totalCost / quantity;
    return UnifiedBatchCostPreview(
      requestedQuantity: quantity,
      physicalQuantity: physicalQuantity,
      shortageQuantity: remaining <= 0.000001 ? 0.0 : remaining,
      totalCost: totalCost,
      unitCost: unitCost,
      usesProvisionalCost: usesProvisionalCost,
      provisionalUnitCost: provisionalUnitCost,
    );
  }

  Future<void> requirePhysicalUnifiedStockInTransaction({
    required Product product,
    required String warehouseId,
    required double quantity,
    required DateTime movementDate,
    required String storeId,
    String operation = 'operation',
  }) async {
    final preview = await previewUnifiedAllocationInTransaction(
      product: product,
      warehouseId: warehouseId,
      quantity: quantity,
      movementDate: movementDate,
      storeId: storeId,
    );
    if (!preview.hasShortage) return;
    throw LocalizedDomainException(
      'error_physical_batch_stock_required',
      values: <String, Object?>{
        'product': product.name,
        'required': quantity,
        'available': preview.physicalQuantity,
        'operation': operation,
      },
      fallback:
          'The $operation requires physical batch stock for ${product.name}. Required: $quantity, available: ${preview.physicalQuantity}.',
    );
  }

  Future<void> removeUnifiedInboundInTransaction({
    required Product product,
    required String warehouseId,
    required String batchId,
    required double quantity,
    required DateTime removedAt,
    required String storeId,
    required String deviceId,
  }) async {
    if (!product.trackStock || quantity <= 0) return;
    final normalizedBatchId = batchId.trim();
    if (normalizedBatchId.isEmpty) {
      throw const LocalizedDomainException(
        'error_batch_restore_invalid',
        fallback: 'A valid batch identity is required.',
      );
    }
    if (BatchInventoryService.isDeficitBatchId(normalizedBatchId)) {
      throw const LocalizedDomainException(
        'error_deficit_inbound_reverse_unsupported',
        fallback:
            'This returned negative-stock deficit cannot be edited safely. Reverse the dependent transaction first and recreate it.',
      );
    }
    final settlementRow = await db.customSelect(
      '''
      SELECT COALESCE(SUM(ids.quantity - ids.reversed_quantity), 0) AS active_qty
      FROM inventory_deficit_settlements ids
      INNER JOIN inventory_stock_deficits d ON d.id = ids.deficit_id
      WHERE ids.incoming_batch_id = ?
        AND d.store_id = ? AND d.warehouse_id = ? AND d.product_id = ?
        AND ids.status <> 'reversed'
        AND ids.quantity - ids.reversed_quantity > 0.000001
      ''',
      variables: <Variable<Object>>[
        Variable<String>(normalizedBatchId),
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
      ],
    ).getSingle();
    final settledQuantity =
        (settlementRow.data['active_qty'] as num? ?? 0).toDouble();
    if (settledQuantity > 0.000001) {
      throw LocalizedDomainException(
        'error_inbound_batch_settled_deficit',
        values: <String, Object?>{
          'product': product.name,
          'batch': normalizedBatchId,
        },
        fallback:
            'Batch $normalizedBatchId for ${product.name} has already settled an earlier negative-stock deficit. Reverse the dependent deficit movement first.',
      );
    }
    await adjustUnifiedBatchInTransaction(
      product: product,
      warehouseId: warehouseId,
      batchId: normalizedBatchId,
      quantityDelta: -quantity,
      adjustedAt: removedAt,
      storeId: storeId,
      deviceId: deviceId,
    );
  }
}
