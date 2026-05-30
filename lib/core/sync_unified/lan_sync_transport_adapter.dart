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

  Future<void> _recordLanResult(DateTime? cursor) => SyncDeviceStateStore.recordSyncResult(
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
    try {
      await _service.startHost(port: _settings.port);
      await _settings.copyWith(
        setupComplete: true,
        hostModeEnabled: true,
        mode: LanSyncDeviceMode.host,
      ).save();
      return const UnifiedSyncResult(
        ok: true,
        message: 'LAN Host is active and ready for local devices.',
      );
    } catch (error) {
      final message = 'LAN Host could not start on port ${_settings.port}: $error';
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
      message: 'LAN initial Host snapshot is served live by the Local Host API.',
      restoredSnapshot: true,
    );
  }

  @override
  Future<UnifiedPairingCodeResult> createPairingCode({int ttlMinutes = 5}) async {
    final code = LanSyncSettings.generatePairingCode();
    final expiresAt = DateTime.now().add(Duration(minutes: ttlMinutes));
    try {
      await _service.startHost(port: _settings.port);
      await _settings.copyWith(
        secret: code,
        setupComplete: true,
        hostModeEnabled: true,
        mode: LanSyncDeviceMode.host,
      ).save();
      return UnifiedPairingCodeResult(
        ok: true,
        message: 'LAN pairing code created. LAN Host is active.',
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
      final message = 'LAN Host could not start on port ${_settings.port}: $error';
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
    final effectiveSettings = _settingsWithUnifiedCursor();
    final pendingCount = _service.store.pendingSyncChangesForTarget('host').length;
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
  Future<UnifiedSyncResult> rebuildFromHostSnapshot({void Function(double value, String label)? onProgress}) async {
    final effectiveSettings = _settingsWithUnifiedCursor();
    final result = await _service.repairFromHostSnapshot(
      effectiveSettings.host,
      port: effectiveSettings.port,
      token: effectiveSettings.secret,
      onProgress: onProgress,
    );
    return UnifiedSyncResult(ok: result.ok, message: result.message, error: _errorFor(result.ok, result.message), cursor: _cursor());
  }

  @override
  Future<UnifiedSyncResult> syncNow({void Function(double value, String label)? onProgress}) async {
    final effectiveSettings = _settingsWithUnifiedCursor();
    final result = await _service.syncNow(
      effectiveSettings.host,
      port: effectiveSettings.port,
      token: effectiveSettings.secret,
      onProgress: onProgress,
    );
    final afterSettings = LanSyncSettings.load();
    await _recordLanResult(afterSettings.lastPullCursor);
    return UnifiedSyncResult(ok: result.ok, message: result.message, error: _errorFor(result.ok, result.message), cursor: _cursor());
  }
}
