part of 'app_store.dart';

extension _AppStoreSplitPricingCosting on AppStore {
void _ensureDefaultPriceLists() {
    final now = DateTime.now();
    if (!_priceLists.any((item) => item.id == 'retail')) {
      _priceLists.insert(
          0,
          PriceList(
              id: 'retail',
              name: 'Retail',
              code: 'retail',
              isDefault: true,
              createdAt: now,
              updatedAt: now));
    }
    if (!_priceLists.any((item) => item.id == 'wholesale')) {
      _priceLists.add(PriceList(
          id: 'wholesale',
          name: 'Wholesale',
          code: 'wholesale',
          createdAt: now,
          updatedAt: now));
    }
    if (!_priceLists.any((item) => item.id == 'wholesale_bulk')) {
      _priceLists.add(PriceList(
          id: 'wholesale_bulk',
          name: 'Wholesale Bulk',
          code: 'wholesale_bulk',
          createdAt: now,
          updatedAt: now));
    }
  }

void _rebuildProductPriceLookupCache() {
    _productPriceByLookupKey.clear();
    for (final item in _productPrices) {
      if (!item.isActive) continue;
      _productPriceByLookupKey[_productPriceLookupKey(
        item.productId,
        item.priceListId,
        item.unitId,
      )] = item;
    }
  }

void _rebuildProductCostLookupCache() {
    _productCostByProductId.clear();
    _productCostIndexByProductId.clear();
    for (var i = 0; i < _productCosts.length; i += 1) {
      final item = _productCosts[i];
      if (item.productId.trim().isEmpty) continue;
      _productCostByProductId[item.productId] = item;
      _productCostIndexByProductId[item.productId] = i;
    }
  }

void _rebuildProductPricingLookupCaches() {
    _rebuildProductPriceLookupCache();
    _rebuildProductCostLookupCache();
  }

void _ensureProductPricingLookupCaches() {
    if (_productPriceByLookupKey.isEmpty && _productPrices.isNotEmpty) {
      _rebuildProductPriceLookupCache();
    }
    if (_productCostByProductId.isEmpty && _productCosts.isNotEmpty) {
      _rebuildProductCostLookupCache();
    }
  }

void _removeProductPricingLookupEntries(String productId) {
    _productPriceByLookupKey.removeWhere(
      (_, value) => value.productId == productId,
    );
    _productCostByProductId.remove(productId);
  }

void _ensureDefaultProductPriceEntries({Product? product}) {
    _ensureDefaultPriceLists();
    _ensureProductPricingLookupCaches();
    final retailId = defaultPriceList.id;
    final now = DateTime.now();
    final productsToCheck = product == null
        ? _products.where((item) => !item.isDeleted)
        : <Product>[product];
    for (final current in productsToCheck) {
      if (current.isDeleted) continue;
      final key = '${current.id}|$retailId|base';
      if (!_productPriceByLookupKey.containsKey(key)) {
        final price = ProductPrice(
          id: 'pp_${current.id}_${retailId}_base',
          productId: current.id,
          priceListId: retailId,
          unitId: 'base',
          baseCurrencyCode: current.originalCurrency,
          baseAmount: current.originalPrice,
          createdAt: current.createdAt,
          updatedAt: now,
        );
        _productPrices.add(price);
        _productPriceByLookupKey[key] = price;
      }
      for (final unit in current.saleUnits) {
        final unitKey = '${current.id}|$retailId|${unit.id}';
        if (_productPriceByLookupKey.containsKey(unitKey)) continue;
        final price = ProductPrice(
          id: 'pp_${current.id}_${retailId}_${unit.id}',
          productId: current.id,
          priceListId: retailId,
          unitId: unit.id,
          baseCurrencyCode: unit.originalCurrency,
          baseAmount: unit.originalPrice,
          createdAt: current.createdAt,
          updatedAt: now,
        );
        _productPrices.add(price);
        _productPriceByLookupKey[unitKey] = price;
      }
    }
  }

Future<void> setDefaultProductBasePrice(
      {required String productId,
      required String unitId,
      required double amount,
      required String currencyCode}) async {
    final productExists = _products.any((item) => item.id == productId);
    requirePermission(productExists
        ? AppPermission.productsEdit
        : AppPermission.productsCreate);
    _ensureDefaultPriceLists();
    final now = DateTime.now();
    final priceListId = defaultPriceList.id;
    final index = _productPrices.indexWhere((item) =>
        item.productId == productId &&
        item.priceListId == priceListId &&
        item.unitId == unitId);
    final price = ProductPrice(
      id: index == -1
          ? 'pp_${productId}_${priceListId}_${unitId}_${now.microsecondsSinceEpoch}'
          : _productPrices[index].id,
      productId: productId,
      priceListId: priceListId,
      unitId: unitId,
      baseCurrencyCode: currencyCode.toUpperCase(),
      baseAmount: amount,
      createdAt: index == -1 ? now : _productPrices[index].createdAt,
      updatedAt: now,
    );
    if (index == -1) {
      _productPrices.add(price);
    } else {
      _productPrices[index] = price;
    }
    _productPriceByLookupKey[
        _productPriceLookupKey(productId, priceListId, unitId)] = price;
    await Future.wait(<Future<void>>[
      _upsertSqliteBusinessRows(
        AppStore._priceListsKey,
        _priceLists.map((item) => item.toJson()),
      ),
      _upsertSqliteBusinessRows(
        AppStore._productPricesKey,
        <Map<String, dynamic>>[price.toJson()],
      ),
    ]);
    _touchDataRevisions(products: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
  }

Future<void> setProductBasePriceForList({
    required String productId,
    required String priceListId,
    required double amount,
    required String currencyCode,
    String unitId = 'base',
  }) async {
    requirePermission(AppPermission.productsEdit);
    _ensureDefaultPriceLists();
    final existing = productPriceFor(productId, priceListId, unitId: unitId);
    final now = DateTime.now();
    final price = ProductPrice(
      id: existing?.id ?? 'pp_${productId}_${priceListId}_$unitId',
      productId: productId,
      priceListId: priceListId,
      unitId: unitId,
      baseCurrencyCode: currencyCode.toUpperCase(),
      baseAmount: amount,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    final index = _productPrices.indexWhere((item) => item.id == price.id);
    if (index == -1) {
      _productPrices.add(price);
    } else {
      _productPrices[index] = price;
    }
    _productPriceByLookupKey[
        _productPriceLookupKey(productId, priceListId, unitId)] = price;
    await _upsertSqliteBusinessRows(
      AppStore._productPricesKey,
      <Map<String, dynamic>>[price.toJson()],
    );
    _touchDataRevisions(products: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
  }

Future<void> setProductPriceOverride({
    required String productPriceId,
    required String currencyCode,
    required double amount,
    ProductPriceOverrideMode mode = ProductPriceOverrideMode.fixed,
    bool isActive = true,
  }) async {
    requirePermission(AppPermission.productsEdit);
    final normalizedCurrency = currencyCode.trim().toUpperCase();
    if (productPriceId.trim().isEmpty || normalizedCurrency.isEmpty) {
      throw ArgumentError('Product price and currency are required.');
    }
    final now = DateTime.now();
    final index = _productPriceOverrides.indexWhere(
      (item) =>
          item.productPriceId == productPriceId &&
          item.currencyCode == normalizedCurrency,
    );
    final override = ProductPriceOverride(
      id: index == -1
          ? 'ppo_${productPriceId}_${normalizedCurrency}_${now.microsecondsSinceEpoch}'
          : _productPriceOverrides[index].id,
      productPriceId: productPriceId,
      currencyCode: normalizedCurrency,
      amount: amount,
      mode: mode,
      isActive: isActive,
      createdAt: index == -1 ? now : _productPriceOverrides[index].createdAt,
      updatedAt: now,
    );
    if (index == -1) {
      _productPriceOverrides.add(override);
    } else {
      _productPriceOverrides[index] = override;
    }
    await _upsertSqliteBusinessRows(
        AppStore._productPriceOverridesKey, <Map<String, dynamic>>[override.toJson()]);
    _touchDataRevisions(products: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
  }

Future<void> removeProductPriceOverride(
      String productPriceId, String currencyCode) async {
    requirePermission(AppPermission.productsEdit);
    final normalizedCurrency = currencyCode.trim().toUpperCase();
    final index = _productPriceOverrides.indexWhere(
      (item) =>
          item.productPriceId == productPriceId &&
          item.currencyCode == normalizedCurrency,
    );
    if (index == -1) return;
    final override = _productPriceOverrides[index]
        .copyWith(isActive: false, updatedAt: DateTime.now());
    _productPriceOverrides[index] = override;
    await _upsertSqliteBusinessRows(
        AppStore._productPriceOverridesKey, <Map<String, dynamic>>[override.toJson()]);
    _touchDataRevisions(products: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
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

InventoryCostResult _resolveCostForSaleItem(SaleItem item, DateTime now) {
    final product = _findProductById(item.productId);
    final cost = productCostFor(item.productId);
    if (_inventoryCostingMethod == InventoryCostingMethod.lastPurchaseCost) {
      return InventoryCostResult(
        method: _inventoryCostingMethod,
        unitCost: cost.lastCost > 0 ? cost.lastCost : (product?.usdCost ?? 0),
      );
    }
    if (_inventoryCostingMethod == InventoryCostingMethod.fifo) {
      var qtyToConsume = item.effectiveBaseQuantity;
      final consumptions = <InventoryCostLayerConsumption>[];
      final indexes = <int>[];
      for (var i = 0; i < _inventoryCostLayers.length; i += 1) {
        final layer = _inventoryCostLayers[i];
        if (layer.productId == item.productId &&
            !layer.isClosed &&
            layer.quantityRemaining > 0) {
          indexes.add(i);
        }
      }
      indexes.sort((a, b) => _inventoryCostLayers[a]
          .createdAt
          .compareTo(_inventoryCostLayers[b].createdAt));
      for (final index in indexes) {
        if (qtyToConsume <= 0) break;
        final layer = _inventoryCostLayers[index];
        final consumed = min(qtyToConsume, layer.quantityRemaining);
        if (consumed <= 0) continue;
        consumptions.add(InventoryCostLayerConsumption(
          layerId: layer.id,
          quantity: consumed,
          unitCost: layer.unitCost,
          currencyCode: layer.currencyCode,
        ));
        final remaining = layer.quantityRemaining - consumed;
        _inventoryCostLayers[index] = layer.copyWith(
          quantityRemaining: remaining,
          isClosed: remaining <= 0,
          updatedAt: now,
        );
        qtyToConsume -= consumed;
      }
      if (qtyToConsume > 0) {
        final fallbackCost = cost.averageCost > 0
            ? cost.averageCost
            : (cost.lastCost > 0 ? cost.lastCost : (product?.usdCost ?? 0));
        if (fallbackCost > 0) {
          consumptions.add(InventoryCostLayerConsumption(
            layerId:
                'negative_stock_${item.productId}_${now.microsecondsSinceEpoch}',
            quantity: qtyToConsume,
            unitCost: fallbackCost,
            currencyCode: 'USD',
          ));
        }
      }
      final totalQty =
          item.effectiveBaseQuantity <= 0 ? 0 : item.effectiveBaseQuantity;
      final totalCost =
          consumptions.fold<double>(0, (sum, entry) => sum + entry.totalCost);
      final unitCost = totalQty <= 0 ? 0.0 : totalCost / totalQty;
      return InventoryCostResult(
        method: _inventoryCostingMethod,
        unitCost: unitCost,
        consumptions: consumptions,
      );
    }
    return InventoryCostResult(
      method: _inventoryCostingMethod,
      unitCost:
          cost.averageCost > 0 ? cost.averageCost : (product?.usdCost ?? 0),
    );
  }

Future<InventoryCostResult> _resolveCostForSaleItemInTransaction(
    VentioDriftDatabase db,
    SaleItem item,
    DateTime now,
  ) async {
    final product = _findProductById(item.productId);
    final cost = productCostFor(item.productId);
    final providedUnitCost = item.unitCost > 0 ? item.unitCost : 0.0;

    double fallbackCost() {
      if (providedUnitCost > 0) return providedUnitCost;
      if (_inventoryCostingMethod == InventoryCostingMethod.lastPurchaseCost &&
          cost.lastCost > 0) {
        return cost.lastCost;
      }
      if (cost.averageCost > 0) return cost.averageCost;
      if (cost.lastCost > 0) return cost.lastCost;
      return product?.usdCost ?? 0.0;
    }

    if (product == null || !product.trackStock) {
      return InventoryCostResult(
        method: _inventoryCostingMethod,
        unitCost: fallbackCost(),
      );
    }

    if (_inventoryCostingMethod != InventoryCostingMethod.fifo) {
      return InventoryCostResult(
        method: _inventoryCostingMethod,
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
      if (!_storeProfile.allowNegativeStock) {
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
      method: _inventoryCostingMethod,
      unitCost: totalQty <= 0 ? 0.0 : totalCost / totalQty,
      consumptions: consumptions,
    );
  }

Future<void> _restoreInventoryCostLayersFromSaleItemsInTransaction(
    VentioDriftDatabase db,
    Iterable<SaleItem> items,
    DateTime now, {
    required DateTime originalSaleDate,
    required String restorationSourceType,
    required String restorationSourceId,
  }) async {
    final materialized = items.toList(growable: false);
    if (materialized.isEmpty ||
        _inventoryCostingMethod != InventoryCostingMethod.fifo) {
      return;
    }
    final layers = await BusinessSqliteStore.readInventoryCostLayers(db);
    final byId = <String, InventoryCostLayer>{
      for (final layer in layers) layer.id: layer,
    };
    // A return/cancellation may refer to FIFO consumptions from an older FIFO
    // era. After switching away from FIFO and back, those historical layers
    // have already been rebased into the current opening layer and must not be
    // resurrected. Determine the boundary from actual method transitions after
    // the sale, rather than from the newest open FIFO row: older builds could
    // leave duplicate/open FIFO history rows that are not real transitions.
    final saleBelongsToCurrentFifoPeriod =
        _saleBelongsToCurrentFifoPeriod(originalSaleDate);

    for (var itemIndex = 0; itemIndex < materialized.length; itemIndex += 1) {
      final item = materialized[itemIndex];
      final canRestoreOriginalLayers = saleBelongsToCurrentFifoPeriod &&
          item.costingMethodAtSale == InventoryCostingMethod.fifo &&
          item.costLayerConsumptions.isNotEmpty &&
          item.costLayerConsumptions.every((consumption) {
            if (consumption.layerId.startsWith('negative_stock_') ||
                consumption.layerId.startsWith('negative_stock:')) {
              return false;
            }
            return byId.containsKey(consumption.layerId);
          });

      if (!canRestoreOriginalLayers) {
        final qty = item.effectiveBaseQuantity;
        if (qty <= 0.000001) continue;
        final layer = InventoryCostLayer(
          id: '$restorationSourceType-$restorationSourceId-${item.productId}-$itemIndex',
          productId: item.productId,
          productName: item.productName,
          quantityReceived: qty,
          quantityRemaining: qty,
          unitCost: max(0.0, item.unitCostPerBase),
          currencyCode: 'USD',
          exchangeRate: 1,
          sourceType: restorationSourceType,
          sourceId: restorationSourceId,
          createdAt: now,
          updatedAt: now,
        );
        await BusinessSqliteStore.upsertEntityPayloads(
          db,
          AppStore._inventoryCostLayersKey,
          <Map<String, dynamic>>[layer.toJson()],
          sortIndices: const <int?>[0],
        );
        byId[layer.id] = layer;
        continue;
      }

      for (final consumption in item.costLayerConsumptions) {
        if (consumption.layerId.startsWith('negative_stock_') ||
            consumption.layerId.startsWith('negative_stock:')) {
          continue;
        }
        final layer = byId[consumption.layerId];
        if (layer == null) {
          throw StateError(
            'Historical FIFO layer ${consumption.layerId} is missing for ${item.productName}.',
          );
        }
        final changed = await db.customUpdate(
          r'''
          UPDATE inventory_cost_layers
          SET quantity_remaining = quantity_remaining + ?,
              is_closed = 0,
              updated_at = ?
          WHERE id = ? AND deleted_at = ''
            AND quantity_remaining + ? <= quantity_received + 0.000001
          ''',
          variables: <Variable<Object>>[
            Variable<double>(consumption.quantity),
            Variable<String>(now.toUtc().toIso8601String()),
            Variable<String>(consumption.layerId),
            Variable<double>(consumption.quantity),
          ],
        );
        if (changed != 1) {
          throw StateError(
            'FIFO layer ${consumption.layerId} could not be restored safely for ${item.productName}.',
          );
        }
        final refreshed = await db.customSelect(
          r'''
          SELECT quantity_received, quantity_remaining
          FROM inventory_cost_layers
          WHERE id = ? AND deleted_at = ''
          LIMIT 1
          ''',
          variables: <Variable<Object>>[
            Variable<String>(consumption.layerId),
          ],
        ).getSingleOrNull();
        if (refreshed == null) {
          throw StateError(
            'FIFO layer ${consumption.layerId} disappeared during restoration.',
          );
        }
        final received =
            (refreshed.data['quantity_received'] as num? ?? 0).toDouble();
        final remaining =
            (refreshed.data['quantity_remaining'] as num? ?? 0).toDouble();
        if (remaining > received + 0.000001) {
          throw StateError(
            'FIFO layer ${consumption.layerId} was restored above its received quantity.',
          );
        }
        byId[consumption.layerId] = layer.copyWith(
          quantityRemaining: remaining,
          isClosed: remaining <= 0.000001,
          updatedAt: now,
        );
      }
    }
  }

Future<void> _closeInventoryCostLayersForPurchaseInTransaction(
    VentioDriftDatabase db,
    Purchase purchase,
    DateTime now,
  ) async {
    final purchaseLayers =
        (await BusinessSqliteStore.readInventoryCostLayers(db))
            .where((layer) => layer.purchaseId == purchase.id)
            .toList(growable: false);
    if (purchaseLayers.isEmpty) return;

    final versionSuffix = '-cost-layer-v${purchase.version}';
    final versionLayers = purchaseLayers
        .where((layer) => layer.id.endsWith(versionSuffix))
        .toList(growable: false);
    final activeLayers =
        versionLayers.isNotEmpty ? versionLayers : purchaseLayers;
    final fifoBasis = _inventoryCostingMethod == InventoryCostingMethod.fifo
        ? _currentOpenFifoEffectiveFrom()
        : null;
    if (fifoBasis != null &&
        activeLayers.any((layer) => layer.createdAt.isBefore(fifoBasis))) {
      throw StateError(
        'Cannot reverse a purchase that predates the current FIFO opening basis. Reverse it before changing costing method, or use a documented inventory adjustment.',
      );
    }

    final consumed = activeLayers.any(
        (layer) => layer.quantityRemaining + 0.000001 < layer.quantityReceived);
    if (consumed) {
      throw StateError(
        'Cannot reverse this purchase after its inventory cost layers have been consumed. Return/cancel the downstream sale or movement first.',
      );
    }

    // The current-version layers are the authority for the consumption guard.
    // Once that guard passes, the purchase reversal must close every persisted
    // layer linked to the purchase directly in SQLite. Do not round-trip these
    // rows through the generic entity upsert path: inventory_cost_layers is an
    // accounting/valuation authority and the reversal must be atomic with the
    // stock/batch reversal that follows in the same outer transaction.
    await db.customUpdate(
      r'''
      UPDATE inventory_cost_layers
      SET quantity_remaining = 0,
          is_closed = 1,
          updated_at = ?
      WHERE purchase_id = ?
        AND deleted_at = ''
      ''',
      variables: <Variable<Object>>[
        Variable<String>(now.toUtc().toIso8601String()),
        Variable<String>(purchase.id),
      ],
    );

    // Read back the authoritative table before allowing the outer transaction
    // to continue. A returned/cancelled purchase must never leave a ghost FIFO
    // balance behind, even if historical receive/repost versions exist.
    final residual = await db.customSelect(
      r'''
      SELECT COALESCE(SUM(quantity_remaining), 0) AS qty
      FROM inventory_cost_layers
      WHERE purchase_id = ?
        AND deleted_at = ''
      ''',
      variables: <Variable<Object>>[Variable<String>(purchase.id)],
    ).getSingle();
    final residualQuantity = (residual.data['qty'] as num? ?? 0).toDouble();
    if (residualQuantity.abs() > 0.000001) {
      throw StateError(
        'Purchase ${purchase.purchaseNo} cost layers did not close atomically; remaining quantity: $residualQuantity.',
      );
    }
  }

Future<_ManufacturingCostResolution> _consumeManufacturingCostInTransaction(
    VentioDriftDatabase db, {
    required Product product,
    required double quantity,
    required String orderId,
    required DateTime now,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('Actual manufacturing consumption must be positive.');
    }
    final productCost = productCostFor(product.id);
    double fallbackCost() {
      if (_inventoryCostingMethod == InventoryCostingMethod.lastPurchaseCost &&
          productCost.lastCost > 0) {
        return productCost.lastCost;
      }
      if (productCost.averageCost > 0) return productCost.averageCost;
      if (productCost.lastCost > 0) return productCost.lastCost;
      return _safeUsdCost(product);
    }

    if (_inventoryCostingMethod != InventoryCostingMethod.fifo) {
      final unitCost = fallbackCost();
      if (!unitCost.isFinite || unitCost < 0) {
        throw StateError('Invalid inventory cost for ${product.name}.');
      }
      return _ManufacturingCostResolution(
        unitCost: unitCost,
        totalCost: quantity * unitCost,
      );
    }

    final layers = (await BusinessSqliteStore.readInventoryCostLayers(db))
        .where((layer) =>
            layer.productId == product.id &&
            !layer.isClosed &&
            layer.quantityRemaining > 0)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    var remaining = quantity;
    var total = 0.0;
    final snapshots = <Map<String, dynamic>>[];
    for (final layer in layers) {
      if (remaining <= 0.000001) break;
      final consumed = min(remaining, layer.quantityRemaining);
      if (consumed <= 0) continue;
      total += consumed * layer.unitCost;
      snapshots.add(<String, dynamic>{
        'layerId': layer.id,
        'quantity': consumed,
        'unitCost': layer.unitCost,
        'currencyCode': layer.currencyCode,
        'orderId': orderId,
      });
      final nextRemaining = layer.quantityRemaining - consumed;
      final updated = layer.copyWith(
        quantityRemaining: nextRemaining,
        isClosed: nextRemaining <= 0.000001,
        updatedAt: now,
      );
      await BusinessSqliteStore.upsertEntityPayloads(
        db,
        AppStore._inventoryCostLayersKey,
        <Map<String, dynamic>>[updated.toJson()],
        sortIndices: const <int?>[0],
      );
      remaining -= consumed;
    }
    if (remaining > 0.000001) {
      final fallback = fallbackCost();
      if (!_storeProfile.allowNegativeStock) {
        throw StateError(
            'FIFO cost layers are insufficient for ${product.name}. Reconcile inventory costing before completing manufacturing.');
      }
      total += remaining * fallback;
      snapshots.add(<String, dynamic>{
        'layerId': 'negative_stock:${product.id}:$orderId',
        'quantity': remaining,
        'unitCost': fallback,
        'currencyCode': 'USD',
        'orderId': orderId,
      });
    }
    return _ManufacturingCostResolution(
      unitCost: total / quantity,
      totalCost: total,
      layerConsumptions: snapshots,
    );
  }

void _restoreInventoryCostLayersFromSaleItem(SaleItem item, DateTime now) {
    if (item.costLayerConsumptions.isEmpty) return;
    for (final consumption in item.costLayerConsumptions) {
      final index = _inventoryCostLayers
          .indexWhere((layer) => layer.id == consumption.layerId);
      if (index == -1) continue;
      final layer = _inventoryCostLayers[index];
      final remaining = layer.quantityRemaining + consumption.quantity;
      _inventoryCostLayers[index] = layer.copyWith(
        quantityRemaining: remaining,
        isClosed: false,
        updatedAt: now,
      );
    }
  }

void _closeInventoryCostLayersForPurchase(String purchaseId, DateTime now) {
    for (var i = 0; i < _inventoryCostLayers.length; i += 1) {
      final layer = _inventoryCostLayers[i];
      if (layer.purchaseId != purchaseId) continue;
      _inventoryCostLayers[i] = layer.copyWith(
        quantityRemaining: 0,
        isClosed: true,
        updatedAt: now,
      );
    }
  }

}
