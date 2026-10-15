part of 'accounting_production_integrity_service.dart';

extension AccountingProductionIntegrityServiceSplitPart1 on AccountingProductionIntegrityService {
  Future<AccountingProductionIntegrityReport> audit() async {
    final issues = <AccountingIntegrityIssue>[];

    await _checkJournalStructure(issues);
    await _checkJournalReferences(issues);
    await _checkPostedEditFamilyUniqueness(issues);
    await _checkVoucherAndControlIntegrity(issues);
    await _checkDocumentPosting(issues);
    await _checkExpensePosting(issues);
    await _checkManufacturingAndCounts(issues);
    await _checkStockReversalLinks(issues);
    await _checkCostingMethodHistory(issues);
    await _checkUnifiedBatchState(issues);

    final reconciliation = await _inventoryReconciliation(issues);

    return AccountingProductionIntegrityReport(
      generatedAt: DateTime.now().toUtc(),
      issues: List<AccountingIntegrityIssue>.unmodifiable(issues),
      inventoryGlBalance: reconciliation.$1,
      inventoryValuation: reconciliation.$2,
    );
  }

  Future<void> _checkJournalStructure(
      List<AccountingIntegrityIssue> issues) async {
    final unbalanced = await _db.customSelect(r'''
      SELECT je.id, je.entry_no,
             COALESCE(SUM(jl.debit), 0) AS debits,
             COALESCE(SUM(jl.credit), 0) AS credits
      FROM journal_entries je
      LEFT JOIN journal_lines jl ON jl.entry_id = je.id
      WHERE je.deleted_at = '' AND je.status IN ('posted', 'reversed')
      GROUP BY je.id, je.entry_no
      HAVING COUNT(jl.id) = 0
         OR ABS(COALESCE(SUM(jl.debit), 0) - COALESCE(SUM(jl.credit), 0)) > 0.005
         OR COALESCE(SUM(jl.debit), 0) <= 0
    ''').get();
    for (final row in unbalanced) {
      final debit = AccountingProductionIntegrityService._num(row.data['debits']);
      final credit = AccountingProductionIntegrityService._num(row.data['credits']);
      issues.add(AccountingIntegrityIssue(
        code: 'unbalanced_or_empty_journal',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'journal_entry',
        entityId: row.data['id']?.toString() ?? '',
        difference: AccountingProductionIntegrityService._round(debit - credit),
        message:
            'Posted/reversed journal ${row.data['entry_no'] ?? ''} is empty or unbalanced.',
      ));
    }

    final orphanLines = await _db.customSelect(r'''
      SELECT jl.id, jl.entry_id
      FROM journal_lines jl
      LEFT JOIN journal_entries je ON je.id = jl.entry_id
      WHERE je.id IS NULL
    ''').get();
    for (final row in orphanLines) {
      issues.add(AccountingIntegrityIssue(
        code: 'orphan_journal_line',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'journal_line',
        entityId: row.data['id']?.toString() ?? '',
        message:
            'Journal line references missing entry ${row.data['entry_id'] ?? ''}.',
      ));
    }

    final missingAccounts = await _db.customSelect(r'''
      SELECT DISTINCT jl.account_id
      FROM journal_lines jl
      LEFT JOIN accounts a ON a.id = jl.account_id
      WHERE a.id IS NULL
    ''').get();
    for (final row in missingAccounts) {
      issues.add(AccountingIntegrityIssue(
        code: 'journal_account_missing',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'account',
        entityId: row.data['account_id']?.toString() ?? '',
        message: 'A journal line references an account that does not exist.',
      ));
    }
  }

