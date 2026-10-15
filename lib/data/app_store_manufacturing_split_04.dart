part of 'app_store.dart';

extension _AppStoreSplitManufacturingPart4 on AppStore {
  Future<ManufacturingOrder> editCompletedManufacturingOrder({
    required String orderId,
    required int expectedVersion,
    required String bomId,
    required double quantity,
    required String rawMaterialsWarehouseId,
    required String rawMaterialsWarehouseName,
    required String finishedGoodsWarehouseId,
    required String finishedGoodsWarehouseName,
    String notes = '',
    List<BatchAllocation> outputBatchAllocations = const <BatchAllocation>[],
    Map<String, double> actualConsumedQuantities = const <String, double>{},
    Map<String, double> wasteQuantities = const <String, double>{},
    Map<String, String> wasteReasons = const <String, String>{},
  }) async {
    requirePermission(AppPermission.inventoryManufacturingManage);
    if (quantity <= 0) {
      throw ArgumentError('Manufacturing quantity must be greater than zero.');
    }
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw StateError(
        'Editing completed manufacturing requires the authoritative SQLite store.',
      );
    }
    await _flushProductDerivedData();
    final persistedOrders =
        await BusinessSqliteStore.readManufacturingOrders(db);
    final initial = persistedOrders.firstWhere(
      (item) => item.id == orderId && !item.isDeleted,
      orElse: () => throw ArgumentError('Manufacturing order was not found.'),
    );
    if (!<String>{'completed', 'complete'}
        .contains(initial.status.trim().toLowerCase())) {
      throw StateError('Only a completed manufacturing order can be edited.');
    }
    if (initial.version != expectedVersion) {
      throw StateError(
        'Manufacturing order changed concurrently. Reload it before editing.',
      );
    }
    final nextVersion = initial.version + 1;
    final technicalReferenceId =
        '${initial.id}:manufacturing_edit:v$nextVersion';
    final operationReferenceId = technicalReferenceId;
    final reversalOperationReferenceId =
        '${initial.id}:manufacturing_edit_reverse:v$nextVersion';
    late ManufacturingOrder updated;

