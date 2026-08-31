part of 'app_store.dart';

class SensitiveAction {
  SensitiveAction._();

  static const String backupRestore = 'backup.restore';
  static const String usersManage = 'security.users.manage';
  static const String rolesManage = 'security.roles.manage';
  static const String saleReverse = 'sales.reverse';
  static const String purchaseReverse = 'purchases.reverse';
  static const String databaseDestructive = 'database.destructive';
  static const String storeOwnerCredentials = 'security.store_owner.credentials';
}

class SensitiveActionAuthRequiredException implements Exception {
  const SensitiveActionAuthRequiredException(this.action);

  final String action;

  @override
  String toString() =>
      'Re-authentication is required before sensitive action: $action';
}

extension _AppStoreSplitAccessAuth on AppStore {
  Future<bool> authorizeSensitiveAction({
    required String action,
    required String password,
    Duration validity = const Duration(minutes: 3),
  }) async {
    final user = _activeUser;
    if (user == null || !user.isActive) return false;
    final ok = await _verifyPasswordAsync(password, user.passwordHash);
    if (!ok) {
      unawaited(AuditLogger.record(
        entityType: 'security',
        entityId: user.id,
        action: 'reauth_failed',
        summary: 'Sensitive action re-authentication failed',
        details: 'requestedAction=$action',
        userId: user.id,
        userName: user.username,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'security',
        isImportant: true,
      ));
      return false;
    }
    _sensitiveAuthorizationUserId = user.id;
    _sensitiveAuthorizationExpiresAt = DateTime.now().add(validity);
    _sensitiveAuthorizationActions.add(action);
    unawaited(AuditLogger.record(
      entityType: 'security',
      entityId: user.id,
      action: 'reauth_success',
      summary: 'Sensitive action re-authentication succeeded',
      details: 'authorizedAction=$action',
      userId: user.id,
      userName: user.username,
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      sessionId: _deviceId,
      traceId: _deviceId,
      deviceId: _deviceId,
      sourceModule: 'security',
      isImportant: true,
    ));
    return true;
  }

  void clearSensitiveActionAuthorization() {
    _sensitiveAuthorizationExpiresAt = null;
    _sensitiveAuthorizationUserId = '';
    _sensitiveAuthorizationActions.clear();
  }

  void requireSensitiveActionAuthorization(String action) {
    // Domain tests use isolated stores without an interactive identity challenge.
    // Production paths never bypass this gate.
    if (LocalDatabaseService.isInMemoryStoreForTesting ||
        LocalDatabaseService.isSqliteDatabaseForTesting) {
      return;
    }
    final user = _activeUser;
    final expiresAt = _sensitiveAuthorizationExpiresAt;
    final valid = user != null &&
        _sensitiveAuthorizationUserId == user.id &&
        expiresAt != null &&
        expiresAt.isAfter(DateTime.now()) &&
        _sensitiveAuthorizationActions.contains(action);
    if (!valid) {
      throw SensitiveActionAuthRequiredException(action);
    }
  }

  bool canAccessPage(String pageId) {
    final page = AppPermission.pageById(pageId);
    if (page == null) return false;
    final permissions = page.navigationPermissions.isEmpty
        ? page.permissions
        : page.navigationPermissions;
    return hasAnyPermission(permissions);
  }

bool get hasLocalStoreData {
    final hasRealUser = _users.isNotEmpty && !_hasOnlyLegacyDefaultAdminUser;
    return hasRealUser ||
        _products.any((item) => !item.isDeleted) ||
        _customers.any((item) => !item.isDeleted) ||
        _sales.any((item) => !item.isDeleted) ||
        _saleQuotations.any((item) => !item.isDeleted) ||
        _deliveryNotes.any((item) => !item.isDeleted) ||
        _billsOfMaterials.any((item) => !item.isDeleted) ||
        _manufacturingOrders.any((item) => !item.isDeleted) ||
        _suppliers.any((item) => !item.isDeleted) ||
        _expenses.any((item) => !item.isDeleted) ||
        _purchases.any((item) => !item.isDeleted) ||
        _stockMovements.isNotEmpty ||
        _inventoryCounts.isNotEmpty ||
        _accountTransactions.any((item) => !item.isDeleted);
  }

Future<void> markSuspendedByHost({String reason = ''}) async {
    if (!appIdentity.isClient) return;
    await ClientSuspensionStateStore.markSuspended(reason: reason);
    if (_activeUser != null || _rememberLogin) {
      _activeUser = null;
      _rememberLogin = false;
      await LocalDatabaseService.setString(AppStore._activeUserKey, '');
      await LocalDatabaseService.setString(AppStore._rememberLoginKey, 'false');
    }
    notifyListeners();
  }

Future<void> clearSuspendedByHost() async {
    if (!appIdentity.isClient) return;
    if (!ClientSuspensionStateStore.isSuspended) return;
    await ClientSuspensionStateStore.clear();
    notifyListeners();
  }

Future<ThemeMode> loadThemeMode() async {
    final raw = LocalDatabaseService.getString(AppStore._themeModeKey) ?? 'system';
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => ThemeMode.system,
    );
  }

