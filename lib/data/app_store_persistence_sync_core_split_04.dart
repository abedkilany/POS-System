part of 'app_store.dart';

extension _AppStoreSplitPersistenceSyncCorePart4 on AppStore {
  String? _sqliteKeyForEntityType(String entityType) {
    switch (entityType) {
      case 'product':
        return AppStore._productsKey;
      case 'customer':
        return AppStore._customersKey;
      case 'supplier':
        return AppStore._suppliersKey;
      case 'supplier_product_price':
        return AppStore._supplierProductPricesKey;
      case 'sale':
        return AppStore._salesKey;
      case 'sale_quotation':
        return AppStore._saleQuotationsKey;
      case 'delivery_note':
        return AppStore._deliveryNotesKey;
      case 'bill_of_materials':
        return AppStore._billsOfMaterialsKey;
      case 'manufacturing_order':
        return AppStore._manufacturingOrdersKey;
      case 'purchase':
        return AppStore._purchasesKey;
      case 'inventory_count':
        return AppStore._inventoryCountsKey;
      case 'warehouse':
        return AppStore._warehousesKey;
      case 'expense':
        return AppStore._expensesKey;
      case 'stock_movement':
        return AppStore._stockMovementsKey;
      case 'account_transaction':
        return AppStore._accountTransactionsKey;
      case 'category':
        return AppStore._categoriesKey;
      case 'brand':
        return AppStore._brandsKey;
      case 'unit':
        return AppStore._unitsKey;
      case 'role':
        return AppStore._rolesKey;
      case 'user':
        return AppStore._usersKey;
    }
    return null;
  }

  void _rememberSqliteDirtyBusinessRow(
    String key,
    Map<String, dynamic> payload,
  ) {
    if (!LocalDatabaseService.isSqliteAuthoritative) return;
    final id = payload['id']?.toString() ?? '';
    if (id.isEmpty) return;
    (_sqliteDirtyBusinessRows[key] ??= <String, Map<String, dynamic>>{})[id] =
        Map<String, dynamic>.from(payload);
  }

  void _forgetSqliteDirtyBusinessRow(String key, String id) {
    final rows = _sqliteDirtyBusinessRows[key];
    rows?.remove(id);
    if (rows?.isEmpty ?? false) {
      _sqliteDirtyBusinessRows.remove(key);
    }
  }

  Map<String, dynamic> _businessPayloadWithoutSyncEnvelope(
    Map<String, dynamic> payload,
  ) {
    final clean = Map<String, dynamic>.from(payload);
    clean.remove('_syncV2');
    return clean;
  }

  void _rememberRemoteSqliteBusinessRows(SyncChange change) {
    if (!LocalDatabaseService.isSqliteAuthoritative) return;

    final businessKey = _sqliteKeyForEntityType(change.entityType);
    if (businessKey != null && change.payload.isNotEmpty) {
      _rememberSqliteDirtyBusinessRow(
        businessKey,
        _businessPayloadWithoutSyncEnvelope(change.payload),
      );
    }

    // Stock movements persist through their own authoritative inventory path.
    // Product rows intentionally carry no inventory quantity anymore.
  }

