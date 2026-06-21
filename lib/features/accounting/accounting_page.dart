import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/responsive.dart';
import '../../core/services/accounting_service.dart';
import '../../data/app_store.dart';
import '../../models/account_transaction.dart';
import '../../models/accounting_account.dart';
import '../../models/journal_entry.dart';
import '../../models/user_role.dart';
import '../accounts/account_ledger_widgets.dart';

class AccountingPage extends StatefulWidget {
  const AccountingPage({super.key, required this.store});

  final AppStore store;

  @override
  State<AccountingPage> createState() => _AccountingPageState();
}

class _AccountingPageState extends State<AccountingPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 11, vsync: this);
    _searchController.addListener(() => setState(() => _query = _searchController.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final metrics = _AccountingMetrics.fromStore(widget.store);

    return Padding(
      padding: VentioResponsive.pageInsets(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AccountingHeader(
            title: tr.text('accounting'),
            onRefresh: () => setState(() {}),
          ),
          const SizedBox(height: 12),
          _CompactSummaryStrip(store: widget.store, metrics: metrics),
          const SizedBox(height: 12),
          _AccountingTabs(controller: _tabController),
          const SizedBox(height: 10),
          _AccountingSearchField(controller: _searchController, query: _query),
          const SizedBox(height: 10),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _AccountsTab(store: widget.store, query: _query, accountType: 'customer'),
                _AccountsTab(store: widget.store, query: _query, accountType: 'supplier'),
                _TransactionsTab(store: widget.store, query: _query, cashOnly: true),
                _TransactionsTab(store: widget.store, query: _query, cashOnly: false),
                _GeneralLedgerTab(store: widget.store, query: _query),
                _TrialBalanceTab(store: widget.store, query: _query),
                _IncomeStatementTab(store: widget.store),
                _BalanceSheetTab(store: widget.store),
                _CashBankReportTab(store: widget.store),
                _AdvancedAccountingTab(store: widget.store),
                _AccountingSettingsTab(store: widget.store),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountingHeader extends StatelessWidget {
  const _AccountingHeader({required this.title, required this.onRefresh});

  final String title;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                AppLocalizations.of(context).text('recent_transactions'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: AppLocalizations.of(context).text('refresh'),
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _CompactSummaryStrip extends StatelessWidget {
  const _CompactSummaryStrip({required this.store, required this.metrics});

  final AppStore store;
  final _AccountingMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final cards = [
      _SummaryMetric(icon: Icons.people_outline, title: tr.text('customer_receivables'), amount: metrics.customerReceivables),
      _SummaryMetric(icon: Icons.local_shipping_outlined, title: tr.text('supplier_payables'), amount: metrics.supplierPayables),
      _SummaryMetric(icon: Icons.south_west, title: tr.text('today_cash_in'), amount: metrics.todayCashIn),
      _SummaryMetric(icon: Icons.north_east, title: tr.text('today_cash_out'), amount: metrics.todayCashOut),
      _SummaryMetric(icon: Icons.assignment_return_outlined, title: tr.text('customer_credits'), amount: metrics.customerCredits, subtle: true),
      _SummaryMetric(icon: Icons.inventory_outlined, title: tr.text('supplier_advances'), amount: metrics.supplierAdvances, subtle: true),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) => SizedBox(width: 220, child: _SummaryTile(store: store, metric: cards[index])),
            ),
          );
        }

        final itemWidth = constraints.maxWidth >= 1200
            ? (constraints.maxWidth - 40) / 6
            : constraints.maxWidth >= 950
                ? (constraints.maxWidth - 24) / 4
                : (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final metric in cards) SizedBox(width: itemWidth, height: 82, child: _SummaryTile(store: store, metric: metric)),
          ],
        );
      },
    );
  }
}

class _SummaryMetric {
  const _SummaryMetric({required this.icon, required this.title, required this.amount, this.subtle = false});

  final IconData icon;
  final String title;
  final double amount;
  final bool subtle;
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.store, required this.metric});

  final AppStore store;
  final _SummaryMetric metric;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: metric.subtle ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.55) : colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(metric.icon, size: 22, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(metric.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 3),
                  Text(
                    formatUsdReferenceAmount(metric.amount, store.storeProfile),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountingTabs extends StatelessWidget {
  const _AccountingTabs({required this.controller});

  final TabController controller;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: TabBar(
          controller: controller,
          isScrollable: true,
          tabs: [
            Tab(icon: const Icon(Icons.person_outline), text: tr.text('customers')),
            Tab(icon: const Icon(Icons.local_shipping_outlined), text: tr.text('suppliers')),
            Tab(icon: const Icon(Icons.payments_outlined), text: tr.text('cash_movement')),
            Tab(icon: const Icon(Icons.history_outlined), text: tr.text('recent_transactions')),
            const Tab(icon: Icon(Icons.menu_book_outlined), text: 'General Ledger'),
            const Tab(icon: Icon(Icons.balance_outlined), text: 'Trial Balance'),
            const Tab(icon: Icon(Icons.trending_up_outlined), text: 'Income Statement'),
            const Tab(icon: Icon(Icons.account_balance_outlined), text: 'Balance Sheet'),
            const Tab(icon: Icon(Icons.account_balance_wallet_outlined), text: 'Cash / Bank'),
            const Tab(icon: Icon(Icons.auto_awesome_motion_outlined), text: 'Advanced'),
            const Tab(icon: Icon(Icons.settings_outlined), text: 'Settings'),
          ],
        ),
      ),
    );
  }
}

class _AccountingSearchField extends StatelessWidget {
  const _AccountingSearchField({required this.controller, required this.query});

