import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/direct_peer_protocol.dart';
import 'package:ventio/core/services/secure_peer_session.dart';

class _FakePeerSession implements SecurePeerSession {
  final StreamController<Map<String, dynamic>> controller =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  String get transportType => 'direct';

  @override
  Stream<Map<String, dynamic>> get messages => controller.stream;

  @override
  Future<void> send(String type, Map<String, dynamic> payload) async {}

  @override
  Future<void> close() => controller.close();

  void emit(Map<String, dynamic> message) => controller.add(message);
}

void main() {
  test('forwards Direct realtime events without treating them as responses',
      () async {
    final connection = _FakePeerSession();
    final session = DirectPeerRequestSession(connection);
    final eventFuture = session.events.first;

    connection.emit({
      'type': 'sync_changed',
      'latestSequence': 42,
    });

    expect(await eventFuture, {
      'type': 'sync_changed',
      'latestSequence': 42,
    });
    await session.close();
  });

  test('closes the realtime event stream when the peer connection closes',
      () async {
    final connection = _FakePeerSession();
    final session = DirectPeerRequestSession(connection);
    final done = Completer<void>();
    session.events.listen((_) {}, onDone: done.complete);

    await connection.controller.close();
    await done.future.timeout(const Duration(seconds: 1));
    await session.close();
  });
}
