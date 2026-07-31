import 'dart:async';
import 'dart:math';

import 'secure_peer_session.dart';

typedef DirectPeerRequestHandler = Future<Map<String, dynamic>> Function(
  String requestKind,
  Map<String, dynamic> payload,
);

class DirectPeerRequestSession {
  DirectPeerRequestSession(this.connection) {
    _subscription = connection.messages.listen(_handleMessage);
  }

  final SecurePeerSession connection;
  final Map<String, Completer<Map<String, dynamic>>> _pending =
      <String, Completer<Map<String, dynamic>>>{};
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  int _counter = 0;
  bool _closed = false;

  String _requestId() {
    _counter += 1;
    return 'direct-${DateTime.now().microsecondsSinceEpoch}-${_counter.toRadixString(36)}-${Random.secure().nextInt(1 << 20).toRadixString(36)}';
  }

  void _handleMessage(Map<String, dynamic> message) {
    if (message['type']?.toString() != 'direct_response') return;
    final id = message['requestId']?.toString().trim() ?? '';
    final completer = _pending.remove(id);
    if (completer != null && !completer.isCompleted) {
      completer.complete(message);
    }
  }

  Future<Map<String, dynamic>> sendRequest(
    String requestKind,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_closed) {
      throw StateError('Direct request session is closed.');
    }
    final requestId = _requestId();
    final completer = Completer<Map<String, dynamic>>();
    _pending[requestId] = completer;
    try {
      await connection.send('direct_request', {
        'requestId': requestId,
        'requestKind': requestKind,
        ...payload,
      });
      return await completer.future.timeout(timeout);
    } finally {
      _pending.remove(requestId);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Direct request session closed.'));
      }
    }
    _pending.clear();
    await _subscription.cancel();
    await connection.close();
  }
}

class DirectPeerHostEndpoint {
  DirectPeerHostEndpoint(
    this.connection, {
    required this.onRequest,
    this.onClosed,
  }) {
    _subscription = connection.messages.listen(
      _handleMessage,
      onDone: () {
        if (!_closed) onClosed?.call();
      },
    );
  }

  final SecurePeerSession connection;
  final DirectPeerRequestHandler onRequest;
  final void Function()? onClosed;
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  bool _closed = false;

  Future<void> _handleMessage(Map<String, dynamic> message) async {
    if (message['type']?.toString() != 'direct_request') return;
    final requestId = message['requestId']?.toString().trim() ?? '';
    final requestKind = message['requestKind']?.toString().trim() ?? '';
    if (requestId.isEmpty || requestKind.isEmpty) return;
    try {
      final response = await onRequest(requestKind, message);
      await connection.send('direct_response', {
        'requestId': requestId,
        'ok': true,
        ...response,
      });
    } catch (error) {
      await connection.send('direct_response', {
        'requestId': requestId,
        'ok': false,
        'error': error.toString(),
      });
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    await connection.close();
  }
}
