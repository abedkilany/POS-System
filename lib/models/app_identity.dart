enum AppPlatformType { windows, android, web, unknown }

enum DeviceRole { standalone, host, client }

enum AppRole { store, customer, delivery, admin }

enum SyncMode { localOnly, lanOnly, cloudConnected, marketplaceEnabled }

class AppIdentity {
  const AppIdentity({
    required this.storeId,
    required this.branchId,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.deviceRole,
    required this.appRole,
    required this.syncMode,
    required this.createdAt,
    required this.updatedAt,
    this.hostDeviceId = '',
    this.cloudTenantId = '',
  });

  final String storeId;
  final String branchId;
  final String deviceId;
  final String deviceName;
  final AppPlatformType platform;
  final DeviceRole deviceRole;
  final AppRole appRole;
  final SyncMode syncMode;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String hostDeviceId;
  final String cloudTenantId;

  bool get isHost => deviceRole == DeviceRole.host;
  bool get isClient => deviceRole == DeviceRole.client;
  bool get isCloudEnabled => syncMode == SyncMode.cloudConnected || syncMode == SyncMode.marketplaceEnabled;
  bool get isMarketplaceEnabled => syncMode == SyncMode.marketplaceEnabled;

  AppIdentity copyWith({
    String? storeId,
    String? branchId,
    String? deviceId,
    String? deviceName,
    AppPlatformType? platform,
    DeviceRole? deviceRole,
    AppRole? appRole,
    SyncMode? syncMode,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? hostDeviceId,
    String? cloudTenantId,
  }) {
    return AppIdentity(
      storeId: storeId ?? this.storeId,
      branchId: branchId ?? this.branchId,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      platform: platform ?? this.platform,
      deviceRole: deviceRole ?? this.deviceRole,
      appRole: appRole ?? this.appRole,
      syncMode: syncMode ?? this.syncMode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      hostDeviceId: hostDeviceId ?? this.hostDeviceId,
      cloudTenantId: cloudTenantId ?? this.cloudTenantId,
    );
  }

  Map<String, dynamic> toJson() => {
        'storeId': storeId,
        'branchId': branchId,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'platform': platform.name,
        'deviceRole': deviceRole.name,
        'appRole': appRole.name,
        'syncMode': syncMode.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'hostDeviceId': hostDeviceId,
        'cloudTenantId': cloudTenantId,
      };

  factory AppIdentity.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    T enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      return fallback;
    }

    return AppIdentity(
      storeId: json['storeId']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? 'main',
      deviceId: json['deviceId']?.toString() ?? '',
      deviceName: json['deviceName']?.toString() ?? '',
      platform: enumByName(AppPlatformType.values, json['platform']?.toString(), AppPlatformType.unknown),
      deviceRole: enumByName(DeviceRole.values, json['deviceRole']?.toString(), DeviceRole.standalone),
      appRole: enumByName(AppRole.values, json['appRole']?.toString(), AppRole.store),
      syncMode: enumByName(SyncMode.values, json['syncMode']?.toString(), SyncMode.localOnly),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
      hostDeviceId: json['hostDeviceId']?.toString() ?? '',
      cloudTenantId: json['cloudTenantId']?.toString() ?? '',
    );
  }

  static AppIdentity defaults({required String deviceId, required AppPlatformType platform}) {
    final now = DateTime.now();
    return AppIdentity(
      storeId: 'store_${deviceId.isEmpty ? now.microsecondsSinceEpoch : deviceId}',
      branchId: 'main',
      deviceId: deviceId,
      deviceName: 'Main device',
      platform: platform,
      deviceRole: platform == AppPlatformType.windows ? DeviceRole.host : DeviceRole.client,
      appRole: AppRole.store,
      syncMode: platform == AppPlatformType.web ? SyncMode.cloudConnected : SyncMode.lanOnly,
      createdAt: now,
      updatedAt: now,
    );
  }
}
