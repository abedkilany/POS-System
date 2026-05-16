import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'dart:math';

import '../../data/app_store.dart';
import '../../models/app_identity.dart';
import '../../models/sync_change.dart';
import 'local_database_service.dart';

typedef LanSyncProgressCallback = void Function(double value, String label);

enum LanSyncDeviceMode { unconfigured, host, client }

class LanSyncSettings {
  const LanSyncSettings({
    required this.host,
    required this.port,
    required this.autoSyncEnabled,
    required this.hostModeEnabled,
    this.setupComplete = false,
    this.mode = LanSyncDeviceMode.unconfigured,
    this.secret = '',
    this.lastPullCursor,
    this.lastConnectionAt,
    this.lastSyncAt,
    this.pairedDevices = const <String, String>{},
  });

  static const String storageKey = 'lan_sync_settings_v2';

  final String host;
  final int port;
  final bool autoSyncEnabled;
  final bool hostModeEnabled;
  final bool setupComplete;
  final LanSyncDeviceMode mode;
  final String secret;
  final DateTime? lastPullCursor;
  final DateTime? lastConnectionAt;
  final DateTime? lastSyncAt;
  /// LAN paired Client credentials: deviceId -> deviceToken.
  /// Host stores this map; Clients store only their own deviceToken in AppIdentity.
  final Map<String, String> pairedDevices;

  bool get isHost => mode == LanSyncDeviceMode.host || hostModeEnabled;
  bool get isClient => mode == LanSyncDeviceMode.client || (!hostModeEnabled && setupComplete);

  LanSyncSettings copyWith({
    String? host,
    int? port,
    bool? autoSyncEnabled,
    bool? hostModeEnabled,
    bool? setupComplete,
    LanSyncDeviceMode? mode,
    String? secret,
    DateTime? lastPullCursor,
    DateTime? lastConnectionAt,
    DateTime? lastSyncAt,
    Map<String, String>? pairedDevices,
    bool clearLastPullCursor = false,
    bool clearLastConnectionAt = false,
    bool clearLastSyncAt = false,
  }) {
    return LanSyncSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      hostModeEnabled: hostModeEnabled ?? this.hostModeEnabled,
      setupComplete: setupComplete ?? this.setupComplete,
      mode: mode ?? this.mode,
      secret: secret ?? this.secret,
      lastPullCursor: clearLastPullCursor ? null : (lastPullCursor ?? this.lastPullCursor),
      lastConnectionAt: clearLastConnectionAt ? null : (lastConnectionAt ?? this.lastConnectionAt),
      lastSyncAt: clearLastSyncAt ? null : (lastSyncAt ?? this.lastSyncAt),
      pairedDevices: pairedDevices ?? this.pairedDevices,
    );
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'autoSyncEnabled': autoSyncEnabled,
        'hostModeEnabled': hostModeEnabled,
        'setupComplete': setupComplete,
        'mode': mode.name,
        'secret': secret,
        'lastPullCursor': lastPullCursor?.toIso8601String(),
        'lastConnectionAt': lastConnectionAt?.toIso8601String(),
        'lastSyncAt': lastSyncAt?.toIso8601String(),
        'pairedDevices': pairedDevices,
      };

  factory LanSyncSettings.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'] as String? ?? '';
    final mode = LanSyncDeviceMode.values.firstWhere(
      (item) => item.name == modeName,
      orElse: () => (json['hostModeEnabled'] as bool? ?? false) ? LanSyncDeviceMode.host : LanSyncDeviceMode.client,
    );
    return LanSyncSettings(
      host: (json['host'] as String?)?.trim().isNotEmpty == true ? (json['host'] as String).trim() : '192.168.1.100',
      port: json['port'] as int? ?? int.tryParse('${json['port']}') ?? 8787,
      autoSyncEnabled: json['autoSyncEnabled'] as bool? ?? true,
      hostModeEnabled: json['hostModeEnabled'] as bool? ?? mode == LanSyncDeviceMode.host,
      setupComplete: json['setupComplete'] as bool? ?? false,
      mode: mode,
      secret: json['secret'] as String? ?? '',
      lastPullCursor: DateTime.tryParse(json['lastPullCursor'] as String? ?? ''),
      lastConnectionAt: DateTime.tryParse(json['lastConnectionAt'] as String? ?? ''),
      lastSyncAt: DateTime.tryParse(json['lastSyncAt'] as String? ?? ''),
      pairedDevices: (json['pairedDevices'] is Map)
          ? Map<String, String>.from((json['pairedDevices'] as Map).map((key, value) => MapEntry('$key', '$value')))
          : const <String, String>{},
    );
  }

  static LanSyncSettings load() {
    final rawV2 = LocalDatabaseService.getString(storageKey);
    if (rawV2 != null && rawV2.trim().isNotEmpty) {
      try {
        return LanSyncSettings.fromJson(Map<String, dynamic>.from(jsonDecode(rawV2) as Map));
      } catch (_) {}
    }

    // Do not auto-migrate legacy LAN settings to a completed v2 setup.
    // The v2 Host/Client selection must be explicit, otherwise upgraded
    // installs can silently skip the setup screen.

    return const LanSyncSettings(
      host: '192.168.1.100',
      port: 8787,
      autoSyncEnabled: true,
      hostModeEnabled: false,
    );
  }

  Future<void> save() async {
    await LocalDatabaseService.setString(storageKey, jsonEncode(toJson()));
  }

  static Future<void> resetSetup() async {
    await LocalDatabaseService.deleteString(storageKey);
  }

  static String generateSecret() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(16, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }

  static String generatePairingCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(8, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }

  static String generateDeviceToken() {
    const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return 'lan_${List.generate(40, (_) => alphabet[random.nextInt(alphabet.length)]).join()}';
  }

  static Future<List<String>> localIpv4Addresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    final addresses = <String>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback && address.address.trim().isNotEmpty) {
          addresses.add(address.address.trim());
        }
      }
    }
    return addresses.toSet().toList();
  }
}

