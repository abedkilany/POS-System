import 'package:drift/drift.dart';

import '../storage/sqlite/ventio_drift_database.dart';

/// Phase 9 production traceability over the authoritative Unified Batch ledger.
///
/// No shadow lineage table is required: purchase/source identity lives on
/// `inventory_batches`, warehouse travel lives on batch-addressed stock
/// movements, and manufacturing lineage is derived from the common
/// manufacturing-order reference shared by input-consumption movements and
/// output batches. Keeping traceability derived from the same authoritative
/// rows prevents a second graph from drifting away from inventory reality.
class InventoryTraceabilityService {
  const InventoryTraceabilityService(this.db);

  final VentioDriftDatabase db;

  static const double tolerance = 0.000001;

  Future<Map<String, dynamic>> traceBatch({
    required String batchId,
    required String storeId,
    int maxDepth = 8,
  }) async {
    final normalizedBatchId = batchId.trim();
    final normalizedStoreId = storeId.trim();
    if (normalizedBatchId.isEmpty) {
      throw ArgumentError('A batch id is required for traceability.');
    }
    if (normalizedStoreId.isEmpty) {
      throw ArgumentError('A store id is required for traceability.');
    }
    if (maxDepth < 0 || maxDepth > 32) {
      throw ArgumentError('Trace depth must be between 0 and 32.');
    }

    final root = await _batchRow(normalizedBatchId, normalizedStoreId);
    if (root == null) {
      throw StateError('Inventory batch $normalizedBatchId was not found.');
    }

    final batches = <String, Map<String, dynamic>>{};
    final movementById = <String, Map<String, dynamic>>{};
    final edges = <String, Map<String, dynamic>>{};
    final queue = <({String batchId, int depth})>[
      (batchId: normalizedBatchId, depth: 0),
    ];
    final visited = <String>{};
    var maxDepthReached = 0;

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (!visited.add(current.batchId)) continue;
      if (current.depth > maxDepth) continue;
      if (current.depth > maxDepthReached) maxDepthReached = current.depth;

      final batch = await _batchRow(current.batchId, normalizedStoreId);
      if (batch == null) continue;
      final balances = await _batchBalances(current.batchId, normalizedStoreId);
      final movements = await _batchMovements(current.batchId, normalizedStoreId);
      batches[current.batchId] = <String, dynamic>{
        ...batch,
        'balances': balances,
      };
      for (final movement in movements) {
        movementById[movement['id'].toString()] = movement;
      }

      final sourceType = batch['sourceType']?.toString() ?? '';
      final sourceId = batch['sourceId']?.toString() ?? '';
      if (sourceType == 'manufacturing_output' && sourceId.isNotEmpty) {
        final inputRows = await db.customSelect(
          '''
          SELECT batch_id AS batchId, product_id AS productId,
                 SUM(ABS(quantity)) AS quantity,
                 CASE WHEN SUM(ABS(quantity)) <= 0 THEN 0
                      ELSE SUM(ABS(quantity * unit_cost)) / SUM(ABS(quantity)) END AS unitCost
          FROM stock_movements
          WHERE store_id = ? AND reference_id = ?
            AND movement_type = 'manufacturing_consume'
            AND deleted_at = '' AND trim(batch_id) <> ''
          GROUP BY batch_id, product_id
          ORDER BY batch_id
          ''',
          variables: <Variable<Object>>[
            Variable<String>(normalizedStoreId),
            Variable<String>(sourceId),
          ],
        ).get();
        for (final row in inputRows) {
          final inputBatchId = row.data['batchId']?.toString() ?? '';
          if (inputBatchId.isEmpty) continue;
          final edgeKey = '$inputBatchId>${current.batchId}>$sourceId';
          edges[edgeKey] = <String, dynamic>{
            'fromBatchId': inputBatchId,
            'toBatchId': current.batchId,
            'relation': 'manufacturing_input_to_output',
            'referenceType': 'manufacturing_order',
            'referenceId': sourceId,
            'inputProductId': row.data['productId']?.toString() ?? '',
            'inputQuantity': (row.data['quantity'] as num? ?? 0).toDouble(),
            'inputUnitCost': (row.data['unitCost'] as num? ?? 0).toDouble(),
          };
          if (current.depth < maxDepth) {
            queue.add((batchId: inputBatchId, depth: current.depth + 1));
          }
        }
      }

      final downstreamOrders = await db.customSelect(
        '''
        SELECT DISTINCT reference_id AS referenceId
        FROM stock_movements
        WHERE store_id = ? AND batch_id = ?
          AND movement_type = 'manufacturing_consume'
          AND deleted_at = '' AND trim(reference_id) <> ''
        ORDER BY reference_id
        ''',
        variables: <Variable<Object>>[
          Variable<String>(normalizedStoreId),
          Variable<String>(current.batchId),
        ],
      ).get();
      for (final orderRow in downstreamOrders) {
        final orderId = orderRow.data['referenceId']?.toString() ?? '';
        if (orderId.isEmpty) continue;
        final outputRows = await db.customSelect(
          '''
          SELECT id, product_id AS productId, initial_quantity AS quantity,
                 unit_cost AS unitCost
          FROM inventory_batches
          WHERE store_id = ? AND source_type = 'manufacturing_output'
            AND source_id = ?
          ORDER BY id
          ''',
          variables: <Variable<Object>>[
            Variable<String>(normalizedStoreId),
            Variable<String>(orderId),
          ],
        ).get();
        for (final outputRow in outputRows) {
          final outputBatchId = outputRow.data['id']?.toString() ?? '';
          if (outputBatchId.isEmpty) continue;
          final edgeKey = '${current.batchId}>$outputBatchId>$orderId';
          edges[edgeKey] = <String, dynamic>{
            'fromBatchId': current.batchId,
            'toBatchId': outputBatchId,
            'relation': 'manufacturing_input_to_output',
            'referenceType': 'manufacturing_order',
            'referenceId': orderId,
            'outputProductId': outputRow.data['productId']?.toString() ?? '',
            'outputQuantity':
                (outputRow.data['quantity'] as num? ?? 0).toDouble(),
            'outputUnitCost':
                (outputRow.data['unitCost'] as num? ?? 0).toDouble(),
          };
          if (current.depth < maxDepth) {
            queue.add((batchId: outputBatchId, depth: current.depth + 1));
          }
        }
      }
    }

