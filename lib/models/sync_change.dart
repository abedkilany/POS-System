class SyncChange {
  const SyncChange({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.deviceId,
    required this.createdAt,
    required this.payload,
    this.storeId = '',
    this.branchId = '',
    this.isSynced = false,
    this.syncedAt,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String operation;
  final String deviceId;
  final DateTime createdAt;
  final Map<String, dynamic> payload;
  final String storeId;
  final String branchId;
  final bool isSynced;
  final DateTime? syncedAt;

  SyncChange copyWith({
    String? id,
    String? entityType,
    String? entityId,
    String? operation,
    String? deviceId,
    DateTime? createdAt,
    Map<String, dynamic>? payload,
    String? storeId,
    String? branchId,
    bool? isSynced,
    DateTime? syncedAt,
  }) {
    return SyncChange(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      deviceId: deviceId ?? this.deviceId,
      createdAt: createdAt ?? this.createdAt,
      payload: payload ?? this.payload,
      storeId: storeId ?? this.storeId,
      branchId: branchId ?? this.branchId,
      isSynced: isSynced ?? this.isSynced,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'entityType': entityType,
        'entityId': entityId,
        'operation': operation,
        'deviceId': deviceId,
        'createdAt': createdAt.toIso8601String(),
        'payload': payload,
        'storeId': storeId,
        'branchId': branchId,
        'isSynced': isSynced,
        'syncedAt': syncedAt?.toIso8601String(),
      };

  factory SyncChange.fromJson(Map<String, dynamic> json) => SyncChange(
        id: json['id'] as String,
        entityType: json['entityType'] as String,
        entityId: json['entityId'] as String,
        operation: json['operation'] as String,
        deviceId: json['deviceId'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
        storeId: json['storeId'] as String? ?? '',
        branchId: json['branchId'] as String? ?? '',
        isSynced: json['isSynced'] as bool? ?? false,
        syncedAt: DateTime.tryParse(json['syncedAt'] as String? ?? ''),
      );
}