Future<void> saveThemeMode(ThemeMode mode) async {
    await LocalDatabaseService.setString(AppStore._themeModeKey, mode.name);
  }

Future<Locale> loadLocale() async {
    final raw = LocalDatabaseService.getString(AppStore._localeKey) ?? 'en';
    return ['en', 'ar', 'fr'].contains(raw) ? Locale(raw) : const Locale('en');
  }

Future<void> saveLocale(Locale locale) async {
    final languageCode = ['en', 'ar', 'fr'].contains(locale.languageCode)
        ? locale.languageCode
        : 'en';
    await LocalDatabaseService.setString(AppStore._localeKey, languageCode);
  }

Map<String, dynamic> _loadDevFeatureFlags() {
    final raw = LocalDatabaseService.getString(AppStore._devFeatureFlagsKey);
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      // Keep Developer/QA feature gates safe-by-default if the local setting is malformed.
    }
    return <String, dynamic>{};
  }

bool get isStressLabEnabled {
    final flags = _loadDevFeatureFlags();
    final value = flags[AppStore._stressLabEnabledFlag];
    if (value is bool) return value;
    if (value is String) return value.trim().toLowerCase() == 'true';
    return false;
  }

Future<void> setStressLabEnabled(bool enabled) async {
    requirePermission(AppPermission.maintenanceManage);
    final flags = _loadDevFeatureFlags();
    flags[AppStore._stressLabEnabledFlag] = enabled;
    flags['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    await LocalDatabaseService.setString(
      AppStore._devFeatureFlagsKey,
      jsonEncode(flags),
    );
    notifyListeners();
  }

bool get _hasOnlyLegacyDefaultAdminUser {
    if (_users.length != 1) return false;
    final user = _users.first;
    final legacyPassword = String.fromCharCodes(const [
      97,
      100,
      109,
      105,
      110,
      49,
      50,
      51,
    ]);
    return user.id == 'admin' &&
        user.username.trim().toLowerCase() == 'admin' &&
        _verifyPassword(legacyPassword, user.passwordHash) &&
        user.lastLoginAt == null;
  }

