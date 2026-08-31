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
    requireAnyPermission(<String>{
      AppPermission.productsManage,
      exists ? AppPermission.productsEdit : AppPermission.productsCreate,
    });
    final now = DateTime.now();
    final isCreate = index == null;
    final existingIndex = index ?? -1;
    final previousProduct = isCreate ? null : _products[existingIndex];
    final requestedInitialStock =
        isCreate && product.trackStock ? product.stock : 0.0;
    if (requestedInitialStock < -0.000001) {
      throw ArgumentError('Opening stock cannot be negative.');
    }
    final authoritativeStock = isCreate
        ? 0.0
        : await totalWarehouseStockFromSqlite(product.id);
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

Future<void> addOrUpdateProductsBulk(List<Product> products) async {
    if (products.isEmpty) return;
    final hasCreates = products.any((item) => _productIndexById[item.id] == null);
    final hasUpdates = products.any((item) => _productIndexById[item.id] != null);
    if (hasCreates) {
      requireAnyPermission(<String>{
        AppPermission.productsManage,
        AppPermission.productsCreate,
      });
    }
    if (hasUpdates) {
      requireAnyPermission(<String>{
        AppPermission.productsManage,
        AppPermission.productsEdit,
      });
    }
    final section = 'product.addOrUpdateBulk';
    final now = DateTime.now();
    final seenCodes = <String>{};
    final seenBarcodes = <String>{};
    var changedCount = 0;
    for (final product in products) {
      final index = _productIndexById[product.id];
      final isCreate = index == null;
      final normalizedProduct = product.code.trim().isEmpty
          ? product.copyWith(
              code: _generateUniqueProductCode(
                exceptProductId: product.id,
                reservedCodes: seenCodes,
              ),
            )
          : product;
      final normalizedCode = normalizedProduct.code.trim().toLowerCase();
      final normalizedBarcode = normalizedProduct.barcode.trim().toLowerCase();
      if (normalizedCode.isNotEmpty && !seenCodes.add(normalizedCode)) {
        throw ArgumentError('Duplicate product code in batch.');
      }
      if (normalizedBarcode.isNotEmpty &&
          !seenBarcodes.add(normalizedBarcode)) {
        throw ArgumentError('Duplicate product barcode in batch.');
      }
      final previousProduct = isCreate ? null : _products[index];
      _validateProduct(normalizedProduct, previousProduct: previousProduct);
      final syncedProduct = _markProductForSync(
        normalizedProduct,
        now,
        isCreate: isCreate,
      );
      if (isCreate) {
        _products.add(syncedProduct);
        _indexProductAt(_products.length - 1, syncedProduct);
      } else {
        _products[index] = syncedProduct;
        _indexProductAt(
          index,
          syncedProduct,
          previousProduct: previousProduct,
        );
      }
      _ensureDefaultProductPriceEntries(product: syncedProduct);
      _ensureProductCostEntries(product: syncedProduct);
      _recordSyncChange(
        entityType: 'product',
        entityId: syncedProduct.id,
        operation: isCreate ? 'create' : 'update',
        payload: syncedProduct.toJson(),
      );
      changedCount += 1;
    }
    _ensureCostingMethodHistory();
    await _traceAsync(
      section,
      'save_dirty',
      () => _saveDirty(products: true, sync: true),
      metadata: <String, Object?>{'count': changedCount},
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
    requireAnyPermission(<String>{
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
            normalizedName.toLowerCase() == AppStore.walkInCustomerName.toLowerCase())
        ? _withSyncMeta<Customer>(walkInCustomer, now, isCreate: false)
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

Future<void> addOrUpdateCustomersBulk(List<Customer> customers) async {
    if (customers.isEmpty) return;
    requirePermission(AppPermission.customersManage);
    final section = 'customer.addOrUpdateBulk';
    final now = DateTime.now();
    final seenNames = <String>{};
    var changedCount = 0;
    for (final customer in customers) {
      final normalizedName = customer.name.trim();
      if (normalizedName.isEmpty) {
        throw ArgumentError('Customer name is required.');
      }
      final normalizedKey = normalizedName.toLowerCase();
      if (!seenNames.add(normalizedKey)) {
        throw ArgumentError('Duplicate customer name in batch.');
      }
      final activeDuplicateId = _customerIdByNormalizedName[normalizedKey];
      final activeDuplicate = activeDuplicateId != null &&
          activeDuplicateId != customer.id &&
          activeDuplicateId != AppStore.walkInCustomerId;
      if (activeDuplicate) {
        throw ArgumentError(
          'Customer name already exists on this device. Sync duplicates will be reported as conflicts.',
        );
      }
      final index = _customerIndexById[customer.id];
      final isCreate = index == null;
      final syncedCustomer = _withSyncMeta<Customer>(
        customer.copyWith(name: normalizedName),
        now,
        isCreate: isCreate,
        clearDeletedAt: true,
      );
      if (isCreate) {
        _customers.add(syncedCustomer);
        _indexCustomerAt(_customers.length - 1, syncedCustomer);
      } else {
        final previousCustomer = _customers[index];
        _customers[index] = syncedCustomer;
        _indexCustomerAt(
          index,
          syncedCustomer,
          previousCustomer: previousCustomer,
        );
      }
      _recordSyncChange(
        entityType: 'customer',
        entityId: syncedCustomer.id,
        operation: isCreate ? 'create' : 'update',
        payload: syncedCustomer.toJson(),
      );
      changedCount += 1;
    }
    await _traceAsync(
      section,
      'save_dirty',
      () => _saveDirty(customers: true, sync: true),
      metadata: <String, Object?>{'count': changedCount},
    );
    notifyListeners();
  }

Future<void> deleteCustomer(String id) async {
    requirePermission(AppPermission.customersManage);
    final index = _customerIndexById[id];
    if (index == null) return;
    final previousCustomer = _customers[index];
    final customer = previousCustomer;
    final isWalkIn = customer.id == AppStore.walkInCustomerId ||
        customer.name.trim().toLowerCase() == AppStore.walkInCustomerName.toLowerCase();
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

Future<void> addOrUpdateSuppliersBulk(List<Supplier> suppliers) async {
    if (suppliers.isEmpty) return;
    requirePermission(AppPermission.suppliersManage);
    final section = 'supplier.addOrUpdateBulk';
    final now = DateTime.now();
    final seenNames = <String>{};
    var changedCount = 0;
    for (final supplier in suppliers) {
      if (supplier.name.trim().isEmpty) {
        throw ArgumentError('Supplier name is required.');
      }
      final normalizedName = supplier.name.trim().toLowerCase();
      if (!seenNames.add(normalizedName)) {
        throw ArgumentError('Duplicate supplier name in batch.');
      }
      final duplicateId = _supplierIdByNormalizedName[normalizedName];
      final duplicate = duplicateId != null && duplicateId != supplier.id;
      if (duplicate) {
        throw ArgumentError(
          'Supplier name already exists on this device. Sync duplicates will be reported as conflicts.',
        );
      }
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
        final previousSupplier = _suppliers[index];
        _suppliers[index] = syncedSupplier;
        _indexSupplierAt(
          index,
          syncedSupplier,
          previousSupplier: previousSupplier,
        );
      }
      _recordSyncChange(
        entityType: 'supplier',
        entityId: syncedSupplier.id,
        operation: isCreate ? 'create' : 'update',
        payload: syncedSupplier.toJson(),
      );
      changedCount += 1;
    }
    await _traceAsync(
      section,
      'save_dirty',
      () => _saveDirty(suppliers: true, sync: true),
      metadata: <String, Object?>{'count': changedCount},
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

Future<void> addOrUpdateExpense(Expense expense) async {
    requirePermission(AppPermission.expensesManage);
    if (expense.title.trim().isEmpty ||
        expense.category.trim().isEmpty ||
        !expense.amount.isFinite ||
        expense.amount <= 0) {
      throw ArgumentError('Invalid expense values.');
    }
    final now = DateTime.now();
    final index = _expenseIndexForId(expense.id);
    final isCreate = index == -1;
    if (!isCreate) {
      final current = _expenses[index];
      if (current.isPosted) {
        throw StateError(
          'Posted expenses cannot be edited. Cancel them first.',
        );
      }
      if (current.isCancelled) {
        throw StateError('Cancelled expenses cannot be edited.');
      }
    }
    final normalized = expense.copyWith(
      status: isCreate ? 'Draft' : expense.status,
    );
    final syncedExpense = _withSyncMeta<Expense>(
      normalized,
      now,
      isCreate: isCreate,
    );
    _putExpenseAtIndex(syncedExpense, isCreate ? _expenses.length : index);
    _recordSyncChange(
      entityType: 'expense',
      entityId: syncedExpense.id,
      operation: isCreate ? 'create' : 'update',
      payload: syncedExpense.toJson(),
    );
    await _saveDirty(expenses: true, sync: true);
    unawaited(
      AppLogger.info(
        area: 'expenses',
        action: isCreate ? 'create_expense' : 'update_expense',
        message: isCreate
            ? 'Expense created successfully.'
            : 'Expense updated successfully.',
        details:
            'expenseId=${syncedExpense.id} title=${syncedExpense.title} amount=${syncedExpense.amount}',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'expense',
        entityId: syncedExpense.id,
        action: isCreate ? 'create' : 'update',
        summary: isCreate ? 'Expense created' : 'Expense updated',
        details: jsonEncode(syncedExpense.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _activeUser?.fullName ?? _activeUser?.username ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'expenses',
        isImportant: true,
      ),
    );
    _touchExpensesData();
    notifyListeners();
  }

Future<void> postExpense(String id, {bool paidInCash = true}) async {
    requireAnyPermission(<String>{
      AppPermission.expensesManage,
      AppPermission.expensesApprove,
    });
    final normalizedId = id.trim();
    final index = _expenseIndexForId(normalizedId);
    final expense = index == -1
        ? await _expenseByIdFromSqlite(normalizedId)
        : _expenses[index];
    if (expense == null || expense.isDeleted) {
      throw ArgumentError('Expense not found.');
    }
    if (expense.isPosted || expense.isCancelled) return;
    final now = DateTime.now();
    final candidate = _expenseSyncMetaPreview(
      expense.copyWith(status: 'Posted'),
      now,
    );
    // Phase 5: cash/accounting must succeed before the Expense becomes Posted.
    // The preview above has no dirty-row side effect, so a failure cannot leave
    // a latent Posted row that might be persisted by a later unrelated save.
    if (paidInCash) {
      await AccountingService.recordExpense(candidate);
    } else {
      await AccountingService.recordExpenseOnCredit(candidate);
    }
    // The posted Expense + accounting + cash + compatibility ledger are already
    // committed atomically. Mirror only when this expense was already resident
    // in AppStore; SQLite remains the authoritative source for paged expenses.
    final posted = candidate;
    if (index != -1) {
      _expenses[index] = posted;
    }
    _recordSyncChange(
      entityType: 'expense',
      entityId: normalizedId,
      operation: 'post',
      payload: posted.toJson(),
    );
    await _saveDirty(expenses: false, accountTransactions: false, sync: true);
    await refreshAccountTransactionsFromSqlite();
    _touchExpensesData();
    notifyListeners();
  }

Future<void> createAndPostExpensesBulk(List<Expense> expenses) async {
    if (expenses.isEmpty) return;
    requirePermission(AppPermission.expensesManage);
    final section = 'expense.createAndPostBulk';
    final now = DateTime.now();
    final prepared =
        <({Expense source, Expense candidate, int index, bool isCreate})>[];

    // Build side-effect-free Posted previews first. AccountingService commits the
    // complete cash/accounting batch in one SQLite transaction. Only after that
    // succeeds do we mark AppStore rows dirty and expose Posted state.
    for (final expense in expenses) {
      if (expense.title.trim().isEmpty ||
          expense.category.trim().isEmpty ||
          !expense.amount.isFinite ||
          expense.amount <= 0) {
        throw ArgumentError('Invalid expense values.');
      }
      final index = _expenseIndexForId(expense.id);
      if (index != -1) {
        final current = _expenses[index];
        if (current.isPosted) {
          throw StateError(
            'Posted expenses cannot be edited. Cancel them first.',
          );
        }
        if (current.isCancelled) {
          throw StateError('Cancelled expenses cannot be edited.');
        }
      }
      final isCreate = index == -1;
      final source = expense.copyWith(status: 'Posted');
      final candidate = _expenseSyncMetaPreview(
        source,
        now,
        isCreate: isCreate,
      );
      prepared.add((
        source: source,
        candidate: candidate,
        index: index,
        isCreate: isCreate,
      ));
    }

    await AccountingService.recordExpensesBulk(
      prepared.map((item) => item.candidate).toList(growable: false),
    );

    for (final item in prepared) {
      // recordExpensesBulk already persisted this preview atomically.
      final syncedExpense = item.candidate;
      _putExpenseAtIndex(
        syncedExpense,
        item.isCreate ? _expenses.length : item.index,
      );
      _recordSyncChange(
        entityType: 'expense',
        entityId: syncedExpense.id,
        operation: item.isCreate ? 'create' : 'update',
        payload: syncedExpense.toJson(),
      );
      _recordSyncChange(
        entityType: 'expense',
        entityId: syncedExpense.id,
        operation: 'post',
        payload: syncedExpense.toJson(),
      );
    }
    await _traceAsync(
      section,
      'save_dirty',
      () => _saveDirty(
        productDerivedData: false,
        expenses: false,
        accountTransactions: false,
        sync: true,
      ),
      metadata: <String, Object?>{'count': prepared.length},
    );
    _touchExpensesData();
    notifyListeners();
  }

Future<void> deleteDraftExpense(String id) async {
    requireAnyPermission(<String>{
      AppPermission.expensesManage,
      AppPermission.expensesDelete,
    });
    final index = _expenseIndexForId(id);
    if (index == -1) return;
    final expense = _expenses[index];
    if (expense.isPosted) {
      throw StateError('Posted expenses cannot be deleted. Cancel them first.');
    }
    if (expense.isCancelled) {
      throw StateError(
        'Cancelled expenses require permanent delete permission.',
      );
    }
    final now = DateTime.now();
    final deleted = _withSyncMeta<Expense>(
      expense.copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    _putExpenseAtIndex(deleted, index);
    _recordSyncChange(
      entityType: 'expense',
      entityId: id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _saveDirty(expenses: true, sync: true);
    _touchExpensesData();
    notifyListeners();
  }

Future<void> cancelExpense(String id, {String reason = ''}) async {
    requireAnyPermission(<String>{
      AppPermission.expensesManage,
      AppPermission.expensesCancel,
    });
    final index = _expenseIndexForId(id);
    if (index == -1) throw ArgumentError('Expense not found.');
    final expense = _expenses[index];
    if (expense.isCancelled) return;
    if (!expense.isPosted) {
      throw StateError(
        'Only posted expenses can be cancelled. Delete draft expenses instead.',
      );
    }
    final now = DateTime.now();
    final cancelledPreview = expense.copyWith(
      status: 'Cancelled',
      cancelReason: reason.trim(),
      cancelledAt: now,
      cancelledByDeviceId: _deviceId,
    );
    final sqliteDb = SqliteMigrationManager.database;
    if (sqliteDb != null) {
      await CashReversalService(sqliteDb).reverseReference(
        referenceType: 'expense',
        referenceId: expense.id,
        reason: reason.trim().isEmpty ? 'Expense cancelled' : reason.trim(),
        createdBy: _actorName(),
        createdByUserId: _activeUser?.id ?? '',
        deviceId: _deviceId,
        occurredAt: now,
      );
    } else {
      await AccountingService.reverseEntryForReference(
        referenceType: 'expense',
        referenceId: expense.id,
        reason: reason.trim().isEmpty ? 'Expense cancelled' : reason.trim(),
        createdBy: _deviceId,
      );
    }
    final cancelled = sqliteDb != null
        ? _expenseSyncMetaPreview(cancelledPreview, now)
        : _withSyncMeta<Expense>(cancelledPreview, now);
    _putExpenseAtIndex(cancelled, index);
    if (sqliteDb == null) {
      await _reverseExpenseLedger(
        cancelled,
        now,
        reason: reason.trim().isEmpty ? 'Expense cancelled' : reason.trim(),
      );
    }
    _recordSyncChange(
      entityType: 'expense',
      entityId: id,
      operation: 'cancel',
      payload: cancelled.toJson(),
    );
    await _saveDirty(
      expenses: sqliteDb == null,
      accountTransactions: sqliteDb == null,
      sync: true,
    );
    _touchExpensesData();
    notifyListeners();
  }

Future<void> permanentlyDeleteCancelledExpense(String id) async {
    requirePermission(AppPermission.databaseManage);
    final index = _expenseIndexForId(id);
    if (index == -1) return;
    final expense = _expenses[index];
    if (!expense.isCancelled) {
      throw StateError('Only cancelled expenses can reach this audit guard.');
    }
    throw StateError(
      'Posted/cancelled expenses are retained for audit and cannot be permanently deleted. Use reversal/correction instead.',
    );
  }

}
