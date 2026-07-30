import 'dart:convert';

import 'local_database_service.dart';

class DirectSyncSettings {
  const DirectSyncSettings({
    required this.apiBaseUrl,
    required this.peerDeviceId,
    this.setupComplete = false,
    this.autoSyncEnabled = true,
    this.stunServer = '',
  });

  static const storageKey = 'direct_sync_settings_v1';
  static const bundledStunServer = String.fromEnvironment('VENTIO_STUN_SERVER');

  final String apiBaseUrl;
  final String peerDeviceId;
  final bool setupComplete;
  final bool autoSyncEnabled;
  final String stunServer;

  List<Map<String, dynamic>> get iceServers => stunServer.trim().isEmpty
      ? const <Map<String, dynamic>>[]
      : <Map<String, dynamic>>[
          <String, dynamic>{'urls': stunServer.trim()},
        ];

  bool get isConfigured =>
      setupComplete &&
      apiBaseUrl.trim().isNotEmpty &&
      peerDeviceId.trim().isNotEmpty;

  DirectSyncSettings copyWith({
    String? apiBaseUrl,
    String? peerDeviceId,
    bool? setupComplete,
    bool? autoSyncEnabled,
    String? stunServer,
  }) =>
      DirectSyncSettings(
        apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
        peerDeviceId: peerDeviceId ?? this.peerDeviceId,
        setupComplete: setupComplete ?? this.setupComplete,
        autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
        stunServer: stunServer ?? this.stunServer,
      );

  Map<String, dynamic> toJson() => {
        'apiBaseUrl': apiBaseUrl,
        'peerDeviceId': peerDeviceId,
        'setupComplete': setupComplete,
        'autoSyncEnabled': autoSyncEnabled,
        'stunServer': stunServer,
      };

  factory DirectSyncSettings.fromJson(Map<String, dynamic> json) =>
      DirectSyncSettings(
        apiBaseUrl: json['apiBaseUrl']?.toString() ?? '',
        peerDeviceId: json['peerDeviceId']?.toString() ?? '',
        setupComplete: json['setupComplete'] == true,
        autoSyncEnabled: json['autoSyncEnabled'] != false,
        stunServer: (json['stunServer']?.toString().trim().isNotEmpty == true)
            ? json['stunServer'].toString()
            : bundledStunServer,
      );

  static DirectSyncSettings load() {
    final raw = LocalDatabaseService.getString(storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return const DirectSyncSettings(
        apiBaseUrl: '',
        peerDeviceId: '',
        stunServer: bundledStunServer,
      );
    }
    try {
      return DirectSyncSettings.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const DirectSyncSettings(
        apiBaseUrl: '',
        peerDeviceId: '',
        stunServer: bundledStunServer,
      );
    }
  }

  Future<void> save() =>
      LocalDatabaseService.setString(storageKey, jsonEncode(toJson()));
}
