part of 'app_store.dart';

extension _AppStoreSplitBackupRecoveryPart4 on AppStore {
  void _replaceUsersWithoutDuplicates(List<AppUser> incoming) {
    final activeBeforeReplace = _activeUser;
    final normalizedIncoming = List<AppUser>.from(incoming);
    // A business-data reset does not log the operator out. Keep the active
    // session when a transient empty reload reaches the save path before the
    // users table has been rehydrated.
    if (normalizedIncoming.isEmpty && activeBeforeReplace != null) {
      normalizedIncoming.add(activeBeforeReplace);
    }
    _users
      ..clear()
      ..addAll(_dedupeUsersByUsername(normalizedIncoming));
    if (_activeUser != null &&
        !_users.any((user) => user.id == _activeUser!.id && user.isActive)) {
      _activeUser = null;
      unawaited(LocalDatabaseService.setString(AppStore._activeUserKey, ''));
    }
  }

  void _mergeUsersWithoutUsernameDuplicates(List<AppUser> incoming) {
    final merged = <AppUser>[..._users];
    for (final remote in incoming) {
      final remoteName = remote.username.trim().toLowerCase();
      if (remoteName.isEmpty) continue;
      final sameIdIndex = merged.indexWhere((user) => user.id == remote.id);
      final sameNameIndex = merged.indexWhere(
        (user) => user.username.trim().toLowerCase() == remoteName,
      );
      final index = sameIdIndex != -1 ? sameIdIndex : sameNameIndex;
      final normalizedRemote = remote.copyWith(username: remoteName);
      if (index == -1) {
        merged.add(normalizedRemote);
      } else if ((normalizedRemote.updatedAt ??
              normalizedRemote.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0))
          .isAfter(
        merged[index].updatedAt ??
            merged[index].createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0),
      )) {
        merged[index] = normalizedRemote;
      }
    }
    _replaceUsersWithoutDuplicates(merged);
  }

  void _mergeByUpdatedAt<T>(
    List<T> local,
    List<T> incoming,
    String Function(T item) idOf,
  ) {
    for (final remote in incoming) {
      final index = local.indexWhere((item) => idOf(item) == idOf(remote));
      if (index == -1) {
        local.add(remote);
        continue;
      }
      if (_readUpdatedAt(remote).isAfter(_readUpdatedAt(local[index]))) {
        local[index] = remote;
      }
    }
  }

  void _mergeSyncChanges(List<SyncChange> incoming) {
    final existingIds = _syncChanges.map((item) => item.id).toSet();
    for (final change in incoming) {
      if (!existingIds.contains(change.id)) {
        _syncChanges.add(change);
        existingIds.add(change.id);
      }
    }
  }

  Future<void> mergeBackupJson(
    String rawJson, {
    bool markSynced = false,
  }) async {
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final products = (decoded['products'] as List<dynamic>? ?? [])
        .map((item) => Product.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final customers = (decoded['customers'] as List<dynamic>? ?? [])
        .map(
          (item) => Customer.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final sales = (decoded['sales'] as List<dynamic>? ?? [])
        .map((item) => Sale.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final rawSaleQuotations = (decoded['saleQuotations'] as List<dynamic>?) ??
        (decoded['quotations'] as List<dynamic>?) ??
        const <dynamic>[];
    final saleQuotations = rawSaleQuotations
        .map(
          (item) =>
              SaleQuotation.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final deliveryNotes = (decoded['deliveryNotes'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              DeliveryNote.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final billsOfMaterials =
        (decoded['billsOfMaterials'] as List<dynamic>? ?? [])
            .map(
              (item) => BillOfMaterials.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final manufacturingOrders =
        (decoded['manufacturingOrders'] as List<dynamic>? ?? [])
            .map(
              (item) => ManufacturingOrder.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final suppliers = (decoded['suppliers'] as List<dynamic>? ?? [])
        .map(
          (item) => Supplier.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final supplierProductPrices =
        (decoded['supplierProductPrices'] as List<dynamic>? ?? [])
            .map(
              (item) => SupplierProductPrice.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final priceLists = (decoded['priceLists'] as List<dynamic>? ?? [])
        .map((item) =>
            PriceList.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final productPrices = (decoded['productPrices'] as List<dynamic>? ?? [])
        .map((item) =>
            ProductPrice.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final productPriceOverrides =
        (decoded['productPriceOverrides'] as List<dynamic>? ?? [])
            .map((item) => ProductPriceOverride.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList();
    final productCosts = (decoded['productCosts'] as List<dynamic>? ?? [])
        .map((item) =>
            ProductCost.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((item) => item.productId.isNotEmpty)
        .toList();
    final costingMethodHistory =
        (decoded['costingMethodHistory'] as List<dynamic>? ?? [])
            .map((item) => CostingMethodHistory.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .where((item) => item.id.isNotEmpty)
            .toList();
    final inventoryCostingMethod = InventoryCostingMethodJson.fromCode(
      decoded['inventoryCostingMethod'] is List
          ? ((decoded['inventoryCostingMethod'] as List).isEmpty
              ? null
              : (decoded['inventoryCostingMethod'] as List).first as String?)
          : decoded['inventoryCostingMethod'] as String?,
    );
    final inventoryCostLayers = (decoded['inventoryCostLayers']
                as List<dynamic>? ??
            [])
        .map((item) =>
            InventoryCostLayer.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((item) => item.id.isNotEmpty && item.productId.isNotEmpty)
        .toList();
    final categories = (decoded['categories'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final brands = (decoded['brands'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final units = (decoded['units'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final expenses = (decoded['expenses'] as List<dynamic>? ?? [])
        .map((item) => Expense.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final purchases = (decoded['purchases'] as List<dynamic>? ?? [])
        .map(
          (item) => Purchase.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final stockMovements = (decoded['stockMovements'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              StockMovement.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final warehouses = (decoded['warehouses'] as List<dynamic>? ?? [])
        .map(
          (item) => Warehouse.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final accountTransactions =
        (decoded['accountTransactions'] as List<dynamic>? ?? [])
            .map(
              (item) => AccountTransaction.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final roles = (decoded['roles'] as List<dynamic>? ?? [])
        .map(
          (item) => UserRole.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final users = (decoded['users'] as List<dynamic>? ?? [])
        .map((item) => AppUser.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();

    _mergeByUpdatedAt<Product>(_products, products, (item) => item.id);
    _mergeByUpdatedAt<Customer>(_customers, customers, (item) => item.id);
    _mergeByUpdatedAt<Sale>(_sales, sales, (item) => item.id);
    _mergeByUpdatedAt<SaleQuotation>(
      _saleQuotations,
      saleQuotations,
      (item) => item.id,
    );
    _mergeByUpdatedAt<DeliveryNote>(
      _deliveryNotes,
      deliveryNotes,
      (item) => item.id,
    );
    _mergeByUpdatedAt<BillOfMaterials>(
      _billsOfMaterials,
      billsOfMaterials,
      (item) => item.id,
    );
    _mergeByUpdatedAt<ManufacturingOrder>(
      _manufacturingOrders,
      manufacturingOrders,
      (item) => item.id,
    );
    _mergeByUpdatedAt<Supplier>(_suppliers, suppliers, (item) => item.id);
    _mergeByUpdatedAt<SupplierProductPrice>(
      _supplierProductPrices,
      supplierProductPrices,
      (item) => item.id,
    );
    _mergeByUpdatedAt<PriceList>(_priceLists, priceLists, (item) => item.id);
    _mergeByUpdatedAt<ProductPrice>(
        _productPrices, productPrices, (item) => item.id);
    _mergeByUpdatedAt<ProductPriceOverride>(
        _productPriceOverrides, productPriceOverrides, (item) => item.id);
    _mergeByUpdatedAt<ProductCost>(
        _productCosts, productCosts, (item) => item.productId);
    _mergeByUpdatedAt<CostingMethodHistory>(
        _costingMethodHistory, costingMethodHistory, (item) => item.id);
    _inventoryCostingMethod =
        _runtimeInventoryCostingMethod(inventoryCostingMethod);
    _mergeByUpdatedAt<InventoryCostLayer>(
        _inventoryCostLayers, inventoryCostLayers, (item) => item.id);
    _rebuildProductCostLookupCache();
    _rebuildInventoryCostLayerLookupCache();
    _mergeByUpdatedAt<CatalogItem>(_categories, categories, (item) => item.id);
    _mergeByUpdatedAt<CatalogItem>(_brands, brands, (item) => item.id);
    _mergeByUpdatedAt<CatalogItem>(_units, units, (item) => item.id);
    _mergeByUpdatedAt<Expense>(_expenses, expenses, (item) => item.id);
    _mergeByUpdatedAt<Purchase>(_purchases, purchases, (item) => item.id);
    _mergeByUpdatedAt<StockMovement>(
      _stockMovements,
      stockMovements,
      (item) => item.id,
    );
    _mergeByUpdatedAt<Warehouse>(_warehouses, warehouses, (item) => item.id);
    _ensureDefaultWarehouse();
    _mergeByUpdatedAt<AccountTransaction>(
      _accountTransactions,
      accountTransactions,
      (item) => item.id,
    );
    _invalidateAccountLedgerCache();
    if (decoded['storeProfile'] != null) {
      _storeProfile = StoreProfile.fromJson(
        Map<String, dynamic>.from(decoded['storeProfile'] as Map),
      );
      AccountingService.configureMoneyPolicy(_storeProfile);
    }
    // Never overwrite the local device identity during LAN pull/merge.
    // The remote snapshot belongs to the Host, while this device must keep
    // its own deviceId/deviceName/role so new local changes are queued
    // correctly toward the Host.
    _appIdentity = appIdentity.copyWith(
      deviceId: _deviceId,
      platform: _detectPlatform(),
    );
    await LocalDatabaseService.setString(
      AppStore._appIdentityKey,
      jsonEncode(_appIdentity!.toJson()),
    );
    _mergeByUpdatedAt<UserRole>(_roles, roles, (item) => item.id);
    _mergeUsersWithoutUsernameDuplicates(users);
    final nowForMergedRemoteChanges = DateTime.now();
    _mergeSyncChanges(
      markSynced
          ? _syncChanges
          : _syncChanges.map((change) {
              if (change.deviceId == _deviceId || change.isSynced) {
                return change;
              }
              return change.copyWith(
                isSynced: true,
                syncedAt: nowForMergedRemoteChanges,
              );
            }).toList(),
    );

    final importedCounter = (decoded['invoiceCounter'] as num?)?.toInt() ?? 0;
    if (importedCounter > _invoiceCounter) _invoiceCounter = importedCounter;
    final importedPurchaseCounter =
        (decoded['purchaseCounter'] as num?)?.toInt() ?? 0;
    if (importedPurchaseCounter > _purchaseCounter) {
      _purchaseCounter = importedPurchaseCounter;
    }

    if (markSynced) {
      final now = DateTime.now();
      for (var i = 0; i < _syncChanges.length; i++) {
        _syncChanges[i] = _syncChanges[i].copyWith(
          isSynced: true,
          syncedAt: now,
        );
      }
    }

    _ensureCatalogDefaults();
    _normalizeCustomers();
    await _saveRolesAndUsers();
    await _saveSyncStateOnly();
    notifyListeners();
  }
}
