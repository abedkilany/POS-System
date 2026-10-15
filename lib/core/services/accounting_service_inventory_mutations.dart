part of 'accounting_service_impl.dart';

/// Reconciles provisional COGS created by an allowed negative-stock sale
/// when a later incoming batch provides the actual unit cost. The posted
/// sales invoice remains immutable; only COGS and inventory value are
/// corrected with a separate auditable journal entry.
Future<String> recordInventoryDeficitCostReconciliationInTransaction({
  required VentioDriftDatabase database,
  required String settlementId,
  required String productId,
  required String productName,
  required double quantity,
  required double provisionalUnitCost,
  required double actualUnitCost,
  required DateTime entryDate,
  String sourceReferenceId = '',
  String sourceReferenceNo = '',
  String createdBy = '',
  String storeId = '',
  String branchId = '',
}) async {
  if (quantity <= 0) return '';
  final difference = _roundMoney(
    quantity * (actualUnitCost - provisionalUnitCost),
  );
  if (difference.abs() <= 0.000001) return '';
  final cogsAccount = await _resolveAccountRoleForDatabase(database, 'cogs');
  final inventoryAccount =
      await _inventoryAccountForProduct(database, productId);
  final amount = difference.abs();
  final lines = difference > 0
      ? <JournalLineDraft>[
          JournalLineDraft(
            accountId: cogsAccount,
            debit: amount,
            credit: 0,
            memo: 'Negative-stock COGS reconciliation - $productName',
          ),
          JournalLineDraft(
            accountId: inventoryAccount,
            debit: 0,
            credit: amount,
            memo: 'Negative-stock inventory reconciliation - $productName',
          ),
        ]
      : <JournalLineDraft>[
          JournalLineDraft(
            accountId: inventoryAccount,
            debit: amount,
            credit: 0,
            memo: 'Negative-stock inventory reconciliation - $productName',
          ),
          JournalLineDraft(
            accountId: cogsAccount,
            debit: 0,
            credit: amount,
            memo: 'Negative-stock COGS reconciliation - $productName',
          ),
        ];
  return createPostedEntry(
    JournalEntryDraft(
      entryDate: entryDate,
      referenceType: 'inventory_deficit_cost_reconciliation',
      referenceId: settlementId,
      referenceNo: sourceReferenceNo.trim().isEmpty
          ? sourceReferenceId
          : sourceReferenceNo.trim(),
      description: 'Negative-stock cost reconciliation - $productName',
      source: 'system',
      createdBy: createdBy,
      storeId: storeId,
      branchId: branchId,
      lines: lines,
    ),
    database: database,
    withinExistingTransaction: true,
  );
}

/// Reconciles a provisional negative-stock cost for non-sale movements.
/// The difference is kept explicit as an inventory cost variance so the
/// inventory ledger remains aligned with the later actual incoming cost.
Future<String> recordInventoryDeficitCostVarianceInTransaction({
  required VentioDriftDatabase database,
  required String settlementId,
  required String productId,
  required String productName,
  required double quantity,
  required double provisionalUnitCost,
  required double actualUnitCost,
  required DateTime entryDate,
  String sourceReferenceId = '',
  String sourceReferenceNo = '',
  String sourceMovementType = '',
  String createdBy = '',
  String storeId = '',
  String branchId = '',
}) async {
  if (quantity <= 0) return '';
  final difference = _roundMoney(
    quantity * (actualUnitCost - provisionalUnitCost),
  );
  if (difference.abs() <= 0.000001) return '';
  final inventoryAccount =
      await _inventoryAccountForProduct(database, productId);
  final lossAccount =
      await _resolveAccountRoleForDatabase(database, 'inventory_count_loss');
  final gainAccount =
      await _resolveAccountRoleForDatabase(database, 'inventory_count_gain');
  final amount = difference.abs();
  final lines = difference > 0
      ? <JournalLineDraft>[
          JournalLineDraft(
            accountId: lossAccount,
            debit: amount,
            credit: 0,
            memo: 'Negative-stock cost variance - $productName',
          ),
          JournalLineDraft(
            accountId: inventoryAccount,
            debit: 0,
            credit: amount,
            memo: 'Negative-stock inventory cost variance - $productName',
          ),
        ]
      : <JournalLineDraft>[
          JournalLineDraft(
            accountId: inventoryAccount,
            debit: amount,
            credit: 0,
            memo: 'Negative-stock inventory cost variance - $productName',
          ),
          JournalLineDraft(
            accountId: gainAccount,
            debit: 0,
            credit: amount,
            memo: 'Negative-stock cost variance - $productName',
          ),
        ];
  return createPostedEntry(
    JournalEntryDraft(
      entryDate: entryDate,
      referenceType: 'inventory_deficit_cost_variance',
      referenceId: settlementId,
      referenceNo: sourceReferenceNo.trim().isEmpty
          ? sourceReferenceId
          : sourceReferenceNo.trim(),
      description:
          'Negative-stock cost variance (${sourceMovementType.trim().isEmpty ? 'stock' : sourceMovementType}) - $productName',
      source: 'system',
      createdBy: createdBy,
      storeId: storeId,
      branchId: branchId,
      lines: lines,
    ),
    database: database,
    withinExistingTransaction: true,
  );
}

