import '../../models/app_identity.dart';
import '../../models/app_user.dart';
import '../../models/user_role.dart';

abstract class SecurityDomainPort {
  AppUser? get activeUser;
  AppUser? get currentUser;
  String get currentRole;
  List<AppUser> get users;
  List<UserRole> get roles;
  UserRole? roleById(String id);
  bool get rememberLogin;
  bool get hasLocalAdminUser;
  AppUser? get storeOwnerUser;
  bool canAccessPage(String pageId);
  bool hasPermission(String permission);
  bool hasAnyPermission(Iterable<String> permissions);
  bool get canViewDashboard;
  bool get canViewProducts;
  bool get canManageProducts;
  bool get canViewCustomers;
  bool get canManageCustomers;
  bool get canManageCustomerPayments;
  bool get canViewSuppliers;
  bool get canManageSuppliers;
  bool get canManageSupplierPayments;
  bool get canViewSales;
  bool get canSell;
  bool get canViewQuotations;
  bool get canManageQuotations;
  bool get canViewDeliveryNotes;
  bool get canManageDeliveryNotes;
  bool get canViewPurchases;
  bool get canManagePurchases;
  bool get canViewExpenses;
  bool get canManageExpenses;
  bool get canViewAccounting;
  bool get canManageAccounting;
  bool get canManageCashBox;
  bool get canViewInventory;
  bool get canManageInventory;
  bool get canViewReports;
  bool get canViewCashBox;
  bool get canViewSettings;
  bool get canViewDatabase;
  bool get canViewMaintenance;
  bool get canManageMaintenance;
  bool get canManageUsers;
  bool get canManageUsersPage;
  bool get canManageDatabase;
  bool get canDeleteOrCancel;
  Future<void> applySessionUser({
    required AppUser activeUser,
    required String currentRole,
    required Set<String> permissions,
    required bool rememberLogin,
  });
  Future<void> clearSessionUser();
  Future<void> addOrUpdateRole(UserRole role);
  Future<void> deleteRole(String id);
  Future<void> addOrUpdateUser(AppUser user, {String? password});
  Future<void> deleteUser(String id);
  Future<bool> verifyAdminPassword(String password);
  Future<void> applyStoreOwnerCredentials({
    required String username,
    required String password,
    String? fullName,
  });
  Future<void> completeInitialAdminSetup({
    required String fullName,
    required String username,
    required String password,
  });
  void requirePermission(String permission);
  void requireAnyPermission(Iterable<String> permissions);
  void requireAllPermissions(Iterable<String> permissions);
  Future<bool> authorizeSensitiveAction({
    required String action,
    required String password,
    Duration validity = const Duration(minutes: 3),
  });
  void requireSensitiveActionAuthorization(String action);
  void clearSensitiveActionAuthorization();
  bool get needsInitialAdminSetup;
  Future<bool> login(
    String username,
    String password, {
    bool remember = false,
  });
  Future<void> logout();
  Future<bool> applySupportPasswordResetToLocalUser({
    required String username,
    required String newPassword,
  });
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
  });
}
