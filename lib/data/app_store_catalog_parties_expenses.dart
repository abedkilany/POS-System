part of 'app_store.dart';

extension _AppStoreSplitCatalogPartiesExpenses on AppStore {
  void _indexProductAt(int index, Product product, {Product? previousProduct}) {
    _productIndexById[product.id] = index;
    if (previousProduct != null) {
      final previousCode = previousProduct.code.trim().toLowerCase();
      if (previousCode.isNotEmpty &&
          _productIdByNormalizedCode[previousCode] == previousProduct.id) {
        _productIdByNormalizedCode.remove(previousCode);
      }
      final previousBarcode = previousProduct.barcode.trim().toLowerCase();
      if (previousBarcode.isNotEmpty &&
          _productIdByNormalizedBarcode[previousBarcode] ==
              previousProduct.id) {
        _productIdByNormalizedBarcode.remove(previousBarcode);
      }
    }
    if (product.isDeleted) return;
    final code = product.code.trim().toLowerCase();
    if (code.isNotEmpty) _productIdByNormalizedCode[code] = product.id;
    final barcode = product.barcode.trim().toLowerCase();
    if (barcode.isNotEmpty) {
      _productIdByNormalizedBarcode[barcode] = product.id;
    }
  }

  void _unindexProduct(Product product) {
    final index = _productIndexById[product.id];
    if (index != null && index >= 0 && index < _products.length) {
      _productIndexById[product.id] = index;
    }
    final code = product.code.trim().toLowerCase();
    if (code.isNotEmpty && _productIdByNormalizedCode[code] == product.id) {
      _productIdByNormalizedCode.remove(code);
    }
    final barcode = product.barcode.trim().toLowerCase();
    if (barcode.isNotEmpty &&
        _productIdByNormalizedBarcode[barcode] == product.id) {
      _productIdByNormalizedBarcode.remove(barcode);
    }
  }

  void _indexCustomerAt(int index, Customer customer,
      {Customer? previousCustomer}) {
    _customerIndexById[customer.id] = index;
    if (previousCustomer != null) {
      final previousName = previousCustomer.name.trim().toLowerCase();
      if (previousName.isNotEmpty &&
          _customerIdByNormalizedName[previousName] == previousCustomer.id) {
        _customerIdByNormalizedName.remove(previousName);
      }
    }
    if (customer.isDeleted) return;
    final normalizedName = customer.name.trim().toLowerCase();
    if (normalizedName.isNotEmpty) {
      _customerIdByNormalizedName[normalizedName] = customer.id;
    }
  }

  void _indexSupplierAt(int index, Supplier supplier,
      {Supplier? previousSupplier}) {
    _supplierIndexById[supplier.id] = index;
    if (previousSupplier != null) {
      final previousName = previousSupplier.name.trim().toLowerCase();
      if (previousName.isNotEmpty &&
          _supplierIdByNormalizedName[previousName] == previousSupplier.id) {
        _supplierIdByNormalizedName.remove(previousName);
      }
    }
    if (supplier.isDeleted) return;
    final normalizedName = supplier.name.trim().toLowerCase();
    if (normalizedName.isNotEmpty) {
      _supplierIdByNormalizedName[normalizedName] = supplier.id;
    }
  }

