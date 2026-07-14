class WarehouseInventory {
  WarehouseInventory({
    required this.id,
    required this.storeId,
    required this.branchId,
    required this.warehouseId,
    required this.productId,
    required this.quantity,
    this.version = 1,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deviceId = '',
    this.syncStatus = 'pending',
    this.lastModifiedByDeviceId = '',
  })  : createdAt = createdAt ?? updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String storeId;
  final String branchId;
  final String warehouseId;
  final String productId;
  final double quantity;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String deviceId;
  final String syncStatus;
  final String lastModifiedByDeviceId;

  String get uniqueKey => '$storeId::$warehouseId::$productId';

  WarehouseInventory copyWith({
    String? storeId,
    String? branchId,
    String? warehouseId,
    String? productId,
    double? quantity,
    int? version,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? deviceId,
    String? syncStatus,
    String? lastModifiedByDeviceId,
  }) {
    return WarehouseInventory(
      id: id,
      storeId: storeId ?? this.storeId,
      branchId: branchId ?? this.branchId,
      warehouseId: warehouseId ?? this.warehouseId,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deviceId: deviceId ?? this.deviceId,
      syncStatus: syncStatus ?? this.syncStatus,
      lastModifiedByDeviceId:
          lastModifiedByDeviceId ?? this.lastModifiedByDeviceId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'storeId': storeId,
        'branchId': branchId,
        'warehouseId': warehouseId,
        'productId': productId,
        'quantity': quantity,
        'version': version,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deviceId': deviceId,
        'syncStatus': syncStatus,
        'lastModifiedByDeviceId': lastModifiedByDeviceId,
      };

  factory WarehouseInventory.fromJson(Map<String, dynamic> json) {
    final updated = DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
        DateTime.now();
    return WarehouseInventory(
      id: json['id']?.toString() ?? '',
      storeId: json['storeId']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? 'main',
      warehouseId: json['warehouseId']?.toString() ?? '',
      productId: json['productId']?.toString() ?? '',
      quantity: (json['quantity'] as num? ?? 0).toDouble(),
      version: (json['version'] as num? ?? 1).toInt(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          updated,
      updatedAt: updated,
      deviceId: json['deviceId']?.toString() ?? '',
      syncStatus: json['syncStatus']?.toString() ?? 'pending',
      lastModifiedByDeviceId:
          json['lastModifiedByDeviceId']?.toString() ?? '',
    );
  }
}
