import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'dart:math';

import '../../data/app_store.dart';
import '../../models/app_identity.dart';
import '../../models/sync_change.dart';
import 'local_database_service.dart';
import 'unified_sync_core_service.dart';
import '../sync_unified/sync_device_state.dart';
import '../snapshot/unified_snapshot_transfer.dart';

typedef LanSyncProgressCallback = void Function(double value, String label);

enum LanSyncDeviceMode { unconfigured, host, client }

class HostRegistryDevice {
  const HostRegistryDevice({
    required this.clientDeviceId,
    required this.deviceToken,
    this.hostDeviceId = '',
    this.deviceName = '',
    this.status = 'active',
    this.source = 'manual',
    this.pairedAt,
    this.lastSeenAt,
    this.lastSyncAt,
  });

  final String clientDeviceId;
  final String deviceToken;
  final String hostDeviceId;
  final String deviceName;
  final String status;
  final String source;
  final DateTime? pairedAt;
  final DateTime? lastSeenAt;
  final DateTime? lastSyncAt;

  bool get isActive => status != 'revoked' && status != 'deleted';

  HostRegistryDevice copyWith({
    String? clientDeviceId,
    String? deviceToken,
    String? hostDeviceId,
    String? deviceName,
    String? status,
    String? source,
    DateTime? pairedAt,
    DateTime? lastSeenAt,
    DateTime? lastSyncAt,
    bool clearHostDeviceId = false,
    bool clearDeviceName = false,
    bool clearLastSeenAt = false,
    bool clearLastSyncAt = false,
  }) {
    return HostRegistryDevice(
      clientDeviceId: clientDeviceId ?? this.clientDeviceId,
      deviceToken: deviceToken ?? this.deviceToken,
      hostDeviceId:
          clearHostDeviceId ? '' : (hostDeviceId ?? this.hostDeviceId),
      deviceName: clearDeviceName ? '' : (deviceName ?? this.deviceName),
      status: status ?? this.status,
      source: source ?? this.source,
      pairedAt: pairedAt ?? this.pairedAt,
      lastSeenAt: clearLastSeenAt ? null : (lastSeenAt ?? this.lastSeenAt),
      lastSyncAt: clearLastSyncAt ? null : (lastSyncAt ?? this.lastSyncAt),
    );
  }

  Map<String, dynamic> toJson() => {
        'clientDeviceId': clientDeviceId,
        'deviceToken': deviceToken,
        'hostDeviceId': hostDeviceId,
        'deviceName': deviceName,
        'status': status,
        'source': source,
        'pairedAt': pairedAt?.toIso8601String(),
        'lastSeenAt': lastSeenAt?.toIso8601String(),
        'lastSyncAt': lastSyncAt?.toIso8601String(),
      };

  factory HostRegistryDevice.fromJson(Map<String, dynamic> json) {
    final clientDeviceId =
        (json['clientDeviceId'] ?? json['deviceId'] ?? '').toString().trim();
    return HostRegistryDevice(
      clientDeviceId: clientDeviceId,
      deviceToken:
          (json['deviceToken'] ?? json['token'] ?? '').toString().trim(),
      hostDeviceId: (json['hostDeviceId'] ?? '').toString().trim(),
      deviceName: (json['deviceName'] ?? json['name'] ?? '').toString().trim(),
      status: (json['status'] ?? 'active').toString().trim().isEmpty
          ? 'active'
          : (json['status'] ?? 'active').toString().trim(),
      source: (json['source'] ?? 'host_registry').toString().trim().isEmpty
          ? 'host_registry'
          : (json['source'] ?? 'host_registry').toString().trim(),
      pairedAt: DateTime.tryParse((json['pairedAt'] ?? '').toString()),
      lastSeenAt: DateTime.tryParse((json['lastSeenAt'] ?? '').toString()),
      lastSyncAt: DateTime.tryParse((json['lastSyncAt'] ?? '').toString()),
    );
  }

  static Map<String, HostRegistryDevice> fromJsonMap(Object? raw) {
    if (raw is! Map) return const <String, HostRegistryDevice>{};
    final result = <String, HostRegistryDevice>{};
    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final device = HostRegistryDevice.fromJson(
          Map<String, dynamic>.from(entry.value as Map));
      final id = device.clientDeviceId.trim().isNotEmpty
          ? device.clientDeviceId.trim()
          : '${entry.key}'.trim();
      if (id.isEmpty) continue;
      result[id] = device.clientDeviceId.trim().isEmpty
          ? device.copyWith(clientDeviceId: id)
          : device;
    }
    return Map.unmodifiable(result);
  }

  static Map<String, HostRegistryDevice> migrateFromPairedDevices(
    Map<String, String> pairedDevices, {
    Map<String, HostRegistryDevice> existing =
        const <String, HostRegistryDevice>{},
    String hostDeviceId = '',
  }) {
    final registry = <String, HostRegistryDevice>{...existing};
    final now = DateTime.now();
    for (final entry in pairedDevices.entries) {
      final clientDeviceId = entry.key.trim();
      final deviceToken = entry.value.trim();
      if (clientDeviceId.isEmpty || deviceToken.isEmpty) continue;
      final current = registry[clientDeviceId];
      registry[clientDeviceId] = (current ??
              HostRegistryDevice(
                clientDeviceId: clientDeviceId,
                deviceToken: deviceToken,
                hostDeviceId: hostDeviceId.trim(),
                source: 'migrated_from_paired_devices',
                pairedAt: now,
              ))
          .copyWith(
        deviceToken: deviceToken,
        hostDeviceId: hostDeviceId.trim().isEmpty
            ? current?.hostDeviceId
            : hostDeviceId.trim(),
        status: 'active',
      );
    }
    return Map.unmodifiable(registry);
  }
}

class LanSyncSettings {
  const LanSyncSettings({
    required this.host,
    required this.port,
    required this.autoSyncEnabled,
    required this.hostModeEnabled,
    this.intervalSeconds = defaultIntervalSeconds,
    this.setupComplete = false,
    this.mode = LanSyncDeviceMode.unconfigured,
    this.secret = '',
    this.lastPullCursor,
    this.lastConnectionAt,
    this.lastSyncAt,
    this.pairedDevices = const <String, String>{},
    Map<String, HostRegistryDevice>? hostRegistry,
  }) : hostRegistry = hostRegistry ?? const <String, HostRegistryDevice>{};

  static const String storageKey = 'lan_sync_settings_v2';
  static const int defaultIntervalSeconds = 30;
  static const int minIntervalSeconds = 5;
  static const int maxIntervalSeconds = 60;

  final String host;
  final int port;
  final bool autoSyncEnabled;
  final bool hostModeEnabled;
  final int intervalSeconds;
  final bool setupComplete;
  final LanSyncDeviceMode mode;
  final String secret;
  final DateTime? lastPullCursor;
  final DateTime? lastConnectionAt;
  final DateTime? lastSyncAt;

  /// LAN paired Client credentials: deviceId -> deviceToken.
  /// Host stores this map; Clients store only their own deviceToken in AppIdentity.
  final Map<String, String> pairedDevices;

  /// Host-owned registry of Clients that belong to this Host.
  /// This is the new single source of truth for Sync Monitoring. It is
  /// initially migrated from pairedDevices so existing Clients do not need
  /// to be paired again after the update.
  final Map<String, HostRegistryDevice> hostRegistry;

  bool get isHost => mode == LanSyncDeviceMode.host || hostModeEnabled;
  bool get isClient =>
      mode == LanSyncDeviceMode.client || (!hostModeEnabled && setupComplete);