class LanSyncResult {
  const LanSyncResult({required this.ok, required this.message});
  final bool ok;
  final String message;
}

class LanSyncService {
  LanSyncService(this.store);

  final AppStore store;
  static HttpServer? _sharedServer;
  static int? _sharedPort;

  bool get isHosting => _sharedServer != null;
  int? get port => _sharedPort;

  Future<void> startHost({int port = 8787}) async {
    if (_sharedServer != null && _sharedPort == port) return;
    await stopHost();
    _sharedServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _sharedPort = port;
    _sharedServer!.listen(_handleRequest, onError: (_) {});
  }

  Future<void> stopHost() async {
    await _sharedServer?.close(force: true);
    _sharedServer = null;
    _sharedPort = null;
  }

  bool _authorized(HttpRequest request, LanSyncSettings settings) {
    final deviceId = request.headers.value('x-device-id')?.trim() ?? '';
    final deviceToken = request.headers.value('x-device-token')?.trim() ?? '';
    if (deviceId.isEmpty || deviceToken.isEmpty) return false;
    final expected = settings.pairedDevices[deviceId]?.trim() ?? '';
    return expected.isNotEmpty && expected == deviceToken;
  }

  String _maskedToken(String? token) {
    final value = (token ?? '').trim();
    if (value.isEmpty) return '<empty>';
    if (value.length <= 4) return '****';
    return '${value.substring(0, 2)}****${value.substring(value.length - 2)}';
  }

