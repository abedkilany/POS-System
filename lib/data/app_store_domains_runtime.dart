part of 'app_store.dart';

final class _AppRuntimeDomain implements AppRuntimeDomainPort {
  _AppRuntimeDomain(this._store);
  final AppStore _store;

  @override
  Future<void> initialize({bool hydrateHeavyData = true}) =>
      _AppStoreSplitStartupMigrations(_store)
          .initialize(hydrateHeavyData: hydrateHeavyData);

  @override
  Future<void> prepareForShutdown() =>
      _AppStoreSplitSyncApplyPart4(_store).prepareForShutdown();

  @override
  Future<ThemeMode> loadThemeMode() =>
      _AppStoreSplitAccessAuth(_store).loadThemeMode();

  @override
  Future<void> saveThemeMode(ThemeMode mode) =>
      _AppStoreSplitAccessAuth(_store).saveThemeMode(mode);

  @override
  Future<Locale> loadLocale() => _AppStoreSplitAccessAuth(_store).loadLocale();

  @override
  Future<void> saveLocale(Locale locale) =>
      _AppStoreSplitAccessAuth(_store).saveLocale(locale);

  @override
  AppIdentity get identity =>
      _store._appIdentity ??
      AppIdentity.defaults(
        deviceId: _store._deviceId,
        platform: _store._detectPlatform(),
      );

  @override
  StoreProfile get profile => _store._storeProfile;

  @override
  bool get isReady => _store._isReady;

  @override
  bool get isCoreDataLoaded => _store._isReady;

  @override
  bool get isLedgerDataLoaded => _store._isReady;

  @override
  bool get isSyncDataLoaded => _store._syncDataLoadCompleted;

  @override
  bool get isSuspendedByHost =>
      identity.isClient && ClientSuspensionStateStore.isSuspended;

  @override
  String get suspendedByHostReason => ClientSuspensionStateStore.reason;

  @override
  int get dashboardRevision => _store._dashboardRevisionReadImpl;

  @override
  int get reportsRevision => _store._reportsRevisionReadImpl;

  @override
  Future<void> updateIdentityDuringSetup(AppIdentity identity) =>
      _AppStoreSplitIdentityUsers(_store)
          .updateAppIdentityDuringSetup(identity);

  @override
  Future<void> updateIdentity(AppIdentity identity) =>
      _AppStoreSplitIdentityUsers(_store).updateAppIdentity(identity);

  @override
  Future<void> updateDeviceName(String deviceName) =>
      _AppStoreSplitIdentityUsers(_store).updateDeviceName(deviceName);

  @override
  Future<void> updateStoreProfile(StoreProfile profile) =>
      _AppStoreSplitPersistenceSyncCorePart3(_store)
          .updateStoreProfile(profile);

  @override
  Future<void> refreshAfterDatabaseChange(String key) =>
      _AppStoreSplitStartupMigrationsPart2(_store)
          .refreshAfterDatabaseChange(key);

  @override
  Future<void> refreshSalesProductData() =>
      _AppStoreSplitStartupMigrationsPart2(_store).refreshSalesProductData();

  @override
  Future<void> reloadAllAfterDatabaseChange() =>
      _AppStoreSplitStartupMigrationsPart2(_store)
          .reloadAllAfterDatabaseChange();

  @override
  Future<void> ensureHeavyDataLoaded({bool failOnError = false}) =>
      _AppStoreSplitCoreLoading(_store)
          .ensureHeavyDataLoaded(failOnError: failOnError);

  @override
  Future<void> markSuspendedByHost({String reason = ''}) =>
      _AppStoreSplitAccessAuth(_store).markSuspendedByHost(reason: reason);

  @override
  Future<void> clearSuspendedByHost() =>
      _AppStoreSplitAccessAuth(_store).clearSuspendedByHost();

  @override
  Future<void> recoverExistingStoreIdentity({
    required String storeId,
    String recoveryKey = '',
    String? branchId,
    String? hostDeviceId,
    String? deviceToken,
    String? controlPlaneTenantId,
    DeviceRole? deviceRole,
    SyncMode? syncMode,
  }) =>
      _AppStoreSplitIdentityUsers(_store).recoverExistingStoreIdentity(
        storeId: storeId,
        recoveryKey: recoveryKey,
        branchId: branchId,
        hostDeviceId: hostDeviceId,
        deviceToken: deviceToken,
        controlPlaneTenantId: controlPlaneTenantId,
        deviceRole: deviceRole,
        syncMode: syncMode,
      );

  @override
  void refreshUi() => _store.notifyListeners();
}
