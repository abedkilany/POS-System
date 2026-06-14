import 'maintenance_storage_info_stub.dart'
    if (dart.library.io) 'maintenance_storage_info_io.dart';

class MaintenanceStorageInfo {
  const MaintenanceStorageInfo({
    required this.databaseDirectoryPath,
    required this.databaseFilePath,
    required this.databaseSizeBytes,
    required this.exists,
    required this.platformLabel,
    this.databaseEngine = 'sqlite',
    this.discoveredSqliteFiles = const <String>[],
  });

  final String databaseDirectoryPath;
  final String databaseFilePath;
  final int databaseSizeBytes;
  final bool exists;
  final String platformLabel;

  /// Active local database engine used by modern Ventio builds.
  final String databaseEngine;

  /// All SQLite candidates found under the Ventio app storage folder.
  final List<String> discoveredSqliteFiles;
}

Future<MaintenanceStorageInfo> getMaintenanceStorageInfo() => getMaintenanceStorageInfoImpl();