  Future<void> _json(HttpRequest request, Object payload, {int status = HttpStatus.ok}) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(payload));
    await request.response.close();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type, X-Device-Id, X-Device-Token, X-Device-Role');
      request.response.headers.add('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');

      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }

      final settings = LanSyncSettings.load();

      if (request.method == 'POST' && request.uri.path == '/pairing/claim') {
        final body = await utf8.decoder.bind(request).join();
        final decoded = body.trim().isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(body) as Map);
        final code = (decoded['code'] ?? decoded['pairingCode'] ?? '').toString().trim();
        final currentCode = settings.secret.trim();
        if (currentCode.isEmpty || code.isEmpty || code != currentCode) {
          await _json(request, {'ok': false, 'error': 'Invalid or expired LAN pairing code.'}, status: HttpStatus.unauthorized);
          return;
        }

        final requestedDeviceId = (decoded['deviceId'] ?? '').toString().trim();
        final deviceId = requestedDeviceId.isNotEmpty ? requestedDeviceId : AppIdentity.defaults(deviceId: '', platform: AppPlatformType.unknown).deviceId;
        final deviceToken = LanSyncSettings.generateDeviceToken();
        final paired = Map<String, String>.from(settings.pairedDevices);
        paired[deviceId] = deviceToken;

        // Single-use LAN pairing: immediately clear the pairing code after the
        // oldest successful claim is accepted. Later claims with the same code fail.
        await settings.copyWith(secret: '', pairedDevices: paired).save();

        final snapshot = jsonDecode(store.exportSyncSnapshotJson()) as Map<String, dynamic>;
        await _json(request, {
          'ok': true,
          'message': 'LAN device paired successfully.',
          'deviceId': deviceId,
          'deviceToken': deviceToken,
          'storeId': store.appIdentity.storeId,
          'branchId': store.appIdentity.branchId,
          'hostDeviceId': store.deviceId,
          'snapshot': snapshot,
        });
        return;
      }

      if (!_authorized(request, settings)) {
        final receivedDeviceId = request.headers.value('x-device-id');
        final receivedDeviceToken = request.headers.value('x-device-token');
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
            'error': 'Unauthorized LAN device token. Please re-pair this Client with the Host.',
          },
          status: HttpStatus.unauthorized,
        );
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

      if (request.method == 'GET' && request.uri.path == '/snapshot') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(store.exportSyncSnapshotJson());
        await request.response.close();
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/changes/pull') {
        final since = DateTime.tryParse(request.uri.queryParameters['since'] ?? '');
        request.response.headers.contentType = ContentType.json;
        request.response.write(store.exportSyncChangesJson(since: since));
        await request.response.close();
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/changes/push') {
        final body = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final changes = (decoded['changes'] as List<dynamic>? ?? [])
            .map((item) => SyncChange.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
        if (changes.any((item) => item.entityType == 'system' && item.operation == 'reset_store_data')) {
          await _json(request, {'ok': false, 'error': 'Reset data can only be initiated on the Host device.'}, status: HttpStatus.forbidden);
          return;
        }
        final latestResetAt = store.latestResetSyncAt;
        final hostReceivedAt = DateTime.now();
        final applicableChanges = (latestResetAt == null
                ? changes
                : changes.where((item) => item.createdAt.isAfter(latestResetAt)).toList())
            // Re-stamp accepted client changes on the Host timeline. Otherwise a
            // second client whose cursor is already newer than the original
            // offline client timestamp may never pull that change.
            .map((item) => item.copyWith(createdAt: hostReceivedAt))
            .toList();
        await store.applyRemoteSyncChanges(applicableChanges, markAppliedAsSynced: true, mirrorToCloud: store.appIdentity.isCloudEnabled && store.appIdentity.isHost);
        await _json(request, {
          'ok': true,
          // Acknowledge all received IDs. Changes older than the latest Host reset
          // are intentionally discarded so stale offline client data cannot revive
          // deleted business data after a central reset.
          'ackIds': changes.map((item) => item.id).toList(),
          'serverTime': DateTime.now().toIso8601String(),
          'discardedBecauseOfReset': changes.length - applicableChanges.length,
        });
        return;
      }

      // Backward compatible endpoints.
      if (request.method == 'GET' && request.uri.path == '/pull') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(store.exportSyncSnapshotJson());
        await request.response.close();
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/sync') {
        final body = await utf8.decoder.bind(request).join();
        await store.mergeBackupJson(body, markSynced: true);
        request.response.headers.contentType = ContentType.json;
        request.response.write(store.exportSyncSnapshotJson());
        await request.response.close();
        return;
      }

      await _json(request, {'ok': false, 'error': 'Not found'}, status: HttpStatus.notFound);
    } catch (error) {
      try {
        await _json(request, {'ok': false, 'error': error.toString()}, status: HttpStatus.internalServerError);
      } catch (_) {}
    }
  }

  HttpClient _client() => HttpClient()..connectionTimeout = const Duration(seconds: 15);

  void _attachToken(HttpClientRequest request, String token) {
    final identity = store.appIdentity;
    if (identity.deviceId.trim().isNotEmpty && identity.deviceToken.trim().isNotEmpty) {
      request.headers.add('X-Device-Id', identity.deviceId.trim());
      request.headers.add('X-Device-Token', identity.deviceToken.trim());
      request.headers.add('X-Device-Role', identity.deviceRole.name);
    }
  }

  Future<LanSyncResult> claimPairingCode(String host, {int port = 8787, required String code}) async {
    final identity = store.appIdentity;
    if (identity.isHost) {
      return const LanSyncResult(ok: false, message: 'Host devices cannot pair as LAN Clients. Use Transfer Host instead.');
    }
    if (identity.isClient && (identity.syncMode == SyncMode.cloudConnected || identity.syncMode == SyncMode.marketplaceEnabled)) {
      return const LanSyncResult(ok: false, message: 'This device is already a Cloud Client. Clear local data or connect to a new Host before using LAN pairing.');
    }
    try {
      final client = _client();
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
        return const LanSyncResult(ok: false, message: 'Pairing code expired or already used. Ask the Host device for a new code.');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (decoded['ok'] != true) {
        return LanSyncResult(ok: false, message: decoded['error']?.toString() ?? 'LAN pairing failed.');
      }

      final snapshot = jsonEncode(decoded['snapshot'] as Map<String, dynamic>);
      await store.importSyncSnapshotJson(snapshot);
      final hostCursor = store.syncSnapshotGeneratedAtFromJson(snapshot);
      final current = store.appIdentity;
      await store.updateAppIdentityDuringSetup(current.copyWith(
        storeId: decoded['storeId']?.toString() ?? current.storeId,
        branchId: decoded['branchId']?.toString() ?? current.branchId,
        deviceId: decoded['deviceId']?.toString() ?? current.deviceId,
        deviceRole: DeviceRole.client,
        syncMode: SyncMode.lanOnly,
        hostDeviceId: decoded['hostDeviceId']?.toString() ?? current.hostDeviceId,
        deviceToken: decoded['deviceToken']?.toString() ?? current.deviceToken,
      ));
      final settings = LanSyncSettings.load();
      await settings.copyWith(
        host: host.trim(),
        port: port,
        mode: LanSyncDeviceMode.client,
        hostModeEnabled: false,
        setupComplete: true,
        autoSyncEnabled: true,
        secret: '',
        lastPullCursor: hostCursor,
        lastConnectionAt: DateTime.now(),
        lastSyncAt: DateTime.now(),
      ).save();
      return const LanSyncResult(ok: true, message: 'LAN pairing completed.');
    } catch (error) {
      return LanSyncResult(ok: false, message: 'LAN pairing failed: $error');
    }
  }

  Future<LanSyncResult> testConnection(String host, {int port = 8787, String token = ''}) async {
    try {
      final client = _client();
      final request = await client.get(host.trim(), port, '/health');
      _attachToken(request, token);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      client.close(force: true);
      return LanSyncResult(ok: response.statusCode == 200, message: response.statusCode == 200 ? 'Connection is healthy.' : 'Host returned ${response.statusCode}: $body');
    } catch (error) {
      return LanSyncResult(ok: false, message: 'Connection failed: $error');
    }
  }

  Future<LanSyncResult> initialClone(String host, {int port = 8787, String token = '', LanSyncProgressCallback? onProgress}) async {
    try {
      onProgress?.call(0.20, 'Connecting to LAN Host snapshot...');
      final client = _client();
      final request = await client.get(host.trim(), port, '/snapshot');
      _attachToken(request, token);
      final response = await request.close();
      onProgress?.call(0.48, 'Downloading Host snapshot...');
      final body = await utf8.decoder.bind(response).join();
      client.close(force: true);
      if (response.statusCode != 200) {
        return LanSyncResult(ok: false, message: 'Initial clone failed: ${response.statusCode} $body');
      }
      onProgress?.call(0.72, 'Applying full Host snapshot locally...');
      await store.importSyncSnapshotJson(body);
      final hostCursor = store.syncSnapshotGeneratedAtFromJson(body);
      final settings = LanSyncSettings.load();
      onProgress?.call(0.94, 'Saving LAN sync cursor...');
      await settings.copyWith(lastPullCursor: hostCursor, lastConnectionAt: DateTime.now(), lastSyncAt: DateTime.now()).save();
      return const LanSyncResult(ok: true, message: 'Initial clone completed.');
    } catch (error) {
      return LanSyncResult(ok: false, message: 'Initial clone failed: $error');
    }
  }

  Future<LanSyncResult> pullNow(String host, {int port = 8787, String token = ''}) async {
    try {
      final client = _client();
      final request = await client.get(host.trim(), port, '/snapshot');
      _attachToken(request, token);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      client.close(force: true);
      if (response.statusCode != 200) {
        return LanSyncResult(ok: false, message: 'Pull failed: ${response.statusCode} $body');
      }
      await store.mergeBackupJson(body, markSynced: false);
      final hostCursor = store.syncSnapshotGeneratedAtFromJson(body);
      final settings = LanSyncSettings.load();
      await settings.copyWith(lastPullCursor: hostCursor, lastConnectionAt: DateTime.now(), lastSyncAt: DateTime.now()).save();
      return const LanSyncResult(ok: true, message: 'Pull completed.');
    } catch (error) {
      return LanSyncResult(ok: false, message: 'Pull failed: $error');
    }
  }


  Future<LanSyncResult> repairFromHostSnapshot(String host, {int port = 8787, String token = '', LanSyncProgressCallback? onProgress}) async {
    if (store.appIdentity.isHost) {
      return const LanSyncResult(ok: false, message: 'Host devices cannot rebuild from LAN Host snapshots. Use Transfer Host instead.');
    }
    try {
      onProgress?.call(0.20, 'Connecting to LAN Host snapshot...');
      final client = _client();
      final request = await client.get(host.trim(), port, '/snapshot');
      _attachToken(request, token);
      final response = await request.close();
      onProgress?.call(0.48, 'Downloading Host snapshot...');
      final body = await utf8.decoder.bind(response).join();
      client.close(force: true);
      if (response.statusCode != 200) {
        return LanSyncResult(ok: false, message: 'Repair snapshot failed: ${response.statusCode} $body');
      }
      onProgress?.call(0.72, 'Applying full Host snapshot locally...');
      await store.importSyncSnapshotJson(body);
      onProgress?.call(0.86, 'Marking rebuilt data as synced...');
      await store.markAllSyncChangesSynced();
      final hostCursor = store.syncSnapshotGeneratedAtFromJson(body);
      final settings = LanSyncSettings.load();
      await settings.copyWith(lastPullCursor: hostCursor, lastConnectionAt: DateTime.now(), lastSyncAt: DateTime.now()).save();
      onProgress?.call(1.0, 'LAN rebuild completed.');
      return const LanSyncResult(ok: true, message: 'LAN rebuild completed from full Host snapshot.');
    } catch (error) {
      return LanSyncResult(ok: false, message: 'Repair snapshot failed: $error');
    }
  }

  Future<LanSyncResult> syncNow(String host, {int port = 8787, String token = '', LanSyncProgressCallback? onProgress}) async {
    final settings = LanSyncSettings.load();
    final pending = store.pendingSyncChangesForTarget('host');

    // New Client bootstrap must use the Host snapshot, not the incremental
    // event stream. A Host can have valid products/customers/sales that were
    // created before LAN sync was enabled or imported from backup, so pulling
    // only /changes/pull on a fresh cursor can legitimately return zero events
    // and leave the Client empty.
    if (settings.isClient && settings.lastPullCursor == null && pending.isEmpty) {
      return initialClone(host, port: port, token: token, onProgress: onProgress);
    }

    final pendingIds = pending.map((item) => item.id).toList();
    var pushCompleted = pending.isEmpty;
    try {
      final client = _client();

      if (pending.isNotEmpty) {
        onProgress?.call(0.18, 'Preparing ${pending.length} local change(s) for LAN push...');
        await store.markSyncQueueChangesInProgress(pendingIds);
        onProgress?.call(0.32, 'Uploading local changes to Host...');
        final pushRequest = await client.post(host.trim(), port, '/changes/push');
        _attachToken(pushRequest, token);
        pushRequest.headers.contentType = ContentType.json;
        pushRequest.write(jsonEncode({
          'deviceId': store.deviceId,
          'storeId': store.appIdentity.storeId,
          'branchId': store.appIdentity.branchId,
          'cursor': settings.lastPullCursor?.toIso8601String(),
          'changes': pending.map((item) => item.toJson()).toList(),
        }));
        final pushResponse = await pushRequest.close();
        final pushBody = await utf8.decoder.bind(pushResponse).join();
        if (pushResponse.statusCode != 200) {
          client.close(force: true);
          final message = 'Push failed: ${pushResponse.statusCode} $pushBody';
          await store.markSyncQueueChangesFailed(pendingIds, message);
          return LanSyncResult(ok: false, message: message);
        }
        final decoded = jsonDecode(pushBody) as Map<String, dynamic>;
        final ackIds = (decoded['ackIds'] as List<dynamic>? ?? []).map((item) => '$item').toList();
        onProgress?.call(0.48, 'Host acknowledged ${ackIds.length} pushed change(s)...');
        await store.markSyncChangesSyncedByIds(ackIds);
        pushCompleted = true;
      }

      final path = settings.lastPullCursor == null
          ? '/changes/pull'
          : '/changes/pull?since=${Uri.encodeQueryComponent(settings.lastPullCursor!.toIso8601String())}';
      onProgress?.call(0.62, 'Pulling new changes from LAN Host...');
      final pullRequest = await client.get(host.trim(), port, path);
      _attachToken(pullRequest, token);
      final pullResponse = await pullRequest.close();
      final pullBody = await utf8.decoder.bind(pullResponse).join();
      client.close(force: true);
      if (pullResponse.statusCode != 200) {
        final message = 'Pull changes failed: ${pullResponse.statusCode} $pullBody';
        final repair = pushCompleted ? await repairFromHostSnapshot(host, port: port, token: token, onProgress: onProgress) : null;
        if (repair?.ok == true) return LanSyncResult(ok: true, message: '$message. ${repair!.message}');
        if (pendingIds.isNotEmpty && !pushCompleted) await store.markSyncQueueChangesFailed(pendingIds, message);
        return LanSyncResult(ok: false, message: repair == null ? message : '$message. ${repair.message}');
      }
      final decodedPull = jsonDecode(pullBody) as Map<String, dynamic>;
      final changes = (decodedPull['changes'] as List<dynamic>? ?? [])
          .map((item) => SyncChange.fromJson(Map<String, dynamic>.from(item as Map)))
          .where((item) => item.deviceId != store.deviceId)
          .toList();
      onProgress?.call(0.78, 'Applying ${changes.length} LAN change(s) locally...');
      await store.applyRemoteSyncChanges(changes, markAppliedAsSynced: true);
      final generatedAt = DateTime.tryParse(decodedPull['generatedAt'] as String? ?? '') ?? DateTime.now();
      onProgress?.call(0.92, 'Saving LAN sync cursor...');
      await settings.copyWith(lastPullCursor: generatedAt, lastConnectionAt: DateTime.now(), lastSyncAt: DateTime.now()).save();
      onProgress?.call(1.0, 'LAN sync completed.');
      return LanSyncResult(
        ok: true,
        message: 'Sync completed. Pushed ${pending.length} change(s), pulled ${changes.length} change(s).',
      );
    } catch (error) {
      if (pushCompleted) {
        final repair = await repairFromHostSnapshot(host, port: port, token: token, onProgress: onProgress);
        if (repair.ok) return LanSyncResult(ok: true, message: 'Incremental sync failed: $error. ${repair.message}');
      }
      if (pendingIds.isNotEmpty && !pushCompleted) await store.markSyncQueueChangesFailed(pendingIds, error.toString());
      return LanSyncResult(ok: false, message: 'Sync failed: $error');
    }
  }
}

