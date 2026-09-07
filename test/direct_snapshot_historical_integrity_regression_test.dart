import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Direct bootstrap uses the same snapshot acceptance policy as LAN', () {
    final recovery =
        File('lib/data/app_store_recovery.dart').readAsStringSync();
    final directProtocol =
        File('lib/core/services/direct_sync_protocol_service.dart')
            .readAsStringSync();
    final pairingFlow =
        File('lib/core/sync_unified/unified_pairing_snapshot_flow.dart')
            .readAsStringSync();

    expect(recovery, isNot(contains('_assertSnapshotBusinessIntegrity')));
    expect(
      recovery,
      isNot(contains('alreadyInTransaction: true')),
    );
    expect(directProtocol, isNot(contains('verifyLocalData: true')));

    final directStart = pairingFlow.indexOf('applyForDirect');
    final lanStart = pairingFlow.indexOf('applyForLan');
    expect(directStart, greaterThanOrEqualTo(0));
    expect(lanStart, greaterThan(directStart));
    final directSection = pairingFlow.substring(directStart, lanStart);
    expect(directSection, isNot(contains('verifyLocalData: true')));
  });
}
