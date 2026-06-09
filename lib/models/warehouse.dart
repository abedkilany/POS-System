class Warehouse {
  Warehouse({
    required this.id,
    required this.name,
    this.code = '',
    this.location = '',
    this.isDefault = false,
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
  })  : createdAt = createdAt ?? updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  static const String defaultId = 'main';
  static const String defaultName = 'Main warehouse';

  final String id, name, code, location;
  final bool isDefault, isActive;
  final DateTime createdAt, updatedAt;
  final DateTime? deletedAt;
  final String deviceId, syncStatus, storeId, branchId, lastModifiedByDeviceId;
  final int version;

  bool get isDeleted => deletedAt != null;

  Warehouse copyWith({String? name, String? code, String? location, bool? isDefault, bool? isActive, DateTime? createdAt, DateTime? updatedAt, DateTime? deletedAt, bool clearDeletedAt = false, String? deviceId, String? syncStatus, String? storeId, String? branchId, int? version, String? lastModifiedByDeviceId}) => Warehouse(
        id: id,
        name: name ?? this.name,
        code: code ?? this.code,
        location: location ?? this.location,
        isDefault: isDefault ?? this.isDefault,
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
        'code': code,
        'location': location,
        'isDefault': isDefault,
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

  factory Warehouse.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final created = DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now;
    return Warehouse(
      id: json['id']?.toString() ?? defaultId,
      name: json['name']?.toString() ?? defaultName,
      code: json['code']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      isDefault: json['isDefault'] as bool? ?? (json['id']?.toString() == defaultId),
      isActive: json['isActive'] as bool? ?? true,
      createdAt: created,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? created,
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
