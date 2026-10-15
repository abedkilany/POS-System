part of 'accounting_production_integrity_service.dart';

extension AccountingProductionIntegrityServiceSplitPart2 on AccountingProductionIntegrityService {

  Future<void> _checkManufacturingAndCounts(
      List<AccountingIntegrityIssue> issues) async {
    final manufacturing = await _db.customSelect(r'''
      SELECT mo.id, mo.order_no, mo.status, mo.journal_entry_id,
             mo.reversal_journal_entry_id
      FROM manufacturing_orders mo
      WHERE mo.deleted_at = ''
        AND (
          (
            lower(trim(mo.status)) = 'completed'
            AND ABS(COALESCE(mo.total_material_cost, 0)
                    + COALESCE(mo.total_waste_cost, 0)
                    + COALESCE(mo.total_eligible_cost, 0)) > 0.005
            AND (
              trim(mo.journal_entry_id) = ''
              OR NOT EXISTS (
                SELECT 1 FROM journal_entries je
                WHERE je.id = mo.journal_entry_id
                  AND je.reference_type = 'manufacturing_order'
                  AND (je.reference_id = mo.id
                       OR instr(je.reference_id, mo.id || ':manufacturing_edit:') = 1)
                  AND je.deleted_at = '' AND je.status = 'posted'
              )
            )
          )
          OR (
            lower(trim(mo.status)) = 'reversed'
            AND trim(mo.journal_entry_id) <> ''
            AND (
              trim(mo.reversal_journal_entry_id) = ''
              OR NOT EXISTS (
                SELECT 1 FROM journal_entries original
                WHERE original.id = mo.journal_entry_id
                  AND original.deleted_at = '' AND original.status = 'reversed'
              )
              OR NOT EXISTS (
                SELECT 1 FROM journal_entries rev
                WHERE rev.id = mo.reversal_journal_entry_id
                  AND rev.deleted_at = '' AND rev.status = 'posted'
                  AND rev.reversed_entry_id = mo.journal_entry_id
              )
            )
          )
        )
    ''').get();
    for (final row in manufacturing) {
      issues.add(AccountingIntegrityIssue(
        code: 'manufacturing_journal_integrity',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'manufacturing_order',
        entityId: row.data['id']?.toString() ?? '',
        message:
            'Manufacturing order ${row.data['order_no'] ?? ''} is not reconciled with its accounting journal/reversal.',
      ));
    }

    final counts = await _db.customSelect(r'''
      SELECT ic.id, ic.count_no, ic.status, ic.journal_entry_id,
             ic.reversal_journal_entry_id
      FROM inventory_counts ic
      WHERE ic.deleted_at = ''
        AND EXISTS (
          SELECT 1 FROM inventory_count_lines line
          WHERE line.inventory_count_id = ic.id
            AND ABS(COALESCE(line.difference_value, 0)) > 0.005
        )
        AND (
          (
            lower(trim(ic.status)) = 'approved'
            AND (
              trim(ic.journal_entry_id) = ''
              OR NOT EXISTS (
                SELECT 1 FROM journal_entries je
                WHERE je.id = ic.journal_entry_id
                  AND je.reference_type = 'inventory_count'
                  AND je.reference_id = ic.id
                  AND je.deleted_at = '' AND je.status = 'posted'
              )
            )
          )
          OR (
            lower(trim(ic.status)) = 'reversed'
            AND (
              trim(ic.reversal_journal_entry_id) = ''
              OR NOT EXISTS (
                SELECT 1 FROM journal_entries original
                WHERE original.id = ic.journal_entry_id
                  AND original.deleted_at = '' AND original.status = 'reversed'
              )
              OR NOT EXISTS (
                SELECT 1 FROM journal_entries rev
                WHERE rev.id = ic.reversal_journal_entry_id
                  AND rev.deleted_at = '' AND rev.status = 'posted'
                  AND rev.reversed_entry_id = ic.journal_entry_id
              )
            )
          )
        )
    ''').get();
    for (final row in counts) {
      issues.add(AccountingIntegrityIssue(
        code: 'inventory_count_journal_integrity',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'inventory_count',
        entityId: row.data['id']?.toString() ?? '',
        message:
            'Inventory count ${row.data['count_no'] ?? ''} is not reconciled with its accounting journal/reversal.',
      ));
    }
  }

