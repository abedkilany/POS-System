import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../models/app_identity.dart';
import 'direct_device_identity.dart';
import 'secure_peer_session.dart';
import 'sync_diagnostics_log.dart';

/// Authenticates the two already-signaled WebRTC peers before sync traffic is
/// allowed. The signaling server supplies the expected peer device ID; the
/// signed nonces prevent a stale or replayed handshake from being accepted.
class DirectPeerHandshake {
  static const _version = 1;
  static const _timeout = Duration(seconds: 15);

  static Future<DirectPeerSessionMaterial> authenticateClient({
    required SecurePeerSession session,
    required AppIdentity identity,
    required String expectedHostDeviceId,
    String expectedHostPublicKey = '',
  }) async {
    SyncDiagnosticsLog.add('[DIRECT_HANDSHAKE] client start');
    final local = await DirectDeviceIdentity.loadOrCreate();
    final clientNonce = _nonce();
    final expiresAtMs = _sessionExpiryMs();
    final hello = {
      ..._packet(
        role: 'client',
        deviceId: identity.deviceId,
        storeId: identity.storeId,
        branchId: identity.branchId,
        nonce: clientNonce,
        publicKey: local.publicKeyEncoded,
        expiresAtMs: expiresAtMs,
      ),
      'type': 'direct_handshake_hello',
    };
    await session.send('direct_handshake_hello', {
      ...hello,
      'signature': local.sign(_canonical(hello)),
    });
    SyncDiagnosticsLog.add('[DIRECT_HANDSHAKE] client hello sent');

    final challenge = await _next(session, 'direct_handshake_challenge');
    SyncDiagnosticsLog.add('[DIRECT_HANDSHAKE] client challenge received');
    _validatePeerPacket(
      challenge,
      role: 'host',
      expectedDeviceId: expectedHostDeviceId,
      identity: identity,
      expectedNonce: clientNonce,
    );
    // The Host challenge carries its own nonce in `nonce`; `peerNonce` is
    // the Client nonce echoed back for scope validation.
    final hostNonce = challenge['nonce']?.toString().trim() ?? '';
    final hostPublicKey = challenge['publicKey']?.toString().trim() ?? '';
    if (hostNonce.isEmpty)
      throw StateError('Direct handshake host nonce missing.');
    if (expectedHostPublicKey.trim().isNotEmpty &&
        hostPublicKey != expectedHostPublicKey.trim()) {
      throw StateError(
          'Direct Host public key does not match the registered key.');
    }
    if (!await DirectDeviceIdentity.verifyOrTrustPeer(
      deviceId: expectedHostDeviceId,
      publicKeyEncoded: hostPublicKey,
    )) {
      throw StateError('Direct Host public key changed unexpectedly.');
    }
    final ack = {
      ..._packet(
        role: 'client',
        deviceId: identity.deviceId,
        storeId: identity.storeId,
        branchId: identity.branchId,
        nonce: clientNonce,
        peerNonce: hostNonce,
        publicKey: local.publicKeyEncoded,
        expiresAtMs: expiresAtMs,
      ),
      'type': 'direct_handshake_ack',
    };
    await session.send('direct_handshake_ack', {
      ...ack,
      'signature': local.sign(_canonical(ack)),
    });
    SyncDiagnosticsLog.add('[DIRECT_HANDSHAKE] client ack sent');
    return _material(
      clientNonce: clientNonce,
      hostNonce: hostNonce,
      clientPublicKey: local.publicKeyEncoded,
      hostPublicKey: hostPublicKey,
      expiresAtMs: int.parse(challenge['expiresAtMs'].toString()),
    );
  }

