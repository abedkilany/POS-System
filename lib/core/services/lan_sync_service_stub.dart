import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../data/app_store.dart';
import 'local_database_service.dart';

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
    bool clearLastPullCursor = false,
    bool clearLastConnectionAt = false,
    bool clearLastSyncAt = false,
  }) => LanSyncSettings(
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
      );

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
    );
  }

  static LanSyncSettings load() {
    final rawV2 = LocalDatabaseService.getString(storageKey);
    if (rawV2 != null && rawV2.trim().isNotEmpty) {
      try {
        return LanSyncSettings.fromJson(Map<String, dynamic>.from(jsonDecode(rawV2) as Map));
      } catch (_) {}
    }
    return const LanSyncSettings(host: '192.168.1.100', port: 8787, autoSyncEnabled: true, hostModeEnabled: false);
  }

  Future<void> save() async => LocalDatabaseService.setString(storageKey, jsonEncode(toJson()));
  static Future<void> resetSetup() async => LocalDatabaseService.deleteString(storageKey);
  static String generateSecret() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(16, (_) => alphabet[random.nextInt(alphabet.length)]).join();
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
  bool get isHosting => false;
  int? get port => null;
  Future<void> startHost({int port = 8787}) async {}
  Future<void> stopHost() async {}
  Future<LanSyncResult> testConnection(String host, {int port = 8787, String token = ''}) async =>
      const LanSyncResult(ok: false, message: 'LAN sync is not available in the web build. Use Cloud Sync/API instead.');
  Future<LanSyncResult> initialClone(String host, {int port = 8787, String token = ''}) async =>
      const LanSyncResult(ok: false, message: 'LAN initial clone is not available in the web build.');
  Future<LanSyncResult> pullNow(String host, {int port = 8787, String token = ''}) async =>
      const LanSyncResult(ok: false, message: 'LAN pull is not available in the web build.');
  Future<LanSyncResult> syncNow(String host, {int port = 8787, String token = ''}) async =>
      const LanSyncResult(ok: false, message: 'LAN sync is not available in the web build.');
}

class AutoLanSyncController {
  AutoLanSyncController(this.store);
  final AppStore store;
  Future<void> start() async {}
  Future<void> stop() async {}
}
