part of 'app_store.dart';

extension _AppStoreSplitIdentityUsers on AppStore {
AppPlatformType _detectPlatform() {
    if (kIsWeb) return AppPlatformType.web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return AppPlatformType.windows;
      case TargetPlatform.android:
        return AppPlatformType.android;
      default:
        return AppPlatformType.unknown;
    }
  }

AppIdentity _loadOrCreateAppIdentity() {
    final raw = LocalDatabaseService.getString(AppStore._appIdentityKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final parsed = AppIdentity.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        final token = parsed.deviceToken.trim().isNotEmpty
            ? parsed.deviceToken.trim()
            : 'device_${DateTime.now().microsecondsSinceEpoch}_${_deviceId.hashCode.abs()}';
        final normalized = parsed.copyWith(
          deviceId: _deviceId,
          platform: _detectPlatform(),
          deviceToken: token,
          deviceName: parsed.deviceName.trim().isNotEmpty
              ? parsed.deviceName.trim()
              : _deviceId,
        );
        unawaited(
          LocalDatabaseService.setString(
            AppStore._appIdentityKey,
            jsonEncode(normalized.toJson()),
          ),
        );
        return normalized;
      } catch (_) {}
    }
    final created = AppIdentity.defaults(
      deviceId: _deviceId,
      platform: _detectPlatform(),
      detectedDeviceName: _detectInitialDeviceName(),
    );
    unawaited(
      LocalDatabaseService.setString(
        AppStore._appIdentityKey,
        jsonEncode(created.toJson()),
      ),
    );
    return created;
  }

String _detectInitialDeviceName() {
    // Keep this conservative and dependency-free. When a platform-specific real
    // device name provider is added later, return it here. Until then, defaults
    // fall back to the stable Ventio deviceId instead of the legacy "Main device".
    return '';
  }

Future<void> updateDeviceName(String deviceName) async {
    requirePermission(AppPermission.settingsManage);
    final cleanName = deviceName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleanName.isEmpty) {
      throw ArgumentError('Device name cannot be empty.');
    }
    if (cleanName.length > 60) {
      throw ArgumentError('Device name must be 60 characters or fewer.');
    }
    final current = appIdentity;
    if (current.deviceName == cleanName) return;
    final normalized = _normalizedLocalIdentity(
      current.copyWith(deviceName: cleanName),
    );
    _appIdentity = normalized;
    await LocalDatabaseService.setString(
      AppStore._appIdentityKey,
      jsonEncode(normalized.toJson()),
    );
    _recordSyncChange(
      entityType: 'app_identity',
      entityId: _deviceId,
      operation: 'update',
      payload: normalized.toJson(),
    );
    await _saveSyncStateOnly();
    notifyListeners();
  }

Future<void> recoverExistingStoreIdentity({
    required String storeId,
    String recoveryKey = '',
    String? branchId,
    String? hostDeviceId,
    String? deviceToken,
    String? controlPlaneTenantId,
    DeviceRole? deviceRole,
    SyncMode? syncMode,
  }) async {
    final cleanStoreId = storeId.trim().toUpperCase();
    final cleanRecoveryKey = recoveryKey.trim().toUpperCase();
    if (!cleanStoreId.startsWith('ST-')) {
      throw ArgumentError('A valid Store ID is required.');
    }
    final cleanBranchId = (branchId == null || branchId.trim().isEmpty)
        ? appIdentity.branchId
        : branchId.trim().toUpperCase();
    final nextRole = deviceRole ?? appIdentity.deviceRole;
    final recoveredIdentity = appIdentity.copyWith(
      storeId: cleanStoreId,
      branchId: cleanBranchId,
      recoveryKey:
          cleanRecoveryKey.isEmpty ? appIdentity.recoveryKey : cleanRecoveryKey,
      hostDeviceId: hostDeviceId ??
          (nextRole == DeviceRole.host ? _deviceId : appIdentity.hostDeviceId),
      deviceToken: (deviceToken == null || deviceToken.trim().isEmpty)
          ? appIdentity.deviceToken
          : deviceToken.trim(),
      controlPlaneTenantId:
          (controlPlaneTenantId == null || controlPlaneTenantId.trim().isEmpty)
              ? appIdentity.controlPlaneTenantId
              : controlPlaneTenantId.trim(),
      deviceRole: nextRole,
      syncMode: syncMode ?? appIdentity.syncMode,
      deviceId: _deviceId,
      platform: _detectPlatform(),
      updatedAt: DateTime.now(),
    );
    _assertLanDirectRoleRules(recoveredIdentity, source: 'store recovery');
    _appIdentity = recoveredIdentity;
    await LocalDatabaseService.setString(
      AppStore._appIdentityKey,
      jsonEncode(_appIdentity!.toJson()),
    );
    notifyListeners();
  }

