part of 'app_store.dart';

extension _AppStoreSplitPersistenceSyncCorePart2 on AppStore {
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
    if (accountTransactions) {
      writes.add(persistRows(AppStore._accountTransactionsKey));
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
}
