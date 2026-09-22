import 'package:flutter/material.dart';

import '../../core/services/accounting_service.dart';
import '../../core/services/account_statement_pdf_service.dart';
import '../../data/app_store.dart';
import '../../models/accounting_account.dart';
import '../../models/expense.dart';

Future<DateTimeRange?> pickAccountStatementDateRange(
  BuildContext context,
) async {
  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month, 1);
  final today = DateTime(now.year, now.month, now.day);
  return showDateRangePicker(
    context: context,
    firstDate: DateTime(2000),
    lastDate: DateTime(now.year + 10, 12, 31),
    currentDate: today,
    initialDateRange: DateTimeRange(start: startOfMonth, end: today),
    helpText: _dateRangeText(context, 'help'),
    saveText: _dateRangeText(context, 'save'),
  );
}

Future<void> printAccountStatementForAccount({
  required BuildContext context,
  required AppStore store,
  required String accountType,
  required String accountId,
  required String accountName,
}) async {
  final range = await pickAccountStatementDateRange(context);
  if (range == null || !context.mounted) return;
  try {
    await AccountStatementPdfService.printAccountStatement(
      context: context,
      accountType: accountType,
      accountName: accountName,
      transactions: store.accountTransactionsForAccount(accountType, accountId),
      from: _startOfDay(range.start),
      to: _endOfDay(range.end),
      profile: store.storeProfile,
      locale: Localizations.localeOf(context),
    );
  } catch (error) {
    if (!context.mounted) return;
    _showPrintError(context, error);
  }
}

Future<void> printExpenseStatementForPeriod({
  required BuildContext context,
  required AppStore store,
}) async {
  final range = await pickAccountStatementDateRange(context);
  if (range == null || !context.mounted) return;
  try {
    final accounts = await AccountingService.listAccounts(activeOnly: true);
    if (!context.mounted) return;
    final selection = await _pickExpenseAccount(context, accounts);
    if (selection == null || !context.mounted) return;

    final accountIds = await _resolveExpenseAccountIds(store.expenses);
    if (!context.mounted) return;
    final selectedExpenses = selection.accountIds == null
        ? store.expenses
        : store.expenses
            .where((expense) =>
                selection.accountIds!.contains(accountIds[expense.id]))
            .toList(growable: false);
    await AccountStatementPdfService.printExpenseStatement(
      context: context,
      expenses: selectedExpenses,
      from: _startOfDay(range.start),
      to: _endOfDay(range.end),
      profile: store.storeProfile,
      accountName: selection.label,
      locale: Localizations.localeOf(context),
    );
  } catch (error) {
    if (!context.mounted) return;
    _showPrintError(context, error);
  }
}

Future<Map<String, String>> _resolveExpenseAccountIds(
  List<Expense> expenses,
) async {
  final roles = expenses
      .where((expense) => !expense.isDeleted)
      .map(AccountingService.expenseAccountRoleKeyForReport)
      .toSet();
  final result = <String, String>{};
  for (final role in roles) {
    try {
      result[role] = await AccountingService.resolveAccountRole(role);
    } catch (_) {
      // Keep the report usable if an old/custom expense has no role mapping.
    }
  }
  return <String, String>{
    for (final expense in expenses)
      expense.id:
          result[AccountingService.expenseAccountRoleKeyForReport(expense)] ??
              '',
  };
}

Future<_ExpenseAccountSelection?> _pickExpenseAccount(
  BuildContext context,
  List<AccountingAccount> accounts,
) async {
  final expenseAccounts = accounts
      .where((account) => account.type.trim().toLowerCase() == 'expense')
      .toList(growable: false);
  if (expenseAccounts.isEmpty) {
    return _ExpenseAccountSelection(
      accountIds: null,
      label: _allAccountsLabel(context),
    );
  }
  return showDialog<_ExpenseAccountSelection>(
    context: context,
    builder: (_) => _ExpenseAccountFilterDialog(accounts: expenseAccounts),
  );
}

String _allAccountsLabel(BuildContext context) {
  final languageCode = Localizations.localeOf(context).languageCode;
  if (languageCode == 'ar') return 'كل الحسابات';
  if (languageCode == 'fr') return 'Tous les comptes';
  return 'All accounts';
}

class _ExpenseAccountSelection {
  const _ExpenseAccountSelection(
      {required this.accountIds, required this.label});

  final Set<String>? accountIds;
  final String label;
}

class _ExpenseAccountFilterDialog extends StatefulWidget {
  const _ExpenseAccountFilterDialog({required this.accounts});

  final List<AccountingAccount> accounts;

  @override
  State<_ExpenseAccountFilterDialog> createState() =>
      _ExpenseAccountFilterDialogState();
}

