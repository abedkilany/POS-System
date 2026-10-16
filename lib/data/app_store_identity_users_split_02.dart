part of 'app_store.dart';

extension _AppStoreSplitIdentityUsersPart2 on AppStore {
  void _restoreActiveUser() {
    if (_isSuspendedByHost) {
      _activeUser = null;
      _rememberLogin = false;
      return;
    }
    if (!_rememberLogin) {
      _activeUser = null;
      return;
    }
    final activeId = LocalDatabaseService.getString(AppStore._activeUserKey);
    if (activeId == null || activeId.isEmpty) return;
    for (final user in _users) {
      if (user.id == activeId && user.isActive) {
        _activeUser = user;
        return;
      }
    }
  }

  bool _isLoginTemporarilyBlocked(String normalizedUsername) {
    final now = DateTime.now();
    final blockedUntil = _loginBlockedUntil[normalizedUsername];
    if (blockedUntil == null) return false;
    if (blockedUntil.isAfter(now)) return true;
    _loginBlockedUntil.remove(normalizedUsername);
    _failedLoginAttempts.remove(normalizedUsername);
    return false;
  }

  void _registerLoginFailure(
    String normalizedUsername, {
    required String reason,
  }) {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(minutes: 5));
    final attempts = _failedLoginAttempts.putIfAbsent(
      normalizedUsername,
      () => <DateTime>[],
    )
      ..removeWhere((item) => item.isBefore(cutoff))
      ..add(now);
    final lockTriggered = attempts.length >= 5;
    if (lockTriggered) {
      _loginBlockedUntil[normalizedUsername] =
          now.add(const Duration(seconds: 30));
      attempts.clear();
    }
    unawaited(AuditLogger.record(
      entityType: 'authentication',
      entityId: normalizedUsername,
      action: lockTriggered ? 'login_locked' : 'login_failed',
      summary: lockTriggered
          ? 'Login temporarily rate limited'
          : 'Login attempt failed',
      details: 'reason=$reason',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      sessionId: _deviceId,
      traceId: _deviceId,
      deviceId: _deviceId,
      sourceModule: 'security',
      isImportant: true,
    ));
  }

  Future<bool> login(
    String username,
    String password, {
    bool remember = false,
  }) async {
    if (_isSuspendedByHost) return false;
    final normalized = username.trim().toLowerCase();
    if (_isLoginTemporarilyBlocked(normalized)) {
      unawaited(AppLogger.warning(
        area: 'login',
        action: 'login_rate_limited',
        message: 'Login attempt blocked by local rate limit.',
        details: 'username=$normalized',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ));
      return false;
    }
    final activeMatches = _users
        .where(
          (user) =>
              user.username.trim().toLowerCase() == normalized && user.isActive,
        )
        .toList();
    if (activeMatches.length > 1) {
      // Security conflict: never guess which duplicated username should log in.
      unawaited(
        AppLogger.warning(
          area: 'login',
          action: 'login_conflict',
          message: 'Duplicate active username prevented login.',
          details: 'username=$normalized count=${activeMatches.length}',
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          devicePlatform: appIdentity.platform.name,
          deviceModel: appIdentity.deviceName.isNotEmpty
              ? appIdentity.deviceName
              : _deviceId,
          isImportant: true,
        ),
      );
      _registerLoginFailure(normalized, reason: 'duplicate_active_username');
      return false;
    }
    for (var index = 0; index < _users.length; index++) {
      final user = _users[index];
      if (user.username.trim().toLowerCase() != normalized || !user.isActive) {
        continue;
      }
      if (!await _verifyPasswordAsync(password, user.passwordHash)) {
        unawaited(
          AppLogger.warning(
            area: 'login',
            action: 'login_failed',
            message: 'Invalid credentials.',
            details: 'username=$normalized',
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            devicePlatform: appIdentity.platform.name,
            deviceModel: appIdentity.deviceName.isNotEmpty
                ? appIdentity.deviceName
                : _deviceId,
            isImportant: true,
          ),
        );
        _registerLoginFailure(normalized, reason: 'invalid_credentials');
        return false;
      }
      _failedLoginAttempts.remove(normalized);
      _loginBlockedUntil.remove(normalized);
      final updated = user.copyWith(lastLoginAt: DateTime.now());
      _users[index] = updated;
      _clearSensitiveActionAuthorization();
      _activeUser = updated;
      _rememberLogin = remember;
      notifyListeners();
      // Login is a session boundary. Persist it before returning so an
      // immediate restart or database refresh cannot observe a half-written
      // user/session state.
      await LocalDatabaseService.setString(
        AppStore._rememberLoginKey,
        remember ? 'true' : 'false',
      );
      await LocalDatabaseService.setString(
        AppStore._activeUserKey,
        remember ? updated.id : '',
      );
      await _saveRolesAndUsers();
      unawaited(
        AppLogger.info(
          area: 'login',
          action: 'login_success',
          message: 'User logged in successfully.',
          details:
              'userId=${updated.id} username=${updated.username} remember=$remember',
          userId: updated.id,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          sessionId: _deviceId,
          traceId: _deviceId,
          devicePlatform: appIdentity.platform.name,
          deviceModel: appIdentity.deviceName.isNotEmpty
              ? appIdentity.deviceName
              : _deviceId,
          isImportant: true,
        ),
      );
      unawaited(AuditLogger.record(
        entityType: 'authentication',
        entityId: updated.id,
        action: 'login_success',
        summary: 'User logged in',
        details: 'remember=$remember',
        userId: updated.id,
        userName: updated.username,
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
    unawaited(
      AppLogger.warning(
        area: 'login',
        action: 'login_failed',
        message: 'User not found or inactive.',
        details: 'username=$normalized',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    _registerLoginFailure(normalized, reason: 'unknown_or_inactive_user');
    return false;
  }

  Future<void> logout() async {
    final user = _activeUser;
    _clearSensitiveActionAuthorization();
    final authCache = AccountAuthCache.load();
    if (authCache != null) {
      try {
        await AccountAuthService().logout(
          accountToken: authCache.accountToken,
          refreshToken: authCache.refreshToken,
        );
      } catch (_) {
        // Local logout must still complete when the control plane is offline.
      }
      await AccountAuthCache.clear();
    }
    _activeUser = null;
    _rememberLogin = false;
    await LocalDatabaseService.setString(AppStore._activeUserKey, '');
    await LocalDatabaseService.setString(AppStore._rememberLoginKey, 'false');
    unawaited(
      AppLogger.info(
        area: 'login',
        action: 'logout',
        message: 'User logged out.',
        details:
            user == null ? '' : 'userId=${user.id} username=${user.username}',
        userId: user?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(AuditLogger.record(
      entityType: 'authentication',
      entityId: user?.id ?? '',
      action: 'logout',
      summary: 'User logged out',
      userId: user?.id ?? '',
      userName: user?.username ?? '',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      sessionId: _deviceId,
      traceId: _deviceId,
      deviceId: _deviceId,
      sourceModule: 'security',
      isImportant: true,
    ));
    notifyListeners();
  }

  Future<void> applySessionUser({
    required AppUser activeUser,
    required String currentRole,
    required Set<String> permissions,
    required bool rememberLogin,
  }) async {
    final index = _users.indexWhere((item) => item.id == activeUser.id);
    if (index == -1) {
      _users.add(activeUser);
    } else {
      _users[index] = activeUser;
    }
    _activeUser = activeUser;
    _currentRole = currentRole;
    _rememberLogin = rememberLogin;
    await LocalDatabaseService.setString(
        AppStore._activeUserKey, activeUser.id);
    await LocalDatabaseService.setString(AppStore._currentRoleKey, currentRole);
    await LocalDatabaseService.setString(
      AppStore._rememberLoginKey,
      rememberLogin ? 'true' : 'false',
    );
    await _saveRolesAndUsers();
    notifyListeners();
  }

  Future<void> clearSessionUser() async {
    _clearSensitiveActionAuthorization();
    _activeUser = null;
    _rememberLogin = false;
    await LocalDatabaseService.setString(AppStore._activeUserKey, '');
    await LocalDatabaseService.setString(AppStore._currentRoleKey, 'admin');
    await LocalDatabaseService.setString(AppStore._rememberLoginKey, 'false');
    notifyListeners();
  }

  Future<void> _loadSessionPermissionsFromStorage() async {
    _currentRole =
        LocalDatabaseService.getString(AppStore._currentRoleKey) ?? 'admin';
  }

  Future<void> _restoreActiveUserFromStorage() async {
    final activeId = LocalDatabaseService.getString(AppStore._activeUserKey);
    if (activeId == null || activeId.trim().isEmpty) return;
    final match =
        _users.where((user) => user.id == activeId).toList(growable: false);
    if (match.isEmpty) return;
    _activeUser = match.first;
  }

  Future<void> _refreshAuthFlags() async {
    _rememberLogin =
        LocalDatabaseService.getString(AppStore._rememberLoginKey) == 'true';
  }

  void refreshUi() {
    notifyListeners();
  }

  Future<bool> applySupportPasswordResetToLocalUser({
    required String username,
    required String newPassword,
  }) async {
    final normalized = username.trim().toLowerCase();
    final cleanPassword = newPassword.trim();
    if (normalized.isEmpty || cleanPassword.length < 6) return false;
    final index = _users.indexWhere(
      (user) =>
          user.isActive && user.username.trim().toLowerCase() == normalized,
    );
    if (index < 0) return false;
    final current = _users[index];
    _users[index] = current.copyWith(
      passwordHash: await _hashPasswordAsync(cleanPassword),
      updatedAt: DateTime.now(),
    );
    await _saveRolesAndUsers();
    notifyListeners();
    return true;
  }

  Future<bool> verifyAdminPassword(String password) async {
    final user = _activeUser;
    if (user == null || !_isAdmin) return false;
    return _verifyPasswordAsync(password, user.passwordHash);
  }

  Future<bool> _verifyPasswordAsync(String password, String storedHash) async {
    if (storedHash.startsWith(AppStore._passwordHashPrefix)) {
      return compute(_verifyPasswordInBackground, <String, String>{
        'password': password.trim(),
        'storedHash': storedHash,
      });
    }
    return _verifyPassword(password, storedHash);
  }

  bool _verifyPassword(String password, String storedHash) {
    final cleaned = password.trim();
    if (storedHash.startsWith(AppStore._passwordHashPrefix)) {
      final parts = storedHash.split(':');
      if (parts.length != 4) return false;
      final iterations = int.tryParse(parts[1]);
      if (iterations == null || iterations < 100000) return false;
      return storedHash ==
          _hashPasswordWithSalt(cleaned, parts[2], iterations: iterations);
    }

    // Backward compatibility for accounts created before the password hash
    // upgrade. Password changes and first-run setup now write PBKDF2 hashes.
    if (storedHash.startsWith(AppStore._legacyLocalCredentialHashPrefix)) {
      final parts = storedHash.split(':');
      if (parts.length != 3) return false;
      return storedHash ==
          _hashLegacyLocalCredentialWithSalt(cleaned, parts[1]);
    }
    return false;
  }

  Future<void> addOrUpdateRole(UserRole role) async {
    requirePermission(AppPermission.rolesManage);
    _requireSensitiveActionAuthorization(SensitiveAction.rolesManage);
    if (role.name.trim().isEmpty) throw ArgumentError('Role name is required.');
    if (role.id == 'admin') {
      throw StateError('The built-in Admin role cannot be edited.');
    }
    final now = DateTime.now();
    final id =
        role.id.trim().isEmpty ? 'role_${now.microsecondsSinceEpoch}' : role.id;
    final saved = UserRole(
      id: id,
      name: role.name.trim(),
      permissions: role.permissions.intersection(
        Set<String>.from(AppPermission.all),
      ),
      isSystem: false,
      createdAt: role.createdAt ?? now,
      updatedAt: now,
    );
    final index = _roles.indexWhere((item) => item.id == id);
    if (index == -1) {
      _roles.add(saved);
    } else {
      if (_roles[index].isSystem) {
        throw StateError('System roles cannot be edited.');
      }
      _roles[index] = saved;
    }
    _recordSyncChange(
      entityType: 'role',
      entityId: saved.id,
      operation: index == -1 ? 'create' : 'update',
      payload: saved.toJson(),
    );
    await _saveRolesAndUsers();
    await _saveSyncStateOnly();
    await AuditLogger.record(
      entityType: 'role',
      entityId: saved.id,
      action: index == -1 ? 'create' : 'update',
      summary: index == -1 ? 'Role created' : 'Role updated',
      details: jsonEncode(<String, Object?>{
        'name': saved.name,
        'permissions': saved.permissions.toList()..sort(),
      }),
      userId: _activeUser?.id ?? '',
      userName: _activeUser?.username ?? '',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      sessionId: _deviceId,
      traceId: _deviceId,
      deviceId: _deviceId,
      sourceModule: 'security',
      isImportant: true,
    );
    notifyListeners();
  }

  Future<void> deleteRole(String id) async {
    requirePermission(AppPermission.rolesManage);
    _requireSensitiveActionAuthorization(SensitiveAction.rolesManage);
    if (id == 'admin') throw StateError('The Admin role cannot be deleted.');
    if (_users.any((user) => user.roleId == id)) {
      throw StateError('Move users to another role before deleting this role.');
    }
    final removed = _roles.firstWhere(
      (role) => role.id == id && !role.isSystem,
    );
    _roles.removeWhere((role) => role.id == id && !role.isSystem);
    _recordSyncChange(
      entityType: 'role',
      entityId: id,
      operation: 'delete',
      payload: removed.toJson(),
    );
    await _saveRolesAndUsers();
    await _saveSyncStateOnly();
    await AuditLogger.record(
      entityType: 'role',
      entityId: id,
      action: 'delete',
      summary: 'Role deleted',
      details: jsonEncode(<String, Object?>{
        'name': removed.name,
        'permissions': removed.permissions.toList()..sort(),
      }),
      userId: _activeUser?.id ?? '',
      userName: _activeUser?.username ?? '',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      sessionId: _deviceId,
      traceId: _deviceId,
      deviceId: _deviceId,
      sourceModule: 'security',
      isImportant: true,
    );
    notifyListeners();
  }

  bool _isStoreOwnerUser(AppUser user) {
    return user.isSystem && user.roleId == 'admin';
  }

  Future<void> _syncStoreOwnerUserToControlPlane(
    AppUser current,
    AppUser desired, {
    String? password,
  }) async {
    var cache = AccountAuthCache.load();
    var token = cache?.accountToken.trim() ?? '';
    final localStoreId = appIdentity.storeId.trim();
    final onlineStoreId = cache?.storeId.trim() ?? '';
    if (cache == null ||
        cache.accountType != 'store_owner' ||
        localStoreId.isEmpty ||
        onlineStoreId.isEmpty ||
        localStoreId != onlineStoreId ||
        token.isEmpty) {
      throw const AppStoreActionException(
        'The Store Owner must be signed in to the matching store account before editing this password.',
      );
    }

    final authService = AccountAuthService();
    final session = await authService.refreshSession(
      accountToken: token,
      refreshToken: cache.refreshToken,
    );
    if (session.ok) {
      if (session.accountType != 'store_owner' ||
          session.storeId.trim() != localStoreId) {
        throw const AppStoreActionException(
          'The signed-in account does not belong to this Store Owner.',
        );
      }
      cache = AccountAuthCache.load() ?? cache;
      final previous = cache;
      await AccountAuthCache.save(
        previous.copyWith(
          accountId: session.accountId.isNotEmpty
              ? session.accountId
              : previous.accountId,
          storeId:
              session.storeId.isNotEmpty ? session.storeId : previous.storeId,
          branchId: session.branchId.isNotEmpty
              ? session.branchId
              : previous.branchId,
          subscriptionStatus: session.subscriptionStatus.isNotEmpty
              ? session.subscriptionStatus
              : previous.subscriptionStatus,
          username: session.username.isNotEmpty
              ? session.username
              : previous.username,
          storeSlug: session.storeSlug.isNotEmpty
              ? session.storeSlug
              : previous.storeSlug,
          storeName: session.storeName.isNotEmpty
              ? session.storeName
              : previous.storeName,
          loginName: session.loginName.isNotEmpty
              ? session.loginName
              : previous.loginName,
          accountType: session.accountType.isNotEmpty
              ? session.accountType
              : previous.accountType,
          trialEndsAt: session.trialEndsAt ?? previous.trialEndsAt,
          devicesLimit: session.devicesLimit ?? previous.devicesLimit,
          adminToken: session.adminToken.isNotEmpty
              ? session.adminToken
              : previous.adminToken,
          accountToken: session.accountToken.isNotEmpty
              ? session.accountToken
              : previous.accountToken,
          refreshToken: session.refreshToken.isNotEmpty
              ? session.refreshToken
              : previous.refreshToken,
          directSyncEnabled: session.directSyncEnabled,
          lastVerifiedAt: DateTime.now(),
        ),
      );
      token = session.accountToken.isNotEmpty ? session.accountToken : token;
    } else if (session.message.toLowerCase().contains('session') ||
        session.message.toLowerCase().contains('unauthorized') ||
        session.message.toLowerCase().contains('token') ||
        session.message.contains('401')) {
      throw const AppStoreActionException(
        'Account re-authentication required before editing the protected Store Owner.',
      );
    }

    final normalizedUsername = desired.username.trim().toLowerCase();
    final cleanName = desired.fullName.trim().isEmpty
        ? 'Administrator'
        : desired.fullName.trim();
    final result = await authService.updateOwnerProfile(
      accountToken: token,
      username: normalizedUsername,
      fullName: cleanName,
      newPassword: password,
    );
    if (!result.ok) {
      final msg = result.message.toLowerCase();
      if (msg.contains('session') ||
          msg.contains('unauthorized') ||
          msg.contains('token') ||
          msg.contains('401')) {
        throw const AppStoreActionException(
          'Account re-authentication required before editing the protected Store Owner.',
        );
      }
      throw AppStoreActionException(
        result.message.isEmpty
            ? 'The account service rejected the Store Owner update. Local changes were not saved.'
            : result.message,
      );
    }
    cache = AccountAuthCache.load();
    if (cache != null) {
      await AccountAuthCache.save(
        cache.copyWith(
          accountId:
              result.accountId.isNotEmpty ? result.accountId : cache.accountId,
          storeId: result.storeId.isNotEmpty ? result.storeId : cache.storeId,
          branchId:
              result.branchId.isNotEmpty ? result.branchId : cache.branchId,
          subscriptionStatus: result.subscriptionStatus.isNotEmpty
              ? result.subscriptionStatus
              : cache.subscriptionStatus,
          username:
              result.username.isNotEmpty ? result.username : normalizedUsername,
          storeSlug:
              result.storeSlug.isNotEmpty ? result.storeSlug : cache.storeSlug,
          storeName:
              result.storeName.isNotEmpty ? result.storeName : cache.storeName,
          loginName:
              result.loginName.isNotEmpty ? result.loginName : cache.loginName,
          accountType: result.accountType.isNotEmpty
              ? result.accountType
              : cache.accountType,
          trialEndsAt: result.trialEndsAt ?? cache.trialEndsAt,
          devicesLimit: result.devicesLimit ?? cache.devicesLimit,
          adminToken: result.adminToken.isNotEmpty
              ? result.adminToken
              : cache.adminToken,
          accountToken: result.accountToken.isNotEmpty
              ? result.accountToken
              : cache.accountToken,
          directSyncEnabled: result.directSyncEnabled,
          lastVerifiedAt: DateTime.now(),
        ),
      );
    }
  }

  AppUser? get storeOwnerUser {
    for (final user in _users) {
      if (_isStoreOwnerUser(user)) return user;
    }
    return null;
  }
}
