import '../../data/app_store.dart';
import '../../models/sync_change.dart';
import '../sync_unified/sync_device_state.dart';
import 'sync_diagnostics_log.dart';

/// Transport-independent Host-authority sync logic.
///
/// LAN and Direct should keep only their network/HTTP details locally. Shared
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

  List<SyncChange> normalizePulledChanges(List<dynamic>? raw) {
    return filterOutLocalEchoes(decodeRemoteChanges(raw));
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

  HostClientAcceptancePlan evaluateClientChangesOnHost(
    Iterable<SyncChange> remoteChanges,
  ) {
    final received = filterOutLocalEchoes(remoteChanges);
    if (received.isEmpty) {
      return const HostClientAcceptancePlan(
        received: <SyncChange>[],
        accepted: <SyncChange>[],
        rejected: <String, String>{},
        discardedBecauseOfReset: 0,
      );
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

    return HostClientAcceptancePlan(
      received: received,
      accepted: applicable,
      rejected: rejected,
      discardedBecauseOfReset:
          rejected.values.where((item) => item.contains('reset')).length,
    );
  }

  /// Applies Client drafts on the Host using the same acceptance rules for LAN
  /// and Direct relay requests.
  Future<HostAcceptedChanges> acceptClientChangesOnHost(
    Iterable<SyncChange> remoteChanges, {
    required bool mirrorToDirect,
    bool verifyApplied = false,
  }) async {
    final plan = evaluateClientChangesOnHost(remoteChanges);
    if (plan.received.isEmpty) {
      return const HostAcceptedChanges(
        ackIds: <String>[],
        accepted: <SyncChange>[],
        discardedBecauseOfReset: 0,
      );
    }

    if (plan.accepted.isNotEmpty) {
      await store.applyRemoteSyncChanges(
        plan.accepted,
        markAppliedAsSynced: true,
        mirrorToDirect: mirrorToDirect,
      );
    }
    if (verifyApplied) {
      await store.assertRemoteSyncChangesApplied(plan.accepted);
    }

    return HostAcceptedChanges(
      ackIds: plan.accepted.map((item) => item.id).toList(),
      accepted: plan.accepted,
      discardedBecauseOfReset: plan.discardedBecauseOfReset,
      rejected: plan.rejected,
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

  Future<void> saveCursorAndRecordTransportState(
    AppStore store, {
    required String transport,
    required DateTime cursor,
    int sequence = 0,
    required Future<void> Function() saveTransportState,
  }) async {
    await saveTransportState();
    await SyncDeviceStateStore.recordUnifiedSyncResult(
      store.appIdentity,
      transport: transport,
      cursor: cursor,
      sequence: sequence,
    );
  }

  Future<void> recordTransportSyncState(
    AppStore store, {
    required String transport,
    DateTime? cursor,
    int? sequence,
  }) {
    return SyncDeviceStateStore.recordUnifiedSyncResult(
      store.appIdentity,
      transport: transport,
      cursor: cursor,
      sequence: sequence,
    );
  }

  bool shouldBypassTransportSyncForHost({
    required bool isHost,
    required bool transportHasNativeHostMode,
  }) {
    return isHost && transportHasNativeHostMode;
  }

  bool shouldRebuildClientFromRestoreMarker(
    Iterable<SyncChange> changes, {
    required bool isClient,
  }) {
    if (!isClient) return false;
    return hasRestoreMarker(changes);
  }

  bool shouldHandlePulledSnapshotAsRepair(
    Map<String, dynamic> decodedPull, {
    required bool isClient,
  }) {
    if (decodedPull['needsSnapshot'] == true) return true;
    final changes = normalizePulledChanges(
      decodedPull['changes'] as List<dynamic>?,
    );
    return shouldRebuildClientFromRestoreMarker(
      changes,
      isClient: isClient,
    );
  }

  UnifiedSyncPullMetadata parsePullMetadata(Map<String, dynamic> decoded) {
    final generatedAt = DateTime.tryParse(
          decoded['generatedAt']?.toString() ?? '',
        ) ??
        DateTime.now();
    final generatedSequence =
        int.tryParse(decoded['generatedSequence']?.toString() ?? '') ?? 0;
    final source = (decoded['source'] ?? '').toString();
    final needsSnapshot = decoded['needsSnapshot'] == true;
    return UnifiedSyncPullMetadata(
      generatedAt: generatedAt,
      generatedSequence: generatedSequence,
      source: source,
      needsSnapshot: needsSnapshot,
    );
  }

  Future<void> compactAfterSuccessfulSync() async {
    final identity = store.appIdentity;
    if (identity.isHost) {
      await store.compactSyncedSyncHistoryForMaintenance();
    } else if (identity.isClient) {
      await store.compactClientSyncedSyncHistoryForMaintenance();
    }
  }

  bool hasRestoreMarker(Iterable<SyncChange> changes) {
    return changes.any((item) =>
        item.entityType == 'system' &&
        item.operation == 'restore_snapshot_ready');
  }
}

class HostClientAcceptancePlan {
  const HostClientAcceptancePlan({
    required this.received,
    required this.accepted,
    required this.rejected,
    required this.discardedBecauseOfReset,
  });

  final List<SyncChange> received;
  final List<SyncChange> accepted;
  final Map<String, String> rejected;
  final int discardedBecauseOfReset;
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

class UnifiedSyncPullMetadata {
  const UnifiedSyncPullMetadata({
    required this.generatedAt,
    required this.generatedSequence,
    required this.source,
    required this.needsSnapshot,
  });

  final DateTime generatedAt;
  final int generatedSequence;
  final String source;
  final bool needsSnapshot;
}
