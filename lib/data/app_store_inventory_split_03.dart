part of 'app_store.dart';

extension _AppStoreSplitInventoryPart3 on AppStore {
  Future<void> reverseExpiryBatchAdjustment(
    String movementId, {
    String reason = '',
  }) async {
    requirePermission(AppPermission.inventoryCorrectionsManage);
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw StateError(
          'Expiry reversal requires the authoritative SQLite store.');
    }
    final original = (await BusinessSqliteStore.readStockMovements(db))
        .where((movement) => movement.id == movementId)
        .firstOrNull;
    if (original == null || original.batchId.isEmpty) {
      throw ArgumentError('Expiry batch movement not found.');
    }
    if (original.reversalOfMovementId.isNotEmpty ||
        (await BusinessSqliteStore.readStockMovements(db)).any(
          (movement) => movement.reversalOfMovementId == original.id,
        )) {
      throw StateError('This expiry adjustment has already been reversed.');
    }
    final product = _findProductById(original.productId);
    if (product == null) throw StateError('Expiry product no longer exists.');
    final now = DateTime.now();
    final reversalId = 'reversal_${original.id}';
    final operationId = original.movementGroupId.isEmpty
        ? original.id
        : original.movementGroupId;
    final stockService = StockTransactionService(
      db,
      deviceId: _deviceId,
      defaultStoreId: appIdentity.storeId,
      defaultBranchId: appIdentity.branchId,
      defaultSyncTarget: _stockTransactionSyncTarget,
      allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
    );
    await db.transaction(() async {
      final activeJournalRow = await db.customSelect(
        '''
        SELECT reference_type
        FROM journal_entries
        WHERE reference_id = ?
          AND reference_type IN ('inventory_waste', 'inventory_adjustment')
          AND deleted_at = '' AND status = 'posted'
        ORDER BY created_at DESC, id DESC
        LIMIT 1
        ''',
        variables: <Variable<Object>>[Variable<String>(operationId)],
      ).getSingleOrNull();
      final accountingReferenceType =
          activeJournalRow?.data['reference_type']?.toString() ?? '';
      if (accountingReferenceType.isEmpty) {
        throw StateError(
            'The accounting journal for this batch adjustment is missing.');
      }

      if (original.quantity < 0) {
        await BatchInventoryService(db).restoreUnifiedInTransaction(
          product: product,
          warehouseId: original.warehouseId,
          allocations: <BatchAllocation>[
            BatchAllocation(
              batchId: original.batchId,
              quantity: original.quantity.abs(),
              unitCost: original.unitCost,
            ),
          ],
          restoredAt: now,
          storeId: appIdentity.storeId,
          deviceId: _deviceId,
        );

        // Only historical pre-Unified adjustments need a compatibility cost
        // layer. New Unified movements restore value through the Batch itself;
        // creating a parallel layer here would re-introduce a second inventory
        // valuation truth.
        final cutoverRow = await db.customSelect(
          '''
          SELECT cutover_at
          FROM unified_batch_cutovers
          WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
          LIMIT 1
          ''',
          variables: <Variable<Object>>[
            Variable<String>(appIdentity.storeId),
            Variable<String>(original.warehouseId),
            Variable<String>(original.productId),
          ],
        ).getSingleOrNull();
        final cutoverAt =
            DateTime.tryParse(cutoverRow?.data['cutover_at']?.toString() ?? '');
        final isHistoricalPreUnified =
            cutoverAt == null || original.date.isBefore(cutoverAt);
        if (isHistoricalPreUnified) {
          final layer = InventoryCostLayer(
            id: '$reversalId-cost-layer',
            productId: product.id,
            productName: product.name,
            quantityReceived: original.quantity.abs(),
            quantityRemaining: original.quantity.abs(),
            unitCost: original.unitCost,
            currencyCode: 'USD',
            exchangeRate: 1,
            sourceType: 'expiry_batch_reversal',
            sourceId: original.id,
            createdAt: now,
            updatedAt: now,
          );
          await BusinessSqliteStore.upsertEntityPayloads(
            db,
            AppStore._inventoryCostLayersKey,
            <Map<String, dynamic>>[layer.toJson()],
            sortIndices: const <int?>[0],
          );
        }
      } else {
        // Phase-2/pre-Unified positive expiry adjustments may still own a
        // legacy cost layer. Remove it only when it exists; new Unified
        // adjustments have no parallel layer.
        final layers = await BusinessSqliteStore.readInventoryCostLayers(db);
        final layer = layers
            .where((item) =>
                item.productId == product.id &&
                item.sourceType == 'expiry_batch_adjustment' &&
                item.sourceId == operationId)
            .firstOrNull;
        if (layer != null) {
          if (layer.quantityRemaining + 0.000001 < original.quantity) {
            throw StateError(
                'Expiry gain has downstream consumption and cannot be reversed.');
          }
          final remaining = layer.quantityRemaining - original.quantity;
          await BusinessSqliteStore.upsertEntityPayloads(
            db,
            AppStore._inventoryCostLayersKey,
            <Map<String, dynamic>>[
              layer
                  .copyWith(
                    quantityRemaining: remaining,
                    isClosed: remaining <= 0.000001,
                    updatedAt: now,
                  )
                  .toJson(),
            ],
            sortIndices: const <int?>[0],
          );
        }
        await BatchInventoryService(db)
            .reverseUnifiedMovementEffectInTransaction(
          product: product,
          warehouseId: original.warehouseId,
          batchId: original.batchId,
          movementQuantity: original.quantity,
          unitCost: original.unitCost,
          reversedAt: now,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          deviceId: _deviceId,
        );
      }

      await _requirePostedJournalInTransaction(
        db,
        referenceType: accountingReferenceType,
        referenceId: operationId,
        failureMessage:
            'Batch adjustment journal is missing; the reversal was rolled back.',
      );
      await AccountingService.reverseEntryForReference(
        referenceType: accountingReferenceType,
        referenceId: operationId,
        reason: reason.trim().isEmpty ? 'Expiry adjustment reversal' : reason,
        createdBy: _actorName(),
        notifyChange: false,
        withinExistingTransaction: true,
      );
      await _requireNoActiveJournalInTransaction(
        db,
        referenceType: accountingReferenceType,
        referenceId: operationId,
        failureMessage:
            'Batch adjustment journal reversal did not complete; the reversal was rolled back.',
      );
      await stockService.recordReversalInTransaction(
        originalMovement: original,
        operationType: 'expiry_batch_reversal',
        documentType: 'inventory_batch',
        documentId: original.batchId,
        reason: reason.trim().isEmpty ? 'Expiry adjustment reversal' : reason,
        reversalMovementId: reversalId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        deviceId: _deviceId,
        syncTarget: _stockTransactionSyncTarget,
      );
      await BatchInventoryService(db).assertWarehouseBatchBalanceInTransaction(
        productId: original.productId,
        warehouseId: original.warehouseId,
        storeId: appIdentity.storeId,
      );
    });
    final reversal = original.copyWith(
      id: reversalId,
      type: '${original.type}_reversal',
      quantity: -original.quantity,
      date: now,
      reason: reason.trim().isEmpty ? 'Expiry adjustment reversal' : reason,
      sourceMovementId: original.id,
      reversalOfMovementId: original.id,
      movementGroupId: 'reversal-${original.id}',
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      lastModifiedByDeviceId: _deviceId,
    );
    _mirrorAuthoritativeStockMovements(<StockMovement>[reversal]);
    await _refreshProductStockCompatibilityCache(<String>[product.id]);
    _inventoryCostLayers
      ..clear()
      ..addAll(await BusinessSqliteStore.readInventoryCostLayers(db));
    _rebuildInventoryCostLayerLookupCache();
    _recordSyncChange(
      entityType: 'stock_movement',
      entityId: reversal.id,
      operation: 'reverse_expiry_batch',
      payload: reversal.toJson(),
    );
    AccountingService.notifyCommittedMutation();
    notifyListeners();
  }

  Future<int> manualStockAdjustmentVersion(String operationReferenceId) async {
    final operationId = operationReferenceId.trim();
    if (operationId.isEmpty) return 0;
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) return 0;
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
    final referenceId = row?.data['reference_id']?.toString() ?? '';
    if (referenceId.isEmpty) return 0;
    if (referenceId == operationId) return 1;
    final parsed = int.tryParse(
      referenceId.substring(prefix.length).replaceFirst('v', ''),
    );
    return parsed ?? 1;
  }
}
