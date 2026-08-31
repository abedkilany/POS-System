import 'maintenance_storage_info.dart';

Future<MaintenanceStorageInfo> getMaintenanceStorageInfoImpl() async {
  return const MaintenanceStorageInfo(
    databaseDirectoryPath: 'browser-private-storage',
    databaseFilePath: 'browser-private-storage',
    databaseSizeBytes: 0,
    exists: true,
    platformLabel: 'web',
    databaseEngine: 'browser',
  );
}
