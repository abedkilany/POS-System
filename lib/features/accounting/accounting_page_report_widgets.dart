part of 'accounting_page.dart';

class _AccountSelector extends StatelessWidget {
  const _AccountSelector(
      {required this.accounts, required this.value, required this.onChanged});

  final List<AccountingAccount> accounts;
  final String? value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        labelText: tr.text('mapped_account'),
      ),
      items: [
        for (final account in accounts.where((account) => account.isPostable))
          DropdownMenuItem<String>(
            value: account.id,
            child: Text(
                '${account.code} • ${_localizedAccountingName(account.name, tr)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged == null
          ? null
          : (accountId) {
              if (accountId == null ||
                  accountId.trim().isEmpty ||
                  accountId == value) {
                return;
              }
              onChanged!(accountId);
            },
    );
  }
}

class _FinancialReportTitle extends StatelessWidget {
  const _FinancialReportTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _ReportBalanceBanner extends StatelessWidget {
  const _ReportBalanceBanner({
    required this.isBalanced,
    required this.balancedText,
    required this.warningText,
  });

  final bool isBalanced;
  final String balancedText;
  final String warningText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = isBalanced
        ? scheme.primaryContainer.withValues(alpha: 0.35)
        : scheme.errorContainer.withValues(alpha: 0.55);
    final foreground =
        isBalanced ? scheme.onPrimaryContainer : scheme.onErrorContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            isBalanced
                ? Icons.check_circle_outline
                : Icons.warning_amber_rounded,
            size: 20,
            color: foreground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isBalanced ? balancedText : warningText,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinancialBreakdownSection extends StatelessWidget {
  const _FinancialBreakdownSection({
    required this.store,
    required this.title,
    required this.totalLabel,
    required this.totalAmount,
    this.rows = const <_StatementRow>[],
    this.accountLines = const <FinancialStatementAccountLine>[],
  });

  final ApplicationSession store;
  final String title;
  final String totalLabel;
  final double totalAmount;
  final List<_StatementRow> rows;
  final List<FinancialStatementAccountLine> accountLines;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          for (final row in rows)
            _FinancialStatementLine(
              label: row.label,
              amount: row.amount,
              store: store,
              highlight: row.highlight,
            ),
          if (accountLines.isNotEmpty)
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              childrenPadding: const EdgeInsets.only(bottom: 6),
              title: Text(
                _accountingUiText(context, 'تفاصيل الحسابات', 'Account details',
                    'Détails des comptes'),
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                _accountingUiText(
                    context,
                    '${accountLines.length} حساب',
                    '${accountLines.length} accounts',
                    '${accountLines.length} comptes'),
              ),
              children: [
                for (final line in accountLines)
                  _FinancialStatementLine(
                    label:
                        '${line.accountCode} • ${_localizedAccountingName(line.accountName, tr)}',
                    amount: line.amount,
                    store: store,
                    compact: true,
                  ),
              ],
            ),
          const Divider(height: 1),
          _FinancialStatementLine(
            label: totalLabel,
            amount: totalAmount,
            store: store,
            highlight: true,
          ),
        ],
      ),
    );
  }
}

class _FinancialStatementLine extends StatelessWidget {
  const _FinancialStatementLine({
    required this.label,
    required this.amount,
    required this.store,
    this.highlight = false,
    this.compact = false,
  });

  final String label;
  final double amount;
  final ApplicationSession store;
  final bool highlight;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = highlight
        ? Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w800)
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: compact ? 6 : 9,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: style,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(_money(store, amount), style: style),
        ],
      ),
    );
  }
}

class _FinancialResultTile extends StatelessWidget {
  const _FinancialResultTile({
    required this.store,
    required this.label,
    required this.amount,
    this.prominent = false,
  });

  final ApplicationSession store;
  final String label;
  final double amount;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: prominent
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            _money(store, amount),
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _FinancialSummaryChip extends StatelessWidget {
  const _FinancialSummaryChip({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: emphasized
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 3),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _StatementCard extends StatelessWidget {
  const _StatementCard(
      {required this.store, required this.title, required this.rows});

  final ApplicationSession store;
  final String title;
  final List<_StatementRow> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: rows.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
            );
          }
          final row = rows[index - 1];
          final style = row.highlight
              ? Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)
              : Theme.of(context).textTheme.bodyLarge;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(child: Text(row.label, style: style)),
                Text(_money(store, row.amount), style: style),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatementRow {
  const _StatementRow(this.label, this.amount, {this.highlight = false});

  final String label;
  final double amount;
  final bool highlight;
}

class _ReportError extends StatelessWidget {
  const _ReportError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      );
}

String _money(ApplicationSession store, double amount) =>
    formatUsdReferenceAmount(amount, store.runtime.profile);

