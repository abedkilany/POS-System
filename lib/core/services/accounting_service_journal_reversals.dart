part of 'accounting_service_impl.dart';

void _requireSalePostedSnapshotMatches(
  Sale sale, {
  required bool validatePaymentTotals,
}) {
  final snapshot = sale.postedSnapshot;
  if (snapshot == null) return;
  const tolerance = 0.000001;
  bool sameNumber(double left, double right) =>
      (left - right).abs() <= tolerance;
  Never mismatch(String reason) => throw StateError(
        'Sale posted snapshot does not match the current document ($reason). Rebuild the snapshot before accounting posting.',
      );

  if (snapshot.documentType != 'sale_invoice') mismatch('document type');
  if (snapshot.documentId.trim() != sale.id.trim()) mismatch('document id');
  if (snapshot.documentNumber.trim() != sale.invoiceNo.trim()) {
    mismatch('document number');
  }
  if (snapshot.party.id.trim() != sale.customerId.trim()) {
    mismatch('customer');
  }
  if (snapshot.warehouseId.trim() != sale.warehouseId.trim()) {
    mismatch('warehouse');
  }
  if (snapshot.lines.length != sale.items.length) mismatch('line count');
  for (var index = 0; index < sale.items.length; index += 1) {
    final item = sale.items[index];
    final line = snapshot.lines[index];
    if (line.lineId.trim() != '${sale.id}-line-$index' ||
        line.productId.trim() != item.productId.trim()) {
      mismatch('line identity at index $index');
    }
    if (!sameNumber(line.quantity, item.quantity) ||
        !sameNumber(line.baseQuantity, item.effectiveBaseQuantity) ||
        !sameNumber(line.conversionToBase, item.conversionToBase) ||
        !sameNumber(line.unitPrice, item.unitPrice) ||
        !sameNumber(line.lineTotal, item.lineTotal)) {
      mismatch('line values at index $index');
    }
  }
  if (!sameNumber(snapshot.totals.subtotal, sale.subtotal) ||
      !sameNumber(snapshot.totals.discount, sale.discount) ||
      !sameNumber(snapshot.totals.grandTotal, sale.total) ||
      !sameNumber(snapshot.totals.baseAmount, sale.baseAmount)) {
    mismatch('totals');
  }
  if (validatePaymentTotals) {
    final expectedPaid = sale.paidAmount.clamp(0, sale.invoiceTotal).toDouble();
    if (!sameNumber(snapshot.totals.paid, expectedPaid) ||
        !sameNumber(
          snapshot.totals.remaining,
          (sale.invoiceTotal - expectedPaid)
              .clamp(0, double.infinity)
              .toDouble(),
        )) {
      mismatch('payment totals');
    }
  }
}