  Future<void> _checkStockReversalLinks(
      List<AccountingIntegrityIssue> issues) async {
    final rows = await _db.customSelect(r'''
      SELECT sm.id, sm.reversal_of_movement_id
      FROM stock_movements sm
      LEFT JOIN stock_movements original ON original.id = sm.reversal_of_movement_id
      WHERE sm.deleted_at = ''
        AND trim(sm.reversal_of_movement_id) <> ''
        AND original.id IS NULL
    ''').get();
    for (final row in rows) {
      issues.add(AccountingIntegrityIssue(
        code: 'orphan_stock_reversal',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'stock_movement',
        entityId: row.data['id']?.toString() ?? '',
        message:
            'Stock reversal references missing movement ${row.data['reversal_of_movement_id'] ?? ''}.',
      ));
    }
  }

  Future<void> _checkCostingMethodHistory(
      List<AccountingIntegrityIssue> issues) async {
    final settingRow = await _db.customSelect(
      "SELECT value FROM settings WHERE key = 'inventory_costing_method_v1' LIMIT 1",
    ).getSingleOrNull();
    final configured =
        settingRow?.data['value']?.toString().trim().toLowerCase() ?? '';
    if (configured != 'batch' && configured != 'unified_batch') {
      issues.add(const AccountingIntegrityIssue(
        code: 'inventory_costing_not_unified_batch',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'costing_method_history',
        message:
            'Phase 4 requires inventory costing to be permanently locked to Unified Batch.',
      ));
    }

    final openRows = await _db.customSelect(r'''
      SELECT id, method, effective_from
      FROM costing_method_history
      WHERE deleted_at = '' AND trim(effective_to) = ''
      ORDER BY effective_from ASC, id ASC
    ''').get();
    if (openRows.length != 1) {
      issues.add(AccountingIntegrityIssue(
        code: 'costing_method_history_open_count',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'costing_method_history',
        difference: openRows.length.toDouble() - 1,
        message:
            'Exactly one costing-method history row must be open; found ${openRows.length}.',
      ));
      return;
    }
    final openMethod =
        openRows.single.data['method']?.toString().trim().toLowerCase() ?? '';
    if (openMethod != 'batch' && openMethod != 'unified_batch') {
      issues.add(AccountingIntegrityIssue(
        code: 'costing_method_history_not_unified_batch',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'costing_method_history',
        entityId: openRows.single.data['id']?.toString() ?? '',
        message:
            'The only open costing-method history row must be Unified Batch.',
      ));
    }
  }

