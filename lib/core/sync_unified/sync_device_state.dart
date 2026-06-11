import 'dart:convert';

import '../../models/app_identity.dart';
import '../services/local_database_service.dart';

/// Transport-independent sync progress for a single device.
///
/// The Host remains the authority for accepted changes. LAN and Cloud are only
/// delivery methods, so a Client must carry one device-level progress marker
/// when switching between transports. This store intentionally lives above the
/// legacy LAN/Cloud cursor keys to allow a safe staged migration.
class SyncDeviceState {
  const SyncDeviceState({
    required this.deviceId,
    required this.storeId,
    required this.branchId,
    this.hostDeviceId = '',
    this.activeTransport = 'local',
    this.lastAppliedHostCursor,
    this.lastAckCursor,
    this.lastAppliedSequence = 0,
    this.lastAckSequence = 0,
    this.lastSyncTransport = '',
    this.lastSeenAt,
    this.updatedAt,
  });

  final String deviceId;
  final String storeId;
  final String branchId;
  final String hostDeviceId;
  final String activeTransport;
  final DateTime? lastAppliedHostCursor;
  final DateTime? lastAckCursor;
  final int lastAppliedSequence;
  final int lastAckSequence;
  final String lastSyncTransport;
  final DateTime? lastSeenAt;
  final DateTime? updatedAt;

