import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'secure_peer_session.dart';
import 'sync_diagnostics_log.dart';

/// Application-level integrity and replay protection layered over a transport.
class AuthenticatedPeerSession implements SecurePeerSession {
  AuthenticatedPeerSession({
    required this.inner,
    required this.sessionId,
    required this.sessionKey,
    required this.expiresAt,
  }) {
    _subscription = inner.messages.listen(_handleMessage,
        onError: _messages.addError, onDone: _messages.close);
  }

  static const _version = 1;

  final SecurePeerSession inner;
  final String sessionId;
  final List<int> sessionKey;
  final DateTime expiresAt;
  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>.broadcast();
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  Future<void> _sendTail = Future<void>.value();
  int _sendQueueDepth = 0;
  int _maxSendQueueDepth = 0;
  int _nextSequence = 0;
  int _lastReceivedSequence = -1;
  bool _closed = false;

  @override
  String get transportType => inner.transportType;

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
            '[SYNC_TRACE] [DIRECT_QUEUE] secure send type=$type queueWaitMs=$queueWaitMs depth=$_sendQueueDepth maxDepth=$_maxSendQueueDepth sessionId=$sessionId');
      }
      _ensureUsable();
      final frame = <String, dynamic>{
        'version': _version,
        'sessionId': sessionId,
        'sequence': _nextSequence++,
        'messageType': type,
        'payload': payload,
        'expiresAtMs': expiresAt.millisecondsSinceEpoch,
      };
      await inner.send('secure_frame', {
        ...frame,
        'mac': _mac(frame),
      });
    } finally {
      _sendQueueDepth--;
      operation.complete();
    }
  }

  void _handleMessage(Map<String, dynamic> message) {
    if (_closed || message['type']?.toString() != 'secure_frame') return;
    final receivedAt = DateTime.now().toUtc().toIso8601String();
    try {
      _ensureUsable();
      final frame = Map<String, dynamic>.from(message)
        ..remove('type')
        ..remove('mac');
      final sequence = int.tryParse(frame['sequence']?.toString() ?? '');
      final messageType = frame['messageType']?.toString().trim() ?? '';
      final payload = frame['payload'];
      final rejectionReasons = <String>[];
      if (frame['version'] != _version) rejectionReasons.add('version');
      if (frame['sessionId']?.toString() != sessionId) {
        rejectionReasons.add('session');
      }
      if (frame['expiresAtMs'] != expiresAt.millisecondsSinceEpoch) {
        rejectionReasons.add('expiry');
      }
      if (sequence == null) {
        rejectionReasons.add('sequence_missing');
      } else if (sequence <= _lastReceivedSequence) {
        rejectionReasons.add('sequence_replay');
      }
      if (messageType.isEmpty) rejectionReasons.add('message_type');
      if (payload is! Map) rejectionReasons.add('payload');
      if (!_constantTimeEquals(message['mac']?.toString() ?? '', _mac(frame))) {
        rejectionReasons.add('mac');
      }
      if (rejectionReasons.isNotEmpty) {
        SyncDiagnosticsLog.add(
            '[SYNC_TRACE] [DIRECT_RX] secure rejected at=$receivedAt frameSequence=${sequence ?? '-'} lastReceived=$_lastReceivedSequence messageType=${messageType.isEmpty ? '-' : messageType} reasons=${rejectionReasons.join(',')} sessionId=$sessionId');
        return;
      }
      final acceptedSequence = sequence;
      if (acceptedSequence == null) return;
      _lastReceivedSequence = acceptedSequence;
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] [DIRECT_RX] secure accepted at=$receivedAt frameSequence=$acceptedSequence messageType=$messageType sessionId=$sessionId');
      _messages.add({
        'type': messageType,
        ...Map<String, dynamic>.from(payload),
      });
    } catch (error) {
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] [DIRECT_RX] secure processing error at=$receivedAt error=$error sessionId=$sessionId');
      // Invalid, expired, or replayed frames are deliberately discarded.
    }
  }

  String _mac(Map<String, dynamic> frame) {
    final canonical = jsonEncode({
      'expiresAtMs': frame['expiresAtMs'],
      'messageType': frame['messageType'],
      'payload': frame['payload'],
      'sequence': frame['sequence'],
      'sessionId': frame['sessionId'],
      'version': frame['version'],
    });
    return base64UrlEncode(
        Hmac(sha256, sessionKey).convert(utf8.encode(canonical)).bytes);
  }

  void _ensureUsable() {
    if (_closed) throw StateError('Authenticated peer session is closed.');
    if (DateTime.now().toUtc().isAfter(expiresAt)) {
      throw StateError('Authenticated peer session has expired.');
    }
  }

  static bool _constantTimeEquals(String left, String right) {
    final a = utf8.encode(left);
    final b = utf8.encode(right);
    if (a.length != b.length) return false;
    var result = 0;
    for (var index = 0; index < a.length; index++) {
      result |= a[index] ^ b[index];
    }
    return result == 0;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    await inner.close();
    await _messages.close();
  }
}
