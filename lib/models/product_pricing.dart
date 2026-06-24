enum ProductPriceOverrideMode { fixed, manual }

extension ProductPriceOverrideModeJson on ProductPriceOverrideMode {
  String get code => this == ProductPriceOverrideMode.manual ? 'manual' : 'fixed';

  static ProductPriceOverrideMode fromCode(String? value) {
    return value == 'manual' ? ProductPriceOverrideMode.manual : ProductPriceOverrideMode.fixed;
  }
}

class PriceList {
  PriceList({
    required this.id,
    required this.name,
    this.code = '',
    this.isDefault = false,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String name;
  final String code;
  final bool isDefault;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  PriceList copyWith({String? id, String? name, String? code, bool? isDefault, bool? isActive, DateTime? createdAt, DateTime? updatedAt}) => PriceList(
        id: id ?? this.id,
        name: name ?? this.name,
        code: code ?? this.code,
        isDefault: isDefault ?? this.isDefault,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'isDefault': isDefault,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory PriceList.fromJson(Map<String, dynamic> json) {
    final updated = DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now();
    return PriceList(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? updated,
      updatedAt: updated,
    );
  }
}

class ProductPrice {
  ProductPrice({
    required this.id,
    required this.productId,
    required this.priceListId,
    required this.unitId,
    required this.baseCurrencyCode,
    required this.baseAmount,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String productId;
  final String priceListId;
  final String unitId;
  final String baseCurrencyCode;
  final double baseAmount;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProductPrice copyWith({String? id, String? productId, String? priceListId, String? unitId, String? baseCurrencyCode, double? baseAmount, bool? isActive, DateTime? createdAt, DateTime? updatedAt}) => ProductPrice(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        priceListId: priceListId ?? this.priceListId,
        unitId: unitId ?? this.unitId,
        baseCurrencyCode: (baseCurrencyCode ?? this.baseCurrencyCode).toUpperCase(),
        baseAmount: baseAmount ?? this.baseAmount,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'priceListId': priceListId,
        'unitId': unitId,
        'baseCurrencyCode': baseCurrencyCode,
        'baseAmount': baseAmount,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ProductPrice.fromJson(Map<String, dynamic> json) {
    final updated = DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now();
    return ProductPrice(
      id: json['id'] as String? ?? '',
      productId: json['productId'] as String? ?? '',
      priceListId: json['priceListId'] as String? ?? '',
      unitId: json['unitId'] as String? ?? 'base',
      baseCurrencyCode: (json['baseCurrencyCode'] as String? ?? 'USD').toUpperCase(),
      baseAmount: (json['baseAmount'] as num? ?? 0).toDouble(),
      isActive: json['isActive'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? updated,
      updatedAt: updated,
    );
  }
}

class ProductPriceOverride {
  ProductPriceOverride({
    required this.id,
    required this.productPriceId,
    required this.currencyCode,
    required this.amount,
    this.mode = ProductPriceOverrideMode.fixed,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String productPriceId;
  final String currencyCode;
  final double amount;
  final ProductPriceOverrideMode mode;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProductPriceOverride copyWith({String? id, String? productPriceId, String? currencyCode, double? amount, ProductPriceOverrideMode? mode, bool? isActive, DateTime? createdAt, DateTime? updatedAt}) => ProductPriceOverride(
        id: id ?? this.id,
        productPriceId: productPriceId ?? this.productPriceId,
        currencyCode: (currencyCode ?? this.currencyCode).toUpperCase(),
        amount: amount ?? this.amount,
        mode: mode ?? this.mode,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'productPriceId': productPriceId,
        'currencyCode': currencyCode,
        'amount': amount,
        'mode': mode.code,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ProductPriceOverride.fromJson(Map<String, dynamic> json) {
    final updated = DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now();
    return ProductPriceOverride(
      id: json['id'] as String? ?? '',
      productPriceId: json['productPriceId'] as String? ?? '',
      currencyCode: (json['currencyCode'] as String? ?? 'USD').toUpperCase(),
      amount: (json['amount'] as num? ?? 0).toDouble(),
      mode: ProductPriceOverrideModeJson.fromCode(json['mode'] as String?),
      isActive: json['isActive'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? updated,
      updatedAt: updated,
    );
  }
}
