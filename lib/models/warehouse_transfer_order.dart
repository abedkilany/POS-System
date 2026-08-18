class WarehouseTransferOrderItem {
  const WarehouseTransferOrderItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    this.unitId = 'base',
    this.unitName = '',
    this.conversionToBase = 1,
    this.unitCost = 0,
  });

  final String productId;
  final String productName;
  final double quantity;
  final String unitId;
  final String unitName;
  final double conversionToBase;
  final double unitCost;

  double get baseQuantity => quantity * conversionToBase;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'unitId': unitId,
        'unitName': unitName,
        'conversionToBase': conversionToBase,
        'baseQuantity': baseQuantity,
        'unitCost': unitCost,
      };

  factory WarehouseTransferOrderItem.fromJson(Map<String, dynamic> json) =>
      WarehouseTransferOrderItem(
        productId: json['productId']?.toString() ?? '',
        productName: json['productName']?.toString() ?? '',
        quantity: (json['quantity'] as num? ?? 0).toDouble(),
        unitId: json['unitId']?.toString() ?? 'base',
        unitName: json['unitName']?.toString() ?? '',
        conversionToBase:
            (json['conversionToBase'] as num? ?? 1).toDouble(),
        unitCost: (json['unitCost'] as num? ?? 0).toDouble(),
      );
}

class WarehouseTransferOrder {
  WarehouseTransferOrder({
    required this.id,
    required this.orderNo,
    required this.fromWarehouseId,
    required this.fromWarehouseName,
    required this.toWarehouseId,
    required this.toWarehouseName,
    required this.date,
    required this.items,
    this.status = 'completed',
    this.notes = '',
    this.createdByUserId = '',
    this.createdByUserName = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deviceId = '',
    this.syncStatus = 'pending',
    this.storeId = '',
    this.branchId = '',
    this.version = 1,
    this.lastModifiedByDeviceId = '',
  })  : createdAt = createdAt ?? date,
        updatedAt = updatedAt ?? createdAt ?? date;

  final String id;
  final String orderNo;
  final String fromWarehouseId;
  final String fromWarehouseName;
  final String toWarehouseId;
  final String toWarehouseName;
  final DateTime date;
  final List<WarehouseTransferOrderItem> items;
  final String status;
  final String notes;
  final String createdByUserId;
  final String createdByUserName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String deviceId;
  final String syncStatus;
  final String storeId;
  final String branchId;
  final int version;
  final String lastModifiedByDeviceId;

  double get totalUnits => items.fold<double>(
        0,
        (sum, item) => sum + item.baseQuantity,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'orderNo': orderNo,
        'fromWarehouseId': fromWarehouseId,
        'fromWarehouseName': fromWarehouseName,
        'toWarehouseId': toWarehouseId,
        'toWarehouseName': toWarehouseName,
        'date': date.toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(growable: false),
        'status': status,
        'notes': notes,
        'createdByUserId': createdByUserId,
        'createdByUserName': createdByUserName,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deviceId': deviceId,
        'syncStatus': syncStatus,
        'storeId': storeId,
        'branchId': branchId,
        'version': version,
        'lastModifiedByDeviceId': lastModifiedByDeviceId,
      };

  factory WarehouseTransferOrder.fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse(json['date']?.toString() ?? '') ??
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now();
    return WarehouseTransferOrder(
      id: json['id']?.toString() ?? '',
      orderNo: json['orderNo']?.toString() ?? '',
      fromWarehouseId: json['fromWarehouseId']?.toString() ?? '',
      fromWarehouseName: json['fromWarehouseName']?.toString() ?? '',
      toWarehouseId: json['toWarehouseId']?.toString() ?? '',
      toWarehouseName: json['toWarehouseName']?.toString() ?? '',
      date: date,
      items: (json['items'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => WarehouseTransferOrderItem.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false),
      status: json['status']?.toString() ?? 'completed',
      notes: json['notes']?.toString() ?? '',
      createdByUserId: json['createdByUserId']?.toString() ?? '',
      createdByUserName: json['createdByUserName']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? date,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? date,
      deviceId: json['deviceId']?.toString() ?? '',
      syncStatus: json['syncStatus']?.toString() ?? 'pending',
      storeId: json['storeId']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? '',
      version: (json['version'] as num? ?? 1).toInt(),
      lastModifiedByDeviceId:
          json['lastModifiedByDeviceId']?.toString() ?? '',
    );
  }
}