  final TextEditingController controller;
  final String query;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        prefixIcon: const Icon(Icons.search),
        labelText: AppLocalizations.of(context).text('search_accounts'),
        suffixIcon: query.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: controller.clear),
      ),
    );
  }
}

class _AccountsTab extends StatelessWidget {
  const _AccountsTab({required this.store, required this.query, required this.accountType});

  final AppStore store;
  final String query;
  final String accountType;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final rows = accountType == 'customer'
        ? store.customers
            .where((customer) => _matches(query, [customer.name, customer.phone, customer.address]))
            .map((customer) => _AccountRowData(
                  id: customer.id,
                  name: customer.name,
                  subtitle: [customer.phone, customer.address].where((part) => part.trim().isNotEmpty).join(' • '),
                  balance: store.accountBalance('customer', customer.id),
                ))
            .toList()
        : store.suppliers
            .where((supplier) => _matches(query, [supplier.name, supplier.nameEn, supplier.nameAr, supplier.phone, supplier.address]))
            .map((supplier) => _AccountRowData(
                  id: supplier.id,
                  name: supplier.name,
                  subtitle: [supplier.phone, supplier.address].where((part) => part.trim().isNotEmpty).join(' • '),
                  balance: store.accountBalance('supplier', supplier.id),
                ))
            .toList();
    rows.sort((a, b) => b.balance.abs().compareTo(a.balance.abs()));

    if (rows.isEmpty) {
      return _EmptyAccountingState(message: tr.text(accountType == 'customer' ? 'no_customers_found' : 'no_suppliers_found'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: ListView.separated(
            itemCount: rows.length + (isWide ? 1 : 0),
            separatorBuilder: (_, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (isWide && index == 0) return _AccountTableHeader(accountType: accountType);
              final row = rows[isWide ? index - 1 : index];
              return _AccountListRow(store: store, accountType: accountType, row: row, isWide: isWide);
            },
          ),
        );
      },
    );
  }
}

class _AccountRowData {
  const _AccountRowData({required this.id, required this.name, required this.subtitle, required this.balance});

  final String id;
  final String name;
  final String subtitle;
  final double balance;
}

class _AccountTableHeader extends StatelessWidget {
  const _AccountTableHeader({required this.accountType});

  final String accountType;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(tr.text(accountType == 'customer' ? 'customer' : 'supplier'), style: TextStyle(color: color, fontWeight: FontWeight.w700))),
          Expanded(flex: 2, child: Text(tr.text('balance'), style: TextStyle(color: color, fontWeight: FontWeight.w700))),
          const SizedBox(width: 260),
        ],
      ),
    );
  }
}

class _AccountListRow extends StatelessWidget {
  const _AccountListRow({required this.store, required this.accountType, required this.row, required this.isWide});

  final AppStore store;
  final String accountType;
  final _AccountRowData row;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final color = accountBalanceColor(context, store, accountType, row.id);
    final actions = [
      OutlinedButton.icon(
        onPressed: () => showAccountLedgerSheet(context: context, store: store, accountType: accountType, accountId: row.id, accountName: row.name),
        icon: const Icon(Icons.list_alt_outlined, size: 18),
        label: Text(tr.text('account_ledger')),
      ),
      FilledButton.icon(
        onPressed: () => showAccountPaymentDialog(context: context, store: store, accountType: accountType, accountId: row.id, accountName: row.name),
        icon: Icon(accountType == 'customer' ? Icons.call_received : Icons.call_made, size: 18),
        label: Text(accountType == 'customer' ? tr.text('receive_payment') : tr.text('pay_supplier')),
      ),
    ];

    if (!isWide) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 18, child: Icon(accountType == 'customer' ? Icons.person_outline : Icons.local_shipping_outlined, size: 20)),
                const SizedBox(width: 10),
                Expanded(child: Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                Text(formatUsdReferenceAmount(row.balance.abs(), store.storeProfile), style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w800)),
              ],
            ),
            if (row.subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(row.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                CircleAvatar(radius: 17, child: Icon(accountType == 'customer' ? Icons.person_outline : Icons.local_shipping_outlined, size: 19)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      if (row.subtitle.isNotEmpty)
                        Text(row.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(formatUsdReferenceAmount(row.balance.abs(), store.storeProfile), style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
          ),
          SizedBox(
            width: 260,
            child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
          ),
        ],
      ),
    );
  }
}

class _TransactionsTab extends StatelessWidget {
  const _TransactionsTab({required this.store, required this.query, required this.cashOnly});

  final AppStore store;
  final String query;
  final bool cashOnly;

  @override
  Widget build(BuildContext context) {
    final rows = store.accountTransactions
        .where((txn) => (!cashOnly || _isCashTxn(txn)) && _matches(query, [txn.accountName, txn.referenceNo, txn.paymentMethod, txn.note, txn.type]))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    if (rows.isEmpty) {
      return _EmptyAccountingState(message: AppLocalizations.of(context).text(cashOnly ? 'no_cash_movements' : 'no_account_transactions'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 780;
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: ListView.separated(
            itemCount: rows.length + (isWide ? 1 : 0),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (isWide && index == 0) return const _TransactionTableHeader();
              final transaction = rows[isWide ? index - 1 : index];
              return _TransactionRow(store: store, transaction: transaction, isWide: isWide);
            },
          ),
        );
      },
    );
  }

  bool _isCashTxn(AccountTransaction txn) => txn.type == 'paymentReceived' || txn.type == 'paymentPaid' || txn.type == 'paymentReversal';
}

