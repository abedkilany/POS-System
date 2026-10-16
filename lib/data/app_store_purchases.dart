part of 'app_store.dart';

extension _AppStoreSplitPurchases on AppStore {
  String _stablePurchaseLineId(
      Purchase purchase, PurchaseItem item, int lineIndex) {
    final existing = item.lineId.trim();
    return existing.isNotEmpty ? existing : '${purchase.id}:line:$lineIndex';
  }

  Future<double> _unifiedOpeningCostForProductInTransaction(
    dynamic sqliteDb, {
    required Product product,
    required String warehouseId,
  }) =>
      InventoryPostingService(sqliteDb, appIdentity,
              productCostFor: _productCostFor)
          .openingUnitCost(product: product, warehouseId: warehouseId);

  Future<void> _ensureUnifiedBatchCutoverForProductInTransaction(
    dynamic sqliteDb, {
    required Product product,
    required String warehouseId,
    required DateTime at,
  }) =>
      InventoryPostingService(sqliteDb, appIdentity,
              productCostFor: _productCostFor)
          .ensureCutover(product: product, warehouseId: warehouseId, at: at);

  Future<void> _assertUnifiedBatchMovementBalancesInTransaction(
    BatchInventoryService batchService,
    Iterable<StockMovement> movements,
  ) =>
      InventoryPostingService(batchService.db, appIdentity,
              productCostFor: _productCostFor)
          .assertMovementBalances(batchService, movements);

  double _purchaseInventoryUnitCostPerBase(
    PurchaseItem item, {
    required double legacyDefaultVatRatePercent,
  }) {
    final product = _findProductById(item.productId);
    if (product == null || item.baseQuantity <= 0) return item.unitCostPerBase;
    final taxProfile = _storeProfile.taxProfileById(
      product.taxProfileId,
      legacyDefaultRatePercent: legacyDefaultVatRatePercent,
    );
    final decimals =
        _storeProfile.currencyByCode(_storeProfile.baseCurrency).decimalPlaces;
    final tax = TaxCalculator.inclusive(
      item.lineTotal,
      taxProfile,
      decimals: decimals,
    );
    // Recoverable input VAT is not inventory cost. Keep the Batch/subledger cost
    // aligned with the taxable base posted to the inventory GL account.
    return tax.taxableBase / item.baseQuantity;
  }

  String _receivedPurchasePaymentStatus({
    required double paidAmount,
    required double total,
  }) {
    const tolerance = 0.000001;
    if (paidAmount <= tolerance) return 'credit';
    if (paidAmount >= total - tolerance) return 'paid';
    return 'partial';
  }