  void _recordSyncChange({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) {
    _traceSync('syncChange', 'enqueue_change', () {
      final now = DateTime.now();
      final identity = appIdentity;
      final changeId = _newSyncEnvelopeId(now, identity.isHost ? 'evt' : 'cmd');

      // Sync V2 bridge:
      // The existing SyncChange envelope is still kept for compatibility with
      // tests, LAN endpoints, and old installations, but every new local change
      // is explicitly tagged as either a Client DraftCommand or a Host
      // AuthoritativeEvent. Direct/LAN transports can therefore enforce the new
      // Host-authoritative contract without guessing from endpoint names.
      final mutationId =
          '${_deviceId}_${now.microsecondsSinceEpoch}_${entityType}_${entityId}_$operation';
      final isHostEvent = identity.isHost;
      final requestId = isHostEvent ? '' : changeId;
      final eventId = isHostEvent ? changeId : '';
      final syncV2Meta = <String, dynamic>{
        'kind': isHostEvent ? 'authoritativeEvent' : 'draftCommand',
        'requestId': requestId,
        'eventId': eventId,
        'clientMutationId': mutationId,
        'sourceDeviceId': _deviceId,
        'sourceRole': identity.deviceRole.name,
        'transport': identity.transportType,
        'recordedAt': now.toIso8601String(),
      };
      final wrappedPayload = <String, dynamic>{
        ...payload,
        '_syncV2': syncV2Meta
      };

      final draftChange = SyncChange(
        id: changeId,
        entityType: entityType,
        entityId: entityId,
        operation: operation,
        deviceId: _deviceId,
        createdAt: now,
        payload: wrappedPayload,
        storeId: identity.storeId,
        branchId: identity.branchId,
        storeEpoch: identity.storeEpoch,
        // Host is the only authority that may assign final ordering. Client
        // draft commands carry sequence 0 until the Host accepts and republishes
        // them as authoritative events.
        sequence: isHostEvent ? _nextSyncSequence() : 0,
      );
      final queued = _enqueueSyncChange(changeId, now);
      // If no sync transport is enabled by the current Sync settings, keep the
      // local audit envelope but mark it complete immediately. This prevents
      // local-only usage from accumulating misleading pending LAN work
      // just because a legacy AppIdentity still says syncMode=lanOnly.
      final change = queued == null
          ? draftChange.copyWith(isSynced: true, syncedAt: now)
          : draftChange;
      _syncChanges.add(change);
      _sqliteDirtySyncChanges.add(change);
      final businessKey = _sqliteKeyForEntityType(entityType);
      if (businessKey != null) {
        _rememberSqliteDirtyBusinessRow(businessKey, payload);
      }
      if (queued != null) _sqliteDirtySyncQueue.add(queued);
    }, metadata: <String, Object?>{
      'entityType': entityType,
      'entityId': entityId,
      'operation': operation,
    });
  }

  DateTime? _loadPhase8AccountingSyncCursor() {
    final raw =
        LocalDatabaseService.getString(AppStore._phase8AccountingSyncCursorKey)
            ?.trim();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  Future<void> _persistPhase8AccountingSyncCursor(DateTime value) async {
    final normalized = value.toUtc();
    await LocalDatabaseService.setString(
      AppStore._phase8AccountingSyncCursorKey,
      normalized.toIso8601String(),
    );
    _phase8AccountingSyncCursor = normalized;
  }

  Future<void> recoverPhase8AccountingSyncAfterStartup() async {
    if (SqliteMigrationManager.database == null) return;
    await _ensureSyncDataLoaded();
    final storedCursor = _loadPhase8AccountingSyncCursor();
    if (storedCursor == null) {
      await _persistPhase8AccountingSyncCursor(DateTime.now().toUtc());
      return;
    }
    _phase8AccountingSyncCursor = storedCursor;
    await recordPhase8AccountingMutationForSync();
  }

  Future<void> recordPhase8AccountingMutationForSync() async {
    if (SqliteMigrationManager.database == null) return;
    if (_phase8AccountingSyncCaptureInFlight) {
      _phase8AccountingSyncCapturePending = true;
      return;
    }
    _phase8AccountingSyncCaptureInFlight = true;
    final capturedAt = DateTime.now().toUtc();
    try {
      var since =
          _phase8AccountingSyncCursor ?? _loadPhase8AccountingSyncCursor();
      // Startup recovery normally establishes the durable baseline before any
      // user mutation is possible. Keep a narrow defensive fallback for tests
      // or non-standard callers that invoke a mutation hook before recovery.
      since ??= capturedAt.subtract(const Duration(seconds: 5));

      final collections =
          await LocalDatabaseService.getPhase8AccountingDeltaRows(since);
      if (collections.isNotEmpty) {
        _recordSyncChange(
          entityType: 'cash_accounting_delta',
          entityId: capturedAt.microsecondsSinceEpoch.toString(),
          operation: 'upsert',
          payload: <String, dynamic>{
            'capturedAt': capturedAt.toIso8601String(),
            'collections': collections,
          },
        );
        // Persist the queue/event before moving the durable cursor. If the
        // process dies before this succeeds, the old cursor remains and the
        // rows are captured again on restart rather than being lost.
        await _saveSyncStateOnly();
      }
      // Advancing an empty scan is safe and avoids repeatedly rescanning an
      // unchanged accounting database. This happens only after the read and,
      // when needed, the sync event persistence have completed successfully.
      await _persistPhase8AccountingSyncCursor(capturedAt);
    } finally {
      _phase8AccountingSyncCaptureInFlight = false;
      if (_phase8AccountingSyncCapturePending) {
        _phase8AccountingSyncCapturePending = false;
        unawaited(recordPhase8AccountingMutationForSync());
      }
    }
  }

  bool get _isLanClientConfigured {
    final raw = LocalDatabaseService.getString('lan_sync_settings_v2');
    if (raw == null || raw.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final mode = decoded['mode']?.toString() ?? '';
      final setupComplete = decoded['setupComplete'] as bool? ?? false;
      final hostModeEnabled = decoded['hostModeEnabled'] as bool? ?? false;
      return setupComplete && (mode == 'client' || !hostModeEnabled);
    } catch (_) {
      return false;
    }
  }

  bool get _isDirectClientConfigured {
    final identity = appIdentity;
    final settings = DirectSyncSettings.load();
    return identity.isClient &&
        identity.deviceId.trim().isNotEmpty &&
        identity.deviceToken.trim().isNotEmpty &&
        settings.isConfigured;
  }

  bool get _isLanHostConfigured {
    final raw = LocalDatabaseService.getString('lan_sync_settings_v2');
    if (raw == null || raw.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final mode = decoded['mode']?.toString() ?? '';
      final setupComplete = decoded['setupComplete'] as bool? ?? false;
      final hostModeEnabled = decoded['hostModeEnabled'] as bool? ?? false;
      return setupComplete && (mode == 'host' || hostModeEnabled);
    } catch (_) {
      return false;
    }
  }

  SyncQueueItem? _enqueueSyncChange(String changeId, DateTime now) {
    final identity = appIdentity;
    final activeTransport = identity.activeSyncTransportNormalized;
    final isLanClient =
        identity.isClient && activeTransport == 'lan' && _isLanClientConfigured;
    final isDirectClient = identity.isClient && activeTransport == 'direct';
    final isDirectHost = identity.isHost && activeTransport == 'direct';

    // Sync architecture v2: the Host is the only source of truth. Both
    // supported remote transports deliver Client work to that Host.
    // Direct Host events must enter the publish queue as well. They are
    // authoritative locally, but Clients still need a broadcast wake-up and
    // must be able to pull them from the Host timeline. Previously Host local
    // writes were marked synced immediately and never reached the publish
    // path, which is especially visible under synthetic sync workloads.
    final target =
        isLanClient || isDirectClient || isDirectHost ? 'host' : 'local';
    if (target == 'local') return null;
    final item = SyncQueueItem(
      id: '$changeId-$target',
      changeId: changeId,
      target: target,
      status: 'pending',
      attempts: 0,
      createdAt: now,
      updatedAt: now,
    );
    _syncQueue.add(item);
    return item;
  }

  String get _stockTransactionSyncTarget {
    final identity = appIdentity;
    final transport = identity.activeSyncTransportNormalized;
    if (identity.isClient && (transport == 'lan' || transport == 'direct')) {
      return 'host';
    }
    if (identity.isHost && transport == 'direct') return 'host';
    return 'local';
  }

  Future<void> _reconcileUnsyncedChangesWithQueue() async {
    final identity = appIdentity;
    final isRemoteClient = identity.isClient &&
        (identity.activeSyncTransportNormalized == 'direct' ||
            identity.activeSyncTransportNormalized == 'lan');
    final isDirectHost =
        identity.isHost && identity.activeSyncTransportNormalized == 'direct';
    if (!isRemoteClient && !isDirectHost) return;

    const target = 'host';
    final queueByChangeId = <String, SyncQueueItem>{
      for (final item in _syncQueue.where((item) => item.target == target))
        item.changeId: item,
    };
    var repaired = 0;
    var reset = 0;
    final now = DateTime.now();

    for (final change in _syncChanges.where((item) => !item.isSynced)) {
      if (isRemoteClient && change.deviceId != _deviceId) continue;
      final existing = queueByChangeId[change.id];
      if (existing == null) {
        final item = SyncQueueItem(
          id: '${change.id}-$target',
          changeId: change.id,
          target: target,
          status: 'pending',
          attempts: 0,
          createdAt: change.createdAt,
          updatedAt: now,
        );
        _syncQueue.add(item);
        queueByChangeId[change.id] = item;
        repaired++;
      } else if (existing.status == 'synced') {
        // The change itself is still unsynced, so a synced queue row is stale.
        final repairedItem = existing.copyWith(
          status: 'pending',
          updatedAt: now,
          clearNextRetryAt: true,
        );
        final index = _syncQueue.indexOf(existing);
        if (index >= 0) _syncQueue[index] = repairedItem;
        queueByChangeId[change.id] = repairedItem;
        reset++;
      }
    }

    if (repaired == 0 && reset == 0) return;
    await _saveSyncStateOnly();
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] syncQueue:reconciled role=${identity.deviceRole.name} '
      'target=$target repaired=$repaired reset=$reset '
      'unsynced=${_syncChanges.where((item) => !item.isSynced).length} '
      'queue=${_syncQueue.length}',
    );
  }

