import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/app_store.dart';
import '../../models/app_identity.dart';
import '../../models/sync_change.dart';

class CloudSyncSettings {
  const CloudSyncSettings({
    required this.enabled,
    required this.apiBaseUrl,
    required this.apiToken,
    this.lastPullCursor,
  });

  final bool enabled;
  final String apiBaseUrl;
  final String apiToken;
  final DateTime? lastPullCursor;

  bool get isConfigured => enabled && apiBaseUrl.trim().isNotEmpty;

  Uri endpoint(String path, [Map<String, String>? query]) {
    final base = apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$base$normalizedPath');
    return query == null ? uri : uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }
}

class CloudSyncResult {
  const CloudSyncResult({required this.ok, required this.message, this.pushed = 0, this.pulled = 0});
  final bool ok;
  final String message;
  final int pushed;
  final int pulled;
}

/// Production-facing cloud sync client.
///
/// Expected Vercel API contract:
/// - GET  /api/health
/// - POST /api/sync/push  -> { ok, ackIds, serverTime }
/// - GET  /api/sync/pull?since=ISO_DATE -> { ok, changes, generatedAt }
///
/// The API must authenticate the bearer token, verify store membership, and write
/// to Neon/PostgreSQL. This service deliberately does not connect Flutter
/// directly to Neon; Flutter talks only to HTTPS API routes.
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
      return const CloudSyncResult(ok: false, message: 'Cloud API settings are not configured.');
    }
    try {
      final response = await _client
          .get(settings.endpoint('/api/health'), headers: _headers(settings))
          .timeout(const Duration(seconds: 10));
      return CloudSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? 'Cloud API connection is healthy.'
            : 'Cloud API returned ${response.statusCode}: ${response.body}',
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
      return const CloudSyncResult(ok: false, message: 'Cloud API settings are not configured yet.');
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
      final pull = await _client
          .get(settings.endpoint('/api/sync/pull', query.isEmpty ? null : query), headers: _headers(settings))
          .timeout(const Duration(seconds: 20));
      if (pull.statusCode < 200 || pull.statusCode >= 300) {
        final message = 'Cloud pull failed: ${pull.statusCode} ${pull.body}';
        if (pendingIds.isNotEmpty) await store.markSyncQueueChangesFailed(pendingIds, message);
        return CloudSyncResult(ok: false, message: message);
      }

      final decodedPull = jsonDecode(pull.body) as Map<String, dynamic>;
      final changes = (decodedPull['changes'] as List<dynamic>? ?? [])
          .map((item) => SyncChange.fromJson(Map<String, dynamic>.from(item as Map)))
          .where((item) => item.deviceId != store.deviceId)
          .toList();
      await store.applyRemoteSyncChanges(changes, markAppliedAsSynced: true);

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