  Future<void> _rebuildProductCostsFromUnifiedBatchesInTransaction(
    dynamic sqliteDb, {
    required Set<String> productIds,
    required DateTime now,
  }) async {
    if (productIds.isEmpty) return;
    final rebuiltCosts = <ProductCost>[];
    final rebuiltProducts = <Product>[];
    for (final productId in productIds) {
      final normalizedProductId = productId.trim();
      if (normalizedProductId.isEmpty) continue;
      final product = _findProductById(normalizedProductId);
      if (product == null || !product.trackStock) continue;

      final valuation = await sqliteDb.customSelect(
        '''
      SELECT COALESCE(SUM(bb.quantity), 0) AS quantity,
             COALESCE(SUM(bb.quantity * b.unit_cost), 0) AS carrying_value
      FROM inventory_batch_balances bb
      INNER JOIN inventory_batches b ON b.id = bb.batch_id
      WHERE bb.store_id = ?
        AND bb.product_id = ?
        AND bb.quantity > 0.000001
      ''',
        variables: <Variable<Object>>[
          Variable<String>(appIdentity.storeId),
          Variable<String>(normalizedProductId),
        ],
      ).getSingle();
      final stockQuantity =
          (valuation.data['quantity'] as num? ?? 0).toDouble();
      final carryingValue =
          (valuation.data['carrying_value'] as num? ?? 0).toDouble();

      // Last purchase cost must come from the latest still-effective purchase
      // receipt, not merely from the batch row that happened to be updated last.
      // Reversed purchase receipts are excluded so an edited/returned historical
      // version cannot remain the compatibility cost authority.
      final latestPurchaseRow = await sqliteDb.customSelect(
        '''
      SELECT b.unit_cost
      FROM inventory_batches b
      INNER JOIN stock_movements sm ON sm.batch_id = b.id
      WHERE b.store_id = ?
        AND b.product_id = ?
        AND b.source_type = 'purchase'
        AND sm.movement_type = 'purchase_receive'
        AND sm.deleted_at = ''
        AND trim(sm.reversal_of_movement_id) = ''
        AND ABS(
          sm.quantity + COALESCE((
            SELECT SUM(reversal.quantity)
            FROM stock_movements reversal
            WHERE reversal.reversal_of_movement_id = sm.id
              AND reversal.deleted_at = ''
              AND NOT EXISTS (
                SELECT 1 FROM stock_movements reversal_of_reversal
                WHERE reversal_of_reversal.reversal_of_movement_id = reversal.id
                  AND reversal_of_reversal.deleted_at = ''
              )
          ), 0)
        ) > 0.000001
      ORDER BY COALESCE(NULLIF(trim(b.received_at), ''), b.created_at) DESC,
               sm.movement_date DESC,
               b.updated_at DESC,
               b.id DESC
      LIMIT 1
      ''',
        variables: <Variable<Object>>[
          Variable<String>(appIdentity.storeId),
          Variable<String>(normalizedProductId),
        ],
      ).getSingleOrNull();
      final latestPurchaseCost =
          (latestPurchaseRow?.data['unit_cost'] as num?)?.toDouble();
      final averageCost = stockQuantity > 0.000001
          ? carryingValue / stockQuantity
          : (latestPurchaseCost ?? 0);
      final lastCost = latestPurchaseCost ?? averageCost;
      if (!averageCost.isFinite ||
          averageCost < -0.000001 ||
          !lastCost.isFinite ||
          lastCost < -0.000001) {
        throw StateError(
          'Invalid rebuilt inventory cost for ${product.name}; purchase edit rolled back.',
        );
      }
      final currentCost = _productCostFor(normalizedProductId);
      final rebuiltCost = currentCost.copyWith(
        averageCost: max(0.0, averageCost),
        lastCost: max(0.0, lastCost),
        currencyCode: 'USD',
        updatedAt: now,
      );
      rebuiltCosts.add(rebuiltCost);
      // Product.cost/originalCost/usdCost are the user-maintained reference cost.
      // Unified Batch is authoritative for inventory valuation and must not
      // overwrite that reference when receipts/returns rebuild stock.
      rebuiltProducts.add(product.copyWith(
        stock: max(0.0, stockQuantity),
        updatedAt: now,
      ));
    }
    if (rebuiltCosts.isEmpty) return;
    await BusinessSqliteStore.upsertEntityPayloads(
      sqliteDb,
      AppStore._productCostsKey,
      rebuiltCosts.map((item) => item.toJson()).toList(growable: false),
    );
    await BusinessSqliteStore.upsertEntityPayloads(
      sqliteDb,
      AppStore._productsKey,
      rebuiltProducts.map((item) => item.toJson()).toList(growable: false),
    );
  }

  Future<BatchAllocation> _receiveUnifiedPurchaseLineInTransaction(
    dynamic sqliteDb, {
    required BatchInventoryService batchService,
    required Purchase purchase,
    required PurchaseItem item,
    required int lineIndex,
    required Product product,
    required String warehouseId,
    required DateTime receivedAt,
    required double inventoryUnitCost,
    Set<String>? ensuredCutovers,
  }) async {
    final cutoverKey = '${product.id}::$warehouseId';
    if (ensuredCutovers == null || ensuredCutovers.add(cutoverKey)) {
      await _ensureUnifiedBatchCutoverForProductInTransaction(
        sqliteDb,
        product: product,
        warehouseId: warehouseId,
        at: receivedAt,
      );
    }
    if (item.batchAllocations.length > 1) {
      throw StateError('Each purchase line must create exactly one batch.');
    }
    final requested =
        item.batchAllocations.isEmpty ? null : item.batchAllocations.first;
    final expiry = requested?.expirationDate;
    if (product.expiryTrackingEnabled && expiry == null) {
      throw StateError('Expiration date is required for ${product.name}.');
    }
    if (!product.expiryTrackingEnabled && expiry != null) {
      throw StateError('${product.name} does not track expiration dates.');
    }
    final stableLineId = _stablePurchaseLineId(purchase, item, lineIndex);
    final sourceLineId = '$stableLineId:v${purchase.version}';
    final batchId = 'batch:${purchase.id}:$sourceLineId';
    return batchService.addUnifiedBatchStockInTransaction(
      product: product,
      warehouseId: warehouseId,
      batchId: batchId,
      quantity: item.baseQuantity,
      unitCost: inventoryUnitCost,
      sourceType: 'purchase',
      sourceId: purchase.id,
      sourceLineId: sourceLineId,
      receivedAt: receivedAt,
      storeId: purchase.storeId,
      branchId: purchase.branchId,
      deviceId: purchase.deviceId,
      supplierBatchNumber: requested?.supplierBatchNumber ?? '',
      manufacturingDate: requested?.manufacturingDate,
      expirationDate: expiry,
      costCurrency: 'USD',
      exchangeRate: item.exchangeRateAtEntry > 0 ? item.exchangeRateAtEntry : 1,
    );
  }

