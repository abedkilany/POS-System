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

  Future<void> _persistProductPriceHistoryRows(
      List<ProductPriceHistoryEntry> rows) async {
    if (rows.isEmpty) return;
    if (LocalDatabaseService.isSqliteAuthoritative) {
      await _upsertSqliteBusinessRows(
        AppStore._productPriceHistoryKey,
        rows.map((item) => item.toJson()),
      );
      return;
    }
    final raw =
        LocalDatabaseService.getString(AppStore._productPriceHistoryKey);
    final existing = <Map<String, dynamic>>[];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          existing.addAll(decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item)));
        }
      } catch (_) {}
    }
    existing.addAll(rows.map((item) => item.toJson()));
    await LocalDatabaseService.setString(
      AppStore._productPriceHistoryKey,
      jsonEncode(existing),
    );
  }

  double _roundProductPriceAmount(double amount, String currencyCode) {
    final decimals = storeProfile.currencyByCode(currencyCode).decimalPlaces;
    final factor = pow(10, decimals.clamp(0, 6)).toDouble();
    return (amount * factor).round() / factor;
  }

  ProductPriceHistoryEntry _buildProductPriceHistoryEntry({
    required ProductPrice? previous,
    required ProductPrice next,
    required String source,
    required String changeType,
    required double changePercent,
    required String batchId,
    required DateTime changedAt,
  }) {
    return ProductPriceHistoryEntry(
      id: 'pph_${next.productId}_${next.priceListId}_${next.unitId}_${changedAt.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
      productId: next.productId,
      priceListId: next.priceListId,
      unitId: next.unitId,
      currencyCode: next.baseCurrencyCode,
      oldAmount: previous?.baseAmount ?? 0,
      newAmount: next.baseAmount,
      changePercent: changePercent,
      changeType: changeType,
      source: source,
      batchId: batchId,
      userId: _activeUser?.id ?? '',
      userName: _actorName(),
      changedAt: changedAt,
    );
  }

  Future<void> _setProductBasePriceWithHistory({
    required String productId,
    required String priceListId,
    required double amount,
    required String currencyCode,
    String unitId = 'base',
    String source = 'manual',
    String changeType = 'manual',
    double changePercent = 0,
    String batchId = '',
  }) async {
    _ensureDefaultPriceLists();
    final normalizedCurrency = currencyCode.trim().toUpperCase();
    if (normalizedCurrency.isEmpty || amount < 0 || !amount.isFinite) {
      throw ArgumentError('A valid non-negative product price is required.');
    }
    final previous = productPriceFor(productId, priceListId, unitId: unitId);
    final roundedAmount = _roundProductPriceAmount(amount, normalizedCurrency);
    if (previous != null &&
        previous.baseCurrencyCode.toUpperCase() == normalizedCurrency &&
        (previous.baseAmount - roundedAmount).abs() < 0.0000001) {
      return;
    }
    final now = DateTime.now();
    final next = ProductPrice(
      id: previous?.id ?? 'pp_${productId}_${priceListId}_$unitId',
      productId: productId,
      priceListId: priceListId,
      unitId: unitId,
      baseCurrencyCode: normalizedCurrency,
      baseAmount: roundedAmount,
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
    );
    final history = _buildProductPriceHistoryEntry(
      previous: previous,
      next: next,
      source: source,
      changeType: previous == null ? 'initial' : changeType,
      changePercent: changePercent,
      batchId: batchId,
      changedAt: now,
    );

    await LocalDatabaseService.runSqliteAuthoritativeTransaction(() async {
      await _upsertSqliteBusinessRows(
        AppStore._priceListsKey,
        _priceLists.map((item) => item.toJson()),
      );
      await _upsertSqliteBusinessRows(
        AppStore._productPricesKey,
        <Map<String, dynamic>>[next.toJson()],
      );
      await _persistProductPriceHistoryRows(
          <ProductPriceHistoryEntry>[history]);
    });

    final index = _productPrices.indexWhere((item) => item.id == next.id);
    if (index == -1) {
      _productPrices.add(next);
    } else {
      _productPrices[index] = next;
    }
    _productPriceByLookupKey[
        _productPriceLookupKey(productId, priceListId, unitId)] = next;
    _touchDataRevisions(products: true);
    _invalidateDerivedDataCaches();
    unawaited(AuditLogger.record(
      entityType: 'product_price',
      entityId: next.id,
      action: previous == null ? 'create' : 'update',
      summary: 'Product price changed',
      details: jsonEncode(history.toJson()),
      userId: _activeUser?.id ?? '',
      userName: _actorName(),
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      sessionId: _deviceId,
      traceId: _deviceId,
      deviceId: _deviceId,
      sourceModule: 'products',
      isImportant: true,
    ));
    notifyListeners();
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
    await _setProductBasePriceWithHistory(
      productId: productId,
      priceListId: defaultPriceList.id,
      unitId: unitId,
      amount: amount,
      currencyCode: currencyCode,
    );
  }

  Future<void> setProductBasePriceForList({
    required String productId,
    required String priceListId,
    required double amount,
    required String currencyCode,
    String unitId = 'base',
  }) async {
    requirePermission(AppPermission.productsEdit);
    await _setProductBasePriceWithHistory(
      productId: productId,
      priceListId: priceListId,
      amount: amount,
      currencyCode: currencyCode,
      unitId: unitId,
    );
  }

  Future<BulkPriceAdjustmentResult> bulkAdjustProductPrices({
    required Iterable<String> productIds,
    required String priceListId,
    required double percentage,
    required bool increase,
    String unitId = 'base',
  }) async {
    requireAnyPermission(<String>{
      AppPermission.productsManage,
      AppPermission.productsEdit,
    });
    await ensureProductsLoaded();
    await ensureProductPricesLoaded();
    final normalizedList = priceListId.trim();
    if (!const {'retail', 'wholesale', 'wholesale_bulk'}
        .contains(normalizedList)) {
      throw ArgumentError('Unsupported price list.');
    }
    if (!percentage.isFinite ||
        percentage <= 0 ||
        (!increase && percentage > 100)) {
      throw ArgumentError('Invalid percentage.');
    }
    final ids =
        productIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) {
      return const BulkPriceAdjustmentResult(
        updatedCount: 0,
        skippedMissingPriceCount: 0,
        unchangedCount: 0,
        batchId: '',
      );
    }

    _ensureDefaultPriceLists();
    _ensureProductPricingLookupCaches();
    final now = DateTime.now();
    final batchId = 'bulk_price_${now.microsecondsSinceEpoch}';
    final changedPrices = <ProductPrice>[];
    final histories = <ProductPriceHistoryEntry>[];
    final changedProducts = <Product>[];
    var missing = 0;
    var unchanged = 0;

    for (final productId in ids) {
      final productIndex = _productIndexById[productId];
      if (productIndex == null ||
          productIndex < 0 ||
          productIndex >= _products.length) {
        missing += 1;
        continue;
      }
      final product = _products[productIndex];
      if (product.isDeleted) {
        missing += 1;
        continue;
      }
      final previous =
          productPriceFor(productId, normalizedList, unitId: unitId);
      if (previous == null) {
        missing += 1;
        continue;
      }
      final factor = increase ? (1 + percentage / 100) : (1 - percentage / 100);
      final rawNextAmount = previous.baseAmount * factor;
      if (!rawNextAmount.isFinite || rawNextAmount < 0) {
        throw ArgumentError(
            'The requested price adjustment produces an invalid price.');
      }
      final nextAmount = _roundProductPriceAmount(
        rawNextAmount,
        previous.baseCurrencyCode,
      );
      if ((nextAmount - previous.baseAmount).abs() < 0.0000001) {
        unchanged += 1;
        continue;
      }
      final next = previous.copyWith(baseAmount: nextAmount, updatedAt: now);
      changedPrices.add(next);
      histories.add(_buildProductPriceHistoryEntry(
        previous: previous,
        next: next,
        source: 'bulk',
        changeType: increase ? 'increase' : 'decrease',
        changePercent: percentage,
        batchId: batchId,
        changedAt: now,
      ));
      if (normalizedList == 'retail' && unitId == 'base') {
        final usd = toUsdReferencePrice(
          nextAmount,
          next.baseCurrencyCode,
          storeProfile,
        );
        changedProducts.add(product.copyWith(
          price: usd,
          originalPrice: nextAmount,
          originalCurrency: next.baseCurrencyCode,
          usdPrice: usd,
          exchangeRateAtEntry: storeProfile.usdToLbpRate,
          updatedAt: now,
          version: product.version + 1,
          lastModifiedByDeviceId: _deviceId,
        ));
      }
    }

    if (changedPrices.isEmpty) {
      return BulkPriceAdjustmentResult(
        updatedCount: 0,
        skippedMissingPriceCount: missing,
        unchangedCount: unchanged,
        batchId: batchId,
      );
    }

    await LocalDatabaseService.runSqliteAuthoritativeTransaction(() async {
      await _upsertSqliteBusinessRows(
        AppStore._productPricesKey,
        changedPrices.map((item) => item.toJson()),
      );
      await _persistProductPriceHistoryRows(histories);
      if (changedProducts.isNotEmpty) {
        await _upsertSqliteBusinessRows(
          AppStore._productsKey,
          changedProducts.map((item) => item.toJson()),
        );
      }
    });

    for (final next in changedPrices) {
      final index = _productPrices.indexWhere((item) => item.id == next.id);
      if (index == -1) {
        _productPrices.add(next);
      } else {
        _productPrices[index] = next;
      }
      _productPriceByLookupKey[_productPriceLookupKey(
          next.productId, next.priceListId, next.unitId)] = next;
    }
    for (final product in changedProducts) {
      final index = _productIndexById[product.id];
      if (index != null && index >= 0 && index < _products.length) {
        _products[index] = product;
      }
    }
    _touchDataRevisions(products: true);
    _invalidateDerivedDataCaches();
    unawaited(AuditLogger.record(
      entityType: 'product_price_batch',
      entityId: batchId,
      action: increase ? 'bulk_increase' : 'bulk_decrease',
      summary: 'Bulk product price adjustment',
      details: jsonEncode(<String, dynamic>{
        'priceListId': normalizedList,
        'unitId': unitId,
        'percentage': percentage,
        'updatedCount': changedPrices.length,
        'skippedMissingPriceCount': missing,
        'unchangedCount': unchanged,
        'productIds': changedPrices.map((item) => item.productId).toList(),
      }),
      userId: _activeUser?.id ?? '',
      userName: _actorName(),
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      sessionId: _deviceId,
      traceId: _deviceId,
      deviceId: _deviceId,
      sourceModule: 'products',
      isImportant: true,
    ));
    notifyListeners();
    return BulkPriceAdjustmentResult(
      updatedCount: changedPrices.length,
      skippedMissingPriceCount: missing,
      unchangedCount: unchanged,
      batchId: batchId,
    );
  }

  Future<List<ProductPriceHistoryEntry>> productPriceHistoryForProduct(
    String productId, {
    int limit = 200,
  }) async {
    final sqliteRows =
        await LocalDatabaseService.getProductPriceHistoryFromSqlite(
      productId: productId,
      limit: limit,
    );
    if (sqliteRows != null) return sqliteRows;
    final raw =
        LocalDatabaseService.getString(AppStore._productPriceHistoryKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <ProductPriceHistoryEntry>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <ProductPriceHistoryEntry>[];
      final rows = decoded
          .whereType<Map>()
          .map((item) => ProductPriceHistoryEntry.fromJson(
              Map<String, dynamic>.from(item)))
          .where((item) => item.productId == productId)
          .toList();
      rows.sort((a, b) => b.changedAt.compareTo(a.changedAt));
      return rows.take(limit.clamp(1, 2000).toInt()).toList(growable: false);
    } catch (_) {
      return const <ProductPriceHistoryEntry>[];
    }
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
    await _upsertSqliteBusinessRows(AppStore._productPriceOverridesKey,
        <Map<String, dynamic>>[override.toJson()]);
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
    await _upsertSqliteBusinessRows(AppStore._productPriceOverridesKey,
        <Map<String, dynamic>>[override.toJson()]);
    _touchDataRevisions(products: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
  }
}
