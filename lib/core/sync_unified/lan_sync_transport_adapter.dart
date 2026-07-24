import '../services/local_database_service.dart';
import '../services/account_auth_service.dart';
import '../services/lan_sync_service.dart';
import 'unified_sync_orchestration.dart';
import 'unified_sync_policy.dart';
import 'sync_contracts.dart';
import 'sync_device_state.dart';
import 'sync_transport_adapter.dart';
import 'unified_sync_transport_helpers.dart';

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

  UnifiedSyncError _errorFor(bool ok, String message) =>
      UnifiedSyncTransportHelpers.classifyError(ok, message);

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

  UnifiedSyncResult _resultFromService(
    LanSyncResult result, {
    required UnifiedCursorEnvelope cursor,
    required int pushed,
    required int pulled,
  }) {
    if (!result.ok) {
      return UnifiedSyncResult(
        ok: false,
        message: result.message,
        pushed: pushed,
        pulled: pulled,
        error: _errorFor(result.ok, result.message),
        cursor: cursor,
      );
    }
    return UnifiedSyncResultFactory.success(
      label: 'LAN',
      pushed: pushed,
      pulled: pulled,
      message: result.message,
      cursor: cursor,
    );
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

  @override
  UnifiedSyncTransportKind get kind => UnifiedSyncTransportKind.lan;

  @override
  String get label => 'LAN';

  @override
  String get deviceId => _service.store.deviceId;

  @override
  String get deviceToken => _service.store.appIdentity.deviceToken;

  @override
  Future<void> stopHostIfSupported() => _service.stopHost();

  @override
  Future<bool> waitForRealtimeSignal() {
    return _service.waitForRealtimeSignal(
      _settings.host,
      port: _settings.port,
      token: _settings.secret,
    );
  }

  @override
  Future<UnifiedSyncResult> testConnection() async {
    final result = await _service.testConnection(
      _settings.host,
      port: _settings.port,
      token: _settings.secret,
    );
    await _service.recordDeviceSyncState('lan', cursor: _unifiedCursor);
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
    final lanEnabled = UnifiedSyncPolicy.canCreateLanPairingCode(
      _service.store.appIdentity,
      setupComplete: savedSettings.setupComplete,
      isHostModeEnabled: savedSettings.isHost,
    );
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
    final effectiveSettings = _settingsWithUnifiedCursor();
    final pendingCount =
        await LocalDatabaseService.pendingSyncQueueCountForTarget(
      'host',
      readyOnly: false,
    );
    final result = await _service.pushPendingOnly(
      effectiveSettings.host,
      port: effectiveSettings.port,
      token: effectiveSettings.secret,
    );
    await _service.recordDeviceSyncState(
      'lan',
      cursor: effectiveSettings.lastPullCursor ?? _unifiedCursor,
      sequence: SyncDeviceStateStore.lastAppliedSequenceForTransport(
        _service.store.appIdentity,
        'lan',
      ),
    );
    return _resultFromService(
      result,
      cursor: _cursor(),
      pushed: result.ok ? pendingCount : 0,
      pulled: 0,
    );
  }

  @override
  Future<UnifiedSyncResult> pullChanges(UnifiedSyncPullRequest request) async {
    final effectiveSettings = _settingsWithUnifiedCursor();
    final before = effectiveSettings.lastPullCursor;
    final result = await _service.pullChangesOnly(
      effectiveSettings.host,
      port: effectiveSettings.port,
      token: effectiveSettings.secret,
    );
    final afterSettings = LanSyncSettings.load();
    final after = afterSettings.lastPullCursor;
    await _service.recordDeviceSyncState(
      'lan',
      cursor: after ?? effectiveSettings.lastPullCursor ?? _unifiedCursor,
      sequence: SyncDeviceStateStore.lastAppliedSequenceForTransport(
        _service.store.appIdentity,
        'lan',
      ),
    );
    final pulled = result.ok && after != null && after != before ? 1 : 0;
    return _resultFromService(
      result,
      cursor: UnifiedCursorEnvelope(
        value: after?.toIso8601String() ?? '',
        generatedAt: after,
        source: 'device',
      ),
      pushed: 0,
      pulled: pulled,
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
    await _service.recordDeviceSyncState(
      'lan',
      cursor: effectiveSettings.lastPullCursor ?? _unifiedCursor,
      sequence: SyncDeviceStateStore.lastAppliedSequenceForTransport(
        _service.store.appIdentity,
        'lan',
      ),
    );
    return _resultFromService(
      result,
      cursor: _cursor(),
      pushed: 0,
      pulled: 0,
    );
  }

  @override
  Future<void> compactAfterSuccessfulSync() async {
    await _service.compactAfterSuccessfulSync();
  }

  @override
  Future<void> requestFreshHostSnapshotIfSupported({
    DateTime? requestedAt,
  }) async {}

  @override
  Future<UnifiedSyncResult> syncNow(
      {void Function(double value, String label)? onProgress}) async {
    if (_service.shouldBypassTransportSyncForHost()) {
      final hostBypass = await UnifiedSyncTransportHelpers.hostSyncBypassResult(
        isHost: true,
        label: 'LAN',
        ensureHostReady: () => _service.startHost(port: _settings.port),
        onProgress: onProgress,
      );
      if (hostBypass != null) return hostBypass;
    }

    return runUnifiedSyncOrchestration(
      label: 'LAN',
      pushRequest:
          UnifiedSyncPushRequest(deviceId: deviceId, deviceToken: deviceToken),
      pushPending: pushPending,
      pullChanges: pullChanges,
      rebuildFromHostSnapshot: rebuildFromHostSnapshot,
      compactAfterSuccessfulSync: compactAfterSuccessfulSync,
      onProgress: onProgress,
      pullFailureMessage: 'LAN pull failed. Host may be offline.',
    );
  }
}