  Future<List<StockMovement>>
      _activeDownstreamMovementsForPurchaseInTransaction(
    dynamic sqliteDb,
    Purchase purchase,
  ) async {
    final rows = await sqliteDb.customSelect(
      '''
      SELECT sm.*
      FROM stock_movements sm
      WHERE sm.batch_id IN (
        SELECT id FROM inventory_batches
        WHERE store_id = ? AND source_type = 'purchase' AND source_id = ?
      )
        AND sm.movement_type NOT IN ('purchase_receive', 'purchase_return')
        AND trim(sm.reversal_of_movement_id) = ''
        AND sm.deleted_at = ''
        AND ABS(
          sm.quantity + COALESCE((
            SELECT SUM(reversal.quantity)
            FROM stock_movements reversal
            WHERE reversal.reversal_of_movement_id = sm.id
              AND reversal.deleted_at = ''
              AND NOT EXISTS (
                SELECT 1 FROM stock_movements reversal_of_reversal
                WHERE reversal_of_reversal.reversal_of_movement_id = reversal.id
                  AND reversal_of_reversal.deleted_at = ''
              )
          ), 0)
        ) > 0.000001
      ORDER BY sm.movement_date ASC, sm.id ASC
      ''',
      variables: <Variable<Object>>[
        Variable<String>(appIdentity.storeId),
        Variable<String>(purchase.id),
      ],
    ).get();
    return rows
        .map<StockMovement>((row) => StockMovement.fromJson(<String, dynamic>{
              'id': row.data['id'],
              'productId': row.data['product_id'],
              'productName': row.data['product_name'],
              'type': row.data['movement_type'],
              'quantity': row.data['quantity'],
              'date': row.data['movement_date'],
              'referenceId': row.data['reference_id'],
              'referenceNo': row.data['reference_no'],
              'reason': row.data['reason'],
              'unitCost': row.data['unit_cost'],
              'warehouseId': row.data['warehouse_id'],
              'warehouseName': row.data['warehouse_name'],
              'batchId': row.data['batch_id'],
              'movementGroupId': row.data['movement_group_id'],
              'documentLineId': row.data['document_line_id'],
              'sourceMovementId': row.data['source_movement_id'],
              'reversalOfMovementId': row.data['reversal_of_movement_id'],
              'idempotencyKey': row.data['idempotency_key'],
              'createdAt': row.data['created_at'],
              'updatedAt': row.data['updated_at'],
              'deviceId': row.data['device_id'],
              'syncStatus': row.data['sync_status'],
              'storeId': row.data['store_id'],
              'branchId': row.data['branch_id'],
              'version': row.data['version'],
              'lastModifiedByDeviceId': row.data['last_modified_by_device_id'],
            }))
        .toList(growable: false);
  }

