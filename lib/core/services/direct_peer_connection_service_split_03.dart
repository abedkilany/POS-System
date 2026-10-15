part of 'direct_peer_connection_service.dart';

/// Long-lived Host-side signaling listener. One signaling WebSocket can carry
/// offers for many Clients; each Client gets its own RTCPeerConnection.
class DirectPeerHostManager {
  DirectPeerHostManager({
    required this.store,
    required this.signalingService,
    required this.signalingSettings,
    required this.iceServers,
    required this.iceTransportPolicy,
    required this.iceCandidatePoolSize,
    required this.onAuthenticated,
    this.onStopped,
  });

  final AppStore store;
  final DirectPeerSignalingService signalingService;
  final DirectPeerSignalingSettings signalingSettings;
  final List<Map<String, dynamic>> iceServers;
  final String iceTransportPolicy;
  final int iceCandidatePoolSize;
  final Future<void> Function(String deviceId, SecurePeerSession connection)
      onAuthenticated;
  final void Function()? onStopped;

  final Map<String, _DirectHostPeerState> _peers =
      <String, _DirectHostPeerState>{};
  final Map<String, List<Object?>> _pendingCandidatesByDevice =
      <String, List<Object?>>{};
  final Set<Future<void>> _inFlightSignals = <Future<void>>{};
  DirectPeerSignalingSession? _signaling;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _closed = false;
  Future<void>? _startFuture;

  Future<void> start() {
    final existing = _startFuture;
    if (existing != null) return existing;
    final future = _start();
    _startFuture = future;
    return future;
  }

  Future<void> _start() async {
    _signaling = await signalingService.open(signalingSettings);
    final signaling = _signaling!;
    _subscription = signaling.signals.listen(
      (signal) {
        late final Future<void> handler;
        handler = _handleSignal(signal);
        _inFlightSignals.add(handler);
        unawaited(handler.whenComplete(() => _inFlightSignals.remove(handler)));
      },
      onError: (Object error, StackTrace stack) {
        SyncDiagnosticsLog.add(
            '[DIRECT_WEBRTC] host manager signal error=$error');
      },
      onDone: () {
        SyncDiagnosticsLog.add('[DIRECT_SIGNAL] host manager websocket closed');
        if (!_closed) onStopped?.call();
      },
    );
    SyncDiagnosticsLog.add('[DIRECT_WEBRTC] host manager listening');
  }

  Future<void> _handleSignal(Map<String, dynamic> signal) async {
    if (_closed) return;
    final targetDeviceId = signal['targetDeviceId']?.toString().trim() ?? '';
    final hostDeviceId = store.sync.deviceId.trim();
    // The coordination service may deliver a signal to every WebSocket
    // session belonging to the pairing. A Host must process only signals
    // addressed to this Host; otherwise echoed offers or another session's
    // traffic can create a peer for the wrong device.
    if (targetDeviceId.isNotEmpty &&
        hostDeviceId.isNotEmpty &&
        targetDeviceId != hostDeviceId) {
      return;
    }
    final deviceId = signal['sourceDeviceId']?.toString().trim() ?? '';
    if (deviceId.isEmpty || deviceId == hostDeviceId) return;
    final kind = signal['kind']?.toString() ?? '';
    var peer = _peers[deviceId];
    try {
      if (kind == 'offer') {
        final pendingCandidates =
            _pendingCandidatesByDevice.remove(deviceId) ?? <Object?>[];
        if (peer != null) {
          SyncDiagnosticsLog.add(
              '[DIRECT_WEBRTC] replacing stale Host peer device=$deviceId');
          await _removePeer(deviceId, peer);
        }
        peer = await _createPeer(deviceId);
        _peers[deviceId] = peer;
        // Candidates can arrive before the offer over the signaling socket.
        // Replay them into the per-client peer; the peer state queues them
        // until its remote description is installed.
        for (final candidate in pendingCandidates) {
          await peer.handleCandidate(candidate);
        }
      }
      final currentPeer = peer;
      if (currentPeer == null) {
        if (kind == 'candidate') {
          final pending = _pendingCandidatesByDevice.putIfAbsent(
              deviceId, () => <Object?>[]);
          if (pending.length < 64) {
            pending.add(signal['candidate']);
          }
          SyncDiagnosticsLog.add(
              '[DIRECT_ICE] host candidate queued before offer device=$deviceId count=${pending.length}');
        }
        return;
      }
      if (kind == 'offer') {
        await currentPeer.handleOffer(signal);
      } else if (kind == 'candidate') {
        await currentPeer.handleCandidate(signal['candidate']);
      }
    } catch (error) {
      SyncDiagnosticsLog.add(
          '[DIRECT_WEBRTC] host peer signal failed device=$deviceId error=$error');
      final currentPeer = _peers[deviceId];
      if (currentPeer != null) await _removePeer(deviceId, currentPeer);
    }
  }

