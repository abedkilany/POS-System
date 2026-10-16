part of 'app_store.dart';

final class _SecurityDomain implements SecurityDomainPort {
  _SecurityDomain(this._store);
  final AppStore _store;

  @override
  AppUser? get activeUser => _store._activeUserReadImpl;
  @override
  AppUser? get currentUser => _store._activeUserReadImpl;
  @override
  String get currentRole => _store._currentRoleReadImpl;
  @override
  List<AppUser> get users => List<AppUser>.unmodifiable(_store._users);
  @override
  List<UserRole> get roles => List<UserRole>.unmodifiable(_store._roles);
  @override
  UserRole? roleById(String id) {
    for (final role in _store._roles) {
      if (role.id == id) return role;
    }
    return null;
  }

  @override
  bool get rememberLogin => _store._rememberLogin;
  @override
  bool get hasLocalAdminUser =>
      _store._users.any((item) => item.roleId == 'admin' && item.isActive);
  @override
  AppUser? get storeOwnerUser =>
      _AppStoreIdentityUsersAuthentication(_store).storeOwnerUser;
  @override
  bool canAccessPage(String pageId) => _store._canAccessPageReadImpl(pageId);
  @override
  bool hasPermission(String permission) =>
      _store._hasPermissionReadImpl(permission);
  @override
  bool hasAnyPermission(Iterable<String> permissions) =>
      permissions.any(_store._hasPermissionReadImpl);
  @override
  bool get canViewDashboard => canAccessPage('dashboard');
  @override
  bool get canViewProducts => hasAnyPermission(const <String>{
        AppPermission.productsView,
        AppPermission.productsManage,
        AppPermission.productsCreate,
        AppPermission.productsEdit,
        AppPermission.productsDelete,
      });
  @override
  bool get canManageProducts => hasAnyPermission(const <String>{
        AppPermission.productsManage,
        AppPermission.productsCreate,
        AppPermission.productsEdit,
        AppPermission.productsDelete,
      });
  @override
  bool get canViewCustomers => hasAnyPermission(const <String>{
        AppPermission.customersView,
        AppPermission.customersManage,
      });
  @override
  bool get canManageCustomers => hasPermission(AppPermission.customersManage);
  @override
  bool get canManageCustomerPayments =>
      hasPermission(AppPermission.customersPaymentManage);
  @override
  bool get canViewSuppliers => hasAnyPermission(const <String>{
        AppPermission.suppliersView,
        AppPermission.suppliersManage,
      });
  @override
  bool get canManageSuppliers => hasPermission(AppPermission.suppliersManage);
  @override
  bool get canManageSupplierPayments =>
      hasPermission(AppPermission.suppliersPaymentManage);
  @override
  bool get canViewSales => hasAnyPermission(const <String>{
        AppPermission.salesView,
        AppPermission.salesCreate,
        AppPermission.salesEdit,
        AppPermission.salesCancel,
      });
  @override
  bool get canSell => hasPermission(AppPermission.salesCreate);
  @override
  bool get canViewQuotations => canAccessPage('quotations');
  @override
  bool get canManageQuotations => hasPermission(AppPermission.quotationsManage);
  @override
  bool get canViewDeliveryNotes => canAccessPage('delivery_notes');
  @override
  bool get canManageDeliveryNotes =>
      hasPermission(AppPermission.deliveryNotesManage);
  @override
  bool get canViewPurchases => canAccessPage('purchases');
  @override
  bool get canManagePurchases => hasPermission(AppPermission.purchasesManage);
  @override
  bool get canViewExpenses => canAccessPage('expenses');
  @override
  bool get canManageExpenses => hasPermission(AppPermission.expensesManage);
  @override
  bool get canViewAccounting => canAccessPage('accounting');
  @override
  bool get canManageAccounting => hasPermission(AppPermission.accountingManage);
  @override
  bool get canManageCashBox => hasPermission(AppPermission.cashBoxManage);
  @override
  bool get canViewInventory => canAccessPage('inventory');
  @override
  bool get canManageInventory => hasAnyPermission(const <String>{
        AppPermission.inventoryWarehousesManage,
        AppPermission.inventoryCorrectionsManage,
        AppPermission.inventoryCountsManage,
        AppPermission.inventoryWasteManage,
        AppPermission.inventoryManufacturingManage,
      });
  @override
  bool get canViewReports => canAccessPage('reports');
  @override
  bool get canViewCashBox => canAccessPage('cash_box') || canViewAccounting;
  @override
  bool get canViewSettings => canAccessPage('settings');
  @override
  bool get canViewDatabase => canAccessPage('database');
  @override
  bool get canViewMaintenance => canAccessPage('maintenance');
  @override
  bool get canManageMaintenance =>
      hasPermission(AppPermission.maintenanceManage);
  @override
  bool get canManageUsers => hasAnyPermission(
        const <String>{AppPermission.usersManage, AppPermission.rolesManage},
      );
  @override
  bool get canManageUsersPage => canManageUsers;
  @override
  bool get canManageDatabase => hasPermission(AppPermission.databaseManage);
  @override
  bool get canDeleteOrCancel => hasPermission(AppPermission.salesCancel);
  @override
  void requirePermission(String permission) =>
      _store._requirePermissionReadImpl(permission);
  @override
  void requireAnyPermission(Iterable<String> permissions) {
    final required = permissions.toList(growable: false);
    if (required.isEmpty || !hasAnyPermission(required)) {
      throw StateError(
        'You do not have any required permission: ${required.join(', ')}',
      );
    }
  }