/// Revalues an already-existing physical Batch when its persisted carrying
/// cost is missing/zero but a positive reference cost can be proven. No
/// quantity changes here: only the inventory asset value changes. This is
/// intentionally separate from manufacturing so the raw-to-finished transfer
/// remains value-neutral after the repair.
Future<String> recordInventoryBatchRevaluationInTransaction({
  required VentioDriftDatabase database,
  required DateTime entryDate,
  required String referenceId,
  required String referenceNo,
  required String productId,
  required String productName,
  required String batchId,
  required double valueDelta,
  String createdBy = '',
  String storeId = '',
  String branchId = '',
  String reason = '',
}) async {
  final roundedDelta = _roundMoney(valueDelta);
  if (roundedDelta.abs() <= 0.000001) return '';
  final inventoryAccount =
      await _inventoryAccountForProduct(database, productId);
  final lines = <JournalLineDraft>[];
  if (roundedDelta > 0) {
    final gainAccount =
        await _resolveAccountRoleForDatabase(database, 'inventory_count_gain');
    lines
      ..add(JournalLineDraft(
        accountId: inventoryAccount,
        debit: roundedDelta,
        credit: 0.0,
        memo: 'Batch cost revaluation - $productName ($batchId)',
      ))
      ..add(JournalLineDraft(
        accountId: gainAccount,
        debit: 0.0,
        credit: roundedDelta,
        memo: 'Batch cost revaluation gain - $productName ($batchId)',
      ));
  } else {
    final lossAccount =
        await _resolveAccountRoleForDatabase(database, 'inventory_count_loss');
    final amount = roundedDelta.abs();
    lines
      ..add(JournalLineDraft(
        accountId: lossAccount,
        debit: amount,
        credit: 0.0,
        memo: 'Batch cost revaluation loss - $productName ($batchId)',
      ))
      ..add(JournalLineDraft(
        accountId: inventoryAccount,
        debit: 0.0,
        credit: amount,
        memo: 'Batch cost revaluation - $productName ($batchId)',
      ));
  }
  return createPostedEntry(
    JournalEntryDraft(
      entryDate: entryDate,
      referenceType: 'inventory_batch_revaluation',
      referenceId: referenceId,
      referenceNo: referenceNo,
      description: reason.trim().isEmpty
          ? 'Inventory Batch cost revaluation - $productName'
          : reason.trim(),
      source: 'system',
      createdBy: createdBy,
      storeId: storeId,
      branchId: branchId,
      lines: lines,
    ),
    database: database,
    withinExistingTransaction: true,
  );
}

