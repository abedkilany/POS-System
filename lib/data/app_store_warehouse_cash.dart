part of 'app_store.dart';

extension _AppStoreSplitWarehouseCash on AppStore {
  int _loadPurchaseCounter() {
    final raw = LocalDatabaseService.getString(AppStore._purchaseCounterKey);
    return int.tryParse(raw ?? '') ?? 0;
  }

  Future<Warehouse> createWarehouse({
    required String name,
    String code = '',
    String location = '',
  }) async {
    requirePermission(AppPermission.inventoryWarehousesManage);
    final cleanedName = name.trim();
    if (cleanedName.isEmpty) throw ArgumentError('Warehouse name is required.');
    _ensureDefaultWarehouse();
    if (_warehouses.any(
      (item) =>
          !item.isDeleted &&
          item.name.toLowerCase() == cleanedName.toLowerCase(),
    )) {
      throw ArgumentError('Warehouse already exists.');
    }
    final now = DateTime.now();
    // A timestamp alone is not a safe identifier on platforms whose clock
    // resolution can return the same microsecond value for rapid successive
    // calls (observed on Windows). Include the device identity for cross-device
    // uniqueness and deterministically suffix any local collision.
    final warehouseIdBase = '${now.microsecondsSinceEpoch}-$_deviceId';
    var warehouseId = warehouseIdBase;
    var warehouseIdCollision = 0;
    final existingWarehouseIds = _warehouses.map((item) => item.id).toSet();
    while (existingWarehouseIds.contains(warehouseId)) {
      warehouseIdCollision += 1;
      warehouseId = '$warehouseIdBase-$warehouseIdCollision';
    }
    final warehouse = Warehouse(
      id: warehouseId,
      name: cleanedName,
      code: code.trim(),
      location: location.trim(),
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      lastModifiedByDeviceId: _deviceId,
    );
    _warehouses.add(warehouse);
    _rememberSqliteDirtyBusinessRow(
        AppStore._warehousesKey, warehouse.toJson());
    _recordSyncChange(
      entityType: 'warehouse',
      entityId: warehouse.id,
      operation: 'create',
      payload: warehouse.toJson(),
    );
    await _saveDirty(warehouses: true, sync: true);
    unawaited(
      AppLogger.info(
        area: 'inventory',
        action: 'create_warehouse',
        message: 'Warehouse created successfully.',
        details: 'warehouseId=${warehouse.id} name=${warehouse.name}',
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
        entityType: 'warehouse',
        entityId: warehouse.id,
        action: 'create',
        summary: 'Warehouse created',
        details: jsonEncode(warehouse.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'inventory',
        isImportant: true,
      ),
    );
    notifyListeners();
    return warehouse;
  }

  Future<List<WarehouseTransferOrder>> recentWarehouseTransferOrders({
    int limit = 100,
  }) async {
    final db = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && db != null) {
      return BusinessSqliteStore.readWarehouseTransferOrders(db, limit: limit);
    }
    return const <WarehouseTransferOrder>[];
  }

  Future<WarehouseTransferOrder> createWarehouseTransferOrder({
    required String fromWarehouseId,
    required String toWarehouseId,
    required List<WarehouseTransferOrderItem> items,
    String notes = '',
  }) async {
    requirePermission(AppPermission.inventoryWarehousesManage);
    if (fromWarehouseId == toWarehouseId) {
      throw ArgumentError('Choose two different warehouses.');
    }
    if (items.isEmpty) {
      throw ArgumentError('Add at least one product to the transfer.');
    }
    _ensureDefaultWarehouse();
    final fromWarehouse = _warehouses.firstWhere(
      (item) => item.id == fromWarehouseId && !item.isDeleted,
      orElse: () => throw ArgumentError('Source warehouse not found.'),
    );
    final toWarehouse = _warehouses.firstWhere(
      (item) => item.id == toWarehouseId && !item.isDeleted,
      orElse: () => throw ArgumentError('Destination warehouse not found.'),
    );

    final normalizedItems = <WarehouseTransferOrderItem>[];
    final seenProductIds = <String>{};
    for (final item in items) {
      if (item.baseQuantity <= 0) {
        throw ArgumentError('Transfer quantities must be positive.');
      }
      if (!seenProductIds.add(item.productId)) {
        throw ArgumentError(
            'A product can only appear once in a transfer order.');
      }
      final productIndex = _productIndexById[item.productId];
      if (productIndex == null) throw ArgumentError('Product not found.');
      final product = _products[productIndex];
      if (!product.trackStock) {
        throw StateError('${product.name} does not track stock.');
      }
      normalizedItems.add(WarehouseTransferOrderItem(
        productId: product.id,
        productName: product.name,
        quantity: item.quantity,
        unitId: item.unitId,
        unitName: item.unitName.isEmpty ? product.unit : item.unitName,
        conversionToBase: item.conversionToBase,
        unitCost: _safeUsdCost(product),
      ));
    }

    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Warehouse transfer orders require SQLite storage.');
    }

