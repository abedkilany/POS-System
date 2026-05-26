import '../services/cloud_sync_service.dart';
import 'sync_contracts.dart';
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
    final code = lower.contains('expired') || lower.contains('already used')
        ? UnifiedSyncErrorCode.expiredPairingCode
        : lower.contains('host snapshot') || lower.contains('snapshot')
            ? UnifiedSyncErrorCode.snapshotUnavailable
            : lower.contains('forbidden') || lower.contains('cannot')
                ? UnifiedSyncErrorCode.forbiddenRole
                : lower.contains('required') || lower.contains('invalid')
                    ? UnifiedSyncErrorCode.validationFailed
                    : UnifiedSyncErrorCode.unknown;
    return UnifiedSyncError(code: code, userMessage: message, debugMessage: message);
  }

  UnifiedCursorEnvelope _cursor() => UnifiedCursorEnvelope(
        value: _settings.lastPullCursor?.toIso8601String() ?? '',
        generatedAt: _settings.lastPullCursor,
        source: 'cloud',
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
    return UnifiedSyncResult(ok: result.ok, message: result.message, error: _errorFor(result.ok, result.message), cursor: _cursor());
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
    final result = await _service.registerCurrentDevice(_settings, transport: transport.trim().isEmpty ? 'cloud' : transport);
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
    await _service.store.ensureHostCloudBootstrapSnapshotQueued(force: true);
    final result = await _service.syncNow(
      _settings,
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
  Future<UnifiedPairingCodeResult> createPairingCode({int ttlMinutes = 5}) async {
    final result = await _service.createPairingCode(_settings, ttlMinutes: ttlMinutes);
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
  Future<UnifiedPairingClaimResult> claimPairingCode(String code) async {
    final result = await _service.claimPairingCode(_settings, code);
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
    final result = await _service.pushPendingForUnifiedEngine(_settings);
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
    final result = await _service.pullAuthoritativeChangesForUnifiedEngine(_settings);
    final current = CloudSyncSettings.load();
    return UnifiedSyncResult(
      ok: result.ok,
      message: result.message,
      pushed: result.pushed,
      pulled: result.pulled,
      restoredSnapshot: result.restoredSnapshot,
      error: _errorFor(result.ok, result.message),
      cursor: UnifiedCursorEnvelope(
        value: current.lastPullCursor?.toIso8601String() ?? '',
        generatedAt: current.lastPullCursor,
        source: 'cloud',
      ),
    );
  }

  @override
  Future<UnifiedSyncResult> rebuildFromHostSnapshot({void Function(double value, String label)? onProgress}) async {
    final result = await _service.rebuildFromCloudHostSnapshot(_settings, onProgress: onProgress);
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
  Future<UnifiedSyncResult> syncNow({void Function(double value, String label)? onProgress}) async {
    final result = await _service.syncNow(_settings, onProgress: onProgress);
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
}