class _TransactionTableHeader extends StatelessWidget {
  const _TransactionTableHeader();

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final style = TextStyle(color: color, fontWeight: FontWeight.w700);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(tr.text('date'), style: style)),
          Expanded(flex: 2, child: Text(tr.text('type'), style: style)),
          Expanded(flex: 3, child: Text(tr.text('account'), style: style)),
          Expanded(flex: 2, child: Text(tr.text('reference'), style: style)),
          SizedBox(width: 130, child: Text(tr.text('amount'), style: style, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.store, required this.transaction, required this.isWide});

  final AppStore store;
  final AccountTransaction transaction;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final amount = transaction.debit > 0 ? transaction.debit : transaction.credit;
    final sign = _displaySign(transaction);
    final amountText = '$sign ${formatUsdReferenceAmount(amount, store.storeProfile)}';
    final accountName = transaction.accountName.trim().isEmpty ? tr.text(transaction.accountType == 'supplier' ? 'supplier' : 'customer') : transaction.accountName;
    final typeText = _typeTitle(context, transaction.type);
    final methodText = transaction.paymentMethod.isEmpty ? '' : _paymentMethodLabel(context, transaction.paymentMethod);
    final note = transaction.note.trim();
    final color = sign == '+' ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error;

    if (!isWide) {
      return ListTile(
        leading: CircleAvatar(child: Icon(_iconForType(transaction.type), size: 20)),
        title: Text(accountName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text([
          _dateText(transaction.date),
          typeText,
          transaction.referenceNo,
          methodText,
          note,
        ].where((part) => part.trim().isNotEmpty).join(' • '), maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Text(amountText, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(_dateText(transaction.date))),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Icon(_iconForType(transaction.type), size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text(typeText, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          Expanded(flex: 3, child: Text(accountName, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: Text([transaction.referenceNo, methodText].where((part) => part.trim().isNotEmpty).join(' • '), maxLines: 1, overflow: TextOverflow.ellipsis)),
          SizedBox(width: 130, child: Text(amountText, textAlign: TextAlign.end, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }

  String _displaySign(AccountTransaction transaction) {
    if (transaction.type == 'paymentReceived') return '+';
    if (transaction.type == 'paymentPaid') return '-';
    if (transaction.type == 'paymentReversal' && transaction.accountType == 'supplier') return '+';
    if (transaction.type == 'paymentReversal' && transaction.accountType == 'customer') return '-';
    return transaction.debit > 0 ? '+' : '-';
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'saleInvoice':
        return Icons.receipt_long_outlined;
      case 'purchaseInvoice':
        return Icons.inventory_2_outlined;
      case 'paymentReceived':
        return Icons.call_received;
      case 'paymentPaid':
        return Icons.call_made;
      case 'paymentReversal':
      case 'cancel':
        return Icons.undo_outlined;
      default:
        return Icons.swap_horiz_outlined;
    }
  }

  String _typeTitle(BuildContext context, String type) {
    final tr = AppLocalizations.of(context);
    switch (type) {
      case 'saleInvoice':
        return tr.text('sale_invoice');
      case 'purchaseInvoice':
        return tr.text('purchase_invoice');
      case 'paymentReceived':
        return tr.text('payment_received');
      case 'paymentPaid':
        return tr.text('payment_paid');
      case 'paymentReversal':
        return tr.text('payment_reversal');
      case 'cancel':
        return tr.text('cancellation_reversal');
      case 'adjustment':
        return tr.text('adjustment');
      default:
        return type;
    }
  }

  String _paymentMethodLabel(BuildContext context, String method) {
    final tr = AppLocalizations.of(context);
    switch (method.toLowerCase()) {
      case 'cash':
        return tr.text('payment_cash');
      case 'card':
        return tr.text('payment_card');
      case 'wish':
        return tr.text('payment_wish');
      case 'check':
        return tr.text('payment_check');
      default:
        return method;
    }
  }

  String _dateText(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}



class _GeneralLedgerTab extends StatelessWidget {
  const _GeneralLedgerTab({required this.store, required this.query});

  final AppStore store;
  final String query;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GeneralLedgerAccountReport>>(
      future: AccountingService.generalLedgerReport(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
        final rows = (snapshot.data ?? <GeneralLedgerAccountReport>[])
            .where((account) => account.lines.isNotEmpty && _matches(query, [account.accountCode, account.accountName, account.accountType]))
            .toList();
        if (rows.isEmpty) {
          return const _EmptyAccountingState(message: 'No journal entries found.');
        }
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final account = rows[index];
            return Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text('${account.accountCode} • ${account.accountName}', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('Debit ${_money(store, account.totalDebit)} • Credit ${_money(store, account.totalCredit)}'),
                trailing: Text(_money(store, account.closingBalance), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                children: [
                  _LedgerLinesTable(store: store, lines: account.lines),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _LedgerLinesTable extends StatelessWidget {
  const _LedgerLinesTable({required this.store, required this.lines});

  final AppStore store;
  final List<GeneralLedgerLineReport> lines;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Entry')),
          DataColumn(label: Text('Reference')),
          DataColumn(label: Text('Description')),
          DataColumn(label: Text('Debit'), numeric: true),
          DataColumn(label: Text('Credit'), numeric: true),
          DataColumn(label: Text('Balance'), numeric: true),
        ],
        rows: [
          for (final line in lines.take(200))
            DataRow(cells: [
              DataCell(Text(_dateText(line.entryDate))),
              DataCell(Text(line.entryNo)),
              DataCell(Text([line.referenceType, line.referenceNo].where((part) => part.trim().isNotEmpty).join(' • '))),
              DataCell(SizedBox(width: 260, child: Text(line.memo.isEmpty ? line.description : line.memo, overflow: TextOverflow.ellipsis))),
              DataCell(Text(_money(store, line.debit))),
              DataCell(Text(_money(store, line.credit))),
              DataCell(Text(_money(store, line.runningBalance))),
            ]),
        ],
      ),
    );
  }
}

class _TrialBalanceTab extends StatelessWidget {
  const _TrialBalanceTab({required this.store, required this.query});

  final AppStore store;
  final String query;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TrialBalanceRowReport>>(
      future: AccountingService.trialBalanceReport(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
        final rows = (snapshot.data ?? <TrialBalanceRowReport>[])
            .where((row) => (row.debit != 0 || row.credit != 0) && _matches(query, [row.accountCode, row.accountName, row.accountType]))
            .toList();
        final totalDebit = rows.fold<double>(0, (sum, row) => sum + row.debit);
        final totalCredit = rows.fold<double>(0, (sum, row) => sum + row.credit);
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Code')),
                  DataColumn(label: Text('Account')),
                  DataColumn(label: Text('Type')),
                  DataColumn(label: Text('Debit'), numeric: true),
                  DataColumn(label: Text('Credit'), numeric: true),
                  DataColumn(label: Text('Balance'), numeric: true),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(cells: [
                      DataCell(Text(row.accountCode)),
                      DataCell(Text(row.accountName)),
                      DataCell(Text(row.accountType)),
                      DataCell(Text(_money(store, row.debit))),
                      DataCell(Text(_money(store, row.credit))),
                      DataCell(Text(_money(store, row.balance))),
                    ]),
                  DataRow(cells: [
                    const DataCell(Text('')),
                    const DataCell(Text('Totals')),
                    const DataCell(Text('')),
                    DataCell(Text(_money(store, totalDebit))),
                    DataCell(Text(_money(store, totalCredit))),
                    DataCell(Text(_money(store, totalDebit - totalCredit))),
                  ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IncomeStatementTab extends StatelessWidget {
  const _IncomeStatementTab({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<IncomeStatementReport>(
      future: AccountingService.incomeStatementReport(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
        final report = snapshot.data ?? const IncomeStatementReport(revenue: 0, costOfGoodsSold: 0, grossProfit: 0, expenses: 0, netProfit: 0);
        return _StatementCard(
          store: store,
          title: 'Income Statement',
          rows: [
            _StatementRow('Sales Revenue', report.revenue),
            _StatementRow('Cost of Goods Sold', -report.costOfGoodsSold),
            _StatementRow('Gross Profit', report.grossProfit, highlight: true),
            _StatementRow('Expenses', -report.expenses),
            _StatementRow('Net Profit', report.netProfit, highlight: true),
          ],
        );
      },
    );
  }
}

class _BalanceSheetTab extends StatelessWidget {
  const _BalanceSheetTab({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BalanceSheetReport>(
      future: AccountingService.balanceSheetReport(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
        final report = snapshot.data ?? const BalanceSheetReport(assets: 0, liabilities: 0, equity: 0, retainedEarnings: 0, liabilitiesAndEquity: 0, difference: 0);
        return _StatementCard(
          store: store,
          title: 'Balance Sheet',
          rows: [
            _StatementRow('Assets', report.assets, highlight: true),
            _StatementRow('Liabilities', report.liabilities),
            _StatementRow('Equity', report.equity),
            _StatementRow('Current Profit / Loss', report.retainedEarnings),
            _StatementRow('Liabilities + Equity', report.liabilitiesAndEquity, highlight: true),
            _StatementRow('Difference', report.difference, highlight: report.difference.abs() > 0.009),
          ],
        );
      },
    );
  }
}

class _CashBankReportTab extends StatelessWidget {
  const _CashBankReportTab({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CashBankMovementReport>>(
      future: AccountingService.cashBankMovementReport(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
        final rows = snapshot.data ?? <CashBankMovementReport>[];
        if (rows.isEmpty) {
          return const _EmptyAccountingState(message: 'No cash or bank movements found.');
        }
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final row = rows[index];
              return ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text('${row.accountCode} • ${row.accountName}'),
                subtitle: Text('In ${_money(store, row.moneyIn)} • Out ${_money(store, row.moneyOut)}'),
                trailing: Text(_money(store, row.closingBalance), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              );
            },
          ),
        );
      },
    );
  }
}



class _AdvancedAccountingTab extends StatefulWidget {
  const _AdvancedAccountingTab({required this.store});

  final AppStore store;

  @override
  State<_AdvancedAccountingTab> createState() => _AdvancedAccountingTabState();
}

class _AdvancedAccountingTabState extends State<_AdvancedAccountingTab> {
  late Future<_AdvancedAccountingData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_AdvancedAccountingData> _load() async {
    final results = await Future.wait<Object>([
      AccountingService.listPaymentAccounts(),
      AccountingService.listCashDrawers(),
      AccountingService.listCheques(),
      AccountingService.listAccountingPeriods(),
      AccountingService.listCostCenters(),
      AccountingService.listAccountingBranches(),
    ]);
    return _AdvancedAccountingData(
      paymentAccounts: results[0] as List<AdvancedAccountingItem>,
      cashDrawers: results[1] as List<AdvancedAccountingItem>,
      cheques: results[2] as List<AdvancedAccountingItem>,
      periods: results[3] as List<AdvancedAccountingItem>,
      costCenters: results[4] as List<AdvancedAccountingItem>,
      branches: results[5] as List<AdvancedAccountingItem>,
    );
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _openDrawerDialog() async {
    final controller = TextEditingController(text: '0');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open Cash Drawer'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Opening balance'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Open')),
        ],
      ),
    );
    if (confirmed == true) {
      await AccountingService.openCashDrawer(drawerNo: 'Main Drawer', openingBalance: double.tryParse(controller.text) ?? 0);
      if (mounted) _refresh();
    }
  }


  Future<void> _manualJournalDialog() async {
    final description = TextEditingController(text: 'Manual journal entry');
    final debitAmount = TextEditingController(text: '0');
    final creditAmount = TextEditingController(text: '0');
    final accounts = await AccountingService.listAccounts();
    final costCenters = await AccountingService.listCostCenters();
    final branches = await AccountingService.listAccountingBranches();
    if (accounts.length < 2) return;
    AccountingAccount? debitAccount = accounts.first;
    AccountingAccount? creditAccount = accounts.length > 1 ? accounts[1] : debitAccount;
    AdvancedAccountingItem? debitCostCenter;
    AdvancedAccountingItem? creditCostCenter;
    AdvancedAccountingItem? branch;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Manual Journal'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: description, decoration: const InputDecoration(labelText: 'Description')),
                const SizedBox(height: 8),
                DropdownButtonFormField<AdvancedAccountingItem?>(
                  initialValue: branch,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Branch'),
                  items: [
                    const DropdownMenuItem<AdvancedAccountingItem?>(value: null, child: Text('No branch')),
                    for (final item in branches) DropdownMenuItem<AdvancedAccountingItem?>(value: item, child: Text('${item.accountCode} - ${item.name}')),
                  ],
                  onChanged: (value) => setDialogState(() => branch = value),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<AccountingAccount>(
                  initialValue: debitAccount,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Debit account'),
                  items: [for (final a in accounts) DropdownMenuItem(value: a, child: Text('${a.code} - ${a.name}'))],
                  onChanged: (value) => setDialogState(() => debitAccount = value),
                ),
                TextField(controller: debitAmount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Debit amount')),
                DropdownButtonFormField<AdvancedAccountingItem?>(
                  initialValue: debitCostCenter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Debit cost center'),
                  items: [
                    const DropdownMenuItem<AdvancedAccountingItem?>(value: null, child: Text('No cost center')),
                    for (final item in costCenters) DropdownMenuItem<AdvancedAccountingItem?>(value: item, child: Text('${item.accountCode} - ${item.name}')),
                  ],
                  onChanged: (value) => setDialogState(() => debitCostCenter = value),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<AccountingAccount>(
                  initialValue: creditAccount,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Credit account'),
                  items: [for (final a in accounts) DropdownMenuItem(value: a, child: Text('${a.code} - ${a.name}'))],
                  onChanged: (value) => setDialogState(() => creditAccount = value),
                ),
                TextField(controller: creditAmount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Credit amount')),
                DropdownButtonFormField<AdvancedAccountingItem?>(
                  initialValue: creditCostCenter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Credit cost center'),
                  items: [
                    const DropdownMenuItem<AdvancedAccountingItem?>(value: null, child: Text('No cost center')),
                    for (final item in costCenters) DropdownMenuItem<AdvancedAccountingItem?>(value: item, child: Text('${item.accountCode} - ${item.name}')),
                  ],
                  onChanged: (value) => setDialogState(() => creditCostCenter = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Post')),
          ],
        ),
      ),
    );
    if (confirmed == true && debitAccount != null && creditAccount != null) {
      final debit = double.tryParse(debitAmount.text) ?? 0;
      final credit = double.tryParse(creditAmount.text) ?? 0;
      final amount = debit > 0 ? debit : credit;
      await AccountingService.createManualJournalEntry(
        entryDate: DateTime.now(),
        description: description.text,
        branchId: branch?.id ?? '',
        lines: [
          JournalLineDraft(accountId: debitAccount!.id, debit: amount, credit: 0, costCenterId: debitCostCenter?.id ?? ''),
          JournalLineDraft(accountId: creditAccount!.id, debit: 0, credit: amount, costCenterId: creditCostCenter?.id ?? ''),
        ],
      );
      if (mounted) _refresh();
    }
  }

  Future<void> _createPaymentAccountDialog() async {
    final name = TextEditingController();
    var type = 'bank';
    var isDefault = false;
    final accounts = await AccountingService.listAccounts();
    if (accounts.isEmpty) return;
    AccountingAccount? selected = accounts.firstWhere((a) => a.type == 'asset', orElse: () => accounts.first);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Payment Account'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const ['cash','bank','card','wallet','cheque','other'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => setDialogState(() => type = v ?? type),
              ),
              DropdownButtonFormField<AccountingAccount>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: 'Mapped account'),
                items: [for (final a in accounts) DropdownMenuItem(value: a, child: Text('${a.code} - ${a.name}'))],
                onChanged: (v) => setDialogState(() => selected = v),
              ),
              CheckboxListTile(value: isDefault, onChanged: (v) => setDialogState(() => isDefault = v ?? false), title: const Text('Default for this type')),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create'))],
        ),
      ),
    );
    if (confirmed == true && selected != null) {
      await AccountingService.createPaymentAccount(name: name.text, type: type, accountId: selected!.id, isDefault: isDefault);
      if (mounted) _refresh();
    }
  }

  Future<void> _createChequeDialog() async {
    final chequeNo = TextEditingController();
    final partyName = TextEditingController();
    final bankName = TextEditingController();
    final amount = TextEditingController(text: '0');
    var direction = 'received';
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Cheque'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: chequeNo, decoration: const InputDecoration(labelText: 'Cheque no')),
              DropdownButtonFormField<String>(
                initialValue: direction,
                decoration: const InputDecoration(labelText: 'Direction'),
                items: const [DropdownMenuItem(value: 'received', child: Text('Received')), DropdownMenuItem(value: 'issued', child: Text('Issued'))],
                onChanged: (v) => setDialogState(() => direction = v ?? direction),
              ),
              TextField(controller: partyName, decoration: const InputDecoration(labelText: 'Party name')),
              TextField(controller: bankName, decoration: const InputDecoration(labelText: 'Bank')),
              TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount')),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create'))],
        ),
      ),
    );
    if (confirmed == true) {
      await AccountingService.createCheque(
        chequeNo: chequeNo.text,
        direction: direction,
        partyType: '',
        partyId: '',
        partyName: partyName.text,
        bankName: bankName.text,
        dueDate: DateTime.now(),
        amount: double.tryParse(amount.text) ?? 0,
      );
      if (mounted) _refresh();
    }
  }

  Future<void> _createMasterDataDialog(String table, String title) async {
    final code = TextEditingController();
    final name = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: code, decoration: const InputDecoration(labelText: 'Code')),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create'))],
      ),
    );
    if (confirmed == true) {
      await AccountingService.createSimpleMasterData(table: table, code: code.text, name: name.text);
      if (mounted) _refresh();
    }
  }


  Future<void> _closeDrawerDialog(AdvancedAccountingItem item) async {
    final counted = TextEditingController(text: item.credit.toStringAsFixed(2));
    final notes = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Close ${item.name}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Expected cash: ${formatCurrency(item.credit)}'),
            const SizedBox(height: 8),
            TextField(controller: counted, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Counted cash')),
            TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Close'))],
      ),
    );
    if (confirmed == true) {
      await AccountingService.closeCashDrawer(sessionId: item.id, countedCash: double.tryParse(counted.text) ?? 0, notes: notes.text);
      if (mounted) _refresh();
    }
  }

  Future<void> _settleCheque(AdvancedAccountingItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear cheque ${item.name}'),
        content: Text('Mark this ${formatCurrency(item.balance)} cheque as cleared?'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear'))],
      ),
    );
    if (confirmed == true) {
      await AccountingService.settleCheque(chequeId: item.id);
      if (mounted) _refresh();
    }
  }

  Future<void> _bounceChequeDialog(AdvancedAccountingItem item) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bounce cheque ${item.name}'),
        content: TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason')),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Bounce'))],
      ),
    );
    if (confirmed == true) {
      await AccountingService.bounceCheque(chequeId: item.id, reason: reason.text);
      if (mounted) _refresh();
    }
  }

  Future<void> _closePeriod(AdvancedAccountingItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Close period ${item.name}'),
        content: const Text('Closing a period prevents posting new accounting entries inside its date range.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Close period'))],
      ),
    );
    if (confirmed == true) {
      await AccountingService.closeAccountingPeriod(periodId: item.id);
      if (mounted) _refresh();
    }
  }

  Future<void> _createPeriodDialog() async {
    final name = TextEditingController(text: 'Current Period');
    final now = DateTime.now();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Accounting Period'),
        content: TextField(controller: name, decoration: const InputDecoration(labelText: 'Period name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );
    if (confirmed == true) {
      await AccountingService.createAccountingPeriod(
        name: name.text,
        startDate: DateTime(now.year, now.month, 1),
        endDate: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
      );
      if (mounted) _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManageAccounting = widget.store.hasPermission(AppPermission.accountingManage);
    return FutureBuilder<_AdvancedAccountingData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _ReportError(message: snapshot.error.toString());
        final data = snapshot.data ?? const _AdvancedAccountingData();
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Advanced Accounting Controls', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('Phase 6 foundation: manual journals service, cash drawer sessions, cheques, payment accounts, periods, cost centers, and branches.', style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(onPressed: canManageAccounting ? _manualJournalDialog : null, icon: const Icon(Icons.edit_note_outlined), label: const Text('Manual journal')),
                        FilledButton.tonalIcon(onPressed: canManageAccounting ? _openDrawerDialog : null, icon: const Icon(Icons.point_of_sale_outlined), label: const Text('Open drawer')),
                        FilledButton.tonalIcon(onPressed: canManageAccounting ? _createPaymentAccountDialog : null, icon: const Icon(Icons.account_balance_wallet_outlined), label: const Text('Payment account')),
                        FilledButton.tonalIcon(onPressed: canManageAccounting ? _createChequeDialog : null, icon: const Icon(Icons.payments_outlined), label: const Text('Cheque')),
                        FilledButton.tonalIcon(onPressed: canManageAccounting ? _createPeriodDialog : null, icon: const Icon(Icons.event_available_outlined), label: const Text('Create period')),
                        FilledButton.tonalIcon(onPressed: canManageAccounting ? () => _createMasterDataDialog('cost_centers', 'Create Cost Center') : null, icon: const Icon(Icons.hub_outlined), label: const Text('Cost center')),
                        FilledButton.tonalIcon(onPressed: canManageAccounting ? () => _createMasterDataDialog('accounting_branches', 'Create Branch') : null, icon: const Icon(Icons.store_mall_directory_outlined), label: const Text('Branch')),
                      ],
                    ),
                    if (!canManageAccounting) ...[
                      const SizedBox(height: 8),
                      Text('Read-only: your role needs Manage accounting permission.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _AdvancedSection(title: 'Payment Accounts', icon: Icons.account_balance_wallet_outlined, items: data.paymentAccounts),
            _AdvancedSection(
              title: 'Cash Drawer Sessions',
              icon: Icons.point_of_sale_outlined,
              items: data.cashDrawers,
              actionBuilder: canManageAccounting
                  ? (item) => item.status == 'open'
                      ? [TextButton.icon(onPressed: () => _closeDrawerDialog(item), icon: const Icon(Icons.lock_outline), label: const Text('Close'))]
                      : const <Widget>[]
                  : null,
            ),
            _AdvancedSection(
              title: 'Cheques',
              icon: Icons.payments_outlined,
              items: data.cheques,
              actionBuilder: canManageAccounting
                  ? (item) => item.status == 'pending'
                      ? [
                          TextButton.icon(onPressed: () => _settleCheque(item), icon: const Icon(Icons.check_circle_outline), label: const Text('Clear')),
                          TextButton.icon(onPressed: () => _bounceChequeDialog(item), icon: const Icon(Icons.cancel_outlined), label: const Text('Bounce')),
                        ]
                      : const <Widget>[]
                  : null,
            ),
            _AdvancedSection(
              title: 'Accounting Periods',
              icon: Icons.date_range_outlined,
              items: data.periods,
              actionBuilder: canManageAccounting
                  ? (item) => item.type == 'open'
                      ? [TextButton.icon(onPressed: () => _closePeriod(item), icon: const Icon(Icons.event_busy_outlined), label: const Text('Close'))]
                      : const <Widget>[]
                  : null,
            ),
            _AdvancedSection(title: 'Cost Centers', icon: Icons.hub_outlined, items: data.costCenters),
            _AdvancedSection(title: 'Branches', icon: Icons.store_mall_directory_outlined, items: data.branches),
          ],
        );
      },
    );
  }
}

