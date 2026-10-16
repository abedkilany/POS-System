import 'dart:collection';

import '../../../models/product.dart';
import 'sale_cart_item.dart';

/// Editable draft lines, independent of widgets, storage and the session.
class SaleCart {
  final List<SaleCartItem> _items = [];
  late final List<SaleCartItem> items = UnmodifiableListView(_items);

  int add(Product product, ProductSaleUnit unit) {
    final unitName = unit.name.trim().isNotEmpty ? unit.name : product.unit;
    final index = _items.indexWhere(
        (item) => item.product.id == product.id && item.unitName == unitName);
    if (index < 0) {
      _items.insert(
          0, SaleCartItem(product: product, quantity: 1, saleUnit: unit));
      return 0;
    }
    _items[index] =
        _items[index].copyWith(quantity: _items[index].quantity + 1);
    return index;
  }

  /// Returns whether the requested quantity exceeds the product's stock cache.
  /// Authoritative warehouse availability is checked again when posting.
  bool changeQuantity(int index, double quantity) {
    if (index < 0 || index >= _items.length || !quantity.isFinite) return false;
    final item = _items[index];
    final minimum = item.product.allowsDecimalQuantity ? 0.001 : 1.0;
    final rounded = item.product.allowsDecimalQuantity
        ? quantity
        : quantity.roundToDouble();
    final next = item.copyWith(quantity: rounded < minimum ? minimum : rounded);
    _items[index] = next;
    return next.needsAutoCorrection;
  }

  void reprice(double Function(Product, ProductSaleUnit) priceFor) {
    for (var index = 0; index < _items.length; index++) {
      final item = _items[index];
      _items[index] = item.copyWith(
        saleUnit: item.saleUnit
            .copyWith(price: priceFor(item.product, item.saleUnit)),
      );
    }
  }

  void removeAt(int index) => _items.removeAt(index);
  void clear() => _items.clear();
  void replaceAll(Iterable<SaleCartItem> items) {
    final snapshot = items.toList();
    _items
      ..clear()
      ..addAll(snapshot);
  }

  double get subtotal => _items.fold(0, (sum, item) => sum + item.lineTotal);
  double get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  SaleCartTotals totals({required double discount, double? batchCost}) {
    final revenue = (subtotal - discount).clamp(0, double.infinity).toDouble();
    final cost = batchCost ??
        _items.fold<double>(
            0, (sum, item) => sum + item.baseQuantity * item.product.usdCost);
    return SaleCartTotals(revenue: revenue, cost: cost);
  }
}

class SaleCartTotals {
  const SaleCartTotals({required this.revenue, required this.cost});
  final double revenue;
  final double cost;
  double get profit => revenue - cost;
  double get profitPercent => revenue <= 0 ? 0 : profit / revenue * 100;
}