    final references = <String, Set<String>>{
      'purchase': <String>{},
      'sale': <String>{},
      'warehouseTransfer': <String>{},
      'manufacturing': <String>{},
      'inventoryAdjustment': <String>{},
    };
    for (final batch in batches.values) {
      final sourceType = batch['sourceType']?.toString() ?? '';
      final sourceId = batch['sourceId']?.toString() ?? '';
      if (sourceId.isNotEmpty) {
        if (sourceType == 'purchase') references['purchase']!.add(sourceId);
        if (sourceType == 'manufacturing_output') {
          references['manufacturing']!.add(sourceId);
        }
      }
    }
    for (final movement in movementById.values) {
      final type = movement['movementType']?.toString() ?? '';
      final referenceId = movement['referenceId']?.toString() ?? '';
      if (referenceId.isEmpty) continue;
      if (type.startsWith('sale')) references['sale']!.add(referenceId);
      if (type == 'transfer_in' || type == 'transfer_out') {
        references['warehouseTransfer']!.add(referenceId);
      }
      if (type.startsWith('manufacturing_')) {
        references['manufacturing']!.add(referenceId);
      }
      if (type == 'adjustment' || type.contains('count')) {
        references['inventoryAdjustment']!.add(referenceId);
      }
    }

    return <String, dynamic>{
      'rootBatchId': normalizedBatchId,
      'storeId': normalizedStoreId,
      'maxDepthRequested': maxDepth,
      'maxDepthReached': maxDepthReached,
      'batchCount': batches.length,
      'movementCount': movementById.length,
      'batches': batches.values.toList(growable: false),
      'movements': movementById.values.toList(growable: false),
      'manufacturingEdges': edges.values.toList(growable: false),
      'references': <String, dynamic>{
        for (final entry in references.entries)
          entry.key: entry.value.toList(growable: false)..sort(),
      },
    };
  }

  Future<void> assertTransferTraceabilityInTransaction({
    required String movementGroupId,
    required String storeId,
  }) async {
    final rows = await db.customSelect(
      '''
      SELECT product_id AS productId, batch_id AS batchId,
             SUM(CASE WHEN movement_type = 'transfer_out' THEN quantity ELSE 0 END) AS outQty,
             SUM(CASE WHEN movement_type = 'transfer_in' THEN quantity ELSE 0 END) AS inQty,
             SUM(CASE WHEN movement_type = 'transfer_out' THEN ABS(quantity * unit_cost) ELSE 0 END) AS outValue,
             SUM(CASE WHEN movement_type = 'transfer_in' THEN ABS(quantity * unit_cost) ELSE 0 END) AS inValue,
             COUNT(DISTINCT CASE WHEN movement_type = 'transfer_out' THEN warehouse_id END) AS sourceWarehouses,
             COUNT(DISTINCT CASE WHEN movement_type = 'transfer_in' THEN warehouse_id END) AS destinationWarehouses,
             COUNT(DISTINCT warehouse_id) AS warehouseCount
      FROM stock_movements
      WHERE store_id = ? AND movement_group_id = ? AND deleted_at = ''
        AND movement_type IN ('transfer_out', 'transfer_in')
      GROUP BY product_id, batch_id
      ORDER BY product_id, batch_id
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(movementGroupId),
      ],
    ).get();
    if (rows.isEmpty) {
      throw StateError('Warehouse transfer has no persisted batch movements.');
    }
    for (final row in rows) {
      final batchId = row.data['batchId']?.toString() ?? '';
      final outQty = (row.data['outQty'] as num? ?? 0).toDouble();
      final inQty = (row.data['inQty'] as num? ?? 0).toDouble();
      final outValue = (row.data['outValue'] as num? ?? 0).toDouble();
      final inValue = (row.data['inValue'] as num? ?? 0).toDouble();
      final sourceWarehouses = (row.data['sourceWarehouses'] as num? ?? 0).toInt();
      final destinationWarehouses =
          (row.data['destinationWarehouses'] as num? ?? 0).toInt();
      final warehouseCount = (row.data['warehouseCount'] as num? ?? 0).toInt();
      if (batchId.isEmpty ||
          (outQty + inQty).abs() > tolerance ||
          (outValue - inValue).abs() > tolerance ||
          sourceWarehouses != 1 ||
          destinationWarehouses != 1 ||
          warehouseCount != 2) {
        throw StateError(
          'Warehouse transfer traceability mismatch for batch $batchId.',
        );
      }
    }
  }

  Future<void> assertManufacturingTraceabilityInTransaction({
    required String orderId,
    required String storeId,
    String operationReferenceId = '',
    required double expectedOutputQuantity,
    required double expectedMaterialCost,
    required double expectedWasteCost,
    required double expectedEligibleCost,
  }) async {
    final operationId = operationReferenceId.trim().isEmpty
        ? orderId
        : operationReferenceId.trim();
    final movementRow = await db.customSelect(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN movement_type = 'manufacturing_consume' THEN ABS(quantity) ELSE 0 END), 0) AS consumedQty,
        COALESCE(SUM(CASE WHEN movement_type = 'manufacturing_consume' THEN ABS(quantity * unit_cost) ELSE 0 END), 0) AS materialCost,
        COALESCE(SUM(CASE WHEN movement_type = 'manufacturing_produce' THEN quantity ELSE 0 END), 0) AS outputQty,
        COALESCE(SUM(CASE WHEN movement_type = 'manufacturing_produce' THEN quantity * unit_cost ELSE 0 END), 0) AS outputValue,
        SUM(CASE WHEN movement_type = 'manufacturing_consume' AND trim(batch_id) = '' THEN 1 ELSE 0 END) AS unbatchedInputs,
        SUM(CASE WHEN movement_type = 'manufacturing_produce' AND trim(batch_id) = '' THEN 1 ELSE 0 END) AS unbatchedOutputs
      FROM stock_movements
      WHERE store_id = ? AND movement_group_id = ? AND deleted_at = ''
        AND movement_type IN ('manufacturing_consume', 'manufacturing_produce')
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(operationId),
      ],
    ).getSingle();
    final materialCost =
        (movementRow.data['materialCost'] as num? ?? 0).toDouble();
    final outputQty = (movementRow.data['outputQty'] as num? ?? 0).toDouble();
    final outputValue =
        (movementRow.data['outputValue'] as num? ?? 0).toDouble();
    final unbatchedInputs =
        (movementRow.data['unbatchedInputs'] as num? ?? 0).toInt();
    final unbatchedOutputs =
        (movementRow.data['unbatchedOutputs'] as num? ?? 0).toInt();
    if ((materialCost - expectedMaterialCost).abs() > tolerance ||
        (outputQty - expectedOutputQuantity).abs() > tolerance ||
        (outputValue - expectedEligibleCost).abs() > tolerance ||
        unbatchedInputs != 0 ||
        unbatchedOutputs != 0 ||
        (expectedMaterialCost - expectedWasteCost - expectedEligibleCost).abs() >
            tolerance) {
      throw StateError(
        'Manufacturing batch traceability/cost conservation failed for $orderId.',
      );
    }

    final invalidBatchRefs = await db.customSelect(
      '''
      SELECT COUNT(*) AS rowCount
      FROM stock_movements sm
      LEFT JOIN inventory_batches b
        ON b.id = sm.batch_id AND b.store_id = sm.store_id
      WHERE sm.store_id = ? AND sm.movement_group_id = ? AND sm.deleted_at = ''
        AND sm.movement_type IN ('manufacturing_consume', 'manufacturing_produce')
        AND (b.id IS NULL OR b.product_id <> sm.product_id)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(operationId),
      ],
    ).getSingle();
    if ((invalidBatchRefs.data['rowCount'] as num? ?? 0).toInt() != 0) {
      throw StateError(
        'Manufacturing movement references an invalid batch for $orderId.',
      );
    }

    final outputBatchRow = await db.customSelect(
      '''
      SELECT COALESCE(SUM(initial_quantity), 0) AS outputQty,
             COALESCE(SUM(initial_quantity * unit_cost), 0) AS outputValue,
             COUNT(*) AS batchCount
      FROM inventory_batches
      WHERE store_id = ? AND source_type = 'manufacturing_output'
        AND source_id = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(operationId),
      ],
    ).getSingle();
    final outputBatchQty =
        (outputBatchRow.data['outputQty'] as num? ?? 0).toDouble();
    final outputBatchValue =
        (outputBatchRow.data['outputValue'] as num? ?? 0).toDouble();
    final batchCount = (outputBatchRow.data['batchCount'] as num? ?? 0).toInt();
    if (batchCount <= 0 ||
        (outputBatchQty - expectedOutputQuantity).abs() > tolerance ||
        (outputBatchValue - expectedEligibleCost).abs() > tolerance) {
      throw StateError(
        'Manufacturing output batches do not reconcile for $orderId.',
      );
    }
  }

  Future<Map<String, dynamic>> verifyIntegrity({
    required String storeId,
  }) async {
    final normalizedStoreId = storeId.trim();
    if (normalizedStoreId.isEmpty) {
      throw ArgumentError('A store id is required for inventory integrity.');
    }
    final issues = <Map<String, dynamic>>[];

    void addIssue(String code, String message, Map<String, Object?> row) {
      issues.add(<String, dynamic>{
        'code': code,
        'message': message,
        ...row,
      });
    }

    final aggregateMismatches = await db.customSelect(
      '''
      WITH keys AS (
        SELECT store_id, warehouse_id, product_id
        FROM warehouse_inventory WHERE store_id = ?
        UNION
        SELECT store_id, warehouse_id, product_id
        FROM inventory_batch_balances WHERE store_id = ?
        UNION
        SELECT store_id, warehouse_id, product_id
        FROM inventory_stock_deficits
        WHERE store_id = ? AND status = 'open' AND quantity_open > 0.000001
      ), warehouse_totals AS (
        SELECT store_id, warehouse_id, product_id, SUM(quantity) AS quantity
        FROM warehouse_inventory WHERE store_id = ?
        GROUP BY store_id, warehouse_id, product_id
      ), batch_totals AS (
        SELECT store_id, warehouse_id, product_id, SUM(quantity) AS quantity
        FROM inventory_batch_balances WHERE store_id = ?
        GROUP BY store_id, warehouse_id, product_id
      ), deficit_totals AS (
        SELECT store_id, warehouse_id, product_id, SUM(quantity_open) AS quantity
        FROM inventory_stock_deficits
        WHERE store_id = ? AND status = 'open' AND quantity_open > 0.000001
        GROUP BY store_id, warehouse_id, product_id
      )
      SELECT k.warehouse_id AS warehouseId, k.product_id AS productId,
             COALESCE(w.quantity, 0) AS warehouseQty,
             COALESCE(b.quantity, 0) - COALESCE(d.quantity, 0) AS batchQty
      FROM keys k
      LEFT JOIN warehouse_totals w ON w.store_id = k.store_id
        AND w.warehouse_id = k.warehouse_id AND w.product_id = k.product_id
      LEFT JOIN batch_totals b ON b.store_id = k.store_id
        AND b.warehouse_id = k.warehouse_id AND b.product_id = k.product_id
      LEFT JOIN deficit_totals d ON d.store_id = k.store_id
        AND d.warehouse_id = k.warehouse_id AND d.product_id = k.product_id
      WHERE ABS(COALESCE(w.quantity, 0)
        - (COALESCE(b.quantity, 0) - COALESCE(d.quantity, 0))) > ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(normalizedStoreId),
        Variable<String>(normalizedStoreId),
        Variable<String>(normalizedStoreId),
        Variable<String>(normalizedStoreId),
        Variable<String>(normalizedStoreId),
        Variable<String>(normalizedStoreId),
        const Variable<double>(tolerance),
      ],
    ).get();
    for (final row in aggregateMismatches) {
      addIssue(
        'warehouse_batch_quantity_mismatch',
        'warehouse_inventory does not equal physical batch balances minus open stock deficits.',
        Map<String, Object?>.from(row.data),
      );
    }

    final invalidBalances = await db.customSelect(
      '''
      SELECT bb.batch_id AS batchId, bb.product_id AS productId,
             bb.warehouse_id AS warehouseId, bb.quantity,
             bb.reserved_quantity AS reservedQuantity
      FROM inventory_batch_balances bb
      LEFT JOIN inventory_batches b ON b.id = bb.batch_id
      WHERE bb.store_id = ? AND (
        b.id IS NULL OR b.store_id <> bb.store_id OR b.product_id <> bb.product_id
        OR bb.quantity < -? OR bb.reserved_quantity < -?
        OR bb.reserved_quantity - bb.quantity > ?
      )
      ''',
      variables: <Variable<Object>>[
        Variable<String>(normalizedStoreId),
        const Variable<double>(tolerance),
        const Variable<double>(tolerance),
        const Variable<double>(tolerance),
      ],
    ).get();
    for (final row in invalidBalances) {
      addIssue(
        'invalid_batch_balance',
        'A batch balance is orphaned, mismatched, negative, or over-reserved.',
        Map<String, Object?>.from(row.data),
      );
    }

    final expiryContractRows = await db.customSelect(
      '''
      SELECT b.id AS batchId, b.product_id AS productId,
             b.expiration_date AS expirationDate,
             p.expiry_tracking_enabled AS expiryTrackingEnabled,
             SUM(bb.quantity) AS currentQuantity
      FROM inventory_batches b
      INNER JOIN products p ON p.id = b.product_id
      INNER JOIN inventory_batch_balances bb
        ON bb.batch_id = b.id AND bb.store_id = b.store_id
      WHERE b.store_id = ? AND p.track_stock = 1 AND p.deleted_at = ''
      GROUP BY b.id, b.product_id, b.expiration_date, p.expiry_tracking_enabled
      HAVING SUM(bb.quantity) > ? AND (
        (p.expiry_tracking_enabled = 1 AND trim(b.expiration_date) = '') OR
        (p.expiry_tracking_enabled = 0 AND trim(b.expiration_date) <> '')
      )
      ''',
      variables: <Variable<Object>>[
        Variable<String>(normalizedStoreId),
        const Variable<double>(tolerance),
      ],
    ).get();
    for (final row in expiryContractRows) {
      addIssue(
        'expiry_contract_violation',
        'Batch expiry data conflicts with the product tracking policy.',
        Map<String, Object?>.from(row.data),
      );
    }

    final orphanMovements = await db.customSelect(
      '''
      SELECT sm.id AS movementId, sm.batch_id AS batchId,
             sm.product_id AS productId, sm.reference_id AS referenceId
      FROM stock_movements sm
      LEFT JOIN inventory_batches b
        ON b.id = sm.batch_id AND b.store_id = sm.store_id
      WHERE sm.store_id = ? AND sm.deleted_at = '' AND trim(sm.batch_id) <> ''
        AND (b.id IS NULL OR b.product_id <> sm.product_id)
      ''',
      variables: <Variable<Object>>[Variable<String>(normalizedStoreId)],
    ).get();
    for (final row in orphanMovements) {
      addIssue(
        'movement_batch_reference_invalid',
        'A stock movement references a missing or different-product batch.',
        Map<String, Object?>.from(row.data),
      );
    }

    final unbatchedPostCutoverTransfers = await db.customSelect(
      '''
      SELECT sm.id AS movementId, sm.movement_group_id AS movementGroupId,
             sm.product_id AS productId, sm.warehouse_id AS warehouseId
      FROM stock_movements sm
      WHERE sm.store_id = ? AND sm.deleted_at = ''
        AND sm.movement_type IN ('transfer_out', 'transfer_in')
        AND trim(sm.batch_id) = ''
        AND EXISTS (
          SELECT 1 FROM unified_batch_cutovers ubc
          WHERE ubc.store_id = sm.store_id
            AND ubc.warehouse_id = sm.warehouse_id
            AND ubc.product_id = sm.product_id
            AND sm.movement_date >= ubc.cutover_at
        )
      ''',
      variables: <Variable<Object>>[Variable<String>(normalizedStoreId)],
    ).get();
    for (final row in unbatchedPostCutoverTransfers) {
      addIssue(
        'warehouse_transfer_missing_batch_identity',
        'A post-cutover warehouse transfer movement has no batch identity.',
        Map<String, Object?>.from(row.data),
      );
    }

    final transferMismatches = await db.customSelect(
      '''
      SELECT movement_group_id AS movementGroupId, product_id AS productId,
             batch_id AS batchId,
             SUM(CASE WHEN movement_type = 'transfer_out' THEN quantity ELSE 0 END) AS outQty,
             SUM(CASE WHEN movement_type = 'transfer_in' THEN quantity ELSE 0 END) AS inQty,
             SUM(CASE WHEN movement_type = 'transfer_out' THEN ABS(quantity * unit_cost) ELSE 0 END) AS outValue,
             SUM(CASE WHEN movement_type = 'transfer_in' THEN ABS(quantity * unit_cost) ELSE 0 END) AS inValue,
             COUNT(DISTINCT warehouse_id) AS warehouseCount
      FROM stock_movements
      WHERE store_id = ? AND deleted_at = ''
        AND movement_type IN ('transfer_out', 'transfer_in')
        AND trim(batch_id) <> ''
      GROUP BY movement_group_id, product_id, batch_id
      HAVING ABS(outQty + inQty) > ? OR ABS(outValue - inValue) > ?
        OR warehouseCount <> 2
      ''',
      variables: <Variable<Object>>[
        Variable<String>(normalizedStoreId),
        const Variable<double>(tolerance),
        const Variable<double>(tolerance),
      ],
    ).get();
    for (final row in transferMismatches) {
      addIssue(
        'warehouse_transfer_traceability_mismatch',
        'A warehouse transfer does not preserve batch quantity/value.',
        Map<String, Object?>.from(row.data),
      );
    }

    final manufacturingMismatches = await db.customSelect(
      '''
      SELECT mo.id AS orderId, mo.output_product_id AS outputProductId,
             mo.actual_output_quantity AS expectedOutputQty,
             mo.total_material_cost AS expectedMaterialCost,
             mo.total_waste_cost AS expectedWasteCost,
             mo.total_eligible_cost AS expectedEligibleCost,
             COALESCE((SELECT SUM(ABS(sm.quantity * sm.unit_cost))
               FROM stock_movements sm
               WHERE sm.store_id = mo.store_id AND sm.reference_id = mo.id
                 AND sm.deleted_at = '' AND sm.movement_type = 'manufacturing_consume'
                 AND NOT EXISTS (
                   SELECT 1 FROM stock_movements rev
                   WHERE rev.reversal_of_movement_id = sm.id
                     AND rev.deleted_at = ''
                 )), 0) AS actualMaterialCost,
             COALESCE((SELECT SUM(sm.quantity)
               FROM stock_movements sm
               WHERE sm.store_id = mo.store_id AND sm.reference_id = mo.id
                 AND sm.deleted_at = '' AND sm.movement_type = 'manufacturing_produce'
                 AND NOT EXISTS (
                   SELECT 1 FROM stock_movements rev
                   WHERE rev.reversal_of_movement_id = sm.id
                     AND rev.deleted_at = ''
                 )), 0) AS actualOutputQty,
             COALESCE((SELECT SUM(sm.quantity * sm.unit_cost)
               FROM stock_movements sm
               WHERE sm.store_id = mo.store_id AND sm.reference_id = mo.id
                 AND sm.deleted_at = '' AND sm.movement_type = 'manufacturing_produce'
                 AND NOT EXISTS (
                   SELECT 1 FROM stock_movements rev
                   WHERE rev.reversal_of_movement_id = sm.id
                     AND rev.deleted_at = ''
                 )), 0) AS actualOutputValue,
             COALESCE((SELECT COUNT(DISTINCT b.id)
               FROM stock_movements sm
               INNER JOIN inventory_batches b
                 ON b.id = sm.batch_id AND b.store_id = sm.store_id
               WHERE sm.store_id = mo.store_id AND sm.reference_id = mo.id
                 AND sm.deleted_at = ''
                 AND sm.movement_type = 'manufacturing_produce'
                 AND trim(sm.batch_id) <> ''
                 AND NOT EXISTS (
                   SELECT 1 FROM stock_movements rev
                   WHERE rev.reversal_of_movement_id = sm.id
                     AND rev.deleted_at = ''
                 )), 0) AS outputBatchCount
      FROM manufacturing_orders mo
      WHERE mo.store_id = ? AND mo.deleted_at = ''
        AND lower(mo.status) = 'completed'
        AND EXISTS (
          SELECT 1 FROM stock_movements scoped
          WHERE scoped.store_id = mo.store_id AND scoped.reference_id = mo.id
            AND scoped.deleted_at = '' AND trim(scoped.batch_id) <> ''
            AND scoped.movement_type IN ('manufacturing_consume', 'manufacturing_produce')
            AND NOT EXISTS (
              SELECT 1 FROM stock_movements rev
              WHERE rev.reversal_of_movement_id = scoped.id
                AND rev.deleted_at = ''
            )
        )
      ''',
      variables: <Variable<Object>>[Variable<String>(normalizedStoreId)],
    ).get();
    for (final row in manufacturingMismatches) {
      final expectedOutputQty =
          (row.data['expectedOutputQty'] as num? ?? 0).toDouble();
      final expectedMaterialCost =
          (row.data['expectedMaterialCost'] as num? ?? 0).toDouble();
      final expectedWasteCost =
          (row.data['expectedWasteCost'] as num? ?? 0).toDouble();
      final expectedEligibleCost =
          (row.data['expectedEligibleCost'] as num? ?? 0).toDouble();
      final actualMaterialCost =
          (row.data['actualMaterialCost'] as num? ?? 0).toDouble();
      final actualOutputQty =
          (row.data['actualOutputQty'] as num? ?? 0).toDouble();
      final actualOutputValue =
          (row.data['actualOutputValue'] as num? ?? 0).toDouble();
      final outputBatchCount =
          (row.data['outputBatchCount'] as num? ?? 0).toInt();
      if ((expectedMaterialCost - actualMaterialCost).abs() > tolerance ||
          (expectedOutputQty - actualOutputQty).abs() > tolerance ||
          (expectedEligibleCost - actualOutputValue).abs() > tolerance ||
          (expectedMaterialCost - expectedWasteCost - expectedEligibleCost)
                  .abs() >
              tolerance ||
          outputBatchCount <= 0) {
        addIssue(
          'manufacturing_traceability_mismatch',
          'A completed manufacturing order does not reconcile input/output batches and costs.',
          Map<String, Object?>.from(row.data),
        );
      }
    }

    final counts = await db.customSelect(
      '''
      SELECT
        (SELECT COUNT(*) FROM warehouses WHERE store_id = ? AND deleted_at = '') AS warehouseCount,
        (SELECT COUNT(*) FROM inventory_batches WHERE store_id = ?) AS batchCount,
        (SELECT COUNT(*) FROM stock_movements WHERE store_id = ? AND deleted_at = '') AS movementCount,
        (SELECT COUNT(*) FROM manufacturing_orders WHERE store_id = ? AND deleted_at = '') AS manufacturingOrderCount
      ''',
      variables: <Variable<Object>>[
        Variable<String>(normalizedStoreId),
        Variable<String>(normalizedStoreId),
        Variable<String>(normalizedStoreId),
        Variable<String>(normalizedStoreId),
      ],
    ).getSingle();

    return <String, dynamic>{
      'storeId': normalizedStoreId,
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
      'healthy': issues.isEmpty,
      'issueCount': issues.length,
      'warehouseCount': (counts.data['warehouseCount'] as num? ?? 0).toInt(),
      'batchCount': (counts.data['batchCount'] as num? ?? 0).toInt(),
      'movementCount': (counts.data['movementCount'] as num? ?? 0).toInt(),
      'manufacturingOrderCount':
          (counts.data['manufacturingOrderCount'] as num? ?? 0).toInt(),
      'issues': issues,
    };
  }

  Future<Map<String, dynamic>?> _batchRow(
    String batchId,
    String storeId,
  ) async {
    final row = await db.customSelect(
      '''
      SELECT id, product_id AS productId, product_name AS productName,
             supplier_batch_number AS supplierBatchNumber,
             manufacturing_date AS manufacturingDate,
             expiration_date AS expirationDate, status,
             source_type AS sourceType, source_id AS sourceId,
             source_line_id AS sourceLineId, unit_cost AS unitCost,
             initial_quantity AS initialQuantity,
             cost_currency AS costCurrency, exchange_rate AS exchangeRate,
             received_at AS receivedAt, created_at AS createdAt,
             updated_at AS updatedAt
      FROM inventory_batches
      WHERE id = ? AND store_id = ?
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(batchId),
        Variable<String>(storeId),
      ],
    ).getSingleOrNull();
    return row == null ? null : Map<String, dynamic>.from(row.data);
  }

  Future<List<Map<String, dynamic>>> _batchBalances(
    String batchId,
    String storeId,
  ) async {
    final rows = await db.customSelect(
      '''
      SELECT warehouse_id AS warehouseId, quantity,
             reserved_quantity AS reservedQuantity, updated_at AS updatedAt
      FROM inventory_batch_balances
      WHERE batch_id = ? AND store_id = ?
      ORDER BY warehouse_id
      ''',
      variables: <Variable<Object>>[
        Variable<String>(batchId),
        Variable<String>(storeId),
      ],
    ).get();
    return rows
        .map((row) => Map<String, dynamic>.from(row.data))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _batchMovements(
    String batchId,
    String storeId,
  ) async {
    final rows = await db.customSelect(
      '''
      SELECT id, product_id AS productId, product_name AS productName,
             batch_id AS batchId, movement_type AS movementType, quantity,
             movement_date AS movementDate, reference_id AS referenceId,
             reference_no AS referenceNo, warehouse_id AS warehouseId,
             warehouse_name AS warehouseName,
             movement_group_id AS movementGroupId,
             document_line_id AS documentLineId,
             source_movement_id AS sourceMovementId,
             reversal_of_movement_id AS reversalOfMovementId,
             unit_cost AS unitCost, reason, notes
      FROM stock_movements
      WHERE store_id = ? AND batch_id = ? AND deleted_at = ''
      ORDER BY movement_date, created_at, id
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(batchId),
      ],
    ).get();
    return rows
        .map((row) => Map<String, dynamic>.from(row.data))
        .toList(growable: false);
  }
}
