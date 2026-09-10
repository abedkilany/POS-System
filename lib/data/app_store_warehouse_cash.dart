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
    _rememberSqliteDirtyBusinessRow(AppStore._warehousesKey, warehouse.toJson());
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

Future<WarehouseTransferOrder> editWarehouseTransferOrder({
    required String orderId,
    required int expectedVersion,
    required String fromWarehouseId,
    required String toWarehouseId,
    required List<WarehouseTransferOrderItem> items,
    String? notes,
    DateTime? date,
  }) async {
    requirePermission(AppPermission.inventoryWarehousesManage);
    final id = orderId.trim();
    if (id.isEmpty) throw ArgumentError('Transfer order id is required.');
    if (fromWarehouseId == toWarehouseId) {
      throw ArgumentError('Choose two different warehouses.');
    }
    if (items.isEmpty) {
      throw ArgumentError('Add at least one product to the transfer.');
    }
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Warehouse transfer editing requires SQLite storage.');
    }
    _ensureDefaultWarehouse();

    Future<WarehouseTransferOrder> loadOrder() async {
      final row = await sqliteDb.customSelect(
        '''
        SELECT id, order_no AS orderNo,
               from_warehouse_id AS fromWarehouseId,
               from_warehouse_name AS fromWarehouseName,
               to_warehouse_id AS toWarehouseId,
               to_warehouse_name AS toWarehouseName,
               document_date AS date, status, notes,
               created_by_user_id AS createdByUserId,
               created_by_user_name AS createdByUserName,
               items_json AS itemsJson,
               created_at AS createdAt, updated_at AS updatedAt,
               device_id AS deviceId, sync_status AS syncStatus,
               store_id AS storeId, branch_id AS branchId, version,
               last_modified_by_device_id AS lastModifiedByDeviceId
        FROM warehouse_transfer_orders
        WHERE id = ? AND deleted_at = ''
        LIMIT 1
        ''',
        variables: <Variable<Object>>[Variable<String>(id)],
      ).getSingleOrNull();
      if (row == null) throw StateError('Warehouse transfer order not found.');
      final data = Map<String, dynamic>.from(row.data);
      try {
        data['items'] = jsonDecode(data.remove('itemsJson')?.toString() ?? '[]');
      } catch (_) {
        data['items'] = const <dynamic>[];
      }
      return WarehouseTransferOrder.fromJson(data);
    }

    Future<List<StockMovement>> activeTransferMovements() async {
      final rows = await sqliteDb.customSelect(
        '''
        SELECT sm.id,
               sm.product_id AS productId,
               sm.product_name AS productName,
               sm.movement_type AS type,
               sm.quantity,
               sm.movement_date AS date,
               sm.reference_id AS referenceId,
               sm.reference_no AS referenceNo,
               sm.reason,
               sm.adjustment_category AS adjustmentCategory,
               sm.notes,
               sm.evidence_ref AS evidenceRef,
               sm.warehouse_id AS warehouseId,
               sm.warehouse_name AS warehouseName,
               sm.batch_id AS batchId,
               sm.movement_group_id AS movementGroupId,
               sm.document_line_id AS documentLineId,
               sm.source_movement_id AS sourceMovementId,
               sm.reversal_of_movement_id AS reversalOfMovementId,
               sm.idempotency_key AS idempotencyKey,
               sm.unit_cost AS unitCost,
               sm.created_at AS createdAt,
               sm.updated_at AS updatedAt,
               sm.device_id AS deviceId,
               sm.sync_status AS syncStatus,
               sm.store_id AS storeId,
               sm.branch_id AS branchId,
               sm.version,
               sm.last_modified_by_device_id AS lastModifiedByDeviceId,
               sm.reviewed_at AS reviewedAt,
               sm.reviewed_by AS reviewedBy,
               sm.review_note AS reviewNote
        FROM stock_movements sm
        WHERE sm.reference_id = ? AND sm.deleted_at = ''
          AND sm.movement_type IN ('transfer_out', 'transfer_in')
          AND sm.reversal_of_movement_id = ''
          AND NOT EXISTS (
            SELECT 1 FROM stock_movements rev
            WHERE rev.reversal_of_movement_id = sm.id AND rev.deleted_at = ''
          )
        ORDER BY sm.created_at, sm.id
        ''',
        variables: <Variable<Object>>[Variable<String>(id)],
      ).get();
      return rows
          .map((row) => StockMovement.fromJson(
                Map<String, dynamic>.from(row.data),
              ))
          .toList(growable: false);
    }

    late Warehouse fromWarehouse;
    late Warehouse toWarehouse;
    late List<WarehouseTransferOrderItem> normalizedItems;
    late List<StockMovement> oldActiveMovements;
    final committedMovements = <StockMovement>[];
    final touchedProductIds = <String>{};
    late WarehouseTransferOrder edited;

    await sqliteDb.transaction(() async {
      final stockService = StockTransactionService(
        sqliteDb,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
      );
      final batchService = BatchInventoryService(sqliteDb);
      final pipeline = PostedDocumentEditPipeline<WarehouseTransferOrder>(
        loadAuthoritative: loadOrder,
        validatePermission: (current) async {
          requirePermission(AppPermission.inventoryWarehousesManage);
          if (current.status.toLowerCase() != 'completed') {
            throw StateError('Only completed transfer orders can be edited.');
          }
        },
        validateVersion: (current) async {
          if (current.version != expectedVersion) {
            throw StateError(
              'Transfer order changed by another user. Reload before editing.',
            );
          }
        },
        validateDependencies: (current) async {
          fromWarehouse = _warehouses.firstWhere(
            (item) => item.id == fromWarehouseId && !item.isDeleted && item.isActive,
            orElse: () => throw ArgumentError('Source warehouse not found.'),
          );
          toWarehouse = _warehouses.firstWhere(
            (item) => item.id == toWarehouseId && !item.isDeleted && item.isActive,
            orElse: () => throw ArgumentError('Destination warehouse not found.'),
          );
          normalizedItems = <WarehouseTransferOrderItem>[];
          final seenProductIds = <String>{};
          for (final item in items) {
            if (!item.baseQuantity.isFinite || item.baseQuantity <= 0) {
              throw ArgumentError('Transfer quantities must be positive.');
            }
            if (!seenProductIds.add(item.productId)) {
              throw ArgumentError(
                'A product can only appear once in a transfer order.',
              );
            }
            final productIndex = _productIndexById[item.productId];
            if (productIndex == null) throw ArgumentError('Product not found.');
            final product = _products[productIndex];
            if (!product.trackStock) {
              throw StateError('${product.name} does not track stock.');
            }
            touchedProductIds.add(product.id);
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
          for (final item in current.items) {
            touchedProductIds.add(item.productId);
          }

          oldActiveMovements = await activeTransferMovements();
          if (oldActiveMovements.isEmpty) {
            throw StateError(
              'Active stock movements for this transfer are missing.',
            );
          }
          for (final movement in oldActiveMovements) {
            if (movement.batchId.trim().isEmpty) {
              throw StateError(
                'Transfer movement ${movement.id} has no batch identity.',
              );
            }
            if (movement.type != 'transfer_in') continue;
            final downstream = await sqliteDb.customSelect(
              '''
              SELECT sm.id
              FROM stock_movements sm
              WHERE sm.deleted_at = ''
                AND sm.store_id = ? AND sm.warehouse_id = ?
                AND sm.product_id = ? AND sm.batch_id = ?
                AND sm.created_at > ?
                AND sm.movement_group_id <> ?
                AND sm.reversal_of_movement_id = ''
                AND NOT EXISTS (
                  SELECT 1 FROM stock_movements rev
                  WHERE rev.reversal_of_movement_id = sm.id
                    AND rev.deleted_at = ''
                )
              LIMIT 1
              ''',
              variables: <Variable<Object>>[
                Variable<String>(movement.storeId.isEmpty ? appIdentity.storeId : movement.storeId),
                Variable<String>(movement.warehouseId),
                Variable<String>(movement.productId),
                Variable<String>(movement.batchId),
                Variable<String>(movement.createdAt.toUtc().toIso8601String()),
                Variable<String>(movement.movementGroupId),
              ],
            ).getSingleOrNull();
            if (downstream != null) {
              throw StateError(
                'Transfer cannot be edited because batch ${movement.batchId} '
                'has a downstream movement in ${movement.warehouseName}.',
              );
            }
          }
        },
        reverseOperationalEffects: (current) async {
          final now = DateTime.now().toUtc();
          final reverseGroup =
              '${current.id}:transfer_edit:v${current.version + 1}:reverse';
          final reversals = <StockMovement>[];
          for (final original in oldActiveMovements) {
            final productIndex = _productIndexById[original.productId];
            if (productIndex == null) {
              throw StateError('Transfer product ${original.productId} is missing.');
            }
            final product = _products[productIndex];
            await batchService.reverseUnifiedMovementEffectInTransaction(
              product: product,
              warehouseId: original.warehouseId,
              batchId: original.batchId,
              movementQuantity: original.quantity,
              unitCost: original.unitCost,
              reversedAt: now,
              storeId: original.storeId.isEmpty
                  ? appIdentity.storeId
                  : original.storeId,
              branchId: appIdentity.branchId,
              deviceId: _deviceId,
            );
            reversals.add(original.copyWith(
              id: '$reverseGroup:${original.id}',
              type: '${original.type}_reversal',
              quantity: -original.quantity,
              date: now,
              reason: 'Transfer order edited',
              movementGroupId: reverseGroup,
              documentLineId: '$reverseGroup:${original.documentLineId}',
              sourceMovementId: original.id,
              reversalOfMovementId: original.id,
              idempotencyKey: '$reverseGroup:${original.id}',
              createdAt: now,
              updatedAt: now,
              deviceId: _deviceId,
              syncStatus: 'pending',
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              lastModifiedByDeviceId: _deviceId,
              clearReviewedAt: true,
              reviewedBy: '',
              reviewNote: '',
            ));
          }
          await stockService.recordMovementsInTransaction(
            operationType: 'warehouse_transfer_order_edit_reverse',
            documentType: 'stock_transfer_order',
            documentId: current.id,
            movementGroupId: reverseGroup,
            idempotencyKey: reverseGroup,
            movements: reversals,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            deviceId: _deviceId,
          );
          committedMovements.addAll(reversals);
          for (final original in oldActiveMovements) {
            await batchService.assertWarehouseBatchBalanceInTransaction(
              productId: original.productId,
              warehouseId: original.warehouseId,
              storeId: appIdentity.storeId,
            );
          }
        },
        reverseAccountingEffects: (current) async {},
        applyChanges: (current) async {
          final now = DateTime.now().toUtc();
          final next = WarehouseTransferOrder(
            id: current.id,
            orderNo: current.orderNo,
            fromWarehouseId: fromWarehouse.id,
            fromWarehouseName: fromWarehouse.name,
            toWarehouseId: toWarehouse.id,
            toWarehouseName: toWarehouse.name,
            date: (date ?? current.date).toUtc(),
            items: normalizedItems,
            status: 'completed',
            notes: notes ?? current.notes,
            createdByUserId: current.createdByUserId,
            createdByUserName: current.createdByUserName,
            createdAt: current.createdAt,
            updatedAt: now,
            deviceId: _deviceId,
            syncStatus: 'pending',
            storeId: current.storeId.isEmpty ? appIdentity.storeId : current.storeId,
            branchId:
                current.branchId.isEmpty ? appIdentity.branchId : current.branchId,
            version: current.version + 1,
            lastModifiedByDeviceId: _deviceId,
          );
          final updated = await sqliteDb.customUpdate(
            '''
            UPDATE warehouse_transfer_orders
            SET from_warehouse_id = ?, from_warehouse_name = ?,
                to_warehouse_id = ?, to_warehouse_name = ?, document_date = ?,
                notes = ?, items_json = ?, total_units = ?, updated_at = ?,
                device_id = ?, sync_status = 'pending', version = version + 1,
                last_modified_by_device_id = ?
            WHERE id = ? AND deleted_at = '' AND status = 'completed'
              AND version = ?
            ''',
            variables: <Variable<Object>>[
              Variable<String>(next.fromWarehouseId),
              Variable<String>(next.fromWarehouseName),
              Variable<String>(next.toWarehouseId),
              Variable<String>(next.toWarehouseName),
              Variable<String>(next.date.toIso8601String()),
              Variable<String>(next.notes.trim()),
              Variable<String>(jsonEncode(
                next.items.map((item) => item.toJson()).toList(growable: false),
              )),
              Variable<double>(next.totalUnits),
              Variable<String>(now.toIso8601String()),
              Variable<String>(_deviceId),
              Variable<String>(_deviceId),
              Variable<String>(current.id),
              Variable<int>(expectedVersion),
            ],
          );
          if (updated != 1) {
            throw StateError('Transfer order changed before edit commit.');
          }
          return next;
        },
        rebuildOperationalEffects: (updated) async {
          final groupId =
              '${updated.id}:transfer_edit:v${updated.version}';
          final movements = <StockMovement>[];
          final movementTime = DateTime.now().toUtc();
          for (var lineIndex = 0;
              lineIndex < updated.items.length;
              lineIndex += 1) {
            final item = updated.items[lineIndex];
            final productIndex = _productIndexById[item.productId];
            if (productIndex == null) {
              throw StateError('Transfer product ${item.productId} is missing.');
            }
            final product = _products[productIndex];
            await _ensureUnifiedBatchCutoverForProductInTransaction(
              sqliteDb,
              product: product,
              warehouseId: updated.fromWarehouseId,
              at: updated.date,
            );
            await _ensureUnifiedBatchCutoverForProductInTransaction(
              sqliteDb,
              product: product,
              warehouseId: updated.toWarehouseId,
              at: updated.date,
            );
            final allocations = await batchService.transferUnifiedInTransaction(
              product: product,
              fromWarehouseId: updated.fromWarehouseId,
              toWarehouseId: updated.toWarehouseId,
              quantity: item.baseQuantity,
              transferredAt: updated.date,
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              deviceId: _deviceId,
              allowNegativeStock: _storeProfile.allowNegativeStock,
            );
            for (var batchIndex = 0;
                batchIndex < allocations.length;
                batchIndex += 1) {
              final allocation = allocations[batchIndex];
              final lineId = '$groupId-line-${lineIndex + 1}-batch-$batchIndex';
              movements.addAll(<StockMovement>[
                StockMovement(
                  id: '$groupId:${item.productId}:out:$batchIndex',
                  productId: item.productId,
                  productName: item.productName,
                  type: 'transfer_out',
                  quantity: -allocation.quantity,
                  date: updated.date,
                  referenceId: updated.id,
                  referenceNo: updated.orderNo,
                  reason: 'Warehouse transfer to ${updated.toWarehouseName}',
                  notes: updated.notes,
                  warehouseId: updated.fromWarehouseId,
                  warehouseName: updated.fromWarehouseName,
                  batchId: allocation.batchId,
                  movementGroupId: groupId,
                  documentLineId: '$lineId-out',
                  idempotencyKey: '$lineId:out',
                  unitCost: allocation.unitCost,
                  createdAt: movementTime,
                  updatedAt: movementTime,
                  deviceId: _deviceId,
                  storeId: appIdentity.storeId,
                  branchId: appIdentity.branchId,
                  lastModifiedByDeviceId: _deviceId,
                ),
                StockMovement(
                  id: '$groupId:${item.productId}:in:$batchIndex',
                  productId: item.productId,
                  productName: item.productName,
                  type: 'transfer_in',
                  quantity: allocation.quantity,
                  date: updated.date,
                  referenceId: updated.id,
                  referenceNo: updated.orderNo,
                  reason: 'Warehouse transfer from ${updated.fromWarehouseName}',
                  notes: updated.notes,
                  warehouseId: updated.toWarehouseId,
                  warehouseName: updated.toWarehouseName,
                  batchId: allocation.batchId,
                  movementGroupId: groupId,
                  documentLineId: '$lineId-in',
                  idempotencyKey: '$lineId:in',
                  unitCost: allocation.unitCost,
                  createdAt: movementTime,
                  updatedAt: movementTime,
                  deviceId: _deviceId,
                  storeId: appIdentity.storeId,
                  branchId: appIdentity.branchId,
                  lastModifiedByDeviceId: _deviceId,
                ),
              ]);
            }
          }
          await stockService.recordMovementsInTransaction(
            operationType: 'warehouse_transfer_order_edit',
            documentType: 'stock_transfer_order',
            documentId: updated.id,
            movementGroupId: groupId,
            idempotencyKey: groupId,
            movements: movements,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            deviceId: _deviceId,
          );
          await _assertUnifiedBatchMovementBalancesInTransaction(
            batchService,
            movements,
          );
          await InventoryTraceabilityService(sqliteDb)
              .assertTransferTraceabilityInTransaction(
            movementGroupId: groupId,
            storeId: appIdentity.storeId,
          );
          committedMovements.addAll(movements);
          return updated;
        },
        buildPostedSnapshot: (updated) async => updated,
        repostAccounting: (updated) async {},
        rebuildDerivedState: (updated) async {},
        verifyIntegrity: (updated) async {
          final row = await sqliteDb.customSelect(
            '''
            SELECT version, status, total_units
            FROM warehouse_transfer_orders
            WHERE id = ? AND deleted_at = '' LIMIT 1
            ''',
            variables: <Variable<Object>>[Variable<String>(updated.id)],
          ).getSingleOrNull();
          if (row == null ||
              (row.data['version'] as num?)?.toInt() != updated.version ||
              row.data['status']?.toString().toLowerCase() != 'completed' ||
              (((row.data['total_units'] as num?)?.toDouble() ?? 0) -
                          updated.totalUnits)
                      .abs() >
                  0.000001) {
            throw StateError('Transfer edit integrity verification failed.');
          }
          final expectedGroup =
              '${updated.id}:transfer_edit:v${updated.version}';
          final activeRows = await sqliteDb.customSelect(
            '''
            SELECT movement_group_id, COUNT(*) AS movement_count
            FROM stock_movements sm
            WHERE sm.reference_id = ? AND sm.deleted_at = ''
              AND sm.movement_type IN ('transfer_out', 'transfer_in')
              AND sm.reversal_of_movement_id = ''
              AND NOT EXISTS (
                SELECT 1 FROM stock_movements rev
                WHERE rev.reversal_of_movement_id = sm.id
                  AND rev.deleted_at = ''
              )
            GROUP BY movement_group_id
            ''',
            variables: <Variable<Object>>[Variable<String>(updated.id)],
          ).get();
          if (activeRows.length != 1 ||
              activeRows.single.data['movement_group_id']?.toString() !=
                  expectedGroup ||
              ((activeRows.single.data['movement_count'] as num?)?.toInt() ?? 0) <=
                  0) {
            throw StateError(
              'Transfer edit left more than one active movement version.',
            );
          }
        },
      );
      edited = await pipeline.execute();
    });

    _mirrorAuthoritativeStockMovements(committedMovements);
    await _refreshProductStockCompatibilityCache(touchedProductIds);
    _recordSyncChange(
      entityType: 'warehouse_transfer_order',
      entityId: edited.id,
      operation: 'posted_edit',
      payload: edited.toJson(),
    );
    for (final movement in committedMovements) {
      _recordSyncChange(
        entityType: 'stock_movement',
        entityId: movement.id,
        operation: movement.reversalOfMovementId.isEmpty
            ? 'transfer_edit'
            : 'transfer_edit_reversal',
        payload: movement.toJson(),
      );
    }
    unawaited(AuditLogger.record(
      entityType: 'warehouse_transfer_order',
      entityId: edited.id,
      action: 'posted_edit',
      summary: 'Warehouse transfer order edited',
      details: jsonEncode(edited.toJson()),
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
    return edited;
  }

Future<void> transferStock({
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required double quantity,
    String notes = '',
  }) async {
    requirePermission(AppPermission.inventoryWarehousesManage);
    if (quantity <= 0) {
      throw ArgumentError('Transfer quantity must be positive.');
    }
    _ensureDefaultWarehouse();
    if (fromWarehouseId == toWarehouseId) {
      throw ArgumentError('Choose two different warehouses.');
    }
    final productIndex = _productIndexById[productId];
    if (productIndex == null) throw ArgumentError('Product not found.');
    final product = _products[productIndex];
    if (!product.trackStock) {
      throw StateError('This product does not track stock.');
    }
    final fromWarehouse = _warehouses.firstWhere(
      (item) => item.id == fromWarehouseId && !item.isDeleted,
      orElse: () => throw ArgumentError('Source warehouse not found.'),
    );
    final toWarehouse = _warehouses.firstWhere(
      (item) => item.id == toWarehouseId && !item.isDeleted,
      orElse: () => throw ArgumentError('Destination warehouse not found.'),
    );
    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      final now = DateTime.now();
      final transferId = now.microsecondsSinceEpoch.toString();
      final stockService = StockTransactionService(
        sqliteDb,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
      );
      final outMovement = StockMovement(
        id: '$transferId-$productId-transfer-out',
        productId: productId,
        productName: product.name,
        type: 'transfer_out',
        quantity: -quantity,
        date: now,
        referenceId: transferId,
        referenceNo: 'TR-$transferId',
        reason: 'Warehouse transfer to ${toWarehouse.name}',
        notes: notes.trim(),
        warehouseId: fromWarehouse.id,
        warehouseName: fromWarehouse.name,
        movementGroupId: transferId,
        documentLineId: '$transferId-line-out',
        idempotencyKey: '$transferId:transfer:out',
        unitCost: _safeUsdCost(product),
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      );
      final inMovement = StockMovement(
        id: '$transferId-$productId-transfer-in',
        productId: productId,
        productName: product.name,
        type: 'transfer_in',
        quantity: quantity,
        date: now,
        referenceId: transferId,
        referenceNo: 'TR-$transferId',
        reason: 'Warehouse transfer from ${fromWarehouse.name}',
        notes: notes.trim(),
        warehouseId: toWarehouse.id,
        warehouseName: toWarehouse.name,
        movementGroupId: transferId,
        documentLineId: '$transferId-line-in',
        idempotencyKey: '$transferId:transfer:in',
        unitCost: _safeUsdCost(product),
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      );
      final batchService = BatchInventoryService(sqliteDb);
      var transferMovements = <StockMovement>[outMovement, inMovement];
      await _traceAsync<void>('inventory.transferStock', 'sqlite_transaction',
          () async {
        await sqliteDb.transaction(() async {
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
            quantity: quantity,
            transferredAt: now,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            deviceId: _deviceId,
            allowNegativeStock: _storeProfile.allowNegativeStock,
          );
          transferMovements = <StockMovement>[
            for (var batchIndex = 0;
                batchIndex < allocations.length;
                batchIndex += 1) ...<StockMovement>[
              outMovement.copyWith(
                id: '${outMovement.id}-batch-$batchIndex',
                quantity: -allocations[batchIndex].quantity,
                batchId: allocations[batchIndex].batchId,
                unitCost: allocations[batchIndex].unitCost,
                documentLineId: '$transferId-line-out-batch-$batchIndex',
                idempotencyKey: '$transferId:transfer:out:$batchIndex',
              ),
              inMovement.copyWith(
                id: '${inMovement.id}-batch-$batchIndex',
                quantity: allocations[batchIndex].quantity,
                batchId: allocations[batchIndex].batchId,
                unitCost: allocations[batchIndex].unitCost,
                documentLineId: '$transferId-line-in-batch-$batchIndex',
                idempotencyKey: '$transferId:transfer:in:$batchIndex',
              ),
            ],
          ];
          await stockService.recordMovementsInTransaction(
            operationType: 'warehouse_transfer',
            documentType: 'stock_transfer',
            documentId: transferId,
            movementGroupId: transferId,
            idempotencyKey: '$transferId:warehouse_transfer',
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
        });
      });
      _mirrorAuthoritativeStockMovements(transferMovements);
      await _refreshProductStockCompatibilityCache(<String>[productId]);
      _recordSyncChange(
        entityType: 'warehouse_transfer',
        entityId: transferId,
        operation: 'transfer',
        payload: <String, dynamic>{
          'id': transferId,
          'referenceNo': 'TR-$transferId',
          'productId': productId,
          'productName': product.name,
          'fromWarehouseId': fromWarehouse.id,
          'fromWarehouseName': fromWarehouse.name,
          'toWarehouseId': toWarehouse.id,
          'toWarehouseName': toWarehouse.name,
          'quantity': quantity,
          'notes': notes.trim(),
          'movementGroupId': transferId,
          'movements': transferMovements.map((item) => item.toJson()).toList(),
        },
      );
      for (final movement in transferMovements) {
        _recordSyncChange(
          entityType: 'stock_movement',
          entityId: movement.id,
          operation: 'transfer',
          payload: movement.toJson(),
        );
      }
      unawaited(
        AppLogger.info(
          area: 'inventory',
          action: 'transfer_stock',
          message: 'Stock transferred successfully.',
          details:
              'productId=$productId from=$fromWarehouseId to=$toWarehouseId quantity=$quantity',
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
          entityType: 'warehouse_transfer',
          entityId: transferId,
          action: 'transfer',
          summary: 'Stock transferred',
          details: jsonEncode(<String, Object?>{
            'productId': productId,
            'fromWarehouseId': fromWarehouseId,
            'toWarehouseId': toWarehouseId,
            'quantity': quantity,
            'notes': notes,
          }),
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
      return;
    }
    final available = stockForWarehouse(productId, fromWarehouseId);
    if (!_storeProfile.allowNegativeStock && available < quantity) {
      throw StateError('Not enough stock in ${fromWarehouse.name}.');
    }
    final now = DateTime.now();
    final transferId = now.microsecondsSinceEpoch.toString();
    _addStockMovement(
      StockMovement(
        id: '$transferId-$productId-transfer-out',
        productId: productId,
        productName: product.name,
        type: 'transfer_out',
        quantity: -quantity,
        date: now,
        referenceId: transferId,
        referenceNo: 'TR-$transferId',
        reason: 'Warehouse transfer to ${toWarehouse.name}',
        notes: notes.trim(),
        warehouseId: fromWarehouse.id,
        warehouseName: fromWarehouse.name,
        movementGroupId: transferId,
        documentLineId: '$transferId-line-out',
        idempotencyKey: '$transferId:transfer:out',
        unitCost: _safeUsdCost(product),
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      recordSync: true,
    );
    _addStockMovement(
      StockMovement(
        id: '$transferId-$productId-transfer-in',
        productId: productId,
        productName: product.name,
        type: 'transfer_in',
        quantity: quantity,
        date: now,
        referenceId: transferId,
        referenceNo: 'TR-$transferId',
        reason: 'Warehouse transfer from ${fromWarehouse.name}',
        notes: notes.trim(),
        warehouseId: toWarehouse.id,
        warehouseName: toWarehouse.name,
        movementGroupId: transferId,
        documentLineId: '$transferId-line-in',
        idempotencyKey: '$transferId:transfer:in',
        unitCost: _safeUsdCost(product),
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      recordSync: true,
    );
    await _saveDirty(stockMovements: true, sync: true);
    unawaited(
      AppLogger.info(
        area: 'inventory',
        action: 'transfer_stock',
        message: 'Stock transferred successfully.',
        details:
            'productId=$productId from=$fromWarehouseId to=$toWarehouseId quantity=$quantity',
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
        entityType: 'warehouse_transfer',
        entityId: transferId,
        action: 'transfer',
        summary: 'Stock transferred',
        details: jsonEncode(<String, Object?>{
          'productId': productId,
          'fromWarehouseId': fromWarehouseId,
          'toWarehouseId': toWarehouseId,
          'quantity': quantity,
          'notes': notes,
        }),
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
  }

Future<Map<String, String>> _openCashVoucherContext() async {
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError(
          'Payment vouchers require the SQLite authoritative store.');
    }
    final branchFilter =
        appIdentity.branchId.trim().isEmpty ? '' : 'AND cds.branch_id = ?';
    final row = await sqliteDb.customSelect(
      '''
      SELECT cds.id AS session_id, cds.cash_location_id
      FROM cash_drawer_sessions cds
      INNER JOIN cash_locations cl ON cl.id = cds.cash_location_id
      WHERE cds.status = 'open'
        AND cl.deleted_at = ''
        AND cl.is_active = 1
        AND cl.type = 'cash_drawer'
        AND cl.device_id = ?
        $branchFilter
      ORDER BY cds.opened_at DESC
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(_deviceId),
        if (appIdentity.branchId.trim().isNotEmpty)
          Variable<String>(appIdentity.branchId.trim()),
      ],
    ).getSingleOrNull();
    if (row == null) {
      throw StateError(
        'لا توجد وردية نقدية مفتوحة لهذا الجهاز. افتح وردية قبل قبول الدفع النقدي.',
      );
    }
    return <String, String>{
      'sessionId': row.data['session_id']?.toString() ?? '',
      'cashLocationId': row.data['cash_location_id']?.toString() ?? '',
    };
  }

Future<double> _saleReturnEntitlementFromSqlite(String saleId) async {
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      return 0;
    }
    final row = await sqliteDb.customSelect(
      '''
      SELECT COALESCE(SUM(credit - debit), 0) AS total
      FROM account_transactions
      WHERE deleted_at = ''
        AND account_type = 'customer'
        AND transaction_type = 'saleReturn'
        AND reference_id = ?
      ''',
      variables: <Variable<Object>>[Variable<String>(saleId.trim())],
    ).getSingle();
    return ((row.data['total'] as num?)?.toDouble() ?? 0)
        .clamp(0, double.infinity)
        .toDouble();
  }

Future<double> refundableSaleCashAmount(String saleId) async {
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Cash refunds require the SQLite authoritative store.');
    }
    final sale = _sales.where((item) => item.id == saleId).firstOrNull ??
        await _saleByIdFromSqlite(saleId);
    if (sale == null) return 0;

    // returnedAmount is not a dedicated authoritative sales-table column.
    // After a SQLite reload it can be zero although the return itself is
    // already committed. Derive the durable entitlement from SQLite.
    final sqliteReturnEntitlement =
        await _saleReturnEntitlementFromSqlite(sale.id);
    final returnedEntitlement =
        max(sale.returnedAmount, sqliteReturnEntitlement);
    final voucherService = PaymentVoucherService(sqliteDb);
    final unallocatedPool =
        await voucherService.unallocatedCashForSale(sale.id);
    final overpaymentEntitlement = !sale.isCancelled
        ? max(max(0.0, sale.paidAmount - sale.invoiceTotal), unallocatedPool)
        : 0.0;
    final entitlement = max(returnedEntitlement, overpaymentEntitlement) > 0
        ? max(returnedEntitlement, overpaymentEntitlement)
        : (sale.isCancelled
            ? (sale.subtotal - sale.discount)
                .clamp(0, double.infinity)
                .toDouble()
            : 0.0);
    if (entitlement <= 0.000001) return 0;
    return voucherService.refundableCashForSale(
      sale.id,
      maxRefundAmount: entitlement,
    );
  }

Future<void> normalizeRefundAllocations() async {
    requirePermission(AppPermission.cashBoxManage);
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Cash refunds require the SQLite authoritative store.');
    }
    await PaymentVoucherService(sqliteDb)
        .normalizeOverAllocatedVouchers(deviceId: _deviceId);
    await refreshAfterDatabaseChange(AppStore._salesKey);
    await refreshAfterDatabaseChange(AppStore._purchasesKey);
  }

Future<double> refundablePurchaseCashAmount(String purchaseId) async {
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Cash refunds require the SQLite authoritative store.');
    }
    final service = PaymentVoucherService(sqliteDb);
    // paid_amount is only a compatibility cache. Always rebuild it from the
    // authoritative active allocations before it participates in a refund
    // decision, so a prior refund can never leave a stale overpayment behind.
    final syncedPaidAmount =
        await service.syncPurchasePaymentCacheFromAllocations(
      purchaseId: purchaseId,
      deviceId: _deviceId,
    );
    final purchase = await _purchaseByIdFromSqlite(purchaseId);
    if (purchase == null) return 0;
    final purchaseTotal =
        purchase.items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    final unallocatedPool =
        await service.unallocatedCashForPurchase(purchase.id);
    final overpayment =
        max(max(0.0, syncedPaidAmount - purchaseTotal), unallocatedPool);
    return service.refundableCashForPurchase(
      purchase.id,
      maxRefundAmount: purchase.isCancelled ? null : overpayment,
    );
  }

Future<double> refundSaleCash({
    required String saleId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) async {
    requirePermission(AppPermission.salesCancel);
    final index = _sales.indexWhere((sale) => sale.id == saleId);
    final sale =
        index == -1 ? await _saleByIdFromSqlite(saleId) : _sales[index];
    if (sale == null) throw ArgumentError('Sale not found.');
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Cash refunds require the SQLite authoritative store.');
    }
    final service = PaymentVoucherService(sqliteDb);
    final preCancellationTotal =
        (sale.subtotal - sale.discount).clamp(0, double.infinity).toDouble();
    final sqliteReturnEntitlement =
        await _saleReturnEntitlementFromSqlite(sale.id);
    final returnedEntitlement =
        max(sale.returnedAmount, sqliteReturnEntitlement);
    final unallocatedPool = await service.unallocatedCashForSale(sale.id);
    final overpaymentEntitlement = !sale.isCancelled
        ? max(max(0.0, sale.paidAmount - sale.invoiceTotal), unallocatedPool)
        : 0.0;
    final refundEntitlement =
        max(returnedEntitlement, overpaymentEntitlement) > 0
            ? max(returnedEntitlement, overpaymentEntitlement)
            : (sale.isCancelled ? preCancellationTotal : 0.0);
    if (!sale.isCancelled && refundEntitlement <= 0.000001) {
      throw StateError(
        'No cash overpayment is available for this sale.',
      );
    }
    final refundable = await service.refundableCashForSale(
      sale.id,
      maxRefundAmount: refundEntitlement,
    );
    if (refundable <= 0.000001) return 0;
    final requested = amount ?? refundable;
    if (!requested.isFinite || requested <= 0) {
      throw ArgumentError('Refund amount must be greater than zero.');
    }
    final context = await _openCashVoucherContext();
    final refundKey = idempotencyKey.trim().isEmpty
        ? 'manual:${DateTime.now().microsecondsSinceEpoch}'
        : idempotencyKey.trim();
    final refunded = await service.refundSaleCash(
      saleId: sale.id,
      invoiceNo: sale.invoiceNo,
      customerId: sale.customerId,
      customerName: sale.customerName,
      requestedAmount: requested,
      maxRefundAmount: refundEntitlement,
      currency: sale.invoiceCurrency,
      cashLocationId: context['cashLocationId'] ?? '',
      cashDrawerSessionId: context['sessionId'] ?? '',
      refundKey: refundKey,
      notes: notes.trim().isEmpty
          ? 'Cash refund for ${sale.invoiceNo}'
          : notes.trim(),
      createdBy: _actorName(),
      createdByUserId: _activeUser?.id ?? '',
      deviceId: _deviceId,
      branchId: appIdentity.branchId,
      storeId: appIdentity.storeId,
      date: date,
    );
    if (refunded <= 0.000001) return 0;

    // PaymentVoucherService persists the customer refund compatibility row
    // inside the same SQLite transaction as journal + Cash Ledger + drawer.
    await refreshAccountTransactionsFromSqlite();
    await refreshAfterDatabaseChange(AppStore._salesKey);
    return refunded;
  }

Future<double> refundPurchaseCash({
    required String purchaseId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) async {
    requirePermission(AppPermission.suppliersPaymentManage);
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Cash refunds require the SQLite authoritative store.');
    }
    final service = PaymentVoucherService(sqliteDb);
    // Make the refund path self-contained: synchronize the compatibility cache
    // from authoritative allocations before computing any entitlement. Do not
    // rely on the cash dialog having run normalization first.
    final syncedPaidAmount =
        await service.syncPurchasePaymentCacheFromAllocations(
      purchaseId: purchaseId,
      deviceId: _deviceId,
    );
    final purchase = await _purchaseByIdFromSqlite(purchaseId);
    if (purchase == null) throw ArgumentError('Purchase not found.');
    final purchaseTotal =
        purchase.items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    final unallocatedPool =
        await service.unallocatedCashForPurchase(purchase.id);
    final overpayment =
        max(max(0.0, syncedPaidAmount - purchaseTotal), unallocatedPool);
    final refundable = await service.refundableCashForPurchase(
      purchase.id,
      maxRefundAmount: purchase.isCancelled ? null : overpayment,
    );
    if (refundable <= 0.000001) return 0;
    final context = await _openCashVoucherContext();
    final refundKey = idempotencyKey.trim().isEmpty
        ? 'manual:${DateTime.now().microsecondsSinceEpoch}:$_deviceId'
        : idempotencyKey.trim();
    final refunded = await service.refundPurchaseCash(
      purchaseId: purchase.id,
      purchaseNo: purchase.purchaseNo,
      supplierId: purchase.supplierId,
      supplierName: purchase.supplierName,
      cashLocationId: context['cashLocationId'] ?? '',
      cashDrawerSessionId: context['sessionId'] ?? '',
      requestedAmount: amount,
      maxRefundAmount: purchase.isCancelled ? null : overpayment,
      currency: storeProfile.baseCurrency,
      notes: notes.trim().isEmpty
          ? 'Cash refund from supplier for ${purchase.purchaseNo}'
          : notes.trim(),
      createdBy: _actorName(),
      createdByUserId: _activeUser?.id ?? '',
      deviceId: _deviceId,
      branchId: appIdentity.branchId,
      storeId: appIdentity.storeId,
      refundKey: refundKey,
      date: date,
    );
    if (refunded <= 0.000001) return 0;

    // The supplier compatibility ledger row is inserted atomically by
    // PaymentVoucherService inside the same SQLite transaction as the refund.
    // Refresh the in-memory compatibility view only; do not persist a second
    // copy from AppStore.
    await refreshAccountTransactionsFromSqlite();
    await refreshAfterDatabaseChange(AppStore._purchasesKey);
    return refunded;
  }

Future<double> refundableExpenseCashAmount(String expenseId) async {
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Cash refunds require the SQLite authoritative store.');
    }
    final expense = _expenses.where((item) => item.id == expenseId).firstOrNull;
    if (expense == null || expense.isDeleted || !expense.isPosted) return 0;
    final service = PaymentVoucherService(sqliteDb);
    final paid = await service.cashPaidForExpense(expense.id);
    final overpayment = max(0.0, paid - expense.amount);
    return service.refundableCashForExpense(
      expense.id,
      maxRefundAmount: overpayment,
    );
  }

Future<double> refundExpenseCash({
    required String expenseId,
    double? amount,
    String notes = '',
  }) async {
    requirePermission(AppPermission.expensesManage);
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Cash refunds require the SQLite authoritative store.');
    }
    final expense = _expenses.where((item) => item.id == expenseId).firstOrNull;
    if (expense == null || expense.isDeleted || !expense.isPosted) {
      throw StateError('Only posted expenses can be refunded.');
    }
    final service = PaymentVoucherService(sqliteDb);
    final paid = await service.cashPaidForExpense(expense.id);
    final overpayment = max(0.0, paid - expense.amount);
    final available = await service.refundableCashForExpense(
      expense.id,
      maxRefundAmount: overpayment,
    );
    final requested = amount ?? available;
    if (!requested.isFinite || requested <= 0) {
      throw ArgumentError('Refund amount must be greater than zero.');
    }
    final context = await _openCashVoucherContext();
    final refunded = await PaymentVoucherService(sqliteDb).refundExpenseCash(
      expenseId: expense.id,
      expenseTitle: expense.title,
      requestedAmount: min(requested, available),
      maxRefundAmount: overpayment,
      cashLocationId: context['cashLocationId'] ?? '',
      cashDrawerSessionId: context['sessionId'] ?? '',
      currency: storeProfile.baseCurrency,
      notes: notes.trim().isEmpty
          ? 'Cash refund for ${expense.title}'
          : notes.trim(),
      createdBy: _actorName(),
      createdByUserId: _activeUser?.id ?? '',
      deviceId: _deviceId,
      branchId: appIdentity.branchId,
      storeId: appIdentity.storeId,
      refundKey: 'manual:${DateTime.now().microsecondsSinceEpoch}',
    );
    if (refunded > 0.000001) await refreshAccountTransactionsFromSqlite();
    return refunded;
  }

Future<void> settleAccountPayment({
    required String accountType,
    required String accountId,
    required String accountName,
    required double amount,
    String paymentMethod = 'Cash',
    String referenceNo = '',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) async {
    final type = accountType.trim().toLowerCase();
    if (type != 'customer' && type != 'supplier') {
      throw ArgumentError('Account type must be customer or supplier.');
    }
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('Payment amount must be greater than zero.');
    }
    if (type == 'customer') {
      requirePermission(AppPermission.customersPaymentManage);
    } else {
      requirePermission(AppPermission.suppliersPaymentManage);
    }

    final method = paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim();
    var cashLocationId = '';
    var cashDrawerSessionId = '';
    if (method.toLowerCase() == 'cash') {
      requirePermission(AppPermission.cashBoxManage);
      final context = await _openCashVoucherContext();
      cashLocationId = context['cashLocationId'] ?? '';
      cashDrawerSessionId = context['sessionId'] ?? '';
    }

    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError(
          'Account payments require the SQLite authoritative store.');
    }
    final when = (date ?? DateTime.now()).toUtc();
    final key = idempotencyKey.trim().isNotEmpty
        ? idempotencyKey.trim()
        : 'account:$type:${accountId.trim()}:payment:${when.microsecondsSinceEpoch}:$_deviceId';
    final service = PaymentVoucherService(sqliteDb);

    if (type == 'customer') {
      await service.createReceipt(
        customerId: accountId.trim(),
        customerName: accountName.trim(),
        amount: amount,
        currency: storeProfile.baseCurrency,
        paymentMethod: method,
        cashLocationId: cashLocationId,
        cashDrawerSessionId: cashDrawerSessionId,
        allocations: const <PaymentAllocationDraft>[],
        notes: notes,
        createdBy: _actorName(),
        createdByUserId: _activeUser?.id ?? '',
        deviceId: _deviceId,
        branchId: appIdentity.branchId,
        storeId: appIdentity.storeId,
        idempotencyKey: key,
        date: when,
      );
    } else {
      await service.createPayment(
        supplierId: accountId.trim(),
        supplierName: accountName.trim(),
        amount: amount,
        currency: storeProfile.baseCurrency,
        paymentMethod: method,
        cashLocationId: cashLocationId,
        cashDrawerSessionId: cashDrawerSessionId,
        allocations: const <PaymentAllocationDraft>[],
        notes: notes,
        createdBy: _actorName(),
        createdByUserId: _activeUser?.id ?? '',
        deviceId: _deviceId,
        branchId: appIdentity.branchId,
        storeId: appIdentity.storeId,
        idempotencyKey: key,
        date: when,
      );
    }

    await refreshAccountTransactionsFromSqlite();
    await _saveDirty(accountTransactions: true, sync: true);
    notifyListeners();
  }

Future<ReceiptVoucher> editReceiptVoucher({
    required String voucherId,
    required int expectedVersion,
    String? customerId,
    String? customerName,
    double? amount,
    String? currency,
    String? paymentMethod,
    String? cashLocationId,
    String? cashDrawerSessionId,
    List<PaymentAllocationDraft>? allocations,
    String? notes,
    DateTime? date,
  }) async {
    requirePermission(AppPermission.customersPaymentManage);
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Receipt editing requires the SQLite authoritative store.');
    }
    final service = PaymentVoucherService(sqliteDb);
    final current = await service.findReceiptById(voucherId);
    if (current == null) throw ArgumentError('Receipt voucher not found.');
    final method = paymentMethod?.trim().isNotEmpty == true
        ? paymentMethod!.trim()
        : current.paymentMethod;
    var resolvedLocationId = cashLocationId ?? current.cashLocationId;
    var resolvedSessionId = cashDrawerSessionId ?? current.cashDrawerSessionId;
    if (method.toLowerCase() == 'cash') {
      requirePermission(AppPermission.cashBoxManage);
      if ((cashLocationId ?? '').trim().isEmpty ||
          (cashDrawerSessionId ?? '').trim().isEmpty) {
        final context = await _openCashVoucherContext();
        resolvedLocationId = context['cashLocationId'] ?? '';
        resolvedSessionId = context['sessionId'] ?? '';
      }
    }
    final edited = await service.editReceipt(
      voucherId: voucherId,
      expectedVersion: expectedVersion,
      customerId: customerId,
      customerName: customerName,
      amount: amount,
      currency: currency,
      paymentMethod: paymentMethod,
      cashLocationId: resolvedLocationId,
      cashDrawerSessionId: resolvedSessionId,
      allocations: allocations,
      notes: notes,
      date: date,
      editedBy: _actorName(),
      editedByUserId: _activeUser?.id ?? '',
      deviceId: _deviceId,
    );
    await refreshAccountTransactionsFromSqlite();
    await _saveDirty(accountTransactions: true, sync: true);
    notifyListeners();
    return edited;
  }

Future<PaymentVoucher> editPaymentVoucher({
    required String voucherId,
    required int expectedVersion,
    String? supplierId,
    String? supplierName,
    double? amount,
    String? currency,
    String? paymentMethod,
    String? cashLocationId,
    String? cashDrawerSessionId,
    List<PaymentAllocationDraft>? allocations,
    String? notes,
    DateTime? date,
  }) async {
    requirePermission(AppPermission.suppliersPaymentManage);
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Payment editing requires the SQLite authoritative store.');
    }
    final service = PaymentVoucherService(sqliteDb);
    final current = await service.findPaymentById(voucherId);
    if (current == null) throw ArgumentError('Payment voucher not found.');
    final method = paymentMethod?.trim().isNotEmpty == true
        ? paymentMethod!.trim()
        : current.paymentMethod;
    var resolvedLocationId = cashLocationId ?? current.cashLocationId;
    var resolvedSessionId = cashDrawerSessionId ?? current.cashDrawerSessionId;
    if (method.toLowerCase() == 'cash') {
      requirePermission(AppPermission.cashBoxManage);
      if ((cashLocationId ?? '').trim().isEmpty ||
          (cashDrawerSessionId ?? '').trim().isEmpty) {
        final context = await _openCashVoucherContext();
        resolvedLocationId = context['cashLocationId'] ?? '';
        resolvedSessionId = context['sessionId'] ?? '';
      }
    }
    final edited = await service.editPayment(
      voucherId: voucherId,
      expectedVersion: expectedVersion,
      supplierId: supplierId,
      supplierName: supplierName,
      amount: amount,
      currency: currency,
      paymentMethod: paymentMethod,
      cashLocationId: resolvedLocationId,
      cashDrawerSessionId: resolvedSessionId,
      allocations: allocations,
      notes: notes,
      date: date,
      editedBy: _actorName(),
      editedByUserId: _activeUser?.id ?? '',
      deviceId: _deviceId,
    );
    await refreshAccountTransactionsFromSqlite();
    await _saveDirty(accountTransactions: true, sync: true);
    notifyListeners();
    return edited;
  }

Future<Sale> settleSalePayment({
    required String saleId,
    required double amount,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) async {
    requirePermission(AppPermission.customersPaymentManage);
    return _settleSalePaymentInternal(
      saleId: saleId,
      amount: amount,
      paymentMethod: paymentMethod,
      notes: notes,
      idempotencyKey: idempotencyKey,
      date: date,
    );
  }

Future<Sale> _settleSalePaymentInternal({
    required String saleId,
    required double amount,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('Payment amount must be greater than zero.');
    }
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError(
          'Sale settlement requires the SQLite authoritative store.');
    }
    final current = await _saleByIdFromSqlite(saleId);
    if (current == null || current.isCancelled) {
      throw StateError('Sale is not available for payment.');
    }
    if (amount > current.balanceDue + 0.000001) {
      throw StateError('Payment exceeds the remaining sale balance.');
    }
    final method = paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim();
    var cashLocationId = '';
    var cashDrawerSessionId = '';
    if (method.toLowerCase() == 'cash') {
      final context = await _openCashVoucherContext();
      cashLocationId = context['cashLocationId'] ?? '';
      cashDrawerSessionId = context['sessionId'] ?? '';
    }
    final when = (date ?? DateTime.now()).toUtc();
    final key = idempotencyKey.trim().isNotEmpty
        ? idempotencyKey.trim()
        : 'sale:${current.id}:payment:${when.microsecondsSinceEpoch}:$_deviceId';
    await PaymentVoucherService(sqliteDb).createReceipt(
      customerId: current.customerId,
      customerName: current.customerName,
      amount: amount,
      currency: current.invoiceCurrency,
      paymentMethod: method,
      cashLocationId: cashLocationId,
      cashDrawerSessionId: cashDrawerSessionId,
      allocations: <PaymentAllocationDraft>[
        PaymentAllocationDraft(
          referenceId: current.id,
          referenceNumber: current.invoiceNo,
          amount: amount,
          referenceAmount: amount,
          referenceCurrency: current.invoiceCurrency,
          exchangeRate: 1,
        ),
      ],
      notes: notes,
      createdBy: _actorName(),
      createdByUserId: _activeUser?.id ?? '',
      deviceId: _deviceId,
      branchId: appIdentity.branchId,
      storeId: appIdentity.storeId,
      idempotencyKey: key,
      date: when,
    );
    await refreshAccountTransactionsFromSqlite();
    final updated = await _saleByIdFromSqlite(current.id);
    if (updated == null) throw StateError('Sale payment cache refresh failed.');
    final index = _sales.indexWhere((item) => item.id == updated.id);
    if (index >= 0) _sales[index] = updated;
    _recordSyncChange(
      entityType: 'sale',
      entityId: updated.id,
      operation: 'payment_cache_update',
      payload: updated.toJson(),
    );
    await _saveDirty(accountTransactions: true, sync: true);
    notifyListeners();
    return updated;
  }

Future<Purchase> settlePurchasePayment({
    required String purchaseId,
    required double amount,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) async {
    requirePermission(AppPermission.suppliersPaymentManage);
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('Payment amount must be greater than zero.');
    }
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError(
          'Purchase settlement requires the SQLite authoritative store.');
    }
    final current = await _purchaseByIdFromSqlite(purchaseId);
    if (current == null || current.isCancelled || !current.isReceived) {
      throw StateError('Purchase is not available for payment.');
    }
    if (amount > current.balanceDue + 0.000001) {
      throw StateError('Payment exceeds the remaining purchase balance.');
    }
    final method = paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim();
    var cashLocationId = '';
    var cashDrawerSessionId = '';
    if (method.toLowerCase() == 'cash') {
      final context = await _openCashVoucherContext();
      cashLocationId = context['cashLocationId'] ?? '';
      cashDrawerSessionId = context['sessionId'] ?? '';
    }
    final when = (date ?? DateTime.now()).toUtc();
    final key = idempotencyKey.trim().isNotEmpty
        ? idempotencyKey.trim()
        : 'purchase:${current.id}:payment:${when.microsecondsSinceEpoch}:$_deviceId';
    await PaymentVoucherService(sqliteDb).createPayment(
      supplierId: current.supplierId,
      supplierName: current.supplierName,
      amount: amount,
      currency: storeProfile.baseCurrency,
      paymentMethod: method,
      cashLocationId: cashLocationId,
      cashDrawerSessionId: cashDrawerSessionId,
      allocations: <PaymentAllocationDraft>[
        PaymentAllocationDraft(
          referenceId: current.id,
          referenceNumber: current.purchaseNo,
          amount: amount,
          referenceAmount: amount,
          referenceCurrency: storeProfile.baseCurrency,
          exchangeRate: 1,
        ),
      ],
      notes: notes,
      createdBy: _actorName(),
      createdByUserId: _activeUser?.id ?? '',
      deviceId: _deviceId,
      branchId: appIdentity.branchId,
      storeId: appIdentity.storeId,
      idempotencyKey: key,
      date: when,
    );
    await refreshAccountTransactionsFromSqlite();
    final updated = await _purchaseByIdFromSqlite(current.id);
    if (updated == null) {
      throw StateError('Purchase payment cache refresh failed.');
    }
    final index = _purchaseIndexForId(updated.id);
    if (index >= 0) _putPurchaseAtIndex(updated, index);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: updated.id,
      operation: 'payment_cache_update',
      payload: updated.toJson(),
    );
    await _saveDirty(accountTransactions: true, sync: true);
    _touchPurchasesData();
    notifyListeners();
    return updated;
  }

PurchaseItem _copyPurchaseItemWith({
    required PurchaseItem item,
    String? lineId,
    List<BatchAllocation>? batchAllocations,
  }) {
    return PurchaseItem(
      lineId: lineId ?? item.lineId,
      productId: item.productId,
      productName: item.productName,
      quantity: item.quantity,
      unitCost: item.unitCost,
      purchaseUnitId: item.purchaseUnitId,
      purchaseUnitName: item.purchaseUnitName,
      conversionToBase: item.conversionToBase,
      originalUnitCost: item.originalUnitCost,
      unitCostCurrency: item.unitCostCurrency,
      exchangeRateAtEntry: item.exchangeRateAtEntry,
      batchAllocations: batchAllocations ?? item.batchAllocations,
    );
  }

}