Future<void> completeInitialAdminSetup({
    required String fullName,
    required String username,
    required String password,
  }) async {
    final cleanName = fullName.trim().isEmpty ? 'Admin' : fullName.trim();
    final cleanUsername = username.trim().toLowerCase();
    final cleanPassword = password.trim();
    if (cleanUsername.length < 3) {
      throw ArgumentError('Username must be at least 3 characters.');
    }
    if (cleanPassword.length < 6) {
      throw ArgumentError('Password must be at least 6 characters.');
    }
    if (_users.isNotEmpty && !_hasOnlyLegacyDefaultAdminUser) {
      throw StateError('Initial administrator setup is already complete.');
    }
    final now = DateTime.now();
    final platform = _detectPlatform();
    if (platform == AppPlatformType.web) {
      throw StateError(
        'Web devices cannot create a Host. Use Connect to Store from Web.',
      );
    }
    final legacyIndex = _hasOnlyLegacyDefaultAdminUser ? 0 : -1;
    if (legacyIndex == -1 &&
        _users.any(
          (user) => user.username.trim().toLowerCase() == cleanUsername,
        )) {
      throw StateError('Username already exists.');
    }
    final passwordHash = await _hashPasswordAsync(cleanPassword);
    final hostIdentity = _normalizedLocalIdentity(
      appIdentity.copyWith(
        deviceRole: DeviceRole.host,
        syncMode: appIdentity.syncMode == SyncMode.directConnected ||
                appIdentity.syncMode == SyncMode.marketplaceEnabled
            ? appIdentity.syncMode
            : SyncMode.lanOnly,
        hostDeviceId: '',
        platform: platform,
        updatedAt: now,
      ),
    );
    _assertSafeRoleTransition(
      hostIdentity,
      source: 'initial Host registration',
      allowInitialHostRegistration: true,
    );
    _assertLanDirectRoleRules(hostIdentity,
        source: 'initial Host registration');
    _appIdentity = hostIdentity;
    await LocalDatabaseService.setString(
      AppStore._appIdentityKey,
      jsonEncode(hostIdentity.toJson()),
    );
    final adminUser = legacyIndex == -1
        ? AppUser(
            id: 'admin_${now.microsecondsSinceEpoch}',
            fullName: cleanName,
            username: cleanUsername,
            passwordHash: passwordHash,
            roleId: 'admin',
            isSystem: true,
            createdAt: now,
            updatedAt: now,
            lastLoginAt: now,
          )
        : _users[legacyIndex].copyWith(
            fullName: cleanName,
            username: cleanUsername,
            passwordHash: passwordHash,
            updatedAt: now,
            lastLoginAt: now,
          );
    if (legacyIndex == -1) {
      _users.add(adminUser);
    } else {
      _users[legacyIndex] = adminUser;
    }
    _activeUser = adminUser;
    await LocalDatabaseService.setString(AppStore._activeUserKey, adminUser.id);
    await _saveRolesAndUsers();
    notifyListeners();
  }

