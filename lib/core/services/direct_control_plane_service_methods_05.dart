part of 'direct_control_plane_service.dart';

extension DirectControlPlaneServiceSplitPart5 on DirectControlPlaneService {

  Future<DirectSyncResult> testConnection(
      VpsControlPlaneSettings settings) async {
    if (!settings.isConfigured) {
      return const DirectSyncResult(
          ok: false, message: 'Direct API URL and token are required.');
    }
    final accessResult = await checkCurrentDeviceAccess(settings);
    if (accessResult != null) return accessResult;

    try {
      final health = await _client
          .get(settings.endpoint('/api/health'), headers: _headers(settings))
          .timeout(const Duration(seconds: 10));
      if (health.statusCode < 200 || health.statusCode >= 300) {
        final authMessage = health.statusCode == 401 || health.statusCode == 403
            ? 'Unauthorized/Token invalid: Direct API rejected the token.'
            : 'Direct Server Unreachable: Direct API returned status ${health.statusCode}: ${health.body}';
        return DirectSyncResult(ok: false, message: authMessage);
      }
      final decoded = jsonDecode(health.body) as Map<String, dynamic>;
      if (decoded['ok'] != true) {
        return const DirectSyncResult(
            ok: false, message: 'Direct health response was not successful.');
      }
    } catch (error) {
      return DirectSyncResult(
          ok: false, message: 'Direct Server Unreachable: $error');
    }

    final identity = store.appIdentity;
    if (!identity.isClient) {
      return const DirectSyncResult(
          ok: true, message: 'Direct API connection is healthy.');
    }

    if (identity.deviceToken.trim().isEmpty) {
      return const DirectSyncResult(
          ok: false,
          message:
              'Unauthorized/Token invalid: this Client has no saved device token. Pair this device again.');
    }

    try {
      final hostStatus = await getHostHeartbeatStatus(settings);
      if (!hostStatus.controlPlaneReachable) {
        final lower = hostStatus.message.toLowerCase();
        final message = lower.contains('401') ||
                lower.contains('403') ||
                lower.contains('unauthorized') ||
                lower.contains('token')
            ? 'Unauthorized/Token invalid: ${hostStatus.message}'
            : 'Direct Server Unreachable: ${hostStatus.message}';
        return DirectSyncResult(ok: false, message: message);
      }
      if (!hostStatus.hostReachable) {
        return DirectSyncResult(
            ok: false, message: 'Host Offline: ${hostStatus.message}');
      }

      return const DirectSyncResult(
          ok: true, message: 'Direct Connected/Ready for Sync.');
    } catch (error) {
      return DirectSyncResult(ok: false, message: 'Sync Not Ready: $error');
    }
  }

  /// Verifies that a Direct Host can establish the same realtime transport
  /// that will carry Client requests. A healthy HTTP API alone is not enough:
  /// the Host must also be reachable through the Relay WebSocket.
  Future<DirectSyncResult> ensureHostRelayReady(
      VpsControlPlaneSettings settings) async {
    final identity = store.appIdentity;
    if (!identity.isHost) {
      return const DirectSyncResult(
          ok: false, message: 'Only a Direct Host can open the Host relay.');
    }
    if (!settings.isConfigured) {
      return const DirectSyncResult(
          ok: false, message: 'Direct API URL and token are required.');
    }
    _RealtimeChannelSession? session;
    try {
      session =
          await _openRealtimeChannel(settings, includeSequenceHint: false);
      await session.channel.stream.first.timeout(const Duration(seconds: 8));
      return const DirectSyncResult(
          ok: true, message: 'Direct Host relay is ready.');
    } catch (error) {
      return DirectSyncResult(
          ok: false, message: 'Direct Host relay is not ready: $error');
    } finally {
      await session?.channel.sink.close();
    }
  }

  Future<DirectSyncResult> validateSingleHost(
      VpsControlPlaneSettings settings) async {
    final identity = store.appIdentity;
    if (!settings.isConfigured) {
      return const DirectSyncResult(
          ok: false, message: 'Direct API URL and token are required.');
    }
    final status = await getHostHeartbeatStatus(settings);
    if (status.controlPlaneReachable &&
        status.hostReachable &&
        status.hostDeviceId.isNotEmpty &&
        status.hostDeviceId != store.deviceId) {
      return DirectSyncResult(
        ok: false,
        message:
            'Another active Host is already connected for store ${identity.storeId}: ${status.hostDeviceName.isEmpty ? status.hostDeviceId : status.hostDeviceName}. Convert this device to a Client or stop the old Host first.',
      );
    }
    return const DirectSyncResult(
        ok: true, message: 'No other active Host was found.');
  }

