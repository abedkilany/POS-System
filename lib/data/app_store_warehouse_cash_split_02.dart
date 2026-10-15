part of 'app_store.dart';

extension _AppStoreSplitWarehouseCashPart2 on AppStore {
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
        data['items'] =
            jsonDecode(data.remove('itemsJson')?.toString() ?? '[]');
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
            (item) =>
                item.id == fromWarehouseId && !item.isDeleted && item.isActive,
            orElse: () => throw ArgumentError('Source warehouse not found.'),
          );
          toWarehouse = _warehouses.firstWhere(
            (item) =>
                item.id == toWarehouseId && !item.isDeleted && item.isActive,
            orElse: () =>
                throw ArgumentError('Destination warehouse not found.'),
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
                Variable<String>(movement.storeId.isEmpty
                    ? appIdentity.storeId
                    : movement.storeId),
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
              throw StateError(
                  'Transfer product ${original.productId} is missing.');
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
            storeId:
                current.storeId.isEmpty ? appIdentity.storeId : current.storeId,
            branchId: current.branchId.isEmpty
                ? appIdentity.branchId
                : current.branchId,
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
          final groupId = '${updated.id}:transfer_edit:v${updated.version}';
          final movements = <StockMovement>[];
          final movementTime = DateTime.now().toUtc();
          for (var lineIndex = 0;
              lineIndex < updated.items.length;
              lineIndex += 1) {
            final item = updated.items[lineIndex];
            final productIndex = _productIndexById[item.productId];
            if (productIndex == null) {
              throw StateError(
                  'Transfer product ${item.productId} is missing.');
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
                  reason:
                      'Warehouse transfer from ${updated.fromWarehouseName}',
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
              ((activeRows.single.data['movement_count'] as num?)?.toInt() ??
                      0) <=
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
}
