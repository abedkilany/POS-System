part of 'app_store.dart';

extension _AppStoreSplitCoreLoading on AppStore {
void _emitTrace(
    String section,
    String phase,
    Stopwatch sw,
    Map<String, Object?> metadata,
  ) {
    final sink = AppStore._traceSink;
    if (sink == null) return;
    sink(section, phase, sw.elapsedMilliseconds, metadata);
  }

Future<T> _traceAsync<T>(
    String section,
    String phase,
    Future<T> Function() action, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final sw = Stopwatch()..start();
    try {
      final result = await action();
      sw.stop();
      _emitTrace(section, phase, sw, metadata);
      return result;
    } catch (_) {
      sw.stop();
      _emitTrace(section, phase, sw, metadata);
      rethrow;
    }
  }

void _traceSync(
    String section,
    String phase,
    void Function() action, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final sw = Stopwatch()..start();
    try {
      action();
    } finally {
      sw.stop();
      _emitTrace(section, phase, sw, metadata);
    }
  }

T _traceSyncResult<T>(
    String section,
    String phase,
    T Function() action, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final sw = Stopwatch()..start();
    try {
      return action();
    } finally {
      sw.stop();
      _emitTrace(section, phase, sw, metadata);
    }
  }

Future<void> warmDeferredPageCaches() async {
    await StartupTimingService.measure(
      'app_store.post_startup_cache_warm',
      () async {
        await Future.wait(<Future<void>>[
          ensurePriceListsLoaded(),
          ensureProductPricesLoaded(),
          ensureProductPriceOverridesLoaded(),
          ensureProductCostsLoaded(),
          _requestSyncDataLoad(),
        ]);
      },
      category: 'app_store',
    );
  }

Future<void> _requestLedgerDataLoad() {
    if (_ledgerDataLoadCompleted) return Future.value();
    final existing = _ledgerDataLoadFuture;
    if (existing != null) return existing;
    final future = ensureAccountTransactionsLoaded();
    _ledgerDataLoadFuture = future.whenComplete(() {
      _ledgerDataLoadFuture = null;
      _ledgerDataLoadCompleted = true;
    });
    return _ledgerDataLoadFuture!;
  }

Future<void> _requestSyncDataLoad() {
    if (_syncDataLoadCompleted) return Future.value();
    final existing = _syncDataLoadFuture;
    if (existing != null) return existing;
    final future = _loadSyncDeferredStartupData();
    _syncDataLoadFuture = future.whenComplete(() {
      _syncDataLoadFuture = null;
      _syncDataLoadCompleted = true;
    });
    return _syncDataLoadFuture!;
  }

Future<void> _loadDeferredGroup<T>({
    required String key,
    required Future<List<T>> Function() loader,
    required List<T> target,
    void Function()? afterLoad,
  }) {
    return _requestDeferredGroupLoad(key, () async {
      final items = await loader();
      target
        ..clear()
        ..addAll(items);
      afterLoad?.call();
      notifyListeners();
    });
  }

Future<void> _requestDeferredGroupLoad(
    String key,
    Future<void> Function() action,
  ) {
    if (_deferredGroupLoadCompleted.contains(key)) {
      return Future.value();
    }
    final existing = _deferredGroupLoadFutures[key];
    if (existing != null) return existing;
    final future = StartupTimingService.measure(
      'app_store.load.$key',
      action,
      category: 'app_store',
      details: 'deferred_group',
    ).then<void>(
      (_) {
        _deferredGroupLoadErrors.remove(key);
        _deferredGroupLoadCompleted.add(key);
      },
      onError: (Object error, StackTrace stackTrace) {
        _deferredGroupLoadErrors[key] = error;
        debugPrint('Deferred group load failed for $key: $error');
        debugPrint('$stackTrace');
      },
    ).whenComplete(() {
      _deferredGroupLoadFutures.remove(key);
    });
    _deferredGroupLoadFutures[key] = future;
    return future;
  }

Future<void> ensureProductPricingLoaded() async {
    await ensureProductsLoaded();
    await ensurePriceListsLoaded();
    await ensureProductPricesLoaded();
    await ensureProductPriceOverridesLoaded();
  }

Future<void> ensureProductCostingDataLoaded() async {
    await ensureProductsLoaded();
    await ensureProductCostsLoaded();
    await ensureCostingMethodHistoryLoaded();
    await ensureInventoryCostLayersLoaded();
    await ensureSupplierProductPricesLoaded();
  }

Future<void> ensureSalesPageDataLoaded() async {
    await ensureProductsLoaded();
    await Future.wait([
      ensureCustomersLoaded(),
      ensureSalesLoaded(),
      ensureDeliveryNotesLoaded(),
      ensureProductPricingLoaded(),
      ensureWarehousesLoaded(),
    ]);
    await _AppStoreSplitStartupMigrations(this)
        ._backfillPostedDocumentSnapshotsIfNeeded();
  }

Future<void> ensurePurchasesPageDataLoaded() async {
    await ensureProductsLoaded();
    await ensureSuppliersLoaded();
    await ensurePurchasesLoaded();
    await ensureSupplierProductPricesLoaded();
    await _AppStoreSplitStartupMigrations(this)
        ._backfillPostedDocumentSnapshotsIfNeeded();
  }

Future<void> ensureAccountingPageDataLoaded() async {
    await ensureCustomersLoaded();
    await ensureSuppliersLoaded();
    await ensureSalesLoaded();
    await ensurePurchasesLoaded();
    await _AppStoreSplitStartupMigrations(this)
        ._backfillPostedDocumentSnapshotsIfNeeded();
    await ensureAccountTransactionsLoaded();
  }

Future<void> ensureQuotationsPageDataLoaded() async {
    await ensureSaleQuotationsLoaded();
  }

Future<void> ensureDeliveryNotesPageDataLoaded() async {
    await ensureSalesLoaded();
    await ensureDeliveryNotesLoaded();
  }

Future<void> ensureInventoryPageDataLoaded() async {
    await ensureProductsLoaded();
    await ensureStockMovementsLoaded();
    await ensureInventoryCountsLoaded();
    await ensureWarehousesLoaded();
  }

Future<void> ensureHeavyDataLoaded({bool failOnError = false}) async {
    await ensureProductsLoaded();
    await ensureCustomersLoaded();
    await ensureSalesLoaded();
    await ensureSaleQuotationsLoaded();
    await ensureDeliveryNotesLoaded();
    await ensureBillsOfMaterialsLoaded();
    await ensureManufacturingOrdersLoaded();
    await ensureSuppliersLoaded();
    await ensureSupplierProductPricesLoaded();
    await ensurePriceListsLoaded();
    await ensureProductPricesLoaded();
    await ensureProductPriceOverridesLoaded();
    await ensureProductCostsLoaded();
    await ensureCostingMethodHistoryLoaded();
    await ensureInventoryCostLayersLoaded();
    await ensureExpensesLoaded();
    await ensurePurchasesLoaded();
    await _AppStoreSplitStartupMigrations(this)
        ._backfillPostedDocumentSnapshotsIfNeeded();
    await ensureStockMovementsLoaded();
    await ensureInventoryCountsLoaded();
    await ensureWarehousesLoaded();
    await ensureAccountTransactionsLoaded();
    await _requestSyncDataLoad();
    _heavyDataLoadCompleted = true;
    _ledgerDataLoadCompleted = true;
    _syncDataLoadCompleted = true;
    if (failOnError && _deferredGroupLoadErrors.isNotEmpty) {
      final details = _deferredGroupLoadErrors.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join(' | ');
      throw StateError('Snapshot data loading failed: $details');
    }
  }

void _ensureSalesCache() {
    if (_cachedSalesGeneration == _salesRevision && _cachedSales != null) {
      return;
    }
    _cachedSales = UnmodifiableListView(
      _sales
          .where((item) => !item.isDeleted)
          .toList(growable: false)
          .reversed
          .toList(growable: false),
    );
    _cachedSalesGeneration = _salesRevision;
  }

List<Sale> get sales {
    unawaited(ensureSalesLoaded());
    _ensureSalesCache();
    return _cachedSales!;
  }

Future<void> ensureCreditNotesLoaded() async {
    if (_creditNotes.isNotEmpty) return;
    // credit_notes_v1 is stored as a scalar JSON list rather than a typed
    // business table. Read the scalar mirror first so SQLite desktop installs
    // retain return history across app restarts; _decodeDeferredList alone only
    // discovers typed entity keys in the SQLite startup path.
    final raw = LocalDatabaseService.getString(AppStore._creditNotesKey);
    if (raw != null && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _creditNotes.addAll(decoded.map((item) => CreditNote.fromJson(
              Map<String, dynamic>.from(item as Map),
            )));
      }
    }
    if (_creditNotes.isEmpty) {
      _creditNotes.addAll(await _decodeDeferredList<CreditNote>(
        AppStore._creditNotesKey,
        CreditNote.fromJson,
        batchSize: 100,
      ));
    }

