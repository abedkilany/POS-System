part of 'batch_inventory_service.dart';

extension BatchInventoryServiceSplitPart3 on BatchInventoryService {

  Future<void> reverseUnifiedMovementEffectInTransaction({
    required Product product,
    required String warehouseId,
    required String batchId,
    required double movementQuantity,
    required double unitCost,
    required DateTime reversedAt,
    required String storeId,
    required String deviceId,
    String branchId = 'main',
  }) async {
    if (!product.trackStock || movementQuantity.abs() <= 0.000001) return;
    if (movementQuantity < 0) {
      await restoreUnifiedInTransaction(
        product: product,
        warehouseId: warehouseId,
        allocations: <BatchAllocation>[
          BatchAllocation(
            batchId: batchId,
            quantity: movementQuantity.abs(),
            unitCost: unitCost,
          ),
        ],
        restoredAt: reversedAt,
        storeId: storeId,
        deviceId: deviceId,
        branchId: branchId,
      );
      return;
    }
    await removeUnifiedInboundInTransaction(
      product: product,
      warehouseId: warehouseId,
      batchId: batchId,
      quantity: movementQuantity,
      removedAt: reversedAt,
      storeId: storeId,
      deviceId: deviceId,
    );
  }

  Future<void> _ensureDeficitBatchAndRecordInTransaction({
    required String productId,
    required String productName,
    required String warehouseId,
    required String deficitBatchId,
    required double quantity,
    required double provisionalUnitCost,
    required DateTime createdAt,
    required String storeId,
    required String branchId,
    required String deviceId,
    required bool expiryTracked,
    required String syncStatus,
  }) async {
    if (quantity <= 0) return;
    final normalizedBatchId = deficitBatchId.trim();
    if (normalizedBatchId.isEmpty) {
      throw const LocalizedDomainException(
        'error_batch_identity_required',
        fallback: 'A deficit batch identity is required.',
      );
    }
    final nowText = createdAt.toUtc().toIso8601String();
    final expirationText = expiryTracked ? '9999-12-31' : '';
    await db.customStatement(
      '''
      INSERT OR IGNORE INTO inventory_batches
        (id, product_id, product_name, supplier_batch_number,
         manufacturing_date, expiration_date, status, source_type, source_id,
         source_line_id, unit_cost, initial_quantity, cost_currency,
         exchange_rate, received_at, store_id, branch_id, created_at,
         updated_at, device_id, last_modified_by_device_id, sync_status, version)
      VALUES (?, ?, ?, 'NEGATIVE-STOCK-DEFICIT', '', ?, 'active',
              'inventory_deficit', ?, ?, ?, ?, 'USD', 1, ?, ?, ?, ?, ?, ?, ?, ?, 1)
      ''',
      <Object?>[
        normalizedBatchId,
        productId,
        productName,
        expirationText,
        normalizedBatchId,
        normalizedBatchId,
        provisionalUnitCost < 0 ? 0.0 : provisionalUnitCost,
        quantity,
        nowText,
        storeId,
        branchId.trim().isEmpty ? 'main' : branchId.trim(),
        nowText,
        nowText,
        deviceId,
        deviceId,
        syncStatus,
      ],
    );
    final deficitId = 'deficit_record:$normalizedBatchId';
    await db.customStatement(
      '''
      INSERT OR IGNORE INTO inventory_stock_deficits
        (id, deficit_batch_id, product_id, warehouse_id, store_id, branch_id,
         quantity_original, quantity_open, provisional_unit_cost, status,
         created_at, updated_at, device_id, last_modified_by_device_id,
         sync_status, version)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'open', ?, ?, ?, ?, ?, 1)
      ''',
      <Object?>[
        deficitId,
        normalizedBatchId,
        productId,
        warehouseId,
        storeId,
        branchId.trim().isEmpty ? 'main' : branchId.trim(),
        quantity,
        quantity,
        provisionalUnitCost < 0 ? 0.0 : provisionalUnitCost,
        nowText,
        nowText,
        deviceId,
        deviceId,
        syncStatus,
      ],
    );
  }

