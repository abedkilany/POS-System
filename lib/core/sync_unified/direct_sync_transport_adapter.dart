import '../services/cloud_sync_service.dart';
import '../services/direct_peer_connection_service.dart';
import '../services/direct_peer_protocol.dart';
import '../services/direct_peer_signaling_service.dart';
import '../services/direct_sync_protocol_service.dart';
import '../services/direct_sync_settings.dart';
import '../services/sync_diagnostics_log.dart';
import '../../data/app_store.dart';
import 'sync_contracts.dart';
import 'sync_device_state.dart';
import 'sync_transport_adapter.dart';
import 'unified_sync_orchestration.dart';

/// Direct transport adapter. The coordination API is used only for pairing
/// and signaling; sync requests are sent through the peer data channel.
class DirectSyncTransportAdapter implements SyncTransportAdapter {
  DirectSyncTransportAdapter(this.store, {DirectSyncSettings? settings})
      : _settings = settings ?? DirectSyncSettings.load(),
        _coordination = DirectPeerSignalingService(store),
        _usesPersistedSettings = settings == null;

  final AppStore store;
  static final Map<String, Future<DirectPeerHostEndpoint>> _hostListeners =
      <String, Future<DirectPeerHostEndpoint>>{};
  DirectSyncSettings _settings;
  final bool _usesPersistedSettings;
  DirectPeerSignalingService _coordination;
  DirectPeerRequestSession? _session;
  Future<DirectPeerRequestSession>? _sessionFuture;
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

  String get _apiBaseUrl {
    final directUrl = _settings.apiBaseUrl.trim();
    if (directUrl.isNotEmpty) return directUrl;
    final savedUrl = CloudSyncSettings.load().apiBaseUrl.trim();
    return savedUrl.isNotEmpty ? savedUrl : CloudSyncSettings.bundledApiBaseUrl;
  }

  CloudSyncSettings get _signalingSettings => CloudSyncSettings(
        enabled: true,
        apiBaseUrl: _apiBaseUrl,
      );

