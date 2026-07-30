import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../data/app_store.dart';
import '../../models/app_identity.dart';

/// Settings used only to reach Ventio's coordination service.
///
/// The coordination service is not a data relay. It only issues a short-lived
/// ticket and forwards direct-connection negotiation messages between the
/// paired Host and Client.
class DirectPeerSignalingSettings {
  const DirectPeerSignalingSettings({required this.apiBaseUrl});

  final String apiBaseUrl;

  Uri endpoint(String path, [Map<String, String>? query]) {
    final base = apiBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base${path.startsWith('/') ? path : '/$path'}');
    return query == null
        ? uri
        : uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  Uri realtimeEndpoint(String path, [Map<String, String>? query]) {
    final uri = endpoint(path, query);
    return uri.replace(scheme: uri.scheme == 'http' ? 'ws' : 'wss');
  }
}

class DirectPeerSignalingSession {
  DirectPeerSignalingSession({
    required this.channel,
    required this.ticket,
  });

  final WebSocketChannel channel;
  final String ticket;

  Stream<Map<String, dynamic>> get signals => channel.stream
      .where((raw) => raw != null)
      .map((raw) => jsonDecode(raw.toString()))
      .where((packet) => packet is Map)
      .map((packet) => Map<String, dynamic>.from(packet))
      .where((packet) => packet['type']?.toString() == 'direct_signal');

  void send(Map<String, dynamic> signal) {
    channel.sink.add(jsonEncode({
      'type': 'direct_signal',
      ...signal,
    }));
  }

  Future<void> close() => channel.sink.close();
}

class DirectPeerSignalingService {
  DirectPeerSignalingService(
    this.store, {
    http.Client? client,
  }) : _client = client ?? http.Client();

  final AppStore store;
  final http.Client _client;

  Map<String, String> _headers() {
    final identity = store.appIdentity;
    return {
      'Accept': 'application/json',
      'X-Device-Id': identity.deviceId,
      'X-Device-Token': identity.deviceToken,
      'X-Device-Role': identity.deviceRole.name,
      'X-Sync-Transport': 'direct',
      'X-Store-Id': identity.storeId,
      'X-Branch-Id': identity.branchId,
    };
  }

  Future<DirectPeerSignalingSession> open(
    DirectPeerSignalingSettings settings,
  ) async {
    final identity = store.appIdentity;
    final response = await _client
        .get(
          settings.endpoint('/api/sync/direct-ticket', {
            'store_id': identity.storeId,
            'branch_id': identity.branchId,
            'role': identity.deviceRole.name,
          }),
          headers: _headers(),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Direct signaling ticket failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    final ticket = decoded is Map ? decoded['ticket']?.toString().trim() : '';
    if (ticket == null || ticket.isEmpty) {
      throw StateError('Direct signaling response is missing a ticket.');
    }

    final channel = WebSocketChannel.connect(
      settings.realtimeEndpoint('/api/sync/realtime', {'ticket': ticket}),
    );
    return DirectPeerSignalingSession(channel: channel, ticket: ticket);
  }

  void dispose() => _client.close();
}

extension DirectPeerIdentity on AppIdentity {
  bool get isDirectTransport => activeSyncTransportNormalized == 'direct';
}
