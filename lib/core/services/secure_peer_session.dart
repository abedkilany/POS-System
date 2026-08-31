import 'dart:async';

/// Transport-independent session used by peer-to-peer sync protocols.
///
/// Implementations may use WebRTC, LAN sockets, or an encrypted relay. The
/// sync protocol must only depend on this contract so that the active network
/// path can change without changing application-level sync messages.
abstract interface class SecurePeerSession {
  /// Identifies the currently selected network path, for diagnostics and
  /// future path selection. Examples: `direct`, `lan`, or `relay`.
  String get transportType;

  Stream<Map<String, dynamic>> get messages;

  Future<void> send(String type, Map<String, dynamic> payload);

  Future<void> close();
}
