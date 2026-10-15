part of 'app_store.dart';

extension _AppStoreSplitPricingCostingPart2 on AppStore {
  Future<Map<String, ProductCostSnapshot>> productCostSnapshotsForProducts(
    Iterable<Product> products, {
    String warehouseId = '',
  }) async {
    final productById = <String, Product>{
      for (final product in products)
        if (product.id.trim().isNotEmpty && !product.isDeleted)
          product.id: product,
    };
    if (productById.isEmpty) return const <String, ProductCostSnapshot>{};

    final normalizedWarehouse = warehouseId.trim();
    final fallback = <String, ProductCostSnapshot>{};
    for (final product in productById.values) {
      final compatibilityCost = productCostFor(product.id);
      final referenceCost = _safeUsdCost(product);
      final currentCost = compatibilityCost.averageCost > 0
          ? compatibilityCost.averageCost
          : referenceCost;
      fallback[product.id] = ProductCostSnapshot(
        productId: product.id,
        currentInventoryUnitCost: currentCost,
        inventoryQuantity: product.trackStock ? max(0.0, product.stock) : 0,
        batchCount: 0,
        lastPurchaseUnitCost: lastPurchasePriceForProduct(product.id),
        referenceUnitCost: referenceCost,
        warehouseId: normalizedWarehouse,
      );
    }

    if (!LocalDatabaseService.isSqliteAuthoritative ||
        SqliteMigrationManager.database == null) {
      return fallback;
    }

    final db = SqliteMigrationManager.database!;
    final ids = productById.keys.toList(growable: false);
    final inventoryByProduct = <String, (double, double, int)>{};
    final lastPurchaseByProduct = <String, double>{};
    const queryChunkSize = 400;
    for (var offset = 0; offset < ids.length; offset += queryChunkSize) {
      final chunk = ids.sublist(
        offset,
        min(ids.length, offset + queryChunkSize),
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      final warehousePredicate =
          normalizedWarehouse.isEmpty ? '' : 'AND bb.warehouse_id = ?';
      final inventoryRows = await db.customSelect(
        '''
        SELECT bb.product_id,
               COALESCE(SUM(bb.quantity), 0) AS quantity,
               COALESCE(SUM(bb.quantity * b.unit_cost), 0) AS carrying_value,
               COUNT(DISTINCT b.id) AS batch_count
        FROM inventory_batch_balances bb
        INNER JOIN inventory_batches b ON b.id = bb.batch_id
          AND b.store_id = bb.store_id AND b.product_id = bb.product_id
        WHERE bb.store_id = ?
          AND bb.product_id IN ($placeholders)
          $warehousePredicate
          AND bb.quantity > 0.000001
          AND b.source_type <> 'inventory_deficit'
          AND b.id NOT LIKE 'deficit:%'
        GROUP BY bb.product_id
        ''',
        variables: <Variable<Object>>[
          Variable<String>(appIdentity.storeId),
          ...chunk.map<Variable<Object>>((id) => Variable<String>(id)),
          if (normalizedWarehouse.isNotEmpty)
            Variable<String>(normalizedWarehouse),
        ],
      ).get();
      for (final row in inventoryRows) {
        final productId = row.data['product_id']?.toString() ?? '';
        if (productId.isEmpty) continue;
        inventoryByProduct[productId] = (
          (row.data['quantity'] as num? ?? 0).toDouble(),
          (row.data['carrying_value'] as num? ?? 0).toDouble(),
          (row.data['batch_count'] as num? ?? 0).toInt(),
        );
      }

      final latestPurchaseRows = await db.customSelect(
        '''
        WITH effective_purchase AS (
          SELECT b.product_id,
                 b.unit_cost,
                 b.received_at,
                 b.created_at,
                 b.updated_at,
                 b.id,
                 sm.movement_date
          FROM inventory_batches b
          INNER JOIN stock_movements sm ON sm.batch_id = b.id
          WHERE b.store_id = ?
            AND b.product_id IN ($placeholders)
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
        ), ranked AS (
          SELECT product_id, unit_cost,
                 ROW_NUMBER() OVER (
                   PARTITION BY product_id
                   ORDER BY COALESCE(NULLIF(trim(received_at), ''), created_at) DESC,
                            movement_date DESC,
                            updated_at DESC,
                            id DESC
                 ) AS rn
          FROM effective_purchase
        )
        SELECT product_id, unit_cost
        FROM ranked
        WHERE rn = 1
        ''',
        variables: <Variable<Object>>[
          Variable<String>(appIdentity.storeId),
          ...chunk.map<Variable<Object>>((id) => Variable<String>(id)),
        ],
      ).get();
      for (final row in latestPurchaseRows) {
        final productId = row.data['product_id']?.toString() ?? '';
        final unitCost = (row.data['unit_cost'] as num?)?.toDouble();
        if (productId.isNotEmpty && unitCost != null && unitCost >= 0) {
          lastPurchaseByProduct[productId] = unitCost;
        }
      }
    }

    final resolved = <String, ProductCostSnapshot>{};
    for (final product in productById.values) {
      final totals = inventoryByProduct[product.id];
      final quantity = totals?.$1 ?? 0.0;
      final carryingValue = totals?.$2 ?? 0.0;
      final currentUnitCost =
          quantity > 0.000001 ? max(0.0, carryingValue) / quantity : 0.0;
      resolved[product.id] = ProductCostSnapshot(
        productId: product.id,
        currentInventoryUnitCost: currentUnitCost,
        inventoryQuantity: quantity,
        batchCount: totals?.$3 ?? 0,
        lastPurchaseUnitCost: lastPurchaseByProduct[product.id],
        referenceUnitCost: _safeUsdCost(product),
        warehouseId: normalizedWarehouse,
      );
    }
    return resolved;
  }

  Future<ProductCostSnapshot> productCostSnapshotForProduct(
    Product product, {
    String warehouseId = '',
  }) async {
    final snapshots = await productCostSnapshotsForProducts(
      <Product>[product],
      warehouseId: warehouseId,
    );
    return snapshots[product.id] ??
        ProductCostSnapshot(
          productId: product.id,
          currentInventoryUnitCost: 0,
          inventoryQuantity: 0,
          batchCount: 0,
          lastPurchaseUnitCost: lastPurchasePriceForProduct(product.id),
          referenceUnitCost: _safeUsdCost(product),
          warehouseId: warehouseId.trim(),
        );
  }

  void _ensureProductCostEntries({Product? product}) {
    _ensureProductPricingLookupCaches();
    final now = DateTime.now();
    final productsToCheck = product == null
        ? _products.where((item) => !item.isDeleted)
        : <Product>[product];
    for (final current in productsToCheck) {
      if (current.isDeleted) continue;
      if (_productCostByProductId.containsKey(current.id)) continue;
      final cost = ProductCost(
        productId: current.id,
        averageCost: _safeUsdCost(current),
        lastCost: _safeUsdCost(current),
        currencyCode: 'USD',
        createdAt: current.createdAt,
        updatedAt: now,
      );
      _productCostIndexByProductId[current.id] = _productCosts.length;
      _productCosts.add(cost);
      _productCostByProductId[current.id] = cost;
    }
  }

  InventoryCostingMethod _runtimeInventoryCostingMethod(
      InventoryCostingMethod requested) {
    // Phase 4 permanently locks production valuation to Unified Batch.
    // Explicit test stores retain legacy method switching only to keep historical
    // migration/regression fixtures readable.
    if (LocalDatabaseService.isInMemoryStoreForTesting ||
        LocalDatabaseService.isSqliteDatabaseForTesting) {
      return requested;
    }
    return InventoryCostingMethod.batch;
  }

  void _ensureCostingMethodHistory() {
    // IMPORTANT: callers must first hydrate the costing-history deferred group.
    // An empty in-memory list before hydration is not evidence that SQLite has
    // no history (and seeding at that point creates duplicate open rows).
    if (_costingMethodHistory.isNotEmpty) return;
    final now = DateTime.now();
    _costingMethodHistory.add(CostingMethodHistory(
      id: 'costing_${now.microsecondsSinceEpoch}',
      method: _inventoryCostingMethod,
      effectiveFrom: now,
      reason: 'Initial costing method',
      createdAt: now,
      updatedAt: now,
    ));
  }

  DateTime? _currentOpenFifoEffectiveFrom() {
    final open = _costingMethodHistory
        .where((item) =>
            item.effectiveTo == null &&
            item.method == InventoryCostingMethod.fifo)
        .toList(growable: false)
      ..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
    return open.isEmpty ? null : open.last.effectiveFrom;
  }

  bool _saleBelongsToCurrentFifoPeriod(DateTime saleDate) {
    if (_inventoryCostingMethod != InventoryCostingMethod.fifo) return false;

    // The sale item itself persists costingMethodAtSale plus the exact FIFO
    // layer consumptions, so this helper only needs to answer whether a real
    // costing-method transition happened after the sale. Requiring history to
    // also prove the method that was active at the exact sale timestamp is too
    // strict: legacy/normalized history rows can start a few microseconds after
    // a persisted sale timestamp and incorrectly force a rebase even though the
    // sale carries concrete FIFO layer ids.
    //
    // A later non-FIFO row is the actual safety boundary. Once the business
    // crossed out of FIFO, inventory may have been rebased and an old purchase
    // layer must not be resurrected. Duplicate/additional FIFO rows do not
    // create such a boundary.
    return !_costingMethodHistory.any((item) =>
        item.effectiveFrom.isAfter(saleDate) &&
        item.method != InventoryCostingMethod.fifo);
  }

  Future<void> _captureFifoSnapshotAsAverageInTransaction(
    VentioDriftDatabase db,
    DateTime now,
  ) async {
    final currentCosts = <String, ProductCost>{
      for (final cost in await BusinessSqliteStore.readProductCosts(db))
        cost.productId: cost,
    };
    final rows = await db.customSelect(
      r'''
      WITH warehouse AS (
        SELECT product_id, SUM(quantity) AS qty
        FROM warehouse_inventory
        WHERE store_id = ? OR trim(store_id) = ''
        GROUP BY product_id
      ), movement_value AS (
        SELECT product_id,
               COUNT(*) AS movement_count,
               SUM(quantity) AS movement_qty,
               SUM(quantity * unit_cost) AS carrying_value
        FROM stock_movements
        WHERE deleted_at = '' AND (store_id = ? OR trim(store_id) = '')
        GROUP BY product_id
      )
      SELECT w.product_id, w.qty,
             COALESCE(m.movement_count, 0) AS movement_count,
             COALESCE(m.movement_qty, 0) AS movement_qty,
             COALESCE(m.carrying_value, 0) AS carrying_value
      FROM warehouse w
      LEFT JOIN movement_value m ON m.product_id = w.product_id
      WHERE w.qty > 0.000001
      ORDER BY w.product_id ASC
      ''',
      variables: <Variable<Object>>[
        Variable<String>(appIdentity.storeId),
        Variable<String>(appIdentity.storeId),
      ],
    ).get();
    final updates = <ProductCost>[];
    for (final row in rows) {
      final productId = row.data['product_id']?.toString() ?? '';
      if (productId.isEmpty) continue;
      final qty = (row.data['qty'] as num? ?? 0).toDouble();
      if (qty <= 0.000001) continue;
      final movementCount = (row.data['movement_count'] as num? ?? 0).toInt();
      final movementQty = (row.data['movement_qty'] as num? ?? 0).toDouble();
      final movementValue =
          (row.data['carrying_value'] as num? ?? 0).toDouble();
      final current = currentCosts[productId] ?? productCostFor(productId);
      final fallbackValue = qty *
          (current.averageCost > 0 ? current.averageCost : current.lastCost);
      final movementBasisIsComplete = movementCount > 0 &&
          (movementQty - qty).abs() <= 0.000001 &&
          movementValue.isFinite &&
          movementValue >= -0.000001;
      final carryingValue = movementBasisIsComplete
          ? max(0.0, movementValue)
          : max(0.0, fallbackValue);
      final average = carryingValue / qty;
      updates.add(current.copyWith(
        averageCost: average.isFinite ? max(0.0, average) : current.averageCost,
        updatedAt: now,
      ));
    }
    if (updates.isNotEmpty) {
      await BusinessSqliteStore.upsertEntityPayloads(
        db,
        AppStore._productCostsKey,
        updates.map((item) => item.toJson()).toList(growable: false),
      );
    }
  }

  Future<void> _rebaseInventoryCostLayersForFifoInTransaction(
    VentioDriftDatabase db, {
    required DateTime now,
    required String transitionId,
  }) async {
    final currentCosts = <String, ProductCost>{
      for (final cost in await BusinessSqliteStore.readProductCosts(db))
        cost.productId: cost,
    };
    final negativeStock = await db.customSelect(
      r'''
      SELECT wi.product_id, SUM(wi.quantity) AS qty
      FROM warehouse_inventory wi
      INNER JOIN products p ON p.id = wi.product_id
        AND p.deleted_at = '' AND p.track_stock = 1
      WHERE wi.store_id = ? OR trim(wi.store_id) = ''
      GROUP BY wi.product_id
      HAVING SUM(wi.quantity) < -0.000001
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(appIdentity.storeId),
      ],
    ).getSingleOrNull();
    if (negativeStock != null) {
      throw StateError(
        'Cannot switch to FIFO while tracked inventory is negative for product ${negativeStock.data['product_id'] ?? ''}. Resolve negative stock first.',
      );
    }

    // Retire every prior active FIFO basis without deleting history.
    await db.customUpdate(
      r'''
      UPDATE inventory_cost_layers
      SET quantity_remaining = 0,
          is_closed = 1,
          updated_at = ?
      WHERE deleted_at = '' AND quantity_remaining > 0.000001
      ''',
      variables: <Variable<Object>>[
        Variable<String>(now.toUtc().toIso8601String()),
      ],
    );

    // warehouse_inventory is authoritative for quantity. Net stock-movement
    // value is used as the carrying-value basis because those movements also
    // drive Inventory/COGS accounting. If history is absent, use ProductCost.
    final rows = await db.customSelect(
      r'''
      WITH warehouse AS (
        SELECT product_id, SUM(quantity) AS qty
        FROM warehouse_inventory
        WHERE store_id = ? OR trim(store_id) = ''
        GROUP BY product_id
      ), movement_value AS (
        SELECT product_id,
               COUNT(*) AS movement_count,
               SUM(quantity) AS movement_qty,
               SUM(quantity * unit_cost) AS carrying_value
        FROM stock_movements
        WHERE deleted_at = '' AND (store_id = ? OR trim(store_id) = '')
        GROUP BY product_id
      )
      SELECT w.product_id, w.qty,
             COALESCE(m.movement_count, 0) AS movement_count,
             COALESCE(m.movement_qty, 0) AS movement_qty,
             COALESCE(m.carrying_value, 0) AS carrying_value,
             p.name AS product_name
      FROM warehouse w
      INNER JOIN products p ON p.id = w.product_id
        AND p.deleted_at = '' AND p.track_stock = 1
      LEFT JOIN movement_value m ON m.product_id = w.product_id
      WHERE w.qty > 0.000001
      ORDER BY w.product_id ASC
      ''',
      variables: <Variable<Object>>[
        Variable<String>(appIdentity.storeId),
        Variable<String>(appIdentity.storeId),
      ],
    ).get();

    final openingLayers = <InventoryCostLayer>[];
    final costUpdates = <ProductCost>[];
    for (final row in rows) {
      final productId = row.data['product_id']?.toString() ?? '';
      final productName = row.data['product_name']?.toString() ?? productId;
      final qty = (row.data['qty'] as num? ?? 0).toDouble();
      if (productId.isEmpty || qty <= 0.000001) continue;
      final movementCount = (row.data['movement_count'] as num? ?? 0).toInt();
      final movementQty = (row.data['movement_qty'] as num? ?? 0).toDouble();
      final movementValue =
          (row.data['carrying_value'] as num? ?? 0).toDouble();
      final current = currentCosts[productId] ?? productCostFor(productId);
      final product = _findProductById(productId);
      final fallbackUnitCost = current.averageCost > 0
          ? current.averageCost
          : current.lastCost > 0
              ? current.lastCost
              : product == null
                  ? 0.0
                  : _safeUsdCost(product);
      final movementBasisIsComplete = movementCount > 0 &&
          (movementQty - qty).abs() <= 0.000001 &&
          movementValue.isFinite &&
          movementValue >= -0.000001;
      final carryingValue = movementBasisIsComplete
          ? max(0.0, movementValue)
          : max(0.0, qty * fallbackUnitCost);
      final unitCost = carryingValue / qty;
      final layer = InventoryCostLayer(
        id: 'costing-opening-$transitionId-$productId',
        productId: productId,
        productName: productName,
        quantityReceived: qty,
        quantityRemaining: qty,
        unitCost: unitCost.isFinite ? max(0.0, unitCost) : 0.0,
        currencyCode: 'USD',
        exchangeRate: 1,
        sourceType: 'costing_method_opening',
        sourceId: transitionId,
        createdAt: now,
        updatedAt: now,
      );
      openingLayers.add(layer);
      costUpdates.add(current.copyWith(
        averageCost: layer.unitCost,
        currencyCode: 'USD',
        updatedAt: now,
      ));
    }
    if (openingLayers.isNotEmpty) {
      await BusinessSqliteStore.upsertEntityPayloads(
        db,
        AppStore._inventoryCostLayersKey,
        openingLayers.map((item) => item.toJson()).toList(growable: false),
      );
    }
    if (costUpdates.isNotEmpty) {
      await BusinessSqliteStore.upsertEntityPayloads(
        db,
        AppStore._productCostsKey,
        costUpdates.map((item) => item.toJson()).toList(growable: false),
      );
    }
  }

  Future<void> setInventoryCostingMethod(InventoryCostingMethod method,
      {String reason = ''}) async {
    requirePermission(AppPermission.productsEdit);
    if (!LocalDatabaseService.isInMemoryStoreForTesting &&
        !LocalDatabaseService.isSqliteDatabaseForTesting &&
        method != InventoryCostingMethod.batch) {
      throw StateError(
        'Inventory costing is permanently locked to Unified Batch in Phase 4.',
      );
    }
    final effectiveMethod = _runtimeInventoryCostingMethod(method);
    await ensureProductCostsLoaded();
    await ensureCostingMethodHistoryLoaded();
    await ensureInventoryCostLayersLoaded();
    if (_inventoryCostingMethod == effectiveMethod &&
        _costingMethodHistory.isNotEmpty) {
      return;
    }

    final now = DateTime.now();
    final transitionId = 'costing_${now.microsecondsSinceEpoch}';
    final previousMethod = _inventoryCostingMethod;
    final nextHistory = <CostingMethodHistory>[
      for (final item in _costingMethodHistory)
        if (item.effectiveTo == null)
          item.copyWith(effectiveTo: now, updatedAt: now)
        else
          item,
      CostingMethodHistory(
        id: transitionId,
        method: effectiveMethod,
        effectiveFrom: now,
        reason: reason.trim(),
        createdAt: now,
        updatedAt: now,
      ),
    ];

    final db = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && db != null) {
      await db.transaction(() async {
        if (previousMethod == InventoryCostingMethod.fifo &&
            effectiveMethod != InventoryCostingMethod.fifo) {
          await _captureFifoSnapshotAsAverageInTransaction(db, now);
        }
        if (effectiveMethod == InventoryCostingMethod.fifo &&
            previousMethod != InventoryCostingMethod.fifo) {
          await _rebaseInventoryCostLayersForFifoInTransaction(
            db,
            now: now,
            transitionId: transitionId,
          );
        }
        await BusinessSqliteStore.upsertEntityPayloads(
          db,
          AppStore._costingMethodHistoryKey,
          nextHistory.map((item) => item.toJson()).toList(growable: false),
        );
        await LocalDatabaseService.setString(
          AppStore._inventoryCostingMethodKey,
          effectiveMethod.code,
        );
      });

      _inventoryCostingMethod = effectiveMethod;
      _costingMethodHistory
        ..clear()
        ..addAll(await BusinessSqliteStore.readCostingMethodHistory(db));
      _productCosts
        ..clear()
        ..addAll(await BusinessSqliteStore.readProductCosts(db));
      _inventoryCostLayers
        ..clear()
        ..addAll(await BusinessSqliteStore.readInventoryCostLayers(db));
      _rebuildProductPricingLookupCaches();
      _rebuildInventoryCostLayerLookupCache();
    } else {
      _inventoryCostingMethod = effectiveMethod;
      _costingMethodHistory
        ..clear()
        ..addAll(nextHistory);
      await Future.wait(<Future<void>>[
        LocalDatabaseService.setString(
            AppStore._inventoryCostingMethodKey, effectiveMethod.code),
        _upsertSqliteBusinessRows(
          AppStore._costingMethodHistoryKey,
          nextHistory.map((item) => item.toJson()),
        ),
      ]);
    }
    _touchDataRevisions(products: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
  }

  ProductCost _upsertProductCostFromPurchase({
    required Product product,
    required double receivedQty,
    required double baseUnitCost,
    required DateTime now,
  }) {
    _ensureProductCostEntries();
    final current = _productCostByProductId[product.id] ??
        ProductCost(
          productId: product.id,
          averageCost: _safeUsdCost(product),
          lastCost: _safeUsdCost(product),
          currencyCode: 'USD',
          createdAt: now,
          updatedAt: now,
        );
    final stockBefore = max(0, product.stock);
    final stockAfter = stockBefore + receivedQty;
    final averageCost = stockAfter <= 0
        ? baseUnitCost
        : ((stockBefore * current.averageCost) + (receivedQty * baseUnitCost)) /
            stockAfter;
    final updated = current.copyWith(
      averageCost: averageCost,
      lastCost: baseUnitCost,
      currencyCode: 'USD',
      updatedAt: now,
    );
    final index = _productCostIndexByProductId[product.id];
    if (index == null || index < 0 || index >= _productCosts.length) {
      final fallbackIndex =
          _productCosts.indexWhere((item) => item.productId == product.id);
      if (fallbackIndex == -1) {
        _productCostIndexByProductId[product.id] = _productCosts.length;
        _productCosts.add(updated);
      } else {
        _productCosts[fallbackIndex] = updated;
        _productCostIndexByProductId[product.id] = fallbackIndex;
      }
    } else {
      _productCosts[index] = updated;
    }
    _productCostByProductId[product.id] = updated;
    return updated;
  }

  void _addInventoryCostLayerFromPurchase({
    required Purchase purchase,
    required PurchaseItem item,
    required int lineIndex,
    required double quantity,
    required double unitCost,
    required DateTime now,
  }) {
    if (quantity <= 0) return;
    final id = '${purchase.id}-$lineIndex-${item.productId}-cost-layer';
    if (_inventoryCostLayerIndexById.containsKey(id)) return;
    _inventoryCostLayerIndexById[id] = _inventoryCostLayers.length;
    _inventoryCostLayers.add(InventoryCostLayer(
      id: id,
      productId: item.productId,
      productName: item.productName,
      quantityReceived: quantity,
      quantityRemaining: quantity,
      unitCost: unitCost,
      currencyCode: 'USD',
      exchangeRate: 1,
      purchaseId: purchase.id,
      purchaseItemId: '$lineIndex',
      sourceType: 'purchase',
      sourceId: purchase.id,
      createdAt: now,
      updatedAt: now,
    ));
  }

  void _addInventoryCostLayerFromStockIncrease({
    required String id,
    required Product product,
    required double quantity,
    required double unitCost,
    required String sourceType,
    required String sourceId,
    required DateTime now,
  }) {
    if (quantity <= 0 || !product.trackStock) return;
    if (_inventoryCostLayerIndexById.containsKey(id)) return;
    _inventoryCostLayerIndexById[id] = _inventoryCostLayers.length;
    _inventoryCostLayers.add(InventoryCostLayer(
      id: id,
      productId: product.id,
      productName: product.name,
      quantityReceived: quantity,
      quantityRemaining: quantity,
      unitCost: unitCost,
      currencyCode: 'USD',
      exchangeRate: 1,
      purchaseId: '',
      purchaseItemId: '',
      sourceType: sourceType,
      sourceId: sourceId,
      createdAt: now,
      updatedAt: now,
    ));
  }

  bool _purchaseHasConsumedCostLayers(String purchaseId) {
    return _inventoryCostLayers.any((layer) =>
        layer.purchaseId == purchaseId &&
        layer.quantityReceived - layer.quantityRemaining > 0.000001);
  }
}