    var changed = false;
    for (var index = 0; index < _creditNotes.length; index += 1) {
      final note = _creditNotes[index];
      if (note.postedSnapshot != null) continue;
      Sale? originalSale;
      for (final candidate in _sales) {
        if (candidate.id == note.originalSaleId) {
          originalSale = candidate;
          break;
        }
      }
      originalSale ??= await _saleByIdFromSqlite(note.originalSaleId);
      if (originalSale == null) continue;
      Customer? customer;
      for (final candidate in _customers) {
        if (candidate.id == note.customerId && !candidate.isDeleted) {
          customer = candidate;
          break;
        }
      }
      final snapshot = PostedDocumentSnapshotService.forSaleReturn(
        creditNote: note,
        originalSale: originalSale,
        profile: _storeProfile,
        customer: customer,
        legacyBackfill: true,
      );
      _creditNotes[index] = note.copyWith(postedSnapshot: snapshot);
      changed = true;
    }
    if (changed) {
      await LocalDatabaseService.setString(
        AppStore._creditNotesKey,
        jsonEncode(_creditNotes.map((item) => item.toJson()).toList()),
      );
    }
  }

Future<CreditNote> issueCreditNote({
    required Sale originalSale,
    required List<SaleItem> items,
    required double amount,
    String refundMethod = 'Customer balance',
    String note = '',
  }) async {
    requirePermission(AppPermission.salesCancel);
    await ensureCreditNotesLoaded();
    if (items.isEmpty || amount <= 0) {
      throw ArgumentError(
          'Credit note must contain items and a positive amount.');
    }
    final now = DateTime.now();
    final number = (_creditNotes.length + 1).toString().padLeft(6, '0');
    var creditNote = CreditNote(
      id: 'credit_note_${now.microsecondsSinceEpoch}',
      creditNoteNo: 'CN-$number',
      originalSaleId: originalSale.id,
      originalInvoiceNo: originalSale.invoiceNo,
      customerName: originalSale.customerName,
      customerId: originalSale.customerId,
      date: now,
      items: items,
      amount: amount,
      currency: originalSale.invoiceCurrency,
      refundMethod: refundMethod,
      note: note,
      createdAt: now,
      updatedAt: now,
    );
    Customer? snapshotCustomer;
    for (final candidate in _customers) {
      if (candidate.id == originalSale.customerId && !candidate.isDeleted) {
        snapshotCustomer = candidate;
        break;
      }
    }
    final usedOriginalIndexes = <int>{};
    final originalLineIndexes = <int>[];
    for (final returnedItem in items) {
      var resolvedIndex = -1;
      for (var index = 0; index < originalSale.items.length; index += 1) {
        if (usedOriginalIndexes.contains(index)) continue;
        final source = originalSale.items[index];
        if (source.productId == returnedItem.productId &&
            source.unitName == returnedItem.unitName &&
            (source.unitPrice - returnedItem.unitPrice).abs() <= 0.000001) {
          resolvedIndex = index;
          break;
        }
      }
      if (resolvedIndex < 0) {
        for (var index = 0; index < originalSale.items.length; index += 1) {
          if (!usedOriginalIndexes.contains(index) &&
              originalSale.items[index].productId == returnedItem.productId) {
            resolvedIndex = index;
            break;
          }
        }
      }
      if (resolvedIndex >= 0) usedOriginalIndexes.add(resolvedIndex);
      originalLineIndexes.add(resolvedIndex);
    }
    final legacyDefaultVatRatePercent =
        await AccountingService.readDefaultVatRatePercent();
    final taxProfileIdByProductId = <String, String>{
      for (final product in _products) product.id: product.taxProfileId,
    };
    creditNote = creditNote.copyWith(
      postedSnapshot: PostedDocumentSnapshotService.forSaleReturn(
        creditNote: creditNote,
        originalSale: originalSale,
        profile: _storeProfile,
        customer: snapshotCustomer,
        user: _activeUser,
        role: currentUserRole,
        originalLineIndexes: originalLineIndexes,
        taxProfileIdByProductId: taxProfileIdByProductId,
        legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
      ),
    );
    _creditNotes.add(creditNote);
    await LocalDatabaseService.setString(
      AppStore._creditNotesKey,
      jsonEncode(_creditNotes.map((item) => item.toJson()).toList()),
    );
    notifyListeners();
    return creditNote;
  }

