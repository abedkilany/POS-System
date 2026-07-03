import '../services/account_auth_service.dart';
import '../services/lan_sync_service.dart';
import 'sync_contracts.dart';
import 'sync_device_state.dart';
import 'sync_transport_adapter.dart';

/// LAN adapter shell for Fix 10A.
///
/// It delegates to the current LAN service without changing the existing LAN
/// protocol. Later phases will normalize its contracts with Cloud.
class LanSyncTransportAdapter implements SyncTransportAdapter {
  LanSyncTransportAdapter({
    required LanSyncService service,
    required LanSyncSettings settings,
  })  : _service = service,
        _settings = settings;

  final LanSyncService _service;
  final LanSyncSettings _settings;

  UnifiedSyncError _errorFor(bool ok, String message) {
    if (ok) return UnifiedSyncError.none;
    final lower = message.toLowerCase();
    final code = lower.contains('socketexception') ||
            lower.contains('timeoutexception') ||
            lower.contains('connection refused') ||
            lower.contains('failed host lookup') ||
            lower.contains('network is unreachable') ||
            lower.contains('no route to host') ||
            lower.contains('connection reset by peer') ||
            lower.contains('broken pipe') ||
            lower.contains('econnrefused') ||
            lower.contains('connection closed') ||
            lower.contains('host offline')
        ? UnifiedSyncErrorCode.networkUnavailable
        : lower.contains('expired') || lower.contains('already used')
            ? UnifiedSyncErrorCode.expiredPairingCode
            : lower.contains('snapshot')
                ? UnifiedSyncErrorCode.snapshotUnavailable
                : lower.contains('host devices cannot') ||
                        lower.contains('already a cloud client')
                    ? UnifiedSyncErrorCode.forbiddenRole
                    : lower.contains('not supported') ||
                            lower.contains('handled by the existing')
                        ? UnifiedSyncErrorCode.unsupported
                        : UnifiedSyncErrorCode.unknown;
    return UnifiedSyncError(
        code: code, userMessage: message, debugMessage: message);
  }

  DateTime? get _unifiedCursor => SyncDeviceStateStore.cursorForTransport(
        _service.store.appIdentity,
        'lan',
        _settings.lastPullCursor,
      );

  UnifiedCursorEnvelope _cursor() {
    final cursor = _unifiedCursor;
    return UnifiedCursorEnvelope(
      value: cursor?.toIso8601String() ?? '',
      generatedAt: cursor,
      source: 'device',
    );
  }

  LanSyncSettings _settingsWithUnifiedCursor() {
    final cursor = _unifiedCursor;
    if (cursor == null || cursor == _settings.lastPullCursor) return _settings;
    return _settings.copyWith(lastPullCursor: cursor);
  }

  bool _clientDeviceLimitReached(LanSyncSettings settings) {
    final allowed = AccountAuthCache.load()?.devicesLimit;
    if (allowed == null) return false;
    final normalizedAllowed = allowed < 0 ? 0 : allowed;
    final hostDeviceId = _service.store.deviceId.trim();
    final linked = settings.hostRegistry.values.where((device) {
      final id = device.clientDeviceId.trim();
      if (id.isEmpty || id == hostDeviceId) return false;
      return device.isActive;
    }).length;
    return linked >= normalizedAllowed;
  }

  Future<void> _recordLanResult(DateTime? cursor) =>
      SyncDeviceStateStore.recordSyncResult(
        _service.store.appIdentity,
        transport: 'lan',
        appliedCursor: cursor,
        ackCursor: cursor,
      );

  @override
  UnifiedSyncTransportKind get kind => UnifiedSyncTransportKind.lan;

  @override
  String get label => 'LAN';

  @override
  String get deviceId => _service.store.deviceId;

  @override
  String get deviceToken => _service.store.appIdentity.deviceToken;

  Future<void> stopHostIfSupported() => _service.stopHost();

  @override
  Future<UnifiedSyncResult> testConnection() async {
    final result = await _service.testConnection(
      _settings.host,
      port: _settings.port,
      token: _settings.secret,
    );
    await _recordLanResult(_unifiedCursor);
    return UnifiedSyncResult(
        ok: result.ok,
        message: result.message,
        error: _errorFor(result.ok, result.message),
        cursor: _cursor());
  }

  @override
  Future<UnifiedHostStatus> getHostStatus() async {
    if (_settings.isHost) {
      return const UnifiedHostStatus(
        cloudReachable: false,
        hostReachable: true,
        message: 'This device is the LAN Host.',
      );
    }
    final result = await testConnection();
    return UnifiedHostStatus(
      cloudReachable: false,
      hostReachable: result.ok,
      message: result.message,
      lastSeenAt: result.ok ? DateTime.now() : null,
    );
  }

