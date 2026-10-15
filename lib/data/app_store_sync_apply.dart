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
      _storeProfile = profile.withMergedLogoAssetsFrom(_storeProfile);
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
    final productPriceHistoryRows =
        (decoded['productPriceHistory'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
    await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
      AppStore._productPriceHistoryKey,
      productPriceHistoryRows,
      sortIndices: List<int?>.generate(
        productPriceHistoryRows.length,
        (index) => index,
      ),
    );
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
}
