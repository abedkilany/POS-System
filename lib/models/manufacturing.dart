
class BillOfMaterialsLine {
  const BillOfMaterialsLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    this.unitCost = 0,
  });

  final String productId;
  final String productName;
  final double quantity;
  final double unitCost;

  double get lineCost => quantity * unitCost;

  BillOfMaterialsLine copyWith({String? productId, String? productName, double? quantity, double? unitCost}) => BillOfMaterialsLine(
        productId: productId ?? this.productId,
        productName: productName ?? this.productName,
        quantity: quantity ?? this.quantity,
        unitCost: unitCost ?? this.unitCost,
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'unitCost': unitCost,
      };

  factory BillOfMaterialsLine.fromJson(Map<String, dynamic> json) => BillOfMaterialsLine(
        productId: json['productId']?.toString() ?? '',
        productName: json['productName']?.toString() ?? '',
        quantity: (json['quantity'] as num? ?? 0).toDouble(),
        unitCost: (json['unitCost'] as num? ?? 0).toDouble(),
      );
}

class BillOfMaterials {
  BillOfMaterials({
    required this.id,
    required this.name,
    required this.outputProductId,
    required this.outputProductName,
    this.outputQuantity = 1,
    List<BillOfMaterialsLine>? components,
    this.notes = '',
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
  })  : components = components ?? const [],
        createdAt = createdAt ?? updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id, name, outputProductId, outputProductName, notes;
  final double outputQuantity;
  final List<BillOfMaterialsLine> components;
  final bool isActive;
  final DateTime createdAt, updatedAt;
  final DateTime? deletedAt;
  final String deviceId, syncStatus, storeId, branchId, lastModifiedByDeviceId;
  final int version;

  bool get isDeleted => deletedAt != null;
  double get unitCost => outputQuantity <= 0 ? 0 : components.fold<double>(0, (sum, item) => sum + item.lineCost) / outputQuantity;

