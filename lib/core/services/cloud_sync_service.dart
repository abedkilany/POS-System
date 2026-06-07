import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../data/app_store.dart';
import '../../models/app_identity.dart';
import '../../models/sync_change.dart';
import 'local_database_service.dart';
import 'unified_sync_core_service.dart';
import '../sync_unified/sync_device_state.dart';

class CloudSyncSettings {
  const CloudSyncSettings({
    required this.enabled,
    required this.apiBaseUrl,
    required this.apiToken,
    this.lastPullCursor,
    this.autoSyncEnabled = true,
    this.intervalSeconds = 15,
  });

  static const _apiBaseUrlKey = 'cloud_api_base_url';
  static const _apiTokenKey = 'cloud_api_token';
  static const _lastPullCursorKey = 'cloud_last_pull_cursor';
  static const _enabledKey = 'cloud_sync_enabled';

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

  static String normalizeApiBaseUrl(String value, {String fallback = ''}) {
    var raw = value.trim();
    if (raw.isEmpty) return fallback.trim();
    raw = raw.replaceAll(RegExp(r'/+$'), '');
    if (raw.startsWith('/')) {
      throw const FormatException('Cloud API URL must be a full domain, not a relative path.');
    }
    if (!raw.contains('://')) {
      raw = 'https://$raw';
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.trim().isEmpty) {
      throw const FormatException('Cloud API URL is invalid.');
    }
    return uri.replace(path: uri.path.replaceAll(RegExp(r'/+$'), '')).toString().replaceAll(RegExp(r'/+$'), '');
  }

  Uri endpoint(String path, [Map<String, String>? query]) {
    final base = normalizeApiBaseUrl(apiBaseUrl);
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
    final enabledRaw = LocalDatabaseService.getString(_enabledKey);
    final autoRaw = LocalDatabaseService.getString(_autoSyncKey);
    final intervalRaw = LocalDatabaseService.getString(_intervalKey);
    final currentOrigin = kIsWeb ? Uri.base.origin : '';
    var normalizedBaseUrl = currentOrigin;
    if (base != null && base.trim().isNotEmpty) {
      try {
        normalizedBaseUrl = normalizeApiBaseUrl(base, fallback: currentOrigin);
      } catch (_) {
        normalizedBaseUrl = currentOrigin;
      }
    }
    return CloudSyncSettings(
      enabled: enabledRaw == null ? true : enabledRaw == 'true',
      apiBaseUrl: normalizedBaseUrl,
      apiToken: token,
      lastPullCursor: DateTime.tryParse(cursorRaw),
      autoSyncEnabled: autoRaw == null ? true : autoRaw == 'true',
      intervalSeconds: int.tryParse(intervalRaw ?? '')?.clamp(5, 3600).toInt() ?? 15,
    );
  }

  Future<void> save() async {
    final normalizedBaseUrl = normalizeApiBaseUrl(apiBaseUrl, fallback: kIsWeb ? Uri.base.origin : '');
    await LocalDatabaseService.setString(_apiBaseUrlKey, normalizedBaseUrl);
    await LocalDatabaseService.setString(_apiTokenKey, apiToken.trim());
    await LocalDatabaseService.setString(_enabledKey, enabled ? 'true' : 'false');
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

  bool get isOnline => lastSeenAt != null && DateTime.now().toUtc().difference(lastSeenAt!.toUtc()) <= const Duration(seconds: 90);

  factory CloudDeviceStatus.fromJson(Map<String, dynamic> json) => CloudDeviceStatus(
        deviceId: (json['deviceId'] ?? json['device_id'] ?? '').toString(),
        deviceName: (json['deviceName'] ?? json['device_name'] ?? '').toString(),
        platform: (json['platform'] ?? '').toString(),
        role: (json['role'] ?? '').toString(),
        transport: (json['transport'] ?? '').toString(),
        lastSeenAt: DateTime.tryParse((json['lastSeenAt'] ?? json['last_seen_at'] ?? '').toString()),
        appVersion: (json['appVersion'] ?? json['app_version'] ?? '').toString(),
        hostDeviceId: (json['hostDeviceId'] ?? json['host_device_id'] ?? '').toString(),
        activeTransport: (json['activeTransport'] ?? json['active_transport'] ?? json['transport'] ?? '').toString(),
        lastSyncTransport: (json['lastSyncTransport'] ?? json['last_sync_transport'] ?? '').toString(),
        lastAppliedCursor: DateTime.tryParse((json['lastAppliedCursor'] ?? json['last_applied_cursor'] ?? '').toString()),
        lastAckCursor: DateTime.tryParse((json['lastAckCursor'] ?? json['last_ack_cursor'] ?? '').toString()),
        lastAppliedSequence: int.tryParse((json['lastAppliedSequence'] ?? json['last_applied_sequence'] ?? '').toString()) ?? 0,
        lastAckSequence: int.tryParse((json['lastAckSequence'] ?? json['last_ack_sequence'] ?? '').toString()) ?? 0,
        lastAckAt: DateTime.tryParse((json['lastAckAt'] ?? json['last_ack_at'] ?? '').toString()),
        online: json['online'] == true,
        revoked: json['revoked'] == true,
        suspended: json['suspended'] == true,
        wipePending: json['wipePending'] == true || json['wipe_pending'] == true,
      );
}


class CloudProvisioningStatus {
  const CloudProvisioningStatus._();

  static const _stateKey = 'cloud_initial_provisioning_state_v1';
  static const _messageKey = 'cloud_initial_provisioning_message_v1';
  static const _requestedAtKey = 'cloud_initial_provisioning_requested_at_v1';
  static const _lastAttemptAtKey = 'cloud_initial_provisioning_last_attempt_at_v1';

  static bool get isPending => LocalDatabaseService.getString(_stateKey) == 'pending';

  static String get message => LocalDatabaseService.getString(_messageKey) ?? 'Initial Store data is downloading from the Host.';

  static DateTime? get requestedAt => DateTime.tryParse(LocalDatabaseService.getString(_requestedAtKey) ?? '');

  static DateTime? get lastAttemptAt => DateTime.tryParse(LocalDatabaseService.getString(_lastAttemptAtKey) ?? '');

  static Future<void> markPending({String message = 'Initial Store data is downloading from the Host.', DateTime? requestedAt}) async {
    final now = DateTime.now().toUtc();
    await LocalDatabaseService.setString(_stateKey, 'pending');
    await LocalDatabaseService.setString(_messageKey, message);
    await LocalDatabaseService.setString(_requestedAtKey, (requestedAt ?? now).toIso8601String());
  }

  static Future<void> markAttempted([DateTime? value]) async {
    await LocalDatabaseService.setString(_lastAttemptAtKey, (value ?? DateTime.now().toUtc()).toIso8601String());
  }