void _requirePurchasePostedSnapshotMatches(
  Purchase purchase, {
  required bool validatePaymentTotals,
}) {
  final snapshot = purchase.postedSnapshot;
  if (snapshot == null) return;
  const tolerance = 0.000001;
  bool sameNumber(double left, double right) =>
      (left - right).abs() <= tolerance;
  Never mismatch(String reason) => throw StateError(
        'Purchase posted snapshot does not match the current document ($reason). Rebuild the snapshot before accounting posting.',
      );

  if (snapshot.documentType != 'purchase_invoice') {
    mismatch('document type');
  }
  if (snapshot.documentId.trim() != purchase.id.trim()) {
    mismatch('document id');
  }
  if (snapshot.documentNumber.trim() != purchase.purchaseNo.trim()) {
    mismatch('document number');
  }
  if (snapshot.party.id.trim() != purchase.supplierId.trim()) {
    mismatch('supplier');
  }
  if (snapshot.warehouseId.trim() != purchase.warehouseId.trim()) {
    mismatch('warehouse');
  }
  if (snapshot.lines.length != purchase.items.length) {
    mismatch('line count');
  }
  for (var index = 0; index < purchase.items.length; index += 1) {
    final item = purchase.items[index];
    final line = snapshot.lines[index];
    final expectedLineId = item.lineId.trim().isEmpty
        ? '${purchase.id}-line-$index'
        : item.lineId.trim();
    if (line.lineId.trim() != expectedLineId ||
        line.productId.trim() != item.productId.trim()) {
      mismatch('line identity at index $index');
    }
    if (!sameNumber(line.quantity, item.quantity) ||
        !sameNumber(line.baseQuantity, item.baseQuantity) ||
        !sameNumber(line.conversionToBase, item.conversionToBase) ||
        !sameNumber(line.unitPrice, item.unitCost) ||
        !sameNumber(line.lineTotal, item.lineTotal)) {
      mismatch('line values at index $index');
    }
  }
  if (!sameNumber(snapshot.totals.subtotal, purchase.subtotal) ||
      !sameNumber(snapshot.totals.grandTotal, purchase.subtotal) ||
      !sameNumber(snapshot.totals.baseAmount, purchase.subtotal)) {
    mismatch('totals');
  }
  if (validatePaymentTotals) {
    final expectedPaid =
        purchase.paidAmount.clamp(0, purchase.subtotal).toDouble();
    if (!sameNumber(snapshot.totals.paid, expectedPaid) ||
        !sameNumber(
          snapshot.totals.remaining,
          (purchase.subtotal - expectedPaid)
              .clamp(0, double.infinity)
              .toDouble(),
        )) {
      mismatch('payment totals');
    }
  }
}

Future<int> countPostedJournalEntriesForReferences({
  required String referenceType,
  required Iterable<String> referenceIds,
}) async {
  if (!isAvailable) return 0;
  final ids = referenceIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();
  final normalizedReferenceType = referenceType.trim();
  if (normalizedReferenceType.isEmpty || ids.isEmpty) return 0;
  final db = _db;
  final placeholders = List<String>.filled(ids.length, '?').join(', ');
  final row = await db.customSelect(
    '''
      SELECT COUNT(*) AS count
      FROM journal_entries
      WHERE deleted_at = '' AND status = 'posted'
        AND reference_type = ?
        AND reference_id IN ($placeholders)
      ''',
    variables: <Variable<Object>>[
      Variable<String>(normalizedReferenceType),
      ...ids.map((id) => Variable<String>(id)),
    ],
  ).getSingleOrNull();
  return row?.read<int>('count') ?? 0;
}

Future<int> countPostedSaleEntriesForSale(
  String saleId,
) async {
  if (!isAvailable) return 0;
  final normalizedSaleId = saleId.trim();
  if (normalizedSaleId.isEmpty) return 0;
  final row = await _db.customSelect(
    '''
      SELECT COUNT(*) AS count
      FROM journal_entries je
      WHERE reference_type = 'sale'
        AND (reference_id = ? OR instr(reference_id, ?) = 1)
        AND deleted_at = '' AND status = 'posted'
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries rev
          WHERE rev.reversed_entry_id = je.id
            AND rev.deleted_at = '' AND rev.status = 'posted'
        )
      ''',
    variables: <Variable<Object>>[
      Variable<String>(normalizedSaleId),
      Variable<String>('$normalizedSaleId:sale_edit:'),
    ],
  ).getSingleOrNull();
  return row?.read<int>('count') ?? 0;
}

