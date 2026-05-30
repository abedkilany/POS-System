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

String _normalizeTransport(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();
  if (normalized == 'lan' || normalized == 'cloud') return normalized;
  return 'local';
}