  LanSyncSettings copyWith({
    String? host,
    int? port,
    bool? autoSyncEnabled,
    bool? hostModeEnabled,
    int? intervalSeconds,
    bool? setupComplete,
    LanSyncDeviceMode? mode,
    String? secret,
    DateTime? lastPullCursor,
    DateTime? lastConnectionAt,
    DateTime? lastSyncAt,
    Map<String, String>? pairedDevices,
    Map<String, HostRegistryDevice>? hostRegistry,
    bool clearLastPullCursor = false,
    bool clearLastConnectionAt = false,
    bool clearLastSyncAt = false,
  }) {
    return LanSyncSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      hostModeEnabled: hostModeEnabled ?? this.hostModeEnabled,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      setupComplete: setupComplete ?? this.setupComplete,
      mode: mode ?? this.mode,
      secret: secret ?? this.secret,
      lastPullCursor:
          clearLastPullCursor ? null : (lastPullCursor ?? this.lastPullCursor),
      lastConnectionAt: clearLastConnectionAt
          ? null
          : (lastConnectionAt ?? this.lastConnectionAt),
      lastSyncAt: clearLastSyncAt ? null : (lastSyncAt ?? this.lastSyncAt),
      pairedDevices: pairedDevices ?? this.pairedDevices,
      hostRegistry: hostRegistry ?? this.hostRegistry,
    );
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'autoSyncEnabled': autoSyncEnabled,
        'intervalSeconds': intervalSeconds,
        'hostModeEnabled': hostModeEnabled,
        'setupComplete': setupComplete,
        'mode': mode.name,
        'secret': secret,
        'lastPullCursor': lastPullCursor?.toIso8601String(),
        'lastConnectionAt': lastConnectionAt?.toIso8601String(),
        'lastSyncAt': lastSyncAt?.toIso8601String(),
        'pairedDevices': pairedDevices,
        'hostRegistry':
            hostRegistry.map((key, value) => MapEntry(key, value.toJson())),
      };

  factory LanSyncSettings.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'] as String? ?? '';
    final mode = LanSyncDeviceMode.values.firstWhere(
      (item) => item.name == modeName,
      orElse: () => (json['hostModeEnabled'] as bool? ?? false)
          ? LanSyncDeviceMode.host
          : LanSyncDeviceMode.client,
    );
    final pairedDevices = (json['pairedDevices'] is Map)
        ? Map<String, String>.from((json['pairedDevices'] as Map)
            .map((key, value) => MapEntry('$key', '$value')))
        : const <String, String>{};
    final hostRegistry = HostRegistryDevice.migrateFromPairedDevices(
      pairedDevices,
      existing: HostRegistryDevice.fromJsonMap(json['hostRegistry']),
    );
    return LanSyncSettings(
      host: (json['host'] as String?)?.trim().isNotEmpty == true
          ? (json['host'] as String).trim()
          : '192.168.1.100',
      port: json['port'] as int? ?? int.tryParse('${json['port']}') ?? 8787,
      autoSyncEnabled: json['autoSyncEnabled'] as bool? ?? true,
      intervalSeconds: normalizeIntervalSeconds(json['intervalSeconds']),
      hostModeEnabled:
          json['hostModeEnabled'] as bool? ?? mode == LanSyncDeviceMode.host,
      setupComplete: json['setupComplete'] as bool? ?? false,
      mode: mode,
      secret: json['secret'] as String? ?? '',
      lastPullCursor:
          DateTime.tryParse(json['lastPullCursor'] as String? ?? ''),
      lastConnectionAt:
          DateTime.tryParse(json['lastConnectionAt'] as String? ?? ''),
      lastSyncAt: DateTime.tryParse(json['lastSyncAt'] as String? ?? ''),
      pairedDevices: pairedDevices,
      hostRegistry: hostRegistry,
    );
  }

  /// Returns a settings copy where Host Registry has been rebuilt/adopted from
  /// the current Host pairedDevices. This is the phase-2 automatic migration:
  /// existing paired Clients become Host Registry members on first Host startup
  /// after the update, without forcing users to pair them again.
  LanSyncSettings withMigratedHostRegistry(String hostDeviceId) {
    final migrated = HostRegistryDevice.migrateFromPairedDevices(
      pairedDevices,
      existing: hostRegistry,
      hostDeviceId: hostDeviceId,
    );
    return copyWith(hostRegistry: migrated);
  }

  /// Adopt a Cloud-paired Client into the Host Registry. The Registry remains
  /// the Monitoring source of truth; Cloud pairing is only allowed to add a
  /// device after the Host verifies that the single-use pairing code was
  /// consumed by that Client for this Host.
  LanSyncSettings withCloudPairedHostRegistryDevice({
    required String hostDeviceId,
    required String clientDeviceId,
    String deviceToken = '',
    String deviceName = '',
    DateTime? pairedAt,
  }) {
    final cleanHostId = hostDeviceId.trim();
    final cleanClientId = clientDeviceId.trim();
    if (cleanHostId.isEmpty || cleanClientId.isEmpty) return this;
    final existing = hostRegistry[cleanClientId];
    final cleanToken = deviceToken.trim().isNotEmpty
        ? deviceToken.trim()
        : (existing?.deviceToken.trim() ?? '');
    final cleanName = deviceName.trim().isNotEmpty
        ? deviceName.trim()
        : (existing?.deviceName.trim() ?? '');
    final registry = <String, HostRegistryDevice>{...hostRegistry};
    registry[cleanClientId] = (existing ??
            HostRegistryDevice(
              clientDeviceId: cleanClientId,
              deviceToken: cleanToken,
              hostDeviceId: cleanHostId,
              deviceName: cleanName,
              source: 'cloud_pairing_claim',
              pairedAt: pairedAt ?? DateTime.now(),
              lastSeenAt: pairedAt ?? DateTime.now(),
            ))
        .copyWith(
      deviceToken: cleanToken,
      hostDeviceId: cleanHostId,
      deviceName: cleanName,
      status: 'active',
      source: 'cloud_pairing_claim',
      pairedAt: existing?.pairedAt ?? pairedAt ?? DateTime.now(),
      lastSeenAt: pairedAt ?? DateTime.now(),
    );
    return copyWith(hostRegistry: Map.unmodifiable(registry));
  }

  bool hostRegistryNeedsMigration(String hostDeviceId) {
    final hostId = hostDeviceId.trim();
    for (final entry in pairedDevices.entries) {
      final clientDeviceId = entry.key.trim();
      final deviceToken = entry.value.trim();
      if (clientDeviceId.isEmpty || deviceToken.isEmpty) continue;
      final registryDevice = hostRegistry[clientDeviceId];
      if (registryDevice == null) return true;
      if (registryDevice.deviceToken.trim() != deviceToken) return true;
      if (hostId.isNotEmpty && registryDevice.hostDeviceId.trim() != hostId) {
        return true;
      }
      if (!registryDevice.isActive) return true;
    }
    return false;
  }

  static LanSyncSettings load() {
    final rawV2 = LocalDatabaseService.getString(storageKey);
    if (rawV2 != null && rawV2.trim().isNotEmpty) {
      try {
        return LanSyncSettings.fromJson(
            Map<String, dynamic>.from(jsonDecode(rawV2) as Map));
      } catch (_) {}
    }

    // Do not auto-migrate legacy LAN settings to a completed v2 setup.
    // The v2 Host/Client selection must be explicit, otherwise upgraded
    // installs can silently skip the setup screen.

    return const LanSyncSettings(
      host: '192.168.1.100',
      port: 8787,
      autoSyncEnabled: false,
      hostModeEnabled: false,
    );
  }

  static int normalizeIntervalSeconds(Object? value) {
    final parsed = value is int
        ? value
        : int.tryParse(value?.toString() ?? '') ?? defaultIntervalSeconds;
    return parsed.clamp(minIntervalSeconds, maxIntervalSeconds).toInt();
  }

  Future<void> save() async {
    await LocalDatabaseService.setString(storageKey, jsonEncode(toJson()));
  }

  static Future<void> resetSetup() async {
    await LocalDatabaseService.deleteString(storageKey);
  }

  static String generateSecret() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(16, (_) => alphabet[random.nextInt(alphabet.length)])
        .join();
  }

  static String generatePairingCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(8, (_) => alphabet[random.nextInt(alphabet.length)])
        .join();
  }

  static String generateDeviceToken() {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return 'lan_${List.generate(40, (_) => alphabet[random.nextInt(alphabet.length)]).join()}';
  }

  static Future<List<String>> localIpv4Addresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    final addresses = <String>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback && address.address.trim().isNotEmpty) {
          addresses.add(address.address.trim());
        }
      }
    }
    return addresses.toSet().toList();
  }
}

class LanSyncResult {
  const LanSyncResult({required this.ok, required this.message});
  final bool ok;
  final String message;
}

class LanSyncService {
  LanSyncService(this.store);

  final AppStore store;
  late final UnifiedSyncCoreService _syncCore = UnifiedSyncCoreService(store);
  Map<String, dynamic>? _snapshotTransferCache;
  DateTime? _snapshotTransferCacheAt;
  static HttpServer? _sharedServer;
  static int? _sharedPort;
  static final Set<String> _activeSnapshotGenerationRebuilds = <String>{};

  String _snapshotGenerationKey(String transport) =>
      'applied_host_snapshot_generation_${transport}_${store.appIdentity.storeId}_${store.appIdentity.branchId}';

  String _snapshotGenerationInProgressKey(String transport) =>
      'in_progress_host_snapshot_generation_${transport}_${store.appIdentity.storeId}_${store.appIdentity.branchId}';

  String _snapshotGenerationFailedKey(String transport) =>
      'failed_host_snapshot_generation_${transport}_${store.appIdentity.storeId}_${store.appIdentity.branchId}';

  String _snapshotGenerationInProgressAtKey(String transport) =>
      'in_progress_host_snapshot_generation_at_${transport}_${store.appIdentity.storeId}_${store.appIdentity.branchId}';

  String _snapshotGenerationFailedAtKey(String transport) =>
      'failed_host_snapshot_generation_at_${transport}_${store.appIdentity.storeId}_${store.appIdentity.branchId}';

  String _restoreCommandExecutedKey(String transport) =>
      'executed_host_restore_command_${transport}_${store.appIdentity.storeId}_${store.appIdentity.branchId}';

  String _restoreCommandInProgressKey(String transport) =>
      'in_progress_host_restore_command_${transport}_${store.appIdentity.storeId}_${store.appIdentity.branchId}';

  String _snapshotGenerationLockId(String transport, String generation) =>
      '${transport}_${store.appIdentity.storeId}_${store.appIdentity.branchId}_$generation';

  String _remoteHostSnapshotGeneration(Map<String, dynamic> decoded) {
    return (decoded['hostSnapshotGeneration'] ??
            decoded['snapshotGeneration'] ??
            decoded['restoreGeneration'] ??
            '')
        .toString()
        .trim();
  }

  String _remoteHostRestoreCommandId(Map<String, dynamic> decoded) {
    return (decoded['hostRestoreCommandId'] ??
            decoded['restoreCommandId'] ??
            decoded['rebuildCommandId'] ??
            decoded['commandId'] ??
            decoded['hostSnapshotGeneration'] ??
            decoded['snapshotGeneration'] ??
            decoded['restoreGeneration'] ??
            '')
        .toString()
        .trim();
  }

  String _restoreCommandIdFromChanges(List<SyncChange> changes) {
    for (final change in changes) {
      if (change.entityType == 'system' &&
          change.operation == 'cloud_restore_snapshot_ready') {
        return _remoteHostRestoreCommandId(change.payload);
      }
    }
    return '';
  }