  Future<_DirectHostPeerState> _createPeer(String deviceId) async {
    final signaling = _signaling!;
    final peerConnection = await createPeerConnection({
      'iceServers': iceServers,
      'iceTransportPolicy': iceTransportPolicy,
      'iceCandidatePoolSize': iceCandidatePoolSize.clamp(0, 16),
    });
    if (_closed) {
      await peerConnection.close();
      throw StateError('Direct Host listener is closing.');
    }
    final state = _DirectHostPeerState(
      store: store,
      deviceId: deviceId,
      peerConnection: peerConnection,
      signaling: signaling,
      iceServers: iceServers,
      onAuthenticated: (connection) => onAuthenticated(deviceId, connection),
      onClosed: () async {
        final current = _peers[deviceId];
        if (current != null) await _removePeer(deviceId, current);
      },
    );
    await state.initialize();
    return state;
  }

  Future<void> _removePeer(String deviceId, _DirectHostPeerState peer) async {
    if (identical(_peers[deviceId], peer)) _peers.remove(deviceId);
    _pendingCandidatesByDevice.remove(deviceId);
    await peer.close();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    if (_inFlightSignals.isNotEmpty) {
      await Future.wait(List<Future<void>>.from(_inFlightSignals));
    }
    for (final entry
        in List<MapEntry<String, _DirectHostPeerState>>.from(_peers.entries)) {
      await _removePeer(entry.key, entry.value);
    }
    _peers.clear();
    _pendingCandidatesByDevice.clear();
    await _signaling?.close();
    _signaling = null;
  }
}

class _DirectHostPeerState {
  _DirectHostPeerState({
    required this.store,
    required this.deviceId,
    required this.peerConnection,
    required this.signaling,
    required this.iceServers,
    required this.onAuthenticated,
    required this.onClosed,
  });

  final AppStore store;
  final String deviceId;
  final RTCPeerConnection peerConnection;
  final DirectPeerSignalingSession signaling;
  final List<Map<String, dynamic>> iceServers;
  final Future<void> Function(SecurePeerSession connection) onAuthenticated;
  final Future<void> Function() onClosed;
  final List<RTCIceCandidate> _pendingCandidates = <RTCIceCandidate>[];
  DirectPeerConnection? _connection;
  bool _remoteDescriptionSet = false;
  bool _authenticationStarted = false;
  bool _closed = false;

