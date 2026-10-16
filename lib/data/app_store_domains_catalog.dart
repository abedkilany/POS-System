part of 'app_store.dart';

final class _CatalogDomain implements CatalogDomainPort {
  _CatalogDomain(this._store);
  final AppStore _store;

  @override
  List<Product> get products => _AppStoreCatalogRead(_store)._productsReadImpl;
  @override
  int get productsRevision => _store._productsRevision;
  @override
  int get productsPageRevision => Object.hashAll(<Object?>[
        _store._productsRevision,
        _store._purchasesRevision,
        _store._storeProfileRevision,
      ]);
  @override
  List<Product> get allProductsForDiagnostics =>
      _AppStoreCatalogRead(_store)._allProductsForDiagnosticsReadImpl;
  @override
  List<Product> get stockTrackedProducts =>
      _AppStoreCatalogRead(_store)._stockTrackedProductsReadImpl;
  @override
  List<CatalogItem> get categories =>
      _AppStoreCatalogRead(_store)._categoriesReadImpl;
  @override
  List<CatalogItem> get brands => _AppStoreCatalogRead(_store)._brandsReadImpl;
  @override
  List<CatalogItem> get units => _AppStoreCatalogRead(_store)._unitsReadImpl;
  @override
  List<ProductPriceOverride> get productPriceOverrides =>
      _AppStoreCatalogRead(_store)._productPriceOverridesReadImpl;
  @override
  List<CostingMethodHistory> get costingMethodHistory =>
      _AppStoreCatalogRead(_store)._costingMethodHistoryReadImpl;
  @override
  Product? productById(String id) =>
      _AppStoreCatalogRead(_store)._productByIdReadImpl(id);
  @override
  Future<void> ensureLoaded() => _store._ensureProductsLoadedImpl();
  @override
  Future<void> ensureProductsLoaded() => _store._ensureProductsLoadedImpl();
  @override
  Future<void> ensureProductCostsLoaded() =>
      _store._ensureProductCostsLoadedImpl();
  @override
  Future<void> ensureProductPricesLoaded() =>
      _store._ensureProductPricesLoadedImpl();
  @override
  Future<void> addOrUpdateProduct(Product product) =>
      _AppStoreSplitCatalogPartiesExpenses(_store).addOrUpdateProduct(product);
  @override
  Future<void> addOrUpdateCategory(CatalogItem item) =>
      _AppStoreCatalogPartiesExpensesCatalogParties(_store)
          .addOrUpdateCategory(item);
  @override
  Future<void> addOrUpdateBrand(CatalogItem item) =>
      _AppStoreCatalogPartiesExpensesCatalogParties(_store).addOrUpdateBrand(item);
  @override
  Future<void> addOrUpdateUnit(CatalogItem item) =>
      _AppStoreCatalogPartiesExpensesCatalogParties(_store).addOrUpdateUnit(item);
  @override
  int productsUsingCatalogItem(String type, CatalogItem item) =>
      _AppStoreCatalogPartiesExpensesCatalogParties(_store)
          .productsUsingCatalogItem(type, item);
  @override
  Future<void> replaceAndDeleteCatalogItem({
    required String type,
    required CatalogItem item,
    CatalogItem? replacement,
  }) =>
      _AppStoreCatalogPartiesExpensesCatalogParties(_store)
          .replaceAndDeleteCatalogItem(
        type: type,
        item: item,
        replacement: replacement,
      );
  @override
  ProductCost productCostFor(String productId) =>
      _AppStoreSplitCoreLoading(_store).productCostFor(productId);
  @override
  Future<ProductCostSnapshot> productCostSnapshotForProduct(
    Product product, {
    String warehouseId = '',
  }) =>
      _AppStorePricingCostingPolicy(_store)
          .productCostSnapshotForProduct(product, warehouseId: warehouseId);
  @override
  Future<Map<String, ProductCostSnapshot>> productCostSnapshotsForProducts(
    Iterable<Product> products, {
    String warehouseId = '',
  }) =>
      _AppStorePricingCostingPolicy(_store).productCostSnapshotsForProducts(
        products,
        warehouseId: warehouseId,
      );
  @override
  double defaultProductUsdPrice(Product product, {String unitId = 'base'}) =>
      _AppStoreSplitCoreLoading(_store)
          .defaultProductUsdPrice(product, unitId: unitId);
  @override
  ProductPrice? defaultProductPriceFor(String productId,
          {String unitId = 'base'}) =>
      _AppStoreSplitCoreLoading(_store)
          .defaultProductPriceFor(productId, unitId: unitId);
  @override
  ProductPrice? productPriceFor(String productId, String priceListId,
          {String unitId = 'base'}) =>
      _AppStoreSplitCoreLoading(_store)
          .productPriceFor(productId, priceListId, unitId: unitId);
  @override
  ProductPriceOverride? productPriceOverrideFor(
    ProductPrice price,
    String currencyCode,
  ) =>
      _AppStoreSplitCoreLoading(_store)
          .productPriceOverrideFor(price, currencyCode);
  @override
  Future<List<ProductPriceHistoryEntry>> productPriceHistoryForProduct(
    String productId, {
    int limit = 200,
  }) =>
      _AppStoreSplitPricingCosting(_store)
          .productPriceHistoryForProduct(productId, limit: limit);
  @override
  Future<void> setDefaultProductBasePrice({
    required String productId,
    required String unitId,
    required double amount,
    required String currencyCode,
  }) =>
      _AppStoreSplitPricingCosting(_store).setDefaultProductBasePrice(
        productId: productId,
        unitId: unitId,
        amount: amount,
        currencyCode: currencyCode,
      );
  @override
  Future<void> setProductBasePriceForList({
    required String productId,
    required String priceListId,
    required double amount,
    required String currencyCode,
    String unitId = 'base',
  }) =>
      _AppStoreSplitPricingCosting(_store).setProductBasePriceForList(
        productId: productId,
        priceListId: priceListId,
        amount: amount,
        currencyCode: currencyCode,
        unitId: unitId,
      );
  @override
  Future<BulkPriceAdjustmentResult> bulkAdjustProductPrices({
    required Iterable<String> productIds,
    required String priceListId,
    required double percentage,
    required bool increase,
    String unitId = 'base',
  }) =>
      _AppStoreSplitPricingCosting(_store).bulkAdjustProductPrices(
        productIds: productIds,
        priceListId: priceListId,
        percentage: percentage,
        increase: increase,
        unitId: unitId,
      );
  @override
  Future<void> setProductPriceOverride({
    required String productPriceId,
    required String currencyCode,
    required double amount,
    ProductPriceOverrideMode mode = ProductPriceOverrideMode.fixed,
    bool isActive = true,
  }) =>
      _AppStoreSplitPricingCosting(_store).setProductPriceOverride(
        productPriceId: productPriceId,
        currencyCode: currencyCode,
        amount: amount,
        mode: mode,
        isActive: isActive,
      );
  @override
  Future<void> removeProductPriceOverride(
    String productPriceId,
    String currencyCode,
  ) =>
      _AppStoreSplitPricingCosting(_store)
          .removeProductPriceOverride(productPriceId, currencyCode);
  @override
  Future<void> deleteProduct(String id) =>
      _AppStoreSplitCatalogPartiesExpenses(_store).deleteProduct(id);
}
