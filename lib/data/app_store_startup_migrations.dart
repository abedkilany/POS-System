part of 'app_store.dart';

extension _AppStoreSplitStartupMigrations on AppStore {
Future<void> initialize({bool hydrateHeavyData = true}) async {
    StartupTimingService.event('app_store.initialize.begin',
        category: 'app_store');
    await LocalDatabaseService.initialize();
    await _ensureDeviceId();

    final isWebStartup = kIsWeb;
    StartupTimingService.event(
      'app_store.startup_mode',
      category: 'app_store',
      details: isWebStartup ? 'web_persistent_store' : 'db_first',
    );

    if (!isWebStartup &&
        !LocalDatabaseService.isSqliteAuthoritative &&
        !LocalDatabaseService.isInMemoryStoreForTesting) {
      throw StateError('SQLite database is not ready for DB-first startup.');
    }

    await StartupTimingService.measure(
      isWebStartup
          ? 'app_store.web_startup_load'
          : 'app_store.db_first_startup_load',
      () async {
        // Keep boot lean: load only the data needed to decide the login gate
        // and restore the current session. Large business lists hydrate lazily
        // through the existing ensure*Loaded() entry points.
        _storeProfile = _loadStoreProfile();
        AccountingService.configureMoneyPolicy(_storeProfile);
        final rolesFuture = _loadRoles();
        final usersFuture = _loadUsers();
        _invoiceCounter = _loadInvoiceCounter();
        _purchaseCounter = _loadPurchaseCounter();
        _currentRole =
            LocalDatabaseService.getString(AppStore._currentRoleKey) ?? 'admin';
        _roles
          ..clear()
          ..addAll(await rolesFuture);
        _users
          ..clear()
          ..addAll(await usersFuture);
        await _ensureDefaultAdminUser();
        _rememberLogin =
            LocalDatabaseService.getString(AppStore._rememberLoginKey) == 'true';
        _restoreActiveUser();
        _appIdentity = _loadOrCreateAppIdentity();
        final initializedIdentity = appIdentity;
        final directSettings = DirectSyncSettings.load();
        final directBootstrapIncomplete = initializedIdentity.isClient &&
            initializedIdentity.activeSyncTransportNormalized == 'direct' &&
            directSettings.hasBootstrapConfiguration &&
            !directSettings.setupComplete;
        if (directBootstrapIncomplete && _activeUser != null) {
          // A failed first Snapshot must never restore a remembered local
          // session from partially imported data. Keep the device behind the
          // connection gate until a new Snapshot completes and is verified.
          _activeUser = null;
          _rememberLogin = false;
          await LocalDatabaseService.setString(AppStore._activeUserKey, '');
          await LocalDatabaseService.setString(
            AppStore._rememberLoginKey,
            'false',
          );
        }
        _syncSequence = _loadSyncSequence();

        if (!kIsWeb &&
            LocalDatabaseService.isSqliteAuthoritative &&
            !LocalDatabaseService.isSqliteDatabaseForTesting) {
          final db = SqliteMigrationManager.database;
          if (db != null) {
            try {
              final closure = await UnifiedBatchPhase4ClosureService(db).close(
                storeId: initializedIdentity.storeId,
                branchId: initializedIdentity.branchId,
                deviceId: _deviceId,
                allowNegativeStock: _storeProfile.allowNegativeStock,
              );
              debugPrint(
                'Unified Batch Phase 4 closed: ${closure.cutoversCreated} cutover(s) created, ${closure.productWarehousePairs} inventory pair(s) verified.',
              );
              await LocalDatabaseService.setString(
                AppStore._inventoryCostingMethodKey,
                InventoryCostingMethod.batch.code,
              );
            } catch (error, stackTrace) {
              // Keep the app available for reconciliation/repair, but never
              // re-enable legacy valuation methods after the Phase 4 build.
              debugPrint('Unified Batch Phase 4 closure requires attention: $error');
              debugPrint('$stackTrace');
              await LocalDatabaseService.setString(
                AppStore._inventoryCostingMethodKey,
                InventoryCostingMethod.batch.code,
              );
            }
            _inventoryCostingMethod = InventoryCostingMethod.batch;
          }
        }
      },
      category: 'app_store',
    );

    if (!kIsWeb &&
        LocalDatabaseService.isSqliteAuthoritative &&
        AccountingService.isAvailable) {
      try {
        await AccountingService.ensureInventoryAccountClassificationMigration();
        final reconciled = await AccountingService
            .reconcileInventoryAccountClassification(
          referenceContext: 'startup',
        );
        if (!reconciled) {
          debugPrint(
            'Inventory account classification reconciliation is blocked by a valuation mismatch.',
          );
        }
      } catch (error, stackTrace) {
        // Reclassification is deliberately conservative. A genuine
        // inventory/GL discrepancy must never be hidden by an automatic
        // gain/loss posting. Startup remains available for repair and a later
        // retry.
        debugPrint(
            'Inventory account reclassification was not applied: $error');
        debugPrint('$stackTrace');
      }
    }

    // In-memory tests exercise synchronous AppStore getters immediately after
    // initialize(). Production keeps the DB-first boot lean and hydrates heavy
    // collections lazily, while tests need an explicit deterministic boundary.
    if (hydrateHeavyData && LocalDatabaseService.isInMemoryStoreForTesting) {
      await ensureHeavyDataLoaded(failOnError: true);
    }

    _isReady = true;
    notifyListeners();
    StartupTimingService.event('app_store.ready', category: 'app_store');
  }

Future<String?> _loadEntityListJsonForStartup(String key) {
    if (LocalDatabaseService.isInMemoryStoreForTesting) {
      return Future<String?>.value(LocalDatabaseService.testingRawValue(key));
    }
    if (kIsWeb) {
      return Future<String?>.value(LocalDatabaseService.getString(key));
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return Future.value(null);
    if (BusinessSqliteStore.isTypedEntityKey(key)) {
      return BusinessSqliteStore.readEntityListJsonByKey(db, key);
    }
    if (SyncSqliteStore.isSqliteBackedKey(key)) {
      return SyncSqliteStore.readKeyJson(db, key);
    }
    return Future.value(null);
  }

Future<List<String>> _loadEntityListJsonBatchesForStartup(
    String key, {
    int batchSize = 100,
  }) {
    if (LocalDatabaseService.isInMemoryStoreForTesting) {
      final raw = LocalDatabaseService.testingRawValue(key);
      if (raw == null || raw.isEmpty) return Future.value(const <String>[]);
      return Future.value(<String>[raw]);
    }
    if (kIsWeb) {
      final raw = LocalDatabaseService.getString(key);
      if (raw == null || raw.isEmpty) return Future.value(const <String>[]);
      return Future.value(<String>[raw]);
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return Future.value(const <String>[]);
    if (BusinessSqliteStore.isTypedEntityKey(key)) {
      return BusinessSqliteStore.readEntityListJsonBatches(
        db,
        key,
        batchSize: batchSize,
      );
    }
    if (key == AppStore._syncChangesKey) {
      return SyncSqliteStore.readSyncChangesJsonBatches(
        db,
        batchSize: batchSize,
      );
    }
    if (key == AppStore._syncQueueKey) {
      return SyncSqliteStore.readSyncQueueJsonBatches(
        db,
        batchSize: batchSize,
      );
    }
    return Future.value(const <String>[]);
  }

Future<List<T>> _decodeDeferredList<T>(
      String key, T Function(Map<String, dynamic>) fromJson,
      {int? batchSize}) async {
    return StartupTimingService.measure(
      'app_store.decode.$key',
      () async {
        if (batchSize != null && batchSize > 0) {
          final batches = await _loadEntityListJsonBatchesForStartup(
            key,
            batchSize: batchSize,
          );
          if (batches.isNotEmpty) {
            final result = <T>[];
            for (final batchRaw in batches) {
              if (batchRaw.trim().isEmpty) {
                await Future<void>.delayed(Duration.zero);
                continue;
              }
              final decoded = batchRaw.length > 250000
                  ? await compute(_decodeJsonListPayload, batchRaw)
                  : _decodeJsonListPayload(batchRaw);
              for (final item in decoded) {
                result.add(fromJson(item));
              }
              await Future<void>.delayed(Duration.zero);
            }
            return result;
          }
        }
        final raw = await _loadEntityListJsonForStartup(key);
        if (raw == null || raw.isEmpty) return <T>[];
        final decoded = raw.length > 250000
            ? await compute(_decodeJsonListPayload, raw)
            : _decodeJsonListPayload(raw);
        final result = <T>[];
        const chunkSize = 750;
        for (var index = 0; index < decoded.length; index += 1) {
          result.add(fromJson(decoded[index]));
          if ((index + 1) % chunkSize == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
        return result;
      },
      category: 'app_store',
    );
  }

Future<List<T>> _loadTypedEntityList<T>(
    String key,
    Future<List<T>?> Function() typedLoader,
    T Function(Map<String, dynamic>) fromJson, {
    int? batchSize,
  }) async {
    final typed = await typedLoader();
    if (typed != null) return typed;
    if (LocalDatabaseService.isSqliteAuthoritative) return <T>[];
    return _decodeDeferredList<T>(
      key,
      fromJson,
      batchSize: batchSize,
    );
  }

Future<List<StockMovement>> _loadStockMovementsForStartup() async {
    final typed = await LocalDatabaseService.getStockMovementsFromSqlite();
    if (typed != null) return typed;
    if (LocalDatabaseService.isSqliteAuthoritative) {
      return <StockMovement>[];
    }
    return _decodeDeferredList<StockMovement>(
      AppStore._stockMovementsKey,
      StockMovement.fromJson,
      batchSize: 100,
    );
  }

Future<List<AccountTransaction>> _loadAccountTransactionsForStartup() async {
    final typed = await LocalDatabaseService.getAccountTransactionsFromSqlite();
    if (typed != null) return typed;
    return _decodeDeferredList<AccountTransaction>(
      AppStore._accountTransactionsKey,
      AccountTransaction.fromJson,
      batchSize: 100,
    );
  }


Future<void> _backfillPostedDocumentSnapshotsIfNeeded() async {
    if (!LocalDatabaseService.isSqliteAuthoritative) return;
    final db = SqliteMigrationManager.database;
    if (db == null) return;

    await db.transaction(() async {
      for (var index = 0; index < _sales.length; index += 1) {
        final sale = _sales[index];
        if (sale.isDeleted || sale.postedSnapshot != null) continue;
        Customer? customer;
        for (final candidate in _customers) {
          if (candidate.id == sale.customerId && !candidate.isDeleted) {
            customer = candidate;
            break;
          }
        }
        final snapshot = PostedDocumentSnapshotService.forSale(
          sale: sale,
          profile: _storeProfile,
          customer: customer,
          legacyBackfill: true,
        );
        final backfilledSale = sale.copyWith(postedSnapshot: snapshot);
        final updated = await db.customUpdate(
          "UPDATE sales SET posted_snapshot_json = ? WHERE id = ? AND posted_snapshot_json = ''",
          variables: <Variable<Object>>[
            Variable<String>(jsonEncode(snapshot.toJson())),
            Variable<String>(sale.id),
          ],
        );
        if (updated > 0) {
          _sales[index] = backfilledSale;
        }
      }

      for (var index = 0; index < _purchases.length; index += 1) {
        final purchase = _purchases[index];
        if (purchase.isDeleted || purchase.isDraft || purchase.postedSnapshot != null) {
          continue;
        }
        Supplier? supplier;
        for (final candidate in _suppliers) {
          if (candidate.id == purchase.supplierId && !candidate.isDeleted) {
            supplier = candidate;
            break;
          }
        }
        final snapshot = PostedDocumentSnapshotService.forPurchase(
          purchase: purchase,
          profile: _storeProfile,
          supplier: supplier,
          legacyBackfill: true,
        );
        final backfilledPurchase =
            purchase.copyWith(postedSnapshot: snapshot);
        final updated = await db.customUpdate(
          "UPDATE purchases SET posted_snapshot_json = ? WHERE id = ? AND posted_snapshot_json = ''",
          variables: <Variable<Object>>[
            Variable<String>(jsonEncode(snapshot.toJson())),
            Variable<String>(purchase.id),
          ],
        );
        if (updated > 0) {
          _purchases[index] = backfilledPurchase;
        }
      }
    });
}

Future<void> _loadDeferredStartupData() async {
    try {
      await StartupTimingService.measure(
        'app_store.core_deferred_startup',
        () async {
          await Future<void>.delayed(Duration.zero);
          final products = await _loadProductsForStartup();
          _products
            ..clear()
            ..addAll(products);
          await Future<void>.delayed(Duration.zero);

          final customers = await _loadCustomersForStartup();
          _customers
            ..clear()
            ..addAll(customers);
          await Future<void>.delayed(Duration.zero);

          final sales = await _loadSalesForStartup();
          _sales
            ..clear()
            ..addAll(sales);
          await Future<void>.delayed(Duration.zero);

          final saleQuotations = await _loadSaleQuotationsForStartup();
          _saleQuotations
            ..clear()
            ..addAll(saleQuotations);
          await Future<void>.delayed(Duration.zero);

          final deliveryNotes = await _loadDeliveryNotesForStartup();
          _deliveryNotes
            ..clear()
            ..addAll(deliveryNotes);
          await Future<void>.delayed(Duration.zero);

          final billsOfMaterials = await _loadBillsOfMaterialsForStartup();
          _billsOfMaterials
            ..clear()
            ..addAll(billsOfMaterials);
          await Future<void>.delayed(Duration.zero);

          final manufacturingOrders =
              await _loadManufacturingOrdersForStartup();
          _manufacturingOrders
            ..clear()
            ..addAll(manufacturingOrders);
          await Future<void>.delayed(Duration.zero);

          final suppliers = await _loadSuppliersForStartup();
          _suppliers
            ..clear()
            ..addAll(suppliers);
          await Future<void>.delayed(Duration.zero);

          final supplierProductPrices =
              await _loadSupplierProductPricesForStartup();
          _supplierProductPrices
            ..clear()
            ..addAll(supplierProductPrices);
          await Future<void>.delayed(Duration.zero);

          final priceLists = await _loadPriceListsForStartup();
          _priceLists
            ..clear()
            ..addAll(priceLists);
          await Future<void>.delayed(Duration.zero);

          final productPrices = await _loadProductPricesForStartup();
          _productPrices
            ..clear()
            ..addAll(productPrices);
          await Future<void>.delayed(Duration.zero);

          final productPriceOverrides =
              await _loadProductPriceOverridesForStartup();
          _productPriceOverrides
            ..clear()
            ..addAll(productPriceOverrides);
          await Future<void>.delayed(Duration.zero);

          final productCosts = await _loadProductCostsForStartup();
          _productCosts
            ..clear()
            ..addAll(productCosts);
          _rebuildProductPricingLookupCaches();
          await Future<void>.delayed(Duration.zero);

          final costingMethodHistory =
              await _loadCostingMethodHistoryForStartup();
          _costingMethodHistory
            ..clear()
            ..addAll(costingMethodHistory);
          await Future<void>.delayed(Duration.zero);

          final inventoryCostLayers =
              await _loadInventoryCostLayersForStartup();
          _inventoryCostLayers
            ..clear()
            ..addAll(inventoryCostLayers);
          _rebuildInventoryCostLayerLookupCache();
          _inventoryCostingMethod = _runtimeInventoryCostingMethod(
            InventoryCostingMethodJson.fromCode(
              LocalDatabaseService.getString(AppStore._inventoryCostingMethodKey),
            ),
          );
          await Future<void>.delayed(Duration.zero);

          final expenses = await _loadExpensesForStartup();
          _expenses
            ..clear()
            ..addAll(expenses);
          await Future<void>.delayed(Duration.zero);

          final purchases = await _loadPurchasesForStartup();
          _purchases
            ..clear()
            ..addAll(purchases);
          await _backfillPostedDocumentSnapshotsIfNeeded();
          await Future<void>.delayed(Duration.zero);

          final stockMovements = await _loadStockMovementsForStartup();
          _stockMovements
            ..clear()
            ..addAll(stockMovements);
          await Future<void>.delayed(Duration.zero);

          final inventoryCounts = await _loadInventoryCountsForStartup();
          _inventoryCounts
            ..clear()
            ..addAll(inventoryCounts);
          await Future<void>.delayed(Duration.zero);

          final warehouses = await _loadWarehousesForStartup();
          _warehouses
            ..clear()
            ..addAll(warehouses);
          await Future<void>.delayed(Duration.zero);

          _ensureDefaultPriceLists();
          _ensureDefaultProductPriceEntries();
          _ensureProductCostEntries();
          _ensureCostingMethodHistory();
          _ensureDefaultWarehouse();

          _normalizeCustomers();
          _ensureCatalogDefaults();
          _rebuildMutableEntityIndexes();
          _touchPurchasesData();
          _touchExpensesData();
          _invoiceCounter = _loadInvoiceCounter();
          _purchaseCounter = _loadPurchaseCounter();
          notifyListeners();
        },
        category: 'app_store',
      );
    } catch (error, stackTrace) {
      debugPrint('Deferred startup data load failed: $error');
      debugPrint('$stackTrace');
    }
  }

Future<void> _loadLedgerDeferredStartupData() async {
    try {
      await StartupTimingService.measure(
        'app_store.ledger_deferred_startup',
        () async {
          await Future<void>.delayed(Duration.zero);
          final accountTransactions =
              await _loadAccountTransactionsForStartup();
          _accountTransactions
            ..clear()
            ..addAll(accountTransactions);
          _invalidateAccountLedgerCache();
          _touchDataRevisions(accountTransactions: true);
          notifyListeners();
        },
        category: 'app_store',
      );
    } catch (error, stackTrace) {
      debugPrint('Ledger startup data load failed: $error');
      debugPrint('$stackTrace');
    }
  }

Future<void> _loadSyncDeferredStartupData() async {
    try {
      await StartupTimingService.measure(
        'app_store.sync_deferred_startup',
        () async {
          if (!LocalDatabaseService.isInMemoryStoreForTesting) {
            await Future<void>.delayed(Duration.zero);
          }
          final syncChanges = await _decodeDeferredList<SyncChange>(
            AppStore._syncChangesKey,
            SyncChange.fromJson,
            batchSize: 100,
          );
          _syncChanges
            ..clear()
            ..addAll(syncChanges);
          if (!LocalDatabaseService.isInMemoryStoreForTesting) {
            await Future<void>.delayed(Duration.zero);
          }

          final syncQueue = await _decodeDeferredList<SyncQueueItem>(
            AppStore._syncQueueKey,
            SyncQueueItem.fromJson,
            batchSize: 100,
          );
          _syncQueue
            ..clear()
            ..addAll(syncQueue);
          await _reconcileUnsyncedChangesWithQueue();
          notifyListeners();
        },
        category: 'app_store',
      );
    } catch (error, stackTrace) {
      debugPrint('Sync startup data load failed: $error');
      debugPrint('$stackTrace');
    }
  }

Future<void> refreshAccountTransactionsFromSqlite() async {
    await refreshAfterDatabaseChange(AppStore._accountTransactionsKey);
  }

Future<void> refreshSalesProductData() async {
    await refreshAfterDatabaseChange(AppStore._productsKey);
    await refreshAfterDatabaseChange(AppStore._priceListsKey);
    await refreshAfterDatabaseChange(AppStore._productPricesKey);
    await refreshAfterDatabaseChange(AppStore._productPriceOverridesKey);
  }

Future<void> refreshAfterDatabaseChange(String key) async {
    try {
      switch (key) {
        case AppStore._appIdentityKey:
          _appIdentity = _loadOrCreateAppIdentity();
          break;

        case AppStore._storeProfileKey:
          _storeProfile = _loadStoreProfile();
          AccountingService.configureMoneyPolicy(_storeProfile);
          _touchDataRevisions(storeProfile: true);
          break;

        case AppStore._productsKey:
          _products
            ..clear()
            ..addAll(await _loadProductsForStartup());
          _ensureCatalogDefaults();
          _touchDataRevisions(products: true);
          break;

        case AppStore._customersKey:
          _customers
            ..clear()
            ..addAll(await _loadCustomersForStartup());
          _normalizeCustomers();
          _touchDataRevisions(customers: true);
          break;

        case AppStore._salesKey:
          _sales
            ..clear()
            ..addAll(await _loadSalesForStartup());
          _invoiceCounter = _loadInvoiceCounter();
          _touchDataRevisions(sales: true);
          break;

        case AppStore._saleQuotationsKey:
          _saleQuotations
            ..clear()
            ..addAll(await _loadSaleQuotationsForStartup());
          break;

        case AppStore._deliveryNotesKey:
          _deliveryNotes
            ..clear()
            ..addAll(await _loadDeliveryNotesForStartup());
          _touchDataRevisions(deliveryNotes: true);
          break;

        case AppStore._billsOfMaterialsKey:
          _billsOfMaterials
            ..clear()
            ..addAll(await _loadBillsOfMaterialsForStartup());
          break;

        case AppStore._manufacturingOrdersKey:
          _manufacturingOrders
            ..clear()
            ..addAll(await _loadManufacturingOrdersForStartup());
          break;

        case AppStore._suppliersKey:
          _suppliers
            ..clear()
            ..addAll(await _loadSuppliersForStartup());
          _touchDataRevisions(suppliers: true);
          break;

        case AppStore._supplierProductPricesKey:
          _supplierProductPrices
            ..clear()
            ..addAll(await _loadSupplierProductPricesForStartup());
          _touchDataRevisions(supplierProductPrices: true);
          break;

        case AppStore._priceListsKey:
          _priceLists
            ..clear()
            ..addAll(await _loadPriceListsForStartup());
          _ensureDefaultPriceLists();
          _rebuildProductPricingLookupCaches();
          _touchDataRevisions(products: true);
          break;

        case AppStore._productPricesKey:
          _productPrices
            ..clear()
            ..addAll(await _loadProductPricesForStartup());
          _ensureDefaultProductPriceEntries();
          _rebuildProductPricingLookupCaches();
          _touchDataRevisions(products: true);
          break;

        case AppStore._productPriceOverridesKey:
          _productPriceOverrides
            ..clear()
            ..addAll(await _loadProductPriceOverridesForStartup());
          _rebuildProductPricingLookupCaches();
          _touchDataRevisions(products: true);
          break;

        case AppStore._productCostsKey:
          _productCosts
            ..clear()
            ..addAll(await _loadProductCostsForStartup());
          _rebuildProductPricingLookupCaches();
          _touchDataRevisions(products: true);
          break;

        case AppStore._costingMethodHistoryKey:
          _costingMethodHistory
            ..clear()
            ..addAll(await _loadCostingMethodHistoryForStartup());
          _touchDataRevisions(products: true);
          break;

        case AppStore._inventoryCostLayersKey:
          _inventoryCostLayers
            ..clear()
            ..addAll(await _loadInventoryCostLayersForStartup());
          _rebuildInventoryCostLayerLookupCache();
          _touchDataRevisions(products: true);
          break;

        case AppStore._expensesKey:
          _expenses
            ..clear()
            ..addAll(await _loadExpensesForStartup());
          _rebuildExpenseIndexes();
          _touchExpensesData();
          break;

        case AppStore._purchasesKey:
          _purchases
            ..clear()
            ..addAll(await _loadPurchasesForStartup());
          _rebuildPurchaseIndexes();
          _touchPurchasesData();
          _purchaseCounter = _loadPurchaseCounter();
          break;

        case AppStore._stockMovementsKey:
          _stockMovements
            ..clear()
            ..addAll(await _loadStockMovementsForStartup());
          _touchDataRevisions(stockMovements: true);
          break;

        case AppStore._inventoryCountsKey:
          _inventoryCounts
            ..clear()
            ..addAll(await _loadInventoryCountsForStartup());
          _touchDataRevisions(inventoryCounts: true);
          break;

        case AppStore._warehousesKey:
          _warehouses
            ..clear()
            ..addAll(await _loadWarehousesForStartup());
          _ensureDefaultWarehouse();
          _touchDataRevisions(warehouses: true);
          break;

        case AppStore._accountTransactionsKey:
          _accountTransactions
            ..clear()
            ..addAll(await _loadAccountTransactionsForStartup());
          _invalidateAccountLedgerCache();
          _touchDataRevisions(accountTransactions: true);
          break;

        case AppStore._categoriesKey:
          _categories
            ..clear()
            ..addAll(await _loadCatalogItemsForStartup(AppStore._categoriesKey));
          _ensureCatalogDefaults();
          _touchDataRevisions(products: true);
          break;

        case AppStore._brandsKey:
          _brands
            ..clear()
            ..addAll(await _loadCatalogItemsForStartup(AppStore._brandsKey));
          _ensureCatalogDefaults();
          _touchDataRevisions(products: true);
          break;

        case AppStore._unitsKey:
          _units
            ..clear()
            ..addAll(await _loadCatalogItemsForStartup(AppStore._unitsKey));
          _ensureCatalogDefaults();
          _touchDataRevisions(products: true);
          break;

        case AppStore._rolesKey:
        case AppStore._usersKey:
        case AppStore._activeUserKey:
        case AppStore._rememberLoginKey:
          _roles
            ..clear()
            ..addAll(await _loadRoles());
          _users
            ..clear()
            ..addAll(await _loadUsers());
          _rememberLogin =
              LocalDatabaseService.getString(AppStore._rememberLoginKey) == 'true';
          _activeUser = null;
          _restoreActiveUser();
          break;

        case AppStore._syncChangesKey:
          _syncChanges
            ..clear()
            ..addAll(await _loadSyncChanges());
          _syncSequence = _loadSyncSequence();
          break;

        case AppStore._syncQueueKey:
          _syncQueue
            ..clear()
            ..addAll(_loadSyncQueue());
          break;

        case AppStore._invoiceCounterKey:
          _invoiceCounter = _loadInvoiceCounter();
          break;

        case AppStore._purchaseCounterKey:
          _purchaseCounter = _loadPurchaseCounter();
          break;

        case AppStore._syncSequenceKey:
          _syncSequence = _loadSyncSequence();
          break;

        default:
          await reloadAllAfterDatabaseChange();
          return;
      }

      _rebuildMutableEntityIndexes();
      _rebuildProductPricingLookupCaches();
      _invalidateDerivedDataCaches();
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('Database admin refresh failed for $key: $error');
      debugPrint('$stackTrace');
      await reloadAllAfterDatabaseChange();
    }
  }

Future<void> reloadAllAfterDatabaseChange() async {
    final sessionBeforeReload = _activeUser;
    _appIdentity = _loadOrCreateAppIdentity();
    _storeProfile = _loadStoreProfile();
    AccountingService.configureMoneyPolicy(_storeProfile);
    _products
      ..clear()
      ..addAll(await _loadProductsForStartup());
    _customers
      ..clear()
      ..addAll(await _loadCustomersForStartup());
    _sales
      ..clear()
      ..addAll(await _loadSalesForStartup());
    _saleQuotations
      ..clear()
      ..addAll(await _loadSaleQuotationsForStartup());
    _deliveryNotes
      ..clear()
      ..addAll(await _loadDeliveryNotesForStartup());
    _billsOfMaterials
      ..clear()
      ..addAll(await _loadBillsOfMaterialsForStartup());
    _manufacturingOrders
      ..clear()
      ..addAll(await _loadManufacturingOrdersForStartup());
    _suppliers
      ..clear()
      ..addAll(await _loadSuppliersForStartup());
    _supplierProductPrices
      ..clear()
      ..addAll(await _loadSupplierProductPricesForStartup());
    _expenses
      ..clear()
      ..addAll(await _loadExpensesForStartup());
    _purchases
      ..clear()
      ..addAll(await _loadPurchasesForStartup());
    _stockMovements
      ..clear()
      ..addAll(await _loadStockMovementsForStartup());
    _inventoryCounts
      ..clear()
      ..addAll(await _loadInventoryCountsForStartup());
    _warehouses
      ..clear()
      ..addAll(await _loadWarehousesForStartup());
    _priceLists
      ..clear()
      ..addAll(await _loadPriceListsForStartup());
    _productPrices
      ..clear()
      ..addAll(await _loadProductPricesForStartup());
    _productPriceOverrides
      ..clear()
      ..addAll(await _loadProductPriceOverridesForStartup());
    _productCosts
      ..clear()
      ..addAll(await _loadProductCostsForStartup());
    _costingMethodHistory
      ..clear()
      ..addAll(await _loadCostingMethodHistoryForStartup());
    _inventoryCostLayers
      ..clear()
      ..addAll(await _loadInventoryCostLayersForStartup());
    _rebuildInventoryCostLayerLookupCache();
    _accountTransactions
      ..clear()
      ..addAll(await _loadAccountTransactionsForStartup());
    _categories
      ..clear()
      ..addAll(await _loadCatalogItemsForStartup(AppStore._categoriesKey));
    _brands
      ..clear()
      ..addAll(await _loadCatalogItemsForStartup(AppStore._brandsKey));
    _units
      ..clear()
      ..addAll(await _loadCatalogItemsForStartup(AppStore._unitsKey));
    _roles
      ..clear()
      ..addAll(await _loadRoles());
    _users
      ..clear()
      ..addAll(await _loadUsers());
    _syncChanges
      ..clear()
      ..addAll(await _loadSyncChanges());
    _syncQueue
      ..clear()
      ..addAll(_loadSyncQueue());
    await _reconcileUnsyncedChangesWithQueue();

    _rememberLogin =
        LocalDatabaseService.getString(AppStore._rememberLoginKey) == 'true';
    _activeUser = null;
    _restoreActiveUser();
    if (_activeUser == null && sessionBeforeReload != null) {
      for (final user in _users) {
        if (user.id == sessionBeforeReload.id && user.isActive) {
          _activeUser = user;
          break;
        }
      }
    }
    _normalizeCustomers();
    _ensureCatalogDefaults();
    _ensureDefaultWarehouse();
    _invoiceCounter = _loadInvoiceCounter();
    _purchaseCounter = _loadPurchaseCounter();
    _syncSequence = _loadSyncSequence();
    _rebuildMutableEntityIndexes();
    _rebuildProductPricingLookupCaches();
    _touchDataRevisions(
      products: true,
      customers: true,
      sales: true,
      deliveryNotes: true,
      suppliers: true,
      supplierProductPrices: true,
      expenses: true,
      purchases: true,
      stockMovements: true,
      inventoryCounts: true,
      warehouses: true,
      accountTransactions: true,
      storeProfile: true,
    );
    _invalidateAccountLedgerCache();
    _invalidateDerivedDataCaches();
    notifyListeners();
  }

Future<void> _ensureDeviceId() async {
    final existing = LocalDatabaseService.getString(AppStore._deviceIdKey);
    if (existing != null && existing.trim().isNotEmpty) {
      _deviceId = _normalizeGeneratedId(existing.trim(), fallbackPrefix: 'DV');
      if (_deviceId != existing.trim()) {
        await LocalDatabaseService.setString(AppStore._deviceIdKey, _deviceId);
      }
      return;
    }
    _deviceId = _generatePrefixedId('DV');
    await LocalDatabaseService.setString(AppStore._deviceIdKey, _deviceId);
  }

String _generatePrefixedId(String prefix) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final body = List<String>.generate(
      6,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
    return '${prefix.toUpperCase()}-$body';
  }

String _normalizeGeneratedId(String value, {required String fallbackPrefix}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return _generatePrefixedId(fallbackPrefix);
    final parts = trimmed.split('-');
    if (parts.length == 2) {
      final rawPrefix = parts.first.toUpperCase();
      final prefix = rawPrefix == 'DEV' || rawPrefix == 'Dev'.toUpperCase()
          ? 'DV'
          : rawPrefix;
      final body = parts.last.toUpperCase();
      return '$prefix-$body';
    }
    return trimmed.toUpperCase();
  }

void _ensureCatalogDefaults() {
    if (_categories.isEmpty) {
      _categories.add(
        CatalogItem(
          id: 'cat_general',
          nameEn: 'General',
          nameAr: 'عام',
          code: 'General',
        ),
      );
    }
    if (_brands.isEmpty) {
      _brands.add(
        CatalogItem(
          id: 'brand_generic',
          nameEn: 'Generic',
          nameAr: 'عام',
          code: 'Generic',
        ),
      );
    }
    if (_units.isEmpty) {
      _units.addAll([
        CatalogItem(
          id: 'unit_pcs',
          nameEn: 'Piece',
          nameAr: 'قطعة',
          code: 'pcs',
        ),
        CatalogItem(id: 'unit_box', nameEn: 'Box', nameAr: 'علبة', code: 'box'),
        CatalogItem(
          id: 'unit_pack',
          nameEn: 'Pack',
          nameAr: 'باكيت',
          code: 'pack',
        ),
        CatalogItem(
          id: 'unit_kg',
          nameEn: 'Kilogram',
          nameAr: 'كيلوغرام',
          code: 'kg',
        ),
        CatalogItem(id: 'unit_g', nameEn: 'Gram', nameAr: 'غرام', code: 'g'),
        CatalogItem(id: 'unit_l', nameEn: 'Liter', nameAr: 'ليتر', code: 'L'),
        CatalogItem(
          id: 'unit_ml',
          nameEn: 'Milliliter',
          nameAr: 'ميليلتر',
          code: 'ml',
        ),
        CatalogItem(id: 'unit_m', nameEn: 'Meter', nameAr: 'متر', code: 'm'),
      ]);
    }
    _seedCatalogFromProducts(
      _categories,
      _products.map((item) => item.category),
    );
    _seedCatalogFromProducts(_brands, _products.map((item) => item.brand));
    _seedCatalogFromProducts(_units, _products.map((item) => item.unit));
  }

void _seedCatalogFromProducts(
    List<CatalogItem> target,
    Iterable<String> values,
  ) {
    final used = target.map((item) => item.nameEn.trim().toLowerCase()).toSet();
    for (final raw in values) {
      final value = raw.trim();
      if (value.isEmpty || used.contains(value.toLowerCase())) continue;
      target.add(
        CatalogItem(
          id: DateTime.now().microsecondsSinceEpoch.toString() +
              target.length.toString(),
          nameEn: value,
          nameAr: '',
          code: value,
        ),
      );
      used.add(value.toLowerCase());
    }
  }

Future<List<SyncChange>> _loadSyncChanges() async {
    final db = SqliteMigrationManager.database;
    final raw = kIsWeb
        ? LocalDatabaseService.getString(AppStore._syncChangesKey)
        : db == null
            ? null
            : await SyncSqliteStore.readSyncChangesJson(db);
    if (raw == null || raw.isEmpty) return <SyncChange>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map(
          (item) => SyncChange.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

int _loadSyncSequence() {
    final stored =
        int.tryParse(LocalDatabaseService.getString(AppStore._syncSequenceKey) ?? '') ??
            0;
    final highest = _syncChanges.fold<int>(
      0,
      (value, change) => change.sequence > value ? change.sequence : value,
    );
    return stored > highest ? stored : highest;
  }

int _nextSyncSequence() {
    _syncSequence += 1;
    return _syncSequence;
  }

String _newSyncEnvelopeId(DateTime now, String prefix) {
    final safeDevice = _deviceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return '${prefix}_${safeDevice}_${now.microsecondsSinceEpoch}_${_syncChanges.length}_$_syncSequence';
  }

Map<String, dynamic> _syncV2MetaOf(SyncChange change) {
    return Map<String, dynamic>.from(
      change.payload['_syncV2'] as Map? ?? const {},
    );
  }

String _syncMetaString(SyncChange change, String key) {
    final value = _syncV2MetaOf(change)[key];
    return value == null ? '' : value.toString();
  }

bool _isReplayOrDuplicateSyncEvent(
    SyncChange change, {
    required Set<String> existingEnvelopeIds,
    required Set<String> existingEventIds,
    required Set<String> acceptedSourceCommandIds,
    required int lastAppliedSequence,
  }) {
    if (existingEnvelopeIds.contains(change.id)) return true;

    final meta = _syncV2MetaOf(change);
    final eventId = (meta['eventId'] ?? '').toString();
    if (eventId.isNotEmpty && existingEventIds.contains(eventId)) return true;

    // Client drafts can arrive more than once when the ACK is lost or the
    // request times out.  Older Host events stored the original draft id in
    // `sourceCommandId`, while newer envelopes also carry a stable `requestId`.
    // Treat both as idempotency keys so a retry is ACKed/skipped instead of
    // being re-applied as a fresh authoritative Host event.
    final sourceCommandId = (meta['sourceCommandId'] ?? '').toString();
    final requestId = (meta['requestId'] ?? '').toString();
    if ((sourceCommandId.isNotEmpty &&
            acceptedSourceCommandIds.contains(sourceCommandId)) ||
        (requestId.isNotEmpty &&
            acceptedSourceCommandIds.contains(requestId)) ||
        acceptedSourceCommandIds.contains(change.id)) {
      return true;
    }

    // Host sequence is the authoritative ordering guard. If this device has
    // already applied a newer/equal Host sequence, the incoming event is a
    // replay from an old cursor/page and must not be applied again.
    if (change.sequence > 0 &&
        lastAppliedSequence > 0 &&
        change.sequence <= lastAppliedSequence) {
      return true;
    }

    return false;
  }

String? validateClientDraftForHostAcceptance(SyncChange change) {
    if (change.entityType == 'system' &&
        change.operation == 'reset_store_data') {
      return 'Reset data can only be initiated on the Host device.';
    }
    if (change.operation == 'delete') return null;
    final p = change.payload;
    switch (change.entityType) {
      case 'product':
        final code = (p['code'] ?? '').toString().trim().toLowerCase();
        final barcode = (p['barcode'] ?? '').toString().trim().toLowerCase();
        if (code.isEmpty) return null;
        final duplicate = _products.any((item) {
          if (item.id == change.entityId || item.isDeleted) return false;
          final sameCode = item.code.trim().toLowerCase() == code;
          final sameBarcode = barcode.isNotEmpty &&
              item.barcode.trim().toLowerCase() == barcode;
          return sameCode || sameBarcode;
        });
        if (duplicate) {
          return 'Product code or barcode already exists on the Host.';
        }
        return null;
      case 'sale':
        final invoiceNo = (p['invoiceNo'] ?? p['invoice_no'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (invoiceNo.isEmpty) return null;
        final duplicate = _sales.any(
          (item) =>
              item.id != change.entityId &&
              !item.isDeleted &&
              item.invoiceNo.trim().toLowerCase() == invoiceNo,
        );
        if (duplicate) return 'Invoice number already exists on the Host.';
        return null;
    }
    return null;
  }

Future<void> clearPendingSyncQueue({bool notify = true}) async {
    _syncQueue.clear();
    await _saveSyncStateOnly();
    if (notify) notifyListeners();
  }

List<SyncQueueItem> _loadSyncQueue() {
    final raw = LocalDatabaseService.getString(AppStore._syncQueueKey);
    if (raw == null) return <SyncQueueItem>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map(
          (item) =>
              SyncQueueItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

int _loadInvoiceCounter() {
    final raw = LocalDatabaseService.getString(AppStore._invoiceCounterKey);
    final stored = int.tryParse(raw ?? '') ?? 0;
    final highestInvoiceNo = _sales.fold<int>(0, (highest, sale) {
      final invoiceNumber = _invoiceSequenceFromNo(sale.invoiceNo);
      return invoiceNumber > highest ? invoiceNumber : highest;
    });
    return stored > highestInvoiceNo ? stored : highestInvoiceNo;
  }

Future<void> _runDataMigrationsIfNeeded() async {
    final current =
        int.tryParse(LocalDatabaseService.getString(AppStore._schemaVersionKey) ?? '') ??
            0;
    if (current >= 17) return;

    if (current < 7) {
      // Version 7 captures unit cost on every historical sale item when possible
      // and initializes a durable invoice counter.
      for (var saleIndex = 0; saleIndex < _sales.length; saleIndex++) {
        final sale = _sales[saleIndex];
        final migratedItems = sale.items.map((item) {
          if (item.unitCost > 0) return item;
          final product = _findProductById(item.productId);
          return SaleItem(
            productId: item.productId,
            productName: item.productName,
            unitPrice: item.unitPrice,
            quantity: item.quantity,
            unitName: item.unitName,
            baseQuantity: item.effectiveBaseQuantity,
            conversionToBase: item.conversionToBase,
            unitCost: product?.usdCost ?? 0,
          );
        }).toList();
        _sales[saleIndex] = Sale(
          id: sale.id,
          invoiceNo: sale.invoiceNo,
          customerName: sale.customerName,
          date: sale.date,
          status: sale.status,
          items: migratedItems,
          discount: sale.discount,
        );
      }
    }

    if (current < 8) {
      _normalizeProductCodes();
    }

    if (current < 9) {
      _prepareExistingDataForSync();
    }

    if (current < 11) {
      _prepareExistingDataForSync();
    }

    if (current < 13) {
      _normalizeProductCostReferences();
    }

    if (current < 14 && _supplierProductPrices.isEmpty) {
      _seedSupplierProductPricesFromPurchaseHistory();
    }

    if (current < 15) {
      _seedSupplierProductPricesFromLegacyProductSuppliers(
        recordSyncChanges: true,
      );
    }

    if (current < 15 &&
        LocalDatabaseService.getString(AppStore._supplierProductPricesKey) == null) {
      await LocalDatabaseService.setString(
        AppStore._supplierProductPricesKey,
        jsonEncode(
          _supplierProductPrices.map((item) => item.toJson()).toList(),
        ),
      );
    }

    _appIdentity = _loadOrCreateAppIdentity();
    _syncSequence = _loadSyncSequence();

    await LocalDatabaseService.setString(
      AppStore._syncSequenceKey,
      _syncSequence.toString(),
    );
    await LocalDatabaseService.setString(AppStore._schemaVersionKey, '17');
    await LocalDatabaseService.setString(
      AppStore._invoiceCounterKey,
      _invoiceCounter.toString(),
    );
    await LocalDatabaseService.setString(
      AppStore._purchaseCounterKey,
      _purchaseCounter.toString(),
    );
    await _saveAll();
  }

double _safeUsdCost(Product product) {
    final usdCost = product.usdCost.isFinite && product.usdCost >= 0
        ? product.usdCost
        : 0.0;
    final originalCost =
        product.originalCost.isFinite && product.originalCost >= 0
            ? product.originalCost
            : 0.0;
    final rawCost =
        product.cost.isFinite && product.cost >= 0 ? product.cost : 0.0;
    if (product.costCurrency.toUpperCase() != 'LBP') {
      return usdCost;
    }

    final sourceLbpCost =
        originalCost > 0 ? originalCost : (rawCost > 0 ? rawCost : usdCost);
    final expectedUsdCost = toUsdReferencePrice(
      sourceLbpCost,
      'LBP',
      storeProfile,
    );
    if (expectedUsdCost <= 0) return usdCost;

    // Legacy records sometimes stored the LBP cost directly in usdCost/cost.
    // When costCurrency is LBP, the USD reference must be originalCost / rate.
    final usdLooksLikeLbp = usdCost > expectedUsdCost * 10 || usdCost > 1000;
    return usdLooksLikeLbp ? expectedUsdCost : usdCost;
  }

void _normalizeProductCostReferences() {
    for (var index = 0; index < _products.length; index++) {
      final product = _products[index];
      final normalizedUsdCost = _safeUsdCost(product);
      if ((normalizedUsdCost - product.usdCost).abs() < 0.000001 &&
          (normalizedUsdCost - product.cost).abs() < 0.000001) {
        continue;
      }
      _products[index] = product.copyWith(
        cost: normalizedUsdCost,
        usdCost: normalizedUsdCost,
      );
    }
  }

void _prepareExistingDataForSync() {
    final now = DateTime.now();
    for (var index = 0; index < _products.length; index++) {
      final item = _products[index];
      _products[index] = item.copyWith(
        createdAt:
            item.createdAt.millisecondsSinceEpoch == 0 ? now : item.createdAt,
        updatedAt:
            item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
        deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
        syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
        storeId: item.storeId.isEmpty ? appIdentity.storeId : item.storeId,
        branchId: item.branchId.isEmpty ? appIdentity.branchId : item.branchId,
        version: item.version <= 0 ? 1 : item.version,
        lastModifiedByDeviceId: item.lastModifiedByDeviceId.isEmpty
            ? (item.deviceId.isEmpty ? _deviceId : item.deviceId)
            : item.lastModifiedByDeviceId,
      );
    }
    for (var index = 0; index < _customers.length; index++) {
      final item = _customers[index];
      _customers[index] = item.copyWith(
        createdAt:
            item.createdAt.millisecondsSinceEpoch == 0 ? now : item.createdAt,
        updatedAt:
            item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
        deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
        syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
        storeId: item.storeId.isEmpty ? appIdentity.storeId : item.storeId,
        branchId: item.branchId.isEmpty ? appIdentity.branchId : item.branchId,
        version: item.version <= 0 ? 1 : item.version,
        lastModifiedByDeviceId: item.lastModifiedByDeviceId.isEmpty
            ? (item.deviceId.isEmpty ? _deviceId : item.deviceId)
            : item.lastModifiedByDeviceId,
      );
    }
    for (var index = 0; index < _sales.length; index++) {
      final item = _sales[index];
      _sales[index] = item.copyWith(
        createdAt: item.createdAt.millisecondsSinceEpoch == 0
            ? item.date
            : item.createdAt,
        updatedAt:
            item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
        deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
        syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
        storeId: item.storeId.isEmpty ? appIdentity.storeId : item.storeId,
        branchId: item.branchId.isEmpty ? appIdentity.branchId : item.branchId,
        version: item.version <= 0 ? 1 : item.version,
        lastModifiedByDeviceId: item.lastModifiedByDeviceId.isEmpty
            ? (item.deviceId.isEmpty ? _deviceId : item.deviceId)
            : item.lastModifiedByDeviceId,
      );
    }
    for (var index = 0; index < _suppliers.length; index++) {
      final item = _suppliers[index];
      _suppliers[index] = item.copyWith(
        createdAt:
            item.createdAt.millisecondsSinceEpoch == 0 ? now : item.createdAt,
        updatedAt:
            item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
        deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
        syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
        storeId: item.storeId.isEmpty ? appIdentity.storeId : item.storeId,
        branchId: item.branchId.isEmpty ? appIdentity.branchId : item.branchId,
        version: item.version <= 0 ? 1 : item.version,
        lastModifiedByDeviceId: item.lastModifiedByDeviceId.isEmpty
            ? (item.deviceId.isEmpty ? _deviceId : item.deviceId)
            : item.lastModifiedByDeviceId,
      );
    }
    for (var index = 0; index < _categories.length; index++) {
      _categories[index] = _prepareCatalogItemForSync(_categories[index], now);
    }
    for (var index = 0; index < _brands.length; index++) {
      _brands[index] = _prepareCatalogItemForSync(_brands[index], now);
    }
    for (var index = 0; index < _units.length; index++) {
      _units[index] = _prepareCatalogItemForSync(_units[index], now);
    }
    for (var index = 0; index < _expenses.length; index++) {
      final item = _expenses[index];
      _expenses[index] = item.copyWith(
        createdAt: item.createdAt.millisecondsSinceEpoch == 0
            ? item.date
            : item.createdAt,
        updatedAt:
            item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
        deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
        syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
        storeId: item.storeId.isEmpty ? appIdentity.storeId : item.storeId,
        branchId: item.branchId.isEmpty ? appIdentity.branchId : item.branchId,
        version: item.version <= 0 ? 1 : item.version,
        lastModifiedByDeviceId: item.lastModifiedByDeviceId.isEmpty
            ? (item.deviceId.isEmpty ? _deviceId : item.deviceId)
            : item.lastModifiedByDeviceId,
      );
    }
  }

CatalogItem _prepareCatalogItemForSync(CatalogItem item, DateTime now) {
    return item.copyWith(
      createdAt:
          item.createdAt.millisecondsSinceEpoch == 0 ? now : item.createdAt,
      updatedAt:
          item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
      deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
      syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
      storeId: item.storeId.isEmpty ? appIdentity.storeId : item.storeId,
      branchId: item.branchId.isEmpty ? appIdentity.branchId : item.branchId,
      version: item.version <= 0 ? 1 : item.version,
      lastModifiedByDeviceId: item.lastModifiedByDeviceId.isEmpty
          ? (item.deviceId.isEmpty ? _deviceId : item.deviceId)
          : item.lastModifiedByDeviceId,
    );
  }

void _normalizeProductCodes() {
    // Legacy migration hook: never auto-renumber duplicate product codes.
    // Product ID remains the identity; duplicate code/barcode conflicts are detected
    // and displayed for manual review instead of silently changing business data.
    for (var index = 0; index < _products.length; index++) {
      final product = _products[index];
      final trimmedCode = product.code.trim();
      if (trimmedCode != product.code) {
        _products[index] = product.copyWith(code: trimmedCode);
      }
    }
  }

}
