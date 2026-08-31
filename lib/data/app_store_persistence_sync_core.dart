part of 'app_store.dart';

extension _AppStoreSplitPersistenceSyncCore on AppStore {
void _rebuildPurchaseIndexes() {
    _purchaseIndexById.clear();
    for (var i = 0; i < _purchases.length; i++) {
      final id = _purchases[i].id.trim();
      if (id.isEmpty) continue;
      _purchaseIndexById[id] = i;
    }
  }

Future<Sale?> _saleByIdFromSqlite(String id) {
    return LocalDatabaseService.getSaleFromSqliteById(id);
  }

Future<Purchase?> _purchaseByIdFromSqlite(String id) {
    return LocalDatabaseService.getPurchaseFromSqliteById(id);
  }

Future<Purchase?> reloadPurchaseFromSqlite(String id) async {
    final purchase = await _purchaseByIdFromSqlite(id);
    if (purchase == null) return null;
    final index = _purchaseIndexForId(purchase.id);
    _putPurchaseAtIndex(purchase, index < 0 ? _purchases.length : index);
    _touchPurchasesData();
    notifyListeners();
    return purchase;
  }

Future<Expense?> _expenseByIdFromSqlite(String id) {
    return LocalDatabaseService.getExpenseFromSqliteById(id);
  }

void _putStockMovementAtIndex(StockMovement movement, int index) {
    final id = movement.id.trim();
    if (id.isEmpty) return;
    if (index == _stockMovements.length) {
      _stockMovements.add(movement);
    } else {
      _stockMovements[index] = movement;
    }
    _stockMovementIndexById[id] = index;
    _warehouseStockCacheDirty = true;
  }

void _mirrorAuthoritativeStockMovements(Iterable<StockMovement> movements) {
    var touched = false;
    for (final movement in movements) {
      final id = movement.id.trim();
      if (id.isEmpty) continue;
      final existingIndex = _stockMovementIndexForId(id);
      if (existingIndex == -1) {
        _stockMovements.add(movement);
        _stockMovementIndexById[id] = _stockMovements.length - 1;
      } else {
        _stockMovements[existingIndex] = movement;
      }
      touched = true;
    }
    if (touched) {
      _touchDataRevisions(stockMovements: true);
    }
  }

void _rebuildExpenseIndexes() {
    _expenseIndexById.clear();
    for (var i = 0; i < _expenses.length; i++) {
      final id = _expenses[i].id.trim();
      if (id.isEmpty) continue;
      _expenseIndexById[id] = i;
    }
  }

void _rebuildAccountTransactionIndexes() {
    _accountTransactionIndexById.clear();
    for (var i = 0; i < _accountTransactions.length; i++) {
      final id = _accountTransactions[i].id.trim();
      if (id.isEmpty) continue;
      _accountTransactionIndexById[id] = i;
    }
  }

void _touchDataRevisions({
    bool products = false,
    bool customers = false,
    bool sales = false,
    bool deliveryNotes = false,
    bool suppliers = false,
    bool supplierProductPrices = false,
    bool expenses = false,
    bool purchases = false,
    bool stockMovements = false,
    bool inventoryCounts = false,
    bool warehouses = false,
    bool accountTransactions = false,
    bool storeProfile = false,
  }) {
    if (products) {
      _productsRevision += 1;
      _warehouseStockCacheDirty = true;
      _cachedProducts = null;
      _cachedProductsGeneration = -1;
      _cachedStockTrackedProducts = null;
      _cachedStockTrackedProductsGeneration = -1;
    }
    if (customers) _customersRevision += 1;
    if (sales) {
      _salesRevision += 1;
      _cachedSales = null;
      _cachedSalesGeneration = -1;
    }
    if (deliveryNotes) {
      _deliveryNotesRevision += 1;
      _cachedDeliveryNotes = null;
      _cachedDeliveryNotesGeneration = -1;
      _cachedDeliveryNoteBySaleId = null;
      _cachedDeliveryNoteBySaleIdGeneration = -1;
    }
    if (suppliers) _suppliersRevision += 1;
    if (supplierProductPrices) _supplierProductPricesRevision += 1;
    if (expenses) {
      _expensesRevision += 1;
      _cachedExpensesOverview = null;
      _cachedExpensesOverviewRevision = -1;
    }
    if (purchases) {
      _purchasesRevision += 1;
      _purchaseInsightsCacheDirty = true;
      _cachedPurchasesOverview = null;
      _cachedPurchasesOverviewRevision = -1;
      _cachedPurchasesOverviewMonthKey = '';
    }
    if (stockMovements) {
      _stockMovementsRevision += 1;
      _warehouseStockCacheDirty = true;
    }
    if (inventoryCounts) _inventoryCountsRevision += 1;
    if (warehouses) {
      _warehousesRevision += 1;
      _warehouseStockCacheDirty = true;
    }
    if (accountTransactions) {
      _accountTransactionsRevision += 1;
      _accountLedgerCacheDirty = true;
    }
    if (storeProfile) _storeProfileRevision += 1;
  }

void _touchPurchasesData() {
    _touchDataRevisions(purchases: true);
  }

void _touchExpensesData() {
    _touchDataRevisions(expenses: true);
  }

void _putPurchaseAtIndex(Purchase purchase, int index) {
    final id = purchase.id.trim();
    if (id.isEmpty) return;
    if (index == _purchases.length) {
      _purchases.add(purchase);
    } else {
      _purchases[index] = purchase;
    }
    _purchaseIndexById[id] = index;
  }

void _removePurchaseAtIndex(int index) {
    if (index < 0 || index >= _purchases.length) return;
    final removedId = _purchases[index].id.trim();
    _purchases.removeAt(index);
    if (removedId.isNotEmpty) {
      _purchaseIndexById.remove(removedId);
    }
    for (var i = index; i < _purchases.length; i++) {
      final id = _purchases[i].id.trim();
      if (id.isNotEmpty) {
        _purchaseIndexById[id] = i;
      }
    }
  }

void _putExpenseAtIndex(Expense expense, int index) {
    final id = expense.id.trim();
    if (id.isEmpty) return;
    if (index == _expenses.length) {
      _expenses.add(expense);
    } else {
      _expenses[index] = expense;
    }
    _expenseIndexById[id] = index;
  }

void _putAccountTransactionAtIndex(
      AccountTransaction transaction, int index) {
    final id = transaction.id.trim();
    if (id.isEmpty) return;
    if (index == _accountTransactions.length) {
      _accountTransactions.add(transaction);
    } else {
      _accountTransactions[index] = transaction;
    }
    _accountTransactionIndexById[id] = index;
  }

void _removeExpenseAtIndex(int index) {
    if (index < 0 || index >= _expenses.length) return;
    final removedId = _expenses[index].id.trim();
    _expenses.removeAt(index);
    if (removedId.isNotEmpty) {
      _expenseIndexById.remove(removedId);
    }
    for (var i = index; i < _expenses.length; i++) {
      final id = _expenses[i].id.trim();
      if (id.isNotEmpty) {
        _expenseIndexById[id] = i;
      }
    }
  }

void _removeAccountTransactionAtIndex(int index) {
    if (index < 0 || index >= _accountTransactions.length) return;
    final removedId = _accountTransactions[index].id.trim();
    _accountTransactions.removeAt(index);
    if (removedId.isNotEmpty) {
      _accountTransactionIndexById.remove(removedId);
    }
    for (var i = index; i < _accountTransactions.length; i++) {
      final id = _accountTransactions[i].id.trim();
      if (id.isNotEmpty) {
        _accountTransactionIndexById[id] = i;
      }
    }
  }

void _compactSyncedHistory() {
    return;
  }

int _earliestStoredAuthoritativeSequence() {
    var earliest = 0;
    for (final change in _syncChanges) {
      if (change.sequence <= 0) continue;
      if (earliest == 0 || change.sequence < earliest) {
        earliest = change.sequence;
      }
    }
    return earliest;
  }

int _latestStoredAuthoritativeSequence() {
    var latest = _syncSequence;
    for (final change in _syncChanges) {
      if (change.sequence > latest) latest = change.sequence;
    }
    return latest;
  }

int _minimumActivePeerAckSequence({
    Duration activeWindow = const Duration(days: 14),
  }) {
    if (!appIdentity.isHost) return _latestStoredAuthoritativeSequence();
    final now = DateTime.now();
    final deletedPeerIds = SyncDeviceAccessStore.deletedDeviceIds();
    final activePeers = SyncDeviceStateStore.loadPeerStates().where((peer) {
      if (deletedPeerIds.contains(peer.deviceId.trim())) return false;
      final seen = peer.lastSeenAt ?? peer.updatedAt;
      if (seen == null) return false;
      return now.difference(seen) <= activeWindow;
    }).toList();
    if (activePeers.isEmpty) return 0;
    return activePeers.fold<int>(1 << 62, (minSeq, peer) {
      final seq = peer.lastAckSequence > 0
          ? peer.lastAckSequence
          : peer.lastAppliedSequence;
      if (seq <= 0) return 0;
      return seq < minSeq ? seq : minSeq;
    });
  }

Future<void> _saveSyncStateOnly() async {
    // Hot-path performance fix: sync status/queue updates must not persist the
    // entire business dataset. Rewriting products, sales, purchases, and stock
    // movements on every sync acknowledgement makes normal data entry slower
    // as the database grows. Persist only the sync tables and sequence here.
    //
    // Use the normal key writer instead of only the SQLite dirty lists because
    // many sync paths mutate existing rows (mark synced/rejected/clear queue).
    // The SQLite backend already merges these rows instead of full deleting,
    // while older export formats still receive the compact sync-only JSON.
    await Future.wait([
      LocalDatabaseService.setString(
        AppStore._syncChangesKey,
        jsonEncode(_syncChanges.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._syncQueueKey,
        jsonEncode(_syncQueue.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._syncSequenceKey,
        _syncSequence.toString(),
      ),
    ]);
  }

Future<void> _saveAll() async {
    _normalizeCustomers();
    _replaceUsersWithoutDuplicates(List<AppUser>.from(_users));
    _compactSyncedHistory();
    await Future.wait([
      LocalDatabaseService.setString(
        AppStore._productsKey,
        jsonEncode(_products.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._customersKey,
        jsonEncode(_customers.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._salesKey,
        jsonEncode(_sales.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._saleQuotationsKey,
        jsonEncode(_saleQuotations.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._deliveryNotesKey,
        jsonEncode(_deliveryNotes.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._billsOfMaterialsKey,
        jsonEncode(_billsOfMaterials.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._manufacturingOrdersKey,
        jsonEncode(_manufacturingOrders.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._suppliersKey,
        jsonEncode(_suppliers.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._supplierProductPricesKey,
        jsonEncode(
          _supplierProductPrices.map((item) => item.toJson()).toList(),
        ),
      ),
      LocalDatabaseService.setString(
        AppStore._priceListsKey,
        jsonEncode(_priceLists.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._productPricesKey,
        jsonEncode(_productPrices.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._productPriceOverridesKey,
        jsonEncode(
            _productPriceOverrides.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._productCostsKey,
        jsonEncode(_productCosts.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._costingMethodHistoryKey,
        jsonEncode(_costingMethodHistory.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._inventoryCostLayersKey,
        jsonEncode(_inventoryCostLayers.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
          AppStore._inventoryCostingMethodKey, _inventoryCostingMethod.code),
      LocalDatabaseService.setString(
        AppStore._categoriesKey,
        jsonEncode(_categories.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._brandsKey,
        jsonEncode(_brands.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._unitsKey,
        jsonEncode(_units.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._expensesKey,
        jsonEncode(_expenses.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._purchasesKey,
        jsonEncode(_purchases.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._stockMovementsKey,
        jsonEncode(_stockMovements.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._inventoryCountsKey,
        jsonEncode(_inventoryCounts.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._warehousesKey,
        jsonEncode(_warehouses.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._accountTransactionsKey,
        jsonEncode(_accountTransactions.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._syncChangesKey,
        jsonEncode(_syncChanges.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        AppStore._syncQueueKey,
        jsonEncode(_syncQueue.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(AppStore._deviceIdKey, _deviceId),
      LocalDatabaseService.setString(
        AppStore._storeProfileKey,
        jsonEncode(_storeProfile.toJson()),
      ),
      LocalDatabaseService.setString(
        AppStore._invoiceCounterKey,
        _invoiceCounter.toString(),
      ),
      LocalDatabaseService.setString(
        AppStore._purchaseCounterKey,
        _purchaseCounter.toString(),
      ),
      LocalDatabaseService.setString(
        AppStore._syncSequenceKey,
        _syncSequence.toString(),
      ),
      LocalDatabaseService.setString(AppStore._schemaVersionKey, '17'),
    ]);
  }

Future<void> _saveDirty({
    bool products = false,
    bool productDerivedData = true,
    bool customers = false,
    bool sales = false,
    bool saleQuotations = false,
    bool deliveryNotes = false,
    bool billsOfMaterials = false,
    bool manufacturingOrders = false,
    bool suppliers = false,
    bool supplierProductPrices = false,
    bool categories = false,
    bool brands = false,
    bool units = false,
    bool expenses = false,
    bool purchases = false,
    bool stockMovements = false,
    bool inventoryCounts = false,
    bool warehouses = false,
    bool accountTransactions = false,
    bool storeProfile = false,
    bool invoiceCounter = false,
    bool purchaseCounter = false,
    bool sync = false,
  }) async {
    _touchDataRevisions(
      products: products,
      customers: customers,
      sales: sales,
      suppliers: suppliers,
      supplierProductPrices: supplierProductPrices,
      expenses: expenses,
      purchases: purchases,
      stockMovements: stockMovements,
      inventoryCounts: inventoryCounts,
      warehouses: warehouses,
      accountTransactions: accountTransactions,
      storeProfile: storeProfile,
    );
    if (LocalDatabaseService.isSqliteAuthoritative) {
      await _traceAsync(
        'saveDirty',
        'sqlite_hot_path',
        () => _saveDirtySqliteHotPath(
          products: products,
          productDerivedData: productDerivedData,
          customers: customers,
          sales: sales,
          saleQuotations: saleQuotations,
          deliveryNotes: deliveryNotes,
          billsOfMaterials: billsOfMaterials,
          manufacturingOrders: manufacturingOrders,
          suppliers: suppliers,
          supplierProductPrices: supplierProductPrices,
          categories: categories,
          brands: brands,
          units: units,
          expenses: expenses,
          purchases: purchases,
          stockMovements: stockMovements,
          inventoryCounts: inventoryCounts,
          warehouses: warehouses,
          accountTransactions: accountTransactions,
          storeProfile: storeProfile,
          invoiceCounter: invoiceCounter,
          purchaseCounter: purchaseCounter,
          sync: sync,
        ),
        metadata: <String, Object?>{
          'products': products,
          'productDerivedData': productDerivedData,
          'customers': customers,
          'sales': sales,
          'suppliers': suppliers,
          'purchases': purchases,
          'stockMovements': stockMovements,
          'accountTransactions': accountTransactions,
          'sync': sync,
        },
      );
      return;
    }

    final writes = <Future<void>>[];
    if (sync) {
      _traceSync('saveDirty', 'compact_sync_history', _compactSyncedHistory);
    }
    if (products) {
      writes.add(
        _traceAsync(
          'saveDirty',
          'write_products',
          () => LocalDatabaseService.setString(
            AppStore._productsKey,
            jsonEncode(_products.map((item) => item.toJson()).toList()),
          ),
        ),
      );
    }
    if (productDerivedData) {
      writes.add(
        _traceAsync(
          'saveDirty',
          'write_product_costs',
          () => _upsertSqliteBusinessRows(
            AppStore._productCostsKey,
            _productCosts.map((item) => item.toJson()),
          ),
        ),
      );
      writes.add(
        _traceAsync(
          'saveDirty',
          'write_price_lists',
          () => _upsertSqliteBusinessRows(
            AppStore._priceListsKey,
            _priceLists.map((item) => item.toJson()),
          ),
        ),
      );
      writes.add(
        _traceAsync(
          'saveDirty',
          'write_product_prices',
          () => _upsertSqliteBusinessRows(
            AppStore._productPricesKey,
            _productPrices.map((item) => item.toJson()),
          ),
        ),
      );
      writes.add(
        _traceAsync(
          'saveDirty',
          'write_product_price_overrides',
          () => _upsertSqliteBusinessRows(
            AppStore._productPriceOverridesKey,
            _productPriceOverrides.map((item) => item.toJson()),
          ),
        ),
      );
      writes.add(
        _traceAsync(
          'saveDirty',
          'write_inventory_costing_method',
          () => LocalDatabaseService.setString(
            AppStore._inventoryCostingMethodKey,
            _inventoryCostingMethod.code,
          ),
        ),
      );
      writes.add(
        _traceAsync(
          'saveDirty',
          'write_costing_history',
          () => _upsertSqliteBusinessRows(
            AppStore._costingMethodHistoryKey,
            _costingMethodHistory.map((item) => item.toJson()),
          ),
        ),
      );
      writes.add(
        _traceAsync(
          'saveDirty',
          'write_inventory_layers',
          () => _upsertSqliteBusinessRows(
            AppStore._inventoryCostLayersKey,
            _inventoryCostLayers.map((item) => item.toJson()),
          ),
        ),
      );
    }
    if (customers) {
      writes.add(_traceAsync(
          'saveDirty',
          'write_customers',
          () => LocalDatabaseService.setString(AppStore._customersKey,
              jsonEncode(_customers.map((item) => item.toJson()).toList()))));
    }
    if (sales) {
      writes.add(_traceAsync(
          'saveDirty',
          'write_sales',
          () => LocalDatabaseService.setString(AppStore._salesKey,
              jsonEncode(_sales.map((item) => item.toJson()).toList()))));
    }
    if (saleQuotations) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._saleQuotationsKey,
          jsonEncode(_saleQuotations.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (deliveryNotes) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._deliveryNotesKey,
          jsonEncode(_deliveryNotes.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (billsOfMaterials) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._billsOfMaterialsKey,
          jsonEncode(_billsOfMaterials.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (manufacturingOrders) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._manufacturingOrdersKey,
          jsonEncode(
            _manufacturingOrders.map((item) => item.toJson()).toList(),
          ),
        ),
      );
    }
    if (suppliers) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._suppliersKey,
          jsonEncode(_suppliers.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (supplierProductPrices) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._supplierProductPricesKey,
          jsonEncode(
            _supplierProductPrices.map((item) => item.toJson()).toList(),
          ),
        ),
      );
    }
    if (categories) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._categoriesKey,
          jsonEncode(_categories.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (brands) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._brandsKey,
          jsonEncode(_brands.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (units) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._unitsKey,
          jsonEncode(_units.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (expenses) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._expensesKey,
          jsonEncode(_expenses.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (purchases) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._purchasesKey,
          jsonEncode(_purchases.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (stockMovements) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._stockMovementsKey,
          jsonEncode(_stockMovements.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (inventoryCounts) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._inventoryCountsKey,
          jsonEncode(_inventoryCounts.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (warehouses) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._warehousesKey,
          jsonEncode(_warehouses.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (accountTransactions) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._accountTransactionsKey,
          jsonEncode(
            _accountTransactions.map((item) => item.toJson()).toList(),
          ),
        ),
      );
    }
    if (storeProfile) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._storeProfileKey,
          jsonEncode(_storeProfile.toJson()),
        ),
      );
    }
    if (invoiceCounter) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._invoiceCounterKey,
          _invoiceCounter.toString(),
        ),
      );
    }
    if (purchaseCounter) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._purchaseCounterKey,
          _purchaseCounter.toString(),
        ),
      );
    }
    if (sync) {
      writes
        ..add(
          LocalDatabaseService.setString(
            AppStore._syncChangesKey,
            jsonEncode(_syncChanges.map((item) => item.toJson()).toList()),
          ),
        )
        ..add(
          LocalDatabaseService.setString(
            AppStore._syncQueueKey,
            jsonEncode(_syncQueue.map((item) => item.toJson()).toList()),
          ),
        )
        ..add(
          LocalDatabaseService.setString(
            AppStore._syncSequenceKey,
            _syncSequence.toString(),
          ),
        );
    }
    if (writes.isEmpty) return;
    await Future.wait(writes);
  }

Future<void> _saveDirtySqliteHotPath({
    bool products = false,
    bool productDerivedData = true,
    bool customers = false,
    bool sales = false,
    bool saleQuotations = false,
    bool deliveryNotes = false,
    bool billsOfMaterials = false,
    bool manufacturingOrders = false,
    bool suppliers = false,
    bool supplierProductPrices = false,
    bool categories = false,
    bool brands = false,
    bool units = false,
    bool expenses = false,
    bool purchases = false,
    bool stockMovements = false,
    bool inventoryCounts = false,
    bool warehouses = false,
    bool accountTransactions = false,
    bool storeProfile = false,
    bool invoiceCounter = false,
    bool purchaseCounter = false,
    bool sync = false,
  }) async {
    final writes = <Future<void>>[];

    Future<void> persistRows(String key) async {
      final rows = _sqliteDirtyBusinessRows.remove(key);
      if (rows == null || rows.isEmpty) return;
      await LocalDatabaseService.upsertBusinessEntityJsons(
        key,
        rows.values.toList(growable: false),
      );
    }

    if (products) {
      writes.add(persistRows(AppStore._productsKey));
    }
    if (productDerivedData) _markProductDerivedDataDirty();
    if (customers) writes.add(persistRows(AppStore._customersKey));
    if (sales) writes.add(persistRows(AppStore._salesKey));
    if (saleQuotations) {
      writes.add(persistRows(AppStore._saleQuotationsKey));
    }
    if (deliveryNotes) {
      writes.add(persistRows(AppStore._deliveryNotesKey));
    }
    if (billsOfMaterials) {
      writes.add(persistRows(AppStore._billsOfMaterialsKey));
    }
    if (manufacturingOrders) {
      writes.add(persistRows(AppStore._manufacturingOrdersKey));
    }
    if (suppliers) writes.add(persistRows(AppStore._suppliersKey));
    if (supplierProductPrices) {
      writes.add(persistRows(AppStore._supplierProductPricesKey));
    }
    if (categories) writes.add(persistRows(AppStore._categoriesKey));
    if (brands) writes.add(persistRows(AppStore._brandsKey));
    if (units) writes.add(persistRows(AppStore._unitsKey));
    if (expenses) writes.add(persistRows(AppStore._expensesKey));
    if (purchases) writes.add(persistRows(AppStore._purchasesKey));
    if (stockMovements) writes.add(persistRows(AppStore._stockMovementsKey));
    if (inventoryCounts) {
      writes.add(persistRows(AppStore._inventoryCountsKey));
    }
    if (warehouses) {
      writes.add(persistRows(AppStore._warehousesKey));
    }
    if (accountTransactions) writes.add(persistRows(AppStore._accountTransactionsKey));

    if (storeProfile) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._storeProfileKey,
          jsonEncode(_storeProfile.toJson()),
        ),
      );
    }
    if (invoiceCounter) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._invoiceCounterKey,
          _invoiceCounter.toString(),
        ),
      );
    }
    if (purchaseCounter) {
      writes.add(
        LocalDatabaseService.setString(
          AppStore._purchaseCounterKey,
          _purchaseCounter.toString(),
        ),
      );
    }

    if (sync) {
      final dirtyChanges = List<SyncChange>.from(_sqliteDirtySyncChanges);
      final dirtyQueue = List<SyncQueueItem>.from(_sqliteDirtySyncQueue);
      _sqliteDirtySyncChanges.clear();
      _sqliteDirtySyncQueue.clear();
      writes.add(LocalDatabaseService.upsertSyncChanges(dirtyChanges));
      writes.add(LocalDatabaseService.upsertSyncQueueItems(dirtyQueue));
      writes.add(
        LocalDatabaseService.setString(
          AppStore._syncSequenceKey,
          _syncSequence.toString(),
        ),
      );
    }

    if (writes.isEmpty) return;
    await Future.wait(writes);
  }

void _resetBusinessDataInMemory({bool keepStoreProfile = true}) {
    _products.clear();
    _customers
      ..clear()
      ..add(walkInCustomer);
    _productPrices.clear();
    _productPriceOverrides.clear();
    _productCosts.clear();
    _inventoryCostLayers.clear();
    _productPriceByLookupKey.clear();
    _productCostByProductId.clear();
    _productCostIndexByProductId.clear();
    _inventoryCostLayerIndexById.clear();
    _sales.clear();
    _suppliers.clear();
    _supplierProductPrices.clear();
    _expenses.clear();
    _purchases.clear();
    _stockMovements.clear();
    _accountTransactions.clear();
    _purchaseIndexById.clear();
    _stockMovementIndexById.clear();
    _expenseIndexById.clear();
    _accountTransactionIndexById.clear();
    _accountLedgerCacheDirty = true;
    _invoiceCounter = 0;
    _purchaseCounter = 0;
    _touchDataRevisions(
      products: true,
      customers: true,
      sales: true,
      suppliers: true,
      supplierProductPrices: true,
      expenses: true,
      purchases: true,
      stockMovements: true,
      inventoryCounts: true,
      warehouses: true,
      accountTransactions: true,
      storeProfile: !keepStoreProfile,
    );
    _invalidateDerivedDataCaches();
    if (!keepStoreProfile) {
      _storeProfile = StoreProfile.defaults;
      AccountingService.configureMoneyPolicy(_storeProfile);
    }
  }

Future<void> resetBusinessData({bool keepStoreProfile = true}) async {
    requirePermission(AppPermission.backupRestore);
    requireSensitiveActionAuthorization(SensitiveAction.databaseDestructive);
    await AuditLogger.record(
      entityType: 'database',
      entityId: appIdentity.storeId,
      action: 'business_reset_started',
      summary: 'Local business data reset started',
      userId: _activeUser?.id ?? '',
      userName: _activeUser?.username ?? '',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      sessionId: _deviceId,
      traceId: _deviceId,
      deviceId: _deviceId,
      sourceModule: 'database',
      isImportant: true,
    );

    // Local-only reset. This must never create a SyncChange or propagate delete
    // operations to Clients. Host factory reset is handled by factoryResetLocalDevice().
    _syncChanges.clear();
    _syncQueue.clear();
    _resetBusinessDataInMemory(keepStoreProfile: keepStoreProfile);
    if (wants('syncChanges') ||
        wants('syncQueue') ||
        wants('localDatabaseEntries')) {
      await LocalDatabaseService.deleteString('direct_last_pull_cursor');
    }
    await _saveAll();
    notifyListeners();
  }

Future<void> clearLocalDeviceBusinessData({
    bool keepStoreProfile = true,
  }) async {
    requirePermission(AppPermission.backupRestore);
    requireSensitiveActionAuthorization(SensitiveAction.databaseDestructive);
    await AuditLogger.record(
      entityType: 'database',
      entityId: appIdentity.storeId,
      action: 'client_business_clear_started',
      summary: 'Client local business data clear started',
      userId: _activeUser?.id ?? '',
      userName: _activeUser?.username ?? '',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      sessionId: _deviceId,
      traceId: _deviceId,
      deviceId: _deviceId,
      sourceModule: 'database',
      isImportant: true,
    );
    // Client-only maintenance operation. This must never create a SyncChange or
    // deletion event because the Host remains the source of truth. It also
    // clears pull cursors so the next sync can rebuild from a full Host
    // snapshot instead of resuming after stale local leftovers.
    final identity = appIdentity;
    _syncChanges.clear();
    _syncQueue.clear();
    _resetBusinessDataInMemory(keepStoreProfile: keepStoreProfile);
    if (wants('syncChanges') ||
        wants('syncQueue') ||
        wants('localDatabaseEntries')) {
      await LocalDatabaseService.deleteString('direct_last_pull_cursor');
    }
    final lanRaw = LocalDatabaseService.getString('lan_sync_settings_v2');
    if (lanRaw != null && lanRaw.trim().isNotEmpty) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(lanRaw) as Map);
        decoded.remove('lastPullCursor');
        decoded['lastSyncAt'] = null;
        await LocalDatabaseService.setString(
          'lan_sync_settings_v2',
          jsonEncode(decoded),
        );
      } catch (_) {
        // Keep the data clear even if old LAN settings are malformed.
      }
    }
    _appIdentity = identity.copyWith(
      deviceId: _deviceId,
      platform: _detectPlatform(),
    );
    await LocalDatabaseService.setString(
      AppStore._appIdentityKey,
      jsonEncode(_appIdentity!.toJson()),
    );
    await _saveAll();
    notifyListeners();
  }

Future<int> clearLocalOnlyPendingSyncChanges() async {
    requirePermission(AppPermission.syncManage);
    final invalidChangeIds = _syncChanges
        .where(
          (change) =>
              !change.isSynced &&
              change.entityType == 'app_identity' &&
              change.operation == 'update',
        )
        .map((change) => change.id)
        .toSet();
    if (invalidChangeIds.isEmpty) return 0;

    final beforeQueue = _syncQueue.length;
    _syncQueue.removeWhere(
      (item) => invalidChangeIds.contains(item.changeId) && !item.isSynced,
    );
    final removedQueueRows = beforeQueue - _syncQueue.length;

    final queuedInvalidIds = _syncQueue.map((item) => item.changeId).toSet();
    _syncChanges.removeWhere(
      (change) =>
          invalidChangeIds.contains(change.id) &&
          !queuedInvalidIds.contains(change.id),
    );

    await _saveSyncStateOnly();
    notifyListeners();
    return removedQueueRows;
  }

Future<void> factoryResetLocalDevice({
    bool enforcePermission = true,
    bool preserveAdminUsers = false,
  }) async {
    if (enforcePermission) {
      requirePermission(AppPermission.settingsManage);
      requireSensitiveActionAuthorization(SensitiveAction.databaseDestructive);
    }
    await AuditLogger.record(
      entityType: 'database',
      entityId: appIdentity.storeId,
      action: 'factory_reset_started',
      summary: 'Local device factory reset started',
      details: 'enforcePermission=$enforcePermission',
      userId: _activeUser?.id ?? '',
      userName: _activeUser?.username ?? '',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      sessionId: _deviceId,
      traceId: _deviceId,
      deviceId: _deviceId,
      sourceModule: 'database',
      isImportant: true,
    );
    _products.clear();
    _customers
      ..clear()
      ..add(walkInCustomer);
    _sales.clear();
    _suppliers.clear();
    _supplierProductPrices.clear();
    _expenses.clear();
    _purchases.clear();
    _stockMovements.clear();
    _accountTransactions.clear();
    _purchaseIndexById.clear();
    _expenseIndexById.clear();
    _accountTransactionIndexById.clear();
    _stockMovementIndexById.clear();
    _touchPurchasesData();
    _touchExpensesData();
    _categories.clear();
    _brands.clear();
    _units.clear();
    _syncChanges.clear();
    _syncQueue.clear();
    _invoiceCounter = 0;
    _purchaseCounter = 0;
    _storeProfile = StoreProfile.defaults;
    AccountingService.configureMoneyPolicy(_storeProfile);
    _activeUser = null;
    _rememberLogin = false;
    if (!preserveAdminUsers) {
      _users.clear();
      _roles.clear();
      await _ensureDefaultAdminUser();
    }
    _deviceId = _generatePrefixedId('DV');
    _appIdentity = AppIdentity.defaults(
      deviceId: _deviceId,
      platform: _detectPlatform(),
    ).copyWith(deviceRole: DeviceRole.standalone, syncMode: SyncMode.localOnly);
    await LocalDatabaseService.setString(AppStore._deviceIdKey, _deviceId);
    await LocalDatabaseService.setString(
      AppStore._appIdentityKey,
      jsonEncode(_appIdentity!.toJson()),
    );
    await LocalDatabaseService.setString(AppStore._activeUserKey, '');
    await LocalDatabaseService.setString(AppStore._rememberLoginKey, 'false');
    if (wants('syncChanges') ||
        wants('syncQueue') ||
        wants('localDatabaseEntries')) {
      await LocalDatabaseService.deleteString('direct_last_pull_cursor');
    }
    await LocalDatabaseService.deleteString('lan_sync_settings_v2');
    _touchDataRevisions(
      products: true,
      customers: true,
      sales: true,
      suppliers: true,
      supplierProductPrices: true,
      expenses: true,
      purchases: true,
      stockMovements: true,
      accountTransactions: true,
      storeProfile: true,
    );
    _invalidateDerivedDataCaches();
    await _saveAll();
    notifyListeners();
  }

bool _hasPendingSyncFor(String entityType, String entityId) {
    final changesById = {for (final change in _syncChanges) change.id: change};
    final pendingChangeIds = _syncQueue
        .where((item) {
          if (item.status == 'synced') return false;
          final change = changesById[item.changeId];
          // Stale pending queue rows tied to already-synced local drafts must
          // not protect those draft changes from compaction.
          if (change != null && change.isSynced && change.sequence <= 0) {
            return false;
          }
          return true;
        })
        .map((item) => item.changeId)
        .toSet();
    return _syncChanges.any(
      (change) =>
          pendingChangeIds.contains(change.id) &&
          change.entityType == entityType &&
          change.entityId == entityId,
    );
  }

Future<int> cleanupSoftDeletedRecords({
    Duration retention = const Duration(days: 30),
  }) async {
    final cutoff = DateTime.now().subtract(retention);
    var removed = 0;
    var productsChanged = false;
    var catalogChanged = false;
    var customersChanged = false;
    var suppliersChanged = false;
    var supplierProductPricesChanged = false;
    var expensesChanged = false;
    var salesChanged = false;
    var purchasesChanged = false;

    bool expired(DateTime? deletedAt) =>
        deletedAt != null && deletedAt.isBefore(cutoff);

    final beforeProducts = _products.length;
    _products.removeWhere(
      (item) =>
          expired(item.deletedAt) &&
          !_hasPendingSyncFor('product', item.id) &&
          !isProductReferenced(item.id),
    );
    removed += beforeProducts - _products.length;
    productsChanged = productsChanged || beforeProducts != _products.length;

    final beforeCustomers = _customers.length;
    _customers.removeWhere(
      (item) =>
          expired(item.deletedAt) &&
          item.id != 'walk_in' &&
          !_hasPendingSyncFor('customer', item.id),
    );
    removed += beforeCustomers - _customers.length;
    customersChanged = customersChanged || beforeCustomers != _customers.length;

    final beforeSuppliers = _suppliers.length;
    _suppliers.removeWhere(
      (item) =>
          expired(item.deletedAt) && !_hasPendingSyncFor('supplier', item.id),
    );
    removed += beforeSuppliers - _suppliers.length;
    suppliersChanged = suppliersChanged || beforeSuppliers != _suppliers.length;

    final beforeSupplierProductPrices = _supplierProductPrices.length;
    _supplierProductPrices.removeWhere(
      (item) =>
          expired(item.deletedAt) &&
          !_hasPendingSyncFor('supplier_product_price', item.id),
    );
    removed += beforeSupplierProductPrices - _supplierProductPrices.length;
    supplierProductPricesChanged = supplierProductPricesChanged ||
        beforeSupplierProductPrices != _supplierProductPrices.length;

    final beforeExpenses = _expenses.length;
    _expenses.removeWhere(
      (item) =>
          expired(item.deletedAt) && !_hasPendingSyncFor('expense', item.id),
    );
    removed += beforeExpenses - _expenses.length;
    expensesChanged = expensesChanged || beforeExpenses != _expenses.length;

    final beforeCategories = _categories.length;
    _categories.removeWhere(
      (item) =>
          expired(item.deletedAt) && !_hasPendingSyncFor('category', item.id),
    );
    removed += beforeCategories - _categories.length;
    catalogChanged = catalogChanged || beforeCategories != _categories.length;

    final beforeBrands = _brands.length;
    _brands.removeWhere(
      (item) =>
          expired(item.deletedAt) && !_hasPendingSyncFor('brand', item.id),
    );
    removed += beforeBrands - _brands.length;
    catalogChanged = catalogChanged || beforeBrands != _brands.length;

    final beforeUnits = _units.length;
    _units.removeWhere(
      (item) => expired(item.deletedAt) && !_hasPendingSyncFor('unit', item.id),
    );
    removed += beforeUnits - _units.length;
    catalogChanged = catalogChanged || beforeUnits != _units.length;

    final beforeSales = _sales.length;
    _sales.removeWhere(
      (item) => expired(item.deletedAt) && !_hasPendingSyncFor('sale', item.id),
    );
    removed += beforeSales - _sales.length;
    salesChanged = salesChanged || beforeSales != _sales.length;

    final beforePurchases = _purchases.length;
    _purchases.removeWhere(
      (item) =>
          expired(item.deletedAt) && !_hasPendingSyncFor('purchase', item.id),
    );
    removed += beforePurchases - _purchases.length;
    purchasesChanged = purchasesChanged || beforePurchases != _purchases.length;

    if (removed > 0) {
      if (productsChanged) {
        _rebuildProductIndexes();
        _rebuildProductPricingLookupCaches();
      }
      if (customersChanged) {
        _rebuildCustomerIndexes();
      }
      if (suppliersChanged) {
        _rebuildSupplierIndexes();
      }
      if (supplierProductPricesChanged) {
        _markSingleSupplierPerProductAsPreferred();
      }
      if (expensesChanged) {
        _rebuildExpenseIndexes();
      }
      if (purchasesChanged) {
        _rebuildPurchaseIndexes();
      }
      _touchDataRevisions(
        products: productsChanged || catalogChanged,
        customers: customersChanged,
        sales: salesChanged,
        suppliers: suppliersChanged,
        supplierProductPrices: supplierProductPricesChanged,
        expenses: expensesChanged,
        purchases: purchasesChanged,
      );
      if (productsChanged ||
          customersChanged ||
          suppliersChanged ||
          supplierProductPricesChanged ||
          expensesChanged ||
          salesChanged ||
          purchasesChanged) {
        _warehouseStockCacheDirty = true;
        _accountLedgerCacheDirty = true;
      }
      await _saveSyncStateOnly();
      notifyListeners();
    }
    return removed;
  }

Future<BusinessDataIntegrityResult> verifyLocalBusinessDataIntegrity() async {
    final problems = <String>[];
    final productIds = _products
        .where((item) => !item.isDeleted)
        .map((item) => item.id)
        .toSet();
    final supplierIds = _suppliers
        .where((item) => !item.isDeleted)
        .map((item) => item.id)
        .toSet();

    for (final price in _supplierProductPrices.where(
      (item) => !item.isDeleted,
    )) {
      if (!productIds.contains(price.productId)) {
        problems.add(
          'Supplier price ${price.id} references missing product ${price.productId}',
        );
      }
      if (!supplierIds.contains(price.supplierId)) {
        problems.add(
          'Supplier price ${price.id} references missing supplier ${price.supplierId}',
        );
      }
    }

    final activePriceKeys = <String>{};
    for (final price in _supplierProductPrices.where(
      (item) => !item.isDeleted,
    )) {
      final key = '${price.productId}::${price.supplierId}';
      if (!activePriceKeys.add(key)) {
        problems.add(
          'Duplicate supplier price for product ${price.productId} and supplier ${price.supplierId}',
        );
      }
    }

    for (final sale in _sales.where((item) => !item.isDeleted)) {
      if (sale.invoiceNo.trim().isEmpty) {
        problems.add('Sale ${sale.id} has no invoice number');
      }
      if (sale.items.isEmpty) {
        problems.add('Sale ${sale.invoiceNo} has no line items');
      }
      for (final item in sale.items) {
        if (!productIds.contains(item.productId)) {
          problems.add(
            'Sale ${sale.invoiceNo} references missing product ${item.productId}',
          );
        }
      }
      final movements = _stockMovements
          .where(
            (movement) =>
                movement.referenceId == sale.id && movement.type == 'sale',
          )
          .toList();
      if (sale.status != 'Cancelled' && movements.length < sale.items.length) {
        problems.add('Sale ${sale.invoiceNo} is missing stock movement(s)');
      }
    }

    for (final purchase in _purchases.where((item) => !item.isDeleted)) {
      if (purchase.items.isEmpty) {
        problems.add('Purchase ${purchase.id} has no line items');
      }
      for (final item in purchase.items) {
        if (!productIds.contains(item.productId)) {
          problems.add(
            'Purchase ${purchase.id} references missing product ${item.productId}',
          );
        }
      }
    }

    return BusinessDataIntegrityResult(
      ok: problems.isEmpty,
      message: problems.isEmpty
          ? 'Business data integrity check passed.'
          : problems.take(8).join('; '),
      problemCount: problems.length,
    );
  }

Future<BusinessDataIntegrityRepairResult> repairMissingProductReferences({
    bool createArchivedProducts = false,
  }) async {
    requirePermission(AppPermission.productsEdit);

    final activeIds = _products
        .where((product) => !product.isDeleted)
        .map((product) => product.id)
        .toSet();
    final references = <String, ({String name, double price, double cost})>{};

    void remember(String id, String name, double price, double cost) {
      final cleanId = id.trim();
      if (cleanId.isEmpty || activeIds.contains(cleanId)) return;
      references.putIfAbsent(
        cleanId,
        () => (
          name: name.trim().isEmpty ? 'Archived product $cleanId' : name.trim(),
          price: price,
          cost: cost,
        ),
      );
    }

    for (final sale in _sales.where((item) => !item.isDeleted)) {
      for (final item in sale.items) {
        remember(
            item.productId, item.productName, item.unitPrice, item.unitCost);
      }
    }
    for (final purchase in _purchases.where((item) => !item.isDeleted)) {
      for (final item in purchase.items) {
        remember(
            item.productId, item.productName, item.unitCost, item.unitCost);
      }
    }
    for (final movement in _stockMovements) {
      remember(
        movement.productId,
        movement.productName,
        movement.unitCost,
        movement.unitCost,
      );
    }

    final now = DateTime.now();
    var reactivated = 0;
    for (var index = 0; index < _products.length; index++) {
      final product = _products[index];
      if (!product.isDeleted || !references.containsKey(product.id)) continue;
      _products[index] = _withSyncMeta<Product>(
        product.copyWith(updatedAt: now, clearDeletedAt: true),
        now,
      );
      _recordSyncChange(
        entityType: 'product',
        entityId: product.id,
        operation: 'restore',
        payload: _products[index].toJson(),
      );
      activeIds.add(product.id);
      reactivated++;
    }

    final unresolved = references.keys
        .where((id) => !activeIds.contains(id))
        .toList(growable: false);
    var archivedCreated = 0;
    if (createArchivedProducts && unresolved.isNotEmpty) {
      final archived = unresolved.map((id) {
        final reference = references[id]!;
        return Product(
          id: id,
          name: '[Archived] ${reference.name}',
          code: 'ARCH-${id.hashCode.abs()}',
          price: reference.price,
          cost: reference.cost,
          stock: 0,
          category: 'Archived references',
          unit: 'pcs',
          trackStock: false,
          isActive: false,
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          syncStatus: 'pending',
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
        );
      }).toList(growable: false);
      await addOrUpdateProductsBulk(archived);
      archivedCreated = archived.length;
    }

    if (reactivated > 0) {
      await _saveDirty(products: true, sync: true);
      _rebuildProductIndexes();
      notifyListeners();
    }
    return BusinessDataIntegrityRepairResult(
      reactivatedProducts: reactivated,
      archivedProductsCreated: archivedCreated,
      unresolvedProductIds:
          createArchivedProducts ? const <String>[] : unresolved,
    );
  }

Future<void> updateStoreProfile(StoreProfile profile) async {
    requirePermission(AppPermission.settingsManage);
    if (wants('storeProfile')) {
      _storeProfile = profile;
      AccountingService.configureMoneyPolicy(_storeProfile);
    }
    _recordSyncChange(
      entityType: 'store_profile',
      entityId: 'store',
      operation: 'update',
      payload: profile.toJson(),
    );
    await _saveDirty(storeProfile: true, sync: true);
    notifyListeners();
  }

Future<void> updateTaxConfiguration({
    required List<TaxProfile> profiles,
    required String defaultTaxProfileId,
  }) async {
    requirePermission(AppPermission.accountingManage);
    if (profiles.isEmpty) {
      throw ArgumentError('At least one tax profile is required.');
    }
    final normalized = <TaxProfile>[];
    final ids = <String>{};
    final codes = <String>{};
    for (final source in profiles) {
      final id = source.id.trim();
      final code = source.code.trim().toUpperCase();
      final name = source.name.trim();
      if (id.isEmpty || code.isEmpty || name.isEmpty) {
        throw ArgumentError('Tax profile id, code, and name are required.');
      }
      if (!ids.add(id)) {
        throw ArgumentError('Duplicate tax profile id: $id');
      }
      if (!codes.add(code)) {
        throw ArgumentError('Duplicate tax profile code: $code');
      }
      final rate = source.treatment == TaxTreatment.standard
          ? (source.ratePercent.isFinite
              ? source.ratePercent.clamp(0, 100).toDouble()
              : 0.0)
          : 0.0;
      normalized.add(source.copyWith(
        id: id,
        code: code,
        name: name,
        ratePercent: rate,
      ));
    }
    final requestedDefault = defaultTaxProfileId.trim();
    TaxProfile? defaultProfile;
    for (final profile in normalized) {
      if (profile.id == requestedDefault && profile.isActive) {
        defaultProfile = profile;
        break;
      }
    }
    if (defaultProfile == null) {
      throw ArgumentError('Default tax profile must be active and available.');
    }
    final activeProfileIds = normalized
        .where((profile) => profile.isActive)
        .map((profile) => profile.id)
        .toSet();
    String orphanedProfileId = '';
    String orphanedProductCode = '';
    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      final rows = await sqliteDb.customSelect(
        '''
        SELECT code, tax_profile_id
        FROM products
        WHERE deleted_at = '' AND is_active = 1 AND tax_profile_id <> ''
        ''',
      ).get();
      for (final row in rows) {
        final assigned = row.data['tax_profile_id']?.toString().trim() ?? '';
        if (assigned.isNotEmpty && !activeProfileIds.contains(assigned)) {
          orphanedProfileId = assigned;
          orphanedProductCode = row.data['code']?.toString() ?? '';
          break;
        }
      }
    } else {
      for (final product in _products) {
        if (product.isDeleted || !product.isActive) continue;
        final assigned = product.taxProfileId.trim();
        if (assigned.isNotEmpty && !activeProfileIds.contains(assigned)) {
          orphanedProfileId = assigned;
          orphanedProductCode = product.code;
          break;
        }
      }
    }
    if (orphanedProfileId.isNotEmpty) {
      throw StateError(
        'Tax profile $orphanedProfileId is still assigned to product '
        '$orphanedProductCode. Reassign the product before removing or '
        'deactivating that tax profile.',
      );
    }
    final next = _storeProfile.copyWith(
      taxProfiles: List<TaxProfile>.unmodifiable(normalized),
      defaultTaxProfileId: defaultProfile.id,
      taxConfigurationVersion: 1,
    );
    _storeProfile = next;
    AccountingService.configureMoneyPolicy(next);
    _recordSyncChange(
      entityType: 'store_profile',
      entityId: 'store',
      operation: 'update',
      payload: next.toJson(),
    );
    await _saveDirty(storeProfile: true, sync: true);

    TaxProfile? standard;
    for (final profile in normalized) {
      if (profile.id == TaxProfile.standardId &&
          profile.treatment == TaxTreatment.standard) {
        standard = profile;
        break;
      }
    }
    if (standard != null) {
      await AccountingService.updateDefaultVatRatePercent(
        standard.ratePercent,
        authorization: this,
      );
    }
    notifyListeners();
  }

Future<void> updateDefaultTaxRatePercent(double ratePercent) async {
    requirePermission(AppPermission.accountingManage);
    final normalizedRate = ratePercent.isFinite
        ? ratePercent.clamp(0, 100).toDouble()
        : 0.0;
    final profiles = <TaxProfile>[];
    var replaced = false;
    for (final profile in _storeProfile.taxProfiles) {
      if (profile.id == TaxProfile.standardId) {
        profiles.add(profile.copyWith(
          ratePercent: normalizedRate,
          treatment: TaxTreatment.standard,
          isActive: true,
        ));
        replaced = true;
      } else {
        profiles.add(profile);
      }
    }
    if (!replaced) {
      profiles.insert(
        0,
        TaxProfile.standardZero.copyWith(ratePercent: normalizedRate),
      );
    }
    await updateTaxConfiguration(
      profiles: profiles,
      defaultTaxProfileId: _storeProfile.defaultTaxProfileId.trim().isEmpty
          ? TaxProfile.standardId
          : _storeProfile.defaultTaxProfileId,
    );
  }

void _validateProduct(Product product, {Product? previousProduct}) {
    if (product.name.trim().isEmpty ||
        product.code.trim().isEmpty ||
        product.category.trim().isEmpty) {
      throw ArgumentError('Product name, code, and category are required.');
    }
    if (!product.price.isFinite ||
        !product.cost.isFinite ||
        product.price < 0 ||
        product.cost < 0 ||
        product.lowStockThreshold < 0) {
      throw ArgumentError(
        'Product price, cost, and low stock threshold must be zero or positive.',
      );
    }

    final taxProfileId = product.taxProfileId.trim();
    if (taxProfileId.isNotEmpty &&
        !_storeProfile.taxProfiles.any(
          (profile) => profile.id == taxProfileId && profile.isActive,
        )) {
      throw ArgumentError('Product tax profile is unavailable or inactive.');
    }

    final normalizedCode = product.code.trim().toLowerCase();
    final normalizedBarcode = product.barcode.trim().toLowerCase();
    final previousCode = previousProduct?.code.trim().toLowerCase();
    final previousBarcode = previousProduct?.barcode.trim().toLowerCase();
    final codeChanged =
        previousProduct == null || normalizedCode != previousCode;
    final barcodeChanged =
        previousProduct == null || normalizedBarcode != previousBarcode;

    String? codeOwnerId;
    if (codeChanged) {
      codeOwnerId = _productIdByNormalizedCode[normalizedCode];
    } else {
      codeOwnerId = previousProduct.id;
    }
    String? barcodeOwnerId;
    if (barcodeChanged && normalizedBarcode.isNotEmpty) {
      barcodeOwnerId = _productIdByNormalizedBarcode[normalizedBarcode];
    } else {
      barcodeOwnerId = previousProduct?.id;
    }
    final duplicate = (codeOwnerId != null && codeOwnerId != product.id) ||
        (barcodeOwnerId != null && barcodeOwnerId != product.id);
    if (duplicate) {
      throw ArgumentError('Product code or barcode already exists.');
    }
  }

String _generateUniqueProductCode({
    String? exceptProductId,
    Set<String>? reservedCodes,
  }) {
    final used = {
      ..._productIdByNormalizedCode.keys.map((value) => value.toUpperCase()),
      ...?reservedCodes,
    };
    var counter = _products.length + 1;
    while (true) {
      final candidate = 'PRD-${counter.toString().padLeft(5, '0')}';
      if (!used.contains(candidate)) return candidate;
      counter++;
    }
  }

String get _invoiceDevicePrefix {
    final clean =
        _deviceId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (appIdentity.isHost) return 'H${clean.padRight(4, '0').substring(0, 4)}';
    return 'C${clean.padRight(4, '0').substring(0, 4)}';
  }

int _invoiceSequenceFromNo(String invoiceNo) {
    final matches = RegExp(r'(\d+)').allMatches(invoiceNo).toList();
    if (matches.isEmpty) return 0;
    return int.tryParse(matches.last.group(1) ?? '') ?? 0;
  }

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
      // Stress Lab/local-only usage from accumulating misleading pending LAN work
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
        LocalDatabaseService.getString(AppStore._phase8AccountingSyncCursorKey)?.trim();
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
    await ensureSyncDataLoaded();
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
    // path, which is especially visible under Stress Lab.
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
      _rememberSqliteDirtyBusinessRow(AppStore._saleQuotationsKey, updated.toJson());
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
      _rememberSqliteDirtyBusinessRow(AppStore._deliveryNotesKey, updated.toJson());
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
      _rememberSqliteDirtyBusinessRow(AppStore._billsOfMaterialsKey, updated.toJson());
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
      _sqliteDirtyBusinessRows[AppStore._accountTransactionsKey]?.remove(transaction.id);
      if (_sqliteDirtyBusinessRows[AppStore._accountTransactionsKey]?.isEmpty ?? false) {
        _sqliteDirtyBusinessRows.remove(AppStore._accountTransactionsKey);
      }
    }
  }

Future<void> addOrUpdateAccountTransaction(
    AccountTransaction transaction,
  ) async {
    requirePermission(AppPermission.accountingManage);
    final now = DateTime.now();
    final normalized = transaction.copyWith(
      accountType: transaction.accountType.trim().toLowerCase(),
      accountName: transaction.accountName.trim(),
      currency: transaction.currency.trim().isEmpty
          ? 'USD'
          : transaction.currency.trim().toUpperCase(),
      paymentMethod: transaction.paymentMethod.trim(),
      debit: _safeAccountAmount(transaction.debit),
      credit: _safeAccountAmount(transaction.credit),
    );
    if (normalized.accountType != 'customer' &&
        normalized.accountType != 'supplier') {
      throw ArgumentError(
        'Account transaction accountType must be customer or supplier.',
      );
    }
    if (normalized.accountId.trim().isEmpty) {
      throw ArgumentError('Account transaction accountId is required.');
    }
    if (normalized.debit == 0 && normalized.credit == 0) {
      throw ArgumentError('Account transaction amount is required.');
    }
    final index = _accountTransactionIndexForId(normalized.id);
    final synced = _withSyncMeta<AccountTransaction>(
      normalized,
      now,
      isCreate: index == -1,
    );
    final previous = index == -1 ? null : _accountTransactions[index];
    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      await sqliteDb.transaction(() async {
        if (previous != null && !previous.isDeleted) {
          await AccountingService.reverseEntryForReference(
            referenceType: previous.isCustomer
                ? 'customer_payment'
                : 'supplier_payment',
            referenceId: previous.id,
            reason: 'Account payment edited',
            createdBy: _actorName(),
            notifyChange: false,
            withinExistingTransaction: true,
          );
        }
        await _persistAccountTransactionInExistingTransaction(
          sqliteDb,
          synced,
        );
        await AccountingService.recordAccountPayment(
          synced,
          database: sqliteDb,
          withinExistingTransaction: true,
          notifyChange: false,
        );
      });
      _forgetSqliteDirtyBusinessRow(AppStore._accountTransactionsKey, synced.id);
      AccountingService.notifyCommittedMutation();
    } else {
      await _persistAccountTransactionSqliteFirst(synced);
      await AccountingService.recordAccountPayment(synced);
    }
    _putAccountTransactionAtIndex(
      synced,
      index == -1 ? _accountTransactions.length : index,
    );
    _replaceAccountTransactionInLedgerCache(
      previous: previous,
      current: synced,
    );
    _recordSyncChange(
      entityType: 'account_transaction',
      entityId: synced.id,
      operation: index == -1 ? 'upsert' : 'update',
      payload: synced.toJson(),
    );
    await _saveDirty(
      accountTransactions:
          !(LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null),
      sync: true,
    );
    notifyListeners();
  }

Future<void> deleteAccountTransaction(String id) async {
    requirePermission(AppPermission.accountingManage);
    final index = _accountTransactionIndexForId(id);
    if (index == -1) return;
    final now = DateTime.now();
    final deleted = _withSyncMeta<AccountTransaction>(
      _accountTransactions[index].copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    final previous = _accountTransactions[index];
    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      await sqliteDb.transaction(() async {
        await AccountingService.reverseEntryForReference(
          referenceType:
              deleted.isCustomer ? 'customer_payment' : 'supplier_payment',
          referenceId: deleted.id,
          reason: 'Account payment deleted',
          createdBy: _actorName(),
          notifyChange: false,
          withinExistingTransaction: true,
        );
        await _persistAccountTransactionInExistingTransaction(
          sqliteDb,
          deleted,
        );
      });
      _forgetSqliteDirtyBusinessRow(
        AppStore._accountTransactionsKey,
        deleted.id,
      );
      AccountingService.notifyCommittedMutation();
    } else {
      await _persistAccountTransactionSqliteFirst(deleted);
      await AccountingService.reverseEntryForReference(
        referenceType:
            deleted.isCustomer ? 'customer_payment' : 'supplier_payment',
        referenceId: deleted.id,
        reason: 'Account payment deleted',
        createdBy: _deviceId,
      );
    }
    _putAccountTransactionAtIndex(deleted, index);
    _replaceAccountTransactionInLedgerCache(
      previous: previous,
      current: deleted,
    );
    _recordSyncChange(
      entityType: 'account_transaction',
      entityId: id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _saveDirty(
      accountTransactions:
          !(LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null),
      sync: true,
    );
    notifyListeners();
  }

Future<void> _upsertAccountTransactionInternal(
    AccountTransaction transaction,
    DateTime now, {
    String operation = 'upsert',
  }) async {
    final normalized = transaction.copyWith(
      accountType: transaction.accountType.trim().toLowerCase(),
      accountName: transaction.accountName.trim(),
      currency: transaction.currency.trim().isEmpty
          ? 'USD'
          : transaction.currency.trim().toUpperCase(),
      paymentMethod: transaction.paymentMethod.trim(),
      debit: _safeAccountAmount(transaction.debit),
      credit: _safeAccountAmount(transaction.credit),
    );
    if (normalized.accountType != 'customer' &&
        normalized.accountType != 'supplier') {
      return;
    }
    if (normalized.accountId.trim().isEmpty) return;
    if (normalized.debit == 0 && normalized.credit == 0) return;
    final index = _accountTransactionIndexForId(normalized.id);
    final synced = _withSyncMeta<AccountTransaction>(
      normalized,
      now,
      isCreate: index == -1,
    );
    final previous = index == -1 ? null : _accountTransactions[index];

    // Financial account movements are SQLite-first: persist before RAM/UI.
    await _persistAccountTransactionSqliteFirst(synced);

    _putAccountTransactionAtIndex(
      synced,
      index == -1 ? _accountTransactions.length : index,
    );
    _replaceAccountTransactionInLedgerCache(
      previous: previous,
      current: synced,
    );
    _recordSyncChange(
      entityType: 'account_transaction',
      entityId: synced.id,
      operation: operation,
      payload: synced.toJson(),
    );
  }

Future<void> _recordPurchaseLedger(Purchase purchase, DateTime now) async {
    if (!purchase.isReceived ||
        purchase.isCancelled ||
        purchase.supplierId.trim().isEmpty) {
      return;
    }
    await _upsertAccountTransactionInternal(
      AccountTransaction(
        id: '${purchase.id}-purchase-invoice',
        accountType: 'supplier',
        accountId: purchase.supplierId,
        accountName: purchase.supplierName,
        date: purchase.date,
        type: 'purchaseInvoice',
        referenceId: purchase.id,
        referenceNo: purchase.purchaseNo,
        debit: 0,
        credit: purchase.subtotal,
        note: 'Purchase invoice ${purchase.purchaseNo}',
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: 'purchase_invoice',
    );
  }

Future<void> _recordPurchaseCancelLedger(
    Purchase purchase,
    DateTime now, {
    String reason = '',
    bool isReturn = false,
  }) async {
    if (purchase.supplierId.trim().isEmpty) return;
    // Reverse the amounts that were actually posted, rather than rebuilding
    // them from the current Purchase object. A purchase can have been migrated
    // after posting; using its current lines can otherwise create
    // a partial or oversized supplier reversal.
    final invoiceId = '${purchase.id}-purchase-invoice';
    final invoiceIndex = _accountTransactions.indexWhere(
      (transaction) => transaction.id == invoiceId,
    );
    if (invoiceIndex == -1) return;
    final total = _accountTransactions[invoiceIndex].credit;
    if (total <= 0) return;
    final note = reason.trim().isEmpty
        ? (isReturn
            ? 'Purchase return ${purchase.purchaseNo}'
            : 'Purchase cancelled')
        : reason.trim();
    await _upsertAccountTransactionInternal(
      AccountTransaction(
        id: isReturn
            ? '${purchase.id}-purchase-return'
            : '${purchase.id}-purchase-cancel',
        accountType: 'supplier',
        accountId: purchase.supplierId,
        accountName: purchase.supplierName,
        date: now,
        type: isReturn ? 'purchaseReturn' : 'cancel',
        referenceId: purchase.id,
        referenceNo: purchase.purchaseNo,
        debit: total,
        credit: 0,
        note: note,
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: isReturn ? 'purchase_return' : 'purchase_cancel',
    );
  }

Future<void> _recordSaleLedger(Sale sale, DateTime now) async {
    final accountId = sale.customerId.trim().isNotEmpty
        ? sale.customerId.trim()
        : sale.customerName.trim();
    if (accountId.isEmpty) return;
    await _upsertAccountTransactionInternal(
      AccountTransaction(
        id: '${sale.id}-sale-invoice',
        accountType: 'customer',
        accountId: accountId,
        accountName: sale.customerName,
        date: sale.date,
        type: 'saleInvoice',
        referenceId: sale.id,
        referenceNo: sale.invoiceNo,
        debit: sale.invoiceTotal,
        credit: 0,
        currency: sale.invoiceCurrency,
        note: 'Sale invoice ${sale.invoiceNo}',
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: 'sale_invoice',
    );
  }

Future<void> _recordSaleCancelLedger(
    Sale sale,
    DateTime now, {
    bool isReturn = false,
    String returnReferenceId = '',
  }) async {
    final accountId = sale.customerId.trim().isNotEmpty
        ? sale.customerId.trim()
        : sale.customerName.trim();
    if (accountId.isEmpty) return;
    final total = sale.invoiceTotal > 0
        ? sale.invoiceTotal
        : ((sale.items.fold<double>(0, (sum, item) => sum + item.lineTotal) -
                sale.discount)
            .clamp(0, double.infinity)
            .toDouble());
    if (total <= 0) return;
    await _upsertAccountTransactionInternal(
      AccountTransaction(
        id: isReturn
            ? (returnReferenceId.trim().isEmpty
                ? '${sale.id}-sale-return'
                : '${sale.id}-sale-return-${returnReferenceId.trim()}')
            : '${sale.id}-sale-cancel',
        accountType: 'customer',
        accountId: accountId,
        accountName: sale.customerName,
        date: now,
        type: isReturn ? 'saleReturn' : 'cancel',
        referenceId: sale.id,
        referenceNo: sale.invoiceNo,
        debit: 0,
        credit: total,
        currency: sale.invoiceCurrency,
        note: isReturn ? 'Sale return ${sale.invoiceNo}' : 'Sale cancelled',
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: isReturn ? 'sale_return' : 'sale_cancel',
    );
  }

Future<void> _reverseExpenseLedger(Expense expense, DateTime now,
      {String reason = ''}) async {
    final accountId = expense.id.trim();
    if (accountId.isEmpty || expense.amount <= 0) return;
    final accountName =
        expense.title.trim().isEmpty ? 'Expense' : expense.title.trim();
    final currency = expense.originalCurrency.trim().isEmpty
        ? 'USD'
        : expense.originalCurrency.trim().toUpperCase();
    final noteSuffix =
        reason.trim().isEmpty ? 'cancelled expense' : reason.trim();
    await _upsertAccountTransactionInternal(
      AccountTransaction(
        id: '${expense.id}-expense-debit-reversal',
        accountType: 'supplier',
        accountId: accountId,
        accountName: accountName,
        date: now,
        type: 'cancel',
        referenceId: expense.id,
        referenceNo: accountName,
        debit: 0,
        credit: expense.amount,
        currency: currency,
        note: 'Reverse expense debit for $noteSuffix',
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: 'expense_reverse_debit',
    );
    await _upsertAccountTransactionInternal(
      AccountTransaction(
        id: '${expense.id}-expense-credit-reversal',
        accountType: 'supplier',
        accountId: accountId,
        accountName: accountName,
        date: now,
        type: 'paymentReversal',
        paymentMethod: 'Cash',
        referenceId: expense.id,
        referenceNo: accountName,
        debit: expense.amount,
        credit: 0,
        currency: currency,
        note: 'Reverse expense payment for $noteSuffix',
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: 'expense_reverse_payment',
    );
  }

}
