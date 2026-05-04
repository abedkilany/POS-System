class StockMovement {
  StockMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.type,
    required this.quantity,
    required this.date,
    this.referenceId = '',
    this.referenceNo = '',
    this.reason = '',
    this.unitCost = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deviceId = '',
    this.syncStatus = 'pending',
    this.storeId = '',
    this.branchId = '',
    this.version = 1,
    this.lastModifiedByDeviceId = '',
  })  : createdAt = createdAt ?? updatedAt ?? date,
        updatedAt = updatedAt ?? createdAt ?? date;

  final String id, productId, productName, type, referenceId, referenceNo, reason;
  final int quantity;
  final double unitCost;
  final DateTime date, createdAt, updatedAt;
  final String deviceId, syncStatus, storeId, branchId, lastModifiedByDeviceId;
  final int version;

  double get value => quantity.abs() * unitCost;

  StockMovement copyWith({String? productName, String? type, int? quantity, DateTime? date, String? referenceId, String? referenceNo, String? reason, double? unitCost, DateTime? createdAt, DateTime? updatedAt, String? deviceId, String? syncStatus, String? storeId, String? branchId, int? version, String? lastModifiedByDeviceId}) => StockMovement(
        id: id,
        productId: productId,
        productName: productName ?? this.productName,
        type: type ?? this.type,
        quantity: quantity ?? this.quantity,
        date: date ?? this.date,
        referenceId: referenceId ?? this.referenceId,
        referenceNo: referenceNo ?? this.referenceNo,
        reason: reason ?? this.reason,
        unitCost: unitCost ?? this.unitCost,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
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
        'productName': productName,
        'type': type,
        'quantity': quantity,
        'date': date.toIso8601String(),
        'referenceId': referenceId,
        'referenceNo': referenceNo,
        'reason': reason,
        'unitCost': unitCost,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deviceId': deviceId,
        'syncStatus': syncStatus,
        'storeId': storeId,
        'branchId': branchId,
        'version': version,
        'lastModifiedByDeviceId': lastModifiedByDeviceId,
      };

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse(json['date']?.toString() ?? json['createdAt']?.toString() ?? '') ?? DateTime.now();
    return StockMovement(
      id: json['id']?.toString() ?? '${json['referenceId'] ?? ''}-${json['productId'] ?? ''}-${json['type'] ?? ''}',
      productId: json['productId']?.toString() ?? '',
      productName: json['productName']?.toString() ?? '',
      type: json['type']?.toString() ?? 'adjustment',
      quantity: (json['quantity'] as num? ?? 0).toInt(),
      date: date,
      referenceId: json['referenceId']?.toString() ?? json['saleId']?.toString() ?? json['purchaseId']?.toString() ?? '',
      referenceNo: json['referenceNo']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      unitCost: (json['unitCost'] as num? ?? 0).toDouble(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? date,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? date,
      deviceId: json['deviceId']?.toString() ?? '',
      syncStatus: json['syncStatus']?.toString() ?? 'synced',
      storeId: json['storeId']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? '',
      version: (json['version'] as num? ?? 1).toInt(),
      lastModifiedByDeviceId: json['lastModifiedByDeviceId']?.toString() ?? json['deviceId']?.toString() ?? '',
    );
  }
}
