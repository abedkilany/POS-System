class InventoryReconciliation {
  const InventoryReconciliation({
    required this.id,
    required this.storeId,
    required this.branchId,
    required this.warehouseId,
    required this.productId,
    required this.legacyProductStock,
    required this.ledgerBalance,
    required this.warehouseBalance,
    required this.difference,
    required this.classification,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
    this.resolutionNote = '',
  });

  final String id;
  final String storeId;
  final String branchId;
  final String warehouseId;
  final String productId;
  final double legacyProductStock;
  final double ledgerBalance;
  final double warehouseBalance;
  final double difference;
  final String classification;
  final String status;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String resolutionNote;

  InventoryReconciliation copyWith({
    String? id,
    String? storeId,
    String? branchId,
    String? warehouseId,
    String? productId,
    double? legacyProductStock,
    double? ledgerBalance,
    double? warehouseBalance,
    double? difference,
    String? classification,
    String? status,
    DateTime? createdAt,
    DateTime? resolvedAt,
    bool clearResolvedAt = false,
    String? resolutionNote,
  }) {
    return InventoryReconciliation(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      branchId: branchId ?? this.branchId,
      warehouseId: warehouseId ?? this.warehouseId,
      productId: productId ?? this.productId,
      legacyProductStock: legacyProductStock ?? this.legacyProductStock,
      ledgerBalance: ledgerBalance ?? this.ledgerBalance,
      warehouseBalance: warehouseBalance ?? this.warehouseBalance,
      difference: difference ?? this.difference,
      classification: classification ?? this.classification,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      resolvedAt: clearResolvedAt ? null : (resolvedAt ?? this.resolvedAt),
      resolutionNote: resolutionNote ?? this.resolutionNote,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'storeId': storeId,
        'branchId': branchId,
        'warehouseId': warehouseId,
        'productId': productId,
        'legacyProductStock': legacyProductStock,
        'ledgerBalance': ledgerBalance,
        'warehouseBalance': warehouseBalance,
        'difference': difference,
        'classification': classification,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'resolvedAt': resolvedAt?.toIso8601String(),
        'resolutionNote': resolutionNote,
      };

  factory InventoryReconciliation.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now();
    return InventoryReconciliation(
      id: json['id']?.toString() ?? '',
      storeId: json['storeId']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? 'main',
      warehouseId: json['warehouseId']?.toString() ?? '',
      productId: json['productId']?.toString() ?? '',
      legacyProductStock:
          (json['legacyProductStock'] as num? ?? 0).toDouble(),
      ledgerBalance: (json['ledgerBalance'] as num? ?? 0).toDouble(),
      warehouseBalance: (json['warehouseBalance'] as num? ?? 0).toDouble(),
      difference: (json['difference'] as num? ?? 0).toDouble(),
      classification: json['classification']?.toString() ?? '',
      status: json['status']?.toString() ?? 'open',
      createdAt: createdAt,
      resolvedAt: DateTime.tryParse(json['resolvedAt']?.toString() ?? ''),
      resolutionNote: json['resolutionNote']?.toString() ?? '',
    );
  }
}
