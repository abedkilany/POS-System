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

  BillOfMaterialsLine copyWith(
          {String? productId,
          String? productName,
          double? quantity,
          double? unitCost}) =>
      BillOfMaterialsLine(
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

  factory BillOfMaterialsLine.fromJson(Map<String, dynamic> json) =>
      BillOfMaterialsLine(
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
        createdAt =
            createdAt ?? updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt =
            updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id, name, outputProductId, outputProductName, notes;
  final double outputQuantity;
  final List<BillOfMaterialsLine> components;
  final bool isActive;
  final DateTime createdAt, updatedAt;
  final DateTime? deletedAt;
  final String deviceId, syncStatus, storeId, branchId, lastModifiedByDeviceId;
  final int version;

  bool get isDeleted => deletedAt != null;
  double get unitCost => outputQuantity <= 0
      ? 0
      : components.fold<double>(0, (sum, item) => sum + item.lineCost) /
          outputQuantity;

  BillOfMaterials copyWith(
          {String? id,
          String? name,
          String? outputProductId,
          String? outputProductName,
          double? outputQuantity,
          List<BillOfMaterialsLine>? components,
          String? notes,
          bool? isActive,
          DateTime? createdAt,
          DateTime? updatedAt,
          DateTime? deletedAt,
          bool clearDeletedAt = false,
          String? deviceId,
          String? syncStatus,
          String? storeId,
          String? branchId,
          int? version,
          String? lastModifiedByDeviceId}) =>
      BillOfMaterials(
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
        lastModifiedByDeviceId:
            lastModifiedByDeviceId ?? this.lastModifiedByDeviceId,
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
    final updated = DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
        DateTime.now();
    return BillOfMaterials(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      outputProductId: json['outputProductId']?.toString() ?? '',
      outputProductName: json['outputProductName']?.toString() ?? '',
      outputQuantity: (json['outputQuantity'] as num? ?? 1).toDouble(),
      components: (json['components'] as List<dynamic>? ?? const [])
          .map((item) => BillOfMaterialsLine.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList(),
      notes: json['notes']?.toString() ?? '',
      isActive: json['isActive'] as bool? ?? true,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? updated,
      updatedAt: updated,
      deletedAt: DateTime.tryParse(json['deletedAt']?.toString() ?? ''),
      deviceId: json['deviceId']?.toString() ?? '',
      syncStatus: json['syncStatus']?.toString() ?? 'synced',
      storeId: json['storeId']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? '',
      version: (json['version'] as num? ?? 1).toInt(),
      lastModifiedByDeviceId: json['lastModifiedByDeviceId']?.toString() ??
          json['deviceId']?.toString() ??
          '',
    );
  }
}

/// Immutable historical cost assigned to a material consumed by an order.
/// [layerConsumptions] contains the exact FIFO layer slices when FIFO is the
/// configured costing policy, allowing a safe reversal without repricing.
class ManufacturingMaterialCost {
  const ManufacturingMaterialCost({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCost,
    required this.totalCost,
    this.costingMethod = 'weighted_average',
    this.movementIds = const <String>[],
    this.layerConsumptions = const <Map<String, dynamic>>[],
  });

  final String productId, productName, costingMethod;
  final double quantity, unitCost, totalCost;
  final List<String> movementIds;
  final List<Map<String, dynamic>> layerConsumptions;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'unitCost': unitCost,
        'totalCost': totalCost,
        'costingMethod': costingMethod,
        'movementIds': movementIds,
        'layerConsumptions': layerConsumptions,
      };

  factory ManufacturingMaterialCost.fromJson(Map<String, dynamic> json) =>
      ManufacturingMaterialCost(
        productId: json['productId']?.toString() ?? '',
        productName: json['productName']?.toString() ?? '',
        quantity: (json['quantity'] as num? ?? 0).toDouble(),
        unitCost: (json['unitCost'] as num? ?? 0).toDouble(),
        totalCost: (json['totalCost'] as num? ?? 0).toDouble(),
        costingMethod: json['costingMethod']?.toString() ?? 'weighted_average',
        movementIds: (json['movementIds'] as List<dynamic>? ?? const [])
            .map((value) => value.toString())
            .toList(growable: false),
        layerConsumptions:
            (json['layerConsumptions'] as List<dynamic>? ?? const [])
                .whereType<Map>()
                .map((value) => Map<String, dynamic>.from(value))
                .toList(growable: false),
      );
}

class ManufacturingWasteLine {
  const ManufacturingWasteLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCost,
    required this.value,
    required this.reason,
  });

  final String productId, productName, reason;
  final double quantity, unitCost, value;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'unitCost': unitCost,
        'value': value,
        'reason': reason,
      };

  factory ManufacturingWasteLine.fromJson(Map<String, dynamic> json) =>
      ManufacturingWasteLine(
        productId: json['productId']?.toString() ?? '',
        productName: json['productName']?.toString() ?? '',
        quantity: (json['quantity'] as num? ?? 0).toDouble(),
        unitCost: (json['unitCost'] as num? ?? 0).toDouble(),
        value: (json['value'] as num? ?? 0).toDouble(),
        reason: json['reason']?.toString() ?? '',
      );
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
    this.actualOutputQuantity = 0,
    this.totalMaterialCost = 0,
    this.totalWasteCost = 0,
    this.totalEligibleCost = 0,
    this.actualUnitCost = 0,
    this.materialCosts = const <ManufacturingMaterialCost>[],
    this.wasteLines = const <ManufacturingWasteLine>[],
    this.journalEntryId = '',
    this.reversalJournalEntryId = '',
    this.completedAt,
    this.completedBy = '',
    this.reversedAt,
    this.reversedBy = '',
    this.reversalReason = '',
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

  final String id,
      orderNo,
      bomId,
      bomName,
      outputProductId,
      outputProductName,
      status,
      notes;
  final String rawMaterialsWarehouseId,
      rawMaterialsWarehouseName,
      finishedGoodsWarehouseId,
      finishedGoodsWarehouseName;
  final double quantity;
  final double actualOutputQuantity,
      totalMaterialCost,
      totalWasteCost,
      totalEligibleCost,
      actualUnitCost;
  final List<ManufacturingMaterialCost> materialCosts;
  final List<ManufacturingWasteLine> wasteLines;
  final String journalEntryId,
      reversalJournalEntryId,
      completedBy,
      reversedBy,
      reversalReason;
  final DateTime? completedAt, reversedAt;
  final DateTime date, createdAt, updatedAt;
  final DateTime? deletedAt;
  final String deviceId, syncStatus, storeId, branchId, lastModifiedByDeviceId;
  final int version;

  bool get isDeleted => deletedAt != null;

  ManufacturingOrder copyWith(
          {String? id,
          String? orderNo,
          String? bomId,
          String? bomName,
          String? outputProductId,
          String? outputProductName,
          double? quantity,
          String? rawMaterialsWarehouseId,
          String? rawMaterialsWarehouseName,
          String? finishedGoodsWarehouseId,
          String? finishedGoodsWarehouseName,
          String? status,
          String? notes,
          double? actualOutputQuantity,
          double? totalMaterialCost,
          double? totalWasteCost,
          double? totalEligibleCost,
          double? actualUnitCost,
          List<ManufacturingMaterialCost>? materialCosts,
          List<ManufacturingWasteLine>? wasteLines,
          String? journalEntryId,
          String? reversalJournalEntryId,
          DateTime? completedAt,
          String? completedBy,
          DateTime? reversedAt,
          String? reversedBy,
          String? reversalReason,
          DateTime? date,
          DateTime? createdAt,
          DateTime? updatedAt,
          DateTime? deletedAt,
          bool clearDeletedAt = false,
          String? deviceId,
          String? syncStatus,
          String? storeId,
          String? branchId,
          int? version,
          String? lastModifiedByDeviceId}) =>
      ManufacturingOrder(
        id: id ?? this.id,
        orderNo: orderNo ?? this.orderNo,
        bomId: bomId ?? this.bomId,
        bomName: bomName ?? this.bomName,
        outputProductId: outputProductId ?? this.outputProductId,
        outputProductName: outputProductName ?? this.outputProductName,
        quantity: quantity ?? this.quantity,
        rawMaterialsWarehouseId:
            rawMaterialsWarehouseId ?? this.rawMaterialsWarehouseId,
        rawMaterialsWarehouseName:
            rawMaterialsWarehouseName ?? this.rawMaterialsWarehouseName,
        finishedGoodsWarehouseId:
            finishedGoodsWarehouseId ?? this.finishedGoodsWarehouseId,
        finishedGoodsWarehouseName:
            finishedGoodsWarehouseName ?? this.finishedGoodsWarehouseName,
        status: status ?? this.status,
        notes: notes ?? this.notes,
        actualOutputQuantity: actualOutputQuantity ?? this.actualOutputQuantity,
        totalMaterialCost: totalMaterialCost ?? this.totalMaterialCost,
        totalWasteCost: totalWasteCost ?? this.totalWasteCost,
        totalEligibleCost: totalEligibleCost ?? this.totalEligibleCost,
        actualUnitCost: actualUnitCost ?? this.actualUnitCost,
        materialCosts: materialCosts ?? this.materialCosts,
        wasteLines: wasteLines ?? this.wasteLines,
        journalEntryId: journalEntryId ?? this.journalEntryId,
        reversalJournalEntryId:
            reversalJournalEntryId ?? this.reversalJournalEntryId,
        completedAt: completedAt ?? this.completedAt,
        completedBy: completedBy ?? this.completedBy,
        reversedAt: reversedAt ?? this.reversedAt,
        reversedBy: reversedBy ?? this.reversedBy,
        reversalReason: reversalReason ?? this.reversalReason,
        date: date ?? this.date,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
        deviceId: deviceId ?? this.deviceId,
        syncStatus: syncStatus ?? this.syncStatus,
        storeId: storeId ?? this.storeId,
        branchId: branchId ?? this.branchId,
        version: version ?? this.version,
        lastModifiedByDeviceId:
            lastModifiedByDeviceId ?? this.lastModifiedByDeviceId,
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
        'actualOutputQuantity': actualOutputQuantity,
        'totalMaterialCost': totalMaterialCost,
        'totalWasteCost': totalWasteCost,
        'totalEligibleCost': totalEligibleCost,
        'actualUnitCost': actualUnitCost,
        'materialCosts': materialCosts.map((item) => item.toJson()).toList(),
        'wasteLines': wasteLines.map((item) => item.toJson()).toList(),
        'journalEntryId': journalEntryId,
        'reversalJournalEntryId': reversalJournalEntryId,
        'completedAt': completedAt?.toIso8601String(),
        'completedBy': completedBy,
        'reversedAt': reversedAt?.toIso8601String(),
        'reversedBy': reversedBy,
        'reversalReason': reversalReason,
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
    final date =
        DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now();
    return ManufacturingOrder(
      id: json['id']?.toString() ?? '',
      orderNo: json['orderNo']?.toString() ?? '',
      bomId: json['bomId']?.toString() ?? '',
      bomName: json['bomName']?.toString() ?? '',
      outputProductId: json['outputProductId']?.toString() ?? '',
      outputProductName: json['outputProductName']?.toString() ?? '',
      quantity: (json['quantity'] as num? ?? 0).toDouble(),
      rawMaterialsWarehouseId:
          json['rawMaterialsWarehouseId']?.toString().isNotEmpty == true
              ? json['rawMaterialsWarehouseId'].toString()
              : 'main',
      rawMaterialsWarehouseName:
          json['rawMaterialsWarehouseName']?.toString().isNotEmpty == true
              ? json['rawMaterialsWarehouseName'].toString()
              : 'Main warehouse',
      finishedGoodsWarehouseId:
          json['finishedGoodsWarehouseId']?.toString().isNotEmpty == true
              ? json['finishedGoodsWarehouseId'].toString()
              : 'main',
      finishedGoodsWarehouseName:
          json['finishedGoodsWarehouseName']?.toString().isNotEmpty == true
              ? json['finishedGoodsWarehouseName'].toString()
              : 'Main warehouse',
      status: json['status']?.toString() ?? 'completed',
      notes: json['notes']?.toString() ?? '',
      actualOutputQuantity:
          (json['actualOutputQuantity'] as num? ?? 0).toDouble(),
      totalMaterialCost: (json['totalMaterialCost'] as num? ?? 0).toDouble(),
      totalWasteCost: (json['totalWasteCost'] as num? ?? 0).toDouble(),
      totalEligibleCost: (json['totalEligibleCost'] as num? ?? 0).toDouble(),
      actualUnitCost: (json['actualUnitCost'] as num? ?? 0).toDouble(),
      materialCosts: (json['materialCosts'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((value) => ManufacturingMaterialCost.fromJson(
              Map<String, dynamic>.from(value)))
          .toList(growable: false),
      wasteLines: (json['wasteLines'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((value) =>
              ManufacturingWasteLine.fromJson(Map<String, dynamic>.from(value)))
          .toList(growable: false),
      journalEntryId: json['journalEntryId']?.toString() ?? '',
      reversalJournalEntryId: json['reversalJournalEntryId']?.toString() ?? '',
      completedAt: DateTime.tryParse(json['completedAt']?.toString() ?? ''),
      completedBy: json['completedBy']?.toString() ?? '',
      reversedAt: DateTime.tryParse(json['reversedAt']?.toString() ?? ''),
      reversedBy: json['reversedBy']?.toString() ?? '',
      reversalReason: json['reversalReason']?.toString() ?? '',
      date: date,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? date,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? date,
      deletedAt: DateTime.tryParse(json['deletedAt']?.toString() ?? ''),
      deviceId: json['deviceId']?.toString() ?? '',
      syncStatus: json['syncStatus']?.toString() ?? 'synced',
      storeId: json['storeId']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? '',
      version: (json['version'] as num? ?? 1).toInt(),
      lastModifiedByDeviceId: json['lastModifiedByDeviceId']?.toString() ??
          json['deviceId']?.toString() ??
          '',
    );
  }
}
