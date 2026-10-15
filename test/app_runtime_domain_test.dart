import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/data/app_store.dart';

void main() {
  test('runtime port preserves identity, profile, and readiness reads', () {
    final store = AppStore();
    addTearDown(store.dispose);

    expect(store.runtime.identity.platform, store.appIdentity.platform);
    expect(store.runtime.identity.deviceRole, store.appIdentity.deviceRole);
    expect(store.runtime.identity.syncMode, store.appIdentity.syncMode);
    expect(store.runtime.profile.toJson(), store.storeProfile.toJson());
    expect(store.runtime.isReady, store.isReady);
    expect(store.runtime.isCoreDataLoaded, store.isCoreDataLoaded);
    expect(store.runtime.isLedgerDataLoaded, store.isLedgerDataLoaded);
    expect(store.runtime.isSyncDataLoaded, store.isSyncDataLoaded);
    expect(store.runtime.isSuspendedByHost, store.isSuspendedByHost);
    expect(
      store.runtime.suspendedByHostReason,
      store.suspendedByHostReason,
    );
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

      expect(await store.loadLocale(), const Locale('ar'));
      expect(await store.loadThemeMode(), ThemeMode.dark);
    } finally {
      store.dispose();
      await LocalDatabaseService.resetForTesting();
    }
  });
}
