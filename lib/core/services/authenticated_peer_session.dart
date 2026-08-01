import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'secure_peer_session.dart';

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
  int _nextSequence = 0;
  int _lastReceivedSequence = -1;
  bool _closed = false;

  @override
  String get transportType => inner.transportType;

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  @override
  Future<void> send(String type, Map<String, dynamic> payload) async {
    final operation = Completer<void>();
    final previous = _sendTail;
    _sendTail = operation.future;
    try {
      await previous;
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
      operation.complete();
    }
  }

  void _handleMessage(Map<String, dynamic> message) {
    if (_closed || message['type']?.toString() != 'secure_frame') return;
    try {
      _ensureUsable();
      final frame = Map<String, dynamic>.from(message)
        ..remove('type')
        ..remove('mac');
      final sequence = int.tryParse(frame['sequence']?.toString() ?? '');
      final messageType = frame['messageType']?.toString().trim() ?? '';
      final payload = frame['payload'];
      if (frame['version'] != _version ||
          frame['sessionId']?.toString() != sessionId ||
          frame['expiresAtMs'] != expiresAt.millisecondsSinceEpoch ||
          sequence == null ||
          sequence <= _lastReceivedSequence ||
          messageType.isEmpty ||
          payload is! Map ||
          !_constantTimeEquals(message['mac']?.toString() ?? '', _mac(frame))) {
        return;
      }
      _lastReceivedSequence = sequence;
      _messages.add({
        'type': messageType,
        ...Map<String, dynamic>.from(payload),
      });
    } catch (_) {
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