/// Posts the financial side of a manual stock adjustment. The caller owns
/// the SQLite transaction together with stock/cost-layer mutations.
Future<String> recordManualInventoryAdjustmentInTransaction({
  required VentioDriftDatabase database,
  required DateTime entryDate,
  required String referenceId,
  required String referenceNo,
  required String productId,
  required String productName,
  required double quantityDelta,
  required double value,
  String adjustmentCategory = 'other',
  String reason = '',
  String createdBy = '',
  String storeId = '',
  String branchId = '',
}) async {
  final amount = _roundMoney(value.abs());
  if (amount <= 0 || quantityDelta == 0) return '';
  final inventoryAccount =
      await _inventoryAccountForProduct(database, productId);
  final category = adjustmentCategory.trim().toLowerCase();
  final lines = <JournalLineDraft>[];
  if (quantityDelta > 0) {
    final gainAccount =
        await _resolveAccountRoleForDatabase(database, 'inventory_count_gain');
    lines
      ..add(JournalLineDraft(
        accountId: inventoryAccount,
        debit: amount,
        credit: 0,
        memo: 'Manual inventory increase - $productName',
      ))
      ..add(JournalLineDraft(
        accountId: gainAccount,
        debit: 0,
        credit: amount,
        memo: 'Manual inventory increase - $productName',
      ));
  } else {
    final lossRole = switch (category) {
      'expired' || 'expiry' => 'inventory_expiry',
      'damage' => 'inventory_damage',
      'weight' || 'weight_variance' => 'inventory_weight_variance',
      'free_sample' => 'marketing_expense',
      'internal_consumption' => 'general_expense',
      _ => 'inventory_count_loss',
    };
    final lossAccount =
        await _resolveAccountRoleForDatabase(database, lossRole);
    lines
      ..add(JournalLineDraft(
        accountId: lossAccount,
        debit: amount,
        credit: 0,
        memo: 'Manual inventory decrease - $productName',
      ))
      ..add(JournalLineDraft(
        accountId: inventoryAccount,
        debit: 0,
        credit: amount,
        memo: 'Manual inventory decrease - $productName',
      ));
  }
  return createPostedEntry(
    JournalEntryDraft(
      entryDate: entryDate,
      referenceType: 'inventory_adjustment',
      referenceId: referenceId,
      referenceNo: referenceNo,
      description: reason.trim().isEmpty
          ? 'Manual inventory adjustment - $productName'
          : reason.trim(),
      source: 'system',
      createdBy: createdBy,
      storeId: storeId,
      branchId: branchId,
      lines: lines,
    ),
    database: database,
    withinExistingTransaction: true,
  );
}

Future<String> recordInventoryWaste({
  required DateTime entryDate,
  required String referenceId,
  required String referenceNo,
  required double amount,
  required String productName,
  String productId = '',
  String createdBy = '',
  String storeId = '',
  String branchId = '',
  String notes = '',
  String expenseRoleKey = 'inventory_damage',
  VentioDriftDatabase? database,
  bool withinExistingTransaction = false,
}) async {
  if (database == null && !isAvailable) return '';
  final db = database ?? _db;
  final cleanAmount = _roundMoney(amount);
  if (cleanAmount <= 0) return '';
  final wasteAccount = await _resolveAccountRoleForDatabase(db, expenseRoleKey);
  final inventoryAccount = productId.trim().isEmpty
      ? await _resolveAccountRoleForDatabase(db, 'inventory_asset')
      : await _inventoryAccountForProduct(db, productId);
  final entryId = await createPostedEntry(
      JournalEntryDraft(
        entryDate: entryDate,
        referenceType: 'inventory_waste',
        referenceId: referenceId,
        referenceNo: referenceNo,
        description: notes.trim().isEmpty
            ? 'هدر وخسارة مخزون - $productName'
            : notes.trim(),
        // journal_entries.source is constrained to system/manual/import/reversal.
        // Keep the business meaning in referenceType and use the valid system source.
        source: 'system',
        createdBy: createdBy,
        storeId: storeId,
        branchId: branchId,
        lines: <JournalLineDraft>[
          JournalLineDraft(
            accountId: wasteAccount,
            debit: cleanAmount,
            credit: 0,
            memo: 'مصروف هدر وخسارة - $productName',
          ),
          JournalLineDraft(
            accountId: inventoryAccount,
            debit: 0,
            credit: cleanAmount,
            memo: 'إخراج مخزون بسبب هدر - $productName',
          ),
        ],
      ),
      database: db,
      withinExistingTransaction: withinExistingTransaction);
  if (entryId.isNotEmpty) _notifyMutation();
  return entryId;
}

