part of 'stock_transaction_service.dart';

extension StockTransactionServiceSplitPart2 on StockTransactionService {

  Future<void> _assertUnifiedBatchIdentityInTransaction(
    StockMovement movement,
  ) async {
    if (movement.quantity.abs() <= 0.000001) return;
    final storeId = movement.storeId.trim().isEmpty
        ? defaultStoreId
        : movement.storeId.trim();
    final warehouseId = movement.warehouseId.trim();
    if (storeId.isEmpty || warehouseId.isEmpty || movement.productId.isEmpty) {
      return;
    }

    final productRow = await db.customSelect(
      '''
      SELECT name, track_stock
      FROM products
      WHERE id = ? AND deleted_at = ''
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(movement.productId),
      ],
    ).getSingleOrNull();
    final trackStock =
        (productRow?.data['track_stock'] as num? ?? 0).toInt() == 1;
    if (!trackStock) return;
    final productName =
        productRow?.data['name']?.toString().trim().isNotEmpty == true
            ? productRow!.data['name']!.toString()
            : movement.productName;

    final phaseRow = await db.customSelect(
      '''
      SELECT value
      FROM migration_meta
      WHERE key = 'unified_batch_phase4_state'
      LIMIT 1
      ''',
    ).getSingleOrNull();
    final phaseState =
        phaseRow?.data['value']?.toString().trim().toLowerCase() ?? '';
    if (phaseState == 'blocked') {
      throw LocalizedDomainException(
        'error_unified_batch_phase4_blocked',
        values: <String, Object?>{'product': productName},
        fallback:
            'Unified Batch migration is blocked by an inventory reconciliation error. Repair the inventory before posting new stock movements.',
      );
    }

    if (movement.batchId.trim().isNotEmpty) return;
    if (phaseState == 'completed') {
      throw LocalizedDomainException(
        'error_post_cutover_batch_required',
        values: <String, Object?>{'product': productName},
        fallback:
            'لا يمكن تسجيل حركة مخزون للمنتج $productName بعد تفعيل نظام الدُفعات دون تحديد الدفعة.',
      );
    }

    final marker = await db.customSelect(
      '''
      SELECT 1
      FROM unified_batch_cutovers uc
      WHERE uc.store_id = ? AND uc.warehouse_id = ? AND uc.product_id = ?
        AND datetime(?) >= datetime(uc.cutover_at)
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(movement.productId),
        Variable<String>(movement.date.toUtc().toIso8601String()),
      ],
    ).getSingleOrNull();
    if (marker == null) return;
    throw LocalizedDomainException(
      'error_post_cutover_batch_required',
      values: <String, Object?>{'product': productName},
      fallback:
          'لا يمكن تسجيل حركة مخزون للمنتج $productName بعد تفعيل نظام الدُفعات دون تحديد الدفعة.',
    );
  }

  Future<String> _applyMovementAtomically(
    StockMovement movement, {
    required String operationType,
    required String documentType,
    required String documentId,
    required String target,
    required int sequence,
    bool skipExistingLookup = false,
  }) async {
    final now = movement.updatedAt.toUtc();
    if (!skipExistingLookup) {
      final existingMovementId = await _existingMovementId(movement);
      if (existingMovementId != null) {
        return existingMovementId;
      }
    }

    final insertedMovement = await _insertStockMovementAppendOnly(
      movement,
      skipExistingCheck: true,
    );
    if (!insertedMovement.inserted) {
      return insertedMovement.movementId;
    }

    await _applyDeltaInTransaction(
      storeId: movement.storeId.isEmpty ? defaultStoreId : movement.storeId,
      warehouseId: movement.warehouseId,
      productId: movement.productId,
      delta: movement.quantity,
      branchId: movement.branchId.isEmpty ? defaultBranchId : movement.branchId,
      warehouseInventoryId: '',
      deviceId: movement.deviceId,
      syncStatus: movement.syncStatus,
      lastModifiedByDeviceId: movement.lastModifiedByDeviceId,
      updatedAt: now,
    );

    final localOnly = target == 'local';
    final change = SyncChange(
      id: movement.id,
      entityType: 'stock_movement',
      entityId: movement.id,
      operation: operationType,
      deviceId: movement.deviceId.isEmpty ? deviceId : movement.deviceId,
      createdAt: now,
      payload: movement.toJson(),
      storeId: movement.storeId.isEmpty ? defaultStoreId : movement.storeId,
      branchId: movement.branchId.isEmpty ? defaultBranchId : movement.branchId,
      isSynced: localOnly,
      syncedAt: localOnly ? now : null,
      storeEpoch: 1,
      sequence: sequence,
    );
    await db.customInsert(
      '''
      INSERT OR REPLACE INTO sync_events
        (id, entity_type, entity_id, operation, device_id, store_id, branch_id,
         payload_json, is_synced, created_at, synced_at, store_epoch, sequence)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(change.id),
        Variable<String>(change.entityType),
        Variable<String>(change.entityId),
        Variable<String>(change.operation),
        Variable<String>(change.deviceId),
        Variable<String>(change.storeId),
        Variable<String>(change.branchId),
        Variable<String>(_payloadJson(change.payload)),
        Variable<int>(localOnly ? 1 : 0),
        Variable<String>(change.createdAt.toIso8601String()),
        Variable<String>(localOnly ? now.toIso8601String() : ''),
        Variable<int>(change.storeEpoch),
        Variable<int>(change.sequence),
      ],
    );
    if (localOnly) return insertedMovement.movementId;
    await db.customInsert(
      '''
      INSERT OR REPLACE INTO pending_sync_changes
        (id, event_id, entity_type, entity_id, operation, device_id, store_id,
         branch_id, payload_json, created_at, store_epoch, sequence)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>('pending_${movement.id}'),
        Variable<String>(change.id),
        Variable<String>(change.entityType),
        Variable<String>(change.entityId),
        Variable<String>(change.operation),
        Variable<String>(change.deviceId),
        Variable<String>(change.storeId),
        Variable<String>(change.branchId),
        Variable<String>(_payloadJson(change.payload)),
        Variable<String>(change.createdAt.toIso8601String()),
        Variable<int>(change.storeEpoch),
        Variable<int>(change.sequence),
      ],
    );
    await db.customInsert(
      '''
      INSERT OR REPLACE INTO sync_queue
        (id, change_id, target, status, attempts, last_error, next_retry_at,
         created_at, updated_at)
      VALUES (?, ?, ?, 'pending', 0, '', '', ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>('queue_${movement.id}'),
        Variable<String>(change.id),
        Variable<String>(target),
        Variable<String>(now.toIso8601String()),
        Variable<String>(now.toIso8601String()),
      ],
    );
    return insertedMovement.movementId;
  }

  Future<_MovementInsertResult> _insertStockMovementAppendOnly(
    StockMovement movement, {
    bool skipExistingCheck = false,
  }) async {
    if (!skipExistingCheck) {
      final existing = await _existingMovementId(movement);
      if (existing != null) {
        return _MovementInsertResult(movementId: existing, inserted: false);
      }
    }
    try {
      await db.customInsert(
        '''
        INSERT INTO stock_movements
          (id, entity_type, created_at, updated_at, deleted_at, device_id,
           sync_status, store_id, branch_id, version, sort_index, product_id,
           product_name, movement_type, quantity, movement_date, reference_id,
           reference_no, reason, adjustment_category, notes, evidence_ref,
           warehouse_id, warehouse_name, batch_id, movement_group_id, document_line_id,
           source_movement_id, reversal_of_movement_id, idempotency_key, unit_cost,
           last_modified_by_device_id, reviewed_at, reviewed_by, review_note)
        VALUES (?, 'stock_movement', ?, ?, '', ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(movement.id),
          Variable<String>(movement.createdAt.toUtc().toIso8601String()),
          Variable<String>(movement.updatedAt.toUtc().toIso8601String()),
          Variable<String>(movement.deviceId),
          Variable<String>(movement.syncStatus),
          Variable<String>(movement.storeId),
          Variable<String>(movement.branchId),
          Variable<int>(movement.version),
          Variable<String>(movement.productId),
          Variable<String>(movement.productName),
          Variable<String>(movement.type),
          Variable<double>(movement.quantity),
          Variable<String>(movement.date.toUtc().toIso8601String()),
          Variable<String>(movement.referenceId),
          Variable<String>(movement.referenceNo),
          Variable<String>(movement.reason),
          Variable<String>(movement.adjustmentCategory),
          Variable<String>(movement.notes),
          Variable<String>(movement.evidenceRef),
          Variable<String>(movement.warehouseId),
          Variable<String>(movement.warehouseName),
          Variable<String>(movement.batchId),
          Variable<String>(movement.movementGroupId),
          Variable<String>(movement.documentLineId),
          Variable<String>(movement.sourceMovementId),
          Variable<String>(movement.reversalOfMovementId),
          Variable<String>(movement.idempotencyKey),
          Variable<double>(movement.unitCost),
          Variable<String>(movement.lastModifiedByDeviceId),
          Variable<String>(
              movement.reviewedAt?.toUtc().toIso8601String() ?? ''),
          Variable<String>(movement.reviewedBy),
          Variable<String>(movement.reviewNote),
        ],
      );
      return _MovementInsertResult(movementId: movement.id, inserted: true);
    } catch (error) {
      if (_isUniqueConstraintError(error)) {
        final existingAfter = await _existingMovementId(movement);
        if (existingAfter != null) {
          return _MovementInsertResult(
            movementId: existingAfter,
            inserted: false,
          );
        }
      }
      rethrow;
    }
  }

  Future<_OperationAcquisition> _acquireOperationRecord({
    required String storeId,
    required String branchId,
    required String operationType,
    required String documentType,
    required String documentId,
    required String movementGroupId,
    required String idempotencyKey,
    required DateTime now,
    required String deviceId,
  }) async {
    final startedAt = now.toIso8601String();
    try {
      await db.customInsert(
        '''
        INSERT INTO stock_operations
          (id, store_id, branch_id, operation_type, document_type, document_id,
           movement_group_id, idempotency_key, status, created_at, started_at,
           updated_at, completed_at, failure_reason, attempt_count, device_id,
           last_modified_by_device_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?, '', '', 1, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(idempotencyKey),
          Variable<String>(storeId),
          Variable<String>(branchId),
          Variable<String>(operationType),
          Variable<String>(documentType),
          Variable<String>(documentId),
          Variable<String>(movementGroupId),
          Variable<String>(idempotencyKey),
          Variable<String>(startedAt),
          Variable<String>(startedAt),
          Variable<String>(startedAt),
          Variable<String>(deviceId),
          Variable<String>(deviceId),
        ],
      );
      return const _OperationAcquisition.proceed(
        currentStatus: 'pending',
        attemptCount: 1,
      );
    } catch (error) {
      if (!_isUniqueConstraintError(error)) rethrow;
      final row = await _loadOperationRow(
        storeId: storeId,
        idempotencyKey: idempotencyKey,
      );
      if (row == null) rethrow;
      final status = row.read<String>('status');
      if (status == 'completed') {
        return _OperationAcquisition.completed(
          await _receiptFromOperationRow(row, storeId: storeId),
        );
      }
      final existingAttemptCount = row.read<int>('attempt_count');
      final existingStartedAt = _parseDate(row.read<String>('started_at')) ??
          _parseDate(row.read<String>('created_at')) ??
          now;
      final isPendingStale = status == 'pending' &&
          now.difference(existingStartedAt) > _operationPendingTimeout;
      if (status == 'pending' && !isPendingStale) {
        return _OperationAcquisition.inProgress(
          'Operation $idempotencyKey is already in progress.',
        );
      }
      await db.customUpdate(
        '''
        UPDATE stock_operations
        SET status = 'pending',
            started_at = ?,
            updated_at = ?,
            completed_at = '',
            failure_reason = '',
            attempt_count = ?,
            device_id = ?,
            last_modified_by_device_id = ?
        WHERE store_id = ? AND idempotency_key = ?
        ''',
        variables: <Variable<Object>>[
          Variable<String>(startedAt),
          Variable<String>(startedAt),
          Variable<int>(existingAttemptCount + 1),
          Variable<String>(deviceId),
          Variable<String>(deviceId),
          Variable<String>(storeId),
          Variable<String>(idempotencyKey),
        ],
      );
      return _OperationAcquisition.proceed(
        currentStatus: status,
        attemptCount: existingAttemptCount + 1,
      );
    }
  }

  Future<void> _markOperationCompleted({
    required String storeId,
    required String idempotencyKey,
    required String deviceId,
    required DateTime completedAt,
  }) async {
    final text = completedAt.toIso8601String();
    await db.customUpdate(
      '''
      UPDATE stock_operations
      SET status = 'completed',
          completed_at = ?,
          started_at = COALESCE(NULLIF(started_at, ''), ?),
          updated_at = ?,
          failure_reason = '',
          device_id = ?,
          last_modified_by_device_id = ?
      WHERE store_id = ? AND idempotency_key = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(text),
        Variable<String>(text),
        Variable<String>(text),
        Variable<String>(deviceId),
        Variable<String>(deviceId),
        Variable<String>(storeId),
        Variable<String>(idempotencyKey),
      ],
    );
  }

  Future<void> _markOperationFailed({
    required String storeId,
    required String branchId,
    required String operationType,
    required String documentType,
    required String documentId,
    required String movementGroupId,
    required String idempotencyKey,
    required String deviceId,
    required String reason,
  }) async {
    final now = DateTime.now().toUtc();
    final updatedRows = await db.customUpdate(
      '''
      UPDATE stock_operations
      SET status = 'failed',
          started_at = COALESCE(NULLIF(started_at, ''), ?),
          updated_at = ?,
          completed_at = '',
          failure_reason = ?,
          attempt_count = attempt_count + 1,
          device_id = ?,
          last_modified_by_device_id = ?
      WHERE idempotency_key = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(now.toIso8601String()),
        Variable<String>(now.toIso8601String()),
        Variable<String>(reason),
        Variable<String>(deviceId),
        Variable<String>(deviceId),
        Variable<String>(idempotencyKey),
      ],
    );
    if (updatedRows > 0) return;
    await db.customInsert(
      '''
      INSERT INTO stock_operations
        (id, store_id, branch_id, operation_type, document_type, document_id,
         movement_group_id, idempotency_key, status, created_at, started_at,
         updated_at, completed_at, failure_reason, attempt_count, device_id,
         last_modified_by_device_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'failed', ?, ?, ?, '', ?, 1, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(idempotencyKey),
        Variable<String>(storeId),
        Variable<String>(branchId),
        Variable<String>(operationType),
        Variable<String>(documentType),
        Variable<String>(documentId),
        Variable<String>(movementGroupId),
        Variable<String>(idempotencyKey),
        Variable<String>(now.toIso8601String()),
        Variable<String>(now.toIso8601String()),
        Variable<String>(now.toIso8601String()),
        Variable<String>(reason),
        Variable<String>(deviceId),
        Variable<String>(deviceId),
      ],
    );
  }

  Future<QueryRow?> _loadOperationRow({
    required String storeId,
    required String idempotencyKey,
  }) async {
    final rows = await db.customSelect(
      '''
      SELECT *
      FROM stock_operations
      WHERE store_id = ? AND idempotency_key = ?
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(idempotencyKey),
      ],
    ).get();
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<String?> _existingMovementId(StockMovement movement) async {
    if (movement.idempotencyKey.trim().isNotEmpty) {
      final rows = await db.customSelect(
        '''
        SELECT id
        FROM stock_movements
        WHERE idempotency_key = ?
        LIMIT 1
        ''',
        variables: <Variable<Object>>[
          Variable<String>(movement.idempotencyKey.trim()),
        ],
      ).get();
      if (rows.isNotEmpty) return rows.first.read<String>('id');
    }
    final rowsById = await db.customSelect(
      '''
      SELECT id
      FROM stock_movements
      WHERE id = ?
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(movement.id),
      ],
    ).get();
    if (rowsById.isNotEmpty) return rowsById.first.read<String>('id');
    return null;
  }

  bool _isUniqueConstraintError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('unique constraint failed') ||
        text.contains('constraint failed') ||
        text.contains('is not unique');
  }

  bool _isInProgressError(Object error) =>
      error is _StockOperationInProgressException;

  Duration get _operationPendingTimeout => const Duration(minutes: 5);

  String _identityKey(String storeId, String warehouseId, String productId) =>
      '$storeId::$warehouseId::$productId';

  Future<StockTransactionReceipt> _receiptFromOperationRow(
    QueryRow row, {
    required String storeId,
  }) async {
    final groupId = row.read<String>('movement_group_id');
    final movementRows = await db.customSelect(
      '''
      SELECT id
      FROM stock_movements
      WHERE store_id = ? AND movement_group_id = ?
      ORDER BY sort_index ASC, updated_at ASC, id ASC
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(groupId),
      ],
    ).get();
    return StockTransactionReceipt(
      operationId: row.read<String>('id'),
      operationType: row.read<String>('operation_type'),
      documentType: row.read<String>('document_type'),
      documentId: row.read<String>('document_id'),
      movementGroupId: groupId,
      movementIds: movementRows
          .map((item) => item.read<String>('id'))
          .toList(growable: false),
      idempotencyKey: row.read<String>('idempotency_key'),
      completedAt: DateTime.tryParse(row.read<String>('completed_at')) ??
          DateTime.now().toUtc(),
    );
  }

  Future<int> _nextSyncSequence() async {
    final dbIdentity = identityHashCode(db);
    final cached = StockTransactionService._nextSyncSequenceByDb[dbIdentity];
    if (cached != null) {
      StockTransactionService._nextSyncSequenceByDb[dbIdentity] = cached + 1;
      return cached;
    }
    final rows = await db
        .customSelect(
            'SELECT COALESCE(MAX(sequence), 0) AS value FROM sync_events')
        .get();
    final next = rows.isEmpty ? 1 : rows.first.read<int>('value') + 1;
    StockTransactionService._nextSyncSequenceByDb[dbIdentity] = next + 1;
    return next;
  }

  StockMovement _normalizeMovement(
    StockMovement movement, {
    required String storeId,
    required String branchId,
    required String deviceId,
    required String movementGroupId,
    required String idempotencyKeyPrefix,
    required String fallbackSyncStatus,
  }) {
    final resolvedIdempotencyKey = movement.idempotencyKey.trim().isEmpty
        ? '$idempotencyKeyPrefix:${movement.id}'
        : movement.idempotencyKey.trim();
    return movement.copyWith(
      storeId: storeId,
      branchId: branchId,
      deviceId: movement.deviceId.trim().isEmpty ? deviceId : movement.deviceId,
      lastModifiedByDeviceId: movement.lastModifiedByDeviceId.trim().isEmpty
          ? deviceId
          : movement.lastModifiedByDeviceId,
      movementGroupId: movement.movementGroupId.trim().isEmpty
          ? movementGroupId
          : movement.movementGroupId,
      idempotencyKey: resolvedIdempotencyKey,
      syncStatus: movement.syncStatus.trim().isEmpty
          ? fallbackSyncStatus
          : movement.syncStatus,
    );
  }

  DateTime? _parseDate(String value) {
    if (value.trim().isEmpty) return null;
    return DateTime.tryParse(value);
  }

  bool _allowNegativeStock(String storeId, String warehouseId) {
    final resolver = allowNegativeStockResolver;
    if (resolver == null) return false;
    return resolver(storeId, warehouseId);
  }

  String _payloadJson(Map<String, dynamic> payload) {
    return jsonEncode(payload);
  }
}