List<SaleQuotation> get saleQuotations {
    unawaited(ensureSaleQuotationsLoaded());
    _ensureSaleQuotationsCache();
    return _cachedSaleQuotations!;
  }

List<DeliveryNote> get deliveryNotes {
    unawaited(ensureDeliveryNotesLoaded());
    _ensureDeliveryNotesCache();
    return _cachedDeliveryNotes!;
  }

List<BillOfMaterials> get billsOfMaterials {
    unawaited(ensureBillsOfMaterialsLoaded());
    _ensureBillsOfMaterialsCache();
    return _cachedBillsOfMaterials!;
  }

List<ManufacturingOrder> get manufacturingOrders {
    unawaited(ensureManufacturingOrdersLoaded());
    _ensureManufacturingOrdersCache();
    return _cachedManufacturingOrders!;
  }

ProductCost productCostFor(String productId) {
    _ensureProductPricingLookupCaches();
    return _productCostByProductId[productId] ??
        ProductCost(productId: productId);
  }

PriceList get defaultPriceList {
    _ensureDefaultPriceLists();
    return _priceLists.firstWhere((item) => item.isDefault && item.isActive,
        orElse: () => _priceLists.first);
  }

ProductPrice? defaultProductPriceFor(String productId,
      {String unitId = 'base'}) {
    _ensureProductPricingLookupCaches();
    _ensureDefaultProductPriceEntries();
    final priceListId = defaultPriceList.id;
    return _productPriceByLookupKey[
        _productPriceLookupKey(productId, priceListId, unitId)];
  }

