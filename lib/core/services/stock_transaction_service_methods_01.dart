part of 'stock_transaction_service.dart';

extension StockTransactionServiceSplitPart1 on StockTransactionService {

  Future<double> getBalance({
    required String storeId,
    required String warehouseId,
    required String productId,
  }) async {
    final inventory = await WarehouseInventoryRepository.getByIdentity(
      db,
      storeId: storeId,
      warehouseId: warehouseId,
      productId: productId,
    );
    return inventory?.quantity ?? 0;
  }

  Future<List<WarehouseInventory>> listBalances({
    String storeId = '',
    String branchId = '',
    String warehouseId = '',
    String productId = '',
  }) {
    return WarehouseInventoryRepository.listBalances(
      db,
      storeId: storeId,
      branchId: branchId,
      warehouseId: warehouseId,
      productId: productId,
    );
  }

  Future<void> validateSufficientStock({
    required String storeId,
    required String warehouseId,
    required String productId,
    required double requestedQuantity,
  }) async {
    if (requestedQuantity <= 0) return;
    if (_allowNegativeStock(storeId, warehouseId)) return;
    final current = await getBalance(
      storeId: storeId,
      warehouseId: warehouseId,
      productId: productId,
    );
    if (current < requestedQuantity) {
      throw StateError(
        'Insufficient stock in warehouse $warehouseId for product $productId. '
        'Available: $current, requested: $requestedQuantity.',
      );
    }
  }

  Future<WarehouseInventory> applyDelta({
    required String storeId,
    required String warehouseId,
    required String productId,
    required double delta,
    String branchId = '',
    String warehouseInventoryId = '',
    String deviceId = '',
    String syncStatus = 'pending',
    String lastModifiedByDeviceId = '',
    DateTime? updatedAt,
  }) async {
    return db.transaction(() async {
      return _applyDeltaInTransaction(
        storeId: storeId,
        warehouseId: warehouseId,
        productId: productId,
        delta: delta,
        branchId: branchId,
        warehouseInventoryId: warehouseInventoryId,
        deviceId: deviceId,
        syncStatus: syncStatus,
        lastModifiedByDeviceId: lastModifiedByDeviceId,
        updatedAt: updatedAt,
      );
    });
  }

  Future<StockTransactionReceipt> recordMovementsAtomically({
    required String operationType,
    required String documentType,
    required String documentId,
    required String movementGroupId,
    required String idempotencyKey,
    required List<StockMovement> movements,
    String storeId = '',
    String branchId = '',
    String deviceId = '',
    String syncTarget = 'direct',
    bool skipExistingMovementLookup = false,
  }) async {
    final resolvedStoreId =
        storeId.trim().isEmpty ? defaultStoreId : storeId.trim();
    final resolvedBranchId =
        branchId.trim().isEmpty ? defaultBranchId : branchId.trim();
    final resolvedDeviceId =
        deviceId.trim().isEmpty ? this.deviceId : deviceId.trim();
    final now = DateTime.now().toUtc();
    final acquisition = await _acquireOperationRecord(
      storeId: resolvedStoreId,
      branchId: resolvedBranchId,
      operationType: operationType,
      documentType: documentType,
      documentId: documentId,
      movementGroupId: movementGroupId,
      idempotencyKey: idempotencyKey,
      now: now,
      deviceId: resolvedDeviceId,
    );
    if (acquisition.completedReceipt != null) {
      return acquisition.completedReceipt!;
    }
    if (!acquisition.proceed) {
      throw _StockOperationInProgressException(
        acquisition.inProgressMessage,
      );
    }
    try {
      late StockTransactionReceipt receipt;
      await db.transaction(() async {
        receipt = await recordMovementsInTransaction(
          operationType: operationType,
          documentType: documentType,
          documentId: documentId,
          movementGroupId: movementGroupId,
          idempotencyKey: idempotencyKey,
          movements: movements,
          storeId: resolvedStoreId,
          branchId: resolvedBranchId,
          deviceId: resolvedDeviceId,
          syncTarget: syncTarget,
          skipExistingMovementLookup: skipExistingMovementLookup,
        );
        // Phase 7: completion metadata is part of the same commit as the stock
        // movements. A process crash can no longer leave committed stock behind
        // while the idempotency record still says "pending".
        await _markOperationCompleted(
          storeId: resolvedStoreId,
          idempotencyKey: idempotencyKey,
          deviceId: resolvedDeviceId,
          completedAt: now,
        );
      });
      return receipt;
    } catch (error) {
      if (!_isInProgressError(error)) {
        await _markOperationFailed(
          storeId: resolvedStoreId,
          branchId: resolvedBranchId,
          operationType: operationType,
          documentType: documentType,
          documentId: documentId,
          movementGroupId: movementGroupId,
          idempotencyKey: idempotencyKey,
          deviceId: resolvedDeviceId,
          reason: error.toString(),
        );
      }
      rethrow;
    }
  }

