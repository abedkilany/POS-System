import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../app_brand.dart';
import '../../data/app_store.dart';
import '../../models/app_identity.dart';
import '../../models/sync_change.dart';
import 'local_database_service.dart';
import 'sync_diagnostics_log.dart';
import 'direct_sync_settings.dart';
import 'direct_device_identity.dart';
import 'unified_sync_core_service.dart';
import '../sync_unified/unified_pairing_lifecycle.dart';
import '../sync_unified/unified_direct_snapshot_retry_flow.dart';
import '../sync_unified/unified_pairing_snapshot_flow.dart';
import '../sync_unified/sync_device_state.dart';
import '../sync_unified/unified_snapshot_lifecycle.dart';
import '../sync_unified/unified_sync_policy.dart';
import '../sync_unified/sync_contracts.dart';
import '../snapshot/unified_snapshot_transfer.dart';
part 'direct_control_plane_service_methods_01.dart';
part 'direct_control_plane_service_methods_02.dart';
part 'direct_control_plane_service_methods_03.dart';
part 'direct_control_plane_service_methods_04.dart';
part 'direct_control_plane_service_methods_05.dart';
part 'direct_control_plane_service_methods_06.dart';

class VpsControlPlaneSettings {
  const VpsControlPlaneSettings({
    required this.enabled,
    required this.apiBaseUrl,
    this.lastPullCursor,
    this.autoSyncEnabled = true,
    this.intervalSeconds = defaultIntervalSeconds,
  });

  static const _apiBaseUrlKey = 'vps_api_base_url';
  static const _lastPullCursorKey = 'direct_last_pull_cursor';
  static const _bundledDirectApiBaseUrl =
      String.fromEnvironment('VPS_API_BASE_URL');
  static const _bundledPublicApiBaseUrl = String.fromEnvironment(
      'PUBLIC_API_BASE_URL',
      defaultValue: 'https://ventioapp.com');

  static Future<void> clearSavedPullCursor() async {
    await LocalDatabaseService.deleteString(_lastPullCursorKey);
  }

  static const _autoSyncKey = 'direct_control_auto_sync_enabled';

  static String generatePairingCode() {
    const alphabet =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final random = Random.secure();
    return List.generate(16, (_) => alphabet[random.nextInt(alphabet.length)])
        .join();
  }

  static const _intervalKey = 'direct_control_auto_sync_interval_seconds';
  static const int defaultIntervalSeconds = 30;
  static const int minIntervalSeconds = 5;
  static const int maxIntervalSeconds = 60;

  final bool enabled;
  final String apiBaseUrl;
  final DateTime? lastPullCursor;
  final bool autoSyncEnabled;
  final int intervalSeconds;