  @override
  Future<UnifiedSyncResult> registerCurrentHost({String transport = ''}) async {
    try {
      await _service.startHost(port: _settings.port);
      final migratedSettings = LanSyncSettings.load();
      await migratedSettings
          .copyWith(
            setupComplete: true,
            hostModeEnabled: true,
            mode: LanSyncDeviceMode.host,
          )
          .save();
      return const UnifiedSyncResult(
        ok: true,
        message: 'LAN Host is active and ready for local devices.',
      );
    } catch (error) {
      final message =
          'LAN Host could not start on port ${_settings.port}: $error';
      return UnifiedSyncResult(
        ok: false,
        message: message,
        error: UnifiedSyncError(
          code: UnifiedSyncErrorCode.unknown,
          userMessage: message,
          debugMessage: message,
        ),
      );
    }
  }

  @override
  Future<UnifiedSyncResult> createInitialHostSnapshot({
    DateTime? minSnapshotUpdatedAt,
    void Function(double value, String label)? onProgress,
  }) async {
    return const UnifiedSyncResult(
      ok: true,
      message:
          'LAN initial Host snapshot is served live by the Local Host API.',
      restoredSnapshot: true,
    );
  }

  @override
  Future<UnifiedPairingCodeResult> createPairingCode(
      {int ttlMinutes = 5}) async {
    final savedSettings = LanSyncSettings.load();
    final lanEnabled = _service.store.appIdentity.isHost &&
        savedSettings.setupComplete &&
        savedSettings.isHost;
    if (!lanEnabled) {
      const message =
          'Enable LAN Sync and save settings before generating a pairing code.';
      return const UnifiedPairingCodeResult(
        ok: false,
        message: message,
        error: UnifiedSyncError(
          code: UnifiedSyncErrorCode.forbiddenRole,
          userMessage: message,
          debugMessage: message,
        ),
      );
    }
    if (_clientDeviceLimitReached(savedSettings)) {
      const message =
          'You have reached the maximum number of devices allowed by your subscription. To add more devices, please contact Ventio Support.';
      return const UnifiedPairingCodeResult(
        ok: false,
        message: message,
        error: UnifiedSyncError(
          code: UnifiedSyncErrorCode.forbiddenRole,
          userMessage: message,
          debugMessage: message,
        ),
      );
    }

    final code = LanSyncSettings.generatePairingCode();
    final expiresAt = DateTime.now().add(Duration(minutes: ttlMinutes));
    try {
      await _service.startHost(port: _settings.port);
      final migratedSettings =
          savedSettings.withMigratedHostRegistry(_service.store.deviceId);
      await migratedSettings.copyWith(secret: code).save();
      return UnifiedPairingCodeResult(
        ok: true,
        message: 'LAN pairing code created.',
        code: code,
        expiresAt: expiresAt,
        contract: UnifiedPairingContract(
          code: code,
          expiresAt: expiresAt,
          transport: 'lan',
          storeId: _service.store.appIdentity.storeId,
          branchId: _service.store.appIdentity.branchId,
          hostDeviceId: _service.store.deviceId,
          host: _settings.host,
          port: _settings.port,
        ),
      );
    } catch (error) {
      final message =
          'LAN Host could not start on port ${_settings.port}: $error';
      return UnifiedPairingCodeResult(
        ok: false,
        message: message,
        error: UnifiedSyncError(
          code: UnifiedSyncErrorCode.unknown,
          userMessage: message,
          debugMessage: message,
        ),
      );
    }
  }

  @override
  Future<UnifiedPairingClaimResult> claimPairingCode(String code,
      {void Function(double value, String label)? onProgress}) async {
    final result = await _service.claimPairingCode(
      _settings.host,
      port: _settings.port,
      code: code,
      onProgress: onProgress,
    );
    return UnifiedPairingClaimResult(
      ok: result.ok,
      message: result.message,
      error: _errorFor(result.ok, result.message),
      contract: UnifiedPairingClaimContract(snapshotAvailable: result.ok),
    );
  }

