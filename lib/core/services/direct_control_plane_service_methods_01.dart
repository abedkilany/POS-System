part of 'direct_control_plane_service.dart';

extension DirectControlPlaneServiceSplitPart1 on DirectControlPlaneService {

  http.Client get client => _client;
  UnifiedSyncCoreService get syncCore => _syncCore;

  Future<bool> _clientDirectHostWorkNeedsDrain() async {
    if (!store.runtime.identity.isClient) return false;

    // A relay ACK means that the Host accepted the draft, not that the Client
    // has applied the Host's authoritative event yet. Submitted rows must not
    // block the pull immediately following the push; otherwise the unified
    // push -> pull cycle deadlocks forever. The next push recovers submitted
    // rows if the authoritative pull was interrupted.
    final outstanding = store.sync.queue.where((item) =>
        item.target == UnifiedSyncQueueTarget.host &&
        item.status != 'synced' &&
        item.status != 'rejected');
    // Pending/in-progress/failed work must pause a rebuild or pull. A
    // submitted row is the result of the push immediately before the pull
    // and must not block that pull.
    return outstanding.any((item) => item.status != 'submitted');
  }

  Future<DirectSyncResult?> _directClientNeedsDrainResult() async {
    if (!await _clientDirectHostWorkNeedsDrain()) return null;
    return const DirectSyncResult(
      ok: true,
      message: DirectControlPlaneService._clientDirectDrainMessage,
      syncDeferred: true,
    );
  }

  Future<DirectSyncResult> _runDirectHostRelaySync(
    VpsControlPlaneSettings settings, {
    DirectSyncProgressCallback? onProgress,
    bool compactHistory = false,
  }) async {
    onProgress?.call(0.10, 'Preparing Host relay connection...');
    final relayReady = await ensureHostRelayReady(settings);
    if (!relayReady.ok) return relayReady;
    onProgress?.call(0.25, 'Sending Host heartbeat...');
    await sendHostHeartbeat(settings);
    onProgress?.call(0.40, 'Registering Host device...');
    await registerCurrentDevice(settings, transport: 'direct');
    final hostPendingCount =
        _syncCore.pendingChangesForTarget(UnifiedSyncQueueTarget.host).length;
    onProgress?.call(0.55, 'Publishing Host changes through Direct relay...');
    final relayPublished = await _broadcastHostAuthorityViaRelay(settings);
    if (!relayPublished) {
      return const DirectSyncResult(
        ok: false,
        message:
            'Host direct relay failed. Legacy Direct fallback is disabled; retry when the relay is available.',
      );
    }
    if (compactHistory) {
      onProgress?.call(0.90, 'Running safe local sync history maintenance...');
      await store.sync.compactSyncedHistoryForMaintenance();
      onProgress?.call(1.0, 'Host Direct sync completed.');
    }
    return DirectSyncResult(
      ok: true,
      pushed: hostPendingCount,
      message: compactHistory
          ? 'Host Direct sync completed through relay. Broadcast $hostPendingCount authoritative change(s).'
          : 'Host direct relay completed. Broadcast $hostPendingCount authoritative change(s).',
    );
  }

  Future<DirectSyncResult> _runDirectClientRelayPush(
    VpsControlPlaneSettings settings, {
    DirectSyncProgressCallback? onProgress,
  }) async {
    onProgress?.call(0.12, 'Registering Client device...');
    await registerCurrentDevice(settings, transport: 'direct');
    onProgress?.call(0.28, 'Sending Client requests to Host relay...');
    final pushed = await _pushPendingViaRelay(settings,
        target: UnifiedSyncQueueTarget.host);
    return DirectSyncResult(
      ok: true,
      pushed: pushed,
      message:
          'Client direct push completed. Sent $pushed request(s) to Host relay and received Host ACK.',
    );
  }