  SyncDeviceState copyWith({
    String? deviceId,
    String? storeId,
    String? branchId,
    String? hostDeviceId,
    String? activeTransport,
    DateTime? lastAppliedHostCursor,
    DateTime? lastAckCursor,
    int? lastAppliedSequence,
    int? lastAckSequence,
    String? lastSyncTransport,
    DateTime? lastSeenAt,
    DateTime? updatedAt,
    bool clearLastAppliedHostCursor = false,
    bool clearLastAckCursor = false,
  }) {
    return SyncDeviceState(
      deviceId: deviceId ?? this.deviceId,
      storeId: storeId ?? this.storeId,
      branchId: branchId ?? this.branchId,
      hostDeviceId: hostDeviceId ?? this.hostDeviceId,
      activeTransport: activeTransport ?? this.activeTransport,
      lastAppliedHostCursor: clearLastAppliedHostCursor ? null : (lastAppliedHostCursor ?? this.lastAppliedHostCursor),
      lastAckCursor: clearLastAckCursor ? null : (lastAckCursor ?? this.lastAckCursor),
      lastAppliedSequence: lastAppliedSequence ?? this.lastAppliedSequence,
      lastAckSequence: lastAckSequence ?? this.lastAckSequence,
      lastSyncTransport: lastSyncTransport ?? this.lastSyncTransport,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'storeId': storeId,
        'branchId': branchId,
        'hostDeviceId': hostDeviceId,
        'activeTransport': activeTransport,
        'lastAppliedHostCursor': lastAppliedHostCursor?.toIso8601String(),
        'lastAckCursor': lastAckCursor?.toIso8601String(),
        'lastAppliedSequence': lastAppliedSequence,
        'lastAckSequence': lastAckSequence,
        'lastSyncTransport': lastSyncTransport,
        'lastSeenAt': lastSeenAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory SyncDeviceState.fromJson(Map<String, dynamic> json, AppIdentity identity) {
    final activeRaw = (json['activeTransport']?.toString() ?? '').trim();
    return SyncDeviceState(
      deviceId: json['deviceId']?.toString() ?? identity.deviceId,
      storeId: json['storeId']?.toString() ?? identity.storeId,
      branchId: json['branchId']?.toString() ?? identity.branchId,
      hostDeviceId: json['hostDeviceId']?.toString() ?? identity.hostDeviceId,
      activeTransport: _normalizeTransport(activeRaw.isNotEmpty ? activeRaw : identity.activeSyncTransport),
      lastAppliedHostCursor: DateTime.tryParse(json['lastAppliedHostCursor']?.toString() ?? ''),
      lastAckCursor: DateTime.tryParse(json['lastAckCursor']?.toString() ?? ''),
      lastAppliedSequence: int.tryParse(json['lastAppliedSequence']?.toString() ?? '') ?? 0,
      lastAckSequence: int.tryParse(json['lastAckSequence']?.toString() ?? '') ?? 0,
      lastSyncTransport: json['lastSyncTransport']?.toString() ?? '',
      lastSeenAt: DateTime.tryParse(json['lastSeenAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  static SyncDeviceState defaults(AppIdentity identity) => SyncDeviceState(
        deviceId: identity.deviceId,
        storeId: identity.storeId,
        branchId: identity.branchId,
        hostDeviceId: identity.hostDeviceId,
        activeTransport: identity.activeSyncTransport,
        updatedAt: DateTime.now(),
      );
}



class HostPeerSyncState {
  const HostPeerSyncState({
    required this.deviceId,
    this.lastAppliedHostCursor,
    this.lastAckCursor,
    this.lastAppliedSequence = 0,
    this.lastAckSequence = 0,
    this.lastSyncTransport = '',
    this.lastSeenAt,
    this.updatedAt,
  });

  final String deviceId;
  final DateTime? lastAppliedHostCursor;
  final DateTime? lastAckCursor;
  final int lastAppliedSequence;
  final int lastAckSequence;
  final String lastSyncTransport;
  final DateTime? lastSeenAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'lastAppliedHostCursor': lastAppliedHostCursor?.toIso8601String(),
        'lastAckCursor': lastAckCursor?.toIso8601String(),
        'lastAppliedSequence': lastAppliedSequence,
        'lastAckSequence': lastAckSequence,
        'lastSyncTransport': lastSyncTransport,
        'lastSeenAt': lastSeenAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory HostPeerSyncState.fromJson(Map<String, dynamic> json) => HostPeerSyncState(
        deviceId: json['deviceId']?.toString() ?? '',
        lastAppliedHostCursor: DateTime.tryParse(json['lastAppliedHostCursor']?.toString() ?? ''),
        lastAckCursor: DateTime.tryParse(json['lastAckCursor']?.toString() ?? ''),
        lastAppliedSequence: int.tryParse(json['lastAppliedSequence']?.toString() ?? '') ?? 0,
        lastAckSequence: int.tryParse(json['lastAckSequence']?.toString() ?? '') ?? 0,
        lastSyncTransport: json['lastSyncTransport']?.toString() ?? '',
        lastSeenAt: DateTime.tryParse(json['lastSeenAt']?.toString() ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      );
}

class SyncDeviceStateStore {
  SyncDeviceStateStore._();

  static const String _stateKey = 'host_authoritative_sync_device_state_v1';
  static const String _cloudCursorKey = 'cloud_last_pull_cursor';
  static const String _lanSettingsKey = 'lan_sync_settings_v2';
  static const String _hostPeerStatesKey = 'host_authoritative_sync_peer_states_v1';

  static SyncDeviceState load(AppIdentity identity) {
    final raw = LocalDatabaseService.getString(_stateKey);
    SyncDeviceState state;
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        state = SyncDeviceState.fromJson(jsonDecode(raw) as Map<String, dynamic>, identity);
      } catch (_) {
        state = SyncDeviceState.defaults(identity);
      }
    } else {
      state = SyncDeviceState.defaults(identity);
    }

    final legacyCursor = _bestLegacyCursor();
    if (state.lastAppliedHostCursor == null && legacyCursor != null) {
      state = state.copyWith(lastAppliedHostCursor: legacyCursor, updatedAt: DateTime.now());
    }
    return state;
  }

  static Future<SyncDeviceState> save(AppIdentity identity, SyncDeviceState state) async {
    final normalized = state.copyWith(
      deviceId: identity.deviceId,
      storeId: identity.storeId,
      branchId: identity.branchId,
      hostDeviceId: identity.hostDeviceId,
      activeTransport: _normalizeTransport(state.activeTransport),
      updatedAt: DateTime.now(),
    );
    await LocalDatabaseService.setString(_stateKey, jsonEncode(normalized.toJson()));
    return normalized;
  }

  static DateTime? unifiedCursor(AppIdentity identity) => load(identity).lastAppliedHostCursor;

  /// Clears local client progress so the next Cloud/LAN pull can rebuild from
  /// a fresh Host snapshot instead of continuing after an old event sequence.
  static Future<void> resetClientProgress(AppIdentity identity, {String transport = 'cloud'}) async {
    final current = load(identity);
    await save(
      identity,
      current.copyWith(
        activeTransport: transport,
        lastAppliedSequence: 0,
        lastAckSequence: 0,
        lastSyncTransport: transport,
        clearLastAppliedHostCursor: true,
        clearLastAckCursor: true,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Returns the best transport-independent marker for a successful sync.
  ///
  /// Clients store their own progress in [SyncDeviceState]. Hosts may only
  /// record successful exchanges per connected peer, so Host health must also
  /// consider [HostPeerSyncState]. This keeps Desktop, Android, LAN and Cloud
  /// status labels consistent.
  static DateTime? lastSuccessfulSyncAt(AppIdentity identity) {
    final state = load(identity);
    var latest = _latest(state.lastAckCursor, state.lastAppliedHostCursor);
    latest = _latest(latest, state.lastSeenAt);

    if (identity.isHost) {
      for (final peer in loadPeerStates()) {
        var peerLatest = _latest(peer.lastAckCursor, peer.lastAppliedHostCursor);
        peerLatest = _latest(peerLatest, peer.lastSeenAt);
        peerLatest = _latest(peerLatest, peer.updatedAt);
        latest = _latest(latest, peerLatest);
      }
    }

    return latest;
  }

  static Future<void> setActiveTransport(AppIdentity identity, String transport) async {
    final current = load(identity);
    await save(identity, current.copyWith(activeTransport: transport, updatedAt: DateTime.now()));
  }

  static Future<void> recordSyncResult(
    AppIdentity identity, {
    required String transport,
    DateTime? appliedCursor,
    DateTime? ackCursor,
    int? appliedSequence,
    int? ackSequence,
    bool online = true,
  }) async {
    final current = load(identity);
    await save(
      identity,
      current.copyWith(
        activeTransport: transport,
        lastSyncTransport: transport,
        lastAppliedHostCursor: appliedCursor ?? current.lastAppliedHostCursor,
        lastAckCursor: ackCursor ?? appliedCursor ?? current.lastAckCursor,
        lastAppliedSequence: _latestInt(current.lastAppliedSequence, appliedSequence),
        lastAckSequence: _latestInt(current.lastAckSequence, ackSequence ?? appliedSequence),
        lastSeenAt: online ? DateTime.now() : current.lastSeenAt,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Returns the cursor that should seed a legacy transport before a sync run.
  /// This lets Cloud and LAN continue using their current APIs while sharing a
  /// transport-independent progress marker.
  static DateTime? cursorForTransport(AppIdentity identity, String transport, DateTime? currentTransportCursor) {
    final state = load(identity);
    return _latest(state.lastAppliedHostCursor, currentTransportCursor);
  }



  static List<HostPeerSyncState> loadPeerStates() {
    final raw = LocalDatabaseService.getString(_hostPeerStatesKey);
    if (raw == null || raw.trim().isEmpty) return const <HostPeerSyncState>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => HostPeerSyncState.fromJson(Map<String, dynamic>.from(item as Map)))
          .where((item) => item.deviceId.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const <HostPeerSyncState>[];
    }
  }

  static Future<void> recordPeerSyncResult({
    required String deviceId,
    required String transport,
    DateTime? appliedCursor,
    DateTime? ackCursor,
    int? appliedSequence,
    int? ackSequence,
  }) async {
    final id = deviceId.trim();
    if (id.isEmpty) return;
    final now = DateTime.now();
    final states = loadPeerStates();
    final byId = <String, HostPeerSyncState>{for (final state in states) state.deviceId: state};
    final current = byId[id];
    byId[id] = HostPeerSyncState(
      deviceId: id,
      lastAppliedHostCursor: _latest(current?.lastAppliedHostCursor, appliedCursor),
      lastAckCursor: _latest(current?.lastAckCursor, ackCursor ?? appliedCursor),
      lastAppliedSequence: _latestInt(current?.lastAppliedSequence ?? 0, appliedSequence),
      lastAckSequence: _latestInt(current?.lastAckSequence ?? 0, ackSequence ?? appliedSequence),
      lastSyncTransport: _normalizeTransport(transport),
      lastSeenAt: now,
      updatedAt: now,
    );
    await LocalDatabaseService.setString(
      _hostPeerStatesKey,
      jsonEncode(byId.values.map((item) => item.toJson()).toList()),
    );
  }

  static Future<void> removePeerState(String deviceId) async {
    final id = deviceId.trim();
    if (id.isEmpty) return;
    final states = loadPeerStates().where((state) => state.deviceId != id).toList();
    await LocalDatabaseService.setString(
      _hostPeerStatesKey,
      jsonEncode(states.map((item) => item.toJson()).toList()),
    );
  }

  static DateTime? _bestLegacyCursor() {
    final cloud = DateTime.tryParse(LocalDatabaseService.getString(_cloudCursorKey) ?? '');
    DateTime? lan;
    final rawLan = LocalDatabaseService.getString(_lanSettingsKey);
    if (rawLan != null && rawLan.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawLan) as Map<String, dynamic>;
        lan = DateTime.tryParse(decoded['lastPullCursor']?.toString() ?? '');
      } catch (_) {}
    }
    return _latest(cloud, lan);
  }

  static int _latestInt(int a, int? b) {
    final next = b ?? 0;
    return next > a ? next : a;
  }

  static DateTime? _latest(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }
}


class ClientSuspensionStateStore {
  ClientSuspensionStateStore._();

  static const String _suspendedKey = 'client_suspended_by_host_v1';
  static const String _reasonKey = 'client_suspended_by_host_reason_v1';
  static const String _updatedAtKey = 'client_suspended_by_host_updated_at_v1';

  static bool get isSuspended => (LocalDatabaseService.getString(_suspendedKey) ?? '').trim() == 'true';
  static String get reason => LocalDatabaseService.getString(_reasonKey) ?? '';
  static DateTime? get updatedAt => DateTime.tryParse(LocalDatabaseService.getString(_updatedAtKey) ?? '');

  static Future<void> markSuspended({String reason = ''}) async {
    await LocalDatabaseService.setString(_suspendedKey, 'true');
    await LocalDatabaseService.setString(_reasonKey, reason.trim().isEmpty ? 'This device has been suspended by the Host.' : reason.trim());
    await LocalDatabaseService.setString(_updatedAtKey, DateTime.now().toIso8601String());
  }

  static Future<void> clear() async {
    await LocalDatabaseService.setString(_suspendedKey, 'false');
    await LocalDatabaseService.setString(_reasonKey, '');
    await LocalDatabaseService.setString(_updatedAtKey, DateTime.now().toIso8601String());
  }
}


class SyncDeviceAccessStore {
  SyncDeviceAccessStore._();

  static const String _suspendedDevicesKey = 'sync_monitoring_suspended_devices_v1';
  static const String _deletedDevicesKey = 'sync_monitoring_deleted_devices_v1';
  static const String _deletedDeviceTokensKey = 'sync_monitoring_deleted_device_tokens_v1';
  static const String _wipePendingDevicesKey = 'sync_monitoring_wipe_pending_devices_v1';
  static const String _wipePendingDeviceTokensKey = 'sync_monitoring_wipe_pending_device_tokens_v1';

  static Set<String> suspendedDeviceIds() => _loadSet(_suspendedDevicesKey);
  static Set<String> deletedDeviceIds() => _loadSet(_deletedDevicesKey);
  static Set<String> wipePendingDeviceIds() => _loadSet(_wipePendingDevicesKey);

  static bool isSuspended(String deviceId) => suspendedDeviceIds().contains(deviceId.trim());
  static bool isDeleted(String deviceId) => deletedDeviceIds().contains(deviceId.trim());
  static bool isWipePending(String deviceId) => wipePendingDeviceIds().contains(deviceId.trim());

  static Map<String, String> deletedDeviceTokens() => _loadMap(_deletedDeviceTokensKey);
  static Map<String, String> wipePendingDeviceTokens() => _loadMap(_wipePendingDeviceTokensKey);

  static bool deletedTokenMatches(String deviceId, String token) {
    final id = deviceId.trim();
    final expected = deletedDeviceTokens()[id]?.trim() ?? '';
    return id.isNotEmpty && expected.isNotEmpty && expected == token.trim();
  }

  static bool wipePendingTokenMatches(String deviceId, String token) {
    final id = deviceId.trim();
    final expected = wipePendingDeviceTokens()[id]?.trim() ?? '';
    return id.isNotEmpty && expected.isNotEmpty && expected == token.trim();
  }

  static Future<void> suspend(String deviceId) async {
    final id = deviceId.trim();
    if (id.isEmpty) return;
    final suspended = suspendedDeviceIds()..add(id);
    await _saveSet(_suspendedDevicesKey, suspended);
  }

  static Future<void> resume(String deviceId) async {
    final id = deviceId.trim();
    if (id.isEmpty) return;
    final suspended = suspendedDeviceIds()..remove(id);
    await _saveSet(_suspendedDevicesKey, suspended);
  }

  static Future<void> markWipePending(String deviceId, {String deviceToken = ''}) async {
    final id = deviceId.trim();
    if (id.isEmpty) return;
    final pending = wipePendingDeviceIds()..add(id);
    final suspended = suspendedDeviceIds()..remove(id);
    final tokens = wipePendingDeviceTokens();
    if (deviceToken.trim().isNotEmpty) tokens[id] = deviceToken.trim();
    await _saveSet(_wipePendingDevicesKey, pending);
    await _saveSet(_suspendedDevicesKey, suspended);
    await _saveMap(_wipePendingDeviceTokensKey, tokens);
  }

  static Future<void> markDeleted(String deviceId, {String deviceToken = ''}) async {
    final id = deviceId.trim();
    if (id.isEmpty) return;
    final deleted = deletedDeviceIds()..add(id);
    final pending = wipePendingDeviceIds()..remove(id);
    final suspended = suspendedDeviceIds()..remove(id);
    final tokens = deletedDeviceTokens();
    final pendingTokens = wipePendingDeviceTokens()..remove(id);
    if (deviceToken.trim().isNotEmpty) tokens[id] = deviceToken.trim();
    await _saveSet(_deletedDevicesKey, deleted);
    await _saveSet(_wipePendingDevicesKey, pending);
    await _saveSet(_suspendedDevicesKey, suspended);
    await _saveMap(_deletedDeviceTokensKey, tokens);
    await _saveMap(_wipePendingDeviceTokensKey, pendingTokens);
  }

  static Future<void> clearWipePending(String deviceId) async {
    final id = deviceId.trim();
    if (id.isEmpty) return;
    final pending = wipePendingDeviceIds()..remove(id);
    final tokens = wipePendingDeviceTokens()..remove(id);
    await _saveSet(_wipePendingDevicesKey, pending);
    await _saveMap(_wipePendingDeviceTokensKey, tokens);
  }

  static Set<String> _loadSet(String key) {
    final raw = LocalDatabaseService.getString(key);
    if (raw == null || raw.trim().isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((item) => item.toString().trim()).where((item) => item.isNotEmpty).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> _saveSet(String key, Set<String> ids) {
    final normalized = ids.map((item) => item.trim()).where((item) => item.isNotEmpty).toList()..sort();
    return LocalDatabaseService.setString(key, jsonEncode(normalized));
  }

  static Map<String, String> _loadMap(String key) {
    final raw = LocalDatabaseService.getString(key);
    if (raw == null || raw.trim().isEmpty) return <String, String>{};
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return decoded.map((key, value) => MapEntry(key.toString().trim(), value.toString().trim()))
        ..removeWhere((key, value) => key.isEmpty || value.isEmpty);
    } catch (_) {
      return <String, String>{};
    }
  }

  static Future<void> _saveMap(String key, Map<String, String> values) {
    final normalized = Map<String, String>.from(values)
      ..removeWhere((key, value) => key.trim().isEmpty || value.trim().isEmpty);
    return LocalDatabaseService.setString(key, jsonEncode(normalized));
  }
}

String _normalizeTransport(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();
  if (normalized == 'lan' || normalized == 'cloud') return normalized;
  return 'local';
}
