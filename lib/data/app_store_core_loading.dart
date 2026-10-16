part of 'app_store.dart';

extension _AppStoreSplitCoreLoading on AppStore {
  static const InventoryReadService _inventoryReadService =
      InventoryReadService();

  static const CommerceReadService _commerceReadService = CommerceReadService();

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

  Future<void> _requestLedgerDataLoad() {
    if (_ledgerDataLoadCompleted) return Future.value();
    final existing = _ledgerDataLoadFuture;
    if (existing != null) return existing;
    final future = _ensureAccountTransactionsLoaded();
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
    await _ensureProductsLoaded();
    await _ensurePriceListsLoaded();
    await _ensureProductPricesLoadedImpl();
    await _ensureProductPriceOverridesLoaded();
  }

  Future<void> ensureSalesPageDataLoaded() async {
    await _ensureProductsLoaded();
    await Future.wait([
      _ensureCustomersLoaded(),
      _ensureSalesLoaded(),
      _ensureDeliveryNotesLoaded(),
      ensureProductPricingLoaded(),
      _ensureWarehousesLoaded(),
    ]);
    await _AppStoreSplitStartupMigrations(this)
        ._backfillPostedDocumentSnapshotsIfNeeded();
  }

  Future<void> ensurePurchasesPageDataLoaded() async {
    await _ensureProductsLoaded();
    await _ensureSuppliersLoaded();
    await _ensurePurchasesLoaded();
    await _ensureSupplierProductPricesLoaded();
    await _AppStoreSplitStartupMigrations(this)
        ._backfillPostedDocumentSnapshotsIfNeeded();
  }

  Future<void> ensureQuotationsPageDataLoaded() async {
    await _ensureSaleQuotationsLoaded();
  }

  Future<void> ensureDeliveryNotesPageDataLoaded() async {
    await _ensureSalesLoaded();
    await _ensureDeliveryNotesLoaded();
  }

  Future<void> _ensureInventoryPageDataLoadedImpl() async {
    await _ensureProductsLoaded();
    await _ensureStockMovementsLoaded();
    await _ensureInventoryCountsLoaded();
    await _ensureWarehousesLoaded();
  }

  Future<void> ensureHeavyDataLoaded({bool failOnError = false}) async {
    await _ensureProductsLoaded();
    await _ensureCustomersLoaded();
    await _ensureSalesLoaded();
    await _ensureSaleQuotationsLoaded();
    await _ensureDeliveryNotesLoaded();
    await _ensureBillsOfMaterialsLoaded();
    await _ensureManufacturingOrdersLoaded();
    await _ensureSuppliersLoaded();
    await _ensureSupplierProductPricesLoaded();
    await _ensurePriceListsLoaded();
    await _ensureProductPricesLoadedImpl();
    await _ensureProductPriceOverridesLoaded();
    await _ensureProductCostsLoaded();
    await _ensureCostingMethodHistoryLoaded();
    await _ensureInventoryCostLayersLoaded();
    await _ensureExpensesLoaded();
    await _ensurePurchasesLoaded();
    await _AppStoreSplitStartupMigrations(this)
        ._backfillPostedDocumentSnapshotsIfNeeded();
    await _ensureStockMovementsLoaded();
    await _ensureInventoryCountsLoaded();
    await _ensureWarehousesLoaded();
    await _ensureAccountTransactionsLoaded();
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
      _commerceReadService.activeSalesNewestFirst(_sales),
    );
    _cachedSalesGeneration = _salesRevision;
  }

  List<Sale> get _salesReadImpl {
    unawaited(_ensureSalesLoaded());
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
        role: _currentUserRole,
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
    unawaited(_ensureSaleQuotationsLoaded());
    _ensureSaleQuotationsCache();
    return _cachedSaleQuotations!;
  }

  List<DeliveryNote> get deliveryNotes {
    unawaited(_ensureDeliveryNotesLoaded());
    _ensureDeliveryNotesCache();
    return _cachedDeliveryNotes!;
  }

  List<BillOfMaterials> get billsOfMaterials {
    unawaited(_ensureBillsOfMaterialsLoaded());
    _ensureBillsOfMaterialsCache();
    return _cachedBillsOfMaterials!;
  }

  List<ManufacturingOrder> get manufacturingOrders {
    unawaited(_ensureManufacturingOrdersLoaded());
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

  List<Expense> get _expensesReadImpl {
    unawaited(_ensureExpensesLoaded());
    return _commerceReadService.activeExpensesNewestFirst(_expenses);
  }

  List<Purchase> get _purchasesReadImpl {
    unawaited(_ensurePurchasesLoaded());
    return _commerceReadService.activePurchasesNewestFirst(_purchases);
  }

  List<StockMovement> get _stockMovementsReadImpl {
    unawaited(_ensureStockMovementsLoaded());
    return _inventoryReadService.newestFirstMovements(_stockMovements);
  }

  List<InventoryCountSession> get inventoryCountSessions {
    unawaited(_ensureInventoryCountsLoaded());
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

  List<Warehouse> get _warehousesReadImpl {
    unawaited(_ensureWarehousesLoaded());
    return _inventoryReadService.activeWarehouses(_warehouses);
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
}