  Future<DirectSyncResult> _runDirectClientAuthoritativeSync(
    VpsControlPlaneSettings settings, {
    DateTime? minSnapshotUpdatedAt,
    DirectSyncProgressCallback? onProgress,
  }) async {
    final baseLastAppliedSequence =
        SyncDeviceStateStore.lastAppliedSequenceForTransport(
            store.runtime.identity, 'direct');
    if (baseLastAppliedSequence <= 0) {
      onProgress?.call(0.32,
          'Rebuilding this device data from the Direct relay snapshot...');
      return rebuildFromDirectHostSnapshot(
        settings.copyWith(clearLastPullCursor: true),
        onProgress: onProgress,
        requestFreshSnapshot: false,
      );
    }

    final relayResult = await _pullAuthoritativeChangesViaRelay(
      settings,
      minSnapshotUpdatedAt: minSnapshotUpdatedAt,
      onProgress: onProgress,
    );
    if (relayResult != null) return relayResult;
    return const DirectSyncResult(
      ok: false,
      message:
          'Direct relay pull failed. Please retry when the relay is available.',
    );
  }

  Future<DirectSyncResult> _drainClientPendingChangesBeforeRebuild(
    VpsControlPlaneSettings settings, {
    DirectSyncProgressCallback? onProgress,
  }) async {
    if (!store.runtime.identity.isClient) {
      return const DirectSyncResult(
          ok: true, message: 'No Client drain needed.');
    }
    if (await _clientDirectHostWorkNeedsDrain()) {
      return const DirectSyncResult(
        ok: false,
        message: DirectControlPlaneService._clientDirectRebuildBlockedMessage,
        syncDeferred: true,
      );
    }
    onProgress?.call(0.06, 'Sending pending Client changes before rebuild...');
    await registerCurrentDevice(settings, transport: 'direct');
    var pushed = 0;
    try {
      pushed += await _pushPendingViaRelay(settings,
          target: UnifiedSyncQueueTarget.host);
    } catch (error) {
      return DirectSyncResult(
        ok: false,
        pushed: pushed,
        message:
            'Direct rebuild is waiting: pending Client changes could not be sent to the Host. $error',
        syncDeferred: true,
      );
    }

    for (var attempt = 0; attempt < 10; attempt += 1) {
      if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 2));
      onProgress?.call(
        (0.08 + attempt * 0.015).clamp(0.08, 0.22).toDouble(),
        'Waiting for Host to confirm pending Client changes (${attempt + 1}/10)...',
      );
      if (!await _clientDirectHostWorkNeedsDrain()) {
        return DirectSyncResult(
          ok: true,
          pushed: pushed,
          message: 'Pending Client changes were confirmed by the Host.',
        );
      }
    }

    return DirectSyncResult(
      ok: true,
      pushed: pushed,
      message: DirectControlPlaneService._clientDirectRebuildBlockedMessage,
      syncDeferred: true,
    );
  }

  bool _directSnapshotEnvelopeMatchesFreshRebuild(
    Map<String, dynamic> envelope, {
    required int minimumSequence,
    required String rebuildRequestId,
    required DateTime requestedAt,
  }) {
    final raw = jsonEncode(envelope);
    final generatedSequence = store.sync.snapshotGeneratedSequenceFromJson(raw);
    final generatedAt = store.sync.snapshotGeneratedAtFromJson(raw);
    final envelopeRequestId =
        (envelope['rebuildRequestId'] ?? envelope['snapshotRequestId'] ?? '')
            .toString()
            .trim();
    if (rebuildRequestId.trim().isEmpty ||
        envelopeRequestId != rebuildRequestId.trim()) {
      return false;
    }
    if (minimumSequence > 0 && generatedSequence < minimumSequence) {
      return false;
    }
    // A manual/safe rebuild must never apply a cached snapshot that existed
    // before the rebuild request. Use a small tolerance for device clock and
    // serialization precision differences, but require the Host to generate the
    // envelope during this rebuild session.
    final lowerBound = requestedAt.toUtc().subtract(const Duration(seconds: 2));
    if (generatedAt.toUtc().isBefore(lowerBound)) {
      return false;
    }
    return true;
  }

  Future<void> _restorePreviousSyncMode(AppIdentity previousIdentity) async {
    final current = store.runtime.identity;
    if (current.syncMode == previousIdentity.syncMode) return;
    try {
      await store.runtime.recoverExistingStoreIdentity(
        storeId: current.storeId,
        branchId: current.branchId,
        recoveryKey: current.recoveryKey,
        hostDeviceId: current.hostDeviceId,
        deviceToken: current.deviceToken,
        controlPlaneTenantId: current.controlPlaneTenantId,
        deviceRole: current.deviceRole,
        syncMode: previousIdentity.syncMode,
      );
    } catch (error) {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] directRecovery:restoreSyncStateFailed error=$error',
      );
    }
  }

  Future<bool?> checkDirectSyncPlanAccess(
      VpsControlPlaneSettings settings) async {
    // Read the subscription entitlement from the server using the Host's
    // authenticated device/account session. Local cache is not authoritative.
    // This read only needs the API origin and store identity. Requiring Direct
    // to already be configured creates a circular lock for a Host that is
    // trying to learn whether it may enable Direct for the first time.
    if (settings.apiBaseUrl.trim().isEmpty ||
        store.runtime.identity.storeId.trim().isEmpty) {
      return null;
    }
    // Do not call listDevicesWithLimit here. The normal Direct control-plane
    // service intentionally uses a retired HTTP client; entitlement lookup is
    // still needed by the Sync settings page while the Host is on LAN.
    final client = http.Client();
    try {
      final identity = store.runtime.identity;
      final response = await client
          .get(
            settings.endpoint('/api/sync/entitlement', {
              'store_id': identity.storeId,
              'branch_id':
                  identity.branchId.isEmpty ? 'main' : identity.branchId,
            }),
            headers: _headers(settings),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] directPlanAccess:entitlementHttp '
          'status=${response.statusCode} store=${identity.storeId} '
          'branch=${identity.branchId}',
        );
        return null;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final allowed = decoded['directSyncEnabled'] == true
          ? true
          : decoded.containsKey('directSyncEnabled')
              ? false
              : null;
      return allowed;
    } catch (error) {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] directPlanAccess:entitlementHttpFailed error=$error',
      );
      return null;
    } finally {
      client.close();
    }
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

  String _snapshotRequestKey(String transport, String generation) =>
      'requested_host_snapshot_generation_${transport}_${store.runtime.identity.storeId}_${store.runtime.identity.branchId}_${generation.trim()}';

  String _snapshotRequestAtKey(String transport, String generation) =>
      'requested_host_snapshot_generation_at_${transport}_${store.runtime.identity.storeId}_${store.runtime.identity.branchId}_${generation.trim()}';

  String _restoreCommandExecutedKey(String transport) =>
      'executed_host_restore_command_${transport}_${store.runtime.identity.storeId}_${store.runtime.identity.branchId}';

  String _restoreCommandInProgressKey(String transport) =>
      'in_progress_host_restore_command_${transport}_${store.runtime.identity.storeId}_${store.runtime.identity.branchId}';

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

  bool _restoreCommandAlreadyExecuted(String transport, String commandId) {
    if (commandId.trim().isEmpty) return false;
    final executed =
        LocalDatabaseService.getString(_restoreCommandExecutedKey(transport)) ??
            '';
    return executed.trim() == commandId.trim();
  }

  Future<void> _markHostSnapshotGenerationApplied(
      String transport, dynamic source,
      {bool markRestoreCommandExecuted = true}) async {
    String generation = '';
    if (source is Map<String, dynamic>) {
      generation = _remoteHostSnapshotGeneration(source);
    }
    if (generation.isEmpty) return;
    await LocalDatabaseService.setString(
        _snapshotGenerationKey(transport), generation);
    if (markRestoreCommandExecuted && source is Map<String, dynamic>) {
      final commandId = _remoteHostRestoreCommandId(source);
      if (commandId.isNotEmpty) {
        await LocalDatabaseService.setString(
            _restoreCommandExecutedKey(transport), commandId);
        await LocalDatabaseService.deleteString(
            _restoreCommandInProgressKey(transport));
      }
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

  bool _directAllowedForIdentity(AppIdentity identity) {
    return UnifiedSyncPolicy.isDirectAllowedForCurrentRole(identity);
  }

  Future<void> _recordDeviceSyncState(
    String transport,
    DateTime? cursor, {
    int sequence = 0,
    VpsControlPlaneSettings? settings,
  }) async {
    final effectiveSequence =
        sequence > 0 ? sequence : store.sync.latestStoredAuthoritativeSequence;
    if (cursor != null) {
      await _syncCore.saveCursorAndRecordTransportState(
        store,
        transport: transport,
        cursor: cursor,
        sequence: effectiveSequence,
        saveTransportState: () async {
          if (settings != null) {
            await settings.copyWith(lastPullCursor: cursor).save();
          }
        },
      );
    }

    // Authoritative ACK: update the Host-visible device state only after the
    // Client has successfully applied the pulled data locally. Pull itself must
    // never be treated as ACK.
    if (settings != null && store.runtime.identity.isClient && cursor != null) {
      await registerCurrentDevice(settings, transport: transport);
    }
  }

  Future<void> recordDeviceSyncState(
    String transport, {
    DateTime? cursor,
    int? sequence,
  }) {
    return _syncCore.recordTransportSyncState(
      store,
      transport: transport,
      cursor: cursor,
      sequence: sequence,
    );
  }

  Future<void> compactAfterSuccessfulSync() {
    return _syncCore.compactAfterSuccessfulSync();
  }

  Future<DirectPairingCodeResult> createPairingCode(
      VpsControlPlaneSettings settings,
      {String transport = 'direct',
      int ttlMinutes = 5}) async {
    final identity = store.runtime.identity;
    final canCreate = transport == 'direct'
        ? identity.isHost && settings.apiBaseUrl.trim().isNotEmpty
        : UnifiedSyncPolicy.canCreateDirectPairingCode(
            identity,
            settingsEnabled: settings.enabled,
            hasApiBaseUrl: settings.apiBaseUrl.trim().isNotEmpty,
          );
    if (!canCreate) {
      return const DirectPairingCodeResult(
          ok: false, message: 'Pairing service is not ready yet.');
    }
    try {
      // Generate the one-time code on the Host, like LAN. The Direct API only
      // brokers the short-lived pairing claim; it must not invent or own the
      // Host's pairing secret.
      final localPairingCode = VpsControlPlaneSettings.generatePairingCode();
      final directIdentity = transport == 'direct'
          ? await DirectDeviceIdentity.loadOrCreate()
          : null;
      // Local Host devices are allowed to request a Direct pairing code without
      // an online account session. The platform permission is enforced by the
      // server from app_stores.direct_sync_enabled, so the local app must not
      // block this action only because account_auth_cache_v1 is empty.
      final response = await _client
          .post(
            settings.endpoint('/api/sync/pairing/create'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'hostDeviceId': store.sync.deviceId,
              'hostDeviceName': identity.deviceName,
              'transport': transport,
              'code': localPairingCode,
              'ttlMinutes': ttlMinutes,
              'recoveryKey': identity.recoveryKey,
              'devicePublicKey': directIdentity?.publicKeyEncoded ?? '',
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        var serverMessage = '';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            serverMessage =
                (decoded['error'] ?? decoded['message'] ?? '').toString();
          }
        } catch (_) {
          serverMessage = response.body;
        }
        serverMessage = serverMessage.trim().isEmpty
            ? '${response.statusCode} ${response.body}'
            : serverMessage.trim();
        return DirectPairingCodeResult(
            ok: false, message: 'Pairing code failed: $serverMessage');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return DirectPairingCodeResult(
            ok: false,
            message:
                'Pairing code failed: ${response.statusCode} ${response.body}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final ok = decoded['ok'] == true;
      if (ok && transport == 'direct') {
        // Never block the Host QR/code on a large snapshot upload. Publish the
        // tiny login bootstrap first in the background, then continue with the
        // full staged snapshot so new Clients can leave Connect to Store quickly
        // and finish provisioning after Login.
        unawaited(_publishPairingBootstrapInBackground(settings));
      }
      return DirectPairingCodeResult(
        ok: ok,
        message: ok
            ? 'Pairing code created.'
            : (decoded['error']?.toString() ?? 'Pairing code failed.'),
        code: decoded['code']?.toString() ?? '',
        expiresAt: DateTime.tryParse(decoded['expiresAt']?.toString() ?? ''),
        storeId: decoded['storeId']?.toString() ?? identity.storeId,
        branchId: decoded['branchId']?.toString() ?? identity.branchId,
        hostDeviceId: decoded['hostDeviceId']?.toString() ?? identity.deviceId,
        transport: decoded['transport']?.toString() ?? transport,
      );
    } catch (error) {
      return DirectPairingCodeResult(
          ok: false, message: 'Pairing code failed: $error');
    }
  }

  Future<void> _publishPairingBootstrapInBackground(
      VpsControlPlaneSettings settings) async {
    try {
      // Pairing only announces the Host. The Client obtains its initial
      // snapshot from the Host through the realtime relay after pairing.
      await sendHostHeartbeat(settings);
      await registerCurrentDevice(settings, transport: 'direct');
      await _broadcastHostAuthorityViaRelay(settings);
    } catch (error) {
      debugPrint(
          'Background Direct pairing provisioning publish failed: $error');
    }
  }

  Future<DirectPairingStatusResult> pairingCodeStatus(
      VpsControlPlaneSettings settings, String code) async {
    final identity = store.runtime.identity;
    if (!UnifiedSyncPolicy.canCheckDirectPairingStatus(identity)) {
      return const DirectPairingStatusResult(
          ok: false,
          status: 'invalid',
          message: 'Only the Host can check pairing code status.');
    }
    if (settings.apiBaseUrl.trim().isEmpty) {
      return const DirectPairingStatusResult(
          ok: false,
          status: 'invalid',
          message: 'Direct Sync is not ready yet.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/pairing/status'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'code': code.trim(),
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        var serverMessage = '';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            serverMessage =
                (decoded['error'] ?? decoded['message'] ?? '').toString();
          }
        } catch (_) {
          serverMessage = response.body;
        }
        serverMessage = serverMessage.trim().isEmpty
            ? '${response.statusCode} ${response.body}'
            : serverMessage.trim();
        return DirectPairingStatusResult(
            ok: false,
            status: 'invalid',
            message: 'Pairing code failed: $serverMessage');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return DirectPairingStatusResult(
            ok: false,
            status: 'invalid',
            message:
                'Pairing code failed: ${response.statusCode} ${response.body}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final status = decoded['status']?.toString() ?? 'invalid';
      return DirectPairingStatusResult(
        ok: decoded['ok'] == true,
        status: status,
        message: decoded['ok'] == true
            ? status
            : (decoded['error']?.toString() ?? 'Pairing code failed.'),
        expiresAt: DateTime.tryParse(decoded['expiresAt']?.toString() ?? ''),
        claimedAt: DateTime.tryParse(decoded['claimedAt']?.toString() ?? ''),
        claimedByDeviceId: decoded['claimedByDeviceId']?.toString() ?? '',
        claimedByDeviceName: decoded['claimedByDeviceName']?.toString() ?? '',
        claimedDeviceToken: decoded['claimedDeviceToken']?.toString() ?? '',
      );
    } catch (error) {
      return DirectPairingStatusResult(
          ok: false, status: 'invalid', message: 'Pairing code failed: $error');
    }
  }
}
