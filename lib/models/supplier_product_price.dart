class SupplierProductPriceHistoryEntry {
  SupplierProductPriceHistoryEntry({
    required this.oldCost,
    required this.newCost,
    required this.currency,
    DateTime? changedAt,
    this.source = 'manual',
  }) : changedAt = changedAt ?? DateTime.now();

  final double oldCost;
  final double newCost;
  final String currency;
  final DateTime changedAt;
  final String source;

  Map<String, dynamic> toJson() => {
        'oldCost': oldCost,
        'newCost': newCost,
        'currency': currency.toUpperCase() == 'LBP' ? 'LBP' : 'USD',
        'changedAt': changedAt.toIso8601String(),
        'source': source,
      };

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  factory SupplierProductPriceHistoryEntry.fromJson(Map<String, dynamic> json) =>
      SupplierProductPriceHistoryEntry(
        oldCost: _toDouble(json['oldCost']),
        newCost: _toDouble(json['newCost']),
        currency: json['currency']?.toString().toUpperCase() == 'LBP' ? 'LBP' : 'USD',
        changedAt: DateTime.tryParse(json['changedAt']?.toString() ?? '') ?? DateTime.now(),
        source: json['source']?.toString() ?? 'manual',
      );
}

class SupplierProductPrice {
  SupplierProductPrice({
    required this.id,
    required this.productId,
    required this.supplierId,
    required this.cost,
    this.currency = 'USD',
    this.isPreferred = false,
    this.supplierSku = '',
    this.minOrderQty,
    this.leadTimeDays,
    this.notes = '',
    List<SupplierProductPriceHistoryEntry>? priceHistory,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.deviceId = '',
    this.syncStatus = 'pending',
    this.storeId = '',
    this.branchId = '',
    this.version = 1,
    this.lastModifiedByDeviceId = '',
  })  : priceHistory = List.unmodifiable(priceHistory ?? const []),
        createdAt = createdAt ?? updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String productId;
  final String supplierId;
  final double cost;
  final String currency;
  final bool isPreferred;
  final String supplierSku;
  final double? minOrderQty;
  final int? leadTimeDays;
  final String notes;
  final List<SupplierProductPriceHistoryEntry> priceHistory;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String deviceId;
  final String syncStatus;
  final String storeId;
  final String branchId;
  final int version;
  final String lastModifiedByDeviceId;

  bool get isDeleted => deletedAt != null;

  SupplierProductPrice copyWith({
    String? id,
    String? productId,
    String? supplierId,
    double? cost,
    String? currency,
    bool? isPreferred,
    String? supplierSku,
    double? minOrderQty,
    bool clearMinOrderQty = false,
    int? leadTimeDays,
    bool clearLeadTimeDays = false,
    String? notes,
    List<SupplierProductPriceHistoryEntry>? priceHistory,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    String? deviceId,
    String? syncStatus,
    String? storeId,
    String? branchId,
    int? version,
    String? lastModifiedByDeviceId,
  }) =>
      SupplierProductPrice(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        supplierId: supplierId ?? this.supplierId,
        cost: cost ?? this.cost,
        currency: currency ?? this.currency,
        isPreferred: isPreferred ?? this.isPreferred,
        supplierSku: supplierSku ?? this.supplierSku,
        minOrderQty: clearMinOrderQty ? null : (minOrderQty ?? this.minOrderQty),
        leadTimeDays: clearLeadTimeDays ? null : (leadTimeDays ?? this.leadTimeDays),
        notes: notes ?? this.notes,
        priceHistory: priceHistory ?? this.priceHistory,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
        deviceId: deviceId ?? this.deviceId,
        syncStatus: syncStatus ?? this.syncStatus,
        storeId: storeId ?? this.storeId,
        branchId: branchId ?? this.branchId,
        version: version ?? this.version,
        lastModifiedByDeviceId: lastModifiedByDeviceId ?? this.lastModifiedByDeviceId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'supplierId': supplierId,
        'cost': cost,
        'currency': currency.toUpperCase() == 'LBP' ? 'LBP' : 'USD',
        'isPreferred': isPreferred,
        'supplierSku': supplierSku,
        'minOrderQty': minOrderQty,
        'leadTimeDays': leadTimeDays,
        'notes': notes,
        'priceHistory': priceHistory.map((item) => item.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'deviceId': deviceId,
        'syncStatus': syncStatus,
        'storeId': storeId,
        'branchId': branchId,
        'version': version,
        'lastModifiedByDeviceId': lastModifiedByDeviceId,
      };

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _toOptionalDouble(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _toOptionalInt(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  factory SupplierProductPrice.fromJson(Map<String, dynamic> json) {
    final updated = DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now();
    final rawHistory = json['priceHistory'];
    final history = rawHistory is List
        ? rawHistory
            .whereType<Map>()
            .map((item) => SupplierProductPriceHistoryEntry.fromJson(Map<String, dynamic>.from(item)))
            .toList()
        : <SupplierProductPriceHistoryEntry>[];
    return SupplierProductPrice(
      id: json['id']?.toString() ?? '',
      productId: json['productId']?.toString() ?? '',
      supplierId: json['supplierId']?.toString() ?? '',
      cost: _toDouble(json['cost'] ?? json['unitCost']),
      currency: (json['currency']?.toString().toUpperCase() == 'LBP') ? 'LBP' : 'USD',
      isPreferred: json['isPreferred'] == true || json['preferredSupplier'] == true,
      supplierSku: json['supplierSku']?.toString() ?? json['supplierSKU']?.toString() ?? json['supplierCode']?.toString() ?? '',
      minOrderQty: _toOptionalDouble(json['minOrderQty'] ?? json['minimumOrderQty']),
      leadTimeDays: _toOptionalInt(json['leadTimeDays'] ?? json['lead_time_days']),
      notes: json['notes']?.toString() ?? '',
      priceHistory: history,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? updated,
      updatedAt: updated,
      deletedAt: DateTime.tryParse(json['deletedAt']?.toString() ?? ''),
      deviceId: json['deviceId']?.toString() ?? '',
      syncStatus: json['syncStatus']?.toString() ?? 'synced',
      storeId: json['storeId']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? '',
      version: (json['version'] as num? ?? 1).toInt(),
      lastModifiedByDeviceId: json['lastModifiedByDeviceId']?.toString() ?? json['deviceId']?.toString() ?? '',
    );
  }
}