  bool _restoreCommandAlreadyExecuted(String transport, String commandId) {
    if (commandId.trim().isEmpty) return false;
    final executed =
        LocalDatabaseService.getString(_restoreCommandExecutedKey(transport)) ??
            '';
    return executed.trim() == commandId.trim();
  }

  bool _needsHostSnapshotGenerationRebuild(
      String transport, Map<String, dynamic> decoded) {
    if (!store.appIdentity.isClient) return false;
    final remote = _remoteHostSnapshotGeneration(decoded);
    if (remote.isEmpty) return false;
    final commandId = _remoteHostRestoreCommandId(decoded);
    final commandExecuted =
        _restoreCommandAlreadyExecuted(transport, commandId);
    if (commandExecuted) return false;
    final applied =
        LocalDatabaseService.getString(_snapshotGenerationKey(transport)) ?? '';
    if (applied.trim() == remote && commandId.isEmpty) return false;

    final lockId = _snapshotGenerationLockId(transport, remote);
    if (_activeSnapshotGenerationRebuilds.contains(lockId)) return false;

    final inProgress = LocalDatabaseService.getString(
            _snapshotGenerationInProgressKey(transport)) ??
        '';
    final inProgressAtRaw = LocalDatabaseService.getString(
            _snapshotGenerationInProgressAtKey(transport)) ??
        '';
    final inProgressAt = DateTime.tryParse(inProgressAtRaw);
    if (inProgress.trim() == remote &&
        inProgressAt != null &&
        DateTime.now().difference(inProgressAt) < const Duration(minutes: 10)) {
      return false;
    }

    final failed = LocalDatabaseService.getString(
            _snapshotGenerationFailedKey(transport)) ??
        '';
    final failedAtRaw = LocalDatabaseService.getString(
            _snapshotGenerationFailedAtKey(transport)) ??
        '';
    final failedAt = DateTime.tryParse(failedAtRaw);
    if (failed.trim() == remote &&
        failedAt != null &&
        DateTime.now().difference(failedAt) < const Duration(minutes: 2)) {
      return false;
    }
    return true;
  }

  Future<void> _markHostSnapshotGenerationApplied(
      String transport, dynamic source) async {
    String generation = '';
    if (source is Map<String, dynamic>) {
      generation = _remoteHostSnapshotGeneration(source);
    }
    if (generation.isEmpty) return;
    final commandId = source is Map<String, dynamic>
        ? _remoteHostRestoreCommandId(source)
        : '';
    await LocalDatabaseService.setString(
        _snapshotGenerationKey(transport), generation);
    if (commandId.isNotEmpty) {
      await LocalDatabaseService.setString(
          _restoreCommandExecutedKey(transport), commandId);
      await LocalDatabaseService.deleteString(
          _restoreCommandInProgressKey(transport));
    }
    await LocalDatabaseService.deleteString(
        _snapshotGenerationInProgressKey(transport));
    await LocalDatabaseService.deleteString(
        _snapshotGenerationInProgressAtKey(transport));
    await LocalDatabaseService.deleteString(
        _snapshotGenerationFailedKey(transport));
    await LocalDatabaseService.deleteString(
        _snapshotGenerationFailedAtKey(transport));
  }

  Future<bool> _beginHostSnapshotGenerationRebuild(
    String transport,
    String generation, {
    String commandId = '',
  }) async {
    if (generation.isEmpty) return false;
    final applied =
        LocalDatabaseService.getString(_snapshotGenerationKey(transport)) ?? '';
    if (applied.trim() == generation && commandId.trim().isEmpty) {
      return false;
    }
    final lockId = _snapshotGenerationLockId(transport, generation);
    if (!_activeSnapshotGenerationRebuilds.add(lockId)) return false;
    await LocalDatabaseService.setString(
        _snapshotGenerationInProgressKey(transport), generation);
    final effectiveCommandId =
        commandId.trim().isEmpty ? generation : commandId.trim();
    if (effectiveCommandId.isNotEmpty) {
      await LocalDatabaseService.setString(
          _restoreCommandInProgressKey(transport), effectiveCommandId);
    }
    await LocalDatabaseService.setString(
        _snapshotGenerationInProgressAtKey(transport),
        DateTime.now().toIso8601String());
    return true;
  }

  Future<void> _finishHostSnapshotGenerationRebuild(
    String transport,
    String generation, {
    required bool success,
  }) async {
    if (generation.isEmpty) return;
    final lockId = _snapshotGenerationLockId(transport, generation);
    _activeSnapshotGenerationRebuilds.remove(lockId);
    if (success) {
      await LocalDatabaseService.setString(
          _snapshotGenerationKey(transport), generation);
      final inProgressCommand = LocalDatabaseService.getString(
              _restoreCommandInProgressKey(transport)) ??
          '';
      if (inProgressCommand.trim().isNotEmpty) {
        await LocalDatabaseService.setString(
            _restoreCommandExecutedKey(transport), inProgressCommand.trim());
        await LocalDatabaseService.deleteString(
            _restoreCommandInProgressKey(transport));
      }
      await LocalDatabaseService.deleteString(
          _snapshotGenerationInProgressKey(transport));
      await LocalDatabaseService.deleteString(
          _snapshotGenerationInProgressAtKey(transport));
      await LocalDatabaseService.deleteString(
          _snapshotGenerationFailedKey(transport));
      await LocalDatabaseService.deleteString(
          _snapshotGenerationFailedAtKey(transport));
    } else {
      await LocalDatabaseService.deleteString(
          _snapshotGenerationInProgressKey(transport));
      await LocalDatabaseService.deleteString(
          _snapshotGenerationInProgressAtKey(transport));
      await LocalDatabaseService.setString(
          _snapshotGenerationFailedKey(transport), generation);
      await LocalDatabaseService.setString(
          _snapshotGenerationFailedAtKey(transport),
          DateTime.now().toIso8601String());
      await LocalDatabaseService.deleteString(
          _restoreCommandInProgressKey(transport));
    }
  }

  Future<LanSyncResult?> _rebuildIfHostSnapshotGenerationChanged(
    String host,
    int port,
    String token,
    Map<String, dynamic> decodedPull, {
    LanSyncProgressCallback? onProgress,
  }) async {
    if (!_needsHostSnapshotGenerationRebuild('lan', decodedPull)) return null;
    final generation = _remoteHostSnapshotGeneration(decodedPull);
    final commandId = _remoteHostRestoreCommandId(decodedPull);
    if (!await _beginHostSnapshotGenerationRebuild(
      'lan',
      generation,
      commandId: commandId,
    )) {
      return null;
    }
    LanSyncResult result;
    try {
      onProgress?.call(
          0.72, 'Host restore detected. Rebuilding from LAN Host snapshot...');
      final settings = LanSyncSettings.load();
      await settings.copyWith(clearLastPullCursor: true).save();
      await SyncDeviceStateStore.resetClientProgress(store.appIdentity,
          transport: 'lan');
      result = await repairFromHostSnapshot(
        host,
        port: port,
        token: token,
        onProgress: onProgress,
      );
      await _finishHostSnapshotGenerationRebuild(
        'lan',
        generation,
        success: result.ok,
      );
    } catch (_) {
      await _finishHostSnapshotGenerationRebuild(
        'lan',
        generation,
        success: false,
      );
      rethrow;
    }
    return result;
  }

  bool get isHosting => _sharedServer != null;
  int? get port => _sharedPort;

  Future<void> startHost({int port = 8787}) async {
    await _ensureHostRegistryMigration();
    if (_sharedServer != null && _sharedPort == port) return;
    await stopHost();
    _sharedServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _sharedPort = port;
    _sharedServer!.listen(_handleRequest, onError: (_) {});
  }

  Future<void> _ensureHostRegistryMigration() async {
    final settings = LanSyncSettings.load();
    final hostDeviceId = store.deviceId.trim();
    if (!settings.hostRegistryNeedsMigration(hostDeviceId)) return;
    await settings.withMigratedHostRegistry(hostDeviceId).save();
  }

  Future<void> stopHost() async {
    await _sharedServer?.close(force: true);
    _sharedServer = null;
    _sharedPort = null;
  }

  bool _authorized(HttpRequest request, LanSyncSettings settings) {
    final deviceId = request.headers.value('x-device-id')?.trim() ?? '';
    final deviceToken = request.headers.value('x-device-token')?.trim() ?? '';
    if (deviceId.isEmpty || deviceToken.isEmpty) return false;
    if (SyncDeviceAccessStore.isSuspended(deviceId) ||
        SyncDeviceAccessStore.isDeleted(deviceId) ||
        SyncDeviceAccessStore.isWipePending(deviceId)) {
      return false;
    }
    final expected = settings.pairedDevices[deviceId]?.trim() ?? '';
    return expected.isNotEmpty && expected == deviceToken;
  }

  bool _deviceCanReceiveWipe(HttpRequest request) {
    final deviceId = request.headers.value('x-device-id')?.trim() ?? '';
    final deviceToken = request.headers.value('x-device-token')?.trim() ?? '';
    return (SyncDeviceAccessStore.isWipePending(deviceId) &&
            SyncDeviceAccessStore.wipePendingTokenMatches(
                deviceId, deviceToken)) ||
        (SyncDeviceAccessStore.isDeleted(deviceId) &&
            SyncDeviceAccessStore.deletedTokenMatches(deviceId, deviceToken));
  }