  Future<void> _checkUnifiedBatchState(
      List<AccountingIntegrityIssue> issues) async {
    final negativeBatches = await _db.customSelect(r'''
      SELECT id, product_id, warehouse_id, quantity
      FROM inventory_batch_balances
      WHERE quantity < -0.005
    ''').get();
    for (final row in negativeBatches) {
      issues.add(AccountingIntegrityIssue(
        code: 'negative_unified_batch_balance',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'inventory_batch_balance',
        entityId: row.data['id']?.toString() ?? '',
        difference: AccountingProductionIntegrityService._round(AccountingProductionIntegrityService._num(row.data['quantity'])),
        message:
            'Unified Batch balance is negative for product ${row.data['product_id'] ?? ''}.',
      ));
    }

    final mismatches = await _db.customSelect(r'''
      WITH scoped AS (
        SELECT store_id, warehouse_id, product_id FROM warehouse_inventory
        UNION
        SELECT store_id, warehouse_id, product_id FROM inventory_batch_balances
        UNION
        SELECT store_id, warehouse_id, product_id FROM inventory_stock_deficits
        WHERE status = 'open' AND quantity_open > 0.000001
      ), warehouse AS (
        SELECT store_id, warehouse_id, product_id, SUM(quantity) AS qty
        FROM warehouse_inventory
        GROUP BY store_id, warehouse_id, product_id
      ), batches AS (
        SELECT store_id, warehouse_id, product_id, SUM(quantity) AS qty
        FROM inventory_batch_balances
        GROUP BY store_id, warehouse_id, product_id
      ), deficits AS (
        SELECT store_id, warehouse_id, product_id, SUM(quantity_open) AS qty
        FROM inventory_stock_deficits
        WHERE status = 'open' AND quantity_open > 0.000001
        GROUP BY store_id, warehouse_id, product_id
      )
      SELECT s.store_id, s.warehouse_id, s.product_id,
             COALESCE(w.qty, 0) AS warehouse_qty,
             COALESCE(b.qty, 0) - COALESCE(d.qty, 0) AS batch_qty
      FROM scoped s
      INNER JOIN products p ON p.id = s.product_id
        AND p.deleted_at = '' AND p.track_stock = 1
      LEFT JOIN warehouse w ON w.store_id = s.store_id
        AND w.warehouse_id = s.warehouse_id AND w.product_id = s.product_id
      LEFT JOIN batches b ON b.store_id = s.store_id
        AND b.warehouse_id = s.warehouse_id AND b.product_id = s.product_id
      LEFT JOIN deficits d ON d.store_id = s.store_id
        AND d.warehouse_id = s.warehouse_id AND d.product_id = s.product_id
      WHERE ABS(COALESCE(w.qty, 0)
        - (COALESCE(b.qty, 0) - COALESCE(d.qty, 0))) > 0.005
    ''').get();
    for (final row in mismatches) {
      final warehouse = AccountingProductionIntegrityService._num(row.data['warehouse_qty']);
      final batches = AccountingProductionIntegrityService._num(row.data['batch_qty']);
      issues.add(AccountingIntegrityIssue(
        code: 'unified_batch_quantity_mismatch',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'product',
        entityId: row.data['product_id']?.toString() ?? '',
        difference: AccountingProductionIntegrityService._round(warehouse - batches),
        message:
            'Warehouse quantity ($warehouse) does not equal Unified Batch quantity net of open deficits ($batches) in warehouse ${row.data['warehouse_id'] ?? ''}.',
      ));
    }

    final invalidMetadata = await _db.customSelect(r'''
      SELECT b.id, b.product_id, b.unit_cost, b.expiration_date,
             p.expiry_tracking_enabled, COALESCE(SUM(bb.quantity), 0) AS qty
      FROM inventory_batches b
      INNER JOIN products p ON p.id = b.product_id
      LEFT JOIN inventory_batch_balances bb ON bb.batch_id = b.id
      WHERE p.deleted_at = '' AND p.track_stock = 1
      GROUP BY b.id, b.product_id, b.unit_cost, b.expiration_date,
               p.expiry_tracking_enabled
      HAVING b.unit_cost < -0.005
        OR (qty > 0.005 AND p.expiry_tracking_enabled = 1
            AND trim(b.expiration_date) = '')
        OR (qty > 0.005 AND p.expiry_tracking_enabled = 0
            AND trim(b.expiration_date) <> '')
    ''').get();
    for (final row in invalidMetadata) {
      issues.add(AccountingIntegrityIssue(
        code: 'invalid_unified_batch_metadata',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'inventory_batch',
        entityId: row.data['id']?.toString() ?? '',
        message:
            'Unified Batch metadata/cost is invalid for product ${row.data['product_id'] ?? ''}.',
      ));
    }

    final missingCutovers = await _db.customSelect(r'''
      SELECT wi.store_id, wi.warehouse_id, wi.product_id
      FROM warehouse_inventory wi
      INNER JOIN products p ON p.id = wi.product_id
        AND p.deleted_at = '' AND p.track_stock = 1
      LEFT JOIN unified_batch_cutovers uc
        ON uc.store_id = wi.store_id AND uc.warehouse_id = wi.warehouse_id
        AND uc.product_id = wi.product_id
      WHERE uc.id IS NULL
    ''').get();
    for (final row in missingCutovers) {
      issues.add(AccountingIntegrityIssue(
        code: 'unified_batch_cutover_missing',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'product',
        entityId: row.data['product_id']?.toString() ?? '',
        message:
            'Tracked inventory has no Phase 4 Unified Batch cutover marker in warehouse ${row.data['warehouse_id'] ?? ''}.',
      ));
    }

    final postCutoverUnbatched = await _db.customSelect(r'''
      SELECT sm.id, sm.product_id, sm.warehouse_id
      FROM stock_movements sm
      INNER JOIN unified_batch_cutovers uc
        ON uc.store_id = sm.store_id AND uc.warehouse_id = sm.warehouse_id
        AND uc.product_id = sm.product_id
      INNER JOIN products p ON p.id = sm.product_id
        AND p.deleted_at = '' AND p.track_stock = 1
      WHERE sm.deleted_at = '' AND sm.quantity < -0.005
        AND trim(sm.batch_id) = ''
        AND datetime(sm.movement_date) >= datetime(uc.cutover_at)
    ''').get();
    for (final row in postCutoverUnbatched) {
      issues.add(AccountingIntegrityIssue(
        code: 'post_cutover_unbatched_stock_out',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'stock_movement',
        entityId: row.data['id']?.toString() ?? '',
        message:
            'A post-cutover stock-out exists without Unified Batch identity.',
      ));
    }

    final closureRow = await _db.customSelect(
      "SELECT value FROM migration_meta WHERE key = 'unified_batch_phase4_closed_at' LIMIT 1",
    ).getSingleOrNull();
    final closureAt = closureRow?.data['value']?.toString().trim() ?? '';
    if (closureAt.isNotEmpty) {
      final lateLegacyLayers = await _db.customSelect(r'''
        SELECT id, product_id
        FROM inventory_cost_layers
        WHERE deleted_at = '' AND datetime(created_at) > datetime(?)
      ''', variables: <Variable<Object>>[
        Variable<String>(closureAt),
      ]).get();
      for (final row in lateLegacyLayers) {
        issues.add(AccountingIntegrityIssue(
          code: 'legacy_cost_layer_post_phase4_write',
          severity: AccountingIntegritySeverity.critical,
          entityType: 'inventory_cost_layer',
          entityId: row.data['id']?.toString() ?? '',
          message:
              'A legacy cost layer was written after the Unified Batch Phase 4 closure.',
        ));
      }
    }
  }

