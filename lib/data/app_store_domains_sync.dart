part of 'app_store.dart';

final class _SyncDomain implements SyncDomainPort {
  _SyncDomain(this._store);
  final AppStore _store;

  @override
  String get deviceId => _store._deviceId;

  @override
  List<SyncChange> get changes => _store._syncChangesReadImpl;
  @override
  List<SyncQueueItem> get queue => _store._syncQueueReadImpl;
  @override
  List<SyncChange> get pendingChanges =>
      _AppStoreSplitCoreLoadingPart2(_store).pendingSyncChanges;
  @override
  List<SyncQueueItem> get pendingQueue =>
      _AppStoreSplitCoreLoadingPart2(_store).pendingSyncQueue;
  @override
  int get sequence => _store._syncSequence;
  @override
  int get pendingCount => pendingQueue.length;
  @override
  int get activeClientPendingCount =>
      _AppStoreSplitCoreLoadingPart2(_store).activeClientPendingSyncCount;
  @override
  int get latestStoredAuthoritativeSequence =>
      _store._latestStoredAuthoritativeSequence();
  @override
  List<DataConflict> get dataConflicts =>
      _AppStoreSplitCoreLoading(_store).dataConflicts;
  @override
  int get blockingDataConflictCount =>
      dataConflicts.where((item) => item.blocking).length;
  @override
  Map<String, dynamic>? get latestHostTransferNotification =>
      _AppStoreSplitIdentityUsers(_store).latestHostTransferNotification;

  @override
  DateTime? get latestResetAt =>
      _AppStoreSplitCoreLoadingPart2(_store).latestResetSyncAt;

  @override
  Future<void> ensureLoaded() => _store._requestSyncDataLoad();

  @override
  bool hasOutstandingWorkForTarget(String target) =>
      _AppStoreSplitCoreLoadingPart2(_store)
          .outstandingSyncQueueCountForTarget(target) >
      0;

  @override
  List<SyncChange> pendingChangesForTarget(
    String target, {
    bool readyOnly = true,
  }) =>
      _AppStoreSplitCoreLoadingPart2(_store)
          .pendingSyncChangesForTarget(target, readyOnly: readyOnly);

  @override
  List<SyncChange> submittedChangesForTarget(String target) =>
      _AppStoreSplitCoreLoadingPart2(_store)
          .submittedSyncChangesForTarget(target);

  @override
  String? validateClientDraftForHostAcceptance(SyncChange change) =>
      _AppStoreSplitStartupMigrationsPart3(_store)
          .validateClientDraftForHostAcceptance(change);

  @override
  Future<void> markPushInProgress(Iterable<String> changeIds) =>
      _AppStoreSplitSyncApplyPart4(_store)
          .markSyncQueueChangesInProgress(changeIds);

  @override
  Future<void> markSubmitted(Iterable<String> ids) =>
      _AppStoreSplitSyncApplyPart3(_store).markSyncChangesSubmittedByIds(ids);

  @override
  Future<void> markAcknowledged(Iterable<String> ids) =>
      _AppStoreSplitSyncApplyPart3(_store).markSyncChangesSyncedByIds(ids);

  @override
  Future<void> markFailed(Iterable<String> changeIds, String message) =>
      _AppStoreSplitSyncApplyPart4(_store)
          .markSyncQueueChangesFailed(changeIds, message);

  @override
  Future<void> markRejected(Map<String, String> rejected) =>
      _AppStoreSplitSyncApplyPart4(_store)
          .markSyncChangesRejectedByIds(rejected);

  @override
  Future<void> applyRemoteChanges(
    Iterable<SyncChange> changes, {
    bool markAppliedAsSynced = false,
    bool mirrorToDirect = false,
  }) =>
      _AppStoreSplitSyncApplyPart2(_store)._applyRemoteSyncChanges(
        changes.toList(),
        markAppliedAsSynced: markAppliedAsSynced,
        mirrorToDirect: mirrorToDirect,
      );

  @override
  Future<void> assertRemoteChangesApplied(List<SyncChange> changes) =>
      _AppStoreSplitSyncApplyPart3(_store)
          .assertRemoteSyncChangesApplied(changes);

  @override
  Future<void> retryFailed({String? target}) =>
      _store._retryFailedSyncQueueDomainImpl(target: target);
  @override
  Future<void> recoverSubmitted({String? target}) =>
      _store._recoverSubmittedSyncQueueDomainImpl(target: target);
  @override
  Future<void> recoverStale({
    String? target,
    Duration staleAfter = const Duration(seconds: 45),
  }) =>
      _store._recoverStaleInProgressSyncQueueDomainImpl(
        target: target,
        staleAfter: staleAfter,
      );

  @override
  Future<List<DataConflict>> ensureDataConflictsLoaded() =>
      _AppStoreSplitCoreLoading(_store).ensureDataConflictsLoaded();

  @override
  Future<BusinessDataIntegrityResult> verifyLocalBusinessDataIntegrity() =>
      _AppStoreSplitPersistenceSyncCorePart3(_store)
          .verifyLocalBusinessDataIntegrity();

  @override
  Future<int> cleanupSoftDeletedRecords({
    Duration retention = const Duration(days: 30),
  }) =>
      _AppStoreSplitPersistenceSyncCorePart3(_store)
          .cleanupSoftDeletedRecords(retention: retention);

  @override
  Future<void> recordPhase8AccountingMutationForSync() =>
      _AppStoreSplitPersistenceSyncCorePart4(_store)
          .recordPhase8AccountingMutationForSync();

  @override
  Future<void> recoverPhase8AccountingSyncAfterStartup() =>
      _AppStoreSplitPersistenceSyncCorePart4(_store)
          .recoverPhase8AccountingSyncAfterStartup();

