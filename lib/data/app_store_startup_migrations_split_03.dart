part of 'app_store.dart';

extension _AppStoreSplitStartupMigrationsPart3 on AppStore {
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
    final stored = int.tryParse(
            LocalDatabaseService.getString(AppStore._syncSequenceKey) ?? '') ??
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
    final current = int.tryParse(
            LocalDatabaseService.getString(AppStore._schemaVersionKey) ?? '') ??
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
        LocalDatabaseService.getString(AppStore._supplierProductPricesKey) ==
            null) {
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
