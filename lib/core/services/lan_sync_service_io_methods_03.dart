part of 'lan_sync_service_io.dart';

extension LanSyncServiceSplitPart3 on LanSyncService {
  Future<LanSyncResult> pullNow(String host,
      {int port = 8787, String token = ''}) async {
    try {
      final snapshotEnvelope = await _downloadLanSnapshotEnvelope(
        host,
        port: port,
        token: token,
        force: true,
      );
      final applied = await UnifiedSnapshotLifecycle.applyEnvelope(
        store: store,
        envelope: snapshotEnvelope,
        afterImport: (_) => _markHostSnapshotGenerationApplied(
          'lan',
          snapshotEnvelope,
        ),
      );
      final hostCursor = applied.cursor;
      final settings = LanSyncSettings.load();
      await settings
          .copyWith(
              lastPullCursor: hostCursor,
              lastConnectionAt: DateTime.now(),
              lastSyncAt: DateTime.now())
          .save();
      return const LanSyncResult(
          ok: true, message: 'Pull completed from LAN snapshot chunks.');
    } catch (error) {
      return LanSyncResult(
          ok: false, message: _failureMessage('Pull failed', error));
    }
  }

  Future<LanSyncResult> _repairFromHostSnapshotImpl(String host,
      {int port = 8787,
      String token = '',
      LanSyncProgressCallback? onProgress}) async {
    if (!UnifiedSyncPolicy.canRebuildFromLanSnapshot(store.appIdentity)) {
      return const LanSyncResult(
          ok: false,
          message:
              'Host devices cannot rebuild from LAN Host snapshots. Use Transfer Host instead.');
    }
    try {
      onProgress?.call(0.10, 'Connecting to LAN Host snapshot...');
      final snapshotEnvelope = await _downloadLanSnapshotEnvelope(
        host,
        port: port,
        token: token,
        force: true,
        onProgress: onProgress,
      );
      onProgress?.call(0.72, 'Applying LAN snapshot chunks locally...');
      final applied = await UnifiedSnapshotLifecycle.applyEnvelope(
        store: store,
        envelope: snapshotEnvelope,
        afterImport: (_) => _markHostSnapshotGenerationApplied(
          'lan',
          snapshotEnvelope,
        ),
        markAllSyncChangesSynced: true,
        cleanupSoftDeleted: false,
      );
      onProgress?.call(0.86, 'Marking rebuilt data as synced...');
      final hostCursor = applied.cursor;
      final settings = LanSyncSettings.load();
      final hostSequence = applied.sequence;
      await _saveCursorAndRecordState(settings, hostCursor,
          sequence: hostSequence);
      await _sendLanAck(host,
          port: port, token: token, cursor: hostCursor, sequence: hostSequence);
      onProgress?.call(0.94, 'Running Client sync log maintenance...');
      await store.compactClientSyncedSyncHistoryForMaintenance();
      onProgress?.call(1.0, 'LAN rebuild completed.');
      return const LanSyncResult(
          ok: true, message: 'LAN rebuild completed from snapshot chunks.');
    } catch (error) {
      if (!_hostRecoveryInProgress && _isNetworkFailure(error)) {
        _hostRecoveryInProgress = true;
        final recovered = await discoverHost(port: port);
        if (recovered != null) {
          try {
            return await repairFromHostSnapshot(recovered,
                port: port, token: token, onProgress: onProgress);
          } finally {
            _hostRecoveryInProgress = false;
          }
        }
        _hostRecoveryInProgress = false;
      }
      return LanSyncResult(
          ok: false, message: 'Repair snapshot failed: $error');
    }
  }

  void _updateHostRegistryDeviceName(String deviceId, String deviceName) {
    final cleanId = deviceId.trim();
    final cleanName = deviceName.trim();
    if (cleanId.isEmpty || cleanName.isEmpty) return;
    final settings = LanSyncSettings.load();
    final existing = settings.hostRegistry[cleanId];
    if (existing == null || existing.deviceName.trim() == cleanName) return;
    final registry =
        Map<String, HostRegistryDevice>.from(settings.hostRegistry);
    registry[cleanId] = existing.copyWith(
      deviceName: cleanName,
      lastSeenAt: DateTime.now(),
    );
    settings.copyWith(hostRegistry: Map.unmodifiable(registry)).save();
  }

