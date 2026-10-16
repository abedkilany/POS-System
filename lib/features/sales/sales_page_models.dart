part of 'sales_page.dart';

class _SaleShiftStatus {
  const _SaleShiftStatus(
      {required this.drawer,
      required this.openSession,
      required this.drawers,
      required this.cashLocations,
      required this.branchId});
  final AdvancedAccountingItem? drawer;
  final AdvancedAccountingItem? openSession;
  final List<AdvancedAccountingItem> drawers;
  final List<AdvancedAccountingItem> cashLocations;
  final String branchId;
}

class _BarcodeProductMatch {
  const _BarcodeProductMatch({required this.product, required this.unit});
  final Product product;
  final ProductSaleUnit? unit;
}

class _SalesQueryResult {
  const _SalesQueryResult({required this.items, required this.totalCount});
  final List<SaleSummary> items;
  final int totalCount;
  bool get hasMore => items.length < totalCount;
}

class _PostedSaleEditLine {
  _PostedSaleEditLine(
      {required this.product,
      required this.quantity,
      required this.unitPrice,
      required this.unitName,
      required this.conversionToBase});
  Product product;
  double quantity;
  double unitPrice;
  String unitName;
  double conversionToBase;
}

enum _QuickProductTileSize { small, medium, large }

class _QuickProductSlot {
  const _QuickProductSlot({this.productId, this.shortName});
  final String? productId;
  final String? shortName;
  Map<String, dynamic> toJson() =>
      {'productId': productId, 'shortName': shortName};
  factory _QuickProductSlot.fromJson(Map<String, dynamic> json) =>
      _QuickProductSlot(
          productId: json['productId'] as String?,
          shortName: json['shortName'] as String?);
}

class _QuickProductPage {
  _QuickProductPage({required this.name, required this.slots});
  String name;
  final List<_QuickProductSlot> slots;
  Map<String, dynamic> toJson() =>
      {'name': name, 'slots': slots.map((slot) => slot.toJson()).toList()};
  factory _QuickProductPage.fromJson(Map<String, dynamic> json) {
    final rawSlots = json['slots'];
    final slots = rawSlots is List
        ? rawSlots
            .whereType<Map<String, dynamic>>()
            .map(_QuickProductSlot.fromJson)
            .toList()
        : <_QuickProductSlot>[];
    while (slots.length < 12) {
      slots.add(const _QuickProductSlot());
    }
    if (slots.length > 12) slots.removeRange(12, slots.length);
    return _QuickProductPage(
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? (json['name'] as String).trim()
            : 'Favorites',
        slots: slots);
  }
}

class _HeldSaleCart {
  const _HeldSaleCart(
      {required this.id,
      required this.name,
      required this.createdAt,
      required this.items});
  final String id;
  final String name;
  final DateTime createdAt;
  final List<_HeldSaleItem> items;
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'items': items.map((item) => item.toJson()).toList()
      };
  factory _HeldSaleCart.fromJson(Map<String, dynamic> json) => _HeldSaleCart(
      id: json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? 'Hold',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((item) =>
              _HeldSaleItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .where((item) => item.quantity > 0 && item.productId.isNotEmpty)
          .toList());
}

class _HeldSaleItem {
  const _HeldSaleItem(
      {required this.productId,
      required this.productName,
      required this.quantity,
      required this.saleUnitId,
      required this.saleUnit});
  final String productId;
  final String productName;
  final double quantity;
  final String saleUnitId;
  final ProductSaleUnit saleUnit;
  factory _HeldSaleItem.fromDraft(SaleCartItem item) => _HeldSaleItem(
      productId: item.product.id,
      productName: item.displayName,
      quantity: item.quantity,
      saleUnitId: item.saleUnit.id,
      saleUnit: item.saleUnit);
  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'saleUnitId': saleUnitId,
        'saleUnit': saleUnit.toJson()
      };
  factory _HeldSaleItem.fromJson(Map<String, dynamic> json) => _HeldSaleItem(
      productId: json['productId'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      quantity: (json['quantity'] as num? ?? 0).toDouble(),
      saleUnitId: json['saleUnitId'] as String? ?? 'base',
      saleUnit: ProductSaleUnit.fromJson(
          Map<String, dynamic>.from(json['saleUnit'] as Map? ?? const {})));
}
