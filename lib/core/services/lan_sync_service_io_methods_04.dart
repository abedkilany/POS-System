part of 'lan_sync_service_io.dart';

extension LanSyncServiceSplitPart4 on LanSyncService {

  Future<LanSyncResult> syncNow(String host,
      {int port = 8787,
      String token = '',
      LanSyncProgressCallback? onProgress}) async {
    final settings = LanSyncSettings.load();
    final pending =
        _syncCore.pendingChangesForTarget(UnifiedSyncQueueTarget.host);

    // New Client bootstrap must use the Host snapshot, not the incremental
    // event stream. A Host can have valid products/customers/sales that were
    // created before LAN sync was enabled or imported from backup, so pulling
    // only /changes/pull on a fresh cursor can legitimately return zero events
    // and leave the Client empty.
    if (settings.isClient &&
        settings.lastPullCursor == null &&
        pending.isEmpty) {
      return initialClone(host,
          port: port, token: token, onProgress: onProgress);
    }

    final pendingIds = _syncCore.changeIds(pending);
    var pushCompleted = pending.isEmpty;
    try {
      final client = _client();

      if (pending.isNotEmpty) {
        onProgress?.call(0.18,
            'Preparing ${pending.length} local change(s) for LAN push...');
        await _syncCore.markPushInProgress(pendingIds);
        onProgress?.call(0.32, 'Uploading local changes to Host...');
        final pushRequest =
            await client.post(host.trim(), port, '/changes/push');
        _attachToken(pushRequest, token);
        pushRequest.headers.contentType = ContentType.json;
        pushRequest.write(jsonEncode({
          'deviceId': store.sync.deviceId,
          'storeId': store.runtime.identity.storeId,
          'branchId': store.runtime.identity.branchId,
          'deviceName': store.runtime.identity.deviceName,
          'cursor': settings.lastPullCursor?.toIso8601String(),
          'changes': pending.map((item) => item.toJson()).toList(),
        }));
        final pushResponse = await pushRequest.close();
        final pushBody = await utf8.decoder.bind(pushResponse).join();
        if (pushResponse.statusCode != 200) {
          client.close(force: true);
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
        onProgress?.call(
            0.48, 'Host accepted ${ackIds.length} pushed change(s)...');
        await _syncCore.markPushAcknowledged(ackIds);
        pushCompleted = true;
      }

      final ackCursor = settings.lastPullCursor?.toIso8601String() ?? '';
      final lastSequence = SyncDeviceStateStore.lastAppliedSequenceForTransport(
          store.runtime.identity, 'lan');
      final seqParam = '&since_sequence=$lastSequence';
      final path = settings.lastPullCursor == null
          ? '/changes/pull?device_id=${Uri.encodeQueryComponent(store.sync.deviceId)}&ack_cursor=${Uri.encodeQueryComponent(ackCursor)}$seqParam'
          : '/changes/pull?device_id=${Uri.encodeQueryComponent(store.sync.deviceId)}&ack_cursor=${Uri.encodeQueryComponent(ackCursor)}&since=${Uri.encodeQueryComponent(settings.lastPullCursor!.toIso8601String())}$seqParam';
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
        final message =
            'Pull changes failed: ${pullResponse.statusCode} $pullBody';
        if (pendingIds.isNotEmpty && !pushCompleted) {
          await _syncCore.markPushFailed(pendingIds, message);
        }
        return LanSyncResult(ok: false, message: message);
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
        isClient: store.runtime.identity.isClient,
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
        isClient: store.runtime.identity.isClient,
      )) {
        final commandId = _restoreCommandIdFromChanges(changes);
        if (_restoreCommandAlreadyExecuted('lan', commandId)) {
          onProgress?.call(0.72,
              'Host restore command already applied. Continuing LAN sync...');
        } else {
          onProgress?.call(0.72,
              'Host restore detected. Rebuilding from LAN Host snapshot...');
          await settings.copyWith(clearLastPullCursor: true).save();
          await SyncDeviceStateStore.resetClientProgress(store.runtime.identity,
              transport: 'lan');
          return repairFromHostSnapshot(host,
              port: port, token: token, onProgress: onProgress);
        }
      }
      onProgress?.call(
          0.78, 'Applying ${changes.length} LAN change(s) locally...');
      await _syncCore.applyAuthoritativeChanges(changes);
      final metadata = _syncCore.parsePullMetadata(decodedPull);
      final generatedAt = metadata.generatedAt;
      final generatedSequence = metadata.generatedSequence;
      onProgress?.call(0.92, 'Saving LAN sync cursor...');
      await _saveCursorAndRecordState(settings, generatedAt,
          sequence: generatedSequence);
      await _sendLanAck(host,
          port: port,
          token: token,
          cursor: generatedAt,
          sequence: generatedSequence);
      await store.runtime.clearSuspendedByHost();
      onProgress?.call(0.97, 'Running Client sync log maintenance...');
      await store.sync.compactClientSyncedHistoryForMaintenance();
      onProgress?.call(1.0, 'LAN sync completed.');
      return LanSyncResult(
        ok: true,
        message:
            'Sync completed. Pushed ${pending.length} change(s), pulled ${changes.length} change(s).',
      );
    } catch (error) {
      if (pendingIds.isNotEmpty && !pushCompleted) {
        await _syncCore.markPushFailed(pendingIds, error.toString());
      }
      return LanSyncResult(
          ok: false, message: _failureMessage('Sync failed', error));
    }
  }
}
