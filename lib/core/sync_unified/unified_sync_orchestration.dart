import 'sync_transport_adapter.dart';

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
  onProgress?.call(0.08, 'Preparing $label sync...');
  final push = await pushPending(pushRequest);
  if (!push.ok) {
    onProgress?.call(1.0, '$label sync failed while sending local changes.');
    return push;
  }

  onProgress?.call(0.55, 'Pulling authoritative $label changes...');
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
  final repair = await rebuildFromHostSnapshot(onProgress: onProgress);
  if (repair.ok) {
    await compactAfterSuccessfulSync?.call();
    return UnifiedSyncResultFactory.success(
      label: label,
      pushed: push.pushed,
      pulled: repair.pulled,
      restoredSnapshot: true,
      cursor: repair.cursor,
    );
  }

  return UnifiedSyncResultFactory.failure(
    message: '${pull.message}. ${repair.message}',
    pushed: push.pushed,
    pulled: pull.pulled,
    error: pull.error.hasError ? pull.error : repair.error,
    cursor: pull.cursor,
  );
}
