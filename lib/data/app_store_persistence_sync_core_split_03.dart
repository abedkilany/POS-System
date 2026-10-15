part of 'app_store.dart';

extension _AppStoreSplitPersistenceSyncCorePart3 on AppStore {
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
    // Historical documents may reference soft-deleted catalog records.
    // Those records still exist and are valid referential targets; only a
    // truly absent entity should fail the business-data integrity check.
    final productIds = _products.map((item) => item.id).toSet();
    final supplierIds = _suppliers.map((item) => item.id).toSet();

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
      // Sale line count is not a valid proxy for stock-movement count:
      // non-stock/service/correction lines, returns, and legacy posted Sales
      // can legitimately have no sale movement. Dedicated inventory integrity
      // checks own movement/batch consistency instead.
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
    // This repair can persist products without going through addOrUpdateProduct.
    // Hydrate costing history first for the same lazy-loading safety invariant.
    await ensureCostingMethodHistoryLoaded();

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
    final normalizedProfile = profile.withMergedLogoAssetsFrom(_storeProfile);
    if (wants('storeProfile')) {
      _storeProfile = normalizedProfile;
      AccountingService.configureMoneyPolicy(_storeProfile);
    }
    _recordSyncChange(
      entityType: 'store_profile',
      entityId: 'store',
      operation: 'update',
      payload: normalizedProfile.toJson(),
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
    final normalizedRate =
        ratePercent.isFinite ? ratePercent.clamp(0, 100).toDouble() : 0.0;
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
}
