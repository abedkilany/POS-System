part of 'direct_control_plane_service.dart';

extension DirectControlPlaneServiceSplitPart3 on DirectControlPlaneService {

  Future<DirectSyncResult> rebuildFromDirectHostSnapshot(
      VpsControlPlaneSettings settings,
      {DirectSyncProgressCallback? onProgress,
      void Function(String message)? onDiagnostic,
      bool requestFreshSnapshot = true,
      String expectedSnapshotGeneration = '',
      String expectedRestoreCommandId = ''}) async {
    final identity = store.appIdentity;
    if (identity.isHost) {
      return const DirectSyncResult(
          ok: false,
          message: 'Host rebuild is only available for Client devices.');
    }
    if (!UnifiedSyncPolicy.canRebuildFromDirectSnapshot(
      identity,
      isConfigured: settings.isConfigured,
    )) {
      return const DirectSyncResult(
          ok: false,
          message: 'Direct API URL and paired device token are required.');
    }

    // Unified safe rebuild contract:
    // 1) send every local Client change to the Host,
    // 2) wait until the Host confirms those changes,
    // 3) request a fresh Host snapshot,
    // 4) apply only a snapshot generated after the request.
    // The local database/ACK are not reset until _applyDirectSnapshotEnvelope().
    final minimumSnapshotSequence = [
      SyncDeviceStateStore.lastAppliedSequenceForTransport(identity, 'direct'),
      SyncDeviceStateStore.lastAckSequenceForTransport(identity, 'direct'),
    ].reduce((a, b) => a > b ? a : b);
    final rebuildRequestId = _newDirectRebuildRequestId();
    final drain = await _drainClientPendingChangesBeforeRebuild(
      settings,
      onProgress: onProgress,
    );
    if (!drain.ok || drain.syncDeferred) return drain;

    DirectSyncResult? freshSnapshotRequest;
    final snapshotRequestedAt = DateTime.now().toUtc();
    if (requestFreshSnapshot) {
      onProgress?.call(0.24,
          'Requesting a fresh Host snapshot after Client changes were confirmed...');
      freshSnapshotRequest = await requestFreshHostSnapshot(
        settings,
        requestedAt: snapshotRequestedAt,
        snapshotGeneration: expectedSnapshotGeneration,
      );
      if (!freshSnapshotRequest.ok) {
        return DirectSyncResult(
          ok: false,
          pushed: drain.pushed,
          message: freshSnapshotRequest.message,
          syncDeferred: freshSnapshotRequest.syncDeferred,
        );
      }
    } else {
      // Even automatic generation/restore rebuilds use the same safe path: do
      // not trust an older cached snapshot after draining local Client changes.
      onProgress?.call(0.24,
          'Waiting for the fresh Host snapshot that matches the rebuild request...');
    }

    final freshEnvelope = await _waitForFreshDirectRebuildSnapshot(
      settings,
      rebuildRequestId: rebuildRequestId,
      minimumSnapshotSequence: minimumSnapshotSequence,
      requestedAt: snapshotRequestedAt,
      onProgress: onProgress,
      onDiagnostic: onDiagnostic,
    );
    if (freshEnvelope == null) {
      return DirectSyncResult(
        ok: false,
        pushed: drain.pushed,
        message:
            'Direct rebuild sent pending Client changes and requested a fresh Host snapshot, but no matching fresh snapshot was available yet. Keep the Host online and retry. ${freshSnapshotRequest?.message ?? ''}',
        syncDeferred: true,
      );
    }

    final applied = await _applyDirectSnapshotEnvelope(
      freshEnvelope,
      settings: settings,
      onProgress: onProgress,
      onDiagnostic: onDiagnostic,
      expectedSnapshotGeneration: expectedSnapshotGeneration,
      expectedRestoreCommandId: expectedRestoreCommandId,
    );
    return DirectSyncResult(
      ok: applied.ok,
      pushed: drain.pushed + applied.pushed,
      pulled: applied.pulled,
      restoredSnapshot: applied.restoredSnapshot,
      syncDeferred: applied.syncDeferred,
      message: applied.message,
    );
  }

