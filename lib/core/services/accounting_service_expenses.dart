part of 'accounting_service_impl.dart';

/// Returns the semantic role used when posting an expense. Reports use this
/// to resolve the same primary/sub-account that received the journal line.
String expenseAccountRoleKeyForReport(Expense expense) =>
    _expenseAccountRoleKey(expense);

Future<String> _resolveExpenseAccountForDatabase(
  VentioDriftDatabase db,
  Expense expense,
) =>
    _resolveAccountRoleForDatabase(db, _expenseAccountRoleKey(expense));

/// Posts a legacy Expense through the Phase 5 authoritative cash path.
///
/// A posted expense is committed atomically as journal + cash_operations +
/// Cash Ledger + cash_locations balance. No expense caller is allowed to
/// mutate the drawer balance separately from its immutable ledger movement.
Future<void> recordExpense(
  Expense expense, {
  double? cashPaidAmount,
}) async {
  if (expense.isDeleted || !expense.isPosted || expense.amount <= 0) return;
  if (!isAvailable) return;
  await _db.transaction(() async {
    // Phase 4: Expense status and all financial effects commit together.
    await _upsertExpenseRowInExistingTransaction(expense);
    await _recordExpenseInExistingTransaction(
      expense,
      cashPaidAmount: cashPaidAmount,
    );
    await _recordExpenseCompatibilityLedgerInExistingTransaction(
      expense,
      cashPaidAmount: cashPaidAmount,
    );
  });
  _notifyMutation();
}

/// Posts an expense on credit without touching the cash drawer or shift.
/// The journal recognizes the expense immediately and carries the amount in
/// the default suppliers/payables account until it is settled later.
Future<void> recordExpenseOnCredit(Expense expense) async {
  if (expense.isDeleted || !expense.isPosted || expense.amount <= 0) return;
  if (!isAvailable) return;
  await _db.transaction(() async {
    await _upsertExpenseRowInExistingTransaction(expense);
    await _recordCreditExpenseInExistingTransaction(expense);
    await _recordCreditExpenseCompatibilityLedgerInExistingTransaction(expense);
  });
  _notifyMutation();
}

/// Reposts an edited posted expense inside the caller's authoritative
/// transaction using a versioned technical reference. The original journal,
/// cash operation, Cash Ledger row and compatibility rows remain immutable.
Future<void> repostEditedExpenseInExistingTransaction(
  Expense expense, {
  required bool paidInCash,
  double? cashPaidAmount,
  required String technicalReferenceId,
}) async {
  if (expense.isDeleted || !expense.isPosted || expense.amount <= 0) {
    throw StateError('Only a valid posted expense can be reposted.');
  }
  final ref = technicalReferenceId.trim();
  if (ref.isEmpty) {
    throw ArgumentError('technicalReferenceId is required.');
  }
  await _upsertExpenseRowInExistingTransaction(expense);
  if (paidInCash) {
    await _recordExpenseInExistingTransaction(
      expense,
      cashPaidAmount: cashPaidAmount,
      accountingReferenceId: ref,
    );
    await _recordExpenseCompatibilityLedgerInExistingTransaction(
      expense,
      cashPaidAmount: cashPaidAmount,
      movementVersionSuffix: 'edit-v${expense.version}',
    );
  } else {
    await _recordCreditExpenseInExistingTransaction(
      expense,
      accountingReferenceId: ref,
    );
    await _recordCreditExpenseCompatibilityLedgerInExistingTransaction(
      expense,
      movementVersionSuffix: 'edit-v${expense.version}',
    );
  }
}

/// Returns posted credit-expense ids that have not yet been settled from cash.
/// Credit approval is identified by the compatibility ledger row written by
/// [recordExpenseOnCredit]. A successful cash settlement is identified by the
/// stable cash-operation idempotency key used by the Cash page.
Future<Set<String>> readOutstandingCreditExpenseIds() async {
  return (await readOutstandingCreditExpenseBalances()).keys.toSet();
}

