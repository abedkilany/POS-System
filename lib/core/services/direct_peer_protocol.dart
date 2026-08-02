import 'dart:async';
import 'dart:math';

import 'secure_peer_session.dart';
import 'sync_diagnostics_log.dart';

typedef DirectPeerRequestHandler = Future<Map<String, dynamic>> Function(
  String requestKind,
  Map<String, dynamic> payload,
);

class DirectPeerRequestSession {
  DirectPeerRequestSession(this.connection) {
    _subscription = connection.messages.listen(
      _handleMessage,
      onDone: _handleConnectionClosed,
      onError: (Object error, StackTrace stack) {
        _handleConnectionClosed();
      },
    );
  }

  final SecurePeerSession connection;
  final Map<String, Completer<Map<String, dynamic>>> _pending =
      <String, Completer<Map<String, dynamic>>>{};
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  int _counter = 0;
  bool _closed = false;

  /// Realtime peer events which are not request/response frames.
  Stream<Map<String, dynamic>> get events => _events.stream;

  String _requestId() {
    _counter += 1;
    return 'direct-${DateTime.now().microsecondsSinceEpoch}-${_counter.toRadixString(36)}-${Random.secure().nextInt(1 << 20).toRadixString(36)}';
  }

  void _handleMessage(Map<String, dynamic> message) {
    final type = message['type']?.toString();
    if (type != 'direct_response') {
      if (type == 'sync_changed' || type == 'host_requests') {
        _events.add(message);
      }
      return;
    }
    final id = message['requestId']?.toString().trim() ?? '';
    final completer = _pending.remove(id);
    if (completer != null && !completer.isCompleted) {
      completer.complete(message);
    }
  }

  void _handleConnectionClosed() {
    if (_closed) return;
    _closed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Direct peer connection closed.'));
      }
    }
    _pending.clear();
    unawaited(_events.close());
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
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] direct request start kind=$requestKind requestId=$requestId');
    final completer = Completer<Map<String, dynamic>>();
    _pending[requestId] = completer;
    try {
      await connection.send('direct_request', {
        'requestId': requestId,
        'requestKind': requestKind,
        ...payload,
      });
      final response = await completer.future.timeout(timeout);
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] direct request result kind=$requestKind requestId=$requestId ok=${response['ok'] == true}');
      return response;
    } catch (error) {
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] direct request failed kind=$requestKind requestId=$requestId error=$error');
      rethrow;
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
    await _events.close();
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
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] host request start kind=$requestKind requestId=$requestId');
      final response = await onRequest(requestKind, message);
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] host request result kind=$requestKind requestId=$requestId ok=true');
      await connection.send('direct_response', {
        'requestId': requestId,
        'ok': true,
        ...response,
      });
    } catch (error) {
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] host request result kind=$requestKind requestId=$requestId ok=false error=$error');
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
