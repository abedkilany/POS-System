import '../services/lan_sync_service.dart';
import 'sync_contracts.dart';
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
    final code = lower.contains('expired') || lower.contains('already used')
        ? UnifiedSyncErrorCode.expiredPairingCode
        : lower.contains('snapshot')
            ? UnifiedSyncErrorCode.snapshotUnavailable
            : lower.contains('host devices cannot') || lower.contains('already a cloud client')
                ? UnifiedSyncErrorCode.forbiddenRole
                : lower.contains('not supported') || lower.contains('handled by the existing')
                    ? UnifiedSyncErrorCode.unsupported
                    : UnifiedSyncErrorCode.unknown;
    return UnifiedSyncError(code: code, userMessage: message, debugMessage: message);
  }

  UnifiedCursorEnvelope _cursor() => UnifiedCursorEnvelope(
        value: _settings.lastPullCursor?.toIso8601String() ?? '',
        generatedAt: _settings.lastPullCursor,
        source: 'lan',
      );

  @override
  UnifiedSyncTransportKind get kind => UnifiedSyncTransportKind.lan;

  @override
  String get label => 'LAN';


  Future<void> stopHostIfSupported() => _service.stopHost();

  @override
  Future<UnifiedSyncResult> testConnection() async {
    final result = await _service.testConnection(
      _settings.host,
      port: _settings.port,
      token: _settings.secret,
    );
    return UnifiedSyncResult(ok: result.ok, message: result.message, error: _errorFor(result.ok, result.message), cursor: _cursor());
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
    await _settings.copyWith(
      setupComplete: true,
      hostModeEnabled: true,
      mode: LanSyncDeviceMode.host,
    ).save();
    return const UnifiedSyncResult(
      ok: true,
      message: 'LAN Host prepared through unified sync transport.',
    );
  }

  @override
  Future<UnifiedSyncResult> createInitialHostSnapshot({
    DateTime? minSnapshotUpdatedAt,
    void Function(double value, String label)? onProgress,
  }) async {
    return const UnifiedSyncResult(
      ok: true,
      message: 'LAN initial Host snapshot is served live by the Local Host API.',
      restoredSnapshot: true,
    );
  }

  @override
  Future<UnifiedPairingCodeResult> createPairingCode({int ttlMinutes = 5}) async {
    final code = LanSyncSettings.generatePairingCode();
    final expiresAt = DateTime.now().add(Duration(minutes: ttlMinutes));
    await _settings.copyWith(
      secret: code,
      setupComplete: true,
      hostModeEnabled: true,
      mode: LanSyncDeviceMode.host,
    ).save();
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
  }

  @override
  Future<UnifiedPairingClaimResult> claimPairingCode(String code) async {
    final result = await _service.claimPairingCode(
      _settings.host,
      port: _settings.port,
      code: code,
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
    final result = await _service.syncNow(
      _settings.host,
      port: _settings.port,
      token: _settings.secret,
    );
    return UnifiedSyncResult(ok: result.ok, message: result.message, error: _errorFor(result.ok, result.message), cursor: _cursor());
  }

  @override
  Future<UnifiedSyncResult> pullChanges(UnifiedSyncPullRequest request) async {
    final result = await _service.pullNow(
      _settings.host,
      port: _settings.port,
      token: _settings.secret,
    );
    return UnifiedSyncResult(ok: result.ok, message: result.message, error: _errorFor(result.ok, result.message), cursor: _cursor());
  }

  @override
  Future<UnifiedSyncResult> rebuildFromHostSnapshot({void Function(double value, String label)? onProgress}) async {
    final result = await _service.repairFromHostSnapshot(
      _settings.host,
      port: _settings.port,
      token: _settings.secret,
      onProgress: onProgress,
    );
    return UnifiedSyncResult(ok: result.ok, message: result.message, error: _errorFor(result.ok, result.message), cursor: _cursor());
  }

  @override
  Future<UnifiedSyncResult> syncNow({void Function(double value, String label)? onProgress}) async {
    final result = await _service.syncNow(
      _settings.host,
      port: _settings.port,
      token: _settings.secret,
      onProgress: onProgress,
    );
    return UnifiedSyncResult(ok: result.ok, message: result.message, error: _errorFor(result.ok, result.message), cursor: _cursor());
  }
}
