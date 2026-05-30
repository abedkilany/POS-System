import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'dart:math';

import '../../data/app_store.dart';
import '../../models/app_identity.dart';
import '../../models/sync_change.dart';
import 'local_database_service.dart';
import 'unified_sync_core_service.dart';
import '../sync_unified/sync_device_state.dart';

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
  late final UnifiedSyncCoreService _syncCore = UnifiedSyncCoreService(store);
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
      final receivedDeviceId = request.headers.value('x-device-id');
      final receivedDeviceToken = request.headers.value('x-device-token');

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
        final sinceSequence = int.tryParse(request.uri.queryParameters['since_sequence'] ?? '') ?? 0;
        // Pull is delivery only. The Host must not mark changes as applied or
        // ACKed until the Client posts /changes/ack after local apply succeeds.
        request.response.headers.contentType = ContentType.json;
        request.response.write(store.exportSyncChangesJson(since: since, sinceSequence: sinceSequence));
        await request.response.close();
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/changes/ack') {
        final body = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final clientDeviceId = decoded['deviceId']?.toString() ?? receivedDeviceId ?? '';
        final cursor = DateTime.tryParse(decoded['lastAppliedCursor']?.toString() ?? decoded['lastAckCursor']?.toString() ?? '');
        final sequence = int.tryParse(decoded['lastAppliedSequence']?.toString() ?? decoded['lastAckSequence']?.toString() ?? '') ?? 0;
        await SyncDeviceStateStore.recordPeerSyncResult(
          deviceId: clientDeviceId,
          transport: 'lan',
          appliedCursor: cursor,
          ackCursor: cursor,
          appliedSequence: sequence,
          ackSequence: sequence,
        );
        await _json(request, {'ok': true, 'serverTime': DateTime.now().toIso8601String()});
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
        final clientCursor = DateTime.tryParse(decoded['cursor']?.toString() ?? '');
        final clientSequence = int.tryParse(decoded['sequence']?.toString() ?? decoded['lastAppliedSequence']?.toString() ?? '') ?? 0;
        final accepted = await _syncCore.acceptClientChangesOnHost(
          changes,
          mirrorToCloud: store.appIdentity.isCloudEnabled && store.appIdentity.isHost,
        );
        await SyncDeviceStateStore.recordPeerSyncResult(
          deviceId: decoded['deviceId']?.toString() ?? receivedDeviceId ?? '',
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
          'rejected': accepted.rejected.entries.map((entry) => {'id': entry.key, 'reason': entry.value}).toList(),
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
            'error': 'Legacy LAN sync endpoint disabled. Use /changes/push and /changes/pull.',
          },
          status: HttpStatus.gone,
        );
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
    // A Client may configure both LAN and Cloud transports. Pairing LAN only
    // prepares another delivery method; the active transport still decides
    // which one auto-sync runs.
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
        activeSyncTransport: 'lan',
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
      await SyncDeviceStateStore.recordSyncResult(store.appIdentity, transport: 'lan', appliedCursor: hostCursor, ackCursor: hostCursor);
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
      final hostSequence = store.syncSnapshotGeneratedSequenceFromJson(body);
      await SyncDeviceStateStore.recordSyncResult(store.appIdentity, transport: 'lan', appliedCursor: hostCursor, ackCursor: hostCursor, appliedSequence: hostSequence, ackSequence: hostSequence);
      await _sendLanAck(host, port: port, token: token, cursor: hostCursor, sequence: hostSequence);
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
      final hostSequence = store.syncSnapshotGeneratedSequenceFromJson(body);
      await SyncDeviceStateStore.recordSyncResult(store.appIdentity, transport: 'lan', appliedCursor: hostCursor, ackCursor: hostCursor, appliedSequence: hostSequence, ackSequence: hostSequence);
      await _sendLanAck(host, port: port, token: token, cursor: hostCursor, sequence: hostSequence);
      onProgress?.call(1.0, 'LAN rebuild completed.');
      return const LanSyncResult(ok: true, message: 'LAN rebuild completed from full Host snapshot.');
    } catch (error) {
      return LanSyncResult(ok: false, message: 'Repair snapshot failed: $error');
    }
  }



  Map<String, String> _decodeRejectedSyncRequests(dynamic raw) {
    final output = <String, String>{};
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final id = (item['id'] ?? '').toString();
          if (id.isNotEmpty) output[id] = (item['reason'] ?? 'Rejected by Host.').toString();
        }
      }
    }
    return output;
  }

  Future<void> _sendLanAck(String host, {int port = 8787, String token = '', required DateTime cursor, int sequence = 0}) async {
    try {
      final client = _client();
      final request = await client.post(host.trim(), port, '/changes/ack');
      _attachToken(request, token);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'deviceId': store.deviceId,
        'storeId': store.appIdentity.storeId,
        'branchId': store.appIdentity.branchId,
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

  Future<LanSyncResult> pushPendingOnly(String host, {int port = 8787, String token = '', LanSyncProgressCallback? onProgress}) async {
    final pending = _syncCore.pendingChangesForTarget('host');
    final pendingIds = _syncCore.changeIds(pending);
    if (pending.isEmpty) return const LanSyncResult(ok: true, message: 'No LAN changes to push.');
    try {
      final client = _client();
      onProgress?.call(0.18, 'Preparing ${pending.length} local change(s) for LAN push...');
      await _syncCore.markPushInProgress(pendingIds);
      final pushRequest = await client.post(host.trim(), port, '/changes/push');
      _attachToken(pushRequest, token);
      pushRequest.headers.contentType = ContentType.json;
      pushRequest.write(jsonEncode({
        'deviceId': store.deviceId,
        'storeId': store.appIdentity.storeId,
        'branchId': store.appIdentity.branchId,
        'cursor': LanSyncSettings.load().lastPullCursor?.toIso8601String(),
        'sequence': SyncDeviceStateStore.load(store.appIdentity).lastAppliedSequence,
        'changes': pending.map((item) => item.toJson()).toList(),
      }));
      final pushResponse = await pushRequest.close();
      final pushBody = await utf8.decoder.bind(pushResponse).join();
      client.close(force: true);
      if (pushResponse.statusCode != 200) {
        final message = 'Push failed: ${pushResponse.statusCode} $pushBody';
        await _syncCore.markPushFailed(pendingIds, message);
        return LanSyncResult(ok: false, message: message);
      }
      final decoded = jsonDecode(pushBody) as Map<String, dynamic>;
      final ackIds = (decoded['ackIds'] as List<dynamic>? ?? []).map((item) => '$item').toList();
      final rejected = _decodeRejectedSyncRequests(decoded['rejected']);
      if (rejected.isNotEmpty) await _syncCore.markPushRejected(rejected);
      await _syncCore.markPushSubmitted(ackIds, fallbackIds: pendingIds);
      return LanSyncResult(ok: true, message: 'LAN push completed. Pushed ${pending.length} change(s).');
    } catch (error) {
      await _syncCore.markPushFailed(pendingIds, error.toString());
      return LanSyncResult(ok: false, message: 'LAN push failed: $error');
    }
  }

  Future<LanSyncResult> pullChangesOnly(String host, {int port = 8787, String token = '', LanSyncProgressCallback? onProgress}) async {
    final settings = LanSyncSettings.load();
    try {
      final client = _client();
      final ackCursor = settings.lastPullCursor?.toIso8601String() ?? '';
      final lastSequence = SyncDeviceStateStore.load(store.appIdentity).lastAppliedSequence;
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
        return LanSyncResult(ok: false, message: 'Pull changes failed: ${pullResponse.statusCode} $pullBody');
      }
      final decodedPull = jsonDecode(pullBody) as Map<String, dynamic>;
      final changes = _syncCore.filterOutLocalEchoes(
        _syncCore.decodeRemoteChanges(decodedPull['changes'] as List<dynamic>?),
      );
      onProgress?.call(0.78, 'Applying ${changes.length} LAN change(s) locally...');
      await _syncCore.applyAuthoritativeChanges(changes);
      final generatedAt = DateTime.tryParse(decodedPull['generatedAt'] as String? ?? '') ?? DateTime.now();
      final generatedSequence = int.tryParse(decodedPull['generatedSequence']?.toString() ?? '') ?? 0;
      await settings.copyWith(lastPullCursor: generatedAt, lastConnectionAt: DateTime.now(), lastSyncAt: DateTime.now()).save();
      await SyncDeviceStateStore.recordSyncResult(store.appIdentity, transport: 'lan', appliedCursor: generatedAt, ackCursor: generatedAt, appliedSequence: generatedSequence, ackSequence: generatedSequence);
      await _sendLanAck(host, port: port, token: token, cursor: generatedAt, sequence: generatedSequence);
      return LanSyncResult(ok: true, message: 'LAN pull completed. Pulled ${changes.length} change(s).');
    } catch (error) {
      return LanSyncResult(ok: false, message: 'LAN pull failed: $error');
    }
  }

  Future<LanSyncResult> syncNow(String host, {int port = 8787, String token = '', LanSyncProgressCallback? onProgress}) async {
    final settings = LanSyncSettings.load();
    final pending = _syncCore.pendingChangesForTarget('host');

    // New Client bootstrap must use the Host snapshot, not the incremental
    // event stream. A Host can have valid products/customers/sales that were
    // created before LAN sync was enabled or imported from backup, so pulling
    // only /changes/pull on a fresh cursor can legitimately return zero events
    // and leave the Client empty.
    if (settings.isClient && settings.lastPullCursor == null && pending.isEmpty) {
      return initialClone(host, port: port, token: token, onProgress: onProgress);
    }

    final pendingIds = _syncCore.changeIds(pending);
    var pushCompleted = pending.isEmpty;
    try {
      final client = _client();

      if (pending.isNotEmpty) {
        onProgress?.call(0.18, 'Preparing ${pending.length} local change(s) for LAN push...');
        await _syncCore.markPushInProgress(pendingIds);
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
          await _syncCore.markPushFailed(pendingIds, message);
          return LanSyncResult(ok: false, message: message);
        }
        final decoded = jsonDecode(pushBody) as Map<String, dynamic>;
        final ackIds = (decoded['ackIds'] as List<dynamic>? ?? []).map((item) => '$item').toList();
        final rejected = _decodeRejectedSyncRequests(decoded['rejected']);
        if (rejected.isNotEmpty) await _syncCore.markPushRejected(rejected);
        onProgress?.call(0.48, 'Host accepted ${ackIds.length} pushed change(s)...');
        await _syncCore.markPushSubmitted(ackIds);
        pushCompleted = true;
      }

      final ackCursor = settings.lastPullCursor?.toIso8601String() ?? '';
      final lastSequence = SyncDeviceStateStore.load(store.appIdentity).lastAppliedSequence;
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
        final message = 'Pull changes failed: ${pullResponse.statusCode} $pullBody';
        final repair = pushCompleted ? await repairFromHostSnapshot(host, port: port, token: token, onProgress: onProgress) : null;
        if (repair?.ok == true) return LanSyncResult(ok: true, message: '$message. ${repair!.message}');
        if (pendingIds.isNotEmpty && !pushCompleted) await _syncCore.markPushFailed(pendingIds, message);
        return LanSyncResult(ok: false, message: repair == null ? message : '$message. ${repair.message}');
      }
      final decodedPull = jsonDecode(pullBody) as Map<String, dynamic>;
      final changes = _syncCore.filterOutLocalEchoes(
        _syncCore.decodeRemoteChanges(decodedPull['changes'] as List<dynamic>?),
      );
      onProgress?.call(0.78, 'Applying ${changes.length} LAN change(s) locally...');
      await _syncCore.applyAuthoritativeChanges(changes);
      final generatedAt = DateTime.tryParse(decodedPull['generatedAt'] as String? ?? '') ?? DateTime.now();
      final generatedSequence = int.tryParse(decodedPull['generatedSequence']?.toString() ?? '') ?? 0;
      onProgress?.call(0.92, 'Saving LAN sync cursor...');
      await settings.copyWith(lastPullCursor: generatedAt, lastConnectionAt: DateTime.now(), lastSyncAt: DateTime.now()).save();
      await SyncDeviceStateStore.recordSyncResult(store.appIdentity, transport: 'lan', appliedCursor: generatedAt, ackCursor: generatedAt, appliedSequence: generatedSequence, ackSequence: generatedSequence);
      await _sendLanAck(host, port: port, token: token, cursor: generatedAt, sequence: generatedSequence);
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
      if (pendingIds.isNotEmpty && !pushCompleted) await _syncCore.markPushFailed(pendingIds, error.toString());
      return LanSyncResult(ok: false, message: 'Sync failed: $error');
    }
  }
}
