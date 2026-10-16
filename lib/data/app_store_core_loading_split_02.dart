part of 'app_store.dart';

extension _AppStoreSplitCoreLoadingPart2 on AppStore {
  static const InventoryReadService _inventoryReadService =
      InventoryReadService();
  static const AccountLedgerReadService _accountLedgerReadService =
      AccountLedgerReadService();

  void _ensureSaleQuotationsCache() {
    if (_isDerivedCacheCurrent(_cachedSaleQuotationsGeneration) &&
        _cachedSaleQuotations != null) {
      return;
    }
    _cachedSaleQuotations = UnmodifiableListView(
      _saleQuotations
          .where((item) => !item.isDeleted)
          .toList(growable: false)
          .reversed
          .toList(growable: false),
    );
    _cachedSaleQuotationsGeneration = _derivedListCacheGeneration;
  }

  void _ensureDeliveryNotesCache() {
    if (_isDerivedCacheCurrent(_cachedDeliveryNotesGeneration) &&
        _cachedDeliveryNotes != null) {
      return;
    }
    _cachedDeliveryNotes = UnmodifiableListView(
      _deliveryNotes
          .where((item) => !item.isDeleted)
          .toList(growable: false)
          .reversed
          .toList(growable: false),
    );
    _cachedDeliveryNotesGeneration = _derivedListCacheGeneration;
  }

  void _ensureDeliveryNoteLookupCache() {
    if (_isDerivedCacheCurrent(_cachedDeliveryNoteBySaleIdGeneration) &&
        _cachedDeliveryNoteBySaleId != null) {
      return;
    }
    final bySaleId = <String, DeliveryNote>{};
    for (final note in _deliveryNotes) {
      if (note.isDeleted) continue;
      final saleId = note.saleId.trim();
      if (saleId.isEmpty) continue;
      bySaleId[saleId] = note;
    }
    _cachedDeliveryNoteBySaleId = bySaleId;
    _cachedDeliveryNoteBySaleIdGeneration = _derivedListCacheGeneration;
  }

  void _ensureBillsOfMaterialsCache() {
    if (_isDerivedCacheCurrent(_cachedBillsOfMaterialsGeneration) &&
        _cachedBillsOfMaterials != null) {
      return;
    }
    _cachedBillsOfMaterials = UnmodifiableListView(
      _billsOfMaterials
          .where((item) => !item.isDeleted && item.isActive)
          .toList(growable: false)
          .reversed
          .toList(growable: false),
    );
    _cachedBillsOfMaterialsGeneration = _derivedListCacheGeneration;
  }

  void _ensureManufacturingOrdersCache() {
    if (_isDerivedCacheCurrent(_cachedManufacturingOrdersGeneration) &&
        _cachedManufacturingOrders != null) {
      return;
    }
    _cachedManufacturingOrders = UnmodifiableListView(
      _manufacturingOrders
          .where((item) => !item.isDeleted)
          .toList(growable: false)
          .reversed
          .toList(growable: false),
    );
    _cachedManufacturingOrdersGeneration = _derivedListCacheGeneration;
  }

  void _rebuildInventoryCostLayerLookupCache() {
    _inventoryCostLayerIndexById.clear();
    for (var i = 0; i < _inventoryCostLayers.length; i += 1) {
      final id = _inventoryCostLayers[i].id.trim();
      if (id.isEmpty) continue;
      _inventoryCostLayerIndexById[id] = i;
    }
  }

  void _ensureWarehouseStockCache() {
    if (!_warehouseStockCacheDirty) return;
    _ensureDefaultWarehouse();
    _warehouseStockByProductCache
      ..clear()
      ..addAll(
        _inventoryReadService.warehouseStockBalances(
          products: _products,
          warehouses: _warehouses,
          movements: _stockMovements,
        ),
      );

    _warehouseStockCacheDirty = false;
  }

  double stockForWarehouse(String productId, String warehouseId) {
    _ensureWarehouseStockCache();
    return _inventoryReadService.stockForWarehouse(
      _warehouseStockByProductCache,
      productId: productId,
      warehouseId: warehouseId,
    );
  }

  Future<double> warehouseStockFromSqlite(
    String productId, {
    String warehouseId = '',
  }) async {
    final resolvedWarehouseId =
        warehouseId.trim().isEmpty ? Warehouse.defaultId : warehouseId.trim();
    if (LocalDatabaseService.isSqliteAuthoritative) {
      final db = SqliteMigrationManager.database;
      if (db != null) {
        final rows = await db.customSelect(
          '''
          SELECT COALESCE(SUM(quantity), 0) AS quantity
          FROM warehouse_inventory
          WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
          ''',
          variables: <Variable<Object>>[
            Variable<String>(appIdentity.storeId),
            Variable<String>(resolvedWarehouseId),
            Variable<String>(productId),
          ],
        ).get();
        if (rows.isNotEmpty) {
          return (rows.first.data['quantity'] as num? ?? 0).toDouble();
        }
      }
    }
    return stockForWarehouse(productId, resolvedWarehouseId);
  }