AppIdentity _identityForLanSnapshotImport(Map<String, dynamic> decoded) {
    final local = appIdentity;
    if (local.isHost) {
      return local.copyWith(
        deviceId: _deviceId,
        platform: _detectPlatform(),
        updatedAt: DateTime.now(),
      );
    }
    if (decoded['appIdentity'] is! Map) {
      return local.copyWith(deviceId: _deviceId, platform: _detectPlatform());
    }
    final remote = AppIdentity.fromJson(
      Map<String, dynamic>.from(decoded['appIdentity'] as Map),
    );
    return local.copyWith(
      storeId: remote.storeId.isNotEmpty ? remote.storeId : local.storeId,
      branchId: remote.branchId.isNotEmpty ? remote.branchId : local.branchId,
      deviceId: _deviceId,
      platform: _detectPlatform(),
      deviceRole: DeviceRole.client,
      appRole: remote.appRole,
      syncMode: local.syncMode == SyncMode.localOnly
          ? SyncMode.lanOnly
          : local.syncMode,
      hostDeviceId:
          remote.deviceId.isNotEmpty ? remote.deviceId : local.hostDeviceId,
      controlPlaneTenantId: remote.controlPlaneTenantId.isNotEmpty
          ? remote.controlPlaneTenantId
          : local.controlPlaneTenantId,
      deviceToken: local.deviceToken.trim().isNotEmpty
          ? local.deviceToken
          : 'device_${DateTime.now().microsecondsSinceEpoch}_${_deviceId.hashCode.abs()}',
      updatedAt: DateTime.now(),
    );
  }

AppIdentity _normalizedLocalIdentity(AppIdentity identity) {
    final token = identity.deviceToken.trim().isNotEmpty
        ? identity.deviceToken.trim()
        : 'device_${DateTime.now().microsecondsSinceEpoch}_${_deviceId.hashCode.abs()}';
    return identity.copyWith(
      deviceId: _deviceId,
      platform: _detectPlatform(),
      deviceToken: token,
      updatedAt: DateTime.now(),
    );
  }

bool _isApprovedHostTransferTarget() {
    final approvedDeviceId = LocalDatabaseService.getString(
          AppStore._hostTransferApprovedDeviceKey,
        )?.trim() ??
        '';
    return approvedDeviceId.isNotEmpty && approvedDeviceId == _deviceId;
  }

