import 'package:flutter_test/flutter_test.dart';

import 'package:ventio/core/sync_unified/unified_sync_policy.dart';
import 'package:ventio/models/app_identity.dart';

void main() {
  group('UnifiedSyncPolicy', () {
    test('allows LAN only for a configured Host or the active LAN client', () {
      final host = AppIdentity.defaults(
        deviceId: 'DV-HOST',
        platform: AppPlatformType.windows,
      ).copyWith(
        deviceRole: DeviceRole.host,
        activeSyncTransport: 'lan',
      );
      final client = AppIdentity.defaults(
        deviceId: 'DV-CLIENT',
        platform: AppPlatformType.windows,
      ).copyWith(
        deviceRole: DeviceRole.client,
        hostDeviceId: 'DV-HOST',
        activeSyncTransport: 'lan',
      );
      final directClient = client.copyWith(activeSyncTransport: 'direct');

      expect(
        UnifiedSyncPolicy.isLanAllowedForCurrentRole(
          host,
          setupComplete: true,
          isHostModeEnabled: true,
          isClientModeEnabled: false,
        ),
        isTrue,
      );
      expect(
        UnifiedSyncPolicy.isLanAllowedForCurrentRole(
          client,
          setupComplete: true,
          isHostModeEnabled: false,
          isClientModeEnabled: true,
        ),
        isTrue,
      );
      expect(
        UnifiedSyncPolicy.isLanAllowedForCurrentRole(
          directClient,
          setupComplete: true,
          isHostModeEnabled: false,
          isClientModeEnabled: true,
        ),
        isFalse,
      );
    });

    test('allows Direct for a Host or the active Direct client', () {
      final host = AppIdentity.defaults(
        deviceId: 'DV-HOST',
        platform: AppPlatformType.web,
      ).copyWith(
        deviceRole: DeviceRole.host,
        syncMode: SyncMode.directConnected,
        activeSyncTransport: 'direct',
      );
      final client = AppIdentity.defaults(
        deviceId: 'DV-CLIENT',
        platform: AppPlatformType.web,
      ).copyWith(
        deviceRole: DeviceRole.client,
        hostDeviceId: 'DV-HOST',
        syncMode: SyncMode.directConnected,
        activeSyncTransport: 'direct',
      );
      final lanClient = client.copyWith(activeSyncTransport: 'lan');

      expect(UnifiedSyncPolicy.isDirectAllowedForCurrentRole(host), isTrue);
      expect(UnifiedSyncPolicy.isDirectAllowedForCurrentRole(client), isTrue);
      expect(
          UnifiedSyncPolicy.isDirectAllowedForCurrentRole(lanClient), isFalse);
    });

    test('gates Direct and LAN roles through shared policy', () {
      final host = AppIdentity.defaults(
        deviceId: 'DV-HOST',
        platform: AppPlatformType.web,
      ).copyWith(
        deviceRole: DeviceRole.host,
        syncMode: SyncMode.directConnected,
        activeSyncTransport: 'direct',
      );
      final client = AppIdentity.defaults(
        deviceId: 'DV-CLIENT',
        platform: AppPlatformType.web,
      ).copyWith(
        deviceRole: DeviceRole.client,
        hostDeviceId: 'DV-HOST',
        syncMode: SyncMode.directConnected,
        activeSyncTransport: 'direct',
      );

      expect(UnifiedSyncPolicy.canClaimLanPairingCode(host), isFalse);
      expect(UnifiedSyncPolicy.canClaimLanPairingCode(client), isTrue);
      expect(UnifiedSyncPolicy.canRebuildFromLanSnapshot(host), isFalse);
      expect(UnifiedSyncPolicy.canRebuildFromLanSnapshot(client), isTrue);
      expect(
        UnifiedSyncPolicy.shouldTrackRemoteSnapshotGeneration(host),
        isFalse,
      );
      expect(
        UnifiedSyncPolicy.shouldTrackRemoteSnapshotGeneration(client),
        isTrue,
      );
      expect(UnifiedSyncPolicy.isDirectHostAllowed(host), isTrue);
      expect(UnifiedSyncPolicy.isDirectHostAllowed(client), isFalse);
      expect(UnifiedSyncPolicy.isDirectClientAllowed(client), isTrue);
      expect(UnifiedSyncPolicy.isDirectClientAllowed(host), isFalse);
    });
  });
}