  static Future<DirectPeerSessionMaterial> authenticateHost({
    required SecurePeerSession session,
    required AppIdentity identity,
    required String expectedClientDeviceId,
    String expectedClientPublicKey = '',
  }) async {
    SyncDiagnosticsLog.add('[DIRECT_HANDSHAKE] host start');
    final local = await DirectDeviceIdentity.loadOrCreate();
    final hello = await _next(session, 'direct_handshake_hello');
    SyncDiagnosticsLog.add('[DIRECT_HANDSHAKE] host hello received');
    _validatePacketScope(hello, identity);
    final clientId = hello['deviceId']?.toString().trim() ?? '';
    if (clientId != expectedClientDeviceId) {
      throw StateError('Direct handshake peer device mismatch.');
    }
    final clientNonce = hello['nonce']?.toString().trim() ?? '';
    final clientPublicKey = hello['publicKey']?.toString().trim() ?? '';
    if (clientNonce.isEmpty ||
        clientPublicKey.isEmpty ||
        !DirectDeviceIdentity.verify(
          message: _canonical(hello),
          signatureEncoded: hello['signature']?.toString() ?? '',
          publicKeyEncoded: clientPublicKey,
        )) {
      throw StateError('Direct client handshake signature is invalid.');
    }
    if (expectedClientPublicKey.trim().isNotEmpty &&
        clientPublicKey != expectedClientPublicKey.trim()) {
      throw StateError(
          'Direct Client public key does not match the registered key.');
    }
    if (!await DirectDeviceIdentity.verifyOrTrustPeer(
      deviceId: clientId,
      publicKeyEncoded: clientPublicKey,
    )) {
      throw StateError('Direct Client public key changed unexpectedly.');
    }

    final hostNonce = _nonce();
    final expiresAtMs = int.parse(hello['expiresAtMs'].toString());
    final challenge = {
      ..._packet(
        role: 'host',
        deviceId: identity.deviceId,
        storeId: identity.storeId,
        branchId: identity.branchId,
        nonce: hostNonce,
        peerNonce: clientNonce,
        publicKey: local.publicKeyEncoded,
        expiresAtMs: expiresAtMs,
      ),
      'type': 'direct_handshake_challenge',
    };
    await session.send('direct_handshake_challenge', {
      ...challenge,
      'signature': local.sign(_canonical(challenge)),
    });
    SyncDiagnosticsLog.add('[DIRECT_HANDSHAKE] host challenge sent');

    final ack = await _next(session, 'direct_handshake_ack');
    SyncDiagnosticsLog.add('[DIRECT_HANDSHAKE] host ack received');
    _validatePacketScope(ack, identity);
    final deviceMatches =
        ack['deviceId']?.toString().trim() == expectedClientDeviceId;
    final nonceMatches = ack['nonce']?.toString().trim() == clientNonce;
    final peerNonceMatches = ack['peerNonce']?.toString().trim() == hostNonce;
    final expiryMatches =
        ack['expiresAtMs']?.toString() == expiresAtMs.toString();
    final keyMatches = ack['publicKey']?.toString().trim() == clientPublicKey;
    final signatureValid = DirectDeviceIdentity.verify(
      message: _canonical(ack),
      signatureEncoded: ack['signature']?.toString() ?? '',
      publicKeyEncoded: clientPublicKey,
    );
    if (!deviceMatches ||
        !nonceMatches ||
        !peerNonceMatches ||
        !expiryMatches ||
        !keyMatches ||
        !signatureValid) {
      SyncDiagnosticsLog.add(
          '[DIRECT_HANDSHAKE] host ack rejected device=$deviceMatches '
          'nonce=$nonceMatches peerNonce=$peerNonceMatches '
          'expiry=$expiryMatches key=$keyMatches signature=$signatureValid');
      throw StateError('Direct client handshake acknowledgement is invalid.');
    }
    SyncDiagnosticsLog.add('[DIRECT_HANDSHAKE] host success');
    return _material(
      clientNonce: clientNonce,
      hostNonce: hostNonce,
      clientPublicKey: clientPublicKey,
      hostPublicKey: local.publicKeyEncoded,
      expiresAtMs: expiresAtMs,
    );
  }

