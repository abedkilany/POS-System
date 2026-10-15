import '../../models/sync_queue_item.dart';

/// State transitions for retryable sync work, independent of persistence.
class SyncQueueRecoveryService {
  const SyncQueueRecoveryService();

  bool retryFailed({
    required List<SyncQueueItem> queue,
    required DateTime now,
    String? target,
  }) {
    var changed = false;
    for (var i = 0; i < queue.length; i++) {
      final item = queue[i];
      if (item.status == 'failed' &&
          (target == null || item.target == target)) {
        queue[i] = item.copyWith(
          status: 'pending',
          updatedAt: now,
          clearNextRetryAt: true,
        );
        changed = true;
      }
    }
    return changed;
  }

  bool recoverStaleInProgress({
    required List<SyncQueueItem> queue,
    required DateTime now,
    required Duration staleAfter,
    String? target,
  }) {
    final cutoff = now.subtract(staleAfter);
    var changed = false;
    for (var i = 0; i < queue.length; i++) {
      final item = queue[i];
      if (item.status == 'inProgress' &&
          item.updatedAt.isBefore(cutoff) &&
          (target == null || item.target == target)) {
        queue[i] = item.copyWith(
          status: 'pending',
          lastError:
              'Recovered stale in-progress sync item after timeout/crash.',
          updatedAt: now,
          clearNextRetryAt: true,
        );
        changed = true;
      }
    }
    return changed;
  }
}