Future<void> reverseSaleEntriesForSale({
  required String saleId,
  String reason = '',
  String createdBy = '',
  bool adjustCashLocationBalance = true,
  bool notifyChange = true,
  bool withinExistingTransaction = false,
}) async {
  if (!isAvailable) return;
  final normalizedSaleId = saleId.trim();
  if (normalizedSaleId.isEmpty) return;
  var remaining = await countPostedSaleEntriesForSale(normalizedSaleId);
  var reversedAny = false;
  var safetyCounter = 0;
  while (remaining > 0) {
    if (safetyCounter++ >= 100) {
      throw StateError(
          'Too many active sale journal entries for $normalizedSaleId.');
    }
    await reverseEntryForReference(
      referenceType: 'sale',
      referenceId: normalizedSaleId,
      reason: reason,
      createdBy: createdBy,
      adjustCashLocationBalance: adjustCashLocationBalance,
      notifyChange: false,
      withinExistingTransaction: withinExistingTransaction,
    );
    final next = await countPostedSaleEntriesForSale(normalizedSaleId);
    if (next >= remaining) {
      throw StateError(
          'Failed to reverse active sale journal for $normalizedSaleId.');
    }
    reversedAny = true;
    remaining = next;
  }
  if (notifyChange && reversedAny) _notifyMutation();
}

Future<int> countPostedPurchaseEntriesForPurchase(
  String purchaseId,
) async {
  if (!isAvailable) return 0;
  final normalizedPurchaseId = purchaseId.trim();
  if (normalizedPurchaseId.isEmpty) return 0;
  final row = await _db.customSelect(
    '''
      SELECT COUNT(*) AS count
      FROM journal_entries je
      WHERE reference_type = 'purchase'
        AND (reference_id = ? OR instr(reference_id, ?) = 1)
        AND deleted_at = '' AND status = 'posted'
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries rev
          WHERE rev.reversed_entry_id = je.id
            AND rev.deleted_at = '' AND rev.status = 'posted'
        )
      ''',
    variables: <Variable<Object>>[
      Variable<String>(normalizedPurchaseId),
      Variable<String>('$normalizedPurchaseId:purchase_edit:'),
    ],
  ).getSingleOrNull();
  return row?.read<int>('count') ?? 0;
}

Future<void> reversePurchaseEntriesForPurchase({
  required String purchaseId,
  String reason = '',
  String createdBy = '',
  bool adjustCashLocationBalance = true,
  bool notifyChange = true,
  bool withinExistingTransaction = false,
}) async {
  if (!isAvailable) return;
  final normalizedPurchaseId = purchaseId.trim();
  if (normalizedPurchaseId.isEmpty) return;
  var remaining =
      await countPostedPurchaseEntriesForPurchase(normalizedPurchaseId);
  var reversedAny = false;
  var safetyCounter = 0;
  while (remaining > 0) {
    if (safetyCounter++ >= 100) {
      throw StateError(
          'Too many active purchase journal entries for $normalizedPurchaseId.');
    }
    await reverseEntryForReference(
      referenceType: 'purchase',
      referenceId: normalizedPurchaseId,
      reason: reason,
      createdBy: createdBy,
      adjustCashLocationBalance: adjustCashLocationBalance,
      notifyChange: false,
      withinExistingTransaction: withinExistingTransaction,
    );
    final next =
        await countPostedPurchaseEntriesForPurchase(normalizedPurchaseId);
    if (next >= remaining) {
      throw StateError(
          'Failed to reverse active purchase journal for $normalizedPurchaseId.');
    }
    reversedAny = true;
    remaining = next;
  }
  if (notifyChange && reversedAny) _notifyMutation();
}

