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
    this.sourceLineId = '',
    this.unitCost = 0,
    this.initialQuantity = 0,
    this.costCurrency = 'USD',
    this.exchangeRate = 1,
    this.receivedAt,
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
  final String sourceLineId;
  final double unitCost;
  final double initialQuantity;
  final String costCurrency;
  final double exchangeRate;
  final DateTime? receivedAt;
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
        'sourceLineId': sourceLineId,
        'unitCost': unitCost,
        'initialQuantity': initialQuantity,
        'costCurrency': costCurrency,
        'exchangeRate': exchangeRate,
        'receivedAt': receivedAt?.toIso8601String(),
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
        sourceLineId: json['sourceLineId']?.toString() ?? '',
        unitCost: (json['unitCost'] as num? ?? 0).toDouble(),
        initialQuantity: (json['initialQuantity'] as num? ?? 0).toDouble(),
        costCurrency: (json['costCurrency']?.toString().trim().isEmpty ?? true)
            ? 'USD'
            : json['costCurrency'].toString().toUpperCase(),
        exchangeRate: (json['exchangeRate'] as num? ?? 1).toDouble(),
        receivedAt: DateTime.tryParse(json['receivedAt']?.toString() ?? ''),
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
    this.unitCost = 0,
  });

  final String batchId;
  final double quantity;
  final double unitCost;
  final String supplierBatchNumber;
  final DateTime? manufacturingDate;
  final DateTime? expirationDate;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'batchId': batchId,
        'quantity': quantity,
        'supplierBatchNumber': supplierBatchNumber,
        'manufacturingDate': manufacturingDate?.toIso8601String(),
        'expirationDate': expirationDate?.toIso8601String(),
        'unitCost': unitCost,
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
        unitCost: (json['unitCost'] as num? ?? 0).toDouble(),
      );
}


class BatchInventoryBalanceCheck {
  const BatchInventoryBalanceCheck({
    required this.productId,
    required this.warehouseId,
    required this.warehouseQuantity,
    required this.batchQuantity,
    required this.batchCarryingValue,
    this.tolerance = 0.000001,
  });

  final String productId;
  final String warehouseId;
  final double warehouseQuantity;
  final double batchQuantity;
  final double batchCarryingValue;
  final double tolerance;

  double get difference => warehouseQuantity - batchQuantity;
  bool get isConsistent => difference.abs() <= tolerance;
}
