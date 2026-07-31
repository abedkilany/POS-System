import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../data/app_store.dart';
import 'direct_peer_signaling_service.dart';
import 'sync_diagnostics_log.dart';

/// A direct, encrypted data connection between one Host and one Client.
///
/// The signaling WebSocket is used only for offer/answer/candidate messages.
/// Application sync frames are sent through the WebRTC data channel after it
/// becomes connected.
class DirectPeerConnection {
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

  Stream<Map<String, dynamic>> get messages => _messages.stream;

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

  Future<DirectPeerConnection> connectAsHost({
    required DirectPeerSignalingSettings signalingSettings,
    required String clientDeviceId,
    List<Map<String, dynamic>> iceServers = const <Map<String, dynamic>>[],
  }) async {
    final signaling = await _signaling.open(signalingSettings);
    final peer = await createPeerConnection({'iceServers': iceServers});
    final connection = Completer<DirectPeerConnection>();
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
        connection.complete(result);
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed &&
          !connection.isCompleted) {
        connection.completeError(StateError('Direct connection failed.'));
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

    return connection.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () =>
          throw TimeoutException('Direct Host connection timed out.'),
    );
  }

  Future<DirectPeerConnection> connectAsClient({
    required DirectPeerSignalingSettings signalingSettings,
    required String hostDeviceId,
    List<Map<String, dynamic>> iceServers = const <Map<String, dynamic>>[],
  }) async {
    final signaling = await _signaling.open(signalingSettings);
    final peer = await createPeerConnection({'iceServers': iceServers});
    final connection = Completer<DirectPeerConnection>();
    final pendingCandidates = <RTCIceCandidate>[];
    var remoteDescriptionSet = false;
    DirectPeerConnection? result;

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
          !connection.isCompleted) {
        connection.complete(result!);
      }
      channel.onDataChannelState = (state) {
        if (state == RTCDataChannelState.RTCDataChannelOpen &&
            !connection.isCompleted) {
          connection.complete(result!);
        }
      };
    };
    peer.onConnectionState = (state) {
      SyncDiagnosticsLog.add('[DIRECT_WEBRTC] client state=$state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed &&
          !connection.isCompleted) {
        connection.completeError(StateError('Direct connection failed.'));
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
      connected.attachSignalSubscription(subscription);
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
  Future<DirectPeerConnection> acceptAsHost({
    required DirectPeerSignalingSettings signalingSettings,
    String clientDeviceId = '',
    List<Map<String, dynamic>> iceServers = const <Map<String, dynamic>>[],
  }) async {
    final signaling = await _signaling.open(signalingSettings);
    final peer = await createPeerConnection({'iceServers': iceServers});
    final connection = Completer<DirectPeerConnection>();
    final pendingCandidates = <RTCIceCandidate>[];
    var remoteDescriptionSet = false;
    var sourceDeviceId = clientDeviceId.trim();
    DirectPeerConnection? result;

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
          !connection.isCompleted) {
        connection.complete(result!);
      }
      channel.onDataChannelState = (state) {
        SyncDiagnosticsLog.add(
            '[DIRECT_WEBRTC] host data channel state=$state');
        if (state == RTCDataChannelState.RTCDataChannelOpen &&
            !connection.isCompleted) {
          connection.complete(result!);
        }
      };
    };
    peer.onConnectionState = (state) {
      SyncDiagnosticsLog.add('[DIRECT_WEBRTC] host-listener state=$state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed &&
          !connection.isCompleted) {
        connection.completeError(StateError('Direct Host connection failed.'));
      }
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
    });

    try {
      final connected = await connection.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () =>
            throw TimeoutException('Direct Host connection timed out.'),
      );
      connected.attachSignalSubscription(subscription);
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