  Future<double> _settleOpenDeficitsWithIncomingBatchInTransaction({
    required String productId,
    required String productName,
    required String warehouseId,
    required String incomingBatchId,
    required double incomingQuantity,
    required double actualUnitCost,
    required DateTime settledAt,
    required String storeId,
    required String branchId,
    required String deviceId,
    required bool postAccountingAdjustments,
  }) async {
    if (incomingQuantity <= 0) return 0.0;
    final deficits = await db.customSelect(
      '''
      SELECT id, deficit_batch_id, quantity_open, provisional_unit_cost
      FROM inventory_stock_deficits
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
        AND status = 'open' AND quantity_open > 0.000001
      ORDER BY created_at ASC, id ASC
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(productId),
      ],
    ).get();
    var remainingIncoming = incomingQuantity;
    var totalSettled = 0.0;
    var settlementIndex = 0;
    final nowText = settledAt.toUtc().toIso8601String();
    for (final deficit in deficits) {
      if (remainingIncoming <= 0.000001) break;
      final open = (deficit.data['quantity_open'] as num? ?? 0).toDouble();
      if (open <= 0.000001) continue;
      final settled = open < remainingIncoming ? open : remainingIncoming;
      if (settled <= 0) continue;
      final deficitId = deficit.data['id']?.toString() ?? '';
      final deficitBatchId = deficit.data['deficit_batch_id']?.toString() ?? '';
      final provisionalUnitCost =
          (deficit.data['provisional_unit_cost'] as num? ?? 0).toDouble();
      final nextOpen = open - settled;
      await db.customStatement(
        '''
        UPDATE inventory_stock_deficits
        SET quantity_open = ?,
            status = CASE WHEN ? <= 0.000001 THEN 'resolved' ELSE 'open' END,
            updated_at = ?, version = version + 1,
            last_modified_by_device_id = ?, sync_status = ?
        WHERE id = ?
        ''',
        <Object?>[
          nextOpen < 0.000001 ? 0.0 : nextOpen,
          nextOpen,
          nowText,
          deviceId,
          postAccountingAdjustments ? 'pending' : 'synced',
          deficitId,
        ],
      );
      if (nextOpen <= 0.000001) {
        await db.customStatement(
          '''
          UPDATE inventory_batches
          SET status = 'depleted', updated_at = ?, version = version + 1,
              last_modified_by_device_id = ?, sync_status = ?
          WHERE id = ? AND store_id = ?
            AND NOT EXISTS (
              SELECT 1 FROM inventory_batch_balances bb
              WHERE bb.batch_id = inventory_batches.id
                AND bb.store_id = inventory_batches.store_id
                AND bb.quantity > 0.000001
            )
          ''',
          <Object?>[
            nowText,
            deviceId,
            postAccountingAdjustments ? 'pending' : 'synced',
            deficitBatchId,
            storeId,
          ],
        );
      }
      final settlementId =
          'deficit_settlement:$deficitId:$incomingBatchId:${settledAt.microsecondsSinceEpoch}:$settlementIndex';
      final costAdjustment = settled * (actualUnitCost - provisionalUnitCost);
      await db.customStatement(
        '''
        INSERT OR IGNORE INTO inventory_deficit_settlements
          (id, deficit_id, incoming_batch_id, quantity, reversed_quantity,
           provisional_unit_cost, actual_unit_cost, cost_adjustment,
           settled_at, updated_at, device_id, status)
        VALUES (?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, 'active')
        ''',
        <Object?>[
          settlementId,
          deficitId,
          incomingBatchId,
          settled,
          provisionalUnitCost,
          actualUnitCost < 0 ? 0.0 : actualUnitCost,
          costAdjustment,
          nowText,
          nowText,
          deviceId,
        ],
      );

      if (postAccountingAdjustments && costAdjustment.abs() > 0.000001) {
        final source = await db.customSelect(
          '''
          SELECT movement_type, reference_id, reference_no, branch_id
          FROM stock_movements
          WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
            AND batch_id = ? AND quantity < 0 AND deleted_at = ''
          ORDER BY movement_date ASC, id ASC
          LIMIT 1
          ''',
          variables: <Variable<Object>>[
            Variable<String>(storeId),
            Variable<String>(warehouseId),
            Variable<String>(productId),
            Variable<String>(deficitBatchId),
          ],
        ).getSingleOrNull();
        final sourceMovementType =
            source?.data['movement_type']?.toString() ?? '';
        final sourceBranchValue =
            source?.data['branch_id']?.toString().trim() ?? '';
        final sourceBranchId =
            sourceBranchValue.isEmpty ? branchId : sourceBranchValue;
        if (sourceMovementType == 'sale') {
          await AccountingService
              .recordInventoryDeficitCostReconciliationInTransaction(
            database: db,
            settlementId: settlementId,
            productId: productId,
            productName: productName,
            quantity: settled,
            provisionalUnitCost: provisionalUnitCost,
            actualUnitCost: actualUnitCost,
            entryDate: settledAt,
            sourceReferenceId: source?.data['reference_id']?.toString() ?? '',
            sourceReferenceNo: source?.data['reference_no']?.toString() ?? '',
            createdBy: deviceId,
            storeId: storeId,
            branchId: sourceBranchId,
          );
        } else if (source != null) {
          await AccountingService.recordInventoryDeficitCostVarianceInTransaction(
            database: db,
            settlementId: settlementId,
            productId: productId,
            productName: productName,
            quantity: settled,
            provisionalUnitCost: provisionalUnitCost,
            actualUnitCost: actualUnitCost,
            entryDate: settledAt,
            sourceReferenceId: source.data['reference_id']?.toString() ?? '',
            sourceReferenceNo: source.data['reference_no']?.toString() ?? '',
            sourceMovementType: sourceMovementType,
            createdBy: deviceId,
            storeId: storeId,
            branchId: sourceBranchId,
          );
        }
      }
      remainingIncoming -= settled;
      totalSettled += settled;
      settlementIndex += 1;
    }
    return totalSettled;
  }

  Future<void> _restoreDeficitAllocationInTransaction({
    required String deficitBatchId,
    required double quantity,
    required DateTime restoredAt,
    required String storeId,
    required String warehouseId,
    required String productId,
    required String productName,
    required String branchId,
    required String deviceId,
    required bool postAccountingAdjustments,
  }) async {
    if (quantity <= 0) return;
    final deficit = await db.customSelect(
      '''
      SELECT id, quantity_open, provisional_unit_cost
      FROM inventory_stock_deficits
      WHERE deficit_batch_id = ? AND store_id = ? AND warehouse_id = ?
        AND product_id = ?
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(deficitBatchId),
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(productId),
      ],
    ).getSingleOrNull();
    if (deficit == null) {
      throw const LocalizedDomainException(
        'error_batch_restore_invalid',
        fallback: 'Negative-stock deficit record was not found.',
      );
    }
    final deficitId = deficit.data['id']?.toString() ?? '';
    final provisionalUnitCost =
        (deficit.data['provisional_unit_cost'] as num? ?? 0).toDouble();
    var remaining = quantity;
    var open = (deficit.data['quantity_open'] as num? ?? 0).toDouble();
    final nowText = restoredAt.toUtc().toIso8601String();
    if (open > 0.000001) {
      final directRestore = open < remaining ? open : remaining;
      open -= directRestore;
      remaining -= directRestore;
      await db.customStatement(
        '''
        UPDATE inventory_stock_deficits
        SET quantity_open = ?, updated_at = ?, version = version + 1,
            last_modified_by_device_id = ?, sync_status = ?
        WHERE id = ?
        ''',
        <Object?>[
          open < 0.000001 ? 0.0 : open,
          nowText,
          deviceId,
          postAccountingAdjustments ? 'pending' : 'synced',
          deficitId,
        ],
      );
    }

