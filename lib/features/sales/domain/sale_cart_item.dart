import '../../../models/product.dart';

class SaleCartItem {
  const SaleCartItem(
      {required this.product,
      required this.quantity,
      ProductSaleUnit? saleUnit})
      : saleUnit = saleUnit ??
            const ProductSaleUnit(
                id: 'base',
                name: '',
                conversionToBase: 1,
                price: 0,
                isDefault: true);
  final Product product;
  final double quantity;
  final ProductSaleUnit saleUnit;
  double get unitPrice => saleUnit.price > 0 ? saleUnit.price : product.price;
  double get conversionToBase =>
      saleUnit.conversionToBase <= 0 ? 1 : saleUnit.conversionToBase;
  double get baseQuantity => quantity * conversionToBase;
  String get unitName =>
      saleUnit.name.trim().isNotEmpty ? saleUnit.name : product.unit;
  String get displayName =>
      saleUnit.id == 'base' || saleUnit.name.trim().isEmpty
          ? product.name
          : saleUnit.name.trim();
  double get lineTotal => quantity * unitPrice;
  bool get needsAutoCorrection =>
      product.trackStock && baseQuantity > product.stock;
  SaleCartItem copyWith(
      {Product? product, double? quantity, ProductSaleUnit? saleUnit}) {
    return SaleCartItem(
        product: product ?? this.product,
        quantity: quantity ?? this.quantity,
        saleUnit: saleUnit ?? this.saleUnit);
  }
}
