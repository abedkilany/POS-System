import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/sync_unified/sync_transport_adapter.dart';
import 'package:ventio/models/app_identity.dart';

void main() {
  test('recognizes direct as a supported unified transport kind', () {
    expect(UnifiedSyncTransportKind.values,
        contains(UnifiedSyncTransportKind.direct));
  });

  test('preserves direct as the selected device transport', () {
    final identity = AppIdentity.defaults(
      deviceId: 'DV-DIRECT',
      platform: AppPlatformType.windows,
    ).copyWith(activeSyncTransport: 'direct');

    expect(identity.activeSyncTransportNormalized, 'direct');
    expect(identity.transportType, 'direct');
  });
}
