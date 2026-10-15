part of 'cash_phase7_migration_service.dart';

extension CashPhase7MigrationServiceSplitPart2 on CashPhase7MigrationService {

  Future<void> _runIntegrityChecks(List<CashPhase7Issue> issues) async {
    final checks = <(String, String, String)>[
      (
        'missing_sale_journal',
        "SELECT id, invoice_no AS ref FROM sales s WHERE s.deleted_at = '' AND lower(s.status) <> 'cancelled' AND NOT EXISTS (SELECT 1 FROM journal_entries je WHERE je.deleted_at = '' AND je.status = 'posted' AND je.reference_type = 'sale' AND (je.reference_id = s.id OR instr(je.reference_id, s.id || ':sale_edit:') = 1) AND NOT EXISTS (SELECT 1 FROM journal_entries rev WHERE rev.reversed_entry_id = je.id AND rev.deleted_at = '' AND rev.status = 'posted'))",
        'Authoritative sale journal is still missing after Phase 7 reconciliation.'
      ),
      (
        'missing_purchase_journal',
        "SELECT id, purchase_no AS ref FROM purchases p WHERE p.deleted_at = '' AND lower(trim(p.status)) = 'received' AND NOT EXISTS (SELECT 1 FROM journal_entries je WHERE je.deleted_at = '' AND je.status = 'posted' AND je.reference_type = 'purchase' AND (je.reference_id = p.id OR je.reference_id LIKE p.id || ':purchase_edit:%') AND NOT EXISTS (SELECT 1 FROM journal_entries rev WHERE rev.reversed_entry_id = je.id AND rev.deleted_at = '' AND rev.status = 'posted'))",
        'Authoritative purchase journal is still missing after Phase 7 reconciliation.'
      ),
      (
        'missing_receipt_journal',
        "SELECT id, voucher_no AS ref FROM receipt_vouchers v WHERE v.deleted_at = '' AND v.status = 'posted' AND NOT EXISTS (SELECT 1 FROM journal_entries je WHERE je.deleted_at = '' AND je.status = 'posted' AND je.reference_type = 'receipt_voucher' AND (je.reference_id = v.id OR instr(je.reference_id, v.id || ':receipt_edit:') = 1) AND NOT EXISTS (SELECT 1 FROM journal_entries rev WHERE rev.reversed_entry_id = je.id AND rev.deleted_at = '' AND rev.status = 'posted'))",
        'Posted receipt voucher has no authoritative journal entry.'
      ),
      (
        'missing_payment_journal',
        "SELECT id, voucher_no AS ref FROM payment_vouchers v WHERE v.deleted_at = '' AND v.status = 'posted' AND NOT EXISTS (SELECT 1 FROM journal_entries je WHERE je.deleted_at = '' AND je.status = 'posted' AND je.reference_type = 'payment_voucher' AND (je.reference_id = v.id OR instr(je.reference_id, v.id || ':payment_edit:') = 1) AND NOT EXISTS (SELECT 1 FROM journal_entries rev WHERE rev.reversed_entry_id = je.id AND rev.deleted_at = '' AND rev.status = 'posted'))",
        'Posted payment voucher has no authoritative journal entry.'
      ),
      (
        'missing_receipt_cash_ledger',
        "SELECT id, voucher_no AS ref FROM receipt_vouchers v WHERE v.deleted_at = '' AND v.status = 'posted' AND v.amount > 0 AND lower(trim(v.payment_method)) = 'cash' AND NOT EXISTS (SELECT 1 FROM cash_ledger_transactions clt WHERE clt.deleted_at = '' AND clt.reference_type = 'receipt_voucher' AND (clt.reference_id = v.id OR instr(clt.reference_id, v.id || ':receipt_edit:') = 1) AND NOT EXISTS (SELECT 1 FROM cash_ledger_transactions rev WHERE rev.reversal_of_id = clt.id AND rev.deleted_at = ''))",
        'Posted cash receipt voucher has no Cash Ledger transaction.'
      ),
      (
        'missing_payment_cash_ledger',
        "SELECT id, voucher_no AS ref FROM payment_vouchers v WHERE v.deleted_at = '' AND v.status = 'posted' AND v.amount > 0 AND lower(trim(v.payment_method)) = 'cash' AND NOT EXISTS (SELECT 1 FROM cash_ledger_transactions clt WHERE clt.deleted_at = '' AND clt.reference_type = 'payment_voucher' AND (clt.reference_id = v.id OR instr(clt.reference_id, v.id || ':payment_edit:') = 1) AND NOT EXISTS (SELECT 1 FROM cash_ledger_transactions rev WHERE rev.reversal_of_id = clt.id AND rev.deleted_at = ''))",
        'Posted cash payment voucher has no Cash Ledger transaction.'
      ),
    ];
    for (final check in checks) {
      final rows = await _db.customSelect(check.$2).get();
      for (final row in rows) {
        issues.add(CashPhase7Issue(
            severity: 'error',
            type: check.$1,
            entityId: row.data['id']?.toString() ?? '',
            referenceNo: row.data['ref']?.toString() ?? '',
            details: check.$3));
      }
    }

    for (final spec in <(String, String)>[
      ('receipt_vouchers', 'receipt'),
      ('payment_vouchers', 'payment')
    ]) {
      final rows = await _db.customSelect('''
        SELECT v.id, v.voucher_no AS ref, v.amount, v.unallocated_amount,
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
        FROM ${spec.$1} v
        LEFT JOIN payment_allocations pa ON pa.voucher_type = ? AND pa.voucher_id = v.id
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
        ) > 0.000001
      ''', variables: <Variable<Object>>[
        Variable<String>(spec.$2),
        Variable<String>(spec.$2),
        Variable<String>(spec.$2),
      ]).get();
      for (final row in rows) {
        issues.add(CashPhase7Issue(
            severity: 'error',
            type: 'voucher_allocation_mismatch',
            entityType: spec.$1,
            entityId: row.data['id']?.toString() ?? '',
            referenceNo: row.data['ref']?.toString() ?? '',
            details:
                'Voucher amount=${row.data['amount']}, refunded=${row.data['refunded']}, allocated=${row.data['allocated']}, unallocated=${row.data['unallocated_amount']}.'));
      }
    }

    final invalidAllocations = await _db.customSelect(r'''
      SELECT pa.id, pa.reference_number AS ref,
             CASE
               WHEN pa.voucher_type = 'receipt' AND rv.id IS NULL THEN 'missing_receipt_voucher'
               WHEN pa.voucher_type = 'payment' AND pv.id IS NULL THEN 'missing_payment_voucher'
               WHEN pa.reference_type = 'sale' AND s.id IS NULL THEN 'missing_sale'
               WHEN pa.reference_type = 'purchase' AND p.id IS NULL THEN 'missing_purchase'
               WHEN pa.voucher_type = 'receipt' AND pa.reference_type = 'sale' AND rv.customer_id <> s.customer_id THEN 'party_mismatch'
               WHEN pa.voucher_type = 'payment' AND pa.reference_type = 'purchase' AND pv.supplier_id <> p.supplier_id THEN 'party_mismatch'
               ELSE '' END AS problem
      FROM payment_allocations pa
      LEFT JOIN receipt_vouchers rv ON pa.voucher_type = 'receipt' AND rv.id = pa.voucher_id AND rv.deleted_at = '' AND rv.status = 'posted'
      LEFT JOIN payment_vouchers pv ON pa.voucher_type = 'payment' AND pv.id = pa.voucher_id AND pv.deleted_at = '' AND pv.status = 'posted'
      LEFT JOIN sales s ON pa.reference_type = 'sale' AND s.id = pa.reference_id AND s.deleted_at = '' AND lower(s.status) <> 'cancelled'
      LEFT JOIN purchases p ON pa.reference_type = 'purchase' AND p.id = pa.reference_id AND p.deleted_at = '' AND lower(p.status) <> 'cancelled'
      WHERE pa.deleted_at = '' AND pa.status = 'active' AND (
        (pa.voucher_type = 'receipt' AND rv.id IS NULL) OR (pa.voucher_type = 'payment' AND pv.id IS NULL) OR
        (pa.reference_type = 'sale' AND s.id IS NULL) OR (pa.reference_type = 'purchase' AND p.id IS NULL) OR
        (pa.voucher_type = 'receipt' AND pa.reference_type = 'sale' AND rv.customer_id <> s.customer_id) OR
        (pa.voucher_type = 'payment' AND pa.reference_type = 'purchase' AND pv.supplier_id <> p.supplier_id))
    ''').get();
    for (final row in invalidAllocations) {
      issues.add(CashPhase7Issue(
          severity: 'error',
          type: 'invalid_payment_allocation',
          entityType: 'payment_allocation',
          entityId: row.data['id']?.toString() ?? '',
          referenceNo: row.data['ref']?.toString() ?? '',
          details: 'Allocation integrity failure: ${row.data['problem']}.'));
    }

    final duplicateJournals = await _db.customSelect(r'''
      SELECT reference_type, reference_id, MAX(reference_no) AS ref, COUNT(*) AS c
      FROM journal_entries
      WHERE deleted_at = '' AND status = 'posted' AND reference_type IN ('sale', 'purchase', 'receipt_voucher', 'payment_voucher')
      GROUP BY reference_type, reference_id HAVING COUNT(*) > 1
    ''').get();
    for (final row in duplicateJournals) {
      issues.add(CashPhase7Issue(
          severity: 'error',
          type: 'duplicate_posted_journal',
          entityType: row.data['reference_type']?.toString() ?? '',
          entityId: row.data['reference_id']?.toString() ?? '',
          referenceNo: row.data['ref']?.toString() ?? '',
          details:
              'Financial reference has ${row.data['c']} posted journal entries.'));
    }

    final duplicateLedger = await _db.customSelect(r'''
      SELECT reference_type, reference_id, MAX(reference_number) AS ref, COUNT(*) AS c
      FROM cash_ledger_transactions
      WHERE deleted_at = '' AND reference_type IN ('receipt_voucher', 'payment_voucher')
      GROUP BY reference_type, reference_id HAVING COUNT(*) > 1
    ''').get();
    for (final row in duplicateLedger) {
      issues.add(CashPhase7Issue(
          severity: 'error',
          type: 'duplicate_cash_ledger_reference',
          entityType: row.data['reference_type']?.toString() ?? '',
          entityId: row.data['reference_id']?.toString() ?? '',
          referenceNo: row.data['ref']?.toString() ?? '',
          details:
              'Voucher reference has ${row.data['c']} active Cash Ledger rows.'));
    }

    for (final row in await _db.customSelect(r'''
      WITH expected AS (
        SELECT account_id AS party_id, SUM(debit - credit) AS balance
        FROM account_transactions
        WHERE deleted_at = '' AND lower(trim(account_type)) = 'customer' AND trim(account_id) <> ''
        GROUP BY account_id
      ), ledger AS (
        SELECT jl.party_id, SUM(jl.debit - jl.credit) AS balance
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.entry_id
        JOIN accounting_settings s ON s.key = 'default_customers_account_id' AND s.account_id = jl.account_id
        WHERE je.deleted_at = '' AND je.status IN ('posted', 'reversed') AND jl.party_type = 'customer' AND jl.party_id <> ''
        GROUP BY jl.party_id
      )
      SELECT e.party_id, e.balance AS expected_balance, COALESCE(l.balance, 0) AS ledger_balance
      FROM expected e LEFT JOIN ledger l ON l.party_id = e.party_id
      WHERE ABS(e.balance - COALESCE(l.balance, 0)) > 0.000001
    ''').get()) {
      issues.add(CashPhase7Issue(
          severity: 'error',
          type: 'customer_control_balance_mismatch',
          entityType: 'customer',
          entityId: row.data['party_id']?.toString() ?? '',
          details:
              'Legacy/customer balance=${row.data['expected_balance']}, accounting receivable=${row.data['ledger_balance']}.'));
    }

    for (final row in await _db.customSelect(r'''
      WITH expected AS (
        SELECT account_id AS party_id, SUM(credit - debit) AS balance
        FROM account_transactions
        WHERE deleted_at = '' AND lower(trim(account_type)) = 'supplier' AND trim(account_id) <> ''
        GROUP BY account_id
      ), ledger AS (
        SELECT jl.party_id, SUM(jl.credit - jl.debit) AS balance
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.entry_id
        JOIN accounting_settings s ON s.key = 'default_suppliers_account_id' AND s.account_id = jl.account_id
        WHERE je.deleted_at = '' AND je.status IN ('posted', 'reversed') AND jl.party_type = 'supplier' AND jl.party_id <> ''
        GROUP BY jl.party_id
      )
      SELECT e.party_id, e.balance AS expected_balance, COALESCE(l.balance, 0) AS ledger_balance
      FROM expected e LEFT JOIN ledger l ON l.party_id = e.party_id
      WHERE ABS(e.balance - COALESCE(l.balance, 0)) > 0.000001
    ''').get()) {
      issues.add(CashPhase7Issue(
          severity: 'error',
          type: 'supplier_control_balance_mismatch',
          entityType: 'supplier',
          entityId: row.data['party_id']?.toString() ?? '',
          details:
              'Legacy/supplier balance=${row.data['expected_balance']}, accounting payable=${row.data['ledger_balance']}.'));
    }

    final unbalanced = await _db.customSelect(r'''
      SELECT je.id, je.entry_no AS ref, ABS(COALESCE(SUM(jl.debit), 0) - COALESCE(SUM(jl.credit), 0)) AS difference
      FROM journal_entries je JOIN journal_lines jl ON jl.entry_id = je.id
      WHERE je.deleted_at = '' AND je.status = 'posted'
      GROUP BY je.id, je.entry_no HAVING ABS(SUM(jl.debit) - SUM(jl.credit)) > 0.000001
    ''').get();
    for (final row in unbalanced) {
      issues.add(CashPhase7Issue(
          severity: 'error',
          type: 'unbalanced_journal_entry',
          entityType: 'journal_entry',
          entityId: row.data['id']?.toString() ?? '',
          referenceNo: row.data['ref']?.toString() ?? '',
          details:
              'Posted journal is not balanced; difference=${row.data['difference']}.'));
    }
  }

