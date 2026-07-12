import 'dart:convert';

import '../../data/app_store.dart';
import '../../models/app_identity.dart';
import '../../models/app_user.dart';
import '../../models/catalog_item.dart';
import '../../models/user_role.dart';
import '../repositories/business_repositories.dart';
import '../services/local_database_service.dart';
import '../services/password_hashing.dart';
import '../storage/sqlite/business_sqlite_store.dart';

class StoreBootstrapService {
  StoreBootstrapService._();

  static Future<void> completeInitialAdminSetup(
    AppStore store, {
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

    final existingUsers = store.users;
    final activeUsers = existingUsers.where((user) => user.isActive).toList();
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
    final onlyLegacyAdmin = activeUsers.length == 1 &&
        activeUsers.first.id == 'admin' &&
        activeUsers.first.username.trim().toLowerCase() == 'admin' &&
        await PasswordHashing.verifyPassword(
          legacyPassword,
          activeUsers.first.passwordHash,
        ) &&
        activeUsers.first.lastLoginAt == null;
    if (activeUsers.isNotEmpty && !onlyLegacyAdmin) {
      throw StateError('Initial administrator setup is already complete.');
    }

    final platform = store.appIdentity.platform;
    if (platform == AppPlatformType.web) {
      throw StateError(
        'Web devices cannot create a Host. Use Connect to Store from Web.',
      );
    }
    final now = DateTime.now();
    final hostIdentity = store.appIdentity.copyWith(
      deviceRole: DeviceRole.host,
      syncMode: store.appIdentity.syncMode == SyncMode.cloudConnected ||
              store.appIdentity.syncMode == SyncMode.marketplaceEnabled
          ? store.appIdentity.syncMode
          : SyncMode.lanOnly,
      hostDeviceId: '',
      updatedAt: now,
    );
    await store.updateAppIdentityDuringSetup(hostIdentity);

    final passwordHash = await PasswordHashing.hashPassword(cleanPassword);
    final adminUser = onlyLegacyAdmin
        ? activeUsers.first.copyWith(
            fullName: cleanName,
            username: cleanUsername,
            passwordHash: passwordHash,
            roleId: 'admin',
            isSystem: true,
            updatedAt: now,
            lastLoginAt: now,
          )
        : AppUser(
            id: 'admin_${now.microsecondsSinceEpoch}',
            fullName: cleanName,
            username: cleanUsername,
            passwordHash: passwordHash,
            roleId: 'admin',
            isSystem: true,
            createdAt: now,
            updatedAt: now,
            lastLoginAt: now,
          );
    await LocalDatabaseService.runSqliteAuthoritativeTransaction(() async {
      final existingRoles = store.roles;
      if (existingRoles.indexWhere((role) => role.id == 'admin') == -1) {
        await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
          BusinessSqliteStore.rolesKey,
          <Map<String, dynamic>>[
            ...existingRoles
                .where((role) => role.id != 'admin')
                .map((item) => item.toJson()),
            UserRole(
              id: 'admin',
              name: 'Admin',
              permissions: Set<String>.from(AppPermission.all),
              isSystem: true,
            ).toJson(),
          ],
        );
      }

      final existingUsers = store.users;
      final users = <Map<String, dynamic>>[
        ...existingUsers
            .where((user) => user.id != adminUser.id)
            .map((item) => item.toJson()),
        adminUser.toJson(),
      ];
      await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
        BusinessSqliteStore.usersKey,
        users,
      );
      await _seedCatalogDefaultsIfMissing(store);
    });
    await store.applySessionUser(
      activeUser: adminUser,
      currentRole: 'Admin',
      permissions: Set<String>.from(AppPermission.all),
      rememberLogin: true,
    );
  }

  static Future<void> recoverOnlineStoreOwnerIdentity(
    AppStore store, {
    required String storeId,
    required String branchId,
    required String storeName,
    required String username,
    required String password,
    String? hostDeviceId,
    String? deviceToken,
    String? cloudTenantId,
    DeviceRole? deviceRole,
    SyncMode? syncMode,
  }) async {
    final cleanStoreId = storeId.trim().toUpperCase();
    final cleanBranchId = branchId.trim().toUpperCase();
    final cleanUsername = username.trim().toLowerCase();
    final cleanPassword = password.trim();
    if (!RegExp(r'^ST-[A-Z0-9]{6,}$').hasMatch(cleanStoreId)) {
      throw ArgumentError('Online login did not return a valid Store ID.');
    }
    if (!RegExp(r'^BR-[A-Z0-9]{6,}$').hasMatch(cleanBranchId)) {
      throw ArgumentError('Online login did not return a valid Branch ID.');
    }
    if (cleanUsername.length < 3) {
      throw ArgumentError('Username must be at least 3 characters.');
    }
    if (cleanPassword.length < 6) {
      throw ArgumentError('Password must be at least 6 characters.');
    }

    final now = DateTime.now();
    final platform = store.appIdentity.platform;
    if (platform == AppPlatformType.web) {
      throw StateError(
        'Web devices cannot recover a Host. Use a desktop device, then import the backup.',
      );
    }

    final role = deviceRole ?? DeviceRole.host;
    final recoveredIdentity = store.appIdentity.copyWith(
      storeId: cleanStoreId,
      branchId: cleanBranchId,
      deviceRole: role,
      syncMode: syncMode ?? SyncMode.localOnly,
      activeSyncTransport: syncMode == SyncMode.cloudConnected ? 'cloud' : '',
      hostDeviceId:
          hostDeviceId ?? (role == DeviceRole.host ? store.deviceId : store.appIdentity.hostDeviceId),
      deviceToken: (deviceToken == null || deviceToken.trim().isEmpty)
          ? store.appIdentity.deviceToken
          : deviceToken.trim(),
      cloudTenantId: (cloudTenantId == null || cloudTenantId.trim().isEmpty)
          ? store.appIdentity.cloudTenantId
          : cloudTenantId.trim(),
      deviceId: store.deviceId,
      platform: platform,
      updatedAt: now,
    );
    await store.updateAppIdentityDuringSetup(recoveredIdentity);

    final cleanStoreName = storeName.trim();
    if (cleanStoreName.isNotEmpty) {
      await LocalDatabaseService.setString(
        'store_profile_v5',
        jsonEncode(
          store.storeProfile.copyWith(name: cleanStoreName).toJson(),
        ),
      );
      await store.refreshAfterDatabaseChange('store_profile_v5');
    }

    final passwordHash = await PasswordHashing.hashPassword(cleanPassword);
    final existingAdminRole = store.roleById('admin');
    if (existingAdminRole == null) {
      await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
        BusinessSqliteStore.rolesKey,
        <Map<String, dynamic>>[
          UserRole(
            id: 'admin',
            name: 'Admin',
            permissions: Set<String>.from(AppPermission.all),
            isSystem: true,
          ).toJson(),
        ],
      );
      await store.refreshAfterDatabaseChange(BusinessSqliteStore.rolesKey);
    }
    AppUser? existingUser;
    for (final user in store.users) {
      if (user.username.trim().toLowerCase() == cleanUsername) {
        existingUser = user;
        break;
      }
    }
    final recoveredUser = existingUser == null
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
        : existingUser.copyWith(
            passwordHash: passwordHash,
            roleId: 'admin',
            updatedAt: now,
            lastLoginAt: now,
            isSystem: true,
          );
    final currentUsers = store.users.toList(growable: false);
    final updatedUsers = currentUsers
        .where((user) => user.id != recoveredUser.id)
        .map((user) => user.toJson())
        .toList(growable: false);
    await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
      BusinessSqliteStore.usersKey,
      <Map<String, dynamic>>[
        ...updatedUsers,
        recoveredUser.toJson(),
      ],
    );
    await store.refreshAfterDatabaseChange(BusinessSqliteStore.usersKey);
    await store.applySessionUser(
      activeUser: recoveredUser,
      currentRole: 'Admin',
      permissions: Set<String>.from(AppPermission.all),
      rememberLogin: true,
    );
  }

  static Future<void> applyCloudStoreOwnerCredentials(
    AppStore store, {
    required String username,
    required String password,
    String? fullName,
  }) async {
    final owner = store.activeUser;
    if (owner == null) return;
    final cleanPassword = password.trim();
    if (cleanPassword.length < 6) {
      throw ArgumentError(
          'Store Owner password must be at least 6 characters.');
    }
    final normalizedUsername = username.trim().toLowerCase().isEmpty
        ? owner.username.trim().toLowerCase()
        : username.trim().toLowerCase();
    final cleanName = (fullName ?? owner.fullName).trim().isEmpty
        ? owner.fullName
        : (fullName ?? owner.fullName).trim();
    final updated = owner.copyWith(
      username: normalizedUsername,
      fullName: cleanName,
      passwordHash: await PasswordHashing.hashPassword(cleanPassword),
      roleId: 'admin',
      extraPermissions: const <String>{},
      deniedPermissions: const <String>{},
      isActive: true,
      isSystem: true,
      updatedAt: DateTime.now(),
    );
    await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
      BusinessSqliteStore.usersKey,
      <Map<String, dynamic>>[
        ...store.users
            .where((user) => user.id != updated.id)
            .map((user) => user.toJson()),
        updated.toJson(),
      ],
    );
    await store.refreshAfterDatabaseChange(BusinessSqliteStore.usersKey);
    await store.applySessionUser(
      activeUser: updated,
      currentRole: 'Admin',
      permissions: Set<String>.from(AppPermission.all),
      rememberLogin: store.rememberLogin,
    );
  }

  static Future<void> _seedCatalogDefaultsIfMissing(AppStore store) async {
    if (((await ProductRepository.getCategories()) ?? const <String>[]).isEmpty) {
      await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
        BusinessSqliteStore.categoriesKey,
        <Map<String, dynamic>>[
          CatalogItem(
            id: 'category_default',
            nameEn: 'General',
            nameAr: '',
            code: 'GENERAL',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ).toJson(),
        ],
      );
    }
    final brands = await InventoryRepository.getCatalogItems(
      BusinessSqliteStore.brandsKey,
    );
    if ((brands ?? const <CatalogItem>[]).isEmpty) {
      await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
        BusinessSqliteStore.brandsKey,
        <Map<String, dynamic>>[
          CatalogItem(
            id: 'brand_default',
            nameEn: 'Default Brand',
            nameAr: '',
            code: 'DEFAULT',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ).toJson(),
        ],
      );
    }
    final units = await InventoryRepository.getCatalogItems(
      BusinessSqliteStore.unitsKey,
    );
    if ((units ?? const <CatalogItem>[]).isEmpty) {
      await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
        BusinessSqliteStore.unitsKey,
        <Map<String, dynamic>>[
          CatalogItem(
            id: 'unit_default',
            nameEn: 'Piece',
            nameAr: '',
            code: 'PCS',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ).toJson(),
        ],
      );
    }
  }
}
