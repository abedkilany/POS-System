enum ProductQuantityType { countable, measurable }

extension ProductQuantityTypeJson on ProductQuantityType {
  String get code => this == ProductQuantityType.measurable ? 'measurable' : 'countable';

  static ProductQuantityType fromCode(String? value) {
    return value == 'measurable' ? ProductQuantityType.measurable : ProductQuantityType.countable;
  }
}

class ProductSaleUnit {
  const ProductSaleUnit({
    required this.id,
    required this.name,
    required this.conversionToBase,
    required this.price,
    double? originalPrice,
    this.originalCurrency = 'USD',
    this.barcode = '',
    this.isDefault = false,
  }) : originalPrice = originalPrice ?? price;

  final String id;
  final String name;
  final double conversionToBase;
  final double price;
  final double originalPrice;
  final String originalCurrency;
  final String barcode;
  final bool isDefault;

  ProductSaleUnit copyWith({String? id, String? name, double? conversionToBase, double? price, double? originalPrice, String? originalCurrency, String? barcode, bool? isDefault}) => ProductSaleUnit(
        id: id ?? this.id,
        name: name ?? this.name,
        conversionToBase: conversionToBase ?? this.conversionToBase,
        price: price ?? this.price,
        originalPrice: originalPrice ?? this.originalPrice,
        originalCurrency: originalCurrency ?? this.originalCurrency,
        barcode: barcode ?? this.barcode,
        isDefault: isDefault ?? this.isDefault,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'conversionToBase': conversionToBase,
        'price': price,
        'originalPrice': originalPrice,
        'originalCurrency': originalCurrency,
        'barcode': barcode,
        'isDefault': isDefault,
      };

  factory ProductSaleUnit.fromJson(Map<String, dynamic> json) => ProductSaleUnit(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        conversionToBase: (json['conversionToBase'] as num? ?? 1).toDouble(),
        price: (json['price'] as num? ?? 0).toDouble(),
        originalPrice: (json['originalPrice'] as num? ?? json['price'] as num? ?? 0).toDouble(),
        originalCurrency: ((json['originalCurrency'] as String? ?? 'USD').toUpperCase() == 'LBP') ? 'LBP' : 'USD',
        barcode: json['barcode'] as String? ?? '',
        isDefault: json['isDefault'] as bool? ?? false,
      );
}

class Product {
  Product({
    required this.id,
    required this.name,
    required this.code,
    this.nameEn = '',
    this.nameAr = '',
    required this.price,
    required this.cost,
    double? originalCost,
    this.costCurrency = 'USD',
    double? usdCost,
    double? costExchangeRateAtEntry,
    required this.stock,
    required this.category,
    double? originalPrice,
    this.originalCurrency = 'USD',
    double? usdPrice,
    double? exchangeRateAtEntry,
    this.barcode = '',
    this.brand = '',
    this.supplier = '',
    this.description = '',
    this.unit = 'pcs',
    this.quantityType = ProductQuantityType.countable,
    List<ProductSaleUnit>? saleUnits,
    List<ProductSaleUnit>? purchaseUnits,
    this.lowStockThreshold = 5,
    this.trackStock = true,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.deviceId = '',
    this.syncStatus = 'pending',
    this.storeId = '',
    this.branchId = '',
    this.version = 1,
    this.lastModifiedByDeviceId = '',
    this.imagePath = '',
  })  : originalCost = originalCost ?? cost,
        usdCost = usdCost ?? cost,
        costExchangeRateAtEntry = costExchangeRateAtEntry ?? 0,
        originalPrice = originalPrice ?? price,
        usdPrice = usdPrice ?? price,
        exchangeRateAtEntry = exchangeRateAtEntry ?? 0,
        saleUnits = saleUnits ?? const [],
        purchaseUnits = purchaseUnits ?? const [],
        createdAt = createdAt ?? updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id, name, code, nameEn, nameAr, category, barcode, brand, supplier, description, unit;
  /// USD reference price used internally by sales, reports, and inventory valuation.
  final double price;
  final double cost;
  final double originalCost;
  final String costCurrency;
  final double usdCost;
  final double costExchangeRateAtEntry;
  final double originalPrice;
  final String originalCurrency;
  final double usdPrice;
  final double exchangeRateAtEntry;
  final double stock;
  final int lowStockThreshold, version;
  final ProductQuantityType quantityType;
  final List<ProductSaleUnit> saleUnits;
  /// Purchase-specific units. Falls back to sale units for legacy products.
  final List<ProductSaleUnit> purchaseUnits;
  final bool trackStock, isActive;
  final DateTime createdAt, updatedAt;
  final DateTime? deletedAt;
  final String deviceId, syncStatus, storeId, branchId, lastModifiedByDeviceId, imagePath;