/// Posts the complete Raw Materials -> WIP -> Finished Goods flow using the
/// immutable costs captured on [order]. This must be called from the same
/// SQLite transaction as the manufacturing stock movements and order row.
Future<String> recordManufacturingCompletionInTransaction({
  required VentioDriftDatabase database,
  required ManufacturingOrder order,
  String technicalReferenceId = '',
}) async {
  if (order.totalMaterialCost <= 0 || order.totalEligibleCost < 0) {
    throw ArgumentError('Manufacturing cost snapshot is invalid.');
  }
  final rawInventory =
      await _resolveAccountRoleForDatabase(database, 'inventory_raw');
  final wipInventory =
      await _resolveAccountRoleForDatabase(database, 'inventory_wip');
  final finishedInventory =
      await _resolveAccountRoleForDatabase(database, 'inventory_finished');
  final wasteAccount = order.totalWasteCost > 0
      ? await _resolveAccountRoleForDatabase(database, 'manufacturing_waste')
      : '';
  final materialCost = _roundMoney(order.totalMaterialCost);
  final wasteCost = _roundMoney(order.totalWasteCost);
  final eligibleCost = _roundMoney(order.totalEligibleCost);
  if ((materialCost - wasteCost - eligibleCost).abs() > 0.0001) {
    throw ArgumentError(
        'Manufacturing material, waste, and eligible costs do not reconcile.');
  }
  // A manufactured intermediate (mix/sub-assembly) carries its historic
  // finished-goods cost into the next order. Only genuine raw inputs credit
  // Raw Materials; this keeps chained BOMs from expensing or counting the
  // same cost twice.
  var rawMaterialCost = 0.0;
  var intermediateMaterialCost = 0.0;
  for (final material in order.materialCosts) {
    final manufactured = await database.customSelect('''
        SELECT 1
        FROM bill_of_materials
        WHERE output_product_id = ?
          AND is_active = 1
          AND deleted_at = ''
        LIMIT 1
      ''', variables: <Variable<Object>>[
      Variable<String>(material.productId),
    ]).getSingleOrNull();
    if (manufactured == null) {
      rawMaterialCost += material.totalCost;
    } else {
      intermediateMaterialCost += material.totalCost;
    }
  }
  rawMaterialCost = _roundMoney(rawMaterialCost);
  intermediateMaterialCost = _roundMoney(intermediateMaterialCost);
  if ((rawMaterialCost + intermediateMaterialCost - materialCost).abs() >
      0.0001) {
    throw ArgumentError(
        'Manufacturing component account allocation does not reconcile.');
  }
  final lines = <JournalLineDraft>[
    JournalLineDraft(
      accountId: wipInventory,
      debit: materialCost,
      credit: 0,
      memo: 'Actual materials consumed by ${order.orderNo}',
    ),
    if (rawMaterialCost > 0)
      JournalLineDraft(
        accountId: rawInventory,
        debit: 0,
        credit: rawMaterialCost,
        memo: 'Raw materials issued to ${order.orderNo}',
      ),
    if (intermediateMaterialCost > 0)
      JournalLineDraft(
        accountId: finishedInventory,
        debit: 0,
        credit: intermediateMaterialCost,
        memo: 'Intermediate goods issued to ${order.orderNo}',
      ),
    if (wasteCost > 0) ...<JournalLineDraft>[
      JournalLineDraft(
        accountId: wasteAccount,
        debit: wasteCost,
        credit: 0,
        memo: 'Manufacturing waste for ${order.orderNo}',
      ),
      JournalLineDraft(
        accountId: wipInventory,
        debit: 0,
        credit: wasteCost,
        memo: 'WIP released as waste for ${order.orderNo}',
      ),
    ],
    if (eligibleCost > 0) ...<JournalLineDraft>[
      JournalLineDraft(
        accountId: finishedInventory,
        debit: eligibleCost,
        credit: 0,
        memo: 'Finished goods accepted from ${order.orderNo}',
      ),
      JournalLineDraft(
        accountId: wipInventory,
        debit: 0,
        credit: eligibleCost,
        memo: 'WIP completed by ${order.orderNo}',
      ),
    ],
  ];
  final postedReferenceId = technicalReferenceId.trim().isEmpty
      ? order.id
      : technicalReferenceId.trim();
  return createPostedEntry(
    JournalEntryDraft(
      entryDate: order.completedAt ?? order.date,
      referenceType: 'manufacturing_order',
      referenceId: postedReferenceId,
      referenceNo: order.orderNo,
      description: 'Manufacturing completion ${order.orderNo}',
      source: 'system',
      createdBy: order.completedBy,
      storeId: order.storeId,
      branchId: order.branchId,
      lines: lines,
    ),
    database: database,
    withinExistingTransaction: true,
  );
}