    final now = DateTime.now();
    final transferId = now.microsecondsSinceEpoch.toString();
    final orderNo = 'TR-$transferId';
    final order = WarehouseTransferOrder(
      id: transferId,
      orderNo: orderNo,
      fromWarehouseId: fromWarehouse.id,
      fromWarehouseName: fromWarehouse.name,
      toWarehouseId: toWarehouse.id,
      toWarehouseName: toWarehouse.name,
      date: now,
      items: normalizedItems,
      notes: notes.trim(),
      createdByUserId: _activeUser?.id ?? '',
      createdByUserName: _actorName(),
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      lastModifiedByDeviceId: _deviceId,
    );
    final stockService = StockTransactionService(
      sqliteDb,
      deviceId: _deviceId,
      defaultStoreId: appIdentity.storeId,
      defaultBranchId: appIdentity.branchId,
      defaultSyncTarget: _stockTransactionSyncTarget,
      allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
    );
    final batchService = BatchInventoryService(sqliteDb);
    final transferMovements = <StockMovement>[];

    await _traceAsync<void>(
        'inventory.createTransferOrder', 'sqlite_transaction', () async {
      await sqliteDb.transaction(() async {
        for (var lineIndex = 0;
            lineIndex < normalizedItems.length;
            lineIndex += 1) {
          final item = normalizedItems[lineIndex];
          final product = _products[_productIndexById[item.productId]!];
          final baseQuantity = item.baseQuantity;
          final lineId = '$transferId-line-${lineIndex + 1}';
          final outMovement = StockMovement(
            id: '$transferId-${item.productId}-out-${lineIndex + 1}',
            productId: item.productId,
            productName: item.productName,
            type: 'transfer_out',
            quantity: -baseQuantity,
            date: now,
            referenceId: transferId,
            referenceNo: orderNo,
            reason: 'Warehouse transfer to ${toWarehouse.name}',
            notes: notes.trim(),
            warehouseId: fromWarehouse.id,
            warehouseName: fromWarehouse.name,
            movementGroupId: transferId,
            documentLineId: '$lineId-out',
            idempotencyKey: '$transferId:$lineId:out',
            unitCost: item.unitCost,
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            lastModifiedByDeviceId: _deviceId,
          );
          final inMovement = StockMovement(
            id: '$transferId-${item.productId}-in-${lineIndex + 1}',
            productId: item.productId,
            productName: item.productName,
            type: 'transfer_in',
            quantity: baseQuantity,
            date: now,
            referenceId: transferId,
            referenceNo: orderNo,
            reason: 'Warehouse transfer from ${fromWarehouse.name}',
            notes: notes.trim(),
            warehouseId: toWarehouse.id,
            warehouseName: toWarehouse.name,
            movementGroupId: transferId,
            documentLineId: '$lineId-in',
            idempotencyKey: '$transferId:$lineId:in',
            unitCost: item.unitCost,
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            lastModifiedByDeviceId: _deviceId,
          );

          await _ensureUnifiedBatchCutoverForProductInTransaction(
            sqliteDb,
            product: product,
            warehouseId: fromWarehouse.id,
            at: now,
          );
          await _ensureUnifiedBatchCutoverForProductInTransaction(
            sqliteDb,
            product: product,
            warehouseId: toWarehouse.id,
            at: now,
          );
          final allocations = await batchService.transferUnifiedInTransaction(
            product: product,
            fromWarehouseId: fromWarehouse.id,
            toWarehouseId: toWarehouse.id,
            quantity: baseQuantity,
            transferredAt: now,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            deviceId: _deviceId,
            allowNegativeStock: _storeProfile.allowNegativeStock,
          );
          for (var batchIndex = 0;
              batchIndex < allocations.length;
              batchIndex += 1) {
            final allocation = allocations[batchIndex];
            transferMovements.addAll(<StockMovement>[
              outMovement.copyWith(
                id: '${outMovement.id}-batch-$batchIndex',
                quantity: -allocation.quantity,
                batchId: allocation.batchId,
                unitCost: allocation.unitCost,
                documentLineId: '$lineId-out-batch-$batchIndex',
                idempotencyKey: '$transferId:$lineId:out:$batchIndex',
              ),
              inMovement.copyWith(
                id: '${inMovement.id}-batch-$batchIndex',
                quantity: allocation.quantity,
                batchId: allocation.batchId,
                unitCost: allocation.unitCost,
                documentLineId: '$lineId-in-batch-$batchIndex',
                idempotencyKey: '$transferId:$lineId:in:$batchIndex',
              ),
            ]);
          }
        }

        await stockService.recordMovementsInTransaction(
          operationType: 'warehouse_transfer_order',
          documentType: 'stock_transfer_order',
          documentId: transferId,
          movementGroupId: transferId,
          idempotencyKey: '$transferId:warehouse_transfer_order',
          movements: transferMovements,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          deviceId: _deviceId,
        );
        await _assertUnifiedBatchMovementBalancesInTransaction(
          batchService,
          transferMovements,
        );
        await InventoryTraceabilityService(sqliteDb)
            .assertTransferTraceabilityInTransaction(
          movementGroupId: transferId,
          storeId: appIdentity.storeId,
        );

        final payload = order.toJson();
        await sqliteDb.customInsert('''
          INSERT INTO warehouse_transfer_orders (
            id, entity_type, created_at, updated_at, deleted_at, device_id,
            sync_status, store_id, branch_id, version,
            last_modified_by_device_id, sort_index, order_no,
            from_warehouse_id, from_warehouse_name, to_warehouse_id,
            to_warehouse_name, document_date, status, notes,
            created_by_user_id, created_by_user_name, items_json, total_units
          ) VALUES (?, 'warehouse_transfer_order', ?, ?, '', ?, 'pending', ?, ?, 1,
                    ?, 0, ?, ?, ?, ?, ?, ?, 'completed', ?, ?, ?, ?, ?)
        ''', variables: <Variable<Object>>[
          Variable<String>(order.id),
          Variable<String>(order.createdAt.toIso8601String()),
          Variable<String>(order.updatedAt.toIso8601String()),
          Variable<String>(_deviceId),
          Variable<String>(appIdentity.storeId),
          Variable<String>(appIdentity.branchId),
          Variable<String>(_deviceId),
          Variable<String>(order.orderNo),
          Variable<String>(order.fromWarehouseId),
          Variable<String>(order.fromWarehouseName),
          Variable<String>(order.toWarehouseId),
          Variable<String>(order.toWarehouseName),
          Variable<String>(order.date.toIso8601String()),
          Variable<String>(order.notes),
          Variable<String>(order.createdByUserId),
          Variable<String>(order.createdByUserName),
          Variable<String>(jsonEncode(payload['items'])),
          Variable<double>(order.totalUnits),
        ]);
      });
    });

    _mirrorAuthoritativeStockMovements(transferMovements);
    await _refreshProductStockCompatibilityCache(
      normalizedItems.map((item) => item.productId).toSet(),
    );
    _recordSyncChange(
      entityType: 'warehouse_transfer_order',
      entityId: order.id,
      operation: 'create',
      payload: order.toJson(),
    );
    for (final movement in transferMovements) {
      _recordSyncChange(
        entityType: 'stock_movement',
        entityId: movement.id,
        operation: 'transfer',
        payload: movement.toJson(),
      );
    }
    unawaited(AuditLogger.record(
      entityType: 'warehouse_transfer_order',
      entityId: order.id,
      action: 'create',
      summary: 'Warehouse transfer order created',
      details: jsonEncode(order.toJson()),
      userId: _activeUser?.id ?? '',
      userName: _actorName(),
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      sessionId: _deviceId,
      traceId: _deviceId,
      deviceId: _deviceId,
      sourceModule: 'inventory',
      isImportant: true,
    ));
    notifyListeners();
    return order;
  }
}