class AutoLanSyncController {
  AutoLanSyncController(this.store) : _service = LanSyncService(store);

  final AppStore store;
  final LanSyncService _service;
  Timer? _periodicTimer;
  Timer? _debounceTimer;
  bool _running = false;
  bool _disposed = false;
  int _lastPendingCount = 0;
  String _lastSettingsSignature = '';

  String _settingsSignature(LanSyncSettings settings) => [
        settings.setupComplete,
        settings.mode.name,
        settings.hostModeEnabled,
        settings.host.trim(),
        settings.port,
        settings.autoSyncEnabled,
        settings.secret.trim(),
      ].join('|');

  bool _lanAllowedForCurrentRole(LanSyncSettings settings) {
    final identity = store.appIdentity;
    if (identity.isHost) return settings.setupComplete && settings.isHost;
    if (identity.isClient) {
      return identity.syncMode == SyncMode.lanOnly && settings.setupComplete && settings.isClient;
    }
    return false;
  }

  Future<void> start() async {
    _disposed = false;
    final settings = LanSyncSettings.load();
    _lastSettingsSignature = _settingsSignature(settings);
    _lastPendingCount = store.pendingSyncCount;

    if (!_lanAllowedForCurrentRole(settings)) {
      await _service.stopHost();
      store.removeListener(_onStoreChanged);
      _periodicTimer?.cancel();
      _debounceTimer?.cancel();
      return;
    }

    if (store.appIdentity.isHost && settings.isHost) {
      try {
        await _service.startHost(port: settings.port);
      } catch (_) {}
    }

    store.removeListener(_onStoreChanged);
    store.addListener(_onStoreChanged);
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(seconds: 30), (_) => _syncBecauseOfTimer());