  Sale _saleSyncMetaPreview(
    Sale item,
    DateTime now, {
    bool isCreate = false,
  }) {
    return item.copyWith(
      createdAt: isCreate ? now : item.createdAt,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      version: _readVersion(item) + (isCreate ? 0 : 1),
      lastModifiedByDeviceId: _deviceId,
      clearDeletedAt: true,
    );
  }

  Purchase _purchaseSyncMetaPreview(
    Purchase item,
    DateTime now, {
    bool isCreate = false,
  }) {
    return item.copyWith(
      createdAt: isCreate ? now : item.createdAt,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      version: _readVersion(item) + (isCreate ? 0 : 1),
      lastModifiedByDeviceId: _deviceId,
      clearDeletedAt: true,
    );
  }

  Expense _expenseSyncMetaPreview(
    Expense item,
    DateTime now, {
    bool isCreate = false,
  }) {
    return item.copyWith(
      createdAt: isCreate ? now : item.createdAt,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      version: _readVersion(item) + (isCreate ? 0 : 1),
      lastModifiedByDeviceId: _deviceId,
      clearDeletedAt: true,
    );
  }

  T _withSyncMeta<T>(
    T item,
    DateTime now, {
    bool isCreate = false,
    bool clearDeletedAt = true,
  }) {
    final nextVersion = _readVersion(item) + (isCreate ? 0 : 1);
    final storeId = appIdentity.storeId;
    final branchId = appIdentity.branchId;
    if (item is Product) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(AppStore._productsKey, updated.toJson());
      return updated as T;
    }
    if (item is Customer) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(AppStore._customersKey, updated.toJson());
      return updated as T;
    }
    if (item is Supplier) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(AppStore._suppliersKey, updated.toJson());
      return updated as T;
    }
    if (item is SupplierProductPrice) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(
        AppStore._supplierProductPricesKey,
        updated.toJson(),
      );
      return updated as T;
    }
    if (item is Expense) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(AppStore._expensesKey, updated.toJson());
      return updated as T;
    }
    if (item is CatalogItem) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      return updated as T;
    }
    if (item is Sale) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(AppStore._salesKey, updated.toJson());
      return updated as T;
    }
    if (item is SaleQuotation) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
      );
      _rememberSqliteDirtyBusinessRow(
          AppStore._saleQuotationsKey, updated.toJson());
      return updated as T;
    }
    if (item is DeliveryNote) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(
          AppStore._deliveryNotesKey, updated.toJson());
      return updated as T;
    }
    if (item is BillOfMaterials) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(
          AppStore._billsOfMaterialsKey, updated.toJson());
      return updated as T;
    }
    if (item is ManufacturingOrder) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(
        AppStore._manufacturingOrdersKey,
        updated.toJson(),
      );
      return updated as T;
    }
    if (item is Purchase) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(AppStore._purchasesKey, updated.toJson());
      return updated as T;
    }
    if (item is AccountTransaction) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(
        AppStore._accountTransactionsKey,
        updated.toJson(),
      );
      return updated as T;
    }
    return item;
  }

  Future<void> _persistAccountTransactionInExistingTransaction(
    dynamic sqliteDb,
    AccountTransaction transaction,
  ) async {
    await BusinessSqliteStore.upsertEntityPayloads(
      sqliteDb,
      AppStore._accountTransactionsKey,
      <Map<String, dynamic>>[transaction.toJson()],
      sortIndices: const <int?>[0],
    );
  }

  Future<void> _persistAccountTransactionSqliteFirst(
    AccountTransaction transaction,
  ) async {
    if (!LocalDatabaseService.isSqliteAuthoritative) return;
    try {
      await LocalDatabaseService.upsertBusinessEntityJsons(
        AppStore._accountTransactionsKey,
        <Map<String, dynamic>>[transaction.toJson()],
      );
    } finally {
      // _withSyncMeta() stages account transactions for the generic dirty-row
      // writer. A direct SQLite-first write owns persistence for this row, so
      // remove that staged copy on both success and failure. On failure the
      // exception is rethrown and RAM/UI is left untouched.
      _sqliteDirtyBusinessRows[AppStore._accountTransactionsKey]
          ?.remove(transaction.id);
      if (_sqliteDirtyBusinessRows[AppStore._accountTransactionsKey]?.isEmpty ??
          false) {
        _sqliteDirtyBusinessRows.remove(AppStore._accountTransactionsKey);
      }
    }
  }
}
