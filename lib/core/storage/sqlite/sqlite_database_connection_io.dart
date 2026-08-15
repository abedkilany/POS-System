import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

QueryExecutor openVentioSqliteConnection() {
  return LazyDatabase(() async {
    final file =
        File(p.join(await getVentioSqliteDirectoryPath(), 'ventio.sqlite'));
    await file.parent.create(recursive: true);
    return NativeDatabase.createInBackground(file);
  });
}

Future<String> getVentioSqliteDirectoryPath() async {
  // Flutter tests must never open the user's real Ventio database. The test
  // suite intentionally resets and seeds SQLite, so using the production
  // APPDATA path here can overwrite a user's store with fixture data.
  if (Platform.environment['FLUTTER_TEST'] == 'true') {
    final testDir = Directory(
      p.join(Directory.systemTemp.path, 'ventio_flutter_test_$pid'),
    );
    await testDir.create(recursive: true);
    return testDir.path;
  }

  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      final dir = Directory(p.join(appData, 'ventio'));
      await dir.create(recursive: true);
      return dir.path;
    }
  }

  final appSupportDir = await getApplicationSupportDirectory();
  final dir = Directory(p.join(appSupportDir.path, 'ventio'));
  await dir.create(recursive: true);
  return dir.path;
}