  Future<void> initialize() async {
    peerConnection.onIceCandidate = (candidate) {
      signaling.send({
        'kind': 'candidate',
        'targetDeviceId': deviceId,
        'candidate': candidate.toMap(),
      });
    };
    peerConnection.onDataChannel = (channel) {
      _connection ??= DirectPeerConnection(
        peerConnection: peerConnection,
        signaling: signaling,
        dataChannel: channel,
        closeSignalingOnClose: false,
      );
      SyncDiagnosticsLog.add(
          '[DIRECT_WEBRTC] host data channel received device=$deviceId state=${channel.state}');
      if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
        unawaited(_authenticate());
      }
      channel.onDataChannelState = (state) {
        SyncDiagnosticsLog.add(
            '[DIRECT_WEBRTC] host data channel device=$deviceId state=$state');
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          unawaited(_authenticate());
        } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
          unawaited(onClosed());
        }
      };
    };
    peerConnection.onConnectionState = (state) {
      SyncDiagnosticsLog.add(
          '[DIRECT_WEBRTC] host peer device=$deviceId state=$state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        unawaited(onClosed());
      }
    };
  }

  Future<void> handleOffer(Map<String, dynamic> signal) async {
    final description = Map<String, dynamic>.from(
        (signal['description'] as Map?) ?? const <String, dynamic>{});
    await peerConnection.setRemoteDescription(RTCSessionDescription(
      description['sdp']?.toString(),
      description['type']?.toString(),
    ));
    _remoteDescriptionSet = true;
    for (final candidate in _pendingCandidates) {
      await peerConnection.addCandidate(candidate);
    }
    _pendingCandidates.clear();
    final answer = await peerConnection.createAnswer({});
    await peerConnection.setLocalDescription(answer);
    await _waitForIceGatheringComplete(peerConnection);
    final localAnswer = await peerConnection.getLocalDescription() ?? answer;
    SyncDiagnosticsLog.add(
        '[DIRECT_ICE] host answer device=$deviceId candidates=${_candidateCount(localAnswer.sdp)}');
    signaling.send({
      'kind': 'answer',
      'targetDeviceId': deviceId,
      'description': localAnswer.toMap(),
    });
    if (_connection?.dataChannel?.state ==
        RTCDataChannelState.RTCDataChannelOpen) {
      await _authenticate();
    }
  }

  Future<void> handleCandidate(Object? raw) async {
    if (_closed) return;
    final candidate = _candidateFromJson(raw);
    if (candidate == null) return;
    if (_remoteDescriptionSet) {
      await peerConnection.addCandidate(candidate);
    } else {
      _pendingCandidates.add(candidate);
    }
  }

  Future<void> _authenticate() async {
    if (_authenticationStarted || _connection == null || _closed) return;
    _authenticationStarted = true;
    try {
      final material = await DirectPeerHandshake.authenticateHost(
        session: _connection!,
        identity: store.runtime.identity,
        expectedClientDeviceId: deviceId,
      );
      if (_closed) return;
      await onAuthenticated(AuthenticatedPeerSession(
        inner: _connection!,
        sessionId: material.sessionId,
        sessionKey: material.sessionKey,
        expiresAt: material.expiresAt,
      ));
    } catch (error) {
      SyncDiagnosticsLog.add(
          '[DIRECT_HANDSHAKE] host authentication failed device=$deviceId error=$error');
      await onClosed();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _connection?.close();
    if (_connection == null) await peerConnection.close();
  }

  static Future<void> _waitForIceGatheringComplete(
    RTCPeerConnection peer,
  ) async {
    final current = await peer.getIceGatheringState();
    if (current == RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }
    final completed = Completer<void>();
    final previous = peer.onIceGatheringState;
    peer.onIceGatheringState = (state) {
      previous?.call(state);
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !completed.isCompleted) {
        completed.complete();
      }
    };
    try {
      await completed.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // Trickle candidates already sent are still usable.
    }
  }

  static RTCIceCandidate? _candidateFromJson(Object? raw) {
    if (raw is! Map) return null;
    final candidate = raw['candidate']?.toString();
    if (candidate == null || candidate.isEmpty) return null;
    return RTCIceCandidate(
      candidate,
      raw['sdpMid']?.toString(),
      int.tryParse(raw['sdpMLineIndex']?.toString() ?? ''),
    );
  }

  static int _candidateCount(String? sdp) =>
      RegExp(r'^a=candidate:', multiLine: true).allMatches(sdp ?? '').length;
}
