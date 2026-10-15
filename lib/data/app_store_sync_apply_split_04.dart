part of 'app_store.dart';

extension _AppStoreSplitSyncApplyPart4 on AppStore {
  Future<void> markSyncQueueChangesInProgress(
    Iterable<String> changeIds,
  ) async {
    await ensureSyncDataLoaded();
    final idSet = changeIds.toSet();
    if (idSet.isEmpty) return;
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _syncQueue.length; i++) {
      if (idSet.contains(_syncQueue[i].changeId) &&
          _syncQueue[i].status != 'synced') {
        _syncQueue[i] = _syncQueue[i].copyWith(
          status: 'inProgress',
          updatedAt: now,
          clearNextRetryAt: true,
        );
        changed = true;
      }
    }
    if (!changed) return;
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> markSyncChangesRejectedByIds(
    Map<String, String> rejected,
  ) async {
    if (rejected.isEmpty) return;
    final idSet = rejected.keys.toSet();
    final now = DateTime.now();
    var changed = false;
    final rejectedChanges = <SyncChange>[];
    for (var i = 0; i < _syncQueue.length; i++) {
      final item = _syncQueue[i];
      final reason = rejected[item.changeId];
      if (idSet.contains(item.changeId) &&
          item.status != 'synced' &&
          reason != null) {
        _syncQueue[i] = item.copyWith(
          status: 'rejected',
          lastError: reason,
          updatedAt: now,
          clearNextRetryAt: true,
        );
        changed = true;
      }
    }
    for (var i = 0; i < _syncChanges.length; i++) {
      final change = _syncChanges[i];
      final matches = idSet.contains(change.id) ||
          idSet.contains(_syncMetaString(change, 'eventId')) ||
          idSet.contains(_syncMetaString(change, 'requestId')) ||
          idSet.contains(_syncMetaString(change, 'sourceCommandId'));
      if (matches) {
        rejectedChanges.add(change);
        _syncChanges[i] = change.copyWith(isSynced: true, syncedAt: now);
        changed = true;
      }
    }
    var quarantinedLocalCreate = false;
    if (rejectedChanges.isNotEmpty) {
      quarantinedLocalCreate = _quarantineRejectedLocalCreates(
        rejectedChanges,
        rejected,
        now,
      );
      changed = quarantinedLocalCreate || changed;
    }
    if (!changed) return;
    if (quarantinedLocalCreate) {
      await _saveDirty(
        products: true,
        customers: true,
        suppliers: true,
        supplierProductPrices: true,
        sync: true,
      );
    } else {
      await _saveSyncStateOnly();
    }
    notifyListeners();
  }

  bool _quarantineRejectedLocalCreates(
    List<SyncChange> rejectedChanges,
    Map<String, String> rejectedReasons,
    DateTime now,
  ) {
    var changed = false;
    for (final change in rejectedChanges) {
      // Only quarantine local creates/drafts. Remote authoritative changes must
      // never be deleted because of a status poll. The most common rejection in
      // the stress tests is duplicate product code/barcode; leaving that local
      // draft visible makes device counts diverge even though the Host rejected it.
      if (change.deviceId != _deviceId || change.operation == 'delete') {
        continue;
      }
      final reason = rejectedReasons[change.id] ??
          rejectedReasons[_syncMetaString(change, 'eventId')] ??
          rejectedReasons[_syncMetaString(change, 'requestId')] ??
          rejectedReasons[_syncMetaString(change, 'sourceCommandId')] ??
          'Rejected by Host.';
      switch (change.entityType) {
        case 'product':
          final index = _productIndexById[change.entityId];
          if (index != null && !_products[index].isDeleted) {
            _products[index] = _products[index].copyWith(
              isActive: false,
              syncStatus: 'rejected: $reason',
              updatedAt: now,
              deletedAt: now,
            );
            _rememberSqliteDirtyBusinessRow(
              AppStore._productsKey,
              _products[index].toJson(),
            );
            changed = true;
          }
          break;
        case 'customer':
          final index = _customers.indexWhere(
            (item) => item.id == change.entityId && !item.isDeleted,
          );
          if (index >= 0) {
            _customers[index] = _customers[index].copyWith(
              syncStatus: 'rejected: $reason',
              updatedAt: now,
              deletedAt: now,
            );
            _rememberSqliteDirtyBusinessRow(
              AppStore._customersKey,
              _customers[index].toJson(),
            );
            changed = true;
          }
          break;
        case 'supplier':
          final index = _suppliers.indexWhere(
            (item) => item.id == change.entityId && !item.isDeleted,
          );
          if (index >= 0) {
            _suppliers[index] = _suppliers[index].copyWith(
              syncStatus: 'rejected: $reason',
              updatedAt: now,
              deletedAt: now,
            );
            _rememberSqliteDirtyBusinessRow(
              AppStore._suppliersKey,
              _suppliers[index].toJson(),
            );
            changed = true;
          }
          break;
        case 'supplier_product_price':
          final index = _supplierProductPrices.indexWhere(
            (item) => item.id == change.entityId && !item.isDeleted,
          );
          if (index >= 0) {
            _supplierProductPrices[index] =
                _supplierProductPrices[index].copyWith(
              syncStatus: 'rejected: $reason',
              updatedAt: now,
              deletedAt: now,
            );
            _rememberSqliteDirtyBusinessRow(
              AppStore._supplierProductPricesKey,
              _supplierProductPrices[index].toJson(),
            );
            changed = true;
          }
          break;
      }
    }
    return changed;
  }

