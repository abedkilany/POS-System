import '../services/cloud_sync_service.dart';
import 'unified_sync_orchestration.dart';
import 'unified_sync_policy.dart';
import 'sync_contracts.dart';
import 'sync_device_state.dart';
import 'sync_transport_adapter.dart';
import 'unified_sync_transport_helpers.dart';

/// Cloud adapter shell for Fix 10A.
///
/// It delegates safe operations to the existing CloudSyncService while keeping
/// push/pull internals untouched until Fix 10B/10C.
class CloudSyncTransportAdapter implements SyncTransportAdapter {
  CloudSyncTransportAdapter({
    required CloudSyncService service,
    required CloudSyncSettings settings,
  })  : _service = service,
        _settings = settings;

  final CloudSyncService _service;
  final CloudSyncSettings _settings;

  UnifiedSyncError _errorFor(bool ok, String message) =>
      UnifiedSyncTransportHelpers.classifyError(ok, message);

  DateTime? get _unifiedCursor => SyncDeviceStateStore.cursorForTransport(
        _service.store.appIdentity,
        'cloud',
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

  DateTime? _cursorFromRequest(UnifiedSyncCursor cursor) {
    if (cursor.generatedAt != null) return cursor.generatedAt;
    final value = cursor.value.trim();
    if (value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  CloudSyncSettings _settingsWithCursor(DateTime? cursor) {
    if (cursor == null || cursor == _settings.lastPullCursor) return _settings;
    return _settings.copyWith(lastPullCursor: cursor);
  }

  UnifiedSyncResult _resultFromService(
    CloudSyncResult result, {
    required UnifiedCursorEnvelope cursor,
    required bool includeDeferredFlag,
  }) {
    final isDeferred = includeDeferredFlag && result.syncDeferred;
    if (isDeferred) {
      return UnifiedSyncResultFactory.deferred(
        label: 'Cloud',
        pushed: result.pushed,
        pulled: result.pulled,
        cursor: cursor,
        reason: result.message,
      );
    }
    const data = <String, dynamic>{};
    if (!result.ok) {
      return UnifiedSyncResult(
        ok: false,
        message: result.message,
        pushed: result.pushed,
        pulled: result.pulled,
        restoredSnapshot: result.restoredSnapshot,
        data: data,
        error: _errorFor(result.ok, result.message),
        cursor: cursor,
      );
    }
    return UnifiedSyncResultFactory.success(
      label: 'Cloud',
      pushed: result.pushed,
      pulled: result.pulled,
      restoredSnapshot: result.restoredSnapshot,
      data: data,
      message: result.message,
      cursor: cursor,
    );
  }

  Future<CloudSyncSettings> _settingsForPull(
      UnifiedSyncPullRequest request) async {
    final identity = _service.store.appIdentity;
    final requestCursor = _cursorFromRequest(request.cursor);
    final baseSequence = SyncDeviceStateStore.lastAppliedSequenceForTransport(
      identity,
      'cloud',
    );
    final appliedCursor =
        SyncDeviceStateStore.lastAppliedCursorForTransport(identity, 'cloud');
    // Only scrub the legacy cursor when this client has never established a
    // Cloud baseline yet. Once a rebuild/import has already stored a cursor,
    // keep it even if the sequence is still 0 so the next pull does not loop
    // back into bootstrap again.
    if (identity.isClient &&
        baseSequence <= 0 &&
        appliedCursor == null &&
        requestCursor == null) {
      // Do not reset ACK/sequence while merely preparing pull settings. A real
      // reset is safe only inside the snapshot apply path, after a valid Host
      // snapshot has been downloaded.
      await CloudSyncSettings.clearSavedPullCursor();
      return _settings.copyWith(clearLastPullCursor: true);
    }
    return _settingsWithCursor(requestCursor ?? _unifiedCursor);
  }

  CloudSyncSettings _settingsForPush(UnifiedSyncPushRequest request) {
    return _settingsWithCursor(
        _cursorFromRequest(request.cursor) ?? _unifiedCursor);
  }

  Future<UnifiedSyncResult> _runUnifiedCloudSync({
    void Function(double value, String label)? onProgress,
    String pullFailureMessage = 'Cloud pull failed.',
  }) {
    return runUnifiedSyncOrchestration(
      label: 'Cloud',
      pushRequest:
          UnifiedSyncPushRequest(deviceId: deviceId, deviceToken: deviceToken),
      pushPending: pushPending,
      pullChanges: pullChanges,
      rebuildFromHostSnapshot: rebuildFromHostSnapshot,
      compactAfterSuccessfulSync: compactAfterSuccessfulSync,
      onProgress: onProgress,
      deferPullResult: (pull) => pull.data['syncDeferred'] == true,
      pullFailureMessage: pullFailureMessage,
    );
  }

  @override
  UnifiedSyncTransportKind get kind => UnifiedSyncTransportKind.cloud;

  @override
  String get label => 'Cloud';

  @override
  String get deviceId => _service.store.deviceId;

  @override
  String get deviceToken => _service.store.appIdentity.deviceToken;

  @override
  Future<bool> waitForRealtimeSignal() {
    return _service.waitForRealtimeSignal(_settings);
  }

  @override
  Future<UnifiedSyncResult> testConnection() async {
    final result = await _service.testConnection(_settings);
    return UnifiedSyncResult(
        ok: result.ok,
        message: result.message,
        error: _errorFor(result.ok, result.message),
        cursor: _cursor());
  }

  @override
  Future<UnifiedHostStatus> getHostStatus() async {
    final status = await _service.getHostHeartbeatStatus(_settings);
    return UnifiedHostStatus(
      cloudReachable: status.cloudReachable,
      hostReachable: status.hostReachable,
      message: status.message,
      lastSeenAt: status.lastSeenAt,
    );
  }

  @override
  Future<UnifiedSyncResult> registerCurrentHost({String transport = ''}) async {
    final relay = await _service.ensureHostRelayReady(_settings);
    if (!relay.ok) {
      return UnifiedSyncResult(
        ok: false,
        message: relay.message,
        error: _errorFor(false, relay.message),
      );
    }
    final result = await _service.registerCurrentDevice(_settings,
        transport: transport.trim().isEmpty ? 'cloud' : transport);
    return UnifiedSyncResult(
      ok: result.ok,
      message: result.message,
      pushed: result.pushed,
      pulled: result.pulled,
      restoredSnapshot: result.restoredSnapshot,
      error: _errorFor(result.ok, result.message),
      cursor: _cursor(),
    );
  }

  @override
  Future<UnifiedSyncResult> createInitialHostSnapshot({
    DateTime? minSnapshotUpdatedAt,
    void Function(double value, String label)? onProgress,
  }) async {
    // Cloud uses the same Host-authoritative relay protocol as LAN. The Host
    // keeps the snapshot locally and serves it through the realtime relay;
    // no snapshot is uploaded to the Cloud database.
    return _runUnifiedCloudSync(
      onProgress: onProgress,
      pullFailureMessage: 'Cloud pull failed.',
    );
  }

  @override
  Future<UnifiedPairingCodeResult> createPairingCode(
      {int ttlMinutes = 5}) async {
    if (!UnifiedSyncPolicy.canCreateCloudPairingCode(
      _service.store.appIdentity,
      settingsEnabled: _settings.enabled,
      hasApiBaseUrl: _settings.apiBaseUrl.trim().isNotEmpty,
    )) {
      const message =
          'Enable Cloud Sync and save settings before generating a pairing code.';
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
    final result =
        await _service.createPairingCode(_settings, ttlMinutes: ttlMinutes);
    return UnifiedPairingCodeResult(
      ok: result.ok,
      message: result.message,
      code: result.code,
      expiresAt: result.expiresAt,
      error: _errorFor(result.ok, result.message),
      contract: result.expiresAt == null
          ? null
          : UnifiedPairingContract(
              code: result.code,
              expiresAt: result.expiresAt!,
              transport: 'cloud',
              storeId: result.storeId,
              branchId: result.branchId,
              hostDeviceId: result.hostDeviceId,
              apiBaseUrl: _settings.apiBaseUrl,
            ),
    );
  }

  @override
  Future<UnifiedPairingClaimResult> claimPairingCode(String code,
      {void Function(double value, String label)? onProgress}) async {
    final result = await _service.claimPairingCode(_settings, code,
        onProgress: onProgress);
    return UnifiedPairingClaimResult(
      ok: result.ok,
      message: result.message,
      identity: result.identity,
      error: _errorFor(result.ok, result.message),
      contract: UnifiedPairingClaimContract(
        identity: result.identity,
        storeId: result.identity?.storeId ?? '',
        branchId: result.identity?.branchId ?? '',
        hostDeviceId: result.identity?.hostDeviceId ?? '',
        deviceToken: result.identity?.deviceToken ?? '',
        snapshotAvailable: result.ok,
      ),
    );
  }

  @override
  Future<UnifiedSyncResult> pushPending(UnifiedSyncPushRequest request) async {
    final effectiveSettings = _settingsForPush(request);
    final result =
        await _service.pushPendingForUnifiedEngine(effectiveSettings);
    await _service.recordDeviceSyncState(
      'cloud',
      cursor: effectiveSettings.lastPullCursor ?? _unifiedCursor,
      sequence: _service.store.latestStoredAuthoritativeSequence,
    );
    return _resultFromService(
      result,
      cursor: _cursor(),
      includeDeferredFlag: true,
    );
  }

  @override
  Future<UnifiedSyncResult> pullChanges(UnifiedSyncPullRequest request) async {
    final effectiveSettings = await _settingsForPull(request);
    final result = await _service
        .pullAuthoritativeChangesForUnifiedEngine(effectiveSettings);
    final current = CloudSyncSettings.load();
    await _service.recordDeviceSyncState(
      'cloud',
      cursor: current.lastPullCursor ??
          effectiveSettings.lastPullCursor ??
          _unifiedCursor,
      sequence: SyncDeviceStateStore.lastAppliedSequenceForTransport(
        _service.store.appIdentity,
        'cloud',
      ),
    );
    return _resultFromService(
      result,
      cursor: UnifiedCursorEnvelope(
        value: current.lastPullCursor?.toIso8601String() ?? '',
        generatedAt: current.lastPullCursor,
        source: 'device',
      ),
      includeDeferredFlag: true,
    );
  }

  @override
  Future<UnifiedSyncResult> rebuildFromHostSnapshot(
      {void Function(double value, String label)? onProgress}) async {
    final effectiveSettings = _settingsWithCursor(_unifiedCursor);
    final result = await _service.rebuildFromCloudHostSnapshot(
        effectiveSettings,
        onProgress: onProgress);
    await _service.recordDeviceSyncState(
      'cloud',
      cursor: effectiveSettings.lastPullCursor ?? _unifiedCursor,
      sequence: SyncDeviceStateStore.lastAppliedSequenceForTransport(
        _service.store.appIdentity,
        'cloud',
      ),
    );
    return _resultFromService(
      result,
      cursor: _cursor(),
      includeDeferredFlag: true,
    );
  }

  @override
  Future<void> compactAfterSuccessfulSync() async {
    await _service.compactAfterSuccessfulSync();
  }

  @override
  Future<void> requestFreshHostSnapshotIfSupported({
    DateTime? requestedAt,
  }) async {
    await _service.requestFreshHostSnapshot(
      _settings,
      requestedAt: requestedAt,
    );
  }

  @override
  Future<void> stopHostIfSupported() async {
    await _service.stopHost(_settings);
  }

  @override
  Future<UnifiedSyncResult> syncNow(
      {void Function(double value, String label)? onProgress}) async {
    return _runUnifiedCloudSync(onProgress: onProgress);
  }
}
