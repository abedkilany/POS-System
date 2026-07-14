import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../app_brand.dart';
import '../../data/app_store.dart';
import '../../models/app_identity.dart';
import '../../models/sync_change.dart';
import 'local_database_service.dart';
import 'sync_diagnostics_log.dart';
import 'unified_sync_core_service.dart';
import '../sync_unified/sync_device_state.dart';
import '../snapshot/unified_snapshot_transfer.dart';

class CloudSyncSettings {
  const CloudSyncSettings({
    required this.enabled,
    required this.apiBaseUrl,
    this.lastPullCursor,
    this.autoSyncEnabled = true,
    this.intervalSeconds = defaultIntervalSeconds,
  });

  static const _apiBaseUrlKey = 'cloud_api_base_url';
  static const _lastPullCursorKey = 'cloud_last_pull_cursor';
  static const _bundledCloudApiBaseUrl =
      String.fromEnvironment('CLOUD_API_BASE_URL');
  static const _bundledPublicApiBaseUrl = String.fromEnvironment(
      'PUBLIC_API_BASE_URL',
      defaultValue: 'https://ventioapp.com');

  static Future<void> clearSavedPullCursor() async {
    await LocalDatabaseService.deleteString(_lastPullCursorKey);
  }

  static const _autoSyncKey = 'cloud_auto_sync_enabled';
  static const _intervalKey = 'cloud_auto_sync_interval_seconds';
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

