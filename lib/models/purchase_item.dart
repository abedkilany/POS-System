class PurchaseItem {
  const PurchaseItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCost,
    this.purchaseUnitId = 'base',
    this.purchaseUnitName = '',
    this.conversionToBase = 1,
    this.originalUnitCost,
    this.unitCostCurrency = 'USD',
    this.exchangeRateAtEntry = 0,
  });

  final String productId;
  final String productName;
  /// Quantity entered in the selected purchase unit. Supports decimals for measurable products.
  final double quantity;
  /// USD reference unit cost for the selected purchase unit.
  final double unitCost;
  final String purchaseUnitId;
  final String purchaseUnitName;
  /// How many base inventory units are contained in one selected purchase unit.
  final double conversionToBase;
  final double? originalUnitCost;
  final String unitCostCurrency;
  final double exchangeRateAtEntry;

  double get baseQuantity => quantity * conversionToBase;
  double get unitCostPerBase => conversionToBase <= 0 ? unitCost : unitCost / conversionToBase;
  double get lineTotal => quantity * unitCost;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'unitCost': unitCost,
        'purchaseUnitId': purchaseUnitId,
        'purchaseUnitName': purchaseUnitName,
        'conversionToBase': conversionToBase,
        'baseQuantity': baseQuantity,
        'unitCostPerBase': unitCostPerBase,
        'originalUnitCost': originalUnitCost ?? unitCost,
        'unitCostCurrency': unitCostCurrency,
        'exchangeRateAtEntry': exchangeRateAtEntry,
      };

  factory PurchaseItem.fromJson(Map<String, dynamic> json) {
    final rawCurrency = (json['unitCostCurrency'] as String? ?? 'USD').toUpperCase();
    final currency = rawCurrency == 'LBP' ? 'LBP' : 'USD';
    final unitCost = (json['unitCost'] as num? ?? 0).toDouble();
    return PurchaseItem(
        productId: json['productId']?.toString() ?? '',
        productName: json['productName']?.toString() ?? '',
        quantity: (json['quantity'] as num? ?? 0).toDouble(),
        unitCost: unitCost,
        purchaseUnitId: json['purchaseUnitId']?.toString() ?? 'base',
        purchaseUnitName: json['purchaseUnitName']?.toString() ?? '',
        conversionToBase: (json['conversionToBase'] as num? ?? 1).toDouble(),
        originalUnitCost: (json['originalUnitCost'] as num?)?.toDouble() ?? unitCost,
        unitCostCurrency: currency,
        exchangeRateAtEntry: (json['exchangeRateAtEntry'] as num? ?? 0).toDouble(),
      );
  }
}
