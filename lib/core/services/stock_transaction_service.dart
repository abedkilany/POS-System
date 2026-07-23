import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/stock_movement.dart';
import '../../models/warehouse_inventory.dart';
import '../../models/sync_change.dart';
import '../repositories/warehouse_inventory_repository.dart';
import '../storage/sqlite/ventio_drift_database.dart';

class StockTransactionReceipt {
  const StockTransactionReceipt({
    required this.operationId,
    required this.operationType,
    required this.documentType,
    required this.documentId,
    required this.movementGroupId,
    required this.movementIds,
    required this.idempotencyKey,
    required this.completedAt,
  });

  final String operationId;
  final String operationType;
  final String documentType;
  final String documentId;
  final String movementGroupId;
  final List<String> movementIds;
  final String idempotencyKey;
  final DateTime completedAt;
}

class StockIntegrityIssue {
  const StockIntegrityIssue({
    required this.storeId,
    required this.warehouseId,
    required this.productId,
    required this.productName,
    required this.warehouseBalance,
    required this.ledgerBalance,
    required this.legacyProductStock,
    required this.difference,
    required this.classification,
  });

  final String storeId;
  final String warehouseId;
  final String productId;
  final String productName;
  final double warehouseBalance;
  final double ledgerBalance;
  final double legacyProductStock;
  final double difference;
  final String classification;
}

class StockIntegrityReport {
  const StockIntegrityReport({
    required this.ok,
    required this.message,
    required this.issues,
  });

  final bool ok;
  final String message;
  final List<StockIntegrityIssue> issues;
}

class _StockOperationInProgressException implements Exception {
  _StockOperationInProgressException(this.message);
  final String message;

  @override
  String toString() => message;
}

class _OperationAcquisition {
  const _OperationAcquisition._({
    required this.proceed,
    required this.completedReceipt,
    required this.inProgressMessage,
    required this.currentStatus,
    required this.attemptCount,
  });

  const _OperationAcquisition.proceed({
    required String currentStatus,
    required int attemptCount,
  }) : this._(
          proceed: true,
          completedReceipt: null,
          inProgressMessage: '',
          currentStatus: currentStatus,
          attemptCount: attemptCount,
        );

  const _OperationAcquisition.completed(this.completedReceipt)
      : proceed = false,
        inProgressMessage = '',
        currentStatus = 'completed',
        attemptCount = 0;

  const _OperationAcquisition.inProgress(this.inProgressMessage)
      : proceed = false,
        completedReceipt = null,
        currentStatus = 'pending',
        attemptCount = 0;

  final bool proceed;
  final StockTransactionReceipt? completedReceipt;
  final String inProgressMessage;
  final String currentStatus;
  final int attemptCount;
}

class _MovementInsertResult {
  const _MovementInsertResult({
    required this.movementId,
    required this.inserted,
  });

  final String movementId;
  final bool inserted;
}

typedef NegativeStockPolicyResolver = bool Function(
  String storeId,
  String warehouseId,
);

class StockTransactionService {
  StockTransactionService(
    this.db, {
    this.deviceId = '',
    this.defaultStoreId = '',
    this.defaultBranchId = 'main',
    this.defaultSyncTarget = 'cloud',
    this.allowNegativeStockResolver,
  });

