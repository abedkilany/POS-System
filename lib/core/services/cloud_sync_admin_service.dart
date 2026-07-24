import '../../data/app_store.dart';
import 'cloud_sync_service.dart';

/// Cloud-only administrative and recovery operations.
///
/// This facade keeps non-sync-runtime actions out of the unified sync path so
/// UI code can distinguish between "run sync" and "manage Cloud state".
class CloudSyncAdminService {
  CloudSyncAdminService(this.store);

  final AppStore store;

  CloudSyncService get _service => CloudSyncService(store);

  Future<bool?> checkPlanAccess(CloudSyncSettings settings) =>
      _service.checkCloudSyncPlanAccess(settings);

  Future<CloudPairingStatusResult> pairingCodeStatus(
    CloudSyncSettings settings,
    String code,
  ) =>
      _service.pairingCodeStatus(settings, code);

  Future<CloudSyncResult> requestHostTransfer(
    CloudSyncSettings settings, {
    String reason = '',
  }) =>
      _service.requestHostTransfer(settings, reason: reason);

  Future<CloudSyncResult> approveHostTransfer(
    CloudSyncSettings settings,
    String deviceId,
  ) =>
      _service.approveHostTransfer(settings, deviceId);

  Future<CloudSyncResult> activateHostTransfer(CloudSyncSettings settings) =>
      _service.activateHostTransfer(settings);

  Future<List<CloudDeviceStatus>> listDevices(CloudSyncSettings settings) =>
      _service.listDevices(settings);

  Future<CloudDevicesResult> listDevicesWithLimit(CloudSyncSettings settings) =>
      _service.listDevicesWithLimit(settings);

  Future<CloudSyncResult> repairLegacyCloudDeviceLinks(
    CloudSyncSettings settings, {
    required Iterable<String> clientDeviceIds,
  }) =>
      _service.repairLegacyCloudDeviceLinks(
        settings,
        clientDeviceIds: clientDeviceIds,
      );

  Future<CloudSyncResult> setDeviceSuspended(
    CloudSyncSettings settings,
    String deviceId, {
    required bool suspended,
  }) =>
      _service.setDeviceSuspended(
        settings,
        deviceId,
        suspended: suspended,
      );

  Future<CloudSyncResult> revokeDevice(
    CloudSyncSettings settings,
    String deviceId,
  ) =>
      _service.revokeDevice(settings, deviceId);

  Future<CloudSyncResult> deleteDeviceRecord(
    CloudSyncSettings settings,
    String deviceId,
  ) =>
      _service.deleteDeviceRecord(settings, deviceId);

  Future<CloudSyncResult> registerCurrentDevice(
    CloudSyncSettings settings, {
    String transport = 'cloud',
  }) =>
      _service.registerCurrentDevice(settings, transport: transport);

  Future<void> publishBootstrapSnapshotToCloud(
    CloudSyncSettings settings, {
    bool force = false,
    void Function(double value, String label)? onProgress,
  }) =>
      _service.publishBootstrapSnapshotToCloud(
        settings,
        force: force,
        onProgress: onProgress,
      );

  Future<CloudSyncResult> pushPendingForUnifiedEngine(
    CloudSyncSettings settings,
  ) =>
      _service.pushPendingForUnifiedEngine(settings);

  Future<CloudStoreRecoveryResult> recoverExistingStoreIdentityFromCloud(
    CloudSyncSettings settings, {
    required String storeId,
    required String branchId,
  }) =>
      _service.recoverExistingStoreIdentityFromCloud(
        settings,
        storeId: storeId,
        branchId: branchId,
      );

  Future<CloudStoreRecoveryResult> recoverExistingStoreFromCloud(
    CloudSyncSettings settings, {
    required String storeId,
    required String branchId,
  }) =>
      _service.recoverExistingStoreFromCloud(
        settings,
        storeId: storeId,
        branchId: branchId,
      );
}
