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

  Future<UnifiedSyncResult> syncNow({
    void Function(double value, String label)? onProgress,
  }) async {
    final request = UnifiedSyncPushRequest(
        deviceId: transport.deviceId, deviceToken: transport.deviceToken);

    onProgress?.call(0.08, 'Preparing $label sync...');
    final push = await transport.pushPending(request);
    if (!push.ok) {
      onProgress?.call(1.0, '$label sync failed while sending local changes.');
      return push;
    }

    onProgress?.call(0.55, 'Pulling authoritative $label changes...');
    final pull = await transport.pullChanges(
      UnifiedSyncPullRequest(
        deviceId: transport.deviceId,
        deviceToken: transport.deviceToken,
        cursor: UnifiedSyncCursor(
          value: push.cursor.value,
          generatedAt: push.cursor.generatedAt,
          source: push.cursor.source,
        ),
      ),
    );

    if (!pull.ok) {
      if (!pull.shouldAttemptSnapshotRepair) {
        onProgress?.call(1.0, '$label pull failed.');
        return UnifiedSyncResult(
          ok: false,
          message: pull.message,
          pushed: push.pushed,
          pulled: pull.pulled,
          error: pull.error,
          cursor: pull.cursor,
        );
      }
      onProgress?.call(0.78, '$label pull failed. Trying snapshot repair...');
      final repair =
          await transport.rebuildFromHostSnapshot(onProgress: onProgress);
      if (repair.ok) {
        await transport.compactAfterSuccessfulSync();
        return UnifiedSyncResult(
          ok: true,
          message: '${pull.message}. ${repair.message}',
          pushed: push.pushed,
          pulled: repair.pulled,
          restoredSnapshot: true,
          cursor: repair.cursor,
        );
      }
      return UnifiedSyncResult(
        ok: false,
        message: '${pull.message}. ${repair.message}',
        pushed: push.pushed,
        pulled: pull.pulled,
        error: pull.error.hasError ? pull.error : repair.error,
        cursor: pull.cursor,
      );
    }

    await transport.compactAfterSuccessfulSync();
    onProgress?.call(1.0, '$label sync completed.');
    return UnifiedSyncResult(
      ok: true,
      message:
          '$label sync completed. Pushed ${push.pushed} change(s), pulled ${pull.pulled} change(s).',
      pushed: push.pushed,
      pulled: pull.pulled,
      restoredSnapshot: pull.restoredSnapshot,
      cursor: pull.cursor,
    );
  }
}
