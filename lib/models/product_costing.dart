enum InventoryCostingMethod { weightedAverage, fifo, lastPurchaseCost }

extension InventoryCostingMethodJson on InventoryCostingMethod {
  String get code {
    switch (this) {
      case InventoryCostingMethod.fifo:
        return 'fifo';
      case InventoryCostingMethod.lastPurchaseCost:
        return 'last_purchase_cost';
      case InventoryCostingMethod.weightedAverage:
        return 'weighted_average';
    }
  }

  static InventoryCostingMethod fromCode(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'fifo':
        return InventoryCostingMethod.fifo;
      case 'last_purchase_cost':
      case 'lastpurchasecost':
      case 'last':
        return InventoryCostingMethod.lastPurchaseCost;
      case 'weighted_average':
      case 'weightedaverage':
      case 'average':
      default:
        return InventoryCostingMethod.weightedAverage;
    }
  }
}

class ProductCost {
  ProductCost({
    required this.productId,
    this.averageCost = 0,
    this.lastCost = 0,
    this.currencyCode = 'USD',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String productId;
  final double averageCost;
  final double lastCost;
  final String currencyCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProductCost copyWith({double? averageCost, double? lastCost, String? currencyCode, DateTime? createdAt, DateTime? updatedAt}) => ProductCost(
        productId: productId,
        averageCost: averageCost ?? this.averageCost,
        lastCost: lastCost ?? this.lastCost,
        currencyCode: (currencyCode ?? this.currencyCode).toUpperCase(),
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'averageCost': averageCost,
        'lastCost': lastCost,
        'currencyCode': currencyCode,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ProductCost.fromJson(Map<String, dynamic> json) {
    final updated = DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now();
    return ProductCost(
      productId: json['productId'] as String? ?? '',
      averageCost: (json['averageCost'] as num? ?? 0).toDouble(),
      lastCost: (json['lastCost'] as num? ?? 0).toDouble(),
      currencyCode: (json['currencyCode'] as String? ?? 'USD').toUpperCase(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? updated,
      updatedAt: updated,
    );
  }
}

class CostingMethodHistory {
  CostingMethodHistory({
    required this.id,
    required this.method,
    required this.effectiveFrom,
    this.effectiveTo,
    this.reason = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final InventoryCostingMethod method;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final String reason;
  final DateTime createdAt;
  final DateTime updatedAt;

  CostingMethodHistory copyWith({InventoryCostingMethod? method, DateTime? effectiveFrom, DateTime? effectiveTo, bool clearEffectiveTo = false, String? reason, DateTime? createdAt, DateTime? updatedAt}) => CostingMethodHistory(
        id: id,
        method: method ?? this.method,
        effectiveFrom: effectiveFrom ?? this.effectiveFrom,
        effectiveTo: clearEffectiveTo ? null : (effectiveTo ?? this.effectiveTo),
        reason: reason ?? this.reason,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method.code,
        'effectiveFrom': effectiveFrom.toIso8601String(),
        'effectiveTo': effectiveTo?.toIso8601String(),
        'reason': reason,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory CostingMethodHistory.fromJson(Map<String, dynamic> json) {
    final updated = DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now();
    return CostingMethodHistory(
      id: json['id'] as String? ?? '',
      method: InventoryCostingMethodJson.fromCode(json['method'] as String?),
      effectiveFrom: DateTime.tryParse(json['effectiveFrom'] as String? ?? '') ?? updated,
      effectiveTo: DateTime.tryParse(json['effectiveTo'] as String? ?? ''),
      reason: json['reason'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? updated,
      updatedAt: updated,
    );
  }
}
