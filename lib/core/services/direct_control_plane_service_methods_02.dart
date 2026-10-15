part of 'direct_control_plane_service.dart';

extension DirectControlPlaneServiceSplitPart2 on DirectControlPlaneService {

  Future<DirectPairingClaimResult> claimPairingCode(
      VpsControlPlaneSettings settings, String code,
      {DirectSyncProgressCallback? onProgress,
      void Function(String message)? onDiagnostic}) async {
    final current = store.appIdentity;
    if (!UnifiedSyncPolicy.canClaimDirectPairingCode(current)) {
      return const DirectPairingClaimResult(
          ok: false,
          message:
              'Host devices cannot pair as Direct Clients. Use Host transfer instead.');
    }
    // A Client may configure both LAN and Direct, but only one active transport
    // should run at a time. Pairing Direct is therefore allowed for an existing
    // LAN Client as long as it is not a Host.
    // Client bootstrap pairing intentionally requires only the Direct API URL and
    // a single-use pairing code. Account sessions stay on Host devices.
    if (!settings.enabled || settings.apiBaseUrl.trim().isEmpty) {
      return const DirectPairingClaimResult(
          ok: false, message: 'Direct API URL is required.');
    }
    var deviceRegistered = false;
    final directIdentity = await DirectDeviceIdentity.loadOrCreate();
    onProgress?.call(0.08, 'Connecting to Direct pairing service...');
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/sync/pairing/claim'),
            headers: _headers(settings),
            body: jsonEncode({
              'code': code.trim(),
              'deviceId': store.deviceId,
              'deviceName': current.deviceName,
              'platform': current.platform.name,
              'appVersion': AppBrand.directAppVersion,
              'devicePublicKey': directIdentity.publicKeyEncoded,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        SyncDiagnosticsLog.add(
            '[DIRECT_PAIRING] claim http status=${response.statusCode}');
        return const DirectPairingClaimResult(
            ok: false,
            message:
                'Pairing code expired or already used. Ask the Host device for a new code.');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['ok'] != true) {
        final reason = (decoded['error'] ?? decoded['message'] ?? '')
            .toString()
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        SyncDiagnosticsLog.add(
            '[DIRECT_PAIRING] claim rejected reason=${reason.isEmpty ? 'unknown' : reason}');
        return const DirectPairingClaimResult(
            ok: false,
            message:
                'Pairing code expired or already used. Ask the Host device for a new code.');
      }
      final claim = UnifiedPairingClaimPayload(
        storeId: decoded['storeId']?.toString() ?? current.storeId,
        branchId: decoded['branchId']?.toString() ?? current.branchId,
        hostDeviceId:
            decoded['hostDeviceId']?.toString() ?? current.hostDeviceId,
        deviceToken: decoded['deviceToken']?.toString() ?? current.deviceToken,
        transport: decoded['transport']?.toString() ?? 'direct',
      );
      final mismatch = UnifiedPairingLifecycle.validateSameStoreClaim(
        current,
        claim,
      );
      if (mismatch != null) {
        return DirectPairingClaimResult(
          ok: false,
          message: mismatch,
        );
      }
      final claimedTransport =
          decoded['transport']?.toString().trim().toLowerCase() ?? 'direct';
      final isDirect = claimedTransport == 'direct';
      final hostPublicKey =
          decoded['hostDevicePublicKey']?.toString().trim() ?? '';
      if (isDirect && hostPublicKey.isNotEmpty) {
        final trusted = await DirectDeviceIdentity.verifyOrTrustPeer(
          deviceId: claim.hostDeviceId,
          publicKeyEncoded: hostPublicKey,
        );
        if (!trusted) {
          return const DirectPairingClaimResult(
            ok: false,
            message: 'The Host device identity changed unexpectedly.',
          );
        }
      }
      final transport = claimedTransport == 'lan'
          ? SyncMode.lanOnly
          : SyncMode.directConnected;
      final identity = UnifiedPairingLifecycle.buildClientIdentity(
        current,
        claim: claim,
        syncMode: transport,
        activeTransport: claimedTransport == 'lan'
            ? 'lan'
            : (isDirect ? 'direct' : 'direct'),
      );
      onProgress?.call(0.22, 'Registering this device...');
      await store.updateAppIdentityDuringSetup(identity);
      deviceRegistered = true;
      if (isDirect) {
        final existingDirect = DirectSyncSettings.load();
        await DirectSyncSettings(
          apiBaseUrl: settings.apiBaseUrl,
          peerDeviceId: claim.hostDeviceId,
          setupComplete: true,
          stunServer: existingDirect.stunServer,
          stunServers: existingDirect.stunServers,
          turnServers: existingDirect.turnServers,
          iceTransportPolicy: existingDirect.iceTransportPolicy,
          iceCandidatePoolSize: existingDirect.iceCandidatePoolSize,
        ).save();
      }

      if (!isDirect &&
          (identity.syncMode == SyncMode.directConnected ||
              identity.syncMode == SyncMode.marketplaceEnabled)) {
        // Phase 3: Connect to Store is not considered complete until the same
        // unified Snapshot used by LAN is fully downloaded, imported and
        // verified. Direct may still transfer through the server, but the
        // lifecycle is now identical to LAN: register -> snapshot chunks ->
        // import -> verify -> ready.
        final requestedAt = DateTime.now().toUtc();
        await DirectProvisioningStatus.markPending(
          requestedAt: requestedAt,
          message: 'Downloading full Store data before activating this device.',
        );

        DirectSyncResult request = const DirectSyncResult(
          ok: true,
          message: 'The latest available Direct snapshot will be used.',
        );

        final retryResult = await UnifiedDirectSnapshotRetryFlow.pollUntilReady<
            UnifiedPairingSnapshotSuccess>(
          // Pairing consumes the one-time code before the Host has necessarily
          // answered the snapshot request. Give the relay enough time to wake
          // the Host and build a large snapshot; otherwise the user is left
          // with a registered Client and a consumed code that cannot be used
          // for a second attempt.
          maxAttempts: 12,
          retryDelay: const Duration(seconds: 3),
          beforeAttempt: (attempt) async {
            if (attempt > 0) {
              onProgress?.call(0.28, 'Waiting for Host full snapshot...');
            }
            await DirectProvisioningStatus.markAttempted(
                DateTime.now().toUtc());
          },
          attempt: (attempt) async {
            final envelope = await _downloadDirectSnapshotEnvelope(
              settings.copyWith(clearLastPullCursor: true),
              force: attempt == 0,
              onProgress: (value, label) {
                final scaled =
                    (0.24 + value * 0.50).clamp(0.24, 0.74).toDouble();
                onProgress?.call(scaled, label);
              },
            );
            onProgress?.call(
                0.78, 'Importing Direct snapshot chunks locally...');
            final snapshotReceivedMessage =
                '[DIRECT_PAIRING] snapshot received attempt=$attempt '
                'format=${envelope['snapshotFormat']} '
                'version=${envelope['snapshotVersion']} '
                'storeId=${envelope['storeId'] ?? envelope['store_id'] ?? ''} '
                'branchId=${envelope['branchId'] ?? envelope['branch_id'] ?? ''} '
                'collections=${(envelope['collections'] as Map?)?.length ?? 0}';
            SyncDiagnosticsLog.add(snapshotReceivedMessage);
            onDiagnostic?.call(snapshotReceivedMessage);
            try {
              final applied = await UnifiedPairingSnapshotFlow.applyForDirect(
                store: store,
                envelope: envelope,
                markSnapshotApplied: () =>
                    _markHostSnapshotGenerationApplied('direct', envelope),
                markProvisioningComplete: () =>
                    DirectProvisioningStatus.markComplete(
                  message: 'Full Store data downloaded.',
                ),
              );
              final snapshotAppliedMessage =
                  '[DIRECT_PAIRING] snapshot applied attempt=$attempt '
                  'verificationOk=${applied.verificationOk} '
                  'verification=${applied.verificationMessage} '
                  'sequence=${applied.sequence} cursor=${applied.cursor.toIso8601String()}';
              SyncDiagnosticsLog.add(snapshotAppliedMessage);
              onDiagnostic?.call(snapshotAppliedMessage);
              return applied;
            } catch (error, stackTrace) {
              final snapshotFailureMessage =
                  '[DIRECT_PAIRING] snapshot apply failed attempt=$attempt '
                  'error=$error stack=${stackTrace.toString().split('\n').take(3).join(' | ')}';
              SyncDiagnosticsLog.add(snapshotFailureMessage);
              onDiagnostic?.call(snapshotFailureMessage);
              rethrow;
            }
          },
        );

        final applied = retryResult.value;
        if (applied != null) {
          onProgress?.call(0.88, 'Finalizing local store data...');
          onProgress?.call(0.94, 'Publishing this device sync state...');
          final registration =
              await registerCurrentDevice(settings, transport: 'direct');
          if (!registration.ok) {
            final registrationFailure =
                '[DIRECT_PAIRING] final device state publish failed '
                'sequence=${applied.sequence} message=${registration.message}';
            SyncDiagnosticsLog.add(registrationFailure);
            onDiagnostic?.call(registrationFailure);
            await DirectProvisioningStatus.markPending(
              requestedAt: requestedAt,
              message:
                  'Store data is installed, but the final Direct sync state is still pending.',
            );
            return DirectPairingClaimResult(
              ok: false,
              message:
                  'Store data was downloaded, but Direct could not confirm this device sync state. Keep the Host online and try again. ${registration.message}',
              identity: store.appIdentity,
            );
          }
          onProgress?.call(1.0, 'Direct snapshot is ready.');
          final successMessage = applied.verificationOk
              ? 'Device paired successfully. Full Store data downloaded. You can sign in now.'
              : 'Device paired successfully. Full Store data downloaded. You can sign in now. Verification warnings: ${applied.verificationMessage}';
          return DirectPairingClaimResult(
            ok: true,
            message: successMessage,
            identity: store.appIdentity,
          );
        }

        if (retryResult.lastFailure != null) {
          final failure = retryResult.lastFailure.toString();
          SyncDiagnosticsLog.add(
              '[DIRECT_PAIRING] all snapshot attempts failed lastFailure=$failure');
          onDiagnostic?.call(
              '[DIRECT_PAIRING] all snapshot attempts failed lastFailure=$failure');
          request = await requestFreshHostSnapshot(
            settings,
            requestedAt: requestedAt,
          );
          if (!request.ok) {
            await DirectProvisioningStatus.markPending(
              requestedAt: requestedAt,
              message: 'The full Store snapshot is not complete yet.',
            );
            return DirectPairingClaimResult(
              ok: false,
              message: '${request.message} Snapshot error: $failure',
              identity: store.appIdentity,
            );
          }
        }

        await DirectProvisioningStatus.markPending(
          requestedAt: requestedAt,
          message: 'The full Store snapshot is not complete yet.',
        );
        return DirectPairingClaimResult(
          ok: false,
          message: request.ok
              ? 'Device registered, but the full Store snapshot is not complete yet. Keep the Host online and try again. Snapshot error: ${retryResult.lastFailure ?? 'unknown'}'
              : '${request.message} Snapshot error: ${retryResult.lastFailure ?? 'unknown'}',
          identity: store.appIdentity,
        );
      }
      return DirectPairingClaimResult(
          ok: true,
          message: 'Device paired successfully. Please sign in.',
          identity: identity);
    } catch (error) {
      SyncDiagnosticsLog.add(
          '[DIRECT_PAIRING] failed afterDeviceRegistered=$deviceRegistered error=$error');
      if (deviceRegistered) {
        return DirectPairingClaimResult(
          ok: false,
          message:
              'Device registered, but the full Store snapshot is not complete. Keep the Host online and try again. Details: $error',
          identity: store.appIdentity,
        );
      }
      return const DirectPairingClaimResult(
          ok: false,
          message:
              'Could not connect this device. Check the pairing code and try again.');
    }
  }