  Future<void> _checkJournalReferences(
      List<AccountingIntegrityIssue> issues) async {
    final duplicateActive = await _db.customSelect(r'''
      SELECT je.reference_type, je.reference_id, COUNT(*) AS count
      FROM journal_entries je
      WHERE je.deleted_at = ''
        AND je.status = 'posted'
        AND trim(je.reference_type) <> ''
        AND trim(je.reference_id) <> ''
        AND NOT EXISTS (
          SELECT 1
          FROM journal_entries reversal
          WHERE reversal.reversed_entry_id = je.id
            AND reversal.deleted_at = ''
            AND reversal.status = 'posted'
        )
        AND je.reference_type IN (
          'sale', 'sale_return', 'purchase', 'receipt_voucher',
          'payment_voucher', 'inventory_waste', 'inventory_adjustment',
          'inventory_count', 'manufacturing_order'
        )
      GROUP BY je.reference_type, je.reference_id
      HAVING COUNT(*) > 1
    ''').get();
    for (final row in duplicateActive) {
      issues.add(AccountingIntegrityIssue(
        code: 'duplicate_active_posting',
        severity: AccountingIntegritySeverity.critical,
        entityType: row.data['reference_type']?.toString() ?? '',
        entityId: row.data['reference_id']?.toString() ?? '',
        message:
            'More than one active posted journal exists for the same accounting reference.',
      ));
    }
  }

  Future<void> _checkPostedEditFamilyUniqueness(
      List<AccountingIntegrityIssue> issues) async {
    final rows = await _db.customSelect(r'''
      SELECT je.id, je.reference_type, je.reference_id
      FROM journal_entries je
      WHERE je.deleted_at = '' AND je.status = 'posted'
        AND je.reference_type IN (
          'sale', 'sale_return', 'purchase', 'receipt_voucher',
          'payment_voucher', 'expense', 'manual_journal',
          'inventory_adjustment', 'manufacturing_order'
        )
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries rev
          WHERE rev.reversed_entry_id = je.id
            AND rev.deleted_at = '' AND rev.status = 'posted'
        )
    ''').get();

    const markers = <String, String>{
      'sale': ':sale_edit:',
      'sale_return': ':sale_return_edit:',
      'purchase': ':purchase_edit:',
      'receipt_voucher': ':receipt_edit:',
      'payment_voucher': ':payment_edit:',
      'expense': ':expense_edit:',
      'manual_journal': ':manual_edit:',
      'inventory_adjustment': ':inventory_adjustment_edit:',
      'manufacturing_order': ':manufacturing_edit:',
    };
    final activeByFamily = <String, List<String>>{};
    for (final row in rows) {
      final type = row.data['reference_type']?.toString() ?? '';
      final referenceId = row.data['reference_id']?.toString() ?? '';
      final marker = markers[type];
      if (marker == null || referenceId.trim().isEmpty) continue;
      final markerIndex = referenceId.indexOf(marker);
      final familyId = markerIndex > 0
          ? referenceId.substring(0, markerIndex)
          : referenceId;
      final key = '$type|$familyId';
      activeByFamily.putIfAbsent(key, () => <String>[]).add(
            row.data['id']?.toString() ?? '',
          );
    }
    for (final entry in activeByFamily.entries) {
      if (entry.value.length <= 1) continue;
      final separator = entry.key.indexOf('|');
      final type = entry.key.substring(0, separator);
      final familyId = entry.key.substring(separator + 1);
      issues.add(AccountingIntegrityIssue(
        code: 'duplicate_active_posted_edit_family',
        severity: AccountingIntegritySeverity.critical,
        entityType: type,
        entityId: familyId,
        message:
            'More than one active journal exists for the same posted-document edit family.',
      ));
    }
  }