  String get accountToken {
    final raw = LocalDatabaseService.getString('account_auth_cache_v1') ?? '';
    if (raw.trim().isEmpty) return '';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return (decoded['accountToken'] ?? '').toString().trim();
      }
    } catch (_) {
      return '';
    }
    return '';
  }

  bool get directSyncAllowedByPlatform {
    final raw = LocalDatabaseService.getString('account_auth_cache_v1') ?? '';
    if (raw.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded['directSyncEnabled'] == true ||
            decoded['direct_sync_enabled'] == true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  bool get hasDeviceCredentials {
    final raw = LocalDatabaseService.getString('app_identity_v1') ?? '';
    try {
      final identity = AppIdentity.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
      return identity.deviceId.trim().isNotEmpty &&
          identity.deviceToken.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool get isConfigured =>
      enabled &&
      apiBaseUrl.trim().isNotEmpty &&
      (hasDeviceCredentials || accountToken.trim().isNotEmpty);

  static String get bundledApiBaseUrl {
    final directUrl = _bundledDirectApiBaseUrl.trim();
    if (directUrl.isNotEmpty) return directUrl;
    return _bundledPublicApiBaseUrl.trim();
  }

  static String normalizeApiBaseUrl(String value, {String fallback = ''}) {
    var raw = value.trim();
    if (raw.isEmpty) return fallback.trim();
    raw = raw.replaceAll(RegExp(r'/+$'), '');
    if (raw.startsWith('/')) {
      throw const FormatException(
          'Direct API URL must be an absolute URL, not a relative path.');
    }
    if (!raw.contains('://')) {
      raw = 'https://$raw';
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.trim().isEmpty) {
      throw const FormatException('Direct API URL is invalid.');
    }
    return uri
        .replace(path: uri.path.replaceAll(RegExp(r'/+$'), ''))
        .toString()
        .replaceAll(RegExp(r'/+$'), '');
  }

  Uri endpoint(String path, [Map<String, String>? query]) {
    final base = normalizeApiBaseUrl(apiBaseUrl);
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$base$normalizedPath');
    return query == null
        ? uri
        : uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  Uri realtimeEndpoint(String path, [Map<String, String>? query]) {
    final uri = endpoint(path, query);
    return uri.replace(scheme: uri.scheme == 'http' ? 'ws' : 'wss');
  }

  VpsControlPlaneSettings copyWith({
    bool? enabled,
    String? apiBaseUrl,
    DateTime? lastPullCursor,
    bool clearLastPullCursor = false,
    bool? autoSyncEnabled,
    int? intervalSeconds,
  }) =>
      VpsControlPlaneSettings(
        enabled: enabled ?? this.enabled,
        apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
        lastPullCursor: clearLastPullCursor
            ? null
            : (lastPullCursor ?? this.lastPullCursor),
        autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
        intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      );

  static VpsControlPlaneSettings load() {
    final base = LocalDatabaseService.getString(_apiBaseUrlKey);
    final cursorRaw = LocalDatabaseService.getString(_lastPullCursorKey) ?? '';
    final autoRaw = LocalDatabaseService.getString(_autoSyncKey);
    final intervalRaw = LocalDatabaseService.getString(_intervalKey);
    final bundledOrigin = bundledApiBaseUrl;
    final currentOrigin = kIsWeb ? Uri.base.origin : bundledOrigin;
    var normalizedBaseUrl = currentOrigin;
    if (base != null && base.trim().isNotEmpty) {
      try {
        normalizedBaseUrl = normalizeApiBaseUrl(base, fallback: currentOrigin);
      } catch (_) {
        normalizedBaseUrl = currentOrigin;
      }
    }
    return VpsControlPlaneSettings(
      enabled: true,
      apiBaseUrl: normalizedBaseUrl,
      lastPullCursor: DateTime.tryParse(cursorRaw),
      autoSyncEnabled: autoRaw == null ? true : autoRaw == 'true',
      intervalSeconds: normalizeIntervalSeconds(intervalRaw),
    );
  }

  static int normalizeIntervalSeconds(Object? value) {
    final parsed = value is int
        ? value
        : int.tryParse(value?.toString() ?? '') ?? defaultIntervalSeconds;
    return parsed.clamp(minIntervalSeconds, maxIntervalSeconds).toInt();
  }

  Future<void> save() async {
    final normalizedBaseUrl = normalizeApiBaseUrl(apiBaseUrl,
        fallback: kIsWeb ? Uri.base.origin : '');
    await LocalDatabaseService.setString(_apiBaseUrlKey, normalizedBaseUrl);
    await LocalDatabaseService.setString(
        _autoSyncKey, autoSyncEnabled ? 'true' : 'false');
    await LocalDatabaseService.setString(
        _intervalKey, normalizeIntervalSeconds(intervalSeconds).toString());
    if (lastPullCursor == null) {
      await LocalDatabaseService.deleteString(_lastPullCursorKey);
    } else {
      await LocalDatabaseService.setString(
          _lastPullCursorKey, lastPullCursor!.toIso8601String());
    }
  }
}

class HostHeartbeatStatus {
  const HostHeartbeatStatus({
    required this.controlPlaneReachable,
    required this.hostReachable,
    this.lastSeenAt,
    this.hostDeviceId = '',
    this.hostDeviceName = '',
    this.message = '',
  });

  final bool controlPlaneReachable;
  final bool hostReachable;
  final DateTime? lastSeenAt;
  final String hostDeviceId;
  final String hostDeviceName;
  final String message;
}

class DirectRealtimeSignal {
  const DirectRealtimeSignal({
    required this.type,
    this.latestSequence = 0,
    this.pendingRequests = 0,
  });

  final String type;
  final int latestSequence;
  final int pendingRequests;
}

class _DirectSnapshotRelayJob {
  _DirectSnapshotRelayJob({
    required this.jobId,
    required this.kind,
    required this.createdAt,
    required this.chunks,
    required this.envelope,
  }) : expiresAt = createdAt.add(const Duration(minutes: 10));

  final String jobId;
  final String kind;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<Map<String, dynamic>> chunks;
  final Map<String, dynamic> envelope;
}

class _RealtimeChannelSession {
  _RealtimeChannelSession({
    required this.channel,
    required this.uri,
  });

  final WebSocketChannel channel;
  final Uri uri;
}

class _RealtimeRelaySession {
  _RealtimeRelaySession._(this._service, this._channelSession) {
    // The server is only a transport bridge here. The Host is the only side
    // that decides whether a change is accepted and what ACK comes back.
    _subscription = _channelSession.channel.stream.listen(
      _handlePacket,
      onError: _handleError,
      onDone: _handleDone,
      cancelOnError: false,
    );
  }

  final DirectControlPlaneService _service;
  final _RealtimeChannelSession _channelSession;
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests =
      <String, Completer<Map<String, dynamic>>>{};
  StreamSubscription<dynamic>? _subscription;
  bool _closed = false;

  static Future<_RealtimeRelaySession> open(
    DirectControlPlaneService service,
    VpsControlPlaneSettings settings, {
    bool includeSequenceHint = false,
  }) async {
    final channelSession = await service._openRealtimeChannel(
      settings,
      includeSequenceHint: includeSequenceHint,
    );
    return _RealtimeRelaySession._(service, channelSession);
  }

  void _completePendingError(Object error, StackTrace stackTrace) {
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
    _pendingRequests.clear();
  }

  void _handlePacket(dynamic raw) {
    if (_closed) return;
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map) return;
      final packet = Map<String, dynamic>.from(decoded);
      final type = (packet['type'] ?? '').toString();
      if (type == 'realtime_welcome') return;
      if (type != 'relay_response') return;
      final requestId =
          (packet['requestId'] ?? packet['request_id'] ?? '').toString().trim();
      if (requestId.isEmpty) return;
      final completer = _pendingRequests.remove(requestId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(packet);
      }
    } catch (error, stackTrace) {
      _completePendingError(error, stackTrace);
    }
  }

  void _handleError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    _completePendingError(error, stackTrace);
  }

  void _handleDone() {
    if (_closed) return;
    _completePendingError(
      StateError('Realtime relay closed before the Host replied.'),
      StackTrace.current,
    );
  }

  Future<Map<String, dynamic>> sendRequest(
    String requestKind,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_closed) {
      throw StateError('Realtime relay session is closed.');
    }
    final requestId = _service._newRelayRequestId();
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[requestId] = completer;
    try {
      _channelSession.channel.sink.add(jsonEncode({
        'type': 'relay_request',
        'requestId': requestId,
        'requestKind': requestKind,
        ...payload,
      }));
      return await completer.future.timeout(timeout);
    } finally {
      _pendingRequests.remove(requestId);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final subscription = _subscription;
    _subscription = null;
    _completePendingError(
      StateError('Realtime relay session was closed.'),
      StackTrace.current,
    );
    if (subscription != null) {
      await subscription.cancel();
    }
    await _channelSession.channel.sink.close();
  }
}

class DirectDeviceStatus {
  const DirectDeviceStatus({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.role,
    required this.transport,
    required this.lastSeenAt,
    required this.appVersion,
    this.hostDeviceId = '',
    this.activeTransport = '',
    this.lastSyncTransport = '',
    this.lastAppliedCursor,
    this.lastAckCursor,
    this.lastAppliedSequence = 0,
    this.lastAckSequence = 0,
    this.lastAckAt,
    this.online = false,
    this.revoked = false,
    this.suspended = false,
    this.wipePending = false,
  });

  final String deviceId;
  final String deviceName;
  final String platform;
  final String role;
  final String transport;
  final DateTime? lastSeenAt;
  final String appVersion;
  final String hostDeviceId;
  final String activeTransport;
  final String lastSyncTransport;
  final DateTime? lastAppliedCursor;
  final DateTime? lastAckCursor;
  final int lastAppliedSequence;
  final int lastAckSequence;
  final DateTime? lastAckAt;
  final bool online;
  final bool revoked;
  final bool suspended;
  final bool wipePending;

  bool get isOnline =>
      lastSeenAt != null &&
      DateTime.now().toUtc().difference(lastSeenAt!.toUtc()) <=
          const Duration(seconds: 90);

  factory DirectDeviceStatus.fromJson(Map<String, dynamic> json) =>
      DirectDeviceStatus(
        deviceId: (json['deviceId'] ?? json['device_id'] ?? '').toString(),
        deviceName:
            (json['deviceName'] ?? json['device_name'] ?? '').toString(),
        platform: (json['platform'] ?? '').toString(),
        role: (json['role'] ?? '').toString(),
        transport: (json['transport'] ?? '').toString(),
        lastSeenAt: DateTime.tryParse(
            (json['lastSeenAt'] ?? json['last_seen_at'] ?? '').toString()),
        appVersion:
            (json['appVersion'] ?? json['app_version'] ?? '').toString(),
        hostDeviceId:
            (json['hostDeviceId'] ?? json['host_device_id'] ?? '').toString(),
        activeTransport: (json['activeTransport'] ??
                json['active_transport'] ??
                json['transport'] ??
                '')
            .toString(),
        lastSyncTransport:
            (json['lastSyncTransport'] ?? json['last_sync_transport'] ?? '')
                .toString(),
        lastAppliedCursor: DateTime.tryParse(
            (json['lastAppliedCursor'] ?? json['last_applied_cursor'] ?? '')
                .toString()),
        lastAckCursor: DateTime.tryParse(
            (json['lastAckCursor'] ?? json['last_ack_cursor'] ?? '')
                .toString()),
        lastAppliedSequence: int.tryParse((json['lastAppliedSequence'] ??
                    json['last_applied_sequence'] ??
                    '')
                .toString()) ??
            0,
        lastAckSequence: int.tryParse(
                (json['lastAckSequence'] ?? json['last_ack_sequence'] ?? '')
                    .toString()) ??
            0,
        lastAckAt: DateTime.tryParse(
            (json['lastAckAt'] ?? json['last_ack_at'] ?? '').toString()),
        online: json['online'] == true,
        revoked: json['revoked'] == true,
        suspended: json['suspended'] == true,
        wipePending:
            json['wipePending'] == true || json['wipe_pending'] == true,
      );
}

class DirectDeviceLimitStatus {
  const DirectDeviceLimitStatus({
    required this.allowed,
    required this.linked,
    required this.available,
    required this.limitReached,
  });

  final int allowed;
  final int linked;
  final int available;
  final bool limitReached;

  factory DirectDeviceLimitStatus.fromJson(Map<String, dynamic> json) {
    final allowed = int.tryParse((json['allowed'] ?? '').toString()) ?? 0;
    final linked = int.tryParse((json['linked'] ?? '').toString()) ?? 0;
    final available = int.tryParse((json['available'] ?? '').toString()) ??
        (allowed - linked).clamp(0, 1 << 30).toInt();
    return DirectDeviceLimitStatus(
      allowed: allowed,
      linked: linked,
      available: available,
      limitReached:
          json['limitReached'] == true || json['limit_reached'] == true,
    );
  }
}

class DirectDevicesResult {
  const DirectDevicesResult({
    required this.devices,
    this.limit,
    this.directSyncEnabled,
  });

  final List<DirectDeviceStatus> devices;
  final DirectDeviceLimitStatus? limit;
  final bool? directSyncEnabled;
}

class DirectProvisioningStatus {
  const DirectProvisioningStatus._();

  static const _stateKey = 'direct_initial_provisioning_state_v1';
  static const _messageKey = 'direct_initial_provisioning_message_v1';
  static const _requestedAtKey = 'direct_initial_provisioning_requested_at_v1';
  static const _lastAttemptAtKey =
      'direct_initial_provisioning_last_attempt_at_v1';
  static const _sectionsKey = 'direct_initial_provisioning_sections_v1';
  static const _allSectionsCompleteKey =
      'direct_initial_provisioning_all_sections_complete_v1';

  static bool get isPending =>
      LocalDatabaseService.getString(_stateKey) == 'pending';

  static String get message =>
      LocalDatabaseService.getString(_messageKey) ??
      'Initial Store data is downloading from the Host.';

  static Map<String, String> get sections {
    final raw = LocalDatabaseService.getString(_sectionsKey);
    if (raw == null || raw.trim().isEmpty) return const <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, String>{};
      return decoded
          .map((key, value) => MapEntry(key.toString(), value.toString()));
    } catch (_) {
      return const <String, String>{};
    }
  }

  static bool get allSectionsComplete =>
      LocalDatabaseService.getString(_allSectionsCompleteKey) == 'true';

  static DateTime? get requestedAt =>
      DateTime.tryParse(LocalDatabaseService.getString(_requestedAtKey) ?? '');

  static DateTime? get lastAttemptAt => DateTime.tryParse(
      LocalDatabaseService.getString(_lastAttemptAtKey) ?? '');

  static Future<void> markPending(
      {String message = 'Initial Store data is downloading from the Host.',
      DateTime? requestedAt}) async {
    final now = DateTime.now().toUtc();
    await LocalDatabaseService.setString(_stateKey, 'pending');
    await LocalDatabaseService.setString(_messageKey, message);
    await LocalDatabaseService.setString(
        _requestedAtKey, (requestedAt ?? now).toIso8601String());
  }

  static Future<void> updateSnapshotSections(Map<String, dynamic>? value,
      {bool? allComplete}) async {
    if (value != null) {
      final normalized = <String, String>{};
      for (final entry in value.entries) {
        normalized[entry.key.toString()] = entry.value.toString();
      }
      await LocalDatabaseService.setString(
          _sectionsKey, jsonEncode(normalized));
    }
    if (allComplete != null) {
      await LocalDatabaseService.setString(
          _allSectionsCompleteKey, allComplete ? 'true' : 'false');
    }
  }

  static Future<void> markAttempted([DateTime? value]) async {
    await LocalDatabaseService.setString(
        _lastAttemptAtKey, (value ?? DateTime.now().toUtc()).toIso8601String());
  }

  static Future<void> markComplete(
      {String message = 'Initial Store data downloaded.'}) async {
    await LocalDatabaseService.setString(_stateKey, 'complete');
    await LocalDatabaseService.setString(_messageKey, message);
    await LocalDatabaseService.setString(_allSectionsCompleteKey, 'true');
    await LocalDatabaseService.deleteString(_lastAttemptAtKey);
  }

  static Future<void> clear() async {
    await LocalDatabaseService.deleteString(_stateKey);
    await LocalDatabaseService.deleteString(_messageKey);
    await LocalDatabaseService.deleteString(_requestedAtKey);
    await LocalDatabaseService.deleteString(_lastAttemptAtKey);
    await LocalDatabaseService.deleteString(_sectionsKey);
    await LocalDatabaseService.deleteString(_allSectionsCompleteKey);
  }
}

