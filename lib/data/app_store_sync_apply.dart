part of 'app_store.dart';

extension _AppStoreSplitSyncApply on AppStore {
Future<void> markAllSyncChangesSynced() async {
    final now = DateTime.now();
    for (var i = 0; i < _syncChanges.length; i++) {
      _syncChanges[i] = _syncChanges[i].copyWith(isSynced: true, syncedAt: now);
    }
    await _saveSyncStateOnly();
    notifyListeners();
  }

Future<void> importSyncSnapshotJson(String rawJson) async {
    await AppStoreRecoveryService(this).importSyncSnapshotJson(rawJson);
  }

Future<void> _replaceFromBackupMap(
    Map<String, dynamic> decoded, {
    bool preserveLocalIdentityForLanClient = false,
  }) async {
    final unifiedChunks = decoded['snapshotChunks'];
    if (unifiedChunks is List) {
      decoded = unifiedSnapshotPayloadFromChunks(
        unifiedChunks
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false),
      );
    }
    final products = (decoded['products'] as List<dynamic>? ?? [])
        .map((item) => Product.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final customers = (decoded['customers'] as List<dynamic>? ?? [])
        .map(
          (item) => Customer.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final sales = (decoded['sales'] as List<dynamic>? ?? [])
        .map((item) => Sale.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final rawSaleQuotations = (decoded['saleQuotations'] as List<dynamic>?) ??
        (decoded['quotations'] as List<dynamic>?) ??
        const <dynamic>[];
    final saleQuotations = rawSaleQuotations
        .map(
          (item) =>
              SaleQuotation.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final deliveryNotes = (decoded['deliveryNotes'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              DeliveryNote.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final billsOfMaterials =
        (decoded['billsOfMaterials'] as List<dynamic>? ?? [])
            .map(
              (item) => BillOfMaterials.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final manufacturingOrders =
        (decoded['manufacturingOrders'] as List<dynamic>? ?? [])
            .map(
              (item) => ManufacturingOrder.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final suppliers = (decoded['suppliers'] as List<dynamic>? ?? [])
        .map(
          (item) => Supplier.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final supplierProductPrices =
        (decoded['supplierProductPrices'] as List<dynamic>? ?? [])
            .map(
              (item) => SupplierProductPrice.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final priceLists = (decoded['priceLists'] as List<dynamic>? ?? [])
        .map((item) =>
            PriceList.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final productPrices = (decoded['productPrices'] as List<dynamic>? ?? [])
        .map((item) =>
            ProductPrice.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final productPriceOverrides =
        (decoded['productPriceOverrides'] as List<dynamic>? ?? [])
            .map((item) => ProductPriceOverride.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList();
    final productCosts = (decoded['productCosts'] as List<dynamic>? ?? [])
        .map((item) =>
            ProductCost.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((item) => item.productId.isNotEmpty)
        .toList();
    final costingMethodHistory =
        (decoded['costingMethodHistory'] as List<dynamic>? ?? [])
            .map((item) => CostingMethodHistory.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .where((item) => item.id.isNotEmpty)
            .toList();
    final inventoryCostingMethod = InventoryCostingMethodJson.fromCode(
      decoded['inventoryCostingMethod'] is List
          ? ((decoded['inventoryCostingMethod'] as List).isEmpty
              ? null
              : (decoded['inventoryCostingMethod'] as List).first as String?)
          : decoded['inventoryCostingMethod'] as String?,
    );
    final inventoryCostLayers = (decoded['inventoryCostLayers']
                as List<dynamic>? ??
            [])
        .map((item) =>
            InventoryCostLayer.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((item) => item.id.isNotEmpty && item.productId.isNotEmpty)
        .toList();
    final categories = (decoded['categories'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final brands = (decoded['brands'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final units = (decoded['units'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final expenses = (decoded['expenses'] as List<dynamic>? ?? [])
        .map((item) => Expense.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final purchases = (decoded['purchases'] as List<dynamic>? ?? [])
        .map(
          (item) => Purchase.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final stockMovements = (decoded['stockMovements'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              StockMovement.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final inventoryCounts = (decoded['inventoryCounts'] as List<dynamic>? ?? [])
        .map(
          (item) => InventoryCountSession.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
    final warehouses = (decoded['warehouses'] as List<dynamic>? ?? [])
        .map(
          (item) => Warehouse.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final accountTransactions =
        (decoded['accountTransactions'] as List<dynamic>? ?? [])
            .map(
              (item) => AccountTransaction.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final roles = (decoded['roles'] as List<dynamic>? ?? [])
        .map(
          (item) => UserRole.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final users = (decoded['users'] as List<dynamic>? ?? [])
        .map((item) => AppUser.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final profile = decoded['storeProfile'] == null
        ? StoreProfile.defaults
        : StoreProfile.fromJson(
            Map<String, dynamic>.from(decoded['storeProfile'] as Map),
          );

    if (wants('products')) {
      _products
        ..clear()
        ..addAll(products);
    }
    if (wants('customers')) {
      _customers
        ..clear()
        ..addAll(customers);
    }
    if (wants('sales')) {
      _sales
        ..clear()
        ..addAll(sales);
    }
    if (wants('saleQuotations')) {
      _saleQuotations
        ..clear()
        ..addAll(saleQuotations);
    }
    if (wants('deliveryNotes')) {
      _deliveryNotes
        ..clear()
        ..addAll(deliveryNotes);
    }
    if (wants('manufacturing')) {
      _billsOfMaterials
        ..clear()
        ..addAll(billsOfMaterials);
      _manufacturingOrders
        ..clear()
        ..addAll(manufacturingOrders);
    }
    if (wants('suppliers')) {
      _suppliers
        ..clear()
        ..addAll(suppliers);
    }
    if (wants('supplierProductPrices')) {
      _supplierProductPrices
        ..clear()
        ..addAll(supplierProductPrices);
    }
    if (wants('priceLists')) {
      _priceLists
        ..clear()
        ..addAll(priceLists);
    }
    if (wants('productPrices')) {
      _productPrices
        ..clear()
        ..addAll(productPrices);
    }
    if (wants('productPriceOverrides')) {
      _productPriceOverrides
        ..clear()
        ..addAll(productPriceOverrides);
    }
    if (wants('productCosts')) {
      _productCosts
        ..clear()
        ..addAll(productCosts);
    }
    if (wants('costingMethodHistory')) {
      _costingMethodHistory
        ..clear()
        ..addAll(costingMethodHistory);
    }
    if (wants('inventoryCostingMethod')) {
      _inventoryCostingMethod =
        _runtimeInventoryCostingMethod(inventoryCostingMethod);
    }
    if (wants('inventoryCostLayers')) {
      _inventoryCostLayers
        ..clear()
        ..addAll(inventoryCostLayers);
    }
    if (wants('categories')) {
      _categories
        ..clear()
        ..addAll(categories);
    }
    if (wants('brands')) {
      _brands
        ..clear()
        ..addAll(brands);
    }
    if (wants('units')) {
      _units
        ..clear()
        ..addAll(units);
    }
    if (wants('expenses')) {
      _expenses
        ..clear()
        ..addAll(expenses);
    }
    if (wants('purchases')) {
      _purchases
        ..clear()
        ..addAll(purchases);
    }
    if (wants('stockMovements')) {
      _stockMovements
        ..clear()
        ..addAll(stockMovements);
    }
    if (wants('inventoryCounts')) {
      _inventoryCounts
        ..clear()
        ..addAll(inventoryCounts);
    }
    if (wants('warehouses')) {
      _warehouses
        ..clear()
        ..addAll(warehouses);
    }
    _ensureDefaultWarehouse();
    if (wants('accountTransactions')) {
      _accountTransactions
        ..clear()
        ..addAll(accountTransactions);
    }
    _invalidateAccountLedgerCache();
    _rebuildProductPricingLookupCaches();
    _syncChanges
      ..clear()
      ..addAll(
        preserveLocalIdentityForLanClient
            ? syncChanges.map(
                (item) =>
                    item.copyWith(isSynced: true, syncedAt: DateTime.now()),
              )
            : syncChanges,
      );
    _syncQueue.clear();
    if (!preserveLocalIdentityForLanClient) _syncQueue.addAll(syncQueue);
    if (wants('storeProfile')) {
      _storeProfile = profile;
      AccountingService.configureMoneyPolicy(_storeProfile);
    }
    if (preserveLocalIdentityForLanClient) {
      _appIdentity = _identityForLanSnapshotImport(decoded);
      await LocalDatabaseService.setString(
        AppStore._appIdentityKey,
        jsonEncode(_appIdentity!.toJson()),
      );
    } else if (decoded['appIdentity'] is Map) {
      _appIdentity = AppIdentity.fromJson(
        Map<String, dynamic>.from(decoded['appIdentity'] as Map),
      ).copyWith(deviceId: _deviceId, platform: _detectPlatform());
      await LocalDatabaseService.setString(
        AppStore._appIdentityKey,
        jsonEncode(_appIdentity!.toJson()),
      );
    }
    if (roles.isNotEmpty) {
      _roles
        ..clear()
        ..addAll(roles);
    }
    if (users.isNotEmpty) _replaceUsersWithoutDuplicates(users);
    await _ensureDefaultAdminUser();
    _invoiceCounter =
        (decoded['invoiceCounter'] as num?)?.toInt() ?? _invoiceCounter;
    _purchaseCounter =
        (decoded['purchaseCounter'] as num?)?.toInt() ?? _purchaseCounter;
    _ensureCatalogDefaults();
    _normalizeCustomers();
    await _saveAll();
    notifyListeners();
  }

Map<String, int> _syncHistoryCompactionResult({
    required int beforeChanges,
    required int beforeQueue,
    required int safeFloorSequence,
    int skipped = 0,
  }) {
    return {
      'removedChanges': beforeChanges - _syncChanges.length,
      'removedQueue': beforeQueue - _syncQueue.length,
      'remainingChanges': _syncChanges.length,
      'remainingQueue': _syncQueue.length,
      'pendingChanges': pendingSyncChanges.length,
      'pendingQueue': pendingSyncQueue.length,
      'safeFloorSequence': safeFloorSequence,
      'earliestSequence': _earliestStoredAuthoritativeSequence(),
      'latestSequence': _latestStoredAuthoritativeSequence(),
      'skipped': skipped,
    };
  }

String _syncHistoryCompactionLogLine(String label, Map<String, int> result) {
    final pendingQueue = result['pendingQueue'] ?? pendingSyncQueue.length;
    final pendingChanges =
        result['pendingChanges'] ?? pendingSyncChanges.length;
    final remainingQueue = result['remainingQueue'] ?? _syncQueue.length;
    final remainingChanges = result['remainingChanges'] ?? _syncChanges.length;
    final safeFloorSequence = result['safeFloorSequence'] ?? 0;
    final earliestSequence =
        result['earliestSequence'] ?? _earliestStoredAuthoritativeSequence();
    final latestSequence =
        result['latestSequence'] ?? _latestStoredAuthoritativeSequence();
    return '$label role=${appIdentity.deviceRole.name.toUpperCase()} '
        'device=$_deviceId store=${appIdentity.storeId} branch=${appIdentity.branchId} '
        'epoch=${appIdentity.storeEpoch} seq=$_syncSequence '
        'products=${_products.length} customers=${_customers.length} suppliers=${_suppliers.length} '
        'sales=${_sales.length} stockMovements=${_stockMovements.length} '
        'pendingQueue=$pendingQueue pendingChanges=$pendingChanges '
        'allQueue=$remainingQueue allChanges=$remainingChanges '
        'safeFloorSequence=$safeFloorSequence earliestSequence=$earliestSequence latestSequence=$latestSequence';
  }

Future<Map<String, int>> compactSyncedSyncHistoryForDiagnostics({
    int keepRecentSyncedChanges = AppStore._syncMaintenanceKeepRecentChanges,
  }) async {
    return _compactSyncedSyncHistory(
      keepRecentSyncedChanges: keepRecentSyncedChanges,
      requireSafeFloorSequence: true,
    );
  }

Future<Map<String, int>> compactSyncedSyncHistoryForMaintenance({
    int keepRecentSyncedChanges = AppStore._syncMaintenanceKeepRecentChanges,
    int minChangesBeforeCompact = AppStore._syncMaintenanceMinChangesBeforeCompact,
  }) async {
    final safeFloorSequence = _minimumActivePeerAckSequence();
    final before = _syncHistoryCompactionResult(
      beforeChanges: _syncChanges.length,
      beforeQueue: _syncQueue.length,
      safeFloorSequence: safeFloorSequence,
    );

    if (!appIdentity.isHost) {
      return Map<String, int>.from(before)..['skipped'] = 1;
    }
    // Host maintenance must not stop just because there is pending Direct/LAN work.
    // Pending queue rows are protected inside _compactSyncedSyncHistory via
    // pendingChangeIds, while old already-synced rows can still be trimmed.
    if (safeFloorSequence <= 0) {
      return Map<String, int>.from(before)..['skipped'] = 1;
    }
    if (_syncChanges.length <= minChangesBeforeCompact && _syncQueue.isEmpty) {
      return Map<String, int>.from(before)..['skipped'] = 1;
    }

    debugPrint(
      _syncHistoryCompactionLogLine('BEFORE_AUTO_COMPACT_SYNC_HISTORY', before),
    );
    final result = await _compactSyncedSyncHistory(
      keepRecentSyncedChanges: keepRecentSyncedChanges,
      requireSafeFloorSequence: true,
      knownSafeFloorSequence: safeFloorSequence,
    );
    debugPrint(
      _syncHistoryCompactionLogLine('AFTER_AUTO_COMPACT_SYNC_HISTORY', result),
    );
    return result;
  }

Future<Map<String, int>> compactClientSyncedSyncHistoryForMaintenance({
    int keepRecentSyncedChanges = AppStore._syncMaintenanceKeepRecentChanges,
  }) async {
    final latestAppliedSequence = _latestStoredAuthoritativeSequence();
    final before = _syncHistoryCompactionResult(
      beforeChanges: _syncChanges.length,
      beforeQueue: _syncQueue.length,
      safeFloorSequence: latestAppliedSequence,
    );

    if (!appIdentity.isClient) {
      return Map<String, int>.from(before)..['skipped'] = 1;
    }
    final removedStaleQueue = _removeStaleClientSyncedQueueRows();
    if (removedStaleQueue > 0) {
      debugPrint(
        'CLIENT_SYNC_STALE_QUEUE_CLEANUP removedQueue=$removedStaleQueue '
        'remainingQueue=${_syncQueue.length} pendingQueue=${pendingSyncQueue.length}',
      );
    }
    if (pendingSyncQueue.isNotEmpty || pendingSyncChanges.isNotEmpty) {
      if (removedStaleQueue > 0) {
        await _saveSyncStateOnly();
        notifyListeners();
        return _syncHistoryCompactionResult(
          beforeChanges: before['remainingChanges'] ?? _syncChanges.length,
          beforeQueue: before['remainingQueue'] ??
              (_syncQueue.length + removedStaleQueue),
          safeFloorSequence: latestAppliedSequence,
          skipped: 1,
        );
      }
      return Map<String, int>.from(before)..['skipped'] = 1;
    }
    if (latestAppliedSequence <= 0) {
      if (removedStaleQueue > 0) {
        await _saveSyncStateOnly();
        notifyListeners();
        return _syncHistoryCompactionResult(
          beforeChanges: before['remainingChanges'] ?? _syncChanges.length,
          beforeQueue: before['remainingQueue'] ??
              (_syncQueue.length + removedStaleQueue),
          safeFloorSequence: latestAppliedSequence,
          skipped: 1,
        );
      }
      return Map<String, int>.from(before)..['skipped'] = 1;
    }
    // Client compaction must still run when authoritative history is above the
    // retention window, even if it is below the Host maintenance threshold.
    // Example: Direct Client can have 353 authoritative synced changes, queue=0,
    // and keepRecentSyncedChanges=200. The old minChangesBeforeCompact=1000
    // guard skipped compaction forever, leaving DB_BLOAT=FAIL although there
    // was no pending work. Skip only when there is nothing to trim.
    final hasAuthoritativeHistoryOverRetention = _syncChanges.any(
          (item) =>
              item.isSynced &&
              item.sequence > 0 &&
              item.sequence <= latestAppliedSequence,
        ) &&
        _syncChanges
                .where((item) => item.isSynced && item.sequence > 0)
                .length >
            keepRecentSyncedChanges;
    final hasSyncedLocalDrafts = _syncChanges.any(
      (item) => item.isSynced && item.sequence <= 0,
    );
    if (!hasAuthoritativeHistoryOverRetention &&
        !hasSyncedLocalDrafts &&
        _syncQueue.isEmpty) {
      if (removedStaleQueue > 0) {
        await _saveSyncStateOnly();
        notifyListeners();
        return _syncHistoryCompactionResult(
          beforeChanges: before['remainingChanges'] ?? _syncChanges.length,
          beforeQueue: before['remainingQueue'] ??
              (_syncQueue.length + removedStaleQueue),
          safeFloorSequence: latestAppliedSequence,
          skipped: 1,
        );
      }
      return Map<String, int>.from(before)..['skipped'] = 1;
    }

    debugPrint(
      _syncHistoryCompactionLogLine(
        'BEFORE_CLIENT_AUTO_COMPACT_SYNC_HISTORY',
        before,
      ),
    );
    final rawResult = await _compactSyncedSyncHistory(
      keepRecentSyncedChanges: keepRecentSyncedChanges,
      requireSafeFloorSequence: false,
      knownSafeFloorSequence: latestAppliedSequence,
    );
    final result = Map<String, int>.from(rawResult);
    if (removedStaleQueue > 0) {
      result['removedQueue'] =
          (result['removedQueue'] ?? 0) + removedStaleQueue;
      result['remainingQueue'] = _syncQueue.length;
      result['pendingQueue'] = pendingSyncQueue.length;
      result['pendingChanges'] = pendingSyncChanges.length;
    }
    debugPrint(
      _syncHistoryCompactionLogLine(
        'AFTER_CLIENT_AUTO_COMPACT_SYNC_HISTORY',
        result,
      ),
    );
    return result;
  }

int _removeStaleClientSyncedQueueRows() {
    if (!appIdentity.isClient || _syncQueue.isEmpty || _syncChanges.isEmpty) {
      return 0;
    }
    final changesById = {for (final change in _syncChanges) change.id: change};
    final beforeQueue = _syncQueue.length;
    _syncQueue.removeWhere((item) {
      final change = changesById[item.changeId];
      if (change == null) return false;
      // A Client may keep old draft queue rows as pending/failed after the Host
      // has already accepted the draft and the local SyncChange is marked
      // synced. Those rows are stale bookkeeping, not real pending work. If we
      // leave them in the queue, client compaction is skipped forever and
      // sequence=0 synced draft changes keep bloating the local database.
      return change.isSynced && change.sequence <= 0;
    });
    return beforeQueue - _syncQueue.length;
  }

Future<Map<String, int>> _compactSyncedSyncHistory({
    required int keepRecentSyncedChanges,
    required bool requireSafeFloorSequence,
    int? knownSafeFloorSequence,
  }) async {
    final beforeChanges = _syncChanges.length;
    final beforeQueue = _syncQueue.length;

    final changesById = {for (final change in _syncChanges) change.id: change};
    final pendingChangeIds = _syncQueue
        .where((item) {
          if (item.status == 'synced') return false;
          final change = changesById[item.changeId];
          // Client-side compaction should not protect stale queue rows tied to
          // local draft changes that are already synced. Those rows may still
          // be marked pending/failed after a network abort, but they no longer
          // represent real pending work.
          if (!requireSafeFloorSequence &&
              change != null &&
              change.isSynced &&
              change.sequence <= 0) {
            return false;
          }
          return true;
        })
        .map((item) => item.changeId)
        .toSet();

    final safeFloorSequence =
        knownSafeFloorSequence ?? _minimumActivePeerAckSequence();
    if (requireSafeFloorSequence && safeFloorSequence <= 0) {
      return _syncHistoryCompactionResult(
        beforeChanges: beforeChanges,
        beforeQueue: beforeQueue,
        safeFloorSequence: safeFloorSequence,
        skipped: 1,
      );
    }

    final isClientLocalCompaction = !requireSafeFloorSequence;

    _syncQueue.removeWhere((item) {
      if (item.status != 'synced') return false;
      // Client-side maintenance may safely remove every already-synced queue
      // row, including local draft commands that never received an
      // authoritative sequence locally (sequence=0). Keeping those rows was the
      // reason Client databases kept thousands of stale SyncQueue entries.
      if (isClientLocalCompaction) return true;

      SyncChange? change;
      for (final candidate in _syncChanges) {
        if (candidate.id == item.changeId) {
          change = candidate;
          break;
        }
      }
      if (change == null) return true;
      if (change.sequence <= 0) return false;
      return change.sequence <= safeFloorSequence;
    });

    final syncedChanges = _syncChanges.where((item) {
      if (!item.isSynced) return false;
      if (pendingChangeIds.contains(item.id)) return false;
      if (item.sequence <= 0) return false;
      return item.sequence <= safeFloorSequence;
    }).toList()
      ..sort((a, b) => b.sequence.compareTo(a.sequence));
    final keepSyncedIds = syncedChanges
        .take(keepRecentSyncedChanges)
        .map((item) => item.id)
        .toSet();

    _syncChanges.removeWhere((item) {
      if (!item.isSynced) return false;
      if (pendingChangeIds.contains(item.id)) return false;
      // Client-created draft changes commonly remain at sequence=0 after the
      // Host accepts and republishes them as authoritative events. Once they
      // are synced and no pending queue references them, they are stale local
      // bookkeeping and must be removed on Clients.
      if (item.sequence <= 0) return isClientLocalCompaction;
      if (item.sequence > safeFloorSequence) return false;
      return !keepSyncedIds.contains(item.id);
    });

    final result = _syncHistoryCompactionResult(
      beforeChanges: beforeChanges,
      beforeQueue: beforeQueue,
      safeFloorSequence: safeFloorSequence,
    );
    if ((result['removedChanges'] ?? 0) > 0 ||
        (result['removedQueue'] ?? 0) > 0) {
      await _saveSyncStateOnly();
      notifyListeners();
    }
    return result;
  }

Future<void> applyRemoteSyncChanges(
    List<SyncChange> incoming, {
    bool markAppliedAsSynced = false,
    bool mirrorToDirect = false,
  }) async {
    final existingIds = _syncChanges.map((item) => item.id).toSet();
    final existingEventIds = _syncChanges
        .map((item) => _syncMetaString(item, 'eventId'))
        .where((item) => item.isNotEmpty)
        .toSet();
    final acceptedSourceCommandIds = <String>{
      ..._syncChanges
          .map((item) => _syncMetaString(item, 'sourceCommandId'))
          .where((item) => item.isNotEmpty),
      ..._syncChanges
          .map((item) => _syncMetaString(item, 'requestId'))
          .where((item) => item.isNotEmpty),
    };
    final lastAppliedSequence = SyncDeviceStateStore.load(
      appIdentity,
    ).lastAppliedSequence;
    final currentEpoch = appIdentity.storeEpoch;
    final sorted = [...incoming]..sort((a, b) {
        final epochCompare = a.storeEpoch.compareTo(b.storeEpoch);
        if (epochCompare != 0) return epochCompare;
        if (a.sequence != 0 || b.sequence != 0) {
          return a.sequence.compareTo(b.sequence);
        }
        return a.createdAt.compareTo(b.createdAt);
      });
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] applyRemote:start incoming=${incoming.length} '
      'sorted=${sorted.length} markApplied=$markAppliedAsSynced '
      'mirrorToDirect=$mirrorToDirect lastAppliedSequence=$lastAppliedSequence '
      'currentEpoch=$currentEpoch',
    );
    for (final change in sorted.take(40)) {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] applyRemote:item ${SyncDiagnosticsLog.summarizeChange(change)}',
      );
    }
    var changed = false;
    var saveAllBusinessData = false;
    var storeProfileChanged = false;
    var productsChanged = false;
    var customersChanged = false;
    var salesChanged = false;
    var saleQuotationsChanged = false;
    var deliveryNotesChanged = false;
    var billsOfMaterialsChanged = false;
    var manufacturingOrdersChanged = false;
    var suppliersChanged = false;
    var supplierProductPricesChanged = false;
    var categoriesChanged = false;
    var brandsChanged = false;
    var unitsChanged = false;
    var expensesChanged = false;
    var purchasesChanged = false;
    var stockMovementsChanged = false;
    var warehousesChanged = false;
    var accountTransactionsChanged = false;
    var rolesUsersChanged = false;
    var invoiceCounterChanged = false;
    var purchaseCounterChanged = false;

    void markEntityDirty(SyncChange change) {
      switch (change.entityType) {
        case 'system':
          if (change.operation == 'reset_store_data' ||
              change.operation == 'restore_snapshot') {
            saveAllBusinessData = true;
            rolesUsersChanged = true;
          }
          break;
        case 'store_profile':
          storeProfileChanged = true;
          break;
        case 'app_identity':
          saveAllBusinessData = true;
          break;
        case 'role':
        case 'user':
          rolesUsersChanged = true;
          break;
        case 'product':
          productsChanged = true;
          break;
        case 'customer':
          customersChanged = true;
          break;
        case 'sale':
          salesChanged = true;
          invoiceCounterChanged = true;
          break;
        case 'sale_quotation':
          saleQuotationsChanged = true;
          break;
        case 'delivery_note':
          deliveryNotesChanged = true;
          break;
        case 'bill_of_materials':
          billsOfMaterialsChanged = true;
          break;
        case 'manufacturing_order':
          manufacturingOrdersChanged = true;
          break;
        case 'supplier':
          suppliersChanged = true;
          break;
        case 'supplier_product_price':
          supplierProductPricesChanged = true;
          break;
        case 'category':
          categoriesChanged = true;
          break;
        case 'brand':
          brandsChanged = true;
          break;
        case 'unit':
          unitsChanged = true;
          break;
        case 'expense':
          expensesChanged = true;
          break;
        case 'purchase':
          purchasesChanged = true;
          purchaseCounterChanged = true;
          break;
        case 'stock_movement':
          stockMovementsChanged = true;
          productsChanged = true;
          break;
        case 'warehouse':
          warehousesChanged = true;
          break;
        case 'account_transaction':
          accountTransactionsChanged = true;
          break;
      }
    }

    for (final change in sorted) {
      if (_isReplayOrDuplicateSyncEvent(
        change,
        existingEnvelopeIds: existingIds,
        existingEventIds: existingEventIds,
        acceptedSourceCommandIds: acceptedSourceCommandIds,
        lastAppliedSequence: lastAppliedSequence,
      )) {
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] applyRemote:skipDuplicate '
          '${SyncDiagnosticsLog.summarizeChange(change)} '
          'lastAppliedSequence=$lastAppliedSequence',
        );
        continue;
      }
      final incomingEpoch = change.storeEpoch;
      if (incomingEpoch < currentEpoch &&
          !(change.entityType == 'system' &&
              change.operation == 'reset_store_data')) {
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] applyRemote:skipEpoch '
          '${SyncDiagnosticsLog.summarizeChange(change)} '
          'incomingEpoch=$incomingEpoch currentEpoch=$currentEpoch',
        );
        continue;
      }
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] applyRemote:before '
        '${SyncDiagnosticsLog.summarizeChange(change)} '
        'localDevice=$_deviceId countBeforeCustomers=${_customers.length} '
        'existsBefore=${_customers.any((item) => item.id == change.entityId)}',
      );
      await _applySyncChangePayload(change);
      if (change.entityType == 'customer') {
        final storedIndex =
            _customers.indexWhere((item) => item.id == change.entityId);
        final stored = storedIndex == -1 ? null : _customers[storedIndex];
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] applyRemote:after entity=customer '
          'id=${change.entityId} name=${stored?.name} '
          'deletedAt=${stored?.deletedAt?.toIso8601String()} '
          'syncStatus=${stored?.syncStatus} version=${stored?.version} '
          'countAfter=${_customers.length}',
        );
      }
      _rememberRemoteSqliteBusinessRows(change);
      markEntityDirty(change);
      // Host-authority sync note:
      // Any draft accepted by the Host must become a new authoritative Host
      // event, even in LAN-only mode. v12 only restamped events that were also
      // mirrored to Direct; pure Local/LAN installs kept the original Client
      // timestamp, so other Clients could miss the delta behind their cursor.
      // Restamping on every Host acceptance makes Local sync timing stable.
      final acceptedAt = DateTime.now();
      final shouldRestampAsHostAuthority =
          appIdentity.isHost && change.deviceId != _deviceId;
      final incomingMeta = _syncV2MetaOf(change);
      final requestId = (incomingMeta['requestId'] ?? change.id).toString();
      final authoritativeEventId = shouldRestampAsHostAuthority
          ? _newSyncEnvelopeId(acceptedAt, 'evt')
          : (_syncMetaString(change, 'eventId').isNotEmpty
              ? _syncMetaString(change, 'eventId')
              : change.id);
      final authoritativePayload = shouldRestampAsHostAuthority
          ? <String, dynamic>{
              ...change.payload,
              '_syncV2': <String, dynamic>{
                ...incomingMeta,
                'kind': 'authoritativeEvent',
                'requestId': requestId,
                'eventId': authoritativeEventId,
                'acceptedByHostDeviceId': _deviceId,
                'acceptedAt': acceptedAt.toIso8601String(),
                'sourceCommandId': requestId,
                'sourceCommandDeviceId': change.deviceId,
              },
            }
          : change.payload;
      final authoritativeChange = shouldRestampAsHostAuthority
          ? change.copyWith(
              id: authoritativeEventId,
              createdAt: acceptedAt,
              deviceId: _deviceId,
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              payload: authoritativePayload,
              storeEpoch: appIdentity.storeEpoch,
              sequence: _nextSyncSequence(),
            )
          : change;
      final storedChange = markAppliedAsSynced
          ? authoritativeChange.copyWith(isSynced: true, syncedAt: acceptedAt)
          : authoritativeChange.copyWith(isSynced: false, syncedAt: null);
      _syncChanges.add(storedChange);
      _sqliteDirtySyncChanges.add(storedChange);
      existingIds.add(change.id);
      existingIds.add(storedChange.id);
      final storedEventId = _syncMetaString(storedChange, 'eventId');
      if (storedEventId.isNotEmpty) existingEventIds.add(storedEventId);
      final storedSourceCommandId = _syncMetaString(
        storedChange,
        'sourceCommandId',
      );
      if (storedSourceCommandId.isNotEmpty) {
        acceptedSourceCommandIds.add(storedSourceCommandId);
      }
      final storedRequestId = _syncMetaString(storedChange, 'requestId');
      if (storedRequestId.isNotEmpty) {
        acceptedSourceCommandIds.add(storedRequestId);
      }
      changed = true;
    }
    if (changed) {
      _ensureCatalogDefaults();
      _normalizeCustomers();
      if (saveAllBusinessData) {
        SyncDiagnosticsLog.add(
            '[SYNC_TRACE] applyRemote:saveAll customersChanged=$customersChanged');
        await _saveAll();
      } else {
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] applyRemote:saveDirty customersChanged=$customersChanged '
          'productsChanged=$productsChanged sync=true',
        );
        await Future.wait([
          if (rolesUsersChanged) _saveRolesAndUsers(),
          _saveDirty(
            products: productsChanged,
            customers: customersChanged,
            sales: salesChanged,
            saleQuotations: saleQuotationsChanged,
            deliveryNotes: deliveryNotesChanged,
            billsOfMaterials: billsOfMaterialsChanged,
            manufacturingOrders: manufacturingOrdersChanged,
            suppliers: suppliersChanged,
            supplierProductPrices: supplierProductPricesChanged,
            expenses: expensesChanged,
            purchases: purchasesChanged,
            stockMovements: stockMovementsChanged,
            warehouses: warehousesChanged,
            accountTransactions: accountTransactionsChanged,
            storeProfile: storeProfileChanged,
            categories: categoriesChanged,
            brands: brandsChanged,
            units: unitsChanged,
            invoiceCounter: invoiceCounterChanged,
            purchaseCounter: purchaseCounterChanged,
            sync: true,
          ),
        ]);
      }
      _touchDataRevisions(
        products: productsChanged,
        customers: customersChanged,
        sales: salesChanged,
        deliveryNotes: deliveryNotesChanged,
        storeProfile: storeProfileChanged,
      );
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] applyRemote:notify changed=true customers=${_customers.length} '
        'visibleCustomers=${customers.length} '
        'customerNames=${customers.map((item) => item.name).join(',')}',
      );
      notifyListeners();
    } else {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] applyRemote:done changed=false customers=${_customers.length} '
        'visibleCustomers=${customers.length}',
      );
    }
  }

void _addDuplicateConflicts<T>(
    List<DataConflict> output,
    Iterable<T> items,
    String entityType,
    String keyName,
    String Function(T item) keyOf,
    String Function(T item) idOf, {
    bool blocking = false,
    String message = '',
  }) {
    final groups = <String, List<T>>{};
    final display = <String, String>{};
    for (final item in items) {
      final raw = keyOf(item).trim();
      final key = _conflictKey(raw);
      if (key.isEmpty) continue;
      groups.putIfAbsent(key, () => <T>[]).add(item);
      display.putIfAbsent(key, () => raw);
    }
    groups.forEach((key, grouped) {
      final ids = grouped
          .map(idOf)
          .where((id) => id.trim().isNotEmpty)
          .toSet()
          .toList();
      if (ids.length > 1) {
        output.add(
          DataConflict(
            entityType: entityType,
            keyName: keyName,
            keyValue: display[key] ?? key,
            recordIds: ids,
            blocking: blocking,
            message: message,
          ),
        );
      }
    });
  }

List<DataConflict> _detectDataConflicts() {
    final result = <DataConflict>[];
    _addDuplicateConflicts<Customer>(
      result,
      _customers.where(
        (item) => !item.isDeleted && item.id != AppStore.walkInCustomerId,
      ),
      'Customers',
      'name',
      (item) => item.name,
      (item) => item.id,
      message:
          'Created offline on more than one device. Keep both records and review manually.',
    );
    _addDuplicateConflicts<Supplier>(
      result,
      _suppliers.where((item) => !item.isDeleted),
      'Suppliers',
      'name',
      (item) => item.name,
      (item) => item.id,
      message:
          'Supplier names are duplicated after sync. Review manually; records were not merged.',
    );
    _addDuplicateConflicts<Product>(
      result,
      _products.where((item) => !item.isDeleted),
      'Products',
      'code',
      (item) => item.code,
      (item) => item.id,
      blocking: true,
      message:
          'Duplicate product codes can affect search, sales, stock, and reports.',
    );
    _addDuplicateConflicts<Product>(
      result,
      _products.where(
        (item) => !item.isDeleted && item.barcode.trim().isNotEmpty,
      ),
      'Products',
      'barcode',
      (item) => item.barcode,
      (item) => item.id,
      blocking: true,
      message:
          'Barcode is ambiguous. Avoid barcode sales until one product barcode is changed.',
    );
    _addDuplicateConflicts<CatalogItem>(
      result,
      _categories.where((item) => !item.isDeleted),
      'Categories',
      'English name',
      (item) => item.nameEn,
      (item) => item.id,
    );
    _addDuplicateConflicts<CatalogItem>(
      result,
      _categories.where((item) => !item.isDeleted),
      'Categories',
      'Arabic name',
      (item) => item.nameAr,
      (item) => item.id,
    );
    _addDuplicateConflicts<CatalogItem>(
      result,
      _brands.where((item) => !item.isDeleted),
      'Brands',
      'English name',
      (item) => item.nameEn,
      (item) => item.id,
    );
    _addDuplicateConflicts<CatalogItem>(
      result,
      _brands.where((item) => !item.isDeleted),
      'Brands',
      'Arabic name',
      (item) => item.nameAr,
      (item) => item.id,
    );
    _addDuplicateConflicts<CatalogItem>(
      result,
      _units.where((item) => !item.isDeleted),
      'Units',
      'English name',
      (item) => item.nameEn,
      (item) => item.id,
    );
    _addDuplicateConflicts<CatalogItem>(
      result,
      _units.where((item) => !item.isDeleted),
      'Units',
      'Arabic name',
      (item) => item.nameAr,
      (item) => item.id,
    );
    _addDuplicateConflicts<AppUser>(
      result,
      _users,
      'Users',
      'username',
      (item) => item.username,
      (item) => item.id,
      blocking: true,
      message:
          'Duplicate usernames are a security conflict. Rename or disable one user before relying on login.',
    );
    _addDuplicateConflicts<UserRole>(
      result,
      _roles,
      'Roles',
      'name',
      (item) => item.name,
      (item) => item.id,
      blocking: true,
      message: 'Duplicate role names can confuse permissions. Rename one role.',
    );
    _addDuplicateConflicts<SupplierProductPrice>(
      result,
      _supplierProductPrices.where((item) => !item.isDeleted),
      'Supplier Product Prices',
      'product + supplier',
      (item) => '${item.productId} / ${item.supplierId}',
      (item) => item.id,
      blocking: true,
      message:
          'A product should have only one active price per supplier. Merge or delete the duplicate record.',
    );
    _addDuplicateConflicts<Sale>(
      result,
      _sales.where((item) => !item.isDeleted),
      'Sales',
      'invoice number',
      (item) => item.invoiceNo,
      (item) => item.id,
      blocking: true,
      message:
          'Duplicate invoice numbers must be reviewed before printing/exporting final reports.',
    );
    return result;
  }

bool _remoteWins(dynamic incoming, dynamic local) {
    final incomingVersion = _readVersion(incoming);
    final localVersion = _readVersion(local);
    if (incomingVersion != localVersion) return incomingVersion > localVersion;

    final incomingUpdatedAt = _readUpdatedAt(incoming);
    final localUpdatedAt = _readUpdatedAt(local);
    if (incomingUpdatedAt.isAfter(localUpdatedAt)) return true;
    if (incomingUpdatedAt.isBefore(localUpdatedAt)) return false;

    // Deterministic tie-breaker for same-version/same-time writes. This avoids
    // oscillation between devices while keeping the Host-authoritative event
    // stream stable.
    try {
      final incomingDevice = (incoming.lastModifiedByDeviceId as String?) ??
          (incoming.deviceId as String?) ??
          '';
      final localDevice = (local.lastModifiedByDeviceId as String?) ??
          (local.deviceId as String?) ??
          '';
      return incomingDevice.compareTo(localDevice) >= 0;
    } catch (_) {
      return true;
    }
  }

void _upsertByUpdatedAt<T>(
    List<T> list,
    T incoming,
    String Function(T item) idOf,
  ) {
    final index = list.indexWhere((item) => idOf(item) == idOf(incoming));
    if (index == -1) {
      list.add(incoming);
    } else if (_remoteWins(incoming, list[index])) {
      list[index] = incoming;
    }
  }

void _applySupplierProductPriceFromSync(SupplierProductPrice incoming) {
    final normalized = incoming.copyWith(syncStatus: 'synced');
    if (!normalized.isDeleted) {
      for (var i = 0; i < _supplierProductPrices.length; i++) {
        final item = _supplierProductPrices[i];
        if (item.isDeleted || item.id == normalized.id) continue;
        final sameProductSupplier = item.productId == normalized.productId &&
            item.supplierId == normalized.supplierId;
        if (!sameProductSupplier) continue;
        if (_remoteWins(normalized, item)) {
          _supplierProductPrices[i] = item.copyWith(
            deletedAt: normalized.updatedAt,
            updatedAt: normalized.updatedAt,
            syncStatus: 'synced',
            notes: [
              item.notes,
              'Merged duplicate supplier price from sync',
            ].where((part) => part.trim().isNotEmpty).join(' — '),
          );
        } else {
          return;
        }
      }
    }
    if (normalized.isPreferred && !normalized.isDeleted) {
      for (var i = 0; i < _supplierProductPrices.length; i++) {
        final item = _supplierProductPrices[i];
        if (!item.isDeleted &&
            item.productId == normalized.productId &&
            item.id != normalized.id &&
            item.isPreferred) {
          _supplierProductPrices[i] = item.copyWith(
            isPreferred: false,
            updatedAt: normalized.updatedAt.isAfter(item.updatedAt)
                ? normalized.updatedAt
                : item.updatedAt,
            syncStatus: 'synced',
          );
        }
      }
    }
    _upsertByUpdatedAt<SupplierProductPrice>(
      _supplierProductPrices,
      normalized,
      (item) => item.id,
    );
  }

Future<void> _applySyncChangePayload(SyncChange change) async {
    final p = change.payload;
    switch (change.entityType) {
      case 'system':
        if (change.operation == 'reset_store_data') {
          _syncChanges.clear();
          _syncQueue.clear();
          final nextEpoch = change.storeEpoch > appIdentity.storeEpoch
              ? change.storeEpoch
              : appIdentity.storeEpoch + 1;
          _appIdentity = appIdentity.copyWith(
            storeEpoch: nextEpoch,
            updatedAt: DateTime.now(),
          );
          await LocalDatabaseService.setString(
            AppStore._appIdentityKey,
            jsonEncode(_appIdentity!.toJson()),
          );
          _resetBusinessDataInMemory(
            keepStoreProfile: p['keepStoreProfile'] as bool? ?? true,
          );
        } else if (change.operation == 'restore_snapshot') {
          // A direct/LAN bootstrap snapshot contains the Host identity. Never let
          // a Client import that identity or it may start behaving as the Host.
          await _replaceFromBackupMap(
            p,
            preserveLocalIdentityForLanClient: true,
          );
        } else if (change.operation == 'request_snapshot') {
          // Snapshot requests are handled by the selected LAN/Direct
          // transport. The retired Direct relay is intentionally ignored.
        }
        break;
      case 'host_transfer':
        if (change.operation == 'request') {
          // Keep the latest transfer request visible to the current Host UI.
          if (appIdentity.isHost) {
            await LocalDatabaseService.setString(
              AppStore._hostTransferRequestKey,
              jsonEncode(p),
            );
          }
        } else if (change.operation == 'approve') {
          final approvedDeviceId =
              p['approvedDeviceId']?.toString().trim() ?? '';
          if (approvedDeviceId == _deviceId) {
            await LocalDatabaseService.setString(
              AppStore._hostTransferApprovedDeviceKey,
              approvedDeviceId,
            );
          }
        } else if (change.operation == 'new_host_activated' ||
            change.operation == 'HOST_CHANGED' ||
            change.operation == 'notify_clients_host_changed') {
          final newHostDeviceId = p['newHostDeviceId']?.toString().trim() ?? '';
          final oldHostDeviceId = p['oldHostDeviceId']?.toString().trim() ?? '';
          final shouldSwitchToNewHost = newHostDeviceId.isNotEmpty &&
              newHostDeviceId != _deviceId &&
              (appIdentity.isClient ||
                  (appIdentity.isHost && oldHostDeviceId == _deviceId));
          if (shouldSwitchToNewHost) {
            await _forceApplyRoleFromTransfer(
              appIdentity.copyWith(
                deviceRole: DeviceRole.client,
                hostDeviceId: newHostDeviceId,
                updatedAt: DateTime.now(),
              ),
            );
            await _storeHostTransferNotification({
              'type': 'host_changed',
              'newHostDeviceId': newHostDeviceId,
              'oldHostDeviceId': oldHostDeviceId,
              'storeId': p['storeId']?.toString() ?? appIdentity.storeId,
              'branchId': p['branchId']?.toString() ?? appIdentity.branchId,
              'receivedAt': DateTime.now().toIso8601String(),
            });
          }
        }
        break;
      case 'store_profile':
        _storeProfile = StoreProfile.fromJson(p);
        AccountingService.configureMoneyPolicy(_storeProfile);
        break;
      case 'app_identity':
        if (change.entityId == _deviceId) {
          final incomingIdentity = _normalizedLocalIdentity(
            AppIdentity.fromJson(p),
          );
          _assertSafeRoleTransition(
            incomingIdentity,
            source: 'remote app identity change',
          );
          _appIdentity = incomingIdentity;
          await LocalDatabaseService.setString(
            AppStore._appIdentityKey,
            jsonEncode(_appIdentity!.toJson()),
          );
        }
        break;
      case 'role':
        if (change.operation == 'delete') {
          _roles.removeWhere(
            (item) => item.id == change.entityId && !item.isSystem,
          );
        } else {
          _upsertByUpdatedAt<UserRole>(
            _roles,
            UserRole.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'user':
        if (change.operation == 'delete') {
          _users.removeWhere(
            (item) => item.id == change.entityId && !item.isSystem,
          );
          if (_activeUser?.id == change.entityId) _activeUser = null;
        } else {
          final incoming = AppUser.fromJson(p);
          _upsertByUpdatedAt<AppUser>(_users, incoming, (item) => item.id);
          if (_activeUser?.id == incoming.id) _activeUser = incoming;
        }
        break;
      case 'product':
        if (change.operation == 'delete' && p.isEmpty) {
          _products.removeWhere((item) => item.id == change.entityId);
        } else {
          final incomingMetadata = Product.fromJson(p);
          final existing = _findProductById(incomingMetadata.id);
          final inventoryProjection = LocalDatabaseService.isSqliteAuthoritative
              ? await totalWarehouseStockFromSqlite(incomingMetadata.id)
              : (existing?.stock ?? 0.0);
          final incoming =
              incomingMetadata.copyWith(stock: inventoryProjection);
          _upsertByUpdatedAt<Product>(_products, incoming, (item) => item.id);
        }
        _rebuildProductIndexes();
        break;
      case 'customer':
        if (change.operation == 'delete' && p.isEmpty) {
          SyncDiagnosticsLog.add(
            '[SYNC_TRACE] applyPayload:customer deleteEmpty id=${change.entityId} '
            'before=${_customers.length}',
          );
          _customers.removeWhere((item) => item.id == change.entityId);
        } else {
          final incoming = Customer.fromJson(p);
          final beforeIndex =
              _customers.indexWhere((item) => item.id == incoming.id);
          final before = beforeIndex == -1 ? null : _customers[beforeIndex];
          SyncDiagnosticsLog.add(
            '[SYNC_TRACE] applyPayload:customer upsert id=${incoming.id} '
            'name=${incoming.name} op=${change.operation} seq=${change.sequence} '
            'incomingUpdatedAt=${incoming.updatedAt.toIso8601String()} '
            'incomingDeletedAt=${incoming.deletedAt?.toIso8601String()} '
            'incomingStatus=${incoming.syncStatus} incomingVersion=${incoming.version} '
            'beforeExists=${before != null} '
            'beforeUpdatedAt=${before?.updatedAt.toIso8601String()} '
            'beforeDeletedAt=${before?.deletedAt?.toIso8601String()} '
            'beforeStatus=${before?.syncStatus} beforeVersion=${before?.version}',
          );
          _upsertByUpdatedAt<Customer>(
            _customers,
            incoming,
            (item) => item.id,
          );
          final afterIndex =
              _customers.indexWhere((item) => item.id == incoming.id);
          final after = afterIndex == -1 ? null : _customers[afterIndex];
          SyncDiagnosticsLog.add(
            '[SYNC_TRACE] applyPayload:customer result id=${incoming.id} '
            'afterExists=${after != null} afterName=${after?.name} '
            'afterUpdatedAt=${after?.updatedAt.toIso8601String()} '
            'afterDeletedAt=${after?.deletedAt?.toIso8601String()} '
            'afterStatus=${after?.syncStatus} afterVersion=${after?.version} '
            'total=${_customers.length}',
          );
        }
        _rebuildCustomerIndexes();
        break;
      case 'supplier':
        if (change.operation == 'delete' && p.isEmpty) {
          _suppliers.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<Supplier>(
            _suppliers,
            Supplier.fromJson(p),
            (item) => item.id,
          );
        }
        _rebuildSupplierIndexes();
        break;
      case 'supplier_product_price':
        if (change.operation == 'delete' && p.isEmpty) {
          _supplierProductPrices.removeWhere(
            (item) => item.id == change.entityId,
          );
        } else {
          _applySupplierProductPriceFromSync(SupplierProductPrice.fromJson(p));
        }
        break;
      case 'expense':
        if (change.operation == 'delete' && p.isEmpty) {
          final expenseIndex = _expenseIndexForId(change.entityId);
          if (expenseIndex != -1) {
            _removeExpenseAtIndex(expenseIndex);
            _touchExpensesData();
          }
        } else {
          final incoming = Expense.fromJson(p);
          _upsertByUpdatedAt<Expense>(
            _expenses,
            incoming,
            (item) => item.id,
          );
          _rebuildExpenseIndexes();
          _touchExpensesData();
        }
        break;
      case 'category':
        if (change.operation == 'delete' && p.isEmpty) {
          _categories.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<CatalogItem>(
            _categories,
            CatalogItem.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'brand':
        if (change.operation == 'delete' && p.isEmpty) {
          _brands.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<CatalogItem>(
            _brands,
            CatalogItem.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'unit':
        if (change.operation == 'delete' && p.isEmpty) {
          _units.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<CatalogItem>(
            _units,
            CatalogItem.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'sale':
        if (change.operation == 'delete' && p.isEmpty) {
          _sales.removeWhere((item) => item.id == change.entityId);
        } else {
          final incomingSale = Sale.fromJson(p);
          _upsertByUpdatedAt<Sale>(_sales, incomingSale, (item) => item.id);
          final invoiceNumber = _invoiceSequenceFromNo(incomingSale.invoiceNo);
          if (invoiceNumber > _invoiceCounter) _invoiceCounter = invoiceNumber;
        }
        break;
      case 'sale_quotation':
        if (change.operation == 'delete' && p.isEmpty) {
          _saleQuotations.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<SaleQuotation>(
            _saleQuotations,
            SaleQuotation.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'delivery_note':
        if (change.operation == 'delete' && p.isEmpty) {
          _deliveryNotes.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<DeliveryNote>(
            _deliveryNotes,
            DeliveryNote.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'bill_of_materials':
        if (change.operation == 'delete' && p.isEmpty) {
          _billsOfMaterials.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<BillOfMaterials>(
            _billsOfMaterials,
            BillOfMaterials.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'manufacturing_order':
        if (change.operation == 'delete' && p.isEmpty) {
          _manufacturingOrders.removeWhere(
            (item) => item.id == change.entityId,
          );
        } else {
          _upsertByUpdatedAt<ManufacturingOrder>(
            _manufacturingOrders,
            ManufacturingOrder.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'purchase':
        if (change.operation == 'delete' && p.isEmpty) {
          final purchaseIndex = _purchaseIndexForId(change.entityId);
          if (purchaseIndex != -1) {
            _removePurchaseAtIndex(purchaseIndex);
            _touchPurchasesData();
          }
        } else {
          final incomingPurchase = Purchase.fromJson(p);
          _upsertByUpdatedAt<Purchase>(
            _purchases,
            incomingPurchase,
            (item) => item.id,
          );
          _rebuildPurchaseIndexes();
          _touchPurchasesData();
        }
        break;
      case 'account_transaction':
        if (change.operation == 'delete' && p.isEmpty) {
          final transactionIndex =
              _accountTransactionIndexForId(change.entityId);
          if (transactionIndex != -1) {
            final previous = _accountTransactions[transactionIndex];
            _removeAccountTransactionAtIndex(transactionIndex);
            _replaceAccountTransactionInLedgerCache(
              previous: previous,
              current: previous.copyWith(deletedAt: DateTime.now()),
            );
          }
          _invalidateAccountLedgerCache();
        } else {
          final incoming = AccountTransaction.fromJson(p);
          final previousIndex = _accountTransactionIndexForId(incoming.id);
          final previous =
              previousIndex == -1 ? null : _accountTransactions[previousIndex];
          _upsertByUpdatedAt<AccountTransaction>(
            _accountTransactions,
            incoming,
            (item) => item.id,
          );
          final currentIndex = _accountTransactionIndexForId(incoming.id);
          final current =
              currentIndex == -1 ? null : _accountTransactions[currentIndex];
          if (current != null) {
            _replaceAccountTransactionInLedgerCache(
              previous: previous,
              current: current,
            );
          }
          _rebuildAccountTransactionIndexes();
          _invalidateAccountLedgerCache();
        }
        break;
      case 'stock_movement':
        final movement = StockMovement.fromJson(p);
        if (_stockMovementIndexForId(movement.id) != -1) break;
        if (LocalDatabaseService.isSqliteAuthoritative &&
            movement.batchId.trim().isEmpty &&
            movement.quantity.abs() > 0.000001) {
          final sqliteDb = SqliteMigrationManager.database;
          if (sqliteDb != null) {
            final marker = await sqliteDb.customSelect(
              '''
              SELECT p.name AS product_name
              FROM unified_batch_cutovers uc
              INNER JOIN products p ON p.id = uc.product_id
                AND p.deleted_at = '' AND p.track_stock = 1
              WHERE uc.store_id = ? AND uc.warehouse_id = ?
                AND uc.product_id = ?
                AND datetime(?) >= datetime(uc.cutover_at)
              LIMIT 1
              ''',
              variables: <Variable<Object>>[
                Variable<String>(movement.storeId.trim().isEmpty
                    ? appIdentity.storeId
                    : movement.storeId.trim()),
                Variable<String>(movement.warehouseId),
                Variable<String>(movement.productId),
                Variable<String>(movement.date.toUtc().toIso8601String()),
              ],
            ).getSingleOrNull();
            if (marker != null) {
              final productName =
                  marker.data['product_name']?.toString() ?? movement.productName;
              throw LocalizedDomainException(
                'error_post_cutover_batch_required',
                values: <String, Object?>{'product': productName},
                fallback:
                    'لا يمكن تسجيل حركة مخزون للمنتج $productName بعد تفعيل نظام الدُفعات دون تحديد الدفعة.',
              );
            }
          }
        }
        final productIndex = _productIndexById[movement.productId];
        if (!_storeProfile.allowNegativeStock &&
            productIndex != null &&
            _products[productIndex].trackStock &&
            _products[productIndex].stock + movement.quantity < -0.000001) {
          throw StateError(
            'Remote stock movement would create negative stock while negative stock is disabled.',
          );
        }
        _putStockMovementAtIndex(
          movement.copyWith(syncStatus: 'synced'),
          _stockMovements.length,
        );
        final productId = movement.productId;
        final index = _productIndexById[productId];
        if (index != null) {
          final product = _products[index];
          if (product.trackStock) {
            if (LocalDatabaseService.isSqliteAuthoritative) {
              await rebuildProductStockCache(productId);
            } else if (movement.quantity != 0) {
              final at = movement.date;
              _products[index] = product.copyWith(
                stock: product.stock + movement.quantity,
                cost:
                    movement.type == 'purchase_receive' && movement.unitCost > 0
                        ? movement.unitCost
                        : product.cost,
                usdCost:
                    movement.type == 'purchase_receive' && movement.unitCost > 0
                        ? movement.unitCost
                        : product.usdCost,
                updatedAt:
                    at.isAfter(product.updatedAt) ? at : product.updatedAt,
                syncStatus: 'synced',
              );
            }
          }
        }
        break;
    }
  }

String? _remoteSyncChangeApplyProblem(SyncChange change) {
    if (change.entityType == 'system') return null;

    bool exists<T>(Iterable<T> items, String Function(T item) idOf) =>
        items.any((item) => idOf(item) == change.entityId);
    final deleteWithEmptyPayload =
        change.operation == 'delete' && change.payload.isEmpty;

    switch (change.entityType) {
      case 'store_profile':
        return null;
      case 'app_identity':
        return null;
      case 'role':
        return deleteWithEmptyPayload ||
                exists<UserRole>(_roles, (item) => item.id)
            ? null
            : 'role ${change.entityId} was not stored locally';
      case 'user':
        return deleteWithEmptyPayload ||
                exists<AppUser>(_users, (item) => item.id)
            ? null
            : 'user ${change.entityId} was not stored locally';
      case 'product':
        return deleteWithEmptyPayload ||
                exists<Product>(_products, (item) => item.id)
            ? null
            : 'product ${change.entityId} was not stored locally';
      case 'customer':
        return deleteWithEmptyPayload ||
                exists<Customer>(_customers, (item) => item.id)
            ? null
            : 'customer ${change.entityId} was not stored locally';
      case 'supplier':
        return deleteWithEmptyPayload ||
                exists<Supplier>(_suppliers, (item) => item.id)
            ? null
            : 'supplier ${change.entityId} was not stored locally';
      case 'supplier_product_price':
        return deleteWithEmptyPayload ||
                exists<SupplierProductPrice>(
                  _supplierProductPrices,
                  (item) => item.id,
                )
            ? null
            : 'supplier product price ${change.entityId} was not stored locally';
      case 'expense':
        return deleteWithEmptyPayload ||
                exists<Expense>(_expenses, (item) => item.id)
            ? null
            : 'expense ${change.entityId} was not stored locally';
      case 'category':
        return deleteWithEmptyPayload ||
                exists<CatalogItem>(_categories, (item) => item.id)
            ? null
            : 'category ${change.entityId} was not stored locally';
      case 'brand':
        return deleteWithEmptyPayload ||
                exists<CatalogItem>(_brands, (item) => item.id)
            ? null
            : 'brand ${change.entityId} was not stored locally';
      case 'unit':
        return deleteWithEmptyPayload ||
                exists<CatalogItem>(_units, (item) => item.id)
            ? null
            : 'unit ${change.entityId} was not stored locally';
      case 'sale':
        return deleteWithEmptyPayload || exists<Sale>(_sales, (item) => item.id)
            ? null
            : 'sale ${change.entityId} was not stored locally';
      case 'sale_quotation':
        return deleteWithEmptyPayload ||
                exists<SaleQuotation>(_saleQuotations, (item) => item.id)
            ? null
            : 'sale quotation ${change.entityId} was not stored locally';
      case 'delivery_note':
        return deleteWithEmptyPayload ||
                exists<DeliveryNote>(_deliveryNotes, (item) => item.id)
            ? null
            : 'delivery note ${change.entityId} was not stored locally';
      case 'bill_of_materials':
        return deleteWithEmptyPayload ||
                exists<BillOfMaterials>(_billsOfMaterials, (item) => item.id)
            ? null
            : 'BOM ${change.entityId} was not stored locally';
      case 'manufacturing_order':
        return deleteWithEmptyPayload ||
                exists<ManufacturingOrder>(
                  _manufacturingOrders,
                  (item) => item.id,
                )
            ? null
            : 'manufacturing order ${change.entityId} was not stored locally';
      case 'purchase':
        return deleteWithEmptyPayload ||
                exists<Purchase>(_purchases, (item) => item.id)
            ? null
            : 'purchase ${change.entityId} was not stored locally';
      case 'account_transaction':
        return deleteWithEmptyPayload ||
                exists<AccountTransaction>(
                  _accountTransactions,
                  (item) => item.id,
                )
            ? null
            : 'account transaction ${change.entityId} was not stored locally';
      case 'stock_movement':
        return exists<StockMovement>(_stockMovements, (item) => item.id)
            ? null
            : 'stock movement ${change.entityId} was not stored locally';
    }
    return null;
  }

Future<void> assertRemoteSyncChangesApplied(List<SyncChange> changes) async {
    final problems = <String>[];
    for (final change in changes) {
      final problem = _remoteSyncChangeApplyProblem(change);
      if (problem != null) problems.add('${change.id}: $problem');
    }
    if (problems.isNotEmpty) {
      throw StateError(
        'Remote sync apply verification failed: ${problems.take(5).join('; ')}',
      );
    }
  }

Future<void> markSyncChangesSubmittedByIds(Iterable<String> ids) async {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _syncQueue.length; i++) {
      final item = _syncQueue[i];
      if (idSet.contains(item.changeId) &&
          item.status != 'synced' &&
          item.status != 'rejected') {
        _syncQueue[i] = item.copyWith(
          status: 'submitted',
          lastError: '',
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

Future<void> markSyncChangesSyncedByIds(Iterable<String> ids) async {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    final now = DateTime.now();
    final matchedChangeIds = <String>{};
    for (var i = 0; i < _syncChanges.length; i++) {
      final change = _syncChanges[i];
      final matches = idSet.contains(change.id) ||
          idSet.contains(_syncMetaString(change, 'eventId')) ||
          idSet.contains(_syncMetaString(change, 'requestId')) ||
          idSet.contains(_syncMetaString(change, 'sourceCommandId'));
      if (matches) {
        matchedChangeIds.add(change.id);
        _syncChanges[i] = change.copyWith(isSynced: true, syncedAt: now);
      }
    }
    for (var i = 0; i < _syncQueue.length; i++) {
      final item = _syncQueue[i];
      if (idSet.contains(item.changeId) ||
          matchedChangeIds.contains(item.changeId)) {
        _syncQueue[i] = item.copyWith(
          status: 'synced',
          updatedAt: now,
          clearNextRetryAt: true,
        );
      }
    }
    await _saveSyncStateOnly();
    notifyListeners();
  }

Future<void> settleLegacyLanHostQueue() async {
    await ensureSyncDataLoaded();
    if (!appIdentity.isHost || appIdentity.isDirectEnabled) return;
    final ids = _syncQueue
        .where((item) => item.target == 'host' && item.status != 'synced')
        .map((item) => item.changeId)
        .where((changeId) => _syncChanges.any(
              (change) => change.id == changeId && change.deviceId == _deviceId,
            ))
        .toList(growable: false);
    if (ids.isNotEmpty) await markSyncChangesSyncedByIds(ids);
  }

Future<int> settleHostQueueThroughPeerAck() async {
    await ensureSyncDataLoaded();
    if (!appIdentity.isHost || _syncQueue.isEmpty) return 0;

    final safeFloorSequence = _minimumActivePeerAckSequence();
    if (safeFloorSequence <= 0) return 0;

    final changesById = <String, SyncChange>{
      for (final change in _syncChanges) change.id: change,
    };
    final ids = _syncQueue
        .where((item) => item.target == 'host' && item.status != 'synced')
        .map((item) => item.changeId)
        .where((changeId) {
      final change = changesById[changeId];
      return change != null &&
          change.deviceId == _deviceId &&
          change.sequence > 0 &&
          change.sequence <= safeFloorSequence;
    }).toList(growable: false);
    if (ids.isEmpty) return 0;

    await markSyncChangesSyncedByIds(ids);
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] hostQueue:settledThroughPeerAck '
      'count=${ids.length} safeFloorSequence=$safeFloorSequence '
      'remainingPending=${pendingSyncQueue.length}',
    );
    return ids.length;
  }

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