  Future<Map<String, dynamic>?> _waitForFreshDirectRebuildSnapshot(
    VpsControlPlaneSettings settings, {
    required String rebuildRequestId,
    required int minimumSnapshotSequence,
    required DateTime requestedAt,
    DirectSyncProgressCallback? onProgress,
    void Function(String message)? onDiagnostic,
  }) async {
    onProgress?.call(
        0.30, 'Waiting for fresh Host snapshot through the relay...');
    for (var attempt = 0; attempt < 8; attempt += 1) {
      if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final envelope = await _downloadDirectSnapshotEnvelopeViaRelay(
          settings.copyWith(clearLastPullCursor: true),
          force: true,
          rebuildRequestId: rebuildRequestId,
          requiredMinSequence: minimumSnapshotSequence,
          onProgress: (value, label) {
            final scaled = (0.32 + value * 0.48).clamp(0.0, 0.82).toDouble();
            onProgress?.call(scaled, label);
          },
        );
        if (_directSnapshotEnvelopeMatchesFreshRebuild(
          envelope,
          minimumSequence: minimumSnapshotSequence,
          rebuildRequestId: rebuildRequestId,
          requestedAt: requestedAt,
        )) {
          return envelope;
        }
        onProgress?.call(
          (0.34 + attempt * 0.05).clamp(0.34, 0.74).toDouble(),
          'Ignoring older Host snapshot and waiting for the fresh rebuild snapshot (${attempt + 1}/8)...',
        );
      } catch (error, stackTrace) {
        onDiagnostic?.call(
            '[DIRECT_REBUILD] snapshot relay attempt=${attempt + 1} failed error=$error stack=${stackTrace.toString().split('\n').take(2).join(' | ')}');
        onProgress?.call(
          (0.34 + attempt * 0.05).clamp(0.34, 0.74).toDouble(),
          'Waiting for fresh Direct snapshot relay (${attempt + 1}/8)...',
        );
      }
    }
    return null;
  }

  Future<DirectSyncResult?> checkCurrentDeviceAccess(
      VpsControlPlaneSettings settings) async {
    final identity = store.appIdentity;
    if (!identity.isClient || !settings.isConfigured) return null;
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/device-access'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'deviceId': store.deviceId,
              'deviceToken': identity.deviceToken,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return DirectSyncResult(
            ok: false,
            message:
                'Device Direct access check failed: ${response.statusCode} ${response.body}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['wipeRequired'] == true ||
          decoded['action'] == 'wipe_local_data') {
        final wipedDeviceId = store.deviceId;
        final wipedStoreId = identity.storeId;
        final wipedBranchId = identity.branchId;
        final wipedToken = identity.deviceToken;
        await _confirmDirectWipe(
          settings,
          storeId: wipedStoreId,
          branchId: wipedBranchId,
          deviceId: wipedDeviceId,
          deviceToken: wipedToken,
        );
        await store.factoryResetLocalDevice(enforcePermission: false);
        return const DirectSyncResult(
            ok: false,
            message: 'Device revoked by Host. Local data was wiped.');
      }
      if (decoded['suspended'] == true || decoded['authorized'] == false) {
        final reason = decoded['reason']?.toString() ??
            'This device is suspended or not authorized for Direct sync.';
        if (decoded['suspended'] == true) {
          await store.markSuspendedByHost(reason: reason);
        }
        return DirectSyncResult(ok: false, message: reason);
      }
      await store.clearSuspendedByHost();
      return null;
    } catch (error) {
      return DirectSyncResult(
          ok: false, message: 'Device Direct access check failed: $error');
    }
  }

  Future<DirectSyncResult> setDeviceSuspended(
      VpsControlPlaneSettings settings, String deviceId,
      {required bool suspended}) async {
    final identity = store.appIdentity;
    if (!UnifiedSyncPolicy.canSuspendDirectDevices(identity)) {
      return const DirectSyncResult(
          ok: false, message: 'Only the Host can suspend devices.');
    }
    if (!settings.isConfigured) {
      return const DirectSyncResult(
          ok: false, message: 'Direct API URL and token are required.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/device-suspend'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'deviceId': deviceId,
              'suspended': suspended
            }),
          )
          .timeout(const Duration(seconds: 10));
      return DirectSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? (suspended
                ? 'Device suspended in Direct.'
                : 'Device resumed in Direct.')
            : 'Device suspend/resume failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return DirectSyncResult(
          ok: false, message: 'Device suspend/resume failed: $error');
    }
  }

  Future<DirectSyncResult> revokeDevice(
      VpsControlPlaneSettings settings, String deviceId) async {
    final identity = store.appIdentity;
    if (!UnifiedSyncPolicy.canRevokeDirectDevices(identity)) {
      return const DirectSyncResult(
          ok: false, message: 'Only the Host can revoke devices.');
    }
    if (!settings.isConfigured) {
      return const DirectSyncResult(
          ok: false, message: 'Direct API URL and token are required.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/device-revoke'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'deviceId': deviceId
            }),
          )
          .timeout(const Duration(seconds: 10));
      return DirectSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? 'Device revoked.'
            : 'Device revoke failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return DirectSyncResult(
          ok: false, message: 'Device revoke failed: $error');
    }
  }

  Future<DirectSyncResult> deleteDeviceRecord(
      VpsControlPlaneSettings settings, String deviceId) async {
    final identity = store.appIdentity;
    if (!UnifiedSyncPolicy.canRemoveDirectDevices(identity)) {
      return const DirectSyncResult(
          ok: false, message: 'Only the Host can remove devices.');
    }
    if (!settings.isConfigured) {
      return const DirectSyncResult(
          ok: false, message: 'Direct API URL and token are required.');
    }
    try {
      final response = await _client
          .delete(
            settings.endpoint('/api/sync/devices'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'deviceId': deviceId,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return DirectSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? 'Device record removed.'
            : 'Device remove failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return DirectSyncResult(
          ok: false, message: 'Device remove failed: $error');
    }
  }

  Map<String, String> _headers(VpsControlPlaneSettings settings,
      {bool includeAccountTokenForClient = false}) {
    final identity = store.appIdentity;
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      // Clients authenticate with their own per-device token. Host/account
      // flows authenticate with the online account session.
      if ((includeAccountTokenForClient || !identity.isClient) &&
          settings.accountToken.trim().isNotEmpty)
        'Authorization': 'Bearer ${settings.accountToken.trim()}',
      'X-Device-Id': store.deviceId,
      'X-Device-Token': identity.deviceToken,
      'X-Device-Role': identity.deviceRole.name,
      'X-Sync-Transport': identity.transportType,
      'X-Store-Id': identity.storeId,
      'X-Branch-Id': identity.branchId,
    };
  }

  Map<String, String> headers(VpsControlPlaneSettings settings) =>
      _headers(settings);

  String _newRelayRequestId() {
    DirectControlPlaneService._relayRequestCounter += 1;
    return '${store.deviceId}-${DateTime.now().microsecondsSinceEpoch}-${DirectControlPlaneService._relayRequestCounter.toRadixString(36)}';
  }

  Future<_RealtimeChannelSession> _openRealtimeChannel(
    VpsControlPlaneSettings settings, {
    bool includeSequenceHint = true,
  }) async {
    final identity = store.appIdentity;
    final state = SyncDeviceStateStore.load(identity);
    final ticketQuery = <String, String>{
      'store_id': identity.storeId,
      'branch_id': identity.branchId,
      'role': identity.isHost ? 'host' : 'client',
    };
    final ticketResponse = await _client
        .get(settings.endpoint('/api/sync/realtime-ticket', ticketQuery),
            headers: _headers(settings))
        .timeout(const Duration(seconds: 8));
    if (ticketResponse.statusCode < 200 || ticketResponse.statusCode >= 300) {
      throw StateError(
          'Realtime ticket failed: ${ticketResponse.statusCode} ${ticketResponse.body}');
    }
    final ticketPayload = jsonDecode(ticketResponse.body);
    final ticket = ticketPayload is Map ? (ticketPayload['ticket'] ?? '') : '';
    if (ticket.toString().trim().isEmpty) {
      throw StateError('Realtime ticket response is missing ticket.');
    }
    final query = <String, String>{
      'ticket': ticket.toString(),
    };
    if (includeSequenceHint &&
        identity.isClient &&
        state.lastAppliedSequence > 0) {
      query['since_sequence'] = state.lastAppliedSequence.toString();
    }
    final uri = settings.realtimeEndpoint('/api/sync/realtime', query);
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] directRealtime:connect role=${identity.deviceRole.name} '
      'device=${identity.deviceId} url=${uri.replace(queryParameters: {
            ...uri.queryParameters,
            'ticket': '***',
          })}',
    );
    return _RealtimeChannelSession(
      channel: WebSocketChannel.connect(uri),
      uri: uri,
    );
  }

  Future<Map<String, dynamic>> _sendRealtimeRequest(
    VpsControlPlaneSettings settings, {
    required String requestKind,
    required Map<String, dynamic> payload,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final session = await _RealtimeRelaySession.open(
      this,
      settings,
      includeSequenceHint: false,
    );
    try {
      return await session.sendRequest(
        requestKind,
        payload,
        timeout: timeout,
      );
    } finally {
      await session.close();
    }
  }

  Future<bool> _sendRealtimeBroadcast(
    VpsControlPlaneSettings settings, {
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    final session = await _openRealtimeChannel(
      settings,
      includeSequenceHint: false,
    );
    try {
      session.channel.sink.add(jsonEncode({
        'type': type,
        ...payload,
      }));
      return true;
    } finally {
      await session.channel.sink.close();
    }
  }

  void _pruneExpiredRelaySnapshotJobs() {
    final now = DateTime.now().toUtc();
    final expired = DirectControlPlaneService._relaySnapshotJobs.entries
        .where((entry) => entry.value.expiresAt.isBefore(now))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final jobId in expired) {
      DirectControlPlaneService._relaySnapshotJobs.remove(jobId);
    }
  }

  Future<_DirectSnapshotRelayJob?> _buildRelaySnapshotJob(
    String snapshotKind, {
    String rebuildRequestId = '',
    int requiredMinSequence = 0,
  }) async {
    final kind =
        snapshotKind.trim().isEmpty ? 'full_store' : snapshotKind.trim();
    if (kind != 'login_bootstrap') {
      await store.ensureHeavyDataLoaded();
    }
    final chunks = kind == 'login_bootstrap'
        ? await store.exportDirectLoginBootstrapSnapshotChunks()
        : await store.exportDirectBootstrapSnapshotChunks(
            maxItemsPerChunk: 300);
    if (chunks.isEmpty) return null;
    if (kind != 'login_bootstrap' &&
        !_relaySnapshotHasBusinessCollections(chunks)) {
      return null;
    }
    final envelope = store.unifiedSnapshotPayloadFromChunks(chunks);
    final cleanRebuildRequestId = rebuildRequestId.trim();
    if (cleanRebuildRequestId.isNotEmpty) {
      envelope['rebuildRequestId'] = cleanRebuildRequestId;
      envelope['snapshotRequestId'] = cleanRebuildRequestId;
      envelope['requiredMinSequence'] = requiredMinSequence;
      envelope['freshRebuildSnapshot'] = true;
      for (final chunk in chunks) {
        chunk['rebuildRequestId'] = cleanRebuildRequestId;
        chunk['snapshotRequestId'] = cleanRebuildRequestId;
        chunk['requiredMinSequence'] = requiredMinSequence;
        chunk['freshRebuildSnapshot'] = true;
      }
    }
    final jobId = (chunks.first['jobId'] ?? '').toString().trim();
    if (jobId.isEmpty) return null;
    final job = _DirectSnapshotRelayJob(
      jobId: jobId,
      kind: kind,
      createdAt: DateTime.now().toUtc(),
      chunks: chunks,
      envelope: envelope,
    );
    _pruneExpiredRelaySnapshotJobs();
    DirectControlPlaneService._relaySnapshotJobs[jobId] = job;
    return job;
  }

  bool _relaySnapshotHasBusinessCollections(
    List<Map<String, dynamic>> chunks,
  ) {
    for (final chunk in chunks) {
      final collection = (chunk['collection'] ?? '').toString().trim();
      if (collection.isEmpty || collection == '_meta') continue;
      return true;
    }
    return false;
  }

  _DirectSnapshotRelayJob? _relaySnapshotJob(String jobId) {
    final cleanJobId = jobId.trim();
    if (cleanJobId.isEmpty) return null;
    _pruneExpiredRelaySnapshotJobs();
    final job = DirectControlPlaneService._relaySnapshotJobs[cleanJobId];
    if (job == null) return null;
    if (job.expiresAt.isBefore(DateTime.now().toUtc())) {
      DirectControlPlaneService._relaySnapshotJobs.remove(cleanJobId);
      return null;
    }
    return job;
  }

  void _releaseRelaySnapshotJob(String jobId) {
    final cleanJobId = jobId.trim();
    if (cleanJobId.isEmpty) return;
    DirectControlPlaneService._relaySnapshotJobs.remove(cleanJobId);
  }
}
