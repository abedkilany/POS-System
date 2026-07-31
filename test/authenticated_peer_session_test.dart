import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/authenticated_peer_session.dart';
import 'package:ventio/core/services/secure_peer_session.dart';

class _FakePeerSession implements SecurePeerSession {
  final incoming = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <Map<String, dynamic>>[];

  @override
  String get transportType => 'fake';

  @override
  Stream<Map<String, dynamic>> get messages => incoming.stream;

  @override
  Future<void> send(String type, Map<String, dynamic> payload) async {
    sent.add({'type': type, ...payload});
  }

  @override
  Future<void> close() async {
    await incoming.close();
  }
}

void main() {
  const sessionId = 'session-1';
  final key = List<int>.generate(32, (index) => index + 1);
  final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 5));

  Map<String, dynamic> frameFor({
    required int sequence,
    required String type,
    required Map<String, dynamic> payload,
    required String mac,
  }) =>
      {
        'type': 'secure_frame',
        'version': 1,
        'sessionId': sessionId,
        'sequence': sequence,
        'messageType': type,
        'payload': payload,
        'expiresAtMs': expiresAt.millisecondsSinceEpoch,
        'mac': mac,
      };

  String macFor({
    required int sequence,
    required String type,
    required Map<String, dynamic> payload,
  }) {
    final canonical = jsonEncode({
      'expiresAtMs': expiresAt.millisecondsSinceEpoch,
      'messageType': type,
      'payload': payload,
      'sequence': sequence,
      'sessionId': sessionId,
      'version': 1,
    });
    return base64UrlEncode(
        Hmac(sha256, key).convert(utf8.encode(canonical)).bytes);
  }

  test('wraps outgoing messages in authenticated frames', () async {
    final raw = _FakePeerSession();
    final session = AuthenticatedPeerSession(
      inner: raw,
      sessionId: sessionId,
      sessionKey: key,
      expiresAt: expiresAt,
    );

    await session.send('direct_request', {'requestId': 'r1'});

    expect(raw.sent, hasLength(1));
    expect(raw.sent.single['type'], 'secure_frame');
    expect(raw.sent.single['sequence'], 0);
    expect(raw.sent.single['mac'], isNotEmpty);
    await session.close();
  });

  test('rejects tampered and replayed frames', () async {
    final raw = _FakePeerSession();
    final session = AuthenticatedPeerSession(
      inner: raw,
      sessionId: sessionId,
      sessionKey: key,
      expiresAt: expiresAt,
    );
    final received = <Map<String, dynamic>>[];
    final subscription = session.messages.listen(received.add);
    final payload = {'requestId': 'r1'};
    final valid = frameFor(
      sequence: 0,
      type: 'direct_response',
      payload: payload,
      mac: macFor(sequence: 0, type: 'direct_response', payload: payload),
    );

    raw.incoming.add({...valid, 'mac': 'tampered'});
    raw.incoming.add(valid);
    raw.incoming.add(valid);
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.single['type'], 'direct_response');
    await subscription.cancel();
    await session.close();
  });

  test('does not send after session expiry', () async {
    final raw = _FakePeerSession();
    final session = AuthenticatedPeerSession(
      inner: raw,
      sessionId: sessionId,
      sessionKey: key,
      expiresAt: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
    );

    await expectLater(
      session.send('direct_request', const {}),
      throwsA(isA<StateError>()),
    );
    await session.close();
  });
}