  Future<(double, double)> _inventoryReconciliation(
      List<AccountingIntegrityIssue> issues) async {
    final accountIds = <String>{};
    final accountByRole = <String, String>{};
    for (final role in const <String>[
      'inventory_asset',
      'inventory_raw',
      'inventory_wip',
      'inventory_finished',
      'inventory_merchandise',
    ]) {
      try {
        final accountId = await AccountingService.resolveAccountRoleForDatabase(
          _db,
          role,
        );
        if (accountId.trim().isNotEmpty) {
          accountIds.add(accountId.trim());
          accountByRole[role] = accountId.trim();
        }
      } catch (error) {
        issues.add(AccountingIntegrityIssue(
          code: 'inventory_account_role_invalid',
          severity: AccountingIntegritySeverity.critical,
          entityType: 'account_role',
          entityId: role,
          message: 'Inventory account role $role cannot be resolved: $error',
        ));
      }
    }

    var glBalance = 0.0;
    if (accountIds.isNotEmpty) {
      final placeholders = List<String>.filled(accountIds.length, '?').join(',');
      final row = await _db.customSelect(
        '''
        SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
        FROM journal_lines jl
        INNER JOIN journal_entries je ON je.id = jl.entry_id
        WHERE jl.account_id IN ($placeholders)
          AND je.deleted_at = ''
          AND je.status IN ('posted', 'reversed')
        ''',
        variables: <Variable<Object>>[
          for (final accountId in accountIds) Variable<String>(accountId),
        ],
      ).getSingle();
      glBalance = AccountingProductionIntegrityService._round(AccountingProductionIntegrityService._num(row.data['balance']));
    }

    final valuationRow = await _db.customSelect(r'''
      SELECT COALESCE(SUM(bb.quantity * b.unit_cost), 0) AS valuation
      FROM inventory_batch_balances bb
      INNER JOIN inventory_batches b ON b.id = bb.batch_id
        AND b.product_id = bb.product_id AND b.store_id = bb.store_id
      INNER JOIN products p ON p.id = bb.product_id
        AND p.deleted_at = '' AND p.track_stock = 1
      WHERE bb.quantity > 0.000001
    ''').getSingle();
    final valuation = AccountingProductionIntegrityService._round(AccountingProductionIntegrityService._num(valuationRow.data['valuation']));

    final difference = AccountingProductionIntegrityService._round(glBalance - valuation);
    if (difference.abs() > 0.05) {
      issues.add(AccountingIntegrityIssue(
        code: 'inventory_gl_valuation_mismatch',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'inventory',
        difference: difference,
        message:
            'Inventory GL balance ($glBalance) does not reconcile to inventory valuation ($valuation).',
      ));
    }

    // Total inventory can reconcile while value is posted to the wrong semantic
    // asset account (for example Merchandise instead of Raw Materials after a
    // BOM change). Verify the per-account distribution as a separate critical
    // invariant so an equal-and-opposite misclassification cannot pass the
    // production gate. Aggregate raw Unified Batch value by semantic class
    // before rounding to avoid per-row rounding drift.
    final expectedByAccount = <String, double>{};
    final semanticRows = await _db.customSelect(r'''
      SELECT CASE
               WHEN EXISTS (
                 SELECT 1 FROM bill_of_materials bom
                 WHERE bom.output_product_id = bb.product_id
                   AND bom.is_active = 1 AND bom.deleted_at = ''
               ) THEN 'inventory_finished'
               WHEN EXISTS (
                 SELECT 1
                 FROM bill_of_materials_lines line
                 INNER JOIN bill_of_materials bom
                   ON bom.id = line.bill_of_material_id
                 WHERE line.product_id = bb.product_id
                   AND bom.is_active = 1 AND bom.deleted_at = ''
               ) THEN 'inventory_raw'
               ELSE 'inventory_merchandise'
             END AS role_key,
             COALESCE(SUM(bb.quantity * b.unit_cost), 0) AS valuation
      FROM inventory_batch_balances bb
      INNER JOIN inventory_batches b ON b.id = bb.batch_id
        AND b.product_id = bb.product_id AND b.store_id = bb.store_id
      INNER JOIN products p ON p.id = bb.product_id
        AND p.deleted_at = '' AND p.track_stock = 1
      WHERE bb.quantity > 0.000001
      GROUP BY role_key
    ''').get();
    for (final row in semanticRows) {
      final roleKey = row.data['role_key']?.toString() ?? '';
      final accountId = accountByRole[roleKey] ?? '';
      if (accountId.isEmpty) continue;
      expectedByAccount[accountId] = AccountingProductionIntegrityService._round(
        (expectedByAccount[accountId] ?? 0) + AccountingProductionIntegrityService._num(row.data['valuation']),
      );
    }
    for (final accountId in accountIds) {
      final row = await _db.customSelect(
        '''
        SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
        FROM journal_lines jl
        INNER JOIN journal_entries je ON je.id = jl.entry_id
        WHERE jl.account_id = ?
          AND je.deleted_at = ''
          AND je.status IN ('posted', 'reversed')
        ''',
        variables: <Variable<Object>>[Variable<String>(accountId)],
      ).getSingle();
      final actual = AccountingProductionIntegrityService._round(AccountingProductionIntegrityService._num(row.data['balance']));
      final expected = AccountingProductionIntegrityService._round(expectedByAccount[accountId] ?? 0);
      final accountDifference = AccountingProductionIntegrityService._round(actual - expected);
      if (accountDifference.abs() > 0.05) {
        issues.add(AccountingIntegrityIssue(
          code: 'inventory_semantic_account_mismatch',
          severity: AccountingIntegritySeverity.critical,
          entityType: 'account',
          entityId: accountId,
          difference: accountDifference,
          message:
              'Inventory account $accountId balance ($actual) does not match its Unified Batch/BOM classification value ($expected).',
        ));
      }
    }

    return (glBalance, valuation);
  }
}
