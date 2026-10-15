part of 'direct_control_plane_service.dart';

extension DirectControlPlaneServiceSplitPart6 on DirectControlPlaneService {

  Future<DirectSyncResult?> _pullAuthoritativeChangesViaRelay(
    VpsControlPlaneSettings settings, {
    DateTime? minSnapshotUpdatedAt,
    DirectSyncProgressCallback? onProgress,
  }) async {
    final identity = store.appIdentity;
    if (identity.isHost) {
      return const DirectSyncResult(
          ok: true,
          message: 'Host devices do not pull authoritative Direct changes.',
          pulled: 0);
    }

    final baseLastAppliedSequence =
        SyncDeviceStateStore.lastAppliedSequenceForTransport(
            store.appIdentity, 'direct');
    if (baseLastAppliedSequence <= 0) return null;

    final initialCursor = settings.lastPullCursor;
    try {
      onProgress?.call(0.35, 'Pulling Direct changes through the relay...');
      final pullPayload = <String, dynamic>{
        'deviceId': store.deviceId,
        'storeId': identity.storeId,
        'branchId': identity.branchId,
        'sinceSequence': baseLastAppliedSequence,
        if (initialCursor != null) 'since': initialCursor.toIso8601String(),
        if (minSnapshotUpdatedAt != null)
          'minSnapshotUpdatedAt': minSnapshotUpdatedAt.toIso8601String(),
        'limit': 1000,
      };
      var response = await _sendRealtimeRequest(
        settings,
        requestKind: 'direct_client_pull',
        payload: pullPayload,
      );
      if (response['ok'] != true) {
        final errorMessage =
            (response['error'] ?? response['message'] ?? 'unknown error')
                .toString();
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] directRelayPull:serverRejected error=$errorMessage',
        );
        return DirectSyncResult(
          ok: false,
          message: 'Direct relay pull rejected by Host: $errorMessage',
        );
      }

      if (_syncCore.shouldHandlePulledSnapshotAsRepair(
        response,
        isClient: store.appIdentity.isClient,
      )) {
        final generation = _remoteHostSnapshotGeneration(response);
        final commandId = _remoteHostRestoreCommandId(response);
        if (_restoreCommandAlreadyExecuted('direct', commandId)) {
          final metadata = _syncCore.parsePullMetadata(response);
          final generatedAt = metadata.generatedAt;
          final generatedSequence = metadata.generatedSequence;
          await settings.copyWith(lastPullCursor: generatedAt).save();
          await _recordDeviceSyncState('direct', generatedAt,
              sequence: generatedSequence, settings: settings);
          return DirectSyncResult(
            ok: true,
            message:
                'A previously executed rebuild command was ignored and the sync cursor was updated.',
            pulled: 0,
          );
        }
        return rebuildFromDirectHostSnapshot(
          settings.copyWith(clearLastPullCursor: true),
          onProgress: onProgress,
          requestFreshSnapshot: false,
          expectedSnapshotGeneration: generation,
          expectedRestoreCommandId: commandId,
        );
      }

