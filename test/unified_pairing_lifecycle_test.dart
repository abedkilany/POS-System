import 'package:flutter_test/flutter_test.dart';

import 'package:ventio/core/sync_unified/unified_pairing_lifecycle.dart';
import 'package:ventio/models/app_identity.dart';

void main() {
  group('UnifiedPairingLifecycle', () {
    test('validates same-store pairing claims consistently', () {
      final current = AppIdentity.defaults(
        deviceId: 'DV-CLIENT',
        platform: AppPlatformType.windows,
      ).copyWith(
        deviceRole: DeviceRole.client,
        storeId: 'ST-ONE',
        branchId: 'BR-MAIN',
        hostDeviceId: 'DV-HOST',
      );

      expect(
        UnifiedPairingLifecycle.validateSameStoreClaim(
          current,
          const UnifiedPairingClaimPayload(
            storeId: 'ST-ONE',
            branchId: 'BR-MAIN',
            hostDeviceId: 'DV-HOST',
          ),
        ),
        isNull,
      );

      expect(
        UnifiedPairingLifecycle.validateSameStoreClaim(
          current,
          const UnifiedPairingClaimPayload(
            storeId: 'ST-TWO',
            branchId: 'BR-MAIN',
            hostDeviceId: 'DV-HOST',
          ),
          label: 'LAN pairing',
        ),
        contains('LAN pairing belongs to a different Store'),
      );
    });

    test('builds a normalized client identity for claimed pairing', () {
      final current = AppIdentity.defaults(
        deviceId: 'DV-OLD',
        platform: AppPlatformType.web,
      ).copyWith(
        deviceRole: DeviceRole.client,
        storeId: 'ST-OLD',
        branchId: 'BR-OLD',
        hostDeviceId: 'DV-OLD-HOST',
        deviceToken: 'old-token',
      );

      final identity = UnifiedPairingLifecycle.buildClientIdentity(
        current,
        claim: const UnifiedPairingClaimPayload(
          storeId: 'ST-NEW',
          branchId: 'BR-NEW',
          hostDeviceId: 'DV-HOST',
          deviceId: 'DV-CLIENT',
          deviceToken: 'new-token',
        ),
        syncMode: SyncMode.cloudConnected,
        activeTransport: 'cloud',
      );

      expect(identity.deviceRole, DeviceRole.client);
      expect(identity.storeId, 'ST-NEW');
      expect(identity.branchId, 'BR-NEW');
      expect(identity.hostDeviceId, 'DV-HOST');
      expect(identity.deviceId, 'DV-CLIENT');
      expect(identity.deviceToken, 'new-token');
      expect(identity.activeSyncTransportNormalized, 'cloud');
    });
  });
}
