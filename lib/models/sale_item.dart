class SaleItem {
  const SaleItem({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    this.unitCost = 0,
    this.unitName = '',
    this.baseQuantity = 0,
    this.conversionToBase = 1,
  });

  final String productId;
  final String productName;
  final double unitPrice;
  final double quantity;
  final String unitName;
  final double baseQuantity;
  final double conversionToBase;

  /// Product cost captured at the time of sale.
  /// This keeps profit reports accurate even if product cost changes later.
  final double unitCost;

  double get effectiveBaseQuantity => baseQuantity > 0 ? baseQuantity : quantity * conversionToBase;
  double get unitCostPerBase => conversionToBase <= 0 ? unitCost : unitCost;
  double get lineTotal => unitPrice * quantity;
  double get lineCost => unitCost * effectiveBaseQuantity;
  double get lineProfit => lineTotal - lineCost;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'unitPrice': unitPrice,
        'quantity': quantity,
        'unitCost': unitCost,
        'unitName': unitName,
        'baseQuantity': effectiveBaseQuantity,
        'conversionToBase': conversionToBase,
      };

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    final rawUnitCost = json['unitCost'] ?? json['costPrice'] ?? json['unit_cost'] ?? 0;
    return SaleItem(
      productId: json['productId'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      unitPrice: (json['unitPrice'] as num? ?? 0).toDouble(),
      quantity: (json['quantity'] as num? ?? 0).toDouble(),
      unitName: json['unitName'] as String? ?? '',
      baseQuantity: (json['baseQuantity'] as num? ?? 0).toDouble(),
      conversionToBase: (json['conversionToBase'] as num? ?? 1).toDouble(),
      unitCost: (rawUnitCost as num? ?? 0).toDouble(),
    );
  }
}
