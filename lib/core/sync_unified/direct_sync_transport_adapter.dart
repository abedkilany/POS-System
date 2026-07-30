import '../services/cloud_sync_service.dart';
import '../services/direct_peer_connection_service.dart';
import '../services/direct_peer_protocol.dart';
import '../services/direct_peer_signaling_service.dart';
import '../services/direct_sync_protocol_service.dart';
import '../services/direct_sync_settings.dart';
import '../../data/app_store.dart';
import 'sync_contracts.dart';
import 'sync_device_state.dart';
import 'sync_transport_adapter.dart';
import 'unified_sync_orchestration.dart';

/// Direct transport adapter. The coordination API is used only for pairing
/// and signaling; sync requests are sent through the peer data channel.
class DirectSyncTransportAdapter implements SyncTransportAdapter {
  DirectSyncTransportAdapter(this.store, {DirectSyncSettings? settings})
      : _settings = settings ?? DirectSyncSettings.load();

  final AppStore store;
  final DirectSyncSettings _settings;
  DirectPeerRequestSession? _session;
  DirectPeerHostEndpoint? _hostEndpoint;
  bool _hostListenerStarting = false;

  @override
  UnifiedSyncTransportKind get kind => UnifiedSyncTransportKind.direct;

  @override
  String get label => 'Direct';

  @override
  String get deviceId => store.deviceId;

  @override
  String get deviceToken => store.appIdentity.deviceToken;

  CloudSyncSettings get _signalingSettings => CloudSyncSettings.load();

  Future<DirectPeerRequestSession> _clientSession() async {
    final existing = _session;
    if (existing != null) return existing;
    if (!_settings.isConfigured) {
      throw StateError('Direct pairing is not configured.');
    }
    final connection = await DirectPeerConnectionService(store).connectAsClient(
      signalingSettings: DirectPeerSignalingSettings(
        apiBaseUrl: _settings.apiBaseUrl,
      ),
      hostDeviceId: _settings.peerDeviceId,
      iceServers: _settings.iceServers,
    );
    final session = DirectPeerRequestSession(connection);
    _session = session;
    return session;
  }

  @override
  Future<bool> waitForRealtimeSignal() async => false;

  @override
  Future<UnifiedSyncResult> testConnection() async {
    try {
      await _clientSession();
      return UnifiedSyncResult(
        ok: true,
        message: 'Direct connection is ready.',
        cursor: _cursor(),
      );
    } catch (error) {
      return UnifiedSyncResult(
        ok: false,
        message: 'Direct connection failed: $error',
        error: const UnifiedSyncError(
          code: UnifiedSyncErrorCode.networkUnavailable,
        ),
        cursor: _cursor(),
      );
    }
  }

  @override
  Future<UnifiedHostStatus> getHostStatus() async {
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
    _startHostListener();
    return const UnifiedSyncResult(
      ok: true,
      message: 'Direct Host is ready for peer connections.',
    );
  }

  @override
  Future<UnifiedSyncResult> createInitialHostSnapshot({
    DateTime? minSnapshotUpdatedAt,
    void Function(double value, String label)? onProgress,
  }) async =>
      const UnifiedSyncResult(
        ok: true,
        message:
            'Direct Host snapshot will be served through the peer channel.',
      );

  @override
  Future<UnifiedPairingCodeResult> createPairingCode(
      {int ttlMinutes = 5}) async {
    if (store.appIdentity.isHost) {
      _startHostListener();
    }
    final result = await CloudSyncService(store).createPairingCode(
      _signalingSettings,
      transport: 'direct',
      ttlMinutes: ttlMinutes,
    );
    return UnifiedPairingCodeResult(
      ok: result.ok,
      message: result.message,
      code: result.code,
      expiresAt: result.expiresAt,
      contract: result.expiresAt == null
          ? null
          : UnifiedPairingContract(
              code: result.code,
              expiresAt: result.expiresAt!,
              transport: 'direct',
              storeId: result.storeId,
              branchId: result.branchId,
              hostDeviceId: result.hostDeviceId,
              apiBaseUrl: _signalingSettings.apiBaseUrl,
            ),
    );
  }

