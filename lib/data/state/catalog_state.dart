import '../../models/catalog_item.dart';
import '../../models/product.dart';
import '../../models/product_costing.dart';
import '../../models/product_pricing.dart';
import '../../models/supplier_product_price.dart';
import 'dart:collection';

/// Session-local cache state. SQLite remains authoritative.
class CatalogState {
  final List<Product> products = [];
  final List<SupplierProductPrice> supplierProductPrices = [];
  final List<PriceList> priceLists = [];
  final List<ProductPrice> productPrices = [];
  final List<ProductPriceOverride> productPriceOverrides = [];
  final List<ProductCost> productCosts = [];
  final List<CostingMethodHistory> costingMethodHistory = [];
  final List<CatalogItem> categories = [];
  final List<CatalogItem> brands = [];
  final List<CatalogItem> units = [];
  final Map<String, int> productIndexById = <String, int>{};
  final Map<String, String> productIdByNormalizedCode = <String, String>{};
  final Map<String, String> productIdByNormalizedBarcode = <String, String>{};
  final Map<String, ProductPrice> productPriceByLookupKey =
      <String, ProductPrice>{};
  final Map<String, ProductCost> productCostByProductId =
      <String, ProductCost>{};
  final Map<String, int> productCostIndexByProductId = <String, int>{};
  List<Product>? cachedProducts;
  int cachedProductsGeneration = -1;
  List<Product>? cachedStockTrackedProducts;
  int cachedStockTrackedProductsGeneration = -1;
  UnmodifiableListView<ProductPriceOverride>? cachedProductPriceOverrides;
  UnmodifiableListView<CostingMethodHistory>? cachedCostingMethodHistory;
  int cachedProductPriceOverridesGeneration = -1;
  int cachedCostingMethodHistoryGeneration = -1;
}
