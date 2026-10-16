import '../../models/app_identity.dart';
import '../../models/business_integrity.dart';
import '../../models/sync_change.dart';
import '../../models/sync_queue_item.dart';
import 'sync_history_policy.dart';

abstract class SyncDomainPort {
  Future<List<Map<String, dynamic>>> exportDirectLoginBootstrapSnapshotChunks();
  String get deviceId;
  List<SyncChange> get changes;
  List<SyncQueueItem> get queue;
  List<SyncChange> get pendingChanges;
  List<SyncQueueItem> get pendingQueue;
  int get sequence;
  int get pendingCount;
  int get activeClientPendingCount;
  int get latestStoredAuthoritativeSequence;
  List<DataConflict> get dataConflicts;
  int get blockingDataConflictCount;
  Map<String, dynamic>? get latestHostTransferNotification;
  DateTime? get latestResetAt;
  Future<void> ensureLoaded();
  bool hasOutstandingWorkForTarget(String target);
  List<SyncChange> pendingChangesForTarget(
    String target, {
    bool readyOnly = true,
  });
  List<SyncChange> submittedChangesForTarget(String target);
  String? validateClientDraftForHostAcceptance(SyncChange change);
  Future<void> markPushInProgress(Iterable<String> changeIds);
  Future<void> markSubmitted(Iterable<String> ids);
  Future<void> markAcknowledged(Iterable<String> ids);
  Future<void> markFailed(Iterable<String> changeIds, String message);
  Future<void> markRejected(Map<String, String> rejected);
  Future<void> applyRemoteChanges(
    Iterable<SyncChange> changes, {
    bool markAppliedAsSynced = false,
    bool mirrorToDirect = false,
  });
  Future<void> assertRemoteChangesApplied(List<SyncChange> changes);
  Future<void> retryFailed({String? target});
  Future<void> recoverSubmitted({String? target});
  Future<void> recoverStale({
    String? target,
    Duration staleAfter = const Duration(seconds: 45),
  });
  Future<List<DataConflict>> ensureDataConflictsLoaded();
  Future<BusinessDataIntegrityResult> verifyLocalBusinessDataIntegrity();
  Future<int> cleanupSoftDeletedRecords({
    Duration retention = const Duration(days: 30),
  });
  Future<void> recordPhase8AccountingMutationForSync();
  Future<void> recoverPhase8AccountingSyncAfterStartup();
  Future<Map<String, int>> compactSyncedHistoryForMaintenance({
    int keepRecentSyncedChanges = SyncHistoryPolicy.keepRecentChanges,
    int minChangesBeforeCompact = SyncHistoryPolicy.minChangesBeforeCompact,
  });
  Future<Map<String, int>> compactClientSyncedHistoryForMaintenance({
    int keepRecentSyncedChanges = SyncHistoryPolicy.keepRecentChanges,
  });
  Future<int> settleHostQueueThroughPeerAck();
  Future<void> settleLegacyLanHostQueue();
  Future<void> importSnapshotJson(String rawJson);
  Future<void> markAllChangesSynced();
  Future<List<Map<String, dynamic>>> exportSnapshotChunks({
    String kind = 'full_store',
    Set<String>? sectionIds,
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  });
  Map<String, dynamic> snapshotPayloadFromChunks(
    List<Map<String, dynamic>> chunks,
  );
  DateTime snapshotGeneratedAtFromJson(String rawJson);
  int snapshotGeneratedSequenceFromJson(String rawJson);
  String exportChangesJson({
    DateTime? since,
    int? sinceSequence,
    int? maxEncodedPayloadBytes,
  });
  String get approvedHostTransferDeviceId;
  Map<String, dynamic>? get pendingHostTransferRequest;
  Future<void> updateAppIdentityLocalOnly(
    AppIdentity identity, {
    String source = 'local sync settings',
  });
  Future<void> setActiveSyncTransport(String transport);
  Future<void> requestHostTransfer({String reason = ''});
  Future<void> approveHostTransfer(String requestingDeviceId);
  Future<void> activateApprovedHostTransfer();
  Future<void> clearHostTransferNotification();
  Future<int> clearLocalOnlyPendingSyncChanges();
  List<SyncQueueItem> pendingSyncQueueForTarget(
    String target, {
    bool readyOnly = true,
  });
  Future<void> clearPendingSyncQueue({bool notify = true});
  Future<void> markSyncQueueItemFailed(String queueItemId, String error);
  Future<String> exportSyncSnapshotJson();
}