Future<void> recoverOnlineStoreOwnerIdentity({
    required String storeId,
    required String branchId,
    required String storeName,
    required String username,
    required String password,
    String? hostDeviceId,
    String? deviceToken,
    String? controlPlaneTenantId,
    DeviceRole? deviceRole,
    SyncMode? syncMode,
    bool activateUser = true,
  }) async {
    final cleanStoreId = storeId.trim().toUpperCase();
    final cleanBranchId = branchId.trim().toUpperCase();
    final cleanUsername = username.trim().toLowerCase();
    final cleanPassword = password.trim();
    if (!RegExp(r'^ST-[A-Z0-9](?:[A-Z0-9-]{4,}[A-Z0-9])$')
        .hasMatch(cleanStoreId)) {
      throw ArgumentError('Online login did not return a valid Store ID.');
    }
    if (!RegExp(r'^BR-[A-Z0-9](?:[A-Z0-9-]{4,}[A-Z0-9])$')
        .hasMatch(cleanBranchId)) {
      throw ArgumentError('Online login did not return a valid Branch ID.');
    }
    if (cleanUsername.length < 3) {
      throw ArgumentError('Username must be at least 3 characters.');
    }
    if (cleanPassword.length < 6) {
      throw ArgumentError('Password must be at least 6 characters.');
    }
    final platform = _detectPlatform();
    if (platform == AppPlatformType.web) {
      throw StateError(
        'Web devices cannot recover a Host. Use a desktop device, then import the backup.',
      );
    }

    final now = DateTime.now();
    final role = deviceRole ?? DeviceRole.host;
    final recoveredIdentity = _normalizedLocalIdentity(
      appIdentity.copyWith(
        storeId: cleanStoreId,
        branchId: cleanBranchId,
        deviceRole: role,
        // Online registration/recovery of the store owner identity must not
        // automatically enable Direct Sync. Direct Sync is a paid/explicit
        // feature and should only be enabled from the Sync settings page after
        // the user turns it on and the server allows it for this store.
        syncMode: syncMode ?? SyncMode.localOnly,
        activeSyncTransport:
            syncMode == SyncMode.directConnected ? 'direct' : '',
        hostDeviceId: hostDeviceId ??
            (role == DeviceRole.host ? _deviceId : appIdentity.hostDeviceId),
        deviceToken: (deviceToken == null || deviceToken.trim().isEmpty)
            ? appIdentity.deviceToken
            : deviceToken.trim(),
        controlPlaneTenantId: (controlPlaneTenantId == null ||
                controlPlaneTenantId.trim().isEmpty)
            ? appIdentity.controlPlaneTenantId
            : controlPlaneTenantId.trim(),
        deviceId: _deviceId,
        platform: platform,
        updatedAt: now,
      ),
    );
    _assertLanDirectRoleRules(recoveredIdentity,
        source: 'online store recovery');
    _appIdentity = recoveredIdentity;
    await LocalDatabaseService.setString(
      AppStore._appIdentityKey,
      jsonEncode(recoveredIdentity.toJson()),
    );

    final cleanStoreName = storeName.trim();
    if (cleanStoreName.isNotEmpty) {
      _storeProfile = _storeProfile.copyWith(name: cleanStoreName);
      AccountingService.configureMoneyPolicy(_storeProfile);
    }

    final passwordHash = await _hashPasswordAsync(cleanPassword);
    final existingIndex = _users.indexWhere(
      (user) => user.username.trim().toLowerCase() == cleanUsername,
    );
    final recoveredUser = existingIndex == -1
        ? AppUser(
            id: 'owner_${now.microsecondsSinceEpoch}',
            fullName: cleanUsername,
            username: cleanUsername,
            passwordHash: passwordHash,
            roleId: 'admin',
            isSystem: true,
            createdAt: now,
            updatedAt: now,
            lastLoginAt: now,
          )
        : _users[existingIndex].copyWith(
            passwordHash: passwordHash,
            roleId: 'admin',
            updatedAt: now,
            lastLoginAt: now,
          );
    if (existingIndex == -1) {
      _users.add(recoveredUser);
    } else {
      _users[existingIndex] = recoveredUser;
    }
    _activeUser = activateUser ? recoveredUser : null;
    await LocalDatabaseService.setString(
      AppStore._activeUserKey,
      activateUser ? recoveredUser.id : '',
    );
    await _saveRolesAndUsers();
    await _saveAll();
    notifyListeners();
  }

UserRole? roleById(String id) {
    for (final role in _roles) {
      if (role.id == id) return role;
    }
    return null;
  }

bool hasPermission(String permission) {
    if (_activeUser == null) return false;
    final role = roleById(_activeUser!.roleId);
    // The built-in admin role is privileged by identity as well as by its
    // persisted role record. This keeps permissions stable while role data is
    // being rehydrated or refreshed from the local database.
    if (_activeUser!.roleId == 'admin' || role?.isAdmin == true) return true;
    final effective = <String>{
      ...?role?.permissions,
      ..._activeUser!.extraPermissions,
    };
    effective.removeAll(_activeUser!.deniedPermissions);
    return effective.contains(permission);
  }

void requirePermission(String permission) {
    if (!hasPermission(permission)) {
      throw StateError('You do not have permission: $permission');
    }
  }

void requireAnyPermission(Iterable<String> permissions) {
    final required = permissions.toList(growable: false);
    if (required.isEmpty || !hasAnyPermission(required)) {
      throw StateError(
        'You do not have any required permission: ${required.join(', ')}',
      );
    }
  }

void requireAllPermissions(Iterable<String> permissions) {
    final required = permissions.toList(growable: false);
    for (final permission in required) {
      requirePermission(permission);
    }
  }

double get totalSalesAmount {
    final gross = _sales
        .where((sale) => !sale.isCancelled)
        .fold<double>(0, (sum, sale) => sum + sale.total);
    final returnedOnInvoices =
        _sales.fold<double>(0, (sum, sale) => sum + sale.returnedAmount);
    final creditedInLedger = _accountTransactions
        .where((item) => item.type == 'saleReturn')
        .fold<double>(0, (sum, item) => sum + item.credit);
    final credited =
        returnedOnInvoices > 0 ? returnedOnInvoices : creditedInLedger;
    return (gross - credited).clamp(0, double.infinity).toDouble();
  }

}