  Future<StockTransactionReceipt> recordMovementsInTransaction({
    required String operationType,
    required String documentType,
    required String documentId,
    required String movementGroupId,
    required String idempotencyKey,
    required List<StockMovement> movements,
    String storeId = '',
    String branchId = '',
    String deviceId = '',
    String syncTarget = 'direct',
    bool skipExistingMovementLookup = false,
  }) async {
    if (idempotencyKey.trim().isEmpty) {
      throw ArgumentError('idempotencyKey is required.');
    }
    if (movementGroupId.trim().isEmpty) {
      throw ArgumentError('movementGroupId is required.');
    }
    if (movements.isEmpty) {
      throw ArgumentError('At least one movement is required.');
    }

    final resolvedStoreId =
        storeId.trim().isEmpty ? defaultStoreId : storeId.trim();
    final resolvedBranchId =
        branchId.trim().isEmpty ? defaultBranchId : branchId.trim();
    final resolvedDeviceId =
        deviceId.trim().isEmpty ? this.deviceId : deviceId.trim();
    final target =
        syncTarget.trim().isEmpty ? defaultSyncTarget : syncTarget.trim();
    final movementIds = <String>[];
    var sequence = await _nextSyncSequence();
    final now = DateTime.now().toUtc();
    for (var index = 0; index < movements.length; index += 1) {
      final movement = movements[index];
      final normalized = _normalizeMovement(
        movement,
        storeId: resolvedStoreId,
        branchId: resolvedBranchId,
        deviceId: resolvedDeviceId,
        movementGroupId: movementGroupId,
        idempotencyKeyPrefix: idempotencyKey,
        fallbackSyncStatus: 'pending',
      );
      await _assertUnifiedBatchIdentityInTransaction(normalized);
      final appliedMovementId = await _applyMovementAtomically(
        normalized,
        operationType: operationType,
        documentType: documentType,
        documentId: documentId,
        target: target,
        sequence: sequence,
        skipExistingLookup: skipExistingMovementLookup,
      );
      movementIds.add(appliedMovementId);
      sequence += 1;
    }

    return StockTransactionReceipt(
      operationId: idempotencyKey,
      operationType: operationType,
      documentType: documentType,
      documentId: documentId,
      movementGroupId: movementGroupId,
      movementIds: movementIds,
      idempotencyKey: idempotencyKey,
      completedAt: now,
    );
  }

  Future<StockTransactionReceipt> recordReversalInTransaction({
    required StockMovement originalMovement,
    required String operationType,
    required String documentType,
    required String documentId,
    String reason = '',
    String? reversalMovementId,
    String storeId = '',
    String branchId = '',
    String deviceId = '',
    String syncTarget = 'direct',
  }) {
    final groupId = 'reversal-${originalMovement.id}';
    final opKey = 'reversal:${originalMovement.id}';
    final normalizedReversalMovementId = reversalMovementId?.trim() ?? '';
    final reversalId = normalizedReversalMovementId.isEmpty
        ? 'reversal_${originalMovement.id}'
        : normalizedReversalMovementId;
    final movement = originalMovement.copyWith(
      id: reversalId,
      idempotencyKey: '$opKey:$reversalId',
      sourceMovementId: originalMovement.id,
      reversalOfMovementId: originalMovement.id,
      movementGroupId: groupId,
      type: reason.trim().isEmpty
          ? '${originalMovement.type}_reversal'
          : originalMovement.type.endsWith('_reversal')
              ? originalMovement.type
              : '${originalMovement.type}_reversal',
      quantity: -originalMovement.quantity,
      reason: reason.trim().isEmpty ? 'Reversal' : reason.trim(),
      clearReviewedAt: true,
      reviewedBy: '',
      reviewNote: '',
    );
    return recordMovementsInTransaction(
      operationType: operationType,
      documentType: documentType,
      documentId: documentId,
      movementGroupId: groupId,
      idempotencyKey: opKey,
      movements: <StockMovement>[
        movement.copyWith(
          productName: originalMovement.productName,
          warehouseId: originalMovement.warehouseId,
          warehouseName: originalMovement.warehouseName,
          sourceMovementId: originalMovement.id,
          reversalOfMovementId: originalMovement.id,
          movementGroupId: groupId,
          idempotencyKey: '$opKey:$reversalId',
        ),
      ],
      storeId: storeId,
      branchId: branchId,
      deviceId: deviceId,
      syncTarget: syncTarget,
    );
  }

