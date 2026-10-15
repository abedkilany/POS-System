part of 'app_store.dart';

extension _AppStoreSplitInventoryPart4 on AppStore {
  /// Safely edits a posted manual inventory adjustment while preserving the
  /// original movement/journal history. The stable [operationReferenceId]
  /// identifies the adjustment family; each successful edit reverses the active
  /// stock/accounting effects and appends a new `inventory_adjustment_edit:vN`
  /// member inside one authoritative SQLite transaction.
  Future<void> editStockAdjustment({
    required String operationReferenceId,
    required int expectedVersion,
    required double quantityDelta,
    required String reason,
    String adjustmentCategory = 'other',
    String notes = '',
    String evidenceRef = '',
    List<BatchAllocation> batchAllocations = const <BatchAllocation>[],
  }) async {
    requirePermission(AppPermission.inventoryCorrectionsManage);
    final operationId = operationReferenceId.trim();
    if (operationId.isEmpty) {
      throw ArgumentError('Inventory adjustment reference is required.');
    }
    if (!quantityDelta.isFinite || quantityDelta.abs() <= 0.000001) {
      throw ArgumentError('Inventory adjustment quantity must be non-zero.');
    }
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw StateError(
        'Editing a posted inventory adjustment requires the authoritative SQLite store.',
      );
    }

    final stockService = StockTransactionService(
      db,
      deviceId: _deviceId,
      defaultStoreId: appIdentity.storeId,
      defaultBranchId: appIdentity.branchId,
      defaultSyncTarget: _stockTransactionSyncTarget,
      allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
    );
    final batchService = BatchInventoryService(db);
    late Product product;
    late String warehouseId;
    late String warehouseName;
    late int nextVersion;
    late String journalReferenceId;
    var newAdjustmentValue = 0.0;
    var newAdjustmentUnitCost = 0.0;
    var committedMovements = const <StockMovement>[];
    var committedAllocations = const <BatchAllocation>[];
    Product? persistedAdjustedProduct;

    Future<List<StockMovement>> readActiveFamily() async {
      final all = await BusinessSqliteStore.readStockMovements(db);
      final reversedIds = <String>{
        for (final movement in all)
          if (movement.reversalOfMovementId.trim().isNotEmpty)
            movement.reversalOfMovementId.trim(),
      };
      return all
          .where(
            (movement) =>
                movement.movementGroupId == operationId &&
                movement.reversalOfMovementId.isEmpty &&
                !reversedIds.contains(movement.id) &&
                (movement.type == 'inventory_loss' ||
                    movement.type == 'inventory_adjustment'),
          )
          .toList(growable: false);
    }

