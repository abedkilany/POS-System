part of 'accounting_service_impl.dart';

Future<List<InventoryValuationRowReport>> inventoryValuationReport({
  VentioDriftDatabase? database,
}) async {
  if (database == null && !isAvailable) {
    return const <InventoryValuationRowReport>[];
  }
  final db = database ?? _db;
  final rawAccount = await _resolveAccountRoleForDatabase(db, 'inventory_raw');
  final finishedAccount =
      await _resolveAccountRoleForDatabase(db, 'inventory_finished');
  final tradingAccount =
      await _resolveAccountRoleForDatabase(db, 'inventory_merchandise');
  final methodRow = await db
      .customSelect(
        "SELECT value FROM settings WHERE key = 'inventory_costing_method_v1' LIMIT 1",
      )
      .getSingleOrNull();
  final costingMethod =
      methodRow?.data['value']?.toString().trim().toLowerCase() ?? 'batch';
  final useBatch = costingMethod == 'batch' || costingMethod == 'unified_batch';

  if (useBatch) {
    // A blocked Phase 4 closure means Unified Batch is not yet a complete
    // valuation authority for every Product x Warehouse pair. Returning a
    // partial Batch valuation here would make accounting reports and
    // reclassification logic look authoritative while silently omitting
    // legacy inventory. Fail closed until the closure is repaired and
    // completed successfully.
    final phase4StateRow = await db.customSelect(
      'SELECT value FROM migration_meta WHERE key = ? LIMIT 1',
      variables: const <Variable<Object>>[
        Variable<String>(
          UnifiedBatchPhase4ClosureService.closureStateMetaKey,
        ),
      ],
    ).getSingleOrNull();
    final phase4State =
        phase4StateRow?.data['value']?.toString().trim().toLowerCase() ?? '';
    if (phase4State == 'blocked') {
      final phase4ErrorRow = await db.customSelect(
        'SELECT value FROM migration_meta WHERE key = ? LIMIT 1',
        variables: const <Variable<Object>>[
          Variable<String>(
            UnifiedBatchPhase4ClosureService.closureErrorMetaKey,
          ),
        ],
      ).getSingleOrNull();
      final detail = phase4ErrorRow?.data['value']?.toString().trim() ?? '';
      throw LocalizedDomainException(
        'error_unified_batch_valuation_blocked',
        values: <String, Object?>{'detail': detail},
        fallback: detail.isEmpty
            ? 'Unified Batch Phase 4 is blocked; inventory valuation is unavailable until reconciliation completes.'
            : 'Unified Batch Phase 4 is blocked; inventory valuation is unavailable until reconciliation completes. $detail',
      );
    }
    final rows = await db.customSelect(r'''
        SELECT wi.product_id, p.name AS product_name, wi.warehouse_id,
               COALESCE(w.name, wi.warehouse_id) AS warehouse_name,
               wi.quantity,
               COALESCE(batch.batch_qty, 0) - COALESCE(deficit.deficit_qty, 0) AS batch_qty,
               COALESCE(batch.batch_value, 0) - COALESCE(deficit.deficit_value, 0) AS batch_value,
               CASE
                 WHEN EXISTS (
                   SELECT 1 FROM bill_of_materials bom
                   WHERE bom.output_product_id = wi.product_id
                     AND bom.is_active = 1 AND bom.deleted_at = ''
                 ) THEN 'finished_goods'
                 WHEN EXISTS (
                   SELECT 1
                   FROM bill_of_materials_lines line
                   INNER JOIN bill_of_materials bom
                     ON bom.id = line.bill_of_material_id
                   WHERE line.product_id = wi.product_id
                     AND bom.is_active = 1 AND bom.deleted_at = ''
                 ) THEN 'raw_materials'
                 ELSE 'merchandise'
               END AS inventory_category
        FROM warehouse_inventory wi
        INNER JOIN products p ON p.id = wi.product_id AND p.deleted_at = ''
        LEFT JOIN warehouses w ON w.id = wi.warehouse_id AND w.deleted_at = ''
        LEFT JOIN (
          SELECT bb.store_id, bb.product_id, bb.warehouse_id,
                 SUM(bb.quantity) AS batch_qty,
                 SUM(bb.quantity * b.unit_cost) AS batch_value
          FROM inventory_batch_balances bb
          INNER JOIN inventory_batches b ON b.id = bb.batch_id
            AND b.product_id = bb.product_id AND b.store_id = bb.store_id
          WHERE b.source_type <> 'inventory_deficit'
            AND b.id NOT LIKE 'deficit:%'
          GROUP BY bb.store_id, bb.product_id, bb.warehouse_id
        ) batch ON batch.store_id = wi.store_id
          AND batch.product_id = wi.product_id
          AND batch.warehouse_id = wi.warehouse_id
        LEFT JOIN (
          SELECT store_id, product_id, warehouse_id,
                 SUM(quantity_open) AS deficit_qty,
                 SUM(quantity_open * provisional_unit_cost) AS deficit_value
          FROM inventory_stock_deficits
          WHERE status = 'open' AND quantity_open > 0.000001
          GROUP BY store_id, product_id, warehouse_id
        ) deficit ON deficit.store_id = wi.store_id
          AND deficit.product_id = wi.product_id
          AND deficit.warehouse_id = wi.warehouse_id
        WHERE ABS(wi.quantity) > 0.000001
        ORDER BY p.name, warehouse_name
      ''').get();
    return rows.map((row) {
      final quantity = _num(row.data['quantity']);
      final batchQuantity = _num(row.data['batch_qty']);
      final batchValue = _num(row.data['batch_value']);
      final unitCost =
          batchQuantity.abs() <= 0.000001 ? 0.0 : batchValue / batchQuantity;
      final category =
          row.data['inventory_category']?.toString() ?? 'merchandise';
      final accountId = switch (category) {
        'finished_goods' => finishedAccount,
        'raw_materials' => rawAccount,
        _ => tradingAccount,
      };
      return InventoryValuationRowReport(
        productId: row.data['product_id']?.toString() ?? '',
        productName: row.data['product_name']?.toString() ?? '',
        warehouseId: row.data['warehouse_id']?.toString() ?? '',
        warehouseName: row.data['warehouse_name']?.toString() ?? '',
        quantity: quantity,
        unitCost: _roundMoney(unitCost),
        totalValue: _roundMoney(batchValue),
        inventoryAccountId: accountId,
        inventoryCategory: category,
        fallbackInventoryAccountId: tradingAccount,
      );
    }).toList(growable: false);
  }

  // Legacy costing branches remain available only for explicit historical
  // regression/migration test stores. Production Phase 4 is locked to Batch.
  final useFifo = costingMethod == 'fifo';
  final rows = await db.customSelect(r'''
      SELECT wi.product_id, p.name AS product_name, wi.warehouse_id,
             COALESCE(w.name, wi.warehouse_id) AS warehouse_name, wi.quantity,
             CASE
               WHEN ? = 1 AND COALESCE(fifo.remaining_qty, 0) > 0
                 THEN fifo.remaining_value / fifo.remaining_qty
               WHEN COALESCE(pc.average_cost, 0) > 0 THEN pc.average_cost
               WHEN COALESCE(p.usd_cost, 0) > 0 THEN p.usd_cost
               ELSE COALESCE(p.cost, 0)
             END AS unit_cost,
             CASE
               WHEN EXISTS (
                 SELECT 1 FROM bill_of_materials bom
                 WHERE bom.output_product_id = wi.product_id
                   AND bom.is_active = 1 AND bom.deleted_at = ''
               ) THEN 'finished_goods'
               WHEN EXISTS (
                 SELECT 1
                 FROM bill_of_materials_lines line
                 INNER JOIN bill_of_materials bom
                   ON bom.id = line.bill_of_material_id
                 WHERE line.product_id = wi.product_id
                   AND bom.is_active = 1 AND bom.deleted_at = ''
               ) THEN 'raw_materials'
               ELSE 'merchandise'
             END AS inventory_category
      FROM warehouse_inventory wi
      INNER JOIN products p ON p.id = wi.product_id AND p.deleted_at = ''
      LEFT JOIN warehouses w ON w.id = wi.warehouse_id AND w.deleted_at = ''
      LEFT JOIN product_costs pc ON pc.product_id = wi.product_id
      LEFT JOIN (
        SELECT product_id,
               SUM(quantity_remaining) AS remaining_qty,
               SUM(quantity_remaining * unit_cost) AS remaining_value
        FROM inventory_cost_layers
        WHERE deleted_at = '' AND is_closed = 0 AND quantity_remaining > 0
        GROUP BY product_id
      ) fifo ON fifo.product_id = wi.product_id
      WHERE ABS(wi.quantity) > 0.000001
      ORDER BY p.name, warehouse_name
    ''', variables: <Variable<Object>>[
    Variable<int>(useFifo ? 1 : 0),
  ]).get();
  return rows.map((row) {
    final quantity = _num(row.data['quantity']);
    final unitCost = _num(row.data['unit_cost']);
    final category =
        row.data['inventory_category']?.toString() ?? 'merchandise';
    final accountId = switch (category) {
      'finished_goods' => finishedAccount,
      'raw_materials' => rawAccount,
      _ => tradingAccount,
    };
    return InventoryValuationRowReport(
      productId: row.data['product_id']?.toString() ?? '',
      productName: row.data['product_name']?.toString() ?? '',
      warehouseId: row.data['warehouse_id']?.toString() ?? '',
      warehouseName: row.data['warehouse_name']?.toString() ?? '',
      quantity: quantity,
      unitCost: _roundMoney(unitCost),
      totalValue: _roundMoney(quantity * unitCost),
      inventoryAccountId: accountId,
      inventoryCategory: category,
      fallbackInventoryAccountId: tradingAccount,
    );
  }).toList(growable: false);
}

