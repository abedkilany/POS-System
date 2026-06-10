class InventoryCountSession {
  InventoryCountSession({
    required this.id,
    required this.countNo,
    required this.createdAt,
    required this.createdBy,
    this.warehouseId = 'main',
    this.warehouseName = 'Main warehouse',
    this.status = 'open',
    this.notes = '',
    this.approvedAt,
    this.approvedBy = '',
    List<InventoryCountLine>? lines,
    DateTime? updatedAt,
  })  : updatedAt = updatedAt ?? createdAt,
        lines = lines ?? <InventoryCountLine>[];

  final String id, countNo, createdBy, warehouseId, warehouseName, status, notes, approvedBy;
  final DateTime createdAt, updatedAt;
  final DateTime? approvedAt;
  final List<InventoryCountLine> lines;

  bool get isOpen => status == 'open';
  bool get isApproved => status == 'approved';
  int get countedLines => lines.where((line) => line.isCounted).length;
  int get totalLines => lines.length;

  InventoryCountSession copyWith({
    String? status,
    String? notes,
    DateTime? approvedAt,
    String? approvedBy,
    List<InventoryCountLine>? lines,
    DateTime? updatedAt,
  }) => InventoryCountSession(
        id: id,
        countNo: countNo,
        createdAt: createdAt,
        createdBy: createdBy,
        warehouseId: warehouseId,
        warehouseName: warehouseName,
        status: status ?? this.status,
        notes: notes ?? this.notes,
        approvedAt: approvedAt ?? this.approvedAt,
        approvedBy: approvedBy ?? this.approvedBy,
        lines: lines ?? this.lines,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'countNo': countNo,
        'createdAt': createdAt.toIso8601String(),
        'createdBy': createdBy,
        'warehouseId': warehouseId,
        'warehouseName': warehouseName,
        'status': status,
        'notes': notes,
        'approvedAt': approvedAt?.toIso8601String(),
        'approvedBy': approvedBy,
        'updatedAt': updatedAt.toIso8601String(),
        'lines': lines.map((line) => line.toJson()).toList(),
      };

  factory InventoryCountSession.fromJson(Map<String, dynamic> json) {
    final created = DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now();
    return InventoryCountSession(
      id: json['id']?.toString() ?? created.microsecondsSinceEpoch.toString(),
      countNo: json['countNo']?.toString() ?? 'CNT-${created.microsecondsSinceEpoch}',
      createdAt: created,
      createdBy: json['createdBy']?.toString() ?? '',
      warehouseId: json['warehouseId']?.toString() ?? 'main',
      warehouseName: json['warehouseName']?.toString() ?? 'Main warehouse',
      status: json['status']?.toString() ?? 'open',
      notes: json['notes']?.toString() ?? '',
      approvedAt: DateTime.tryParse(json['approvedAt']?.toString() ?? ''),
      approvedBy: json['approvedBy']?.toString() ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? created,
      lines: (json['lines'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => InventoryCountLine.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }
}

class InventoryCountLine {
  InventoryCountLine({
    required this.productId,
    required this.productName,
    required this.snapshotStock,
    this.productCode = '',
    this.countedQty,
    this.countedAt,
    this.countedBy = '',
    this.note = '',
  });

  final String productId, productName, productCode, countedBy, note;
  final double snapshotStock;
  final double? countedQty;
  final DateTime? countedAt;

  bool get isCounted => countedQty != null && countedAt != null;

  InventoryCountLine copyWith({double? countedQty, DateTime? countedAt, String? countedBy, String? note}) => InventoryCountLine(
        productId: productId,
        productName: productName,
        productCode: productCode,
        snapshotStock: snapshotStock,
        countedQty: countedQty ?? this.countedQty,
        countedAt: countedAt ?? this.countedAt,
        countedBy: countedBy ?? this.countedBy,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'productCode': productCode,
        'snapshotStock': snapshotStock,
        'countedQty': countedQty,
        'countedAt': countedAt?.toIso8601String(),
        'countedBy': countedBy,
        'note': note,
      };

  factory InventoryCountLine.fromJson(Map<String, dynamic> json) => InventoryCountLine(
        productId: json['productId']?.toString() ?? '',
        productName: json['productName']?.toString() ?? '',
        productCode: json['productCode']?.toString() ?? '',
        snapshotStock: (json['snapshotStock'] as num? ?? 0).toDouble(),
        countedQty: (json['countedQty'] as num?)?.toDouble(),
        countedAt: DateTime.tryParse(json['countedAt']?.toString() ?? ''),
        countedBy: json['countedBy']?.toString() ?? '',
        note: json['note']?.toString() ?? '',
      );
}
