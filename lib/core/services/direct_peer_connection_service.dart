import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../data/app_store.dart';
import 'authenticated_peer_session.dart';
import 'direct_peer_handshake.dart';
import 'direct_peer_signaling_service.dart';
import 'secure_peer_session.dart';
import 'sync_diagnostics_log.dart';

/// A direct, encrypted data connection between one Host and one Client.
///
/// The signaling WebSocket is used only for offer/answer/candidate messages.
/// Application sync frames are sent through the WebRTC data channel after it
/// becomes connected.
class DirectPeerConnection implements SecurePeerSession {
  static const int _maxDataChannelPayloadBytes = 6000;

  DirectPeerConnection({
    required this.peerConnection,
    required this.signaling,
    required RTCDataChannel dataChannel,
    this.closeSignalingOnClose = true,
  }) {
    this.dataChannel = dataChannel;
    _bindDataChannel(dataChannel);
  }

  final RTCPeerConnection peerConnection;
  final DirectPeerSignalingSession signaling;
  final bool closeSignalingOnClose;
  RTCDataChannel? dataChannel;
  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _signalSubscription;
  final Map<String, List<String?>> _incomingFragments =
      <String, List<String?>>{};
  Future<void> _sendTail = Future<void>.value();
  int _sendQueueDepth = 0;
  int _maxSendQueueDepth = 0;
  int _fragmentCounter = 0;
  bool _closed = false;

  @override
  String get transportType => 'direct';

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  @override
  Future<void> send(String type, Map<String, dynamic> payload) async {
    final queuedAt = Stopwatch()..start();
    _sendQueueDepth++;
    if (_sendQueueDepth > _maxSendQueueDepth) {
      _maxSendQueueDepth = _sendQueueDepth;
    }
    final operation = Completer<void>();
    final previous = _sendTail;
    _sendTail = operation.future;
    try {
      await previous;
      final queueWaitMs = queuedAt.elapsedMilliseconds;
      if (queueWaitMs >= 100 || _sendQueueDepth >= 8) {
        SyncDiagnosticsLog.add(
            '[DIRECT_QUEUE] data send type=$type queueWaitMs=$queueWaitMs depth=$_sendQueueDepth maxDepth=$_maxSendQueueDepth');
      }
      final channel = dataChannel;
      if (channel == null ||
          channel.state != RTCDataChannelState.RTCDataChannelOpen) {
        throw StateError('Direct data channel is not open.');
      }
      if (type.startsWith('direct_handshake_')) {
        SyncDiagnosticsLog.add('[DIRECT_HANDSHAKE] send type=$type');
      }
      final encoded = utf8.encode(jsonEncode({
        'type': type,
        ...payload,
      }));
      if (encoded.length <= _maxDataChannelPayloadBytes) {
        await channel.send(RTCDataChannelMessage(utf8.decode(encoded)));
        return;
      }

      _fragmentCounter++;
      final fragmentId =
          'fragment-${DateTime.now().microsecondsSinceEpoch}-$_fragmentCounter';
      final total = (encoded.length + _maxDataChannelPayloadBytes - 1) ~/
          _maxDataChannelPayloadBytes;
      SyncDiagnosticsLog.add(
          '[DIRECT_DATA] send fragmented type=$type bytes=${encoded.length} fragments=$total');
      for (var index = 0; index < total; index++) {
        final start = index * _maxDataChannelPayloadBytes;
        final end = (start + _maxDataChannelPayloadBytes).clamp(
          0,
          encoded.length,
        );
        final fragment = <String, dynamic>{
          'type': 'direct_fragment',
          'fragmentId': fragmentId,
          'index': index,
          'total': total,
          'data': base64Encode(encoded.sublist(start, end)),
        };
        await channel.send(RTCDataChannelMessage(jsonEncode(fragment)));
      }
    } finally {
      _sendQueueDepth--;
      operation.complete();
    }
  }