  Future<bool> _handleBlockedDevice(
      HttpRequest request, LanSyncSettings settings) async {
    final deviceId = request.headers.value('x-device-id')?.trim() ?? '';
    if (deviceId.isEmpty) return false;
    if ((SyncDeviceAccessStore.isWipePending(deviceId) ||
            SyncDeviceAccessStore.isDeleted(deviceId)) &&
        _deviceCanReceiveWipe(request)) {
      await _json(
          request,
          {
            'ok': false,
            'action': 'wipe_local_data',
            'wipeRequired': true,
            'error':
                'This device was deleted by the Host. Local data must be wiped.',
          },
          status: HttpStatus.gone);
      return true;
    }
    if (SyncDeviceAccessStore.isSuspended(deviceId)) {
      await _json(
          request,
          {
            'ok': false,
            'action': 'suspended',
            'suspended': true,
            'error':
                'This device is suspended by the Host. Resume it from Sync Monitoring to continue.',
          },
          status: HttpStatus.forbidden);
      return true;
    }
    return false;
  }

  String _maskedToken(String? token) {
    final value = (token ?? '').trim();
    if (value.isEmpty) return '<empty>';
    if (value.length <= 4) return '****';
    return '${value.substring(0, 2)}****${value.substring(value.length - 2)}';
  }