  @override
  Future<UnifiedPairingClaimResult> claimPairingCode(String code,
      {void Function(double value, String label)? onProgress}) async {
    final result = await CloudSyncService(store).claimPairingCode(
      _signalingSettings,
      code,
      onProgress: onProgress,
    );
    return UnifiedPairingClaimResult(
      ok: result.ok,
      message: result.message,
      identity: result.identity,
      error: result.ok
          ? UnifiedSyncError.none
          : const UnifiedSyncError(
              code: UnifiedSyncErrorCode.invalidPairingCode),
      contract: UnifiedPairingClaimContract(
        identity: result.identity,
        storeId: result.identity?.storeId ?? '',
        branchId: result.identity?.branchId ?? '',
        hostDeviceId: result.identity?.hostDeviceId ?? '',
        deviceToken: result.identity?.deviceToken ?? '',
        snapshotAvailable: false,
      ),
    );
  }

  @override
  Future<UnifiedSyncResult> pushPending(UnifiedSyncPushRequest request) async {
    final session = await _clientSession();
    return DirectClientSyncService(store, session).pushPending();
  }

  @override
  Future<UnifiedSyncResult> pullChanges(UnifiedSyncPullRequest request) async {
    final session = await _clientSession();
    return DirectClientSyncService(store, session).pullChanges();
  }

  @override
  Future<UnifiedSyncResult> rebuildFromHostSnapshot({
    void Function(double value, String label)? onProgress,
  }) async {
    final session = await _clientSession();
    return DirectClientSyncService(store, session).rebuildFromHostSnapshot(
      onProgress: onProgress,
    );
  }

  @override
  Future<void> compactAfterSuccessfulSync() =>
      DirectSyncProtocolMaintenance.compact(store);

  @override
  Future<void> stopHostIfSupported() async {
    await _hostEndpoint?.close();
    _hostEndpoint = null;
    await _session?.close();
    _session = null;
  }

  @override
  Future<void> requestFreshHostSnapshotIfSupported(
      {DateTime? requestedAt}) async {}

  @override
  Future<UnifiedSyncResult> syncNow({
    void Function(double value, String label)? onProgress,
  }) async {
    if (store.appIdentity.isHost) {
      _startHostListener();
      return const UnifiedSyncResult(
        ok: true,
        message: 'Direct Host is ready for peer connections.',
      );
    }
    return runUnifiedSyncOrchestration(
      label: 'Direct',
      pushRequest: UnifiedSyncPushRequest(
        deviceId: deviceId,
        deviceToken: deviceToken,
      ),
      pushPending: pushPending,
      pullChanges: pullChanges,
      rebuildFromHostSnapshot: rebuildFromHostSnapshot,
      compactAfterSuccessfulSync: compactAfterSuccessfulSync,
      onProgress: onProgress,
      pullFailureMessage: 'Direct pull failed. Host may be offline.',
    );
  }

  void _startHostListener() {
    if (_hostListenerStarting ||
        _hostEndpoint != null ||
        !store.appIdentity.isHost) {
      return;
    }
    _hostListenerStarting = true;
    () async {
      try {
        final connection =
            await DirectPeerConnectionService(store).acceptAsHost(
          signalingSettings: DirectPeerSignalingSettings(
            apiBaseUrl: _signalingSettings.apiBaseUrl,
          ),
          iceServers: _settings.iceServers,
        );
        _hostEndpoint = DirectPeerHostEndpoint(
          connection,
          onRequest: DirectHostSyncEndpoint(store).handleRequest,
        );
      } catch (_) {
        // The next registration/sync tick retries the listener.
      } finally {
        _hostListenerStarting = false;
      }
    }();
  }

  UnifiedCursorEnvelope _cursor() {
    final cursor = SyncDeviceStateStore.cursorForTransport(
      store.appIdentity,
      'direct',
      null,
    );
    return UnifiedCursorEnvelope(
      value: cursor?.toIso8601String() ?? '',
      generatedAt: cursor,
      source: 'device',
    );
  }
}

abstract final class DirectSyncProtocolMaintenance {
  static Future<void> compact(AppStore store) async {
    await store.compactClientSyncedSyncHistoryForMaintenance();
  }
}