typedef DirectSyncProgressCallback = void Function(double value, String label);

class DirectSyncResult {
  const DirectSyncResult(
      {required this.ok,
      required this.message,
      this.pushed = 0,
      this.pulled = 0,
      this.restoredSnapshot = false,
      this.syncDeferred = false});
  final bool ok;
  final String message;
  final int pushed;
  final int pulled;
  final bool restoredSnapshot;
  final bool syncDeferred;
}

class DirectPairingCodeResult {
  const DirectPairingCodeResult(
      {required this.ok,
      required this.message,
      this.code = '',
      this.expiresAt,
      this.storeId = '',
      this.branchId = 'main',
      this.hostDeviceId = '',
      this.transport = 'direct'});
  final bool ok;
  final String message;
  final String code;
  final DateTime? expiresAt;
  final String storeId;
  final String branchId;
  final String hostDeviceId;
  final String transport;
}

class DirectPairingStatusResult {
  const DirectPairingStatusResult({
    required this.ok,
    required this.status,
    required this.message,
    this.expiresAt,
    this.claimedAt,
    this.claimedByDeviceId = '',
    this.claimedByDeviceName = '',
    this.claimedDeviceToken = '',
  });
  final bool ok;
  final String status;
  final String message;
  final DateTime? expiresAt;
  final DateTime? claimedAt;
  final String claimedByDeviceId;
  final String claimedByDeviceName;
  final String claimedDeviceToken;
}

