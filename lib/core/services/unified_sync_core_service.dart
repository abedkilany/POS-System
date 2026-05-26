import '../../data/app_store.dart';
import '../../models/sync_change.dart';

/// Transport-independent Host-authority sync logic.
///
/// LAN and Cloud should keep only their network/HTTP details locally. Shared
/// rules such as pending queue selection, Host acceptance, stale reset
/// protection, echo filtering, applying authoritative changes, and ACK handling
/// live here so a sync bug is fixed once for both transports.
class UnifiedSyncCoreService {
  UnifiedSyncCoreService(this.store);

  final AppStore store;

  List<SyncChange> pendingChangesForTarget(String target) {
    return store.pendingSyncChangesForTarget(target);
  }

  List<String> changeIds(Iterable<SyncChange> changes) {
    return changes.map((item) => item.id).toList();
  }

  Future<void> markPushInProgress(Iterable<String> changeIds) {
    return store.markSyncQueueChangesInProgress(changeIds);
  }

  Future<void> markPushAcknowledged(Iterable<String> ackIds, {Iterable<String> fallbackIds = const <String>[]}) {
    final ids = ackIds.isEmpty ? fallbackIds : ackIds;
    return store.markSyncChangesSyncedByIds(ids);
  }

  Future<void> markPushFailed(Iterable<String> changeIds, String message) {
    return store.markSyncQueueChangesFailed(changeIds, message);
  }

  List<SyncChange> decodeRemoteChanges(List<dynamic>? raw) {
    return (raw ?? const <dynamic>[])
        .map((item) => SyncChange.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  List<SyncChange> filterOutLocalEchoes(Iterable<SyncChange> changes) {
    return changes.where((item) => item.deviceId != store.deviceId).toList();
  }

  bool containsHostOnlyOperation(Iterable<SyncChange> changes) {
    return changes.any((item) => item.entityType == 'system' && item.operation == 'reset_store_data');
  }

  /// Applies Client drafts on the Host using the same acceptance rules for LAN
  /// and Cloud relay requests.
  Future<HostAcceptedChanges> acceptClientChangesOnHost(
    Iterable<SyncChange> remoteChanges, {
    required bool mirrorToCloud,
    bool verifyApplied = false,
  }) async {
    final received = filterOutLocalEchoes(remoteChanges);
    if (received.isEmpty) {
      return const HostAcceptedChanges(ackIds: <String>[], accepted: <SyncChange>[], discardedBecauseOfReset: 0);
    }

    final latestResetAt = store.latestResetSyncAt;
    final hostReceivedAt = DateTime.now();
    final applicable = (latestResetAt == null
            ? received
            : received.where((item) => item.createdAt.isAfter(latestResetAt)).toList())
        // Put accepted Client drafts on the Host timeline. This avoids a Client
        // with a newer cursor missing an older offline Client change.
        .map((item) => item.copyWith(createdAt: hostReceivedAt))
        .toList();

    await store.applyRemoteSyncChanges(
      applicable,
      markAppliedAsSynced: true,
      mirrorToCloud: mirrorToCloud,
    );
    if (verifyApplied) {
      await store.assertRemoteSyncChangesApplied(applicable);
    }

    return HostAcceptedChanges(
      ackIds: received.map((item) => item.id).toList(),
      accepted: applicable,
      discardedBecauseOfReset: received.length - applicable.length,
    );
  }

  Future<int> applyAuthoritativeChanges(
    Iterable<SyncChange> remoteChanges, {
    bool cleanupSoftDeleted = false,
  }) async {
    final changes = filterOutLocalEchoes(remoteChanges);
    await store.applyRemoteSyncChanges(changes, markAppliedAsSynced: true);
    if (cleanupSoftDeleted && changes.isNotEmpty) {
      await store.cleanupSoftDeletedRecords();
    }
    return changes.length;
  }
}

class HostAcceptedChanges {
  const HostAcceptedChanges({
    required this.ackIds,
    required this.accepted,
    required this.discardedBecauseOfReset,
  });

  final List<String> ackIds;
  final List<SyncChange> accepted;
  final int discardedBecauseOfReset;
}
