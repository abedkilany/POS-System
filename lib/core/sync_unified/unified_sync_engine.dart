import 'unified_sync_orchestration.dart';
import 'sync_transport_adapter.dart';

/// Transport-agnostic sync engine.
///
/// Stage 2 makes this class the single orchestration path for a normal sync run:
/// 1) push local pending work through the selected transport,
/// 2) pull authoritative Host changes through the same transport,
/// 3) attempt snapshot repair when pull fails after a successful push.
///
/// LAN and Cloud adapters should only know how to move data. Decisions about
/// sync order, failure handling, and result aggregation live here so bugs in the
/// sync flow are fixed once for both transports.
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

  Future<UnifiedPairingClaimResult> claimPairingCode(String code,
          {void Function(double value, String label)? onProgress}) =>
      transport.claimPairingCode(code, onProgress: onProgress);

  Future<UnifiedSyncResult> pushPending(UnifiedSyncPushRequest request) =>
      transport.pushPending(request);

  Future<UnifiedSyncResult> pullChanges(UnifiedSyncPullRequest request) =>
      transport.pullChanges(request);

  Future<UnifiedSyncResult> rebuildFromHostSnapshot({
    void Function(double value, String label)? onProgress,
  }) =>
      transport.rebuildFromHostSnapshot(onProgress: onProgress);

  Future<bool> waitForRealtimeSignal() => transport.waitForRealtimeSignal();

  Future<void> stopHostIfSupported() => transport.stopHostIfSupported();

  Future<void> requestFreshHostSnapshotIfSupported({
    DateTime? requestedAt,
  }) =>
      transport.requestFreshHostSnapshotIfSupported(requestedAt: requestedAt);

  Future<UnifiedSyncResult> syncNow({
    void Function(double value, String label)? onProgress,
  }) =>
      runUnifiedSyncOrchestration(
        label: label,
        pushRequest: UnifiedSyncPushRequest(
          deviceId: transport.deviceId,
          deviceToken: transport.deviceToken,
        ),
        pushPending: transport.pushPending,
        pullChanges: transport.pullChanges,
        rebuildFromHostSnapshot: transport.rebuildFromHostSnapshot,
        compactAfterSuccessfulSync: transport.compactAfterSuccessfulSync,
        onProgress: onProgress,
        pullFailureMessage: '$label pull failed.',
      );
}
