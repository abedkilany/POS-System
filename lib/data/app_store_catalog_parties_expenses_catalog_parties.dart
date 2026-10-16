part of 'app_store.dart';

extension _AppStoreCatalogPartiesExpensesCatalogParties on AppStore {

  Future<void> deleteCustomer(String id) async {
    requirePermission(AppPermission.customersManage);
    final index = _customerIndexById[id];
    if (index == null) return;
    final previousCustomer = _customers[index];
    final customer = previousCustomer;
    final isWalkIn = customer.id == AppStore.walkInCustomerId ||
        customer.name.trim().toLowerCase() ==
            AppStore.walkInCustomerName.toLowerCase();
    if (isWalkIn) return;
    final now = DateTime.now();
    final deletedCustomer = _withSyncMeta<Customer>(
      previousCustomer.copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    _customers[index] = deletedCustomer;
    _recordSyncChange(
      entityType: 'customer',
      entityId: id,
      operation: 'delete',
      payload: deletedCustomer.toJson(),
    );
    _indexCustomerAt(
      index,
      deletedCustomer,
      previousCustomer: previousCustomer,
    );
    await _saveDirty(customers: true, sync: true);
    unawaited(
      AppLogger.info(
        area: 'customers',
        action: 'delete_customer',
        message: 'Customer deleted successfully.',
        details: 'customerId=$id',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'customer',
        entityId: id,
        action: 'delete',
        summary: 'Customer deleted',
        details: jsonEncode(_customers[index].toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'customers',
        isImportant: true,
      ),
    );
    notifyListeners();
  }

  Future<void> addOrUpdateSupplier(Supplier supplier) async {
    final section = 'supplier.addOrUpdate';
    requirePermission(AppPermission.suppliersManage);
    if (supplier.name.trim().isEmpty) {
      throw ArgumentError('Supplier name is required.');
    }
    final normalizedName = supplier.name.trim().toLowerCase();
    final duplicateId = _supplierIdByNormalizedName[normalizedName];
    final duplicate = duplicateId != null && duplicateId != supplier.id;
    if (duplicate) {
      throw ArgumentError(
        'Supplier name already exists on this device. Sync duplicates will be reported as conflicts.',
      );
    }
    final now = DateTime.now();
    final cleanedSupplier = supplier.copyWith(name: supplier.name.trim());
    final index = _supplierIndexById[cleanedSupplier.id];
    final isCreate = index == null;
    final syncedSupplier = _withSyncMeta<Supplier>(
      cleanedSupplier,
      now,
      isCreate: isCreate,
    );
    if (isCreate) {
      _suppliers.add(syncedSupplier);
      _indexSupplierAt(_suppliers.length - 1, syncedSupplier);
    } else {
      final existingIndex = index;
      final previousSupplier = _suppliers[existingIndex];
      _suppliers[existingIndex] = syncedSupplier;
      _indexSupplierAt(
        existingIndex,
        syncedSupplier,
        previousSupplier: previousSupplier,
      );
    }
    _traceSync(section, 'record_sync_change', () {
      _recordSyncChange(
        entityType: 'supplier',
        entityId: syncedSupplier.id,
        operation: isCreate ? 'create' : 'update',
        payload: syncedSupplier.toJson(),
      );
    }, metadata: <String, Object?>{
      'supplierId': syncedSupplier.id,
      'isCreate': isCreate
    });
    await _traceAsync(
        section, 'save_dirty', () => _saveDirty(suppliers: true, sync: true),
        metadata: <String, Object?>{
          'supplierId': syncedSupplier.id,
          'isCreate': isCreate
        });
    unawaited(
      AppLogger.info(
        area: 'suppliers',
        action: isCreate ? 'create_supplier' : 'update_supplier',
        message: isCreate
            ? 'Supplier created successfully.'
            : 'Supplier updated successfully.',
        details: 'supplierId=${syncedSupplier.id} name=${syncedSupplier.name}',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'supplier',
        entityId: syncedSupplier.id,
        action: isCreate ? 'create' : 'update',
        summary: isCreate ? 'Supplier created' : 'Supplier updated',
        details: jsonEncode(syncedSupplier.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'suppliers',
        isImportant: true,
      ),
    );
    notifyListeners();
  }


  Future<void> deleteSupplier(String id) async {
    requirePermission(AppPermission.suppliersManage);
    final index = _supplierIndexById[id];
    if (index == null) return;
    final now = DateTime.now();
    final previousSupplier = _suppliers[index];
    final deletedSupplier = _withSyncMeta<Supplier>(
      previousSupplier.copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    _suppliers[index] = deletedSupplier;
    _recordSyncChange(
      entityType: 'supplier',
      entityId: id,
      operation: 'delete',
      payload: deletedSupplier.toJson(),
    );
    _indexSupplierAt(index, deletedSupplier,
        previousSupplier: previousSupplier);
    final affectedPrices = _softDeleteSupplierProductPrices(
      supplierId: id,
      now: now,
      reason: 'Supplier deleted',
    );
    await _saveDirty(
      suppliers: true,
      supplierProductPrices: affectedPrices > 0,
      sync: true,
    );
    notifyListeners();
  }

  Future<void> addOrUpdateCategory(CatalogItem item) async {
    requirePermission(AppPermission.catalogManage);
    final previousItem = _categories
        .where((existing) => existing.id == item.id)
        .cast<CatalogItem?>()
        .firstOrNull;
    final syncedItem = _addOrUpdateCatalogItem(_categories, item);
    final productsChanged =
        _propagateCatalogRename('category', previousItem, syncedItem);
    _recordSyncChange(
      entityType: 'category',
      entityId: syncedItem.id,
      operation: _categories
                      .where((existing) => existing.id == syncedItem.id)
                      .length ==
                  1 &&
              syncedItem.createdAt == syncedItem.updatedAt
          ? 'create'
          : 'update',
      payload: syncedItem.toJson(),
    );
    await _saveDirty(
      categories: true,
      products: productsChanged,
      sync: true,
    );
    notifyListeners();
  }

  Future<void> addOrUpdateBrand(CatalogItem item) async {
    requirePermission(AppPermission.catalogManage);
    final previousItem = _brands
        .where((existing) => existing.id == item.id)
        .cast<CatalogItem?>()
        .firstOrNull;
    final syncedItem = _addOrUpdateCatalogItem(_brands, item);
    final productsChanged =
        _propagateCatalogRename('brand', previousItem, syncedItem);
    _recordSyncChange(
      entityType: 'brand',
      entityId: syncedItem.id,
      operation:
          syncedItem.createdAt == syncedItem.updatedAt ? 'create' : 'update',
      payload: syncedItem.toJson(),
    );
    await _saveDirty(
      brands: true,
      products: productsChanged,
      sync: true,
    );
    notifyListeners();
  }

  Future<void> addOrUpdateUnit(CatalogItem item) async {
    requirePermission(AppPermission.catalogManage);
    final previousItem = _units
        .where((existing) => existing.id == item.id)
        .cast<CatalogItem?>()
        .firstOrNull;
    final syncedItem = _addOrUpdateCatalogItem(_units, item);
    final productsChanged =
        _propagateCatalogRename('unit', previousItem, syncedItem);
    _recordSyncChange(
      entityType: 'unit',
      entityId: syncedItem.id,
      operation:
          syncedItem.createdAt == syncedItem.updatedAt ? 'create' : 'update',
      payload: syncedItem.toJson(),
    );
    await _saveDirty(
      units: true,
      products: productsChanged,
      sync: true,
    );
    notifyListeners();
  }

  CatalogItem _addOrUpdateCatalogItem(
    List<CatalogItem> list,
    CatalogItem item,
  ) {
    if (item.nameEn.trim().isEmpty && item.nameAr.trim().isEmpty) {
      throw ArgumentError('English or Arabic name is required.');
    }
    final normalizedEn = item.nameEn.trim().toLowerCase();
    final normalizedAr = item.nameAr.trim().toLowerCase();
    final duplicate = list.any((existing) {
      if (existing.id == item.id || existing.isDeleted) return false;
      return (normalizedEn.isNotEmpty &&
              existing.nameEn.trim().toLowerCase() == normalizedEn) ||
          (normalizedAr.isNotEmpty &&
              existing.nameAr.trim().toLowerCase() == normalizedAr);
    });
    if (duplicate) throw ArgumentError('This name already exists.');
    final index = list.indexWhere((existing) => existing.id == item.id);
    final now = DateTime.now();
    final isCreate = index == -1;
    final syncedItem = _markCatalogItemForSync(item, now, isCreate: isCreate);
    if (isCreate) {
      list.add(syncedItem);
    } else {
      list[index] = syncedItem;
    }
    return syncedItem;
  }

  bool _catalogReferenceChanged(CatalogItem? previous, CatalogItem current) {
    if (previous == null) return false;
    return _catalogReferenceValue(previous).trim().toLowerCase() !=
        _catalogReferenceValue(current).trim().toLowerCase();
  }

  bool _catalogItemMatchesValue(CatalogItem item, String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return item.code.trim().toLowerCase() == normalized ||
        item.nameEn.trim().toLowerCase() == normalized ||
        item.nameAr.trim().toLowerCase() == normalized;
  }

  int productsUsingCatalogItem(String type, CatalogItem item) {
    if (type != 'category' && type != 'unit' && type != 'brand') return 0;
    return _products.where((product) {
      if (product.isDeleted) return false;
      final value = switch (type) {
        'category' => product.category,
        'brand' => product.brand,
        _ => product.unit,
      };
      return _catalogItemMatchesValue(item, value);
    }).length;
  }

  bool _propagateCatalogRename(
    String type,
    CatalogItem? previous,
    CatalogItem current,
  ) {
    if (!_catalogReferenceChanged(previous, current)) return false;
    final oldValue = _catalogReferenceValue(previous!);
    final newValue = _catalogReferenceValue(current);
    var changed = false;
    for (var i = 0; i < _products.length; i++) {
      final product = _products[i];
      if (product.isDeleted) continue;
      final currentValue = switch (type) {
        'category' => product.category,
        'brand' => product.brand,
        _ => product.unit,
      };
      if (!_valueMatchesCatalogReference(currentValue, oldValue)) continue;
      final updatedProduct = _markProductForSync(
        switch (type) {
          'category' => product.copyWith(category: newValue),
          'brand' => product.copyWith(brand: newValue),
          _ => product.copyWith(unit: newValue),
        },
        DateTime.now(),
      );
      _products[i] = updatedProduct;
      _recordSyncChange(
        entityType: 'product',
        entityId: updatedProduct.id,
        operation: 'update',
        payload: updatedProduct.toJson(),
      );
      changed = true;
    }
    return changed;
  }

  bool _valueMatchesCatalogReference(String value, String reference) {
    final normalizedValue = value.trim().toLowerCase();
    final normalizedReference = reference.trim().toLowerCase();
    if (normalizedValue.isEmpty || normalizedReference.isEmpty) return false;
    return normalizedValue == normalizedReference;
  }

  Future<void> replaceAndDeleteCatalogItem({
    required String type,
    required CatalogItem item,
    CatalogItem? replacement,
  }) async {
    requirePermission(AppPermission.catalogManage);
    if (type != 'category' && type != 'unit') {
      throw ArgumentError('Unsupported catalog type.');
    }
    final list = type == 'category' ? _categories : _units;
    final activeItems = list.where((entry) => !entry.isDeleted).toList();
    if (activeItems.length <= 1) {
      throw StateError('At least one item must remain.');
    }
    final index = list.indexWhere((entry) => entry.id == item.id);
    if (index == -1 || list[index].isDeleted) return;

    final usageCount = productsUsingCatalogItem(type, item);
    if (usageCount > 0) {
      if (replacement == null || replacement.id == item.id) {
        throw StateError('A replacement item is required.');
      }
      if (!activeItems.any((entry) => entry.id == replacement.id)) {
        throw StateError('Replacement item was not found.');
      }
    }

    final now = DateTime.now();
    var productsChanged = false;
    if (usageCount > 0) {
      final replacementValue = _catalogReferenceValue(replacement!);
      if (replacementValue.trim().isEmpty) {
        throw StateError('Replacement item has no usable value.');
      }
      for (var i = 0; i < _products.length; i++) {
        final product = _products[i];
        if (product.isDeleted) continue;
        final currentValue =
            type == 'category' ? product.category : product.unit;
        if (!_catalogItemMatchesValue(item, currentValue)) continue;
        final updatedProduct = _markProductForSync(
          type == 'category'
              ? product.copyWith(category: replacementValue)
              : product.copyWith(unit: replacementValue),
          now,
        );
        _products[i] = updatedProduct;
        _recordSyncChange(
          entityType: 'product',
          entityId: updatedProduct.id,
          operation: 'update',
          payload: updatedProduct.toJson(),
        );
        productsChanged = true;
      }
    }

    final deletedItem = _withSyncMeta<CatalogItem>(
      list[index].copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    list[index] = deletedItem;
    _recordSyncChange(
      entityType: type,
      entityId: deletedItem.id,
      operation: 'delete',
      payload: deletedItem.toJson(),
    );

    await _saveDirty(
      products: productsChanged,
      categories: type == 'category',
      units: type == 'unit',
      sync: true,
    );
    notifyListeners();
  }
}