  bool get isDeleted => deletedAt != null;
  double get profit => price - cost;
  double get marginPercent => price <= 0 ? 0 : ((price - cost) / price) * 100;
  bool get isLowStock => trackStock && stock <= lowStockThreshold;
  double get stockCostValue => usdCost * stock;
  double get stockRetailValue => usdPrice * stock;
  bool get allowsDecimalQuantity => quantityType == ProductQuantityType.measurable;
  List<ProductSaleUnit> get effectiveSaleUnits {
    final base = ProductSaleUnit(id: 'base', name: unit, conversionToBase: 1, price: price, originalPrice: originalPrice, originalCurrency: originalCurrency, barcode: barcode, isDefault: true);
    final merged = <ProductSaleUnit>[base, ...saleUnits.where((item) => item.conversionToBase > 0)];
    final seen = <String>{};
    return merged.where((item) {
      final key = item.id.trim().isNotEmpty ? item.id : '${item.name}-${item.conversionToBase}-${item.barcode}';
      return seen.add(key);
    }).toList();
  }

  List<ProductSaleUnit> get effectivePurchaseUnits {
    final sourceUnits = purchaseUnits.isNotEmpty ? purchaseUnits : saleUnits;
    final base = ProductSaleUnit(id: 'base', name: unit, conversionToBase: 1, price: cost, originalPrice: originalCost, originalCurrency: costCurrency, barcode: barcode, isDefault: true);
    final merged = <ProductSaleUnit>[base, ...sourceUnits.where((item) => item.conversionToBase > 0)];
    final seen = <String>{};
    return merged.where((item) {
      final key = item.id.trim().isNotEmpty ? item.id : '${item.name}-${item.conversionToBase}-${item.barcode}';
      return seen.add(key);
    }).toList();
  }

  ProductSaleUnit? purchaseUnitForBarcode(String code) {
    final normalized = code.trim();
    if (normalized.isEmpty) return null;
    for (final unit in effectivePurchaseUnits) {
      if (unit.barcode.trim() == normalized) return unit;
    }
    return null;
  }

  ProductSaleUnit? unitForBarcode(String code) {
    final normalized = code.trim();
    if (normalized.isEmpty) return null;
    for (final unit in effectiveSaleUnits) {
      if (unit.barcode.trim() == normalized) return unit;
    }
    return null;
  }