  Future<Map<String, Map<String, double>>>
      warehouseStockBalancesFromSqlite() async {
    if (LocalDatabaseService.isSqliteAuthoritative) {
      final db = SqliteMigrationManager.database;
      if (db != null) {
        final rows = await db.customSelect(
          '''
          SELECT warehouse_id, product_id, quantity
          FROM warehouse_inventory
          WHERE store_id = ? AND ABS(quantity) > 0.0000001
          ORDER BY warehouse_id ASC, product_id ASC
          ''',
          variables: <Variable<Object>>[
            Variable<String>(appIdentity.storeId),
          ],
        ).get();
        final balances = <String, Map<String, double>>{};
        for (final row in rows) {
          final warehouseId =
              (row.data['warehouse_id'] as String? ?? '').trim();
          final productId = (row.data['product_id'] as String? ?? '').trim();
          final quantity = (row.data['quantity'] as num? ?? 0).toDouble();
          if (warehouseId.isEmpty ||
              productId.isEmpty ||
              quantity.abs() <= 0.0000001) {
            continue;
          }
          (balances[warehouseId] ??= <String, double>{})[productId] = quantity;
        }
        return balances;
      }
    }

    final balances = <String, Map<String, double>>{};
    for (final product in _stockTrackedProducts) {
      for (final entry in warehouseStockForProduct(product.id).entries) {
        if (entry.value.abs() <= 0.0000001) continue;
        (balances[entry.key] ??= <String, double>{})[product.id] = entry.value;
      }
    }
    return balances;
  }

  Future<double> totalWarehouseStockFromSqlite(String productId) async {
    if (LocalDatabaseService.isSqliteAuthoritative) {
      final db = SqliteMigrationManager.database;
      if (db != null) {
        final rows = await db.customSelect(
          '''
          SELECT COALESCE(SUM(quantity), 0) AS quantity
          FROM warehouse_inventory
          WHERE store_id = ? AND product_id = ?
          ''',
          variables: <Variable<Object>>[
            Variable<String>(appIdentity.storeId),
            Variable<String>(productId),
          ],
        ).get();
        if (rows.isNotEmpty) {
          return (rows.first.data['quantity'] as num? ?? 0).toDouble();
        }
      }
    }
    final balances = warehouseStockForProduct(productId);
    return balances.values.fold<double>(0, (sum, value) => sum + value);
  }

  Map<String, double> warehouseStockForProduct(String productId) {
    _ensureWarehouseStockCache();
    return Map.unmodifiable(
      _warehouseStockByProductCache[productId] ?? const <String, double>{},
    );
  }

  List<AccountTransaction> get _accountTransactionsReadImpl {
    unawaited(_ensureAccountTransactionsLoaded());
    return _accountLedgerReadService
        .activeTransactionsNewestFirst(_accountTransactions);
  }

  void _invalidateAccountLedgerCache() {
    _accountLedgerCacheDirty = true;
  }

  bool _isLedgerTrackedAccountTransaction(AccountTransaction item) {
    return _accountLedgerReadService.isTracked(item);
  }

  void _removeAccountTransactionFromLedgerCache(AccountTransaction item) {
    if (_accountLedgerCacheDirty || !_isLedgerTrackedAccountTransaction(item)) {
      return;
    }
    final key = _accountLedgerKey(item.accountType, item.accountId);
    final balance = _accountBalanceCache[key];
    if (balance != null) {
      final nextBalance = balance - item.signedAmount;
      if (nextBalance.abs() < 0.000001) {
        _accountBalanceCache.remove(key);
      } else {
        _accountBalanceCache[key] = nextBalance;
      }
    }
    final rows = _accountTransactionsByAccountCache[key];
    if (rows == null) return;
    rows.removeWhere((row) => row.id == item.id);
    if (rows.isEmpty) {
      _accountTransactionsByAccountCache.remove(key);
    }
  }

  void _addAccountTransactionToLedgerCache(AccountTransaction item) {
    if (_accountLedgerCacheDirty || !_isLedgerTrackedAccountTransaction(item)) {
      return;
    }
    final key = _accountLedgerKey(item.accountType, item.accountId);
    _accountBalanceCache[key] =
        (_accountBalanceCache[key] ?? 0) + item.signedAmount;
    final rows =
        _accountTransactionsByAccountCache[key] ??= <AccountTransaction>[];
    rows.removeWhere((row) => row.id == item.id);
    rows.add(item);
    rows.sort((a, b) => b.date.compareTo(a.date));
  }

