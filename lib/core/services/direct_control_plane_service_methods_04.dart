part of 'direct_control_plane_service.dart';

extension DirectControlPlaneServiceSplitPart4 on DirectControlPlaneService {

  Future<DirectRealtimeSignal?> _handleRealtimePacket(
    VpsControlPlaneSettings settings,
    WebSocketChannel channel,
    Map<String, dynamic> decoded,
  ) async {
    final identity = store.appIdentity;
    final type = (decoded['type'] ?? '').toString();
    if (type == 'realtime_welcome') return null;

    if (identity.isHost && type == 'relay_request') {
      final requestId = (decoded['requestId'] ?? decoded['request_id'] ?? '')
          .toString()
          .trim();
      final requestKind = (decoded['requestKind'] ??
              decoded['request_kind'] ??
              decoded['kind'] ??
              '')
          .toString()
          .trim();
      // The relay routes Host responses back to the requesting Client by
      // sourceDeviceId. The incoming relay request already carries the
      // Client identity; every Host response must preserve it.
      final sourceDeviceId =
          (decoded['sourceDeviceId'] ?? decoded['source_device_id'] ?? '')
              .toString()
              .trim();
      if (requestId.isEmpty) return null;

      if (requestKind == 'direct_snapshot_manifest') {
        final snapshotKind =
            (decoded['snapshotKind'] ?? decoded['snapshot_kind'] ?? '')
                .toString()
                .trim();
        final rebuildRequestId = (decoded['rebuildRequestId'] ??
                decoded['rebuild_request_id'] ??
                decoded['snapshotRequestId'] ??
                decoded['snapshot_request_id'] ??
                '')
            .toString()
            .trim();
        final requiredMinSequence = int.tryParse(
                (decoded['requiredMinSequence'] ??
                        decoded['required_min_sequence'] ??
                        0)
                    .toString()) ??
            0;
        final job = await _buildRelaySnapshotJob(
          snapshotKind,
          rebuildRequestId: rebuildRequestId,
          requiredMinSequence: requiredMinSequence,
        );
        if (job == null) {
          channel.sink.add(jsonEncode({
            'type': 'relay_response',
            'requestId': requestId,
            'sourceDeviceId': sourceDeviceId,
            'ok': false,
            'error': 'Host snapshot could not be prepared.',
            'serverTime': DateTime.now().toIso8601String(),
          }));
          return null;
        }
        final generatedSequence = int.tryParse(
                (job.envelope['syncGeneratedSequence'] ?? 0).toString()) ??
            0;
        if (requiredMinSequence > 0 &&
            generatedSequence < requiredMinSequence) {
          _releaseRelaySnapshotJob(job.jobId);
          channel.sink.add(jsonEncode({
            'type': 'relay_response',
            'requestId': requestId,
            'sourceDeviceId': sourceDeviceId,
            'ok': false,
            'error':
                'Host snapshot is older than the confirmed Client changes. Retry after Host finishes applying requests.',
            'serverTime': DateTime.now().toIso8601String(),
          }));
          return null;
        }
        channel.sink.add(jsonEncode({
          'type': 'relay_response',
          'requestId': requestId,
          'sourceDeviceId': sourceDeviceId,
          'ok': true,
          'jobId': job.jobId,
          'snapshotFormat': job.envelope['snapshotFormat'],
          'snapshotVersion': job.envelope['snapshotVersion'],
          'snapshotKind': job.envelope['snapshotKind'],
          'snapshotManifest': job.envelope['snapshotManifest'],
          'totalChunks': job.chunks.length,
          'syncGeneratedAt': job.envelope['syncGeneratedAt'],
          'syncGeneratedSequence': job.envelope['syncGeneratedSequence'],
          'hostSnapshotGeneration': job.envelope['hostSnapshotGeneration'],
          'snapshotGeneration': job.envelope['snapshotGeneration'],
          'hostRestoreCommandId': job.envelope['hostRestoreCommandId'],
          'restoreCommandId': job.envelope['restoreCommandId'],
          'rebuildRequestId': job.envelope['rebuildRequestId'],
          'snapshotRequestId': job.envelope['snapshotRequestId'],
          'requiredMinSequence': job.envelope['requiredMinSequence'],
          'freshRebuildSnapshot': job.envelope['freshRebuildSnapshot'],
          'serverTime': DateTime.now().toIso8601String(),
        }));
        return null;
      }

      if (requestKind == 'direct_snapshot_chunk') {
        final jobId =
            (decoded['jobId'] ?? decoded['job_id'] ?? '').toString().trim();
        final ordinal = int.tryParse(
                (decoded['ordinal'] ?? decoded['chunkOrdinal'] ?? 0)
                    .toString()) ??
            0;
        final job = _relaySnapshotJob(jobId);
        if (job == null || ordinal < 0 || ordinal >= job.chunks.length) {
          channel.sink.add(jsonEncode({
            'type': 'relay_response',
            'requestId': requestId,
            'sourceDeviceId': sourceDeviceId,
            'ok': false,
            'error': 'Snapshot chunk is unavailable.',
            'serverTime': DateTime.now().toIso8601String(),
          }));
          return null;
        }
        channel.sink.add(jsonEncode({
          'type': 'relay_response',
          'requestId': requestId,
          'sourceDeviceId': sourceDeviceId,
          'ok': true,
          'jobId': job.jobId,
          'ordinal': ordinal,
          'totalChunks': job.chunks.length,
          'chunk': job.chunks[ordinal],
          'serverTime': DateTime.now().toIso8601String(),
        }));
        return null;
      }

      if (requestKind == 'direct_snapshot_release') {
        final jobId =
            (decoded['jobId'] ?? decoded['job_id'] ?? '').toString().trim();
        _releaseRelaySnapshotJob(jobId);
        channel.sink.add(jsonEncode({
          'type': 'relay_response',
          'requestId': requestId,
          'sourceDeviceId': sourceDeviceId,
          'ok': true,
          'released': true,
          'serverTime': DateTime.now().toIso8601String(),
        }));
        return null;
      }

      if (requestKind == 'direct_client_push') {
        final rawChanges =
            decoded['changes'] as List<dynamic>? ?? const <dynamic>[];
        final clientDeviceId =
            (decoded['deviceId'] ?? sourceDeviceId).toString().trim();
        final clientSequence = int.tryParse(
                (decoded['lastAppliedSequence'] ?? decoded['sequence'] ?? 0)
                    .toString()) ??
            0;
        final changes = _syncCore.filterOutLocalEchoes(
          _syncCore.decodeRemoteChanges(rawChanges),
        );
        final accepted = await _syncCore.acceptClientChangesOnHost(
          changes,
          // Direct is a transport relay only. Once the Host accepts a Client
          // draft, enqueue the new Host-authoritative event for the normal
          // Direct publish path just like LAN does for a Direct-enabled Host.
          // The relay ACK alone only confirms receipt of the draft; it must
          // not be the point at which the Client considers the change final.
          mirrorToDirect: true,
          verifyApplied: true,
        );
        // Publish the newly restamped Host-authoritative events immediately.
        // Waiting for the next periodic Host tick leaves the Client with an
        // ACK for its draft but no prompt to pull the authoritative event.
        // The relay still carries only the notification; the event data stays
        // on the Host and is fetched by the Client in direct_client_pull.
        if (accepted.accepted.isNotEmpty) {
          final published = await _broadcastHostAuthorityViaRelay(settings);
          if (!published) {
            SyncDiagnosticsLog.add(
              '[SYNC_TRACE] directRelay:acceptedClientChangesPublishFailed '
              'accepted=${accepted.accepted.length}',
            );
          }
        }
        // Keep Direct peer progress consistent with LAN. The sequence here is
        // the Client's last applied Host sequence, so it records what the
        // Client has confirmed without pretending that the just-pushed draft
        // is authoritative before the Client pulls it back from the Host.
        if (clientDeviceId.isNotEmpty) {
          await SyncDeviceStateStore.recordPeerSyncResult(
            deviceId: clientDeviceId,
            transport: 'direct',
            appliedSequence: clientSequence,
            ackSequence: clientSequence,
          );
        }
        final response = <String, dynamic>{
          'type': 'relay_response',
          'requestId': requestId,
          'sourceDeviceId': sourceDeviceId,
          'ok': true,
          'ackIds': accepted.ackIds,
          'rejected': accepted.rejected.entries
              .map((entry) => {'id': entry.key, 'reason': entry.value})
              .toList(),
          'latestSequence': store.latestStoredAuthoritativeSequence,
          'serverTime': DateTime.now().toIso8601String(),
        };
        channel.sink.add(jsonEncode(response));
        channel.sink.add(jsonEncode({
          'type': 'sync_changed',
          'changed': true,
          'latestSequence': store.latestStoredAuthoritativeSequence,
          'pendingRequests': 0,
          'relayKind': 'direct_client_push',
        }));
        return null;
      }

      if (requestKind == 'direct_client_pull') {
        final sinceSequence = int.tryParse(
                (decoded['sinceSequence'] ?? decoded['since_sequence'] ?? 0)
                    .toString()) ??
            0;
        final since = DateTime.tryParse(
            (decoded['since'] ?? decoded['sinceAt'] ?? '').toString());
        final minSnapshotUpdatedAt = DateTime.tryParse(
            (decoded['minSnapshotUpdatedAt'] ??
                    decoded['min_snapshot_updated_at'] ??
                    '')
                .toString());
        if (sinceSequence <= 0 && since == null) {
          channel.sink.add(jsonEncode({
            'type': 'relay_response',
            'requestId': requestId,
            'ok': false,
            'error':
                'A relay pull requires a direct sequence baseline. Use the snapshot path first.',
            'serverTime': DateTime.now().toIso8601String(),
          }));
          return null;
        }
        final response = Map<String, dynamic>.from(
          jsonDecode(
            store.exportSyncChangesJson(
              since: since,
              sinceSequence: sinceSequence,
            ),
          ) as Map,
        );
        response['type'] = 'relay_response';
        response['requestId'] = requestId;
        response['sourceDeviceId'] = sourceDeviceId;
        response['ok'] = true;
        response['source'] = 'relay';
        response['hasMore'] = false;
        response['nextCursor'] = null;
        response['serverTime'] = DateTime.now().toIso8601String();
        if (minSnapshotUpdatedAt != null) {
          response['minSnapshotUpdatedAt'] =
              minSnapshotUpdatedAt.toIso8601String();
        }
        channel.sink.add(jsonEncode(response));
        return null;
      }

      if (requestKind == 'direct_client_ack') {
        final clientDeviceId =
            (decoded['deviceId'] ?? sourceDeviceId).toString().trim();
        final appliedSequence = int.tryParse(
                (decoded['appliedSequence'] ?? decoded['applied_sequence'] ?? 0)
                    .toString()) ??
            0;
        final ackSequence = int.tryParse(
                (decoded['ackSequence'] ?? decoded['ack_sequence'] ?? 0)
                    .toString()) ??
            appliedSequence;
        final appliedCursor = DateTime.tryParse(
            (decoded['appliedCursor'] ?? decoded['applied_cursor'] ?? '')
                .toString());
        final ackCursor = DateTime.tryParse(
            (decoded['ackCursor'] ?? decoded['ack_cursor'] ?? '').toString());

        if (clientDeviceId.isNotEmpty) {
          await SyncDeviceStateStore.recordPeerSyncResult(
            deviceId: clientDeviceId,
            transport: 'direct',
            appliedSequence: appliedSequence,
            ackSequence: ackSequence,
            appliedCursor: appliedCursor,
            ackCursor: ackCursor,
          );
          await store.settleHostQueueThroughPeerAck();
          await store.compactSyncedSyncHistoryForMaintenance();
        }
        channel.sink.add(jsonEncode({
          'type': 'relay_response',
          'requestId': requestId,
          'sourceDeviceId': sourceDeviceId,
          'ok': true,
          'appliedSequence': appliedSequence,
          'ackSequence': ackSequence,
          'serverTime': DateTime.now().toIso8601String(),
        }));
        return null;
      }

      channel.sink.add(jsonEncode({
        'type': 'relay_response',
        'requestId': requestId,
        'sourceDeviceId': sourceDeviceId,
        'ok': false,
        'error': 'Unknown relay request kind: $requestKind',
        'serverTime': DateTime.now().toIso8601String(),
      }));
      return null;
    }

    final changed = decoded['changed'] == true;
    if (!changed) return null;
    final latestSequence =
        int.tryParse((decoded['latestSequence'] ?? '0').toString()) ?? 0;
    final pendingRequests =
        int.tryParse((decoded['pendingRequests'] ?? '0').toString()) ?? 0;
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] directRealtime:event type=$type '
      'latestSequence=$latestSequence pendingRequests=$pendingRequests',
    );
    return DirectRealtimeSignal(
      type: type,
      latestSequence: latestSequence,
      pendingRequests: pendingRequests,
    );
  }

  Future<void> _confirmDirectWipe(
    VpsControlPlaneSettings settings, {
    required String storeId,
    required String branchId,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      await _client
          .post(
            settings.endpoint('/api/sync/device-wipe-ack'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (store.appIdentity.isHost &&
                  settings.accountToken.trim().isNotEmpty)
                'Authorization': 'Bearer ${settings.accountToken.trim()}',
              'X-Device-Id': deviceId,
              'X-Device-Token': deviceToken,
              'X-Device-Role': 'client',
              'X-Sync-Transport': 'direct',
              'X-Store-Id': storeId,
              'X-Branch-Id': branchId,
            },
            body: jsonEncode({
              'storeId': storeId,
              'branchId': branchId,
              'deviceId': deviceId,
              'deviceToken': deviceToken,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Keep wipe_pending on Direct when confirmation cannot be delivered.
      // The next contact will receive the wipe command again.
    }
  }

  Future<DirectSyncResult> registerCurrentDevice(
      VpsControlPlaneSettings settings,
      {String transport = 'direct'}) async {
    final identity = store.appIdentity;
    if (!settings.isConfigured) {
      return const DirectSyncResult(
          ok: false, message: 'Direct API URL and token are required.');
    }
    final deviceState = SyncDeviceStateStore.load(identity);
    final lastAppliedCursor =
        SyncDeviceStateStore.lastAppliedCursorForTransport(identity, transport);
    final lastAckCursor =
        SyncDeviceStateStore.lastAckCursorForTransport(identity, transport);
    final lastAppliedSequence =
        SyncDeviceStateStore.lastAppliedSequenceForTransport(
            identity, transport);
    final lastAckSequence =
        SyncDeviceStateStore.lastAckSequenceForTransport(identity, transport);
    final appliedSnapshotGeneration =
        LocalDatabaseService.getString(_snapshotGenerationKey(transport)) ?? '';
    if (identity.isClient &&
        transport == 'direct' &&
        lastAppliedSequence <= 0 &&
        lastAckSequence <= 0 &&
        (lastAppliedCursor != null ||
            appliedSnapshotGeneration.trim().isNotEmpty)) {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] directRegister:skipZeroAckPublish '
        'device=${identity.deviceId} appliedGeneration=$appliedSnapshotGeneration',
      );
      return const DirectSyncResult(
        ok: true,
        syncDeferred: true,
        message:
            'Client heartbeat skipped because local Direct ACK is zero without a newly applied snapshot.',
      );
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/devices'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'deviceId': store.deviceId,
              'deviceName': identity.deviceName,
              'platform': identity.platform.name,
              'role': identity.deviceRole.name,
              'transport': transport,
              'activeTransport': identity.activeSyncTransportNormalized,
              'lastSyncTransport': deviceState.lastSyncTransport.isEmpty
                  ? transport
                  : deviceState.lastSyncTransport,
              'lastAppliedCursor': lastAppliedCursor?.toIso8601String(),
              'lastAckCursor': lastAckCursor?.toIso8601String(),
              'lastAppliedSequence': lastAppliedSequence,
              'lastAckSequence': lastAckSequence,
              'deviceToken': identity.deviceToken,
              'hostDeviceId': identity.hostDeviceId,
              'appVersion': AppBrand.directAppVersion,
              'storeEpoch': identity.storeEpoch,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return DirectSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? 'Device heartbeat updated.'
            : 'Device heartbeat failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return DirectSyncResult(
          ok: false, message: 'Device heartbeat failed: $error');
    }
  }

  Future<DirectSyncResult> requestHostTransfer(VpsControlPlaneSettings settings,
      {String reason = ''}) async {
    final identity = store.appIdentity;
    if (!UnifiedSyncPolicy.canRequestDirectHostTransfer(identity)) {
      return const DirectSyncResult(
          ok: false, message: 'Only Clients can request Host transfer.');
    }
    if (settings.apiBaseUrl.trim().isEmpty) {
      return const DirectSyncResult(
          ok: false, message: 'Direct API URL is required.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/host-transfer/request'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'requestingDeviceId': store.deviceId,
              'currentHostDeviceId': identity.hostDeviceId,
              'reason': reason,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return DirectSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? 'Host transfer request sent.'
            : 'Host transfer request failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return DirectSyncResult(
          ok: false, message: 'Host transfer request failed: $error');
    }
  }

  Future<DirectSyncResult> approveHostTransfer(
      VpsControlPlaneSettings settings, String requestingDeviceId) async {
    final identity = store.appIdentity;
    if (!UnifiedSyncPolicy.canApproveDirectHostTransfer(identity)) {
      return const DirectSyncResult(
          ok: false, message: 'Only Hosts can approve Host transfer.');
    }
    if (!settings.isConfigured) {
      return const DirectSyncResult(
          ok: false, message: 'Direct API URL and token are required.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/host-transfer/approve'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'requestingDeviceId': requestingDeviceId,
              'approvedByHostDeviceId': store.deviceId,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return DirectSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? 'Host transfer approved in Direct.'
            : 'Host transfer approval failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return DirectSyncResult(
          ok: false, message: 'Host transfer approval failed: $error');
    }
  }

  Future<DirectSyncResult> activateHostTransfer(
      VpsControlPlaneSettings settings) async {
    final identity = store.appIdentity;
    if (!settings.isConfigured && settings.apiBaseUrl.trim().isEmpty) {
      return const DirectSyncResult(
          ok: false, message: 'Direct API URL is required.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/host-transfer/activate'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'newHostDeviceId': store.deviceId,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return DirectSyncResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? 'Host transfer activated in Direct.'
            : 'Host transfer activation failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      return DirectSyncResult(
          ok: false, message: 'Host transfer activation failed: $error');
    }
  }

  Future<List<DirectDeviceStatus>> listDevices(
      VpsControlPlaneSettings settings) async {
    final result = await listDevicesWithLimit(settings);
    return result.devices;
  }

  Future<DirectDevicesResult> listDevicesWithLimit(
    VpsControlPlaneSettings settings, {
    String? storeIdOverride,
    String? branchIdOverride,
  }) async {
    final identity = store.appIdentity;
    if (!settings.isConfigured) {
      return const DirectDevicesResult(devices: <DirectDeviceStatus>[]);
    }
    final storeId = (storeIdOverride ?? identity.storeId).trim();
    final branchId = (branchIdOverride ?? identity.branchId).trim();
    if (storeId.isEmpty) {
      return const DirectDevicesResult(devices: <DirectDeviceStatus>[]);
    }
    // The regular service client is intentionally retired for legacy Direct
    // sync calls, but the monitoring page still needs the live device registry.
    // Use a short-lived real HTTP client so Direct-linked devices are visible.
    final client = http.Client();
    try {
      final response = await client
          .get(
            settings.endpoint('/api/sync/devices', {
              'store_id': storeId,
              'branch_id': branchId.isEmpty ? 'main' : branchId,
            }),
            headers: _headers(settings, includeAccountTokenForClient: true),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const DirectDevicesResult(devices: <DirectDeviceStatus>[]);
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final devices = (decoded['devices'] as List<dynamic>? ?? [])
          .map((item) => DirectDeviceStatus.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList();
      final limitRaw = decoded['deviceLimit'] ?? decoded['device_limit'];
      final limit = limitRaw is Map
          ? DirectDeviceLimitStatus.fromJson(
              Map<String, dynamic>.from(limitRaw))
          : null;
      final directSyncEnabled = decoded['directSyncEnabled'] == true
          ? true
          : decoded.containsKey('directSyncEnabled')
              ? false
              : null;
      return DirectDevicesResult(
        devices: devices,
        limit: limit,
        directSyncEnabled: directSyncEnabled,
      );
    } finally {
      client.close();
    }
  }

  Future<DirectSyncResult> repairLegacyDirectDeviceLinks(
    VpsControlPlaneSettings settings, {
    required Iterable<String> clientDeviceIds,
  }) async {
    final identity = store.appIdentity;
    if (!UnifiedSyncPolicy.canRepairDirectDeviceLinks(identity)) {
      return const DirectSyncResult(
          ok: false, message: 'Only the Host can repair Direct device links.');
    }
    if (!settings.isConfigured) {
      return const DirectSyncResult(
          ok: false, message: 'Direct API URL and token are required.');
    }
    final cleanClientIds = clientDeviceIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && id != store.deviceId)
        .toSet()
        .toList();
    if (cleanClientIds.isEmpty) {
      return const DirectSyncResult(
          ok: true, message: 'No legacy Direct device links need repair.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/devices/repair-host-links'),
            headers: _headers(settings),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'hostDeviceId': store.deviceId,
              'clientDeviceIds': cleanClientIds,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return DirectSyncResult(
            ok: false,
            message:
                'Direct device link repair failed: ${response.statusCode} ${response.body}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final repaired = int.tryParse('${decoded['repaired'] ?? 0}') ?? 0;
      final checked =
          int.tryParse('${decoded['checked'] ?? cleanClientIds.length}') ??
              cleanClientIds.length;
      return DirectSyncResult(
          ok: decoded['ok'] == true,
          message:
              'Direct device links checked: $checked, repaired: $repaired.');
    } catch (error) {
      return DirectSyncResult(
          ok: false, message: 'Direct device link repair failed: $error');
    }
  }
}