String _dateText(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class _EmptyAccountingState extends StatelessWidget {
  const _EmptyAccountingState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _AccountingMetrics {
  const _AccountingMetrics({
    required this.customerReceivables,
    required this.customerCredits,
    required this.supplierPayables,
    required this.supplierAdvances,
    required this.todayCashIn,
    required this.todayCashOut,
    required this.cashBalance,
    required this.bankBalance,
    required this.monthNetSales,
    required this.monthGrossProfit,
    required this.monthExpenses,
    required this.monthNetProfit,
  });

  final double customerReceivables;
  final double customerCredits;
  final double supplierPayables;
  final double supplierAdvances;
  final double todayCashIn;
  final double todayCashOut;
  final double cashBalance;
  final double bankBalance;
  final double monthNetSales;
  final double monthGrossProfit;
  final double monthExpenses;
  final double monthNetProfit;

  factory _AccountingMetrics.fromSummary(Map<String, Object?> summary) {
    return _AccountingMetrics(
      customerReceivables: _doubleValue(summary['customerReceivables']),
      customerCredits: _doubleValue(summary['customerCredits']),
      supplierPayables: _doubleValue(summary['supplierPayables']),
      supplierAdvances: _doubleValue(summary['supplierAdvances']),
      todayCashIn: _doubleValue(summary['todayCashIn']),
      todayCashOut: _doubleValue(summary['todayCashOut']),
      cashBalance: _doubleValue(summary['cashBalance']),
      bankBalance: _doubleValue(summary['bankBalance']),
      monthNetSales: _doubleValue(summary['monthNetSales']),
      monthGrossProfit: _doubleValue(summary['monthGrossProfit']),
      monthExpenses: _doubleValue(summary['monthExpenses']),
      monthNetProfit: _doubleValue(summary['monthNetProfit']),
    );
  }
}

double _doubleValue(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _localizedAccountingType(String value, AppLocalizations tr) {
  final normalized =
      value.trim().toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');
  if (normalized.isEmpty) return '';
  const keys = <String, String>{
    'asset': 'account_type_asset',
    'liability': 'account_type_liability',
    'equity': 'account_type_equity',
    'revenue': 'account_type_revenue',
    'expense': 'account_type_expense',
    'cost_of_sales': 'account_type_cost_of_sales',
    'cash': 'payment_type_cash',
    'bank': 'payment_type_bank',
    'card': 'payment_type_card',
    'cheque': 'payment_type_cheque',
    'check': 'payment_type_cheque',
    'cash_drawer': 'cash_drawer',
    'main_vault': 'main_vault',
    'branch_vault': 'branch_vault',
    'wallet': 'wallet',
    'other': 'other',
    'overage': 'overage',
    'shortage': 'shortage',
    'balanced': 'balanced',
    'accounting_period': 'accounting_period',
    'fixed_asset': 'fixed_asset',
    'cost_center': 'cost_center',
    'branch': 'branch',
  };
  final key = keys[normalized];
  return key == null ? value : tr.text(key);
}

String _localizedAccountingStatus(String value, AppLocalizations tr) {
  final normalized =
      value.trim().toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');
  if (normalized.isEmpty) return '';
  if (normalized == 'reversed') {
    final language = tr.locale.languageCode;
    if (language == 'ar') return 'معكوس';
    if (language == 'fr') return 'Extournée';
    return 'Reversed';
  }
  const keys = <String, String>{
    'active': 'status_active',
    'inactive': 'status_inactive',
    'open': 'status_open',
    'closed': 'status_closed',
    'pending': 'status_pending',
    'cleared': 'status_cleared',
    'bounced': 'status_bounced',
    'cancelled': 'status_cancelled',
    'canceled': 'status_cancelled',
    'deposited': 'status_deposited',
    'collected': 'status_collected',
    'draft': 'status_draft',
    'posted': 'status_posted',
    'void': 'status_void',
  };
  final key = keys[normalized];
  return key == null ? value : tr.text(key);
}

String _localizedAccountingName(String value, AppLocalizations tr) {
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll(' & ', ' and ')
      .replaceAll('&', 'and')
      .replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return '';
  const keys = <String, String>{
    'assets': 'coa_assets',
    'cash': 'coa_cash',
    'bank': 'coa_bank',
    'customers / accounts receivable': 'coa_customers_receivable',
    'inventory': 'coa_inventory',
    'fixed assets': 'coa_fixed_assets',
    'accumulated depreciation': 'coa_accumulated_depreciation',
    'vat input / recoverable tax': 'coa_vat_input',
    'liabilities': 'coa_liabilities',
    'suppliers / accounts payable': 'coa_suppliers_payable',
    'vat output / tax payable': 'coa_vat_output',
    'equity': 'coa_equity',
    'owner capital': 'coa_owner_capital',
    'revenue': 'coa_revenue',
    'sales revenue': 'coa_sales_revenue',
    'cost of sales': 'coa_cost_of_sales',
    'cost of goods sold': 'coa_cogs',
    'expenses': 'coa_expenses',
    'general expenses': 'coa_general_expenses',
    'cash over / short': 'coa_cash_over_short',
    'depreciation expense': 'coa_depreciation_expense',
    'cash drawer': 'cash_drawer',
    'bank / card': 'bank_card',
    'main cost center': 'main_cost_center',
    'main branch': 'main_branch',
    'default cost center': 'default_cost_center',
    'default accounting branch': 'default_accounting_branch',
  };
  final key = keys[normalized];
  return key == null ? value : tr.text(key);
}

String _localizedAccountingNote(String value, AppLocalizations tr) {
  final normalized = value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return '';
  const keys = <String, String>{
    'default payment account for advanced accounting':
        'default_payment_account_advanced',
    'default cost center': 'default_cost_center',
    'default accounting branch': 'default_accounting_branch',
  };
  final key = keys[normalized];
  return key == null ? value : tr.text(key);
}

String _normalizedSearchQuery(String query) => query.trim().toLowerCase();

bool _matchesNormalized(String normalizedQuery, List<String?> values) {
  if (normalizedQuery.isEmpty) return true;
  return values
      .whereType<String>()
      .any((value) => value.toLowerCase().contains(normalizedQuery));
}

String _joinParts(List<String?> values) => values
    .whereType<String>()
    .where((part) => part.trim().isNotEmpty)
    .join(' • ');