ProductPrice? productPriceFor(String productId, String priceListId,
      {String unitId = 'base'}) {
    _ensureDefaultProductPriceEntries();
    _ensureProductPricingLookupCaches();
    return _productPriceByLookupKey[
        _productPriceLookupKey(productId, priceListId, unitId)];
  }

ProductPriceOverride? productPriceOverrideFor(
      ProductPrice price, String currencyCode) {
    final normalizedCurrency = currencyCode.trim().toUpperCase();
    for (final item in _productPriceOverrides) {
      if (item.productPriceId == price.id &&
          item.currencyCode == normalizedCurrency &&
          item.isActive) {
        return item;
      }
    }
    return null;
  }

double productPriceAmountForCurrency(Product product, String currencyCode,
      {String unitId = 'base'}) {
    final price = defaultProductPriceFor(product.id, unitId: unitId);
    if (price == null) {
      final fallbackUsd = unitId == 'base' ? product.usdPrice : product.price;
      return fromUsdReferencePrice(fallbackUsd, currencyCode, storeProfile);
    }
    final override = productPriceOverrideFor(price, currencyCode);
    if (override != null) {
      return override.amount;
    }
    return convertCurrency(
      price.baseAmount,
      price.baseCurrencyCode,
      currencyCode.trim().toUpperCase(),
      storeProfile,
    );
  }

double defaultProductUsdPrice(Product product, {String unitId = 'base'}) {
    final price = defaultProductPriceFor(product.id, unitId: unitId);
    if (price == null) {
      return unitId == 'base' ? product.usdPrice : product.price;
    }
    final saleCurrency = storeProfile.defaultSaleInvoiceCurrency;
    final override = productPriceOverrideFor(price, saleCurrency);
    if (override != null) {
      return toUsdReferencePrice(
          override.amount, override.currencyCode, storeProfile);
    }
    return toUsdReferencePrice(
        price.baseAmount, price.baseCurrencyCode, storeProfile);
  }

