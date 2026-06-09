import 'dart:io';

import 'package:path/path.dart' as p;

import '../storage/sqlite/sqlite_database_connection_io.dart';
import 'local_database_path.dart';
import 'maintenance_storage_info.dart';

Future<MaintenanceStorageInfo> getMaintenanceStorageInfoImpl() async {
  final directoryPath = await getVentioSqliteDirectoryPath();
  final directory = Directory(directoryPath);
  await directory.create(recursive: true);

  final preferredSqlitePath = p.join(directoryPath, 'ventio.sqlite');
  final sqliteFiles = await _findSqliteFiles(directory);
  final databaseFilePath = sqliteFiles.contains(preferredSqlitePath)
      ? preferredSqlitePath
      : (sqliteFiles.isNotEmpty ? sqliteFiles.first : preferredSqlitePath);
  final sqliteFile = File(databaseFilePath);
  final exists = await sqliteFile.exists();
  final size = exists ? await sqliteFile.length() : 0;

  final hiveDirectoryPath = await getVentioHiveDirectoryPath();
  final legacyHiveFilePath = p.join(hiveDirectoryPath, 'ventio.hive');
  final legacyHiveFile = File(legacyHiveFilePath);
  final legacyHiveExists = await legacyHiveFile.exists();
  final legacyHiveSize = legacyHiveExists ? await legacyHiveFile.length() : 0;

  return MaintenanceStorageInfo(
    databaseDirectoryPath: directoryPath,
    databaseFilePath: databaseFilePath,
    databaseSizeBytes: size,
    exists: exists,
    platformLabel: Platform.operatingSystem,
    databaseEngine: 'sqlite',
    legacyHiveFilePath: legacyHiveFilePath,
    legacyHiveExists: legacyHiveExists,
    legacyHiveSizeBytes: legacyHiveSize,
    discoveredSqliteFiles: sqliteFiles,
  );
}

Future<List<String>> _findSqliteFiles(Directory directory) async {
  if (!await directory.exists()) return const <String>[];

  final files = <File>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) continue;
    final lowerName = p.basename(entity.path).toLowerCase();
    if (lowerName.endsWith('.sqlite') || lowerName.endsWith('.db')) {
      files.add(entity);
    }
  }

  files.sort((a, b) {
    final aPreferred = p.basename(a.path).toLowerCase() == 'ventio.sqlite';
    final bPreferred = p.basename(b.path).toLowerCase() == 'ventio.sqlite';
    if (aPreferred != bPreferred) return aPreferred ? -1 : 1;
    final aModified = a.lastModifiedSync();
    final bModified = b.lastModifiedSync();
    return bModified.compareTo(aModified);
  });

  return files.map((file) => file.path).toList(growable: false);
}
