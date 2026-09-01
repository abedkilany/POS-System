import 'package:drift/drift.dart';

import '../storage/sqlite/ventio_drift_database.dart';
import 'accounting_service.dart';

enum AccountingIntegritySeverity { critical, warning }

class AccountingIntegrityIssue {
  const AccountingIntegrityIssue({
    required this.code,
    required this.severity,
    required this.message,
    this.entityType = '',
    this.entityId = '',
    this.difference = 0,
  });

  final String code;
  final AccountingIntegritySeverity severity;
  final String message;
  final String entityType;
  final String entityId;
  final double difference;
}

class AccountingProductionIntegrityReport {
  const AccountingProductionIntegrityReport({
    required this.generatedAt,
    required this.issues,
    required this.inventoryGlBalance,
    required this.inventoryValuation,
  });

  final DateTime generatedAt;
  final List<AccountingIntegrityIssue> issues;
  final double inventoryGlBalance;
  final double inventoryValuation;

  int get criticalCount => issues
      .where((issue) => issue.severity == AccountingIntegritySeverity.critical)
      .length;
  int get warningCount => issues
      .where((issue) => issue.severity == AccountingIntegritySeverity.warning)
      .length;
  bool get isProductionReady => criticalCount == 0;
}

/// Read-only accounting closure gate.
///
/// This service intentionally never repairs data. It verifies the invariants
/// that must remain true after the operational workflows have committed. A
/// production deployment can therefore run the audit repeatedly without
/// changing accounting, inventory, cash, or document state.
class AccountingProductionIntegrityService {
  AccountingProductionIntegrityService(this._db);

  final VentioDriftDatabase _db;
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
      final debit = _num(row.data['debits']);
      final credit = _num(row.data['credits']);
      issues.add(AccountingIntegrityIssue(
        code: 'unbalanced_or_empty_journal',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'journal_entry',
        entityId: row.data['id']?.toString() ?? '',
        difference: _round(debit - credit),
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
        final amount = _num(row.data['amount']);
        final refunded = _num(row.data['refunded']);
        final allocated = _num(row.data['allocated']);
        final unallocated = _num(row.data['unallocated_amount']);
        issues.add(AccountingIntegrityIssue(
          code: 'voucher_allocation_refund_mismatch',
          severity: AccountingIntegritySeverity.critical,
          entityType: referenceType,
          entityId: row.data['id']?.toString() ?? '',
          difference: _round((amount - refunded) - allocated - unallocated),
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
      final location = _num(row.data['location_balance']);
      final gl = _num(row.data['gl_balance']);
      issues.add(AccountingIntegrityIssue(
        code: 'cash_location_gl_mismatch',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'cash_account',
        entityId: row.data['account_id']?.toString() ?? '',
        difference: _round(location - gl),
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
      final expected = _num(row.data['expected_balance']);
      final ledger = _num(row.data['ledger_balance']);
      issues.add(AccountingIntegrityIssue(
        code: '${partyType}_control_balance_mismatch',
        severity: AccountingIntegritySeverity.critical,
        entityType: partyType,
        entityId: row.data['party_id']?.toString() ?? '',
        difference: _round(expected - ledger),
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
        difference: _round(_num(row.data['quantity'])),
        message:
            'Unified Batch balance is negative for product ${row.data['product_id'] ?? ''}.',
      ));
    }

    final mismatches = await _db.customSelect(r'''
      WITH scoped AS (
        SELECT store_id, warehouse_id, product_id FROM warehouse_inventory
        UNION
        SELECT store_id, warehouse_id, product_id FROM inventory_batch_balances
      ), warehouse AS (
        SELECT store_id, warehouse_id, product_id, SUM(quantity) AS qty
        FROM warehouse_inventory
        GROUP BY store_id, warehouse_id, product_id
      ), batches AS (
        SELECT store_id, warehouse_id, product_id, SUM(quantity) AS qty
        FROM inventory_batch_balances
        GROUP BY store_id, warehouse_id, product_id
      )
      SELECT s.store_id, s.warehouse_id, s.product_id,
             COALESCE(w.qty, 0) AS warehouse_qty,
             COALESCE(b.qty, 0) AS batch_qty
      FROM scoped s
      INNER JOIN products p ON p.id = s.product_id
        AND p.deleted_at = '' AND p.track_stock = 1
      LEFT JOIN warehouse w ON w.store_id = s.store_id
        AND w.warehouse_id = s.warehouse_id AND w.product_id = s.product_id
      LEFT JOIN batches b ON b.store_id = s.store_id
        AND b.warehouse_id = s.warehouse_id AND b.product_id = s.product_id
      WHERE ABS(COALESCE(w.qty, 0) - COALESCE(b.qty, 0)) > 0.005
    ''').get();
    for (final row in mismatches) {
      final warehouse = _num(row.data['warehouse_qty']);
      final batches = _num(row.data['batch_qty']);
      issues.add(AccountingIntegrityIssue(
        code: 'unified_batch_quantity_mismatch',
        severity: AccountingIntegritySeverity.critical,
        entityType: 'product',
        entityId: row.data['product_id']?.toString() ?? '',
        difference: _round(warehouse - batches),
        message:
            'Warehouse quantity ($warehouse) does not equal Unified Batch quantity ($batches) in warehouse ${row.data['warehouse_id'] ?? ''}.',
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
      glBalance = _round(_num(row.data['balance']));
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
    final valuation = _round(_num(valuationRow.data['valuation']));

    final difference = _round(glBalance - valuation);
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
      expectedByAccount[accountId] = _round(
        (expectedByAccount[accountId] ?? 0) + _num(row.data['valuation']),
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
      final actual = _round(_num(row.data['balance']));
      final expected = _round(expectedByAccount[accountId] ?? 0);
      final accountDifference = _round(actual - expected);
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

  static double _num(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0.0;

  static double _round(double value) => (value * 100).roundToDouble() / 100;
}