/// Returns each posted credit expense and the amount that is still payable.
/// Expense payables can be posted to the default suppliers account or to a
/// dedicated accrued liability account, so include all liability accounts.
/// This also understands partial cash settlements performed later from the
/// Cash page, so the same expense can be settled over more than one payment.
Future<Map<String, double>> readOutstandingCreditExpenseBalances() async {
  if (!isAvailable) return <String, double>{};
  final rows = await _db.customSelect(
    '''
      SELECT balances.expense_id, balances.payable, balances.settled
      FROM (
      SELECT e.id AS expense_id,
             MAX(
               COALESCE((
                 SELECT SUM(jl.credit - jl.debit)
                 FROM journal_entries je
                 JOIN journal_lines jl ON jl.entry_id = je.id
                 JOIN accounts a ON a.id = jl.account_id
                 WHERE je.reference_type = 'expense'
                   AND (je.reference_id = e.id OR
                        instr(je.reference_id, e.id || ':expense_edit:') = 1)
                   AND je.deleted_at = '' AND je.status = 'posted'
                   AND LOWER(a.type) = 'liability'
                   AND NOT EXISTS (
                     SELECT 1 FROM journal_entries rev
                     WHERE rev.reversed_entry_id = je.id
                       AND rev.deleted_at = '' AND rev.status = 'posted'
                   )
               ), 0),
               COALESCE((
                 SELECT SUM(CASE WHEN at.credit > 0 THEN at.credit ELSE 0 END)
                 FROM account_transactions at
                 WHERE at.reference_id = e.id
                   AND at.deleted_at = ''
                   AND LOWER(at.transaction_type) = 'expense'
                   AND LOWER(at.payment_method) = 'credit'
               ), 0)
             ) AS payable,
             COALESCE((
               SELECT SUM(co.amount)
               FROM cash_operations co
               WHERE co.deleted_at = ''
                 AND LOWER(co.status) = 'posted'
                 AND (
                   co.idempotency_key =
                     ('expense-credit-settlement:' || e.id)
                   OR co.idempotency_key LIKE
                     ('expense-credit-settlement:' || e.id || ':%')
                 )
             ), 0) AS settled
      FROM expenses e
      WHERE e.deleted_at = ''
        AND LOWER(e.expense_status) = 'posted'
      ) balances
      WHERE balances.payable - balances.settled > 0.005
      ''',
  ).get();
  final result = <String, double>{};
  for (final row in rows) {
    final id = row.data['expense_id']?.toString().trim() ?? '';
    final payable = (row.data['payable'] as num?)?.toDouble() ?? 0;
    final settled = (row.data['settled'] as num?)?.toDouble() ?? 0;
    final remaining = _roundMoney(payable - settled);
    if (id.isNotEmpty && remaining > 0) result[id] = remaining;
  }
  return result;
}

/// Resolves the liability account that holds a posted expense's payable.
/// Older expenses may have been credited to accrued-expense or accrued-
/// payroll accounts instead of the current default suppliers account.
Future<String> resolveCreditExpensePayableAccount(
  String expenseId,
) async {
  final id = expenseId.trim();
  if (id.isEmpty) return '';
  if (!isAvailable) return '';
  final row = await _db.customSelect(
    '''
      SELECT jl.account_id, SUM(jl.credit - jl.debit) AS outstanding
      FROM journal_entries je
      JOIN journal_lines jl ON jl.entry_id = je.id
      JOIN accounts a ON a.id = jl.account_id
      WHERE je.reference_type = 'expense'
        AND (je.reference_id = ? OR
             instr(je.reference_id, ? || ':expense_edit:') = 1)
        AND je.deleted_at = '' AND je.status = 'posted'
        AND LOWER(a.type) = 'liability'
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries rev
          WHERE rev.reversed_entry_id = je.id
            AND rev.deleted_at = '' AND rev.status = 'posted'
        )
      GROUP BY jl.account_id
      HAVING SUM(jl.credit - jl.debit) > 0.005
      ORDER BY outstanding DESC, jl.account_id
      LIMIT 1
      ''',
    variables: <Variable<Object>>[
      Variable<String>(id),
      Variable<String>(id),
    ],
  ).getSingleOrNull();
  final accountId = row?.data['account_id']?.toString().trim() ?? '';
  if (accountId.isNotEmpty) return accountId;

  // Compatibility-only legacy entries do not retain a liability account id.
  return resolveAccountRole('accounts_payable');
}
