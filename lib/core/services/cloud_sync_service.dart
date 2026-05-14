import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../data/app_store.dart';
import '../../models/app_identity.dart';
import '../../models/sync_change.dart';
import 'local_database_service.dart';

class CloudSyncSettings {
  const CloudSyncSettings({
    required this.enabled,
    required this.apiBaseUrl,
    required this.apiToken,
    this.lastPullCursor,
    this.autoSyncEnabled = true,
    this.intervalSeconds = 30,
  });

  static const _apiBaseUrlKey = 'cloud_api_base_url';
  static const _apiTokenKey = 'cloud_api_token';
  static const _lastPullCursorKey = 'cloud_last_pull_cursor';

  static Future<void> clearSavedPullCursor() async {
    await LocalDatabaseService.deleteString(_lastPullCursorKey);
  }
  static const _autoSyncKey = 'cloud_auto_sync_enabled';
  static const _intervalKey = 'cloud_auto_sync_interval_seconds';

  final bool enabled;
  final String apiBaseUrl;
  final String apiToken;
  final DateTime? lastPullCursor;
  final bool autoSyncEnabled;
  final int intervalSeconds;

  bool get isConfigured => enabled && apiBaseUrl.trim().isNotEmpty && apiToken.trim().isNotEmpty;

  Uri endpoint(String path, [Map<String, String>? query]) {
    final base = apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$base$normalizedPath');
    return query == null ? uri : uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  CloudSyncSettings copyWith({
    bool? enabled,
    String? apiBaseUrl,
    String? apiToken,
    DateTime? lastPullCursor,
    bool clearLastPullCursor = false,
    bool? autoSyncEnabled,
    int? intervalSeconds,
  }) =>
      CloudSyncSettings(
        enabled: enabled ?? this.enabled,
        apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
        apiToken: apiToken ?? this.apiToken,
        lastPullCursor: clearLastPullCursor ? null : (lastPullCursor ?? this.lastPullCursor),
        autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
        intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      );

  static CloudSyncSettings load() {
    final base = LocalDatabaseService.getString(_apiBaseUrlKey);
    final token = LocalDatabaseService.getString(_apiTokenKey) ?? '';
    final cursorRaw = LocalDatabaseService.getString(_lastPullCursorKey) ?? '';
    final autoRaw = LocalDatabaseService.getString(_autoSyncKey);
    final intervalRaw = LocalDatabaseService.getString(_intervalKey);
    final currentOrigin = kIsWeb ? Uri.base.origin : '';
    return CloudSyncSettings(
      enabled: true,
      apiBaseUrl: (base == null || base.trim().isEmpty) ? currentOrigin : base.trim(),
      apiToken: token,
      lastPullCursor: DateTime.tryParse(cursorRaw),
      autoSyncEnabled: autoRaw == null ? true : autoRaw == 'true',
      intervalSeconds: int.tryParse(intervalRaw ?? '')?.clamp(30, 3600).toInt() ?? 30,
    );
  }

  Future<void> save() async {
    await LocalDatabaseService.setString(_apiBaseUrlKey, apiBaseUrl.trim());
    await LocalDatabaseService.setString(_apiTokenKey, apiToken.trim());
    await LocalDatabaseService.setString(_autoSyncKey, autoSyncEnabled ? 'true' : 'false');
    await LocalDatabaseService.setString(_intervalKey, intervalSeconds.toString());
    if (lastPullCursor == null) {
      await LocalDatabaseService.deleteString(_lastPullCursorKey);
    } else {
      await LocalDatabaseService.setString(_lastPullCursorKey, lastPullCursor!.toIso8601String());
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


class CloudDeviceStatus {
  const CloudDeviceStatus({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.role,
    required this.transport,
    required this.lastSeenAt,
    required this.appVersion,
    this.revoked = false,
  });

  final String deviceId;
  final String deviceName;
  final String platform;
  final String role;
  final String transport;
  final DateTime? lastSeenAt;
  final String appVersion;
  final bool revoked;

  bool get isOnline => lastSeenAt != null && DateTime.now().toUtc().difference(lastSeenAt!.toUtc()) <= const Duration(seconds: 90);

  factory CloudDeviceStatus.fromJson(Map<String, dynamic> json) => CloudDeviceStatus(
        deviceId: (json['deviceId'] ?? json['device_id'] ?? '').toString(),
        deviceName: (json['deviceName'] ?? json['device_name'] ?? '').toString(),
        platform: (json['platform'] ?? '').toString(),
        role: (json['role'] ?? '').toString(),
        transport: (json['transport'] ?? '').toString(),
        lastSeenAt: DateTime.tryParse((json['lastSeenAt'] ?? json['last_seen_at'] ?? '').toString()),
        appVersion: (json['appVersion'] ?? json['app_version'] ?? '').toString(),
        revoked: json['revoked'] == true,
      );
}

class CloudSyncResult {
  const CloudSyncResult({required this.ok, required this.message, this.pushed = 0, this.pulled = 0});
  final bool ok;
  final String message;
  final int pushed;
  final int pulled;
}

class CloudSyncService {
  CloudSyncService(this.store, {http.Client? client}) : _client = client ?? http.Client();

  final AppStore store;
  final http.Client _client;

  Map<String, String> _headers(CloudSyncSettings settings) {
    final identity = store.appIdentity;
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      // The deployment token keeps backward compatibility with the current API,
      // while the device headers prepare the server for per-device auth.
      if (settings.apiToken.trim().isNotEmpty) 'Authorization': 'Bearer ${settings.apiToken.trim()}',
      'X-Device-Id': store.deviceId,
      'X-Device-Token': identity.deviceToken,
      'X-Device-Role': identity.deviceRole.name,
      'X-Sync-Transport': identity.transportType,
      'X-Store-Id': identity.storeId,
      'X-Branch-Id': identity.branchId,
    };
  }


  Future<CloudSyncResult> registerCurrentDevice(CloudSyncSettings settings, {String transport = 'cloud'}) async {
    final identity = store.appIdentity;
    if (!settings.isConfigured) return const CloudSyncResult(ok: false, message: 'Cloud API URL and token are required.');
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
              'deviceToken': identity.deviceToken,
              'appVersion': 'store-manager-pro',
              'storeEpoch': identity.storeEpoch,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return CloudSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300 ? 'Device heartbeat updated.' : 'Device heartbeat failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Device heartbeat failed: $error');
    }
  }

  Future<List<CloudDeviceStatus>> listDevices(CloudSyncSettings settings) async {
    final identity = store.appIdentity;
    if (!settings.isConfigured) return const <CloudDeviceStatus>[];
    final response = await _client
        .get(
          settings.endpoint('/api/sync/devices', {
            'store_id': identity.storeId,
            'branch_id': identity.branchId,
          }),
          headers: _headers(settings),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) return const <CloudDeviceStatus>[];
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return (decoded['devices'] as List<dynamic>? ?? [])
        .map((item) => CloudDeviceStatus.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<CloudSyncResult> testConnection(CloudSyncSettings settings) async {
    if (!settings.isConfigured) {
      return const CloudSyncResult(ok: false, message: 'Cloud API URL and token are required.');
    }
    try {
      final response = await _client.get(settings.endpoint('/api/health'), headers: _headers(settings)).timeout(const Duration(seconds: 10));
      return CloudSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300 ? 'Cloud API connection is healthy.' : 'Cloud API returned ${response.statusCode}: ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Cloud API connection failed: $error');
    }
  }

  Future<CloudSyncResult> validateSingleHost(CloudSyncSettings settings) async {
    final identity = store.appIdentity;
    if (!settings.isConfigured) {
      return const CloudSyncResult(ok: false, message: 'Cloud API URL and token are required.');
    }
    final status = await getHostHeartbeatStatus(settings);
    if (status.cloudReachable && status.hostReachable && status.hostDeviceId.isNotEmpty && status.hostDeviceId != store.deviceId) {
      return CloudSyncResult(
        ok: false,
        message: 'Another active Host is already connected for store ${identity.storeId}: ${status.hostDeviceName.isEmpty ? status.hostDeviceId : status.hostDeviceName}. Change this device to CLIENT or turn off the old Host first.',
      );
    }
    return const CloudSyncResult(ok: true, message: 'No other active Host was found.');
  }

  Future<CloudSyncResult> sendHostHeartbeat(CloudSyncSettings settings) async {
    final identity = store.appIdentity;
    if (!identity.isCloudEnabled || !identity.isHost) {
      return const CloudSyncResult(ok: false, message: 'Heartbeat is only sent by a cloud-enabled Host device.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(ok: false, message: 'Cloud API URL and token are required.');
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
              'appVersion': 'store-manager-pro',
              'syncMode': identity.syncMode.name,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return CloudSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300 ? 'Host heartbeat updated.' : 'Host heartbeat failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Host heartbeat failed: $error');
    }
  }

  Future<HostHeartbeatStatus> getHostHeartbeatStatus(CloudSyncSettings settings, {Duration staleAfter = const Duration(seconds: 90)}) async {
    final identity = store.appIdentity;
    if (!settings.isConfigured) {
      return const HostHeartbeatStatus(cloudReachable: false, hostReachable: false, message: 'Cloud API URL and token are required.');
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
        return HostHeartbeatStatus(cloudReachable: false, hostReachable: false, message: 'Cloud API returned ${response.statusCode}: ${response.body}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final rawLastSeen = decoded['lastSeenAt'] ?? decoded['last_seen_at'];
      final lastSeenAt = rawLastSeen == null ? null : DateTime.tryParse(rawLastSeen.toString());
      final hostReachable = lastSeenAt != null && DateTime.now().toUtc().difference(lastSeenAt.toUtc()) <= staleAfter;
      final hostDeviceId = (decoded['hostDeviceId'] ?? decoded['host_device_id'] ?? '').toString();
      final hostDeviceName = (decoded['hostDeviceName'] ?? decoded['host_device_name'] ?? '').toString();
      return HostHeartbeatStatus(
        cloudReachable: true,
        hostReachable: hostReachable,
        lastSeenAt: lastSeenAt,
        hostDeviceId: hostDeviceId,
        hostDeviceName: hostDeviceName,
        message: hostReachable ? 'Host heartbeat is fresh.' : (lastSeenAt == null ? 'No host heartbeat was found.' : 'Host heartbeat is stale.'),
      );
    } catch (error) {
      return HostHeartbeatStatus(cloudReachable: false, hostReachable: false, message: 'Cloud API connection failed: $error');
    }
  }

  Future<int> _pushPendingToEndpoint(CloudSyncSettings settings, String target, String path) async {
    final identity = store.appIdentity;
    final pending = store.pendingSyncChangesForTarget(target);
    final pendingIds = pending.map((item) => item.id).toList();
    if (pending.isEmpty) return 0;

    await store.markSyncQueueChangesInProgress(pendingIds);
    final push = await _client
        .post(
          settings.endpoint(path),
          headers: _headers(settings),
          body: jsonEncode({
            'deviceId': store.deviceId,
            'storeId': identity.storeId,
            'branchId': identity.branchId,
            'changes': pending.map((item) => item.toJson()).toList(),
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (push.statusCode < 200 || push.statusCode >= 300) {
      final message = 'Cloud push failed: ${push.statusCode} ${push.body}';
      await store.markSyncQueueChangesFailed(pendingIds, message);
      throw StateError(message);
    }
    final decoded = jsonDecode(push.body) as Map<String, dynamic>;
    final ackIds = (decoded['ackIds'] as List<dynamic>? ?? []).map((item) => '$item').toList();
    await store.markSyncChangesSyncedByIds(ackIds.isEmpty ? pendingIds : ackIds);
    return pending.length;
  }

  Future<int> _hostPullRemoteRequests(CloudSyncSettings settings) async {
    final identity = store.appIdentity;
    if (!identity.isHost) return 0;
    final pull = await _client
        .get(
          settings.endpoint('/api/sync/requests/pull', {
            'store_id': identity.storeId,
            'branch_id': identity.branchId,
            'host_device_id': store.deviceId,
          }),
          headers: _headers(settings),
        )
        .timeout(const Duration(seconds: 20));
    if (pull.statusCode < 200 || pull.statusCode >= 300) {
      throw StateError('Cloud request pull failed: ${pull.statusCode} ${pull.body}');
    }
    final decoded = jsonDecode(pull.body) as Map<String, dynamic>;
    final changes = (decoded['changes'] as List<dynamic>? ?? [])
        .map((item) => SyncChange.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((item) => item.deviceId != store.deviceId)
        .toList();
    if (changes.isEmpty) return 0;

    // Host accepts remote drafts here, applies them locally, and queues them to
    // Cloud as authoritative events. This keeps Cloud as a relay/mirror only.
    await store.applyRemoteSyncChanges(changes, markAppliedAsSynced: true, mirrorToCloud: true);

    final ackIds = changes.map((item) => item.id).toList();
    await _client
        .post(
          settings.endpoint('/api/sync/requests/ack'),
          headers: _headers(settings),
          body: jsonEncode({'storeId': identity.storeId, 'branchId': identity.branchId, 'hostDeviceId': store.deviceId, 'ackIds': ackIds}),
        )
        .timeout(const Duration(seconds: 20));
    return changes.length;
  }

  Future<CloudSyncResult> syncNow(CloudSyncSettings settings) async {
    final identity = store.appIdentity;
    if (identity.syncMode == SyncMode.localOnly || identity.syncMode == SyncMode.lanOnly) {
      return const CloudSyncResult(ok: false, message: 'Enable cloudConnected or marketplaceEnabled sync mode first.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(ok: false, message: 'Cloud API URL and token are required.');
    }

    try {
      var pushed = 0;
      var pulled = 0;
      var acceptedRemoteRequests = 0;

      if (identity.isHost) {
        await store.ensureHostCloudBootstrapSnapshotQueued();
        await sendHostHeartbeat(settings);
        await registerCurrentDevice(settings, transport: 'cloud');
        acceptedRemoteRequests = await _hostPullRemoteRequests(settings);
        pushed += await _pushPendingToEndpoint(settings, 'cloud', '/api/sync/push');
        return CloudSyncResult(
          ok: true,
          pushed: pushed,
          pulled: 0,
          message: 'Host cloud sync completed. Accepted $acceptedRemoteRequests remote request(s), pushed $pushed authoritative change(s).',
        );
      } else {
        // Any cloud-enabled Client that has local draft changes should send
        // them to the Host relay. LAN Clients normally queue to target "host",
        // so this only affects Web or remote desktop/mobile Clients whose
        // pending changes target "cloud_host".
        await registerCurrentDevice(settings, transport: 'cloud');
        pushed += await _pushPendingToEndpoint(settings, 'cloud_host', '/api/sync/requests/push');
      }

      final initialCursor = settings.lastPullCursor;
      var pageCursor = '';
      DateTime? finalPullCursor;
      var pageCount = 0;
      const maxPagesPerRun = 200;

      while (true) {
        pageCount += 1;
        if (pageCount > maxPagesPerRun) {
          return CloudSyncResult(ok: false, message: 'Cloud pull stopped after $maxPagesPerRun pages to avoid an endless loop. Please retry sync.');
        }

        final query = <String, String>{
          'store_id': identity.storeId,
          'branch_id': identity.branchId,
          'limit': '1000',
        };
        if (initialCursor != null) query['since'] = initialCursor.toIso8601String();
        if (pageCursor.isNotEmpty) query['cursor'] = pageCursor;

        final pull = await _client.get(settings.endpoint('/api/sync/pull', query), headers: _headers(settings)).timeout(const Duration(seconds: 20));
        if (pull.statusCode < 200 || pull.statusCode >= 300) {
          final message = 'Cloud pull failed: ${pull.statusCode} ${pull.body}';
          return CloudSyncResult(ok: false, message: message);
        }

        final decodedPull = jsonDecode(pull.body) as Map<String, dynamic>;
        final changes = (decodedPull['changes'] as List<dynamic>? ?? [])
            .map((item) => SyncChange.fromJson(Map<String, dynamic>.from(item as Map)))
            .where((item) => item.deviceId != store.deviceId)
            .toList();
        await store.applyRemoteSyncChanges(changes, markAppliedAsSynced: true);
        pulled += changes.length;

        final hasMore = decodedPull['hasMore'] == true;
        pageCursor = (decodedPull['nextCursor'] ?? '').toString();
        if (!hasMore) {
          finalPullCursor = DateTime.tryParse(decodedPull['generatedAt']?.toString() ?? '');
          break;
        }
        if (pageCursor.isEmpty) {
          return const CloudSyncResult(ok: false, message: 'Cloud pull pagination failed: missing next cursor.');
        }
      }

      if (finalPullCursor != null) {
        await settings.copyWith(lastPullCursor: finalPullCursor).save();
      }

      return CloudSyncResult(
        ok: true,
        pushed: pushed,
        pulled: pulled,
        message: 'Cloud sync completed. Sent $pushed request(s) to Host relay, pulled $pulled authoritative change(s).',
      );
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Cloud sync failed: $error');
    }
  }
}

class AutoCloudSyncController {
  AutoCloudSyncController(this.store);

  final AppStore store;
  Timer? _timer;
  Timer? _debounceTimer;
  bool _running = false;
  bool _disposed = false;
  int _lastCloudQueueCount = 0;
  int _lastRelayQueueCount = 0;

  Future<void> start() async {
    stop();
    _disposed = false;
    if (!store.appIdentity.isCloudEnabled) return;
    final settings = CloudSyncSettings.load();
    if (!settings.autoSyncEnabled || !settings.isConfigured) return;

    _lastCloudQueueCount = store.pendingSyncQueueForTarget('cloud', readyOnly: false).length;
    _lastRelayQueueCount = store.pendingSyncQueueForTarget('cloud_host', readyOnly: false).length;
    store.removeListener(_onStoreChanged);
    store.addListener(_onStoreChanged);

    final interval = Duration(seconds: settings.intervalSeconds.clamp(30, 3600).toInt());
    _timer = Timer.periodic(interval, (_) => _tick());
    await _tick();
  }

  void stop() {
    _disposed = true;
    store.removeListener(_onStoreChanged);
    _timer?.cancel();
    _debounceTimer?.cancel();
    _timer = null;
    _debounceTimer = null;
  }

  void _onStoreChanged() {
    if (_disposed) return;
    final settings = CloudSyncSettings.load();
    if (!settings.autoSyncEnabled || !settings.isConfigured || !store.appIdentity.isCloudEnabled) return;

    final cloudCount = store.pendingSyncQueueForTarget('cloud', readyOnly: false).length;
    final relayCount = store.pendingSyncQueueForTarget('cloud_host', readyOnly: false).length;
    final hasNewCloudWork = cloudCount > _lastCloudQueueCount || relayCount > _lastRelayQueueCount;
    _lastCloudQueueCount = cloudCount;
    _lastRelayQueueCount = relayCount;
    if (!hasNewCloudWork) return;

    // Do not wait for the next polling interval after a local edit. This is why
    // some devices appeared to sync at 30 seconds even when polling was set to 5.
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 3), () => _tick());
  }

  Future<void> _tick() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      final settings = CloudSyncSettings.load();
      if (settings.autoSyncEnabled && settings.isConfigured && store.appIdentity.isCloudEnabled) {
        await CloudSyncService(store).syncNow(settings);
        _lastCloudQueueCount = store.pendingSyncQueueForTarget('cloud', readyOnly: false).length;
        _lastRelayQueueCount = store.pendingSyncQueueForTarget('cloud_host', readyOnly: false).length;
      }
    } finally {
      _running = false;
    }
  }
}
