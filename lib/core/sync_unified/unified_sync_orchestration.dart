import 'sync_transport_adapter.dart';
import '../services/sync_diagnostics_log.dart';

typedef UnifiedSyncPushInvoker = Future<UnifiedSyncResult> Function(
    UnifiedSyncPushRequest request);

typedef UnifiedSyncPullInvoker = Future<UnifiedSyncResult> Function(
    UnifiedSyncPullRequest request);

typedef UnifiedSnapshotRepairInvoker = Future<UnifiedSyncResult> Function({
  void Function(double value, String label)? onProgress,
});

/// Shared push/pull/repair orchestration used by LAN and Cloud transports.
///
/// The caller provides transport-specific push, pull, and repair handlers.
/// This keeps the sync order and result aggregation in one place while leaving
/// the actual network transport isolated in the adapter.
Future<UnifiedSyncResult> runUnifiedSyncOrchestration({
  required String label,
  required UnifiedSyncPushRequest pushRequest,
  required UnifiedSyncPushInvoker pushPending,
  required UnifiedSyncPullInvoker pullChanges,
  required UnifiedSnapshotRepairInvoker rebuildFromHostSnapshot,
  Future<void> Function()? compactAfterSuccessfulSync,
  void Function(double value, String label)? onProgress,
  bool Function(UnifiedSyncResult pull)? deferPullResult,
  String? pullFailureMessage,
}) async {
  SyncDiagnosticsLog.add('[SYNC_TRACE] orchestration start transport=$label');
  onProgress?.call(0.08, 'Preparing $label sync...');
  SyncDiagnosticsLog.add('[SYNC_TRACE] push start transport=$label');
  final push = await pushPending(pushRequest);
  SyncDiagnosticsLog.add(
      '[SYNC_TRACE] push result transport=$label ok=${push.ok} pushed=${push.pushed} message=${push.message}');
  if (!push.ok) {
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] orchestration failed stage=push transport=$label');
    onProgress?.call(1.0, '$label sync failed while sending local changes.');
    return push;
  }

  onProgress?.call(0.55, 'Pulling authoritative $label changes...');
  SyncDiagnosticsLog.add(
      '[SYNC_TRACE] pull start transport=$label cursor=${push.cursor.value}');
  final pull = await pullChanges(
    UnifiedSyncPullRequest(
      deviceId: pushRequest.deviceId,
      deviceToken: pushRequest.deviceToken,
      cursor: UnifiedSyncCursor(
        value: push.cursor.value,
        generatedAt: push.cursor.generatedAt,
        source: push.cursor.source,
      ),
    ),
  );

  if (deferPullResult?.call(pull) == true) {
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] pull deferred transport=$label pulled=${pull.pulled} message=${pull.message}');
    onProgress?.call(1.0, pull.message);
    return UnifiedSyncResultFactory.deferred(
      label: label,
      pushed: push.pushed,
      pulled: pull.pulled,
      cursor: pull.cursor,
      reason:
          pull.deferredReason.isNotEmpty ? pull.deferredReason : pull.message,
    );
  }

  if (pull.ok) {
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] pull result transport=$label ok=true pulled=${pull.pulled}');
    await compactAfterSuccessfulSync?.call();
    onProgress?.call(1.0, '$label sync completed.');
    return UnifiedSyncResultFactory.success(
      label: label,
      pushed: push.pushed,
      pulled: pull.pulled,
      restoredSnapshot: pull.restoredSnapshot,
      cursor: pull.cursor,
    );
  }

  if (!pull.shouldRepairAfterPullFailure()) {
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] pull result transport=$label ok=false error=${pull.message}');
    onProgress?.call(1.0, pullFailureMessage ?? '$label pull failed.');
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
  SyncDiagnosticsLog.add('[SYNC_TRACE] repair start transport=$label');
  final repair = await rebuildFromHostSnapshot(onProgress: onProgress);
  SyncDiagnosticsLog.add(
      '[SYNC_TRACE] repair result transport=$label ok=${repair.ok} message=${repair.message}');
  if (repair.ok) {
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] orchestration complete transport=$label restoredSnapshot=true');
    await compactAfterSuccessfulSync?.call();
    return UnifiedSyncResultFactory.success(
      label: label,
      pushed: push.pushed,
      pulled: repair.pulled,
      restoredSnapshot: true,
      cursor: repair.cursor,
    );
  }

  SyncDiagnosticsLog.add(
      '[SYNC_TRACE] orchestration failed stage=repair transport=$label');
  return UnifiedSyncResultFactory.failure(
    message: '${pull.message}. ${repair.message}',
    pushed: push.pushed,
    pulled: pull.pulled,
    error: pull.error.hasError ? pull.error : repair.error,
    cursor: pull.cursor,
  );
}
