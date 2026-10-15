part of 'app_store.dart';

class AppStoreRecoveryService {
  AppStoreRecoveryService(this.store);

  final AppStore store;

  Future<String> exportBackupJson() async {
    store.requirePermission(AppPermission.backupExport);
    final payload = await store._backupPayload(includeDeviceAndSyncState: true);
    return compute(_encodePrettyBackupPayload, payload);
  }
}
