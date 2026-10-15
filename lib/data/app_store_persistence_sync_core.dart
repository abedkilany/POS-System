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
}
