import 'product_costing.dart';

class InventoryCostLayerConsumption {
  const InventoryCostLayerConsumption({
    required this.layerId,
    required this.quantity,
    required this.unitCost,
    this.currencyCode = 'USD',
  });

  final String layerId;
  final double quantity;
  final double unitCost;
  final String currencyCode;

  double get totalCost => quantity * unitCost;

  Map<String, dynamic> toJson() => {
        'layerId': layerId,
        'quantity': quantity,
        'unitCost': unitCost,
        'currencyCode': currencyCode,
      };

  factory InventoryCostLayerConsumption.fromJson(Map<String, dynamic> json) =>
      InventoryCostLayerConsumption(
        layerId: json['layerId'] as String? ?? '',
        quantity: (json['quantity'] as num? ?? 0).toDouble(),
        unitCost: (json['unitCost'] as num? ?? 0).toDouble(),
        currencyCode: (json['currencyCode'] as String? ?? 'USD').toUpperCase(),
      );
}

class InventoryCostLayer {
  InventoryCostLayer({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantityReceived,
    required this.quantityRemaining,
    required this.unitCost,
    this.currencyCode = 'USD',
    this.exchangeRate = 1,
    this.purchaseId = '',
    this.purchaseItemId = '',
    this.sourceType = 'purchase',
    this.sourceId = '',
    this.isClosed = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String productId;
  final String productName;
  final double quantityReceived;
  final double quantityRemaining;
  final double unitCost;
  final String currencyCode;
  final double exchangeRate;
  final String purchaseId;
  final String purchaseItemId;
  final String sourceType;
  final String sourceId;
  final bool isClosed;
  final DateTime createdAt;
  final DateTime updatedAt;

  InventoryCostLayer copyWith({
    double? quantityReceived,
    double? quantityRemaining,
    double? unitCost,
    String? currencyCode,
    double? exchangeRate,
    String? purchaseId,
    String? purchaseItemId,
    String? sourceType,
    String? sourceId,
    bool? isClosed,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final remaining = quantityRemaining ?? this.quantityRemaining;
    return InventoryCostLayer(
      id: id,
      productId: productId,
      productName: productName,
      quantityReceived: quantityReceived ?? this.quantityReceived,
      quantityRemaining: remaining,
      unitCost: unitCost ?? this.unitCost,
      currencyCode: (currencyCode ?? this.currencyCode).toUpperCase(),
      exchangeRate: exchangeRate ?? this.exchangeRate,
      purchaseId: purchaseId ?? this.purchaseId,
      purchaseItemId: purchaseItemId ?? this.purchaseItemId,
      sourceType: sourceType ?? this.sourceType,
      sourceId: sourceId ?? this.sourceId,
      isClosed: isClosed ?? remaining <= 0,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'productName': productName,
        'quantityReceived': quantityReceived,
        'quantityRemaining': quantityRemaining,
        'unitCost': unitCost,
        'currencyCode': currencyCode,
        'exchangeRate': exchangeRate,
        'purchaseId': purchaseId,
        'purchaseItemId': purchaseItemId,
        'sourceType': sourceType,
        'sourceId': sourceId,
        'isClosed': isClosed,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory InventoryCostLayer.fromJson(Map<String, dynamic> json) {
    final updated = DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now();
    return InventoryCostLayer(
      id: json['id'] as String? ?? '',
      productId: json['productId'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      quantityReceived: (json['quantityReceived'] as num? ?? 0).toDouble(),
      quantityRemaining: (json['quantityRemaining'] as num? ?? 0).toDouble(),
      unitCost: (json['unitCost'] as num? ?? 0).toDouble(),
      currencyCode: (json['currencyCode'] as String? ?? 'USD').toUpperCase(),
      exchangeRate: (json['exchangeRate'] as num? ?? 1).toDouble(),
      purchaseId: json['purchaseId'] as String? ?? '',
      purchaseItemId: json['purchaseItemId'] as String? ?? '',
      sourceType: json['sourceType'] as String? ?? 'purchase',
      sourceId: json['sourceId'] as String? ?? '',
      isClosed: json['isClosed'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? updated,
      updatedAt: updated,
    );
  }
}

class InventoryCostResult {
  const InventoryCostResult({
    required this.method,
    required this.unitCost,
    this.currencyCode = 'USD',
    this.consumptions = const <InventoryCostLayerConsumption>[],
  });

  final InventoryCostingMethod method;
  final double unitCost;
  final String currencyCode;
  final List<InventoryCostLayerConsumption> consumptions;

  double get totalConsumedQuantity => consumptions.fold<double>(0, (sum, item) => sum + item.quantity);
}