  Map<String, String> _decodeRejectedSyncRequests(dynamic raw) {
    final output = <String, String>{};
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final id = (item['id'] ?? '').toString();
          if (id.isNotEmpty) {
            output[id] = (item['reason'] ?? 'Rejected by Host.').toString();
          }
        }
      }
    }
    return output;
  }

  Future<void> _saveCursorAndRecordState(
    LanSyncSettings settings,
    DateTime cursor, {
    int sequence = 0,
  }) async {
    await settings
        .copyWith(
          lastPullCursor: cursor,
          lastConnectionAt: DateTime.now(),
          lastSyncAt: DateTime.now(),
        )
        .save();
    await _syncCore.saveCursorAndRecordTransportState(
      store,
      transport: 'lan',
      cursor: cursor,
      sequence: sequence,
      saveTransportState: () async {},
    );
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

  bool shouldBypassTransportSyncForHost() {
    return _syncCore.shouldBypassTransportSyncForHost(
      isHost: store.appIdentity.isHost || isHosting,
      transportHasNativeHostMode: true,
    );
  }

  Future<void> compactAfterSuccessfulSync() {
    return _syncCore.compactAfterSuccessfulSync();
  }

  Future<LanSyncResult?> _handleLanAccessResponse(int statusCode, String body,
      {required String host, int port = 8787, String token = ''}) async {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (decoded['wipeRequired'] == true ||
          decoded['action'] == 'wipe_local_data') {
        final wipedDeviceId = store.deviceId;
        final wipedStoreId = store.appIdentity.storeId;
        final wipedBranchId = store.appIdentity.branchId;
        final wipedToken = store.appIdentity.deviceToken;
        await _confirmLanWipe(host,
            port: port,
            token: token,
            storeId: wipedStoreId,
            branchId: wipedBranchId,
            deviceId: wipedDeviceId,
            deviceToken: wipedToken);
        await store.factoryResetLocalDevice(enforcePermission: false);
        return const LanSyncResult(
            ok: false,
            message: 'Device deleted by Host. Local data was wiped.');
      }
      if (decoded['suspended'] == true || decoded['action'] == 'suspended') {
        final reason =
            decoded['error']?.toString() ?? 'Device is suspended by Host.';
        await store.markSuspendedByHost(reason: reason);
        return LanSyncResult(ok: false, message: reason);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _confirmLanWipe(
    String host, {
    int port = 8787,
    String token = '',
    required String storeId,
    required String branchId,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final client = _client();
      final request = await client.post(host.trim(), port, '/device-wipe-ack');
      _attachToken(request, token);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'storeId': storeId,
        'branchId': branchId,
        'deviceId': deviceId,
        'deviceToken': deviceToken,
      }));
      await request.close().timeout(const Duration(seconds: 10));
      client.close(force: true);
    } catch (_) {
      // Keep wipe pending on the Host if the ACK cannot be delivered.
      // The next sync contact will receive the wipe command again.
    }
  }

  Future<void> _sendLanAck(String host,
      {int port = 8787,
      String token = '',
      required DateTime cursor,
      int sequence = 0}) async {
    try {
      final client = _client();
      final request = await client.post(host.trim(), port, '/changes/ack');
      _attachToken(request, token);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'deviceId': store.deviceId,
        'storeId': store.appIdentity.storeId,
        'branchId': store.appIdentity.branchId,
        'deviceName': store.appIdentity.deviceName,
        'lastAppliedCursor': cursor.toIso8601String(),
        'lastAckCursor': cursor.toIso8601String(),
        'lastAppliedSequence': sequence,
        'lastAckSequence': sequence,
      }));
      await request.close();
      client.close(force: true);
    } catch (_) {
      // ACK is best-effort; the next LAN pull/heartbeat can repair Host visibility.
    }
  }

  Future<LanSyncResult> _pushPendingOnlyImpl(String host,
      {int port = 8787,
      String token = '',
      LanSyncProgressCallback? onProgress}) async {
    final pending =
        _syncCore.pendingChangesForTarget(UnifiedSyncQueueTarget.host);
    final pendingIds = _syncCore.changeIds(pending);
    if (pending.isEmpty) {
      return const LanSyncResult(ok: true, message: 'No LAN changes to push.');
    }
    try {
      final client = _client();
      onProgress?.call(
          0.18, 'Preparing ${pending.length} local change(s) for LAN push...');
      await _syncCore.markPushInProgress(pendingIds);
      final pushRequest = await client.post(host.trim(), port, '/changes/push');
      _attachToken(pushRequest, token);
      pushRequest.headers.contentType = ContentType.json;
      pushRequest.write(jsonEncode({
        'deviceId': store.deviceId,
        'storeId': store.appIdentity.storeId,
        'branchId': store.appIdentity.branchId,
        'deviceName': store.appIdentity.deviceName,
        'cursor': LanSyncSettings.load().lastPullCursor?.toIso8601String(),
        'sequence': SyncDeviceStateStore.lastAppliedSequenceForTransport(
            store.appIdentity, 'lan'),
        'changes': pending.map((item) => item.toJson()).toList(),
      }));
      final pushResponse = await pushRequest.close();
      final pushBody = await utf8.decoder.bind(pushResponse).join();
      client.close(force: true);
      if (pushResponse.statusCode != 200) {
        final access = await _handleLanAccessResponse(
            pushResponse.statusCode, pushBody,
            host: host, port: port, token: token);
        if (access != null) return access;
        final message = 'Push failed: ${pushResponse.statusCode} $pushBody';
        await _syncCore.markPushFailed(pendingIds, message);
        return LanSyncResult(ok: false, message: message);
      }
      final decoded = jsonDecode(pushBody) as Map<String, dynamic>;
      final ackIds = (decoded['ackIds'] as List<dynamic>? ?? [])
          .map((item) => '$item')
          .toList();
      final rejected = _decodeRejectedSyncRequests(decoded['rejected']);
      if (rejected.isNotEmpty) await _syncCore.markPushRejected(rejected);
      await _syncCore.markPushAcknowledged(ackIds, fallbackIds: pendingIds);
      await store.clearSuspendedByHost();
      return LanSyncResult(
          ok: true,
          message: 'LAN push completed. Pushed ${pending.length} change(s).');
    } catch (error) {
      if (!_hostRecoveryInProgress && _isNetworkFailure(error)) {
        _hostRecoveryInProgress = true;
        final recovered = await discoverHost(port: port);
        if (recovered != null) {
          try {
            return await pushPendingOnly(recovered,
                port: port, token: token, onProgress: onProgress);
          } finally {
            _hostRecoveryInProgress = false;
          }
        }
        _hostRecoveryInProgress = false;
      }
      await _syncCore.markPushFailed(pendingIds, error.toString());
      return LanSyncResult(
          ok: false, message: _failureMessage('LAN push failed', error));
    }
  }

  Future<bool> waitForRealtimeSignal(String host,
      {int port = 8787,
      String token = '',
      Duration wait = const Duration(seconds: 25)}) async {
    try {
      await _ensureRealtimeClient(host, port: port, token: token);
      final signal = await _realtimeSignals.stream.first.timeout(wait);
      return signal;
    } catch (_) {
      await _closeRealtimeClient();
      // Keep the existing long-poll endpoint as a compatibility fallback
      // while older Hosts or restricted LANs are being upgraded.
      final fallback = await _waitForLongPollSignal(
        host,
        port: port,
        token: token,
        wait: wait,
      );
      if (!fallback) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      return fallback;
    }
  }

  Future<void> _ensureRealtimeClient(String host,
      {int port = 8787, String token = ''}) async {
    if (_realtimeChannel != null) return;
    final cleanHost = host.trim();
    if (cleanHost.isEmpty) throw const SocketException('LAN Host is empty.');
    final uri = Uri(
      scheme: 'ws',
      host: cleanHost,
      port: port,
      path: '/realtime',
    );
    final identity = store.appIdentity;
    final headers = <String, String>{
      'X-Device-Id': identity.deviceId,
      'X-Device-Token':
          token.trim().isNotEmpty ? token.trim() : identity.deviceToken.trim(),
      'X-Device-Role': identity.deviceRole.name,
    };
    final channel = IOWebSocketChannel.connect(uri, headers: headers);
    _realtimeChannel = channel;
    _realtimeSubscription = channel.stream.listen(
      (raw) {
        try {
          final decoded = jsonDecode(raw.toString());
          if (decoded is Map && decoded['type'] == 'sync_changed') {
            _realtimeSignals.add(true);
          }
        } catch (_) {
          // Invalid realtime frames are ignored; pull reconciliation remains authoritative.
        }
      },
      onDone: () {
        _realtimeChannel = null;
        _realtimeSubscription = null;
        _realtimeSignals.add(false);
      },
      onError: (_, __) {
        _realtimeChannel = null;
        _realtimeSubscription = null;
        _realtimeSignals.add(false);
      },
      cancelOnError: true,
    );
    await channel.ready;
  }

  Future<bool> _waitForLongPollSignal(String host,
      {int port = 8787,
      String token = '',
      Duration wait = const Duration(seconds: 25)}) async {
    try {
      final settings = LanSyncSettings.load();
      final client = _client();
      final lastSequence = SyncDeviceStateStore.lastAppliedSequenceForTransport(
          store.appIdentity, 'lan');
      final query = <String, String>{
        'wait_seconds': wait.inSeconds.clamp(1, 25).toString(),
        'since_sequence': lastSequence.toString(),
      };
      if (settings.lastPullCursor != null) {
        query['since'] = settings.lastPullCursor!.toIso8601String();
      }
      final path =
          Uri(path: '/changes/signal', queryParameters: query).toString();
      final request = await client.get(host.trim(), port, path);
      _attachToken(request, token);
      final response =
          await request.close().timeout(wait + const Duration(seconds: 8));
      final body = await utf8.decoder.bind(response).join();
      client.close(force: true);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      return decoded['changed'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<LanSyncResult> _pullChangesOnlyImpl(String host,
      {int port = 8787,
      String token = '',
      LanSyncProgressCallback? onProgress}) async {
    final settings = LanSyncSettings.load();
    try {
      final client = _client();
      final ackCursor = settings.lastPullCursor?.toIso8601String() ?? '';
      final lastSequence = SyncDeviceStateStore.lastAppliedSequenceForTransport(
          store.appIdentity, 'lan');
      final seqParam = '&since_sequence=$lastSequence';
      final path = settings.lastPullCursor == null
          ? '/changes/pull?device_id=${Uri.encodeQueryComponent(store.deviceId)}&ack_cursor=${Uri.encodeQueryComponent(ackCursor)}$seqParam'
          : '/changes/pull?device_id=${Uri.encodeQueryComponent(store.deviceId)}&ack_cursor=${Uri.encodeQueryComponent(ackCursor)}&since=${Uri.encodeQueryComponent(settings.lastPullCursor!.toIso8601String())}$seqParam';
      onProgress?.call(0.62, 'Pulling new changes from LAN Host...');
      final pullRequest = await client.get(host.trim(), port, path);
      _attachToken(pullRequest, token);
      final pullResponse = await pullRequest.close();
      final pullBody = await utf8.decoder.bind(pullResponse).join();
      client.close(force: true);
      if (pullResponse.statusCode != 200) {
        final access = await _handleLanAccessResponse(
            pullResponse.statusCode, pullBody,
            host: host, port: port, token: token);
        if (access != null) return access;
        return LanSyncResult(
            ok: false,
            message:
                'Pull changes failed: ${pullResponse.statusCode} $pullBody');
      }
      final decodedPull = jsonDecode(pullBody) as Map<String, dynamic>;
      final generationRebuild = await _rebuildIfHostSnapshotGenerationChanged(
        host,
        port,
        token,
        decodedPull,
        onProgress: onProgress,
      );
      if (generationRebuild != null) return generationRebuild;
      if (_syncCore.shouldHandlePulledSnapshotAsRepair(
        decodedPull,
        isClient: store.appIdentity.isClient,
      )) {
        final repair = await repairFromHostSnapshot(host,
            port: port, token: token, onProgress: onProgress);
        return repair.ok
            ? LanSyncResult(
                ok: true,
                message: 'LAN event log gap detected. ${repair.message}')
            : LanSyncResult(
                ok: false,
                message:
                    'LAN event log gap detected and repair failed. ${repair.message}');
      }
      final changes = _syncCore
          .normalizePulledChanges(decodedPull['changes'] as List<dynamic>?);
      if (_syncCore.shouldRebuildClientFromRestoreMarker(
        changes,
        isClient: store.appIdentity.isClient,
      )) {
        final commandId = _restoreCommandIdFromChanges(changes);
        if (_restoreCommandAlreadyExecuted('lan', commandId)) {
          onProgress?.call(0.72,
              'Host restore command already applied. Continuing LAN sync...');
        } else {
          onProgress?.call(0.72,
              'Host restore detected. Rebuilding from LAN Host snapshot...');
          await settings.copyWith(clearLastPullCursor: true).save();
          await SyncDeviceStateStore.resetClientProgress(store.appIdentity,
              transport: 'lan');
          return repairFromHostSnapshot(host,
              port: port, token: token, onProgress: onProgress);
        }
      }
      onProgress?.call(
          0.78, 'Applying ${changes.length} LAN change(s) locally...');
      await _syncCore.applyAuthoritativeChanges(changes);
      final generatedAt =
          DateTime.tryParse(decodedPull['generatedAt'] as String? ?? '') ??
              DateTime.now();
      final generatedSequence =
          int.tryParse(decodedPull['generatedSequence']?.toString() ?? '') ?? 0;
      await settings
          .copyWith(
              lastPullCursor: generatedAt,
              lastConnectionAt: DateTime.now(),
              lastSyncAt: DateTime.now())
          .save();
      await _saveCursorAndRecordState(settings, generatedAt,
          sequence: generatedSequence);
      await _sendLanAck(host,
          port: port,
          token: token,
          cursor: generatedAt,
          sequence: generatedSequence);
      await store.clearSuspendedByHost();
      return LanSyncResult(
          ok: true,
          message: 'LAN pull completed. Pulled ${changes.length} change(s).');
    } catch (error) {
      if (!_hostRecoveryInProgress && _isNetworkFailure(error)) {
        _hostRecoveryInProgress = true;
        final recovered = await discoverHost(port: port);
        if (recovered != null) {
          try {
            return await pullChangesOnly(recovered,
                port: port, token: token, onProgress: onProgress);
          } finally {
            _hostRecoveryInProgress = false;
          }
        }
        _hostRecoveryInProgress = false;
      }
      return LanSyncResult(
          ok: false, message: _failureMessage('LAN pull failed', error));
    }
  }
}