Future<List<ManufacturingOrderCostReport>>
    manufacturingOrderCostReport() async {
  if (!isAvailable) return const <ManufacturingOrderCostReport>[];
  final orders = await BusinessSqliteStore.readManufacturingOrders(_db);
  return orders
      .where((order) => !order.isDeleted && order.status != 'in_progress')
      .map((order) => ManufacturingOrderCostReport(
            orderId: order.id,
            orderNo: order.orderNo,
            outputProductId: order.outputProductId,
            outputProductName: order.outputProductName,
            outputQuantity: order.actualOutputQuantity > 0
                ? order.actualOutputQuantity
                : order.quantity,
            totalMaterialCost: order.totalMaterialCost,
            wasteValue: order.totalWasteCost,
            eligibleCost: order.totalEligibleCost,
            actualUnitCost: order.actualUnitCost,
            status: order.status,
            journalEntryId: order.journalEntryId,
            materialCosts: order.materialCosts,
          ))
      .toList(growable: false);
}

Future<List<ManufacturingWasteReportRow>> manufacturingWasteReport() async {
  if (!isAvailable) return const <ManufacturingWasteReportRow>[];
  final orders = await BusinessSqliteStore.readManufacturingOrders(_db);
  return <ManufacturingWasteReportRow>[
    for (final order in orders)
      if (!order.isDeleted)
        for (final waste in order.wasteLines)
          ManufacturingWasteReportRow(
            orderId: order.id,
            orderNo: order.orderNo,
            productId: waste.productId,
            productName: waste.productName,
            quantity: waste.quantity,
            unitCost: waste.unitCost,
            value: waste.value,
            reason: waste.reason,
            status: order.status,
          ),
  ];
}

