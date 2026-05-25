class Product {
  Product({
    required this.id,
    required this.name,
    required this.code,
    this.nameEn = '',
    this.nameAr = '',
    required this.price,
    required this.cost,
    required this.stock,
    required this.category,
    this.barcode = '',
    this.brand = '',
    this.supplier = '',
    this.description = '',
    this.unit = 'pcs',
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
  })  : createdAt = createdAt ?? updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id, name, code, nameEn, nameAr, category, barcode, brand, supplier, description, unit;
  final double price, cost;
  final int stock, lowStockThreshold, version;
  final bool trackStock, isActive;
  final DateTime createdAt, updatedAt;
  final DateTime? deletedAt;
  final String deviceId, syncStatus, storeId, branchId, lastModifiedByDeviceId;

  bool get isDeleted => deletedAt != null;
  double get profit => price - cost;
  double get marginPercent => price <= 0 ? 0 : ((price - cost) / price) * 100;
  bool get isLowStock => trackStock && stock <= lowStockThreshold;
  double get stockCostValue => cost * stock;
  double get stockRetailValue => price * stock;

  Product copyWith({String? id, String? name, String? code, String? nameEn, String? nameAr, double? price, double? cost, int? stock, String? category, String? barcode, String? brand, String? supplier, String? description, String? unit, int? lowStockThreshold, bool? trackStock, bool? isActive, DateTime? createdAt, DateTime? updatedAt, DateTime? deletedAt, bool clearDeletedAt = false, String? deviceId, String? syncStatus, String? storeId, String? branchId, int? version, String? lastModifiedByDeviceId}) => Product(
    id: id ?? this.id, name: name ?? this.name, code: code ?? this.code, nameEn: nameEn ?? this.nameEn, nameAr: nameAr ?? this.nameAr, price: price ?? this.price, cost: cost ?? this.cost, stock: stock ?? this.stock, category: category ?? this.category, barcode: barcode ?? this.barcode, brand: brand ?? this.brand, supplier: supplier ?? this.supplier, description: description ?? this.description, unit: unit ?? this.unit, lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold, trackStock: trackStock ?? this.trackStock, isActive: isActive ?? this.isActive, createdAt: createdAt ?? this.createdAt, updatedAt: updatedAt ?? this.updatedAt, deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt), deviceId: deviceId ?? this.deviceId, syncStatus: syncStatus ?? this.syncStatus, storeId: storeId ?? this.storeId, branchId: branchId ?? this.branchId, version: version ?? this.version, lastModifiedByDeviceId: lastModifiedByDeviceId ?? this.lastModifiedByDeviceId);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'code': code, 'nameEn': nameEn, 'nameAr': nameAr, 'price': price, 'cost': cost, 'stock': stock, 'category': category, 'barcode': barcode, 'brand': brand, 'supplier': supplier, 'description': description, 'unit': unit, 'lowStockThreshold': lowStockThreshold, 'trackStock': trackStock, 'isActive': isActive, 'createdAt': createdAt.toIso8601String(), 'updatedAt': updatedAt.toIso8601String(), 'deletedAt': deletedAt?.toIso8601String(), 'deviceId': deviceId, 'syncStatus': syncStatus, 'storeId': storeId, 'branchId': branchId, 'version': version, 'lastModifiedByDeviceId': lastModifiedByDeviceId};

  factory Product.fromJson(Map<String, dynamic> json) {
    final updated = DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now();
    return Product(id: json['id'] as String, name: json['name'] as String? ?? json['nameEn'] as String? ?? json['nameAr'] as String? ?? '', code: json['code'] as String? ?? '', nameEn: json['nameEn'] as String? ?? json['name'] as String? ?? '', nameAr: json['nameAr'] as String? ?? '', price: (json['price'] as num? ?? 0).toDouble(), cost: (json['cost'] as num? ?? 0).toDouble(), stock: (json['stock'] as num? ?? 0).toInt(), category: json['category'] as String? ?? 'General', barcode: json['barcode'] as String? ?? '', brand: json['brand'] as String? ?? '', supplier: json['supplier'] as String? ?? '', description: json['description'] as String? ?? '', unit: json['unit'] as String? ?? 'pcs', lowStockThreshold: (json['lowStockThreshold'] as num? ?? 5).toInt(), trackStock: json['trackStock'] as bool? ?? true, isActive: json['isActive'] as bool? ?? true, createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? updated, updatedAt: updated, deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''), deviceId: json['deviceId'] as String? ?? '', syncStatus: json['syncStatus'] as String? ?? 'synced', storeId: json['storeId'] as String? ?? '', branchId: json['branchId'] as String? ?? '', version: (json['version'] as num? ?? 1).toInt(), lastModifiedByDeviceId: json['lastModifiedByDeviceId'] as String? ?? json['deviceId'] as String? ?? '');
  }
}