  Future<void> _checkVoucherAndControlIntegrity(
      List<AccountingIntegrityIssue> issues) async {
    for (final spec in const <(String, String, String, String)>[
      ('receipt_vouchers', 'receipt', 'receipt_voucher', 'customer'),
      ('payment_vouchers', 'payment', 'payment_voucher', 'supplier'),
    ]) {
      final voucherTable = spec.$1;
      final voucherType = spec.$2;
      final referenceType = spec.$3;
      final partyType = spec.$4;
      final editFamilyMarker =
          voucherType == 'receipt' ? ':receipt_edit:' : ':payment_edit:';

      final missingJournal = await _db.customSelect(
        '''
        SELECT v.id, v.voucher_no
        FROM $voucherTable v
        WHERE v.deleted_at = '' AND v.status = 'posted'
          AND NOT EXISTS (
            SELECT 1 FROM journal_entries je
            WHERE je.reference_type = ?
              AND (je.reference_id = v.id
                   OR instr(je.reference_id, v.id || ?) = 1)
              AND je.deleted_at = '' AND je.status = 'posted'
              AND NOT EXISTS (
                SELECT 1 FROM journal_entries rev
                WHERE rev.reversed_entry_id = je.id
                  AND rev.deleted_at = '' AND rev.status = 'posted'
              )
          )
        ''',
        variables: <Variable<Object>>[
          Variable<String>(referenceType),
          Variable<String>(editFamilyMarker),
        ],
      ).get();
      for (final row in missingJournal) {
        issues.add(AccountingIntegrityIssue(
          code: 'posted_voucher_missing_journal',
          severity: AccountingIntegritySeverity.critical,
          entityType: referenceType,
          entityId: row.data['id']?.toString() ?? '',
          message:
              'Posted $voucherType voucher ${row.data['voucher_no'] ?? ''} has no active journal.',
        ));
      }

      final missingCashLedger = await _db.customSelect(
        '''
        SELECT v.id, v.voucher_no
        FROM $voucherTable v
        WHERE v.deleted_at = '' AND v.status = 'posted'
          AND lower(trim(v.payment_method)) = 'cash'
          AND NOT EXISTS (
            SELECT 1 FROM cash_ledger_transactions clt
            WHERE clt.reference_type = ?
              AND (clt.reference_id = v.id
                   OR instr(clt.reference_id, v.id || ?) = 1)
              AND clt.deleted_at = ''
              AND NOT EXISTS (
                SELECT 1 FROM cash_ledger_transactions reversal
                WHERE reversal.reversal_of_id = clt.id
                  AND reversal.deleted_at = ''
              )
          )
        ''',
        variables: <Variable<Object>>[
          Variable<String>(referenceType),
          Variable<String>(editFamilyMarker),
        ],
      ).get();
      for (final row in missingCashLedger) {
        issues.add(AccountingIntegrityIssue(
          code: 'cash_voucher_missing_cash_ledger',
          severity: AccountingIntegritySeverity.critical,
          entityType: referenceType,
          entityId: row.data['id']?.toString() ?? '',
          message:
              'Posted cash $voucherType voucher ${row.data['voucher_no'] ?? ''} has no active Cash Ledger movement.',
        ));
      }

      final allocationMismatch = await _db.customSelect(
        '''
        SELECT v.id, v.voucher_no, v.amount, v.unallocated_amount,
               COALESCE(SUM(
                 CASE
                   WHEN pa.status = 'active' AND pa.deleted_at = ''
                     THEN CASE WHEN pa.allocation_kind = 'reversal'
                               THEN -pa.amount ELSE pa.amount END
                   ELSE 0
                 END
               ), 0) AS allocated,
               COALESCE((
                 SELECT SUM(cra.amount)
                 FROM cash_refund_allocations cra
                 WHERE cra.voucher_type = ?
                   AND cra.voucher_id = v.id
                   AND cra.deleted_at = ''
               ), 0) AS refunded
        FROM $voucherTable v
        LEFT JOIN payment_allocations pa
          ON pa.voucher_type = ? AND pa.voucher_id = v.id
        WHERE v.deleted_at = '' AND v.status = 'posted'
        GROUP BY v.id, v.voucher_no, v.amount, v.unallocated_amount
        HAVING ABS(
          (v.amount - COALESCE((
            SELECT SUM(cra.amount)
            FROM cash_refund_allocations cra
            WHERE cra.voucher_type = ?
              AND cra.voucher_id = v.id
              AND cra.deleted_at = ''
          ), 0))
          - (v.unallocated_amount + COALESCE(SUM(
            CASE
              WHEN pa.status = 'active' AND pa.deleted_at = ''
                THEN CASE WHEN pa.allocation_kind = 'reversal'
                          THEN -pa.amount ELSE pa.amount END
              ELSE 0
            END
          ), 0))
        ) > 0.005
        ''',
        variables: <Variable<Object>>[
          Variable<String>(voucherType),
          Variable<String>(voucherType),
          Variable<String>(voucherType),
        ],
      ).get();
      for (final row in allocationMismatch) {
        final amount = AccountingProductionIntegrityService._num(row.data['amount']);
        final refunded = AccountingProductionIntegrityService._num(row.data['refunded']);
        final allocated = AccountingProductionIntegrityService._num(row.data['allocated']);
        final unallocated = AccountingProductionIntegrityService._num(row.data['unallocated_amount']);
        issues.add(AccountingIntegrityIssue(
          code: 'voucher_allocation_refund_mismatch',
          severity: AccountingIntegritySeverity.critical,
          entityType: referenceType,
          entityId: row.data['id']?.toString() ?? '',
          difference: AccountingProductionIntegrityService._round((amount - refunded) - allocated - unallocated),
          message:
              'Voucher amount minus refunds does not equal net allocated plus unallocated balance.',
        ));
      }

      final invalidPartyAllocations = await _db.customSelect(
        '''
        SELECT pa.id
        FROM payment_allocations pa
        LEFT JOIN $voucherTable v
          ON v.id = pa.voucher_id
          AND v.deleted_at = '' AND v.status = 'posted'
        WHERE pa.voucher_type = ?
          AND pa.deleted_at = '' AND pa.status = 'active'
          AND v.id IS NULL
        ''',
        variables: <Variable<Object>>[Variable<String>(voucherType)],
      ).get();
      for (final row in invalidPartyAllocations) {
        issues.add(AccountingIntegrityIssue(
          code: 'orphan_payment_allocation',
          severity: AccountingIntegritySeverity.critical,
          entityType: 'payment_allocation',
          entityId: row.data['id']?.toString() ?? '',
          message: 'Active $partyType allocation references no posted voucher.',
        ));
      }
    }

    await _checkPartyControlBalance(
      issues,
      partyType: 'customer',
      roleKey: 'accounts_receivable',
      expectedExpression: 'debit - credit',
      ledgerExpression: 'jl.debit - jl.credit',
    );
    await _checkPartyControlBalance(
      issues,
      partyType: 'supplier',
      roleKey: 'accounts_payable',
      expectedExpression: 'credit - debit',
      ledgerExpression: 'jl.credit - jl.debit',
    );

    final cashRows = await _db.customSelect(r'''
      WITH location_balance AS (
        SELECT account_id, SUM(current_balance) AS balance
        FROM cash_locations
        WHERE deleted_at = '' AND is_active = 1 AND trim(account_id) <> ''
        GROUP BY account_id
      ), gl_balance AS (
        SELECT jl.account_id, SUM(jl.debit - jl.credit) AS balance
        FROM journal_lines jl
        INNER JOIN journal_entries je ON je.id = jl.entry_id
        WHERE je.deleted_at = '' AND je.status IN ('posted', 'reversed')
        GROUP BY jl.account_id
      )
      SELECT l.account_id, l.balance AS location_balance,
             COALESCE(g.balance, 0) AS gl_balance
      FROM location_balance l
      LEFT JOIN gl_balance g ON g.account_id = l.account_id
      WHERE ABS(l.balance - COALESCE(g.balance, 0)) > 0.005
    ''').get();
    for (final row in cashRows) {
      final location = AccountingProductionIntegrityService._num(row.data['location_balance']);
      final gl = AccountingProductionIntegrityService._num(row.data['gl_balance']);
      issues.add(AccountingIntegrityIssue(
        code: 'cash_location_gl_mismatch',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'cash_account',
        entityId: row.data['account_id']?.toString() ?? '',
        difference: AccountingProductionIntegrityService._round(location - gl),
        message:
            'Cash-location balance ($location) does not reconcile to its GL cash balance ($gl).',
      ));
    }
  }