  Future<DirectStoreRecoveryResult> recoverExistingStoreFromDirect(
    VpsControlPlaneSettings settings, {
    required String storeId,
    String recoveryKey = '',
    String? branchId,
    DirectSyncProgressCallback? onProgress,
  }) async {
    final previousIdentity = store.appIdentity;
    final cleanStoreId = storeId.trim().toUpperCase();
    final cleanBranchId = (branchId == null || branchId.trim().isEmpty)
        ? ''
        : branchId.trim().toUpperCase();
    final cleanRecoveryKey = recoveryKey.trim().toUpperCase();
    if (settings.apiBaseUrl.trim().isEmpty) {
      return const DirectStoreRecoveryResult(
          ok: false, message: 'Direct API URL is required.');
    }
    if (!cleanStoreId.startsWith('ST-')) {
      return const DirectStoreRecoveryResult(
          ok: false, message: 'A valid Store ID is required.');
    }
    if (settings.accountToken.trim().isEmpty) {
      return const DirectStoreRecoveryResult(
          ok: false,
          message: 'Online account session is required. Please sign in again.');
    }

    try {
      onProgress?.call(0.10, 'Verifying online account and Store access...');
      final claimResponse = await _client
          .post(
            settings.endpoint('/api/sync/recovery/claim'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer ${settings.accountToken.trim()}',
            },
            body: jsonEncode({
              'storeId': cleanStoreId,
              'branchId': cleanBranchId,
              if (cleanRecoveryKey.isNotEmpty) 'recoveryKey': cleanRecoveryKey,
              'deviceId': store.deviceId,
              'deviceName': store.appIdentity.deviceName,
              'platform': store.appIdentity.platform.name,
              'appVersion': AppBrand.directAppVersion,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (claimResponse.statusCode < 200 || claimResponse.statusCode >= 300) {
        return DirectStoreRecoveryResult(
            ok: false,
            message:
                'Store recovery failed: ${claimResponse.statusCode} ${claimResponse.body}');
      }
      final claim = jsonDecode(claimResponse.body) as Map<String, dynamic>;
      if (claim['ok'] != true) {
        return DirectStoreRecoveryResult(
            ok: false,
            message: claim['error']?.toString() ?? 'Store recovery failed.');
      }

      final recoveredBranchId =
          (claim['branchId'] ?? claim['branch_id'] ?? cleanBranchId)
                  .toString()
                  .trim()
                  .isEmpty
              ? 'BR-MAIN1'
              : (claim['branchId'] ?? claim['branch_id'] ?? cleanBranchId)
                  .toString()
                  .trim()
                  .toUpperCase();
      final deviceToken =
          (claim['deviceToken'] ?? claim['device_token'] ?? '').toString();
      final hostDeviceId =
          (claim['hostDeviceId'] ?? claim['host_device_id'] ?? store.deviceId)
              .toString();
      final controlPlaneTenantId =
          (claim['controlPlaneTenantId'] ?? claim['direct_tenant_id'] ?? '')
              .toString();

      onProgress?.call(0.25, 'Recovering permanent Store identity...');
      await store.recoverExistingStoreIdentity(
        storeId: cleanStoreId,
        branchId: recoveredBranchId,
        recoveryKey: cleanRecoveryKey,
        hostDeviceId: hostDeviceId.isEmpty ? store.deviceId : hostDeviceId,
        deviceToken: deviceToken,
        controlPlaneTenantId: controlPlaneTenantId,
        deviceRole: DeviceRole.host,
        syncMode: SyncMode.directConnected,
      );
      await settings.copyWith(enabled: true, clearLastPullCursor: true).save();
      await VpsControlPlaneSettings.clearSavedPullCursor();

      onProgress?.call(
          0.45, 'Downloading the latest Direct snapshot through the relay...');
      final envelope = await _downloadDirectSnapshotEnvelopeViaRelay(
        settings.copyWith(clearLastPullCursor: true),
        force: true,
        onProgress: (value, label) {
          onProgress?.call(
            (0.45 + value * 0.40).clamp(0.45, 0.88).toDouble(),
            label,
          );
        },
      );
      final applied = await _applyDirectSnapshotEnvelope(
        envelope,
        settings: settings,
        onProgress: onProgress,
        expectedSnapshotGeneration:
            (claim['snapshotGeneration'] ?? claim['snapshot_generation'] ?? '')
                .toString(),
        expectedRestoreCommandId:
            (claim['restoreCommandId'] ?? claim['restore_command_id'] ?? '')
                .toString(),
      );
      if (!applied.ok) {
        return DirectStoreRecoveryResult(
          ok: false,
          message:
              'Store identity recovered, but snapshot restore failed: ${applied.message}',
          identity: store.appIdentity,
        );
      }
      final pulled = applied.pulled;
      final restoredSnapshot = applied.restoredSnapshot;

      final deviceLimit = claim['deviceLimit'] is Map
          ? DirectDeviceLimitStatus.fromJson(
              Map<String, dynamic>.from(claim['deviceLimit'] as Map),
            )
          : null;

      onProgress?.call(0.90, 'Announcing recovered Host through relay...');
      await _broadcastHostAuthorityViaRelay(settings);
      await sendHostHeartbeat(settings);
      onProgress?.call(1.0, 'Store recovered.');
      await _restorePreviousSyncMode(previousIdentity);
      return DirectStoreRecoveryResult(
        ok: true,
        message: 'Current Store recovered successfully.',
        identity: store.appIdentity,
        restoredSnapshot: restoredSnapshot,
        pulled: pulled,
        username: (claim['username'] ?? '').toString(),
        loginName: (claim['loginName'] ?? claim['login_name'] ?? '').toString(),
        storeName: (claim['storeName'] ?? claim['store_name'] ?? '').toString(),
        storeSlug: (claim['storeSlug'] ?? claim['store_slug'] ?? '').toString(),
        directSyncEnabled: claim['directSyncEnabled'] == true ||
            claim['direct_sync_enabled'] == true,
        deviceLimit: deviceLimit,
      );
    } catch (error) {
      await _restorePreviousSyncMode(previousIdentity);
      return DirectStoreRecoveryResult(
          ok: false, message: 'Store recovery failed: $error');
    }
  }

  Future<DirectStoreRecoveryResult> recoverExistingStoreIdentityFromDirect(
    VpsControlPlaneSettings settings, {
    required String storeId,
    String recoveryKey = '',
    String? branchId,
    DirectSyncProgressCallback? onProgress,
  }) async {
    final previousIdentity = store.appIdentity;
    final cleanStoreId = storeId.trim().toUpperCase();
    final cleanBranchId = (branchId == null || branchId.trim().isEmpty)
        ? ''
        : branchId.trim().toUpperCase();
    final cleanRecoveryKey = recoveryKey.trim().toUpperCase();
    if (settings.apiBaseUrl.trim().isEmpty) {
      return const DirectStoreRecoveryResult(
          ok: false, message: 'Direct API URL is required.');
    }
    if (!cleanStoreId.startsWith('ST-')) {
      return const DirectStoreRecoveryResult(
          ok: false, message: 'A valid Store ID is required.');
    }
    if (settings.accountToken.trim().isEmpty) {
      return const DirectStoreRecoveryResult(
          ok: false,
          message: 'Online account session is required. Please sign in again.');
    }

    try {
      onProgress?.call(0.10, 'Verifying online account and Store access...');
      final claimResponse = await _client
          .post(
            settings.endpoint('/api/sync/recovery/claim'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer ${settings.accountToken.trim()}',
            },
            body: jsonEncode({
              'mode': 'identity',
              'storeId': cleanStoreId,
              'branchId': cleanBranchId,
              if (cleanRecoveryKey.isNotEmpty) 'recoveryKey': cleanRecoveryKey,
              'deviceId': store.deviceId,
              'deviceName': store.appIdentity.deviceName,
              'platform': store.appIdentity.platform.name,
              'appVersion': AppBrand.directAppVersion,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (claimResponse.statusCode < 200 || claimResponse.statusCode >= 300) {
        return DirectStoreRecoveryResult(
            ok: false,
            message:
                'Store identity recovery failed: ${claimResponse.statusCode} ${claimResponse.body}');
      }
      final claim = jsonDecode(claimResponse.body) as Map<String, dynamic>;
      if (claim['ok'] != true) {
        return DirectStoreRecoveryResult(
            ok: false,
            message: claim['error']?.toString() ??
                'Store identity recovery failed.');
      }

      final recoveredBranchId =
          (claim['branchId'] ?? claim['branch_id'] ?? cleanBranchId)
                  .toString()
                  .trim()
                  .isEmpty
              ? 'BR-MAIN1'
              : (claim['branchId'] ?? claim['branch_id'] ?? cleanBranchId)
                  .toString()
                  .trim()
                  .toUpperCase();
      final deviceToken =
          (claim['deviceToken'] ?? claim['device_token'] ?? '').toString();
      final hostDeviceId =
          (claim['hostDeviceId'] ?? claim['host_device_id'] ?? store.deviceId)
              .toString();
      final controlPlaneTenantId =
          (claim['controlPlaneTenantId'] ?? claim['direct_tenant_id'] ?? '')
              .toString();
      final deviceLimit = claim['deviceLimit'] is Map
          ? DirectDeviceLimitStatus.fromJson(
              Map<String, dynamic>.from(claim['deviceLimit'] as Map),
            )
          : null;

      onProgress?.call(0.25, 'Recovering permanent Store identity...');
      await store.recoverExistingStoreIdentity(
        storeId: cleanStoreId,
        branchId: recoveredBranchId,
        recoveryKey: cleanRecoveryKey,
        hostDeviceId: hostDeviceId.isEmpty ? store.deviceId : hostDeviceId,
        deviceToken: deviceToken,
        controlPlaneTenantId: controlPlaneTenantId,
        deviceRole: DeviceRole.host,
        syncMode: SyncMode.directConnected,
      );
      await settings.copyWith(enabled: true, clearLastPullCursor: true).save();
      await VpsControlPlaneSettings.clearSavedPullCursor();
      onProgress?.call(1.0, 'Store identity recovered.');
      await _restorePreviousSyncMode(previousIdentity);
      return DirectStoreRecoveryResult(
        ok: true,
        message: 'Store identity recovered.',
        identity: store.appIdentity,
        username: (claim['username'] ?? '').toString(),
        loginName: (claim['loginName'] ?? claim['login_name'] ?? '').toString(),
        storeName: (claim['storeName'] ?? claim['store_name'] ?? '').toString(),
        storeSlug: (claim['storeSlug'] ?? claim['store_slug'] ?? '').toString(),
        directSyncEnabled: claim['directSyncEnabled'] == true ||
            claim['direct_sync_enabled'] == true,
        deviceLimit: deviceLimit,
      );
    } catch (error) {
      await _restorePreviousSyncMode(previousIdentity);
      return DirectStoreRecoveryResult(
          ok: false, message: 'Store identity recovery failed: $error');
    }
  }

  Future<bool> _shouldRequestFreshSnapshotForGeneration(
    String transport,
    String generation, {
    Duration cooldown = const Duration(minutes: 15),
  }) async {
    final cleanGeneration = generation.trim();
    if (cleanGeneration.isEmpty) return true;
    final applied =
        LocalDatabaseService.getString(_snapshotGenerationKey(transport)) ?? '';
    if (applied.trim() == cleanGeneration) return false;
    final requested = LocalDatabaseService.getString(
            _snapshotRequestKey(transport, cleanGeneration)) ??
        '';
    final requestedAtRaw = LocalDatabaseService.getString(
            _snapshotRequestAtKey(transport, cleanGeneration)) ??
        '';
    final requestedAt = DateTime.tryParse(requestedAtRaw);
    if (requested == cleanGeneration &&
        requestedAt != null &&
        DateTime.now().difference(requestedAt) < cooldown) {
      return false;
    }
    return true;
  }

  Future<void> _markFreshSnapshotRequestedForGeneration(
      String transport, String generation) async {
    final cleanGeneration = generation.trim();
    if (cleanGeneration.isEmpty) return;
    await LocalDatabaseService.setString(
        _snapshotRequestKey(transport, cleanGeneration), cleanGeneration);
    await LocalDatabaseService.setString(
        _snapshotRequestAtKey(transport, cleanGeneration),
        DateTime.now().toIso8601String());
  }

  String _newDirectRebuildRequestId() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final device = store.deviceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return 'direct-rebuild-$now-${device.isEmpty ? 'device' : device}';
  }

  Future<DirectSyncResult> requestFreshHostSnapshot(
      VpsControlPlaneSettings settings,
      {DateTime? requestedAt,
      String snapshotGeneration = ''}) async {
    final identity = store.appIdentity;
    if (identity.isHost) {
      return const DirectSyncResult(
          ok: true, message: 'Host can publish its snapshot directly.');
    }
    if (!UnifiedSyncPolicy.canRequestDirectSnapshot(
      identity,
      isConfigured: settings.isConfigured,
    )) {
      return const DirectSyncResult(
          ok: false, message: 'Direct Sync is not ready yet.');
    }
    final cleanGeneration = snapshotGeneration.trim();
    if (cleanGeneration.isNotEmpty &&
        !await _shouldRequestFreshSnapshotForGeneration(
            'direct', cleanGeneration)) {
      return const DirectSyncResult(
          ok: true,
          message:
              'A snapshot for this generation was already requested or applied, so no duplicate request will be sent.');
    }
    await _markFreshSnapshotRequestedForGeneration('direct', cleanGeneration);
    return const DirectSyncResult(
      ok: true,
      message:
          'Fresh Host snapshot will be fetched directly through the relay on the next attempt.',
    );
  }
}
