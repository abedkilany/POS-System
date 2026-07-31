import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart' as pc;

/// Persistent signing identity for the Direct transport.
///
/// The private scalar is kept in platform secure storage. The public key is
/// exchanged during the Direct handshake and never used as a secret.
class DirectDeviceIdentity {
  DirectDeviceIdentity._({
    required this.privateKey,
    required this.publicKey,
  });

  static const _privateKeyStorageKey = 'direct_device_private_key_v1';
  static const _publicKeyStorageKey = 'direct_device_public_key_v1';
  static const _trustedPeersStorageKey = 'direct_trusted_peer_keys_v1';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  final pc.ECPrivateKey privateKey;
  final pc.ECPublicKey publicKey;

  String get publicKeyEncoded => base64UrlEncode(publicKeyBytes);

  String get fingerprint => sha256.convert(publicKeyBytes).toString();

  Uint8List get publicKeyBytes => publicKey.Q!.getEncoded(false);

  /// Trust-on-first-use pinning for the current peer.
  static Future<bool> verifyOrTrustPeer({
    required String deviceId,
    required String publicKeyEncoded,
  }) async {
    final normalizedId = deviceId.trim();
    final normalizedKey = publicKeyEncoded.trim();
    if (normalizedId.isEmpty || normalizedKey.isEmpty) return false;
    final raw = await _storage.read(key: _trustedPeersStorageKey);
    Map<String, dynamic> peers = <String, dynamic>{};
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) peers = Map<String, dynamic>.from(decoded);
      } catch (_) {
        return false;
      }
    }
    final existing = peers[normalizedId]?.toString().trim() ?? '';
    if (existing.isNotEmpty) return existing == normalizedKey;
    peers[normalizedId] = normalizedKey;
    await _storage.write(
      key: _trustedPeersStorageKey,
      value: jsonEncode(peers),
    );
    return true;
  }

  static Future<DirectDeviceIdentity> loadOrCreate() async {
    final storedPrivate = await _storage.read(key: _privateKeyStorageKey);
    final storedPublic = await _storage.read(key: _publicKeyStorageKey);
    if (storedPrivate != null && storedPublic != null) {
      try {
        final identity = _fromEncoded(storedPrivate, storedPublic);
        if (identity != null) return identity;
      } catch (_) {
        // Corrupt or incompatible key material is replaced below.
      }
    }

    final generated = _generate();
    await _storage.write(
      key: _privateKeyStorageKey,
      value: base64UrlEncode(_privateBytes(generated.privateKey.d!)),
    );
    await _storage.write(
      key: _publicKeyStorageKey,
      value: generated.publicKeyEncoded,
    );
    return generated;
  }

  String sign(Uint8List message) {
    final signer = pc.ECDSASigner(
      pc.SHA256Digest(),
      pc.HMac(pc.SHA256Digest(), 64),
    )..init(true, pc.PrivateKeyParameter<pc.ECPrivateKey>(privateKey));
    final signature = signer.generateSignature(message) as pc.ECSignature;
    return base64UrlEncode(
      Uint8List.fromList([
        ..._bigIntBytes(signature.r, 32),
        ..._bigIntBytes(signature.s, 32),
      ]),
    );
  }

  static bool verify({
    required Uint8List message,
    required String signatureEncoded,
    required String publicKeyEncoded,
  }) {
    try {
      final signatureBytes = base64Url.decode(signatureEncoded);
      if (signatureBytes.length != 64) return false;
      final publicBytes = base64Url.decode(publicKeyEncoded);
      final curve = pc.ECCurve_secp256r1();
      final point = curve.curve.decodePoint(publicBytes);
      if (point == null) return false;
      final signer = pc.ECDSASigner(pc.SHA256Digest())
        ..init(
          false,
          pc.PublicKeyParameter<pc.ECPublicKey>(
            pc.ECPublicKey(point, curve),
          ),
        );
      return signer.verifySignature(
        message,
        pc.ECSignature(
          _bigIntFromBytes(signatureBytes.sublist(0, 32)),
          _bigIntFromBytes(signatureBytes.sublist(32)),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  static DirectDeviceIdentity? _fromEncoded(
    String privateEncoded,
    String publicEncoded,
  ) {
    final curve = pc.ECCurve_secp256r1();
    final privateBytes = base64Url.decode(privateEncoded);
    final publicBytes = base64Url.decode(publicEncoded);
    if (privateBytes.length != 32 || publicBytes.length != 65) return null;
    final point = curve.curve.decodePoint(publicBytes);
    if (point == null) return null;
    return DirectDeviceIdentity._(
      privateKey: pc.ECPrivateKey(_bigIntFromBytes(privateBytes), curve),
      publicKey: pc.ECPublicKey(point, curve),
    );
  }

  static DirectDeviceIdentity _generate() {
    final curve = pc.ECCurve_secp256r1();
    final random = math.Random.secure();
    BigInt scalar;
    do {
      final bytes = Uint8List.fromList(
        List<int>.generate(32, (_) => random.nextInt(256)),
      );
      scalar = _bigIntFromBytes(bytes);
    } while (scalar == BigInt.zero || scalar >= curve.n);
    final point = curve.G * scalar;
    return DirectDeviceIdentity._(
      privateKey: pc.ECPrivateKey(scalar, curve),
      publicKey: pc.ECPublicKey(point, curve),
    );
  }

  static Uint8List _privateBytes(BigInt value) => _bigIntBytes(value, 32);

  static Uint8List _bigIntBytes(BigInt value, int length) {
    final hex = value.toRadixString(16).padLeft(length * 2, '0');
    return Uint8List.fromList(List<int>.generate(
      length,
      (index) => int.parse(hex.substring(index * 2, index * 2 + 2), radix: 16),
    ));
  }

  static BigInt _bigIntFromBytes(List<int> bytes) => BigInt.parse(
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
        radix: 16,
      );
}