      var rawChanges =
          response['changes'] as List<dynamic>? ?? const <dynamic>[];
      var latestSequence = int.tryParse(
            (response['latestSequence'] ?? response['generatedSequence'] ?? 0)
                .toString(),
          ) ??
          0;
      // A Host can be finishing the same write that triggered the relay
      // notification. Retry once when the Host advertises a newer sequence but
      // the first pull frame is empty. This keeps the Direct path deterministic
      // without storing the event on the server.
      if (rawChanges.isEmpty &&
          latestSequence > baseLastAppliedSequence &&
          response['needsSnapshot'] != true) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        final retry = await _sendRealtimeRequest(
          settings,
          requestKind: 'direct_client_pull',
          payload: pullPayload,
        );
        if (retry['ok'] == true) {
          response = retry;
          rawChanges =
              response['changes'] as List<dynamic>? ?? const <dynamic>[];
          latestSequence = int.tryParse(
                (response['latestSequence'] ??
                        response['generatedSequence'] ??
                        0)
                    .toString(),
              ) ??
              0;
        }
      }
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] directRelayPull:decoded source=${response['source']} '
        'changes=${rawChanges.length} '
        'requestedSince=$baseLastAppliedSequence latestSequence=$latestSequence '
        'needsSnapshot=${response['needsSnapshot'] == true} '
        'generatedAt=${response['generatedAt']} '
        'generatedSequence=${response['generatedSequence']}',
      );
      if (rawChanges.isEmpty &&
          latestSequence > baseLastAppliedSequence &&
          response['needsSnapshot'] != true) {
        return DirectSyncResult(
          ok: false,
          message:
              'Direct relay reported Host sequence $latestSequence, but returned no changes. Snapshot repair is required.',
        );
      }
      for (final raw in rawChanges.take(40)) {
        final change =
            SyncChange.fromJson(Map<String, dynamic>.from(raw as Map));
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] directRelayPull:rawChange ${SyncDiagnosticsLog.summarizeChange(change)}',
        );
      }

      final changes = _syncCore.normalizePulledChanges(rawChanges);

      final metadata = _syncCore.parsePullMetadata(response);
      final source = metadata.source;
      final restoredSnapshot =
          changes.any((item) => item.operation == 'restore_snapshot') ||
              (initialCursor == null &&
                  source == 'entity_snapshots' &&
                  changes.isNotEmpty);

      onProgress?.call(
          0.72, 'Applying ${changes.length} Direct change(s) from relay...');
      final applied = await _syncCore.applyAuthoritativeChanges(changes);

      final finalPullCursor = metadata.generatedAt;
      final finalPullSequence = metadata.generatedSequence;
      await _recordDeviceSyncState('direct', finalPullCursor,
          sequence: finalPullSequence, settings: settings);

      // Direct notifications are only a wake-up optimization. The actual
      // delivery contract is Client pull -> apply -> ACK, just like LAN. The
      // Host must learn about the sequence after the Client has successfully
      // applied it so history retention and peer progress are based on a real
      // pull, not on the transient sync_changed notification.
      try {
        await _sendRealtimeRequest(
          settings,
          requestKind: 'direct_client_ack',
          payload: {
            'deviceId': store.deviceId,
            'storeId': identity.storeId,
            'branchId': identity.branchId,
            'appliedSequence': finalPullSequence,
            'ackSequence': finalPullSequence,
            'appliedCursor': finalPullCursor.toIso8601String(),
            'ackCursor': finalPullCursor.toIso8601String(),
          },
        );
      } catch (error) {
        // Applying the pulled data already succeeded. A transient ACK failure
        // must not turn a successful pull into a snapshot-repair request; the
        // next periodic pull will retry the ACK with the same sequence.
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] directRelayPull:ackFailed '
          'sequence=$finalPullSequence error=$error',
        );
      }

      if (applied > 0) {
        onProgress?.call(0.92, 'Cleaning up after Direct sync...');
        await store.cleanupSoftDeletedRecords();
      }
      if (store.appIdentity.isClient &&
          (restoredSnapshot || applied > 0) &&
          !store.needsInitialAdminSetup) {
        await DirectProvisioningStatus.markComplete(
            message: 'Initial Store data downloaded.');
      }
      return DirectSyncResult(
        ok: true,
        pulled: applied,
        restoredSnapshot: restoredSnapshot,
        message:
            'Direct relay pull completed. Pulled $applied authoritative change(s).',
      );
    } catch (error) {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] directRelayPull:error $error',
      );
      return DirectSyncResult(
        ok: false,
        message: 'Direct relay pull failed: $error',
      );
    }
  }

  Future<DirectSyncResult> pushPendingForUnifiedEngine(
      VpsControlPlaneSettings settings,
      {DirectSyncProgressCallback? onProgress}) async {
    final identity = store.appIdentity;
    if (!_directAllowedForIdentity(identity)) {
      return const DirectSyncResult(
          ok: false,
          message:
              'Direct is not the active/configured sync transport for this device.');
    }
    if (!settings.isConfigured) {
      return const DirectSyncResult(
          ok: false, message: 'Direct API URL and token are required.');
    }

    try {
      var pushed = 0;

      if (identity.isHost) {
        final relayReady = await ensureHostRelayReady(settings);
        if (!relayReady.ok) return relayReady;
        onProgress?.call(0.25, 'Sending Host heartbeat...');
        await sendHostHeartbeat(settings);
        onProgress?.call(0.40, 'Registering Host device...');
        await registerCurrentDevice(settings, transport: 'direct');
        final hostPendingCount = _syncCore
            .pendingChangesForTarget(UnifiedSyncQueueTarget.host)
            .length;
        onProgress?.call(
            0.55, 'Publishing Host changes through Direct relay...');
        final relayPublished = await _broadcastHostAuthorityViaRelay(settings);
        if (!relayPublished) {
          return const DirectSyncResult(
            ok: false,
            message:
                'Host direct relay failed. Legacy Direct fallback is disabled; retry when the relay is available.',
          );
        }
        pushed = hostPendingCount;
        return DirectSyncResult(
          ok: true,
          pushed: pushed,
          message:
              'Host direct relay completed. Broadcast $pushed authoritative change(s).',
        );
      }

      onProgress?.call(0.12, 'Registering Client device...');
      await registerCurrentDevice(settings, transport: 'direct');
      onProgress?.call(0.22, 'Sending Client requests to Host relay...');
      pushed += await _pushPendingViaRelay(settings,
          target: UnifiedSyncQueueTarget.host);
      return DirectSyncResult(
          ok: true,
          pushed: pushed,
          message:
              'Client direct push completed. Sent $pushed request(s) to Host relay and received Host ACK.');
    } catch (error) {
      return DirectSyncResult(ok: false, message: 'Direct push failed: $error');
    }
  }

  Future<DirectSyncResult> pullAuthoritativeChangesForUnifiedEngine(
    VpsControlPlaneSettings settings, {
    DateTime? minSnapshotUpdatedAt,
    DirectSyncProgressCallback? onProgress,
  }) async {
    final identity = store.appIdentity;
    if (identity.isHost) {
      return const DirectSyncResult(
          ok: true,
          message: 'Host devices do not pull authoritative Direct changes.',
          pulled: 0);
    }
    if (!_directAllowedForIdentity(identity)) {
      return const DirectSyncResult(
          ok: false,
          message:
              'Direct is not the active/configured sync transport for this device.');
    }
    if (!settings.isConfigured) {
      return const DirectSyncResult(
          ok: false, message: 'Direct API URL and token are required.');
    }

    final drain = await _directClientNeedsDrainResult();
    if (drain != null) return drain;

    try {
      return _runDirectClientAuthoritativeSync(
        settings,
        minSnapshotUpdatedAt: minSnapshotUpdatedAt,
        onProgress: onProgress,
      );
    } catch (error) {
      return DirectSyncResult(ok: false, message: 'Direct pull failed: $error');
    }
  }

  Future<DirectSyncResult> syncNow(VpsControlPlaneSettings settings,
      {DateTime? minSnapshotUpdatedAt,
      DirectSyncProgressCallback? onProgress}) async {
    final identity = store.appIdentity;
    if (!_directAllowedForIdentity(identity)) {
      return const DirectSyncResult(
          ok: false,
          message:
              'Direct is not the active/configured sync transport for this device.');
    }
    if (!settings.isConfigured) {
      return const DirectSyncResult(
          ok: false, message: 'Direct API URL and token are required.');
    }
    final accessResult = await checkCurrentDeviceAccess(settings);
    if (accessResult != null) return accessResult;

    try {
      var pushed = 0;

      if (identity.isHost) {
        final hostResult = await _runDirectHostRelaySync(
          settings,
          onProgress: onProgress,
          compactHistory: true,
        );
        return hostResult;
      }

      // Direct follows the same business rules as LAN. The only difference is
      // that the connection to the Host goes through the external gateway.
      final clientPush =
          await _runDirectClientRelayPush(settings, onProgress: onProgress);
      pushed += clientPush.pushed;

      final relayResult = await _runDirectClientAuthoritativeSync(
        settings,
        minSnapshotUpdatedAt: minSnapshotUpdatedAt,
        onProgress: onProgress,
      );
      return DirectSyncResult(
        ok: relayResult.ok,
        pushed: pushed + relayResult.pushed,
        pulled: relayResult.pulled,
        restoredSnapshot: relayResult.restoredSnapshot,
        syncDeferred: relayResult.syncDeferred,
        message: relayResult.message,
      );
    } catch (error) {
      return DirectSyncResult(ok: false, message: 'Direct sync failed: $error');
    }
  }
}
