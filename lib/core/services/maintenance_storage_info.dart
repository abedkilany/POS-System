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
    this.legacyHiveFilePath = '',
    this.legacyHiveExists = false,
    this.legacyHiveSizeBytes = 0,
    this.discoveredSqliteFiles = const <String>[],
  });

  final String databaseDirectoryPath;
  final String databaseFilePath;
  final int databaseSizeBytes;
  final bool exists;
  final String platformLabel;

  /// Active local database engine used by modern Ventio builds.
  final String databaseEngine;

  /// Legacy Hive file details are reported for migration diagnostics only.
  /// Missing Hive is OK after SQLite phase 3B has been validated.
  final String legacyHiveFilePath;
  final bool legacyHiveExists;
  final int legacyHiveSizeBytes;

  /// All SQLite candidates found under the Ventio app storage folder.
  final List<String> discoveredSqliteFiles;
}

Future<MaintenanceStorageInfo> getMaintenanceStorageInfo() => getMaintenanceStorageInfoImpl();