  Future<DirectSyncResult> sendHostHeartbeat(
      VpsControlPlaneSettings settings) async {
    final identity = store.appIdentity;
    if (!identity.isDirectEnabled || !identity.isHost) {
      return const DirectSyncResult(
          ok: false,
          message: 'Heartbeat is only sent by a direct-enabled Host device.');
    }
    if (!settings.isConfigured) {
      return const DirectSyncResult(
          ok: false, message: 'Direct API URL and token are required.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/host-heartbeat'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'hostDeviceId': store.deviceId,
              'hostDeviceName': identity.deviceName,
              'platform': identity.platform.name,
              'appVersion': AppBrand.directAppVersion,
              'syncMode': identity.syncMode.name,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return DirectSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? 'Host heartbeat updated.'
            : 'Host heartbeat failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return DirectSyncResult(
          ok: false, message: 'Host heartbeat failed: $error');
    }
  }

  Future<DirectSyncResult> stopHost(VpsControlPlaneSettings settings) async {
    final identity = store.appIdentity;
    if (!identity.isHost || !settings.isConfigured) {
      return const DirectSyncResult(
          ok: true, message: 'Direct Host is already stopped.');
    }
    try {
      final response = await _client
          .delete(
            settings.endpoint('/api/sync/host-heartbeat', {
              'store_id': identity.storeId,
              'branch_id': identity.branchId,
              'host_device_id': store.deviceId,
            }),
            headers: _headers(settings),
          )
          .timeout(const Duration(seconds: 10));
      return DirectSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? 'Direct Host stopped.'
            : 'Direct Host stop failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return DirectSyncResult(
          ok: false, message: 'Direct Host stop failed: $error');
    }
  }

  Future<bool> waitForRealtimeSignal(
    VpsControlPlaneSettings settings, {
    Duration wait = const Duration(seconds: 25),
  }) async {
    final identity = store.appIdentity;
    if (!_directAllowedForIdentity(identity) || !settings.isConfigured) {
      return false;
    }
    try {
      final session = await _openRealtimeChannel(settings);
      final channel = session.channel;
      final completer = Completer<bool>();
      late final StreamSubscription<dynamic> subscription;
      subscription = channel.stream.listen(
        (raw) async {
          if (completer.isCompleted) return;
          final decoded = jsonDecode(raw.toString());
          if (decoded is! Map) return;
          final signal = await _handleRealtimePacket(
            settings,
            channel,
            Map<String, dynamic>.from(decoded),
          );
          if (signal != null && !completer.isCompleted) {
            completer.complete(true);
          }
        },
        onError: (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(false);
        },
        cancelOnError: false,
      );
      try {
        return await completer.future.timeout(
          wait + const Duration(seconds: 8),
          onTimeout: () => false,
        );
      } finally {
        await subscription.cancel();
        await channel.sink.close();
      }
    } catch (_) {
      return false;
    }
  }

  Stream<DirectRealtimeSignal> watchRealtimeSignals(
    VpsControlPlaneSettings settings,
  ) async* {
    final identity = store.appIdentity;
    if (!_directAllowedForIdentity(identity) || !settings.isConfigured) {
      return;
    }
    final session = await _openRealtimeChannel(settings);
    final channel = session.channel;
    try {
      await for (final raw in channel.stream) {
        final decoded = jsonDecode(raw.toString());
        if (decoded is! Map) continue;
        final packet = Map<String, dynamic>.from(decoded);
        final type = (packet['type'] ?? '').toString();
        if (type == 'realtime_welcome') {
          SyncDiagnosticsLog.add(
            '[SYNC_TRACE] directRealtime:connected role=${identity.deviceRole.name} '
            'device=${identity.deviceId} url=${session.uri.replace(queryParameters: {
                  ...session.uri.queryParameters,
                  'ticket': '***',
                })}',
          );
          continue;
        }
        final signal = await _handleRealtimePacket(settings, channel, packet);
        if (signal == null) continue;
        yield signal;
      }
    } finally {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] directRealtime:closed role=${identity.deviceRole.name} '
        'device=${identity.deviceId}',
      );
      unawaited(channel.sink.close());
    }
  }

  Future<HostHeartbeatStatus> getHostHeartbeatStatus(
      VpsControlPlaneSettings settings,
      {Duration staleAfter = const Duration(seconds: 90)}) async {
    final identity = store.appIdentity;
    if (!settings.isConfigured) {
      return const HostHeartbeatStatus(
          controlPlaneReachable: false,
          hostReachable: false,
          message: 'Direct API URL and token are required.');
    }
    try {
      final response = await _client
          .get(
            settings.endpoint('/api/sync/host-heartbeat', {
              'store_id': identity.storeId,
              'branch_id': identity.branchId,
            }),
            headers: _headers(settings),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return HostHeartbeatStatus(
            controlPlaneReachable: false,
            hostReachable: false,
            message:
                'Direct API returned status ${response.statusCode}: ${response.body}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final rawLastSeen = decoded['lastSeenAt'] ?? decoded['last_seen_at'];
      final lastSeenAt = rawLastSeen == null
          ? null
          : DateTime.tryParse(rawLastSeen.toString());
      final hostReachable = lastSeenAt != null &&
          DateTime.now().toUtc().difference(lastSeenAt.toUtc()) <= staleAfter;
      final hostDeviceId =
          (decoded['hostDeviceId'] ?? decoded['host_device_id'] ?? '')
              .toString();
      final hostDeviceName =
          (decoded['hostDeviceName'] ?? decoded['host_device_name'] ?? '')
              .toString();
      return HostHeartbeatStatus(
        controlPlaneReachable: true,
        hostReachable: hostReachable,
        lastSeenAt: lastSeenAt,
        hostDeviceId: hostDeviceId,
        hostDeviceName: hostDeviceName,
        message: hostReachable
            ? 'Host heartbeat is fresh.'
            : (lastSeenAt == null
                ? 'No host heartbeat was found.'
                : 'Host heartbeat is stale.'),
      );
    } catch (error) {
      return HostHeartbeatStatus(
          controlPlaneReachable: false,
          hostReachable: false,
          message: 'Direct API connection failed: $error');
    }
  }

  Future<Map<String, dynamic>?> runDirectMaintenance(
      VpsControlPlaneSettings settings,
      {int eventRetentionDays = 30}) async {
    // Direct is a relay only. Sync history and snapshots are maintained by the
    // Host's local database, so there is no remote maintenance operation.
    return null;
    /* Legacy remote maintenance call intentionally disabled.
    if (!identity.isHost ||
        !identity.isDirectEnabled ||
        !settings.isConfigured) {
      return null;
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/maintenance'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'hostDeviceId': store.deviceId,
              'deviceId': store.deviceId,
              'eventRetentionDays': eventRetentionDays,
              'processedRequestRetentionDays': 3,
              'deletedSnapshotRetentionDays': 7,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
            'Direct maintenance failed: ${response.statusCode} ${response.body}');
        return null;
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (error) {
      debugPrint('Direct maintenance failed: $error');
      return null;
    }
    */
  }

  Future<Map<String, dynamic>> _downloadDirectSnapshotEnvelope(
    VpsControlPlaneSettings settings, {
    bool force = false,
    DirectSyncProgressCallback? onProgress,
  }) =>
      _downloadDirectSnapshotEnvelopeViaRelay(
        settings,
        force: force,
        onProgress: onProgress,
      );

  Future<Map<String, dynamic>> _downloadDirectSnapshotEnvelopeViaRelay(
    VpsControlPlaneSettings settings, {
    bool force = false,
    DirectSyncProgressCallback? onProgress,
    String snapshotKind = 'full_store',
    String rebuildRequestId = '',
    int requiredMinSequence = 0,
  }) async {
    final transport = _DirectRelaySnapshotPullTransport(
      service: this,
      settings: settings,
      snapshotKind: snapshotKind,
      rebuildRequestId: rebuildRequestId,
      requiredMinSequence: requiredMinSequence,
    );
    try {
      return await const UnifiedSnapshotTransferService().downloadEnvelope(
        transport,
        force: force,
        labelPrefix: 'Direct snapshot',
        onProgress: onProgress,
      );
    } finally {
      await transport.dispose();
    }
  }

  Future<DirectSyncResult> _applyDirectSnapshotEnvelope(
    Map<String, dynamic> envelope, {
    required VpsControlPlaneSettings settings,
    required DirectSyncProgressCallback? onProgress,
    void Function(String message)? onDiagnostic,
    required String expectedSnapshotGeneration,
    required String expectedRestoreCommandId,
  }) async {
    if ((envelope['hostSnapshotGeneration'] ?? '').toString().trim().isEmpty &&
        expectedSnapshotGeneration.trim().isNotEmpty) {
      envelope['hostSnapshotGeneration'] = expectedSnapshotGeneration.trim();
      envelope['snapshotGeneration'] = expectedSnapshotGeneration.trim();
    }
    if ((envelope['hostRestoreCommandId'] ?? '').toString().trim().isEmpty &&
        expectedRestoreCommandId.trim().isNotEmpty) {
      envelope['hostRestoreCommandId'] = expectedRestoreCommandId.trim();
      envelope['restoreCommandId'] = expectedRestoreCommandId.trim();
    }
    onProgress?.call(0.84, 'Applying Direct snapshot chunks locally...');
    // Reset the Client progress only after a valid Host snapshot envelope has
    // been downloaded and is about to be applied. This prevents pressure/offline
    // rebuild deferrals from publishing ACK/sequence = 0 without an applied
    // replacement snapshot.
    await VpsControlPlaneSettings.clearSavedPullCursor();
    await SyncDeviceStateStore.resetClientProgress(store.appIdentity,
        transport: 'direct');
    late final UnifiedSnapshotApplyResult applied;
    try {
      applied = await UnifiedSnapshotLifecycle.applyEnvelope(
        store: store,
        envelope: envelope,
        afterImport: (_) => _markHostSnapshotGenerationApplied(
          'direct',
          envelope,
          markRestoreCommandExecuted: true,
        ),
      );
    } catch (error, stackTrace) {
      onDiagnostic?.call(
          '[DIRECT_REBUILD] snapshot apply failed error=$error stack=${stackTrace.toString().split('\n').take(3).join(' | ')}');
      rethrow;
    }
    onDiagnostic?.call(
        '[DIRECT_REBUILD] snapshot applied sequence=${applied.sequence}');
    onProgress?.call(0.90, 'Finalizing rebuilt local data...');
    onProgress?.call(0.96, 'Cleaning up local records...');
    await DirectProvisioningStatus.markComplete(
        message: 'Initial Store data downloaded.');
    await _recordDeviceSyncState(
      'direct',
      applied.cursor,
      sequence: applied.sequence,
      settings: settings,
    );
    onProgress?.call(1.0, 'Direct rebuild completed.');
    return DirectSyncResult(
      ok: true,
      pulled: applied.transferredChunks,
      restoredSnapshot: true,
      message: applied.verificationOk
          ? 'Direct rebuild completed from unified snapshot chunks.'
          : 'Unified snapshot chunks downloaded, but local verification found problems: ${applied.verificationMessage}',
    );
  }

  Future<int> publishLoginBootstrapSnapshotToDirect(
    VpsControlPlaneSettings settings, {
    bool force = false,
    void Function(double value, String label)? onProgress,
  }) async {
    // Direct is a transport relay only. The Host must never upload business
    // snapshots to the Direct API, including the old login bootstrap path.
    // New Clients obtain their snapshot from the Host through the realtime
    // relay in `_DirectSnapshotRelayPullTransport`.
    return 0;
  }

  Future<int> publishBootstrapSnapshotToDirect(
    VpsControlPlaneSettings settings, {
    bool force = false,
    void Function(double value, String label)? onProgress,
  }) async {
    // Kept as a compatibility shim for older callers. Direct snapshots are
    // never uploaded; the Host serves them through the realtime relay.
    return 0;
    /* Legacy upload implementation intentionally disabled.
    final identity = store.appIdentity;
    if (!identity.isHost ||
        !identity.isDirectEnabled ||
        !settings.isConfigured) {
      return 0;
    }
    await store.ensureHeavyDataLoaded();
    final chunks =
        await store.exportDirectBootstrapSnapshotChunks(maxItemsPerChunk: 300);
    if (chunks.isEmpty || !_relaySnapshotHasBusinessCollections(chunks)) {
      return 0;
    }
    return const UnifiedSnapshotTransferService().uploadChunks(
      _DirectSnapshotPushTransport(
        settings: settings,
        headers: _headers(settings),
        client: _client,
      ),
      chunks,
      force: force,
      preserveExisting: false,
      labelPrefix: 'Direct snapshot',
      onProgress: onProgress,
    );
    */
  }

  Future<int> _pushPendingViaRelay(
    VpsControlPlaneSettings settings, {
    required String target,
  }) async {
    final identity = store.appIdentity;
    const transport = 'direct';
    var totalPushed = 0;
    var batchNumber = 0;
    const batchSize = 500;
    // Recover rows left in `submitted` by a previous sync attempt once at the
    // start of this push operation. Do not recover them inside the batch loop:
    // Client pushes intentionally remain `submitted` until the following Pull
    // applies the Host-authoritative event. Recovering them on every iteration
    // would turn the same push into an endless resend loop.
    await store.recoverSubmittedSyncQueue(target: target);
    final relaySession = await _RealtimeRelaySession.open(
      this,
      settings,
      includeSequenceHint: false,
    );

    try {
      while (true) {
        await store.recoverStaleInProgressSyncQueue(target: target);
        await store.retryFailedSyncQueue(target: target);
        final pending = _syncCore
            .pendingChangesForTarget(target)
            .take(batchSize)
            .toList(growable: false);
        final pendingIds = _syncCore.changeIds(pending);
        if (pending.isEmpty) break;
        batchNumber += 1;

        await _syncCore.markPushInProgress(pendingIds);
        try {
          final response = await relaySession.sendRequest(
            'direct_client_push',
            {
              'deviceId': store.deviceId,
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'sequence': SyncDeviceStateStore.lastAppliedSequenceForTransport(
                  identity, transport),
              'lastAppliedSequence':
                  SyncDeviceStateStore.lastAppliedSequenceForTransport(
                      identity, transport),
              'batchNumber': batchNumber,
              'batchSize': pending.length,
              'changes': pending.map((item) => item.toJson()).toList(),
            },
          );
          if (response['ok'] != true) {
            final message = 'Direct relay push failed in batch $batchNumber: '
                '${response['error'] ?? response['message'] ?? 'unknown error'}';
            await _syncCore.markPushFailed(pendingIds, message);
            throw StateError(message);
          }
          final ackIds = (response['ackIds'] as List<dynamic>? ?? [])
              .map((item) => '$item')
              .where((item) => item.trim().isNotEmpty)
              .toList();
          final rejected = <String, String>{};
          final rawRejected = response['rejected'];
          if (rawRejected is List) {
            for (final item in rawRejected) {
              if (item is Map) {
                final id = (item['id'] ?? '').toString().trim();
                if (id.isNotEmpty) {
                  rejected[id] =
                      (item['reason'] ?? 'Rejected by Host.').toString();
                }
              }
            }
          }
          if (rejected.isNotEmpty) await _syncCore.markPushRejected(rejected);
          if (target == 'host') {
            // The relay ACK only confirms that the Host accepted the draft.
            // The change becomes final after the Client pulls the Host's
            // authoritative event. Marking it synced here can lose a change
            // when the following pull is interrupted or returns no data.
            await _syncCore.markPushSubmitted(ackIds);
          } else {
            // Host-originated Direct changes are already authoritative locally.
            await _syncCore.markPushAcknowledged(ackIds,
                fallbackIds: pendingIds);
          }
          totalPushed += pending.length;
        } catch (error) {
          await _syncCore.markPushFailed(
            pendingIds,
            'Direct relay push failed in batch $batchNumber: $error',
          );
          rethrow;
        }
      }
    } finally {
      await relaySession.close();
    }

    return totalPushed;
  }

  Future<bool> _broadcastHostAuthorityViaRelay(
    VpsControlPlaneSettings settings,
  ) async {
    // Recover queue rows left behind by older Direct builds or an interrupted
    // relay call before selecting the Host events to publish. Without this,
    // the event can remain locally unsynced while pendingChangesForTarget()
    // sees no ready row, so the Client stays at an older ACK sequence forever.
    await store.recoverSubmittedSyncQueue(target: UnifiedSyncQueueTarget.host);
    await store.recoverStaleInProgressSyncQueue(
        target: UnifiedSyncQueueTarget.host);
    await store.retryFailedSyncQueue(target: UnifiedSyncQueueTarget.host);
    final identity = store.appIdentity;
    final pending =
        _syncCore.pendingChangesForTarget(UnifiedSyncQueueTarget.host);
    if (pending.isEmpty) return true;
    final pendingIds = _syncCore.changeIds(pending);
    final latestSequence = store.latestStoredAuthoritativeSequence;
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] directRelay:hostBroadcastStart '
      'pending=${pending.length} latestSequence=$latestSequence',
    );
    try {
      await _sendRealtimeBroadcast(
        settings,
        type: 'sync_changed',
        payload: {
          'changed': true,
          'latestSequence': latestSequence,
          'pendingRequests': pending.length,
          'deviceId': store.deviceId,
          'storeId': identity.storeId,
          'branchId': identity.branchId,
          'relayKind': 'host_publish',
        },
      );
      await _syncCore.markPushAcknowledged(pendingIds, fallbackIds: pendingIds);
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] directRelay:hostBroadcastDone '
        'published=${pending.length} latestSequence=$latestSequence',
      );
      return true;
    } catch (error) {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] directRelay:hostBroadcastFailed error=$error',
      );
      return false;
    }
  }
}
