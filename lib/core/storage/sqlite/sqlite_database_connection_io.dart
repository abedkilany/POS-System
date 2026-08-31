import 'dart:io';
import 'dart:isolate';

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

final String _flutterTestDatabaseNamespace =
    '${pid}_${Isolate.current.hashCode}_${DateTime.now().microsecondsSinceEpoch}';

Future<String> getVentioSqliteDirectoryPath() async {
  // Flutter tests must never open the user's real Ventio database. Each test
  // suite runs in its own Dart isolate, while multiple suites can share the
  // same OS process. A PID-only directory therefore lets independent Drift
  // databases open the same ventio.sqlite and causes cross-suite locks/races.
  // Keep one stable namespace per isolate so a suite can reopen its own DB,
  // while different suites are physically isolated from each other.
  if (Platform.environment['FLUTTER_TEST'] == 'true') {
    final testDir = Directory(
      p.join(
        Directory.systemTemp.path,
        'ventio_flutter_test_$_flutterTestDatabaseNamespace',
      ),
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