  final VentioDriftDatabase db;
  final String deviceId;
  final String defaultStoreId;
  final String defaultBranchId;
  final String defaultSyncTarget;
  final NegativeStockPolicyResolver? allowNegativeStockResolver;
  static final Map<int, int> _nextSyncSequenceByDb = <int, int>{};

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
    String syncTarget = 'cloud',
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
      final receipt = await db.transaction(
        () => recordMovementsInTransaction(
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
        ),
      );
      await _markOperationCompleted(
        storeId: resolvedStoreId,
        idempotencyKey: idempotencyKey,
        deviceId: resolvedDeviceId,
        completedAt: now,
      );
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
    String syncTarget = 'cloud',
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
    String syncTarget = 'cloud',
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
    String syncTarget = 'cloud',
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
    final backfillCompleted = await _warehouseInventoryBackfillCompleted();
    final products = await db.customSelect('''
      SELECT id, name, stock
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
    final coveredProducts = <String>{};

    final issues = <StockIntegrityIssue>[];
    final seenKeys = <String>{};
    for (final row in inventoryRows) {
      final storeValue = row.read<String>('store_id');
      final warehouseId = row.read<String>('warehouse_id');
      final productId = row.read<String>('product_id');
      final key = _identityKey(storeValue, warehouseId, productId);
      seenKeys.add(key);
      coveredProducts.add(productId);
      final warehouseBalance = (row.data['quantity'] as num? ?? 0).toDouble();
      final ledgerBalance = movementByIdentity[key] ?? 0;
      final legacyStock =
          (productById[productId]?['stock'] as num? ?? 0).toDouble();
      final productName = productById[productId]?['name']?.toString() ?? '';
      final difference = warehouseBalance - ledgerBalance;
      final classification = ledgerBalance == 0 && legacyStock > 0
          ? 'legacy_unassigned'
          : warehouseBalance == 0 && ledgerBalance != 0
              ? 'missing_warehouse_balance'
              : difference.abs() > 0.000001
                  ? 'warehouse_balance_mismatch'
                  : (legacyStock - warehouseBalance).abs() > 0.000001
                      ? 'ledger_mismatch'
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
      coveredProducts.add(productId);
      final ledgerBalance = (row.data['quantity'] as num? ?? 0).toDouble();
      final legacyStock =
          (productById[productId]?['stock'] as num? ?? 0).toDouble();
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

    for (final row in products) {
      final productId = row.read<String>('id');
      final legacyStock = (row.data['stock'] as num? ?? 0).toDouble();
      if (coveredProducts.contains(productId)) continue;
      if (!backfillCompleted && legacyStock <= 0) continue;
      final classification =
          legacyStock > 0 ? 'legacy_unassigned' : 'missing_warehouse_balance';
      issues.add(
        StockIntegrityIssue(
          storeId: resolvedStoreId,
          warehouseId: '',
          productId: productId,
          productName: row.data['name']?.toString() ?? '',
          warehouseBalance: 0,
          ledgerBalance: 0,
          legacyProductStock: legacyStock,
          difference: -legacyStock,
          classification: classification,
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

  Future<bool> _warehouseInventoryBackfillCompleted() async {
    final rows = await db.customSelect(
      'SELECT value FROM migration_meta WHERE key = ?',
      variables: <Variable<Object>>[
        Variable<String>('warehouse_inventory_backfill_v1'),
      ],
    ).get();
    return rows.isNotEmpty && rows.first.read<String>('value') == 'done';
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
      isSynced: false,
      storeEpoch: 1,
      sequence: sequence,
    );
    await db.customInsert(
      '''
      INSERT OR REPLACE INTO sync_events
        (id, entity_type, entity_id, operation, device_id, store_id, branch_id,
         payload_json, is_synced, created_at, synced_at, store_epoch, sequence)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, '', ?, ?)
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
        Variable<String>(change.createdAt.toIso8601String()),
        Variable<int>(change.storeEpoch),
        Variable<int>(change.sequence),
      ],
    );
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
           warehouse_id, warehouse_name, movement_group_id, document_line_id,
           source_movement_id, reversal_of_movement_id, idempotency_key, unit_cost,
           last_modified_by_device_id, reviewed_at, reviewed_by, review_note)
        VALUES (?, 'stock_movement', ?, ?, '', ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
    final cached = _nextSyncSequenceByDb[dbIdentity];
    if (cached != null) {
      _nextSyncSequenceByDb[dbIdentity] = cached + 1;
      return cached;
    }
    final rows = await db
        .customSelect(
            'SELECT COALESCE(MAX(sequence), 0) AS value FROM sync_events')
        .get();
    final next = rows.isEmpty ? 1 : rows.first.read<int>('value') + 1;
    _nextSyncSequenceByDb[dbIdentity] = next + 1;
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
