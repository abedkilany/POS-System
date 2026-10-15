part of 'business_sqlite_store_impl.dart';

Future<List<StockMovement>> readStockMovements(VentioDriftDatabase db) async {
  final rows = await db.customSelect('''
      SELECT id, product_id, product_name, movement_type, quantity,
             movement_date, reference_id, reference_no, reason,
             adjustment_category, notes, evidence_ref, warehouse_id,
             warehouse_name, batch_id, movement_group_id, document_line_id,
             source_movement_id, reversal_of_movement_id, idempotency_key,
             unit_cost, created_at, updated_at, device_id,
             sync_status, store_id, branch_id, version,
             last_modified_by_device_id, reviewed_at, reviewed_by, review_note
      FROM stock_movements
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
  return rows.map(_stockMovementFromRow).toList(growable: false);
}

Future<BusinessQueryPage<StockMovement>> queryStockMovements(
  VentioDriftDatabase db, {
  String query = '',
  String type = 'all',
  String productId = '',
  String warehouseId = '',
  DateTime? from,
  DateTime? to,
  bool? reviewed,
  int limit = 50,
  int offset = 0,
  String sortMode = 'newest',
}) async {
  final conditions = <String>["deleted_at = ''"];
  final variables = <Variable<Object>>[];
  final normalizedType = type.trim().toLowerCase();
  if (normalizedType.isNotEmpty && normalizedType != 'all') {
    conditions.add('lower(movement_type) = ?');
    variables.add(Variable<String>(normalizedType));
  }
  final normalizedProductId = productId.trim();
  if (normalizedProductId.isNotEmpty) {
    conditions.add('product_id = ?');
    variables.add(Variable<String>(normalizedProductId));
  }
  final normalizedWarehouseId = warehouseId.trim();
  if (normalizedWarehouseId.isNotEmpty) {
    conditions.add('warehouse_id = ?');
    variables.add(Variable<String>(normalizedWarehouseId));
  }
  if (from != null) {
    conditions.add('movement_date >= ?');
    variables.add(Variable<String>(_iso(from.toLocal())));
  }
  if (to != null) {
    conditions.add('movement_date < ?');
    variables.add(
      Variable<String>(_iso(to.toLocal().add(const Duration(days: 1)))),
    );
  }
  if (reviewed != null) {
    conditions.add(reviewed ? "reviewed_at <> ''" : "reviewed_at = ''");
  }
  final normalized = query.trim().toLowerCase();
  if (normalized.isNotEmpty) {
    conditions.add(
      "id IN (SELECT entity_id FROM search_index WHERE entity_type = 'stock_movement' AND search_text LIKE ?)",
    );
    variables.add(Variable<String>(_likePattern(normalized)));
  }
  final whereSql = conditions.join(' AND ');
  final safeLimit = _safeLimit(limit);
  final safeOffset = _safeOffset(offset);
  final usesTextSearch = normalized.isNotEmpty;
  final queryLimit = usesTextSearch ? safeLimit + 1 : safeLimit;
  final totalFuture = usesTextSearch
      ? null
      : _countWhere(db, 'stock_movements', whereSql, variables);
  final orderBy = switch (sortMode.trim().toLowerCase()) {
    'oldest' => 'movement_date ASC, updated_at ASC, id ASC',
    'product' => 'lower(product_name) ASC, movement_date DESC, id DESC',
    'quantity_high' => 'ABS(quantity) DESC, movement_date DESC, id DESC',
    'quantity_low' => 'ABS(quantity) ASC, movement_date DESC, id DESC',
    _ => 'movement_date DESC, updated_at DESC, id DESC',
  };
  final rows = await db.customSelect('''
      SELECT id, product_id, product_name, movement_type, quantity,
             movement_date, reference_id, reference_no, reason,
             adjustment_category, notes, evidence_ref, warehouse_id,
             warehouse_name, batch_id, movement_group_id, document_line_id,
             source_movement_id, reversal_of_movement_id, idempotency_key,
             unit_cost, created_at, updated_at, device_id,
             sync_status, store_id, branch_id, version,
             last_modified_by_device_id, reviewed_at, reviewed_by, review_note
      FROM stock_movements
      WHERE $whereSql
      ORDER BY $orderBy
      LIMIT ? OFFSET ?
    ''', variables: <Variable<Object>>[
    ...variables,
    Variable<int>(queryLimit),
    Variable<int>(safeOffset),
  ]).get();
  final hasMoreSearchRows = usesTextSearch && rows.length > safeLimit;
  final pageRows =
      hasMoreSearchRows ? rows.take(safeLimit).toList(growable: false) : rows;
  final total = usesTextSearch
      ? safeOffset + pageRows.length + (hasMoreSearchRows ? 1 : 0)
      : await totalFuture!;
  return BusinessQueryPage<StockMovement>(
    items: pageRows.map(_stockMovementFromRow).toList(growable: false),
    totalCount: total,
    limit: safeLimit,
    offset: safeOffset,
  );
}

Future<Map<String, Object?>> assistantStockBalances(
  VentioDriftDatabase db, {
  String storeId = '',
  String productQuery = '',
  String warehouseQuery = '',
}) async {
  final conditions = <String>[];
  final variables = <Variable<Object>>[];
  if (storeId.trim().isNotEmpty) {
    conditions.add('wi.store_id = ?');
    variables.add(Variable<String>(storeId.trim()));
  }
  final normalizedProduct = productQuery.trim().toLowerCase();
  if (normalizedProduct.isNotEmpty) {
    conditions.add(
      "(lower(COALESCE(p.name, '')) LIKE ? OR lower(wi.product_id) LIKE ?)",
    );
    final pattern = _likePattern(normalizedProduct);
    variables
      ..add(Variable<String>(pattern))
      ..add(Variable<String>(pattern));
  }
  final normalizedWarehouse = warehouseQuery.trim().toLowerCase();
  if (normalizedWarehouse.isNotEmpty) {
    conditions.add(
      "(lower(COALESCE(w.name, '')) LIKE ? OR lower(wi.warehouse_id) LIKE ?)",
    );
    final pattern = _likePattern(normalizedWarehouse);
    variables
      ..add(Variable<String>(pattern))
      ..add(Variable<String>(pattern));
  }
  final whereSql = conditions.isEmpty ? '1=1' : conditions.join(' AND ');
  final totalRow = await db.customSelect('''
      SELECT COUNT(*) AS balance_count
      FROM warehouse_inventory wi
      LEFT JOIN products p
        ON p.id = wi.product_id AND p.store_id = wi.store_id
      LEFT JOIN warehouses w
        ON w.id = wi.warehouse_id AND w.store_id = wi.store_id
      WHERE $whereSql
    ''', variables: variables).getSingle();
  final rows = await db.customSelect('''
      SELECT wi.branch_id AS branch_id,
             wi.product_id AS product_id,
             COALESCE(NULLIF(trim(p.name), ''), wi.product_id) AS product_name,
             wi.warehouse_id AS warehouse_id,
             COALESCE(NULLIF(trim(w.name), ''), wi.warehouse_id)
               AS warehouse_name,
             wi.quantity AS quantity
      FROM warehouse_inventory wi
      LEFT JOIN products p
        ON p.id = wi.product_id AND p.store_id = wi.store_id
      LEFT JOIN warehouses w
        ON w.id = wi.warehouse_id AND w.store_id = wi.store_id
      WHERE $whereSql
      ORDER BY ABS(wi.quantity) DESC, lower(product_name) ASC,
               lower(warehouse_name) ASC
      LIMIT 101
    ''', variables: variables).get();
  final balances = rows.take(100).map((row) {
    return <String, Object?>{
      'branchId': row.data['branch_id']?.toString() ?? '',
      'productId': row.data['product_id']?.toString() ?? '',
      'productName': row.data['product_name']?.toString() ?? '',
      'warehouseId': row.data['warehouse_id']?.toString() ?? '',
      'warehouseName': row.data['warehouse_name']?.toString() ?? '',
      'quantity': (row.data['quantity'] as num?)?.toDouble() ?? 0,
    };
  }).toList(growable: false);
  final balanceCount = (totalRow.data['balance_count'] as num?)?.toInt() ?? 0;
  return <String, Object?>{
    'productWarehouseCount': balanceCount,
    'balances': balances,
    'balancesTruncated': balanceCount > balances.length,
    'quantityTotalsCombined': false,
  };
}

Future<Map<String, Object?>> assistantStockMovementSummary(
  VentioDriftDatabase db, {
  required DateTime from,
  required DateTime to,
  String storeId = '',
  String productQuery = '',
  String warehouseQuery = '',
  String type = 'all',
}) async {
  final conditions = <String>["deleted_at = ''"];
  final variables = <Variable<Object>>[];
  conditions.add('movement_date >= ?');
  variables.add(Variable<String>(_iso(from.toLocal())));
  conditions.add('movement_date < ?');
  variables.add(
    Variable<String>(_iso(to.toLocal().add(const Duration(days: 1)))),
  );
  if (storeId.trim().isNotEmpty) {
    conditions.add('store_id = ?');
    variables.add(Variable<String>(storeId.trim()));
  }
  final normalizedType = type.trim().toLowerCase();
  if (normalizedType.isNotEmpty && normalizedType != 'all') {
    conditions.add('lower(movement_type) = ?');
    variables.add(Variable<String>(normalizedType));
  }
  final normalizedProduct = productQuery.trim().toLowerCase();
  if (normalizedProduct.isNotEmpty) {
    conditions.add('lower(product_name) LIKE ?');
    variables.add(Variable<String>(_likePattern(normalizedProduct)));
  }
  final normalizedWarehouse = warehouseQuery.trim().toLowerCase();
  if (normalizedWarehouse.isNotEmpty) {
    conditions.add('lower(warehouse_name) LIKE ?');
    variables.add(Variable<String>(_likePattern(normalizedWarehouse)));
  }
  final whereSql = conditions.join(' AND ');
  final totals = await db.customSelect('''
      SELECT COUNT(*) AS movement_count,
             COALESCE(SUM(quantity * unit_cost), 0)
               AS recorded_value_change_usd_reference,
             SUM(CASE WHEN unit_cost <= 0 THEN 1 ELSE 0 END)
               AS movements_without_recorded_cost
      FROM stock_movements
      WHERE $whereSql
    ''', variables: variables).getSingle();
  final groupCountRow = await db.customSelect('''
      SELECT COUNT(*) AS group_count
      FROM (
        SELECT branch_id, product_id, product_name, warehouse_id,
               warehouse_name, lower(movement_type)
        FROM stock_movements
        WHERE $whereSql
        GROUP BY branch_id, product_id, product_name, warehouse_id,
                 warehouse_name, lower(movement_type)
      ) movement_groups
    ''', variables: variables).getSingle();
  final rows = await db.customSelect('''
      SELECT branch_id, product_id, product_name, warehouse_id, warehouse_name,
             lower(movement_type) AS movement_type,
             COUNT(*) AS movement_count,
             COALESCE(SUM(quantity), 0) AS net_quantity,
             COALESCE(SUM(quantity * unit_cost), 0)
               AS recorded_value_change_usd_reference
      FROM stock_movements
      WHERE $whereSql
      GROUP BY branch_id, product_id, product_name, warehouse_id,
               warehouse_name, lower(movement_type)
      ORDER BY ABS(COALESCE(SUM(quantity * unit_cost), 0)) DESC,
               lower(product_name) ASC, lower(warehouse_name) ASC,
               movement_type ASC
      LIMIT 101
    ''', variables: variables).get();
  final groups = rows.take(100).map((row) {
    return <String, Object?>{
      'branchId': row.data['branch_id']?.toString() ?? '',
      'productId': row.data['product_id']?.toString() ?? '',
      'productName': row.data['product_name']?.toString() ?? '',
      'warehouseId': row.data['warehouse_id']?.toString() ?? '',
      'warehouseName': row.data['warehouse_name']?.toString() ?? '',
      'movementType': row.data['movement_type']?.toString() ?? '',
      'movementCount': (row.data['movement_count'] as num?)?.toInt() ?? 0,
      'netQuantity': (row.data['net_quantity'] as num?)?.toDouble() ?? 0,
      'recordedValueChangeUsdReference':
          (row.data['recorded_value_change_usd_reference'] as num?)
                  ?.toDouble() ??
              0,
    };
  }).toList(growable: false);
  final groupCount = (groupCountRow.data['group_count'] as num?)?.toInt() ?? 0;
  return <String, Object?>{
    'movementCount': (totals.data['movement_count'] as num?)?.toInt() ?? 0,
    'recordedValueChangeUsdReference':
        (totals.data['recorded_value_change_usd_reference'] as num?)
                ?.toDouble() ??
            0,
    'movementsWithoutRecordedCost':
        (totals.data['movements_without_recorded_cost'] as num?)?.toInt() ?? 0,
    'productWarehouseTypeGroupCount': groupCount,
    'groups': groups,
    'groupsTruncated': groupCount > groups.length,
    'quantitiesAreGroupedByProductAndWarehouse': true,
  };
}

Future<BusinessQueryPage<StockMovement>> queryWasteLossMovements(
  VentioDriftDatabase db, {
  int limit = 50,
  int offset = 0,
}) async {
  const whereSql =
      "(movement_type = 'inventory_loss' OR (movement_type = 'inventory_adjustment' AND quantity < 0))";
  final total = await _countWhere(db, 'stock_movements', whereSql, const []);
  final safeLimit = _safeLimit(limit);
  final safeOffset = _safeOffset(offset);
  final rows = await db.customSelect('''
      SELECT id, product_id, product_name, movement_type, quantity,
             movement_date, reference_id, reference_no, reason,
             adjustment_category, notes, evidence_ref, warehouse_id,
             warehouse_name, batch_id, movement_group_id, document_line_id,
             source_movement_id, reversal_of_movement_id, idempotency_key,
             unit_cost, created_at, updated_at, device_id,
             sync_status, store_id, branch_id, version,
             last_modified_by_device_id, reviewed_at, reviewed_by, review_note
      FROM stock_movements
      WHERE $whereSql
      ORDER BY movement_date DESC, updated_at DESC, id DESC
      LIMIT ? OFFSET ?
    ''', variables: <Variable<Object>>[
    Variable<int>(safeLimit),
    Variable<int>(safeOffset),
  ]).get();
  return BusinessQueryPage<StockMovement>(
    items: rows.map(_stockMovementFromRow).toList(growable: false),
    totalCount: total,
    limit: safeLimit,
    offset: safeOffset,
  );
}

Future<List<StockMovement>> readUnreversedInventoryCountMovements(
  VentioDriftDatabase db,
  String inventoryCountId,
) async {
  final rows = await db.customSelect('''
      SELECT sm.id, sm.product_id, sm.product_name, sm.movement_type,
             sm.quantity, sm.movement_date, sm.reference_id, sm.reference_no,
             sm.reason, sm.adjustment_category, sm.notes, sm.evidence_ref,
             sm.warehouse_id, sm.warehouse_name, sm.batch_id,
             sm.movement_group_id, sm.document_line_id, sm.source_movement_id,
             sm.reversal_of_movement_id, sm.idempotency_key, sm.unit_cost,
             sm.created_at, sm.updated_at, sm.device_id, sm.sync_status,
             sm.store_id, sm.branch_id, sm.version,
             sm.last_modified_by_device_id, sm.reviewed_at, sm.reviewed_by,
             sm.review_note
      FROM stock_movements sm
      WHERE sm.reference_id = ?
        AND sm.movement_type = 'count_adjustment'
        AND sm.deleted_at = ''
        AND NOT EXISTS (
          SELECT 1 FROM stock_movements rev
          WHERE rev.reversal_of_movement_id = sm.id
            AND rev.deleted_at = ''
        )
      ORDER BY sm.movement_date ASC, sm.id ASC
    ''', variables: <Variable<Object>>[
    Variable<String>(inventoryCountId),
  ]).get();
  return rows.map(_stockMovementFromRow).toList(growable: false);
}

Future<Map<String, int>> countStockMovementsAfterByProduct(
  VentioDriftDatabase db,
  Map<String, DateTime> countedAtByProduct,
) async {
  if (countedAtByProduct.isEmpty) return const <String, int>{};
  final result = <String, int>{};
  for (final entry in countedAtByProduct.entries) {
    final productId = entry.key.trim();
    if (productId.isEmpty) continue;
    final rows = await db.customSelect('''
        SELECT COUNT(*) AS c
        FROM stock_movements
        WHERE product_id = ?
          AND movement_type <> 'count_adjustment'
          AND movement_date > ?
      ''', variables: <Variable<Object>>[
      Variable<String>(productId),
      Variable<String>(_iso(entry.value.toLocal())),
    ]).get();
    result[productId] = rows.isEmpty ? 0 : rows.first.read<int>('c');
  }
  return result;
}
