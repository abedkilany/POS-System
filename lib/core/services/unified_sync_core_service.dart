import '../../data/app_store.dart';
import '../../models/sync_change.dart';
import 'sync_diagnostics_log.dart';

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

  Future<void> markPushSubmitted(Iterable<String> ackIds,
      {Iterable<String> fallbackIds = const <String>[]}) {
    final ids = ackIds.isEmpty ? fallbackIds : ackIds;
    return store.markSyncChangesSubmittedByIds(ids);
  }

  Future<void> markPushAcknowledged(Iterable<String> ackIds,
      {Iterable<String> fallbackIds = const <String>[]}) {
    final ids = ackIds.isEmpty ? fallbackIds : ackIds;
    return store.markSyncChangesSyncedByIds(ids);
  }

  Future<void> markPushFailed(Iterable<String> changeIds, String message) {
    return store.markSyncQueueChangesFailed(changeIds, message);
  }

  List<SyncChange> submittedChangesForTarget(String target) {
    return store.submittedSyncChangesForTarget(target);
  }

  Future<void> markPushRejected(Map<String, String> rejected) {
    return store.markSyncChangesRejectedByIds(rejected);
  }

  List<SyncChange> decodeRemoteChanges(List<dynamic>? raw) {
    return (raw ?? const <dynamic>[])
        .map((item) =>
            SyncChange.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  List<SyncChange> filterOutLocalEchoes(Iterable<SyncChange> changes) {
    final list = changes.toList();
    final filtered =
        list.where((item) => item.deviceId != store.deviceId).toList();
    if (list.length != filtered.length) {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] core:echoFilter input=${list.length} output=${filtered.length} '
        'localDevice=${store.deviceId} removed=${list.length - filtered.length}',
      );
      for (final change
          in list.where((item) => item.deviceId == store.deviceId).take(20)) {
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] core:echoRemoved ${SyncDiagnosticsLog.summarizeChange(change)}',
        );
      }
    }
    return filtered;
  }

  bool containsHostOnlyOperation(Iterable<SyncChange> changes) {
    return changes.any((item) =>
        item.entityType == 'system' && item.operation == 'reset_store_data');
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
      return const HostAcceptedChanges(
          ackIds: <String>[],
          accepted: <SyncChange>[],
          discardedBecauseOfReset: 0);
    }

    final latestResetAt = store.latestResetSyncAt;
    final hostReceivedAt = DateTime.now();
    final rejected = <String, String>{};
    final applicable = <SyncChange>[];
    for (final item in received) {
      if (latestResetAt != null && !item.createdAt.isAfter(latestResetAt)) {
        rejected[item.id] = 'Request is older than the latest Host reset.';
        continue;
      }
      final problem = store.validateClientDraftForHostAcceptance(item);
      if (problem != null) {
        rejected[item.id] = problem;
        continue;
      }
      // Put accepted Client drafts on the Host timeline. This avoids a Client
      // with a newer cursor missing an older offline Client change.
      applicable.add(item.copyWith(createdAt: hostReceivedAt));
    }

    if (applicable.isNotEmpty) {
      await store.applyRemoteSyncChanges(
        applicable,
        markAppliedAsSynced: true,
        mirrorToCloud: mirrorToCloud,
      );
    }
    if (verifyApplied) {
      await store.assertRemoteSyncChangesApplied(applicable);
    }

    return HostAcceptedChanges(
      ackIds: applicable.map((item) => item.id).toList(),
      accepted: applicable,
      discardedBecauseOfReset:
          rejected.values.where((item) => item.contains('reset')).length,
      rejected: rejected,
    );
  }

  Future<int> applyAuthoritativeChanges(
    Iterable<SyncChange> remoteChanges, {
    bool cleanupSoftDeleted = false,
  }) async {
    final remoteList = remoteChanges.toList();
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] core:applyAuthoritative start remote=${remoteList.length} '
      'cleanupSoftDeleted=$cleanupSoftDeleted localDevice=${store.deviceId}',
    );
    for (final change in remoteList.take(40)) {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] core:authoritative ${SyncDiagnosticsLog.summarizeChange(change)}',
      );
    }

    // Host confirmation rule: drafts pushed to a relay are only final after
    // the Host republishes them as authoritative changes. If this device is
    // the origin, the matching local queue row is confirmed here instead of
    // being confirmed by the relay ACK.
    await store.markSyncChangesSyncedByIds(remoteList.expand((item) {
      final meta = Map<String, dynamic>.from(
          item.payload['_syncV2'] as Map? ?? const {});
      return <String>[
        item.id,
        (meta['eventId'] ?? '').toString(),
        (meta['requestId'] ?? '').toString(),
        (meta['sourceCommandId'] ?? '').toString(),
      ].where((value) => value.isNotEmpty);
    }));

    final changes = filterOutLocalEchoes(remoteList);
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] core:applyAuthoritative afterEchoFilter=${changes.length}',
    );
    await store.applyRemoteSyncChanges(changes, markAppliedAsSynced: true);
    if (cleanupSoftDeleted && changes.isNotEmpty) {
      await store.cleanupSoftDeletedRecords();
    }
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] core:applyAuthoritative done countedApplied=${changes.length}',
    );
    return changes.length;
  }
}

class HostAcceptedChanges {
  const HostAcceptedChanges({
    required this.ackIds,
    required this.accepted,
    required this.discardedBecauseOfReset,
    this.rejected = const <String, String>{},
  });

  final List<String> ackIds;
  final List<SyncChange> accepted;
  final int discardedBecauseOfReset;
  final Map<String, String> rejected;
}
