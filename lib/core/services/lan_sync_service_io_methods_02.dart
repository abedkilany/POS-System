part of 'lan_sync_service_io.dart';

extension LanSyncServiceSplitPart2 on LanSyncService {

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.headers.add('Access-Control-Allow-Headers',
          'Content-Type, X-Device-Id, X-Device-Token, X-Device-Role');
      request.response.headers
          .add('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');

      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }

      final settings = LanSyncSettings.load();
      final receivedDeviceId = request.headers.value('x-device-id');
      final receivedDeviceToken = request.headers.value('x-device-token');

      if (request.method == 'POST' && request.uri.path == '/pairing/claim') {
        final body = await utf8.decoder.bind(request).join();
        final decoded = body.trim().isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(body) as Map);
        final code =
            (decoded['code'] ?? decoded['pairingCode'] ?? '').toString().trim();
        final currentCode = settings.secret.trim();
        final expired = settings.pairingCodeExpiresAt == null ||
            !DateTime.now().isBefore(settings.pairingCodeExpiresAt!);
        if (currentCode.isEmpty ||
            code.isEmpty ||
            code != currentCode ||
            expired) {
          await _json(request,
              {'ok': false, 'error': 'Invalid or expired LAN pairing code.'},
              status: HttpStatus.unauthorized);
          return;
        }

        final requestedDeviceId = (decoded['deviceId'] ?? '').toString().trim();
        final deviceId = requestedDeviceId.isNotEmpty
            ? requestedDeviceId
            : AppIdentity.defaults(
                    deviceId: '', platform: AppPlatformType.unknown)
                .deviceId;
        await _refreshCachedDeviceLimit();
        if (_clientDeviceLimitReached(settings, excludeDeviceId: deviceId)) {
          await _json(
            request,
            {'ok': false, 'error': 'Device limit reached.'},
            status: HttpStatus.forbidden,
          );
          return;
        }
        final deviceToken = LanSyncSettings.generateDeviceToken();
        final paired = Map<String, String>.from(settings.pairedDevices);
        paired[deviceId] = deviceToken;
        final registry = HostRegistryDevice.migrateFromPairedDevices(
          paired,
          existing: settings.hostRegistry,
          hostDeviceId: store.deviceId,
        );

        // Single-use LAN pairing: immediately clear the pairing code after the
        // oldest successful claim is accepted. Later claims with the same code fail.
        await settings
            .copyWith(secret: '', pairedDevices: paired, hostRegistry: registry)
            .save();

        final snapshotInfo = await _snapshotManifestResponse(force: true);
        await _json(request, {
          'ok': true,
          'message': 'LAN device paired successfully.',
          'deviceId': deviceId,
          'deviceToken': deviceToken,
          'storeId': store.appIdentity.storeId,
          'branchId': store.appIdentity.branchId,
          'hostDeviceId': store.deviceId,
          'snapshotAvailable': true,
          'snapshotManifest': snapshotInfo['snapshotManifest'],
          'totalChunks': snapshotInfo['totalChunks'],
          'syncGeneratedAt': snapshotInfo['syncGeneratedAt'],
          'syncGeneratedSequence': snapshotInfo['syncGeneratedSequence'],
        });
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/device-wipe-ack') {
        final body = await utf8.decoder.bind(request).join();
        final decoded = body.trim().isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(body) as Map);
        final clientDeviceId =
            (decoded['deviceId'] ?? receivedDeviceId ?? '').toString().trim();
        final deviceToken =
            (decoded['deviceToken'] ?? receivedDeviceToken ?? '')
                .toString()
                .trim();
        if (clientDeviceId.isEmpty ||
            !SyncDeviceAccessStore.wipePendingTokenMatches(
                clientDeviceId, deviceToken)) {
          await _json(
              request, {'ok': false, 'error': 'Invalid wipe acknowledgement.'},
              status: HttpStatus.unauthorized);
          return;
        }
        // Fix #11: ACK confirms the client received the wipe command, but it
        // must not automatically remove the device from the Host list. The row
        // remains Wipe Pending until the admin presses Permanent Delete.
        await _json(request, {
          'ok': true,
          'wipeConfirmed': true,
          'serverTime': DateTime.now().toIso8601String()
        });
        return;
      }

      if (!_authorized(request, settings)) {
        if (await _handleBlockedDevice(request, settings)) return;
        // Keep a safe log for troubleshooting LAN/Host pairing problems without printing full tokens.
        developer.log(
          'LAN SYNC AUTH FAILED: path=${request.uri.path} '
          "from=${request.connectionInfo?.remoteAddress.address ?? 'unknown'} "
          'deviceId=${receivedDeviceId ?? '<empty>'} token=${_maskedToken(receivedDeviceToken)}',
          name: 'ventio.lan_sync',
        );
        await _json(
          request,
          {
            'ok': false,
            'error':
                'Unauthorized LAN device token. Please re-pair this Client with the Host.',
          },
          status: HttpStatus.unauthorized,
        );
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/realtime') {
        await _handleRealtimeSocket(request);
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/health') {
        await _json(request, {
          'ok': true,
          'mode': 'host',
          'deviceId': store.deviceId,
          'pending': store.pendingSyncCount,
          'generatedAt': DateTime.now().toIso8601String(),
        });
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/changes/signal') {
        final since =
            DateTime.tryParse(request.uri.queryParameters['since'] ?? '');
        final sinceSequence =
            int.tryParse(request.uri.queryParameters['since_sequence'] ?? '') ??
                0;
        final waitSeconds =
            (int.tryParse(request.uri.queryParameters['wait_seconds'] ?? '') ??
                    25)
                .clamp(1, 25);
        final deadline =
            DateTime.now().add(Duration(seconds: waitSeconds.toInt()));
        while (true) {
          final payload =
              _lanSignalPayload(since: since, sinceSequence: sinceSequence);
          if (payload['changed'] == true || DateTime.now().isAfter(deadline)) {
            await _json(request, payload);
            return;
          }
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }

      if (request.method == 'GET' && request.uri.path == '/snapshot/manifest') {
        final force = request.uri.queryParameters['force'] == '1';
        await _json(request, await _snapshotManifestResponse(force: force));
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/snapshot/chunk') {
        final ordinal =
            int.tryParse(request.uri.queryParameters['ordinal'] ?? '') ?? -1;
        final envelope = await _currentLanSnapshotEnvelope();
        final chunks =
            (envelope['snapshotChunks'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false);
        if (ordinal < 0 || ordinal >= chunks.length) {
          await _json(
              request, {'ok': false, 'error': 'Snapshot chunk not found.'},
              status: HttpStatus.notFound);
          return;
        }
        await _json(request, {
          'ok': true,
          'chunk': chunks[ordinal],
          'ordinal': ordinal,
          'totalChunks': chunks.length,
          'snapshotManifest': envelope['snapshotManifest'],
          'syncGeneratedAt': envelope['syncGeneratedAt'],
          'syncGeneratedSequence': envelope['syncGeneratedSequence'],
        });
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/snapshot') {
        request.response.headers.contentType = ContentType.json;
        request.response
            .write(jsonEncode(await _currentLanSnapshotEnvelope(force: true)));
        await request.response.close();
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/changes/pull') {
        final since =
            DateTime.tryParse(request.uri.queryParameters['since'] ?? '');
        final sinceSequence =
            int.tryParse(request.uri.queryParameters['since_sequence'] ?? '') ??
                0;
        // Pull is delivery only. The Host must not mark changes as applied or
        // ACKed until the Client posts /changes/ack after local apply succeeds.
        request.response.headers.contentType = ContentType.json;
        request.response.write(store.exportSyncChangesJson(
            since: since, sinceSequence: sinceSequence));
        await request.response.close();
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/changes/ack') {
        final body = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final clientDeviceId =
            decoded['deviceId']?.toString() ?? receivedDeviceId ?? '';
        final clientDeviceName = decoded['deviceName']?.toString() ?? '';
        _updateHostRegistryDeviceName(clientDeviceId, clientDeviceName);
        final cursor = DateTime.tryParse(
            decoded['lastAppliedCursor']?.toString() ??
                decoded['lastAckCursor']?.toString() ??
                '');
        final sequence = int.tryParse(
                decoded['lastAppliedSequence']?.toString() ??
                    decoded['lastAckSequence']?.toString() ??
                    '') ??
            0;
        await SyncDeviceStateStore.recordPeerSyncResult(
          deviceId: clientDeviceId,
          transport: 'lan',
          appliedCursor: cursor,
          ackCursor: cursor,
          appliedSequence: sequence,
          ackSequence: sequence,
        );
        await store.settleHostQueueThroughPeerAck();
        await store.compactSyncedSyncHistoryForMaintenance();
        await _json(request,
            {'ok': true, 'serverTime': DateTime.now().toIso8601String()});
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/changes/push') {
        final body = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final changes = (decoded['changes'] as List<dynamic>? ?? [])
            .map((item) =>
                SyncChange.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
        if (changes.any((item) =>
            item.entityType == 'system' &&
            item.operation == 'reset_store_data')) {
          await _json(
              request,
              {
                'ok': false,
                'error': 'Reset data can only be initiated on the Host device.'
              },
              status: HttpStatus.forbidden);
          return;
        }
        final clientCursor =
            DateTime.tryParse(decoded['cursor']?.toString() ?? '');
        final clientSequence = int.tryParse(decoded['sequence']?.toString() ??
                decoded['lastAppliedSequence']?.toString() ??
                '') ??
            0;
        final accepted = await _syncCore.acceptClientChangesOnHost(
          changes,
          mirrorToDirect:
              store.appIdentity.isDirectEnabled && store.appIdentity.isHost,
        );
        final clientDeviceId =
            decoded['deviceId']?.toString() ?? receivedDeviceId ?? '';
        final clientDeviceName = decoded['deviceName']?.toString() ?? '';
        _updateHostRegistryDeviceName(clientDeviceId, clientDeviceName);
        await SyncDeviceStateStore.recordPeerSyncResult(
          deviceId: clientDeviceId,
          transport: 'lan',
          ackCursor: clientCursor,
          ackSequence: clientSequence,
        );
        await _json(request, {
          'ok': true,
          // Acknowledge all received IDs. Changes older than the latest Host reset
          // are intentionally discarded so stale offline client data cannot revive
          // deleted business data after a central reset.
          'ackIds': accepted.ackIds,
          'rejected': accepted.rejected.entries
              .map((entry) => {'id': entry.key, 'reason': entry.value})
              .toList(),
          'serverTime': DateTime.now().toIso8601String(),
          'discardedBecauseOfReset': accepted.discardedBecauseOfReset,
        });
        return;
      }

      // Legacy LAN Sync V1 endpoints are intentionally disabled.
      // Stage 4 keeps all LAN synchronization on the unified /changes/* protocol
      // so old clients cannot merge snapshots directly into Host data.
      if ((request.method == 'GET' && request.uri.path == '/pull') ||
          (request.method == 'POST' && request.uri.path == '/sync')) {
        await _json(
          request,
          {
            'ok': false,
            'error':
                'Legacy LAN sync endpoint disabled. Use /changes/push and /changes/pull.',
          },
          status: HttpStatus.gone,
        );
        return;
      }

      await _json(request, {'ok': false, 'error': 'Not found'},
          status: HttpStatus.notFound);
    } catch (error) {
      try {
        await _json(request, {'ok': false, 'error': error.toString()},
            status: HttpStatus.internalServerError);
      } catch (_) {}
    }
  }

  Future<void> _handleRealtimeSocket(HttpRequest request) async {
    if (!store.appIdentity.isHost) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    final deviceId = request.headers.value('x-device-id')?.trim() ?? '';
    final socket = await WebSocketTransformer.upgrade(request);
    LanSyncService._realtimeClients[socket] = deviceId;
    SyncDeviceStateStore.recordPeerOnline(deviceId);
    socket.pingInterval = const Duration(seconds: 30);
    socket.add(jsonEncode({
      'type': 'realtime_welcome',
      'changed': false,
      'hostDeviceId': store.deviceId,
      'serverTime': DateTime.now().toIso8601String(),
    }));
    socket.listen(
      (_) {},
      onDone: () {
        LanSyncService._realtimeClients.remove(socket);
        SyncDeviceStateStore.recordPeerOffline(deviceId);
      },
      onError: (_, __) {
        LanSyncService._realtimeClients.remove(socket);
        SyncDeviceStateStore.recordPeerOffline(deviceId);
      },
      cancelOnError: true,
    );
  }

  Future<void> _closeRealtimeClient() async {
    await _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    await _realtimeChannel?.sink.close();
    _realtimeChannel = null;
  }

  HttpClient _client() =>
      HttpClient()..connectionTimeout = const Duration(seconds: 15);

  Future<String?> discoverHost({int port = 8787}) async {
    if (store.appIdentity.isHost || store.appIdentity.storeId.trim().isEmpty) {
      return null;
    }
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final request = jsonEncode({
        'protocol': LanSyncService._discoveryProtocol,
        'type': 'discover',
        'storeId': store.appIdentity.storeId,
        'branchId': store.appIdentity.branchId,
        'hostDeviceId': store.appIdentity.hostDeviceId,
      });
      final completer = Completer<String?>();
      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = socket!.receive()) != null) {
          try {
            final decoded = jsonDecode(utf8.decode(datagram!.data));
            if (decoded is! Map ||
                decoded['protocol'] != LanSyncService._discoveryProtocol ||
                decoded['type'] != 'host' ||
                '${decoded['storeId'] ?? ''}'.trim() !=
                    store.appIdentity.storeId.trim() ||
                '${decoded['branchId'] ?? ''}'.trim() !=
                    store.appIdentity.branchId.trim()) {
              continue;
            }
            final expectedHostId = store.appIdentity.hostDeviceId.trim();
            final discoveredHostId = '${decoded['hostDeviceId'] ?? ''}'.trim();
            if (expectedHostId.isNotEmpty &&
                discoveredHostId != expectedHostId) {
              continue;
            }
            final discoveredPort =
                int.tryParse('${decoded['port'] ?? port}') ?? port;
            if (discoveredPort != port) continue;
            if (!completer.isCompleted) {
              completer.complete(datagram.address.address);
            }
          } catch (_) {
            // Ignore unrelated UDP traffic on the discovery port.
          }
        }
      }, onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      });
      final payload = utf8.encode(request);
      socket.send(payload, InternetAddress('255.255.255.255'), LanSyncService._discoveryPort);
      socket.send(payload, InternetAddress('224.0.0.251'), LanSyncService._discoveryPort);
      final host = await completer.future.timeout(
        const Duration(milliseconds: 1200),
        onTimeout: () => null,
      );
      if (host == null || host.trim().isEmpty) return null;
      try {
        final client = _client();
        final health = await client.get(host, port, '/health');
        _attachToken(health, store.appIdentity.deviceToken);
        final response = await health.close();
        await utf8.decoder.bind(response).drain();
        client.close(force: true);
        if (response.statusCode != 200) return null;
      } catch (_) {
        return null;
      }
      final settings = LanSyncSettings.load();
      if (settings.host.trim() != host.trim()) {
        await settings.copyWith(host: host.trim()).save();
      }
      return host.trim();
    } catch (_) {
      return null;
    } finally {
      await subscription?.cancel();
      socket?.close();
    }
  }

  void _attachToken(HttpClientRequest request, String token,
      {String? deviceId}) {
    final identity = store.appIdentity;
    final headerDeviceId = (deviceId ?? identity.deviceId).trim();
    final headerToken =
        token.trim().isNotEmpty ? token.trim() : identity.deviceToken.trim();
    if (headerDeviceId.isNotEmpty && headerToken.isNotEmpty) {
      request.headers.add('X-Device-Id', headerDeviceId);
      request.headers.add('X-Device-Token', headerToken);
      request.headers.add('X-Device-Role', identity.deviceRole.name);
    }
  }

  Future<LanSyncResult> claimPairingCode(String host,
      {int port = 8787,
      required String code,
      LanSyncProgressCallback? onProgress}) async {
    final identity = store.appIdentity;
    if (!UnifiedSyncPolicy.canClaimLanPairingCode(identity)) {
      return const LanSyncResult(
          ok: false,
          message:
              'Host devices cannot pair as LAN Clients. Use Transfer Host instead.');
    }
    // A Client may configure both LAN and Direct transports. Pairing LAN only
    // prepares another delivery method; the active transport still decides
    // which one auto-sync runs.
    try {
      onProgress?.call(0.08, 'Connecting to LAN Host...');
      final client = _client();
      onProgress?.call(0.14, 'Verifying LAN pairing code...');
      final request = await client.post(host.trim(), port, '/pairing/claim');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'code': code.trim(),
        'deviceId': store.deviceId,
        'deviceName': store.appIdentity.deviceName,
        'platform': store.appIdentity.platform.name,
      }));
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      client.close(force: true);
      if (response.statusCode != 200) {
        return const LanSyncResult(
            ok: false,
            message:
                'Pairing code expired or already used. Ask the Host device for a new code.');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (decoded['ok'] != true) {
        return LanSyncResult(
            ok: false,
            message: decoded['error']?.toString() ?? 'LAN pairing failed.');
      }
      final claim = UnifiedPairingClaimPayload(
        storeId: decoded['storeId']?.toString() ?? identity.storeId,
        branchId: decoded['branchId']?.toString() ?? identity.branchId,
        hostDeviceId:
            decoded['hostDeviceId']?.toString() ?? identity.hostDeviceId,
        deviceId: decoded['deviceId']?.toString() ?? identity.deviceId,
        deviceToken: decoded['deviceToken']?.toString() ?? identity.deviceToken,
        transport: 'lan',
      );
      final mismatch = UnifiedPairingLifecycle.validateSameStoreClaim(
        identity,
        claim,
        label: 'LAN pairing',
      );
      if (mismatch != null) {
        return LanSyncResult(ok: false, message: mismatch);
      }

      final current = store.appIdentity;
      onProgress?.call(0.22, 'Registering this device...');
      final clientIdentity = UnifiedPairingLifecycle.buildClientIdentity(
        current,
        claim: claim,
        syncMode: SyncMode.lanOnly,
        activeTransport: 'lan',
      );
      await store.updateAppIdentityDuringSetup(clientIdentity);
      final snapshotEnvelope = await _downloadLanSnapshotEnvelope(
        host,
        port: port,
        token: clientIdentity.deviceToken,
        deviceId: clientIdentity.deviceId,
        // A new Client must never bootstrap from the Host's short-lived
        // snapshot cache; the Host may have just created users or changed
        // roles since that cache was built.
        force: true,
        onProgress: onProgress,
      );
      onProgress?.call(0.74, 'Importing LAN snapshot chunks locally...');
      final settings = LanSyncSettings.load();
      await UnifiedPairingSnapshotFlow.applyForLan(
        store: store,
        envelope: snapshotEnvelope,
        host: host,
        port: port,
        markSnapshotApplied: () => _markHostSnapshotGenerationApplied(
          'lan',
          snapshotEnvelope,
        ),
        saveLanSettings: (cursor) => settings
            .copyWith(
              host: host.trim(),
              port: port,
              mode: LanSyncDeviceMode.client,
              hostModeEnabled: false,
              setupComplete: true,
              autoSyncEnabled: true,
              secret: '',
              lastPullCursor: cursor,
              lastConnectionAt: DateTime.now(),
              lastSyncAt: DateTime.now(),
            )
            .save(),
        saveCursorAndState: (cursor, sequence) =>
            // saveLanSettings runs immediately before this callback. Reload
            // the persisted settings so cursor bookkeeping cannot overwrite
            // the newly saved client/setup state with the pre-pairing object.
            _saveCursorAndRecordState(
          LanSyncSettings.load(),
          cursor,
          sequence: sequence,
        ),
      );
      onProgress?.call(1.0, 'LAN snapshot is ready.');
      return LanSyncResult(
        ok: true,
        message: 'LAN pairing completed.',
        identity: store.appIdentity,
      );
    } catch (error) {
      return LanSyncResult(ok: false, message: 'LAN pairing failed: $error');
    }
  }

  Future<LanSyncResult> testConnection(String host,
      {int port = 8787, String token = ''}) async {
    try {
      final client = _client();
      final request = await client.get(host.trim(), port, '/health');
      _attachToken(request, token);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      client.close(force: true);
      return LanSyncResult(
          ok: response.statusCode == 200,
          message: response.statusCode == 200
              ? 'Connection is healthy.'
              : 'Host returned ${response.statusCode}: $body');
    } catch (error) {
      final recovered = await discoverHost(port: port);
      if (recovered != null) {
        return testConnection(recovered, port: port, token: token);
      }
      return LanSyncResult(ok: false, message: 'Connection failed: $error');
    }
  }

  Future<Map<String, dynamic>> _downloadLanSnapshotEnvelope(
    String host, {
    int port = 8787,
    String token = '',
    String? deviceId,
    bool force = false,
    LanSyncProgressCallback? onProgress,
  }) {
    return const UnifiedSnapshotTransferService().downloadEnvelope(
      _LanSnapshotPullTransport(
        host: host,
        port: port,
        token: token,
        deviceId: deviceId ?? store.appIdentity.deviceId,
        attachToken: _attachToken,
        newClient: _client,
      ),
      force: force,
      labelPrefix: 'LAN snapshot',
      onProgress: onProgress,
    );
  }

  Future<LanSyncResult> initialClone(String host,
      {int port = 8787,
      String token = '',
      LanSyncProgressCallback? onProgress}) async {
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
      );
      final hostCursor = applied.cursor;
      final settings = LanSyncSettings.load();
      onProgress?.call(0.94, 'Saving LAN sync cursor...');
      final hostSequence = applied.sequence;
      await _saveCursorAndRecordState(settings, hostCursor,
          sequence: hostSequence);
      await _sendLanAck(host,
          port: port, token: token, cursor: hostCursor, sequence: hostSequence);
      return const LanSyncResult(
          ok: true,
          message: 'Initial clone completed from LAN snapshot chunks.');
    } catch (error) {
      return LanSyncResult(ok: false, message: 'Initial clone failed: $error');
    }
  }
}