class DirectPairingClaimResult {
  const DirectPairingClaimResult(
      {required this.ok, required this.message, this.identity});
  final bool ok;
  final String message;
  final AppIdentity? identity;
}

class DirectStoreRecoveryResult {
  const DirectStoreRecoveryResult(
      {required this.ok,
      required this.message,
      this.identity,
      this.restoredSnapshot = false,
      this.pulled = 0,
      this.username = '',
      this.loginName = '',
      this.storeName = '',
      this.storeSlug = '',
      this.directSyncEnabled = false,
      this.deviceLimit});
  final bool ok;
  final String message;
  final AppIdentity? identity;
  final bool restoredSnapshot;
  final int pulled;
  final String username;
  final String loginName;
  final String storeName;
  final String storeSlug;
  final bool directSyncEnabled;
  final DirectDeviceLimitStatus? deviceLimit;
}

class DirectControlPlaneService {
  DirectControlPlaneService(this.store, {http.Client? client})
      : _client = client ?? _RetiredDirectSyncHttpClient();

  final AppStore store;
  final http.Client _client;
  late final UnifiedSyncCoreService _syncCore = UnifiedSyncCoreService(store);
  static int _relayRequestCounter = 0;
  static final Map<String, _DirectSnapshotRelayJob> _relaySnapshotJobs =
      <String, _DirectSnapshotRelayJob>{};
  static const String _clientDirectDrainMessage =
      'Client direct sync paused until Host confirms pending local changes. Pull and snapshot rebuild are deferred.';
  static const String _clientDirectRebuildBlockedMessage =
      'Direct rebuild is paused until the Client finishes sending its pending changes to the Host.';
}

