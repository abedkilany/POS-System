class SaleItem {
  const SaleItem({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    this.unitCost = 0,
  });

  final String productId;
  final String productName;
  final double unitPrice;
  final int quantity;

  /// Product cost captured at the time of sale.
  /// This keeps profit reports accurate even if product cost changes later.
  final double unitCost;

  double get lineTotal => unitPrice * quantity;
  double get lineCost => unitCost * quantity;
  double get lineProfit => lineTotal - lineCost;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'unitPrice': unitPrice,
        'quantity': quantity,
        'unitCost': unitCost,
      };

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    final rawUnitCost = json['unitCost'] ?? json['costPrice'] ?? json['unit_cost'] ?? 0;
    return SaleItem(
      productId: json['productId'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      unitPrice: (json['unitPrice'] as num? ?? 0).toDouble(),
      quantity: (json['quantity'] as num? ?? 0).toInt(),
      unitCost: (rawUnitCost as num? ?? 0).toDouble(),
    );
  }
}