  void _bindDataChannel(RTCDataChannel channel) {
    dataChannel = channel;
    channel.onMessage = (message) {
      if (_closed || message.isBinary) return;
      try {
        final decoded = jsonDecode(message.text);
        if (decoded is Map) {
          final packet = Map<String, dynamic>.from(decoded);
          final packetType = packet['type']?.toString() ?? '-';
          if (packetType == 'secure_frame') {
            SyncDiagnosticsLog.add(
                '[DIRECT_RX] raw frame received type=$packetType bytes=${message.text.length} channelState=${channel.state}');
          }
          if (packet['type']?.toString() == 'direct_fragment') {
            _handleIncomingFragment(packet);
            return;
          }
          final type = packet['type']?.toString() ?? '-';
          if (type.startsWith('direct_handshake_')) {
            SyncDiagnosticsLog.add('[DIRECT_HANDSHAKE] received type=$type');
          }
          _messages.add(packet);
        }
      } catch (error) {
        SyncDiagnosticsLog.add('[DIRECT_DATA] invalid frame error=$error');
        // Invalid frames are ignored. The sync protocol validates each
        // request after decoding and never trusts arbitrary payloads.
      }
    };
  }

  void _handleIncomingFragment(Map<String, dynamic> fragment) {
    final id = fragment['fragmentId']?.toString() ?? '';
    final index = int.tryParse(fragment['index']?.toString() ?? '') ?? -1;
    final total = int.tryParse(fragment['total']?.toString() ?? '') ?? 0;
    final data = fragment['data']?.toString() ?? '';
    if (id.isEmpty ||
        index < 0 ||
        total < 1 ||
        index >= total ||
        data.isEmpty) {
      return;
    }
    final parts = _incomingFragments.putIfAbsent(
      id,
      () => List<String?>.filled(total, null),
    );
    if (parts.length != total) {
      _incomingFragments.remove(id);
      return;
    }
    parts[index] = data;
    if (parts.any((part) => part == null)) return;
    _incomingFragments.remove(id);
    try {
      final bytes = <int>[];
      for (final part in parts) {
        bytes.addAll(base64Decode(part!));
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map) {
        final packet = Map<String, dynamic>.from(decoded);
        final type = packet['type']?.toString() ?? '-';
        SyncDiagnosticsLog.add(
            '[DIRECT_RX] reassembled frame received type=$type bytes=${bytes.length} channelState=${dataChannel?.state}');
        if (type.startsWith('direct_handshake_')) {
          SyncDiagnosticsLog.add('[DIRECT_HANDSHAKE] received type=$type');
        }
        _messages.add(packet);
      }
    } catch (error) {
      SyncDiagnosticsLog.add(
          '[DIRECT_DATA] invalid fragmented frame error=$error');
    }
  }

  void attachSignalSubscription(
    StreamSubscription<Map<String, dynamic>> subscription,
  ) {
    _signalSubscription = subscription;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    SyncDiagnosticsLog.add('[DIRECT_WEBRTC] connection closing');
    await _signalSubscription?.cancel();
    await dataChannel?.close();
    await peerConnection.close();
    if (closeSignalingOnClose) await signaling.close();
    await _messages.close();
  }
}

class DirectPeerConnectionService {
  DirectPeerConnectionService(this.store,
      {DirectPeerSignalingService? signaling})
      : _signaling = signaling ?? DirectPeerSignalingService(store);

  final AppStore store;
  final DirectPeerSignalingService _signaling;