  static DirectPeerSessionMaterial _material({
    required String clientNonce,
    required String hostNonce,
    required String clientPublicKey,
    required String hostPublicKey,
    required int expiresAtMs,
  }) {
    final seed = utf8.encode(
      'ventio-direct-session-v1|$clientNonce|$hostNonce|'
      '$clientPublicKey|$hostPublicKey',
    );
    final key = sha256.convert(seed).bytes;
    final sessionId = sha256.convert(<int>[...key, ...seed]).toString();
    return DirectPeerSessionMaterial(
      sessionId: sessionId,
      sessionKey: key,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMs, isUtc: true),
    );
  }

  static Future<Map<String, dynamic>> _next(
    SecurePeerSession session,
    String type,
  ) async {
    try {
      return await session.messages
          .firstWhere((message) => message['type']?.toString() == type)
          .timeout(_timeout);
    } on TimeoutException {
      SyncDiagnosticsLog.add('[DIRECT_HANDSHAKE] timeout waiting=$type');
      throw TimeoutException('Direct handshake timed out waiting for $type.');
    }
  }

  static void _validatePeerPacket(
    Map<String, dynamic> packet, {
    required String role,
    required String expectedDeviceId,
    required AppIdentity identity,
    required String expectedNonce,
  }) {
    _validatePacketScope(packet, identity);
    if (packet['role']?.toString() != role ||
        packet['deviceId']?.toString().trim() != expectedDeviceId ||
        packet['peerNonce']?.toString().trim() != expectedNonce) {
      throw StateError('Direct handshake peer identity mismatch.');
    }
    final publicKey = packet['publicKey']?.toString().trim() ?? '';
    if (publicKey.isEmpty ||
        !DirectDeviceIdentity.verify(
          message: _canonical(packet),
          signatureEncoded: packet['signature']?.toString() ?? '',
          publicKeyEncoded: publicKey,
        )) {
      throw StateError('Direct handshake peer signature is invalid.');
    }
  }

  static void _validatePacketScope(
      Map<String, dynamic> packet, AppIdentity identity) {
    if (packet['version'] != _version ||
        packet['storeId']?.toString() != identity.storeId ||
        packet['branchId']?.toString() != identity.branchId) {
      throw StateError('Direct handshake scope mismatch.');
    }
  }

  static Map<String, dynamic> _packet({
    required String role,
    required String deviceId,
    required String storeId,
    required String branchId,
    required String nonce,
    required String publicKey,
    required int expiresAtMs,
    String peerNonce = '',
  }) =>
      {
        'version': _version,
        'role': role,
        'deviceId': deviceId,
        'storeId': storeId,
        'branchId': branchId,
        'nonce': nonce,
        'peerNonce': peerNonce,
        'publicKey': publicKey,
        'expiresAtMs': expiresAtMs,
      };

  static int _sessionExpiryMs() => DateTime.now()
      .toUtc()
      .add(const Duration(minutes: 30))
      .millisecondsSinceEpoch;

  static String _nonce() {
    final random = Random.secure();
    return base64UrlEncode(
        Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256))));
  }

  static Uint8List _canonical(Map<String, dynamic> packet) {
    final copy = Map<String, dynamic>.from(packet)..remove('signature');
    return Uint8List.fromList(utf8.encode(jsonEncode({
      'branchId': copy['branchId'] ?? '',
      'deviceId': copy['deviceId'] ?? '',
      'nonce': copy['nonce'] ?? '',
      'peerNonce': copy['peerNonce'] ?? '',
      'publicKey': copy['publicKey'] ?? '',
      'role': copy['role'] ?? '',
      'storeId': copy['storeId'] ?? '',
      'type': copy['type'] ?? '',
      'version': copy['version'] ?? 0,
      'expiresAtMs': copy['expiresAtMs'] ?? 0,
    })));
  }
}

class DirectPeerSessionMaterial {
  const DirectPeerSessionMaterial({
    required this.sessionId,
    required this.sessionKey,
    required this.expiresAt,
  });

  final String sessionId;
  final List<int> sessionKey;
  final DateTime expiresAt;
}
