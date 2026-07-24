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
      final cloudClient = client.copyWith(activeSyncTransport: 'cloud');

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
          cloudClient,
          setupComplete: true,
          isHostModeEnabled: false,
          isClientModeEnabled: true,
        ),
        isFalse,
      );
    });

    test('allows Cloud only for a cloud-enabled Host or active Cloud client',
        () {
      final host = AppIdentity.defaults(
        deviceId: 'DV-HOST',
        platform: AppPlatformType.web,
      ).copyWith(
        deviceRole: DeviceRole.host,
        syncMode: SyncMode.cloudConnected,
        activeSyncTransport: 'cloud',
      );
      final client = AppIdentity.defaults(
        deviceId: 'DV-CLIENT',
        platform: AppPlatformType.web,
      ).copyWith(
        deviceRole: DeviceRole.client,
        hostDeviceId: 'DV-HOST',
        syncMode: SyncMode.cloudConnected,
        activeSyncTransport: 'cloud',
      );
      final lanClient = client.copyWith(activeSyncTransport: 'lan');

      expect(UnifiedSyncPolicy.isCloudAllowedForCurrentRole(host), isTrue);
      expect(UnifiedSyncPolicy.isCloudAllowedForCurrentRole(client), isTrue);
      expect(
          UnifiedSyncPolicy.isCloudAllowedForCurrentRole(lanClient), isFalse);
    });

    test('gates pairing and rebuild readiness through shared policy', () {
      final host = AppIdentity.defaults(
        deviceId: 'DV-HOST',
        platform: AppPlatformType.web,
      ).copyWith(
        deviceRole: DeviceRole.host,
        syncMode: SyncMode.cloudConnected,
        activeSyncTransport: 'cloud',
      );
      final client = AppIdentity.defaults(
        deviceId: 'DV-CLIENT',
        platform: AppPlatformType.web,
      ).copyWith(
        deviceRole: DeviceRole.client,
        hostDeviceId: 'DV-HOST',
        syncMode: SyncMode.cloudConnected,
        activeSyncTransport: 'cloud',
      );

      expect(
        UnifiedSyncPolicy.canCreateCloudPairingCode(
          host,
          settingsEnabled: true,
          hasApiBaseUrl: true,
        ),
        isTrue,
      );
      expect(
        UnifiedSyncPolicy.canCreateCloudPairingCode(
          client,
          settingsEnabled: true,
          hasApiBaseUrl: true,
        ),
        isFalse,
      );
      expect(UnifiedSyncPolicy.canClaimCloudPairingCode(host), isFalse);
      expect(UnifiedSyncPolicy.canClaimCloudPairingCode(client), isTrue);
      expect(
        UnifiedSyncPolicy.canRequestCloudSnapshot(
          client,
          isConfigured: true,
        ),
        isTrue,
      );
      expect(
        UnifiedSyncPolicy.canRebuildFromCloudSnapshot(
          client,
          isConfigured: true,
        ),
        isTrue,
      );
      expect(
        UnifiedSyncPolicy.canRebuildFromCloudSnapshot(
          host,
          isConfigured: true,
        ),
        isFalse,
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
      expect(UnifiedSyncPolicy.canCheckCloudPairingStatus(host), isTrue);
      expect(UnifiedSyncPolicy.canCheckCloudPairingStatus(client), isFalse);
      expect(UnifiedSyncPolicy.canSuspendCloudDevices(host), isTrue);
      expect(UnifiedSyncPolicy.canSuspendCloudDevices(client), isFalse);
      expect(UnifiedSyncPolicy.canRevokeCloudDevices(host), isTrue);
      expect(UnifiedSyncPolicy.canRevokeCloudDevices(client), isFalse);
      expect(UnifiedSyncPolicy.canRemoveCloudDevices(host), isTrue);
      expect(UnifiedSyncPolicy.canRemoveCloudDevices(client), isFalse);
      expect(UnifiedSyncPolicy.canRequestCloudHostTransfer(host), isFalse);
      expect(UnifiedSyncPolicy.canRequestCloudHostTransfer(client), isTrue);
      expect(UnifiedSyncPolicy.canApproveCloudHostTransfer(host), isTrue);
      expect(UnifiedSyncPolicy.canApproveCloudHostTransfer(client), isFalse);
      expect(UnifiedSyncPolicy.canRepairCloudDeviceLinks(host), isTrue);
      expect(UnifiedSyncPolicy.canRepairCloudDeviceLinks(client), isFalse);
    });
  });
}
