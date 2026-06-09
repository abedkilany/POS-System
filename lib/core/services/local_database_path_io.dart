import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<Directory> _ventioHiveDirectory({required bool create}) async {
  Directory dir;
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      dir = Directory(p.join(appData, 'ventio'));
    } else {
      final appSupportDir = await getApplicationSupportDirectory();
      dir = Directory(p.join(appSupportDir.path, 'ventio'));
    }
  } else {
    final appSupportDir = await getApplicationSupportDirectory();
    dir = Directory(p.join(appSupportDir.path, 'ventio'));
  }

  if (create) await dir.create(recursive: true);
  return dir;
}

Future<String> getVentioHiveDirectoryPathImpl() async {
  final dir = await _ventioHiveDirectory(create: true);
  return dir.path;
}

Future<bool> hasLegacyVentioHiveDatabaseImpl() async {
  final dir = await _ventioHiveDirectory(create: false);
  final hiveFile = File(p.join(dir.path, 'ventio.hive'));
  return hiveFile.exists();
}

Future<void> retireLegacyVentioHiveFilesIfPresentImpl() async {
  final dir = await _ventioHiveDirectory(create: false);
  if (!await dir.exists()) return;

  final fixedNames = <String>{
    'ventio.hive',
    'ventio.lock',
  };

  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (fixedNames.contains(name) || name.startsWith('ventio.hive')) {
      try {
        await entity.delete();
      } catch (_) {
        // Best-effort cleanup only. A locked legacy Hive file should not block
        // the SQLite-authoritative app startup path.
      }
    }
  }
}
