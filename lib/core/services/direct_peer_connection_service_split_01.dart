part of 'direct_peer_connection_service.dart';

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
            '[SYNC_TRACE] [DIRECT_QUEUE] data send type=$type queueWaitMs=$queueWaitMs depth=$_sendQueueDepth maxDepth=$_maxSendQueueDepth');
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
      final bufferedBefore = await _readBufferedAmount(channel);
      if (encoded.length <= _maxDataChannelPayloadBytes) {
        await channel.send(RTCDataChannelMessage(utf8.decode(encoded)));
        final bufferedAfter = await _readBufferedAmount(channel);
        SyncDiagnosticsLog.add(
            '[SYNC_TRACE] [DIRECT_CHANNEL] send type=$type requestId=${payload['requestId'] ?? '-'} bytes=${encoded.length} state=${channel.state} bufferedBefore=${bufferedBefore ?? '-'} bufferedAfter=${bufferedAfter ?? '-'} queueWaitMs=$queueWaitMs');
        return;
      }

      _fragmentCounter++;
      final fragmentId =
          'fragment-${DateTime.now().microsecondsSinceEpoch}-$_fragmentCounter';
      final total = (encoded.length + _maxDataChannelPayloadBytes - 1) ~/
          _maxDataChannelPayloadBytes;
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] [DIRECT_DATA] send fragmented type=$type bytes=${encoded.length} fragments=$total');
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
      final bufferedAfter = await _readBufferedAmount(channel);
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] [DIRECT_CHANNEL] send type=$type requestId=${payload['requestId'] ?? '-'} bytes=${encoded.length} fragments=$total state=${channel.state} bufferedBefore=${bufferedBefore ?? '-'} bufferedAfter=${bufferedAfter ?? '-'} queueWaitMs=$queueWaitMs');
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
            final securePayload = packet['payload'];
            final requestId = securePayload is Map
                ? securePayload['requestId']?.toString() ?? '-'
                : '-';
            SyncDiagnosticsLog.add(
                '[SYNC_TRACE] [DIRECT_RX] raw frame received type=$packetType messageType=${packet['messageType'] ?? '-'} requestId=$requestId bytes=${message.text.length} channelState=${channel.state}');
          }
          if (packet['type']?.toString() == 'direct_fragment') {
            _handleIncomingFragment(packet);
            return;
          }
          final type = packet['type']?.toString() ?? '-';
          if (type.startsWith('direct_handshake_')) {
            SyncDiagnosticsLog.add(
                '[SYNC_TRACE] [DIRECT_HANDSHAKE] received type=$type');
          }
          _messages.add(packet);
        }
      } catch (error) {
        SyncDiagnosticsLog.add(
            '[SYNC_TRACE] [DIRECT_DATA] invalid frame error=$error');
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
        final securePayload = packet['payload'];
        final requestId = securePayload is Map
            ? securePayload['requestId']?.toString() ?? '-'
            : '-';
        SyncDiagnosticsLog.add(
            '[SYNC_TRACE] [DIRECT_RX] reassembled frame received type=$type messageType=${packet['messageType'] ?? '-'} requestId=$requestId bytes=${bytes.length} channelState=${dataChannel?.state}');
        if (type.startsWith('direct_handshake_')) {
          SyncDiagnosticsLog.add(
              '[SYNC_TRACE] [DIRECT_HANDSHAKE] received type=$type');
        }
        _messages.add(packet);
      }
    } catch (error) {
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] [DIRECT_DATA] invalid fragmented frame error=$error');
    }
  }

  static Future<int?> _readBufferedAmount(RTCDataChannel channel) async {
    try {
      return await channel.getBufferedAmount();
    } catch (_) {
      return null;
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