  Future<StockTransactionReceipt> recordReversal({
    required StockMovement originalMovement,
    required String operationType,
    required String documentType,
    required String documentId,
    String reason = '',
    String? reversalMovementId,
    String storeId = '',
    String branchId = '',
    String deviceId = '',
    String syncTarget = 'direct',
  }) {
    final groupId = 'reversal-${originalMovement.id}';
    final opKey = 'reversal:${originalMovement.id}';
    final normalizedReversalMovementId = reversalMovementId?.trim() ?? '';
    final reversalId = normalizedReversalMovementId.isEmpty
        ? 'reversal_${originalMovement.id}'
        : normalizedReversalMovementId;
    final movement = originalMovement.copyWith(
      id: reversalId,
      idempotencyKey: '$opKey:$reversalId',
      sourceMovementId: originalMovement.id,
      reversalOfMovementId: originalMovement.id,
      movementGroupId: groupId,
      type: reason.trim().isEmpty
          ? '${originalMovement.type}_reversal'
          : originalMovement.type.endsWith('_reversal')
              ? originalMovement.type
              : '${originalMovement.type}_reversal',
      quantity: -originalMovement.quantity,
      reason: reason.trim().isEmpty ? 'Reversal' : reason.trim(),
      clearReviewedAt: true,
      reviewedBy: '',
      reviewNote: '',
    );
    return recordMovementsAtomically(
      operationType: operationType,
      documentType: documentType,
      documentId: documentId,
      movementGroupId: groupId,
      idempotencyKey: opKey,
      movements: <StockMovement>[
        movement.copyWith(
          productName: originalMovement.productName,
          warehouseId: originalMovement.warehouseId,
          warehouseName: originalMovement.warehouseName,
          sourceMovementId: originalMovement.id,
          reversalOfMovementId: originalMovement.id,
          movementGroupId: groupId,
          idempotencyKey: '$opKey:$reversalId',
        ),
      ],
      storeId: storeId,
      branchId: branchId,
      deviceId: deviceId,
      syncTarget: syncTarget,
    );
  }