  Future<void> addOrUpdateProduct(Product product) async {
    final section = 'product.addOrUpdate';
    final index = _productIndexById[product.id];
    final exists = index != null;
    _requireAnyPermission(<String>{
      AppPermission.productsManage,
      exists ? AppPermission.productsEdit : AppPermission.productsCreate,
    });
    // Product saves also flush product-derived data. Load costing history from
    // its authoritative source first so an unloaded cache can never be
    // mistaken for an empty history and seeded with a bogus Initial row.
    await _ensureCostingMethodHistoryLoaded();
    final now = DateTime.now();
    final isCreate = index == null;
    final existingIndex = index ?? -1;
    final previousProduct = isCreate ? null : _products[existingIndex];
    final requestedInitialStock =
        isCreate && product.trackStock ? product.stock : 0.0;
    if (requestedInitialStock < -0.000001) {
      throw ArgumentError('Opening stock cannot be negative.');
    }
    final authoritativeStock =
        isCreate ? 0.0 : await _totalWarehouseStockFromSqlite(product.id);
    final sourceNeutralProduct = product.copyWith(stock: authoritativeStock);
    final normalizedProduct = sourceNeutralProduct.code.trim().isEmpty
        ? sourceNeutralProduct.copyWith(
            code: _generateUniqueProductCode(exceptProductId: product.id),
          )
        : sourceNeutralProduct;

    final enablesExpiryTracking = normalizedProduct.expiryTrackingEnabled &&
        (previousProduct?.expiryTrackingEnabled != true);
    final disablesExpiryTracking = !normalizedProduct.expiryTrackingEnabled &&
        (previousProduct?.expiryTrackingEnabled == true);
    if (enablesExpiryTracking && authoritativeStock > 0.000001) {
      throw StateError(
        'Move existing stock into dated batches before enabling expiration tracking.',
      );
    }
    if (disablesExpiryTracking && authoritativeStock > 0.000001) {
      throw StateError(
        'Deplete or migrate dated stock before disabling expiration tracking.',
      );
    }
    _traceSync(section, 'validate', () {
      _validateProduct(normalizedProduct, previousProduct: previousProduct);
    }, metadata: <String, Object?>{
      'productId': normalizedProduct.id,
      'isCreate': isCreate
    });
    final syncedProduct = _traceSyncResult<Product>(
      section,
      'mark_sync',
      () => _markProductForSync(
        normalizedProduct,
        now,
        isCreate: isCreate,
      ),
      metadata: <String, Object?>{
        'productId': normalizedProduct.id,
        'isCreate': isCreate
      },
    );
    if (isCreate) {
      _products.add(syncedProduct);
      _indexProductAt(_products.length - 1, syncedProduct);
    } else {
      final existingIndex = index;
      _products[existingIndex] = syncedProduct;
      _indexProductAt(
        existingIndex,
        syncedProduct,
        previousProduct: previousProduct,
      );
    }
    _traceSync(section, 'ensure_price_entries', () {
      _ensureDefaultProductPriceEntries(product: syncedProduct);
    }, metadata: <String, Object?>{'productId': syncedProduct.id});
    _traceSync(section, 'ensure_cost_entries', () {
      _ensureProductCostEntries(product: syncedProduct);
    }, metadata: <String, Object?>{'productId': syncedProduct.id});
    _traceSync(section, 'ensure_costing_history', _ensureCostingMethodHistory);
    _traceSync(section, 'record_sync_change', () {
      _recordSyncChange(
        entityType: 'product',
        entityId: syncedProduct.id,
        operation: isCreate ? 'create' : 'update',
        payload: syncedProduct.toJson(),
      );
    }, metadata: <String, Object?>{
      'productId': syncedProduct.id,
      'isCreate': isCreate
    });
    await _traceAsync(
        section, 'save_dirty', () => _saveDirty(products: true, sync: true),
        metadata: <String, Object?>{
          'productId': syncedProduct.id,
          'isCreate': isCreate
        });
    if (isCreate && requestedInitialStock > 0.000001) {
      await _createOpeningStockForNewProduct(
        syncedProduct,
        requestedInitialStock,
      );
    }
    unawaited(
      AppLogger.info(
        area: 'products',
        action: isCreate ? 'create_product' : 'update_product',
        message: isCreate
            ? 'Product created successfully.'
            : 'Product updated successfully.',
        details:
            'productId=${syncedProduct.id} code=${syncedProduct.code} name=${syncedProduct.name}',
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
        entityType: 'product',
        entityId: syncedProduct.id,
        action: isCreate ? 'create' : 'update',
        summary: isCreate ? 'Product created' : 'Product updated',
        details: jsonEncode(syncedProduct.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'products',
        isImportant: true,
      ),
    );
    notifyListeners();
  }

  bool isProductReferenced(String productId) {
    if (productId.trim().isEmpty) return false;
    final usedInSales = _sales.any(
      (sale) =>
          !sale.isDeleted &&
          sale.items.any((item) => item.productId == productId),
    );
    if (usedInSales) return true;
    final usedInPurchases = _purchases.any(
      (purchase) =>
          !purchase.isDeleted &&
          purchase.items.any((item) => item.productId == productId),
    );
    if (usedInPurchases) return true;
    return _stockMovements.any((movement) => movement.productId == productId);
  }

  Future<void> _createOpeningStockForNewProduct(
    Product product,
    double quantity,
  ) async {
    if (!product.trackStock || quantity <= 0.000001) return;
    if (product.expiryTrackingEnabled) {
      throw LocalizedDomainException(
        'error_expiry_batches_required',
        values: {'product': product.name},
        fallback:
            'Opening stock for ${product.name} requires an expiry batch. Create the product with zero opening stock, then receive or adjust a dated batch.',
      );
    }
    _ensureDefaultWarehouse();
    final now = DateTime.now();
    final warehouse = _warehouses.firstWhere(
      (item) => item.id == Warehouse.defaultId && !item.isDeleted,
      orElse: () => Warehouse(
        id: Warehouse.defaultId,
        name: Warehouse.defaultName,
        isDefault: true,
      ),
    );
    final movement = StockMovement(
      id: '${product.id}-opening-stock',
      productId: product.id,
      productName: product.name,
      type: 'opening_stock',
      quantity: quantity,
      date: now,
      referenceId: product.id,
      referenceNo: product.code,
      reason: 'Opening stock at product creation',
      notes: 'Authoritative warehouse opening quantity',
      warehouseId: warehouse.id,
      warehouseName: warehouse.name,
      movementGroupId: '${product.id}-opening-stock',
      documentLineId: '${product.id}-opening-stock-line',
      idempotencyKey: '${product.id}:opening-stock',
      unitCost: _safeUsdCost(product),
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      lastModifiedByDeviceId: _deviceId,
    );

    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      final stockService = StockTransactionService(
        sqliteDb,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => false,
      );
      final batchService = BatchInventoryService(sqliteDb);
      final unitCost = _safeUsdCost(product);
      late BatchAllocation openingBatch;
      late StockMovement postedMovement;
      await sqliteDb.transaction(() async {
        openingBatch = await batchService.addUnifiedBatchStockInTransaction(
          product: product,
          warehouseId: warehouse.id,
          batchId: '${product.id}-opening-stock-batch',
          quantity: quantity,
          unitCost: unitCost,
          sourceType: 'opening_stock',
          sourceId: product.id,
          sourceLineId: '${product.id}:opening-stock',
          receivedAt: now,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          deviceId: _deviceId,
        );
        postedMovement = movement.copyWith(
          batchId: openingBatch.batchId,
          unitCost: openingBatch.unitCost,
        );
        await stockService.recordMovementsInTransaction(
          operationType: 'opening_stock',
          documentType: 'product',
          documentId: product.id,
          movementGroupId: movement.movementGroupId,
          idempotencyKey: '${product.id}:opening-stock-op',
          movements: <StockMovement>[postedMovement],
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          deviceId: _deviceId,
        );
        await batchService.assertWarehouseBatchBalanceInTransaction(
          productId: product.id,
          warehouseId: warehouse.id,
          storeId: appIdentity.storeId,
        );
      });
      _mirrorAuthoritativeStockMovements(<StockMovement>[postedMovement]);
      await _refreshProductStockCompatibilityCache(<String>[product.id]);
      _inventoryCostLayers
        ..clear()
        ..addAll(await BusinessSqliteStore.readInventoryCostLayers(sqliteDb));
      _rebuildInventoryCostLayerLookupCache();
      _recordInventoryBatchSyncChanges(
        product: product,
        allocations: <BatchAllocation>[openingBatch],
        sourceType: 'opening_stock',
        sourceId: product.id,
        sourceLineId: '${product.id}:opening-stock',
        now: now,
        unitCost: unitCost,
      );
      _recordSyncChange(
        entityType: 'stock_movement',
        entityId: postedMovement.id,
        operation: 'opening_stock',
        payload: postedMovement.toJson(),
      );
      await _saveDirty(
        products: false,
        productDerivedData: false,
        stockMovements: false,
        sync: true,
      );
      return;
    }

    final index = _productIndexById[product.id];
    if (index != null) {
      _products[index] = _products[index].copyWith(stock: quantity);
    }
    _addStockMovement(movement, recordSync: true);
    await _saveDirty(
      products: true,
      productDerivedData: false,
      stockMovements: true,
      sync: true,
    );
  }