class _AdvancedAccountingData {
  const _AdvancedAccountingData({
    this.paymentAccounts = const <AdvancedAccountingItem>[],
    this.cashDrawers = const <AdvancedAccountingItem>[],
    this.cheques = const <AdvancedAccountingItem>[],
    this.periods = const <AdvancedAccountingItem>[],
    this.costCenters = const <AdvancedAccountingItem>[],
    this.branches = const <AdvancedAccountingItem>[],
  });

  final List<AdvancedAccountingItem> paymentAccounts;
  final List<AdvancedAccountingItem> cashDrawers;
  final List<AdvancedAccountingItem> cheques;
  final List<AdvancedAccountingItem> periods;
  final List<AdvancedAccountingItem> costCenters;
  final List<AdvancedAccountingItem> branches;
}

class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({required this.title, required this.icon, required this.items, this.actionBuilder});

  final String title;
  final IconData icon;
  final List<AdvancedAccountingItem> items;
  final List<Widget> Function(AdvancedAccountingItem item)? actionBuilder;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${items.length} records'),
        children: items.isEmpty
            ? const [ListTile(title: Text('No records yet.'))]
            : [
                for (final item in items)
                  ListTile(
                    title: Text(item.name.isEmpty ? item.id : item.name),
                    subtitle: Text([item.type, item.status, item.accountCode, item.accountName, item.notes].where((value) => value.trim().isNotEmpty).join(' • ')),
                    trailing: Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (item.balance != 0) Text(formatCurrency(item.balance)),
                        ...?actionBuilder?.call(item),
                      ],
                    ),
                  ),
              ],
      ),
    );
  }
}

