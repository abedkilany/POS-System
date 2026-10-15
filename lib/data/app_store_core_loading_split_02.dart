part of 'app_store.dart';

extension _AppStoreSplitCoreLoadingPart2 on AppStore {
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
    final warehouseIds = _warehouses
        .where((item) => !item.isDeleted)
        .map((item) => item.id)
        .toList(growable: false);
    _warehouseStockByProductCache.clear();
    for (final product in _products.where((item) => !item.isDeleted)) {
      _warehouseStockByProductCache[product.id] = <String, double>{
        for (final id in warehouseIds) id: 0,
      };
    }

    for (final movement in _stockMovements) {
      final productId = movement.productId.trim();
      if (productId.isEmpty) continue;
      final wid = movement.warehouseId.trim().isEmpty
          ? Warehouse.defaultId
          : movement.warehouseId.trim();
      final result = _warehouseStockByProductCache.putIfAbsent(
        productId,
        () => <String, double>{for (final id in warehouseIds) id: 0},
      );
      result[wid] = (result[wid] ?? 0) + movement.quantity;
    }

    _warehouseStockCacheDirty = false;
  }

  double stockForWarehouse(String productId, String warehouseId) {
    _ensureWarehouseStockCache();
    final wid =
        warehouseId.trim().isEmpty ? Warehouse.defaultId : warehouseId.trim();
    return _warehouseStockByProductCache[productId]?[wid] ?? 0;
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
    for (final product in stockTrackedProducts) {
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

  List<AccountTransaction> get accountTransactions {
    unawaited(ensureAccountTransactionsLoaded());
    return List.unmodifiable(
      _accountTransactions
          .where((item) => !item.isDeleted)
          .toList(growable: false)
          .reversed
          .toList(growable: false),
    );
  }

  void _invalidateAccountLedgerCache() {
    _accountLedgerCacheDirty = true;
  }

  bool _isLedgerTrackedAccountTransaction(AccountTransaction item) {
    if (item.isDeleted) return false;
    final type = item.accountType.trim().toLowerCase();
    if (type != 'customer' && type != 'supplier') return false;
    return item.accountId.trim().isNotEmpty;
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
    _accountBalanceCache.clear();
    _accountTransactionsByAccountCache.clear();
    for (final item in _accountTransactions) {
      if (item.isDeleted) continue;
      final type = item.accountType.trim().toLowerCase();
      if (type != 'customer' && type != 'supplier') continue;
      final accountId = item.accountId.trim();
      if (accountId.isEmpty) continue;
      final key = _accountLedgerKey(type, accountId);
      _accountBalanceCache[key] =
          (_accountBalanceCache[key] ?? 0) + item.signedAmount;
      (_accountTransactionsByAccountCache[key] ??= <AccountTransaction>[]).add(
        item,
      );
    }
    for (final rows in _accountTransactionsByAccountCache.values) {
      rows.sort((a, b) => b.date.compareTo(a.date));
    }
    _accountLedgerCacheDirty = false;
  }

  List<AccountTransaction> accountTransactionsForAccount(
    String accountType,
    String accountId,
  ) {
    _requestLedgerDataLoad();
    _ensureAccountLedgerCache();
    return List.unmodifiable(
      _accountTransactionsByAccountCache[_accountLedgerKey(
            accountType,
            accountId,
          )] ??
          const <AccountTransaction>[],
    );
  }

  double accountBalance(String accountType, String accountId) {
    _requestLedgerDataLoad();
    _ensureAccountLedgerCache();
    return _accountBalanceCache[_accountLedgerKey(accountType, accountId)] ?? 0;
  }

  List<Map<String, dynamic>> databaseRows(String entity) {
    requirePermission(AppPermission.databaseManage);
    switch (entity) {
      case 'products':
        return List.unmodifiable(
          _products
              .where((item) => !item.isDeleted)
              .map((item) => item.toJson()),
        );
      case 'customers':
        return List.unmodifiable(
          _customers
              .where((item) => !item.isDeleted)
              .map((item) => item.toJson()),
        );
      case 'suppliers':
        return List.unmodifiable(
          _suppliers
              .where((item) => !item.isDeleted)
              .map((item) => item.toJson()),
        );
      case 'supplierProductPrices':
        return List.unmodifiable(
          _supplierProductPrices
              .where((item) => !item.isDeleted)
              .map((item) => item.toJson()),
        );
      case 'expenses':
        return List.unmodifiable(
          _expenses
              .where((item) => !item.isDeleted)
              .map((item) => item.toJson()),
        );
      case 'categories':
        return List.unmodifiable(
          _categories
              .where((item) => !item.isDeleted)
              .map((item) => item.toJson()),
        );
      case 'brands':
        return List.unmodifiable(
          _brands.where((item) => !item.isDeleted).map((item) => item.toJson()),
        );
      case 'units':
        return List.unmodifiable(
          _units.where((item) => !item.isDeleted).map((item) => item.toJson()),
        );
    }
    throw ArgumentError('Unsupported database entity: $entity');
  }

  Future<void> saveDatabaseRow(String entity, Map<String, dynamic> json) async {
    requirePermission(AppPermission.databaseManage);
    switch (entity) {
      case 'products':
        await addOrUpdateProduct(Product.fromJson(json));
        return;
      case 'customers':
        await addOrUpdateCustomer(Customer.fromJson(json));
        return;
      case 'suppliers':
        await addOrUpdateSupplier(Supplier.fromJson(json));
        return;
      case 'supplierProductPrices':
        await addOrUpdateSupplierProductPrice(
          SupplierProductPrice.fromJson(json),
        );
        return;
      case 'expenses':
        await addOrUpdateExpense(Expense.fromJson(json));
        return;
      case 'categories':
        await addOrUpdateCategory(CatalogItem.fromJson(json));
        return;
      case 'brands':
        await addOrUpdateBrand(CatalogItem.fromJson(json));
        return;
      case 'units':
        await addOrUpdateUnit(CatalogItem.fromJson(json));
        return;
    }
    throw ArgumentError('Unsupported database entity: $entity');
  }

  Future<void> deleteDatabaseRow(String entity, String id) async {
    requirePermission(AppPermission.databaseManage);
    switch (entity) {
      case 'products':
        await deleteProduct(id);
        return;
      case 'customers':
        await deleteCustomer(id);
        return;
      case 'suppliers':
        await deleteSupplier(id);
        return;
      case 'supplierProductPrices':
        await deleteSupplierProductPrice(id);
        return;
      case 'expenses':
        await deleteExpense(id);
        return;
      case 'categories':
        await _deleteCatalogItem(_categories, 'category', id, categories: true);
        return;
      case 'brands':
        await _deleteCatalogItem(_brands, 'brand', id, brands: true);
        return;
      case 'units':
        await _deleteCatalogItem(_units, 'unit', id, units: true);
        return;
    }
    throw ArgumentError('Unsupported database entity: $entity');
  }

  Future<void> _deleteCatalogItem(
    List<CatalogItem> list,
    String entityType,
    String id, {
    bool categories = false,
    bool brands = false,
    bool units = false,
  }) async {
    requirePermission(AppPermission.catalogManage);
    final index = list.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final now = DateTime.now();
    list[index] = _withSyncMeta<CatalogItem>(
      list[index].copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    _recordSyncChange(
      entityType: entityType,
      entityId: id,
      operation: 'delete',
      payload: list[index].toJson(),
    );
    await _saveDirty(
      categories: categories,
      brands: brands,
      units: units,
      sync: true,
    );
    notifyListeners();
  }

  List<SyncChange> get syncChanges {
    _requestSyncDataLoad();
    return List.unmodifiable(_syncChanges);
  }

  List<SyncQueueItem> get syncQueue {
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
    if (target.isEmpty) return pendingSyncCount;
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
