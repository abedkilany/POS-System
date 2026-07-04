import '../services/cloud_sync_service.dart';
import 'sync_contracts.dart';
import 'sync_device_state.dart';
import 'sync_transport_adapter.dart';

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
            : lower.contains('host snapshot') || lower.contains('snapshot')
                ? UnifiedSyncErrorCode.snapshotUnavailable
                : lower.contains('forbidden') || lower.contains('cannot')
                    ? UnifiedSyncErrorCode.forbiddenRole
                    : lower.contains('required') || lower.contains('invalid')
                        ? UnifiedSyncErrorCode.validationFailed
                        : UnifiedSyncErrorCode.unknown;
    return UnifiedSyncError(
        code: code, userMessage: message, debugMessage: message);
  }

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

  Future<CloudSyncSettings> _settingsForPull() async {
    final identity = _service.store.appIdentity;
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
    if (identity.isClient && baseSequence <= 0 && appliedCursor == null) {
      // Do not reset ACK/sequence while merely preparing pull settings. A real
      // reset is safe only inside the snapshot apply path, after a valid Host
      // snapshot has been downloaded.
      await CloudSyncSettings.clearSavedPullCursor();
      return _settings.copyWith(clearLastPullCursor: true);
    }
    final cursor = _unifiedCursor;
    if (cursor == null || cursor == _settings.lastPullCursor) return _settings;
    return _settings.copyWith(lastPullCursor: cursor);
  }

  CloudSyncSettings _settingsWithUnifiedCursor() {
    final cursor = _unifiedCursor;
    if (cursor == null || cursor == _settings.lastPullCursor) return _settings;
    return _settings.copyWith(lastPullCursor: cursor);
  }

  Future<void> _recordCloudResult(
    DateTime? cursor, {
    int? sequence,
  }) =>
      SyncDeviceStateStore.recordSyncResult(
        _service.store.appIdentity,
        transport: 'cloud',
        appliedCursor: cursor,
        ackCursor: cursor,
        appliedSequence: sequence,
        ackSequence: sequence,
      );

  @override
  UnifiedSyncTransportKind get kind => UnifiedSyncTransportKind.cloud;

  @override
  String get label => 'Cloud';

  @override
  String get deviceId => _service.store.deviceId;

  @override
  String get deviceToken => _service.store.appIdentity.deviceToken;

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
    await _service.publishBootstrapSnapshotToCloud(_settings,
        force: true, onProgress: onProgress);
    final effectiveSettings = _settingsWithUnifiedCursor();
    final result = await _service.syncNow(
      effectiveSettings,
      minSnapshotUpdatedAt: minSnapshotUpdatedAt,
      onProgress: onProgress,
    );
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
  Future<UnifiedPairingCodeResult> createPairingCode(
      {int ttlMinutes = 5}) async {
    if (!_settings.enabled) {
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
    final effectiveSettings = _settingsWithUnifiedCursor();
    final result =
        await _service.pushPendingForUnifiedEngine(effectiveSettings);
    await _recordCloudResult(
      _unifiedCursor,
      sequence: _service.store.latestStoredAuthoritativeSequence,
    );
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
  Future<UnifiedSyncResult> pullChanges(UnifiedSyncPullRequest request) async {
    final effectiveSettings = await _settingsForPull();
    final result = await _service
        .pullAuthoritativeChangesForUnifiedEngine(effectiveSettings);
    final current = CloudSyncSettings.load();
    await _recordCloudResult(
      current.lastPullCursor,
      sequence: SyncDeviceStateStore.lastAppliedSequenceForTransport(
        _service.store.appIdentity,
        'cloud',
      ),
    );
    return UnifiedSyncResult(
      ok: result.ok,
      message: result.message,
      pushed: result.pushed,
      pulled: result.pulled,
      restoredSnapshot: result.restoredSnapshot,
      data: result.syncDeferred
          ? const {'syncDeferred': true}
          : const <String, dynamic>{},
      error: _errorFor(result.ok, result.message),
      cursor: UnifiedCursorEnvelope(
        value: current.lastPullCursor?.toIso8601String() ?? '',
        generatedAt: current.lastPullCursor,
        source: 'device',
      ),
    );
  }

  @override
  Future<UnifiedSyncResult> rebuildFromHostSnapshot(
      {void Function(double value, String label)? onProgress}) async {
    final effectiveSettings = _settingsWithUnifiedCursor();
    final result = await _service.rebuildFromCloudHostSnapshot(
        effectiveSettings,
        onProgress: onProgress);
    await _recordCloudResult(
      _unifiedCursor,
      sequence: SyncDeviceStateStore.lastAppliedSequenceForTransport(
        _service.store.appIdentity,
        'cloud',
      ),
    );
    return UnifiedSyncResult(
      ok: result.ok,
      message: result.message,
      data: result.syncDeferred
          ? const {'syncDeferred': true}
          : const <String, dynamic>{},
      pushed: result.pushed,
      pulled: result.pulled,
      restoredSnapshot: result.restoredSnapshot,
      error: _errorFor(result.ok, result.message),
      cursor: _cursor(),
    );
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
    onProgress?.call(0.08, 'Preparing Cloud sync...');
    final push = await pushPending(
        UnifiedSyncPushRequest(deviceId: deviceId, deviceToken: deviceToken));
    if (!push.ok) {
      onProgress?.call(1.0, 'Cloud sync failed while sending local changes.');
      return push;
    }

    onProgress?.call(0.55, 'Pulling authoritative Cloud changes...');
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
    if (pull.data['syncDeferred'] == true) {
      onProgress?.call(1.0, pull.message);
      return UnifiedSyncResult(
        ok: true,
        message: pull.message,
        pushed: push.pushed,
        pulled: 0,
        restoredSnapshot: false,
        data: const {'syncDeferred': true},
        cursor: pull.cursor,
      );
    }
    if (pull.ok) {
      await compactAfterSuccessfulSync();
      onProgress?.call(1.0, 'Cloud sync completed.');
      return UnifiedSyncResult(
        ok: true,
        message:
            'Cloud sync completed. Pushed ${push.pushed} change(s), pulled ${pull.pulled} change(s).',
        pushed: push.pushed,
        pulled: pull.pulled,
        restoredSnapshot: pull.restoredSnapshot,
        cursor: pull.cursor,
      );
    }

    if (!pull.shouldAttemptSnapshotRepair) {
      onProgress?.call(1.0, 'Cloud pull failed.');
      return UnifiedSyncResult(
        ok: false,
        message: pull.message,
        pushed: push.pushed,
        pulled: pull.pulled,
        error: pull.error,
        cursor: pull.cursor,
      );
    }

    onProgress?.call(0.78, 'Cloud pull failed. Trying snapshot repair...');
    final repair = await rebuildFromHostSnapshot(onProgress: onProgress);
    if (repair.ok) {
      await compactAfterSuccessfulSync();
      return UnifiedSyncResult(
        ok: true,
        message: '${pull.message}. ${repair.message}',
        pushed: push.pushed,
        pulled: repair.pulled,
        restoredSnapshot: true,
        cursor: repair.cursor,
      );
    }
    return UnifiedSyncResult(
      ok: false,
      message: '${pull.message}. ${repair.message}',
      pushed: push.pushed,
      pulled: pull.pulled,
      error: pull.error.hasError ? pull.error : repair.error,
      cursor: pull.cursor,
    );
  }
}
