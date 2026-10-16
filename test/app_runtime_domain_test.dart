import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/data/app_store.dart';

void main() {
  test('runtime port preserves identity, profile, and readiness reads', () {
    final store = AppStore();
    addTearDown(store.dispose);

    final runtime = store.runtime;
    expect(runtime.identity.deviceId, isNotEmpty);
    expect(runtime.profile, isNotNull);
    expect(runtime.isReady, isFalse);
    expect(runtime.isCoreDataLoaded, isFalse);
    expect(runtime.isLedgerDataLoaded, isFalse);
    expect(runtime.isSyncDataLoaded, isFalse);
    expect(runtime.isSuspendedByHost, isFalse);
    expect(runtime.dashboardRevision, isNonNegative);
    expect(runtime.reportsRevision, isNonNegative);
  });

  test('runtime port preserves locale and theme preference behavior', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await LocalDatabaseService.resetForTesting();
    LocalDatabaseService.useInMemoryStoreForTesting();
    final store = AppStore();
    try {
      expect(await store.runtime.loadLocale(), const Locale('en'));
      expect(await store.runtime.loadThemeMode(), ThemeMode.system);

      await store.runtime.saveLocale(const Locale('ar'));
      await store.runtime.saveThemeMode(ThemeMode.dark);

      expect(await store.runtime.loadLocale(), const Locale('ar'));
      expect(await store.runtime.loadThemeMode(), ThemeMode.dark);
    } finally {
      store.dispose();
      await LocalDatabaseService.resetForTesting();
    }
  });
}
