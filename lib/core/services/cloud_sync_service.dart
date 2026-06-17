import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_brand.dart';
import '../../data/app_store.dart';
import '../../models/app_identity.dart';
import '../../models/sync_change.dart';
import 'local_database_service.dart';
import 'unified_sync_core_service.dart';
import '../sync_unified/sync_device_state.dart';
import '../snapshot/unified_snapshot_transfer.dart';

const bool _temporarySyncDiagnostics = true;

void _syncDiag(String message) {
  if (_temporarySyncDiagnostics) {
    debugPrint('[SYNC_DIAG] $message');
  }
}

String _identityRoleLabel(AppIdentity identity) {
  if (identity.isHost) return 'host';
  if (identity.isClient) return 'client';
  return 'unknown';
}

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
  // Temporary diagnostic interval while investigating Cloud host/client lag.
  static const int defaultIntervalSeconds = 5;

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
          'يجب أن يكون رابط واجهة السحابة نطاقاً كاملاً وليس مساراً نسبياً.');
    }
    if (!raw.contains('://')) {
      raw = 'https://$raw';
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.trim().isEmpty) {
      throw const FormatException('رابط واجهة السحابة غير صالح.');
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
      intervalSeconds: defaultIntervalSeconds,
    );
  }

  Future<void> save() async {
    final normalizedBaseUrl = normalizeApiBaseUrl(apiBaseUrl,
        fallback: kIsWeb ? Uri.base.origin : '');
    await LocalDatabaseService.setString(_apiBaseUrlKey, normalizedBaseUrl);
    await LocalDatabaseService.setString(
        _autoSyncKey, autoSyncEnabled ? 'true' : 'false');
    await LocalDatabaseService.setString(
        _intervalKey, defaultIntervalSeconds.toString());
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
      'يتم تنزيل بيانات المتجر الأولية من جهاز المضيف.';

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
      {String message = 'يتم تنزيل بيانات المتجر الأولية من جهاز المضيف.',
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
      {String message = 'تم تنزيل بيانات المتجر الأولية.'}) async {
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
      this.restoredSnapshot = false});
  final bool ok;
  final String message;
  final int pushed;
  final int pulled;
  final bool restoredSnapshot;
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
      this.pulled = 0});
  final bool ok;
  final String message;
  final AppIdentity? identity;
  final bool restoredSnapshot;
  final int pulled;
}

class CloudSyncService {
  CloudSyncService(this.store, {http.Client? client})
      : _client = client ?? http.Client();

