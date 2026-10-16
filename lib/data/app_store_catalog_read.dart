part of 'app_store.dart';

extension _AppStoreCatalogRead on AppStore {
  List<Product> get _productsReadImpl {
    unawaited(_ensureProductsLoaded());
    _ensureProductsCacheReadImpl();
    return _cachedProducts!;
  }

  Product? _productByIdReadImpl(String id) {
    return const CatalogReadService().productById(
      id,
      products: _products,
      indexById: _productIndexById,
    );
  }

  List<Product> get _allProductsForDiagnosticsReadImpl =>
      List.unmodifiable(_products);

  List<ProductPriceOverride> get _productPriceOverridesReadImpl {
    unawaited(_ensureProductPriceOverridesLoaded());
    _ensureProductPriceOverridesCacheReadImpl();
    return _cachedProductPriceOverrides!;
  }

  List<CostingMethodHistory> get _costingMethodHistoryReadImpl {
    unawaited(_ensureCostingMethodHistoryLoaded());
    _ensureCostingMethodHistoryCacheReadImpl();
    return _cachedCostingMethodHistory!;
  }

  List<CatalogItem> get _categoriesReadImpl {
    return const CatalogReadService().activeItems(_categories);
  }

  List<CatalogItem> get _brandsReadImpl {
    return const CatalogReadService().activeItems(_brands);
  }

  List<CatalogItem> get _unitsReadImpl {
    return const CatalogReadService().activeItems(_units);
  }

  List<Product> get _stockTrackedProductsReadImpl {
    unawaited(_ensureProductsLoaded());
    _ensureStockTrackedProductsCacheReadImpl();
    return _cachedStockTrackedProducts!;
  }

  void _ensureProductsCacheReadImpl() {
    if (_cachedProductsGeneration == _productsRevision &&
        _cachedProducts != null) {
      return;
    }
    _cachedProducts = List.unmodifiable(
      _sortedProductsReadImpl(
        _products.where((item) => !item.isDeleted).toList(growable: false),
      ),
    );
    _cachedProductsGeneration = _productsRevision;
  }

  void _ensureStockTrackedProductsCacheReadImpl() {
    if (_cachedStockTrackedProductsGeneration == _productsRevision &&
        _cachedStockTrackedProducts != null) {
      return;
    }
    _ensureProductsCacheReadImpl();
    _cachedStockTrackedProducts = List.unmodifiable(
      _cachedProducts!.where((item) => item.trackStock).toList(growable: false),
    );
    _cachedStockTrackedProductsGeneration = _productsRevision;
  }

  void _ensureProductPriceOverridesCacheReadImpl() {
    if (_cachedProductPriceOverridesGeneration == _productsRevision &&
        _cachedProductPriceOverrides != null) {
      return;
    }
    _cachedProductPriceOverrides = UnmodifiableListView(
      _productPriceOverrides
          .where((item) => item.isActive)
          .toList(growable: false),
    );
    _cachedProductPriceOverridesGeneration = _productsRevision;
  }

  void _ensureCostingMethodHistoryCacheReadImpl() {
    if (_cachedCostingMethodHistoryGeneration == _productsRevision &&
        _cachedCostingMethodHistory != null) {
      return;
    }
    _cachedCostingMethodHistory = UnmodifiableListView(
      _costingMethodHistory.toList(growable: false)
        ..sort((a, b) => b.effectiveFrom.compareTo(a.effectiveFrom)),
    );
    _cachedCostingMethodHistoryGeneration = _productsRevision;
  }

  List<Product> _sortedProductsReadImpl(List<Product> items) {
    return const CatalogReadService().sortProducts(items);
  }

  Product? _findProductByIdReadImpl(String id) {
    final index = _productIndexById[id];
    if (index == null) return null;
    if (index < 0 || index >= _products.length) return null;
    final product = _products[index];
    return product.id == id ? product : null;
  }

  Product? _findProductForHistoricalSaleReadImpl(String id) {
    final product = _findProductByIdReadImpl(id);
    if (product == null) return null;
    final sourceId = _historicalSourceProductId(product);
    if (sourceId.isEmpty || sourceId == product.id) return product;
    return _findProductByIdReadImpl(sourceId) ?? product;
  }

  // Sale returns must address the exact product stored on the original sale.
  // Historical products are intentionally separate catalog records, so they
  // must not be resolved back to their current/source product here.
  Product? _findProductForSaleReturnReadImpl(String id) {
    return _findProductByIdReadImpl(id);
  }

  bool _isHistoricalProductReadImpl(String id) {
    final product = _findProductByIdReadImpl(id);
    return product != null && _historicalSourceProductId(product).isNotEmpty;
  }

  String _operationalProductIdReadImpl(String id) {
    final product = _findProductByIdReadImpl(id);
    if (product == null) return id.trim();
    final sourceId = _historicalSourceProductId(product);
    return sourceId.isEmpty ? product.id : sourceId;
  }
}

String _historicalSourceProductId(Product product) {
  final match = RegExp(
    r'\[ventio-history-source-id:([^\]]+)\]',
  ).firstMatch(product.description);
  return match?.group(1)?.trim() ?? '';
}