  Future<String> _resolveCashLocation(Map<String, Object?> row) async {
    final deviceId = row['device_id']?.toString().trim() ?? '';
    final branchId = row['branch_id']?.toString().trim() ?? '';
    final result = await _db.customSelect(
      '''
      SELECT id FROM cash_locations
      WHERE deleted_at = '' AND is_active = 1 AND type = 'cash_drawer'
        AND (
          (? <> '' AND device_id = ?)
          OR (? = '' AND ? <> '' AND branch_id = ?)
        )
      ORDER BY
        CASE WHEN ? <> '' AND device_id = ? THEN 0 ELSE 1 END,
        CASE WHEN ? <> '' AND branch_id = ? THEN 0 ELSE 1 END,
        CASE WHEN id = 'cl_main_drawer' THEN 0 ELSE 1 END,
        is_default DESC, id
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(deviceId),
        Variable<String>(deviceId),
        Variable<String>(deviceId),
        Variable<String>(branchId),
        Variable<String>(branchId),
        Variable<String>(deviceId),
        Variable<String>(deviceId),
        Variable<String>(branchId),
        Variable<String>(branchId),
      ],
    ).getSingleOrNull();
    return result?.data['id']?.toString() ?? '';
  }

  Future<int> _countJournalEntries(List<String> types) async {
    final placeholders = List<String>.filled(types.length, '?').join(',');
    final row = await _db
        .customSelect(
          "SELECT COUNT(*) AS c FROM journal_entries WHERE deleted_at = '' AND status = 'posted' AND reference_type IN ($placeholders)",
          variables: types.map((e) => Variable<String>(e)).toList(),
        )
        .getSingle();
    return (row.data['c'] as num?)?.toInt() ?? 0;
  }

  Future<int> _countLedger() async {
    final row = await _db
        .customSelect(
            "SELECT COUNT(*) AS c FROM cash_ledger_transactions WHERE deleted_at = ''")
        .getSingle();
    return (row.data['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> _persistIssues(
      String runId, List<CashPhase7Issue> issues) async {
    final now = DateTime.now().toUtc().toIso8601String();
    for (final issue in issues) {
      await _db.customInsert(
        '''
        INSERT INTO cash_phase7_issues
          (id, run_id, severity, issue_type, entity_type, entity_id, reference_no, details, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(_id('cash_p7_issue')),
          Variable<String>(runId),
          Variable<String>(issue.severity),
          Variable<String>(issue.type),
          Variable<String>(issue.entityType),
          Variable<String>(issue.entityId),
          Variable<String>(issue.referenceNo),
          Variable<String>(issue.details),
          Variable<String>(now),
        ],
      );
    }
  }

  double _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  DateTime _date(String? value, {DateTime? fallback}) =>
      DateTime.tryParse(value ?? '')?.toUtc() ??
      fallback ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