  Future<void> _json(HttpRequest request, Object payload,
      {int status = HttpStatus.ok}) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(payload));
    await request.response.close();
  }

  Map<String, dynamic> _currentLanSnapshotEnvelope({bool force = false}) {
    final now = DateTime.now();
    final cached = _snapshotTransferCache;
    final age = _snapshotTransferCacheAt == null
        ? const Duration(days: 1)
        : now.difference(_snapshotTransferCacheAt!);
    if (!force && cached != null && age < const Duration(minutes: 5)) {
      return cached;
    }
    final envelope = store.exportUnifiedSnapshotEnvelope(
      kind: 'full_store',
      maxItemsPerChunk: 300,
    );
    _snapshotTransferCache = envelope;
    _snapshotTransferCacheAt = now;
    return envelope;
  }

  Map<String, dynamic> _snapshotManifestResponse({bool force = false}) {
    final envelope = _currentLanSnapshotEnvelope(force: force);
    return <String, dynamic>{
      'ok': true,
      'snapshotFormat': envelope['snapshotFormat'],
      'snapshotVersion': envelope['snapshotVersion'],
      'snapshotKind': envelope['snapshotKind'],
      'snapshotManifest': envelope['snapshotManifest'],
      'totalChunks': envelope['totalChunks'],
      'syncGeneratedAt': envelope['syncGeneratedAt'],
      'syncGeneratedSequence': envelope['syncGeneratedSequence'],
      'hostSnapshotGeneration': envelope['hostSnapshotGeneration'],
      'snapshotGeneration': envelope['snapshotGeneration'],
      'hostRestoreCommandId': envelope['hostRestoreCommandId'],
      'restoreCommandId': envelope['restoreCommandId'],
    };
  }

  Map<String, dynamic> _lanSignalPayload({
    DateTime? since,
    int sinceSequence = 0,
  }) {
    final decoded = jsonDecode(store.exportSyncChangesJson(
        since: since, sinceSequence: sinceSequence)) as Map<String, dynamic>;
    final changes = decoded['changes'] as List<dynamic>? ?? const <dynamic>[];
    return {
      'ok': true,
      'changed': changes.isNotEmpty,
      'changeCount': changes.length,
      'latestSequence':
          int.tryParse(decoded['generatedSequence']?.toString() ?? '') ?? 0,
      'generatedAt': decoded['generatedAt']?.toString() ??
          DateTime.now().toIso8601String(),
      'serverTime': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.headers.add('Access-Control-Allow-Headers',
          'Content-Type, X-Device-Id, X-Device-Token, X-Device-Role');
      request.response.headers
          .add('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');

      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }

      final settings = LanSyncSettings.load();
      final receivedDeviceId = request.headers.value('x-device-id');
      final receivedDeviceToken = request.headers.value('x-device-token');

      if (request.method == 'POST' && request.uri.path == '/pairing/claim') {
        final body = await utf8.decoder.bind(request).join();
        final decoded = body.trim().isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(body) as Map);
        final code =
            (decoded['code'] ?? decoded['pairingCode'] ?? '').toString().trim();
        final currentCode = settings.secret.trim();
        if (currentCode.isEmpty || code.isEmpty || code != currentCode) {
          await _json(request,
              {'ok': false, 'error': 'Invalid or expired LAN pairing code.'},
              status: HttpStatus.unauthorized);
          return;
        }

        final requestedDeviceId = (decoded['deviceId'] ?? '').toString().trim();
        final deviceId = requestedDeviceId.isNotEmpty
            ? requestedDeviceId
            : AppIdentity.defaults(
                    deviceId: '', platform: AppPlatformType.unknown)
                .deviceId;
        final deviceToken = LanSyncSettings.generateDeviceToken();
        final paired = Map<String, String>.from(settings.pairedDevices);
        paired[deviceId] = deviceToken;
        final registry = HostRegistryDevice.migrateFromPairedDevices(
          paired,
          existing: settings.hostRegistry,
          hostDeviceId: store.deviceId,
        );

        // Single-use LAN pairing: immediately clear the pairing code after the
        // oldest successful claim is accepted. Later claims with the same code fail.
        await settings
            .copyWith(secret: '', pairedDevices: paired, hostRegistry: registry)
            .save();

        final snapshotInfo = _snapshotManifestResponse(force: true);
        await _json(request, {
          'ok': true,
          'message': 'LAN device paired successfully.',
          'deviceId': deviceId,
          'deviceToken': deviceToken,
          'storeId': store.appIdentity.storeId,
          'branchId': store.appIdentity.branchId,
          'hostDeviceId': store.deviceId,
          'snapshotAvailable': true,
          'snapshotManifest': snapshotInfo['snapshotManifest'],
          'totalChunks': snapshotInfo['totalChunks'],
          'syncGeneratedAt': snapshotInfo['syncGeneratedAt'],
          'syncGeneratedSequence': snapshotInfo['syncGeneratedSequence'],
        });
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/device-wipe-ack') {
        final body = await utf8.decoder.bind(request).join();
        final decoded = body.trim().isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(body) as Map);
        final clientDeviceId =
            (decoded['deviceId'] ?? receivedDeviceId ?? '').toString().trim();
        final deviceToken =
            (decoded['deviceToken'] ?? receivedDeviceToken ?? '')
                .toString()
                .trim();
        if (clientDeviceId.isEmpty ||
            !SyncDeviceAccessStore.wipePendingTokenMatches(
                clientDeviceId, deviceToken)) {
          await _json(
              request, {'ok': false, 'error': 'Invalid wipe acknowledgement.'},
              status: HttpStatus.unauthorized);
          return;
        }
        // Fix #11: ACK confirms the client received the wipe command, but it
        // must not automatically remove the device from the Host list. The row
        // remains Wipe Pending until the admin presses Permanent Delete.
        await _json(request, {
          'ok': true,
          'wipeConfirmed': true,
          'serverTime': DateTime.now().toIso8601String()
        });
        return;
      }

      if (!_authorized(request, settings)) {
        if (await _handleBlockedDevice(request, settings)) return;
        // Keep a safe log for troubleshooting LAN/Host pairing problems without printing full tokens.
        developer.log(
          'LAN SYNC AUTH FAILED: path=${request.uri.path} '
          "from=${request.connectionInfo?.remoteAddress.address ?? 'unknown'} "
          'deviceId=${receivedDeviceId ?? '<empty>'} token=${_maskedToken(receivedDeviceToken)}',
          name: 'ventio.lan_sync',
        );
        await _json(
          request,
          {
            'ok': false,
            'error':
                'Unauthorized LAN device token. Please re-pair this Client with the Host.',
          },
          status: HttpStatus.unauthorized,
        );
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/health') {
        await _json(request, {
          'ok': true,
          'mode': 'host',
          'deviceId': store.deviceId,
          'pending': store.pendingSyncCount,
          'generatedAt': DateTime.now().toIso8601String(),
        });
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/changes/signal') {
        final since =
            DateTime.tryParse(request.uri.queryParameters['since'] ?? '');
        final sinceSequence =
            int.tryParse(request.uri.queryParameters['since_sequence'] ?? '') ??
                0;
        final waitSeconds =
            (int.tryParse(request.uri.queryParameters['wait_seconds'] ?? '') ??
                    25)
                .clamp(1, 25);
        final deadline =
            DateTime.now().add(Duration(seconds: waitSeconds.toInt()));
        while (true) {
          final payload =
              _lanSignalPayload(since: since, sinceSequence: sinceSequence);
          if (payload['changed'] == true || DateTime.now().isAfter(deadline)) {
            await _json(request, payload);
            return;
          }
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }

      if (request.method == 'GET' && request.uri.path == '/snapshot/manifest') {
        final force = request.uri.queryParameters['force'] == '1';
        await _json(request, _snapshotManifestResponse(force: force));
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/snapshot/chunk') {
        final ordinal =
            int.tryParse(request.uri.queryParameters['ordinal'] ?? '') ?? -1;
        final envelope = _currentLanSnapshotEnvelope();
        final chunks =
            (envelope['snapshotChunks'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false);
        if (ordinal < 0 || ordinal >= chunks.length) {
          await _json(
              request, {'ok': false, 'error': 'Snapshot chunk not found.'},
              status: HttpStatus.notFound);
          return;
        }
        await _json(request, {
          'ok': true,
          'chunk': chunks[ordinal],
          'ordinal': ordinal,
          'totalChunks': chunks.length,
          'snapshotManifest': envelope['snapshotManifest'],
          'syncGeneratedAt': envelope['syncGeneratedAt'],
          'syncGeneratedSequence': envelope['syncGeneratedSequence'],
        });
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/snapshot') {
        request.response.headers.contentType = ContentType.json;
        request.response
            .write(jsonEncode(_currentLanSnapshotEnvelope(force: true)));
        await request.response.close();
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/changes/pull') {
        final since =
            DateTime.tryParse(request.uri.queryParameters['since'] ?? '');
        final sinceSequence =
            int.tryParse(request.uri.queryParameters['since_sequence'] ?? '') ??
                0;
        // Pull is delivery only. The Host must not mark changes as applied or
        // ACKed until the Client posts /changes/ack after local apply succeeds.
        request.response.headers.contentType = ContentType.json;
        request.response.write(store.exportSyncChangesJson(
            since: since, sinceSequence: sinceSequence));
        await request.response.close();
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/changes/ack') {
        final body = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final clientDeviceId =
            decoded['deviceId']?.toString() ?? receivedDeviceId ?? '';
        final clientDeviceName = decoded['deviceName']?.toString() ?? '';
        _updateHostRegistryDeviceName(clientDeviceId, clientDeviceName);
        final cursor = DateTime.tryParse(
            decoded['lastAppliedCursor']?.toString() ??
                decoded['lastAckCursor']?.toString() ??
                '');
        final sequence = int.tryParse(
                decoded['lastAppliedSequence']?.toString() ??
                    decoded['lastAckSequence']?.toString() ??
                    '') ??
            0;
        await SyncDeviceStateStore.recordPeerSyncResult(
          deviceId: clientDeviceId,
          transport: 'lan',
          appliedCursor: cursor,
          ackCursor: cursor,
          appliedSequence: sequence,
          ackSequence: sequence,
        );
        await store.compactSyncedSyncHistoryForMaintenance();
        await _json(request,
            {'ok': true, 'serverTime': DateTime.now().toIso8601String()});
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/changes/push') {
        final body = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final changes = (decoded['changes'] as List<dynamic>? ?? [])
            .map((item) =>
                SyncChange.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
        if (changes.any((item) =>
            item.entityType == 'system' &&
            item.operation == 'reset_store_data')) {
          await _json(
              request,
              {
                'ok': false,
                'error': 'Reset data can only be initiated on the Host device.'
              },
              status: HttpStatus.forbidden);
          return;
        }
        final clientCursor =
            DateTime.tryParse(decoded['cursor']?.toString() ?? '');
        final clientSequence = int.tryParse(decoded['sequence']?.toString() ??
                decoded['lastAppliedSequence']?.toString() ??
                '') ??
            0;
        final accepted = await _syncCore.acceptClientChangesOnHost(
          changes,
          mirrorToCloud:
              store.appIdentity.isCloudEnabled && store.appIdentity.isHost,
        );
        final clientDeviceId =
            decoded['deviceId']?.toString() ?? receivedDeviceId ?? '';
        final clientDeviceName = decoded['deviceName']?.toString() ?? '';
        _updateHostRegistryDeviceName(clientDeviceId, clientDeviceName);
        await SyncDeviceStateStore.recordPeerSyncResult(
          deviceId: clientDeviceId,
          transport: 'lan',
          ackCursor: clientCursor,
          ackSequence: clientSequence,
        );
        await _json(request, {
          'ok': true,
          // Acknowledge all received IDs. Changes older than the latest Host reset
          // are intentionally discarded so stale offline client data cannot revive
          // deleted business data after a central reset.
          'ackIds': accepted.ackIds,
          'rejected': accepted.rejected.entries
              .map((entry) => {'id': entry.key, 'reason': entry.value})
              .toList(),
          'serverTime': DateTime.now().toIso8601String(),
          'discardedBecauseOfReset': accepted.discardedBecauseOfReset,
        });
        return;
      }

      // Legacy LAN Sync V1 endpoints are intentionally disabled.
      // Stage 4 keeps all LAN synchronization on the unified /changes/* protocol
      // so old clients cannot merge snapshots directly into Host data.
      if ((request.method == 'GET' && request.uri.path == '/pull') ||
          (request.method == 'POST' && request.uri.path == '/sync')) {
        await _json(
          request,
          {
            'ok': false,
            'error':
                'Legacy LAN sync endpoint disabled. Use /changes/push and /changes/pull.',
          },
          status: HttpStatus.gone,
        );
        return;
      }

      await _json(request, {'ok': false, 'error': 'Not found'},
          status: HttpStatus.notFound);
    } catch (error) {
      try {
        await _json(request, {'ok': false, 'error': error.toString()},
            status: HttpStatus.internalServerError);
      } catch (_) {}
    }
  }

  HttpClient _client() =>
      HttpClient()..connectionTimeout = const Duration(seconds: 15);

  void _attachToken(HttpClientRequest request, String token,
      {String? deviceId}) {
    final identity = store.appIdentity;
    final headerDeviceId = (deviceId ?? identity.deviceId).trim();
    final headerToken =
        token.trim().isNotEmpty ? token.trim() : identity.deviceToken.trim();
    if (headerDeviceId.isNotEmpty && headerToken.isNotEmpty) {
      request.headers.add('X-Device-Id', headerDeviceId);
      request.headers.add('X-Device-Token', headerToken);
      request.headers.add('X-Device-Role', identity.deviceRole.name);
    }
  }

  Future<LanSyncResult> claimPairingCode(String host,
      {int port = 8787,
      required String code,
      LanSyncProgressCallback? onProgress}) async {
    final identity = store.appIdentity;
    if (identity.isHost) {
      return const LanSyncResult(
          ok: false,
          message:
              'Host devices cannot pair as LAN Clients. Use Transfer Host instead.');
    }
    // A Client may configure both LAN and Cloud transports. Pairing LAN only
    // prepares another delivery method; the active transport still decides
    // which one auto-sync runs.
    try {
      onProgress?.call(0.08, 'Connecting to LAN Host...');
      final client = _client();
      onProgress?.call(0.14, 'Verifying LAN pairing code...');
      final request = await client.post(host.trim(), port, '/pairing/claim');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'code': code.trim(),
        'deviceId': store.deviceId,
        'deviceName': store.appIdentity.deviceName,
        'platform': store.appIdentity.platform.name,
      }));
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      client.close(force: true);
      if (response.statusCode != 200) {
        return const LanSyncResult(
            ok: false,
            message:
                'Pairing code expired or already used. Ask the Host device for a new code.');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (decoded['ok'] != true) {
        return LanSyncResult(
            ok: false,
            message: decoded['error']?.toString() ?? 'LAN pairing failed.');
      }
      final claimedStoreId = decoded['storeId']?.toString() ?? identity.storeId;
      final claimedBranchId =
          decoded['branchId']?.toString() ?? identity.branchId;
      final claimedHostDeviceId =
          decoded['hostDeviceId']?.toString() ?? identity.hostDeviceId;
      if (identity.isClient && identity.hostDeviceId.trim().isNotEmpty) {
        final mismatches = <String>[];
        if (identity.storeId.trim().toUpperCase() !=
            claimedStoreId.trim().toUpperCase()) {
          mismatches.add('Store ID');
        }
        if (identity.branchId.trim().toUpperCase() !=
            claimedBranchId.trim().toUpperCase()) {
          mismatches.add('Branch ID');
        }
        if (identity.hostDeviceId.trim().toUpperCase() !=
            claimedHostDeviceId.trim().toUpperCase()) {
          mismatches.add('Host ID');
        }
        if (mismatches.isNotEmpty) {
          return LanSyncResult(
              ok: false,
              message:
                  'LAN pairing belongs to a different Store (${mismatches.join(', ')}). Use the current Host pairing code.');
        }
      }

      final current = store.appIdentity;
      final pairedDeviceId =
          decoded['deviceId']?.toString() ?? current.deviceId;
      final pairedDeviceToken =
          decoded['deviceToken']?.toString() ?? current.deviceToken;
      onProgress?.call(0.22, 'Registering this device...');
      await store.updateAppIdentityDuringSetup(current.copyWith(
        storeId: claimedStoreId,
        branchId: claimedBranchId,
        deviceId: pairedDeviceId,
        deviceRole: DeviceRole.client,
        syncMode: SyncMode.lanOnly,
        activeSyncTransport: 'lan',
        hostDeviceId: claimedHostDeviceId,
        deviceToken: pairedDeviceToken,
      ));
      final snapshotEnvelope = await _downloadLanSnapshotEnvelope(
        host,
        port: port,
        token: pairedDeviceToken,
        deviceId: pairedDeviceId,
        force: false,
        onProgress: onProgress,
      );
      final snapshot = jsonEncode(snapshotEnvelope);
      onProgress?.call(0.74, 'Importing LAN snapshot chunks locally...');
      await store.importSyncSnapshotJson(snapshot);
      await _markHostSnapshotGenerationApplied('lan', snapshotEnvelope);
      final hostCursor = store.syncSnapshotGeneratedAtFromJson(snapshot);
      final settings = LanSyncSettings.load();
      await settings
          .copyWith(
            host: host.trim(),
            port: port,
            mode: LanSyncDeviceMode.client,
            hostModeEnabled: false,
            setupComplete: true,
            autoSyncEnabled: true,
            secret: '',
            lastPullCursor: hostCursor,
            lastConnectionAt: DateTime.now(),
            lastSyncAt: DateTime.now(),
          )
          .save();
      await SyncDeviceStateStore.recordSyncResult(store.appIdentity,
          transport: 'lan', appliedCursor: hostCursor, ackCursor: hostCursor);
      onProgress?.call(1.0, 'LAN snapshot is ready.');
      return const LanSyncResult(ok: true, message: 'LAN pairing completed.');
    } catch (error) {
      return LanSyncResult(ok: false, message: 'LAN pairing failed: $error');
    }
  }

  Future<LanSyncResult> testConnection(String host,
      {int port = 8787, String token = ''}) async {
    try {
      final client = _client();
      final request = await client.get(host.trim(), port, '/health');
      _attachToken(request, token);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      client.close(force: true);
      return LanSyncResult(
          ok: response.statusCode == 200,
          message: response.statusCode == 200
              ? 'Connection is healthy.'
              : 'Host returned ${response.statusCode}: $body');
    } catch (error) {
      return LanSyncResult(ok: false, message: 'Connection failed: $error');
    }
  }

  Future<Map<String, dynamic>> _downloadLanSnapshotEnvelope(
    String host, {
    int port = 8787,
    String token = '',
    String? deviceId,
    bool force = false,
    LanSyncProgressCallback? onProgress,
  }) {
    return const UnifiedSnapshotTransferService().downloadEnvelope(
      _LanSnapshotPullTransport(
        host: host,
        port: port,
        token: token,
        deviceId: deviceId ?? store.appIdentity.deviceId,
        attachToken: _attachToken,
        newClient: _client,
      ),
      force: force,
      labelPrefix: 'LAN snapshot',
      onProgress: onProgress,
    );
  }

  Future<LanSyncResult> initialClone(String host,
      {int port = 8787,
      String token = '',
      LanSyncProgressCallback? onProgress}) async {
    try {
      onProgress?.call(0.10, 'Connecting to LAN Host snapshot...');
      final snapshotEnvelope = await _downloadLanSnapshotEnvelope(
        host,
        port: port,
        token: token,
        force: true,
        onProgress: onProgress,
      );
      final snapshot = jsonEncode(snapshotEnvelope);
      onProgress?.call(0.72, 'Applying LAN snapshot chunks locally...');
      await store.importSyncSnapshotJson(snapshot);
      await _markHostSnapshotGenerationApplied('lan', snapshotEnvelope);
      final hostCursor = store.syncSnapshotGeneratedAtFromJson(snapshot);
      final settings = LanSyncSettings.load();
      onProgress?.call(0.94, 'Saving LAN sync cursor...');
      await settings
          .copyWith(
              lastPullCursor: hostCursor,
              lastConnectionAt: DateTime.now(),
              lastSyncAt: DateTime.now())
          .save();
      final hostSequence =
          store.syncSnapshotGeneratedSequenceFromJson(snapshot);
      await SyncDeviceStateStore.recordSyncResult(store.appIdentity,
          transport: 'lan',
          appliedCursor: hostCursor,
          ackCursor: hostCursor,
          appliedSequence: hostSequence,
          ackSequence: hostSequence);
      await _sendLanAck(host,
          port: port, token: token, cursor: hostCursor, sequence: hostSequence);
      return const LanSyncResult(
          ok: true,
          message: 'Initial clone completed from LAN snapshot chunks.');
    } catch (error) {
      return LanSyncResult(ok: false, message: 'Initial clone failed: $error');
    }
  }

  Future<LanSyncResult> pullNow(String host,
      {int port = 8787, String token = ''}) async {
    try {
      final snapshotEnvelope = await _downloadLanSnapshotEnvelope(
        host,
        port: port,
        token: token,
        force: true,
      );
      final snapshot = jsonEncode(snapshotEnvelope);
      await store.importSyncSnapshotJson(snapshot);
      await _markHostSnapshotGenerationApplied('lan', snapshotEnvelope);
      final hostCursor = store.syncSnapshotGeneratedAtFromJson(snapshot);
      final settings = LanSyncSettings.load();
      await settings
          .copyWith(
              lastPullCursor: hostCursor,
              lastConnectionAt: DateTime.now(),
              lastSyncAt: DateTime.now())
          .save();
      return const LanSyncResult(
          ok: true, message: 'Pull completed from LAN snapshot chunks.');
    } catch (error) {
      return LanSyncResult(ok: false, message: 'Pull failed: $error');
    }
  }

  Future<LanSyncResult> repairFromHostSnapshot(String host,
      {int port = 8787,
      String token = '',
      LanSyncProgressCallback? onProgress}) async {
    if (store.appIdentity.isHost) {
      return const LanSyncResult(
          ok: false,
          message:
              'Host devices cannot rebuild from LAN Host snapshots. Use Transfer Host instead.');
    }
    try {
      onProgress?.call(0.10, 'Connecting to LAN Host snapshot...');
      final snapshotEnvelope = await _downloadLanSnapshotEnvelope(
        host,
        port: port,
        token: token,
        force: true,
        onProgress: onProgress,
      );
      final snapshot = jsonEncode(snapshotEnvelope);
      onProgress?.call(0.72, 'Applying LAN snapshot chunks locally...');
      await store.importSyncSnapshotJson(snapshot);
      await _markHostSnapshotGenerationApplied('lan', snapshotEnvelope);
      onProgress?.call(0.86, 'Marking rebuilt data as synced...');
      await store.markAllSyncChangesSynced();
      final hostCursor = store.syncSnapshotGeneratedAtFromJson(snapshot);
      final settings = LanSyncSettings.load();
      await settings
          .copyWith(
              lastPullCursor: hostCursor,
              lastConnectionAt: DateTime.now(),
              lastSyncAt: DateTime.now())
          .save();
      final hostSequence =
          store.syncSnapshotGeneratedSequenceFromJson(snapshot);
      await SyncDeviceStateStore.recordSyncResult(store.appIdentity,
          transport: 'lan',
          appliedCursor: hostCursor,
          ackCursor: hostCursor,
          appliedSequence: hostSequence,
          ackSequence: hostSequence);
      await _sendLanAck(host,
          port: port, token: token, cursor: hostCursor, sequence: hostSequence);
      onProgress?.call(0.94, 'Running Client sync log maintenance...');
      await store.compactClientSyncedSyncHistoryForMaintenance();
      onProgress?.call(1.0, 'LAN rebuild completed.');
      return const LanSyncResult(
          ok: true, message: 'LAN rebuild completed from snapshot chunks.');
    } catch (error) {
      return LanSyncResult(
          ok: false, message: 'Repair snapshot failed: $error');
    }
  }

  void _updateHostRegistryDeviceName(String deviceId, String deviceName) {
    final cleanId = deviceId.trim();
    final cleanName = deviceName.trim();
    if (cleanId.isEmpty || cleanName.isEmpty) return;
    final settings = LanSyncSettings.load();
    final existing = settings.hostRegistry[cleanId];
    if (existing == null || existing.deviceName.trim() == cleanName) return;
    final registry =
        Map<String, HostRegistryDevice>.from(settings.hostRegistry);
    registry[cleanId] = existing.copyWith(
      deviceName: cleanName,
      lastSeenAt: DateTime.now(),
    );
    settings.copyWith(hostRegistry: Map.unmodifiable(registry)).save();
  }

  Map<String, String> _decodeRejectedSyncRequests(dynamic raw) {
    final output = <String, String>{};
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final id = (item['id'] ?? '').toString();
          if (id.isNotEmpty) {
            output[id] = (item['reason'] ?? 'Rejected by Host.').toString();
          }
        }
      }
    }
    return output;
  }

  Future<LanSyncResult?> _handleLanAccessResponse(int statusCode, String body,
      {required String host, int port = 8787, String token = ''}) async {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (decoded['wipeRequired'] == true ||
          decoded['action'] == 'wipe_local_data') {
        final wipedDeviceId = store.deviceId;
        final wipedStoreId = store.appIdentity.storeId;
        final wipedBranchId = store.appIdentity.branchId;
        final wipedToken = store.appIdentity.deviceToken;
        await _confirmLanWipe(host,
            port: port,
            token: token,
            storeId: wipedStoreId,
            branchId: wipedBranchId,
            deviceId: wipedDeviceId,
            deviceToken: wipedToken);
        await store.factoryResetLocalDevice();
        return const LanSyncResult(
            ok: false,
            message: 'Device deleted by Host. Local data was wiped.');
      }
      if (decoded['suspended'] == true || decoded['action'] == 'suspended') {
        final reason =
            decoded['error']?.toString() ?? 'Device is suspended by Host.';
        await store.markSuspendedByHost(reason: reason);
        return LanSyncResult(ok: false, message: reason);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _confirmLanWipe(
    String host, {
    int port = 8787,
    String token = '',
    required String storeId,
    required String branchId,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final client = _client();
      final request = await client.post(host.trim(), port, '/device-wipe-ack');
      _attachToken(request, token);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'storeId': storeId,
        'branchId': branchId,
        'deviceId': deviceId,
        'deviceToken': deviceToken,
      }));
      await request.close().timeout(const Duration(seconds: 10));
      client.close(force: true);
    } catch (_) {
      // Keep wipe pending on the Host if the ACK cannot be delivered.
      // The next sync contact will receive the wipe command again.
    }
  }

  Future<void> _sendLanAck(String host,
      {int port = 8787,
      String token = '',
      required DateTime cursor,
      int sequence = 0}) async {
    try {
      final client = _client();
      final request = await client.post(host.trim(), port, '/changes/ack');
      _attachToken(request, token);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'deviceId': store.deviceId,
        'storeId': store.appIdentity.storeId,
        'branchId': store.appIdentity.branchId,
        'deviceName': store.appIdentity.deviceName,
        'lastAppliedCursor': cursor.toIso8601String(),
        'lastAckCursor': cursor.toIso8601String(),
        'lastAppliedSequence': sequence,
        'lastAckSequence': sequence,
      }));
      await request.close();
      client.close(force: true);
    } catch (_) {
      // ACK is best-effort; the next LAN pull/heartbeat can repair Host visibility.
    }
  }

  Future<LanSyncResult> pushPendingOnly(String host,
      {int port = 8787,
      String token = '',
      LanSyncProgressCallback? onProgress}) async {
    final pending = _syncCore.pendingChangesForTarget('host');
    final pendingIds = _syncCore.changeIds(pending);
    if (pending.isEmpty) {
      return const LanSyncResult(ok: true, message: 'No LAN changes to push.');
    }
    try {
      final client = _client();
      onProgress?.call(
          0.18, 'Preparing ${pending.length} local change(s) for LAN push...');
      await _syncCore.markPushInProgress(pendingIds);
      final pushRequest = await client.post(host.trim(), port, '/changes/push');
      _attachToken(pushRequest, token);
      pushRequest.headers.contentType = ContentType.json;
      pushRequest.write(jsonEncode({
        'deviceId': store.deviceId,
        'storeId': store.appIdentity.storeId,
        'branchId': store.appIdentity.branchId,
        'deviceName': store.appIdentity.deviceName,
        'cursor': LanSyncSettings.load().lastPullCursor?.toIso8601String(),
        'sequence':
            SyncDeviceStateStore.load(store.appIdentity).lastAppliedSequence,
        'changes': pending.map((item) => item.toJson()).toList(),
      }));
      final pushResponse = await pushRequest.close();
      final pushBody = await utf8.decoder.bind(pushResponse).join();
      client.close(force: true);
      if (pushResponse.statusCode != 200) {
        final access = await _handleLanAccessResponse(
            pushResponse.statusCode, pushBody,
            host: host, port: port, token: token);
        if (access != null) return access;
        final message = 'Push failed: ${pushResponse.statusCode} $pushBody';
        await _syncCore.markPushFailed(pendingIds, message);
        return LanSyncResult(ok: false, message: message);
      }
      final decoded = jsonDecode(pushBody) as Map<String, dynamic>;
      final ackIds = (decoded['ackIds'] as List<dynamic>? ?? [])
          .map((item) => '$item')
          .toList();
      final rejected = _decodeRejectedSyncRequests(decoded['rejected']);
      if (rejected.isNotEmpty) await _syncCore.markPushRejected(rejected);
      await _syncCore.markPushSubmitted(ackIds, fallbackIds: pendingIds);
      await store.clearSuspendedByHost();
      return LanSyncResult(
          ok: true,
          message: 'LAN push completed. Pushed ${pending.length} change(s).');
    } catch (error) {
      await _syncCore.markPushFailed(pendingIds, error.toString());
      return LanSyncResult(ok: false, message: 'LAN push failed: $error');
    }
  }

  Future<bool> waitForRealtimeSignal(String host,
      {int port = 8787,
      String token = '',
      Duration wait = const Duration(seconds: 25)}) async {
    try {
      final settings = LanSyncSettings.load();
      final client = _client();
      final lastSequence =
          SyncDeviceStateStore.load(store.appIdentity).lastAppliedSequence;
      final query = <String, String>{
        'wait_seconds': wait.inSeconds.clamp(1, 25).toString(),
        'since_sequence': lastSequence.toString(),
      };
      if (settings.lastPullCursor != null) {
        query['since'] = settings.lastPullCursor!.toIso8601String();
      }
      final path =
          Uri(path: '/changes/signal', queryParameters: query).toString();
      final request = await client.get(host.trim(), port, path);
      _attachToken(request, token);
      final response =
          await request.close().timeout(wait + const Duration(seconds: 8));
      final body = await utf8.decoder.bind(response).join();
      client.close(force: true);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      return decoded['changed'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<LanSyncResult> pullChangesOnly(String host,
      {int port = 8787,
      String token = '',
      LanSyncProgressCallback? onProgress}) async {
    final settings = LanSyncSettings.load();
    try {
      final client = _client();
      final ackCursor = settings.lastPullCursor?.toIso8601String() ?? '';
      final lastSequence =
          SyncDeviceStateStore.load(store.appIdentity).lastAppliedSequence;
      final seqParam = '&since_sequence=$lastSequence';
      final path = settings.lastPullCursor == null
          ? '/changes/pull?device_id=${Uri.encodeQueryComponent(store.deviceId)}&ack_cursor=${Uri.encodeQueryComponent(ackCursor)}$seqParam'
          : '/changes/pull?device_id=${Uri.encodeQueryComponent(store.deviceId)}&ack_cursor=${Uri.encodeQueryComponent(ackCursor)}&since=${Uri.encodeQueryComponent(settings.lastPullCursor!.toIso8601String())}$seqParam';
      onProgress?.call(0.62, 'Pulling new changes from LAN Host...');
      final pullRequest = await client.get(host.trim(), port, path);
      _attachToken(pullRequest, token);
      final pullResponse = await pullRequest.close();
      final pullBody = await utf8.decoder.bind(pullResponse).join();
      client.close(force: true);
      if (pullResponse.statusCode != 200) {
        final access = await _handleLanAccessResponse(
            pullResponse.statusCode, pullBody,
            host: host, port: port, token: token);
        if (access != null) return access;
        return LanSyncResult(
            ok: false,
            message:
                'Pull changes failed: ${pullResponse.statusCode} $pullBody');
      }
      final decodedPull = jsonDecode(pullBody) as Map<String, dynamic>;
      final generationRebuild = await _rebuildIfHostSnapshotGenerationChanged(
        host,
        port,
        token,
        decodedPull,
        onProgress: onProgress,
      );
      if (generationRebuild != null) return generationRebuild;
      if (decodedPull['needsSnapshot'] == true) {
        final repair = await repairFromHostSnapshot(host,
            port: port, token: token, onProgress: onProgress);
        return repair.ok
            ? LanSyncResult(
                ok: true,
                message: 'LAN event log gap detected. ${repair.message}')
            : LanSyncResult(
                ok: false,
                message:
                    'LAN event log gap detected and repair failed. ${repair.message}');
      }
      final changes = _syncCore.filterOutLocalEchoes(
        _syncCore.decodeRemoteChanges(decodedPull['changes'] as List<dynamic>?),
      );
      final restoreMarker = changes.any((item) =>
          item.entityType == 'system' &&
          item.operation == 'cloud_restore_snapshot_ready');
      if (restoreMarker && store.appIdentity.isClient) {
        final commandId = _restoreCommandIdFromChanges(changes);
        if (_restoreCommandAlreadyExecuted('lan', commandId)) {
          onProgress?.call(0.72,
              'Host restore command already applied. Continuing LAN sync...');
        } else {
          onProgress?.call(0.72,
              'Host restore detected. Rebuilding from LAN Host snapshot...');
          await settings.copyWith(clearLastPullCursor: true).save();
          await SyncDeviceStateStore.resetClientProgress(store.appIdentity,
              transport: 'lan');
          return repairFromHostSnapshot(host,
              port: port, token: token, onProgress: onProgress);
        }
      }
      onProgress?.call(
          0.78, 'Applying ${changes.length} LAN change(s) locally...');
      await _syncCore.applyAuthoritativeChanges(changes);
      final generatedAt =
          DateTime.tryParse(decodedPull['generatedAt'] as String? ?? '') ??
              DateTime.now();
      final generatedSequence =
          int.tryParse(decodedPull['generatedSequence']?.toString() ?? '') ?? 0;
      await settings
          .copyWith(
              lastPullCursor: generatedAt,
              lastConnectionAt: DateTime.now(),
              lastSyncAt: DateTime.now())
          .save();
      await SyncDeviceStateStore.recordSyncResult(store.appIdentity,
          transport: 'lan',
          appliedCursor: generatedAt,
          ackCursor: generatedAt,
          appliedSequence: generatedSequence,
          ackSequence: generatedSequence);
      await _sendLanAck(host,
          port: port,
          token: token,
          cursor: generatedAt,
          sequence: generatedSequence);
      await store.clearSuspendedByHost();
      return LanSyncResult(
          ok: true,
          message: 'LAN pull completed. Pulled ${changes.length} change(s).');
    } catch (error) {
      return LanSyncResult(ok: false, message: 'LAN pull failed: $error');
    }
  }

  Future<LanSyncResult> syncNow(String host,
      {int port = 8787,
      String token = '',
      LanSyncProgressCallback? onProgress}) async {
    final settings = LanSyncSettings.load();
    final pending = _syncCore.pendingChangesForTarget('host');

    // New Client bootstrap must use the Host snapshot, not the incremental
    // event stream. A Host can have valid products/customers/sales that were
    // created before LAN sync was enabled or imported from backup, so pulling
    // only /changes/pull on a fresh cursor can legitimately return zero events
    // and leave the Client empty.
    if (settings.isClient &&
        settings.lastPullCursor == null &&
        pending.isEmpty) {
      return initialClone(host,
          port: port, token: token, onProgress: onProgress);
    }

    final pendingIds = _syncCore.changeIds(pending);
    var pushCompleted = pending.isEmpty;
    try {
      final client = _client();

      if (pending.isNotEmpty) {
        onProgress?.call(0.18,
            'Preparing ${pending.length} local change(s) for LAN push...');
        await _syncCore.markPushInProgress(pendingIds);
        onProgress?.call(0.32, 'Uploading local changes to Host...');
        final pushRequest =
            await client.post(host.trim(), port, '/changes/push');
        _attachToken(pushRequest, token);
        pushRequest.headers.contentType = ContentType.json;
        pushRequest.write(jsonEncode({
          'deviceId': store.deviceId,
          'storeId': store.appIdentity.storeId,
          'branchId': store.appIdentity.branchId,
          'deviceName': store.appIdentity.deviceName,
          'cursor': settings.lastPullCursor?.toIso8601String(),
          'changes': pending.map((item) => item.toJson()).toList(),
        }));
        final pushResponse = await pushRequest.close();
        final pushBody = await utf8.decoder.bind(pushResponse).join();
        if (pushResponse.statusCode != 200) {
          client.close(force: true);
          final access = await _handleLanAccessResponse(
              pushResponse.statusCode, pushBody,
              host: host, port: port, token: token);
          if (access != null) return access;
          final message = 'Push failed: ${pushResponse.statusCode} $pushBody';
          await _syncCore.markPushFailed(pendingIds, message);
          return LanSyncResult(ok: false, message: message);
        }
        final decoded = jsonDecode(pushBody) as Map<String, dynamic>;
        final ackIds = (decoded['ackIds'] as List<dynamic>? ?? [])
            .map((item) => '$item')
            .toList();
        final rejected = _decodeRejectedSyncRequests(decoded['rejected']);
        if (rejected.isNotEmpty) await _syncCore.markPushRejected(rejected);
        onProgress?.call(
            0.48, 'Host accepted ${ackIds.length} pushed change(s)...');
        await _syncCore.markPushSubmitted(ackIds);
        pushCompleted = true;
      }

      final ackCursor = settings.lastPullCursor?.toIso8601String() ?? '';
      final lastSequence =
          SyncDeviceStateStore.load(store.appIdentity).lastAppliedSequence;
      final seqParam = '&since_sequence=$lastSequence';
      final path = settings.lastPullCursor == null
          ? '/changes/pull?device_id=${Uri.encodeQueryComponent(store.deviceId)}&ack_cursor=${Uri.encodeQueryComponent(ackCursor)}$seqParam'
          : '/changes/pull?device_id=${Uri.encodeQueryComponent(store.deviceId)}&ack_cursor=${Uri.encodeQueryComponent(ackCursor)}&since=${Uri.encodeQueryComponent(settings.lastPullCursor!.toIso8601String())}$seqParam';
      onProgress?.call(0.62, 'Pulling new changes from LAN Host...');
      final pullRequest = await client.get(host.trim(), port, path);
      _attachToken(pullRequest, token);
      final pullResponse = await pullRequest.close();
      final pullBody = await utf8.decoder.bind(pullResponse).join();
      client.close(force: true);
      if (pullResponse.statusCode != 200) {
        final access = await _handleLanAccessResponse(
            pullResponse.statusCode, pullBody,
            host: host, port: port, token: token);
        if (access != null) return access;
        final message =
            'Pull changes failed: ${pullResponse.statusCode} $pullBody';
        final repair = pushCompleted
            ? await repairFromHostSnapshot(host,
                port: port, token: token, onProgress: onProgress)
            : null;
        if (repair?.ok == true) {
          return LanSyncResult(
              ok: true, message: '$message. ${repair!.message}');
        }
        if (pendingIds.isNotEmpty && !pushCompleted) {
          await _syncCore.markPushFailed(pendingIds, message);
        }
        return LanSyncResult(
            ok: false,
            message: repair == null ? message : '$message. ${repair.message}');
      }
      final decodedPull = jsonDecode(pullBody) as Map<String, dynamic>;
      final generationRebuild = await _rebuildIfHostSnapshotGenerationChanged(
        host,
        port,
        token,
        decodedPull,
        onProgress: onProgress,
      );
      if (generationRebuild != null) return generationRebuild;
      if (decodedPull['needsSnapshot'] == true) {
        final repair = await repairFromHostSnapshot(host,
            port: port, token: token, onProgress: onProgress);
        return repair.ok
            ? LanSyncResult(
                ok: true,
                message: 'LAN event log gap detected. ${repair.message}')
            : LanSyncResult(
                ok: false,
                message:
                    'LAN event log gap detected and repair failed. ${repair.message}');
      }
      final changes = _syncCore.filterOutLocalEchoes(
        _syncCore.decodeRemoteChanges(decodedPull['changes'] as List<dynamic>?),
      );
      final restoreMarker = changes.any((item) =>
          item.entityType == 'system' &&
          item.operation == 'cloud_restore_snapshot_ready');
      if (restoreMarker && store.appIdentity.isClient) {
        final commandId = _restoreCommandIdFromChanges(changes);
        if (_restoreCommandAlreadyExecuted('lan', commandId)) {
          onProgress?.call(0.72,
              'Host restore command already applied. Continuing LAN sync...');
        } else {
          onProgress?.call(0.72,
              'Host restore detected. Rebuilding from LAN Host snapshot...');
          await settings.copyWith(clearLastPullCursor: true).save();
          await SyncDeviceStateStore.resetClientProgress(store.appIdentity,
              transport: 'lan');
          return repairFromHostSnapshot(host,
              port: port, token: token, onProgress: onProgress);
        }
      }
      onProgress?.call(
          0.78, 'Applying ${changes.length} LAN change(s) locally...');
      await _syncCore.applyAuthoritativeChanges(changes);
      final generatedAt =
          DateTime.tryParse(decodedPull['generatedAt'] as String? ?? '') ??
              DateTime.now();
      final generatedSequence =
          int.tryParse(decodedPull['generatedSequence']?.toString() ?? '') ?? 0;
      onProgress?.call(0.92, 'Saving LAN sync cursor...');
      await settings
          .copyWith(
              lastPullCursor: generatedAt,
              lastConnectionAt: DateTime.now(),
              lastSyncAt: DateTime.now())
          .save();
      await SyncDeviceStateStore.recordSyncResult(store.appIdentity,
          transport: 'lan',
          appliedCursor: generatedAt,
          ackCursor: generatedAt,
          appliedSequence: generatedSequence,
          ackSequence: generatedSequence);
      await _sendLanAck(host,
          port: port,
          token: token,
          cursor: generatedAt,
          sequence: generatedSequence);
      await store.clearSuspendedByHost();
      onProgress?.call(0.97, 'Running Client sync log maintenance...');
      await store.compactClientSyncedSyncHistoryForMaintenance();
      onProgress?.call(1.0, 'LAN sync completed.');
      return LanSyncResult(
        ok: true,
        message:
            'Sync completed. Pushed ${pending.length} change(s), pulled ${changes.length} change(s).',
      );
    } catch (error) {
      if (pushCompleted) {
        final repair = await repairFromHostSnapshot(host,
            port: port, token: token, onProgress: onProgress);
        if (repair.ok) {
          return LanSyncResult(
              ok: true,
              message: 'Incremental sync failed: $error. ${repair.message}');
        }
      }
      if (pendingIds.isNotEmpty && !pushCompleted) {
        await _syncCore.markPushFailed(pendingIds, error.toString());
      }
      return LanSyncResult(ok: false, message: 'Sync failed: $error');
    }
  }
}

class _LanSnapshotPullTransport implements UnifiedSnapshotChunkPullTransport {
  _LanSnapshotPullTransport({
    required this.host,
    required this.port,
    required this.token,
    required this.deviceId,
    required this.attachToken,
    required this.newClient,
  });

  final String host;
  final int port;
  final String token;
  final String deviceId;
  final void Function(HttpClientRequest request, String token,
      {String? deviceId}) attachToken;
  final HttpClient Function() newClient;

  @override
  Future<UnifiedSnapshotManifestResponse> requestManifest(
      {bool force = false}) async {
    final client = newClient();
    try {
      final path = force ? '/snapshot/manifest?force=1' : '/snapshot/manifest';
      final request = await client.get(host.trim(), port, path);
      attachToken(request, token, deviceId: deviceId);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        throw StateError(
            'Snapshot manifest failed: ${response.statusCode} $body');
      }
      final decoded = Map<String, dynamic>.from(jsonDecode(body) as Map);
      return UnifiedSnapshotManifestResponse(
        manifest: Map<String, dynamic>.from(
            (decoded['snapshotManifest'] as Map?) ?? const <String, dynamic>{}),
        totalChunks: (decoded['totalChunks'] as num?)?.toInt() ?? 0,
        snapshotFormat: decoded['snapshotFormat']?.toString(),
        snapshotVersion: decoded['snapshotVersion'],
        snapshotKind: decoded['snapshotKind']?.toString(),
        syncGeneratedAt: decoded['syncGeneratedAt']?.toString(),
        syncGeneratedSequence:
            (decoded['syncGeneratedSequence'] as num?)?.toInt(),
        hostSnapshotGeneration: decoded['hostSnapshotGeneration']?.toString(),
        snapshotGeneration: decoded['snapshotGeneration']?.toString(),
        hostRestoreCommandId: decoded['hostRestoreCommandId']?.toString(),
        restoreCommandId: decoded['restoreCommandId']?.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<UnifiedSnapshotChunkResponse> requestChunk(int ordinal) async {
    final client = newClient();
    try {
      final request = await client.get(
          host.trim(), port, '/snapshot/chunk?ordinal=$ordinal');
      attachToken(request, token, deviceId: deviceId);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        throw StateError(
            'Snapshot chunk ${ordinal + 1} failed: ${response.statusCode} $body');
      }
      final decoded = Map<String, dynamic>.from(jsonDecode(body) as Map);
      final chunk = decoded['chunk'];
      if (chunk is! Map) {
        throw StateError('Snapshot chunk ${ordinal + 1} is invalid.');
      }
      return UnifiedSnapshotChunkResponse(
        chunk: Map<String, dynamic>.from(chunk),
        ordinal: (decoded['ordinal'] as num?)?.toInt() ?? ordinal,
        totalChunks: (decoded['totalChunks'] as num?)?.toInt() ?? 0,
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> ackChunk(int ordinal) async {
    // LAN snapshot chunk ACK is currently client-local; the unified transfer
    // engine still calls this hook so LAN and Cloud share the same pipeline.
  }
}
