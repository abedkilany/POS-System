import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:ventio/core/contracts/application_session.dart';
import '../../models/app_identity.dart';
import '../../models/sync_change.dart';
import 'account_auth_service.dart';
import 'local_database_service.dart';
import 'unified_sync_core_service.dart';
import '../sync_unified/unified_pairing_lifecycle.dart';
import '../sync_unified/unified_pairing_snapshot_flow.dart';
import '../sync_unified/sync_device_state.dart';
import '../sync_unified/unified_snapshot_lifecycle.dart';
import '../sync_unified/unified_sync_policy.dart';
import '../sync_unified/sync_contracts.dart';
import '../snapshot/unified_snapshot_transfer.dart';
part 'lan_sync_service_io_methods_01.dart';
part 'lan_sync_service_io_methods_02.dart';
part 'lan_sync_service_io_methods_03.dart';
part 'lan_sync_service_io_methods_04.dart';

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
    this.pairingCodeExpiresAt,
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
  final DateTime? pairingCodeExpiresAt;
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
    DateTime? pairingCodeExpiresAt,
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
      pairingCodeExpiresAt: pairingCodeExpiresAt ?? this.pairingCodeExpiresAt,
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
        'pairingCodeExpiresAt': pairingCodeExpiresAt?.toIso8601String(),
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
      pairingCodeExpiresAt:
          DateTime.tryParse(json['pairingCodeExpiresAt']?.toString() ?? ''),
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

  /// Adopt a Direct-paired Client into the Host Registry. The Registry remains
  /// the Monitoring source of truth; Direct pairing is only allowed to add a
  /// device after the Host verifies that the single-use pairing code was
  /// consumed by that Client for this Host.
  LanSyncSettings withDirectPairedHostRegistryDevice({
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
              source: 'direct_pairing_claim',
              pairedAt: pairedAt ?? DateTime.now(),
              lastSeenAt: pairedAt ?? DateTime.now(),
            ))
        .copyWith(
      deviceToken: cleanToken,
      hostDeviceId: cleanHostId,
      deviceName: cleanName,
      status: 'active',
      source: 'direct_pairing_claim',
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
  const LanSyncResult({required this.ok, required this.message, this.identity});
  final bool ok;
  final String message;
  final AppIdentity? identity;
}

class LanSyncService {
  LanSyncService(this.store);

  static const int _discoveryPort = 8788;
  static const String _discoveryProtocol = 'ventio-lan-discovery-v1';

  final SyncSession store;
  late final UnifiedSyncCoreService _syncCore = UnifiedSyncCoreService(store.sync);
  Map<String, dynamic>? _snapshotTransferCache;
  DateTime? _snapshotTransferCacheAt;
  static HttpServer? _sharedServer;
  static int? _sharedPort;
  static LanSyncService? _sharedHostService;
  static final Map<WebSocket, String> _realtimeClients = <WebSocket, String>{};
  static final Set<String> _activeSnapshotGenerationRebuilds = <String>{};
  RawDatagramSocket? _discoverySocket;
  bool _hostRecoveryInProgress = false;
  WebSocketChannel? _realtimeChannel;
  StreamSubscription<dynamic>? _realtimeSubscription;
  final StreamController<bool> _realtimeSignals =
      StreamController<bool>.broadcast();
  bool _storeListenerAttached = false;

  // Keep these transport operations as virtual instance members. Their
  // implementations live in an extension for file-size management, while
  // subclasses and tests can still override the service API as before.
  Future<LanSyncResult> repairFromHostSnapshot(
    String host, {
    int port = 8787,
    String token = '',
    LanSyncProgressCallback? onProgress,
  }) =>
      _repairFromHostSnapshotImpl(
        host,
        port: port,
        token: token,
        onProgress: onProgress,
      );

  Future<LanSyncResult> pushPendingOnly(
    String host, {
    int port = 8787,
    String token = '',
    LanSyncProgressCallback? onProgress,
  }) =>
      _pushPendingOnlyImpl(
        host,
        port: port,
        token: token,
        onProgress: onProgress,
      );

  Future<LanSyncResult> pullChangesOnly(
    String host, {
    int port = 8787,
    String token = '',
    LanSyncProgressCallback? onProgress,
  }) =>
      _pullChangesOnlyImpl(
        host,
        port: port,
        token: token,
        onProgress: onProgress,
      );
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
    // engine still calls this hook so LAN and Direct share the same pipeline.
  }
}
