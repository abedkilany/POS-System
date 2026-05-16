import 'sync_transport_adapter.dart';

/// Transport-agnostic sync facade introduced by Fix 10A.
///
/// Existing LAN and Cloud services remain the source of truth in this phase.
/// This engine only defines the common orchestration layer that later phases
/// will connect to real LAN/Cloud adapters.
class UnifiedSyncEngine {
  UnifiedSyncEngine(this.transport);

  final SyncTransportAdapter transport;

  UnifiedSyncTransportKind get kind => transport.kind;
  String get label => transport.label;

  Future<UnifiedSyncResult> testConnection() => transport.testConnection();

  Future<UnifiedHostStatus> getHostStatus() => transport.getHostStatus();

  Future<UnifiedSyncResult> registerCurrentHost({String transportName = ''}) =>
      transport.registerCurrentHost(transport: transportName);

  Future<UnifiedSyncResult> createInitialHostSnapshot({
    DateTime? minSnapshotUpdatedAt,
    void Function(double value, String label)? onProgress,
  }) =>
      transport.createInitialHostSnapshot(
        minSnapshotUpdatedAt: minSnapshotUpdatedAt,
        onProgress: onProgress,
      );

  Future<UnifiedPairingCodeResult> createPairingCode({int ttlMinutes = 5}) =>
      transport.createPairingCode(ttlMinutes: ttlMinutes);

  Future<UnifiedPairingClaimResult> claimPairingCode(String code) =>
      transport.claimPairingCode(code);

  Future<UnifiedSyncResult> pushPending(UnifiedSyncPushRequest request) =>
      transport.pushPending(request);

  Future<UnifiedSyncResult> pullChanges(UnifiedSyncPullRequest request) =>
      transport.pullChanges(request);

  Future<UnifiedSyncResult> rebuildFromHostSnapshot({
    void Function(double value, String label)? onProgress,
  }) =>
      transport.rebuildFromHostSnapshot(onProgress: onProgress);

  Future<UnifiedSyncResult> syncNow({
    void Function(double value, String label)? onProgress,
  }) =>
      transport.syncNow(onProgress: onProgress);
}
