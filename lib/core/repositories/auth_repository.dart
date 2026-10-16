import 'dart:async';

import 'package:ventio/core/contracts/application_session.dart';
import '../services/app_logging_service.dart';
import '../services/password_hashing.dart';

class AuthRepository {
  AuthRepository._();

  static Future<bool> login(
    AuthenticationSession store,
    String username,
    String password, {
    bool remember = false,
  }) async {
    if (store.runtime.isSuspendedByHost) return false;
    final normalized = username.trim().toLowerCase();
    final users = store.security.users;
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
          storeId: store.runtime.identity.storeId,
          branchId: store.runtime.identity.branchId,
          devicePlatform: store.runtime.identity.platform.name,
          deviceModel: store.runtime.identity.deviceName.isNotEmpty
              ? store.runtime.identity.deviceName
              : store.sync.deviceId,
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
          storeId: store.runtime.identity.storeId,
          branchId: store.runtime.identity.branchId,
          devicePlatform: store.runtime.identity.platform.name,
          deviceModel: store.runtime.identity.deviceName.isNotEmpty
              ? store.runtime.identity.deviceName
              : store.sync.deviceId,
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
          storeId: store.runtime.identity.storeId,
          branchId: store.runtime.identity.branchId,
          devicePlatform: store.runtime.identity.platform.name,
          deviceModel: store.runtime.identity.deviceName.isNotEmpty
              ? store.runtime.identity.deviceName
              : store.sync.deviceId,
          isImportant: true,
        ),
      );
      return false;
    }

    final role = store.security.roleById(user.roleId);
    final permissions = <String>{
      ...?role?.permissions,
      ...user.extraPermissions,
    }..removeAll(user.deniedPermissions);
    final roleName = role?.name ?? user.roleId;
    final now = DateTime.now();
    final updated = user.copyWith(lastLoginAt: now);
    await store.security.applySessionUser(
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
        storeId: store.runtime.identity.storeId,
        branchId: store.runtime.identity.branchId,
        sessionId: store.sync.deviceId,
        traceId: store.sync.deviceId,
        devicePlatform: store.runtime.identity.platform.name,
        deviceModel: store.runtime.identity.deviceName.isNotEmpty
            ? store.runtime.identity.deviceName
            : store.sync.deviceId,
        isImportant: true,
      ),
    );
    return true;
  }

  static Future<void> logout(AuthenticationSession store) async {
    final user = store.security.activeUser;
    await store.security.clearSessionUser();
    unawaited(
      AppLogger.info(
        area: 'login',
        action: 'logout',
        message: 'User logged out.',
        details:
            user == null ? '' : 'userId=${user.id} username=${user.username}',
        userId: user?.id ?? '',
        storeId: store.runtime.identity.storeId,
        branchId: store.runtime.identity.branchId,
        devicePlatform: store.runtime.identity.platform.name,
        deviceModel: store.runtime.identity.deviceName.isNotEmpty
            ? store.runtime.identity.deviceName
            : store.sync.deviceId,
        isImportant: true,
      ),
    );
  }

  static Future<bool> hasLocalAdminUser(AuthenticationSession store) async {
    final users = store.security.users;
    return users.any((user) => user.roleId == 'admin' && user.isActive);
  }

  static Future<bool> needsInitialAdminSetup(AuthenticationSession store) async {
    final users = store.security.users;
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