  Future<void> deleteProduct(String id) async {
    _requireAnyPermission(<String>{
      AppPermission.productsManage,
      AppPermission.productsDelete,
    });
    final index = _productIndexById[id];
    if (index == null) return;
    if (isProductReferenced(id)) {
      throw StateError(
        'Cannot delete a product that is used by sales, purchases, or stock movements. Deactivate it instead.',
      );
    }
    final now = DateTime.now();
    final previousProduct = _products[index];
    final deletedProduct = _withSyncMeta<Product>(
      previousProduct.copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    _products[index] = deletedProduct;
    _recordSyncChange(
      entityType: 'product',
      entityId: id,
      operation: 'delete',
      payload: deletedProduct.toJson(),
    );
    _unindexProduct(previousProduct);
    _removeProductPricingLookupEntries(id);
    final affectedPrices = _softDeleteSupplierProductPrices(
      productId: id,
      now: now,
      reason: 'Product deleted',
    );
    await _saveDirty(
      products: true,
      productDerivedData: false,
      supplierProductPrices: affectedPrices > 0,
      sync: true,
    );
    unawaited(
      AppLogger.info(
        area: 'products',
        action: 'delete_product',
        message: 'Product deleted successfully.',
        details: 'productId=$id affectedSupplierProductPrices=$affectedPrices',
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
        entityType: 'product',
        entityId: id,
        action: 'delete',
        summary: 'Product deleted',
        details: jsonEncode(deletedProduct.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'products',
        isImportant: true,
      ),
    );
    notifyListeners();
  }

  int _softDeleteSupplierProductPrices({
    String? productId,
    String? supplierId,
    required DateTime now,
    String reason = '',
  }) {
    var affected = 0;
    for (var i = 0; i < _supplierProductPrices.length; i++) {
      final item = _supplierProductPrices[i];
      if (item.isDeleted) continue;
      final matchesProduct = productId == null || item.productId == productId;
      final matchesSupplier =
          supplierId == null || item.supplierId == supplierId;
      if (!matchesProduct || !matchesSupplier) continue;
      final updated = _withSyncMeta<SupplierProductPrice>(
        item.copyWith(
          deletedAt: now,
          notes: reason.trim().isEmpty
              ? item.notes
              : [
                  item.notes,
                  reason,
                ].where((part) => part.trim().isNotEmpty).join(' — '),
        ),
        now,
        clearDeletedAt: false,
      );
      _supplierProductPrices[i] = updated;
      _recordSyncChange(
        entityType: 'supplier_product_price',
        entityId: updated.id,
        operation: 'delete',
        payload: updated.toJson(),
      );
      affected++;
    }
    return affected;
  }

  Future<void> addOrUpdateCustomer(Customer customer) async {
    final section = 'customer.addOrUpdate';
    requirePermission(AppPermission.customersManage);
    if (customer.name.trim().isEmpty) {
      throw ArgumentError('Customer name is required.');
    }
    final normalizedName = customer.name.trim();
    final activeDuplicateId =
        _customerIdByNormalizedName[normalizedName.toLowerCase()];
    final activeDuplicate = activeDuplicateId != null &&
        activeDuplicateId != customer.id &&
        activeDuplicateId != AppStore.walkInCustomerId;
    if (activeDuplicate) {
      throw ArgumentError(
        'Customer name already exists on this device. Sync duplicates will be reported as conflicts.',
      );
    }
    final now = DateTime.now();
    final incoming = (customer.id == AppStore.walkInCustomerId ||
            normalizedName.toLowerCase() ==
                AppStore.walkInCustomerName.toLowerCase())
        ? _withSyncMeta<Customer>(_walkInCustomer, now, isCreate: false)
        : _withSyncMeta<Customer>(
            customer.copyWith(name: normalizedName),
            now,
            isCreate: false,
          );
    final index = _customerIndexById[incoming.id];

    final isCreate = index == null;
    final baseCustomer = isCreate
        ? incoming
        : (() {
            final existingIndex = index;
            return incoming.copyWith(
              id: _customers[existingIndex].id,
              clearDeletedAt: true,
            );
          })();
    final syncedCustomer = _withSyncMeta<Customer>(
      baseCustomer,
      now,
      isCreate: isCreate,
      clearDeletedAt: true,
    );
    if (isCreate) {
      _customers.add(syncedCustomer);
      _indexCustomerAt(_customers.length - 1, syncedCustomer);
    } else {
      final existingIndex = index;
      final previousCustomer = _customers[existingIndex];
      _customers[existingIndex] = syncedCustomer;
      _indexCustomerAt(
        existingIndex,
        syncedCustomer,
        previousCustomer: previousCustomer,
      );
    }
    _traceSync(section, 'record_sync_change', () {
      _recordSyncChange(
        entityType: 'customer',
        entityId: syncedCustomer.id,
        operation: isCreate ? 'create' : 'update',
        payload: syncedCustomer.toJson(),
      );
    }, metadata: <String, Object?>{
      'customerId': syncedCustomer.id,
      'isCreate': isCreate
    });
    await _traceAsync(
        section, 'save_dirty', () => _saveDirty(customers: true, sync: true),
        metadata: <String, Object?>{
          'customerId': syncedCustomer.id,
          'isCreate': isCreate
        });
    unawaited(
      AppLogger.info(
        area: 'customers',
        action: isCreate ? 'create_customer' : 'update_customer',
        message: isCreate
            ? 'Customer created successfully.'
            : 'Customer updated successfully.',
        details: 'customerId=${syncedCustomer.id} name=${syncedCustomer.name}',
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
        entityId: syncedCustomer.id,
        action: isCreate ? 'create' : 'update',
        summary: isCreate ? 'Customer created' : 'Customer updated',
        details: jsonEncode(syncedCustomer.toJson()),
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
}
