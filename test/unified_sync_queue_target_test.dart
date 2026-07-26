import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/sync_unified/sync_contracts.dart';

void main() {
  test('LAN and Cloud use stable Host-facing queue targets', () {
    expect(UnifiedSyncQueueTarget.host, 'host');
    expect(UnifiedSyncQueueTarget.cloudHost, 'cloud_host');
    expect(UnifiedSyncQueueTarget.cloudAuthority, 'cloud');
    expect(UnifiedSyncQueueTarget.host,
        isNot(UnifiedSyncQueueTarget.cloudHost));
  });
}
