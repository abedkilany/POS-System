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
    this.intervalSeconds = 10,
  });

  static const _apiBaseUrlKey = 'cloud_api_base_url';
  static const _apiTokenKey = 'cloud_api_token';
  static const _lastPullCursorKey = 'cloud_last_pull_cursor';
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
      intervalSeconds: int.tryParse(intervalRaw ?? '')?.clamp(5, 3600).toInt() ?? 10,
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

  Map<String, String> _headers(CloudSyncSettings settings) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (settings.apiToken.trim().isNotEmpty) 'Authorization': 'Bearer ${settings.apiToken.trim()}',
      };

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
          body: jsonEncode({'storeId': identity.storeId, 'hostDeviceId': store.deviceId, 'ackIds': ackIds}),
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
        acceptedRemoteRequests = await _hostPullRemoteRequests(settings);
        pushed += await _pushPendingToEndpoint(settings, 'cloud', '/api/sync/push');
        return CloudSyncResult(
          ok: true,
          pushed: pushed,
          pulled: 0,
          message: 'Host cloud sync completed. Accepted $acceptedRemoteRequests remote request(s), pushed $pushed authoritative change(s).',
        );
      } else if (identity.platform == AppPlatformType.web) {
        pushed += await _pushPendingToEndpoint(settings, 'cloud_host', '/api/sync/requests/push');
      } else {
        // A non-host desktop/mobile client should talk to the Host over LAN.
        // Keep Cloud read-only for it to avoid multiple sources of truth.
      }

      final query = <String, String>{
        'store_id': identity.storeId,
        'branch_id': identity.branchId,
      };
      final cursor = settings.lastPullCursor;
      if (cursor != null) query['since'] = cursor.toIso8601String();
      final pull = await _client.get(settings.endpoint('/api/sync/pull', query), headers: _headers(settings)).timeout(const Duration(seconds: 20));
      if (pull.statusCode < 200 || pull.statusCode >= 300) {
        final message = 'Cloud pull failed: ${pull.statusCode} ${pull.body}';
        return CloudSyncResult(ok: false, message: message);
      }

      final decodedPull = jsonDecode(pull.body) as Map<String, dynamic>;
      final generatedAt = DateTime.tryParse(decodedPull['generatedAt']?.toString() ?? '') ?? DateTime.now();
      final changes = (decodedPull['changes'] as List<dynamic>? ?? [])
          .map((item) => SyncChange.fromJson(Map<String, dynamic>.from(item as Map)))
          .where((item) => item.deviceId != store.deviceId)
          .toList();
      await store.applyRemoteSyncChanges(changes, markAppliedAsSynced: true);
      await settings.copyWith(lastPullCursor: generatedAt).save();
      pulled += changes.length;

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
  bool _running = false;

  Future<void> start() async {
    stop();
    if (!store.appIdentity.isCloudEnabled) return;
    final settings = CloudSyncSettings.load();
    if (!settings.autoSyncEnabled || !settings.isConfigured) return;
    final interval = Duration(seconds: settings.intervalSeconds.clamp(5, 3600).toInt());
    _timer = Timer.periodic(interval, (_) => _tick());
    await _tick();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_running) return;
    _running = true;
    try {
      final settings = CloudSyncSettings.load();
      if (settings.autoSyncEnabled && settings.isConfigured && store.appIdentity.isCloudEnabled) {
        await CloudSyncService(store).syncNow(settings);
      }
    } finally {
      _running = false;
    }
  }
}