  Future<SecurePeerSession> connectAsHost({
    required DirectPeerSignalingSettings signalingSettings,
    required String clientDeviceId,
    List<Map<String, dynamic>> iceServers = const <Map<String, dynamic>>[],
    String iceTransportPolicy = 'all',
    int iceCandidatePoolSize = 0,
  }) async {
    final signaling = await _signaling.open(signalingSettings);
    final peer = await createPeerConnection({
      'iceServers': iceServers,
      'iceTransportPolicy': iceTransportPolicy,
      'iceCandidatePoolSize': iceCandidatePoolSize.clamp(0, 16),
    });
    SyncDiagnosticsLog.add(
        '[DIRECT_ICE] host peer created servers=${iceServers.length} policy=$iceTransportPolicy');
    final connection = Completer<SecurePeerSession>();
    var authenticationStarted = false;
    late Future<void> Function() authenticateHost;
    late final DirectPeerConnection result;
    final channel = await peer.createDataChannel(
      'ventio-sync',
      RTCDataChannelInit()..ordered = true,
    );
    result = DirectPeerConnection(
      peerConnection: peer,
      signaling: signaling,
      dataChannel: channel,
    );
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen &&
          !connection.isCompleted) {
        authenticateHost();
      }
    };

    peer.onIceCandidate = (candidate) {
      SyncDiagnosticsLog.add(
          '[DIRECT_WEBRTC] host ice candidate type=${_candidateType(candidate.candidate)}');
      signaling.send({
        'kind': 'candidate',
        'targetDeviceId': clientDeviceId,
        'candidate': candidate.toMap(),
      });
    };
    peer.onConnectionState = (state) {
      SyncDiagnosticsLog.add('[DIRECT_WEBRTC] host state=$state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
          !connection.isCompleted) {
        unawaited(_logIcePath(peer, 'host'));
        authenticateHost();
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed &&
          !connection.isCompleted) {
        connection.completeError(StateError('Direct connection failed.'));
      }
    };
    peer.onIceConnectionState = (state) {
      SyncDiagnosticsLog.add('[DIRECT_WEBRTC] host ice state=$state');
    };
    authenticateHost = () async {
      if (authenticationStarted || connection.isCompleted) return;
      authenticationStarted = true;
      try {
        final material = await DirectPeerHandshake.authenticateHost(
          session: result,
          identity: store.appIdentity,
          expectedClientDeviceId: clientDeviceId,
          expectedClientPublicKey: await _signaling.fetchPeerPublicKey(
            signalingSettings,
            clientDeviceId,
          ),
        );
        if (!connection.isCompleted) {
          connection.complete(AuthenticatedPeerSession(
            inner: result,
            sessionId: material.sessionId,
            sessionKey: material.sessionKey,
            expiresAt: material.expiresAt,
          ));
        }
      } catch (error, stackTrace) {
        if (!connection.isCompleted) {
          connection.completeError(error, stackTrace);
        }
      }
    };

    final subscription = signaling.signals.listen((signal) async {
      if (signal['sourceDeviceId']?.toString() != clientDeviceId) return;
      final kind = signal['kind']?.toString();
      if (kind == 'answer') {
        final description = Map<String, dynamic>.from(
            (signal['description'] as Map?) ?? const <String, dynamic>{});
        await peer.setRemoteDescription(
          RTCSessionDescription(
            description['sdp']?.toString(),
            description['type']?.toString(),
          ),
        );
      } else if (kind == 'candidate') {
        await _addCandidate(peer, signal['candidate']);
      }
    });
    result.attachSignalSubscription(subscription);

    final offer = await peer.createOffer({});
    await peer.setLocalDescription(offer);
    final localOffer = await peer.getLocalDescription() ?? offer;
    SyncDiagnosticsLog.add(
        '[DIRECT_ICE] host offer candidates=${_candidateCount(localOffer.sdp)}');
    signaling.send({
      'kind': 'offer',
      'targetDeviceId': clientDeviceId,
      'description': localOffer.toMap(),
    });

    final connected = await connection.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () =>
          throw TimeoutException('Direct Host connection timed out.'),
    );
    result.attachSignalSubscription(subscription);
    return connected;
  }

  Future<SecurePeerSession> connectAsClient({
    required DirectPeerSignalingSettings signalingSettings,
    required String hostDeviceId,
    List<Map<String, dynamic>> iceServers = const <Map<String, dynamic>>[],
    String iceTransportPolicy = 'all',
    int iceCandidatePoolSize = 0,
  }) async {
    final signaling = await _signaling.open(signalingSettings);
    final peer = await createPeerConnection({
      'iceServers': iceServers,
      'iceTransportPolicy': iceTransportPolicy,
      'iceCandidatePoolSize': iceCandidatePoolSize.clamp(0, 16),
    });
    SyncDiagnosticsLog.add(
        '[DIRECT_ICE] client peer created servers=${iceServers.length} policy=$iceTransportPolicy');
    final connection = Completer<SecurePeerSession>();
    final pendingCandidates = <RTCIceCandidate>[];
    var remoteDescriptionSet = false;
    DirectPeerConnection? result;
    var authenticationStarted = false;
    late Future<void> Function() authenticateClient;
    var iceRestartInFlight = false;
    var iceRestartAttempts = 0;
    var lastIceRestartAt = DateTime.fromMillisecondsSinceEpoch(0);

    // The Client must create the data channel before creating the offer.
    // Otherwise the SDP has no m=application section and libwebrtc has no
    // transport to negotiate, which results in zero ICE candidates.
    final localChannel = await peer.createDataChannel(
      'ventio-sync',
      RTCDataChannelInit()..ordered = true,
    );
    result = DirectPeerConnection(
      peerConnection: peer,
      signaling: signaling,
      dataChannel: localChannel,
    );
    SyncDiagnosticsLog.add(
        '[DIRECT_WEBRTC] client data channel created state=${localChannel.state}');
    localChannel.onDataChannelState = (state) {
      SyncDiagnosticsLog.add(
          '[DIRECT_WEBRTC] client data channel state=$state');
      if (state == RTCDataChannelState.RTCDataChannelOpen &&
          !connection.isCompleted) {
        authenticateClient();
      }
    };

    Future<void> restartIceOffer() async {
      if (iceRestartInFlight || !remoteDescriptionSet) {
        return;
      }
      final now = DateTime.now();
      if (now.difference(lastIceRestartAt) < const Duration(seconds: 2)) {
        return;
      }
      if (iceRestartAttempts >= 3) {
        SyncDiagnosticsLog.add(
            '[DIRECT_WEBRTC] client ice restart exhausted attempts=$iceRestartAttempts');
        return;
      }
      iceRestartInFlight = true;
      lastIceRestartAt = now;
      iceRestartAttempts += 1;
      try {
        await Future<void>.delayed(Duration(seconds: iceRestartAttempts * 2));
        await peer.restartIce();
        final offer = await peer.createOffer(<String, dynamic>{
          'iceRestart': true,
        });
        await peer.setLocalDescription(offer);
        await _waitForIceGatheringComplete(peer);
        final localOffer = await peer.getLocalDescription() ?? offer;
        SyncDiagnosticsLog.add(
            '[DIRECT_ICE] client restart offer candidates=${_candidateCount(localOffer.sdp)}');
        signaling.send({
          'kind': 'offer',
          'targetDeviceId': hostDeviceId,
          'description': localOffer.toMap(),
          'iceRestart': true,
        });
        SyncDiagnosticsLog.add(
            '[DIRECT_WEBRTC] client ice restart offer sent attempt=$iceRestartAttempts');
      } catch (error) {
        SyncDiagnosticsLog.add(
            '[DIRECT_WEBRTC] client ice restart failed=$error');
      } finally {
        iceRestartInFlight = false;
      }
    }

    peer.onIceCandidate = (candidate) {
      SyncDiagnosticsLog.add(
          '[DIRECT_WEBRTC] client ice candidate type=${_candidateType(candidate.candidate)}');
      signaling.send({
        'kind': 'candidate',
        'targetDeviceId': hostDeviceId,
        'candidate': candidate.toMap(),
      });
    };
    peer.onDataChannel = (channel) {
      SyncDiagnosticsLog.add(
          '[DIRECT_WEBRTC] client remote data channel state=${channel.state}');
      result ??= DirectPeerConnection(
          peerConnection: peer, signaling: signaling, dataChannel: channel);
      if (channel.state == RTCDataChannelState.RTCDataChannelOpen &&
          !connection.isCompleted) {
        authenticateClient();
      }
      channel.onDataChannelState = (state) {
        if (state == RTCDataChannelState.RTCDataChannelOpen &&
            !connection.isCompleted) {
          authenticateClient();
        }
      };
    };
    authenticateClient = () async {
      if (authenticationStarted || result == null || connection.isCompleted) {
        return;
      }
      authenticationStarted = true;
      try {
        final material = await DirectPeerHandshake.authenticateClient(
          session: result!,
          identity: store.appIdentity,
          expectedHostDeviceId: hostDeviceId,
          expectedHostPublicKey: await _signaling.fetchPeerPublicKey(
            signalingSettings,
            hostDeviceId,
          ),
        );
        if (!connection.isCompleted) {
          connection.complete(AuthenticatedPeerSession(
            inner: result!,
            sessionId: material.sessionId,
            sessionKey: material.sessionKey,
            expiresAt: material.expiresAt,
          ));
        }
      } catch (error, stackTrace) {
        if (!connection.isCompleted) {
          connection.completeError(error, stackTrace);
        }
      }
    };

    peer.onConnectionState = (state) {
      SyncDiagnosticsLog.add('[DIRECT_WEBRTC] client state=$state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        iceRestartAttempts = 0;
        unawaited(_logIcePath(peer, 'client'));
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        unawaited(restartIceOffer());
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed &&
            !connection.isCompleted &&
            iceRestartAttempts >= 3) {
          connection.completeError(StateError('Direct connection failed.'));
        }
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        unawaited(result?.close());
      }
    };
    peer.onIceConnectionState = (state) {
      SyncDiagnosticsLog.add('[DIRECT_WEBRTC] client ice state=$state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        unawaited(restartIceOffer());
      }
    };
    peer.onIceGatheringState = (state) {
      SyncDiagnosticsLog.add('[DIRECT_WEBRTC] client ice gathering=$state');
    };

    final subscription = signaling.signals.listen((signal) async {
      try {
        if (signal['sourceDeviceId']?.toString() != hostDeviceId) return;
        final kind = signal['kind']?.toString();
        SyncDiagnosticsLog.add('[DIRECT_WEBRTC] client signal kind=$kind');
        if (kind == 'answer') {
          final description = Map<String, dynamic>.from(
              (signal['description'] as Map?) ?? const <String, dynamic>{});
          await peer.setRemoteDescription(
            RTCSessionDescription(
              description['sdp']?.toString(),
              description['type']?.toString(),
            ),
          );
          remoteDescriptionSet = true;
          for (final candidate in pendingCandidates) {
            await peer.addCandidate(candidate);
          }
          pendingCandidates.clear();
        } else if (kind == 'candidate') {
          final candidate = _candidateFromJson(signal['candidate']);
          if (candidate == null) return;
          if (remoteDescriptionSet) {
            await peer.addCandidate(candidate);
            SyncDiagnosticsLog.add(
                '[DIRECT_ICE] client remote candidate added');
          } else {
            pendingCandidates.add(candidate);
            SyncDiagnosticsLog.add(
                '[DIRECT_ICE] client remote candidate queued count=${pendingCandidates.length}');
          }
        }
      } catch (error, stackTrace) {
        SyncDiagnosticsLog.add('[DIRECT_WEBRTC] client signal error=$error');
        if (!connection.isCompleted) {
          connection.completeError(error, stackTrace);
        }
      }
    }, onError: (Object error, StackTrace stackTrace) {
      SyncDiagnosticsLog.add('[DIRECT_SIGNAL] client stream error=$error');
      if (!connection.isCompleted) connection.completeError(error, stackTrace);
    }, onDone: () {
      SyncDiagnosticsLog.add('[DIRECT_SIGNAL] client stream closed');
      if (!connection.isCompleted) {
        connection.completeError(
            StateError('Direct Client signaling channel was closed.'));
      }
    });

    final offer = await peer.createOffer({});
    await peer.setLocalDescription(offer);
    await _waitForIceGatheringComplete(peer);
    final localOffer = await peer.getLocalDescription() ?? offer;
    SyncDiagnosticsLog.add(
        '[DIRECT_ICE] client offer candidates=${_candidateCount(localOffer.sdp)}');
    signaling.send({
      'kind': 'offer',
      'targetDeviceId': hostDeviceId,
      'description': localOffer.toMap(),
    });

    try {
      final connected = await connection.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () =>
            throw TimeoutException('Direct Client connection timed out.'),
      );
      result?.attachSignalSubscription(subscription);
      return connected;
    } catch (_) {
      SyncDiagnosticsLog.add(
          '[DIRECT_WEBRTC] client connection failed or timed out');
      await subscription.cancel();
      await peer.close();
      await signaling.close();
      rethrow;
    }
  }

  /// Waits for one Client offer and completes the Host side of the direct
  /// connection. The signaling channel carries no sync data.
  Future<SecurePeerSession> acceptAsHost({
    required DirectPeerSignalingSettings signalingSettings,
    String clientDeviceId = '',
    List<Map<String, dynamic>> iceServers = const <Map<String, dynamic>>[],
    String iceTransportPolicy = 'all',
    int iceCandidatePoolSize = 0,
  }) async {
    final signaling = await _signaling.open(signalingSettings);
    final peer = await createPeerConnection({
      'iceServers': iceServers,
      'iceTransportPolicy': iceTransportPolicy,
      'iceCandidatePoolSize': iceCandidatePoolSize.clamp(0, 16),
    });
    SyncDiagnosticsLog.add(
        '[DIRECT_ICE] host-listener peer created servers=${iceServers.length} policy=$iceTransportPolicy');
    final connection = Completer<SecurePeerSession>();
    final pendingCandidates = <RTCIceCandidate>[];
    var remoteDescriptionSet = false;
    var sourceDeviceId = clientDeviceId.trim();
    DirectPeerConnection? result;
    var authenticationStarted = false;
    late Future<void> Function() authenticateHost;

    peer.onIceCandidate = (candidate) {
      SyncDiagnosticsLog.add(
          '[DIRECT_WEBRTC] host-listener ice candidate type=${_candidateType(candidate.candidate)}');
      if (sourceDeviceId.isEmpty) return;
      signaling.send({
        'kind': 'candidate',
        'targetDeviceId': sourceDeviceId,
        'candidate': candidate.toMap(),
      });
    };
    peer.onDataChannel = (channel) {
      result ??= DirectPeerConnection(
        peerConnection: peer,
        signaling: signaling,
        dataChannel: channel,
      );
      SyncDiagnosticsLog.add(
          '[DIRECT_WEBRTC] host data channel received state=${channel.state}');
      if (channel.state == RTCDataChannelState.RTCDataChannelOpen &&
          !connection.isCompleted) {
        authenticateHost();
      }
      channel.onDataChannelState = (state) {
        SyncDiagnosticsLog.add(
            '[DIRECT_WEBRTC] host data channel state=$state');
        if (state == RTCDataChannelState.RTCDataChannelOpen &&
            !connection.isCompleted) {
          authenticateHost();
        }
      };
    };
    authenticateHost = () async {
      if (authenticationStarted ||
          result == null ||
          sourceDeviceId.isEmpty ||
          connection.isCompleted) {
        return;
      }
      authenticationStarted = true;
      try {
        final material = await DirectPeerHandshake.authenticateHost(
          session: result!,
          identity: store.appIdentity,
          expectedClientDeviceId: sourceDeviceId,
        );
        if (!connection.isCompleted) {
          connection.complete(AuthenticatedPeerSession(
            inner: result!,
            sessionId: material.sessionId,
            sessionKey: material.sessionKey,
            expiresAt: material.expiresAt,
          ));
        }
      } catch (error, stackTrace) {
        if (!connection.isCompleted) {
          connection.completeError(error, stackTrace);
        }
      }
    };

    peer.onConnectionState = (state) {
      SyncDiagnosticsLog.add('[DIRECT_WEBRTC] host-listener state=$state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed &&
          !connection.isCompleted) {
        connection.completeError(StateError('Direct Host connection failed.'));
      }
    };
    peer.onIceConnectionState = (state) {
      SyncDiagnosticsLog.add('[DIRECT_WEBRTC] host-listener ice state=$state');
    };
    peer.onIceGatheringState = (state) {
      SyncDiagnosticsLog.add(
          '[DIRECT_WEBRTC] host-listener ice gathering=$state');
    };

    final subscription = signaling.signals.listen((signal) async {
      try {
        final signalSource = signal['sourceDeviceId']?.toString().trim() ?? '';
        if (signalSource.isEmpty ||
            (sourceDeviceId.isNotEmpty && signalSource != sourceDeviceId)) {
          return;
        }
        sourceDeviceId = signalSource;
        final kind = signal['kind']?.toString();
        SyncDiagnosticsLog.add('[DIRECT_WEBRTC] host signal kind=$kind');
        if (kind == 'offer') {
          final description = Map<String, dynamic>.from(
              (signal['description'] as Map?) ?? const <String, dynamic>{});
          await peer.setRemoteDescription(
            RTCSessionDescription(
              description['sdp']?.toString(),
              description['type']?.toString(),
            ),
          );
          remoteDescriptionSet = true;
          for (final candidate in pendingCandidates) {
            await peer.addCandidate(candidate);
          }
          pendingCandidates.clear();
          final answer = await peer.createAnswer({});
          await peer.setLocalDescription(answer);
          await _waitForIceGatheringComplete(peer);
          final localAnswer = await peer.getLocalDescription() ?? answer;
          SyncDiagnosticsLog.add(
              '[DIRECT_ICE] host answer candidates=${_candidateCount(localAnswer.sdp)}');
          signaling.send({
            'kind': 'answer',
            'targetDeviceId': sourceDeviceId,
            'description': localAnswer.toMap(),
          });
          if (result?.dataChannel?.state ==
                  RTCDataChannelState.RTCDataChannelOpen &&
              !connection.isCompleted) {
            authenticateHost();
          }
        } else if (kind == 'candidate') {
          final candidate = _candidateFromJson(signal['candidate']);
          if (candidate == null) return;
          if (remoteDescriptionSet) {
            await peer.addCandidate(candidate);
            SyncDiagnosticsLog.add('[DIRECT_ICE] host remote candidate added');
          } else {
            pendingCandidates.add(candidate);
            SyncDiagnosticsLog.add(
                '[DIRECT_ICE] host remote candidate queued count=${pendingCandidates.length}');
          }
        }
      } catch (error) {
        SyncDiagnosticsLog.add('[DIRECT_WEBRTC] host signal error=$error');
        if (!connection.isCompleted) connection.completeError(error);
      }
    }, onError: (Object error, StackTrace stackTrace) {
      if (!connection.isCompleted) connection.completeError(error, stackTrace);
    }, onDone: () {
      if (!connection.isCompleted) {
        connection.completeError(
            StateError('Direct Host signaling channel was closed.'));
      }
    });

    try {
      // A pairing code remains valid for several minutes. The Host must keep
      // listening for the whole period instead of closing after 30 seconds.
      final connected = await connection.future;
      result?.attachSignalSubscription(subscription);
      return connected;
    } catch (_) {
      SyncDiagnosticsLog.add('[DIRECT_WEBRTC] host connection failed');
      await subscription.cancel();
      await peer.close();
      await signaling.close();
      rethrow;
    }
  }

  static Future<void> _addCandidate(
    RTCPeerConnection peer,
    Object? raw,
  ) async {
    final candidate = _candidateFromJson(raw);
    if (candidate != null) await peer.addCandidate(candidate);
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
      // Trickle candidates remain enabled. A peer may still connect with the
      // candidates already emitted before the gathering timeout.
    }
  }

  static Future<void> _logIcePath(
    RTCPeerConnection peer,
    String role,
  ) async {
    try {
      final reports = await peer.getStats();
      final pairs = reports.where((report) => report.type == 'candidate-pair');
      final selected = pairs.firstWhere(
        (report) =>
            report.values['nominated'] == true ||
            report.values['selected'] == true ||
            report.values['state']?.toString() == 'succeeded',
        orElse: () => pairs.isEmpty ? reports.first : pairs.first,
      );
      final values = selected.values;
      SyncDiagnosticsLog.add(
        '[DIRECT_WEBRTC] $role path state=${values['state'] ?? '-'} '
        'localType=${values['localCandidateType'] ?? '-'} '
        'remoteType=${values['remoteCandidateType'] ?? '-'} '
        'protocol=${values['protocol'] ?? '-'}',
      );
    } catch (error) {
      SyncDiagnosticsLog.add(
          '[DIRECT_WEBRTC] $role path stats unavailable=$error');
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

  static String _candidateType(String? raw) {
    final value = raw?.trim() ?? '';
    final match = RegExp(r' typ ([a-z]+)').firstMatch(value);
    return match?.group(1) ?? (value.isEmpty ? 'none' : 'unknown');
  }
}

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
    final hostDeviceId = store.deviceId.trim();
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
        identity: store.appIdentity,
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