class _AccountingSettingsTab extends StatefulWidget {
  const _AccountingSettingsTab({required this.store});

  final AppStore store;

  @override
  State<_AccountingSettingsTab> createState() => _AccountingSettingsTabState();
}

class _AccountingSettingsTabState extends State<_AccountingSettingsTab> {
  late Future<_AccountingSettingsData> _future;

  static const List<_AccountingSettingDefinition> _definitions = [
    _AccountingSettingDefinition(
      key: 'default_cash_account_id',
      title: 'Default Cash Account',
      subtitle: 'Used for cash sales, customer cash payments, supplier cash payments, and cash expenses.',
      icon: Icons.payments_outlined,
    ),
    _AccountingSettingDefinition(
      key: 'default_bank_account_id',
      title: 'Default Bank / Card Account',
      subtitle: 'Used for card, bank, Wish, check, and non-cash payment methods.',
      icon: Icons.account_balance_outlined,
    ),
    _AccountingSettingDefinition(
      key: 'default_customers_account_id',
      title: 'Customers Receivable Account',
      subtitle: 'Used when a sale leaves an amount due from the customer.',
      icon: Icons.people_outline,
    ),
    _AccountingSettingDefinition(
      key: 'default_suppliers_account_id',
      title: 'Suppliers Payable Account',
      subtitle: 'Used when a purchase leaves an amount due to the supplier.',
      icon: Icons.local_shipping_outlined,
    ),
    _AccountingSettingDefinition(
      key: 'default_inventory_account_id',
      title: 'Inventory Account',
      subtitle: 'Used for inventory received from purchases and inventory issued by sales.',
      icon: Icons.inventory_2_outlined,
    ),
    _AccountingSettingDefinition(
      key: 'default_sales_account_id',
      title: 'Sales Revenue Account',
      subtitle: 'Used as the credit side of posted sale invoices.',
      icon: Icons.point_of_sale_outlined,
    ),
    _AccountingSettingDefinition(
      key: 'default_cogs_account_id',
      title: 'Cost of Goods Sold Account',
      subtitle: 'Used when sales generate product cost from inventory.',
      icon: Icons.trending_down_outlined,
    ),
    _AccountingSettingDefinition(
      key: 'default_expense_account_id',
      title: 'Default Expense Account',
      subtitle: 'Used for posted expenses until detailed expense categories are mapped later.',
      icon: Icons.receipt_long_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_AccountingSettingsData> _load() async {
    final results = await Future.wait<Object>([
      AccountingService.listAccounts(activeOnly: true),
      AccountingService.readDefaultAccountMap(),
    ]);
    return _AccountingSettingsData(
      accounts: (results[0] as List<AccountingAccount>)
          .where((account) => account.subtype != 'group' && account.isActive)
          .toList(),
      settings: results[1] as Map<String, String>,
    );
  }

  Future<void> _updateSetting(String key, String accountId) async {
    await AccountingService.updateDefaultAccount(key: key, accountId: accountId);
    if (!mounted) return;
    setState(() => _future = _load());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Accounting setting updated.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AccountingSettingsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
        final data = snapshot.data ?? const _AccountingSettingsData(accounts: <AccountingAccount>[], settings: <String, String>{});
        final canManageAccounting = widget.store.hasPermission(AppPermission.accountingManage);
        if (data.accounts.isEmpty) {
          return const _EmptyAccountingState(message: 'No active posting accounts found.');
        }
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _definitions.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Accounting Account Mapping', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        'These settings control which chart-of-accounts account is used when Ventio automatically posts sales, purchases, expenses, and payments.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      if (!canManageAccounting) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Read-only: your role needs Manage accounting permission to change mappings.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                    ],
                  ),
                );
              }
              final definition = _definitions[index - 1];
              return _AccountingSettingRow(
                definition: definition,
                accounts: data.accounts,
                selectedAccountId: data.settings[definition.key] ?? '',
                onChanged: canManageAccounting ? (accountId) => _updateSetting(definition.key, accountId) : null,
              );
            },
          ),
        );
      },
    );
  }
}