  @override
  Future<Map<String, int>> compactSyncedHistoryForMaintenance({
    int keepRecentSyncedChanges = AppStore._syncMaintenanceKeepRecentChanges,
    int minChangesBeforeCompact =
        AppStore._syncMaintenanceMinChangesBeforeCompact,
  }) =>
      _AppStoreSplitSyncApply(_store).compactSyncedSyncHistoryForMaintenance(
        keepRecentSyncedChanges: keepRecentSyncedChanges,
        minChangesBeforeCompact: minChangesBeforeCompact,
      );

  @override
  Future<Map<String, int>> compactClientSyncedHistoryForMaintenance({
    int keepRecentSyncedChanges = AppStore._syncMaintenanceKeepRecentChanges,
  }) =>
      _AppStoreSplitSyncApply(_store)
          .compactClientSyncedSyncHistoryForMaintenance(
        keepRecentSyncedChanges: keepRecentSyncedChanges,
      );

  @override
  Future<int> settleHostQueueThroughPeerAck() =>
      _AppStoreSplitSyncApplyPart3(_store).settleHostQueueThroughPeerAck();

  @override
  Future<void> settleLegacyLanHostQueue() =>
      _AppStoreSplitSyncApplyPart3(_store).settleLegacyLanHostQueue();

  @override
  Future<void> importSnapshotJson(String rawJson) =>
      _AppStoreSplitSyncApply(_store).importSyncSnapshotJson(rawJson);

  @override
  Future<void> markAllChangesSynced() =>
      _AppStoreSplitSyncApply(_store).markAllSyncChangesSynced();

  @override
  Future<List<Map<String, dynamic>>> exportSnapshotChunks({
    String kind = 'full_store',
    Set<String>? sectionIds,
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  }) =>
      _AppStoreSplitBackupRecovery(_store).exportUnifiedSnapshotChunks(
        kind: kind,
        sectionIds: sectionIds,
        maxItemsPerChunk: maxItemsPerChunk,
        maxEncodedPayloadBytes: maxEncodedPayloadBytes,
      );

  @override
  Map<String, dynamic> snapshotPayloadFromChunks(
    List<Map<String, dynamic>> chunks,
  ) =>
      _AppStoreSplitBackupRecovery(_store)
          .unifiedSnapshotPayloadFromChunks(chunks);

  @override
  DateTime snapshotGeneratedAtFromJson(String rawJson) =>
      _AppStoreSplitBackupRecoveryPart2(_store)
          .syncSnapshotGeneratedAtFromJson(rawJson);

  @override
  int snapshotGeneratedSequenceFromJson(String rawJson) =>
      _AppStoreSplitBackupRecoveryPart2(_store)
          .syncSnapshotGeneratedSequenceFromJson(rawJson);

  @override
  String exportChangesJson({
    DateTime? since,
    int? sinceSequence,
    int? maxEncodedPayloadBytes,
  }) =>
      _AppStoreSplitBackupRecoveryPart2(_store).exportSyncChangesJson(
        since: since,
        sinceSequence: sinceSequence,
        maxEncodedPayloadBytes: maxEncodedPayloadBytes,
      );

  @override
  String get approvedHostTransferDeviceId =>
      LocalDatabaseService.getString(AppStore._hostTransferApprovedDeviceKey)
          ?.trim() ??
      '';

  @override
  Map<String, dynamic>? get pendingHostTransferRequest =>
      _AppStoreSplitIdentityUsers(_store).pendingHostTransferRequest;

  @override
  Future<void> updateAppIdentityLocalOnly(
    AppIdentity identity, {
    String source = 'local sync settings',
  }) =>
      _AppStoreSplitIdentityUsers(_store)
          .updateAppIdentityLocalOnly(identity, source: source);

  @override
  Future<void> setActiveSyncTransport(String transport) =>
      _AppStoreSplitIdentityUsers(_store).setActiveSyncTransport(transport);

  @override
  Future<void> requestHostTransfer({String reason = ''}) =>
      _AppStoreSplitIdentityUsers(_store).requestHostTransfer(reason: reason);

  @override
  Future<void> approveHostTransfer(String requestingDeviceId) =>
      _AppStoreSplitIdentityUsers(_store)
          .approveHostTransfer(requestingDeviceId);

  @override
  Future<void> activateApprovedHostTransfer() =>
      _AppStoreSplitIdentityUsers(_store).activateApprovedHostTransfer();

  @override
  Future<void> clearHostTransferNotification() =>
      _AppStoreSplitIdentityUsers(_store).clearHostTransferNotification();

  @override
  Future<int> clearLocalOnlyPendingSyncChanges() =>
      _AppStoreSplitPersistenceSyncCorePart2(_store)
          .clearLocalOnlyPendingSyncChanges();

  @override
  List<SyncQueueItem> pendingSyncQueueForTarget(
    String target, {
    bool readyOnly = true,
  }) =>
      _AppStoreSplitCoreLoadingPart2(_store)
          .pendingSyncQueueForTarget(target, readyOnly: readyOnly);

  @override
  Future<void> clearPendingSyncQueue({bool notify = true}) =>
      _AppStoreSplitStartupMigrationsPart3(_store)
          .clearPendingSyncQueue(notify: notify);

  @override
  Future<void> markSyncQueueItemFailed(String queueItemId, String error) =>
      _AppStoreSplitSyncApplyPart4(_store)
          .markSyncQueueItemFailed(queueItemId, error);

  @override
  Future<String> exportSyncSnapshotJson() =>
      _AppStoreSplitBackupRecoveryPart2(_store).exportSyncSnapshotJson();
}