  Product copyWith({String? id, String? name, String? code, String? nameEn, String? nameAr, double? price, double? cost, double? originalCost, String? costCurrency, double? usdCost, double? costExchangeRateAtEntry, double? stock, String? category, double? originalPrice, String? originalCurrency, double? usdPrice, double? exchangeRateAtEntry, String? barcode, String? brand, String? supplier, String? description, String? unit, ProductQuantityType? quantityType, List<ProductSaleUnit>? saleUnits, List<ProductSaleUnit>? purchaseUnits, int? lowStockThreshold, bool? trackStock, bool? isActive, DateTime? createdAt, DateTime? updatedAt, DateTime? deletedAt, bool clearDeletedAt = false, String? deviceId, String? syncStatus, String? storeId, String? branchId, int? version, String? lastModifiedByDeviceId, String? imagePath}) {
    final resolvedPrice = price ?? this.price;
    final resolvedCost = cost ?? this.cost;
    final resolvedOriginalCurrency = originalCurrency ?? this.originalCurrency;
    final resolvedCostCurrency = costCurrency ?? this.costCurrency;
    final resolvedUsdPrice = usdPrice ?? (price != null && resolvedOriginalCurrency == 'USD' ? resolvedPrice : this.usdPrice);
    final resolvedUsdCost = usdCost ?? (cost != null && resolvedCostCurrency == 'USD' ? resolvedCost : this.usdCost);

    return Product(
      id: id ?? this.id, name: name ?? this.name, code: code ?? this.code, nameEn: nameEn ?? this.nameEn, nameAr: nameAr ?? this.nameAr, price: resolvedPrice, cost: resolvedCost, originalCost: originalCost ?? this.originalCost, costCurrency: resolvedCostCurrency, usdCost: resolvedUsdCost, costExchangeRateAtEntry: costExchangeRateAtEntry ?? this.costExchangeRateAtEntry, stock: stock ?? this.stock, category: category ?? this.category, originalPrice: originalPrice ?? this.originalPrice, originalCurrency: resolvedOriginalCurrency, usdPrice: resolvedUsdPrice, exchangeRateAtEntry: exchangeRateAtEntry ?? this.exchangeRateAtEntry, barcode: barcode ?? this.barcode, brand: brand ?? this.brand, supplier: supplier ?? this.supplier, description: description ?? this.description, unit: unit ?? this.unit, quantityType: quantityType ?? this.quantityType, saleUnits: saleUnits ?? this.saleUnits, purchaseUnits: purchaseUnits ?? this.purchaseUnits, lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold, trackStock: trackStock ?? this.trackStock, isActive: isActive ?? this.isActive, createdAt: createdAt ?? this.createdAt, updatedAt: updatedAt ?? this.updatedAt, deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt), deviceId: deviceId ?? this.deviceId, syncStatus: syncStatus ?? this.syncStatus, storeId: storeId ?? this.storeId, branchId: branchId ?? this.branchId, version: version ?? this.version, lastModifiedByDeviceId: lastModifiedByDeviceId ?? this.lastModifiedByDeviceId, imagePath: imagePath ?? this.imagePath);
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'code': code, 'nameEn': nameEn, 'nameAr': nameAr, 'price': price, 'cost': cost, 'originalCost': originalCost, 'costCurrency': costCurrency, 'usdCost': usdCost, 'costExchangeRateAtEntry': costExchangeRateAtEntry, 'originalPrice': originalPrice, 'originalCurrency': originalCurrency, 'usdPrice': usdPrice, 'exchangeRateAtEntry': exchangeRateAtEntry, 'stock': stock, 'category': category, 'barcode': barcode, 'brand': brand, 'supplier': supplier, 'description': description, 'unit': unit, 'quantityType': quantityType.code, 'saleUnits': saleUnits.map((unit) => unit.toJson()).toList(), 'purchaseUnits': purchaseUnits.map((unit) => unit.toJson()).toList(), 'lowStockThreshold': lowStockThreshold, 'trackStock': trackStock, 'isActive': isActive, 'createdAt': createdAt.toIso8601String(), 'updatedAt': updatedAt.toIso8601String(), 'deletedAt': deletedAt?.toIso8601String(), 'deviceId': deviceId, 'syncStatus': syncStatus, 'storeId': storeId, 'branchId': branchId, 'version': version, 'lastModifiedByDeviceId': lastModifiedByDeviceId, 'imagePath': imagePath};

  factory Product.fromJson(Map<String, dynamic> json) {
    final updated = DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now();
    final rawPrice = json['price'] as num? ?? json['usdPrice'] as num? ?? 0;
    final price = rawPrice.toDouble();
    final originalCurrency = (json['originalCurrency'] as String? ?? 'USD').toUpperCase();
    final rawCost = (json['cost'] as num? ?? json['usdCost'] as num? ?? 0).toDouble();
    final costCurrencyRaw = (json['costCurrency'] as String? ?? 'USD').toUpperCase();
    final costCurrency = costCurrencyRaw == 'LBP' ? 'LBP' : 'USD';
    return Product(id: json['id'] as String, name: json['name'] as String? ?? json['nameEn'] as String? ?? json['nameAr'] as String? ?? '', code: json['code'] as String? ?? '', nameEn: json['nameEn'] as String? ?? json['name'] as String? ?? '', nameAr: json['nameAr'] as String? ?? '', price: price, cost: rawCost, originalCost: (json['originalCost'] as num? ?? rawCost).toDouble(), costCurrency: costCurrency, usdCost: (json['usdCost'] as num? ?? rawCost).toDouble(), costExchangeRateAtEntry: (json['costExchangeRateAtEntry'] as num? ?? 0).toDouble(), originalPrice: (json['originalPrice'] as num? ?? price).toDouble(), originalCurrency: originalCurrency == 'LBP' ? 'LBP' : 'USD', usdPrice: (json['usdPrice'] as num? ?? price).toDouble(), exchangeRateAtEntry: (json['exchangeRateAtEntry'] as num? ?? 0).toDouble(), stock: (json['stock'] as num? ?? 0).toDouble(), category: json['category'] as String? ?? 'General', barcode: json['barcode'] as String? ?? '', brand: json['brand'] as String? ?? '', supplier: json['supplier'] as String? ?? '', description: json['description'] as String? ?? '', unit: json['unit'] as String? ?? 'pcs', quantityType: ProductQuantityTypeJson.fromCode(json['quantityType'] as String?), saleUnits: (json['saleUnits'] as List<dynamic>? ?? const []).map((item) => ProductSaleUnit.fromJson(Map<String, dynamic>.from(item as Map))).toList(), purchaseUnits: (json['purchaseUnits'] as List<dynamic>? ?? const []).map((item) => ProductSaleUnit.fromJson(Map<String, dynamic>.from(item as Map))).toList(), lowStockThreshold: (json['lowStockThreshold'] as num? ?? 5).toInt(), trackStock: json['trackStock'] as bool? ?? true, isActive: json['isActive'] as bool? ?? true, createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? updated, updatedAt: updated, deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''), deviceId: json['deviceId'] as String? ?? '', syncStatus: json['syncStatus'] as String? ?? 'synced', storeId: json['storeId'] as String? ?? '', branchId: json['branchId'] as String? ?? '', version: (json['version'] as num? ?? 1).toInt(), lastModifiedByDeviceId: json['lastModifiedByDeviceId'] as String? ?? json['deviceId'] as String? ?? '', imagePath: json['imagePath'] as String? ?? '');
  }
}
