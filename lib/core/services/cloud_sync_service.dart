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

  bool get hasDeploymentToken => apiToken.trim().isNotEmpty;
  bool get hasDeviceCredentials {
    final raw = LocalDatabaseService.getString('app_identity_v1') ?? '';
    try {
      final identity = AppIdentity.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      return identity.deviceId.trim().isNotEmpty && identity.deviceToken.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }
  bool get isConfigured => enabled && apiBaseUrl.trim().isNotEmpty && (hasDeploymentToken || hasDeviceCredentials);

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

typedef CloudSyncProgressCallback = void Function(double value, String label);

class CloudSyncResult {
  const CloudSyncResult({required this.ok, required this.message, this.pushed = 0, this.pulled = 0, this.restoredSnapshot = false});
  final bool ok;
  final String message;
  final int pushed;
  final int pulled;
  final bool restoredSnapshot;
}


class CloudPairingCodeResult {
  const CloudPairingCodeResult({required this.ok, required this.message, this.code = '', this.expiresAt});
  final bool ok;
  final String message;
  final String code;
  final DateTime? expiresAt;
}

class CloudPairingClaimResult {
  const CloudPairingClaimResult({required this.ok, required this.message, this.identity});
  final bool ok;
  final String message;
  final AppIdentity? identity;
}

class CloudSyncService {
  CloudSyncService(this.store, {http.Client? client}) : _client = client ?? http.Client();

  final AppStore store;
  final http.Client _client;


  Future<CloudPairingCodeResult> createPairingCode(CloudSyncSettings settings, {String transport = 'cloud', int ttlMinutes = 5}) async {
    final identity = store.appIdentity;
    if (!identity.isHost) return const CloudPairingCodeResult(ok: false, message: 'Only the Host can create pairing codes.');
    if (!settings.hasDeploymentToken || settings.apiBaseUrl.trim().isEmpty) return const CloudPairingCodeResult(ok: false, message: 'Cloud API URL and Host deployment token are required.');
    try {
      if (transport == 'cloud') {
        await store.ensureHostCloudBootstrapSnapshotQueued(force: true);
        await _pushPendingToEndpoint(settings, 'cloud', '/api/sync/push');
      }
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
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return CloudPairingCodeResult(ok: false, message: 'Pairing code failed: ${response.statusCode} ${response.body}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return CloudPairingCodeResult(
        ok: decoded['ok'] == true,
        message: decoded['ok'] == true ? 'Pairing code created.' : (decoded['error']?.toString() ?? 'Pairing code failed.'),
        code: decoded['code']?.toString() ?? '',
        expiresAt: DateTime.tryParse(decoded['expiresAt']?.toString() ?? ''),
      );
    } catch (error) {
      return CloudPairingCodeResult(ok: false, message: 'Pairing code failed: $error');
    }
  }

  Future<CloudPairingClaimResult> claimPairingCode(CloudSyncSettings settings, String code) async {
    final current = store.appIdentity;
    // Client bootstrap pairing intentionally requires only the Cloud API URL and
    // a single-use pairing code. The Host deployment token must stay on Host devices.
    if (!settings.enabled || settings.apiBaseUrl.trim().isEmpty) {
      return const CloudPairingClaimResult(ok: false, message: 'Cloud API URL is required.');
    }
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
              'appVersion': 'store-manager-pro',
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return CloudPairingClaimResult(ok: false, message: 'Pairing failed: ${response.statusCode} ${response.body}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['ok'] != true) {
        return CloudPairingClaimResult(ok: false, message: decoded['error']?.toString() ?? 'Pairing failed.');
      }
      final transport = decoded['transport']?.toString() == 'lan' ? SyncMode.lanOnly : SyncMode.cloudConnected;
      final identity = current.copyWith(
        storeId: decoded['storeId']?.toString() ?? current.storeId,
        branchId: decoded['branchId']?.toString() ?? current.branchId,
        hostDeviceId: decoded['hostDeviceId']?.toString() ?? current.hostDeviceId,
        deviceRole: DeviceRole.client,
        syncMode: transport,
        deviceToken: decoded['deviceToken']?.toString() ?? current.deviceToken,
        updatedAt: DateTime.now(),
      );
      await store.updateAppIdentityDuringSetup(identity);
      if (identity.syncMode == SyncMode.cloudConnected || identity.syncMode == SyncMode.marketplaceEnabled) {
        final rebuild = await rebuildFromCloudHostSnapshot(settings);
        if (!rebuild.ok) {
          return CloudPairingClaimResult(ok: false, message: 'Pairing succeeded, but Host snapshot rebuild failed: ${rebuild.message}', identity: identity);
        }
      }
      return CloudPairingClaimResult(ok: true, message: 'Device paired successfully. Full Host snapshot was applied.', identity: identity);
    } catch (error) {
      return CloudPairingClaimResult(ok: false, message: 'Pairing failed: $error');
    }
  }

  Future<CloudSyncResult> requestFreshHostSnapshot(CloudSyncSettings settings, {DateTime? requestedAt}) async {
    final identity = store.appIdentity;
    if (identity.isHost) return const CloudSyncResult(ok: true, message: 'Host can publish its own snapshot directly.');
    if (!settings.isConfigured) return const CloudSyncResult(ok: false, message: 'Cloud API URL and token are required.');
    final now = requestedAt ?? DateTime.now().toUtc();
    final request = SyncChange(
      id: '${now.microsecondsSinceEpoch}-${store.deviceId}-snapshot-request',
      entityType: 'system',
      entityId: 'store',
      operation: 'request_snapshot',
      deviceId: store.deviceId,
      createdAt: now,
      payload: <String, dynamic>{
        '_syncV2': <String, dynamic>{
          'kind': 'draftCommand',
          'transport': 'cloud',
          'recordedAt': now.toIso8601String(),
          'sourceRole': 'client',
          'sourceDeviceId': store.deviceId,
          'clientMutationId': '${store.deviceId}_${now.microsecondsSinceEpoch}_system_store_request_snapshot',
        },
        'reason': 'cloud_rebuild_from_host',
        'requestedAt': now.toIso8601String(),
        'storeId': identity.storeId,
        'branchId': identity.branchId,
      },
      storeId: identity.storeId,
      branchId: identity.branchId,
      storeEpoch: identity.storeEpoch,
    );
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/requests/push'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'deviceId': store.deviceId,
              'changes': [request.toJson()],
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return CloudSyncResult(ok: false, message: 'Fresh Host snapshot request failed: ${response.statusCode} ${response.body}');
      }
      return const CloudSyncResult(ok: true, message: 'Fresh Host snapshot requested. The Host will publish a new full snapshot on its next Cloud sync.');
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Fresh Host snapshot request failed: $error');
    }
  }

  Future<CloudSyncResult> rebuildFromCloudHostSnapshot(CloudSyncSettings settings, {CloudSyncProgressCallback? onProgress}) async {
    final identity = store.appIdentity;
    if (identity.isHost) {
      return const CloudSyncResult(ok: false, message: 'Rebuild from Host is only for Client devices.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(ok: false, message: 'Cloud API URL and paired device token are required.');
    }

    onProgress?.call(0.08, 'Requesting a fresh Host snapshot...');
    final snapshotRequestedAt = DateTime.now().toUtc();
    final request = await requestFreshHostSnapshot(settings, requestedAt: snapshotRequestedAt);
    if (!request.ok) return request;

    onProgress?.call(0.18, 'Clearing local Client data...');
    await store.clearLocalDeviceBusinessData();
    await CloudSyncSettings.clearSavedPullCursor();

    var freshSettings = settings.copyWith(clearLastPullCursor: true);
    var totalPulled = 0;
    CloudSyncResult? lastResult;

    // Give the Host a few Cloud sync ticks to consume the rebuild request and
    // publish a fresh restore_snapshot. If the Host is currently offline, the
    // request remains pending in cloud_change_requests and the user can retry
    // when the Host comes online.
    for (var attempt = 0; attempt < 6; attempt += 1) {
      if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 3));
      final attemptProgress = (0.28 + attempt * 0.09).clamp(0.28, 0.73).toDouble();
      onProgress?.call(attemptProgress, 'Waiting for Host snapshot and pulling updates (attempt ${attempt + 1}/6)...');
      lastResult = await syncNow(freshSettings, minSnapshotUpdatedAt: snapshotRequestedAt, onProgress: (value, label) {
        final scaled = attemptProgress + (value * 0.08);
        onProgress?.call(scaled.clamp(0.0, 0.82).toDouble(), label);
      });
      if (!lastResult.ok) break;
      totalPulled += lastResult.pulled;
      freshSettings = CloudSyncSettings.load().copyWith(clearLastPullCursor: attempt == 0 ? true : false);
      if (lastResult.restoredSnapshot) {
        onProgress?.call(0.88, 'Verifying rebuilt local data...');
        final repaired = await store.verifyLocalBusinessDataIntegrity();
        onProgress?.call(0.94, 'Cleaning up local records...');
        await store.cleanupSoftDeletedRecords();
        onProgress?.call(1.0, 'Cloud rebuild completed.');
        return CloudSyncResult(
          ok: repaired.ok,
          pushed: lastResult.pushed,
          pulled: totalPulled,
          restoredSnapshot: true,
          message: repaired.ok
              ? 'Cloud rebuild completed from a requested fresh Host snapshot. ${lastResult.message}'
              : 'Cloud rebuild pulled a fresh Host snapshot, but local verification found problems: ${repaired.message}',
        );
      }
    }

    return CloudSyncResult(
      ok: false,
      pushed: lastResult?.pushed ?? 0,
      pulled: totalPulled,
      message: 'Cloud rebuild requested a fresh Host snapshot, but no snapshot was pulled yet. Keep the Host online and retry. ${lastResult?.message ?? ''}',
    );
  }

  Future<CloudSyncResult> revokeDevice(CloudSyncSettings settings, String deviceId) async {
    final identity = store.appIdentity;
    if (!identity.isHost) return const CloudSyncResult(ok: false, message: 'Only the Host can revoke devices.');
    if (!settings.isConfigured) return const CloudSyncResult(ok: false, message: 'Cloud API URL and token are required.');
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/device-revoke'),
            headers: _headers(settings),
            body: jsonEncode({'storeId': identity.storeId, 'branchId': identity.branchId, 'deviceId': deviceId}),
          )
          .timeout(const Duration(seconds: 10));
      return CloudSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300 ? 'Device revoked.' : 'Device revoke failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Device revoke failed: $error');
    }
  }

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

    // Safety-critical ordering:
    // 1) apply the client drafts locally on the Host,
    // 2) verify the entities now exist in the Host's local database,
    // 3) publish the re-stamped authoritative Host events to Cloud,
    // 4) only then ACK the relay requests as accepted.
    // If any step fails, the relay rows stay pending/failed and will retry.
    await store.applyRemoteSyncChanges(changes, markAppliedAsSynced: true, mirrorToCloud: true);
    await store.assertRemoteSyncChangesApplied(changes);
    await _pushPendingToEndpoint(settings, 'cloud', '/api/sync/push');

    final ackIds = changes.map((item) => item.id).toList();
    final ack = await _client
        .post(
          settings.endpoint('/api/sync/requests/ack'),
          headers: _headers(settings),
          body: jsonEncode({'storeId': identity.storeId, 'branchId': identity.branchId, 'hostDeviceId': store.deviceId, 'ackIds': ackIds}),
        )
        .timeout(const Duration(seconds: 20));
    if (ack.statusCode < 200 || ack.statusCode >= 300) {
      throw StateError('Cloud request ACK failed: ${ack.statusCode} ${ack.body}');
    }
    return changes.length;
  }

  Future<CloudSyncResult> syncNow(CloudSyncSettings settings, {DateTime? minSnapshotUpdatedAt, CloudSyncProgressCallback? onProgress}) async {
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
        onProgress?.call(0.10, 'Preparing Host cloud snapshot queue...');
        await store.ensureHostCloudBootstrapSnapshotQueued();
        onProgress?.call(0.25, 'Sending Host heartbeat...');
        await sendHostHeartbeat(settings);
        onProgress?.call(0.40, 'Registering Host device...');
        await registerCurrentDevice(settings, transport: 'cloud');
        onProgress?.call(0.55, 'Checking Client requests...');
        acceptedRemoteRequests = await _hostPullRemoteRequests(settings);
        onProgress?.call(0.75, 'Uploading authoritative Host changes...');
        pushed += await _pushPendingToEndpoint(settings, 'cloud', '/api/sync/push');
        onProgress?.call(1.0, 'Host cloud sync completed.');
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
        onProgress?.call(0.12, 'Registering Client device...');
        await registerCurrentDevice(settings, transport: 'cloud');
        onProgress?.call(0.28, 'Sending Client requests to Host relay...');
        pushed += await _pushPendingToEndpoint(settings, 'cloud_host', '/api/sync/requests/push');
      }

      final initialCursor = settings.lastPullCursor;
      var pageCursor = '';
      DateTime? finalPullCursor;
      var pageCount = 0;
      var restoredSnapshot = false;
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
        if (initialCursor == null && minSnapshotUpdatedAt != null) {
          query['min_snapshot_updated_at'] = minSnapshotUpdatedAt.toIso8601String();
        }
        if (pageCursor.isNotEmpty) query['cursor'] = pageCursor;

        final pullProgress = (0.35 + (pageCount - 1) * 0.08).clamp(0.35, 0.82).toDouble();
        onProgress?.call(pullProgress, 'Pulling Cloud changes page $pageCount...');
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
        restoredSnapshot = restoredSnapshot || changes.any((item) => item.operation == 'restore_snapshot');
        onProgress?.call((0.42 + (pageCount - 1) * 0.08).clamp(0.42, 0.86).toDouble(), 'Applying ${changes.length} Cloud change(s) from page $pageCount...');
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

      onProgress?.call(0.90, 'Saving Cloud sync cursor...');
      if (finalPullCursor != null) {
        await settings.copyWith(lastPullCursor: finalPullCursor).save();
      }

      if (pulled > 0) {
        onProgress?.call(0.96, 'Cleaning up after Cloud sync...');
        await store.cleanupSoftDeletedRecords();
      }
      onProgress?.call(1.0, 'Cloud sync completed.');
      return CloudSyncResult(
        ok: true,
        pushed: pushed,
        pulled: pulled,
        restoredSnapshot: restoredSnapshot,
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
      var settings = CloudSyncSettings.load();
      if (settings.autoSyncEnabled && settings.isConfigured && store.appIdentity.isCloudEnabled) {
        final hasOutgoingWork = store.pendingSyncQueueForTarget('cloud', readyOnly: false).isNotEmpty ||
            store.pendingSyncQueueForTarget('cloud_host', readyOnly: false).isNotEmpty;
        final cursor = settings.lastPullCursor;
        final staleClient = store.appIdentity.isClient &&
            cursor != null &&
            DateTime.now().toUtc().difference(cursor.toUtc()) > const Duration(days: 7);
        if (staleClient && !hasOutgoingWork) {
          final repair = await CloudSyncService(store).rebuildFromCloudHostSnapshot(settings);
          if (!repair.ok) {
            // Fall back to a cursor reset only if a full repair could not be
            // completed yet, for example when the Host is offline. The pending
            // snapshot request remains in the relay for the Host to process.
            await CloudSyncSettings.clearSavedPullCursor();
            settings = settings.copyWith(clearLastPullCursor: true);
          } else {
            settings = CloudSyncSettings.load();
          }
        }
        await CloudSyncService(store).syncNow(settings);
        _lastCloudQueueCount = store.pendingSyncQueueForTarget('cloud', readyOnly: false).length;
        _lastRelayQueueCount = store.pendingSyncQueueForTarget('cloud_host', readyOnly: false).length;
      }
    } finally {
      _running = false;
    }
  }
}
