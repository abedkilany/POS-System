part of 'app_store.dart';

extension _AppStoreCatalogRead on AppStore {
  List<Product> get _productsReadImpl {
    unawaited(ensureProductsLoaded());
    _ensureProductsCacheReadImpl();
    return _cachedProducts!;
  }

  Product? _productByIdReadImpl(String id) {
    final index = _productIndexById[id.trim()];
    if (index == null || index < 0 || index >= _products.length) return null;
    final product = _products[index];
    return product.isDeleted ? null : product;
  }

  List<Product> get _allProductsForDiagnosticsReadImpl => List.unmodifiable(_products);

  List<PriceList> get _priceListsReadImpl {
    unawaited(ensurePriceListsLoaded());
    _ensurePriceListsCacheReadImpl();
    return _cachedPriceLists!;
  }

  List<ProductPrice> get _productPricesReadImpl {
    unawaited(ensureProductPricesLoaded());
    _ensureProductPricesCacheReadImpl();
    return _cachedProductPrices!;
  }

  List<ProductPriceOverride> get _productPriceOverridesReadImpl {
    unawaited(ensureProductPriceOverridesLoaded());
    _ensureProductPriceOverridesCacheReadImpl();
    return _cachedProductPriceOverrides!;
  }

  List<ProductCost> get _productCostsReadImpl {
    unawaited(ensureProductCostsLoaded());
    _ensureProductCostsCacheReadImpl();
    return _cachedProductCosts!;
  }

  List<CostingMethodHistory> get _costingMethodHistoryReadImpl {
    unawaited(ensureCostingMethodHistoryLoaded());
    _ensureCostingMethodHistoryCacheReadImpl();
    return _cachedCostingMethodHistory!;
  }

  List<InventoryCostLayer> get _inventoryCostLayersReadImpl {
    unawaited(ensureInventoryCostLayersLoaded());
    _ensureInventoryCostLayersCacheReadImpl();
    return _cachedInventoryCostLayers!;
  }

  List<CatalogItem> get _categoriesReadImpl {
    return List.unmodifiable(
      _categories.where((item) => !item.isDeleted).toList(growable: false),
    );
  }

  List<CatalogItem> get _brandsReadImpl {
    return List.unmodifiable(
      _brands.where((item) => !item.isDeleted).toList(growable: false),
    );
  }

  List<CatalogItem> get _unitsReadImpl {
    return List.unmodifiable(
      _units.where((item) => !item.isDeleted).toList(growable: false),
    );
  }

  List<Product> get _stockTrackedProductsReadImpl {
    unawaited(ensureProductsLoaded());
    _ensureStockTrackedProductsCacheReadImpl();
    return _cachedStockTrackedProducts!;
  }

  Product? _findProductByCodeReadImpl(String code) {
    final normalized = code.trim().toLowerCase();
    final productId = _productIdByNormalizedCode[normalized] ??
        _productIdByNormalizedBarcode[normalized];
    if (productId != null) return _findProductByIdReadImpl(productId);
    final matches = _products
        .where((product) => !product.isDeleted)
        .where(
          (product) => product.effectiveSaleUnits.any(
            (unit) =>
                unit.barcode.trim().isNotEmpty &&
                unit.barcode.trim().toLowerCase() == normalized,
          ),
        )
        .toList();
    if (matches.length != 1) return null;
    return matches.first;
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

  void _ensurePriceListsCacheReadImpl() {
    if (_cachedPriceListsGeneration == _productsRevision &&
        _cachedPriceLists != null) {
      return;
    }
    _cachedPriceLists = UnmodifiableListView(
      _priceLists.where((item) => item.isActive).toList(growable: false),
    );
    _cachedPriceListsGeneration = _productsRevision;
  }

  void _ensureProductPricesCacheReadImpl() {
    if (_cachedProductPricesGeneration == _productsRevision &&
        _cachedProductPrices != null) {
      return;
    }
    _cachedProductPrices = UnmodifiableListView(
      _productPrices.where((item) => item.isActive).toList(growable: false),
    );
    _cachedProductPricesGeneration = _productsRevision;
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

  void _ensureProductCostsCacheReadImpl() {
    if (_cachedProductCostsGeneration == _productsRevision &&
        _cachedProductCosts != null) {
      return;
    }
    _cachedProductCosts = UnmodifiableListView(
      _productCosts.toList(growable: false),
    );
    _cachedProductCostsGeneration = _productsRevision;
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

  void _ensureInventoryCostLayersCacheReadImpl() {
    if (_cachedInventoryCostLayersGeneration == _productsRevision &&
        _cachedInventoryCostLayers != null) {
      return;
    }
    _cachedInventoryCostLayers = UnmodifiableListView(
      _inventoryCostLayers.toList(growable: false)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
    );
    _cachedInventoryCostLayersGeneration = _productsRevision;
  }

  List<Product> _sortedProductsReadImpl(List<Product> items) {
    final sorted = List<Product>.from(items);
    sorted.sort((a, b) {
      final nameCompare = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (nameCompare != 0) return nameCompare;
      final codeCompare = a.code.toLowerCase().compareTo(b.code.toLowerCase());
      if (codeCompare != 0) return codeCompare;
      return a.id.compareTo(b.id);
    });
    return sorted;
  }

  Product? _findProductByIdReadImpl(String id) {
    final index = _productIndexById[id];
    if (index == null) return null;
    if (index < 0 || index >= _products.length) return null;
    final product = _products[index];
    return product.id == id ? product : null;
  }
}