  void _replaceAccountTransactionInLedgerCache({
    AccountTransaction? previous,
    required AccountTransaction current,
  }) {
    if (_accountLedgerCacheDirty) return;
    if (previous != null) {
      _removeAccountTransactionFromLedgerCache(previous);
    }
    _addAccountTransactionToLedgerCache(current);
  }

  void _ensureAccountLedgerCache() {
    if (!_accountLedgerCacheDirty) return;
    final index = _accountLedgerReadService.buildIndex(_accountTransactions);
    _accountBalanceCache
      ..clear()
      ..addAll(index.balanceByAccount);
    _accountTransactionsByAccountCache
      ..clear()
      ..addAll(index.transactionsByAccount);
    _accountLedgerCacheDirty = false;
  }

  List<AccountTransaction> _accountTransactionsForAccountReadImpl(
    String accountType,
    String accountId,
  ) {
    _requestLedgerDataLoad();
    _ensureAccountLedgerCache();
    return _accountLedgerReadService.transactionsForAccount(
      accountType: accountType,
      accountId: accountId,
      index: _accountTransactionsByAccountCache,
    );
  }

  double _accountBalanceReadImpl(String accountType, String accountId) {
    _requestLedgerDataLoad();
    _ensureAccountLedgerCache();
    return _accountLedgerReadService.accountBalance(
      accountType: accountType,
      accountId: accountId,
      balances: _accountBalanceCache,
    );
  }

  List<SyncChange> get _syncChangesReadImpl {
    _requestSyncDataLoad();
    return List.unmodifiable(_syncChanges);
  }

  List<SyncQueueItem> get _syncQueueReadImpl {
    _requestSyncDataLoad();
    return List.unmodifiable(_syncQueue);
  }

  List<SyncQueueItem> get pendingSyncQueue {
    _requestSyncDataLoad();
    return List.unmodifiable(_syncQueue.where((item) => item.isPending));
  }

  List<SyncChange> get pendingSyncChanges {
    _requestSyncDataLoad();
    return List.unmodifiable(_syncChanges.where((item) => !item.isSynced));
  }

  List<SyncQueueItem> pendingSyncQueueForTarget(
    String target, {
    bool readyOnly = true,
  }) {
    _requestSyncDataLoad();
    final items = _syncQueue.where(
      (item) => item.target == target && item.isPending,
    );
    return List.unmodifiable(
      readyOnly ? items.where((item) => item.isReadyToSend) : items,
    );
  }

  List<SyncChange> pendingSyncChangesForTarget(
    String target, {
    bool readyOnly = true,
  }) {
    _requestSyncDataLoad();
    final queueItems = pendingSyncQueueForTarget(target, readyOnly: readyOnly);
    final ids = queueItems.map((item) => item.changeId).toSet();
    return List.unmodifiable(
      _syncChanges.where(
        (change) => ids.contains(change.id) && !change.isSynced,
      ),
    );
  }

  List<SyncChange> submittedSyncChangesForTarget(String target) {
    _requestSyncDataLoad();
    final ids = _syncQueue
        .where((item) => item.target == target && item.status == 'submitted')
        .map((item) => item.changeId)
        .toSet();
    return List.unmodifiable(
      _syncChanges.where(
        (change) => ids.contains(change.id) && !change.isSynced,
      ),
    );
  }

  int outstandingSyncQueueCountForTarget(String target) {
    _requestSyncDataLoad();
    return _syncQueue
        .where((item) => item.target == target && item.status != 'synced')
        .length;
  }

  String get activeClientSyncTarget {
    if (!appIdentity.isClient) return '';
    final active = appIdentity.activeSyncTransportNormalized;
    if (active == 'lan' || active == 'direct') return 'host';
    return '';
  }

  int get activeClientPendingSyncCount {
    _requestSyncDataLoad();
    final target = activeClientSyncTarget;
    if (target.isEmpty) return _pendingSyncCount;
    return pendingSyncQueueForTarget(target, readyOnly: false).length;
  }

  DateTime? get latestResetSyncAt {
    _requestSyncDataLoad();
    DateTime? latest;
    for (final change in _syncChanges) {
      if (change.entityType == 'system' &&
          change.operation == 'reset_store_data') {
        if (latest == null || change.createdAt.isAfter(latest)) {
          latest = change.createdAt;
        }
      }
    }
    return latest;
  }
}