  BillOfMaterials copyWith({String? id, String? name, String? outputProductId, String? outputProductName, double? outputQuantity, List<BillOfMaterialsLine>? components, String? notes, bool? isActive, DateTime? createdAt, DateTime? updatedAt, DateTime? deletedAt, bool clearDeletedAt = false, String? deviceId, String? syncStatus, String? storeId, String? branchId, int? version, String? lastModifiedByDeviceId}) => BillOfMaterials(
        id: id ?? this.id,
        name: name ?? this.name,
        outputProductId: outputProductId ?? this.outputProductId,
        outputProductName: outputProductName ?? this.outputProductName,
        outputQuantity: outputQuantity ?? this.outputQuantity,
        components: components ?? this.components,
        notes: notes ?? this.notes,
        isActive: isActive ?? this.isActive,
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
        'name': name,
        'outputProductId': outputProductId,
        'outputProductName': outputProductName,
        'outputQuantity': outputQuantity,
        'components': components.map((item) => item.toJson()).toList(),
        'notes': notes,
        'isActive': isActive,
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

  factory BillOfMaterials.fromJson(Map<String, dynamic> json) {
    final updated = DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now();
    return BillOfMaterials(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      outputProductId: json['outputProductId']?.toString() ?? '',
      outputProductName: json['outputProductName']?.toString() ?? '',
      outputQuantity: (json['outputQuantity'] as num? ?? 1).toDouble(),
      components: (json['components'] as List<dynamic>? ?? const []).map((item) => BillOfMaterialsLine.fromJson(Map<String, dynamic>.from(item as Map))).toList(),
      notes: json['notes']?.toString() ?? '',
      isActive: json['isActive'] as bool? ?? true,
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

class ManufacturingOrder {
  ManufacturingOrder({
    required this.id,
    required this.orderNo,
    required this.bomId,
    required this.bomName,
    required this.outputProductId,
    required this.outputProductName,
    required this.quantity,
    this.rawMaterialsWarehouseId = 'main',
    this.rawMaterialsWarehouseName = 'Main warehouse',
    this.finishedGoodsWarehouseId = 'main',
    this.finishedGoodsWarehouseName = 'Main warehouse',
    this.status = 'completed',
    this.notes = '',
    DateTime? date,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.deviceId = '',
    this.syncStatus = 'pending',
    this.storeId = '',
    this.branchId = '',
    this.version = 1,
    this.lastModifiedByDeviceId = '',
  })  : date = date ?? DateTime.now(),
        createdAt = createdAt ?? updatedAt ?? date ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? date ?? DateTime.now();

  final String id, orderNo, bomId, bomName, outputProductId, outputProductName, status, notes;
  final String rawMaterialsWarehouseId,
      rawMaterialsWarehouseName,
      finishedGoodsWarehouseId,
      finishedGoodsWarehouseName;
  final double quantity;
  final DateTime date, createdAt, updatedAt;
  final DateTime? deletedAt;
  final String deviceId, syncStatus, storeId, branchId, lastModifiedByDeviceId;
  final int version;

  bool get isDeleted => deletedAt != null;

  ManufacturingOrder copyWith({String? id, String? orderNo, String? bomId, String? bomName, String? outputProductId, String? outputProductName, double? quantity, String? rawMaterialsWarehouseId, String? rawMaterialsWarehouseName, String? finishedGoodsWarehouseId, String? finishedGoodsWarehouseName, String? status, String? notes, DateTime? date, DateTime? createdAt, DateTime? updatedAt, DateTime? deletedAt, bool clearDeletedAt = false, String? deviceId, String? syncStatus, String? storeId, String? branchId, int? version, String? lastModifiedByDeviceId}) => ManufacturingOrder(
        id: id ?? this.id,
        orderNo: orderNo ?? this.orderNo,
        bomId: bomId ?? this.bomId,
        bomName: bomName ?? this.bomName,
        outputProductId: outputProductId ?? this.outputProductId,
        outputProductName: outputProductName ?? this.outputProductName,
        quantity: quantity ?? this.quantity,
        rawMaterialsWarehouseId: rawMaterialsWarehouseId ?? this.rawMaterialsWarehouseId,
        rawMaterialsWarehouseName: rawMaterialsWarehouseName ?? this.rawMaterialsWarehouseName,
        finishedGoodsWarehouseId: finishedGoodsWarehouseId ?? this.finishedGoodsWarehouseId,
        finishedGoodsWarehouseName: finishedGoodsWarehouseName ?? this.finishedGoodsWarehouseName,
        status: status ?? this.status,
        notes: notes ?? this.notes,
        date: date ?? this.date,
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
        'orderNo': orderNo,
        'bomId': bomId,
        'bomName': bomName,
        'outputProductId': outputProductId,
        'outputProductName': outputProductName,
        'quantity': quantity,
        'rawMaterialsWarehouseId': rawMaterialsWarehouseId,
        'rawMaterialsWarehouseName': rawMaterialsWarehouseName,
        'finishedGoodsWarehouseId': finishedGoodsWarehouseId,
        'finishedGoodsWarehouseName': finishedGoodsWarehouseName,
        'status': status,
        'notes': notes,
        'date': date.toIso8601String(),
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

  factory ManufacturingOrder.fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now();
    return ManufacturingOrder(
      id: json['id']?.toString() ?? '',
      orderNo: json['orderNo']?.toString() ?? '',
      bomId: json['bomId']?.toString() ?? '',
      bomName: json['bomName']?.toString() ?? '',
      outputProductId: json['outputProductId']?.toString() ?? '',
      outputProductName: json['outputProductName']?.toString() ?? '',
      quantity: (json['quantity'] as num? ?? 0).toDouble(),
      rawMaterialsWarehouseId: json['rawMaterialsWarehouseId']?.toString().isNotEmpty == true
          ? json['rawMaterialsWarehouseId'].toString()
          : 'main',
      rawMaterialsWarehouseName: json['rawMaterialsWarehouseName']?.toString().isNotEmpty == true
          ? json['rawMaterialsWarehouseName'].toString()
          : 'Main warehouse',
      finishedGoodsWarehouseId: json['finishedGoodsWarehouseId']?.toString().isNotEmpty == true
          ? json['finishedGoodsWarehouseId'].toString()
          : 'main',
      finishedGoodsWarehouseName: json['finishedGoodsWarehouseName']?.toString().isNotEmpty == true
          ? json['finishedGoodsWarehouseName'].toString()
          : 'Main warehouse',
      status: json['status']?.toString() ?? 'completed',
      notes: json['notes']?.toString() ?? '',
      date: date,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? date,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? date,
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