Map<String, dynamic>? get pendingHostTransferRequest {
    final raw =
        LocalDatabaseService.getString(AppStore._hostTransferRequestKey)?.trim() ?? '';
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

Map<String, dynamic>? get latestHostTransferNotification {
    final raw =
        LocalDatabaseService.getString(AppStore._hostTransferNotificationKey)?.trim() ??
            '';
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

Future<void> clearHostTransferNotification() async {
    await LocalDatabaseService.setString(AppStore._hostTransferNotificationKey, '');
    notifyListeners();
  }

Future<void> _storeHostTransferNotification(
    Map<String, dynamic> payload,
  ) async {
    await LocalDatabaseService.setString(
      AppStore._hostTransferNotificationKey,
      jsonEncode(payload),
    );
  }

Future<void> clearLocalHostTransferRequest() async {
    await LocalDatabaseService.setString(AppStore._hostTransferRequestKey, '');
    notifyListeners();
  }

Future<void> _forceApplyRoleFromTransfer(AppIdentity next) async {
    final normalized = _normalizedLocalIdentity(next);
    _appIdentity = normalized;
    await LocalDatabaseService.setString(
      AppStore._appIdentityKey,
      jsonEncode(normalized.toJson()),
    );
  }

void _assertSafeRoleTransition(
    AppIdentity next, {
    required String source,
    bool allowApprovedTransfer = false,
    bool allowInitialHostRegistration = false,
  }) {
    final current = _appIdentity;
    if (current == null) return;
    if (current.deviceRole == next.deviceRole) return;

    // Fix #4: backup, restore, pairing, rebuild, and snapshot import flows must
    // never silently convert a Host into a Client. Host role changes are only
    // allowed through the official Transfer Host flow.
    if (current.isHost && next.isClient) {
      throw StateError(
        'Host devices cannot be converted to Clients by $source. Use Transfer Host instead.',
      );
    }

    // A Client can become Host only after an explicit Host transfer approval.
    if (current.isClient &&
        next.isHost &&
        !allowInitialHostRegistration &&
        !(allowApprovedTransfer && _isApprovedHostTransferTarget())) {
      throw StateError(
        'Client devices cannot become Host by $source. Request and approve Transfer Host first.',
      );
    }
  }

void _assertLanDirectRoleRules(AppIdentity next, {required String source}) {
    final platform = next.platform == AppPlatformType.unknown
        ? _detectPlatform()
        : next.platform;

    // Fix #9: Web devices must never be authoritative Hosts because browsers
    // cannot reliably run the local Host API/server and should not own Host
    // authority for Direct either.
    if (platform == AppPlatformType.web && next.isHost) {
      throw StateError(
        'Web devices cannot operate as Host. Use a desktop or native mobile Host device.',
      );
    }

    final lanHost = _isLanHostConfigured;
    final lanClient = _isLanClientConfigured;
    final directClient =
        next.isClient && next.activeSyncTransportNormalized == 'direct';
    final lanIdentityClient =
        next.isClient && next.syncMode == SyncMode.lanOnly;

    // A Host may expose LAN and Direct together. It must not simultaneously
    // carry LAN Client state from an old pairing.
    if (next.isHost && lanClient) {
      throw StateError(
        'A Host device cannot keep LAN Client state. Clear local data or use Transfer Host before changing sync role.',
      );
    }

    // A Client may have both transport configurations available, but only one
    // active transport may run at a time.
    if (next.isClient && lanClient && directClient) {
      final active = next.activeSyncTransportNormalized;
      if (active != 'lan' && active != 'direct') {
        throw StateError(
          'Client has LAN and Direct configured but no active sync transport was selected.',
        );
      }
    }
    if (lanIdentityClient && directClient) {
      final active = next.activeSyncTransportNormalized;
      if (active != 'lan' && active != 'direct') {
        throw StateError(
          'Client has LAN and Direct configured but no active sync transport was selected.',
        );
      }
    }

    // Prevent a Host from retaining Client configuration from a prior pairing.
    if (lanHost && directClient) {
      throw StateError(
        'LAN Host + Direct Client is not allowed by $source. Host devices cannot be Clients in another sync system.',
      );
    }
  }

Future<void> updateAppIdentityDuringSetup(AppIdentity identity) async {
    final normalized = _normalizedLocalIdentity(identity);
    _assertSafeRoleTransition(normalized, source: 'setup/pairing/rebuild');
    _assertLanDirectRoleRules(normalized, source: 'setup/pairing/rebuild');
    _appIdentity = normalized;
    await LocalDatabaseService.setString(
      AppStore._appIdentityKey,
      jsonEncode(normalized.toJson()),
    );
    await SyncDeviceStateStore.setActiveTransport(
      normalized,
      normalized.activeSyncTransportNormalized,
    );
    notifyListeners();
  }

Future<void> updateAppIdentity(AppIdentity identity) async {
    requirePermission(AppPermission.settingsManage);
    final normalized = _normalizedLocalIdentity(identity);
    _assertSafeRoleTransition(normalized, source: 'settings update');
    _assertLanDirectRoleRules(normalized, source: 'settings update');
    final previousJson = jsonEncode(appIdentity.toJson());
    final nextJson = jsonEncode(normalized.toJson());
    if (previousJson == nextJson) return;
    _appIdentity = normalized;
    await LocalDatabaseService.setString(AppStore._appIdentityKey, nextJson);
    _recordSyncChange(
      entityType: 'app_identity',
      entityId: _deviceId,
      operation: 'update',
      payload: normalized.toJson(),
    );
    await _saveSyncStateOnly();
    await SyncDeviceStateStore.setActiveTransport(
      normalized,
      normalized.activeSyncTransportNormalized,
    );
    notifyListeners();
  }

Future<void> updateAppIdentityLocalOnly(
    AppIdentity identity, {
    String source = 'local sync settings',
  }) async {
    requirePermission(AppPermission.syncManage);
    final normalized = _normalizedLocalIdentity(identity);
    _assertSafeRoleTransition(normalized, source: source);
    _assertLanDirectRoleRules(normalized, source: source);
    final previousJson = jsonEncode(appIdentity.toJson());
    final nextJson = jsonEncode(normalized.toJson());
    if (previousJson == nextJson) return;
    _appIdentity = normalized;
    await LocalDatabaseService.setString(AppStore._appIdentityKey, nextJson);
    await SyncDeviceStateStore.setActiveTransport(
      normalized,
      normalized.activeSyncTransportNormalized,
    );
    notifyListeners();
  }

Future<void> setActiveSyncTransport(String transport) async {
    requirePermission(AppPermission.syncManage);
    final normalizedTransport = transport.trim().toLowerCase();
    if (normalizedTransport != 'lan' && normalizedTransport != 'direct') {
      throw ArgumentError(
          'Active sync transport must be either lan or direct.');
    }
    final identity = appIdentity;
    if (!identity.isClient) {
      throw StateError(
        'Only Client devices switch the active sync transport. Hosts may run LAN and Direct together.',
      );
    }
    if (normalizedTransport == 'lan' && !_isLanClientConfigured) {
      throw StateError(
        'LAN is configured only when this device has a saved Client pairing. Configure LAN before switching to it.',
      );
    }
    if (normalizedTransport == 'direct' && !_isDirectClientConfigured) {
      throw StateError(
        'Direct is configured only when this device has saved Direct credentials. Pair this device with a Host before switching to Direct.',
      );
    }

    final nextIdentity = identity.copyWith(
      syncMode: normalizedTransport == 'lan'
          ? SyncMode.lanOnly
          : SyncMode.directConnected,
      activeSyncTransport: normalizedTransport,
      updatedAt: DateTime.now(),
    );
    _assertLanDirectRoleRules(nextIdentity, source: 'active transport switch');
    _appIdentity = nextIdentity;
    await LocalDatabaseService.setString(
      AppStore._appIdentityKey,
      jsonEncode(nextIdentity.toJson()),
    );
    await SyncDeviceStateStore.setActiveTransport(
      nextIdentity,
      normalizedTransport,
    );
    await _retargetPendingClientSyncQueue(normalizedTransport);
    notifyListeners();
  }

Future<void> _retargetPendingClientSyncQueue(String activeTransport) async {
    final newTarget = 'host';
    final oldTarget = 'host';
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _syncQueue.length; i++) {
      final item = _syncQueue[i];
      if (item.target == oldTarget && item.isPending) {
        _syncQueue[i] = item.copyWith(
          id: '${item.changeId}-$newTarget',
          target: newTarget,
          status: 'pending',
          updatedAt: now,
          clearNextRetryAt: true,
        );
        changed = true;
      }
    }
    if (changed) await _saveSyncStateOnly();
  }

Future<void> requestHostTransfer({String reason = ''}) async {
    requirePermission(AppPermission.syncManage);
    if (!appIdentity.isClient) {
      throw StateError('Only a Client device can request Host transfer.');
    }
    final payload = <String, dynamic>{
      'requestingDeviceId': _deviceId,
      'storeId': appIdentity.storeId,
      'branchId': appIdentity.branchId,
      'hostDeviceId': appIdentity.hostDeviceId,
      'reason': reason.trim(),
      'requestedAt': DateTime.now().toIso8601String(),
      'status': 'pending',
    };
    await LocalDatabaseService.setString(
      AppStore._hostTransferRequestKey,
      jsonEncode(payload),
    );
    _recordSyncChange(
      entityType: 'host_transfer',
      entityId: _deviceId,
      operation: 'request',
      payload: payload,
    );
    await _saveSyncStateOnly();
    notifyListeners();
  }

Future<void> approveHostTransfer(String requestingDeviceId) async {
    requirePermission(AppPermission.syncManage);
    final cleanDeviceId = requestingDeviceId.trim();
    if (!appIdentity.isHost) {
      throw StateError('Only the current Host can approve Host transfer.');
    }
    if (cleanDeviceId.isEmpty || cleanDeviceId == _deviceId) {
      throw ArgumentError('A valid requesting Client Device ID is required.');
    }
    await LocalDatabaseService.setString(
      AppStore._hostTransferApprovedDeviceKey,
      cleanDeviceId,
    );
    final transferPayload = <String, dynamic>{
      'approvedDeviceId': cleanDeviceId,
      'approvedByHostDeviceId': _deviceId,
      'storeId': appIdentity.storeId,
      'branchId': appIdentity.branchId,
      'approvedAt': DateTime.now().toIso8601String(),
    };
    _recordSyncChange(
      entityType: 'host_transfer',
      entityId: cleanDeviceId,
      operation: 'approve',
      payload: transferPayload,
    );
    _recordSyncChange(
      entityType: 'host_transfer',
      entityId: cleanDeviceId,
      operation: 'host_transfer_approved_pending_activation',
      payload: {...transferPayload, 'status': 'approved_pending_activation'},
    );

    // The current Host must remain authoritative after approval. The device
    // requesting the transfer becomes Host only after explicit activation, then
    // publishes HOST_CHANGED. This prevents any period with no Host.
    await LocalDatabaseService.setString(
      AppStore._hostTransferRequestKey,
      jsonEncode({
        ...transferPayload,
        'requestingDeviceId': cleanDeviceId,
        'status': 'approved_pending_activation',
      }),
    );
    await _saveSyncStateOnly();
    notifyListeners();
  }

Future<void> activateApprovedHostTransfer() async {
    requirePermission(AppPermission.syncManage);
    if (!appIdentity.isClient) {
      throw StateError(
        'Only a Client device can activate an approved Host transfer.',
      );
    }
    if (!_isApprovedHostTransferTarget()) {
      throw StateError('No approved Host transfer was found for this device.');
    }
    final oldHostDeviceId = appIdentity.hostDeviceId;
    final next = _normalizedLocalIdentity(
      appIdentity.copyWith(
        deviceRole: DeviceRole.host,
        hostDeviceId: '',
        updatedAt: DateTime.now(),
      ),
    );
    _assertSafeRoleTransition(
      next,
      source: 'approved Host transfer',
      allowApprovedTransfer: true,
    );
    _assertLanDirectRoleRules(next, source: 'approved Host transfer');
    _appIdentity = next;
    await LocalDatabaseService.setString(
      AppStore._appIdentityKey,
      jsonEncode(next.toJson()),
    );
    await LocalDatabaseService.setString(AppStore._hostTransferApprovedDeviceKey, '');
    final activationPayload = <String, dynamic>{
      'newHostDeviceId': _deviceId,
      'oldHostDeviceId': oldHostDeviceId,
      'storeId': next.storeId,
      'branchId': next.branchId,
      'activatedAt': DateTime.now().toIso8601String(),
    };
    _recordSyncChange(
      entityType: 'host_transfer',
      entityId: _deviceId,
      operation: 'activate',
      payload: activationPayload,
    );
    _recordSyncChange(
      entityType: 'host_transfer',
      entityId: _deviceId,
      operation: 'new_host_activated',
      payload: activationPayload,
    );
    _recordSyncChange(
      entityType: 'host_transfer',
      entityId: _deviceId,
      operation: 'HOST_CHANGED',
      payload: activationPayload,
    );
    await _saveSyncStateOnly();
    notifyListeners();
  }

Future<void> setCurrentRole(String role) async {
    throw StateError('Roles must be assigned through Users & Permissions.');
  }

Future<List<UserRole>> _loadRoles() async {
    final db = SqliteMigrationManager.database;
    final raw = LocalDatabaseService.isInMemoryStoreForTesting
        ? LocalDatabaseService.testingRawValue(AppStore._rolesKey)
        : kIsWeb
            ? LocalDatabaseService.getString(AppStore._rolesKey)
            : db == null
                ? null
                : await BusinessSqliteStore.readEntityListJsonByKey(
                    db, AppStore._rolesKey);
    if (raw == null || raw.isEmpty) return <UserRole>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map(
          (item) => UserRole.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

Future<List<AppUser>> _loadUsers() async {
    final db = SqliteMigrationManager.database;
    final raw = LocalDatabaseService.isInMemoryStoreForTesting
        ? LocalDatabaseService.testingRawValue(AppStore._usersKey)
        : kIsWeb
            ? LocalDatabaseService.getString(AppStore._usersKey)
            : db == null
                ? null
                : await BusinessSqliteStore.readEntityListJsonByKey(
                    db, AppStore._usersKey);
    if (raw == null || raw.isEmpty) return <AppUser>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => AppUser.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

Future<void> _saveRolesAndUsers() async {
    await LocalDatabaseService.setString(
      AppStore._rolesKey,
      jsonEncode(_roles.map((item) => item.toJson()).toList()),
    );
    await LocalDatabaseService.setString(
      AppStore._usersKey,
      jsonEncode(_users.map((item) => item.toJson()).toList()),
    );
  }

Future<void> _ensureDefaultAdminUser() async {
    final now = DateTime.now();
    final existingAdminRole = _roles.indexWhere((role) => role.id == 'admin');
    if (existingAdminRole == -1) {
      _roles.add(
        UserRole(
          id: 'admin',
          name: 'Admin',
          permissions: Set<String>.from(AppPermission.all),
          isSystem: true,
          createdAt: now,
          updatedAt: now,
        ),
      );
    } else {
      _roles[existingAdminRole] = _roles[existingAdminRole].copyWith(
        name: 'Admin',
        permissions: Set<String>.from(AppPermission.all),
        isSystem: true,
        updatedAt: now,
      );
    }
    // Do not create a default admin account/password. A first-time install
    // must create its initial administrator from the login setup screen.
    await _saveRolesAndUsers();
  }

void _restoreActiveUser() {
    if (isSuspendedByHost) {
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
    if (isSuspendedByHost) return false;
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
      clearSensitiveActionAuthorization();
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
    clearSensitiveActionAuthorization();
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
    await LocalDatabaseService.setString(AppStore._activeUserKey, activeUser.id);
    await LocalDatabaseService.setString(AppStore._currentRoleKey, currentRole);
    await LocalDatabaseService.setString(
      AppStore._rememberLoginKey,
      rememberLogin ? 'true' : 'false',
    );
    await _saveRolesAndUsers();
    notifyListeners();
  }

Future<void> clearSessionUser() async {
    clearSensitiveActionAuthorization();
    _activeUser = null;
    _rememberLogin = false;
    await LocalDatabaseService.setString(AppStore._activeUserKey, '');
    await LocalDatabaseService.setString(AppStore._currentRoleKey, 'admin');
    await LocalDatabaseService.setString(AppStore._rememberLoginKey, 'false');
    notifyListeners();
  }

Future<void> _loadSessionPermissionsFromStorage() async {
    _currentRole = LocalDatabaseService.getString(AppStore._currentRoleKey) ?? 'admin';
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
    if (user == null || !isAdmin) return false;
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
    requireSensitiveActionAuthorization(SensitiveAction.rolesManage);
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
    requireSensitiveActionAuthorization(SensitiveAction.rolesManage);
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

Future<void> applyStoreOwnerCredentials({
    required String username,
    required String password,
    String? fullName,
  }) async {
    requireSensitiveActionAuthorization(SensitiveAction.storeOwnerCredentials);
    final owner = storeOwnerUser;
    if (owner == null) return;
    final cleanPassword = password.trim();
    if (cleanPassword.length < 6) {
      throw ArgumentError(
          'Store Owner password must be at least 6 characters.');
    }
    final index = _users.indexWhere((item) => item.id == owner.id);
    if (index == -1) return;
    final normalizedUsername = username.trim().toLowerCase().isEmpty
        ? owner.username.trim().toLowerCase()
        : username.trim().toLowerCase();
    final cleanName = (fullName ?? owner.fullName).trim().isEmpty
        ? owner.fullName
        : (fullName ?? owner.fullName).trim();
    final updated = owner.copyWith(
      username: normalizedUsername,
      fullName: cleanName,
      passwordHash: await _hashPasswordAsync(cleanPassword),
      roleId: 'admin',
      extraPermissions: const <String>{},
      deniedPermissions: const <String>{},
      isActive: true,
      isSystem: true,
      updatedAt: DateTime.now(),
    );
    _users[index] = updated;
    if (_activeUser?.id == updated.id) _activeUser = updated;
    await _saveRolesAndUsers();
    await AuditLogger.record(
      entityType: 'user',
      entityId: updated.id,
      action: 'store_owner_credentials_changed',
      summary: 'Store Owner credentials changed',
      details: jsonEncode(<String, Object?>{
        'username': updated.username,
        'fullName': updated.fullName,
        'passwordChanged': true,
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

Future<void> addOrUpdateUser(AppUser user, {String? password}) async {
    requirePermission(AppPermission.usersManage);
    requireSensitiveActionAuthorization(SensitiveAction.usersManage);
    if (user.fullName.trim().isEmpty || user.username.trim().isEmpty) {
      throw ArgumentError('Name and username are required.');
    }
    if (roleById(user.roleId) == null) throw ArgumentError('Role not found.');
    final normalizedUsername = user.username.trim().toLowerCase();
    final duplicate = _users.any(
      (item) =>
          item.id != user.id &&
          item.username.trim().toLowerCase() == normalizedUsername,
    );
    if (duplicate) throw ArgumentError('Username already exists.');
    final now = DateTime.now();
    final isCreate = user.id.trim().isEmpty ||
        _users.indexWhere((item) => item.id == user.id) == -1;
    if (isCreate && (password == null || password.trim().length < 6)) {
      throw ArgumentError('Password must be at least 6 characters.');
    }
    if (!isCreate &&
        password != null &&
        password.trim().isNotEmpty &&
        password.trim().length < 6) {
      throw ArgumentError('Password must be at least 6 characters.');
    }
    final id = user.id.trim().isEmpty
        ? 'user_${now.microsecondsSinceEpoch}'
        : user.id.trim();
    final index = _users.indexWhere((item) => item.id == id);
    final current = index == -1 ? null : _users[index];
    final editingStoreOwner = current != null && _isStoreOwnerUser(current);

    if (editingStoreOwner) {
      if (password != null &&
          password.trim().isNotEmpty &&
          password.trim().length < 6) {
        throw ArgumentError(
            'Store Owner password must be at least 6 characters.');
      }
      if (user.roleId != 'admin' || user.isActive != true) {
        throw const AppStoreActionException(
          'Store Owner must always keep Full Access and cannot be disabled.',
        );
      }
      if (user.extraPermissions.isNotEmpty ||
          user.deniedPermissions.isNotEmpty) {
        throw const AppStoreActionException(
          'Store Owner permissions are locked and cannot have local overrides.',
        );
      }
    }

    final saved = AppUser(
      id: id,
      fullName: user.fullName.trim(),
      username: normalizedUsername,
      passwordHash: password != null && password.trim().isNotEmpty
          ? await _hashPasswordAsync(password.trim())
          : user.passwordHash,
      roleId: editingStoreOwner ? 'admin' : user.roleId,
      extraPermissions: editingStoreOwner
          ? const <String>{}
          : user.extraPermissions.intersection(
              Set<String>.from(AppPermission.all),
            ),
      deniedPermissions: editingStoreOwner
          ? const <String>{}
          : user.deniedPermissions.intersection(
              Set<String>.from(AppPermission.all),
            ),
      isActive: editingStoreOwner ? true : user.isActive,
      isSystem: editingStoreOwner ? true : user.isSystem,
      createdAt: user.createdAt ?? now,
      updatedAt: now,
      lastLoginAt: user.lastLoginAt,
    );

    if (editingStoreOwner) {
      await _syncStoreOwnerUserToControlPlane(current, saved,
          password: password);
    }

    if (index == -1) {
      _users.add(saved);
    } else {
      if (_users[index].isSystem && saved.roleId != 'admin') {
        throw StateError('The built-in admin user must keep the Admin role.');
      }
      if (_users[index].isSystem && !editingStoreOwner) {
        throw StateError(
            'System users cannot be edited as regular local users.');
      }
      _users[index] = saved;
      if (_activeUser?.id == saved.id) _activeUser = saved;
    }
    _recordSyncChange(
      entityType: 'user',
      entityId: saved.id,
      operation: isCreate ? 'create' : 'update',
      payload: saved.toJson(),
    );
    await _saveRolesAndUsers();
    await _saveSyncStateOnly();
    await AuditLogger.record(
      entityType: 'user',
      entityId: saved.id,
      action: isCreate ? 'create' : 'update',
      summary: isCreate ? 'User created' : 'User updated',
      details: jsonEncode(<String, Object?>{
        'username': saved.username,
        'fullName': saved.fullName,
        'roleId': saved.roleId,
        'isActive': saved.isActive,
        'extraPermissions': saved.extraPermissions.toList()..sort(),
        'deniedPermissions': saved.deniedPermissions.toList()..sort(),
        'passwordChanged': password != null && password.trim().isNotEmpty,
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

Future<void> deleteUser(String id) async {
    requirePermission(AppPermission.usersManage);
    requireSensitiveActionAuthorization(SensitiveAction.usersManage);
    final user = _users.firstWhere((item) => item.id == id);
    final adminCount =
        _users.where((item) => item.roleId == 'admin' && item.isActive).length;
    if (user.roleId == 'admin' && adminCount <= 1) {
      throw StateError(
        'Create another active admin before deleting this user.',
      );
    }
    if (user.isSystem) {
      throw StateError('The built-in admin user cannot be deleted.');
    }
    _users.removeWhere((item) => item.id == id);
    _recordSyncChange(
      entityType: 'user',
      entityId: id,
      operation: 'delete',
      payload: user.toJson(),
    );
    await _saveRolesAndUsers();
    await _saveSyncStateOnly();
    await AuditLogger.record(
      entityType: 'user',
      entityId: id,
      action: 'delete',
      summary: 'User deleted',
      details: jsonEncode(<String, Object?>{
        'username': user.username,
        'fullName': user.fullName,
        'roleId': user.roleId,
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

Future<String> _hashPasswordAsync(String password) async {
    final salt = _generateSalt();
    return compute(_hashPasswordInBackground, <String, String>{
      'password': password,
      'salt': salt,
      'iterations': AppStore._passwordHashIterations.toString(),
    });
  }

String _hashPasswordWithSalt(
    String password,
    String salt, {
    required int iterations,
  }) {
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
    derivator.init(pc.Pbkdf2Parameters(base64Url.decode(salt), iterations, 32));
    final hash = derivator.process(
      Uint8List.fromList(utf8.encode('ventio|password|$password')),
    );
    return '${AppStore._passwordHashPrefix}$iterations:$salt:${base64UrlEncode(hash)}';
  }

String _hashLegacyLocalCredentialWithSalt(String password, String salt) {
    const legacyPurpose = 'store_manager_pro|local_'
        'p'
        'in_v2';
    List<int> digest = utf8.encode('$legacyPurpose|$salt|$password');
    for (var i = 0; i < 12000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return '${AppStore._legacyLocalCredentialHashPrefix}$salt:${base64UrlEncode(digest)}';
  }

String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

StoreProfile _loadStoreProfile() {
    final raw = LocalDatabaseService.getString(AppStore._storeProfileKey);
    if (raw == null) return StoreProfile.defaults;
    return StoreProfile.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  }

void _normalizeCustomers() {
    // Keep ID as the only source of truth.
    // Do not merge, delete, or hide customers only because they share the same name.
    // Offline devices may legitimately create separate records with identical names;
    // those records are surfaced through dataConflicts after sync instead.
    final normalized = <Customer>[];
    var hasWalkIn = false;
    final seenIds = <String>{};

    for (final customer in _customers) {
      final trimmedName = customer.name.trim();
      final normalizedName = trimmedName.toLowerCase();
      final isWalkIn = customer.id == AppStore.walkInCustomerId ||
          normalizedName == AppStore.walkInCustomerName.toLowerCase();

      if (isWalkIn) {
        if (!hasWalkIn) {
          normalized.add(walkInCustomer);
          hasWalkIn = true;
          seenIds.add(AppStore.walkInCustomerId);
        }
        continue;
      }

      if (seenIds.contains(customer.id)) {
        continue;
      }

      normalized.add(customer.copyWith(name: trimmedName));
      seenIds.add(customer.id);
    }

    if (!hasWalkIn) {
      normalized.insert(0, walkInCustomer);
    } else {
      normalized
        ..removeWhere((c) => c.id == AppStore.walkInCustomerId)
        ..insert(0, walkInCustomer);
    }

    _customers
      ..clear()
      ..addAll(normalized);
    _rebuildCustomerIndexes();
  }

Future<void> _persistProductDerivedData() async {
    if (!LocalDatabaseService.isSqliteAuthoritative) return;
    await Future.wait(<Future<void>>[
      _upsertSqliteBusinessRows(
        AppStore._priceListsKey,
        _priceLists.map((item) => item.toJson()),
      ),
      _upsertSqliteBusinessRows(
        AppStore._productPricesKey,
        _productPrices.map((item) => item.toJson()),
      ),
      _upsertSqliteBusinessRows(
        AppStore._productPriceOverridesKey,
        _productPriceOverrides.map((item) => item.toJson()),
      ),
      _upsertSqliteBusinessRows(
        AppStore._productCostsKey,
        _productCosts.map((item) => item.toJson()),
      ),
      LocalDatabaseService.setString(
        AppStore._inventoryCostingMethodKey,
        _inventoryCostingMethod.code,
      ),
      _upsertSqliteBusinessRows(
        AppStore._costingMethodHistoryKey,
        _costingMethodHistory.map((item) => item.toJson()),
      ),
      _upsertSqliteBusinessRows(
        AppStore._inventoryCostLayersKey,
        _inventoryCostLayers.map((item) => item.toJson()),
      ),
    ]);
  }

Future<void> _upsertSqliteBusinessRows(
    String key,
    Iterable<Map<String, dynamic>> rows,
  ) {
    final materializedRows = rows.toList(growable: false);
    if (!LocalDatabaseService.isSqliteAuthoritative) {
      return LocalDatabaseService.setString(key, jsonEncode(materializedRows));
    }
    return LocalDatabaseService.upsertBusinessEntityJsons(
      key,
      materializedRows,
    );
  }

void _markProductDerivedDataDirty() {
    _productDerivedDataDirty = true;
    _productDerivedDataFlushTimer?.cancel();
    _productDerivedDataFlushTimer = null;
    // Once shutdown draining has started, do not create a new timer-owned async
    // task. prepareForShutdown() drains the dirty flag synchronously instead.
    if (_shutdownPrepared) return;
    _productDerivedDataFlushTimer = Timer(
      const Duration(milliseconds: 120),
      () {
        _productDerivedDataFlushTimer = null;
        unawaited(_flushProductDerivedData());
      },
    );
  }

Future<void> _flushProductDerivedData() async {
    // Drain until both the dirty flag and any already-started write are clear.
    // The in-flight check must happen before the dirty check: an active writer
    // sets dirty=false before awaiting SQLite, so returning on !dirty here would
    // let shutdown close Drift while that writer is still running.
    while (true) {
      final inFlight = _productDerivedDataFlushInFlight;
      if (inFlight != null) {
        await inFlight;
        continue;
      }
      if (!_productDerivedDataDirty) return;

      _productDerivedDataDirty = false;
      final future = _persistProductDerivedData();
      _productDerivedDataFlushInFlight = future;
      try {
        await future;
      } finally {
        if (identical(_productDerivedDataFlushInFlight, future)) {
          _productDerivedDataFlushInFlight = null;
        }
      }
    }
  }

Future<bool> _schedulePurchaseAccounting(Purchase purchase) async {
    if (!AccountingService.isAvailable) return true;
    final purchaseId = purchase.id.trim();
    if (purchaseId.isEmpty) return false;
    while (_pendingPurchaseAccountingTasks.length >=
        AppStore._maxPurchaseAccountingBacklog) {
      final pending = _pendingPurchaseAccountingTasks.values.toList();
      if (pending.isEmpty) break;
      await Future.any<void>(
        pending.map((task) => task.catchError((_) => false)),
      );
    }
    final future = _purchaseAccountingQueue.then<bool>(
      (_) => _postPurchaseAccounting(purchase),
      onError: (_) => _postPurchaseAccounting(purchase),
    );
    _purchaseAccountingQueue = future.then<void>(
      (_) {},
      onError: (_) {},
    );
    _pendingPurchaseAccountingTasks[purchaseId] = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_pendingPurchaseAccountingTasks[purchaseId], future)) {
          _pendingPurchaseAccountingTasks.remove(purchaseId);
        }
      }),
    );
    return future;
  }

Future<bool> _postPurchaseAccounting(Purchase purchase) async {
    try {
      return await _traceAsync<bool>(
        'purchases.createPurchase',
        'accounting_post',
        () => AccountingService.recordPurchase(purchase,
            paymentPostedSeparately: true),
      );
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.error(
          area: 'purchases',
          action: 'record_purchase_accounting',
          message: 'Purchase accounting posting failed.',
          details:
              'purchaseId=${purchase.id} purchaseNo=${purchase.purchaseNo} error=$error',
          stackTrace: stackTrace.toString(),
          userId: _activeUser?.id ?? '',
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
      return false;
    }
  }

Future<void> _waitForPendingPurchaseAccounting(String purchaseId) async {
    final pending = _pendingPurchaseAccountingTasks[purchaseId.trim()];
    if (pending == null) return;
    try {
      await pending;
    } catch (_) {
      // The background poster already logged the failure.
    }
  }

Future<void> waitForPendingAccounting({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (!AccountingService.isAvailable) return;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final pending = <Future<void>>[
        ..._pendingPurchaseAccountingTasks.values,
      ];
      if (pending.isEmpty) return;
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      try {
        await Future.wait<void>(
          pending.map(
            (future) => future.catchError((_) {}),
          ),
        ).timeout(remaining);
      } on TimeoutException {
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }
  }

void _rebuildProductIndexes() {
    _productIndexById.clear();
    _productIdByNormalizedCode.clear();
    _productIdByNormalizedBarcode.clear();
    for (var i = 0; i < _products.length; i += 1) {
      final product = _products[i];
      _productIndexById[product.id] = i;
      if (product.isDeleted) continue;
      final code = product.code.trim().toLowerCase();
      if (code.isNotEmpty) _productIdByNormalizedCode[code] = product.id;
      final barcode = product.barcode.trim().toLowerCase();
      if (barcode.isNotEmpty) {
        _productIdByNormalizedBarcode[barcode] = product.id;
      }
    }
    _cachedProducts = null;
    _cachedProductsGeneration = -1;
  }

void _rebuildCustomerIndexes() {
    _customerIndexById.clear();
    _customerIdByNormalizedName.clear();
    for (var i = 0; i < _customers.length; i += 1) {
      final customer = _customers[i];
      _customerIndexById[customer.id] = i;
      if (customer.isDeleted) continue;
      final normalizedName = customer.name.trim().toLowerCase();
      if (normalizedName.isNotEmpty) {
        _customerIdByNormalizedName[normalizedName] = customer.id;
      }
    }
  }

void _rebuildSupplierIndexes() {
    _supplierIndexById.clear();
    _supplierIdByNormalizedName.clear();
    for (var i = 0; i < _suppliers.length; i += 1) {
      final supplier = _suppliers[i];
      _supplierIndexById[supplier.id] = i;
      if (supplier.isDeleted) continue;
      final normalizedName = supplier.name.trim().toLowerCase();
      if (normalizedName.isNotEmpty) {
        _supplierIdByNormalizedName[normalizedName] = supplier.id;
      }
    }
  }

void _rebuildMutableEntityIndexes() {
    _rebuildProductIndexes();
    _rebuildCustomerIndexes();
    _rebuildSupplierIndexes();
    _rebuildPurchaseIndexes();
    _rebuildExpenseIndexes();
    _rebuildAccountTransactionIndexes();
    _rebuildStockMovementIndexes();
  }

void _rebuildProductInventoryProjectionFromMovements() {
    final totals = <String, double>{};
    for (final movement in _stockMovements) {
      final productId = movement.productId.trim();
      if (productId.isEmpty) continue;
      totals.update(
        productId,
        (value) => value + movement.quantity,
        ifAbsent: () => movement.quantity,
      );
    }
    for (var index = 0; index < _products.length; index += 1) {
      final product = _products[index];
      if (product.isDeleted || !product.trackStock) continue;
      _products[index] = product.copyWith(stock: totals[product.id] ?? 0.0);
    }
  }

void _rebuildStockMovementIndexes() {
    _stockMovementIndexById.clear();
    for (var i = 0; i < _stockMovements.length; i++) {
      final id = _stockMovements[i].id.trim();
      if (id.isEmpty) continue;
      _stockMovementIndexById[id] = i;
    }
  }

}