/// Posts the accounting effect of an approved stock count.
///
/// A shortage debits the dedicated inventory-count loss account and credits
/// inventory. An overage debits inventory and credits the dedicated gain
/// account. Keeping the whole count in one journal preserves both sides of
/// the count instead of netting away the audit detail.
Future<String> recordInventoryCountAdjustment({
  required DateTime entryDate,
  required String referenceId,
  required String referenceNo,
  required List<InventoryCountVariance> variances,
  String createdBy = '',
  String storeId = '',
  String branchId = '',
  String notes = '',
  VentioDriftDatabase? database,
  bool withinExistingTransaction = false,
}) async {
  if (variances.isEmpty || (database == null && !isAvailable)) return '';
  final db = database ?? _db;
  final lossAccount =
      await _resolveAccountRoleForDatabase(db, 'inventory_count_loss');
  final gainAccount =
      await _resolveAccountRoleForDatabase(db, 'inventory_count_gain');

  final lines = <JournalLineDraft>[];
  var totalVariance = 0.0;
  for (final variance in variances) {
    final amount = _roundMoney(variance.amount.abs());
    if (amount <= 0) continue;
    final inventoryAccount = variance.productId.trim().isEmpty
        ? await _resolveAccountRoleForDatabase(db, 'inventory_asset')
        : await _inventoryAccountForProduct(db, variance.productId);
    totalVariance += amount;
    final isShortage = variance.delta < 0;
    final memo = isShortage
        ? 'عجز جرد مخزون ${variance.productName}'
        : 'زيادة جرد مخزون ${variance.productName}';
    if (isShortage) {
      lines
        ..add(JournalLineDraft(
          accountId: lossAccount,
          debit: amount,
          credit: 0,
          memo: memo,
        ))
        ..add(JournalLineDraft(
          accountId: inventoryAccount,
          debit: 0,
          credit: amount,
          memo: memo,
        ));
    } else {
      lines
        ..add(JournalLineDraft(
          accountId: inventoryAccount,
          debit: amount,
          credit: 0,
          memo: memo,
        ))
        ..add(JournalLineDraft(
          accountId: gainAccount,
          debit: 0,
          credit: amount,
          memo: memo,
        ));
    }
  }
  if (totalVariance <= 0 || lines.isEmpty) return '';

  final entryId = await createPostedEntry(
    JournalEntryDraft(
      entryDate: entryDate,
      referenceType: 'inventory_count',
      referenceId: referenceId,
      referenceNo: referenceNo,
      description: notes.trim().isEmpty
          ? 'تسوية فروقات جرد المخزون $referenceNo'
          : notes.trim(),
      source: 'system',
      createdBy: createdBy,
      storeId: storeId,
      branchId: branchId,
      lines: lines,
    ),
    database: db,
    withinExistingTransaction: withinExistingTransaction,
  );
  if (entryId.isNotEmpty && !withinExistingTransaction) _notifyMutation();
  return entryId;
}

