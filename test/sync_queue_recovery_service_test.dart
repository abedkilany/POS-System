import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/sync_queue_recovery_service.dart';
import 'package:ventio/models/sync_queue_item.dart';

void main() {
  const service = SyncQueueRecoveryService();
  final now = DateTime(2026, 1, 10, 12);

  test('retries failed items only for the requested target', () {
    final queue = <SyncQueueItem>[
      SyncQueueItem(
        id: 'failed-host',
        changeId: 'change-1',
        target: 'host',
        status: 'failed',
        attempts: 2,
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(hours: 1)),
        nextRetryAt: now.add(const Duration(hours: 1)),
      ),
      SyncQueueItem(
        id: 'failed-marketplace',
        changeId: 'change-2',
        target: 'marketplace',
        status: 'failed',
        attempts: 3,
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(hours: 1)),
      ),
      SyncQueueItem(
        id: 'already-pending',
        changeId: 'change-3',
        target: 'host',
        status: 'pending',
        attempts: 0,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    expect(service.retryFailed(queue: queue, now: now, target: 'host'), isTrue);
    expect(queue[0].status, 'pending');
    expect(queue[0].updatedAt, now);
    expect(queue[0].nextRetryAt, isNull);
    expect(queue[1].status, 'failed');
    expect(queue[2].status, 'pending');
  });

  test('recovers only stale in-progress items for the target', () {
    final queue = <SyncQueueItem>[
      SyncQueueItem(
        id: 'stale-host',
        changeId: 'change-1',
        target: 'host',
        status: 'inProgress',
        attempts: 1,
        createdAt: now.subtract(const Duration(hours: 1)),
        updatedAt: now.subtract(const Duration(minutes: 2)),
        nextRetryAt: now.add(const Duration(hours: 1)),
      ),
      SyncQueueItem(
        id: 'fresh-host',
        changeId: 'change-2',
        target: 'host',
        status: 'inProgress',
        attempts: 1,
        createdAt: now,
        updatedAt: now.subtract(const Duration(seconds: 10)),
      ),
      SyncQueueItem(
        id: 'stale-marketplace',
        changeId: 'change-3',
        target: 'marketplace',
        status: 'inProgress',
        attempts: 1,
        createdAt: now.subtract(const Duration(hours: 1)),
        updatedAt: now.subtract(const Duration(minutes: 2)),
      ),
    ];

    expect(
      service.recoverStaleInProgress(
        queue: queue,
        now: now,
        staleAfter: const Duration(seconds: 45),
        target: 'host',
      ),
      isTrue,
    );
    expect(queue[0].status, 'pending');
    expect(queue[0].lastError,
        'Recovered stale in-progress sync item after timeout/crash.');
    expect(queue[0].nextRetryAt, isNull);
    expect(queue[1].status, 'inProgress');
    expect(queue[2].status, 'inProgress');
  });
}