Future<void> reverseEntryForReference({
  required String referenceType,
  required String referenceId,
  String reason = '',
  String createdBy = '',
  bool adjustCashLocationBalance = true,
  bool notifyChange = true,
  bool withinExistingTransaction = false,
}) async {
  if (!isAvailable) return;
  final db = _db;
  if (referenceType.trim().isEmpty || referenceId.trim().isEmpty) return;
  final normalizedReferenceType = referenceType.trim();
  final normalizedReferenceId = referenceId.trim();
  // Posted document edits use versioned technical references. A later
  // edit/return/cancel must reverse the latest active member of that family.
  final editFamilyPrefix = normalizedReferenceType == 'purchase'
      ? '$normalizedReferenceId:purchase_edit:'
      : normalizedReferenceType == 'sale'
          ? '$normalizedReferenceId:sale_edit:'
          : normalizedReferenceType == 'receipt_voucher'
              ? '$normalizedReferenceId:receipt_edit:'
              : normalizedReferenceType == 'payment_voucher'
                  ? '$normalizedReferenceId:payment_edit:'
                  : normalizedReferenceType == 'expense'
                      ? '$normalizedReferenceId:expense_edit:'
                      : normalizedReferenceType == 'manual_journal'
                          ? '$normalizedReferenceId:manual_edit:'
                          : normalizedReferenceType == 'inventory_adjustment'
                              ? '$normalizedReferenceId:inventory_adjustment_edit:'
                              : normalizedReferenceType == 'sale_return'
                                  ? '$normalizedReferenceId:sale_return_edit:'
                                  : normalizedReferenceType ==
                                          'manufacturing_order'
                                      ? '$normalizedReferenceId:manufacturing_edit:'
                                      : '';
  final hasEditFamily = editFamilyPrefix.isNotEmpty;
  final entryRow = await db.customSelect(
    hasEditFamily
        ? '''
      SELECT id, entry_no, entry_date, reference_type, reference_id, reference_no,
             description, created_by, store_id, branch_id
      FROM journal_entries je
      WHERE reference_type = ?
        AND (reference_id = ? OR instr(reference_id, ?) = 1)
        AND deleted_at = '' AND status = 'posted'
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries rev
          WHERE rev.reversed_entry_id = je.id
            AND rev.deleted_at = '' AND rev.status = 'posted'
        )
      ORDER BY created_at DESC, entry_date DESC
      LIMIT 1
      '''
        : '''
      SELECT id, entry_no, entry_date, reference_type, reference_id, reference_no,
             description, created_by, store_id, branch_id
      FROM journal_entries je
      WHERE reference_type = ? AND reference_id = ?
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
      Variable<String>(normalizedReferenceType),
      Variable<String>(normalizedReferenceId),
      if (hasEditFamily) Variable<String>(editFamilyPrefix),
    ],
  ).getSingleOrNull();
  if (entryRow == null) return;

  final original = entryRow.data;
  final originalId = original['id']?.toString() ?? '';
  final alreadyReversed = await db.customSelect(
    '''
      SELECT id FROM journal_entries
      WHERE reversed_entry_id = ? AND deleted_at = '' AND status = 'posted'
      LIMIT 1
      ''',
    variables: <Variable<Object>>[Variable<String>(originalId)],
  ).getSingleOrNull();
  if (alreadyReversed != null) return;

  final lineRows = await db.customSelect(
    '''
      SELECT account_id, debit, credit, memo, party_type, party_id, party_name, cost_center_id
      FROM journal_lines
      WHERE entry_id = ?
      ORDER BY line_no
      ''',
    variables: <Variable<Object>>[Variable<String>(originalId)],
  ).get();
  if (lineRows.isEmpty) return;

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
  }).toList();
  _validateBalancedDraft(JournalEntryDraft(
    entryDate: DateTime.now(),
    description: 'تحقق العكس',
    lines: reversalLines,
  ));

  final now = DateTime.now().toUtc().toIso8601String();
  final reversalId = _newId('je');
  final entryNo = await _nextEntryNo(db, DateTime.now());
  final storeId = original['store_id']?.toString() ?? '';
  final branchId = original['branch_id']?.toString() ?? '';
  final actor = createdBy.trim().isNotEmpty
      ? createdBy.trim()
      : (original['created_by']?.toString() ?? '');
  final originalEntryNo = original['entry_no']?.toString() ?? '';
  final description = reason.trim().isEmpty
      ? 'عكس قيد اليومية $originalEntryNo'
      : 'عكس قيد اليومية $originalEntryNo: ${reason.trim()}';

  Future<void> persistReversal() async {
    final cashBalanceDeltas = <String, double>{};
    if (adjustCashLocationBalance) {
      for (final line in reversalLines) {
        final delta = line.debit - line.credit;
        if (delta.abs() < 0.01) continue;
        final cashLocations = await db.customSelect(
          '''
            SELECT id
            FROM cash_locations
            WHERE account_id = ? AND type = 'cash_drawer'
              AND deleted_at = '' AND is_active = 1
            ''',
          variables: <Variable<Object>>[
            Variable<String>(line.accountId),
          ],
        ).get();
        for (final location in cashLocations) {
          final locationId = location.data['id']?.toString() ?? '';
          if (locationId.isEmpty) continue;
          cashBalanceDeltas[locationId] =
              (cashBalanceDeltas[locationId] ?? 0) + delta;
        }
      }
      // Validate every resulting outflow before creating the reversal journal.
      // This keeps DENY mode atomic even for legacy callers that still ask
      // journal reversal code to repair operational cash balances.
      for (final entry in cashBalanceDeltas.entries) {
        if (entry.value < 0) {
          await ensureCashOutflowAllowed(
            cashLocationId: entry.key,
            amount: -entry.value,
            database: db,
          );
        }
      }
    }

    await db.customInsert(
      '''
        INSERT INTO journal_entries
          (id, entry_no, entry_date, reference_type, reference_id, reference_no,
           description, status, source, created_by, posted_at, reversed_entry_id,
           created_at, updated_at, store_id, branch_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'posted', 'reversal', ?, ?, ?, ?, ?, ?, ?)
        ''',
      variables: <Variable<Object>>[
        Variable<String>(reversalId),
        Variable<String>(entryNo),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
        Variable<String>('${referenceType}_reversal'),
        Variable<String>(referenceId),
        Variable<String>(original['reference_no']?.toString() ?? ''),
        Variable<String>(description),
        Variable<String>(actor),
        Variable<String>(now),
        Variable<String>(originalId),
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(storeId),
        Variable<String>(branchId),
      ],
    );

    for (var index = 0; index < reversalLines.length; index++) {
      final line = reversalLines[index];
      final account = await _accountSnapshot(db, line.accountId);
      await db.customInsert(
        '''
          INSERT INTO journal_lines
            (id, entry_id, line_no, account_id, account_code, account_name,
             debit, credit, memo, party_type, party_id, party_name, cost_center_id, created_at,
             updated_at, store_id, branch_id)
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
          Variable<String>(storeId),
          Variable<String>(branchId),
        ],
      );
    }
    // Legacy callers may still ask the journal reversal to repair the
    // operational cash balance. Phase 6 cash-event reversals set this to
    // false and let the immutable Cash Ledger reversal own that balance.
    if (adjustCashLocationBalance) {
      for (final entry in cashBalanceDeltas.entries) {
        if (entry.value.abs() < 0.01) continue;
        await applyCashLocationDelta(
          cashLocationId: entry.key,
          delta: entry.value,
          updatedAt: now,
          database: db,
        );
      }
    }
    await db.customUpdate(
      '''
        UPDATE journal_entries
        SET status = 'reversed', updated_at = ?, reversal_reason = ?,
            reversed_at = ?, reversed_by = ?, reversed_by_entry_id = ?
        WHERE id = ? AND status = 'posted'
        ''',
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(reason.trim()),
        Variable<String>(now),
        Variable<String>(actor),
        Variable<String>(reversalId),
        Variable<String>(originalId),
      ],
    );
    await _writeAuditLogInTransaction(
      db,
      action: 'reverse_entry',
      entityType: 'journal_entry',
      entityId: originalId,
      referenceType: referenceType,
      referenceId: referenceId,
      details: description,
      createdBy: actor,
      storeId: storeId,
      branchId: branchId,
      createdAt: now,
    );
  }

  if (withinExistingTransaction) {
    await persistReversal();
  } else {
    await db.transaction(persistReversal);
  }
  if (notifyChange) _notifyMutation();
}