class _ExpenseAccountFilterDialogState
    extends State<_ExpenseAccountFilterDialog> {
  String? selectedParentId;
  String? selectedAccountId;

  Map<String, List<AccountingAccount>> get _childrenByParent {
    final result = <String, List<AccountingAccount>>{};
    for (final account in widget.accounts) {
      if (account.parentId.trim().isNotEmpty) {
        (result[account.parentId] ??= <AccountingAccount>[]).add(account);
      }
    }
    for (final children in result.values) {
      children.sort((a, b) => a.code.compareTo(b.code));
    }
    return result;
  }

  List<AccountingAccount> get _roots {
    final ids = widget.accounts.map((account) => account.id).toSet();
    final roots = widget.accounts
        .where((account) =>
            account.parentId.trim().isEmpty ||
            !ids.contains(account.parentId.trim()))
        .toList(growable: false);
    return roots..sort((a, b) => a.code.compareTo(b.code));
  }

  List<AccountingAccount> _branch(String rootId) {
    final children = _childrenByParent;
    final result = <AccountingAccount>[];
    void visit(String parentId) {
      for (final child in children[parentId] ?? const <AccountingAccount>[]) {
        result.add(child);
        visit(child.id);
      }
    }

    final root = widget.accounts.where((account) => account.id == rootId);
    if (root.isNotEmpty) result.add(root.first);
    visit(rootId);
    return result;
  }

  String _text(String ar, String en, String fr) {
    final languageCode = Localizations.localeOf(context).languageCode;
    if (languageCode == 'ar') return ar;
    if (languageCode == 'fr') return fr;
    return en;
  }

  String _accountLabel(AccountingAccount account, {bool indent = false}) =>
      '${indent ? '   ' : ''}${account.code} - ${account.name}';

  @override
  Widget build(BuildContext context) {
    final branches = selectedParentId == null
        ? const <AccountingAccount>[]
        : _branch(selectedParentId!);
    final allLabel = _allAccountsLabel(context);
    final allChildrenLabel = _text(
      'كل الحسابات الفرعية',
      'All sub-accounts',
      'Tous les sous-comptes',
    );
    return AlertDialog(
      title: Text(_text('فلترة حساب المصاريف', 'Expense account filter',
          'Filtre du compte de dépenses')),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String?>(
              initialValue: selectedParentId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _text(
                    'الحساب الأساسي', 'Primary account', 'Compte principal'),
              ),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(allLabel)),
                ..._roots.map((account) => DropdownMenuItem<String?>(
                      value: account.id,
                      child: Text(_accountLabel(account)),
                    )),
              ],
              onChanged: (value) => setState(() {
                selectedParentId = value;
                selectedAccountId = null;
              }),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              initialValue: selectedAccountId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _text('الحساب الفرعي', 'Sub-account', 'Sous-compte'),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(selectedParentId == null
                      ? _text(
                          'اختر الحساب الأساسي أولًا',
                          'Select a primary account first',
                          'Sélectionnez d’abord un compte principal')
                      : allChildrenLabel),
                ),
                ...branches.map((account) => DropdownMenuItem<String?>(
                      value: account.id,
                      child: Text(_accountLabel(account,
                          indent: account.id != selectedParentId)),
                    )),
              ],
              onChanged: selectedParentId == null
                  ? null
                  : (value) => setState(() => selectedAccountId = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_text('إلغاء', 'Cancel', 'Annuler')),
        ),
        FilledButton(
          onPressed: () {
            final ids = selectedParentId == null
                ? null
                : (selectedAccountId == null
                    ? _branch(selectedParentId!)
                        .map((account) => account.id)
                        .toSet()
                    : _branch(selectedAccountId!)
                        .map((account) => account.id)
                        .toSet());
            final selected = selectedAccountId == null
                ? (selectedParentId == null
                    ? allLabel
                    : _accountLabel(_roots.firstWhere(
                        (account) => account.id == selectedParentId)))
                : _accountLabel(branches
                    .firstWhere((account) => account.id == selectedAccountId));
            Navigator.pop(
              context,
              _ExpenseAccountSelection(accountIds: ids, label: selected),
            );
          },
          child: Text(_text('متابعة', 'Continue', 'Continuer')),
        ),
      ],
    );
  }
}

DateTime _startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _endOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day, 23, 59, 59, 999);

String _dateRangeText(BuildContext context, String key) {
  final languageCode = Localizations.localeOf(context).languageCode;
  if (languageCode == 'ar') {
    return key == 'save' ? 'تم' : 'حدد فترة الكشف';
  }
  if (languageCode == 'fr') {
    return key == 'save' ? 'Terminé' : 'Sélectionner la période';
  }
  return key == 'save' ? 'Done' : 'Select statement period';
}

void _showPrintError(BuildContext context, Object error) {
  final languageCode = Localizations.localeOf(context).languageCode;
  final prefix = languageCode == 'ar'
      ? 'تعذر طباعة كشف الحساب'
      : languageCode == 'fr'
          ? 'Impossible d’imprimer le relevé'
          : 'Could not print the statement';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$prefix: $error')),
  );
}
