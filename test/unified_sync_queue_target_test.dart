import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/sync_unified/sync_contracts.dart';

void main() {
  test('LAN and Direct use the stable Host-facing queue target', () {
    expect(UnifiedSyncQueueTarget.host, 'host');
  });
}