class _AccountingSettingsData {
  const _AccountingSettingsData({required this.accounts, required this.settings});

  final List<AccountingAccount> accounts;
  final Map<String, String> settings;
}

class _AccountingSettingDefinition {
  const _AccountingSettingDefinition({required this.key, required this.title, required this.subtitle, required this.icon});

  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
}

class _AccountingSettingRow extends StatelessWidget {
  const _AccountingSettingRow({required this.definition, required this.accounts, required this.selectedAccountId, required this.onChanged});

  final _AccountingSettingDefinition definition;
  final List<AccountingAccount> accounts;
  final String selectedAccountId;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedExists = accounts.any((account) => account.id == selectedAccountId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final selector = _AccountSelector(
            accounts: accounts,
            value: selectedExists ? selectedAccountId : null,
            onChanged: onChanged,
          );
          final info = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 18, child: Icon(definition.icon, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(definition.title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(definition.subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [info, const SizedBox(height: 10), selector],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: info),
              const SizedBox(width: 20),
              SizedBox(width: 380, child: selector),
            ],
          );
        },
      ),
    );
  }
}

class _AccountSelector extends StatelessWidget {
  const _AccountSelector({required this.accounts, required this.value, required this.onChanged});

  final List<AccountingAccount> accounts;
  final String? value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        labelText: 'Mapped account',
      ),
      items: [
        for (final account in accounts)
          DropdownMenuItem<String>(
            value: account.id,
            child: Text('${account.code} • ${account.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged == null
          ? null
          : (accountId) {
              if (accountId == null || accountId.trim().isEmpty || accountId == value) return;
              onChanged!(accountId);
            },
    );
  }
}

