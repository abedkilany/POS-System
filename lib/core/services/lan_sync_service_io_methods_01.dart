part of 'lan_sync_service_io.dart';

extension LanSyncServiceSplitPart1 on LanSyncService {

  void _attachStoreListener() {
    if (_storeListenerAttached) return;
    store.addListener(_onStoreChanged);
    _storeListenerAttached = true;
  }

  void _onStoreChanged() {
    if (!store.runtime.identity.isHost) return;
    final sequence = store.sync.latestStoredAuthoritativeSequence;
    if (sequence <= 0) return;
    final payload = jsonEncode({
      'type': 'sync_changed',
      'changed': true,
      'latestSequence': sequence,
      'serverTime': DateTime.now().toIso8601String(),
    });
    for (final entry
        in List<MapEntry<WebSocket, String>>.from(LanSyncService._realtimeClients.entries)) {
      final socket = entry.key;
      if (socket.readyState != WebSocket.open) {
        LanSyncService._realtimeClients.remove(socket);
        continue;
      }
      try {
        socket.add(payload);
      } catch (_) {
        LanSyncService._realtimeClients.remove(socket);
      }
    }
  }

  bool _isNetworkFailure(Object error) {
    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException) {
      return true;
    }
    final lower = error.toString().toLowerCase();
    return lower.contains('connection refused') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('no route to host') ||
        lower.contains('connection reset by peer') ||
        lower.contains('broken pipe') ||
        lower.contains('econnrefused') ||
        lower.contains('connection closed');
  }

  String _failureMessage(String prefix, Object error) {
    final text = error.toString().trim();
    if (_isNetworkFailure(error)) {
      return '$prefix: Host Offline. $text';
    }
    return '$prefix: $text';
  }

  String _snapshotGenerationKey(String transport) =>
      'applied_host_snapshot_generation_${transport}_${store.runtime.identity.storeId}_${store.runtime.identity.branchId}';

  String _snapshotGenerationInProgressKey(String transport) =>
      'in_progress_host_snapshot_generation_${transport}_${store.runtime.identity.storeId}_${store.runtime.identity.branchId}';

  String _snapshotGenerationFailedKey(String transport) =>
      'failed_host_snapshot_generation_${transport}_${store.runtime.identity.storeId}_${store.runtime.identity.branchId}';

  String _snapshotGenerationInProgressAtKey(String transport) =>
      'in_progress_host_snapshot_generation_at_${transport}_${store.runtime.identity.storeId}_${store.runtime.identity.branchId}';

  String _snapshotGenerationFailedAtKey(String transport) =>
      'failed_host_snapshot_generation_at_${transport}_${store.runtime.identity.storeId}_${store.runtime.identity.branchId}';

  String _restoreCommandExecutedKey(String transport) =>
      'executed_host_restore_command_${transport}_${store.runtime.identity.storeId}_${store.runtime.identity.branchId}';

  String _restoreCommandInProgressKey(String transport) =>
      'in_progress_host_restore_command_${transport}_${store.runtime.identity.storeId}_${store.runtime.identity.branchId}';

  String _snapshotGenerationLockId(String transport, String generation) =>
      '${transport}_${store.runtime.identity.storeId}_${store.runtime.identity.branchId}_$generation';

  String _remoteHostSnapshotGeneration(Map<String, dynamic> decoded) {
    return (decoded['hostSnapshotGeneration'] ??
            decoded['snapshotGeneration'] ??
            decoded['restoreGeneration'] ??
            '')
        .toString()
        .trim();
  }

  String _remoteHostRestoreCommandId(Map<String, dynamic> decoded) {
    return (decoded['hostRestoreCommandId'] ??
            decoded['restoreCommandId'] ??
            decoded['rebuildCommandId'] ??
            decoded['commandId'] ??
            decoded['hostSnapshotGeneration'] ??
            decoded['snapshotGeneration'] ??
            decoded['restoreGeneration'] ??
            '')
        .toString()
        .trim();
  }

  String _restoreCommandIdFromChanges(List<SyncChange> changes) {
    for (final change in changes) {
      if (change.entityType == 'system' &&
          change.operation == 'restore_snapshot_ready') {
        return _remoteHostRestoreCommandId(change.payload);
      }
    }
    return '';
  }

  bool _restoreCommandAlreadyExecuted(String transport, String commandId) {
    if (commandId.trim().isEmpty) return false;
    final executed =
        LocalDatabaseService.getString(_restoreCommandExecutedKey(transport)) ??
            '';
    return executed.trim() == commandId.trim();
  }

  bool _needsHostSnapshotGenerationRebuild(
      String transport, Map<String, dynamic> decoded) {
    if (!UnifiedSyncPolicy.shouldTrackRemoteSnapshotGeneration(
        store.runtime.identity)) {
      return false;
    }
    final remote = _remoteHostSnapshotGeneration(decoded);
    if (remote.isEmpty) return false;
    final commandId = _remoteHostRestoreCommandId(decoded);
    final commandExecuted =
        _restoreCommandAlreadyExecuted(transport, commandId);
    if (commandExecuted) return false;
    final applied =
        LocalDatabaseService.getString(_snapshotGenerationKey(transport)) ?? '';
    if (applied.trim() == remote && commandId.isEmpty) return false;

    final lockId = _snapshotGenerationLockId(transport, remote);
    if (LanSyncService._activeSnapshotGenerationRebuilds.contains(lockId)) return false;

    final inProgress = LocalDatabaseService.getString(
            _snapshotGenerationInProgressKey(transport)) ??
        '';
    final inProgressAtRaw = LocalDatabaseService.getString(
            _snapshotGenerationInProgressAtKey(transport)) ??
        '';
    final inProgressAt = DateTime.tryParse(inProgressAtRaw);
    if (inProgress.trim() == remote &&
        inProgressAt != null &&
        DateTime.now().difference(inProgressAt) < const Duration(minutes: 10)) {
      return false;
    }

    final failed = LocalDatabaseService.getString(
            _snapshotGenerationFailedKey(transport)) ??
        '';
    final failedAtRaw = LocalDatabaseService.getString(
            _snapshotGenerationFailedAtKey(transport)) ??
        '';
    final failedAt = DateTime.tryParse(failedAtRaw);
    if (failed.trim() == remote &&
        failedAt != null &&
        DateTime.now().difference(failedAt) < const Duration(minutes: 2)) {
      return false;
    }
    return true;
  }

  Future<void> _markHostSnapshotGenerationApplied(
      String transport, dynamic source) async {
    String generation = '';
    if (source is Map<String, dynamic>) {
      generation = _remoteHostSnapshotGeneration(source);
    }
    if (generation.isEmpty) return;
    final commandId = source is Map<String, dynamic>
        ? _remoteHostRestoreCommandId(source)
        : '';
    await LocalDatabaseService.setString(
        _snapshotGenerationKey(transport), generation);
    if (commandId.isNotEmpty) {
      await LocalDatabaseService.setString(
          _restoreCommandExecutedKey(transport), commandId);
      await LocalDatabaseService.deleteString(
          _restoreCommandInProgressKey(transport));
    }
    await LocalDatabaseService.deleteString(
        _snapshotGenerationInProgressKey(transport));
    await LocalDatabaseService.deleteString(
        _snapshotGenerationInProgressAtKey(transport));
    await LocalDatabaseService.deleteString(
        _snapshotGenerationFailedKey(transport));
    await LocalDatabaseService.deleteString(
        _snapshotGenerationFailedAtKey(transport));
  }

  Future<bool> _beginHostSnapshotGenerationRebuild(
    String transport,
    String generation, {
    String commandId = '',
  }) async {
    if (generation.isEmpty) return false;
    final applied =
        LocalDatabaseService.getString(_snapshotGenerationKey(transport)) ?? '';
    if (applied.trim() == generation && commandId.trim().isEmpty) {
      return false;
    }
    final lockId = _snapshotGenerationLockId(transport, generation);
    if (!LanSyncService._activeSnapshotGenerationRebuilds.add(lockId)) return false;
    await LocalDatabaseService.setString(
        _snapshotGenerationInProgressKey(transport), generation);
    final effectiveCommandId =
        commandId.trim().isEmpty ? generation : commandId.trim();
    if (effectiveCommandId.isNotEmpty) {
      await LocalDatabaseService.setString(
          _restoreCommandInProgressKey(transport), effectiveCommandId);
    }
    await LocalDatabaseService.setString(
        _snapshotGenerationInProgressAtKey(transport),
        DateTime.now().toIso8601String());
    return true;
  }

  Future<void> _finishHostSnapshotGenerationRebuild(
    String transport,
    String generation, {
    required bool success,
  }) async {
    if (generation.isEmpty) return;
    final lockId = _snapshotGenerationLockId(transport, generation);
    LanSyncService._activeSnapshotGenerationRebuilds.remove(lockId);
    if (success) {
      await LocalDatabaseService.setString(
          _snapshotGenerationKey(transport), generation);
      final inProgressCommand = LocalDatabaseService.getString(
              _restoreCommandInProgressKey(transport)) ??
          '';
      if (inProgressCommand.trim().isNotEmpty) {
        await LocalDatabaseService.setString(
            _restoreCommandExecutedKey(transport), inProgressCommand.trim());
        await LocalDatabaseService.deleteString(
            _restoreCommandInProgressKey(transport));
      }
      await LocalDatabaseService.deleteString(
          _snapshotGenerationInProgressKey(transport));
      await LocalDatabaseService.deleteString(
          _snapshotGenerationInProgressAtKey(transport));
      await LocalDatabaseService.deleteString(
          _snapshotGenerationFailedKey(transport));
      await LocalDatabaseService.deleteString(
          _snapshotGenerationFailedAtKey(transport));
    } else {
      await LocalDatabaseService.deleteString(
          _snapshotGenerationInProgressKey(transport));
      await LocalDatabaseService.deleteString(
          _snapshotGenerationInProgressAtKey(transport));
      await LocalDatabaseService.setString(
          _snapshotGenerationFailedKey(transport), generation);
      await LocalDatabaseService.setString(
          _snapshotGenerationFailedAtKey(transport),
          DateTime.now().toIso8601String());
      await LocalDatabaseService.deleteString(
          _restoreCommandInProgressKey(transport));
    }
  }

  Future<LanSyncResult?> _rebuildIfHostSnapshotGenerationChanged(
    String host,
    int port,
    String token,
    Map<String, dynamic> decodedPull, {
    LanSyncProgressCallback? onProgress,
  }) async {
    if (!_needsHostSnapshotGenerationRebuild('lan', decodedPull)) return null;
    final generation = _remoteHostSnapshotGeneration(decodedPull);
    final commandId = _remoteHostRestoreCommandId(decodedPull);
    if (!await _beginHostSnapshotGenerationRebuild(
      'lan',
      generation,
      commandId: commandId,
    )) {
      return null;
    }
    LanSyncResult result;
    try {
      onProgress?.call(
          0.72, 'Host restore detected. Rebuilding from LAN Host snapshot...');
      final settings = LanSyncSettings.load();
      await settings.copyWith(clearLastPullCursor: true).save();
      await SyncDeviceStateStore.resetClientProgress(store.runtime.identity,
          transport: 'lan');
      result = await repairFromHostSnapshot(
        host,
        port: port,
        token: token,
        onProgress: onProgress,
      );
      await _finishHostSnapshotGenerationRebuild(
        'lan',
        generation,
        success: result.ok,
      );
    } catch (_) {
      await _finishHostSnapshotGenerationRebuild(
        'lan',
        generation,
        success: false,
      );
      rethrow;
    }
    return result;
  }

  bool get isHosting => LanSyncService._sharedServer != null;
  int? get port => LanSyncService._sharedPort;

  Future<void> startHost({int port = 8787}) async {
    await _ensureHostRegistryMigration();
    if (LanSyncService._sharedServer != null && LanSyncService._sharedPort == port) {
      _attachStoreListener();
      LanSyncService._sharedHostService = this;
      return;
    }
    await stopHost();
    LanSyncService._sharedServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    LanSyncService._sharedPort = port;
    LanSyncService._sharedHostService = this;
    _attachStoreListener();
    LanSyncService._sharedServer!.listen(_handleRequest, onError: (_) {});
    await _startDiscoveryResponder();
  }

  Future<void> _startDiscoveryResponder() async {
    _discoverySocket?.close();
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        LanSyncService._discoveryPort,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      _discoverySocket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = socket.receive()) != null) {
          final packet = datagram!;
          try {
            final decoded = jsonDecode(utf8.decode(packet.data));
            if (decoded is! Map ||
                decoded['protocol'] != LanSyncService._discoveryProtocol ||
                decoded['type'] != 'discover') {
              continue;
            }
            final identity = store.runtime.identity;
            final requestedStore = '${decoded['storeId'] ?? ''}'.trim();
            final requestedBranch = '${decoded['branchId'] ?? ''}'.trim();
            if (requestedStore != identity.storeId.trim() ||
                requestedBranch != identity.branchId.trim()) {
              continue;
            }
            final response = jsonEncode({
              'protocol': LanSyncService._discoveryProtocol,
              'type': 'host',
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'hostDeviceId': store.sync.deviceId,
              'port': LanSyncService._sharedPort ?? 8787,
            });
            socket.send(utf8.encode(response), packet.address, packet.port);
          } catch (_) {
            // Discovery packets are unauthenticated hints; HTTP auth remains authoritative.
          }
        }
      }, onError: (_) {});
    } catch (_) {
      _discoverySocket = null;
      // LAN HTTP sync remains usable if the platform blocks UDP discovery.
    }
  }

  Future<void> _ensureHostRegistryMigration() async {
    final settings = LanSyncSettings.load();
    final hostDeviceId = store.sync.deviceId.trim();
    if (!settings.hostRegistryNeedsMigration(hostDeviceId)) return;
    await settings.withMigratedHostRegistry(hostDeviceId).save();
  }

  Future<void> stopHost() async {
    _discoverySocket?.close();
    _discoverySocket = null;
    await _closeRealtimeClient();
    for (final socket in LanSyncService._realtimeClients.keys.toList()) {
      await socket.close(WebSocketStatus.goingAway, 'Host stopped');
    }
    LanSyncService._realtimeClients.clear();
    await LanSyncService._sharedServer?.close(force: true);
    LanSyncService._sharedServer = null;
    LanSyncService._sharedPort = null;
    if (identical(LanSyncService._sharedHostService, this)) {
      if (_storeListenerAttached) {
        store.removeListener(_onStoreChanged);
        _storeListenerAttached = false;
      }
      LanSyncService._sharedHostService = null;
    }
  }

  bool _authorized(HttpRequest request, LanSyncSettings settings) {
    final deviceId = request.headers.value('x-device-id')?.trim() ?? '';
    final deviceToken = request.headers.value('x-device-token')?.trim() ?? '';
    if (deviceId.isEmpty || deviceToken.isEmpty) return false;
    if (SyncDeviceAccessStore.isSuspended(deviceId) ||
        SyncDeviceAccessStore.isDeleted(deviceId) ||
        SyncDeviceAccessStore.isWipePending(deviceId)) {
      return false;
    }
    final expected = settings.pairedDevices[deviceId]?.trim() ?? '';
    return expected.isNotEmpty && expected == deviceToken;
  }

  bool _deviceCanReceiveWipe(HttpRequest request) {
    final deviceId = request.headers.value('x-device-id')?.trim() ?? '';
    final deviceToken = request.headers.value('x-device-token')?.trim() ?? '';
    return (SyncDeviceAccessStore.isWipePending(deviceId) &&
            SyncDeviceAccessStore.wipePendingTokenMatches(
                deviceId, deviceToken)) ||
        (SyncDeviceAccessStore.isDeleted(deviceId) &&
            SyncDeviceAccessStore.deletedTokenMatches(deviceId, deviceToken));
  }

  Future<bool> _handleBlockedDevice(
      HttpRequest request, LanSyncSettings settings) async {
    final deviceId = request.headers.value('x-device-id')?.trim() ?? '';
    if (deviceId.isEmpty) return false;
    if ((SyncDeviceAccessStore.isWipePending(deviceId) ||
            SyncDeviceAccessStore.isDeleted(deviceId)) &&
        _deviceCanReceiveWipe(request)) {
      await _json(
          request,
          {
            'ok': false,
            'action': 'wipe_local_data',
            'wipeRequired': true,
            'error':
                'This device was deleted by the Host. Local data must be wiped.',
          },
          status: HttpStatus.gone);
      return true;
    }
    if (SyncDeviceAccessStore.isSuspended(deviceId)) {
      await _json(
          request,
          {
            'ok': false,
            'action': 'suspended',
            'suspended': true,
            'error':
                'This device is suspended by the Host. Resume it from Sync Monitoring to continue.',
          },
          status: HttpStatus.forbidden);
      return true;
    }
    return false;
  }

  String _maskedToken(String? token) {
    final value = (token ?? '').trim();
    if (value.isEmpty) return '<empty>';
    if (value.length <= 4) return '****';
    return '${value.substring(0, 2)}****${value.substring(value.length - 2)}';
  }

  Future<void> _json(HttpRequest request, Object payload,
      {int status = HttpStatus.ok}) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(payload));
    await request.response.close();
  }

  Future<Map<String, dynamic>> _currentLanSnapshotEnvelope(
      {bool force = false}) async {
    final now = DateTime.now();
    final cached = _snapshotTransferCache;
    final age = _snapshotTransferCacheAt == null
        ? const Duration(days: 1)
        : now.difference(_snapshotTransferCacheAt!);
    if (!force && cached != null && age < const Duration(minutes: 5)) {
      return cached;
    }

    // Snapshot export reads the in-memory business collections. The Host can
    // start with these collections unloaded while SQLite already contains the
    // real data, which would produce an apparently successful but empty
    // Client bootstrap. Always hydrate the data before building a fresh
    // snapshot (pairing uses force=true).
    await store.runtime.ensureHeavyDataLoaded();
    final envelope = await store.recovery.exportUnifiedSnapshotEnvelope(
      kind: 'full_store',
      maxItemsPerChunk: 300,
    );
    _snapshotTransferCache = envelope;
    _snapshotTransferCacheAt = now;
    return envelope;
  }

  Future<Map<String, dynamic>> _snapshotManifestResponse(
      {bool force = false}) async {
    final envelope = await _currentLanSnapshotEnvelope(force: force);
    return <String, dynamic>{
      'ok': true,
      'snapshotFormat': envelope['snapshotFormat'],
      'snapshotVersion': envelope['snapshotVersion'],
      'snapshotKind': envelope['snapshotKind'],
      'snapshotManifest': envelope['snapshotManifest'],
      'totalChunks': envelope['totalChunks'],
      'syncGeneratedAt': envelope['syncGeneratedAt'],
      'syncGeneratedSequence': envelope['syncGeneratedSequence'],
      'hostSnapshotGeneration': envelope['hostSnapshotGeneration'],
      'snapshotGeneration': envelope['snapshotGeneration'],
      'hostRestoreCommandId': envelope['hostRestoreCommandId'],
      'restoreCommandId': envelope['restoreCommandId'],
    };
  }

  Map<String, dynamic> _lanSignalPayload({
    DateTime? since,
    int sinceSequence = 0,
  }) {
    final decoded = jsonDecode(store.sync.exportChangesJson(
        since: since, sinceSequence: sinceSequence)) as Map<String, dynamic>;
    final changes = decoded['changes'] as List<dynamic>? ?? const <dynamic>[];
    return {
      'ok': true,
      'changed': changes.isNotEmpty,
      'changeCount': changes.length,
      'latestSequence':
          int.tryParse(decoded['generatedSequence']?.toString() ?? '') ?? 0,
      'generatedAt': decoded['generatedAt']?.toString() ??
          DateTime.now().toIso8601String(),
      'serverTime': DateTime.now().toIso8601String(),
    };
  }

  bool _clientDeviceLimitReached(LanSyncSettings settings,
      {String excludeDeviceId = ''}) {
    final allowed = AccountAuthCache.load()?.devicesLimit;
    if (allowed == null) return false;
    final normalizedAllowed = allowed < 0 ? 0 : allowed;
    final hostDeviceId = store.sync.deviceId.trim();
    final excluded = excludeDeviceId.trim();
    final linked = settings.hostRegistry.values.where((device) {
      final id = device.clientDeviceId.trim();
      if (id.isEmpty || id == hostDeviceId || id == excluded) return false;
      return device.isActive;
    }).length;
    return linked >= normalizedAllowed;
  }

  Future<void> _refreshCachedDeviceLimit() async {
    final cache = AccountAuthCache.load();
    final token = cache?.accountToken.trim() ?? '';
    if (token.isEmpty) return;
    try {
      final result = await AccountAuthService()
          .refreshSession(accountToken: token)
          .timeout(const Duration(seconds: 5));
      if (!result.ok || result.devicesLimit == null) return;
      await AccountAuthService.cacheOnlineResult(
        result,
        mode: cache?.mode.isEmpty == true ? 'login' : (cache?.mode ?? 'login'),
      );
    } catch (_) {
      // LAN pairing must remain usable offline; keep the last known entitlement.
    }
  }
}
