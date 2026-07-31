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
  DirectPeerConnection({
    required this.peerConnection,
    required this.signaling,
    required RTCDataChannel dataChannel,
  }) {
    this.dataChannel = dataChannel;
    _bindDataChannel(dataChannel);
  }

  final RTCPeerConnection peerConnection;
  final DirectPeerSignalingSession signaling;
  RTCDataChannel? dataChannel;
  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _signalSubscription;
  bool _closed = false;

  @override
  String get transportType => 'direct';

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  @override
  Future<void> send(String type, Map<String, dynamic> payload) async {
    final channel = dataChannel;
    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('Direct data channel is not open.');
    }
    await channel.send(RTCDataChannelMessage(jsonEncode({
      'type': type,
      ...payload,
    })));
  }

  void _bindDataChannel(RTCDataChannel channel) {
    dataChannel = channel;
    channel.onMessage = (message) {
      if (_closed || message.isBinary) return;
      try {
        final decoded = jsonDecode(message.text);
        if (decoded is Map) {
          _messages.add(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {
        // Invalid frames are ignored. The sync protocol validates each
        // request after decoding and never trusts arbitrary payloads.
      }
    };
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
    await _signalSubscription?.cancel();
    await dataChannel?.close();
    await peerConnection.close();
    await signaling.close();
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
          !connection.isCompleted) authenticateHost();
    };

    peer.onIceCandidate = (candidate) {
      SyncDiagnosticsLog.add(
          '[DIRECT_WEBRTC] client ice candidate=${candidate.candidate?.isNotEmpty == true}');
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
    signaling.send({
      'kind': 'offer',
      'targetDeviceId': clientDeviceId,
      'description': offer.toMap(),
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
    final connection = Completer<SecurePeerSession>();
    final pendingCandidates = <RTCIceCandidate>[];
    var remoteDescriptionSet = false;
    DirectPeerConnection? result;
    var authenticationStarted = false;
    late Future<void> Function() authenticateClient;
    var iceRestartInFlight = false;
    var iceRestartAttempts = 0;
    var lastIceRestartAt = DateTime.fromMillisecondsSinceEpoch(0);

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
      signaling.send({
        'kind': 'candidate',
        'targetDeviceId': hostDeviceId,
        'candidate': candidate.toMap(),
      });
    };
    peer.onDataChannel = (channel) {
      result ??= DirectPeerConnection(
        peerConnection: peer,
        signaling: signaling,
        dataChannel: channel,
      );
      if (channel.state == RTCDataChannelState.RTCDataChannelOpen &&
          !connection.isCompleted) authenticateClient();
      channel.onDataChannelState = (state) {
        if (state == RTCDataChannelState.RTCDataChannelOpen &&
            !connection.isCompleted) authenticateClient();
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
        if (!connection.isCompleted)
          connection.completeError(error, stackTrace);
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
      if (signal['sourceDeviceId']?.toString() != hostDeviceId) return;
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
        } else {
          pendingCandidates.add(candidate);
        }
      }
    });

    final offer = await peer.createOffer({});
    await peer.setLocalDescription(offer);
    await _waitForIceGatheringComplete(peer);
    final localOffer = await peer.getLocalDescription() ?? offer;
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
    final connection = Completer<SecurePeerSession>();
    final pendingCandidates = <RTCIceCandidate>[];
    var remoteDescriptionSet = false;
    var sourceDeviceId = clientDeviceId.trim();
    DirectPeerConnection? result;
    var authenticationStarted = false;
    late Future<void> Function() authenticateHost;

    peer.onIceCandidate = (candidate) {
      SyncDiagnosticsLog.add(
          '[DIRECT_WEBRTC] host-listener ice candidate=${candidate.candidate?.isNotEmpty == true}');
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
          !connection.isCompleted) authenticateHost();
      channel.onDataChannelState = (state) {
        SyncDiagnosticsLog.add(
            '[DIRECT_WEBRTC] host data channel state=$state');
        if (state == RTCDataChannelState.RTCDataChannelOpen &&
            !connection.isCompleted) authenticateHost();
      };
    };
    authenticateHost = () async {
      if (authenticationStarted ||
          result == null ||
          sourceDeviceId.isEmpty ||
          connection.isCompleted) return;
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
        if (!connection.isCompleted)
          connection.completeError(error, stackTrace);
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
          } else {
            pendingCandidates.add(candidate);
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
}