  Future<void> _requirePurchaseBatchesUnusedInTransaction(
    dynamic sqliteDb,
    Purchase purchase,
  ) async {
    final blockers = await _activeDownstreamMovementsForPurchaseInTransaction(
      sqliteDb,
      purchase,
    );
    if (blockers.isNotEmpty) {
      final first = blockers.first;
      throw StateError(
        'Cannot edit or cancel ${purchase.purchaseNo}: batch ${first.batchId} has an active ${first.type} movement (${first.referenceNo.isEmpty ? first.referenceId : first.referenceNo}). Reverse that movement first.',
      );
    }

    final deficitSettlement = await sqliteDb.customSelect(
      '''
      SELECT ids.id, ids.incoming_batch_id, ids.quantity, ids.reversed_quantity
      FROM inventory_deficit_settlements ids
      INNER JOIN inventory_batches b ON b.id = ids.incoming_batch_id
      WHERE b.store_id = ? AND b.source_type = 'purchase' AND b.source_id = ?
        AND ids.status <> 'reversed'
        AND ids.quantity - ids.reversed_quantity > 0.000001
      ORDER BY ids.settled_at ASC, ids.id ASC
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(appIdentity.storeId),
        Variable<String>(purchase.id),
      ],
    ).getSingleOrNull();
    if (deficitSettlement != null) {
      throw StateError(
        'Cannot edit or cancel ${purchase.purchaseNo}: part of its received batch has already settled an earlier negative-stock deficit. Reverse the dependent stock movement first.',
      );
    }

    // Legacy purchases may be mixed: an expiry line can already own a batch
    // while a non-expiry line from the same invoice has no historical batch.
    // Guard lineage per stock-tracked line rather than per purchase.
    final warehouseId = purchase.warehouseId.trim().isEmpty
        ? Warehouse.defaultId
        : purchase.warehouseId.trim();
    final legacyUnbatchedProductIds = <String>{};
    for (var lineIndex = 0; lineIndex < purchase.items.length; lineIndex += 1) {
      final item = purchase.items[lineIndex];
      final product = _findProductById(item.productId);
      if (product == null) {
        throw StateError('Product ${item.productId} was not found.');
      }
      if (!product.trackStock) continue;

      var receiptMovements = await _activePurchaseReceiveMovements(
        sqliteDb,
        purchaseId: purchase.id,
        productId: item.productId,
        documentLineId: _stablePurchaseLineId(purchase, item, lineIndex),
      );
      if (receiptMovements.isEmpty) {
        receiptMovements = await _activePurchaseReceiveMovements(
          sqliteDb,
          purchaseId: purchase.id,
          productId: item.productId,
          documentLineId: '${purchase.id}-line-$lineIndex',
        );
      }
      final hasLegacyUnbatchedReceipt = receiptMovements.any(
        (movement) => movement.batchId.trim().isEmpty,
      );
      if (!hasLegacyUnbatchedReceipt) continue;

      // Once a legacy no-batch receipt has been absorbed into an aggregate
      // opening batch, its exact lot lineage no longer exists. Reversing that
      // historical receipt would change warehouse_inventory without a safe
      // batch slice to reverse, so block it until the historical migration.
      final cutoverMarker = await sqliteDb.customSelect(
        '''
        SELECT id
        FROM unified_batch_cutovers
        WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
        LIMIT 1
        ''',
        variables: <Variable<Object>>[
          Variable<String>(appIdentity.storeId),
          Variable<String>(warehouseId),
          Variable<String>(item.productId),
        ],
      ).getSingleOrNull();
      if (cutoverMarker != null) {
        throw StateError(
          'Cannot edit, cancel, or return legacy ${purchase.purchaseNo}: ${product.name} was already absorbed into the Unified Batch opening balance and has no exact historical batch identity. Complete the historical migration first.',
        );
      }
      legacyUnbatchedProductIds.add(item.productId);
    }

    if (legacyUnbatchedProductIds.isEmpty) return;
    final productIds = legacyUnbatchedProductIds.toList(growable: false);
    final placeholders = List.filled(productIds.length, '?').join(',');
    final legacyRows = await sqliteDb.customSelect(
      '''
      SELECT sm.movement_type, sm.reference_id, sm.reference_no, sm.product_name
      FROM stock_movements sm
      WHERE sm.store_id = ? AND sm.warehouse_id = ?
        AND sm.product_id IN ($placeholders)
        AND sm.quantity < -0.000001
        AND sm.movement_type <> 'purchase_return'
        AND sm.reference_id <> ?
        AND sm.movement_date >= ?
        AND trim(sm.reversal_of_movement_id) = ''
        AND sm.deleted_at = ''
        AND ABS(
          sm.quantity + COALESCE((
            SELECT SUM(reversal.quantity)
            FROM stock_movements reversal
            WHERE reversal.reversal_of_movement_id = sm.id
              AND reversal.deleted_at = ''
              AND NOT EXISTS (
                SELECT 1 FROM stock_movements reversal_of_reversal
                WHERE reversal_of_reversal.reversal_of_movement_id = reversal.id
                  AND reversal_of_reversal.deleted_at = ''
              )
          ), 0)
        ) > 0.000001
      ORDER BY sm.movement_date ASC, sm.id ASC
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(appIdentity.storeId),
        Variable<String>(warehouseId),
        ...productIds.map(Variable<String>.new),
        Variable<String>(purchase.id),
        Variable<String>(purchase.date.toUtc().toIso8601String()),
      ],
    ).getSingleOrNull();
    if (legacyRows != null) {
      final type = legacyRows.data['movement_type']?.toString() ?? 'stock';
      final refNo = legacyRows.data['reference_no']?.toString() ?? '';
      final refId = legacyRows.data['reference_id']?.toString() ?? '';
      final productName = legacyRows.data['product_name']?.toString() ?? '';
      throw StateError(
        'Cannot edit or cancel legacy ${purchase.purchaseNo}: $productName has a later active $type movement (${refNo.isEmpty ? refId : refNo}). Reverse it first.',
      );
    }
  }
}
