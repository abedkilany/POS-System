class PurchaseItem {
  const PurchaseItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCost,
  });

  final String productId;
  final String productName;
  final int quantity;
  final double unitCost;

  double get lineTotal => quantity * unitCost;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'unitCost': unitCost,
      };

  factory PurchaseItem.fromJson(Map<String, dynamic> json) => PurchaseItem(
        productId: json['productId']?.toString() ?? '',
        productName: json['productName']?.toString() ?? '',
        quantity: (json['quantity'] as num? ?? 0).toInt(),
        unitCost: (json['unitCost'] as num? ?? 0).toDouble(),
      );
}