  final AppStore store;
  final http.Client _client;
  late final UnifiedSyncCoreService _syncCore = UnifiedSyncCoreService(store);
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
          'تم اكتشاف نسخة مسترجعة جديدة على المضيف. جارٍ إعادة بناء بيانات الجهاز...');
      await CloudSyncSettings.clearSavedPullCursor();
      await SyncDeviceStateStore.resetClientProgress(store.appIdentity,
          transport: 'cloud');
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
    _syncDiag(
      'recordDeviceSyncState device=${store.appIdentity.deviceId} '
      'role=${_identityRoleLabel(store.appIdentity)} transport=$transport '
      'cursor=${cursor?.toIso8601String() ?? 'null'} sequence=$sequence '
      'willRegisterAck=${settings != null && store.appIdentity.isClient && cursor != null}',
    );
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

  Future<CloudPairingCodeResult> createPairingCode(CloudSyncSettings settings,
      {String transport = 'cloud', int ttlMinutes = 5}) async {
    final identity = store.appIdentity;
    if (!identity.isHost) {
      return const CloudPairingCodeResult(
          ok: false, message: 'يمكن لجهاز المضيف فقط إنشاء رموز الاقتران.');
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
                'فشل إنشاء رمز الاقتران: ${response.statusCode} ${response.body}');
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
            ? 'تم إنشاء رمز الاقتران.'
            : (decoded['error']?.toString() ?? 'فشل إنشاء رمز الاقتران.'),
        code: decoded['code']?.toString() ?? '',
        expiresAt: DateTime.tryParse(decoded['expiresAt']?.toString() ?? ''),
      );
    } catch (error) {
      return CloudPairingCodeResult(
          ok: false, message: 'فشل إنشاء رمز الاقتران: $error');
    }
  }

  Future<void> _publishPairingBootstrapInBackground(
      CloudSyncSettings settings) async {
    try {
      await publishLoginBootstrapSnapshotToCloud(settings, force: true);
      await _pushPendingToEndpoint(settings, 'cloud', '/api/sync/push');
      await publishBootstrapSnapshotToCloud(settings, force: true);
    } catch (error) {
      debugPrint('فشل نشر تهيئة الاقتران السحابية في الخلفية: $error');
    }
  }

  Future<CloudPairingStatusResult> pairingCodeStatus(
      CloudSyncSettings settings, String code) async {
    final identity = store.appIdentity;
    if (!identity.isHost) {
      return const CloudPairingStatusResult(
          ok: false,
          status: 'invalid',
          message: 'يمكن لجهاز المضيف فقط التحقق من حالة رمز الاقتران.');
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
                'فشل فحص حالة الاقتران: ${response.statusCode} ${response.body}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final status = decoded['status']?.toString() ?? 'invalid';
      return CloudPairingStatusResult(
        ok: decoded['ok'] == true,
        status: status,
        message: decoded['ok'] == true
            ? status
            : (decoded['error']?.toString() ?? 'فشل فحص حالة الاقتران.'),
        expiresAt: DateTime.tryParse(decoded['expiresAt']?.toString() ?? ''),
        claimedAt: DateTime.tryParse(decoded['claimedAt']?.toString() ?? ''),
        claimedByDeviceId: decoded['claimedByDeviceId']?.toString() ?? '',
        claimedByDeviceName: decoded['claimedByDeviceName']?.toString() ?? '',
        claimedDeviceToken: decoded['claimedDeviceToken']?.toString() ?? '',
      );
    } catch (error) {
      return CloudPairingStatusResult(
          ok: false,
          status: 'invalid',
          message: 'فشل فحص حالة الاقتران: $error');
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
                  'فشل تهيئة تسجيل الدخول السحابية: ${pull.statusCode} ${pull.body}');
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
                  'فشلت متابعة صفحات تهيئة تسجيل الدخول السحابية: مؤشر الصفحة التالية مفقود.');
        }
      }
      // Do not save the global Cloud pull cursor here. This is only a partial
      // login bootstrap; leaving the cursor empty lets the post-login
      // provisioning sync download the complete snapshot from the beginning.
      return CloudSyncResult(
          ok: true,
          pulled: pulled,
          restoredSnapshot: pulled > 0,
          message: 'تم سحب $pulled سجل/سجلات تسجيل دخول من التهيئة السحابية.');
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'فشل تهيئة تسجيل الدخول السحابية: $error');
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
              'لا يمكن لأجهزة المضيف الاقتران كعملاء سحابة. استخدم نقل المضيف بدلاً من ذلك.');
    }
    // A Client may configure both LAN and Cloud, but only one active transport
    // should run at a time. Pairing Cloud is therefore allowed for an existing
    // LAN Client as long as it is not a Host.
    // Client bootstrap pairing intentionally requires only the Cloud API URL and
    // a single-use pairing code. Account sessions stay on Host devices.
    if (!settings.enabled || settings.apiBaseUrl.trim().isEmpty) {
      return const CloudPairingClaimResult(
          ok: false, message: 'رابط واجهة السحابة مطلوب.');
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
                'انتهت صلاحية رمز الاقتران أو تم استخدامه مسبقاً. اطلب رمزاً جديداً من جهاز المضيف.');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['ok'] != true) {
        return const CloudPairingClaimResult(
            ok: false,
            message:
                'انتهت صلاحية رمز الاقتران أو تم استخدامه مسبقاً. اطلب رمزاً جديداً من جهاز المضيف.');
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
                  'رمز الاقتران يخص متجراً مختلفاً (${mismatches.join(', ')}). استخدم رمز الاقتران من المضيف الحالي.');
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
          message: 'جارٍ تنزيل بيانات المتجر كاملة قبل تفعيل الجهاز.',
        );

        CloudSyncResult request = const CloudSyncResult(
          ok: true,
          message: 'سيتم استخدام أحدث لقطة سحابية متاحة.',
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
            if (!verified.ok || store.needsInitialAdminSetup) {
              throw StateError(verified.message);
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
              message: 'تم تنزيل بيانات المتجر كاملة.',
            );
            onProgress?.call(1.0, 'Cloud snapshot is ready.');
            return CloudPairingClaimResult(
              ok: true,
              message:
                  'تم اقتران الجهاز وتنزيل بيانات المتجر كاملة. يمكنك تسجيل الدخول الآن.',
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
          message: 'لم تكتمل لقطة المتجر الكاملة بعد.',
        );
        return CloudPairingClaimResult(
          ok: false,
          message: request.ok
              ? 'تم تسجيل الجهاز، لكن لم تكتمل لقطة المتجر الكاملة بعد. أبقِ المضيف متصلاً وحاول مرة أخرى.'
              : request.message,
          identity: store.appIdentity,
        );
      }
      return CloudPairingClaimResult(
          ok: true,
          message: 'تم اقتران الجهاز بنجاح. يرجى تسجيل الدخول.',
          identity: identity);
    } catch (error) {
      if (deviceRegistered) {
        return CloudPairingClaimResult(
          ok: false,
          message:
              'تم تسجيل الجهاز، لكن لم تكتمل لقطة المتجر الكاملة. أبقِ المضيف متصلاً وحاول مرة أخرى.',
          identity: store.appIdentity,
        );
      }
      return const CloudPairingClaimResult(
          ok: false,
          message:
              'تعذر توصيل هذا الجهاز. تحقق من رمز الاقتران وحاول مرة أخرى.');
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
    final cleanBranchId = (branchId == null || branchId.trim().isEmpty)
        ? ''
        : branchId.trim().toUpperCase();
    final cleanRecoveryKey = recoveryKey.trim().toUpperCase();
    if (settings.apiBaseUrl.trim().isEmpty) {
      return const CloudStoreRecoveryResult(
          ok: false, message: 'رابط واجهة السحابة مطلوب.');
    }
    if (!cleanStoreId.startsWith('ST-') || cleanRecoveryKey.isEmpty) {
      return const CloudStoreRecoveryResult(
          ok: false, message: 'يجب إدخال معرّف متجر ومفتاح استرداد صالحين.');
    }

    try {
      onProgress?.call(0.10, 'جارٍ التحقق من معرّف المتجر ومفتاح الاسترداد...');
      final claimResponse = await _client
          .post(
            settings.endpoint('/api/sync/recovery/claim'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (store.appIdentity.isHost &&
                  settings.accountToken.trim().isNotEmpty)
                'Authorization': 'Bearer ${settings.accountToken.trim()}',
            },
            body: jsonEncode({
              'storeId': cleanStoreId,
              'branchId': cleanBranchId,
              'recoveryKey': cleanRecoveryKey,
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
                'فشل استرداد المتجر: ${claimResponse.statusCode} ${claimResponse.body}');
      }
      final claim = jsonDecode(claimResponse.body) as Map<String, dynamic>;
      if (claim['ok'] != true) {
        return CloudStoreRecoveryResult(
            ok: false,
            message: claim['error']?.toString() ?? 'فشل استرداد المتجر.');
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

      onProgress?.call(0.25, 'جارٍ استعادة هوية المتجر الدائمة...');
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

      onProgress?.call(0.45, 'جارٍ تنزيل أحدث لقطة سحابية...');
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
                  'تم استرداد هوية المتجر، لكن فشل تنزيل اللقطة: ${pull.statusCode} ${pull.body}',
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
            message: 'تم اكتشاف فجوة في سجل أحداث السحابة. يلزم إصلاح اللقطة.',
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
            'تم تطبيق $pulled سجل/سجلات مستردة...');
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
              message: 'فشلت متابعة صفحات استرداد المتجر.',
              identity: store.appIdentity,
              pulled: pulled);
        }
      }

      onProgress?.call(0.90, 'جارٍ نشر لقطة المضيف المستردة...');
      await publishBootstrapSnapshotToCloud(settings,
          force: true, onProgress: onProgress);
      await _pushPendingToEndpoint(settings, 'cloud', '/api/sync/push');
      await sendHostHeartbeat(settings);
      onProgress?.call(1.0, 'تم استرداد المتجر.');
      return CloudStoreRecoveryResult(
          ok: true,
          message: 'تم استرداد المتجر الحالي بنجاح.',
          identity: store.appIdentity,
          restoredSnapshot: restoredSnapshot,
          pulled: pulled);
    } catch (error) {
      return CloudStoreRecoveryResult(
          ok: false, message: 'فشل استرداد المتجر: $error');
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

  Future<CloudSyncResult> requestFreshHostSnapshot(CloudSyncSettings settings,
      {DateTime? requestedAt, String snapshotGeneration = ''}) async {
    final identity = store.appIdentity;
    if (identity.isHost) {
      return const CloudSyncResult(
          ok: true, message: 'يمكن للمضيف نشر لقطته مباشرة.');
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
              'تم طلب Snapshot لهذا الجيل سابقاً أو تم تطبيقه، لذلك لن يتم إرسال طلب مكرر.');
    }
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
          'clientMutationId':
              '${store.deviceId}_${now.microsecondsSinceEpoch}_system_store_request_snapshot',
        },
        'reason': 'cloud_rebuild_from_host',
        'requestedAt': now.toIso8601String(),
        if (cleanGeneration.isNotEmpty) 'snapshotGeneration': cleanGeneration,
        if (cleanGeneration.isNotEmpty)
          'hostSnapshotGeneration': cleanGeneration,
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
        return CloudSyncResult(
            ok: false,
            message:
                'فشل طلب لقطة حديثة من المضيف: ${response.statusCode} ${response.body}');
      }
      await _markFreshSnapshotRequestedForGeneration('cloud', cleanGeneration);
      return const CloudSyncResult(
          ok: true,
          message:
              'تم طلب لقطة حديثة من المضيف. سينشر المضيف لقطة كاملة جديدة عند المزامنة السحابية التالية.');
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'فشل طلب لقطة حديثة من المضيف: $error');
    }
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
          message: 'إعادة البناء من المضيف متاحة فقط لأجهزة العميل.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false,
          message: 'رابط واجهة السحابة ورمز الجهاز المقترن مطلوبان.');
    }

    final snapshotRequestedAt = DateTime.now().toUtc();
    if (requestFreshSnapshot) {
      onProgress?.call(0.08, 'جارٍ طلب لقطة حديثة من المضيف...');
      final request = await requestFreshHostSnapshot(
        settings,
        requestedAt: snapshotRequestedAt,
        snapshotGeneration: expectedSnapshotGeneration,
      );
      if (!request.ok) return request;
    } else {
      onProgress?.call(0.08,
          'تم العثور على Snapshot منشورة مسبقاً. لن يتم إرسال طلب جديد للمضيف...');
    }

    onProgress?.call(0.18,
        'جارٍ التحقق من وجود لقطة حديثة من المضيف قبل تعديل البيانات المحلية...');
    // Phase 2: first try the transport-neutral chunk downloader. Cloud and LAN
    // now share the same manifest -> chunks -> envelope -> importer pipeline;
    // only the requestManifest/requestChunk transport is different.
    for (var attempt = 0; attempt < 6; attempt += 1) {
      if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 3));
      try {
        final envelope = await _downloadCloudSnapshotEnvelope(
          settings.copyWith(clearLastPullCursor: true),
          force: false,
          onProgress: (value, label) {
            final scaled = (0.22 + value * 0.58).clamp(0.0, 0.82).toDouble();
            onProgress?.call(scaled, label);
          },
        );
        if ((envelope['hostSnapshotGeneration'] ?? '')
                .toString()
                .trim()
                .isEmpty &&
            expectedSnapshotGeneration.trim().isNotEmpty) {
          envelope['hostSnapshotGeneration'] =
              expectedSnapshotGeneration.trim();
          envelope['snapshotGeneration'] = expectedSnapshotGeneration.trim();
        }
        if ((envelope['hostRestoreCommandId'] ?? '')
                .toString()
                .trim()
                .isEmpty &&
            expectedRestoreCommandId.trim().isNotEmpty) {
          envelope['hostRestoreCommandId'] = expectedRestoreCommandId.trim();
          envelope['restoreCommandId'] = expectedRestoreCommandId.trim();
        }
        onProgress?.call(0.84, 'جارٍ تطبيق دفعات اللقطة السحابية محلياً...');
        await store.importSyncSnapshotJson(jsonEncode(envelope));
        await _markHostSnapshotGenerationApplied('cloud', envelope,
            markRestoreCommandExecuted: true);
        onProgress?.call(
            0.90, 'جارٍ التحقق من البيانات المحلية بعد إعادة البناء...');
        final repaired = await store.verifyLocalBusinessDataIntegrity();
        onProgress?.call(0.96, 'جارٍ تنظيف السجلات المحلية...');
        await store.cleanupSoftDeletedRecords();
        // The snapshot was imported successfully. Do not repeat the same rebuild
        // just because the post-import integrity check reports warnings.
        await CloudProvisioningStatus.markComplete(
            message: 'تم تنزيل بيانات المتجر الأولية.');
        final cursor =
            store.syncSnapshotGeneratedAtFromJson(jsonEncode(envelope));
        final sequence =
            store.syncSnapshotGeneratedSequenceFromJson(jsonEncode(envelope));
        // A successful Cloud rebuild establishes the Client baseline. Persist
        // the pull cursor and publish the device progress to the server;
        // otherwise the server keeps seeing this Client at sequence 0 and the
        // next Cloud cycle may re-enter provisioning/rebuild instead of pulling
        // incremental sync_events.
        await settings.copyWith(lastPullCursor: cursor).save();
        await _recordDeviceSyncState(
          'cloud',
          cursor,
          sequence: sequence,
          settings: settings.copyWith(lastPullCursor: cursor),
        );
        onProgress?.call(1.0, 'اكتملت إعادة البناء السحابية.');
        return CloudSyncResult(
          ok: repaired.ok,
          pulled: (envelope['totalChunks'] as num?)?.toInt() ?? 0,
          restoredSnapshot: true,
          message: repaired.ok
              ? 'اكتملت إعادة البناء السحابية من دفعات Snapshot موحدة.'
              : 'تم تنزيل دفعات Snapshot موحدة، لكن فحص البيانات المحلي وجد مشاكل: ${repaired.message}',
        );
      } catch (_) {
        onProgress?.call(
          (0.24 + attempt * 0.08).clamp(0.24, 0.68).toDouble(),
          'بانتظار توفر دفعات Snapshot السحابية (المحاولة ${attempt + 1}/6)...',
        );
      }
    }

    // Do not wipe current Client data until a fresh restore_snapshot is actually
    // received and applied. Failed pairing or unavailable Host data must not
    // erase anything locally. Keep the legacy entity-snapshot pull as a
    // compatibility fallback for servers not yet migrated to chunk downloads.
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
      final attemptProgress =
          (0.28 + attempt * 0.09).clamp(0.28, 0.73).toDouble();
      onProgress?.call(attemptProgress,
          'بانتظار لقطة المضيف وسحب التحديثات (المحاولة ${attempt + 1}/6)...');
      lastResult = await syncNow(freshSettings,
          minSnapshotUpdatedAt: snapshotRequestedAt,
          onProgress: (value, label) {
        final scaled = attemptProgress + (value * 0.08);
        onProgress?.call(scaled.clamp(0.0, 0.82).toDouble(), label);
      });
      if (!lastResult.ok) break;
      totalPulled += lastResult.pulled;
      freshSettings = CloudSyncSettings.load()
          .copyWith(clearLastPullCursor: attempt == 0 ? true : false);
      if (lastResult.restoredSnapshot) {
        onProgress?.call(
            0.88, 'جارٍ التحقق من البيانات المحلية بعد إعادة البناء...');
        final repaired = await store.verifyLocalBusinessDataIntegrity();
        onProgress?.call(0.94, 'جارٍ تنظيف السجلات المحلية...');
        await store.cleanupSoftDeletedRecords();
        await CloudProvisioningStatus.markComplete(
            message: 'تم تنزيل بيانات المتجر الأولية.');
        onProgress?.call(1.0, 'اكتملت إعادة البناء السحابية.');
        return CloudSyncResult(
          ok: repaired.ok,
          pushed: lastResult.pushed,
          pulled: totalPulled,
          restoredSnapshot: true,
          message: repaired.ok
              ? 'اكتملت إعادة البناء السحابية من لقطة حديثة مطلوبة من المضيف. ${lastResult.message}'
              : 'سحبت إعادة البناء السحابية لقطة حديثة من المضيف، لكن فحص البيانات المحلي وجد مشاكل: ${repaired.message}',
        );
      }
    }

    return CloudSyncResult(
      ok: false,
      pushed: lastResult?.pushed ?? 0,
      pulled: totalPulled,
      message:
          'طلبت إعادة البناء السحابية لقطة حديثة من المضيف، لكن لم يتم سحب أي لقطة بعد. أبقِ المضيف متصلاً وأعد المحاولة. ${lastResult?.message ?? ''}',
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
                'فشل فحص صلاحية وصول الجهاز إلى السحابة: ${response.statusCode} ${response.body}');
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
        await store.factoryResetLocalDevice();
        return const CloudSyncResult(
            ok: false,
            message: 'تم حذف الجهاز من قبل المضيف. تم مسح البيانات المحلية.');
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
          ok: false, message: 'فشل فحص صلاحية وصول الجهاز إلى السحابة: $error');
    }
  }

  Future<CloudSyncResult> setDeviceSuspended(
      CloudSyncSettings settings, String deviceId,
      {required bool suspended}) async {
    final identity = store.appIdentity;
    if (!identity.isHost) {
      return const CloudSyncResult(
          ok: false, message: 'يمكن للمضيف فقط تعليق الأجهزة.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'رابط واجهة السحابة والرمز مطلوبان.');
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
                ? 'تم تعليق الجهاز في السحابة.'
                : 'تمت إعادة تفعيل الجهاز في السحابة.')
            : 'فشل تعليق/إعادة تفعيل الجهاز: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'فشل تعليق/إعادة تفعيل الجهاز: $error');
    }
  }

  Future<CloudSyncResult> revokeDevice(
      CloudSyncSettings settings, String deviceId) async {
    final identity = store.appIdentity;
    if (!identity.isHost) {
      return const CloudSyncResult(
          ok: false, message: 'يمكن للمضيف فقط إلغاء الأجهزة.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'رابط واجهة السحابة والرمز مطلوبان.');
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
            ? 'تم إلغاء الجهاز.'
            : 'فشل إلغاء الجهاز: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'فشل إلغاء الجهاز: $error');
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
          ok: false, message: 'رابط واجهة السحابة والرمز مطلوبان.');
    }
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
              'lastSyncTransport': deviceState.lastSyncTransport.isEmpty
                  ? transport
                  : deviceState.lastSyncTransport,
              'lastAppliedCursor':
                  deviceState.lastAppliedHostCursor?.toIso8601String(),
              'lastAckCursor': deviceState.lastAckCursor?.toIso8601String(),
              'lastAppliedSequence': deviceState.lastAppliedSequence,
              'lastAckSequence': deviceState.lastAckSequence,
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
            ? 'تم تحديث نبض الجهاز.'
            : 'فشل نبض الجهاز: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'فشل نبض الجهاز: $error');
    }
  }

  Future<CloudSyncResult> requestHostTransfer(CloudSyncSettings settings,
      {String reason = ''}) async {
    final identity = store.appIdentity;
    if (!identity.isClient) {
      return const CloudSyncResult(
          ok: false, message: 'يمكن للعملاء فقط طلب نقل المضيف.');
    }
    if (settings.apiBaseUrl.trim().isEmpty) {
      return const CloudSyncResult(
          ok: false, message: 'رابط واجهة السحابة مطلوب.');
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
            ? 'تم إرسال طلب نقل المضيف.'
            : 'فشل طلب نقل المضيف: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'فشل طلب نقل المضيف: $error');
    }
  }

  Future<CloudSyncResult> approveHostTransfer(
      CloudSyncSettings settings, String requestingDeviceId) async {
    final identity = store.appIdentity;
    if (!identity.isHost) {
      return const CloudSyncResult(
          ok: false, message: 'يمكن للمضيفين فقط الموافقة على نقل المضيف.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'رابط واجهة السحابة والرمز مطلوبان.');
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
            ? 'تمت الموافقة على نقل المضيف في السحابة.'
            : 'فشل اعتماد نقل المضيف: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'فشل اعتماد نقل المضيف: $error');
    }
  }

  Future<CloudSyncResult> activateHostTransfer(
      CloudSyncSettings settings) async {
    final identity = store.appIdentity;
    if (!settings.isConfigured && settings.apiBaseUrl.trim().isEmpty) {
      return const CloudSyncResult(
          ok: false, message: 'رابط واجهة السحابة مطلوب.');
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
            ? 'تم تفعيل نقل المضيف في السحابة.'
            : 'فشل تفعيل نقل المضيف: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'فشل تفعيل نقل المضيف: $error');
    }
  }

  Future<List<CloudDeviceStatus>> listDevices(
      CloudSyncSettings settings) async {
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
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const <CloudDeviceStatus>[];
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return (decoded['devices'] as List<dynamic>? ?? [])
        .map((item) =>
            CloudDeviceStatus.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<CloudSyncResult> repairLegacyCloudDeviceLinks(
    CloudSyncSettings settings, {
    required Iterable<String> clientDeviceIds,
  }) async {
    final identity = store.appIdentity;
    if (!identity.isHost) {
      return const CloudSyncResult(
          ok: false, message: 'يمكن للمضيف فقط إصلاح روابط أجهزة السحابة.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'رابط واجهة السحابة والرمز مطلوبان.');
    }
    final cleanClientIds = clientDeviceIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && id != store.deviceId)
        .toSet()
        .toList();
    if (cleanClientIds.isEmpty) {
      return const CloudSyncResult(
          ok: true,
          message: 'لا توجد روابط أجهزة سحابية قديمة تحتاج إلى إصلاح.');
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
                'فشل إصلاح روابط أجهزة السحابة: ${response.statusCode} ${response.body}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final repaired = int.tryParse('${decoded['repaired'] ?? 0}') ?? 0;
      final checked =
          int.tryParse('${decoded['checked'] ?? cleanClientIds.length}') ??
              cleanClientIds.length;
      return CloudSyncResult(
          ok: decoded['ok'] == true,
          message:
              'تم فحص روابط أجهزة السحابة: $checked، تم إصلاح: $repaired.');
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'فشل إصلاح روابط أجهزة السحابة: $error');
    }
  }

  Future<CloudSyncResult> testConnection(CloudSyncSettings settings) async {
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'رابط واجهة السحابة والرمز مطلوبان.');
    }
    final accessResult = await checkCurrentDeviceAccess(settings);
    if (accessResult != null) return accessResult;

    try {
      final health = await _client
          .get(settings.endpoint('/api/health'), headers: _headers(settings))
          .timeout(const Duration(seconds: 10));
      if (health.statusCode < 200 || health.statusCode >= 300) {
        final authMessage = health.statusCode == 401 || health.statusCode == 403
            ? 'غير مصرح/الرمز غير صالح: رفضت واجهة السحابة الرمز.'
            : 'تعذر الوصول إلى خادم السحابة: أرجعت واجهة السحابة الحالة ${health.statusCode}: ${health.body}';
        return CloudSyncResult(ok: false, message: authMessage);
      }
      final decoded = jsonDecode(health.body) as Map<String, dynamic>;
      if (decoded['ok'] != true) {
        return const CloudSyncResult(
            ok: false, message: 'Cloud health response was not successful.');
      }
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'تعذر الوصول إلى خادم السحابة: $error');
    }

    final identity = store.appIdentity;
    if (!identity.isClient) {
      return const CloudSyncResult(
          ok: true, message: 'اتصال واجهة السحابة سليم.');
    }

    if (identity.deviceToken.trim().isEmpty) {
      return const CloudSyncResult(
          ok: false,
          message:
              'غير مصرح/الرمز غير صالح: لا يحتوي هذا العميل على رمز جهاز محفوظ. أعد اقتران هذا الجهاز.');
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
            : 'تعذر الوصول إلى خادم السحابة: ${hostStatus.message}';
        return CloudSyncResult(ok: false, message: message);
      }
      if (!hostStatus.hostReachable) {
        return CloudSyncResult(
            ok: false, message: 'المضيف غير متصل: ${hostStatus.message}');
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
            ? 'غير مصرح/الرمز غير صالح: رفضت المزامنة السحابية هذا الجهاز. أعد اقتران هذا الجهاز.'
            : 'المزامنة غير جاهزة: فشل فحص المزامنة السحابية بالحالة ${ping.statusCode}: ${ping.body}';
        return CloudSyncResult(ok: false, message: message);
      }

      return const CloudSyncResult(
          ok: true, message: 'السحابة متصلة وجاهزة للمزامنة.');
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'المزامنة غير جاهزة: $error');
    }
  }

  Future<CloudSyncResult> validateSingleHost(CloudSyncSettings settings) async {
    final identity = store.appIdentity;
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'رابط واجهة السحابة والرمز مطلوبان.');
    }
    final status = await getHostHeartbeatStatus(settings);
    if (status.cloudReachable &&
        status.hostReachable &&
        status.hostDeviceId.isNotEmpty &&
        status.hostDeviceId != store.deviceId) {
      return CloudSyncResult(
        ok: false,
        message:
            'يوجد مضيف نشط آخر متصل بالفعل للمتجر ${identity.storeId}: ${status.hostDeviceName.isEmpty ? status.hostDeviceId : status.hostDeviceName}. حوّل هذا الجهاز إلى عميل أو أوقف المضيف القديم أولاً.',
      );
    }
    return const CloudSyncResult(
        ok: true, message: 'لم يتم العثور على مضيف نشط آخر.');
  }

  Future<CloudSyncResult> sendHostHeartbeat(CloudSyncSettings settings) async {
    final identity = store.appIdentity;
    if (!identity.isCloudEnabled || !identity.isHost) {
      return const CloudSyncResult(
          ok: false,
          message: 'يتم إرسال النبض فقط من جهاز مضيف مفعّل للسحابة.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'رابط واجهة السحابة والرمز مطلوبان.');
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
            ? 'تم تحديث نبض المضيف.'
            : 'فشل نبض المضيف: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'فشل نبض المضيف: $error');
    }
  }

  Future<HostHeartbeatStatus> getHostHeartbeatStatus(CloudSyncSettings settings,
      {Duration staleAfter = const Duration(seconds: 90)}) async {
    final identity = store.appIdentity;
    if (!settings.isConfigured) {
      return const HostHeartbeatStatus(
          cloudReachable: false,
          hostReachable: false,
          message: 'رابط واجهة السحابة والرمز مطلوبان.');
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
                'أرجعت واجهة السحابة الحالة ${response.statusCode}: ${response.body}');
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
            ? 'نبض المضيف حديث.'
            : (lastSeenAt == null
                ? 'لم يتم العثور على نبض للمضيف.'
                : 'نبض المضيف قديم.'),
      );
    } catch (error) {
      return HostHeartbeatStatus(
          cloudReachable: false,
          hostReachable: false,
          message: 'فشل اتصال واجهة السحابة: $error');
    }
  }

  Future<Map<String, dynamic>?> runCloudMaintenance(CloudSyncSettings settings,
      {int keepRecentEvents = 200}) async {
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
              'keepRecentEvents': keepRecentEvents,
              'activeDeviceDays': 14,
              'processedRequestRetentionDays': 3,
              'deletedSnapshotRetentionDays': 7,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
            'فشلت صيانة السحابة: ${response.statusCode} ${response.body}');
        return null;
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (error) {
      debugPrint('فشلت صيانة السحابة: $error');
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
    final chunks = store.exportCloudLoginBootstrapSnapshotChunks();
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
    final chunks =
        store.exportCloudBootstrapSnapshotChunks(maxItemsPerChunk: 300);
    if (chunks.isEmpty) return 0;
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
              body: jsonEncode({
                'deviceId': store.deviceId,
                'storeId': identity.storeId,
                'branchId': identity.branchId,
                'sequence':
                    SyncDeviceStateStore.load(identity).lastAppliedSequence,
                'lastAppliedSequence':
                    SyncDeviceStateStore.load(identity).lastAppliedSequence,
                'batchNumber': batchNumber,
                'batchSize': pending.length,
                'changes': pending.map((item) => item.toJson()).toList(),
              }),
            )
            .timeout(const Duration(seconds: 30));
        if (push.statusCode < 200 || push.statusCode >= 300) {
          final message =
              'فشل الدفع السحابي في الدفعة $batchNumber: ${push.statusCode} ${push.body}';
          await _syncCore.markPushFailed(pendingIds, message);
          throw StateError(message);
        }
        final decoded = jsonDecode(push.body) as Map<String, dynamic>;
        final ackIds = (decoded['ackIds'] as List<dynamic>? ?? [])
            .map((item) => '$item')
            .toList();
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
        await _syncCore.markPushFailed(
            pendingIds, 'فشل الدفع السحابي في الدفعة $batchNumber: $error');
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
          if (id.isNotEmpty) {
            output[id] =
                (item['reason'] ?? 'تم رفضه من قبل المضيف.').toString();
          }
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
    if (acceptedIds.isNotEmpty) {
      await _syncCore.markPushAcknowledged(acceptedIds);
    }

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
      throw StateError(
          'فشل سحب طلبات السحابة: ${pull.statusCode} ${pull.body}');
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
            'rejected': accepted.rejected.entries
                .map((entry) => {'id': entry.key, 'reason': entry.value})
                .toList(),
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (ack.statusCode < 200 || ack.statusCode >= 300) {
      throw StateError('فشل تأكيد طلب السحابة: ${ack.statusCode} ${ack.body}');
    }

    // Publish the newly authoritative Host events after ACK. If this upload
    // fails, the Host keeps those cloud queue rows retryable without trapping
    // the already-accepted Client request in submitted/pending state.
    await _pushPendingToEndpoint(settings, 'cloud', '/api/sync/push');
    return changes.length;
  }

  Future<CloudSyncResult> pushPendingForUnifiedEngine(
      CloudSyncSettings settings,
      {CloudSyncProgressCallback? onProgress}) async {
    final identity = store.appIdentity;
    if (!_cloudAllowedForIdentity(identity)) {
      return const CloudSyncResult(
          ok: false,
          message: 'السحابة ليست وسيلة المزامنة النشطة/المهيأة لهذا الجهاز.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'رابط واجهة السحابة والرمز مطلوبان.');
    }

    try {
      var pushed = 0;
      var acceptedRemoteRequests = 0;

      if (identity.isHost) {
        onProgress?.call(0.10, 'جارٍ تجهيز قائمة لقطات المضيف السحابية...');
        await store.ensureHostCloudBootstrapSnapshotQueued();
        final repairedCloudQueue =
            await store.repairMissingHostCloudQueueForPendingChanges();
        if (repairedCloudQueue > 0) {
          onProgress?.call(0.18,
              'تم إصلاح $repairedCloudQueue عنصر/عناصر مفقودة في قائمة المضيف السحابية...');
        }
        onProgress?.call(0.25, 'جارٍ إرسال نبض المضيف...');
        await sendHostHeartbeat(settings);
        onProgress?.call(0.40, 'جارٍ تسجيل جهاز المضيف...');
        await registerCurrentDevice(settings, transport: 'cloud');
        onProgress?.call(0.55, 'جارٍ فحص طلبات العملاء...');
        acceptedRemoteRequests = await _hostPullRemoteRequests(settings);
        onProgress?.call(0.75, 'جارٍ رفع تغييرات المضيف المعتمدة...');
        await store.repairMissingHostCloudQueueForPendingChanges();
        pushed +=
            await _pushPendingToEndpoint(settings, 'cloud', '/api/sync/push');
        await runCloudMaintenance(settings);
        return CloudSyncResult(
          ok: true,
          pushed: pushed,
          message:
              'اكتمل الدفع السحابي للمضيف. تم قبول $acceptedRemoteRequests طلب/طلبات بعيدة، وتم دفع $pushed تغيير/تغييرات معتمدة.',
        );
      }

      onProgress?.call(0.12, 'جارٍ تسجيل جهاز العميل...');
      await registerCurrentDevice(settings, transport: 'cloud');
      onProgress?.call(0.22, 'جارٍ فحص طلبات العميل المرسلة...');
      await _pollSubmittedClientRequests(settings);
      onProgress?.call(0.28, 'جارٍ إرسال طلبات العميل إلى وسيط المضيف...');
      pushed += await _pushPendingToEndpoint(
          settings, 'cloud_host', '/api/sync/requests/push');
      return CloudSyncResult(
          ok: true,
          pushed: pushed,
          message:
              'اكتمل الدفع السحابي للعميل. تم إرسال $pushed طلب/طلبات إلى وسيط المضيف.');
    } catch (error) {
      return CloudSyncResult(ok: false, message: 'فشل الدفع السحابي: $error');
    }
  }

  Future<bool> _cloudSnapshotIsNewerThanLocal(
    CloudSyncSettings settings,
  ) async {
    if (!store.appIdentity.isClient) return false;
    try {
      final state = SyncDeviceStateStore.load(store.appIdentity);
      final localCursor =
          state.lastAppliedHostCursor ?? settings.lastPullCursor;
      final manifest = await _CloudSnapshotPullTransport(
        settings: settings,
        headers: _headers(settings),
        client: _client,
        storeId: store.appIdentity.storeId,
        branchId: store.appIdentity.branchId,
      ).requestManifest();
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
          message: 'أجهزة المضيف لا تسحب تغييرات سحابية معتمدة.',
          pulled: 0);
    }
    if (!_cloudAllowedForIdentity(identity)) {
      return const CloudSyncResult(
          ok: false,
          message: 'السحابة ليست وسيلة المزامنة النشطة/المهيأة لهذا الجهاز.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'رابط واجهة السحابة والرمز مطلوبان.');
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
      final baseLastAppliedSequence =
          SyncDeviceStateStore.load(store.appIdentity).lastAppliedSequence;
      _syncDiag(
        'clientPull:start device=${identity.deviceId} store=${identity.storeId} '
        'branch=${identity.branchId} apiBase=${settings.apiBaseUrl} '
        'initialCursor=${initialCursor?.toIso8601String() ?? 'null'} '
        'baseLastAppliedSequence=$baseLastAppliedSequence '
        'minSnapshotUpdatedAt=${minSnapshotUpdatedAt?.toIso8601String() ?? 'null'}',
      );
      if (await _cloudSnapshotIsNewerThanLocal(settings)) {
        _syncDiag(
            'clientPull:snapshotNewerThanLocal -> rebuildFromCloudHostSnapshot');
        onProgress?.call(0.32,
            'تم العثور على Snapshot أحدث من المضيف. جارٍ إعادة بناء بيانات هذا الجهاز...');
        await CloudSyncSettings.clearSavedPullCursor();
        await SyncDeviceStateStore.resetClientProgress(store.appIdentity,
            transport: 'cloud');
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
                  'توقف السحب السحابي بعد $maxPagesPerRun صفحة لتجنب حلقة لا نهائية. يرجى إعادة محاولة المزامنة.');
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
            pullProgress, 'جارٍ سحب تغييرات السحابة - صفحة $pageCount...');
        _syncDiag(
            'clientPull:request page=$pageCount url=$endpoint query=$query');
        final pull = await _client
            .get(endpoint, headers: _headers(settings))
            .timeout(const Duration(seconds: 20));
        _syncDiag(
          'clientPull:response page=$pageCount status=${pull.statusCode} '
          'bodyBytes=${pull.bodyBytes.length}',
        );
        if (pull.statusCode < 200 || pull.statusCode >= 300) {
          _syncDiag(
              'clientPull:error status=${pull.statusCode} body=${pull.body}');
          return CloudSyncResult(
              ok: false,
              message: 'فشل السحب السحابي: ${pull.statusCode} ${pull.body}');
        }

        final decodedPull = jsonDecode(pull.body) as Map<String, dynamic>;
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
          _syncDiag('clientPull:needsSnapshot source=${decodedPull['source']}');
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
                  'تم تجاهل أمر إعادة بناء منفذ سابقاً وتحديث مؤشر المزامنة.',
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
        final changes = _syncCore.filterOutLocalEchoes(
          _syncCore
              .decodeRemoteChanges(decodedPull['changes'] as List<dynamic>?),
        );
        final source = (decodedPull['source'] ?? '').toString();
        _syncDiag(
          'clientPull:decoded page=$pageCount source=$source '
          'changes=${changes.length} hasMore=${decodedPull['hasMore']} '
          'generatedAt=${decodedPull['generatedAt']} '
          'generatedSequence=${decodedPull['generatedSequence']} '
          'allSectionsComplete=$allSnapshotSectionsComplete',
        );
        final restoreMarker = changes.any((item) =>
            item.entityType == 'system' &&
            item.operation == 'cloud_restore_snapshot_ready');
        if (restoreMarker && store.appIdentity.isClient) {
          final commandId = _restoreCommandIdFromChanges(changes);
          if (_restoreCommandAlreadyExecuted('cloud', commandId)) {
            restoredSnapshot = false;
          } else {
            onProgress?.call(0.50,
                'تم العثور على استرجاع جديد على المضيف. جارٍ إعادة بناء بيانات الجهاز من Snapshot كاملة...');
            await CloudSyncSettings.clearSavedPullCursor();
            await SyncDeviceStateStore.resetClientProgress(store.appIdentity,
                transport: 'cloud');
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
            'جارٍ تطبيق ${changes.length} تغيير/تغييرات سحابية من الصفحة $pageCount...');
        final applied = await _syncCore.applyAuthoritativeChanges(changes);
        pulled += applied;
        _syncDiag(
            'clientPull:applied page=$pageCount applied=$applied totalPulled=$pulled');

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
              message:
                  'فشلت متابعة صفحات السحب السحابي: مؤشر الصفحة التالية مفقود.');
        }
      }

      final initialSnapshotStillUploading = initialCursor == null &&
          restoredSnapshot &&
          !allSnapshotSectionsComplete;
      if (initialSnapshotStillUploading) {
        onProgress?.call(0.90, 'بانتظار انتهاء المضيف من رفع أقسام المتجر...');
        await CloudProvisioningStatus.markPending(
            message:
                'ما زال المضيف يرفع بيانات المتجر. سيستمر التنزيل تلقائياً.');
      } else {
        onProgress?.call(0.90, 'جارٍ حفظ مؤشر المزامنة السحابية...');
        if (finalPullCursor != null) {
          _syncDiag(
            'clientPull:saveCursor cursor=${finalPullCursor.toIso8601String()} '
            'sequence=$finalPullSequence pulled=$pulled',
          );
          await settings.copyWith(lastPullCursor: finalPullCursor).save();
          await _recordDeviceSyncState('cloud', finalPullCursor,
              sequence: finalPullSequence, settings: settings);
        }
      }

      if (pulled > 0) {
        onProgress?.call(0.96, 'جارٍ التنظيف بعد المزامنة السحابية...');
        await store.cleanupSoftDeletedRecords();
      }
      if (store.appIdentity.isClient &&
          (restoredSnapshot || pulled > 0) &&
          !store.needsInitialAdminSetup &&
          !initialSnapshotStillUploading) {
        await CloudProvisioningStatus.markComplete(
            message: 'تم تنزيل بيانات المتجر الأولية.');
      }
      return CloudSyncResult(
        ok: true,
        pulled: pulled,
        restoredSnapshot: restoredSnapshot,
        message: 'اكتمل السحب السحابي. تم سحب $pulled تغيير/تغييرات معتمدة.',
      );
    } catch (error) {
      _syncDiag('clientPull:exception $error');
      return CloudSyncResult(ok: false, message: 'فشل السحب السحابي: $error');
    }
  }

  Future<CloudSyncResult> syncNow(CloudSyncSettings settings,
      {DateTime? minSnapshotUpdatedAt,
      CloudSyncProgressCallback? onProgress}) async {
    final identity = store.appIdentity;
    if (!_cloudAllowedForIdentity(identity)) {
      return const CloudSyncResult(
          ok: false,
          message: 'السحابة ليست وسيلة المزامنة النشطة/المهيأة لهذا الجهاز.');
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
          ok: false, message: 'رابط واجهة السحابة والرمز مطلوبان.');
    }
    final accessResult = await checkCurrentDeviceAccess(settings);
    if (accessResult != null) return accessResult;

    try {
      var pushed = 0;
      var pulled = 0;
      var acceptedRemoteRequests = 0;

      if (identity.isHost) {
        onProgress?.call(0.10, 'جارٍ تجهيز قائمة لقطات المضيف السحابية...');
        await store.ensureHostCloudBootstrapSnapshotQueued();
        final repairedCloudQueue =
            await store.repairMissingHostCloudQueueForPendingChanges();
        if (repairedCloudQueue > 0) {
          onProgress?.call(0.18,
              'تم إصلاح $repairedCloudQueue عنصر/عناصر مفقودة في قائمة المضيف السحابية...');
        }
        onProgress?.call(0.25, 'جارٍ إرسال نبض المضيف...');
        await sendHostHeartbeat(settings);
        onProgress?.call(0.40, 'جارٍ تسجيل جهاز المضيف...');
        await registerCurrentDevice(settings, transport: 'cloud');
        onProgress?.call(0.55, 'جارٍ فحص طلبات العملاء...');
        acceptedRemoteRequests = await _hostPullRemoteRequests(settings);
        onProgress?.call(0.75, 'جارٍ رفع تغييرات المضيف المعتمدة...');
        await store.repairMissingHostCloudQueueForPendingChanges();
        pushed +=
            await _pushPendingToEndpoint(settings, 'cloud', '/api/sync/push');
        onProgress?.call(0.90, 'جارٍ تشغيل صيانة آمنة لسجل المزامنة المحلي...');
        await store.compactSyncedSyncHistoryForMaintenance();
        onProgress?.call(0.96, 'جارٍ تشغيل صيانة آمنة للسحابة...');
        await runCloudMaintenance(settings);
        onProgress?.call(1.0, 'اكتملت مزامنة المضيف السحابية.');
        return CloudSyncResult(
          ok: true,
          pushed: pushed,
          pulled: 0,
          message:
              'اكتملت مزامنة المضيف السحابية. تم قبول $acceptedRemoteRequests طلب/طلبات بعيدة، وتم دفع $pushed تغيير/تغييرات معتمدة.',
        );
      } else {
        // Any cloud-enabled Client that has local draft changes should send
        // them to the Host relay. LAN Clients normally queue to target "host",
        // so this only affects Web or remote desktop/mobile Clients whose
        // pending changes target "cloud_host".
        onProgress?.call(0.12, 'جارٍ تسجيل جهاز العميل...');
        await registerCurrentDevice(settings, transport: 'cloud');
        onProgress?.call(0.28, 'جارٍ إرسال طلبات العميل إلى وسيط المضيف...');
        pushed += await _pushPendingToEndpoint(
            settings, 'cloud_host', '/api/sync/requests/push');
      }

      final initialCursor = settings.lastPullCursor;
      // Freeze the sequence watermark for the whole paginated pull. Reading
      // lastAppliedSequence after every page can skip pages: page 1 advances the
      // local state, then page 2 asks Cloud for sequence > the new value while
      // also passing the old page cursor. That combination can silently miss
      // events, which showed up as product count differences across devices.
      final baseLastAppliedSequence =
          SyncDeviceStateStore.load(store.appIdentity).lastAppliedSequence;
      if (await _cloudSnapshotIsNewerThanLocal(settings)) {
        onProgress?.call(0.32,
            'تم العثور على Snapshot أحدث من المضيف. جارٍ إعادة بناء بيانات هذا الجهاز...');
        await CloudSyncSettings.clearSavedPullCursor();
        await SyncDeviceStateStore.resetClientProgress(store.appIdentity,
            transport: 'cloud');
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
                  'توقف السحب السحابي بعد $maxPagesPerRun صفحة لتجنب حلقة لا نهائية. يرجى إعادة محاولة المزامنة.');
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
            pullProgress, 'جارٍ سحب تغييرات السحابة - صفحة $pageCount...');
        final pull = await _client
            .get(settings.endpoint('/api/sync/pull', query),
                headers: _headers(settings))
            .timeout(const Duration(seconds: 20));
        if (pull.statusCode < 200 || pull.statusCode >= 300) {
          final message = 'فشل السحب السحابي: ${pull.statusCode} ${pull.body}';
          return CloudSyncResult(ok: false, message: message);
        }

        final decodedPull = jsonDecode(pull.body) as Map<String, dynamic>;
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
                  'تم تجاهل أمر إعادة بناء منفذ سابقاً وتحديث مؤشر المزامنة.',
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
        final changes = _syncCore.filterOutLocalEchoes(
          _syncCore
              .decodeRemoteChanges(decodedPull['changes'] as List<dynamic>?),
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
                'تم العثور على استرجاع جديد على المضيف. جارٍ إعادة بناء بيانات الجهاز من Snapshot كاملة...');
            await CloudSyncSettings.clearSavedPullCursor();
            await SyncDeviceStateStore.resetClientProgress(store.appIdentity,
                transport: 'cloud');
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
            'جارٍ تطبيق ${changes.length} تغيير/تغييرات سحابية من الصفحة $pageCount...');
        pulled += await _syncCore.applyAuthoritativeChanges(changes);

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
              message:
                  'فشلت متابعة صفحات السحب السحابي: مؤشر الصفحة التالية مفقود.');
        }
      }

      final initialSnapshotStillUploading = initialCursor == null &&
          restoredSnapshot &&
          !allSnapshotSectionsComplete;
      if (initialSnapshotStillUploading) {
        onProgress?.call(0.90, 'بانتظار انتهاء المضيف من رفع أقسام المتجر...');
        await CloudProvisioningStatus.markPending(
            message:
                'ما زال المضيف يرفع بيانات المتجر. سيستمر التنزيل تلقائياً.');
      } else {
        onProgress?.call(0.90, 'جارٍ حفظ مؤشر المزامنة السحابية...');
        if (finalPullCursor != null) {
          await settings.copyWith(lastPullCursor: finalPullCursor).save();
          await _recordDeviceSyncState('cloud', finalPullCursor,
              sequence: finalPullSequence, settings: settings);
        }
      }

      if (pulled > 0) {
        onProgress?.call(0.94, 'جارٍ التنظيف بعد المزامنة السحابية...');
        await store.cleanupSoftDeletedRecords();
      }
      if (store.appIdentity.isClient) {
        onProgress?.call(0.97, 'جارٍ تشغيل صيانة سجل مزامنة العميل...');
        await store.compactClientSyncedSyncHistoryForMaintenance();
      }
      if (store.appIdentity.isClient &&
          (restoredSnapshot || pulled > 0) &&
          !store.needsInitialAdminSetup &&
          !initialSnapshotStillUploading) {
        await CloudProvisioningStatus.markComplete(
            message: 'تم تنزيل بيانات المتجر الأولية.');
      }
      return CloudSyncResult(
        ok: true,
        pushed: pushed,
        pulled: pulled,
        restoredSnapshot: restoredSnapshot,
        message:
            'اكتملت المزامنة السحابية. تم إرسال $pushed طلب/طلبات إلى وسيط المضيف، وتم سحب $pulled تغيير/تغييرات معتمدة.',
      );
    } catch (error) {
      return CloudSyncResult(
          ok: false, message: 'فشلت المزامنة السحابية: $error');
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
          'هناك لقطة تهيئة سحابية قيد التنفيذ بالفعل. حاول بعد انتهائها أو استخدم إعادة البناء الإجبارية.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          'فشل رفع جزء Snapshot: ${response.statusCode} ${response.body}');
    }
  }
}