    if (store.appIdentity.isClient && settings.autoSyncEnabled && settings.isClient) {
      unawaited(_runClientSync());
    }
  }

  Future<void> stop() async {
    _disposed = true;
    store.removeListener(_onStoreChanged);
    _periodicTimer?.cancel();
    _debounceTimer?.cancel();
    unawaited(_service.stopHost());
  }

  void _onStoreChanged() {
    if (_disposed) return;
    final settings = LanSyncSettings.load();
    final signature = _settingsSignature(settings);
    if (signature != _lastSettingsSignature) {
      _lastSettingsSignature = signature;
      unawaited(_applySettingsChange(settings));
    }
    final pending = store.pendingSyncCount;
    final pendingIncreased = pending > _lastPendingCount;
    _lastPendingCount = pending;
    if (!_lanAllowedForCurrentRole(settings) || !settings.autoSyncEnabled || !settings.isClient || !pendingIncreased) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 1), () => _runClientSync());
  }

  void _syncBecauseOfTimer() {
    final settings = LanSyncSettings.load();
    final signature = _settingsSignature(settings);
    if (signature != _lastSettingsSignature) {
      _lastSettingsSignature = signature;
      unawaited(_applySettingsChange(settings));
    }
    if (!_lanAllowedForCurrentRole(settings)) {
      unawaited(_service.stopHost());
      return;
    }
    if (store.appIdentity.isHost && settings.isHost) {
      if (!_service.isHosting || _service.port != settings.port) {
        unawaited(_service.startHost(port: settings.port));
      }
      return;
    }
    if (!settings.autoSyncEnabled) return;
    // Keep LAN reconnects responsive: failed items are moved back to pending
    // on the next auto tick instead of waiting for long backoff windows.
    unawaited(store.retryFailedSyncQueue(target: 'host'));
    unawaited(_runClientSync());
  }

  Future<void> _applySettingsChange(LanSyncSettings settings) async {
    if (_disposed) return;
    if (!_lanAllowedForCurrentRole(settings) || !settings.isHost) {
      unawaited(_service.stopHost());
    } else if (!_service.isHosting || _service.port != settings.port) {
      await _service.startHost(port: settings.port);
    }
    if (store.appIdentity.isClient && _lanAllowedForCurrentRole(settings) && settings.autoSyncEnabled && settings.isClient) {
      await store.retryFailedSyncQueue(target: 'host');
      await _runClientSync();
    }
  }

  Future<void> _runClientSync() async {
    if (_running || _disposed) return;
    final settings = LanSyncSettings.load();
    if (!_lanAllowedForCurrentRole(settings) || !settings.autoSyncEnabled || !settings.isClient || settings.host.trim().isEmpty) return;

    _running = true;
    try {
      await store.retryFailedSyncQueue(target: 'host');
      final result = await _service.syncNow(settings.host, port: settings.port, token: settings.secret);
      if (result.ok) {
        _lastPendingCount = store.pendingSyncCount;
      }
    } finally {
      _running = false;
    }
  }
}