  Future<void> _checkPartyControlBalance(
    List<AccountingIntegrityIssue> issues, {
    required String partyType,
    required String roleKey,
    required String expectedExpression,
    required String ledgerExpression,
  }) async {
    String accountId;
    try {
      accountId = await AccountingService.resolveAccountRoleForDatabase(
        _db,
        roleKey,
      );
    } catch (error) {
      issues.add(AccountingIntegrityIssue(
        code: 'party_control_role_invalid',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'account_role',
        entityId: roleKey,
        message: 'Control-account role $roleKey cannot be resolved: $error',
      ));
      return;
    }

    final rows = await _db.customSelect(
      '''
      WITH parties AS (
        SELECT account_id AS party_id
        FROM account_transactions
        WHERE deleted_at = '' AND lower(trim(account_type)) = ?
          AND trim(account_id) <> ''
        UNION
        SELECT jl.party_id
        FROM journal_lines jl
        INNER JOIN journal_entries je ON je.id = jl.entry_id
        WHERE je.deleted_at = '' AND je.status IN ('posted', 'reversed')
          AND jl.account_id = ? AND jl.party_type = ? AND trim(jl.party_id) <> ''
      ), expected AS (
        SELECT account_id AS party_id, SUM($expectedExpression) AS balance
        FROM account_transactions
        WHERE deleted_at = '' AND lower(trim(account_type)) = ?
          AND trim(account_id) <> ''
        GROUP BY account_id
      ), ledger AS (
        SELECT jl.party_id, SUM($ledgerExpression) AS balance
        FROM journal_lines jl
        INNER JOIN journal_entries je ON je.id = jl.entry_id
        WHERE je.deleted_at = '' AND je.status IN ('posted', 'reversed')
          AND jl.account_id = ? AND jl.party_type = ? AND trim(jl.party_id) <> ''
        GROUP BY jl.party_id
      )
      SELECT parties.party_id,
             COALESCE(expected.balance, 0) AS expected_balance,
             COALESCE(ledger.balance, 0) AS ledger_balance
      FROM parties
      LEFT JOIN expected ON expected.party_id = parties.party_id
      LEFT JOIN ledger ON ledger.party_id = parties.party_id
      WHERE ABS(COALESCE(expected.balance, 0) - COALESCE(ledger.balance, 0)) > 0.005
      ''',
      variables: <Variable<Object>>[
        Variable<String>(partyType),
        Variable<String>(accountId),
        Variable<String>(partyType),
        Variable<String>(partyType),
        Variable<String>(accountId),
        Variable<String>(partyType),
      ],
    ).get();
    for (final row in rows) {
      final expected = AccountingProductionIntegrityService._num(row.data['expected_balance']);
      final ledger = AccountingProductionIntegrityService._num(row.data['ledger_balance']);
      issues.add(AccountingIntegrityIssue(
        code: '${partyType}_control_balance_mismatch',
        severity: AccountingIntegritySeverity.critical,
        entityType: partyType,
        entityId: row.data['party_id']?.toString() ?? '',
        difference: AccountingProductionIntegrityService._round(expected - ledger),
        message:
            '$partyType compatibility balance ($expected) does not reconcile to its control-account ledger ($ledger).',
      ));
    }
  }

