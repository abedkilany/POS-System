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
      intervalSeconds: int.tryParse(intervalRaw ?? '')?.clamp(15, 3600).toInt() ?? 30,
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

  Future<CloudSyncResult> syncNow(CloudSyncSettings settings) async {
    final identity = store.appIdentity;
    if (identity.syncMode == SyncMode.localOnly || identity.syncMode == SyncMode.lanOnly) {
      return const CloudSyncResult(ok: false, message: 'Enable cloudConnected or marketplaceEnabled sync mode first.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(ok: false, message: 'Cloud API URL and token are required.');
    }

    final pending = store.pendingSyncChangesForTarget('cloud');
    final pendingIds = pending.map((item) => item.id).toList();

    try {
      if (pending.isNotEmpty) {
        await store.markSyncQueueChangesInProgress(pendingIds);
        final push = await _client
            .post(
              settings.endpoint('/api/sync/push'),
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
          return CloudSyncResult(ok: false, message: message);
        }
        final decoded = jsonDecode(push.body) as Map<String, dynamic>;
        final ackIds = (decoded['ackIds'] as List<dynamic>? ?? []).map((item) => '$item').toList();
        await store.markSyncChangesSyncedByIds(ackIds.isEmpty ? pendingIds : ackIds);
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
        if (pendingIds.isNotEmpty) await store.markSyncQueueChangesFailed(pendingIds, message);
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

      return CloudSyncResult(
        ok: true,
        pushed: pending.length,
        pulled: changes.length,
        message: 'Cloud sync completed. Pushed ${pending.length} change(s), pulled ${changes.length} change(s).',
      );
    } catch (error) {
      if (pendingIds.isNotEmpty) await store.markSyncQueueChangesFailed(pendingIds, error.toString());
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
    if (!kIsWeb || !store.appIdentity.isCloudEnabled) return;
    final settings = CloudSyncSettings.load();
    if (!settings.autoSyncEnabled || !settings.isConfigured) return;
    final interval = Duration(seconds: settings.intervalSeconds.clamp(15, 3600).toInt());
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
