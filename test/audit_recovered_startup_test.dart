import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/services/app_logging_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/data/app_store.dart';

void main() {
  final path = Platform.environment['VENTIO_RECOVERY_REHEARSAL'];
  test('recovered copy completes real database and AppStore startup twice', () async {
    if (path == null || !path.endsWith('.rehearsal.sqlite')) {
      throw StateError('An isolated rehearsal file is required.');
    }
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    for (var attempt = 0; attempt < 2; attempt++) {
      final db = VentioDriftDatabase(NativeDatabase(File(path)));
      await db.initializeFoundation();
      SqliteMigrationManager.attachDatabaseOverride(db);
      final store = AppStore();
      try {
        await store.initialize(hydrateHeavyData: false);
        expect(store.isReady, isTrue);
        expect((await AuditLogger.verifyIntegrity()).ok, isTrue);
        await store.prepareForShutdown();
      } finally {
        store.dispose();
        await LocalDatabaseService.resetForTesting();
      }
    }
  }, skip: path == null, timeout: const Timeout(Duration(minutes: 3)));
}
