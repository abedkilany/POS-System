import 'dart:convert';

import 'local_database_service.dart';

class DirectIceServer {
  const DirectIceServer({
    required this.urls,
    this.username = '',
    this.credential = '',
  });

  final List<String> urls;
  final String username;
  final String credential;

  Map<String, dynamic> toIceConfig() => {
        'urls': urls.length == 1 ? urls.first : urls,
        if (username.trim().isNotEmpty) 'username': username.trim(),
        if (credential.trim().isNotEmpty) 'credential': credential,
      };

  Map<String, dynamic> toJson() => {
        'urls': urls,
        'username': username,
        'credential': credential,
      };

  factory DirectIceServer.fromJson(Object? raw) {
    if (raw is! Map) return const DirectIceServer(urls: <String>[]);
    final rawUrls = raw['urls'];
    final urls = rawUrls is List
        ? rawUrls
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList()
        : rawUrls
                ?.toString()
                .split(RegExp(r'[\s,;]+'))
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toList() ??
            const <String>[];
    return DirectIceServer(
      urls: urls,
      username: raw['username']?.toString() ?? '',
      credential: raw['credential']?.toString() ?? '',
    );
  }
}

class DirectSyncSettings {
  const DirectSyncSettings({
    required this.apiBaseUrl,
    required this.peerDeviceId,
    this.setupComplete = false,
    this.autoSyncEnabled = true,
    this.stunServer = '',
    this.stunServers = const <String>[],
    this.turnServers = const <DirectIceServer>[],
    this.iceTransportPolicy = 'all',
    this.iceCandidatePoolSize = 0,
  });

  static const storageKey = 'direct_sync_settings_v1';
  static const bundledStunServer = String.fromEnvironment('VENTIO_STUN_SERVER');

  final String apiBaseUrl;
  final String peerDeviceId;
  final bool setupComplete;
  final bool autoSyncEnabled;
  final String stunServer;
  final List<String> stunServers;
  final List<DirectIceServer> turnServers;
  final String iceTransportPolicy;
  final int iceCandidatePoolSize;

  List<Map<String, dynamic>> get iceServers {
    final values = <String>{};
    final configs = <Map<String, dynamic>>[];
    final legacy = stunServer.trim().isEmpty
        ? const <String>[]
        : stunServer.split(RegExp(r'[\s,;]+'));
    final stuns = <String>[...stunServers, ...legacy]
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty);
    for (final url in stuns) {
      if (values.add(url)) {
        configs.add(<String, dynamic>{'urls': url});
      }
    }
    configs.addAll(turnServers
        .where((server) => server.urls.isNotEmpty)
        .map((server) => server.toIceConfig()));
    return configs;
  }

  /// Uses the API host as the runtime STUN host when no explicit STUN value
  /// was bundled or saved. This keeps Windows and other native builds free of
  /// build-time deployment data.
  List<Map<String, dynamic>> iceServersForApiBaseUrl(String apiBaseUrl) {
    if (iceServers.isNotEmpty) return iceServers;
    final base = apiBaseUrl.trim();
    if (base.isEmpty) return const <Map<String, dynamic>>[];
    final uri = Uri.tryParse(base);
    final host = uri?.host.trim() ?? '';
    if (host.isEmpty || host == 'localhost' || host == '127.0.0.1') {
      return const <Map<String, dynamic>>[];
    }
    return <Map<String, dynamic>>[
      <String, dynamic>{'urls': 'stun:$host:3478'},
    ];
  }

  Map<String, dynamic> rtcConfigurationForApiBaseUrl(String apiBaseUrl) => {
        'iceServers': iceServersForApiBaseUrl(apiBaseUrl),
        'iceTransportPolicy': iceTransportPolicy == 'relay' ? 'relay' : 'all',
        'iceCandidatePoolSize': iceCandidatePoolSize.clamp(0, 16),
      };

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
    List<String>? stunServers,
    List<DirectIceServer>? turnServers,
    String? iceTransportPolicy,
    int? iceCandidatePoolSize,
  }) =>
      DirectSyncSettings(
        apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
        peerDeviceId: peerDeviceId ?? this.peerDeviceId,
        setupComplete: setupComplete ?? this.setupComplete,
        autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
        stunServer: stunServer ?? this.stunServer,
        stunServers: stunServers ?? this.stunServers,
        turnServers: turnServers ?? this.turnServers,
        iceTransportPolicy: iceTransportPolicy ?? this.iceTransportPolicy,
        iceCandidatePoolSize: iceCandidatePoolSize ?? this.iceCandidatePoolSize,
      );

  Map<String, dynamic> toJson() => {
        'apiBaseUrl': apiBaseUrl,
        'peerDeviceId': peerDeviceId,
        'setupComplete': setupComplete,
        'autoSyncEnabled': autoSyncEnabled,
        'stunServer': stunServer,
        'stunServers': stunServers,
        'turnServers': turnServers.map((server) => server.toJson()).toList(),
        'iceTransportPolicy': iceTransportPolicy,
        'iceCandidatePoolSize': iceCandidatePoolSize,
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
        stunServers: (json['stunServers'] is List)
            ? (json['stunServers'] as List)
                .map((item) => item.toString())
                .toList()
            : const <String>[],
        turnServers: (json['turnServers'] is List)
            ? (json['turnServers'] as List)
                .map(DirectIceServer.fromJson)
                .where((server) => server.urls.isNotEmpty)
                .toList()
            : const <DirectIceServer>[],
        iceTransportPolicy:
            json['iceTransportPolicy']?.toString().toLowerCase() == 'relay'
                ? 'relay'
                : 'all',
        iceCandidatePoolSize:
            int.tryParse(json['iceCandidatePoolSize']?.toString() ?? '') ?? 0,
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