    await db.transaction(() async {
      final edited = await PostedDocumentEditPipeline<List<StockMovement>>(
        loadAuthoritative: () async {
          final active = await readActiveFamily();
          if (active.isEmpty) {
            throw StateError(
              'The active manual inventory adjustment was not found or has already been reversed.',
            );
          }
          final first = active.first;
          if (active.any(
            (movement) =>
                movement.productId != first.productId ||
                movement.warehouseId != first.warehouseId,
          )) {
            throw StateError(
              'Inventory adjustment family contains inconsistent product or warehouse movements.',
            );
          }
          final resolved = _findProductById(first.productId);
          if (resolved == null || !resolved.trackStock) {
            throw StateError(
              'Adjusted product no longer exists or no longer tracks stock.',
            );
          }
          product = resolved;
          warehouseId = first.warehouseId.trim().isEmpty
              ? Warehouse.defaultId
              : first.warehouseId.trim();
          warehouseName = first.warehouseName.trim().isEmpty
              ? resolveWarehouseForPurchase(warehouseId: warehouseId).name
              : first.warehouseName.trim();
          return active;
        },
        validatePermission: (_) async {
          requirePermission(AppPermission.inventoryCorrectionsManage);
        },
        validateVersion: (_) async {
          final prefix = '$operationId:inventory_adjustment_edit:';
          final row = await db.customSelect(
            '''
            SELECT reference_id
            FROM journal_entries je
            WHERE je.reference_type = 'inventory_adjustment'
              AND (je.reference_id = ? OR instr(je.reference_id, ?) = 1)
              AND je.deleted_at = '' AND je.status = 'posted'
              AND NOT EXISTS (
                SELECT 1 FROM journal_entries rev
                WHERE rev.reversed_entry_id = je.id
                  AND rev.deleted_at = '' AND rev.status = 'posted'
              )
            ORDER BY je.created_at DESC, je.entry_date DESC, je.id DESC
            LIMIT 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>(operationId),
              Variable<String>(prefix),
            ],
          ).getSingleOrNull();
          if (row == null) {
            throw StateError(
              'The active accounting journal for this adjustment is missing.',
            );
          }
          final activeReference = row.data['reference_id']?.toString() ?? '';
          var currentVersion = 1;
          if (activeReference.startsWith(prefix)) {
            currentVersion = int.tryParse(
                  activeReference
                      .substring(prefix.length)
                      .replaceFirst('v', ''),
                ) ??
                1;
          }
          if (expectedVersion != currentVersion) {
            throw StateError(
              'Inventory adjustment changed concurrently. Reload it before editing.',
            );
          }
          nextVersion = currentVersion + 1;
          journalReferenceId =
              '$operationId:inventory_adjustment_edit:v$nextVersion';
        },
        validateDependencies: (current) async {
          for (final movement in current) {
            if (movement.batchId.trim().isEmpty) {
              throw StateError(
                'Historical non-batch inventory adjustments cannot be edited safely. Reverse them and create a new adjustment instead.',
              );
            }
            if (movement.quantity > 0.000001) {
              final balanceRow = await db.customSelect(
                '''
                SELECT COALESCE(quantity, 0) AS quantity
                FROM inventory_batch_balances
                WHERE store_id = ? AND warehouse_id = ?
                  AND product_id = ? AND batch_id = ?
                LIMIT 1
                ''',
                variables: <Variable<Object>>[
                  Variable<String>(appIdentity.storeId),
                  Variable<String>(warehouseId),
                  Variable<String>(product.id),
                  Variable<String>(movement.batchId),
                ],
              ).getSingleOrNull();
              final available =
                  (balanceRow?.data['quantity'] as num? ?? 0).toDouble();
              if (available + 0.000001 < movement.quantity) {
                throw StateError(
                  'This inventory gain has downstream consumption and cannot be edited until the downstream movement is reversed.',
                );
              }
            }
          }
        },
        reverseOperationalEffects: (current) async {
          final reversedAt = DateTime.now();
          for (final movement in current) {
            await batchService.reverseUnifiedMovementEffectInTransaction(
              product: product,
              warehouseId: warehouseId,
              batchId: movement.batchId,
              movementQuantity: movement.quantity,
              unitCost: movement.unitCost,
              reversedAt: reversedAt,
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              deviceId: _deviceId,
            );
            await stockService.recordReversalInTransaction(
              originalMovement: movement,
              operationType: 'manual_adjustment_edit_reversal',
              documentType: 'inventory_adjustment',
              documentId: operationId,
              reason: 'Inventory adjustment edited',
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              deviceId: _deviceId,
              syncTarget: _stockTransactionSyncTarget,
            );
          }
          await batchService.assertWarehouseBatchBalanceInTransaction(
            productId: product.id,
            warehouseId: warehouseId,
            storeId: appIdentity.storeId,
          );
        },
        reverseAccountingEffects: (_) async {
          await AccountingService.reverseEntryForReference(
            referenceType: 'inventory_adjustment',
            referenceId: operationId,
            reason: 'Inventory adjustment edited',
            createdBy: _actorName(),
            adjustCashLocationBalance: false,
            notifyChange: false,
            withinExistingTransaction: true,
          );
        },
        applyChanges: (current) async => current,
        rebuildOperationalEffects: (_) async {
          final now = DateTime.now();
          await _ensureUnifiedBatchCutoverForProductInTransaction(
            db,
            product: product,
            warehouseId: warehouseId,
            at: now,
          );
          final baseMovementId =
              '$operationId-inventory-adjustment-edit-v$nextVersion';
          final resolved = <BatchAllocation>[];
          final movements = <StockMovement>[];
          if (quantityDelta < 0) {
            final allocations = await batchService.allocateUnifiedInTransaction(
              product: product,
              warehouseId: warehouseId,
              quantity: quantityDelta.abs(),
              movementDate: now,
              storeId: appIdentity.storeId,
              deviceId: _deviceId,
              branchId: appIdentity.branchId,
              allowNegativeStock: _storeProfile.allowNegativeStock,
            );
            resolved.addAll(allocations);
            newAdjustmentValue = allocations.fold<double>(
              0,
              (sum, allocation) =>
                  sum + allocation.quantity * allocation.unitCost,
            );
            newAdjustmentUnitCost = quantityDelta.abs() <= 0
                ? 0
                : newAdjustmentValue / quantityDelta.abs();
          } else {
            newAdjustmentUnitCost =
                await _unifiedOpeningCostForProductInTransaction(
              db,
              product: product,
              warehouseId: warehouseId,
            );
            final requested = product.expiryTrackingEnabled
                ? batchAllocations
                : <BatchAllocation>[
                    BatchAllocation(
                      batchId: '$baseMovementId-batch-0',
                      quantity: quantityDelta,
                      unitCost: newAdjustmentUnitCost,
                    ),
                  ];
            if (product.expiryTrackingEnabled && requested.isEmpty) {
              throw LocalizedDomainException(
                'error_expiry_batches_required',
                values: {'product': product.name},
                fallback: 'Expiry batches are required for ${product.name}.',
              );
            }
            final requestedTotal = requested.fold<double>(
              0,
              (sum, allocation) => sum + allocation.quantity,
            );
            if ((requestedTotal - quantityDelta).abs() > 0.000001) {
              throw LocalizedDomainException(
                'error_batch_quantity_total',
                values: {'product': product.name, 'quantity': quantityDelta},
                fallback:
                    'Batch quantities for ${product.name} must equal $quantityDelta.',
              );
            }
            for (var batchIndex = 0;
                batchIndex < requested.length;
                batchIndex += 1) {
              final input = requested[batchIndex];
              resolved.add(
                await batchService.addUnifiedBatchStockInTransaction(
                  product: product,
                  warehouseId: warehouseId,
                  batchId: input.batchId.trim().isEmpty
                      ? '$baseMovementId-batch-$batchIndex'
                      : input.batchId.trim(),
                  quantity: input.quantity,
                  unitCost: newAdjustmentUnitCost,
                  sourceType: 'manual_adjustment_edit',
                  sourceId: operationId,
                  sourceLineId:
                      '$operationId:inventory_adjustment_edit:v$nextVersion:$batchIndex',
                  receivedAt: now,
                  storeId: appIdentity.storeId,
                  branchId: appIdentity.branchId,
                  deviceId: _deviceId,
                  supplierBatchNumber: input.supplierBatchNumber,
                  manufacturingDate: input.manufacturingDate,
                  expirationDate: input.expirationDate,
                ),
              );
            }
            newAdjustmentValue = quantityDelta * newAdjustmentUnitCost;
          }

          for (var batchIndex = 0;
              batchIndex < resolved.length;
              batchIndex += 1) {
            final allocation = resolved[batchIndex];
            movements.add(
              StockMovement(
                id: '$baseMovementId-batch-$batchIndex',
                productId: product.id,
                productName: product.name,
                type: quantityDelta < 0
                    ? 'inventory_loss'
                    : 'inventory_adjustment',
                quantity: quantityDelta < 0
                    ? -allocation.quantity
                    : allocation.quantity,
                date: now,
                referenceId: product.id,
                referenceNo: product.code,
                reason: reason.trim().isEmpty
                    ? 'Manual adjustment edit'
                    : reason.trim(),
                adjustmentCategory: adjustmentCategory.trim().isEmpty
                    ? 'other'
                    : adjustmentCategory.trim(),
                notes: notes.trim(),
                evidenceRef: evidenceRef.trim(),
                warehouseId: warehouseId,
                warehouseName: warehouseName,
                batchId: allocation.batchId,
                movementGroupId: operationId,
                documentLineId:
                    '$operationId-edit-v$nextVersion-line-batch-$batchIndex',
                idempotencyKey:
                    '$operationId:inventory_adjustment_edit:v$nextVersion:$batchIndex',
                unitCost: allocation.unitCost,
                createdAt: now,
                updatedAt: now,
                deviceId: _deviceId,
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                lastModifiedByDeviceId: _deviceId,
              ),
            );
          }
          await stockService.recordMovementsInTransaction(
            operationType: 'manual_adjustment_edit',
            documentType: 'inventory_adjustment',
            documentId: operationId,
            movementGroupId: operationId,
            idempotencyKey:
                '$operationId:inventory_adjustment_edit:v$nextVersion',
            movements: movements,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            deviceId: _deviceId,
            skipExistingMovementLookup: true,
          );
          await _assertUnifiedBatchMovementBalancesInTransaction(
            batchService,
            movements,
          );
          committedAllocations = List<BatchAllocation>.unmodifiable(resolved);
          committedMovements = List<StockMovement>.unmodifiable(movements);
          return movements;
        },
        buildPostedSnapshot: (updated) async => updated,
        repostAccounting: (_) async {
          final journalId = await AccountingService
              .recordManualInventoryAdjustmentInTransaction(
            database: db,
            entryDate: DateTime.now(),
            referenceId: journalReferenceId,
            referenceNo: product.code,
            productId: product.id,
            productName: product.name,
            quantityDelta: quantityDelta,
            value: newAdjustmentValue,
            adjustmentCategory: adjustmentCategory,
            reason: reason,
            createdBy: _activeUser?.fullName ?? _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
          );
          if (newAdjustmentValue.abs() >= 0.005 && journalId.trim().isEmpty) {
            throw StateError(
              'Edited inventory adjustment accounting journal was not created.',
            );
          }
        },
        rebuildDerivedState: (_) async {
          final stockAfterRow = await db.customSelect(
            '''
            SELECT COALESCE(SUM(quantity), 0) AS quantity
            FROM warehouse_inventory
            WHERE product_id = ?
            ''',
            variables: <Variable<Object>>[Variable<String>(product.id)],
          ).getSingleOrNull();
          final stockAfter =
              (stockAfterRow?.data['quantity'] as num? ?? 0).toDouble();
          final changedAt = DateTime.now();
          persistedAdjustedProduct = _withSyncMeta<Product>(
            product.copyWith(stock: stockAfter, updatedAt: changedAt),
            changedAt,
          );
          await BusinessSqliteStore.upsertEntityPayloads(
            db,
            AppStore._productsKey,
            <Map<String, dynamic>>[persistedAdjustedProduct!.toJson()],
            sortIndices: const <int?>[0],
          );
        },
        verifyIntegrity: (_) async {
          final activeRows = await db.customSelect(
            '''
            SELECT COALESCE(SUM(sm.quantity), 0) AS quantity
            FROM stock_movements sm
            WHERE sm.movement_group_id = ?
              AND sm.movement_type IN ('inventory_loss', 'inventory_adjustment')
              AND sm.deleted_at = ''
              AND NOT EXISTS (
                SELECT 1 FROM stock_movements rev
                WHERE rev.reversal_of_movement_id = sm.id
                  AND rev.deleted_at = ''
              )
            ''',
            variables: <Variable<Object>>[Variable<String>(operationId)],
          ).getSingle();
          final activeQuantity =
              (activeRows.data['quantity'] as num? ?? 0).toDouble();
          if ((activeQuantity - quantityDelta).abs() > 0.000001) {
            throw StateError(
              'Edited inventory adjustment failed stock integrity verification.',
            );
          }
          final journalRow = await db.customSelect(
            '''
            SELECT je.id
            FROM journal_entries je
            WHERE je.reference_type = 'inventory_adjustment'
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
              Variable<String>(journalReferenceId),
            ],
          ).getSingleOrNull();
          if (newAdjustmentValue.abs() >= 0.005 && journalRow == null) {
            throw StateError(
              'Edited inventory adjustment failed accounting integrity verification.',
            );
          }
          await batchService.assertWarehouseBatchBalanceInTransaction(
            productId: product.id,
            warehouseId: warehouseId,
            storeId: appIdentity.storeId,
          );
        },
      ).execute();
      if (edited.isEmpty) {
        throw StateError(
          'Edited inventory adjustment produced no stock movement.',
        );
      }
    });

    if (persistedAdjustedProduct != null) {
      final productIndex = _productIndexById[product.id];
      if (productIndex != null) {
        _products[productIndex] = persistedAdjustedProduct!;
      }
    }
    await refreshAfterDatabaseChange(AppStore._stockMovementsKey);
    await _refreshProductStockCompatibilityCache(<String>[product.id]);
    _inventoryCostLayers
      ..clear()
      ..addAll(await BusinessSqliteStore.readInventoryCostLayers(db));
    _rebuildInventoryCostLayerLookupCache();
    if (quantityDelta > 0 && committedAllocations.isNotEmpty) {
      _recordInventoryBatchSyncChanges(
        product: product,
        allocations: committedAllocations,
        sourceType: 'manual_adjustment_edit',
        sourceId: operationId,
        now: DateTime.now(),
        unitCost: newAdjustmentUnitCost,
        sourceLineIds: <String>[
          for (var index = 0; index < committedAllocations.length; index += 1)
            '$operationId:inventory_adjustment_edit:v$nextVersion:$index',
        ],
      );
    }
    for (final movement in committedMovements) {
      _recordSyncChange(
        entityType: 'stock_movement',
        entityId: movement.id,
        operation: 'edit_adjustment',
        payload: movement.toJson(),
      );
    }
    AccountingService.notifyCommittedMutation();
    notifyListeners();
  }
}