  Future<DirectPeerRequestSession> _clientSession() async {
    final existing = _session;
    if (existing != null) return existing;
    final pending = _sessionFuture;
    if (pending != null) return pending;
    final future = _openClientSession();
    _sessionFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_sessionFuture, future)) _sessionFuture = null;
    }
  }

  Future<DirectPeerRequestSession> _openClientSession() async {
    if (_usesPersistedSettings) _settings = DirectSyncSettings.load();
    if (!_settings.isConfigured) {
      throw StateError('Direct pairing is not configured.');
    }
    try {
      final dynamicIceServers = await _coordination.fetchIceServers(
        DirectPeerSignalingSettings(apiBaseUrl: _apiBaseUrl),
      );
      SyncDiagnosticsLog.add(
          '[DIRECT_ICE] client configured=${_settings.iceServersForApiBaseUrl(_apiBaseUrl).length} dynamic=${dynamicIceServers.length}');
      final connection =
          await DirectPeerConnectionService(store).connectAsClient(
        signalingSettings: DirectPeerSignalingSettings(
          apiBaseUrl: _apiBaseUrl,
        ),
        hostDeviceId: _settings.peerDeviceId,
        iceServers: [
          ..._settings.iceServersForApiBaseUrl(_apiBaseUrl),
          ...dynamicIceServers,
        ],
        iceTransportPolicy: _settings.iceTransportPolicy,
        iceCandidatePoolSize: _settings.iceCandidatePoolSize,
      );
      final session = DirectPeerRequestSession(connection);
      _session = session;
      return session;
    } catch (error) {
      SyncDiagnosticsLog.add(
          '[DIRECT_WEBRTC] client session start failed=$error');
      _session = null;
      rethrow;
    }
  }

  Future<void> _invalidateClientSession(Object error) async {
    SyncDiagnosticsLog.add('[DIRECT_WEBRTC] client session invalidated=$error');
    final session = _session;
    _session = null;
    await session?.close();
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
    SyncDiagnosticsLog.add('[DIRECT_PAIRING] create start ttl=$ttlMinutes');
    if (store.appIdentity.isHost) {
      _startHostListener();
    }
    final result = await CloudSyncService(store).createPairingCode(
      _signalingSettings,
      transport: 'direct',
      ttlMinutes: ttlMinutes,
    );
    SyncDiagnosticsLog.add(
        '[DIRECT_PAIRING] create result ok=${result.ok} transport=direct');
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
    SyncDiagnosticsLog.add('[DIRECT_PAIRING] claim start');
    final result = await CloudSyncService(store).claimPairingCode(
      _signalingSettings,
      code,
      onProgress: onProgress,
    );
    if (result.ok && _usesPersistedSettings) {
      _settings = DirectSyncSettings.load();
    }
    SyncDiagnosticsLog.add(
        '[DIRECT_PAIRING] claim result ok=${result.ok} transport=direct '
        'message=${result.message.replaceAll(RegExp(r'\s+'), ' ').trim()}');
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
    try {
      final session = await _clientSession();
      return await DirectClientSyncService(store, session).pushPending();
    } catch (error) {
      await _invalidateClientSession(error);
      return UnifiedSyncResult(
        ok: false,
        message: 'Direct push connection failed: $error',
        error: const UnifiedSyncError(
          code: UnifiedSyncErrorCode.networkUnavailable,
        ),
        cursor: _cursor(),
      );
    }
  }

  @override
  Future<UnifiedSyncResult> pullChanges(UnifiedSyncPullRequest request) async {
    try {
      final session = await _clientSession();
      return await DirectClientSyncService(store, session).pullChanges();
    } catch (error) {
      await _invalidateClientSession(error);
      return UnifiedSyncResult(
        ok: false,
        message: 'Direct pull connection failed: $error',
        error: const UnifiedSyncError(
          code: UnifiedSyncErrorCode.networkUnavailable,
        ),
        cursor: _cursor(),
      );
    }
  }

  @override
  Future<UnifiedSyncResult> rebuildFromHostSnapshot({
    void Function(double value, String label)? onProgress,
  }) async {
    try {
      final session = await _clientSession();
      return await DirectClientSyncService(store, session)
          .rebuildFromHostSnapshot(
        onProgress: onProgress,
      );
    } catch (error) {
      await _invalidateClientSession(error);
      return UnifiedSyncResult(
        ok: false,
        message: 'Direct snapshot connection failed: $error',
        error: const UnifiedSyncError(
          code: UnifiedSyncErrorCode.networkUnavailable,
        ),
        cursor: _cursor(),
      );
    }
  }

  @override
  Future<void> compactAfterSuccessfulSync() =>
      DirectSyncProtocolMaintenance.compact(store);

  @override
  Future<void> stopHostIfSupported() async {
    final listenerKey = '${store.appIdentity.storeId}:${store.deviceId}';
    _hostListeners.remove(listenerKey);
    await _hostEndpoint?.close();
    _hostEndpoint = null;
    await _session?.close();
    _session = null;
    _sessionFuture = null;
    _coordination.dispose();
    _coordination = DirectPeerSignalingService(store);
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
    if (_usesPersistedSettings) _settings = DirectSyncSettings.load();
    final listenerKey = '${store.appIdentity.storeId}:${store.deviceId}';
    final existingListener = _hostListeners[listenerKey];
    if (existingListener != null) {
      existingListener.then((endpoint) {
        _hostEndpoint ??= endpoint;
      });
      _hostListenerStarting = false;
      return;
    }
    late Future<DirectPeerHostEndpoint> listener;
    listener = () async {
      // Keep one Host listener alive. A temporary WebSocket or WebRTC failure
      // must not make a still-running Host disappear until the next app tick.
      while (store.appIdentity.isHost) {
        try {
          final dynamicIceServers = await _coordination.fetchIceServers(
            DirectPeerSignalingSettings(apiBaseUrl: _apiBaseUrl),
          );
          SyncDiagnosticsLog.add(
              '[DIRECT_ICE] host configured=${_settings.iceServersForApiBaseUrl(_apiBaseUrl).length} dynamic=${dynamicIceServers.length}');
          final connection =
              await DirectPeerConnectionService(store).acceptAsHost(
            signalingSettings: DirectPeerSignalingSettings(
              apiBaseUrl: _signalingSettings.apiBaseUrl,
            ),
            iceServers: [
              ..._settings.iceServersForApiBaseUrl(_apiBaseUrl),
              ...dynamicIceServers,
            ],
            iceTransportPolicy: _settings.iceTransportPolicy,
            iceCandidatePoolSize: _settings.iceCandidatePoolSize,
          );
          return DirectPeerHostEndpoint(
            connection,
            onRequest: DirectHostSyncEndpoint(store).handleRequest,
            onClosed: () {
              if (_hostEndpoint?.connection == connection) {
                _hostEndpoint = null;
                _hostListenerStarting = false;
                if (identical(_hostListeners[listenerKey], listener)) {
                  _hostListeners.remove(listenerKey);
                }
                _startHostListener();
              }
            },
          );
        } catch (error) {
          SyncDiagnosticsLog.add('[DIRECT_WEBRTC] host listener retry=$error');
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
      throw StateError('Direct Host listener stopped.');
    }();
    _hostListeners[listenerKey] = listener;
    listener.then((endpoint) {
      _hostEndpoint = endpoint;
      _hostListenerStarting = false;
    }, onError: (_) {
      _hostListeners.remove(listenerKey);
      _hostListenerStarting = false;
    });
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