  Future<StockIntegrityReport> checkIntegrity({
    String storeId = '',
  }) async {
    final resolvedStoreId =
        storeId.trim().isEmpty ? defaultStoreId : storeId.trim();
    final products = await db.customSelect('''
      SELECT id, name
      FROM products
      WHERE deleted_at = '' AND (? = '' OR store_id = ?)
      ORDER BY id ASC
    ''', variables: <Variable<Object>>[
      Variable<String>(resolvedStoreId),
      Variable<String>(resolvedStoreId),
    ]).get();
    final inventoryRows = await db.customSelect('''
      SELECT store_id, warehouse_id, product_id, quantity
      FROM warehouse_inventory
      WHERE (? = '' OR store_id = ?)
    ''', variables: <Variable<Object>>[
      Variable<String>(resolvedStoreId),
      Variable<String>(resolvedStoreId),
    ]).get();
    final movementRows = await db.customSelect('''
      SELECT store_id, warehouse_id, product_id, COALESCE(SUM(quantity), 0) AS quantity
      FROM stock_movements
      WHERE (? = '' OR store_id = ?)
      GROUP BY store_id, warehouse_id, product_id
    ''', variables: <Variable<Object>>[
      Variable<String>(resolvedStoreId),
      Variable<String>(resolvedStoreId),
    ]).get();

    final movementByIdentity = <String, double>{
      for (final row in movementRows)
        _identityKey(
          row.read<String>('store_id'),
          row.read<String>('warehouse_id'),
          row.read<String>('product_id'),
        ): (row.data['quantity'] as num? ?? 0).toDouble(),
    };
    final productById = <String, Map<String, dynamic>>{
      for (final row in products) row.read<String>('id'): row.data,
    };
    final issues = <StockIntegrityIssue>[];
    final seenKeys = <String>{};
    for (final row in inventoryRows) {
      final storeValue = row.read<String>('store_id');
      final warehouseId = row.read<String>('warehouse_id');
      final productId = row.read<String>('product_id');
      final key = _identityKey(storeValue, warehouseId, productId);
      seenKeys.add(key);
      final warehouseBalance = (row.data['quantity'] as num? ?? 0).toDouble();
      final ledgerBalance = movementByIdentity[key] ?? 0;
      const legacyStock = 0.0;
      final productName = productById[productId]?['name']?.toString() ?? '';
      final difference = warehouseBalance - ledgerBalance;
      final classification = warehouseBalance == 0 && ledgerBalance != 0
          ? 'missing_warehouse_balance'
          : difference.abs() > 0.000001
              ? 'warehouse_balance_mismatch'
              : 'ok';
      if (classification != 'ok') {
        issues.add(
          StockIntegrityIssue(
            storeId: storeValue,
            warehouseId: warehouseId,
            productId: productId,
            productName: productName,
            warehouseBalance: warehouseBalance,
            ledgerBalance: ledgerBalance,
            legacyProductStock: legacyStock,
            difference: difference,
            classification: classification,
          ),
        );
      }
    }

    for (final row in movementRows) {
      final storeValue = row.read<String>('store_id');
      final warehouseId = row.read<String>('warehouse_id');
      final productId = row.read<String>('product_id');
      final key = _identityKey(storeValue, warehouseId, productId);
      if (seenKeys.contains(key)) continue;
      final ledgerBalance = (row.data['quantity'] as num? ?? 0).toDouble();
      const legacyStock = 0.0;
      final productName = productById[productId]?['name']?.toString() ?? '';
      issues.add(
        StockIntegrityIssue(
          storeId: storeValue,
          warehouseId: warehouseId,
          productId: productId,
          productName: productName,
          warehouseBalance: 0,
          ledgerBalance: ledgerBalance,
          legacyProductStock: legacyStock,
          difference: -ledgerBalance,
          classification: 'missing_warehouse_balance',
        ),
      );
    }


    final movementWithoutWarehouseRows = await db.customSelect('''
      SELECT store_id, branch_id, product_id, product_name, quantity, warehouse_id
      FROM stock_movements
      WHERE (? = '' OR store_id = ?)
        AND (warehouse_id IS NULL OR TRIM(warehouse_id) = '')
    ''', variables: <Variable<Object>>[
      Variable<String>(resolvedStoreId),
      Variable<String>(resolvedStoreId),
    ]).get();
    for (final row in movementWithoutWarehouseRows) {
      issues.add(
        StockIntegrityIssue(
          storeId: row.read<String>('store_id'),
          warehouseId: '',
          productId: row.read<String>('product_id'),
          productName: row.read<String>('product_name'),
          warehouseBalance: 0,
          ledgerBalance: (row.data['quantity'] as num? ?? 0).toDouble(),
          legacyProductStock: 0,
          difference: (row.data['quantity'] as num? ?? 0).toDouble(),
          classification: 'missing_warehouse_balance',
        ),
      );
    }

    final duplicateIdempotencyRows = await db.customSelect('''
      SELECT store_id, idempotency_key, COUNT(*) AS row_count
      FROM stock_movements
      WHERE (? = '' OR store_id = ?)
        AND TRIM(COALESCE(idempotency_key, '')) <> ''
      GROUP BY store_id, idempotency_key
      HAVING COUNT(*) > 1
    ''', variables: <Variable<Object>>[
      Variable<String>(resolvedStoreId),
      Variable<String>(resolvedStoreId),
    ]).get();
    for (final row in duplicateIdempotencyRows) {
      issues.add(
        StockIntegrityIssue(
          storeId: row.read<String>('store_id'),
          warehouseId: '',
          productId: row.read<String>('idempotency_key'),
          productName: 'Duplicate idempotency key',
          warehouseBalance: 0,
          ledgerBalance: (row.data['row_count'] as num? ?? 0).toDouble(),
          legacyProductStock: 0,
          difference: (row.data['row_count'] as num? ?? 0).toDouble() - 1,
          classification: 'ledger_mismatch',
        ),
      );
    }

    final staleOperationRows = await db.customSelect('''
      SELECT store_id, branch_id, document_id, operation_type, status, started_at, updated_at
      FROM stock_operations
      WHERE (? = '' OR store_id = ?)
        AND status = 'pending'
    ''', variables: <Variable<Object>>[
      Variable<String>(resolvedStoreId),
      Variable<String>(resolvedStoreId),
    ]).get();
    for (final row in staleOperationRows) {
      final startedAt = _parseDate(row.read<String>('started_at')) ??
          _parseDate(row.read<String>('updated_at')) ??
          DateTime.now();
      if (DateTime.now().toUtc().difference(startedAt) <=
          _operationPendingTimeout) {
        continue;
      }
      issues.add(
        StockIntegrityIssue(
          storeId: row.read<String>('store_id'),
          warehouseId: '',
          productId: row.read<String>('document_id'),
          productName: row.read<String>('operation_type'),
          warehouseBalance: 0,
          ledgerBalance: 0,
          legacyProductStock: 0,
          difference: 0,
          classification: 'ledger_mismatch',
        ),
      );
    }

    final message = issues.isEmpty
        ? 'No integrity issues detected.'
        : 'Detected ${issues.length} stock integrity issue(s).';
    return StockIntegrityReport(
      ok: issues.isEmpty,
      message: message,
      issues: issues,
    );
  }