    await db.transaction(() async {
      updated = await PostedDocumentEditPipeline<ManufacturingOrder>(
        loadAuthoritative: () async {
          final rows = await BusinessSqliteStore.readManufacturingOrders(db);
          return rows.firstWhere(
            (item) => item.id == orderId && !item.isDeleted,
            orElse: () => throw StateError(
                'Manufacturing order disappeared during edit.'),
          );
        },
        validatePermission: (_) async {
          requirePermission(AppPermission.inventoryManufacturingManage);
        },
        validateVersion: (current) async {
          if (current.version != expectedVersion) {
            throw StateError(
              'Manufacturing order changed concurrently. Reload it before editing.',
            );
          }
          if (!<String>{'completed', 'complete'}
              .contains(current.status.trim().toLowerCase())) {
            throw StateError(
              'Only a completed manufacturing order can be edited.',
            );
          }
        },
        validateDependencies: (current) async {
          final activeMovements =
              await BusinessSqliteStore.readStockMovements(db);
          final reversedIds = activeMovements
              .where((movement) => movement.reversalOfMovementId.isNotEmpty)
              .map((movement) => movement.reversalOfMovementId)
              .toSet();
          final outputMovements = activeMovements.where(
            (movement) =>
                movement.referenceId == current.id &&
                movement.type == 'manufacturing_produce' &&
                movement.reversalOfMovementId.isEmpty &&
                !reversedIds.contains(movement.id),
          );
          if (outputMovements.isEmpty) {
            throw StateError(
              'Active manufacturing output movements are missing.',
            );
          }
          for (final outputMovement in outputMovements) {
            final downstream = activeMovements.any(
              (movement) =>
                  movement.productId == outputMovement.productId &&
                  movement.warehouseId == outputMovement.warehouseId &&
                  (outputMovement.batchId.isEmpty ||
                      movement.batchId == outputMovement.batchId) &&
                  movement.referenceId != current.id &&
                  movement.reversalOfMovementId.isEmpty &&
                  !reversedIds.contains(movement.id) &&
                  movement.date.isAfter(outputMovement.date) &&
                  movement.quantity < -0.000001,
            );
            if (downstream) {
              throw StateError(
                'Manufactured output has downstream consumption. Reverse the downstream movement before editing this order.',
              );
            }
          }
        },
        reverseOperationalEffects: (current) async {
          await _AppStoreSplitManufacturingPart5(this)
              .reverseManufacturingOrder(
            orderId: current.id,
            reason: 'Manufacturing order edited to version $nextVersion',
            withinExistingTransactionInternal: true,
            suppressPostCommitInternal: true,
            operationReferenceIdOverride: reversalOperationReferenceId,
          );
        },
        reverseAccountingEffects: (current) async {
          final activeJournal = await db.customSelect(
            '''
            SELECT id
            FROM journal_entries je
            WHERE je.reference_type = 'manufacturing_order'
              AND (je.reference_id = ? OR instr(je.reference_id, ?) = 1)
              AND je.deleted_at = '' AND je.status = 'posted'
              AND NOT EXISTS (
                SELECT 1 FROM journal_entries rev
                WHERE rev.reversed_entry_id = je.id
                  AND rev.deleted_at = '' AND rev.status = 'posted'
              )
            LIMIT 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>(current.id),
              Variable<String>('${current.id}:manufacturing_edit:'),
            ],
          ).getSingleOrNull();
          if (activeJournal != null) {
            throw StateError(
              'Manufacturing accounting reversal did not complete.',
            );
          }
        },
        applyChanges: (current) async => current,
        rebuildOperationalEffects: (current) async {
          return _AppStoreSplitManufacturingPart3(this)
              .completeManufacturingOrder(
            bomId: bomId,
            quantity: quantity,
            rawMaterialsWarehouseId: rawMaterialsWarehouseId,
            rawMaterialsWarehouseName: rawMaterialsWarehouseName,
            finishedGoodsWarehouseId: finishedGoodsWarehouseId,
            finishedGoodsWarehouseName: finishedGoodsWarehouseName,
            notes: notes,
            outputBatchAllocations: outputBatchAllocations,
            actualConsumedQuantities: actualConsumedQuantities,
            wasteQuantities: wasteQuantities,
            wasteReasons: wasteReasons,
            existingOrderId: current.id,
            allowCompletedRepostInternal: true,
            withinExistingTransactionInternal: true,
            suppressPostCommitInternal: true,
            technicalReferenceIdOverride: technicalReferenceId,
            operationReferenceIdOverride: operationReferenceId,
            existingOrderOverride: current,
          );
        },
        buildPostedSnapshot: (current) async => current,
        repostAccounting: (current) async {
          final journal = await db.customSelect(
            '''
            SELECT id
            FROM journal_entries je
            WHERE je.reference_type = 'manufacturing_order'
              AND je.reference_id = ?
              AND je.deleted_at = '' AND je.status = 'posted'
              AND NOT EXISTS (
                SELECT 1 FROM journal_entries rev
                WHERE rev.reversed_entry_id = je.id
                  AND rev.deleted_at = '' AND rev.status = 'posted'
              )
            LIMIT 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>(technicalReferenceId),
            ],
          ).getSingleOrNull();
          if (journal == null || current.journalEntryId.trim().isEmpty) {
            throw StateError(
              'Edited manufacturing accounting journal was not persisted.',
            );
          }
        },
        rebuildDerivedState: (current) async {},
        verifyIntegrity: (current) async {
          if (current.version != nextVersion ||
              current.status.trim().toLowerCase() != 'completed') {
            throw StateError(
              'Edited manufacturing order failed version/status verification.',
            );
          }
          final persisted =
              (await BusinessSqliteStore.readManufacturingOrders(db))
                  .firstWhere(
            (item) => item.id == current.id && !item.isDeleted,
            orElse: () => throw StateError(
              'Edited manufacturing order was not persisted.',
            ),
          );
          if (persisted.version != nextVersion ||
              persisted.journalEntryId != current.journalEntryId) {
            throw StateError(
              'Edited manufacturing order failed persistence verification.',
            );
          }
          final movementRow = await db.customSelect(
            '''
            SELECT
              SUM(CASE WHEN movement_type = 'manufacturing_produce'
                       THEN quantity ELSE 0 END) AS produced,
              COUNT(*) AS movementCount
            FROM stock_movements sm
            WHERE sm.movement_group_id = ? AND sm.deleted_at = ''
              AND sm.movement_type IN ('manufacturing_consume', 'manufacturing_produce')
            ''',
            variables: <Variable<Object>>[
              Variable<String>(operationReferenceId),
            ],
          ).getSingle();
          final produced =
              (movementRow.data['produced'] as num? ?? 0).toDouble();
          final movementCount =
              (movementRow.data['movementCount'] as num? ?? 0).toInt();
          if (movementCount <= 0 || (produced - quantity).abs() > 0.000001) {
            throw StateError(
              'Edited manufacturing order failed stock verification.',
            );
          }
        },
      ).execute();
    });

    final authoritativeOrders =
        await BusinessSqliteStore.readManufacturingOrders(db);
    final persistedUpdated = authoritativeOrders.firstWhere(
      (item) => item.id == updated.id && !item.isDeleted,
      orElse: () => updated,
    );
    final orderIndex = _manufacturingOrders
        .indexWhere((item) => item.id == persistedUpdated.id);
    if (orderIndex == -1) {
      _manufacturingOrders.add(persistedUpdated);
    } else {
      _manufacturingOrders[orderIndex] = persistedUpdated;
    }
    final allMovements = await BusinessSqliteStore.readStockMovements(db);
    _mirrorAuthoritativeStockMovements(allMovements);
    _inventoryCostLayers
      ..clear()
      ..addAll(await BusinessSqliteStore.readInventoryCostLayers(db));
    _rebuildInventoryCostLayerLookupCache();
    _productCosts
      ..clear()
      ..addAll(await BusinessSqliteStore.readProductCosts(db));
    _rebuildProductCostLookupCache();

    final newBom = _billsOfMaterials.firstWhere(
      (item) => item.id == bomId && !item.isDeleted,
      orElse: () => throw StateError('Edited manufacturing BOM is missing.'),
    );
    final touchedProductIds = <String>{
      initial.outputProductId,
      persistedUpdated.outputProductId,
      for (final line in initial.materialCosts) line.productId,
      for (final line in newBom.components) line.productId,
    };
    await _refreshProductStockCompatibilityCache(touchedProductIds);

    _recordSyncChange(
      entityType: 'manufacturing_order',
      entityId: persistedUpdated.id,
      operation: 'edit_completed',
      payload: persistedUpdated.toJson(),
    );
    for (final movement in allMovements.where(
      (movement) =>
          movement.movementGroupId == operationReferenceId ||
          movement.movementGroupId == reversalOperationReferenceId,
    )) {
      _recordSyncChange(
        entityType: 'stock_movement',
        entityId: movement.id,
        operation: movement.movementGroupId == operationReferenceId
            ? 'manufacturing_edit'
            : 'manufacturing_edit_reversal',
        payload: movement.toJson(),
      );
    }

    final batchRows = await db.customSelect(
      '''
      SELECT id, initial_quantity, unit_cost, supplier_batch_number,
             manufacturing_date, expiration_date, received_at
      FROM inventory_batches
      WHERE store_id = ? AND source_type = 'manufacturing_output'
        AND source_id = ?
      ORDER BY received_at, id
      ''',
      variables: <Variable<Object>>[
        Variable<String>(appIdentity.storeId),
        Variable<String>(operationReferenceId),
      ],
    ).get();
    final outputProduct = _findProductById(persistedUpdated.outputProductId);
    if (outputProduct != null && batchRows.isNotEmpty) {
      final allocations = batchRows.map((row) {
        final data = row.data;
        return BatchAllocation(
          batchId: data['id']?.toString() ?? '',
          quantity: (data['initial_quantity'] as num? ?? 0).toDouble(),
          unitCost: (data['unit_cost'] as num? ?? 0).toDouble(),
          supplierBatchNumber: data['supplier_batch_number']?.toString() ?? '',
          manufacturingDate:
              DateTime.tryParse(data['manufacturing_date']?.toString() ?? ''),
          expirationDate:
              DateTime.tryParse(data['expiration_date']?.toString() ?? ''),
        );
      }).toList(growable: false);
      _recordInventoryBatchSyncChanges(
        product: outputProduct,
        allocations: allocations,
        sourceType: 'manufacturing_output',
        sourceId: operationReferenceId,
        now: persistedUpdated.completedAt ?? DateTime.now(),
        unitCost: persistedUpdated.actualUnitCost,
        sourceLineIds: <String>[
          for (var index = 0; index < allocations.length; index += 1)
            '$operationReferenceId:output:$index',
        ],
        receivedAt: persistedUpdated.completedAt,
      );
    }
    await _saveDirty(sync: true);
    AccountingService.notifyCommittedMutation();
    _invalidateDerivedDataCaches();
    notifyListeners();
    return persistedUpdated;
  }
}
