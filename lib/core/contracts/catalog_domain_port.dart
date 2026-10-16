import '../../models/catalog_item.dart';
import '../../models/product.dart';
import '../../models/product_cost_snapshot.dart';
import '../../models/product_costing.dart';
import '../../models/product_pricing.dart';

abstract class CatalogDomainPort {
  List<Product> get products;
  int get productsRevision;
  int get productsPageRevision;
  List<Product> get allProductsForDiagnostics;
  List<Product> get stockTrackedProducts;
  List<CatalogItem> get categories;
  List<CatalogItem> get brands;
  List<CatalogItem> get units;
  List<ProductPriceOverride> get productPriceOverrides;
  List<CostingMethodHistory> get costingMethodHistory;
  Product? productById(String id);
  Future<void> ensureLoaded();
  Future<void> ensureProductsLoaded();
  Future<void> ensureProductCostsLoaded();
  Future<void> ensureProductPricesLoaded();
  Future<void> addOrUpdateProduct(Product product);
  Future<void> addOrUpdateCategory(CatalogItem item);
  Future<void> addOrUpdateBrand(CatalogItem item);
  Future<void> addOrUpdateUnit(CatalogItem item);
  int productsUsingCatalogItem(String type, CatalogItem item);
  Future<void> replaceAndDeleteCatalogItem({
    required String type,
    required CatalogItem item,
    CatalogItem? replacement,
  });
  ProductCost productCostFor(String productId);
  Future<ProductCostSnapshot> productCostSnapshotForProduct(
    Product product, {
    String warehouseId = '',
  });
  Future<Map<String, ProductCostSnapshot>> productCostSnapshotsForProducts(
    Iterable<Product> products, {
    String warehouseId = '',
  });
  double defaultProductUsdPrice(Product product, {String unitId = 'base'});
  ProductPrice? defaultProductPriceFor(String productId,
      {String unitId = 'base'});
  ProductPrice? productPriceFor(String productId, String priceListId,
      {String unitId = 'base'});
  ProductPriceOverride? productPriceOverrideFor(
    ProductPrice price,
    String currencyCode,
  );
  Future<List<ProductPriceHistoryEntry>> productPriceHistoryForProduct(
    String productId, {
    int limit = 200,
  });
  Future<void> setDefaultProductBasePrice({
    required String productId,
    required String unitId,
    required double amount,
    required String currencyCode,
  });
  Future<void> setProductBasePriceForList({
    required String productId,
    required String priceListId,
    required double amount,
    required String currencyCode,
    String unitId = 'base',
  });
  Future<BulkPriceAdjustmentResult> bulkAdjustProductPrices({
    required Iterable<String> productIds,
    required String priceListId,
    required double percentage,
    required bool increase,
    String unitId = 'base',
  });
  Future<void> setProductPriceOverride({
    required String productPriceId,
    required String currencyCode,
    required double amount,
    ProductPriceOverrideMode mode = ProductPriceOverrideMode.fixed,
    bool isActive = true,
  });
  Future<void> removeProductPriceOverride(
    String productPriceId,
    String currencyCode,
  );
  Future<void> deleteProduct(String id);
}