  Future<WarehouseInventory> _applyDeltaInTransaction({
    required String storeId,
    required String warehouseId,
    required String productId,
    required double delta,
    required String branchId,
    required String warehouseInventoryId,
    required String deviceId,
    required String syncStatus,
    required String lastModifiedByDeviceId,
    required DateTime? updatedAt,
  }) async {
    if (delta == 0) {
      final existing = await WarehouseInventoryRepository.getByIdentity(
        db,
        storeId: storeId,
        warehouseId: warehouseId,
        productId: productId,
      );
      if (existing != null) return existing;
      final now = updatedAt ?? DateTime.now().toUtc();
      final created = WarehouseInventory(
        id: warehouseInventoryId.isEmpty
            ? 'wi_${storeId}_${warehouseId}_${productId}_${now.microsecondsSinceEpoch}'
            : warehouseInventoryId,
        storeId: storeId,
        branchId: branchId.isEmpty ? defaultBranchId : branchId,
        warehouseId: warehouseId,
        productId: productId,
        quantity: 0,
        createdAt: now,
        updatedAt: now,
        deviceId: deviceId,
        syncStatus: syncStatus,
        lastModifiedByDeviceId:
            lastModifiedByDeviceId.isEmpty ? deviceId : lastModifiedByDeviceId,
      );
      await WarehouseInventoryRepository.upsert(db, created);
      return created;
    }

    if (delta < 0) {
      await validateSufficientStock(
        storeId: storeId,
        warehouseId: warehouseId,
        productId: productId,
        requestedQuantity: delta.abs(),
      );
    }

    final existing = await WarehouseInventoryRepository.getByIdentity(
      db,
      storeId: storeId,
      warehouseId: warehouseId,
      productId: productId,
    );
    final now = (updatedAt ?? DateTime.now()).toUtc();
    final nextQuantity = (existing?.quantity ?? 0) + delta;
    final nextVersion = (existing?.version ?? 0) + 1;
    final inventory = WarehouseInventory(
      id: existing?.id ??
          (warehouseInventoryId.isEmpty
              ? 'wi_${storeId}_${warehouseId}_${productId}_${now.microsecondsSinceEpoch}'
              : warehouseInventoryId),
      storeId: storeId,
      branchId: branchId.isEmpty
          ? (existing?.branchId.isNotEmpty == true
              ? existing!.branchId
              : defaultBranchId)
          : branchId,
      warehouseId: warehouseId,
      productId: productId,
      quantity: nextQuantity,
      version: nextVersion,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      deviceId: deviceId,
      syncStatus: syncStatus,
      lastModifiedByDeviceId:
          lastModifiedByDeviceId.isEmpty ? deviceId : lastModifiedByDeviceId,
    );
    await WarehouseInventoryRepository.upsert(db, inventory);
    return inventory;
  }
}
