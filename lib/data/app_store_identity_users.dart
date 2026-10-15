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
}