List<DataConflict> get dataConflicts {
    return List.unmodifiable(_detectDataConflicts());
  }

Future<List<DataConflict>> ensureDataConflictsLoaded() async {
    await ensureHeavyDataLoaded();
    return dataConflicts;
  }

List<Expense> get expenses {
    unawaited(ensureExpensesLoaded());
    return List.unmodifiable(
      _expenses
          .where((item) => !item.isDeleted)
          .toList(growable: false)
          .reversed
          .toList(growable: false),
    );
  }

List<Purchase> get purchases {
    unawaited(ensurePurchasesLoaded());
    return List.unmodifiable(
      _purchases
          .where((item) => !item.isDeleted)
          .toList(growable: false)
          .reversed
          .toList(growable: false),
    );
  }

List<StockMovement> get stockMovements {
    unawaited(ensureStockMovementsLoaded());
    return List.unmodifiable(
      _stockMovements.toList(growable: false).reversed.toList(growable: false),
    );
  }

List<InventoryCountSession> get inventoryCountSessions {
    unawaited(ensureInventoryCountsLoaded());
    return List.unmodifiable(
      _inventoryCounts.toList(growable: false).reversed.toList(growable: false),
    );
  }

InventoryCountSession? get activeInventoryCountSession {
    for (final session in _inventoryCounts.reversed) {
      if (session.isOpen) return session;
    }
    return null;
  }

List<Warehouse> get warehouses {
    unawaited(ensureWarehousesLoaded());
    return List.unmodifiable(
      _warehouses
          .where((item) => !item.isDeleted && item.isActive)
          .toList(growable: false),
    );
  }

Warehouse get defaultWarehouse {
    _ensureDefaultWarehouse();
    return _warehouses.firstWhere(
      (item) => item.id == Warehouse.defaultId,
      orElse: () => Warehouse(
        id: Warehouse.defaultId,
        name: Warehouse.defaultName,
        isDefault: true,
      ),
    );
  }

Warehouse resolveWarehouseForSale({String warehouseId = ''}) {
    _ensureDefaultWarehouse();
    final normalized = warehouseId.trim();
    final activeWarehouses = _warehouses
        .where((item) => !item.isDeleted && item.isActive)
        .toList(growable: false);
    if (normalized.isNotEmpty) {
      return activeWarehouses.firstWhere(
        (item) => item.id == normalized,
        orElse: () => defaultWarehouse,
      );
    }
    return activeWarehouses.firstWhere(
      (item) => item.isDefault,
      orElse: () => defaultWarehouse,
    );
  }

String get saleWarehouseId {
    final storeId = appIdentity.storeId.trim();
    if (storeId.isEmpty) return '';
    return LocalDatabaseService.getString(
          'sale_warehouse_v1_${storeId}_${appIdentity.branchId.trim()}',
        )?.trim() ??
        '';
  }

Future<void> setSaleWarehouseId(String warehouseId) async {
    requirePermission(AppPermission.settingsManage);
    final storeId = appIdentity.storeId.trim();
    if (storeId.isEmpty) return;
    await LocalDatabaseService.setString(
      'sale_warehouse_v1_${storeId}_${appIdentity.branchId.trim()}',
      warehouseId.trim(),
    );
    notifyListeners();
  }

Warehouse resolveWarehouseForPurchase({String warehouseId = ''}) {
    return resolveWarehouseForSale(warehouseId: warehouseId);
  }

void _ensureDefaultWarehouse() {
    if (_warehouses.any(
      (item) => item.id == Warehouse.defaultId && !item.isDeleted,
    )) {
      return;
    }
    final now = DateTime.now();
    _warehouses.insert(
      0,
      Warehouse(
        id: Warehouse.defaultId,
        name: Warehouse.defaultName,
        code: 'MAIN',
        isDefault: true,
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
    );
    _rememberSqliteDirtyBusinessRow(
      AppStore._warehousesKey,
      _warehouses.first.toJson(),
    );
  }

void _invalidateDerivedDataCaches() {
    _derivedListCacheGeneration += 1;
    _warehouseStockCacheDirty = true;
    _purchaseInsightsCacheDirty = true;
  }

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
