import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/recovery_file_service.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/app_identity.dart';

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

void main() {
  final identity = AppIdentity(
    storeId: 'ST-TEST01',
    branchId: 'BR-TEST01',
    deviceId: 'DV-TEST01',
    deviceName: 'Recovery Test',
    platform: AppPlatformType.windows,
    deviceRole: DeviceRole.host,
    appRole: AppRole.store,
    syncMode: SyncMode.localOnly,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    recoveryKey: 'RK-TEST-RECOVERY',
    storeEpoch: 3,
  );

  final service = RecoveryFileService(identityProvider: () => identity);

  test('exports a signed v2 file and parses its normalized identity', () {
    final raw = service.exportRecoveryFileJson(
      controlPlaneApiUrl: '  https://control.example/api  ',
    );
    final payload = jsonDecode(raw) as Map<String, dynamic>;

    expect(payload['format'], 'ventio_store_recovery_file');
    expect(payload['version'], 2);
    expect(payload['generatedAt'], isA<String>());
    expect(payload['controlPlaneApiUrl'], 'https://control.example/api');
    expect(payload['signature'], isA<String>());
    expect(
      service.parseRecoveryFileJson(raw),
      <String, String>{
        'storeId': 'ST-TEST01',
        'branchId': 'BR-TEST01',
        'controlPlaneApiUrl': 'https://control.example/api',
        'recoveryKey': 'RK-TEST-RECOVERY',
      },
    );
  });

  test('rejects recovery files with a changed payload or signature', () {
    final raw = service.exportRecoveryFileJson();
    final changedPayload = Map<String, dynamic>.from(jsonDecode(raw) as Map)
      ..['controlPlaneApiUrl'] = 'https://changed.example';
    expect(
      () => service.parseRecoveryFileJson(jsonEncode(changedPayload)),
      throwsA(isA<ArgumentError>().having(
        (error) => error.message,
        'message',
        contains('checksum failed'),
      )),
    );

    final changedSignature = Map<String, dynamic>.from(jsonDecode(raw) as Map)
      ..['signature'] = 'invalid-signature';
    expect(
      () => service.parseRecoveryFileJson(jsonEncode(changedSignature)),
      throwsA(isA<ArgumentError>().having(
        (error) => error.message,
        'message',
        contains('signature failed'),
      )),
    );
  });

  test('continues to read legacy v1 recovery files without a signature', () {
    final legacy = <String, dynamic>{
      'format': 'ventio_store_recovery_file',
      'version': 1,
      'generatedAt': '2025-01-02T03:04:05.000Z',
      'storeId': 'st-legacy01',
      'branchId': 'br-legacy01',
      'controlPlaneApiUrl': ' https://legacy.example/api ',
      'recoveryKey': 'rk-legacy-recovery',
    };
    legacy['checksum'] = _checksum(legacy);

    expect(
      service.parseRecoveryFileJson(jsonEncode(legacy)),
      <String, String>{
        'storeId': 'ST-LEGACY01',
        'branchId': 'BR-LEGACY01',
        'controlPlaneApiUrl': 'https://legacy.example/api',
        'recoveryKey': 'RK-LEGACY-RECOVERY',
      },
    );
  });

  test('typed and compatibility APIs use the recovery file reader', () {
    final raw = service.exportRecoveryFileJson();
    final store = AppStore();

    expect(store.recovery.parseRecoveryFileJson(raw)['storeId'], 'ST-TEST01');
    expect(store.recovery.parseRecoveryFileJson(raw)['recoveryKey'],
        'RK-TEST-RECOVERY');
  });

  test('typed and compatibility exports retain the backup permission gate', () {
    final store = AppStore();

    expect(
      () => store.recovery.exportRecoveryFileJson(),
      throwsA(isA<StateError>()),
    );
    expect(
      () => store.recovery.exportRecoveryFileJson(),
      throwsA(isA<StateError>()),
    );
  });
}