  Future<void> _checkDocumentPosting(
      List<AccountingIntegrityIssue> issues) async {
    final sales = await _db.customSelect(r'''
      SELECT s.id, s.invoice_no, s.status
      FROM sales s
      WHERE s.deleted_at = ''
        AND lower(trim(s.status)) <> 'cancelled'
        AND EXISTS (
          SELECT 1 FROM sale_items si
          WHERE si.sale_id = s.id
            AND (
              ABS(COALESCE(si.quantity, 0) * COALESCE(si.unit_price, 0)) > 0.005
              OR ABS(COALESCE(si.base_quantity, si.quantity, 0) * COALESCE(si.unit_cost, 0)) > 0.005
            )
        )
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries je
          WHERE je.reference_type = 'sale'
            AND (je.reference_id = s.id
                 OR instr(je.reference_id, s.id || ':sale_edit:') = 1)
            AND je.deleted_at = '' AND je.status = 'posted'
            AND NOT EXISTS (
              SELECT 1 FROM journal_entries rev
              WHERE rev.reversed_entry_id = je.id
                AND rev.deleted_at = '' AND rev.status = 'posted'
            )
        )
    ''').get();
    for (final row in sales) {
      issues.add(AccountingIntegrityIssue(
        code: 'sale_missing_active_journal',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'sale',
        entityId: row.data['id']?.toString() ?? '',
        message:
            'Active sale ${row.data['invoice_no'] ?? ''} has accounting value but no active journal.',
      ));
    }

    final cancelledSales = await _db.customSelect(r'''
      SELECT s.id, s.invoice_no
      FROM sales s
      WHERE s.deleted_at = ''
        AND lower(trim(s.status)) = 'cancelled'
        AND EXISTS (
          SELECT 1 FROM journal_entries je
          WHERE je.reference_type = 'sale'
            AND (je.reference_id = s.id
                 OR instr(je.reference_id, s.id || ':sale_edit:') = 1)
            AND je.deleted_at = '' AND je.status = 'posted'
            AND NOT EXISTS (
              SELECT 1 FROM journal_entries rev
              WHERE rev.reversed_entry_id = je.id
                AND rev.deleted_at = '' AND rev.status = 'posted'
            )
        )
    ''').get();
    for (final row in cancelledSales) {
      issues.add(AccountingIntegrityIssue(
        code: 'cancelled_sale_has_active_journal',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'sale',
        entityId: row.data['id']?.toString() ?? '',
        message:
            'Cancelled sale ${row.data['invoice_no'] ?? ''} still has an active sale journal.',
      ));
    }

    final returnedSales = await _db.customSelect(r'''
      SELECT s.id, s.invoice_no, s.status
      FROM sales s
      WHERE s.deleted_at = ''
        AND lower(trim(s.status)) IN ('returned', 'partially returned')
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries je
          WHERE je.reference_type = 'sale_return'
            AND je.reference_no = s.invoice_no
            AND je.deleted_at = '' AND je.status = 'posted'
            AND NOT EXISTS (
              SELECT 1 FROM journal_entries rev
              WHERE rev.reversed_entry_id = je.id
                AND rev.deleted_at = '' AND rev.status = 'posted'
            )
        )
    ''').get();
    for (final row in returnedSales) {
      issues.add(AccountingIntegrityIssue(
        code: 'returned_sale_missing_return_journal',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'sale',
        entityId: row.data['id']?.toString() ?? '',
        message:
            'Returned sale ${row.data['invoice_no'] ?? ''} has no active sale-return journal.',
      ));
    }

    final purchases = await _db.customSelect(r'''
      SELECT p.id, p.purchase_no
      FROM purchases p
      WHERE p.deleted_at = ''
        AND lower(trim(p.status)) = 'received'
        AND EXISTS (
          SELECT 1 FROM purchase_items pi
          WHERE pi.purchase_id = p.id
            AND ABS(COALESCE(pi.quantity, 0) * COALESCE(pi.unit_cost, 0)) > 0.005
        )
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries je
          WHERE je.reference_type = 'purchase'
            AND (je.reference_id = p.id OR je.reference_id LIKE p.id || ':purchase_edit:%')
            AND je.deleted_at = '' AND je.status = 'posted'
            AND NOT EXISTS (
              SELECT 1 FROM journal_entries rev
              WHERE rev.reversed_entry_id = je.id
                AND rev.deleted_at = '' AND rev.status = 'posted'
            )
        )
    ''').get();
    for (final row in purchases) {
      issues.add(AccountingIntegrityIssue(
        code: 'received_purchase_missing_active_journal',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'purchase',
        entityId: row.data['id']?.toString() ?? '',
        message:
            'Received purchase ${row.data['purchase_no'] ?? ''} has value but no active journal.',
      ));
    }

    final cancelledPurchases = await _db.customSelect(r'''
      SELECT p.id, p.purchase_no
      FROM purchases p
      WHERE p.deleted_at = ''
        AND lower(trim(p.status)) IN ('cancelled', 'returned')
        AND EXISTS (
          SELECT 1 FROM journal_entries je
          WHERE je.reference_type = 'purchase'
            AND (je.reference_id = p.id OR je.reference_id LIKE p.id || ':purchase_edit:%')
            AND je.deleted_at = '' AND je.status = 'posted'
            AND NOT EXISTS (
              SELECT 1 FROM journal_entries rev
              WHERE rev.reversed_entry_id = je.id
                AND rev.deleted_at = '' AND rev.status = 'posted'
            )
        )
    ''').get();
    for (final row in cancelledPurchases) {
      issues.add(AccountingIntegrityIssue(
        code: 'cancelled_purchase_has_active_journal',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'purchase',
        entityId: row.data['id']?.toString() ?? '',
        message:
            'Cancelled/returned purchase ${row.data['purchase_no'] ?? ''} still has an active purchase journal.',
      ));
    }
  }