  @override
  void requireAllPermissions(Iterable<String> permissions) {
    for (final permission in permissions) {
      requirePermission(permission);
    }
  }

  @override
  Future<bool> authorizeSensitiveAction({
    required String action,
    required String password,
    Duration validity = const Duration(minutes: 3),
  }) =>
      _store._authorizeSensitiveAction(
        action: action,
        password: password,
        validity: validity,
      );
  @override
  void requireSensitiveActionAuthorization(String action) =>
      _store._requireSensitiveActionAuthorizationDomainImpl(action);
  @override
  void clearSensitiveActionAuthorization() =>
      _store._clearSensitiveActionAuthorizationDomainImpl();

  @override
  bool get needsInitialAdminSetup =>
      _store._users.isEmpty || _store._hasOnlyLegacyDefaultAdminUser;

  @override
  Future<bool> login(
    String username,
    String password, {
    bool remember = false,
  }) =>
      _AppStoreIdentityUsersAuthentication(_store)
          .login(username, password, remember: remember);

  @override
  Future<void> logout() => _AppStoreIdentityUsersAuthentication(_store).logout();

  @override
  Future<bool> applySupportPasswordResetToLocalUser({
    required String username,
    required String newPassword,
  }) =>
      _AppStoreIdentityUsersAuthentication(_store)
          .applySupportPasswordResetToLocalUser(
        username: username,
        newPassword: newPassword,
      );

  @override
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
  }) =>
      _AppStoreSplitAccessAuth(_store).recoverOnlineStoreOwnerIdentity(
        storeId: storeId,
        branchId: branchId,
        storeName: storeName,
        username: username,
        password: password,
        hostDeviceId: hostDeviceId,
        deviceToken: deviceToken,
        controlPlaneTenantId: controlPlaneTenantId,
        deviceRole: deviceRole,
        syncMode: syncMode,
        activateUser: activateUser,
      );

  @override
  Future<void> applySessionUser({
    required AppUser activeUser,
    required String currentRole,
    required Set<String> permissions,
    required bool rememberLogin,
  }) =>
      _AppStoreIdentityUsersAuthentication(_store).applySessionUser(
        activeUser: activeUser,
        currentRole: currentRole,
        permissions: permissions,
        rememberLogin: rememberLogin,
      );

  @override
  Future<void> clearSessionUser() =>
      _AppStoreIdentityUsersAuthentication(_store).clearSessionUser();

  @override
  Future<void> addOrUpdateRole(UserRole role) =>
      _AppStoreIdentityUsersAuthentication(_store).addOrUpdateRole(role);

  @override
  Future<void> deleteRole(String id) =>
      _AppStoreIdentityUsersAuthentication(_store).deleteRole(id);

  @override
  Future<void> addOrUpdateUser(AppUser user, {String? password}) =>
      _AppStoreIdentityUsersCredentialsPersistence(_store)
          .addOrUpdateUser(user, password: password);

  @override
  Future<void> deleteUser(String id) =>
      _AppStoreIdentityUsersCredentialsPersistence(_store).deleteUser(id);

  @override
  Future<bool> verifyAdminPassword(String password) =>
      _AppStoreIdentityUsersAuthentication(_store).verifyAdminPassword(password);

  @override
  Future<void> applyStoreOwnerCredentials({
    required String username,
    required String password,
    String? fullName,
  }) =>
      _AppStoreIdentityUsersCredentialsPersistence(_store).applyStoreOwnerCredentials(
        username: username,
        password: password,
        fullName: fullName,
      );

  @override
  Future<void> completeInitialAdminSetup({
    required String fullName,
    required String username,
    required String password,
  }) =>
      _AppStoreSplitAccessAuth(_store).completeInitialAdminSetup(
        fullName: fullName,
        username: username,
        password: password,
      );
}