  static Future<void> markComplete({String message = 'Initial Store data downloaded.'}) async {
    await LocalDatabaseService.setString(_stateKey, 'complete');
    await LocalDatabaseService.setString(_messageKey, message);
    await LocalDatabaseService.deleteString(_lastAttemptAtKey);
  }

  static Future<void> clear() async {
    await LocalDatabaseService.deleteString(_stateKey);
    await LocalDatabaseService.deleteString(_messageKey);
    await LocalDatabaseService.deleteString(_requestedAtKey);
    await LocalDatabaseService.deleteString(_lastAttemptAtKey);
  }
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
  const CloudPairingClaimResult({required this.ok, required this.message, this.identity, this.initialDataReady = true});
  final bool ok;
  final String message;
  final AppIdentity? identity;

  /// Pairing-code claim can succeed before the first Host snapshot is available.
  /// Keep Connect to Store open until this becomes true so the Client is not
  /// sent to Login without users/store data.
  final bool initialDataReady;
}

class CloudStoreRecoveryResult {
  const CloudStoreRecoveryResult({required this.ok, required this.message, this.identity, this.restoredSnapshot = false, this.pulled = 0});
  final bool ok;
  final String message;
  final AppIdentity? identity;
  final bool restoredSnapshot;
  final int pulled;
}

class CloudSyncService {
  CloudSyncService(this.store, {http.Client? client}) : _client = client ?? http.Client();

  final AppStore store;
  final http.Client _client;
  late final UnifiedSyncCoreService _syncCore = UnifiedSyncCoreService(store);

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
    await SyncDeviceStateStore.recordSyncResult(
      store.appIdentity,
      transport: transport,
      appliedCursor: cursor,
      ackCursor: cursor,
      appliedSequence: sequence,
      ackSequence: sequence,
    );

    // Authoritative ACK: update the Host-visible device state only after the
    // Client has successfully applied the pulled data locally. Pull itself must
    // never be treated as ACK.
    if (settings != null && store.appIdentity.isClient && cursor != null) {
      await registerCurrentDevice(settings, transport: transport);
    }
  }