  bool get cloudSyncAllowedByPlatform {
    final raw = LocalDatabaseService.getString('account_auth_cache_v1') ?? '';
    if (raw.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded['cloudSyncEnabled'] == true ||
            decoded['cloud_sync_enabled'] == true;
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
    final cloudUrl = _bundledCloudApiBaseUrl.trim();
    if (cloudUrl.isNotEmpty) return cloudUrl;
    return _bundledPublicApiBaseUrl.trim();
  }

  static String normalizeApiBaseUrl(String value, {String fallback = ''}) {
    var raw = value.trim();
    if (raw.isEmpty) return fallback.trim();
    raw = raw.replaceAll(RegExp(r'/+$'), '');
    if (raw.startsWith('/')) {
      throw const FormatException(
          'Cloud API URL must be an absolute URL, not a relative path.');
    }
    if (!raw.contains('://')) {
      raw = 'https://$raw';
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.trim().isEmpty) {
      throw const FormatException('Cloud API URL is invalid.');
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

  CloudSyncSettings copyWith({
    bool? enabled,
    String? apiBaseUrl,
    DateTime? lastPullCursor,
    bool clearLastPullCursor = false,
    bool? autoSyncEnabled,
    int? intervalSeconds,
  }) =>
      CloudSyncSettings(
        enabled: enabled ?? this.enabled,
        apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
        lastPullCursor: clearLastPullCursor
            ? null
            : (lastPullCursor ?? this.lastPullCursor),
        autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
        intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      );

  static CloudSyncSettings load() {
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
    return CloudSyncSettings(
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
    required this.cloudReachable,
    required this.hostReachable,
    this.lastSeenAt,
    this.hostDeviceId = '',
    this.hostDeviceName = '',
    this.message = '',
  });

  final bool cloudReachable;
  final bool hostReachable;
  final DateTime? lastSeenAt;
  final String hostDeviceId;
  final String hostDeviceName;
  final String message;
}

class CloudRealtimeSignal {
  const CloudRealtimeSignal({
    required this.type,
    this.latestSequence = 0,
    this.pendingRequests = 0,
  });

  final String type;
  final int latestSequence;
  final int pendingRequests;
}

class _CloudSnapshotRelayJob {
  _CloudSnapshotRelayJob({
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
    _subscription = _channelSession.channel.stream.listen(
      _handlePacket,
      onError: _handleError,
      onDone: _handleDone,
      cancelOnError: false,
    );
  }

  final CloudSyncService _service;
  final _RealtimeChannelSession _channelSession;
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests =
      <String, Completer<Map<String, dynamic>>>{};
  StreamSubscription<dynamic>? _subscription;
  bool _closed = false;

  static Future<_RealtimeRelaySession> open(
    CloudSyncService service,
    CloudSyncSettings settings, {
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

class CloudDeviceStatus {
  const CloudDeviceStatus({
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

  factory CloudDeviceStatus.fromJson(Map<String, dynamic> json) =>
      CloudDeviceStatus(
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

class CloudDeviceLimitStatus {
  const CloudDeviceLimitStatus({
    required this.allowed,
    required this.linked,
    required this.available,
    required this.limitReached,
  });

  final int allowed;
  final int linked;
  final int available;
  final bool limitReached;

  factory CloudDeviceLimitStatus.fromJson(Map<String, dynamic> json) {
    final allowed = int.tryParse((json['allowed'] ?? '').toString()) ?? 0;
    final linked = int.tryParse((json['linked'] ?? '').toString()) ?? 0;
    final available = int.tryParse((json['available'] ?? '').toString()) ??
        (allowed - linked).clamp(0, 1 << 30).toInt();
    return CloudDeviceLimitStatus(
      allowed: allowed,
      linked: linked,
      available: available,
      limitReached:
          json['limitReached'] == true || json['limit_reached'] == true,
    );
  }
}

class CloudDevicesResult {
  const CloudDevicesResult({
    required this.devices,
    this.limit,
  });

  final List<CloudDeviceStatus> devices;
  final CloudDeviceLimitStatus? limit;
}

class CloudProvisioningStatus {
  const CloudProvisioningStatus._();

  static const _stateKey = 'cloud_initial_provisioning_state_v1';
  static const _messageKey = 'cloud_initial_provisioning_message_v1';
  static const _requestedAtKey = 'cloud_initial_provisioning_requested_at_v1';
  static const _lastAttemptAtKey =
      'cloud_initial_provisioning_last_attempt_at_v1';
  static const _sectionsKey = 'cloud_initial_provisioning_sections_v1';
  static const _allSectionsCompleteKey =
      'cloud_initial_provisioning_all_sections_complete_v1';

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

typedef CloudSyncProgressCallback = void Function(double value, String label);

class CloudSyncResult {
  const CloudSyncResult(
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

class CloudPairingCodeResult {
  const CloudPairingCodeResult(
      {required this.ok,
      required this.message,
      this.code = '',
      this.expiresAt});
  final bool ok;
  final String message;
  final String code;
  final DateTime? expiresAt;
}

class CloudPairingStatusResult {
  const CloudPairingStatusResult({
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

class CloudPairingClaimResult {
  const CloudPairingClaimResult(
      {required this.ok, required this.message, this.identity});
  final bool ok;
  final String message;
  final AppIdentity? identity;
}

class CloudStoreRecoveryResult {
  const CloudStoreRecoveryResult(
      {required this.ok,
      required this.message,
      this.identity,
      this.restoredSnapshot = false,
      this.pulled = 0,
      this.username = '',
      this.loginName = '',
      this.storeName = '',
      this.storeSlug = '',
      this.cloudSyncEnabled = false,
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
  final bool cloudSyncEnabled;
  final CloudDeviceLimitStatus? deviceLimit;
}

class CloudSyncService {
  CloudSyncService(this.store, {http.Client? client})
      : _client = client ?? http.Client();

  final AppStore store;
  final http.Client _client;
  late final UnifiedSyncCoreService _syncCore = UnifiedSyncCoreService(store);
  static final Set<String> _activeSnapshotGenerationRebuilds = <String>{};
  static int _relayRequestCounter = 0;
  static final Map<String, _CloudSnapshotRelayJob> _relaySnapshotJobs =
      <String, _CloudSnapshotRelayJob>{};
  static const String _clientCloudDrainMessage =
      'Client cloud sync paused until Host confirms pending local changes. Pull and snapshot rebuild are deferred.';
  static const String _clientCloudRebuildBlockedMessage =
      'Cloud rebuild is paused until the Client finishes sending its pending changes to the Host.';

  Future<bool> _clientCloudHostWorkNeedsDrain() async {
    if (!store.appIdentity.isClient) return false;

    // Cloud Client now uses the LAN-style direct Host relay contract:
    // Client -> Cloud relay -> Host -> final Host ACK in the same request.
    // The legacy Cloud inbox contract left rows in `submitted` and then waited
    // for /api/sync/requests/status. That is intentionally disabled for the
    // direct relay mode because it can block pull/rebuild forever when no
    // legacy cloud_change_requests row exists.
    //
    // If an older build left cloud_host rows as submitted, recover them to
    // pending so the next relay push sends them again. Until that happens,
    // any pull or rebuild must stay paused.
    await store.recoverSubmittedSyncQueue(target: 'cloud_host');
    return store.hasOutstandingSyncWorkForTarget('cloud_host');
  }


  Future<CloudSyncResult> _drainClientPendingChangesBeforeRebuild(
    CloudSyncSettings settings, {
    CloudSyncProgressCallback? onProgress,
  }) async {
    if (!store.appIdentity.isClient) {
      return const CloudSyncResult(ok: true, message: 'No Client drain needed.');
    }
    if (await _clientCloudHostWorkNeedsDrain()) {
      return const CloudSyncResult(
        ok: false,
        message: _clientCloudRebuildBlockedMessage,
        syncDeferred: true,
      );
    }
    onProgress?.call(0.06, 'Sending pending Client changes before rebuild...');
    await registerCurrentDevice(settings, transport: 'cloud');
    var pushed = 0;
    try {
      pushed += await _pushPendingViaRelay(settings, target: 'cloud_host');
    } catch (error) {
      return CloudSyncResult(
        ok: false,
        pushed: pushed,
        message: 'Cloud rebuild is waiting: pending Client changes could not be sent to the Host. $error',
        syncDeferred: true,
      );
    }

    for (var attempt = 0; attempt < 10; attempt += 1) {
      if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 2));
      onProgress?.call(
        (0.08 + attempt * 0.015).clamp(0.08, 0.22).toDouble(),
        'Waiting for Host to confirm pending Client changes (${attempt + 1}/10)...',
      );
      if (!await _clientCloudHostWorkNeedsDrain()) {
        return CloudSyncResult(
          ok: true,
          pushed: pushed,
          message: 'Pending Client changes were confirmed by the Host.',
        );
      }
    }

    return CloudSyncResult(
      ok: true,
      pushed: pushed,
      message: _clientCloudRebuildBlockedMessage,
      syncDeferred: true,
    );
  }

  bool _cloudSnapshotEnvelopeMatchesFreshRebuild(
    Map<String, dynamic> envelope, {
    required int minimumSequence,
    required String rebuildRequestId,
    required DateTime requestedAt,
  }) {
    final raw = jsonEncode(envelope);
    final generatedSequence = store.syncSnapshotGeneratedSequenceFromJson(raw);
    final generatedAt = store.syncSnapshotGeneratedAtFromJson(raw);
    final envelopeRequestId =
        (envelope['rebuildRequestId'] ?? envelope['snapshotRequestId'] ?? '')
            .toString()
            .trim();
    if (rebuildRequestId.trim().isEmpty ||
        envelopeRequestId != rebuildRequestId.trim()) {
      return false;
    }
    if (minimumSequence > 0 && generatedSequence < minimumSequence) {
      return false;
    }
    // A manual/safe rebuild must never apply a cached snapshot that existed
    // before the rebuild request. Use a small tolerance for device clock and
    // serialization precision differences, but require the Host to generate the
    // envelope during this rebuild session.
    final lowerBound = requestedAt.toUtc().subtract(const Duration(seconds: 2));
    if (generatedAt.toUtc().isBefore(lowerBound)) {
      return false;
    }
    return true;
  }

  Future<void> _restorePreviousSyncMode(AppIdentity previousIdentity) async {
    final current = store.appIdentity;
    if (current.syncMode == previousIdentity.syncMode) return;
    try {
      await store.recoverExistingStoreIdentity(
        storeId: current.storeId,
        branchId: current.branchId,
        recoveryKey: current.recoveryKey,
        hostDeviceId: current.hostDeviceId,
        deviceToken: current.deviceToken,
        cloudTenantId: current.cloudTenantId,
        deviceRole: current.deviceRole,
        syncMode: previousIdentity.syncMode,
      );
    } catch (error) {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] cloudRecovery:restoreSyncStateFailed error=$error',
      );
    }
  }

  Future<bool?> checkCloudSyncPlanAccess(CloudSyncSettings settings) async {
    final identity = store.appIdentity;
    final storeId = identity.storeId.trim();
    final branchId =
        identity.branchId.trim().isEmpty ? 'main' : identity.branchId.trim();
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] cloudAccess:start '
      'device=${identity.deviceId} '
      'role=${identity.deviceRole.name} '
      'store=$storeId '
      'branch=$branchId '
      'apiBase=${settings.apiBaseUrl} '
      'configured=${settings.isConfigured} '
      'hasAccountToken=${settings.accountToken.trim().isNotEmpty} '
      'hasDeviceToken=${identity.deviceToken.trim().isNotEmpty} '
      'transport=${identity.transportType}',
    );
    if (settings.apiBaseUrl.trim().isEmpty || storeId.isEmpty) {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] cloudAccess:skipped '
        'reason=${settings.apiBaseUrl.trim().isEmpty ? 'emptyApiBase' : 'emptyStoreId'}',
      );
      return null;
    }

    try {
      // Use the same identity headers used by cloud push/pull. The endpoint also
      // receives store/branch as query params so older proxies or middleware
      // cannot drop the entitlement context.
      final response = await _client
          .get(
            settings.endpoint('/api/sync/cloud-access', {
              'storeId': storeId,
              'branchId': branchId,
            }),
            headers: _headers(settings),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        SyncDiagnosticsLog.add(
            '[SYNC_TRACE] cloudAccess:failed status=${response.statusCode} body=${response.body}');
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final allowed = decoded['cloudSyncEnabled'] == true ||
            decoded['cloud_sync_enabled'] == true ||
            decoded['allowed'] == true;
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] cloudAccess:decoded '
          'allowed=$allowed body=$decoded',
        );
        return allowed;
      }
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] cloudAccess:decodedUnexpected type=${decoded.runtimeType}');
    } catch (error) {
      SyncDiagnosticsLog.add('[SYNC_TRACE] cloudAccess:error $error');
      return null;
    }
    return null;
  }

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

  String _snapshotRequestKey(String transport, String generation) =>
      'requested_host_snapshot_generation_${transport}_${store.appIdentity.storeId}_${store.appIdentity.branchId}_${generation.trim()}';

  String _snapshotRequestAtKey(String transport, String generation) =>
      'requested_host_snapshot_generation_at_${transport}_${store.appIdentity.storeId}_${store.appIdentity.branchId}_${generation.trim()}';

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

  Future<void> _markRestoreCommandExecuted(
      String transport, dynamic source) async {
    if (source is! Map<String, dynamic>) return;
    final commandId = _remoteHostRestoreCommandId(source);
    if (commandId.isEmpty) return;
    await LocalDatabaseService.setString(
        _restoreCommandExecutedKey(transport), commandId);
    await LocalDatabaseService.deleteString(
        _restoreCommandInProgressKey(transport));
  }

  Future<void> _markHostSnapshotGenerationApplied(
      String transport, dynamic source,
      {bool markRestoreCommandExecuted = true}) async {
    String generation = '';
    if (source is Map<String, dynamic>) {
      generation = _remoteHostSnapshotGeneration(source);
    }
    if (generation.isEmpty) return;
    await LocalDatabaseService.setString(
        _snapshotGenerationKey(transport), generation);
    if (markRestoreCommandExecuted) {
      await _markRestoreCommandExecuted(transport, source);
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

  Future<CloudSyncResult?> _rebuildIfHostSnapshotGenerationChanged(
    CloudSyncSettings settings,
    Map<String, dynamic> decodedPull, {
    CloudSyncProgressCallback? onProgress,
  }) async {
    if (!_needsHostSnapshotGenerationRebuild('cloud', decodedPull)) return null;
    final generation = _remoteHostSnapshotGeneration(decodedPull);
    final commandId = _remoteHostRestoreCommandId(decodedPull);
    if (!await _beginHostSnapshotGenerationRebuild(
      'cloud',
      generation,
      commandId: commandId,
    )) {
      return null;
    }
    CloudSyncResult result;
    try {
      onProgress?.call(0.50,
          'A newer Host restore was detected. Rebuilding this device data...');
      result = await rebuildFromCloudHostSnapshot(
        settings.copyWith(clearLastPullCursor: true),
        onProgress: onProgress,
        requestFreshSnapshot: false,
        expectedSnapshotGeneration: generation,
        expectedRestoreCommandId: commandId,
      );
      await _finishHostSnapshotGenerationRebuild(
        'cloud',
        generation,
        success: result.ok,
      );
    } catch (_) {
      await _finishHostSnapshotGenerationRebuild(
        'cloud',
        generation,
        success: false,
      );
      rethrow;
    }
    return result;
  }

  bool _cloudAllowedForIdentity(AppIdentity identity) {
    if (identity.isHost) return identity.isCloudEnabled;
    if (!identity.isClient) return false;
    return identity.activeSyncTransportNormalized == 'cloud';
  }

  Future<void> _recordDeviceSyncState(
    String transport,
    DateTime? cursor, {
    int sequence = 0,
    CloudSyncSettings? settings,
  }) async {
    final effectiveSequence =
        sequence > 0 ? sequence : store.latestStoredAuthoritativeSequence;
    await SyncDeviceStateStore.recordSyncResult(
      store.appIdentity,
      transport: transport,
      appliedCursor: cursor,
      ackCursor: cursor,
      appliedSequence: effectiveSequence,
      ackSequence: effectiveSequence,
    );

    // Authoritative ACK: update the Host-visible device state only after the
    // Client has successfully applied the pulled data locally. Pull itself must
    // never be treated as ACK.
    if (settings != null && store.appIdentity.isClient && cursor != null) {
      await registerCurrentDevice(settings, transport: transport);
    }
  }

  Future<CloudPairingCodeResult> createPairingCode(CloudSyncSettings settings,
      {String transport = 'cloud', int ttlMinutes = 5}) async {
    final identity = store.appIdentity;
    if (!identity.isHost) {
      return const CloudPairingCodeResult(
          ok: false, message: 'Only the Host can create pairing codes.');
    }
    if (settings.apiBaseUrl.trim().isEmpty) {
      return const CloudPairingCodeResult(
          ok: false, message: 'Cloud Sync is not ready yet.');
    }
    try {
      // Local Host devices are allowed to request a Cloud pairing code without
      // an online account session. The platform permission is enforced by the
      // server from app_stores.cloud_sync_enabled, so the local app must not
      // block this action only because account_auth_cache_v1 is empty.
      final response = await _client
          .post(
            settings.endpoint('/api/sync/pairing/create'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'hostDeviceId': store.deviceId,
              'hostDeviceName': identity.deviceName,
              'transport': transport,
              'ttlMinutes': ttlMinutes,
              'recoveryKey': identity.recoveryKey,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        var serverMessage = '';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            serverMessage =
                (decoded['error'] ?? decoded['message'] ?? '').toString();
          }
        } catch (_) {
          serverMessage = response.body;
        }
        serverMessage = serverMessage.trim().isEmpty
            ? '${response.statusCode} ${response.body}'
            : serverMessage.trim();
        return CloudPairingCodeResult(
            ok: false, message: 'Pairing code failed: $serverMessage');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return CloudPairingCodeResult(
            ok: false,
            message:
                'Pairing code failed: ${response.statusCode} ${response.body}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final ok = decoded['ok'] == true;
      if (ok && transport == 'cloud') {
        // Never block the Host QR/code on a large snapshot upload. Publish the
        // tiny login bootstrap first in the background, then continue with the
        // full staged snapshot so new Clients can leave Connect to Store quickly
        // and finish provisioning after Login.
        unawaited(_publishPairingBootstrapInBackground(settings));
      }
      return CloudPairingCodeResult(
        ok: ok,
        message: ok
            ? 'Pairing code created.'
            : (decoded['error']?.toString() ?? 'Pairing code failed.'),
        code: decoded['code']?.toString() ?? '',
        expiresAt: DateTime.tryParse(decoded['expiresAt']?.toString() ?? ''),
      );
    } catch (error) {
      return CloudPairingCodeResult(
          ok: false, message: 'Pairing code failed: $error');
    }
  }

  Future<void> _publishPairingBootstrapInBackground(
      CloudSyncSettings settings) async {
    try {
      // Pairing must make the full Cloud bootstrap snapshot available before a
      // Client can finish Connect to Store. Start that publish in the
      // background so the Host UI still returns immediately.
      await publishBootstrapSnapshotToCloud(settings, force: true);
      await sendHostHeartbeat(settings);
      await registerCurrentDevice(settings, transport: 'cloud');
      await _broadcastHostAuthorityViaRelay(settings);
    } catch (error) {
      debugPrint(
          'Background Cloud pairing provisioning publish failed: $error');
    }
  }

  Future<CloudPairingStatusResult> pairingCodeStatus(
      CloudSyncSettings settings, String code) async {
    final identity = store.appIdentity;
    if (!identity.isHost) {
      return const CloudPairingStatusResult(
          ok: false,
          status: 'invalid',
          message: 'Only the Host can check pairing code status.');
    }
    if (settings.apiBaseUrl.trim().isEmpty) {
      return const CloudPairingStatusResult(
          ok: false,
          status: 'invalid',
          message: 'Cloud Sync is not ready yet.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/pairing/status'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'code': code.trim(),
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        var serverMessage = '';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            serverMessage =
                (decoded['error'] ?? decoded['message'] ?? '').toString();
          }
        } catch (_) {
          serverMessage = response.body;
        }
        serverMessage = serverMessage.trim().isEmpty
            ? '${response.statusCode} ${response.body}'
            : serverMessage.trim();
        return CloudPairingStatusResult(
            ok: false,
            status: 'invalid',
            message: 'Pairing code failed: $serverMessage');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return CloudPairingStatusResult(
            ok: false,
            status: 'invalid',
            message:
                'Pairing code failed: ${response.statusCode} ${response.body}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final status = decoded['status']?.toString() ?? 'invalid';
      return CloudPairingStatusResult(
        ok: decoded['ok'] == true,
        status: status,
        message: decoded['ok'] == true
            ? status
            : (decoded['error']?.toString() ?? 'Pairing code failed.'),
        expiresAt: DateTime.tryParse(decoded['expiresAt']?.toString() ?? ''),
        claimedAt: DateTime.tryParse(decoded['claimedAt']?.toString() ?? ''),
        claimedByDeviceId: decoded['claimedByDeviceId']?.toString() ?? '',
        claimedByDeviceName: decoded['claimedByDeviceName']?.toString() ?? '',
        claimedDeviceToken: decoded['claimedDeviceToken']?.toString() ?? '',
      );
    } catch (error) {
      return CloudPairingStatusResult(
          ok: false, status: 'invalid', message: 'Pairing code failed: $error');
    }
  }

  // ignore: unused_element
  Future<CloudSyncResult> _pullLoginBootstrap(CloudSyncSettings settings,
      {DateTime? minSnapshotUpdatedAt}) async {
    final identity = store.appIdentity;
    try {
      await registerCurrentDevice(settings, transport: 'cloud');
      var pageCursor = '';
      var pulled = 0;
      const maxPages = 10;
      for (var page = 0; page < maxPages; page += 1) {
        final query = <String, String>{
          'store_id': identity.storeId,
          'branch_id': identity.branchId,
          'limit': '250',
          'bootstrap': 'login',
        };
        if (minSnapshotUpdatedAt != null) {
          query['min_snapshot_updated_at'] =
              minSnapshotUpdatedAt.toIso8601String();
        }
        if (pageCursor.isNotEmpty) query['cursor'] = pageCursor;

        final pull = await _client
            .get(settings.endpoint('/api/sync/pull', query),
                headers: _headers(settings))
            .timeout(const Duration(seconds: 30));
        if (pull.statusCode < 200 || pull.statusCode >= 300) {
          return CloudSyncResult(
              ok: false,
              message:
                  'Cloud login provisioning failed: ${pull.statusCode} ${pull.body}');
        }
        final decodedPull = jsonDecode(pull.body) as Map<String, dynamic>;
        final changes = _syncCore.filterOutLocalEchoes(
          _syncCore
              .decodeRemoteChanges(decodedPull['changes'] as List<dynamic>?),
        );
        pulled += await _syncCore.applyAuthoritativeChanges(changes);
        final hasMore = decodedPull['hasMore'] == true;
        pageCursor = (decodedPull['nextCursor'] ?? '').toString();
        if (!hasMore) break;
        if (pageCursor.isEmpty) {
          return const CloudSyncResult(
              ok: false,
              message:
                  'Cloud login provisioning pagination failed: missing next cursor.');
        }
      }
      // Do not save the global Cloud pull cursor here. This is only a partial
      // login bootstrap; leaving the cursor empty lets the post-login
      // provisioning sync download the complete snapshot from the beginning.
      return CloudSyncResult(
          ok: true,
          pulled: pulled,
          restoredSnapshot: pulled > 0,
          message: 'Pulled $pulled login provisioning record(s).');
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'Cloud login provisioning failed: $error');
    }
  }

  Future<CloudPairingClaimResult> claimPairingCode(
      CloudSyncSettings settings, String code,
      {CloudSyncProgressCallback? onProgress}) async {
    final current = store.appIdentity;
    if (current.isHost) {
      return const CloudPairingClaimResult(
          ok: false,
          message:
              'Host devices cannot pair as Cloud Clients. Use Host transfer instead.');
    }
    // A Client may configure both LAN and Cloud, but only one active transport
    // should run at a time. Pairing Cloud is therefore allowed for an existing
    // LAN Client as long as it is not a Host.
    // Client bootstrap pairing intentionally requires only the Cloud API URL and
    // a single-use pairing code. Account sessions stay on Host devices.
    if (!settings.enabled || settings.apiBaseUrl.trim().isEmpty) {
      return const CloudPairingClaimResult(
          ok: false, message: 'Cloud API URL is required.');
    }
    var deviceRegistered = false;
    onProgress?.call(0.08, 'Connecting to Cloud pairing service...');
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/pairing/claim'),
            headers: _headers(settings),
            body: jsonEncode({
              'code': code.trim(),
              'deviceId': store.deviceId,
              'deviceName': current.deviceName,
              'platform': current.platform.name,
              'appVersion': AppBrand.cloudAppVersion,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const CloudPairingClaimResult(
            ok: false,
            message:
                'Pairing code expired or already used. Ask the Host device for a new code.');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['ok'] != true) {
        return const CloudPairingClaimResult(
            ok: false,
            message:
                'Pairing code expired or already used. Ask the Host device for a new code.');
      }
      final claimedStoreId = decoded['storeId']?.toString() ?? current.storeId;
      final claimedBranchId =
          decoded['branchId']?.toString() ?? current.branchId;
      final claimedHostDeviceId =
          decoded['hostDeviceId']?.toString() ?? current.hostDeviceId;
      if (current.isClient && current.hostDeviceId.trim().isNotEmpty) {
        final mismatches = <String>[];
        if (current.storeId.trim().toUpperCase() !=
            claimedStoreId.trim().toUpperCase()) {
          mismatches.add('Store ID');
        }
        if (current.branchId.trim().toUpperCase() !=
            claimedBranchId.trim().toUpperCase()) {
          mismatches.add('Branch ID');
        }
        if (current.hostDeviceId.trim().toUpperCase() !=
            claimedHostDeviceId.trim().toUpperCase()) {
          mismatches.add('Host ID');
        }
        if (mismatches.isNotEmpty) {
          return CloudPairingClaimResult(
              ok: false,
              message:
                  'Pairing code belongs to a different Store (${mismatches.join(', ')}). Use the current Host pairing code.');
        }
      }
      final transport = decoded['transport']?.toString() == 'lan'
          ? SyncMode.lanOnly
          : SyncMode.cloudConnected;
      final identity = current.copyWith(
        storeId: claimedStoreId,
        branchId: claimedBranchId,
        hostDeviceId: claimedHostDeviceId,
        deviceRole: DeviceRole.client,
        syncMode: transport,
        activeSyncTransport: transport == SyncMode.lanOnly ? 'lan' : 'cloud',
        deviceToken: decoded['deviceToken']?.toString() ?? current.deviceToken,
        updatedAt: DateTime.now(),
      );
      onProgress?.call(0.22, 'Registering this device...');
      await store.updateAppIdentityDuringSetup(identity);
      deviceRegistered = true;

      if (identity.syncMode == SyncMode.cloudConnected ||
          identity.syncMode == SyncMode.marketplaceEnabled) {
        // Phase 3: Connect to Store is not considered complete until the same
        // unified Snapshot used by LAN is fully downloaded, imported and
        // verified. Cloud may still transfer through the server, but the
        // lifecycle is now identical to LAN: register -> snapshot chunks ->
        // import -> verify -> ready.
        final requestedAt = DateTime.now().toUtc();
        await CloudProvisioningStatus.markPending(
          requestedAt: requestedAt,
          message: 'Downloading full Store data before activating this device.',
        );

        CloudSyncResult request = const CloudSyncResult(
          ok: true,
          message: 'The latest available Cloud snapshot will be used.',
        );

        for (var attempt = 0; attempt < 6; attempt += 1) {
          if (attempt > 0) {
            onProgress?.call(0.28, 'Waiting for Host full snapshot...');
            await Future<void>.delayed(const Duration(seconds: 3));
          }
          await CloudProvisioningStatus.markAttempted(DateTime.now().toUtc());
          try {
            final envelope = await _downloadCloudSnapshotEnvelope(
              settings.copyWith(clearLastPullCursor: true),
              force: attempt == 0,
              onProgress: (value, label) {
                final scaled =
                    (0.24 + value * 0.50).clamp(0.24, 0.74).toDouble();
                onProgress?.call(scaled, label);
              },
            );
            onProgress?.call(
                0.78, 'Importing Cloud snapshot chunks locally...');
            await store.importSyncSnapshotJson(jsonEncode(envelope));
            await _markHostSnapshotGenerationApplied('cloud', envelope);
            onProgress?.call(0.88, 'Verifying local store data...');
            final verified = await store.verifyLocalBusinessDataIntegrity();
            if (store.needsInitialAdminSetup) {
              throw StateError(verified.message);
            }
            // Verification warnings should not restart pairing after a
            // successful import; retrying would just ask for the same snapshot
            // again and can loop forever.
            if (!verified.ok) {
              debugPrint(
                  'Cloud pairing completed with verification warnings: ${verified.message}');
            }
            final cursor =
                store.syncSnapshotGeneratedAtFromJson(jsonEncode(envelope));
            final sequence = store
                .syncSnapshotGeneratedSequenceFromJson(jsonEncode(envelope));
            await SyncDeviceStateStore.recordSyncResult(
              store.appIdentity,
              transport: 'cloud',
              appliedCursor: cursor,
              ackCursor: cursor,
              appliedSequence: sequence,
              ackSequence: sequence,
            );
            await CloudProvisioningStatus.markComplete(
              message: 'Full Store data downloaded.',
            );
            onProgress?.call(1.0, 'Cloud snapshot is ready.');
            final successMessage = verified.ok
                ? 'Device paired successfully. Full Store data downloaded. You can sign in now.'
                : 'Device paired successfully. Full Store data downloaded. You can sign in now. Verification warnings: ${verified.message}';
            return CloudPairingClaimResult(
              ok: true,
              message: successMessage,
              identity: store.appIdentity,
            );
          } catch (_) {
            request = await requestFreshHostSnapshot(settings,
                requestedAt: requestedAt);
            if (!request.ok) break;
          }
        }

        await CloudProvisioningStatus.markPending(
          requestedAt: requestedAt,
          message: 'The full Store snapshot is not complete yet.',
        );
        return CloudPairingClaimResult(
          ok: false,
          message: request.ok
              ? 'Device registered, but the full Store snapshot is not complete yet. Keep the Host online and try again.'
              : request.message,
          identity: store.appIdentity,
        );
      }
      return CloudPairingClaimResult(
          ok: true,
          message: 'Device paired successfully. Please sign in.',
          identity: identity);
    } catch (error) {
      if (deviceRegistered) {
        return CloudPairingClaimResult(
          ok: false,
          message:
              'Device registered, but the full Store snapshot is not complete. Keep the Host online and try again.',
          identity: store.appIdentity,
        );
      }
      return const CloudPairingClaimResult(
          ok: false,
          message:
              'Could not connect this device. Check the pairing code and try again.');
    }
  }

  Future<CloudStoreRecoveryResult> recoverExistingStoreFromCloud(
    CloudSyncSettings settings, {
    required String storeId,
    String recoveryKey = '',
    String? branchId,
    CloudSyncProgressCallback? onProgress,
  }) async {
    final previousIdentity = store.appIdentity;
    final cleanStoreId = storeId.trim().toUpperCase();
    final cleanBranchId = (branchId == null || branchId.trim().isEmpty)
        ? ''
        : branchId.trim().toUpperCase();
    final cleanRecoveryKey = recoveryKey.trim().toUpperCase();
    if (settings.apiBaseUrl.trim().isEmpty) {
      return const CloudStoreRecoveryResult(
          ok: false, message: 'Cloud API URL is required.');
    }
    if (!cleanStoreId.startsWith('ST-')) {
      return const CloudStoreRecoveryResult(
          ok: false, message: 'A valid Store ID is required.');
    }
    if (settings.accountToken.trim().isEmpty) {
      return const CloudStoreRecoveryResult(
          ok: false,
          message: 'Online account session is required. Please sign in again.');
    }

    try {
      onProgress?.call(0.10, 'Verifying online account and Store access...');
      final claimResponse = await _client
          .post(
            settings.endpoint('/api/sync/recovery/claim'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer ${settings.accountToken.trim()}',
            },
            body: jsonEncode({
              'storeId': cleanStoreId,
              'branchId': cleanBranchId,
              if (cleanRecoveryKey.isNotEmpty) 'recoveryKey': cleanRecoveryKey,
              'deviceId': store.deviceId,
              'deviceName': store.appIdentity.deviceName,
              'platform': store.appIdentity.platform.name,
              'appVersion': AppBrand.cloudAppVersion,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (claimResponse.statusCode < 200 || claimResponse.statusCode >= 300) {
        return CloudStoreRecoveryResult(
            ok: false,
            message:
                'Store recovery failed: ${claimResponse.statusCode} ${claimResponse.body}');
      }
      final claim = jsonDecode(claimResponse.body) as Map<String, dynamic>;
      if (claim['ok'] != true) {
        return CloudStoreRecoveryResult(
            ok: false,
            message: claim['error']?.toString() ?? 'Store recovery failed.');
      }

      final recoveredBranchId =
          (claim['branchId'] ?? claim['branch_id'] ?? cleanBranchId)
                  .toString()
                  .trim()
                  .isEmpty
              ? 'BR-MAIN1'
              : (claim['branchId'] ?? claim['branch_id'] ?? cleanBranchId)
                  .toString()
                  .trim()
                  .toUpperCase();
      final deviceToken =
          (claim['deviceToken'] ?? claim['device_token'] ?? '').toString();
      final hostDeviceId =
          (claim['hostDeviceId'] ?? claim['host_device_id'] ?? store.deviceId)
              .toString();
      final cloudTenantId =
          (claim['cloudTenantId'] ?? claim['cloud_tenant_id'] ?? '').toString();

      onProgress?.call(0.25, 'Recovering permanent Store identity...');
      await store.recoverExistingStoreIdentity(
        storeId: cleanStoreId,
        branchId: recoveredBranchId,
        recoveryKey: cleanRecoveryKey,
        hostDeviceId: hostDeviceId.isEmpty ? store.deviceId : hostDeviceId,
        deviceToken: deviceToken,
        cloudTenantId: cloudTenantId,
        deviceRole: DeviceRole.host,
        syncMode: SyncMode.cloudConnected,
      );
      await settings.copyWith(enabled: true, clearLastPullCursor: true).save();
      await CloudSyncSettings.clearSavedPullCursor();

      onProgress?.call(0.45, 'Downloading the latest Cloud snapshot...');
      var pageCursor = '';
      var pulled = 0;
      var restoredSnapshot = false;
      var allSnapshotSectionsComplete = true;
      const maxPages = 200;
      for (var page = 0; page < maxPages; page += 1) {
        final query = <String, String>{
          'store_id': cleanStoreId,
          'branch_id': recoveredBranchId,
          'limit': '1000',
        };
        if (pageCursor.isNotEmpty) query['cursor'] = pageCursor;
        final pull = await _client
            .get(settings.endpoint('/api/sync/pull', query),
                headers: _headers(settings))
            .timeout(const Duration(seconds: 20));
        if (pull.statusCode < 200 || pull.statusCode >= 300) {
          return CloudStoreRecoveryResult(
              ok: false,
              message:
                  'Store identity recovered, but snapshot download failed: ${pull.statusCode} ${pull.body}',
              identity: store.appIdentity);
        }
        final decodedPull = jsonDecode(pull.body) as Map<String, dynamic>;
        if ((decodedPull['source'] ?? '').toString() == 'entity_snapshots') {
          final pageAllSectionsComplete =
              decodedPull['allSnapshotSectionsComplete'] == true;
          allSnapshotSectionsComplete =
              allSnapshotSectionsComplete && pageAllSectionsComplete;
          await CloudProvisioningStatus.updateSnapshotSections(
            decodedPull['snapshotSections'] is Map<String, dynamic>
                ? decodedPull['snapshotSections'] as Map<String, dynamic>
                : null,
            allComplete: pageAllSectionsComplete,
          );
        }
        if (decodedPull['needsSnapshot'] == true) {
          await CloudSyncSettings.clearSavedPullCursor();
          return CloudStoreRecoveryResult(
            ok: false,
            message:
                'Cloud event log gap detected. Snapshot repair is required.',
            identity: store.appIdentity,
            restoredSnapshot: true,
            pulled: pulled,
          );
        }
        final changes = _syncCore.filterOutLocalEchoes(
          _syncCore
              .decodeRemoteChanges(decodedPull['changes'] as List<dynamic>?),
        );
        restoredSnapshot = restoredSnapshot ||
            changes.isNotEmpty ||
            decodedPull['source'] == 'entity_snapshots';
        pulled += await _syncCore.applyAuthoritativeChanges(changes);
        onProgress?.call(
            (0.45 + (page + 1) * 0.04).clamp(0.45, 0.88).toDouble(),
            'Applied $pulled recovered record(s)...');
        if (decodedPull['hasMore'] != true) {
          final generatedAt =
              DateTime.tryParse(decodedPull['generatedAt']?.toString() ?? '');
          if (generatedAt != null) {
            await settings.copyWith(lastPullCursor: generatedAt).save();
          }
          break;
        }
        pageCursor = (decodedPull['nextCursor'] ?? '').toString();
        if (pageCursor.isEmpty) {
          return CloudStoreRecoveryResult(
              ok: false,
              message: 'Store recovery pagination failed.',
              identity: store.appIdentity,
              pulled: pulled);
        }
      }

      final deviceLimit = claim['deviceLimit'] is Map
          ? CloudDeviceLimitStatus.fromJson(
              Map<String, dynamic>.from(claim['deviceLimit'] as Map),
            )
          : null;

      onProgress?.call(0.90, 'Publishing recovered Host snapshot...');
      await publishBootstrapSnapshotToCloud(settings,
          force: true, onProgress: onProgress);
      await _pushPendingToEndpoint(settings, 'cloud', '/api/sync/push');
      await sendHostHeartbeat(settings);
      onProgress?.call(1.0, 'Store recovered.');
      await _restorePreviousSyncMode(previousIdentity);
      return CloudStoreRecoveryResult(
        ok: true,
        message: 'Current Store recovered successfully.',
        identity: store.appIdentity,
        restoredSnapshot: restoredSnapshot,
        pulled: pulled,
        username: (claim['username'] ?? '').toString(),
        loginName: (claim['loginName'] ?? claim['login_name'] ?? '').toString(),
        storeName: (claim['storeName'] ?? claim['store_name'] ?? '').toString(),
        storeSlug: (claim['storeSlug'] ?? claim['store_slug'] ?? '').toString(),
        cloudSyncEnabled: claim['cloudSyncEnabled'] == true ||
            claim['cloud_sync_enabled'] == true,
        deviceLimit: deviceLimit,
      );
    } catch (error) {
      await _restorePreviousSyncMode(previousIdentity);
      return CloudStoreRecoveryResult(
          ok: false, message: 'Store recovery failed: $error');
    }
  }

  Future<CloudStoreRecoveryResult> recoverExistingStoreIdentityFromCloud(
    CloudSyncSettings settings, {
    required String storeId,
    String recoveryKey = '',
    String? branchId,
    CloudSyncProgressCallback? onProgress,
  }) async {
    final previousIdentity = store.appIdentity;
    final cleanStoreId = storeId.trim().toUpperCase();
    final cleanBranchId = (branchId == null || branchId.trim().isEmpty)
        ? ''
        : branchId.trim().toUpperCase();
    final cleanRecoveryKey = recoveryKey.trim().toUpperCase();
    if (settings.apiBaseUrl.trim().isEmpty) {
      return const CloudStoreRecoveryResult(
          ok: false, message: 'Cloud API URL is required.');
    }
    if (!cleanStoreId.startsWith('ST-')) {
      return const CloudStoreRecoveryResult(
          ok: false, message: 'A valid Store ID is required.');
    }
    if (settings.accountToken.trim().isEmpty) {
      return const CloudStoreRecoveryResult(
          ok: false,
          message: 'Online account session is required. Please sign in again.');
    }

    try {
      onProgress?.call(0.10, 'Verifying online account and Store access...');
      final claimResponse = await _client
          .post(
            settings.endpoint('/api/sync/recovery/claim'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer ${settings.accountToken.trim()}',
            },
            body: jsonEncode({
              'mode': 'identity',
              'storeId': cleanStoreId,
              'branchId': cleanBranchId,
              if (cleanRecoveryKey.isNotEmpty) 'recoveryKey': cleanRecoveryKey,
              'deviceId': store.deviceId,
              'deviceName': store.appIdentity.deviceName,
              'platform': store.appIdentity.platform.name,
              'appVersion': AppBrand.cloudAppVersion,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (claimResponse.statusCode < 200 || claimResponse.statusCode >= 300) {
        return CloudStoreRecoveryResult(
            ok: false,
            message:
                'Store identity recovery failed: ${claimResponse.statusCode} ${claimResponse.body}');
      }
      final claim = jsonDecode(claimResponse.body) as Map<String, dynamic>;
      if (claim['ok'] != true) {
        return CloudStoreRecoveryResult(
            ok: false,
            message: claim['error']?.toString() ??
                'Store identity recovery failed.');
      }

      final recoveredBranchId =
          (claim['branchId'] ?? claim['branch_id'] ?? cleanBranchId)
                  .toString()
                  .trim()
                  .isEmpty
              ? 'BR-MAIN1'
              : (claim['branchId'] ?? claim['branch_id'] ?? cleanBranchId)
                  .toString()
                  .trim()
                  .toUpperCase();
      final deviceToken =
          (claim['deviceToken'] ?? claim['device_token'] ?? '').toString();
      final hostDeviceId =
          (claim['hostDeviceId'] ?? claim['host_device_id'] ?? store.deviceId)
              .toString();
      final cloudTenantId =
          (claim['cloudTenantId'] ?? claim['cloud_tenant_id'] ?? '').toString();
      final deviceLimit = claim['deviceLimit'] is Map
          ? CloudDeviceLimitStatus.fromJson(
              Map<String, dynamic>.from(claim['deviceLimit'] as Map),
            )
          : null;

      onProgress?.call(0.25, 'Recovering permanent Store identity...');
      await store.recoverExistingStoreIdentity(
        storeId: cleanStoreId,
        branchId: recoveredBranchId,
        recoveryKey: cleanRecoveryKey,
        hostDeviceId: hostDeviceId.isEmpty ? store.deviceId : hostDeviceId,
        deviceToken: deviceToken,
        cloudTenantId: cloudTenantId,
        deviceRole: DeviceRole.host,
        syncMode: SyncMode.cloudConnected,
      );
      await settings.copyWith(enabled: true, clearLastPullCursor: true).save();
      await CloudSyncSettings.clearSavedPullCursor();
      onProgress?.call(1.0, 'Store identity recovered.');
      await _restorePreviousSyncMode(previousIdentity);
      return CloudStoreRecoveryResult(
        ok: true,
        message: 'Store identity recovered.',
        identity: store.appIdentity,
        username: (claim['username'] ?? '').toString(),
        loginName: (claim['loginName'] ?? claim['login_name'] ?? '').toString(),
        storeName: (claim['storeName'] ?? claim['store_name'] ?? '').toString(),
        storeSlug: (claim['storeSlug'] ?? claim['store_slug'] ?? '').toString(),
        cloudSyncEnabled: claim['cloudSyncEnabled'] == true ||
            claim['cloud_sync_enabled'] == true,
        deviceLimit: deviceLimit,
      );
    } catch (error) {
      await _restorePreviousSyncMode(previousIdentity);
      return CloudStoreRecoveryResult(
          ok: false, message: 'Store identity recovery failed: $error');
    }
  }

  Future<bool> _shouldRequestFreshSnapshotForGeneration(
    String transport,
    String generation, {
    Duration cooldown = const Duration(minutes: 15),
  }) async {
    final cleanGeneration = generation.trim();
    if (cleanGeneration.isEmpty) return true;
    final applied =
        LocalDatabaseService.getString(_snapshotGenerationKey(transport)) ?? '';
    if (applied.trim() == cleanGeneration) return false;
    final requested = LocalDatabaseService.getString(
            _snapshotRequestKey(transport, cleanGeneration)) ??
        '';
    final requestedAtRaw = LocalDatabaseService.getString(
            _snapshotRequestAtKey(transport, cleanGeneration)) ??
        '';
    final requestedAt = DateTime.tryParse(requestedAtRaw);
    if (requested == cleanGeneration &&
        requestedAt != null &&
        DateTime.now().difference(requestedAt) < cooldown) {
      return false;
    }
    return true;
  }

  Future<void> _markFreshSnapshotRequestedForGeneration(
      String transport, String generation) async {
    final cleanGeneration = generation.trim();
    if (cleanGeneration.isEmpty) return;
    await LocalDatabaseService.setString(
        _snapshotRequestKey(transport, cleanGeneration), cleanGeneration);
    await LocalDatabaseService.setString(
        _snapshotRequestAtKey(transport, cleanGeneration),
        DateTime.now().toIso8601String());
  }

  String _newCloudRebuildRequestId() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final device = store.deviceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return 'cloud-rebuild-$now-${device.isEmpty ? 'device' : device}';
  }

  Future<CloudSyncResult> requestFreshHostSnapshot(CloudSyncSettings settings,
      {DateTime? requestedAt, String snapshotGeneration = ''}) async {
    final identity = store.appIdentity;
    if (identity.isHost) {
      return const CloudSyncResult(
          ok: true, message: 'Host can publish its snapshot directly.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'Cloud Sync is not ready yet.');
    }
    final cleanGeneration = snapshotGeneration.trim();
    if (cleanGeneration.isNotEmpty &&
        !await _shouldRequestFreshSnapshotForGeneration(
            'cloud', cleanGeneration)) {
      return const CloudSyncResult(
          ok: true,
          message:
              'A snapshot for this generation was already requested or applied, so no duplicate request will be sent.');
    }
    await _markFreshSnapshotRequestedForGeneration('cloud', cleanGeneration);
    return const CloudSyncResult(
      ok: true,
      message:
          'Fresh Host snapshot will be fetched directly through the relay on the next attempt.',
    );
  }

  Future<CloudSyncResult> rebuildFromCloudHostSnapshot(
      CloudSyncSettings settings,
      {CloudSyncProgressCallback? onProgress,
      bool requestFreshSnapshot = true,
      String expectedSnapshotGeneration = '',
      String expectedRestoreCommandId = ''}) async {
    final identity = store.appIdentity;
    if (identity.isHost) {
      return const CloudSyncResult(
          ok: false,
          message: 'Host rebuild is only available for Client devices.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false,
          message: 'Cloud API URL and paired device token are required.');
    }

    // Unified safe rebuild contract:
    // 1) send every local Client change to the Host,
    // 2) wait until the Host confirms those changes,
    // 3) request a fresh Host snapshot,
    // 4) apply only a snapshot generated after the request.
    // The local database/ACK are not reset until _applyCloudSnapshotEnvelope().
    final minimumSnapshotSequence = [
      SyncDeviceStateStore.lastAppliedSequenceForTransport(identity, 'cloud'),
      SyncDeviceStateStore.lastAckSequenceForTransport(identity, 'cloud'),
    ].reduce((a, b) => a > b ? a : b);
    final rebuildRequestId = _newCloudRebuildRequestId();
    final drain = await _drainClientPendingChangesBeforeRebuild(
      settings,
      onProgress: onProgress,
    );
    if (!drain.ok || drain.syncDeferred) return drain;

    CloudSyncResult? freshSnapshotRequest;
    final snapshotRequestedAt = DateTime.now().toUtc();
    if (requestFreshSnapshot) {
      onProgress?.call(
          0.24, 'Requesting a fresh Host snapshot after Client changes were confirmed...');
      freshSnapshotRequest = await requestFreshHostSnapshot(
        settings,
        requestedAt: snapshotRequestedAt,
        snapshotGeneration: expectedSnapshotGeneration,
      );
      if (!freshSnapshotRequest.ok) {
        return CloudSyncResult(
          ok: false,
          pushed: drain.pushed,
          message: freshSnapshotRequest.message,
          syncDeferred: freshSnapshotRequest.syncDeferred,
        );
      }
    } else {
      // Even automatic generation/restore rebuilds use the same safe path: do
      // not trust an older cached snapshot after draining local Client changes.
      onProgress?.call(0.24,
          'Waiting for the fresh Host snapshot that matches the rebuild request...');
    }

    onProgress?.call(
        0.30, 'Waiting for fresh Host snapshot through the relay...');
    for (var attempt = 0; attempt < 8; attempt += 1) {
      if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final envelope = await _downloadCloudSnapshotEnvelopeViaRelay(
          settings.copyWith(clearLastPullCursor: true),
          force: true,
          rebuildRequestId: rebuildRequestId,
          requiredMinSequence: minimumSnapshotSequence,
          onProgress: (value, label) {
            final scaled = (0.32 + value * 0.48).clamp(0.0, 0.82).toDouble();
            onProgress?.call(scaled, label);
          },
        );
        if (!_cloudSnapshotEnvelopeMatchesFreshRebuild(
          envelope,
          minimumSequence: minimumSnapshotSequence,
          rebuildRequestId: rebuildRequestId,
          requestedAt: snapshotRequestedAt,
        )) {
          onProgress?.call(
            (0.34 + attempt * 0.05).clamp(0.34, 0.74).toDouble(),
            'Ignoring older Host snapshot and waiting for the fresh rebuild snapshot (${attempt + 1}/8)...',
          );
          continue;
        }
        final applied = await _applyCloudSnapshotEnvelope(
          envelope,
          settings: settings,
          onProgress: onProgress,
          expectedSnapshotGeneration: expectedSnapshotGeneration,
          expectedRestoreCommandId: expectedRestoreCommandId,
        );
        return CloudSyncResult(
          ok: applied.ok,
          pushed: drain.pushed + applied.pushed,
          pulled: applied.pulled,
          restoredSnapshot: applied.restoredSnapshot,
          syncDeferred: applied.syncDeferred,
          message: applied.message,
        );
      } catch (_) {
        onProgress?.call(
          (0.34 + attempt * 0.05).clamp(0.34, 0.74).toDouble(),
          'Waiting for fresh Cloud snapshot relay (${attempt + 1}/8)...',
        );
      }
    }

    return CloudSyncResult(
      ok: false,
      pushed: drain.pushed,
      message:
          'Cloud rebuild sent pending Client changes and requested a fresh Host snapshot, but no matching fresh snapshot was available yet. Keep the Host online and retry. ${freshSnapshotRequest?.message ?? ''}',
      syncDeferred: true,
    );
  }

  Future<CloudSyncResult?> checkCurrentDeviceAccess(
      CloudSyncSettings settings) async {
    final identity = store.appIdentity;
    if (!identity.isClient || !settings.isConfigured) return null;
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/device-access'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'deviceId': store.deviceId,
              'deviceToken': identity.deviceToken,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return CloudSyncResult(
            ok: false,
            message:
                'Device Cloud access check failed: ${response.statusCode} ${response.body}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['wipeRequired'] == true ||
          decoded['action'] == 'wipe_local_data') {
        final wipedDeviceId = store.deviceId;
        final wipedStoreId = identity.storeId;
        final wipedBranchId = identity.branchId;
        final wipedToken = identity.deviceToken;
        await _confirmCloudWipe(
          settings,
          storeId: wipedStoreId,
          branchId: wipedBranchId,
          deviceId: wipedDeviceId,
          deviceToken: wipedToken,
        );
        await store.factoryResetLocalDevice(enforcePermission: false);
        return const CloudSyncResult(
            ok: false,
            message: 'Device revoked by Host. Local data was wiped.');
      }
      if (decoded['suspended'] == true || decoded['authorized'] == false) {
        final reason = decoded['reason']?.toString() ??
            'This device is suspended or not authorized for Cloud sync.';
        if (decoded['suspended'] == true) {
          await store.markSuspendedByHost(reason: reason);
        }
        return CloudSyncResult(ok: false, message: reason);
      }
      await store.clearSuspendedByHost();
      return null;
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'Device Cloud access check failed: $error');
    }
  }

  Future<CloudSyncResult> setDeviceSuspended(
      CloudSyncSettings settings, String deviceId,
      {required bool suspended}) async {
    final identity = store.appIdentity;
    if (!identity.isHost) {
      return const CloudSyncResult(
          ok: false, message: 'Only the Host can suspend devices.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'Cloud API URL and token are required.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/device-suspend'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'deviceId': deviceId,
              'suspended': suspended
            }),
          )
          .timeout(const Duration(seconds: 10));
      return CloudSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? (suspended
                ? 'Device suspended in Cloud.'
                : 'Device resumed in Cloud.')
            : 'Device suspend/resume failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'Device suspend/resume failed: $error');
    }
  }

  Future<CloudSyncResult> revokeDevice(
      CloudSyncSettings settings, String deviceId) async {
    final identity = store.appIdentity;
    if (!identity.isHost) {
      return const CloudSyncResult(
          ok: false, message: 'Only the Host can revoke devices.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'Cloud API URL and token are required.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/device-revoke'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'deviceId': deviceId
            }),
          )
          .timeout(const Duration(seconds: 10));
      return CloudSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? 'Device revoked.'
            : 'Device revoke failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'Device revoke failed: $error');
    }
  }

  Future<CloudSyncResult> deleteDeviceRecord(
      CloudSyncSettings settings, String deviceId) async {
    final identity = store.appIdentity;
    if (!identity.isHost) {
      return const CloudSyncResult(
          ok: false, message: 'Only the Host can remove devices.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'Cloud API URL and token are required.');
    }
    try {
      final response = await _client
          .delete(
            settings.endpoint('/api/sync/devices'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'deviceId': deviceId,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return CloudSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? 'Device record removed.'
            : 'Device remove failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'Device remove failed: $error');
    }
  }

  Map<String, String> _headers(CloudSyncSettings settings) {
    final identity = store.appIdentity;
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      // Clients authenticate with their own per-device token. Host/account
      // flows authenticate with the online account session.
      if (!identity.isClient && settings.accountToken.trim().isNotEmpty)
        'Authorization': 'Bearer ${settings.accountToken.trim()}',
      'X-Device-Id': store.deviceId,
      'X-Device-Token': identity.deviceToken,
      'X-Device-Role': identity.deviceRole.name,
      'X-Sync-Transport': identity.transportType,
      'X-Store-Id': identity.storeId,
      'X-Branch-Id': identity.branchId,
    };
  }

  String _newRelayRequestId() {
    _relayRequestCounter += 1;
    return '${store.deviceId}-${DateTime.now().microsecondsSinceEpoch}-${_relayRequestCounter.toRadixString(36)}';
  }

  Future<_RealtimeChannelSession> _openRealtimeChannel(
    CloudSyncSettings settings, {
    bool includeSequenceHint = true,
  }) async {
    final identity = store.appIdentity;
    final state = SyncDeviceStateStore.load(identity);
    final ticketQuery = <String, String>{
      'store_id': identity.storeId,
      'branch_id': identity.branchId,
      'role': identity.isHost ? 'host' : 'client',
    };
    final ticketResponse = await _client
        .get(settings.endpoint('/api/sync/realtime-ticket', ticketQuery),
            headers: _headers(settings))
        .timeout(const Duration(seconds: 8));
    if (ticketResponse.statusCode < 200 || ticketResponse.statusCode >= 300) {
      throw StateError(
          'Realtime ticket failed: ${ticketResponse.statusCode} ${ticketResponse.body}');
    }
    final ticketPayload = jsonDecode(ticketResponse.body);
    final ticket = ticketPayload is Map ? (ticketPayload['ticket'] ?? '') : '';
    if (ticket.toString().trim().isEmpty) {
      throw StateError('Realtime ticket response is missing ticket.');
    }
    final query = <String, String>{
      'ticket': ticket.toString(),
    };
    if (includeSequenceHint &&
        identity.isClient &&
        state.lastAppliedSequence > 0) {
      query['since_sequence'] = state.lastAppliedSequence.toString();
    }
    final uri = settings.realtimeEndpoint('/api/sync/realtime', query);
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] cloudRealtime:connect role=${identity.deviceRole.name} '
      'device=${identity.deviceId} url=${uri.replace(queryParameters: {
            ...uri.queryParameters,
            'ticket': '***',
          })}',
    );
    return _RealtimeChannelSession(
      channel: WebSocketChannel.connect(uri),
      uri: uri,
    );
  }

  Future<Map<String, dynamic>> _sendRealtimeRequest(
    CloudSyncSettings settings, {
    required String requestKind,
    required Map<String, dynamic> payload,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final session = await _RealtimeRelaySession.open(
      this,
      settings,
      includeSequenceHint: false,
    );
    try {
      return await session.sendRequest(
        requestKind,
        payload,
        timeout: timeout,
      );
    } finally {
      await session.close();
    }
  }

  Future<bool> _sendRealtimeBroadcast(
    CloudSyncSettings settings, {
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    final session = await _openRealtimeChannel(
      settings,
      includeSequenceHint: false,
    );
    try {
      session.channel.sink.add(jsonEncode({
        'type': type,
        ...payload,
      }));
      return true;
    } finally {
      await session.channel.sink.close();
    }
  }

  void _pruneExpiredRelaySnapshotJobs() {
    final now = DateTime.now().toUtc();
    final expired = _relaySnapshotJobs.entries
        .where((entry) => entry.value.expiresAt.isBefore(now))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final jobId in expired) {
      _relaySnapshotJobs.remove(jobId);
    }
  }

  Future<_CloudSnapshotRelayJob?> _buildRelaySnapshotJob(
    String snapshotKind, {
    String rebuildRequestId = '',
    int requiredMinSequence = 0,
  }) async {
    final kind =
        snapshotKind.trim().isEmpty ? 'full_store' : snapshotKind.trim();
    if (kind != 'login_bootstrap') {
      await store.ensureHeavyDataLoaded();
    }
    final chunks = kind == 'login_bootstrap'
        ? await store.exportCloudLoginBootstrapSnapshotChunks()
        : await store.exportCloudBootstrapSnapshotChunks(maxItemsPerChunk: 300);
    if (chunks.isEmpty) return null;
    if (kind != 'login_bootstrap' &&
        !_relaySnapshotHasBusinessCollections(chunks)) {
      return null;
    }
    final envelope = store.unifiedSnapshotPayloadFromChunks(chunks);
    final cleanRebuildRequestId = rebuildRequestId.trim();
    if (cleanRebuildRequestId.isNotEmpty) {
      envelope['rebuildRequestId'] = cleanRebuildRequestId;
      envelope['snapshotRequestId'] = cleanRebuildRequestId;
      envelope['requiredMinSequence'] = requiredMinSequence;
      envelope['freshRebuildSnapshot'] = true;
      for (final chunk in chunks) {
        chunk['rebuildRequestId'] = cleanRebuildRequestId;
        chunk['snapshotRequestId'] = cleanRebuildRequestId;
        chunk['requiredMinSequence'] = requiredMinSequence;
        chunk['freshRebuildSnapshot'] = true;
      }
    }
    final jobId = (chunks.first['jobId'] ?? '').toString().trim();
    if (jobId.isEmpty) return null;
    final job = _CloudSnapshotRelayJob(
      jobId: jobId,
      kind: kind,
      createdAt: DateTime.now().toUtc(),
      chunks: chunks,
      envelope: envelope,
    );
    _pruneExpiredRelaySnapshotJobs();
    _relaySnapshotJobs[jobId] = job;
    return job;
  }

  bool _relaySnapshotHasBusinessCollections(
    List<Map<String, dynamic>> chunks,
  ) {
    for (final chunk in chunks) {
      final collection = (chunk['collection'] ?? '').toString().trim();
      if (collection.isEmpty || collection == '_meta') continue;
      return true;
    }
    return false;
  }

  _CloudSnapshotRelayJob? _relaySnapshotJob(String jobId) {
    final cleanJobId = jobId.trim();
    if (cleanJobId.isEmpty) return null;
    _pruneExpiredRelaySnapshotJobs();
    final job = _relaySnapshotJobs[cleanJobId];
    if (job == null) return null;
    if (job.expiresAt.isBefore(DateTime.now().toUtc())) {
      _relaySnapshotJobs.remove(cleanJobId);
      return null;
    }
    return job;
  }

  void _releaseRelaySnapshotJob(String jobId) {
    final cleanJobId = jobId.trim();
    if (cleanJobId.isEmpty) return;
    _relaySnapshotJobs.remove(cleanJobId);
  }

  Future<CloudRealtimeSignal?> _handleRealtimePacket(
    CloudSyncSettings settings,
    WebSocketChannel channel,
    Map<String, dynamic> decoded,
  ) async {
    final identity = store.appIdentity;
    final type = (decoded['type'] ?? '').toString();
    if (type == 'realtime_welcome') return null;

    if (identity.isHost && type == 'relay_request') {
      final requestId = (decoded['requestId'] ?? decoded['request_id'] ?? '')
          .toString()
          .trim();
      final requestKind = (decoded['requestKind'] ??
              decoded['request_kind'] ??
              decoded['kind'] ??
              '')
          .toString()
          .trim();
      if (requestId.isEmpty) return null;

      if (requestKind == 'cloud_snapshot_manifest') {
        final snapshotKind =
            (decoded['snapshotKind'] ?? decoded['snapshot_kind'] ?? '')
                .toString()
                .trim();
        final rebuildRequestId = (decoded['rebuildRequestId'] ??
                decoded['rebuild_request_id'] ??
                decoded['snapshotRequestId'] ??
                decoded['snapshot_request_id'] ??
                '')
            .toString()
            .trim();
        final requiredMinSequence = int.tryParse(
                (decoded['requiredMinSequence'] ??
                        decoded['required_min_sequence'] ??
                        0)
                    .toString()) ??
            0;
        final job = await _buildRelaySnapshotJob(
          snapshotKind,
          rebuildRequestId: rebuildRequestId,
          requiredMinSequence: requiredMinSequence,
        );
        if (job == null) {
          channel.sink.add(jsonEncode({
            'type': 'relay_response',
            'requestId': requestId,
            'ok': false,
            'error': 'Host snapshot could not be prepared.',
            'serverTime': DateTime.now().toIso8601String(),
          }));
          return null;
        }
        final generatedSequence = int.tryParse(
                (job.envelope['syncGeneratedSequence'] ?? 0).toString()) ??
            0;
        if (requiredMinSequence > 0 && generatedSequence < requiredMinSequence) {
          _releaseRelaySnapshotJob(job.jobId);
          channel.sink.add(jsonEncode({
            'type': 'relay_response',
            'requestId': requestId,
            'ok': false,
            'error':
                'Host snapshot is older than the confirmed Client changes. Retry after Host finishes applying requests.',
            'serverTime': DateTime.now().toIso8601String(),
          }));
          return null;
        }
        channel.sink.add(jsonEncode({
          'type': 'relay_response',
          'requestId': requestId,
          'ok': true,
          'jobId': job.jobId,
          'snapshotFormat': job.envelope['snapshotFormat'],
          'snapshotVersion': job.envelope['snapshotVersion'],
          'snapshotKind': job.envelope['snapshotKind'],
          'snapshotManifest': job.envelope['snapshotManifest'],
          'totalChunks': job.chunks.length,
          'syncGeneratedAt': job.envelope['syncGeneratedAt'],
          'syncGeneratedSequence': job.envelope['syncGeneratedSequence'],
          'hostSnapshotGeneration': job.envelope['hostSnapshotGeneration'],
          'snapshotGeneration': job.envelope['snapshotGeneration'],
          'hostRestoreCommandId': job.envelope['hostRestoreCommandId'],
          'restoreCommandId': job.envelope['restoreCommandId'],
          'rebuildRequestId': job.envelope['rebuildRequestId'],
          'snapshotRequestId': job.envelope['snapshotRequestId'],
          'requiredMinSequence': job.envelope['requiredMinSequence'],
          'freshRebuildSnapshot': job.envelope['freshRebuildSnapshot'],
          'serverTime': DateTime.now().toIso8601String(),
        }));
        return null;
      }

      if (requestKind == 'cloud_snapshot_chunk') {
        final jobId =
            (decoded['jobId'] ?? decoded['job_id'] ?? '').toString().trim();
        final ordinal = int.tryParse(
                (decoded['ordinal'] ?? decoded['chunkOrdinal'] ?? 0)
                    .toString()) ??
            0;
        final job = _relaySnapshotJob(jobId);
        if (job == null || ordinal < 0 || ordinal >= job.chunks.length) {
          channel.sink.add(jsonEncode({
            'type': 'relay_response',
            'requestId': requestId,
            'ok': false,
            'error': 'Snapshot chunk is unavailable.',
            'serverTime': DateTime.now().toIso8601String(),
          }));
          return null;
        }
        channel.sink.add(jsonEncode({
          'type': 'relay_response',
          'requestId': requestId,
          'ok': true,
          'jobId': job.jobId,
          'ordinal': ordinal,
          'totalChunks': job.chunks.length,
          'chunk': job.chunks[ordinal],
          'serverTime': DateTime.now().toIso8601String(),
        }));
        return null;
      }

      if (requestKind == 'cloud_snapshot_release') {
        final jobId =
            (decoded['jobId'] ?? decoded['job_id'] ?? '').toString().trim();
        _releaseRelaySnapshotJob(jobId);
        channel.sink.add(jsonEncode({
          'type': 'relay_response',
          'requestId': requestId,
          'ok': true,
          'released': true,
          'serverTime': DateTime.now().toIso8601String(),
        }));
        return null;
      }

      if (requestKind == 'cloud_client_push') {
        final rawChanges =
            decoded['changes'] as List<dynamic>? ?? const <dynamic>[];
        final changes = _syncCore.filterOutLocalEchoes(
          _syncCore.decodeRemoteChanges(rawChanges),
        );
        final accepted = await _syncCore.acceptClientChangesOnHost(
          changes,
          mirrorToCloud: false,
          verifyApplied: true,
        );
        final response = <String, dynamic>{
          'type': 'relay_response',
          'requestId': requestId,
          'ok': true,
          'ackIds': accepted.ackIds,
          'rejected': accepted.rejected.entries
              .map((entry) => {'id': entry.key, 'reason': entry.value})
              .toList(),
          'latestSequence': store.latestStoredAuthoritativeSequence,
          'serverTime': DateTime.now().toIso8601String(),
        };
        channel.sink.add(jsonEncode(response));
        channel.sink.add(jsonEncode({
          'type': 'sync_changed',
          'changed': true,
          'latestSequence': store.latestStoredAuthoritativeSequence,
          'pendingRequests': 0,
          'relayKind': 'cloud_client_push',
        }));
        return null;
      }

      if (requestKind == 'cloud_client_pull') {
        final sinceSequence = int.tryParse(
                (decoded['sinceSequence'] ?? decoded['since_sequence'] ?? 0)
                    .toString()) ??
            0;
        final since = DateTime.tryParse(
            (decoded['since'] ?? decoded['sinceAt'] ?? '').toString());
        final minSnapshotUpdatedAt = DateTime.tryParse(
            (decoded['minSnapshotUpdatedAt'] ??
                    decoded['min_snapshot_updated_at'] ??
                    '')
                .toString());
        if (sinceSequence <= 0 && since == null) {
          channel.sink.add(jsonEncode({
            'type': 'relay_response',
            'requestId': requestId,
            'ok': false,
            'error':
                'A relay pull requires a cloud sequence baseline. Use the snapshot path first.',
            'serverTime': DateTime.now().toIso8601String(),
          }));
          return null;
        }
        final response = Map<String, dynamic>.from(
          jsonDecode(
            store.exportSyncChangesJson(
              since: since,
              sinceSequence: sinceSequence,
            ),
          ) as Map,
        );
        response['type'] = 'relay_response';
        response['requestId'] = requestId;
        response['ok'] = true;
        response['source'] = 'relay';
        response['hasMore'] = false;
        response['nextCursor'] = null;
        response['serverTime'] = DateTime.now().toIso8601String();
        if (minSnapshotUpdatedAt != null) {
          response['minSnapshotUpdatedAt'] =
              minSnapshotUpdatedAt.toIso8601String();
        }
        channel.sink.add(jsonEncode(response));
        return null;
      }

      channel.sink.add(jsonEncode({
        'type': 'relay_response',
        'requestId': requestId,
        'ok': false,
        'error': 'Unknown relay request kind: $requestKind',
        'serverTime': DateTime.now().toIso8601String(),
      }));
      return null;
    }

    final changed = decoded['changed'] == true;
    if (!changed) return null;
    final latestSequence =
        int.tryParse((decoded['latestSequence'] ?? '0').toString()) ?? 0;
    final pendingRequests =
        int.tryParse((decoded['pendingRequests'] ?? '0').toString()) ?? 0;
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] cloudRealtime:event type=$type '
      'latestSequence=$latestSequence pendingRequests=$pendingRequests',
    );
    return CloudRealtimeSignal(
      type: type,
      latestSequence: latestSequence,
      pendingRequests: pendingRequests,
    );
  }

  Future<void> _confirmCloudWipe(
    CloudSyncSettings settings, {
    required String storeId,
    required String branchId,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      await _client
          .post(
            settings.endpoint('/api/sync/device-wipe-ack'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (store.appIdentity.isHost &&
                  settings.accountToken.trim().isNotEmpty)
                'Authorization': 'Bearer ${settings.accountToken.trim()}',
              'X-Device-Id': deviceId,
              'X-Device-Token': deviceToken,
              'X-Device-Role': 'client',
              'X-Sync-Transport': 'cloud',
              'X-Store-Id': storeId,
              'X-Branch-Id': branchId,
            },
            body: jsonEncode({
              'storeId': storeId,
              'branchId': branchId,
              'deviceId': deviceId,
              'deviceToken': deviceToken,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Keep wipe_pending on Cloud when confirmation cannot be delivered.
      // The next contact will receive the wipe command again.
    }
  }

  Future<CloudSyncResult> registerCurrentDevice(CloudSyncSettings settings,
      {String transport = 'cloud'}) async {
    final identity = store.appIdentity;
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'Cloud API URL and token are required.');
    }
    final deviceState = SyncDeviceStateStore.load(identity);
    final lastAppliedCursor =
        SyncDeviceStateStore.lastAppliedCursorForTransport(identity, transport);
    final lastAckCursor =
        SyncDeviceStateStore.lastAckCursorForTransport(identity, transport);
    final lastAppliedSequence =
        SyncDeviceStateStore.lastAppliedSequenceForTransport(identity, transport);
    final lastAckSequence =
        SyncDeviceStateStore.lastAckSequenceForTransport(identity, transport);
    final appliedSnapshotGeneration =
        LocalDatabaseService.getString(_snapshotGenerationKey(transport)) ?? '';
    if (identity.isClient &&
        transport == 'cloud' &&
        lastAppliedSequence <= 0 &&
        lastAckSequence <= 0 &&
        (lastAppliedCursor != null || appliedSnapshotGeneration.trim().isNotEmpty)) {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] cloudRegister:skipZeroAckPublish '
        'device=${identity.deviceId} appliedGeneration=$appliedSnapshotGeneration',
      );
      return const CloudSyncResult(
        ok: true,
        syncDeferred: true,
        message:
            'Client heartbeat skipped because local Cloud ACK is zero without a newly applied snapshot.',
      );
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/devices'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'deviceId': store.deviceId,
              'deviceName': identity.deviceName,
              'platform': identity.platform.name,
              'role': identity.deviceRole.name,
              'transport': transport,
              'activeTransport': identity.activeSyncTransportNormalized,
              'lastSyncTransport': deviceState.lastSyncTransport.isEmpty
                  ? transport
                  : deviceState.lastSyncTransport,
              'lastAppliedCursor': lastAppliedCursor?.toIso8601String(),
              'lastAckCursor': lastAckCursor?.toIso8601String(),
              'lastAppliedSequence': lastAppliedSequence,
              'lastAckSequence': lastAckSequence,
              'deviceToken': identity.deviceToken,
              'hostDeviceId': identity.hostDeviceId,
              'appVersion': AppBrand.cloudAppVersion,
              'storeEpoch': identity.storeEpoch,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return CloudSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? 'Device heartbeat updated.'
            : 'Device heartbeat failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'Device heartbeat failed: $error');
    }
  }

  Future<CloudSyncResult> requestHostTransfer(CloudSyncSettings settings,
      {String reason = ''}) async {
    final identity = store.appIdentity;
    if (!identity.isClient) {
      return const CloudSyncResult(
          ok: false, message: 'Only Clients can request Host transfer.');
    }
    if (settings.apiBaseUrl.trim().isEmpty) {
      return const CloudSyncResult(
          ok: false, message: 'Cloud API URL is required.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/host-transfer/request'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'requestingDeviceId': store.deviceId,
              'currentHostDeviceId': identity.hostDeviceId,
              'reason': reason,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return CloudSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? 'Host transfer request sent.'
            : 'Host transfer request failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'Host transfer request failed: $error');
    }
  }

  Future<CloudSyncResult> approveHostTransfer(
      CloudSyncSettings settings, String requestingDeviceId) async {
    final identity = store.appIdentity;
    if (!identity.isHost) {
      return const CloudSyncResult(
          ok: false, message: 'Only Hosts can approve Host transfer.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'Cloud API URL and token are required.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/host-transfer/approve'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'requestingDeviceId': requestingDeviceId,
              'approvedByHostDeviceId': store.deviceId,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return CloudSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? 'Host transfer approved in Cloud.'
            : 'Host transfer approval failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'Host transfer approval failed: $error');
    }
  }

  Future<CloudSyncResult> activateHostTransfer(
      CloudSyncSettings settings) async {
    final identity = store.appIdentity;
    if (!settings.isConfigured && settings.apiBaseUrl.trim().isEmpty) {
      return const CloudSyncResult(
          ok: false, message: 'Cloud API URL is required.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/host-transfer/activate'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'newHostDeviceId': store.deviceId,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return CloudSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? 'Host transfer activated in Cloud.'
            : 'Host transfer activation failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'Host transfer activation failed: $error');
    }
  }

  Future<List<CloudDeviceStatus>> listDevices(
      CloudSyncSettings settings) async {
    final result = await listDevicesWithLimit(settings);
    return result.devices;
  }

  Future<CloudDevicesResult> listDevicesWithLimit(
      CloudSyncSettings settings) async {
    final identity = store.appIdentity;
    if (!settings.isConfigured) {
      return const CloudDevicesResult(devices: <CloudDeviceStatus>[]);
    }
    final response = await _client
        .get(
          settings.endpoint('/api/sync/devices', {
            'store_id': identity.storeId,
            'branch_id': identity.branchId,
          }),
          headers: _headers(settings),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const CloudDevicesResult(devices: <CloudDeviceStatus>[]);
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final devices = (decoded['devices'] as List<dynamic>? ?? [])
        .map((item) =>
            CloudDeviceStatus.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final limitRaw = decoded['deviceLimit'] ?? decoded['device_limit'];
    final limit = limitRaw is Map
        ? CloudDeviceLimitStatus.fromJson(Map<String, dynamic>.from(limitRaw))
        : null;
    return CloudDevicesResult(devices: devices, limit: limit);
  }

  Future<CloudSyncResult> repairLegacyCloudDeviceLinks(
    CloudSyncSettings settings, {
    required Iterable<String> clientDeviceIds,
  }) async {
    final identity = store.appIdentity;
    if (!identity.isHost) {
      return const CloudSyncResult(
          ok: false, message: 'Only the Host can repair Cloud device links.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'Cloud API URL and token are required.');
    }
    final cleanClientIds = clientDeviceIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && id != store.deviceId)
        .toSet()
        .toList();
    if (cleanClientIds.isEmpty) {
      return const CloudSyncResult(
          ok: true, message: 'No legacy Cloud device links need repair.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/devices/repair-host-links'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'hostDeviceId': store.deviceId,
              'clientDeviceIds': cleanClientIds,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return CloudSyncResult(
            ok: false,
            message:
                'Cloud device link repair failed: ${response.statusCode} ${response.body}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final repaired = int.tryParse('${decoded['repaired'] ?? 0}') ?? 0;
      final checked =
          int.tryParse('${decoded['checked'] ?? cleanClientIds.length}') ??
              cleanClientIds.length;
      return CloudSyncResult(
          ok: decoded['ok'] == true,
          message:
              'Cloud device links checked: $checked, repaired: $repaired.');
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'Cloud device link repair failed: $error');
    }
  }

  Future<CloudSyncResult> testConnection(CloudSyncSettings settings) async {
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'Cloud API URL and token are required.');
    }
    final accessResult = await checkCurrentDeviceAccess(settings);
    if (accessResult != null) return accessResult;

    try {
      final health = await _client
          .get(settings.endpoint('/api/health'), headers: _headers(settings))
          .timeout(const Duration(seconds: 10));
      if (health.statusCode < 200 || health.statusCode >= 300) {
        final authMessage = health.statusCode == 401 || health.statusCode == 403
            ? 'Unauthorized/Token invalid: Cloud API rejected the token.'
            : 'Cloud Server Unreachable: Cloud API returned status ${health.statusCode}: ${health.body}';
        return CloudSyncResult(ok: false, message: authMessage);
      }
      final decoded = jsonDecode(health.body) as Map<String, dynamic>;
      if (decoded['ok'] != true) {
        return const CloudSyncResult(
            ok: false, message: 'Cloud health response was not successful.');
      }
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'Cloud Server Unreachable: $error');
    }

    final identity = store.appIdentity;
    if (!identity.isClient) {
      return const CloudSyncResult(
          ok: true, message: 'Cloud API connection is healthy.');
    }

    if (identity.deviceToken.trim().isEmpty) {
      return const CloudSyncResult(
          ok: false,
          message:
              'Unauthorized/Token invalid: this Client has no saved device token. Pair this device again.');
    }

    try {
      final hostStatus = await getHostHeartbeatStatus(settings);
      if (!hostStatus.cloudReachable) {
        final lower = hostStatus.message.toLowerCase();
        final message = lower.contains('401') ||
                lower.contains('403') ||
                lower.contains('unauthorized') ||
                lower.contains('token')
            ? 'Unauthorized/Token invalid: ${hostStatus.message}'
            : 'Cloud Server Unreachable: ${hostStatus.message}';
        return CloudSyncResult(ok: false, message: message);
      }
      if (!hostStatus.hostReachable) {
        return CloudSyncResult(
            ok: false, message: 'Host Offline: ${hostStatus.message}');
      }

      final state = SyncDeviceStateStore.load(identity);
      final query = <String, String>{
        'store_id': identity.storeId,
        'branch_id': identity.branchId,
        'limit': '1',
      };
      if (state.lastAppliedSequence > 0) {
        query['since_sequence'] = state.lastAppliedSequence.toString();
      } else if (settings.lastPullCursor != null) {
        query['since'] = settings.lastPullCursor!.toIso8601String();
      }

      final ping = await _client
          .get(settings.endpoint('/api/sync/pull', query),
              headers: _headers(settings))
          .timeout(const Duration(seconds: 10));
      if (ping.statusCode < 200 || ping.statusCode >= 300) {
        final message = ping.statusCode == 401 || ping.statusCode == 403
            ? 'Unauthorized/Token invalid: Cloud Sync rejected this device. Pair this device again.'
            : 'Sync Not Ready: Cloud sync check failed with status ${ping.statusCode}: ${ping.body}';
        return CloudSyncResult(ok: false, message: message);
      }

      return const CloudSyncResult(
          ok: true, message: 'Cloud Connected/Ready for Sync.');
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Sync Not Ready: $error');
    }
  }

  Future<CloudSyncResult> validateSingleHost(CloudSyncSettings settings) async {
    final identity = store.appIdentity;
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'Cloud API URL and token are required.');
    }
    final status = await getHostHeartbeatStatus(settings);
    if (status.cloudReachable &&
        status.hostReachable &&
        status.hostDeviceId.isNotEmpty &&
        status.hostDeviceId != store.deviceId) {
      return CloudSyncResult(
        ok: false,
        message:
            'Another active Host is already connected for store ${identity.storeId}: ${status.hostDeviceName.isEmpty ? status.hostDeviceId : status.hostDeviceName}. Convert this device to a Client or stop the old Host first.',
      );
    }
    return const CloudSyncResult(
        ok: true, message: 'No other active Host was found.');
  }

  Future<CloudSyncResult> sendHostHeartbeat(CloudSyncSettings settings) async {
    final identity = store.appIdentity;
    if (!identity.isCloudEnabled || !identity.isHost) {
      return const CloudSyncResult(
          ok: false,
          message: 'Heartbeat is only sent by a cloud-enabled Host device.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'Cloud API URL and token are required.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/host-heartbeat'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'hostDeviceId': store.deviceId,
              'hostDeviceName': identity.deviceName,
              'platform': identity.platform.name,
              'appVersion': AppBrand.cloudAppVersion,
              'syncMode': identity.syncMode.name,
              'recoveryKey': identity.recoveryKey,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return CloudSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? 'Host heartbeat updated.'
            : 'Host heartbeat failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'Host heartbeat failed: $error');
    }
  }

  Future<bool> waitForRealtimeSignal(
    CloudSyncSettings settings, {
    Duration wait = const Duration(seconds: 25),
  }) async {
    final identity = store.appIdentity;
    if (!_cloudAllowedForIdentity(identity) || !settings.isConfigured) {
      return false;
    }
    try {
      final session = await _openRealtimeChannel(settings);
      final channel = session.channel;
      final completer = Completer<bool>();
      late final StreamSubscription<dynamic> subscription;
      subscription = channel.stream.listen(
        (raw) async {
          if (completer.isCompleted) return;
          final decoded = jsonDecode(raw.toString());
          if (decoded is! Map) return;
          final signal = await _handleRealtimePacket(
            settings,
            channel,
            Map<String, dynamic>.from(decoded),
          );
          if (signal != null && !completer.isCompleted) {
            completer.complete(true);
          }
        },
        onError: (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(false);
        },
        cancelOnError: false,
      );
      try {
        return await completer.future.timeout(
          wait + const Duration(seconds: 8),
          onTimeout: () => false,
        );
      } finally {
        await subscription.cancel();
        await channel.sink.close();
      }
    } catch (_) {
      return false;
    }
  }

  Stream<CloudRealtimeSignal> watchRealtimeSignals(
    CloudSyncSettings settings,
  ) async* {
    final identity = store.appIdentity;
    if (!_cloudAllowedForIdentity(identity) || !settings.isConfigured) {
      return;
    }
    final session = await _openRealtimeChannel(settings);
    final channel = session.channel;
    try {
      await for (final raw in channel.stream) {
        final decoded = jsonDecode(raw.toString());
        if (decoded is! Map) continue;
        final packet = Map<String, dynamic>.from(decoded);
        final type = (packet['type'] ?? '').toString();
        if (type == 'realtime_welcome') {
          SyncDiagnosticsLog.add(
            '[SYNC_TRACE] cloudRealtime:connected role=${identity.deviceRole.name} '
            'device=${identity.deviceId} url=${session.uri.replace(queryParameters: {
                  ...session.uri.queryParameters,
                  'ticket': '***',
                })}',
          );
          continue;
        }
        final signal = await _handleRealtimePacket(settings, channel, packet);
        if (signal == null) continue;
        yield signal;
      }
    } finally {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] cloudRealtime:closed role=${identity.deviceRole.name} '
        'device=${identity.deviceId}',
      );
      unawaited(channel.sink.close());
    }
  }

  Future<HostHeartbeatStatus> getHostHeartbeatStatus(CloudSyncSettings settings,
      {Duration staleAfter = const Duration(seconds: 90)}) async {
    final identity = store.appIdentity;
    if (!settings.isConfigured) {
      return const HostHeartbeatStatus(
          cloudReachable: false,
          hostReachable: false,
          message: 'Cloud API URL and token are required.');
    }
    try {
      final response = await _client
          .get(
            settings.endpoint('/api/sync/host-heartbeat', {
              'store_id': identity.storeId,
              'branch_id': identity.branchId,
            }),
            headers: _headers(settings),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return HostHeartbeatStatus(
            cloudReachable: false,
            hostReachable: false,
            message:
                'Cloud API returned status ${response.statusCode}: ${response.body}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final rawLastSeen = decoded['lastSeenAt'] ?? decoded['last_seen_at'];
      final lastSeenAt = rawLastSeen == null
          ? null
          : DateTime.tryParse(rawLastSeen.toString());
      final hostReachable = lastSeenAt != null &&
          DateTime.now().toUtc().difference(lastSeenAt.toUtc()) <= staleAfter;
      final hostDeviceId =
          (decoded['hostDeviceId'] ?? decoded['host_device_id'] ?? '')
              .toString();
      final hostDeviceName =
          (decoded['hostDeviceName'] ?? decoded['host_device_name'] ?? '')
              .toString();
      return HostHeartbeatStatus(
        cloudReachable: true,
        hostReachable: hostReachable,
        lastSeenAt: lastSeenAt,
        hostDeviceId: hostDeviceId,
        hostDeviceName: hostDeviceName,
        message: hostReachable
            ? 'Host heartbeat is fresh.'
            : (lastSeenAt == null
                ? 'No host heartbeat was found.'
                : 'Host heartbeat is stale.'),
      );
    } catch (error) {
      return HostHeartbeatStatus(
          cloudReachable: false,
          hostReachable: false,
          message: 'Cloud API connection failed: $error');
    }
  }

  Future<Map<String, dynamic>?> runCloudMaintenance(CloudSyncSettings settings,
      {int eventRetentionDays = 30}) async {
    final identity = store.appIdentity;
    if (!identity.isHost ||
        !identity.isCloudEnabled ||
        !settings.isConfigured) {
      return null;
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/maintenance'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'hostDeviceId': store.deviceId,
              'deviceId': store.deviceId,
              'eventRetentionDays': eventRetentionDays,
              'processedRequestRetentionDays': 3,
              'deletedSnapshotRetentionDays': 7,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
            'Cloud maintenance failed: ${response.statusCode} ${response.body}');
        return null;
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (error) {
      debugPrint('Cloud maintenance failed: $error');
      return null;
    }
  }

  Future<Map<String, dynamic>> _downloadCloudSnapshotEnvelope(
    CloudSyncSettings settings, {
    bool force = false,
    CloudSyncProgressCallback? onProgress,
  }) {
    final identity = store.appIdentity;
    return const UnifiedSnapshotTransferService().downloadEnvelope(
      _CloudSnapshotPullTransport(
        settings: settings,
        headers: _headers(settings),
        client: _client,
        storeId: identity.storeId,
        branchId: identity.branchId,
      ),
      force: force,
      labelPrefix: 'Cloud snapshot',
      onProgress: onProgress,
    );
  }

  Future<Map<String, dynamic>> _downloadCloudSnapshotEnvelopeViaRelay(
    CloudSyncSettings settings, {
    bool force = false,
    CloudSyncProgressCallback? onProgress,
    String snapshotKind = 'full_store',
    String rebuildRequestId = '',
    int requiredMinSequence = 0,
  }) async {
    final transport = _CloudRelaySnapshotPullTransport(
      service: this,
      settings: settings,
      snapshotKind: snapshotKind,
      rebuildRequestId: rebuildRequestId,
      requiredMinSequence: requiredMinSequence,
    );
    try {
      return await const UnifiedSnapshotTransferService().downloadEnvelope(
        transport,
        force: force,
        labelPrefix: 'Cloud snapshot',
        onProgress: onProgress,
      );
    } finally {
      await transport.dispose();
    }
  }

  Future<CloudSyncResult> _applyCloudSnapshotEnvelope(
    Map<String, dynamic> envelope, {
    required CloudSyncSettings settings,
    required CloudSyncProgressCallback? onProgress,
    required String expectedSnapshotGeneration,
    required String expectedRestoreCommandId,
  }) async {
    if ((envelope['hostSnapshotGeneration'] ?? '').toString().trim().isEmpty &&
        expectedSnapshotGeneration.trim().isNotEmpty) {
      envelope['hostSnapshotGeneration'] = expectedSnapshotGeneration.trim();
      envelope['snapshotGeneration'] = expectedSnapshotGeneration.trim();
    }
    if ((envelope['hostRestoreCommandId'] ?? '').toString().trim().isEmpty &&
        expectedRestoreCommandId.trim().isNotEmpty) {
      envelope['hostRestoreCommandId'] = expectedRestoreCommandId.trim();
      envelope['restoreCommandId'] = expectedRestoreCommandId.trim();
    }
    onProgress?.call(0.84, 'Applying Cloud snapshot chunks locally...');
    // Reset the Client progress only after a valid Host snapshot envelope has
    // been downloaded and is about to be applied. This prevents pressure/offline
    // rebuild deferrals from publishing ACK/sequence = 0 without an applied
    // replacement snapshot.
    await CloudSyncSettings.clearSavedPullCursor();
    await SyncDeviceStateStore.resetClientProgress(store.appIdentity,
        transport: 'cloud');
    await store.importSyncSnapshotJson(jsonEncode(envelope));
    await _markHostSnapshotGenerationApplied('cloud', envelope,
        markRestoreCommandExecuted: true);
    onProgress?.call(0.90, 'Verifying rebuilt local data...');
    final repaired = await store.verifyLocalBusinessDataIntegrity();
    if (!repaired.ok) {
      debugPrint(
          'Cloud rebuild completed with verification warnings: ${repaired.message}');
    }
    onProgress?.call(0.96, 'Cleaning up local records...');
    await store.cleanupSoftDeletedRecords();
    await CloudProvisioningStatus.markComplete(
        message: 'Initial Store data downloaded.');
    final cursor = store.syncSnapshotGeneratedAtFromJson(jsonEncode(envelope));
    final sequence =
        store.syncSnapshotGeneratedSequenceFromJson(jsonEncode(envelope));
    await settings.copyWith(lastPullCursor: cursor).save();
    await _recordDeviceSyncState(
      'cloud',
      cursor,
      sequence: sequence,
      settings: settings.copyWith(lastPullCursor: cursor),
    );
    onProgress?.call(1.0, 'Cloud rebuild completed.');
    return CloudSyncResult(
      ok: true,
      pulled: (envelope['totalChunks'] as num?)?.toInt() ?? 0,
      restoredSnapshot: true,
      message: repaired.ok
          ? 'Cloud rebuild completed from unified snapshot chunks.'
          : 'Unified snapshot chunks downloaded, but local verification found problems: ${repaired.message}',
    );
  }

  Future<int> publishLoginBootstrapSnapshotToCloud(
    CloudSyncSettings settings, {
    bool force = false,
    void Function(double value, String label)? onProgress,
  }) async {
    final identity = store.appIdentity;
    if (!identity.isHost ||
        !identity.isCloudEnabled ||
        !settings.isConfigured) {
      return 0;
    }
    await store.removeLegacyCloudBootstrapSnapshotQueue();
    final chunks = await store.exportCloudLoginBootstrapSnapshotChunks();
    if (chunks.isEmpty) return 0;
    return const UnifiedSnapshotTransferService().uploadChunks(
      _CloudSnapshotPushTransport(
        settings: settings,
        headers: _headers(settings),
        client: _client,
      ),
      chunks,
      force: force,
      preserveExisting: true,
      labelPrefix: 'Cloud login snapshot',
      onProgress: onProgress,
    );
  }

  Future<int> publishBootstrapSnapshotToCloud(
    CloudSyncSettings settings, {
    bool force = false,
    void Function(double value, String label)? onProgress,
  }) async {
    final identity = store.appIdentity;
    if (!identity.isHost ||
        !identity.isCloudEnabled ||
        !settings.isConfigured) {
      return 0;
    }
    await store.removeLegacyCloudBootstrapSnapshotQueue();
    await store.ensureHeavyDataLoaded();
    final chunks =
        await store.exportCloudBootstrapSnapshotChunks(maxItemsPerChunk: 300);
    if (chunks.isEmpty || !_relaySnapshotHasBusinessCollections(chunks)) {
      return 0;
    }
    return const UnifiedSnapshotTransferService().uploadChunks(
      _CloudSnapshotPushTransport(
        settings: settings,
        headers: _headers(settings),
        client: _client,
      ),
      chunks,
      force: force,
      preserveExisting: false,
      labelPrefix: 'Cloud snapshot',
      onProgress: onProgress,
    );
  }

  Future<int> _pushPendingToEndpoint(
      CloudSyncSettings settings, String target, String path) async {
    final identity = store.appIdentity;
    const transport = 'cloud';
    var totalPushed = 0;
    var batchNumber = 0;

    // Keep pending pushes closer to snapshot transport: send larger compressed
    // chunks so network overhead and server round trips stay low even when the
    // queue contains tens of thousands of rows. The server still ACKs each
    // compressed chunk, so a timeout never marks unsent data as synced.
    const batchSize = 1500;

    while (true) {
      await store.recoverStaleInProgressSyncQueue(target: target);
      await store.retryFailedSyncQueue(target: target);
      final pending = _syncCore
          .pendingChangesForTarget(target)
          .take(batchSize)
          .toList(growable: false);
      final pendingIds = _syncCore.changeIds(pending);
      if (pending.isEmpty) break;
      batchNumber += 1;

      await _syncCore.markPushInProgress(pendingIds);
      try {
        final push = await _client
            .post(
              settings.endpoint(path),
              headers: _headers(settings),
              body: jsonEncode(_buildCompressedPendingPushBody(
                identity: identity,
                transport: transport,
                batchNumber: batchNumber,
                pending: pending,
              )),
            )
            .timeout(const Duration(seconds: 60));
        if (push.statusCode < 200 || push.statusCode >= 300) {
          final message =
              'Cloud push failed in batch $batchNumber: ${push.statusCode} ${push.body}';
          await _syncCore.markPushFailed(pendingIds, message);
          throw StateError(message);
        }
        final decoded = jsonDecode(push.body) as Map<String, dynamic>;
        final ackIds = (decoded['ackIds'] as List<dynamic>? ?? [])
            .map((item) => '$item')
            .toList();
        final rejected = _decodeRejectedSyncRequests(decoded['rejected']);
        if (rejected.isNotEmpty) await _syncCore.markPushRejected(rejected);
        await _syncCore.markPushAcknowledged(ackIds, fallbackIds: pendingIds);
        totalPushed += pending.length;
      } catch (error) {
        // Keep the affected batch retryable. Already acknowledged previous
        // batches remain synced; unsent later batches were never touched.
        await _syncCore.markPushFailed(
            pendingIds, 'Cloud push failed in batch $batchNumber: $error');
        rethrow;
      }
    }

    return totalPushed;
  }

  Map<String, dynamic> _buildCompressedPendingPushBody({
    required AppIdentity identity,
    required String transport,
    required int batchNumber,
    required List<SyncChange> pending,
  }) {
    final changesJson = pending.map((item) => item.toJson()).toList();
    final rawJson = jsonEncode(changesJson);
    final compressed = GZipEncoder().encode(utf8.encode(rawJson));
    final encodedPayload = base64Encode(compressed);
    return {
      'deviceId': store.deviceId,
      'storeId': identity.storeId,
      'branchId': identity.branchId,
      'sequence': SyncDeviceStateStore.lastAppliedSequenceForTransport(
          identity, transport),
      'lastAppliedSequence': SyncDeviceStateStore.lastAppliedSequenceForTransport(
          identity, transport),
      'batchNumber': batchNumber,
      'batchSize': pending.length,
      'changesEncoding': 'gzip+base64+json',
      'changesPayload': encodedPayload,
    };
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

  Future<int> _pushPendingViaRelay(
    CloudSyncSettings settings, {
    required String target,
  }) async {
    final identity = store.appIdentity;
    const transport = 'cloud';
    var totalPushed = 0;
    var batchNumber = 0;
    const batchSize = 500;
    final relaySession = await _RealtimeRelaySession.open(
      this,
      settings,
      includeSequenceHint: false,
    );

    try {
      while (true) {
        await store.recoverSubmittedSyncQueue(target: target);
        await store.recoverStaleInProgressSyncQueue(target: target);
        await store.retryFailedSyncQueue(target: target);
        final pending = _syncCore
            .pendingChangesForTarget(target)
            .take(batchSize)
            .toList(growable: false);
        final pendingIds = _syncCore.changeIds(pending);
        if (pending.isEmpty) break;
        batchNumber += 1;

        await _syncCore.markPushInProgress(pendingIds);
        try {
          final response = await relaySession.sendRequest(
            'cloud_client_push',
            {
              'deviceId': store.deviceId,
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'sequence': SyncDeviceStateStore.lastAppliedSequenceForTransport(
                  identity, transport),
              'lastAppliedSequence':
                  SyncDeviceStateStore.lastAppliedSequenceForTransport(
                      identity, transport),
              'batchNumber': batchNumber,
              'batchSize': pending.length,
              'changes': pending.map((item) => item.toJson()).toList(),
            },
          );
          if (response['ok'] != true) {
            final message = 'Cloud relay push failed in batch $batchNumber: '
                '${response['error'] ?? response['message'] ?? 'unknown error'}';
            await _syncCore.markPushFailed(pendingIds, message);
            throw StateError(message);
          }
          final ackIds = (response['ackIds'] as List<dynamic>? ?? [])
              .map((item) => '$item')
              .where((item) => item.trim().isNotEmpty)
              .toList();
          final rejected = _decodeRejectedSyncRequests(response['rejected']);
          if (rejected.isNotEmpty) await _syncCore.markPushRejected(rejected);
          if (target == 'cloud_host') {
            // Realtime relay responses come directly from the Host. Unlike the
            // legacy /api/sync/requests/push endpoint, this ACK is the final
            // Host decision, not just Cloud inbox delivery. Keeping these rows
            // as `submitted` leaves the Client waiting for /requests/status,
            // but no cloud_change_requests row exists for direct relay ACKs;
            // the Client then intermittently stays pending and skips pull.
            await _syncCore.markPushAcknowledged(ackIds,
                fallbackIds: pendingIds);
          } else {
            await _syncCore.markPushAcknowledged(ackIds,
                fallbackIds: pendingIds);
          }
          totalPushed += pending.length;
        } catch (error) {
          await _syncCore.markPushFailed(
            pendingIds,
            'Cloud relay push failed in batch $batchNumber: $error',
          );
          rethrow;
        }
      }
    } finally {
      await relaySession.close();
    }

    return totalPushed;
  }

  Future<bool> _broadcastHostAuthorityViaRelay(
    CloudSyncSettings settings,
  ) async {
    final identity = store.appIdentity;
    final pending = _syncCore.pendingChangesForTarget('cloud');
    if (pending.isEmpty) return true;
    final pendingIds = _syncCore.changeIds(pending);
    final latestSequence = store.latestStoredAuthoritativeSequence;
    try {
      await _sendRealtimeBroadcast(
        settings,
        type: 'sync_changed',
        payload: {
          'changed': true,
          'latestSequence': latestSequence,
          'pendingRequests': pending.length,
          'deviceId': store.deviceId,
          'storeId': identity.storeId,
          'branchId': identity.branchId,
          'relayKind': 'cloud_host_publish',
        },
      );
      await _syncCore.markPushAcknowledged(pendingIds, fallbackIds: pendingIds);
      return true;
    } catch (error) {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] cloudRelay:hostBroadcastFailed error=$error',
      );
      return false;
    }
  }

  Future<CloudSyncResult?> _pullAuthoritativeChangesViaRelay(
    CloudSyncSettings settings, {
    DateTime? minSnapshotUpdatedAt,
    CloudSyncProgressCallback? onProgress,
  }) async {
    final identity = store.appIdentity;
    if (identity.isHost) {
      return const CloudSyncResult(
          ok: true,
          message: 'Host devices do not pull authoritative Cloud changes.',
          pulled: 0);
    }

    final baseLastAppliedSequence =
        SyncDeviceStateStore.lastAppliedSequenceForTransport(
            store.appIdentity, 'cloud');
    if (baseLastAppliedSequence <= 0) return null;

    final initialCursor = settings.lastPullCursor;
    try {
      onProgress?.call(0.35, 'Pulling Cloud changes through the relay...');
      final response = await _sendRealtimeRequest(
        settings,
        requestKind: 'cloud_client_pull',
        payload: {
          'deviceId': store.deviceId,
          'storeId': identity.storeId,
          'branchId': identity.branchId,
          'sinceSequence': baseLastAppliedSequence,
          if (initialCursor != null) 'since': initialCursor.toIso8601String(),
          if (minSnapshotUpdatedAt != null)
            'minSnapshotUpdatedAt': minSnapshotUpdatedAt.toIso8601String(),
          'limit': 1000,
        },
      );
      if (response['ok'] != true) {
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] cloudRelayPull:serverRejected error=${response['error'] ?? response['message'] ?? 'unknown error'}',
        );
        return null;
      }

      if (response['needsSnapshot'] == true) {
        final generation = _remoteHostSnapshotGeneration(response);
        final commandId = _remoteHostRestoreCommandId(response);
        if (_restoreCommandAlreadyExecuted('cloud', commandId)) {
          final generatedAt =
              DateTime.tryParse(response['generatedAt']?.toString() ?? '') ??
                  DateTime.now();
          final generatedSequence =
              int.tryParse(response['generatedSequence']?.toString() ?? '') ??
                  0;
          await settings.copyWith(lastPullCursor: generatedAt).save();
          await _recordDeviceSyncState('cloud', generatedAt,
              sequence: generatedSequence, settings: settings);
          return CloudSyncResult(
            ok: true,
            message:
                'A previously executed rebuild command was ignored and the sync cursor was updated.',
            pulled: 0,
          );
        }
        return rebuildFromCloudHostSnapshot(
          settings.copyWith(clearLastPullCursor: true),
          onProgress: onProgress,
          requestFreshSnapshot: false,
          expectedSnapshotGeneration: generation,
          expectedRestoreCommandId: commandId,
        );
      }

      final rawChanges =
          response['changes'] as List<dynamic>? ?? const <dynamic>[];
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] cloudRelayPull:decoded source=${response['source']} '
        'changes=${rawChanges.length} '
        'generatedAt=${response['generatedAt']} '
        'generatedSequence=${response['generatedSequence']}',
      );
      for (final raw in rawChanges.take(40)) {
        final change =
            SyncChange.fromJson(Map<String, dynamic>.from(raw as Map));
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] cloudRelayPull:rawChange ${SyncDiagnosticsLog.summarizeChange(change)}',
        );
      }

      final decodedChanges = _syncCore.decodeRemoteChanges(rawChanges);
      final changes = _syncCore.filterOutLocalEchoes(decodedChanges);
      final restoreMarker = changes.any((item) =>
          item.entityType == 'system' &&
          item.operation == 'cloud_restore_snapshot_ready');
      if (restoreMarker && store.appIdentity.isClient) {
        final commandId = _restoreCommandIdFromChanges(changes);
        if (!_restoreCommandAlreadyExecuted('cloud', commandId)) {
          onProgress?.call(0.50,
              'A new Host restore was found. Rebuilding device data from a full snapshot...');
          return rebuildFromCloudHostSnapshot(
            settings.copyWith(clearLastPullCursor: true),
            onProgress: onProgress,
            requestFreshSnapshot: false,
            expectedRestoreCommandId: commandId,
          );
        }
      }

      final source = (response['source'] ?? '').toString();
      final restoredSnapshot =
          changes.any((item) => item.operation == 'restore_snapshot') ||
              (initialCursor == null &&
                  source == 'entity_snapshots' &&
                  changes.isNotEmpty);

      onProgress?.call(
          0.72, 'Applying ${changes.length} Cloud change(s) from relay...');
      final applied = await _syncCore.applyAuthoritativeChanges(changes);

      final finalPullCursor =
          DateTime.tryParse((response['generatedAt'] ?? '').toString()) ??
              DateTime.now().toUtc();
      final finalPullSequence =
          int.tryParse((response['generatedSequence'] ?? '0').toString()) ?? 0;
      await settings.copyWith(lastPullCursor: finalPullCursor).save();
      await _recordDeviceSyncState('cloud', finalPullCursor,
          sequence: finalPullSequence, settings: settings);

      if (applied > 0) {
        onProgress?.call(0.92, 'Cleaning up after Cloud sync...');
        await store.cleanupSoftDeletedRecords();
      }
      if (store.appIdentity.isClient &&
          (restoredSnapshot || applied > 0) &&
          !store.needsInitialAdminSetup) {
        await CloudProvisioningStatus.markComplete(
            message: 'Initial Store data downloaded.');
      }
      return CloudSyncResult(
        ok: true,
        pulled: applied,
        restoredSnapshot: restoredSnapshot,
        message:
            'Cloud relay pull completed. Pulled $applied authoritative change(s).',
      );
    } catch (error) {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] cloudRelayPull:error $error',
      );
      return null;
    }
  }

  Future<CloudSyncResult> pushPendingForUnifiedEngine(
      CloudSyncSettings settings,
      {CloudSyncProgressCallback? onProgress}) async {
    final identity = store.appIdentity;
    if (!_cloudAllowedForIdentity(identity)) {
      return const CloudSyncResult(
          ok: false,
          message:
              'Cloud is not the active/configured sync transport for this device.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'Cloud API URL and token are required.');
    }

    if (await _clientCloudHostWorkNeedsDrain()) {
      return const CloudSyncResult(
        ok: true,
        message: _clientCloudDrainMessage,
        syncDeferred: true,
      );
    }

    try {
      var pushed = 0;

      if (identity.isHost) {
        onProgress?.call(0.10, 'Preparing Host cloud snapshot queue...');
        await store.ensureHostCloudBootstrapSnapshotQueued();
        final repairedCloudQueue =
            await store.repairMissingHostCloudQueueForPendingChanges();
        if (repairedCloudQueue > 0) {
          onProgress?.call(0.18,
              '$repairedCloudQueue missing Host cloud snapshot queue item(s) were repaired...');
        }
        onProgress?.call(0.25, 'Sending Host heartbeat...');
        await sendHostHeartbeat(settings);
        onProgress?.call(0.40, 'Registering Host device...');
        await registerCurrentDevice(settings, transport: 'cloud');
        final hostPendingCount =
            _syncCore.pendingChangesForTarget('cloud').length;
        onProgress?.call(
            0.55, 'Publishing Host changes through Cloud relay...');
        final relayPublished = await _broadcastHostAuthorityViaRelay(settings);
        if (!relayPublished) {
          return const CloudSyncResult(
            ok: false,
            message:
                'Host cloud relay failed. Legacy Cloud fallback is disabled; retry when the relay is available.',
          );
        }
        pushed = hostPendingCount;
        await runCloudMaintenance(settings);
        return CloudSyncResult(
          ok: true,
          pushed: pushed,
          message:
              'Host cloud relay completed. Broadcast $pushed authoritative change(s).',
        );
      }

      onProgress?.call(0.12, 'Registering Client device...');
      await registerCurrentDevice(settings, transport: 'cloud');
      onProgress?.call(0.22, 'Sending Client requests to Host relay...');
      pushed += await _pushPendingViaRelay(settings, target: 'cloud_host');
      return CloudSyncResult(
          ok: true,
          pushed: pushed,
          message:
              'Client cloud push completed. Sent $pushed request(s) to Host relay and received Host ACK.');
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Cloud push failed: $error');
    }
  }

  Future<bool> _cloudSnapshotIsNewerThanLocal(
    CloudSyncSettings settings,
  ) async {
    if (!store.appIdentity.isClient) return false;
    try {
      final localCursor = SyncDeviceStateStore.lastAppliedCursorForTransport(
              store.appIdentity, 'cloud') ??
          settings.lastPullCursor;
      UnifiedSnapshotManifestResponse? manifest;
      try {
        manifest = await _CloudRelaySnapshotPullTransport(
          service: this,
          settings: settings,
        ).requestManifest();
      } catch (_) {
        manifest = await _CloudSnapshotPullTransport(
          settings: settings,
          headers: _headers(settings),
          client: _client,
          storeId: store.appIdentity.storeId,
          branchId: store.appIdentity.branchId,
        ).requestManifest();
      }
      final remoteSequence = manifest.syncGeneratedSequence ?? 0;
      final lastAppliedSequence =
          SyncDeviceStateStore.lastAppliedSequenceForTransport(
              store.appIdentity, 'cloud');
      if (remoteSequence > 0 && lastAppliedSequence >= remoteSequence) {
        return false;
      }
      final commandId =
          (manifest.hostRestoreCommandId ?? manifest.restoreCommandId ?? '')
              .trim();
      if (_restoreCommandAlreadyExecuted('cloud', commandId)) return false;
      final generation =
          (manifest.hostSnapshotGeneration ?? manifest.snapshotGeneration ?? '')
              .trim();
      if (generation.isNotEmpty) {
        if (!_needsHostSnapshotGenerationRebuild('cloud', <String, dynamic>{
          'hostSnapshotGeneration': generation,
          'snapshotGeneration': generation,
          'hostRestoreCommandId': commandId,
          'restoreCommandId': commandId,
        })) {
          return false;
        }
        return true;
      }
      final remoteGeneratedAt =
          DateTime.tryParse(manifest.syncGeneratedAt ?? '');
      if (remoteGeneratedAt == null) return false;
      if (localCursor == null) return true;
      // Add a small tolerance so re-reading the same materialized snapshot does
      // not trigger repeated rebuilds due to clock precision differences.
      return remoteGeneratedAt.toUtc().isAfter(
            localCursor.toUtc().add(const Duration(seconds: 2)),
          );
    } catch (_) {
      // Snapshot freshness is a safety net. If the manifest is temporarily not
      // reachable, keep the normal incremental pull path alive.
      return false;
    }
  }

  Future<CloudSyncResult> pullAuthoritativeChangesForUnifiedEngine(
    CloudSyncSettings settings, {
    DateTime? minSnapshotUpdatedAt,
    CloudSyncProgressCallback? onProgress,
  }) async {
    final identity = store.appIdentity;
    if (identity.isHost) {
      return const CloudSyncResult(
          ok: true,
          message: 'Host devices do not pull authoritative Cloud changes.',
          pulled: 0);
    }
    if (!_cloudAllowedForIdentity(identity)) {
      return const CloudSyncResult(
          ok: false,
          message:
              'Cloud is not the active/configured sync transport for this device.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'Cloud API URL and token are required.');
    }

    if (await _clientCloudHostWorkNeedsDrain()) {
      return const CloudSyncResult(
        ok: true,
        message: _clientCloudDrainMessage,
        syncDeferred: true,
      );
    }

    try {
      // Freeze the sequence watermark for the whole paginated pull. Reading
      // lastAppliedSequence after every page can skip pages: page 1 advances the
      // local state, then page 2 asks Cloud for sequence > the new value while
      // also passing the old page cursor. That combination can silently miss
      // events, which showed up as product count differences across devices.
      final baseLastAppliedSequence =
          SyncDeviceStateStore.lastAppliedSequenceForTransport(
              store.appIdentity, 'cloud');
      final relayResult = baseLastAppliedSequence > 0
          ? await _pullAuthoritativeChangesViaRelay(
              settings,
              minSnapshotUpdatedAt: minSnapshotUpdatedAt,
              onProgress: onProgress,
            )
          : null;
      if (relayResult != null) return relayResult;
      var pulled = 0;
      // Sequence is the authoritative Cloud watermark. Never combine it
      // with the legacy timestamp cursor: a newer local timestamp can filter out
      // older-but-unapplied Host events and leave the Client stuck behind the
      // Host (for example Host latest=32206 while Client ACK=32187). Only use
      // the legacy cursor for pre-sequence clients.
      final initialCursor =
          baseLastAppliedSequence > 0 ? null : settings.lastPullCursor;
      final shouldUseSnapshotBootstrap = baseLastAppliedSequence <= 0;
      if (shouldUseSnapshotBootstrap &&
          await _cloudSnapshotIsNewerThanLocal(settings)) {
        onProgress?.call(0.32,
            'A newer Host snapshot was found. Rebuilding this device data...');
        return rebuildFromCloudHostSnapshot(
          settings.copyWith(clearLastPullCursor: true),
          onProgress: onProgress,
          requestFreshSnapshot: false,
        );
      }
      var pageCursor = '';
      DateTime? finalPullCursor;
      var finalPullSequence = 0;
      var pageCount = 0;
      var restoredSnapshot = false;
      var allSnapshotSectionsComplete = true;
      const maxPagesPerRun = 200;

      while (true) {
        pageCount += 1;
        if (pageCount > maxPagesPerRun) {
          return CloudSyncResult(
              ok: false,
              message:
                  'Cloud pull stopped after $maxPagesPerRun pages to avoid an infinite loop. Please retry sync.');
        }

        final query = <String, String>{
          'store_id': identity.storeId,
          'branch_id': identity.branchId,
          'limit': '1000',
        };
        if (baseLastAppliedSequence > 0) {
          query['since_sequence'] = baseLastAppliedSequence.toString();
        }
        if (initialCursor != null) {
          query['since'] = initialCursor.toIso8601String();
        }
        if (initialCursor == null && minSnapshotUpdatedAt != null) {
          query['min_snapshot_updated_at'] =
              minSnapshotUpdatedAt.toIso8601String();
        }
        if (pageCursor.isNotEmpty) query['cursor'] = pageCursor;
        final endpoint = settings.endpoint('/api/sync/pull', query);

        final pullProgress =
            (0.35 + (pageCount - 1) * 0.08).clamp(0.35, 0.82).toDouble();
        onProgress?.call(
            pullProgress, 'Pulling Cloud changes page $pageCount...');
        final pull = await _client
            .get(endpoint, headers: _headers(settings))
            .timeout(const Duration(seconds: 20));
        if (pull.statusCode < 200 || pull.statusCode >= 300) {
          return CloudSyncResult(
              ok: false,
              message: 'Cloud pull failed: ${pull.statusCode} ${pull.body}');
        }

        final decodedPull = jsonDecode(pull.body) as Map<String, dynamic>;
        final rawChanges =
            decodedPull['changes'] as List<dynamic>? ?? const <dynamic>[];
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] cloudPull:decoded page=$pageCount '
          'source=${decodedPull['source']} '
          'changes=${rawChanges.length} '
          'hasMore=${decodedPull['hasMore']} '
          'generatedAt=${decodedPull['generatedAt']} '
          'generatedSequence=${decodedPull['generatedSequence']}',
        );
        for (final raw in rawChanges.take(40)) {
          final change =
              SyncChange.fromJson(Map<String, dynamic>.from(raw as Map));
          SyncDiagnosticsLog.add(
            '[SYNC_TRACE] cloudPull:rawChange ${SyncDiagnosticsLog.summarizeChange(change)}',
          );
        }
        final generationRebuild = await _rebuildIfHostSnapshotGenerationChanged(
          settings,
          decodedPull,
          onProgress: onProgress,
        );
        if (generationRebuild != null) return generationRebuild;
        if ((decodedPull['source'] ?? '').toString() == 'entity_snapshots') {
          final pageAllSectionsComplete =
              decodedPull['allSnapshotSectionsComplete'] == true;
          allSnapshotSectionsComplete =
              allSnapshotSectionsComplete && pageAllSectionsComplete;
          await CloudProvisioningStatus.updateSnapshotSections(
            decodedPull['snapshotSections'] is Map<String, dynamic>
                ? decodedPull['snapshotSections'] as Map<String, dynamic>
                : null,
            allComplete: pageAllSectionsComplete,
          );
        }
        if (decodedPull['needsSnapshot'] == true) {
          await CloudSyncSettings.clearSavedPullCursor();
          final generation = _remoteHostSnapshotGeneration(decodedPull);
          final commandId = _remoteHostRestoreCommandId(decodedPull);
          if (_restoreCommandAlreadyExecuted('cloud', commandId)) {
            final generatedAt = DateTime.tryParse(
                    decodedPull['generatedAt']?.toString() ?? '') ??
                DateTime.now();
            final generatedSequence = int.tryParse(
                    decodedPull['generatedSequence']?.toString() ?? '') ??
                0;
            await settings.copyWith(lastPullCursor: generatedAt).save();
            await _recordDeviceSyncState('cloud', generatedAt,
                sequence: generatedSequence, settings: settings);
            return CloudSyncResult(
              ok: true,
              message:
                  'A previously executed rebuild command was ignored and the sync cursor was updated.',
              pulled: pulled,
            );
          }
          return rebuildFromCloudHostSnapshot(
            settings.copyWith(clearLastPullCursor: true),
            onProgress: onProgress,
            requestFreshSnapshot: false,
            expectedSnapshotGeneration: generation,
            expectedRestoreCommandId: commandId,
          );
        }
        final decodedChanges = _syncCore.decodeRemoteChanges(rawChanges);
        final changes = _syncCore.filterOutLocalEchoes(decodedChanges);
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] cloudPull:filtered page=$pageCount '
          'decoded=${decodedChanges.length} afterEchoFilter=${changes.length} '
          'localDevice=${store.deviceId}',
        );
        final source = (decodedPull['source'] ?? '').toString();
        final restoreMarker = changes.any((item) =>
            item.entityType == 'system' &&
            item.operation == 'cloud_restore_snapshot_ready');
        if (restoreMarker && store.appIdentity.isClient) {
          final commandId = _restoreCommandIdFromChanges(changes);
          if (_restoreCommandAlreadyExecuted('cloud', commandId)) {
            restoredSnapshot = false;
          } else {
            onProgress?.call(0.50,
                'A new Host restore was found. Rebuilding device data from a full snapshot...');
            // A Host Restore is a full replacement, not an incremental change.
            // Do not depend on timestamp filters here: old backup rows can carry
            // historical updatedAt values, and the marker time may be newer than
            // some rows. Force the unified snapshot downloader/importer to rebuild
            // the Client from the currently published Host snapshot.
            return rebuildFromCloudHostSnapshot(
              settings.copyWith(clearLastPullCursor: true),
              onProgress: onProgress,
              requestFreshSnapshot: false,
              expectedRestoreCommandId: commandId,
            );
          }
        }
        restoredSnapshot = restoredSnapshot ||
            changes.any((item) => item.operation == 'restore_snapshot') ||
            (initialCursor == null &&
                source == 'entity_snapshots' &&
                changes.isNotEmpty);
        onProgress?.call(
            (0.42 + (pageCount - 1) * 0.08).clamp(0.42, 0.86).toDouble(),
            'Applying ${changes.length} Cloud change(s) from page $pageCount...');
        final applied = await _syncCore.applyAuthoritativeChanges(changes);
        pulled += applied;
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] cloudPull:applied page=$pageCount '
          'decodedChanges=${changes.length} applied=$applied totalPulled=$pulled',
        );

        final hasMore = decodedPull['hasMore'] == true;
        pageCursor = (decodedPull['nextCursor'] ?? '').toString();
        if (!hasMore) {
          finalPullCursor =
              DateTime.tryParse(decodedPull['generatedAt']?.toString() ?? '');
          finalPullSequence = int.tryParse(
                  decodedPull['generatedSequence']?.toString() ?? '') ??
              finalPullSequence;
          break;
        }
        if (pageCursor.isEmpty) {
          return const CloudSyncResult(
              ok: false,
              message: 'Cloud pull pagination failed: missing next cursor.');
        }
      }

      final initialSnapshotStillUploading = initialCursor == null &&
          restoredSnapshot &&
          !allSnapshotSectionsComplete;
      if (initialSnapshotStillUploading) {
        onProgress?.call(
            0.90, 'Waiting for Host to finish uploading Store sections...');
        await CloudProvisioningStatus.markPending(
            message:
                'Host is still uploading store data. Download will continue automatically.');
      } else {
        onProgress?.call(0.90, 'Saving Cloud sync cursor...');
        if (finalPullCursor != null) {
          await settings.copyWith(lastPullCursor: finalPullCursor).save();
          await _recordDeviceSyncState('cloud', finalPullCursor,
              sequence: finalPullSequence, settings: settings);
        }
      }

      if (pulled > 0) {
        onProgress?.call(0.96, 'Cleaning up after Cloud sync...');
        await store.cleanupSoftDeletedRecords();
      }
      if (store.appIdentity.isClient &&
          (restoredSnapshot || pulled > 0) &&
          !store.needsInitialAdminSetup &&
          !initialSnapshotStillUploading) {
        await CloudProvisioningStatus.markComplete(
            message: 'Initial Store data downloaded.');
      }
      return CloudSyncResult(
        ok: true,
        pulled: pulled,
        restoredSnapshot: restoredSnapshot,
        message:
            'Cloud pull completed. Pulled $pulled authoritative change(s).',
      );
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Cloud pull failed: $error');
    }
  }

  Future<CloudSyncResult> syncNow(CloudSyncSettings settings,
      {DateTime? minSnapshotUpdatedAt,
      CloudSyncProgressCallback? onProgress}) async {
    final identity = store.appIdentity;
    if (!_cloudAllowedForIdentity(identity)) {
      return const CloudSyncResult(
          ok: false,
          message:
              'Cloud is not the active/configured sync transport for this device.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'Cloud API URL and token are required.');
    }
    final accessResult = await checkCurrentDeviceAccess(settings);
    if (accessResult != null) return accessResult;

    try {
      var pushed = 0;
      var pulled = 0;

      if (identity.isHost) {
        onProgress?.call(0.10, 'Preparing Host cloud snapshot queue...');
        await store.ensureHostCloudBootstrapSnapshotQueued();
        final repairedCloudQueue =
            await store.repairMissingHostCloudQueueForPendingChanges();
        if (repairedCloudQueue > 0) {
          onProgress?.call(0.18,
              '$repairedCloudQueue missing Host cloud snapshot queue item(s) were repaired...');
        }
        onProgress?.call(0.25, 'Sending Host heartbeat...');
        await sendHostHeartbeat(settings);
        onProgress?.call(0.40, 'Registering Host device...');
        await registerCurrentDevice(settings, transport: 'cloud');
        final hostPendingCount =
            _syncCore.pendingChangesForTarget('cloud').length;
        onProgress?.call(0.55, 'Publishing Host changes through Cloud relay...');
        final relayPublished = await _broadcastHostAuthorityViaRelay(settings);
        if (!relayPublished) {
          return const CloudSyncResult(
            ok: false,
            message:
                'Host cloud relay failed. Legacy Cloud fallback is disabled; retry when the relay is available.',
          );
        }
        pushed = hostPendingCount;
        onProgress?.call(
            0.90, 'Running safe local sync history maintenance...');
        await store.compactSyncedSyncHistoryForMaintenance();
        onProgress?.call(0.96, 'Running safe Cloud maintenance...');
        await runCloudMaintenance(settings);
        onProgress?.call(1.0, 'Host Cloud sync completed.');
        return CloudSyncResult(
          ok: true,
          pushed: pushed,
          pulled: 0,
          message:
              'Host Cloud sync completed through relay. Broadcast $pushed authoritative change(s).',
        );
      } else {
        // Any cloud-enabled Client that has local draft changes should send
        // them to the Host relay. LAN Clients normally queue to target "host",
        // so this only affects Web or remote desktop/mobile Clients whose
        // pending changes target "cloud_host".
        onProgress?.call(0.12, 'Registering Client device...');
        await registerCurrentDevice(settings, transport: 'cloud');
        onProgress?.call(0.28, 'Sending Client requests to Host relay...');
        pushed += await _pushPendingViaRelay(settings, target: 'cloud_host');
      }

      // Freeze the sequence watermark for the whole paginated pull. Reading
      // lastAppliedSequence after every page can skip pages: page 1 advances the
      // local state, then page 2 asks Cloud for sequence > the new value while
      // also passing the old page cursor. That combination can silently miss
      // events, which showed up as product count differences across devices.
      final baseLastAppliedSequence =
          SyncDeviceStateStore.lastAppliedSequenceForTransport(
              store.appIdentity, 'cloud');
      // Sequence is the authoritative Cloud watermark. Never combine it
      // with the legacy timestamp cursor: a newer local timestamp can filter out
      // older-but-unapplied Host events and leave the Client stuck behind the
      // Host. Only use the legacy cursor for pre-sequence clients.
      final initialCursor =
          baseLastAppliedSequence > 0 ? null : settings.lastPullCursor;
      final shouldUseSnapshotBootstrap = baseLastAppliedSequence <= 0;
      if (shouldUseSnapshotBootstrap &&
          await _cloudSnapshotIsNewerThanLocal(settings)) {
        onProgress?.call(0.32,
            'A newer Host snapshot was found. Rebuilding this device data...');
        return rebuildFromCloudHostSnapshot(
          settings.copyWith(clearLastPullCursor: true),
          onProgress: onProgress,
          requestFreshSnapshot: false,
        );
      }
      var pageCursor = '';
      DateTime? finalPullCursor;
      var finalPullSequence = 0;
      var pageCount = 0;
      var restoredSnapshot = false;
      var allSnapshotSectionsComplete = true;
      const maxPagesPerRun = 200;

      while (true) {
        pageCount += 1;
        if (pageCount > maxPagesPerRun) {
          return CloudSyncResult(
              ok: false,
              message:
                  'Cloud pull stopped after $maxPagesPerRun pages to avoid an infinite loop. Please retry sync.');
        }

        final query = <String, String>{
          'store_id': identity.storeId,
          'branch_id': identity.branchId,
          'limit': '1000',
        };
        if (baseLastAppliedSequence > 0) {
          query['since_sequence'] = baseLastAppliedSequence.toString();
        }
        if (initialCursor != null) {
          query['since'] = initialCursor.toIso8601String();
        }
        if (initialCursor == null && minSnapshotUpdatedAt != null) {
          query['min_snapshot_updated_at'] =
              minSnapshotUpdatedAt.toIso8601String();
        }
        if (pageCursor.isNotEmpty) query['cursor'] = pageCursor;

        final pullProgress =
            (0.35 + (pageCount - 1) * 0.08).clamp(0.35, 0.82).toDouble();
        onProgress?.call(
            pullProgress, 'Pulling Cloud changes page $pageCount...');
        final pull = await _client
            .get(settings.endpoint('/api/sync/pull', query),
                headers: _headers(settings))
            .timeout(const Duration(seconds: 20));
        if (pull.statusCode < 200 || pull.statusCode >= 300) {
          final message = 'Cloud pull failed: ${pull.statusCode} ${pull.body}';
          return CloudSyncResult(ok: false, message: message);
        }

        final decodedPull = jsonDecode(pull.body) as Map<String, dynamic>;
        final rawChanges =
            decodedPull['changes'] as List<dynamic>? ?? const <dynamic>[];
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] cloudSyncNow:decoded page=$pageCount '
          'source=${decodedPull['source']} '
          'changes=${rawChanges.length} '
          'hasMore=${decodedPull['hasMore']} '
          'generatedAt=${decodedPull['generatedAt']} '
          'generatedSequence=${decodedPull['generatedSequence']}',
        );
        for (final raw in rawChanges.take(40)) {
          final change =
              SyncChange.fromJson(Map<String, dynamic>.from(raw as Map));
          SyncDiagnosticsLog.add(
            '[SYNC_TRACE] cloudSyncNow:rawChange ${SyncDiagnosticsLog.summarizeChange(change)}',
          );
        }
        final generationRebuild = await _rebuildIfHostSnapshotGenerationChanged(
          settings,
          decodedPull,
          onProgress: onProgress,
        );
        if (generationRebuild != null) return generationRebuild;
        if ((decodedPull['source'] ?? '').toString() == 'entity_snapshots') {
          final pageAllSectionsComplete =
              decodedPull['allSnapshotSectionsComplete'] == true;
          allSnapshotSectionsComplete =
              allSnapshotSectionsComplete && pageAllSectionsComplete;
          await CloudProvisioningStatus.updateSnapshotSections(
            decodedPull['snapshotSections'] is Map<String, dynamic>
                ? decodedPull['snapshotSections'] as Map<String, dynamic>
                : null,
            allComplete: pageAllSectionsComplete,
          );
        }
        if (decodedPull['needsSnapshot'] == true) {
          await CloudSyncSettings.clearSavedPullCursor();
          final generation = _remoteHostSnapshotGeneration(decodedPull);
          final commandId = _remoteHostRestoreCommandId(decodedPull);
          if (_restoreCommandAlreadyExecuted('cloud', commandId)) {
            final generatedAt = DateTime.tryParse(
                    decodedPull['generatedAt']?.toString() ?? '') ??
                DateTime.now();
            final generatedSequence = int.tryParse(
                    decodedPull['generatedSequence']?.toString() ?? '') ??
                0;
            await settings.copyWith(lastPullCursor: generatedAt).save();
            await _recordDeviceSyncState('cloud', generatedAt,
                sequence: generatedSequence, settings: settings);
            return CloudSyncResult(
              ok: true,
              message:
                  'A previously executed rebuild command was ignored and the sync cursor was updated.',
              pushed: pushed,
              pulled: pulled,
            );
          }
          return rebuildFromCloudHostSnapshot(
            settings.copyWith(clearLastPullCursor: true),
            onProgress: onProgress,
            requestFreshSnapshot: false,
            expectedSnapshotGeneration: generation,
            expectedRestoreCommandId: commandId,
          );
        }
        final decodedChanges = _syncCore.decodeRemoteChanges(rawChanges);
        final changes = _syncCore.filterOutLocalEchoes(decodedChanges);
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] cloudSyncNow:filtered page=$pageCount '
          'decoded=${decodedChanges.length} afterEchoFilter=${changes.length} '
          'localDevice=${store.deviceId}',
        );
        final source = (decodedPull['source'] ?? '').toString();
        final restoreMarker = changes.any((item) =>
            item.entityType == 'system' &&
            item.operation == 'cloud_restore_snapshot_ready');
        if (restoreMarker && store.appIdentity.isClient) {
          final commandId = _restoreCommandIdFromChanges(changes);
          if (_restoreCommandAlreadyExecuted('cloud', commandId)) {
            restoredSnapshot = false;
          } else {
            onProgress?.call(0.50,
                'A new Host restore was found. Rebuilding device data from a full snapshot...');
            // A Host Restore is a full replacement, not an incremental change.
            // Do not depend on timestamp filters here: old backup rows can carry
            // historical updatedAt values, and the marker time may be newer than
            // some rows. Force the unified snapshot downloader/importer to rebuild
            // the Client from the currently published Host snapshot.
            return rebuildFromCloudHostSnapshot(
              settings.copyWith(clearLastPullCursor: true),
              onProgress: onProgress,
              requestFreshSnapshot: false,
              expectedRestoreCommandId: commandId,
            );
          }
        }
        restoredSnapshot = restoredSnapshot ||
            changes.any((item) => item.operation == 'restore_snapshot') ||
            (initialCursor == null &&
                source == 'entity_snapshots' &&
                changes.isNotEmpty);
        onProgress?.call(
            (0.42 + (pageCount - 1) * 0.08).clamp(0.42, 0.86).toDouble(),
            'Applying ${changes.length} Cloud change(s) from page $pageCount...');
        final applied = await _syncCore.applyAuthoritativeChanges(changes);
        pulled += applied;
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] cloudSyncNow:applied page=$pageCount '
          'decodedChanges=${changes.length} applied=$applied totalPulled=$pulled',
        );

        final hasMore = decodedPull['hasMore'] == true;
        pageCursor = (decodedPull['nextCursor'] ?? '').toString();
        if (!hasMore) {
          finalPullCursor =
              DateTime.tryParse(decodedPull['generatedAt']?.toString() ?? '');
          finalPullSequence = int.tryParse(
                  decodedPull['generatedSequence']?.toString() ?? '') ??
              finalPullSequence;
          break;
        }
        if (pageCursor.isEmpty) {
          return const CloudSyncResult(
              ok: false,
              message: 'Cloud pull pagination failed: missing next cursor.');
        }
      }

      final initialSnapshotStillUploading = initialCursor == null &&
          restoredSnapshot &&
          !allSnapshotSectionsComplete;
      if (initialSnapshotStillUploading) {
        onProgress?.call(
            0.90, 'Waiting for Host to finish uploading Store sections...');
        await CloudProvisioningStatus.markPending(
            message:
                'Host is still uploading store data. Download will continue automatically.');
      } else {
        onProgress?.call(0.90, 'Saving Cloud sync cursor...');
        if (finalPullCursor != null) {
          await settings.copyWith(lastPullCursor: finalPullCursor).save();
          await _recordDeviceSyncState('cloud', finalPullCursor,
              sequence: finalPullSequence, settings: settings);
        }
      }

      if (pulled > 0) {
        onProgress?.call(0.94, 'Cleaning up after Cloud sync...');
        await store.cleanupSoftDeletedRecords();
      }
      if (store.appIdentity.isClient) {
        onProgress?.call(0.97, 'Running Client sync history maintenance...');
        await store.compactClientSyncedSyncHistoryForMaintenance();
      }
      if (store.appIdentity.isClient &&
          (restoredSnapshot || pulled > 0) &&
          !store.needsInitialAdminSetup &&
          !initialSnapshotStillUploading) {
        await CloudProvisioningStatus.markComplete(
            message: 'Initial Store data downloaded.');
      }
      return CloudSyncResult(
        ok: true,
        pushed: pushed,
        pulled: pulled,
        restoredSnapshot: restoredSnapshot,
        message:
            'Cloud sync completed. Sent $pushed request(s) to Host relay, pulled $pulled authoritative change(s).',
      );
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Cloud sync failed: $error');
    }
  }
}

