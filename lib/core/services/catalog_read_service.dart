import '../../models/catalog_item.dart';
import '../../models/product.dart';

/// Read-only catalog queries shared by the typed port and data adapter.
class CatalogReadService {
  const CatalogReadService();

  List<CatalogItem> activeItems(Iterable<CatalogItem> items) =>
      List<CatalogItem>.unmodifiable(
        items.where((item) => !item.isDeleted),
      );

  Product? productById(
    String id, {
    required List<Product> products,
    required Map<String, int> indexById,
  }) {
    final index = indexById[id.trim()];
    if (index == null || index < 0 || index >= products.length) return null;
    final product = products[index];
    return product.isDeleted ? null : product;
  }

  List<Product> sortProducts(Iterable<Product> products) {
    final sorted = List<Product>.of(products);
    sorted.sort((a, b) {
      final nameCompare = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (nameCompare != 0) return nameCompare;
      final codeCompare = a.code.toLowerCase().compareTo(b.code.toLowerCase());
      if (codeCompare != 0) return codeCompare;
      return a.id.compareTo(b.id);
    });
    return sorted;
  }
}