  @override
  Future<UnifiedSyncResult> pushPending(UnifiedSyncPushRequest request) async {
    await _service.store.ensureSyncDataLoaded();
    final effectiveSettings = _settingsWithUnifiedCursor();
    final pendingCount =
        _service.store.pendingSyncChangesForTarget('host').length;
    final result = await _service.pushPendingOnly(
      effectiveSettings.host,
      port: effectiveSettings.port,
      token: effectiveSettings.secret,
    );
    return UnifiedSyncResult(
      ok: result.ok,
      message: result.message,
      pushed: result.ok ? pendingCount : 0,
      error: _errorFor(result.ok, result.message),
      cursor: _cursor(),
    );
  }

  @override
  Future<UnifiedSyncResult> pullChanges(UnifiedSyncPullRequest request) async {
    await _service.store.ensureSyncDataLoaded();
    final effectiveSettings = _settingsWithUnifiedCursor();
    final before = effectiveSettings.lastPullCursor;
    final result = await _service.pullChangesOnly(
      effectiveSettings.host,
      port: effectiveSettings.port,
      token: effectiveSettings.secret,
    );
    final afterSettings = LanSyncSettings.load();
    final after = afterSettings.lastPullCursor;
    await _recordLanResult(after);
    final pulled = result.ok && after != null && after != before ? 1 : 0;
    return UnifiedSyncResult(
      ok: result.ok,
      message: result.message,
      pulled: pulled,
      error: _errorFor(result.ok, result.message),
      cursor: UnifiedCursorEnvelope(
        value: after?.toIso8601String() ?? '',
        generatedAt: after,
        source: 'device',
      ),
    );
  }

  @override
  Future<UnifiedSyncResult> rebuildFromHostSnapshot(
      {void Function(double value, String label)? onProgress}) async {
    final effectiveSettings = _settingsWithUnifiedCursor();
    final result = await _service.repairFromHostSnapshot(
      effectiveSettings.host,
      port: effectiveSettings.port,
      token: effectiveSettings.secret,
      onProgress: onProgress,
    );
    return UnifiedSyncResult(
        ok: result.ok,
        message: result.message,
        error: _errorFor(result.ok, result.message),
        cursor: _cursor());
  }

  @override
  Future<void> compactAfterSuccessfulSync() async {
    try {
      final identity = _service.store.appIdentity;
      if (identity.isHost) {
        await _service.store.compactSyncedSyncHistoryForMaintenance();
      } else if (identity.isClient) {
        await _service.store.compactClientSyncedSyncHistoryForMaintenance();
      }
    } catch (_) {
      // Best-effort maintenance: never fail a successful sync because local
      // compaction failed.
    }
  }

  @override
  Future<UnifiedSyncResult> syncNow(
      {void Function(double value, String label)? onProgress}) async {
    if (_service.store.appIdentity.isHost || _settings.isHost) {
      onProgress?.call(
          1.0, 'LAN Host is active. Host devices do not run LAN client sync.');
      try {
        await _service.startHost(port: _settings.port);
      } catch (_) {
        // Keep this guard non-fatal: the caller may only be trying to avoid the
        // invalid Host-as-client pull flow. Host start errors are shown by the
        // dedicated LAN setup/status actions.
      }
      return const UnifiedSyncResult(
        ok: true,
        message: 'LAN Host active. Skipped LAN client push/pull on Host.',
      );
    }

    onProgress?.call(0.08, 'Preparing LAN sync...');
    final push = await pushPending(
        UnifiedSyncPushRequest(deviceId: deviceId, deviceToken: deviceToken));
    if (!push.ok) {
      onProgress?.call(1.0, 'LAN sync failed while sending local changes.');
      return push;
    }

    onProgress?.call(0.55, 'Pulling authoritative LAN changes...');
    final pull = await pullChanges(
      UnifiedSyncPullRequest(
        deviceId: deviceId,
        deviceToken: deviceToken,
        cursor: UnifiedSyncCursor(
          value: push.cursor.value,
          generatedAt: push.cursor.generatedAt,
          source: push.cursor.source,
        ),
      ),
    );
    if (pull.ok) {
      await compactAfterSuccessfulSync();
      onProgress?.call(1.0, 'LAN sync completed.');
      return UnifiedSyncResult(
        ok: true,
        message:
            'LAN sync completed. Pushed ${push.pushed} change(s), pulled ${pull.pulled} change(s).',
        pushed: push.pushed,
        pulled: pull.pulled,
        restoredSnapshot: pull.restoredSnapshot,
        cursor: pull.cursor,
      );
    }

    onProgress?.call(1.0, 'LAN pull failed. Host may be offline.');
    return UnifiedSyncResult(
      ok: false,
      message: pull.message,
      pushed: push.pushed,
      pulled: pull.pulled,
      error: pull.error,
      cursor: pull.cursor,
    );
  }
}