class _CloudSnapshotPullTransport implements UnifiedSnapshotChunkPullTransport {
  _CloudSnapshotPullTransport({
    required this.settings,
    required this.headers,
    required this.client,
    required this.storeId,
    required this.branchId,
  });

  final CloudSyncSettings settings;
  final Map<String, String> headers;
  final http.Client client;
  final String storeId;
  final String branchId;
  String _jobId = '';

  @override
  Future<UnifiedSnapshotManifestResponse> requestManifest(
      {bool force = false}) async {
    final response = await client
        .get(
          settings.endpoint('/api/sync/bootstrap-snapshot', {
            'mode': 'manifest',
            'store_id': storeId,
            'branch_id': branchId,
          }),
          headers: headers,
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          'Cloud snapshot manifest failed: ${response.statusCode} ${response.body}');
    }
    final decoded = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    _jobId = (decoded['jobId'] ?? '').toString();
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
  }

  @override
  Future<UnifiedSnapshotChunkResponse> requestChunk(int ordinal) async {
    final query = <String, String>{
      'mode': 'chunk',
      'store_id': storeId,
      'branch_id': branchId,
      'ordinal': ordinal.toString(),
    };
    if (_jobId.trim().isNotEmpty) query['job_id'] = _jobId;
    final response = await client
        .get(settings.endpoint('/api/sync/bootstrap-snapshot', query),
            headers: headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          'Cloud snapshot chunk ${ordinal + 1} failed: ${response.statusCode} ${response.body}');
    }
    final decoded = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final chunk = decoded['chunk'];
    if (chunk is! Map) {
      throw StateError('Cloud snapshot chunk ${ordinal + 1} is invalid.');
    }
    return UnifiedSnapshotChunkResponse(
      chunk: Map<String, dynamic>.from(chunk),
      ordinal: (decoded['ordinal'] as num?)?.toInt() ?? ordinal,
      totalChunks: (decoded['totalChunks'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> ackChunk(int ordinal) async {
    // Cloud snapshot chunk ACK is currently client-local; the unified transfer
    // engine still calls this hook so Cloud and LAN share the same pipeline.
  }
}

class _CloudRelaySnapshotPullTransport
    implements UnifiedSnapshotChunkPullTransport {
  _CloudRelaySnapshotPullTransport({
    required CloudSyncService service,
    required this.settings,
    String snapshotKind = 'full_store',
    String rebuildRequestId = '',
    int requiredMinSequence = 0,
  })  : _service = service,
        _snapshotKind = snapshotKind,
        _rebuildRequestId = rebuildRequestId,
        _requiredMinSequence = requiredMinSequence;

  final CloudSyncService _service;
  final CloudSyncSettings settings;
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
          'Cloud relay request failed.');
    }
    return response;
  }

  Future<void> dispose() async {
    try {
      if (_jobId.trim().isNotEmpty) {
        await _request('cloud_snapshot_release', {'jobId': _jobId});
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
    final identity = _service.store.appIdentity;
    final response = await _request('cloud_snapshot_manifest', {
      'storeId': identity.storeId,
      'branchId': identity.branchId,
      'deviceId': _service.store.deviceId,
      'snapshotKind': _snapshotKind,
      'force': force,
      if (_rebuildRequestId.trim().isNotEmpty)
        'rebuildRequestId': _rebuildRequestId.trim(),
      if (_requiredMinSequence > 0)
        'requiredMinSequence': _requiredMinSequence,
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
      requiredMinSequence:
          (response['requiredMinSequence'] as num?)?.toInt(),
    );
  }

  @override
  Future<UnifiedSnapshotChunkResponse> requestChunk(int ordinal) async {
    if (_jobId.trim().isEmpty) {
      throw StateError('Cloud relay snapshot job has not been created yet.');
    }
    final response = await _request('cloud_snapshot_chunk', {
      'jobId': _jobId,
      'ordinal': ordinal,
    });
    final chunk = response['chunk'];
    if (chunk is! Map) {
      throw StateError('Cloud relay snapshot chunk ${ordinal + 1} is invalid.');
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

class _CloudSnapshotPushTransport implements UnifiedSnapshotChunkPushTransport {
  _CloudSnapshotPushTransport({
    required this.settings,
    required this.headers,
    required this.client,
  });

  final CloudSyncSettings settings;
  final Map<String, String> headers;
  final http.Client client;

  @override
  Future<void> uploadChunk(Map<String, dynamic> chunk,
      {required bool force, required bool preserveExisting}) async {
    final body = Map<String, dynamic>.from(chunk);
    body['force'] = force;
    body['preserveExisting'] = preserveExisting;
    http.Response? response;
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt += 1) {
      try {
        response = await client
            .post(
              settings.endpoint('/api/sync/bootstrap-snapshot'),
              headers: headers,
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 429 && response.statusCode < 500) break;
      } catch (error) {
        lastError = error;
      }
      if (attempt < 3) {
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    if (response == null) {
      throw StateError('Failed to upload snapshot chunk: $lastError');
    }
    if (response.statusCode == 409 && !force) {
      throw StateError(
          'A Cloud provisioning snapshot is already running. Try again after it finishes or use force rebuild.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          'Failed to upload snapshot chunk: ${response.statusCode} ${response.body}');
    }
  }
}