    if (remaining > 0.000001) {
      final settlements = await db.customSelect(
        '''
        SELECT id, incoming_batch_id, quantity, reversed_quantity,
               actual_unit_cost
        FROM inventory_deficit_settlements
        WHERE deficit_id = ? AND reversed_quantity < quantity - 0.000001
        ORDER BY settled_at DESC, id DESC
        ''',
        variables: <Variable<Object>>[
          Variable<String>(deficitId),
        ],
      ).get();
      var restoreIndex = 0;
      for (final settlement in settlements) {
        if (remaining <= 0.000001) break;
        final settledQuantity =
            (settlement.data['quantity'] as num? ?? 0).toDouble();
        final reversedQuantity =
            (settlement.data['reversed_quantity'] as num? ?? 0).toDouble();
        final availableToRestore = settledQuantity - reversedQuantity;
        if (availableToRestore <= 0.000001) continue;
        final restored =
            availableToRestore < remaining ? availableToRestore : remaining;
        final incomingBatchId =
            settlement.data['incoming_batch_id']?.toString() ?? '';
        final updated = await db.customUpdate(
          '''
          UPDATE inventory_batch_balances
          SET quantity = quantity + ?, version = version + 1,
              updated_at = ?, device_id = ?, last_modified_by_device_id = ?,
              sync_status = ?
          WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
            AND batch_id = ?
          ''',
          variables: <Variable<Object>>[
            Variable<double>(restored),
            Variable<String>(nowText),
            Variable<String>(deviceId),
            Variable<String>(deviceId),
            Variable<String>(
                postAccountingAdjustments ? 'pending' : 'synced'),
            Variable<String>(storeId),
            Variable<String>(warehouseId),
            Variable<String>(productId),
            Variable<String>(incomingBatchId),
          ],
          updates: const <TableInfo<Table, Object?>>{},
        );
        if (updated != 1) {
          throw LocalizedDomainException(
            'error_batch_no_longer_exists',
            values: {'batch': incomingBatchId},
            fallback: 'Batch $incomingBatchId no longer exists.',
          );
        }
        await db.customStatement(
          '''
          UPDATE inventory_batches
          SET status = 'active', updated_at = ?, version = version + 1,
              last_modified_by_device_id = ?, sync_status = ?
          WHERE id = ? AND store_id = ?
          ''',
          <Object?>[
            nowText,
            deviceId,
            postAccountingAdjustments ? 'pending' : 'synced',
            incomingBatchId,
            storeId,
          ],
        );
        final nextReversed = reversedQuantity + restored;
        final settlementId = settlement.data['id']?.toString() ?? '';
        await db.customStatement(
          '''
          UPDATE inventory_deficit_settlements
          SET reversed_quantity = ?,
              status = CASE
                WHEN ? >= quantity - 0.000001 THEN 'reversed'
                ELSE 'partial_reversal'
              END,
              updated_at = ?
          WHERE id = ?
          ''',
          <Object?>[
            nextReversed,
            nextReversed,
            nowText,
            settlementId,
          ],
        );
        if (postAccountingAdjustments) {
          final source = await db.customSelect(
            '''
            SELECT movement_type, reference_id, reference_no, branch_id
            FROM stock_movements
            WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
              AND batch_id = ? AND quantity < 0 AND deleted_at = ''
            ORDER BY movement_date ASC, id ASC
            LIMIT 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>(storeId),
              Variable<String>(warehouseId),
              Variable<String>(productId),
              Variable<String>(deficitBatchId),
            ],
          ).getSingleOrNull();
          if (source != null) {
            final actualUnitCost =
                (settlement.data['actual_unit_cost'] as num? ?? 0).toDouble();
            final sourceMovementType =
                source.data['movement_type']?.toString() ?? '';
            final sourceBranchId =
                source.data['branch_id']?.toString().trim().isNotEmpty == true
                    ? source.data['branch_id'].toString()
                    : branchId;
            final reversalSettlementId =
                '$settlementId:restore:${restoredAt.microsecondsSinceEpoch}:$restoreIndex';
            if (sourceMovementType == 'sale') {
              await AccountingService
                  .recordInventoryDeficitCostReconciliationInTransaction(
                database: db,
                settlementId: reversalSettlementId,
                productId: productId,
                productName: productName,
                quantity: restored,
                provisionalUnitCost: actualUnitCost,
                actualUnitCost: provisionalUnitCost,
                entryDate: restoredAt,
                sourceReferenceId:
                    source.data['reference_id']?.toString() ?? '',
                sourceReferenceNo:
                    source.data['reference_no']?.toString() ?? '',
                createdBy: deviceId,
                storeId: storeId,
                branchId: sourceBranchId,
              );
            } else {
              await AccountingService
                  .recordInventoryDeficitCostVarianceInTransaction(
                database: db,
                settlementId: reversalSettlementId,
                productId: productId,
                productName: productName,
                quantity: restored,
                provisionalUnitCost: actualUnitCost,
                actualUnitCost: provisionalUnitCost,
                entryDate: restoredAt,
                sourceReferenceId:
                    source.data['reference_id']?.toString() ?? '',
                sourceReferenceNo:
                    source.data['reference_no']?.toString() ?? '',
                sourceMovementType: sourceMovementType,
                createdBy: deviceId,
                storeId: storeId,
                branchId: sourceBranchId,
              );
            }
          }
        }
        remaining -= restored;
        restoreIndex += 1;
      }
    }

    if (remaining > 0.000001) {
      throw const LocalizedDomainException(
        'error_batch_restore_invalid',
        fallback: 'Negative-stock deficit cannot be restored completely.',
      );
    }
    final activeSettlementRow = await db.customSelect(
      '''
      SELECT COALESCE(SUM(quantity - reversed_quantity), 0) AS active_qty
      FROM inventory_deficit_settlements
      WHERE deficit_id = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(deficitId),
      ],
    ).getSingle();
    final activeSettled =
        (activeSettlementRow.data['active_qty'] as num? ?? 0).toDouble();
    final refreshedDeficit = await db.customSelect(
      'SELECT quantity_open FROM inventory_stock_deficits WHERE id = ?',
      variables: <Variable<Object>>[Variable<String>(deficitId)],
    ).getSingle();
    final refreshedOpen =
        (refreshedDeficit.data['quantity_open'] as num? ?? 0).toDouble();
    if (refreshedOpen <= 0.000001 && activeSettled <= 0.000001) {
      await db.customStatement(
        '''
        UPDATE inventory_stock_deficits
        SET status = 'reversed', updated_at = ?, version = version + 1,
            last_modified_by_device_id = ?, sync_status = ?
        WHERE id = ?
        ''',
        <Object?>[
          nowText,
          deviceId,
          postAccountingAdjustments ? 'pending' : 'synced',
          deficitId,
        ],
      );
    }
  }
}
