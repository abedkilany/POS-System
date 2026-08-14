enum InventoryBatchStatus { active, blocked, depleted, disposed }

extension InventoryBatchStatusJson on InventoryBatchStatus {
  String get code => name;

  static InventoryBatchStatus fromCode(String? value) {
    return InventoryBatchStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => InventoryBatchStatus.active,
    );
  }
}

class InventoryBatch {
  const InventoryBatch({
    required this.id,
    required this.productId,
    required this.productName,
    this.supplierBatchNumber = '',
    this.manufacturingDate,
    this.expirationDate,
    this.status = InventoryBatchStatus.active,
    this.sourceType = '',
    this.sourceId = '',
    this.createdAt,
    this.updatedAt,
    this.storeId = '',
    this.branchId = '',
    this.deviceId = '',
    this.lastModifiedByDeviceId = '',
    this.version = 1,
  });

  final String id;
  final String productId;
  final String productName;
  final String supplierBatchNumber;
  final DateTime? manufacturingDate;
  final DateTime? expirationDate;
  final InventoryBatchStatus status;
  final String sourceType;
  final String sourceId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String storeId;
  final String branchId;
  final String deviceId;
  final String lastModifiedByDeviceId;
  final int version;

  bool get isBlocked => status == InventoryBatchStatus.blocked;
  bool get isExpired {
    final expiry = expirationDate;
    if (expiry == null) return false;
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    return expiry.isBefore(startOfToday);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'productId': productId,
        'productName': productName,
        'supplierBatchNumber': supplierBatchNumber,
        'manufacturingDate': manufacturingDate?.toIso8601String(),
        'expirationDate': expirationDate?.toIso8601String(),
        'status': status.code,
        'sourceType': sourceType,
        'sourceId': sourceId,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'storeId': storeId,
        'branchId': branchId,
        'deviceId': deviceId,
        'lastModifiedByDeviceId': lastModifiedByDeviceId,
        'version': version,
      };

  factory InventoryBatch.fromJson(Map<String, dynamic> json) => InventoryBatch(
        id: json['id']?.toString() ?? '',
        productId: json['productId']?.toString() ?? '',
        productName: json['productName']?.toString() ?? '',
        supplierBatchNumber: json['supplierBatchNumber']?.toString() ?? '',
        manufacturingDate:
            DateTime.tryParse(json['manufacturingDate']?.toString() ?? ''),
        expirationDate:
            DateTime.tryParse(json['expirationDate']?.toString() ?? ''),
        status: InventoryBatchStatusJson.fromCode(json['status']?.toString()),
        sourceType: json['sourceType']?.toString() ?? '',
        sourceId: json['sourceId']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
        storeId: json['storeId']?.toString() ?? '',
        branchId: json['branchId']?.toString() ?? '',
        deviceId: json['deviceId']?.toString() ?? '',
        lastModifiedByDeviceId:
            json['lastModifiedByDeviceId']?.toString() ?? '',
        version: (json['version'] as num? ?? 1).toInt(),
      );
}

class InventoryBatchBalance {
  const InventoryBatchBalance({
    required this.batchId,
    required this.productId,
    required this.warehouseId,
    required this.quantity,
    this.reservedQuantity = 0,
  });

  final String batchId;
  final String productId;
  final String warehouseId;
  final double quantity;
  final double reservedQuantity;

  double get availableQuantity => quantity - reservedQuantity;
}

class BatchAllocation {
  const BatchAllocation({
    required this.batchId,
    required this.quantity,
    this.supplierBatchNumber = '',
    this.manufacturingDate,
    this.expirationDate,
  });

  final String batchId;
  final double quantity;
  final String supplierBatchNumber;
  final DateTime? manufacturingDate;
  final DateTime? expirationDate;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'batchId': batchId,
        'quantity': quantity,
        'supplierBatchNumber': supplierBatchNumber,
        'manufacturingDate': manufacturingDate?.toIso8601String(),
        'expirationDate': expirationDate?.toIso8601String(),
      };

  factory BatchAllocation.fromJson(Map<String, dynamic> json) =>
      BatchAllocation(
        batchId: json['batchId']?.toString() ?? '',
        quantity: (json['quantity'] as num? ?? 0).toDouble(),
        supplierBatchNumber: json['supplierBatchNumber']?.toString() ?? '',
        manufacturingDate:
            DateTime.tryParse(json['manufacturingDate']?.toString() ?? ''),
        expirationDate:
            DateTime.tryParse(json['expirationDate']?.toString() ?? ''),
      );
}