  Future<void> markSyncQueueChangesFailed(
    Iterable<String> changeIds,
    String error,
  ) async {
    final idSet = changeIds.toSet();
    if (idSet.isEmpty) return;
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _syncQueue.length; i++) {
      if (idSet.contains(_syncQueue[i].changeId) &&
          _syncQueue[i].status != 'synced') {
        final attempts = _syncQueue[i].attempts + 1;
        _syncQueue[i] = _syncQueue[i].copyWith(
          status: 'failed',
          attempts: attempts,
          lastError: error,
          updatedAt: now,
          // LAN sync should not block manual/auto retries for minutes.
          // A short backoff keeps reconnects responsive while still avoiding
          // a tight loop during brief network failures.
          nextRetryAt: now.add(Duration(seconds: (attempts * 5).clamp(5, 30))),
        );
        changed = true;
      }
    }
    if (!changed) return;
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> retryFailedSyncQueue({String? target}) async {
    await ensureSyncDataLoaded();
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _syncQueue.length; i++) {
      final item = _syncQueue[i];
      if (item.status == 'failed' &&
          (target == null || item.target == target)) {
        _syncQueue[i] = item.copyWith(
          status: 'pending',
          updatedAt: now,
          clearNextRetryAt: true,
        );
        changed = true;
      }
    }
    if (!changed) return;
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> recoverStaleInProgressSyncQueue({
    String? target,
    Duration staleAfter = const Duration(seconds: 45),
  }) async {
    final now = DateTime.now();
    final cutoff = now.subtract(staleAfter);
    var changed = false;
    for (var i = 0; i < _syncQueue.length; i++) {
      final item = _syncQueue[i];
      if (item.status == 'inProgress' &&
          item.updatedAt.isBefore(cutoff) &&
          (target == null || item.target == target)) {
        _syncQueue[i] = item.copyWith(
          status: 'pending',
          lastError:
              'Recovered stale in-progress sync item after timeout/crash.',
          updatedAt: now,
          clearNextRetryAt: true,
        );
        changed = true;
      }
    }
    if (!changed) return;
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> recoverSubmittedSyncQueue({String? target}) async {
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _syncQueue.length; i++) {
      final item = _syncQueue[i];
      if (item.status == 'submitted' &&
          (target == null || item.target == target)) {
        _syncQueue[i] = item.copyWith(
          status: 'pending',
          lastError:
              'Recovered legacy submitted sync item for direct Host relay confirmation.',
          updatedAt: now,
          clearNextRetryAt: true,
        );
        changed = true;
      }
    }
    if (!changed) return;
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> markSyncQueueItemFailed(String queueItemId, String error) async {
    final index = _syncQueue.indexWhere((item) => item.id == queueItemId);
    if (index == -1) return;
    final now = DateTime.now();
    final attempts = _syncQueue[index].attempts + 1;
    _syncQueue[index] = _syncQueue[index].copyWith(
      status: 'failed',
      attempts: attempts,
      lastError: error,
      updatedAt: now,
      nextRetryAt: now.add(Duration(minutes: attempts.clamp(1, 30))),
    );
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> prepareForShutdown() async {
    if (_shutdownPrepared) {
      // A concurrent caller may arrive while the first shutdown drain is still
      // finishing. _flushProductDerivedData() is re-entrant and waits for the
      // same in-flight writer, so this remains a deterministic barrier.
      await _flushProductDerivedData();
      await LocalDatabaseService.flushPendingWrites();
      return;
    }
    _shutdownPrepared = true;
    _productDerivedDataFlushTimer?.cancel();
    _productDerivedDataFlushTimer = null;
    await _flushProductDerivedData();
    // A mutation that raced with the first drain cannot schedule a new timer
    // once _shutdownPrepared is true, but it can set dirty. Drain once more as
    // a defensive barrier before the SQLite facade itself is flushed/closed.
    await _flushProductDerivedData();
    await LocalDatabaseService.flushPendingWrites();
  }
}