  Future<void> _checkExpensePosting(
      List<AccountingIntegrityIssue> issues) async {
    final postedExpenses = await _db.customSelect(r'''
      SELECT e.id, e.title
      FROM expenses e
      WHERE e.deleted_at = ''
        AND lower(trim(e.expense_status)) = 'posted'
        AND ABS(COALESCE(e.amount, 0)) > 0.005
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries je
          WHERE je.reference_type = 'expense'
            AND (je.reference_id = e.id
                 OR instr(je.reference_id, e.id || ':expense_edit:') = 1)
            AND je.deleted_at = '' AND je.status = 'posted'
            AND NOT EXISTS (
              SELECT 1 FROM journal_entries rev
              WHERE rev.reversed_entry_id = je.id
                AND rev.deleted_at = '' AND rev.status = 'posted'
            )
        )
    ''').get();
    for (final row in postedExpenses) {
      issues.add(AccountingIntegrityIssue(
        code: 'posted_expense_missing_active_journal',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'expense',
        entityId: row.data['id']?.toString() ?? '',
        message:
            'Posted expense ${row.data['title'] ?? ''} has value but no active journal.',
      ));
    }

    final cancelledExpenses = await _db.customSelect(r'''
      SELECT e.id, e.title
      FROM expenses e
      WHERE e.deleted_at = ''
        AND lower(trim(e.expense_status)) = 'cancelled'
        AND EXISTS (
          SELECT 1 FROM journal_entries je
          WHERE je.reference_type = 'expense'
            AND (je.reference_id = e.id
                 OR instr(je.reference_id, e.id || ':expense_edit:') = 1)
            AND je.deleted_at = '' AND je.status = 'posted'
            AND NOT EXISTS (
              SELECT 1 FROM journal_entries rev
              WHERE rev.reversed_entry_id = je.id
                AND rev.deleted_at = '' AND rev.status = 'posted'
            )
        )
    ''').get();
    for (final row in cancelledExpenses) {
      issues.add(AccountingIntegrityIssue(
        code: 'cancelled_expense_has_active_journal',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'expense',
        entityId: row.data['id']?.toString() ?? '',
        message:
            'Cancelled expense ${row.data['title'] ?? ''} still has an active journal.',
      ));
    }
  }
}
