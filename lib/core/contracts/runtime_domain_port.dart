import 'package:flutter/material.dart' show Locale, ThemeMode;
import '../../models/app_identity.dart';
import '../../models/store_profile.dart';

abstract class AppRuntimeDomainPort {
  Future<void> initialize({bool hydrateHeavyData = true});
  Future<void> prepareForShutdown();
  Future<ThemeMode> loadThemeMode();
  Future<void> saveThemeMode(ThemeMode mode);
  Future<Locale> loadLocale();
  Future<void> saveLocale(Locale locale);
  AppIdentity get identity;
  StoreProfile get profile;
  bool get isReady;
  bool get isCoreDataLoaded;
  bool get isLedgerDataLoaded;
  bool get isSyncDataLoaded;
  bool get isSuspendedByHost;
  String get suspendedByHostReason;
  int get dashboardRevision;
  int get reportsRevision;
  Future<void> updateIdentityDuringSetup(AppIdentity identity);
  Future<void> updateIdentity(AppIdentity identity);
  Future<void> updateDeviceName(String deviceName);
  Future<void> updateStoreProfile(StoreProfile profile);
  Future<void> refreshAfterDatabaseChange(String key);
  Future<void> refreshSalesProductData();
  Future<void> reloadAllAfterDatabaseChange();
  Future<void> ensureHeavyDataLoaded({bool failOnError = false});
  Future<void> markSuspendedByHost({String reason = ''});
  Future<void> clearSuspendedByHost();
  Future<void> recoverExistingStoreIdentity({
    required String storeId,
    String recoveryKey = '',
    String? branchId,
    String? hostDeviceId,
    String? deviceToken,
    String? controlPlaneTenantId,
    DeviceRole? deviceRole,
    SyncMode? syncMode,
  });
  void refreshUi();
}
