import 'dart:async';

import '../../data/app_store.dart';
import '../services/app_logging_service.dart';
import '../services/password_hashing.dart';

class AuthRepository {
  AuthRepository._();

  static Future<bool> login(
    AppStore store,
    String username,
    String password, {
    bool remember = false,
  }) async {
    if (store.isSuspendedByHost) return false;
    final normalized = username.trim().toLowerCase();
    final users = store.users;
    final activeMatches = users
        .where(
          (user) =>
              user.username.trim().toLowerCase() == normalized && user.isActive,
        )
        .toList(growable: false);
    if (activeMatches.length > 1) {
      unawaited(
        AppLogger.warning(
          area: 'login',
          action: 'login_conflict',
          message: 'Duplicate active username prevented login.',
          details: 'username=$normalized count=${activeMatches.length}',
          storeId: store.appIdentity.storeId,
          branchId: store.appIdentity.branchId,
          devicePlatform: store.appIdentity.platform.name,
          deviceModel: store.appIdentity.deviceName.isNotEmpty
              ? store.appIdentity.deviceName
              : store.deviceId,
          isImportant: true,
        ),
      );
      return false;
    }
    final user = activeMatches.isEmpty ? null : activeMatches.first;
    if (user == null) {
      unawaited(
        AppLogger.warning(
          area: 'login',
          action: 'login_failed',
          message: 'User not found or inactive.',
          details: 'username=$normalized',
          storeId: store.appIdentity.storeId,
          branchId: store.appIdentity.branchId,
          devicePlatform: store.appIdentity.platform.name,
          deviceModel: store.appIdentity.deviceName.isNotEmpty
              ? store.appIdentity.deviceName
              : store.deviceId,
          isImportant: true,
        ),
      );
      return false;
    }
    if (!await PasswordHashing.verifyPassword(password, user.passwordHash)) {
      unawaited(
        AppLogger.warning(
          area: 'login',
          action: 'login_failed',
          message: 'Invalid credentials.',
          details: 'username=$normalized',
          storeId: store.appIdentity.storeId,
          branchId: store.appIdentity.branchId,
          devicePlatform: store.appIdentity.platform.name,
          deviceModel: store.appIdentity.deviceName.isNotEmpty
              ? store.appIdentity.deviceName
              : store.deviceId,
          isImportant: true,
        ),
      );
      return false;
    }

    final role = store.roleById(user.roleId);
    final permissions = <String>{
      ...?role?.permissions,
      ...user.extraPermissions,
    }..removeAll(user.deniedPermissions);
    final roleName = role?.name ?? user.roleId;
    final now = DateTime.now();
    final updated = user.copyWith(lastLoginAt: now);
    await store.applySessionUser(
      activeUser: updated,
      currentRole: roleName,
      permissions: permissions,
      rememberLogin: remember,
    );
    unawaited(
      AppLogger.info(
        area: 'login',
        action: 'login_success',
        message: 'User logged in successfully.',
        details:
            'userId=${updated.id} username=${updated.username} remember=$remember',
        userId: updated.id,
        storeId: store.appIdentity.storeId,
        branchId: store.appIdentity.branchId,
        sessionId: store.deviceId,
        traceId: store.deviceId,
        devicePlatform: store.appIdentity.platform.name,
        deviceModel: store.appIdentity.deviceName.isNotEmpty
            ? store.appIdentity.deviceName
            : store.deviceId,
        isImportant: true,
      ),
    );
    return true;
  }

  static Future<void> logout(AppStore store) async {
    final user = store.activeUser;
    await store.clearSessionUser();
    unawaited(
      AppLogger.info(
        area: 'login',
        action: 'logout',
        message: 'User logged out.',
        details:
            user == null ? '' : 'userId=${user.id} username=${user.username}',
        userId: user?.id ?? '',
        storeId: store.appIdentity.storeId,
        branchId: store.appIdentity.branchId,
        devicePlatform: store.appIdentity.platform.name,
        deviceModel: store.appIdentity.deviceName.isNotEmpty
            ? store.appIdentity.deviceName
            : store.deviceId,
        isImportant: true,
      ),
    );
  }

  static Future<bool> hasLocalAdminUser(AppStore store) async {
    final users = store.users;
    return users.any((user) => user.roleId == 'admin' && user.isActive);
  }

  static Future<bool> needsInitialAdminSetup(AppStore store) async {
    final users = store.users;
    if (users.isEmpty) return true;
    if (users.length != 1) return false;
    final user = users.first;
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
        user.lastLoginAt == null &&
        await PasswordHashing.verifyPassword(
          legacyPassword,
          user.passwordHash,
        );
  }
}