/// Reverses the posted journal for an approved inventory count. The caller
/// owns the SQLite transaction so accounting, stock and count status are
/// reversed atomically.
Future<String> reverseInventoryCountAdjustmentInTransaction({
  required VentioDriftDatabase database,
  required String referenceId,
  String reason = '',
  String createdBy = '',
}) async {
  final normalizedReferenceId = referenceId.trim();
  if (normalizedReferenceId.isEmpty) return '';
  final originalRow = await database.customSelect(
    '''
      SELECT id, entry_no, reference_no, created_by, store_id, branch_id
      FROM journal_entries je
      WHERE reference_type = 'inventory_count' AND reference_id = ?
        AND deleted_at = '' AND status = 'posted'
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries rev
          WHERE rev.reversed_entry_id = je.id
            AND rev.deleted_at = '' AND rev.status = 'posted'
        )
      ORDER BY created_at DESC, entry_date DESC
      LIMIT 1
      ''',
    variables: <Variable<Object>>[
      Variable<String>(normalizedReferenceId),
    ],
  ).getSingleOrNull();
  if (originalRow == null) {
    final existing = await database.customSelect(
      '''
        SELECT rev.id
        FROM journal_entries rev
        JOIN journal_entries orig ON orig.id = rev.reversed_entry_id
        WHERE orig.reference_type = 'inventory_count'
          AND orig.reference_id = ?
          AND rev.deleted_at = '' AND rev.status = 'posted'
        ORDER BY rev.created_at DESC
        LIMIT 1
        ''',
      variables: <Variable<Object>>[
        Variable<String>(normalizedReferenceId),
      ],
    ).getSingleOrNull();
    return existing?.data['id']?.toString() ?? '';
  }

  final original = originalRow.data;
  final originalId = original['id']?.toString() ?? '';
  final lineRows = await database.customSelect(
    '''
      SELECT account_id, debit, credit, memo, party_type, party_id,
             party_name, cost_center_id
      FROM journal_lines
      WHERE entry_id = ?
      ORDER BY line_no
      ''',
    variables: <Variable<Object>>[Variable<String>(originalId)],
  ).get();
  if (lineRows.isEmpty) return '';
  final reversalLines = lineRows.map((row) {
    final data = row.data;
    return JournalLineDraft(
      accountId: data['account_id']?.toString() ?? '',
      debit: _cleanAmount(_num(data['credit'])),
      credit: _cleanAmount(_num(data['debit'])),
      memo: 'عكس: ${data['memo']?.toString() ?? ''}',
      partyType: data['party_type']?.toString() ?? '',
      partyId: data['party_id']?.toString() ?? '',
      partyName: data['party_name']?.toString() ?? '',
      costCenterId: data['cost_center_id']?.toString() ?? '',
    );
  }).toList(growable: false);
  _validateBalancedDraft(JournalEntryDraft(
    entryDate: DateTime.now(),
    description: 'تحقق عكس الجرد',
    lines: reversalLines,
  ));

  final nowDate = DateTime.now().toUtc();
  final now = nowDate.toIso8601String();
  await _assertDateNotInClosedPeriod(
    nowDate,
    original['branch_id']?.toString() ?? '',
    database: database,
  );
  final reversalId = _newId('je');
  final entryNo = await _nextEntryNo(database, nowDate);
  final actor = createdBy.trim().isNotEmpty
      ? createdBy.trim()
      : (original['created_by']?.toString() ?? '');
  final originalEntryNo = original['entry_no']?.toString() ?? '';
  final description = reason.trim().isEmpty
      ? 'عكس جرد المخزون $originalEntryNo'
      : 'عكس جرد المخزون $originalEntryNo: ${reason.trim()}';

  await database.customInsert(
    '''
      INSERT INTO journal_entries
        (id, entry_no, entry_date, reference_type, reference_id, reference_no,
         description, status, source, created_by, posted_at, reversed_entry_id,
         created_at, updated_at, store_id, branch_id)
      VALUES (?, ?, ?, 'inventory_count_reversal', ?, ?, ?, 'posted',
              'reversal', ?, ?, ?, ?, ?, ?, ?)
      ''',
    variables: <Variable<Object>>[
      Variable<String>(reversalId),
      Variable<String>(entryNo),
      Variable<String>(now),
      Variable<String>(normalizedReferenceId),
      Variable<String>(original['reference_no']?.toString() ?? ''),
      Variable<String>(description),
      Variable<String>(actor),
      Variable<String>(now),
      Variable<String>(originalId),
      Variable<String>(now),
      Variable<String>(now),
      Variable<String>(original['store_id']?.toString() ?? ''),
      Variable<String>(original['branch_id']?.toString() ?? ''),
    ],
  );
  for (var index = 0; index < reversalLines.length; index++) {
    final line = reversalLines[index];
    final account = await _accountSnapshot(database, line.accountId);
    await database.customInsert(
      '''
        INSERT INTO journal_lines
          (id, entry_id, line_no, account_id, account_code, account_name,
           debit, credit, memo, party_type, party_id, party_name,
           cost_center_id, created_at, updated_at, store_id, branch_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
      variables: <Variable<Object>>[
        Variable<String>(_newId('jl')),
        Variable<String>(reversalId),
        Variable<int>(index + 1),
        Variable<String>(line.accountId),
        Variable<String>(account.code),
        Variable<String>(account.name),
        Variable<double>(_cleanAmount(line.debit)),
        Variable<double>(_cleanAmount(line.credit)),
        Variable<String>(line.memo),
        Variable<String>(line.partyType),
        Variable<String>(line.partyId),
        Variable<String>(line.partyName),
        Variable<String>(line.costCenterId),
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(original['store_id']?.toString() ?? ''),
        Variable<String>(original['branch_id']?.toString() ?? ''),
      ],
    );
  }
  await _writeAuditLogInTransaction(
    database,
    action: 'reverse_inventory_count',
    entityType: 'journal_entry',
    entityId: reversalId,
    referenceType: 'inventory_count',
    referenceId: normalizedReferenceId,
    details: description,
    createdBy: actor,
    storeId: original['store_id']?.toString() ?? '',
    branchId: original['branch_id']?.toString() ?? '',
    createdAt: now,
  );
  return reversalId;
}