Future<List<InventoryCountVarianceReportRow>>
    inventoryCountVarianceReport() async {
  if (!isAvailable) return const <InventoryCountVarianceReportRow>[];
  final rows = await _db.customSelect('''
      SELECT ic.id AS session_id, ic.count_no, ic.status,
             ic.journal_entry_id, ic.reversal_journal_entry_id,
             l.product_id, l.product_name, l.system_qty_at_approval,
             l.counted_qty, l.difference_qty, l.unit_cost,
             l.difference_value, l.stock_movement_id
      FROM inventory_counts ic
      INNER JOIN inventory_count_lines l ON l.inventory_count_id = ic.id
      WHERE ic.deleted_at = '' AND COALESCE(l.difference_qty, 0) != 0
      ORDER BY ic.created_at, ic.count_no, l.line_no
    ''').get();
  return rows
      .map((row) => InventoryCountVarianceReportRow.fromRow(row.data))
      .toList(growable: false);
}

Future<List<CashBankMovementReport>> cashBankMovementReport() async {
  if (!isAvailable) return const <CashBankMovementReport>[];
  final accountIds = await _cashAndBankAccountIds(_db);
  if (accountIds.isEmpty) return <CashBankMovementReport>[];
  final placeholders = List.filled(accountIds.length, '?').join(',');
  final rows = await _db.customSelect(
    '''
      SELECT jl.account_id, jl.account_code, jl.account_name,
             COALESCE(SUM(jl.debit), 0) AS money_in,
             COALESCE(SUM(jl.credit), 0) AS money_out
      FROM journal_lines jl
      INNER JOIN journal_entries je ON je.id = jl.entry_id
      WHERE jl.account_id IN ($placeholders)
        AND je.deleted_at = ''
        AND je.status IN ('posted', 'reversed')
      GROUP BY jl.account_id, jl.account_code, jl.account_name
      ORDER BY jl.account_code
      ''',
    variables: <Variable<Object>>[
      for (final accountId in accountIds) Variable<String>(accountId),
    ],
  ).get();
  return rows.map((row) {
    final moneyIn = _num(row.data['money_in']);
    final moneyOut = _num(row.data['money_out']);
    return CashBankMovementReport(
      accountId: row.data['account_id']?.toString() ?? '',
      accountCode: row.data['account_code']?.toString() ?? '',
      accountName: row.data['account_name']?.toString() ?? '',
      moneyIn: _roundMoney(moneyIn),
      moneyOut: _roundMoney(moneyOut),
      closingBalance: _roundMoney(moneyIn - moneyOut),
    );
  }).toList();
}