/// Prevents legacy Direct Sync callers from reaching the network while the
/// remaining UI/admin references are removed. Direct and LAN own all runtime
/// synchronization; production code must never inject a live HTTP client
/// into this retired service.
class _RetiredDirectSyncHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw StateError(
      'Direct Sync has been removed. Use LAN or Direct transport.',
    );
  }
}

class _DirectRelaySnapshotPullTransport
    implements UnifiedSnapshotChunkPullTransport {
  _DirectRelaySnapshotPullTransport({
    required DirectControlPlaneService service,
    required this.settings,
    String snapshotKind = 'full_store',
    String rebuildRequestId = '',
    int requiredMinSequence = 0,
  })  : _service = service,
        _snapshotKind = snapshotKind,
        _rebuildRequestId = rebuildRequestId,
        _requiredMinSequence = requiredMinSequence;

  final DirectControlPlaneService _service;
  final VpsControlPlaneSettings settings;
  final String _snapshotKind;
  final String _rebuildRequestId;
  final int _requiredMinSequence;
  String _jobId = '';
  _RealtimeRelaySession? _relaySession;
  Future<_RealtimeRelaySession>? _relaySessionFuture;

  Future<_RealtimeRelaySession> _session() async {
    final existing = _relaySession;
    if (existing != null) return existing;
    _relaySessionFuture ??= _RealtimeRelaySession.open(
      _service,
      settings,
      includeSequenceHint: false,
    );
    try {
      _relaySession = await _relaySessionFuture!;
      return _relaySession!;
    } catch (_) {
      _relaySessionFuture = null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _request(
    String requestKind,
    Map<String, dynamic> payload,
  ) async {
    final response = await (await _session()).sendRequest(
      requestKind,
      payload,
      timeout: const Duration(seconds: 45),
    );
    if (response['ok'] != true) {
      throw StateError(response['error']?.toString() ??
          response['message']?.toString() ??
          'Direct relay request failed.');
    }
    return response;
  }

  Future<void> dispose() async {
    try {
      if (_jobId.trim().isNotEmpty) {
        await _request('direct_snapshot_release', {'jobId': _jobId});
      }
    } catch (_) {
      // Best-effort cleanup only.
    } finally {
      final session = _relaySession;
      _relaySession = null;
      _relaySessionFuture = null;
      if (session != null) {
        await session.close();
      }
    }
  }

  @override
  Future<UnifiedSnapshotManifestResponse> requestManifest(
      {bool force = false}) async {
    final identity = _service.store.runtime.identity;
    final response = await _request('direct_snapshot_manifest', {
      'storeId': identity.storeId,
      'branchId': identity.branchId,
      'deviceId': _service.store.sync.deviceId,
      'snapshotKind': _snapshotKind,
      'force': force,
      if (_rebuildRequestId.trim().isNotEmpty)
        'rebuildRequestId': _rebuildRequestId.trim(),
      if (_requiredMinSequence > 0) 'requiredMinSequence': _requiredMinSequence,
    });
    _jobId = (response['jobId'] ?? '').toString().trim();
    return UnifiedSnapshotManifestResponse(
      manifest: Map<String, dynamic>.from(
          (response['snapshotManifest'] as Map?) ?? const <String, dynamic>{}),
      totalChunks: (response['totalChunks'] as num?)?.toInt() ?? 0,
      snapshotFormat: response['snapshotFormat']?.toString(),
      snapshotVersion: response['snapshotVersion'],
      snapshotKind: response['snapshotKind']?.toString(),
      syncGeneratedAt: response['syncGeneratedAt']?.toString(),
      syncGeneratedSequence:
          (response['syncGeneratedSequence'] as num?)?.toInt(),
      hostSnapshotGeneration: response['hostSnapshotGeneration']?.toString(),
      snapshotGeneration: response['snapshotGeneration']?.toString(),
      hostRestoreCommandId: response['hostRestoreCommandId']?.toString(),
      restoreCommandId: response['restoreCommandId']?.toString(),
      rebuildRequestId: response['rebuildRequestId']?.toString(),
      requiredMinSequence: (response['requiredMinSequence'] as num?)?.toInt(),
    );
  }

  @override
  Future<UnifiedSnapshotChunkResponse> requestChunk(int ordinal) async {
    if (_jobId.trim().isEmpty) {
      throw StateError('Direct relay snapshot job has not been created yet.');
    }
    final response = await _request('direct_snapshot_chunk', {
      'jobId': _jobId,
      'ordinal': ordinal,
    });
    final chunk = response['chunk'];
    if (chunk is! Map) {
      throw StateError(
          'Direct relay snapshot chunk ${ordinal + 1} is invalid.');
    }
    return UnifiedSnapshotChunkResponse(
      chunk: Map<String, dynamic>.from(chunk),
      ordinal: (response['ordinal'] as num?)?.toInt() ?? ordinal,
      totalChunks: (response['totalChunks'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> ackChunk(int ordinal) async {
    // Relay snapshot chunks are retrieved directly from the Host memory cache.
    // The transfer service keeps this hook so the relay transport still fits
    // the same shared pipeline as LAN and HTTP.
  }
}
