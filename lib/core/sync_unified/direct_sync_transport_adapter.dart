import 'dart:async';

import '../services/direct_peer_connection_service.dart';
import '../services/direct_peer_pairing_service.dart';
import '../services/direct_peer_protocol.dart';
import '../services/direct_peer_signaling_service.dart';
import '../services/secure_peer_session.dart';
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
        _pairing = DirectPeerPairingService(store),
        _usesPersistedSettings = settings == null;

  final AppStore store;
  DirectSyncSettings _settings;
  final bool _usesPersistedSettings;
  DirectPeerSignalingService _coordination;
  final DirectPeerPairingService _pairing;
  DirectPeerRequestSession? _session;
  Future<DirectPeerRequestSession>? _sessionFuture;
  DirectPeerHostManager? _hostManager;
  final Map<String, DirectPeerHostEndpoint> _hostEndpoints =
      <String, DirectPeerHostEndpoint>{};
  bool _hostListenerStarting = false;
  Future<void>? _hostStartFuture;
  bool _hostRestartScheduled = false;
  bool _hostStopRequested = false;
  StreamSubscription<Map<String, dynamic>>? _clientEventSubscription;
  final Map<String, int> _pendingHostRealtimeSequences = <String, int>{};
  final Map<String, int> _lastAdvertisedSequenceByClient = <String, int>{};
  final Set<String> _drainingHostRealtimeClients = <String>{};
  bool _storeListenerAttached = false;

  void _attachStoreListener() {
    if (_storeListenerAttached) return;
    store.addListener(_onStoreChanged);
    _storeListenerAttached = true;
  }

  void _onStoreChanged() {
    if (!store.appIdentity.isHost || _hostEndpoints.isEmpty) return;
    final sequence = store.latestStoredAuthoritativeSequence;
    if (sequence <= 0) return;
    for (final deviceId in _hostEndpoints.keys) {
      final pending = _pendingHostRealtimeSequences[deviceId] ?? 0;
      if (sequence > pending) {
        _pendingHostRealtimeSequences[deviceId] = sequence;
      }
      unawaited(_drainHostRealtimeEvents(deviceId));
    }
  }

  Future<void> _drainHostRealtimeEvents(String deviceId) async {
    if (!_drainingHostRealtimeClients.add(deviceId)) return;
    try {
      while (true) {
        final endpoint = _hostEndpoints[deviceId];
        final sequence = _pendingHostRealtimeSequences.remove(deviceId);
        if (endpoint == null || sequence == null) break;
        final lastAdvertised = _lastAdvertisedSequenceByClient[deviceId] ?? 0;
        if (sequence <= lastAdvertised) continue;
        try {
          await endpoint.connection.send('sync_changed', {
            'changed': true,
            'latestSequence': sequence,
            'sourceDeviceId': store.deviceId,
          });
          _lastAdvertisedSequenceByClient[deviceId] = sequence;
          SyncDiagnosticsLog.add(
              '[DIRECT_REALTIME] host sync_changed sequence=$sequence client=$deviceId');
        } catch (error) {
          SyncDiagnosticsLog.add(
              '[DIRECT_REALTIME] host event failed sequence=$sequence client=$deviceId error=$error');
        }
      }
    } finally {
      _drainingHostRealtimeClients.remove(deviceId);
      if (_pendingHostRealtimeSequences.containsKey(deviceId)) {
        unawaited(_drainHostRealtimeEvents(deviceId));
      }
    }
  }

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
    return directUrl.isNotEmpty
        ? directUrl
        : DirectSyncSettings.bundledApiBaseUrl;
  }

  DirectPeerSignalingSettings get _signalingSettings =>
      DirectPeerSignalingSettings(apiBaseUrl: _apiBaseUrl);

  DirectSyncSettings get _pairingSettings =>
      _settings.copyWith(apiBaseUrl: _apiBaseUrl);

  Future<DirectPeerRequestSession> _clientSession() async {
    if (store.appIdentity.isHost) {
      throw StateError('Direct Host cannot open a Client session.');
    }
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
    _attachStoreListener();
    if (store.appIdentity.isHost) {
      throw StateError('Direct Host cannot open a Client session.');
    }
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
      _clientEventSubscription = session.events.listen(
        (event) {
          SyncDiagnosticsLog.add(
              '[DIRECT_REALTIME] client event type=${event['type']} '
              'sequence=${event['latestSequence'] ?? '-'}');
        },
        onDone: () {
          if (identical(_session, session)) {
            _session = null;
            _clientEventSubscription = null;
            SyncDiagnosticsLog.add('[DIRECT_REALTIME] client session closed');
          }
        },
      );
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
    await _clientEventSubscription?.cancel();
    _clientEventSubscription = null;
    await session?.close();
  }

  @override
  Future<bool> waitForRealtimeSignal() async {
    if (store.appIdentity.isHost) return false;
    try {
      final session = await _clientSession();
      final completer = Completer<bool>();
      late final StreamSubscription<Map<String, dynamic>> subscription;
      subscription = session.events.listen((event) {
        if (event['type'] != 'sync_changed' || completer.isCompleted) return;
        completer.complete(true);
      }, onDone: () {
        if (!completer.isCompleted) completer.complete(false);
      });
      try {
        return await completer.future.timeout(
          const Duration(seconds: 25),
          onTimeout: () => false,
        );
      } finally {
        await subscription.cancel();
      }
    } catch (error) {
      SyncDiagnosticsLog.add('[DIRECT_REALTIME] wait failed=$error');
      return false;
    }
  }

  @override
  Future<UnifiedSyncResult> testConnection() async {
    if (store.appIdentity.isHost) {
      await _startHostListener();
      return UnifiedSyncResult(
        ok: true,
        message: 'Direct Host is ready for peer connections.',
        cursor: _cursor(),
      );
    }
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
      controlPlaneReachable: false,
      hostReachable: result.ok,
      message: result.message,
      lastSeenAt: result.ok ? DateTime.now() : null,
    );
  }

  @override
  Future<UnifiedSyncResult> registerCurrentHost({String transport = ''}) async {
    _attachStoreListener();
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
    final result = await _pairing.createPairingCode(
      _pairingSettings,
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
    final result = await _pairing.claimPairingCode(
      _pairingSettings,
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
    if (store.appIdentity.isHost) {
      return const UnifiedSyncResult(
        ok: true,
        message: 'Direct Host does not push as a Client.',
      );
    }
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
    if (store.appIdentity.isHost) {
      return const UnifiedSyncResult(
        ok: true,
        message: 'Direct Host does not pull as a Client.',
      );
    }
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
    if (store.appIdentity.isHost) {
      return const UnifiedSyncResult(
        ok: true,
        message: 'Direct Host already owns the authoritative snapshot.',
      );
    }
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
    _hostStopRequested = true;
    _hostRestartScheduled = false;
    await _hostManager?.close();
    _hostManager = null;
    for (final entry in List<MapEntry<String, DirectPeerHostEndpoint>>.from(
        _hostEndpoints.entries)) {
      SyncDeviceStateStore.recordPeerOffline(entry.key);
      await entry.value.close();
    }
    _hostEndpoints.clear();
    _pendingHostRealtimeSequences.clear();
    _lastAdvertisedSequenceByClient.clear();
    _drainingHostRealtimeClients.clear();
    await _session?.close();
    _session = null;
    await _clientEventSubscription?.cancel();
    _clientEventSubscription = null;
    if (_storeListenerAttached) {
      store.removeListener(_onStoreChanged);
      _storeListenerAttached = false;
    }
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

  Future<void> _startHostListener() {
    _attachStoreListener();
    _hostStopRequested = false;
    if (_hostRestartScheduled ||
        _hostListenerStarting ||
        _hostManager != null ||
        !store.appIdentity.isHost) {
      return _hostStartFuture ?? Future<void>.value();
    }
    _hostListenerStarting = true;
    if (_usesPersistedSettings) _settings = DirectSyncSettings.load();
    final future = _openHostManager();
    _hostStartFuture = future;
    return future.whenComplete(() {
      if (identical(_hostStartFuture, future)) {
        _hostStartFuture = null;
      }
    });
  }

  Future<void> _openHostManager() async {
    try {
      final dynamicIceServers = await _coordination.fetchIceServers(
        DirectPeerSignalingSettings(apiBaseUrl: _apiBaseUrl),
      );
      SyncDiagnosticsLog.add(
          '[DIRECT_ICE] host configured=${_settings.iceServersForApiBaseUrl(_apiBaseUrl).length} dynamic=${dynamicIceServers.length}');
      late final DirectPeerHostManager manager;
      manager = DirectPeerHostManager(
        store: store,
        signalingService: _coordination,
        signalingSettings: _signalingSettings,
        iceServers: [
          ..._settings.iceServersForApiBaseUrl(_apiBaseUrl),
          ...dynamicIceServers,
        ],
        iceTransportPolicy: _settings.iceTransportPolicy,
        iceCandidatePoolSize: _settings.iceCandidatePoolSize,
        onAuthenticated: _onHostClientAuthenticated,
        onStopped: () {
          if (identical(_hostManager, manager)) {
            unawaited(_restartHostManager(manager));
          }
        },
      );
      _hostManager = manager;
      await manager.start();
      if (identical(_hostManager, manager) && !_hostRestartScheduled) {
        _hostListenerStarting = false;
      }
    } catch (error) {
      _hostManager = null;
      SyncDiagnosticsLog.add('[DIRECT_WEBRTC] host listener retry=$error');
      _hostListenerStarting = false;
      _scheduleHostRestart();
    }
  }

  void _scheduleHostRestart() {
    if (_hostRestartScheduled ||
        _hostStopRequested ||
        !store.appIdentity.isHost) {
      return;
    }
    _hostRestartScheduled = true;
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (_hostStopRequested || !store.appIdentity.isHost) {
        _hostRestartScheduled = false;
        return;
      }
      _hostRestartScheduled = false;
      _hostListenerStarting = false;
      _startHostListener();
    });
  }

  Future<void> _restartHostManager(DirectPeerHostManager manager) async {
    if (_hostRestartScheduled ||
        _hostStopRequested ||
        !identical(_hostManager, manager)) {
      return;
    }
    _hostRestartScheduled = true;
    _hostListenerStarting = true;
    try {
      await manager.close();
      if (identical(_hostManager, manager)) _hostManager = null;
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!_hostStopRequested && store.appIdentity.isHost) {
        _hostRestartScheduled = false;
        _hostListenerStarting = false;
        _startHostListener();
      }
    } finally {
      if (_hostStopRequested || !store.appIdentity.isHost) {
        _hostRestartScheduled = false;
        _hostListenerStarting = false;
      }
    }
  }

  Future<void> _onHostClientAuthenticated(
      String deviceId, SecurePeerSession connection) async {
    final previous = _hostEndpoints.remove(deviceId);
    await previous?.close();
    _pendingHostRealtimeSequences.remove(deviceId);
    _lastAdvertisedSequenceByClient.remove(deviceId);
    _drainingHostRealtimeClients.remove(deviceId);
    late final DirectPeerHostEndpoint endpoint;
    endpoint = DirectPeerHostEndpoint(
      connection,
      onRequest: DirectHostSyncEndpoint(store).handleRequest,
      onClosed: () {
        if (identical(_hostEndpoints[deviceId], endpoint)) {
          _hostEndpoints.remove(deviceId);
          SyncDeviceStateStore.recordPeerOffline(deviceId);
          _pendingHostRealtimeSequences.remove(deviceId);
          _lastAdvertisedSequenceByClient.remove(deviceId);
          _drainingHostRealtimeClients.remove(deviceId);
        }
      },
    );
    _hostEndpoints[deviceId] = endpoint;
    SyncDeviceStateStore.recordPeerOnline(deviceId);
    SyncDiagnosticsLog.add(
        '[DIRECT_WEBRTC] host client ready device=$deviceId clients=${_hostEndpoints.length}');
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
