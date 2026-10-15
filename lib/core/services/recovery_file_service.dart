import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/app_identity.dart';

/// Encodes and validates the small recovery file used to reconnect a store.
///
/// This file contains store identity and recovery credentials only; full
/// business backup import/export remains a separate workflow.
class RecoveryFileService {
  const RecoveryFileService({required this.identityProvider});

  final AppIdentity Function() identityProvider;

  String exportRecoveryFileJson({String controlPlaneApiUrl = ''}) {
    final identity = identityProvider();
    final payload = <String, dynamic>{
      'format': 'ventio_store_recovery_file',
      'version': 2,
      'generatedAt': DateTime.now().toIso8601String(),
      'storeId': identity.storeId,
      'branchId': identity.branchId,
      'controlPlaneApiUrl': controlPlaneApiUrl.trim(),
      'recoveryKey': identity.recoveryKey,
      'storeEpoch': identity.storeEpoch,
    };
    payload['checksum'] = _checksum(payload);
    payload['signature'] = _signature(payload);
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Map<String, String> parseRecoveryFileJson(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw ArgumentError('Invalid recovery file.');
    }
    final payload = Map<String, dynamic>.from(decoded);
    if (payload['format']?.toString() != 'ventio_store_recovery_file') {
      throw ArgumentError('Invalid recovery file format.');
    }
    final version = (payload['version'] as num? ?? 0).toInt();
    if (version < 1 || version > 2) {
      throw ArgumentError('Unsupported recovery file version.');
    }
    final expected = payload['checksum']?.toString() ?? '';
    if (expected.isEmpty || expected != _checksum(payload)) {
      throw ArgumentError('Recovery file checksum failed.');
    }
    if (version >= 2) {
      final signature = payload['signature']?.toString() ?? '';
      if (signature.isEmpty || signature != _signature(payload)) {
        throw ArgumentError('Recovery file signature failed.');
      }
    }
    final storeId = payload['storeId']?.toString().trim().toUpperCase() ?? '';
    final branchId = payload['branchId']?.toString().trim().toUpperCase() ?? '';
    final recoveryKey =
        payload['recoveryKey']?.toString().trim().toUpperCase() ?? '';
    if (!storeId.startsWith('ST-') ||
        branchId.isEmpty ||
        !recoveryKey.startsWith('RK-')) {
      throw ArgumentError(
        'Recovery file is missing required store identity fields.',
      );
    }
    return {
      'storeId': storeId,
      'branchId': branchId,
      'controlPlaneApiUrl':
          payload['controlPlaneApiUrl']?.toString().trim() ?? '',
      'recoveryKey': recoveryKey,
    };
  }

  String _checksum(Map<String, dynamic> payload) {
    final copy = Map<String, dynamic>.from(payload)
      ..remove('checksum')
      ..remove('signature');
    final canonical = jsonEncode(
      Map.fromEntries(
        copy.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
    );
    var hash = 2166136261;
    for (final unit in canonical.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String _signature(Map<String, dynamic> payload) {
    final copy = Map<String, dynamic>.from(payload)
      ..remove('checksum')
      ..remove('signature');
    final canonical = jsonEncode(
      Map.fromEntries(
        copy.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
    );
    final storeSecret =
        "${copy['storeId'] ?? ''}|${copy['branchId'] ?? ''}|${copy['recoveryKey'] ?? ''}|${copy['storeEpoch'] ?? ''}";
    return Hmac(sha256, utf8.encode(storeSecret))
        .convert(utf8.encode(canonical))
        .toString();
  }
}
