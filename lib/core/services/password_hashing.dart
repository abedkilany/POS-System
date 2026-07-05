import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;

import 'local_database_service.dart';

class PasswordHashing {
  PasswordHashing._();

  static const String passwordHashPrefix = 'pbkdf2sha256:';
  static const String legacyLocalCredentialHashPrefix = 'sha256salt:';
  static const int passwordHashIterations = 150000;

  static Future<String> hashPassword(String password) async {
    final salt = _generateSalt();
    final iterations = LocalDatabaseService.isInMemoryStoreForTesting
        ? 100000
        : passwordHashIterations;
    return compute(_hashPasswordInBackground, <String, String>{
      'password': password.trim(),
      'salt': salt,
      'iterations': iterations.toString(),
    });
  }

  static Future<bool> verifyPassword(String password, String storedHash) async {
    if (storedHash.startsWith(passwordHashPrefix)) {
      return compute(_verifyPasswordInBackground, <String, String>{
        'password': password.trim(),
        'storedHash': storedHash,
      });
    }
    return _verifyLegacyPassword(password.trim(), storedHash);
  }

  static String _hashPasswordInBackground(Map<String, String> request) {
    final password = request['password'] ?? '';
    final salt = request['salt'] ?? '';
    final iterations = int.tryParse(request['iterations'] ?? '') ?? 0;
    if (password.isEmpty || salt.isEmpty || iterations <= 0) {
      return '';
    }
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
    derivator.init(pc.Pbkdf2Parameters(base64Url.decode(salt), iterations, 32));
    final hash = derivator.process(
      Uint8List.fromList(utf8.encode('ventio|password|$password')),
    );
    return '$passwordHashPrefix$iterations:$salt:${base64UrlEncode(hash)}';
  }

  static bool _verifyPasswordInBackground(Map<String, String> request) {
    final password = request['password'] ?? '';
    final storedHash = request['storedHash'] ?? '';
    if (!storedHash.startsWith(passwordHashPrefix)) return false;
    final parts = storedHash.split(':');
    if (parts.length != 4) return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 100000) return false;
    return storedHash == _hashPasswordWithSalt(password, parts[2], iterations);
  }

  static bool _verifyLegacyPassword(String password, String storedHash) {
    if (!storedHash.startsWith(legacyLocalCredentialHashPrefix)) return false;
    final parts = storedHash.split(':');
    if (parts.length != 3) return false;
    return storedHash == _hashLegacyPasswordWithSalt(password, parts[1]);
  }

  static String _hashPasswordWithSalt(
    String password,
    String salt,
    int iterations,
  ) {
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
    derivator.init(pc.Pbkdf2Parameters(base64Url.decode(salt), iterations, 32));
    final hash = derivator.process(
      Uint8List.fromList(utf8.encode('ventio|password|$password')),
    );
    return '$passwordHashPrefix$iterations:$salt:${base64UrlEncode(hash)}';
  }

  static String _hashLegacyPasswordWithSalt(String password, String salt) {
    const legacyPurpose = 'store_manager_pro|local_pin_v2';
    List<int> digest = utf8.encode('$legacyPurpose|$salt|$password');
    for (var i = 0; i < 12000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return '$legacyLocalCredentialHashPrefix$salt:${base64UrlEncode(digest)}';
  }

  static String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}