class _StatementCard extends StatelessWidget {
  const _StatementCard({required this.store, required this.title, required this.rows});

  final AppStore store;
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
              child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            );
          }
          final row = rows[index - 1];
          final style = row.highlight ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800) : Theme.of(context).textTheme.bodyLarge;
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
          child: Text(message, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      );
}

String _money(AppStore store, double amount) => formatUsdReferenceAmount(amount, store.storeProfile);

String _dateText(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

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
              Icon(Icons.account_balance_wallet_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
  });

  final double customerReceivables;
  final double customerCredits;
  final double supplierPayables;
  final double supplierAdvances;
  final double todayCashIn;
  final double todayCashOut;

  factory _AccountingMetrics.fromStore(AppStore store) {
    final customers = store.customers;
    final suppliers = store.suppliers;
    final accountTransactions = store.accountTransactions;
    final customerReceivables = customers.fold<double>(0, (sum, customer) {
      final balance = store.accountBalance('customer', customer.id);
      return balance > 0 ? sum + balance : sum;
    });
    final customerCredits = customers.fold<double>(0, (sum, customer) {
      final balance = store.accountBalance('customer', customer.id);
      return balance < 0 ? sum + balance.abs() : sum;
    });
    final supplierPayables = suppliers.fold<double>(0, (sum, supplier) {
      final balance = store.accountBalance('supplier', supplier.id);
      return balance < 0 ? sum + balance.abs() : sum;
    });
    final supplierAdvances = suppliers.fold<double>(0, (sum, supplier) {
      final balance = store.accountBalance('supplier', supplier.id);
      return balance > 0 ? sum + balance : sum;
    });
    final today = DateTime.now();
    final todayCashIn = accountTransactions.where((txn) => _sameDay(txn.date, today) && _isCashIn(txn)).fold<double>(0, (sum, txn) => sum + _cashAmount(txn));
    final todayCashOut = accountTransactions.where((txn) => _sameDay(txn.date, today) && _isCashOut(txn)).fold<double>(0, (sum, txn) => sum + _cashAmount(txn));
    return _AccountingMetrics(
      customerReceivables: customerReceivables,
      customerCredits: customerCredits,
      supplierPayables: supplierPayables,
      supplierAdvances: supplierAdvances,
      todayCashIn: todayCashIn,
      todayCashOut: todayCashOut,
    );
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  static bool _isCashIn(AccountTransaction txn) => txn.type == 'paymentReceived' || (txn.type == 'paymentReversal' && txn.accountType == 'supplier');
  static bool _isCashOut(AccountTransaction txn) => txn.type == 'paymentPaid' || (txn.type == 'paymentReversal' && txn.accountType == 'customer');
  static double _cashAmount(AccountTransaction txn) => txn.debit > 0 ? txn.debit : txn.credit;
}

bool _matches(String query, List<String?> values) {
  if (query.trim().isEmpty) return true;
  return values.whereType<String>().any((value) => value.toLowerCase().contains(query));
}