  Future<CloudPairingCodeResult> createPairingCode(CloudSyncSettings settings, {String transport = 'cloud', int ttlMinutes = 5}) async {
    final identity = store.appIdentity;
    if (!identity.isHost) return const CloudPairingCodeResult(ok: false, message: 'Only the Host can create pairing codes.');
    if (!settings.hasDeploymentToken || settings.apiBaseUrl.trim().isEmpty) return const CloudPairingCodeResult(ok: false, message: 'Cloud API URL and Host deployment token are required.');
    try {
      if (transport == 'cloud') {
        // Cloud pairing is a provisioning transaction: the Host must publish a
        // fresh bootstrap snapshot before issuing a single-use code. Otherwise
        // the code can become Used while the Client still has no users/store
        // data and gets sent back to Connect to Store.
        try {
          await publishBootstrapSnapshotToCloud(settings, force: true);
          await _pushPendingToEndpoint(settings, 'cloud', '/api/sync/push');
        } catch (error) {
          debugPrint('Pairing bootstrap warning: $error');
        }
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
              'recoveryKey': identity.recoveryKey,
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

  Future<CloudPairingStatusResult> pairingCodeStatus(CloudSyncSettings settings, String code) async {
    final identity = store.appIdentity;
    if (!identity.isHost) return const CloudPairingStatusResult(ok: false, status: 'invalid', message: 'Only the Host can check pairing code status.');
    if (!settings.hasDeploymentToken || settings.apiBaseUrl.trim().isEmpty) return const CloudPairingStatusResult(ok: false, status: 'invalid', message: 'Cloud API URL and Host deployment token are required.');
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
        return CloudPairingStatusResult(ok: false, status: 'invalid', message: 'Pairing status failed: ${response.statusCode} ${response.body}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final status = decoded['status']?.toString() ?? 'invalid';
      return CloudPairingStatusResult(
        ok: decoded['ok'] == true,
        status: status,
        message: decoded['ok'] == true ? status : (decoded['error']?.toString() ?? 'Pairing status failed.'),
        expiresAt: DateTime.tryParse(decoded['expiresAt']?.toString() ?? ''),
        claimedAt: DateTime.tryParse(decoded['claimedAt']?.toString() ?? ''),
        claimedByDeviceId: decoded['claimedByDeviceId']?.toString() ?? '',
        claimedByDeviceName: decoded['claimedByDeviceName']?.toString() ?? '',
        claimedDeviceToken: decoded['claimedDeviceToken']?.toString() ?? '',
      );
    } catch (error) {
      return CloudPairingStatusResult(ok: false, status: 'invalid', message: 'Pairing status failed: $error');
    }
  }

  Future<CloudPairingClaimResult> claimPairingCode(CloudSyncSettings settings, String code) async {
    final current = store.appIdentity;
    if (current.isHost) {
      return const CloudPairingClaimResult(ok: false, message: 'Host devices cannot pair as Cloud Clients. Use Transfer Host instead.');
    }
    // A Client may configure both LAN and Cloud, but only one active transport
    // should run at a time. Pairing Cloud is therefore allowed for an existing
    // LAN Client as long as it is not a Host.
    // Client bootstrap pairing intentionally requires only the Cloud API URL and
    // a single-use pairing code. The Host deployment token must stay on Host devices.
    if (!settings.enabled || settings.apiBaseUrl.trim().isEmpty) {
      return const CloudPairingClaimResult(ok: false, message: 'Cloud API URL is required.');
    }
    var deviceRegistered = false;
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
        return const CloudPairingClaimResult(ok: false, message: 'Pairing code expired or already used. Ask the Host device for a new code.');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['ok'] != true) {
        return const CloudPairingClaimResult(ok: false, message: 'Pairing code expired or already used. Ask the Host device for a new code.');
      }
      final claimedStoreId = decoded['storeId']?.toString() ?? current.storeId;
      final claimedBranchId = decoded['branchId']?.toString() ?? current.branchId;
      final claimedHostDeviceId = decoded['hostDeviceId']?.toString() ?? current.hostDeviceId;
      if (current.isClient && current.hostDeviceId.trim().isNotEmpty) {
        final mismatches = <String>[];
        if (current.storeId.trim().toUpperCase() != claimedStoreId.trim().toUpperCase()) mismatches.add('Store ID');
        if (current.branchId.trim().toUpperCase() != claimedBranchId.trim().toUpperCase()) mismatches.add('Branch ID');
        if (current.hostDeviceId.trim().toUpperCase() != claimedHostDeviceId.trim().toUpperCase()) mismatches.add('Host ID');
        if (mismatches.isNotEmpty) {
          return CloudPairingClaimResult(ok: false, message: 'Pairing code belongs to a different Store (${mismatches.join(', ')}). Use the current Host pairing code.');
        }
      }
      final transport = decoded['transport']?.toString() == 'lan' ? SyncMode.lanOnly : SyncMode.cloudConnected;
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
      await store.updateAppIdentityDuringSetup(identity);
      deviceRegistered = true;

      if (identity.syncMode == SyncMode.cloudConnected || identity.syncMode == SyncMode.marketplaceEnabled) {
        // Pairing and provisioning are separate lifecycle steps. A valid pairing
        // code must permanently register this device as a Client even when the
        // Host has not published the initial snapshot yet. The background Cloud
        // sync controller can continue retrying the provisioning/download step
        // after the user returns to Login.
        final requestedAt = DateTime.now().toUtc();
        await CloudProvisioningStatus.markPending(
          requestedAt: requestedAt,
          message: 'Device paired. Initial Store data is being prepared by the Host.',
        );

        // Bootstrap must be treated as a real provisioning step, not only as
        // a successful pairing-code claim. First try to pull the current Cloud
        // materialized snapshot immediately. If the Host has already published
        // its store data, this lets the Client continue without waiting for a
        // new Host sync tick. If no snapshot is available yet, request a fresh
        // Host snapshot and poll a few times while the Host processes the
        // request through the normal Host-authoritative Cloud relay.
        //
        // IMPORTANT: reload settings from disk after updateAppIdentityDuringSetup
        // so that the new deviceToken is visible to isConfigured/hasDeviceCredentials.
        // The `settings` variable captured earlier in this method does not carry
        // the token that the server just issued.
        var appliedInitialData = false;
        var initialPull = await syncNow(CloudSyncSettings.load().copyWith(clearLastPullCursor: true));
        appliedInitialData = initialPull.ok && (initialPull.pulled > 0 || initialPull.restoredSnapshot);

        var request = const CloudSyncResult(ok: true, message: 'Initial pull used existing Cloud snapshot.');
        if (!appliedInitialData) {
          request = await requestFreshHostSnapshot(CloudSyncSettings.load(), requestedAt: requestedAt);
        }

        if (request.ok && !appliedInitialData) {
          // Always load settings fresh from disk inside the retry loop.
          // The first attempt clears the pull cursor so we re-pull the full
          // Host snapshot; subsequent attempts keep whatever cursor the
          // previous pull wrote so we do not re-apply already-seen events.
          for (var attempt = 0; attempt < 6; attempt += 1) {
            if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 3));
            await CloudProvisioningStatus.markAttempted(DateTime.now().toUtc());
            final retrySettings = CloudSyncSettings.load().copyWith(
              clearLastPullCursor: attempt == 0,
            );
            initialPull = await syncNow(retrySettings, minSnapshotUpdatedAt: requestedAt);
            appliedInitialData = initialPull.ok && (initialPull.pulled > 0 || initialPull.restoredSnapshot);
            if (appliedInitialData) break;
          }
        }

        if (appliedInitialData) {
          await CloudProvisioningStatus.markComplete(message: 'Initial Store data downloaded.');
        }
        return CloudPairingClaimResult(
          ok: true,
          message: appliedInitialData
              ? 'Device paired successfully. Initial Store data was downloaded. Please sign in.'
              : 'Device paired successfully, but initial Store data was not downloaded yet. Keep the Host online, run Sync Now on the Host, then tap Retry Download Store Data.',
          identity: identity,
          initialDataReady: appliedInitialData,
        );
      }
      return CloudPairingClaimResult(ok: true, message: 'Device paired successfully. Please sign in.', identity: identity, initialDataReady: true);
    } catch (error) {
      if (deviceRegistered) {
        return CloudPairingClaimResult(
          ok: true,
          message: 'Device paired successfully, but initial Store data was not downloaded yet. Keep the Host online, run Sync Now on the Host, then tap Retry Download Store Data.',
          identity: store.appIdentity,
          initialDataReady: false,
        );
      }
      return const CloudPairingClaimResult(ok: false, message: 'Could not connect this device. Check the pairing code and try again.');
    }
  }

  Future<CloudStoreRecoveryResult> recoverExistingStoreFromCloud(
    CloudSyncSettings settings, {
    required String storeId,
    required String recoveryKey,
    String? branchId,
    CloudSyncProgressCallback? onProgress,
  }) async {
    final cleanStoreId = storeId.trim().toUpperCase();
    final cleanBranchId = (branchId == null || branchId.trim().isEmpty) ? '' : branchId.trim().toUpperCase();
    final cleanRecoveryKey = recoveryKey.trim().toUpperCase();
    if (settings.apiBaseUrl.trim().isEmpty) {
      return const CloudStoreRecoveryResult(ok: false, message: 'Cloud API URL is required.');
    }
    if (!cleanStoreId.startsWith('ST-') || cleanRecoveryKey.isEmpty) {
      return const CloudStoreRecoveryResult(ok: false, message: 'A valid Store ID and Recovery Key are required.');
    }

    try {
      onProgress?.call(0.10, 'Verifying Store ID and Recovery Key...');
      final claimResponse = await _client.post(
        settings.endpoint('/api/sync/recovery/claim'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (settings.apiToken.trim().isNotEmpty) 'Authorization': 'Bearer ${settings.apiToken.trim()}',
        },
        body: jsonEncode({
          'storeId': cleanStoreId,
          'branchId': cleanBranchId,
          'recoveryKey': cleanRecoveryKey,
          'deviceId': store.deviceId,
          'deviceName': store.appIdentity.deviceName,
          'platform': store.appIdentity.platform.name,
          'appVersion': 'store-manager-pro',
        }),
      ).timeout(const Duration(seconds: 15));

      if (claimResponse.statusCode < 200 || claimResponse.statusCode >= 300) {
        return CloudStoreRecoveryResult(ok: false, message: 'Store recovery failed: ${claimResponse.statusCode} ${claimResponse.body}');
      }
      final claim = jsonDecode(claimResponse.body) as Map<String, dynamic>;
      if (claim['ok'] != true) {
        return CloudStoreRecoveryResult(ok: false, message: claim['error']?.toString() ?? 'Store recovery failed.');
      }

      final recoveredBranchId = (claim['branchId'] ?? claim['branch_id'] ?? cleanBranchId).toString().trim().isEmpty ? 'BR-MAIN1' : (claim['branchId'] ?? claim['branch_id'] ?? cleanBranchId).toString().trim().toUpperCase();
      final deviceToken = (claim['deviceToken'] ?? claim['device_token'] ?? '').toString();
      final hostDeviceId = (claim['hostDeviceId'] ?? claim['host_device_id'] ?? store.deviceId).toString();
      final cloudTenantId = (claim['cloudTenantId'] ?? claim['cloud_tenant_id'] ?? '').toString();

      onProgress?.call(0.25, 'Restoring permanent store identity...');
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

      onProgress?.call(0.45, 'Downloading latest Cloud snapshot...');
      var pageCursor = '';
      var pulled = 0;
      var restoredSnapshot = false;
      const maxPages = 200;
      for (var page = 0; page < maxPages; page += 1) {
        final query = <String, String>{
          'store_id': cleanStoreId,
          'branch_id': recoveredBranchId,
          'limit': '1000',
        };
        if (pageCursor.isNotEmpty) query['cursor'] = pageCursor;
        final pull = await _client.get(settings.endpoint('/api/sync/pull', query), headers: _headers(settings)).timeout(const Duration(seconds: 20));
        if (pull.statusCode < 200 || pull.statusCode >= 300) {
          return CloudStoreRecoveryResult(ok: false, message: 'Store identity recovered, but snapshot download failed: ${pull.statusCode} ${pull.body}', identity: store.appIdentity);
        }
        final decodedPull = jsonDecode(pull.body) as Map<String, dynamic>;
        if (decodedPull['needsSnapshot'] == true) {
          await CloudSyncSettings.clearSavedPullCursor();
          return CloudStoreRecoveryResult(
            ok: false,
            message: 'Cloud event log gap detected. Snapshot repair is required.',
            identity: store.appIdentity,
            restoredSnapshot: true,
            pulled: pulled,
          );
        }
        final changes = _syncCore.filterOutLocalEchoes(
          _syncCore.decodeRemoteChanges(decodedPull['changes'] as List<dynamic>?),
        );
        restoredSnapshot = restoredSnapshot || changes.isNotEmpty || decodedPull['source'] == 'entity_snapshots';
        pulled += await _syncCore.applyAuthoritativeChanges(changes);
        onProgress?.call((0.45 + (page + 1) * 0.04).clamp(0.45, 0.88).toDouble(), 'Applied $pulled recovered record(s)...');
        if (decodedPull['hasMore'] != true) {
          final generatedAt = DateTime.tryParse(decodedPull['generatedAt']?.toString() ?? '');
          if (generatedAt != null) await settings.copyWith(lastPullCursor: generatedAt).save();
          break;
        }
        pageCursor = (decodedPull['nextCursor'] ?? '').toString();
        if (pageCursor.isEmpty) {
          return CloudStoreRecoveryResult(ok: false, message: 'Store recovery pagination failed.', identity: store.appIdentity, pulled: pulled);
        }
      }

      onProgress?.call(0.90, 'Publishing recovered Host snapshot...');
      await publishBootstrapSnapshotToCloud(settings, force: true, onProgress: onProgress);
      await _pushPendingToEndpoint(settings, 'cloud', '/api/sync/push');
      await sendHostHeartbeat(settings);
      onProgress?.call(1.0, 'Store recovered.');
      return CloudStoreRecoveryResult(ok: true, message: 'Existing store recovered successfully.', identity: store.appIdentity, restoredSnapshot: restoredSnapshot, pulled: pulled);
    } catch (error) {
      return CloudStoreRecoveryResult(ok: false, message: 'Store recovery failed: $error');
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

    onProgress?.call(0.18, 'Checking for fresh Host snapshot before changing local data...');
    // Do not wipe current Client data until a fresh restore_snapshot is actually
    // received and applied. Failed pairing or unavailable Host data must not
    // erase anything locally.
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
        await CloudProvisioningStatus.markComplete(message: 'Initial Store data downloaded.');
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

  Future<CloudSyncResult?> checkCurrentDeviceAccess(CloudSyncSettings settings) async {
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
        return CloudSyncResult(ok: false, message: 'Cloud device access check failed: ${response.statusCode} ${response.body}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['wipeRequired'] == true || decoded['action'] == 'wipe_local_data') {
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
        await store.factoryResetLocalDevice();
        return const CloudSyncResult(ok: false, message: 'Device deleted by Host. Local data was wiped.');
      }
      if (decoded['suspended'] == true || decoded['authorized'] == false) {
        final reason = decoded['reason']?.toString() ?? 'This device is suspended or not authorized for Cloud sync.';
        if (decoded['suspended'] == true) {
          await store.markSuspendedByHost(reason: reason);
        }
        return CloudSyncResult(ok: false, message: reason);
      }
      await store.clearSuspendedByHost();
      return null;
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Cloud device access check failed: $error');
    }
  }

  Future<CloudSyncResult> setDeviceSuspended(CloudSyncSettings settings, String deviceId, {required bool suspended}) async {
    final identity = store.appIdentity;
    if (!identity.isHost) return const CloudSyncResult(ok: false, message: 'Only the Host can suspend devices.');
    if (!settings.isConfigured) return const CloudSyncResult(ok: false, message: 'Cloud API URL and token are required.');
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/device-suspend'),
            headers: _headers(settings),
            body: jsonEncode({'storeId': identity.storeId, 'branchId': identity.branchId, 'deviceId': deviceId, 'suspended': suspended}),
          )
          .timeout(const Duration(seconds: 10));
      return CloudSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? (suspended ? 'Device suspended in Cloud.' : 'Device resumed in Cloud.')
            : 'Cloud device suspend/resume failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Cloud device suspend/resume failed: $error');
    }
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
              if (settings.apiToken.trim().isNotEmpty) 'Authorization': 'Bearer ${settings.apiToken.trim()}',
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


  Future<CloudSyncResult> registerCurrentDevice(CloudSyncSettings settings, {String transport = 'cloud'}) async {
    final identity = store.appIdentity;
    if (!settings.isConfigured) return const CloudSyncResult(ok: false, message: 'Cloud API URL and token are required.');
    final deviceState = SyncDeviceStateStore.load(identity);
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
              'lastSyncTransport': deviceState.lastSyncTransport.isEmpty ? transport : deviceState.lastSyncTransport,
              'lastAppliedCursor': deviceState.lastAppliedHostCursor?.toIso8601String(),
              'lastAckCursor': deviceState.lastAckCursor?.toIso8601String(),
              'lastAppliedSequence': deviceState.lastAppliedSequence,
              'lastAckSequence': deviceState.lastAckSequence,
              'deviceToken': identity.deviceToken,
              'hostDeviceId': identity.hostDeviceId,
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

  Future<CloudSyncResult> requestHostTransfer(CloudSyncSettings settings, {String reason = ''}) async {
    final identity = store.appIdentity;
    if (!identity.isClient) return const CloudSyncResult(ok: false, message: 'Only Clients can request Host transfer.');
    if (settings.apiBaseUrl.trim().isEmpty) return const CloudSyncResult(ok: false, message: 'Cloud API URL is required.');
    try {
      final response = await _client.post(
        settings.endpoint('/api/sync/host-transfer/request'),
        headers: _headers(settings),
        body: jsonEncode({
          'storeId': identity.storeId,
          'branchId': identity.branchId,
          'requestingDeviceId': store.deviceId,
          'currentHostDeviceId': identity.hostDeviceId,
          'reason': reason,
        }),
      ).timeout(const Duration(seconds: 10));
      return CloudSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300 ? 'Host transfer request sent.' : 'Host transfer request failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Host transfer request failed: $error');
    }
  }

  Future<CloudSyncResult> approveHostTransfer(CloudSyncSettings settings, String requestingDeviceId) async {
    final identity = store.appIdentity;
    if (!identity.isHost) return const CloudSyncResult(ok: false, message: 'Only Hosts can approve Host transfer.');
    if (!settings.isConfigured) return const CloudSyncResult(ok: false, message: 'Cloud API URL and token are required.');
    try {
      final response = await _client.post(
        settings.endpoint('/api/sync/host-transfer/approve'),
        headers: _headers(settings),
        body: jsonEncode({
          'storeId': identity.storeId,
          'branchId': identity.branchId,
          'requestingDeviceId': requestingDeviceId,
          'approvedByHostDeviceId': store.deviceId,
        }),
      ).timeout(const Duration(seconds: 10));
      return CloudSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300 ? 'Host transfer approved in Cloud.' : 'Host transfer approval failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Host transfer approval failed: $error');
    }
  }

  Future<CloudSyncResult> activateHostTransfer(CloudSyncSettings settings) async {
    final identity = store.appIdentity;
    if (!settings.isConfigured && settings.apiBaseUrl.trim().isEmpty) return const CloudSyncResult(ok: false, message: 'Cloud API URL is required.');
    try {
      final response = await _client.post(
        settings.endpoint('/api/sync/host-transfer/activate'),
        headers: _headers(settings),
        body: jsonEncode({
          'storeId': identity.storeId,
          'branchId': identity.branchId,
          'newHostDeviceId': store.deviceId,
        }),
      ).timeout(const Duration(seconds: 10));
      return CloudSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300 ? 'Host transfer activated in Cloud.' : 'Host transfer activation failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Host transfer activation failed: $error');
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

  Future<CloudSyncResult> repairLegacyCloudDeviceLinks(
    CloudSyncSettings settings, {
    required Iterable<String> clientDeviceIds,
  }) async {
    final identity = store.appIdentity;
    if (!identity.isHost) return const CloudSyncResult(ok: false, message: 'Only the Host can repair Cloud device links.');
    if (!settings.isConfigured) return const CloudSyncResult(ok: false, message: 'Cloud API URL and token are required.');
    final cleanClientIds = clientDeviceIds.map((id) => id.trim()).where((id) => id.isNotEmpty && id != store.deviceId).toSet().toList();
    if (cleanClientIds.isEmpty) return const CloudSyncResult(ok: true, message: 'No legacy Cloud device links need repair.');
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
        return CloudSyncResult(ok: false, message: 'Cloud device link repair failed: ${response.statusCode} ${response.body}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final repaired = int.tryParse('${decoded['repaired'] ?? 0}') ?? 0;
      final checked = int.tryParse('${decoded['checked'] ?? cleanClientIds.length}') ?? cleanClientIds.length;
      return CloudSyncResult(ok: decoded['ok'] == true, message: 'Cloud device links checked: $checked, repaired: $repaired.');
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Cloud device link repair failed: $error');
    }
  }

  Future<CloudSyncResult> testConnection(CloudSyncSettings settings) async {
    if (!settings.isConfigured) {
      return const CloudSyncResult(ok: false, message: 'Cloud API URL and token are required.');
    }
    final accessResult = await checkCurrentDeviceAccess(settings);
    if (accessResult != null) return accessResult;

    try {
      final health = await _client.get(settings.endpoint('/api/health'), headers: _headers(settings)).timeout(const Duration(seconds: 10));
      if (health.statusCode < 200 || health.statusCode >= 300) {
        final authMessage = health.statusCode == 401 || health.statusCode == 403
            ? 'Unauthorized/Token invalid: Cloud API rejected the token.'
            : 'Cloud Server Unreachable: Cloud API returned ${health.statusCode}: ${health.body}';
        return CloudSyncResult(ok: false, message: authMessage);
      }
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Cloud Server Unreachable: $error');
    }

    final identity = store.appIdentity;
    if (!identity.isClient) {
      return const CloudSyncResult(ok: true, message: 'Cloud API connection is healthy.');
    }

    if (identity.deviceToken.trim().isEmpty) {
      return const CloudSyncResult(ok: false, message: 'Unauthorized/Token invalid: this Client has no saved device token. Pair this device again.');
    }

    try {
      final hostStatus = await getHostHeartbeatStatus(settings);
      if (!hostStatus.cloudReachable) {
        final lower = hostStatus.message.toLowerCase();
        final message = lower.contains('401') || lower.contains('403') || lower.contains('unauthorized') || lower.contains('token')
            ? 'Unauthorized/Token invalid: ${hostStatus.message}'
            : 'Cloud Server Unreachable: ${hostStatus.message}';
        return CloudSyncResult(ok: false, message: message);
      }
      if (!hostStatus.hostReachable) {
        return CloudSyncResult(ok: false, message: 'Host Offline: ${hostStatus.message}');
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

      final ping = await _client.get(settings.endpoint('/api/sync/pull', query), headers: _headers(settings)).timeout(const Duration(seconds: 10));
      if (ping.statusCode < 200 || ping.statusCode >= 300) {
        final message = ping.statusCode == 401 || ping.statusCode == 403
            ? 'Unauthorized/Token invalid: Cloud sync rejected this device. Pair this device again.'
            : 'Sync Not Ready: Cloud sync ping failed with ${ping.statusCode}: ${ping.body}';
        return CloudSyncResult(ok: false, message: message);
      }

      return const CloudSyncResult(ok: true, message: 'Cloud Connected/Ready for Sync.');
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Sync Not Ready: $error');
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
              'recoveryKey': identity.recoveryKey,
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

  Future<Map<String, dynamic>?> runCloudMaintenance(CloudSyncSettings settings, {int keepRecentEvents = 200}) async {
    final identity = store.appIdentity;
    if (!identity.isHost || !identity.isCloudEnabled || !settings.isConfigured) return null;
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
              'keepRecentEvents': keepRecentEvents,
              'activeDeviceDays': 14,
              'processedRequestRetentionDays': 3,
              'deletedSnapshotRetentionDays': 7,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('Cloud maintenance failed: ${response.statusCode} ${response.body}');
        return null;
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (error) {
      debugPrint('Cloud maintenance failed: $error');
      return null;
    }
  }


  Future<int> publishBootstrapSnapshotToCloud(
    CloudSyncSettings settings, {
    bool force = false,
    void Function(double value, String label)? onProgress,
  }) async {
    final identity = store.appIdentity;
    if (!identity.isHost || !identity.isCloudEnabled || !settings.hasDeploymentToken) return 0;
    await store.removeLegacyCloudBootstrapSnapshotQueue();
    final chunks = store.exportCloudBootstrapSnapshotChunks(maxItemsPerChunk: 50);
    if (chunks.isEmpty) return 0;

    for (var i = 0; i < chunks.length; i += 1) {
      final chunk = Map<String, dynamic>.from(chunks[i]);
      chunk['force'] = force && i == 0;
      final response = await _client
          .post(
            settings.endpoint('/api/sync/bootstrap-snapshot'),
            headers: _headers(settings),
            body: jsonEncode(chunk),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 409) {
        if (!force) {
          throw StateError('Another Cloud bootstrap snapshot is already in progress. Try again after it finishes or use force rebuild.');
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Cloud bootstrap snapshot failed: ${response.statusCode} ${response.body}');
      }
      onProgress?.call((0.10 + ((i + 1) / chunks.length) * 0.70).clamp(0.10, 0.80).toDouble(), 'Publishing snapshot chunk ${i + 1}/${chunks.length}...');
    }
    return chunks.length;
  }


  Future<int> _pushPendingToEndpoint(CloudSyncSettings settings, String target, String path) async {
    final identity = store.appIdentity;
    var totalPushed = 0;
    var batchNumber = 0;

    // Safety-critical fix for large Host -> Cloud publishes:
    // Do not upload tens of thousands of changes in one HTTP request. A single
    // timeout could leave the Host appearing idle while Cloud clients are still
    // missing data. Push in small acknowledged batches and mark only the batch
    // currently being sent as in-progress.
    const batchSize = 20;

    while (true) {
      await store.recoverStaleInProgressSyncQueue(target: target);
      await store.retryFailedSyncQueue(target: target);
      final pending = _syncCore.pendingChangesForTarget(target).take(batchSize).toList(growable: false);
      final pendingIds = _syncCore.changeIds(pending);
      if (pending.isEmpty) break;
      batchNumber += 1;

      await _syncCore.markPushInProgress(pendingIds);
      try {
        final push = await _client
            .post(
              settings.endpoint(path),
              headers: _headers(settings),
              body: jsonEncode({
                'deviceId': store.deviceId,
                'storeId': identity.storeId,
                'branchId': identity.branchId,
                'sequence': SyncDeviceStateStore.load(identity).lastAppliedSequence,
                'lastAppliedSequence': SyncDeviceStateStore.load(identity).lastAppliedSequence,
                'batchNumber': batchNumber,
                'batchSize': pending.length,
                'changes': pending.map((item) => item.toJson()).toList(),
              }),
            )
            .timeout(const Duration(seconds: 30));
        if (push.statusCode < 200 || push.statusCode >= 300) {
          final message = 'Cloud push failed on batch $batchNumber: ${push.statusCode} ${push.body}';
          await _syncCore.markPushFailed(pendingIds, message);
          throw StateError(message);
        }
        final decoded = jsonDecode(push.body) as Map<String, dynamic>;
        final ackIds = (decoded['ackIds'] as List<dynamic>? ?? []).map((item) => '$item').toList();
        final rejected = _decodeRejectedSyncRequests(decoded['rejected']);
        if (rejected.isNotEmpty) await _syncCore.markPushRejected(rejected);
        if (target == 'cloud_host') {
          // Relay ACK only means the draft reached the Cloud inbox. It is not a
          // Host confirmation and must not turn the local draft into confirmed data.
          await _syncCore.markPushSubmitted(ackIds, fallbackIds: pendingIds);
        } else {
          await _syncCore.markPushAcknowledged(ackIds, fallbackIds: pendingIds);
        }
        totalPushed += pending.length;
      } catch (error) {
        // Keep the affected batch retryable. Already acknowledged previous
        // batches remain synced; unsent later batches were never touched.
        await _syncCore.markPushFailed(pendingIds, 'Cloud push failed on batch $batchNumber: $error');
        rethrow;
      }
    }

    return totalPushed;
  }



  Map<String, String> _decodeRejectedSyncRequests(dynamic raw) {
    final output = <String, String>{};
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final id = (item['id'] ?? '').toString();
          if (id.isNotEmpty) output[id] = (item['reason'] ?? 'Rejected by Host.').toString();
        }
      }
    }
    return output;
  }

  Future<void> _pollSubmittedClientRequests(CloudSyncSettings settings) async {
    final identity = store.appIdentity;
    if (!identity.isClient) return;
    final submitted = _syncCore.submittedChangesForTarget('cloud_host');
    if (submitted.isEmpty) return;
    final requestIds = submitted.map((item) => item.id).toList();
    final response = await _client
        .post(
          settings.endpoint('/api/sync/requests/status'),
          headers: _headers(settings),
          body: jsonEncode({
            'deviceId': store.deviceId,
            'storeId': identity.storeId,
            'branchId': identity.branchId,
            'requestIds': requestIds,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) return;
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final acceptedRaw = decoded['acceptedIds'] ?? decoded['accepted_ids'];
    final acceptedIds = (acceptedRaw is List ? acceptedRaw : const <dynamic>[])
        .map((item) => '$item')
        .where((item) => item.trim().isNotEmpty)
        .toList();
    final rejected = _decodeRejectedSyncRequests(decoded['rejected']);

    // A relay ACK only means the Cloud server received the request. The final
    // decision comes later from the Host. Once the Host reports accepted, mark
    // the draft as acknowledged so the Client no longer counts it as pending.
    if (acceptedIds.isNotEmpty) await _syncCore.markPushAcknowledged(acceptedIds);

    // Rejected drafts must not remain as normal local data. AppStore will mark
    // the queue row as rejected and quarantine local creates that the Host did
    // not accept, e.g. duplicate product code/barcode.
    if (rejected.isNotEmpty) await _syncCore.markPushRejected(rejected);
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
    final changes = _syncCore.filterOutLocalEchoes(
      _syncCore.decodeRemoteChanges(decoded['changes'] as List<dynamic>?),
    );
    if (changes.isEmpty) return 0;

    // Accept Client drafts on the Host first. Once local Host persistence is
    // verified, ACK the relay request immediately; the Client must not stay
    // pending just because the Host -> Cloud publish later times out.
    final accepted = await _syncCore.acceptClientChangesOnHost(
      changes,
      mirrorToCloud: true,
      verifyApplied: true,
    );

    final ackIds = accepted.ackIds;
    final ack = await _client
        .post(
          settings.endpoint('/api/sync/requests/ack'),
          headers: _headers(settings),
          body: jsonEncode({
            'storeId': identity.storeId,
            'branchId': identity.branchId,
            'hostDeviceId': store.deviceId,
            'ackIds': ackIds,
            'rejected': accepted.rejected.entries.map((entry) => {'id': entry.key, 'reason': entry.value}).toList(),
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (ack.statusCode < 200 || ack.statusCode >= 300) {
      throw StateError('Cloud request ACK failed: ${ack.statusCode} ${ack.body}');
    }

    // Publish the newly authoritative Host events after ACK. If this upload
    // fails, the Host keeps those cloud queue rows retryable without trapping
    // the already-accepted Client request in submitted/pending state.
    await _pushPendingToEndpoint(settings, 'cloud', '/api/sync/push');
    return changes.length;
  }


  Future<CloudSyncResult> pushPendingForUnifiedEngine(CloudSyncSettings settings, {CloudSyncProgressCallback? onProgress}) async {
    final identity = store.appIdentity;
    if (!_cloudAllowedForIdentity(identity)) {
      return const CloudSyncResult(ok: false, message: 'Cloud is not the active/configured sync transport for this device.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(ok: false, message: 'Cloud API URL and token are required.');
    }

    try {
      var pushed = 0;
      var acceptedRemoteRequests = 0;

      if (identity.isHost) {
        onProgress?.call(0.10, 'Preparing Host cloud snapshot queue...');
        await store.ensureHostCloudBootstrapSnapshotQueued();
        final repairedCloudQueue = await store.repairMissingHostCloudQueueForPendingChanges();
        if (repairedCloudQueue > 0) {
          onProgress?.call(0.18, 'Repaired $repairedCloudQueue missing Host cloud queue item(s)...');
        }
        onProgress?.call(0.25, 'Sending Host heartbeat...');
        await sendHostHeartbeat(settings);
        onProgress?.call(0.40, 'Registering Host device...');
        await registerCurrentDevice(settings, transport: 'cloud');
        onProgress?.call(0.55, 'Checking Client requests...');
        acceptedRemoteRequests = await _hostPullRemoteRequests(settings);
        onProgress?.call(0.75, 'Uploading authoritative Host changes...');
        await store.repairMissingHostCloudQueueForPendingChanges();
        pushed += await _pushPendingToEndpoint(settings, 'cloud', '/api/sync/push');
        await runCloudMaintenance(settings);
        return CloudSyncResult(
          ok: true,
          pushed: pushed,
          message: 'Host cloud push completed. Accepted $acceptedRemoteRequests remote request(s), pushed $pushed authoritative change(s).',
        );
      }

      onProgress?.call(0.12, 'Registering Client device...');
      await registerCurrentDevice(settings, transport: 'cloud');
      onProgress?.call(0.22, 'Checking submitted Client requests...');
      await _pollSubmittedClientRequests(settings);
      onProgress?.call(0.28, 'Sending Client requests to Host relay...');
      pushed += await _pushPendingToEndpoint(settings, 'cloud_host', '/api/sync/requests/push');
      return CloudSyncResult(ok: true, pushed: pushed, message: 'Client cloud push completed. Sent $pushed request(s) to Host relay.');
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Cloud push failed: $error');
    }
  }

  Future<CloudSyncResult> pullAuthoritativeChangesForUnifiedEngine(
    CloudSyncSettings settings, {
    DateTime? minSnapshotUpdatedAt,
    CloudSyncProgressCallback? onProgress,
  }) async {
    final identity = store.appIdentity;
    if (identity.isHost) {
      return const CloudSyncResult(ok: true, message: 'Host devices do not pull authoritative Cloud changes.', pulled: 0);
    }
    if (!_cloudAllowedForIdentity(identity)) {
      return const CloudSyncResult(ok: false, message: 'Cloud is not the active/configured sync transport for this device.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(ok: false, message: 'Cloud API URL and token are required.');
    }

    try {
      await _pollSubmittedClientRequests(settings);
      var pulled = 0;
      final initialCursor = settings.lastPullCursor;
      // Freeze the sequence watermark for the whole paginated pull. Reading
      // lastAppliedSequence after every page can skip pages: page 1 advances the
      // local state, then page 2 asks Cloud for sequence > the new value while
      // also passing the old page cursor. That combination can silently miss
      // events, which showed up as product count differences across devices.
      final baseLastAppliedSequence = SyncDeviceStateStore.load(store.appIdentity).lastAppliedSequence;
      var pageCursor = '';
      DateTime? finalPullCursor;
      var finalPullSequence = 0;
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
        if (baseLastAppliedSequence > 0) query['since_sequence'] = baseLastAppliedSequence.toString();
        if (initialCursor != null) query['since'] = initialCursor.toIso8601String();
        if (initialCursor == null && minSnapshotUpdatedAt != null) {
          query['min_snapshot_updated_at'] = minSnapshotUpdatedAt.toIso8601String();
        }
        if (pageCursor.isNotEmpty) query['cursor'] = pageCursor;

        final pullProgress = (0.35 + (pageCount - 1) * 0.08).clamp(0.35, 0.82).toDouble();
        onProgress?.call(pullProgress, 'Pulling Cloud changes page $pageCount...');
        final pull = await _client.get(settings.endpoint('/api/sync/pull', query), headers: _headers(settings)).timeout(const Duration(seconds: 20));
        if (pull.statusCode < 200 || pull.statusCode >= 300) {
          return CloudSyncResult(ok: false, message: 'Cloud pull failed: ${pull.statusCode} ${pull.body}');
        }

        final decodedPull = jsonDecode(pull.body) as Map<String, dynamic>;
        if (decodedPull['needsSnapshot'] == true) {
          await CloudSyncSettings.clearSavedPullCursor();
          return CloudSyncResult(
            ok: false,
            message: 'Cloud event log gap detected. Snapshot repair is required.',
            restoredSnapshot: true,
            pulled: pulled,
          );
        }
        final changes = _syncCore.filterOutLocalEchoes(
          _syncCore.decodeRemoteChanges(decodedPull['changes'] as List<dynamic>?),
        );
        final source = (decodedPull['source'] ?? '').toString();
        restoredSnapshot = restoredSnapshot ||
            changes.any((item) => item.operation == 'restore_snapshot') ||
            (initialCursor == null && source == 'entity_snapshots' && changes.isNotEmpty);
        onProgress?.call((0.42 + (pageCount - 1) * 0.08).clamp(0.42, 0.86).toDouble(), 'Applying ${changes.length} Cloud change(s) from page $pageCount...');
        pulled += await _syncCore.applyAuthoritativeChanges(changes);

        final hasMore = decodedPull['hasMore'] == true;
        pageCursor = (decodedPull['nextCursor'] ?? '').toString();
        if (!hasMore) {
          finalPullCursor = DateTime.tryParse(decodedPull['generatedAt']?.toString() ?? '');
          finalPullSequence = int.tryParse(decodedPull['generatedSequence']?.toString() ?? '') ?? finalPullSequence;
          break;
        }
        if (pageCursor.isEmpty) {
          return const CloudSyncResult(ok: false, message: 'Cloud pull pagination failed: missing next cursor.');
        }
      }

      onProgress?.call(0.90, 'Saving Cloud sync cursor...');
      if (finalPullCursor != null) {
        await settings.copyWith(lastPullCursor: finalPullCursor).save();
        await _recordDeviceSyncState('cloud', finalPullCursor, sequence: finalPullSequence, settings: settings);
      }

      if (pulled > 0) {
        onProgress?.call(0.96, 'Cleaning up after Cloud sync...');
        await store.cleanupSoftDeletedRecords();
      }
      if (store.appIdentity.isClient && (restoredSnapshot || pulled > 0)) {
        await CloudProvisioningStatus.markComplete(message: 'Initial Store data downloaded.');
      }
      return CloudSyncResult(
        ok: true,
        pulled: pulled,
        restoredSnapshot: restoredSnapshot,
        message: 'Cloud pull completed. Pulled $pulled authoritative change(s).',
      );
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'Cloud pull failed: $error');
    }
  }

  Future<CloudSyncResult> syncNow(CloudSyncSettings settings, {DateTime? minSnapshotUpdatedAt, CloudSyncProgressCallback? onProgress}) async {
    final identity = store.appIdentity;
    if (!_cloudAllowedForIdentity(identity)) {
      return const CloudSyncResult(ok: false, message: 'Cloud is not the active/configured sync transport for this device.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(ok: false, message: 'Cloud API URL and token are required.');
    }
    final accessResult = await checkCurrentDeviceAccess(settings);
    if (accessResult != null) return accessResult;

    try {
      var pushed = 0;
      var pulled = 0;
      var acceptedRemoteRequests = 0;

      if (identity.isHost) {
        onProgress?.call(0.10, 'Preparing Host cloud snapshot queue...');
        await store.ensureHostCloudBootstrapSnapshotQueued();
        final repairedCloudQueue = await store.repairMissingHostCloudQueueForPendingChanges();
        if (repairedCloudQueue > 0) {
          onProgress?.call(0.18, 'Repaired $repairedCloudQueue missing Host cloud queue item(s)...');
        }
        onProgress?.call(0.25, 'Sending Host heartbeat...');
        await sendHostHeartbeat(settings);
        onProgress?.call(0.40, 'Registering Host device...');
        await registerCurrentDevice(settings, transport: 'cloud');
        onProgress?.call(0.55, 'Checking Client requests...');
        acceptedRemoteRequests = await _hostPullRemoteRequests(settings);
        onProgress?.call(0.75, 'Uploading authoritative Host changes...');
        await store.repairMissingHostCloudQueueForPendingChanges();
        pushed += await _pushPendingToEndpoint(settings, 'cloud', '/api/sync/push');
        onProgress?.call(0.90, 'Running safe local sync log maintenance...');
        await store.compactSyncedSyncHistoryForMaintenance();
        onProgress?.call(0.96, 'Running safe Cloud maintenance...');
        await runCloudMaintenance(settings);
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
      // Freeze the sequence watermark for the whole paginated pull. Reading
      // lastAppliedSequence after every page can skip pages: page 1 advances the
      // local state, then page 2 asks Cloud for sequence > the new value while
      // also passing the old page cursor. That combination can silently miss
      // events, which showed up as product count differences across devices.
      final baseLastAppliedSequence = SyncDeviceStateStore.load(store.appIdentity).lastAppliedSequence;
      var pageCursor = '';
      DateTime? finalPullCursor;
      var finalPullSequence = 0;
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
        if (baseLastAppliedSequence > 0) query['since_sequence'] = baseLastAppliedSequence.toString();
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
        if (decodedPull['needsSnapshot'] == true) {
          await CloudSyncSettings.clearSavedPullCursor();
          return CloudSyncResult(
            ok: false,
            message: 'Cloud event log gap detected. Snapshot repair is required.',
            restoredSnapshot: true,
            pulled: pulled,
          );
        }
        final changes = _syncCore.filterOutLocalEchoes(
          _syncCore.decodeRemoteChanges(decodedPull['changes'] as List<dynamic>?),
        );
        final source = (decodedPull['source'] ?? '').toString();
        restoredSnapshot = restoredSnapshot ||
            changes.any((item) => item.operation == 'restore_snapshot') ||
            (initialCursor == null && source == 'entity_snapshots' && changes.isNotEmpty);
        onProgress?.call((0.42 + (pageCount - 1) * 0.08).clamp(0.42, 0.86).toDouble(), 'Applying ${changes.length} Cloud change(s) from page $pageCount...');
        pulled += await _syncCore.applyAuthoritativeChanges(changes);

        final hasMore = decodedPull['hasMore'] == true;
        pageCursor = (decodedPull['nextCursor'] ?? '').toString();
        if (!hasMore) {
          finalPullCursor = DateTime.tryParse(decodedPull['generatedAt']?.toString() ?? '');
          finalPullSequence = int.tryParse(decodedPull['generatedSequence']?.toString() ?? '') ?? finalPullSequence;
          break;
        }
        if (pageCursor.isEmpty) {
          return const CloudSyncResult(ok: false, message: 'Cloud pull pagination failed: missing next cursor.');
        }
      }

      onProgress?.call(0.90, 'Saving Cloud sync cursor...');
      if (finalPullCursor != null) {
        await settings.copyWith(lastPullCursor: finalPullCursor).save();
        await _recordDeviceSyncState('cloud', finalPullCursor, sequence: finalPullSequence, settings: settings);
      }

      if (pulled > 0) {
        onProgress?.call(0.94, 'Cleaning up after Cloud sync...');
        await store.cleanupSoftDeletedRecords();
      }
      if (store.appIdentity.isClient) {
        onProgress?.call(0.97, 'Running Client sync log maintenance...');
        await store.compactClientSyncedSyncHistoryForMaintenance();
      }
      if (store.appIdentity.isClient && (restoredSnapshot || pulled > 0)) {
        await CloudProvisioningStatus.markComplete(message: 'Initial Store data downloaded.');
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
