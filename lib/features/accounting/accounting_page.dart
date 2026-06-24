import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/responsive.dart';
import '../../core/services/accounting_service.dart';
import '../../core/services/accounting_aging_service.dart';
import '../../data/app_store.dart';
import '../../models/account_transaction.dart';
import '../../models/app_user.dart';
import '../../models/accounting_account.dart';
import '../../models/journal_entry.dart';
import '../../models/aging_report.dart';
import '../../models/user_role.dart';
import '../accounts/account_ledger_widgets.dart';

class AccountingPage extends StatefulWidget {
  const AccountingPage({super.key, required this.store});

  final AppStore store;

  @override
  State<AccountingPage> createState() => _AccountingPageState();
}

class _AccountingPageState extends State<AccountingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _searchController.addListener(() =>
        setState(() => _query = _searchController.text.trim().toLowerCase()));
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
                _AccountsAccountingGroup(store: widget.store, query: _query),
                _CashAccountingGroup(store: widget.store, query: _query),
                _ReportsAccountingGroup(store: widget.store, query: _query),
                _SettingsAccountingGroup(store: widget.store),
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
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                AppLocalizations.of(context).text('recent_transactions'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
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

class _CachedFuturePanel<T> extends StatefulWidget {
  const _CachedFuturePanel({
    required this.store,
    required this.cacheKey,
    required this.loadFuture,
    required this.builder,
  });

  final AppStore store;
  final Object cacheKey;
  final Future<T> Function() loadFuture;
  final Widget Function(BuildContext context, AsyncSnapshot<T> snapshot)
      builder;

  @override
  State<_CachedFuturePanel<T>> createState() => _CachedFuturePanelState<T>();
}

class _CachedFuturePanelState<T> extends State<_CachedFuturePanel<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loadFuture();
    widget.store.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _CachedFuturePanel<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_refresh);
      widget.store.addListener(_refresh);
    }
    if (oldWidget.cacheKey != widget.cacheKey) {
      _refresh();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _future = widget.loadFuture());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: widget.builder,
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
      _SummaryMetric(
          icon: Icons.people_outline,
          title: tr.text('customer_receivables'),
          amount: metrics.customerReceivables),
      _SummaryMetric(
          icon: Icons.local_shipping_outlined,
          title: tr.text('supplier_payables'),
          amount: metrics.supplierPayables),
      _SummaryMetric(
          icon: Icons.south_west,
          title: tr.text('today_cash_in'),
          amount: metrics.todayCashIn),
      _SummaryMetric(
          icon: Icons.north_east,
          title: tr.text('today_cash_out'),
          amount: metrics.todayCashOut),
      _SummaryMetric(
          icon: Icons.assignment_return_outlined,
          title: tr.text('customer_credits'),
          amount: metrics.customerCredits,
          subtle: true),
      _SummaryMetric(
          icon: Icons.inventory_outlined,
          title: tr.text('supplier_advances'),
          amount: metrics.supplierAdvances,
          subtle: true),
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
              itemBuilder: (context, index) => SizedBox(
                  width: 220,
                  child: _SummaryTile(store: store, metric: cards[index])),
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
            for (final metric in cards)
              SizedBox(
                  width: itemWidth,
                  height: 82,
                  child: _SummaryTile(store: store, metric: metric)),
          ],
        );
      },
    );
  }
}

class _SummaryMetric {
  const _SummaryMetric(
      {required this.icon,
      required this.title,
      required this.amount,
      this.subtle = false});

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
      color: metric.subtle
          ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.55)
          : colorScheme.surfaceContainerHighest,
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
                  Text(metric.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 3),
                  Text(
                    formatUsdReferenceAmount(metric.amount, store.storeProfile),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
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
            Tab(
                icon: const Icon(Icons.people_alt_outlined),
                text: tr.text('accounts')),
            Tab(
                icon: const Icon(Icons.point_of_sale_outlined),
                text: tr.text('cash_management')),
            Tab(
                icon: const Icon(Icons.assessment_outlined),
                text: tr.text('reports')),
            Tab(
                icon: const Icon(Icons.settings_outlined),
                text: tr.text('settings')),
          ],
        ),
      ),
    );
  }
}

class _AccountsAccountingGroup extends StatelessWidget {
  const _AccountsAccountingGroup({required this.store, required this.query});

  final AppStore store;
  final String query;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return DefaultTabController(
      length: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AccountingGroupTabs(
            tabs: [
              Tab(
                  icon: const Icon(Icons.person_outline),
                  text: tr.text('customers')),
              Tab(
                  icon: const Icon(Icons.local_shipping_outlined),
                  text: tr.text('suppliers')),
              Tab(
                  icon: const Icon(Icons.schedule_outlined),
                  text: tr.text('aging_reports')),
              Tab(
                  icon: const Icon(Icons.history_outlined),
                  text: tr.text('recent_transactions')),
              Tab(
                  icon: const Icon(Icons.menu_book_outlined),
                  text: tr.text('general_ledger')),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              children: [
                _AccountsTab(
                    store: store, query: query, accountType: 'customer'),
                _AccountsTab(
                    store: store, query: query, accountType: 'supplier'),
                _AgingReportsTab(store: store, query: query),
                _TransactionsTab(store: store, query: query, cashOnly: false),
                _GeneralLedgerTab(store: store, query: query),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CashAccountingGroup extends StatelessWidget {
  const _CashAccountingGroup({required this.store, required this.query});

  final AppStore store;
  final String query;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AccountingGroupTabs(
            tabs: [
              Tab(
                  icon: const Icon(Icons.payments_outlined),
                  text: tr.text('cash_movement')),
              Tab(
                  icon: const Icon(Icons.point_of_sale_outlined),
                  text: tr.text('cash_management')),
              Tab(
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  text: tr.text('cash_bank')),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              children: [
                _TransactionsTab(store: store, query: query, cashOnly: true),
                _AdvancedAccountingTab(store: store, cashOnly: true),
                _CashBankReportTab(store: store),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportsAccountingGroup extends StatelessWidget {
  const _ReportsAccountingGroup({required this.store, required this.query});

  final AppStore store;
  final String query;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return DefaultTabController(
      length: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AccountingGroupTabs(
            tabs: [
              Tab(
                  icon: const Icon(Icons.balance_outlined),
                  text: tr.text('trial_balance')),
              Tab(
                  icon: const Icon(Icons.trending_up_outlined),
                  text: tr.text('income_statement')),
              Tab(
                  icon: const Icon(Icons.account_balance_outlined),
                  text: tr.text('balance_sheet')),
              Tab(
                  icon: const Icon(Icons.waterfall_chart_outlined),
                  text: tr.text('cash_flow_statement')),
              Tab(
                  icon: const Icon(Icons.receipt_long_outlined),
                  text: tr.text('tax_report')),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              children: [
                _TrialBalanceTab(store: store, query: query),
                _IncomeStatementTab(store: store),
                _BalanceSheetTab(store: store),
                _CashFlowStatementTab(store: store),
                _TaxReportTab(store: store),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsAccountingGroup extends StatelessWidget {
  const _SettingsAccountingGroup({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AccountingGroupTabs(
            tabs: [
              Tab(
                  icon: const Icon(Icons.auto_awesome_motion_outlined),
                  text: tr.text('advanced')),
              Tab(
                  icon: const Icon(Icons.settings_outlined),
                  text: tr.text('settings')),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              children: [
                _AdvancedAccountingTab(store: store),
                _AccountingSettingsTab(store: store),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountingGroupTabs extends StatelessWidget {
  const _AccountingGroupTabs({required this.tabs});

  final List<Widget> tabs;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: TabBar(
          isScrollable: true,
          tabs: tabs,
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
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close), onPressed: controller.clear),
      ),
    );
  }
}

class _AccountsTab extends StatelessWidget {
  const _AccountsTab(
      {required this.store, required this.query, required this.accountType});

  final AppStore store;
  final String query;
  final String accountType;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final normalizedQuery = _normalizedSearchQuery(query);
    final rows = accountType == 'customer'
        ? store.customers
            .where((customer) => _matchesNormalized(normalizedQuery,
                [customer.name, customer.phone, customer.address]))
            .map((customer) => _AccountRowData(
                  id: customer.id,
                  name: customer.name,
                  subtitle: [customer.phone, customer.address]
                      .where((part) => part.trim().isNotEmpty)
                      .join(' • '),
                  balance: store.accountBalance('customer', customer.id),
                ))
            .toList()
        : store.suppliers
            .where((supplier) => _matchesNormalized(normalizedQuery, [
                  supplier.name,
                  supplier.nameEn,
                  supplier.nameAr,
                  supplier.phone,
                  supplier.address
                ]))
            .map((supplier) => _AccountRowData(
                  id: supplier.id,
                  name: supplier.name,
                  subtitle: [supplier.phone, supplier.address]
                      .where((part) => part.trim().isNotEmpty)
                      .join(' • '),
                  balance: store.accountBalance('supplier', supplier.id),
                ))
            .toList();
    rows.sort((a, b) => b.balance.abs().compareTo(a.balance.abs()));

    if (rows.isEmpty) {
      return _EmptyAccountingState(
          message: tr.text(accountType == 'customer'
              ? 'no_customers_found'
              : 'no_suppliers_found'));
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
              if (isWide && index == 0)
                return _AccountTableHeader(accountType: accountType);
              final row = rows[isWide ? index - 1 : index];
              return _AccountListRow(
                  store: store,
                  accountType: accountType,
                  row: row,
                  isWide: isWide);
            },
          ),
        );
      },
    );
  }
}

class _AccountRowData {
  const _AccountRowData(
      {required this.id,
      required this.name,
      required this.subtitle,
      required this.balance});

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
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.55),
      child: Row(
        children: [
          Expanded(
              flex: 4,
              child: Text(
                  tr.text(accountType == 'customer' ? 'customer' : 'supplier'),
                  style: TextStyle(color: color, fontWeight: FontWeight.w700))),
          Expanded(
              flex: 2,
              child: Text(tr.text('balance'),
                  style: TextStyle(color: color, fontWeight: FontWeight.w700))),
          const SizedBox(width: 260),
        ],
      ),
    );
  }
}

class _AccountListRow extends StatelessWidget {
  const _AccountListRow(
      {required this.store,
      required this.accountType,
      required this.row,
      required this.isWide});

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
        onPressed: () => showAccountLedgerSheet(
            context: context,
            store: store,
            accountType: accountType,
            accountId: row.id,
            accountName: row.name),
        icon: const Icon(Icons.list_alt_outlined, size: 18),
        label: Text(tr.text('account_ledger')),
      ),
      FilledButton.icon(
        onPressed: () => showAccountPaymentDialog(
            context: context,
            store: store,
            accountType: accountType,
            accountId: row.id,
            accountName: row.name),
        icon: Icon(
            accountType == 'customer' ? Icons.call_received : Icons.call_made,
            size: 18),
        label: Text(accountType == 'customer'
            ? tr.text('receive_payment')
            : tr.text('pay_supplier')),
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
                CircleAvatar(
                    radius: 18,
                    child: Icon(
                        accountType == 'customer'
                            ? Icons.person_outline
                            : Icons.local_shipping_outlined,
                        size: 20)),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700))),
                Text(
                    formatUsdReferenceAmount(
                        row.balance.abs(), store.storeProfile),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.w800)),
              ],
            ),
            if (row.subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(row.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                CircleAvatar(
                    radius: 17,
                    child: Icon(
                        accountType == 'customer'
                            ? Icons.person_outline
                            : Icons.local_shipping_outlined,
                        size: 19)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      if (row.subtitle.isNotEmpty)
                        Text(row.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
                formatUsdReferenceAmount(row.balance.abs(), store.storeProfile),
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w800)),
          ),
          SizedBox(
            width: 260,
            child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: actions),
          ),
        ],
      ),
    );
  }
}

class _AgingReportsTab extends StatelessWidget {
  const _AgingReportsTab({required this.store, required this.query});

  final AppStore store;
  final String query;

  @override
  Widget build(BuildContext context) {
    final customerReport = AccountingAgingService.customerAgingFromStore(
      sales: store.sales,
      accountTransactions: store.accountTransactions,
    );
    final supplierReport = AccountingAgingService.supplierAgingFromStore(
      purchases: store.purchases,
      accountTransactions: store.accountTransactions,
    );

    return ListView(
      children: [
        _AgingReportSection(
          store: store,
          title: AppLocalizations.of(context).text('customer_aging'),
          subtitle:
              AppLocalizations.of(context).text('customer_aging_subtitle'),
          icon: Icons.people_outline,
          report: customerReport,
          query: query,
        ),
        const SizedBox(height: 12),
        _AgingReportSection(
          store: store,
          title: AppLocalizations.of(context).text('supplier_aging'),
          subtitle:
              AppLocalizations.of(context).text('supplier_aging_subtitle'),
          icon: Icons.local_shipping_outlined,
          report: supplierReport,
          query: query,
        ),
      ],
    );
  }
}

class _AgingReportSection extends StatelessWidget {
  const _AgingReportSection({
    required this.store,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.report,
    required this.query,
  });

  final AppStore store;
  final String title;
  final String subtitle;
  final IconData icon;
  final AgingReportResult report;
  final String query;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final normalizedQuery = _normalizedSearchQuery(query);
    final rows = report.rows
        .where((row) => _matchesNormalized(normalizedQuery, [row.partyName]))
        .toList();
    final documents = report.openDocuments
        .where((doc) =>
            _matchesNormalized(normalizedQuery, [doc.partyName, doc.number]))
        .take(80)
        .toList();

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      Text(subtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                    ],
                  ),
                ),
                Text(_money(store, report.total),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _AgingBucketChip(
                    store: store,
                    label: tr.text('current'),
                    amount: report.current),
                _AgingBucketChip(
                    store: store, label: '0-30', amount: report.days1To30),
                _AgingBucketChip(
                    store: store, label: '31-60', amount: report.days31To60),
                _AgingBucketChip(
                    store: store, label: '61-90', amount: report.days61To90),
                _AgingBucketChip(
                    store: store, label: '90+', amount: report.over90),
              ],
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              _EmptyAccountingState(message: tr.text('no_aging_balances'))
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(label: Text(tr.text('account'))),
                    DataColumn(label: Text(tr.text('current')), numeric: true),
                    const DataColumn(label: Text('0-30'), numeric: true),
                    const DataColumn(label: Text('31-60'), numeric: true),
                    const DataColumn(label: Text('61-90'), numeric: true),
                    const DataColumn(label: Text('90+'), numeric: true),
                    DataColumn(label: Text(tr.text('total')), numeric: true),
                  ],
                  rows: [
                    for (final row in rows)
                      DataRow(cells: [
                        DataCell(Text(row.partyName,
                            overflow: TextOverflow.ellipsis)),
                        DataCell(Text(_money(store, row.current))),
                        DataCell(Text(_money(store, row.days1To30))),
                        DataCell(Text(_money(store, row.days31To60))),
                        DataCell(Text(_money(store, row.days61To90))),
                        DataCell(Text(_money(store, row.over90))),
                        DataCell(Text(_money(store, row.total))),
                      ]),
                  ],
                ),
              ),
            if (documents.isNotEmpty) ...[
              const Divider(height: 24),
              Text(tr.text('open_documents'),
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(label: Text(tr.text('date'))),
                    DataColumn(label: Text(tr.text('reference'))),
                    DataColumn(label: Text(tr.text('account'))),
                    DataColumn(label: Text(tr.text('age_days')), numeric: true),
                    DataColumn(label: Text(tr.text('bucket'))),
                    DataColumn(label: Text(tr.text('balance')), numeric: true),
                  ],
                  rows: [
                    for (final doc in documents)
                      DataRow(cells: [
                        DataCell(Text(_dateText(doc.date))),
                        DataCell(
                            Text(doc.number.isEmpty ? doc.id : doc.number)),
                        DataCell(Text(doc.partyName)),
                        DataCell(Text(doc.ageDays.toString())),
                        DataCell(
                            Text(_agingBucketText(context, doc.bucketLabel))),
                        DataCell(Text(_money(store, doc.openAmount))),
                      ]),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AgingBucketChip extends StatelessWidget {
  const _AgingBucketChip(
      {required this.store, required this.label, required this.amount});

  final AppStore store;
  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: ${_money(store, amount)}'),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    );
  }
}

String _agingBucketText(BuildContext context, String bucket) {
  switch (bucket) {
    case 'current':
      return AppLocalizations.of(context).text('current');
    case '0_30':
      return '0-30';
    case '31_60':
      return '31-60';
    case '61_90':
      return '61-90';
    default:
      return '90+';
  }
}

class _TransactionsTab extends StatelessWidget {
  const _TransactionsTab(
      {required this.store, required this.query, required this.cashOnly});

  final AppStore store;
  final String query;
  final bool cashOnly;

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _normalizedSearchQuery(query);
    final rows = store.accountTransactions
        .where((txn) =>
            (!cashOnly || _isCashTxn(txn)) &&
            _matchesNormalized(normalizedQuery, [
              txn.accountName,
              txn.referenceNo,
              txn.paymentMethod,
              txn.note,
              txn.type
            ]))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    if (rows.isEmpty) {
      return _EmptyAccountingState(
          message: AppLocalizations.of(context).text(
              cashOnly ? 'no_cash_movements' : 'no_account_transactions'));
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
              return _TransactionRow(
                  store: store, transaction: transaction, isWide: isWide);
            },
          ),
        );
      },
    );
  }

  bool _isCashTxn(AccountTransaction txn) =>
      txn.type == 'paymentReceived' ||
      txn.type == 'paymentPaid' ||
      txn.type == 'paymentReversal';
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
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.55),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(tr.text('date'), style: style)),
          Expanded(flex: 2, child: Text(tr.text('type'), style: style)),
          Expanded(flex: 3, child: Text(tr.text('account'), style: style)),
          Expanded(flex: 2, child: Text(tr.text('reference'), style: style)),
          SizedBox(
              width: 130,
              child: Text(tr.text('amount'),
                  style: style, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow(
      {required this.store, required this.transaction, required this.isWide});

  final AppStore store;
  final AccountTransaction transaction;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final amount =
        transaction.debit > 0 ? transaction.debit : transaction.credit;
    final sign = _displaySign(transaction);
    final amountText =
        '$sign ${formatUsdReferenceAmount(amount, store.storeProfile)}';
    final accountName = transaction.accountName.trim().isEmpty
        ? tr.text(
            transaction.accountType == 'supplier' ? 'supplier' : 'customer')
        : transaction.accountName;
    final typeText = _typeTitle(context, transaction.type);
    final methodText = transaction.paymentMethod.isEmpty
        ? ''
        : _paymentMethodLabel(context, transaction.paymentMethod);
    final note = transaction.note.trim();
    final color = sign == '+'
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;

    if (!isWide) {
      return ListTile(
        leading:
            CircleAvatar(child: Icon(_iconForType(transaction.type), size: 20)),
        title: Text(accountName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
            [
              _dateText(transaction.date),
              typeText,
              transaction.referenceNo,
              methodText,
              note,
            ].where((part) => part.trim().isNotEmpty).join(' • '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        trailing: Text(amountText,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w800)),
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
                Icon(_iconForType(transaction.type),
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(typeText,
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          Expanded(
              flex: 3,
              child: Text(accountName,
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(
              flex: 2,
              child: Text(
                  [transaction.referenceNo, methodText]
                      .where((part) => part.trim().isNotEmpty)
                      .join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
          SizedBox(
              width: 130,
              child: Text(amountText,
                  textAlign: TextAlign.end,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: color, fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }

  String _displaySign(AccountTransaction transaction) {
    if (transaction.type == 'paymentReceived') return '+';
    if (transaction.type == 'paymentPaid') return '-';
    if (transaction.type == 'paymentReversal' &&
        transaction.accountType == 'supplier') return '+';
    if (transaction.type == 'paymentReversal' &&
        transaction.accountType == 'customer') return '-';
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

  String _dateText(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _GeneralLedgerTab extends StatelessWidget {
  const _GeneralLedgerTab({required this.store, required this.query});

  final AppStore store;
  final String query;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final normalizedQuery = _normalizedSearchQuery(query);
    return _CachedFuturePanel<List<GeneralLedgerAccountReport>>(
      store: store,
      cacheKey: 'general_ledger_report',
      loadFuture: AccountingService.generalLedgerReport,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
        final rows = (snapshot.data ?? <GeneralLedgerAccountReport>[])
            .where((account) =>
                account.lines.isNotEmpty &&
                _matchesNormalized(normalizedQuery, [
                  account.accountCode,
                  account.accountName,
                  account.accountType
                ]))
            .toList();
        if (rows.isEmpty) {
          return _EmptyAccountingState(
              message: tr.text('no_journal_entries_found'));
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
                title: Text(
                    '${account.accountCode} • ${_localizedAccountingName(account.accountName, tr)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${tr.text('debit')} ${_money(store, account.totalDebit)} • ${tr.text('credit')} ${_money(store, account.totalCredit)}'),
                trailing: Text(_money(store, account.closingBalance),
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
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
    final tr = AppLocalizations.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          DataColumn(label: Text(tr.text('date'))),
          DataColumn(label: Text(tr.text('entry'))),
          DataColumn(label: Text(tr.text('reference'))),
          DataColumn(label: Text(tr.text('description'))),
          DataColumn(label: Text(tr.text('debit')), numeric: true),
          DataColumn(label: Text(tr.text('credit')), numeric: true),
          DataColumn(label: Text(tr.text('balance')), numeric: true),
        ],
        rows: [
          for (final line in lines.take(200))
            DataRow(cells: [
              DataCell(Text(_dateText(line.entryDate))),
              DataCell(Text(line.entryNo)),
              DataCell(
                  Text(_joinParts([line.referenceType, line.referenceNo]))),
              DataCell(SizedBox(
                  width: 260,
                  child: Text(line.memo.isEmpty ? line.description : line.memo,
                      overflow: TextOverflow.ellipsis))),
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
    final tr = AppLocalizations.of(context);
    final normalizedQuery = _normalizedSearchQuery(query);
    return _CachedFuturePanel<List<TrialBalanceRowReport>>(
      store: store,
      cacheKey: 'trial_balance_report',
      loadFuture: AccountingService.trialBalanceReport,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
        final rows = (snapshot.data ?? <TrialBalanceRowReport>[])
            .where((row) =>
                (row.debit != 0 || row.credit != 0) &&
                _matchesNormalized(normalizedQuery,
                    [row.accountCode, row.accountName, row.accountType]))
            .toList();
        final totalDebit = rows.fold<double>(0, (sum, row) => sum + row.debit);
        final totalCredit =
            rows.fold<double>(0, (sum, row) => sum + row.credit);
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text(tr.text('code'))),
                  DataColumn(label: Text(tr.text('account'))),
                  DataColumn(label: Text(tr.text('type'))),
                  DataColumn(label: Text(tr.text('debit')), numeric: true),
                  DataColumn(label: Text(tr.text('credit')), numeric: true),
                  DataColumn(label: Text(tr.text('balance')), numeric: true),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(cells: [
                      DataCell(Text(row.accountCode)),
                      DataCell(
                          Text(_localizedAccountingName(row.accountName, tr))),
                      DataCell(
                          Text(_localizedAccountingType(row.accountType, tr))),
                      DataCell(Text(_money(store, row.debit))),
                      DataCell(Text(_money(store, row.credit))),
                      DataCell(Text(_money(store, row.balance))),
                    ]),
                  DataRow(cells: [
                    const DataCell(Text('')),
                    DataCell(Text(tr.text('totals'))),
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
    final tr = AppLocalizations.of(context);
    return _CachedFuturePanel<IncomeStatementReport>(
      store: store,
      cacheKey: 'income_statement_report',
      loadFuture: AccountingService.incomeStatementReport,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
        final report = snapshot.data ??
            const IncomeStatementReport(
                revenue: 0,
                costOfGoodsSold: 0,
                grossProfit: 0,
                expenses: 0,
                netProfit: 0);
        return _StatementCard(
          store: store,
          title: tr.text('income_statement'),
          rows: [
            _StatementRow(tr.text('sales_revenue'), report.revenue),
            _StatementRow(
                tr.text('cost_of_goods_sold'), -report.costOfGoodsSold),
            _StatementRow(tr.text('gross_profit'), report.grossProfit,
                highlight: true),
            _StatementRow(tr.text('expenses'), -report.expenses),
            _StatementRow(tr.text('net_profit'), report.netProfit,
                highlight: true),
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
    final tr = AppLocalizations.of(context);
    return _CachedFuturePanel<BalanceSheetReport>(
      store: store,
      cacheKey: 'balance_sheet_report',
      loadFuture: AccountingService.balanceSheetReport,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
        final report = snapshot.data ??
            const BalanceSheetReport(
                assets: 0,
                liabilities: 0,
                equity: 0,
                retainedEarnings: 0,
                liabilitiesAndEquity: 0,
                difference: 0);
        return _StatementCard(
          store: store,
          title: tr.text('balance_sheet'),
          rows: [
            _StatementRow(tr.text('assets'), report.assets, highlight: true),
            _StatementRow(tr.text('liabilities'), report.liabilities),
            _StatementRow(tr.text('equity'), report.equity),
            _StatementRow(
                tr.text('current_profit_loss'), report.retainedEarnings),
            _StatementRow(
                tr.text('liabilities_equity'), report.liabilitiesAndEquity,
                highlight: true),
            _StatementRow(tr.text('difference'), report.difference,
                highlight: report.difference.abs() > 0.009),
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
    final tr = AppLocalizations.of(context);
    return _CachedFuturePanel<List<CashBankMovementReport>>(
      store: store,
      cacheKey: 'cash_bank_report',
      loadFuture: AccountingService.cashBankMovementReport,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
        final rows = snapshot.data ?? <CashBankMovementReport>[];
        if (rows.isEmpty) {
          return _EmptyAccountingState(
              message: tr.text('no_cash_or_bank_movements_found'));
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
                title: Text(
                    '${row.accountCode} • ${_localizedAccountingName(row.accountName, tr)}'),
                subtitle: Text(
                    '${tr.text('in')} ${_money(store, row.moneyIn)} • ${tr.text('out')} ${_money(store, row.moneyOut)}'),
                trailing: Text(_money(store, row.closingBalance),
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              );
            },
          ),
        );
      },
    );
  }
}

class _CashFlowStatementTab extends StatelessWidget {
  const _CashFlowStatementTab({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return _CachedFuturePanel<CashFlowStatementReport>(
      store: store,
      cacheKey: 'cash_flow_report',
      loadFuture: AccountingService.cashFlowStatementReport,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
        final report = snapshot.data ??
            const CashFlowStatementReport(
              operatingInflows: 0,
              operatingOutflows: 0,
              investingInflows: 0,
              investingOutflows: 0,
              financingInflows: 0,
              financingOutflows: 0,
              openingCash: 0,
              closingCash: 0,
            );
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(tr.text('cash_flow_statement'),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _CashFlowSection(
                store: store,
                title: tr.text('operating_activities'),
                inflows: report.operatingInflows,
                outflows: report.operatingOutflows,
                net: report.operatingNet,
              ),
              _CashFlowSection(
                store: store,
                title: tr.text('investing_activities'),
                inflows: report.investingInflows,
                outflows: report.investingOutflows,
                net: report.investingNet,
              ),
              _CashFlowSection(
                store: store,
                title: tr.text('financing_activities'),
                inflows: report.financingInflows,
                outflows: report.financingOutflows,
                net: report.financingNet,
              ),
              const Divider(height: 28),
              _StatementLine(
                  label: tr.text('opening_cash_balance'),
                  value: _money(store, report.openingCash),
                  highlight: true),
              _StatementLine(
                  label: tr.text('net_change_in_cash'),
                  value: _money(store, report.netChangeInCash),
                  highlight: true),
              _StatementLine(
                  label: tr.text('closing_cash_balance'),
                  value: _money(store, report.closingCash),
                  highlight: true),
              const SizedBox(height: 20),
              Text(tr.text('cash_flow_details'),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (report.lines.isEmpty)
                _EmptyAccountingState(
                    message: tr.text('no_cash_flow_movements_found'))
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      DataColumn(label: Text(tr.text('date'))),
                      DataColumn(label: Text(tr.text('reference'))),
                      DataColumn(label: Text(tr.text('category'))),
                      DataColumn(label: Text(tr.text('description'))),
                      DataColumn(label: Text(tr.text('in')), numeric: true),
                      DataColumn(label: Text(tr.text('out')), numeric: true),
                      DataColumn(label: Text(tr.text('net')), numeric: true),
                    ],
                    rows: [
                      for (final line in report.lines)
                        DataRow(cells: [
                          DataCell(Text(_dateText(line.entryDate))),
                          DataCell(Text(_joinParts(
                              [line.referenceType, line.referenceNo]))),
                          DataCell(
                              Text(_cashFlowCategoryLabel(tr, line.category))),
                          DataCell(SizedBox(
                              width: 280,
                              child: Text(line.description,
                                  overflow: TextOverflow.ellipsis))),
                          DataCell(Text(_money(store, line.inflow))),
                          DataCell(Text(_money(store, line.outflow))),
                          DataCell(Text(_money(store, line.netCashFlow))),
                        ]),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CashFlowSection extends StatelessWidget {
  const _CashFlowSection(
      {required this.store,
      required this.title,
      required this.inflows,
      required this.outflows,
      required this.net});

  final AppStore store;
  final String title;
  final double inflows;
  final double outflows;
  final double net;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          _StatementLine(
              label: tr.text('cash_inflows'), value: _money(store, inflows)),
          _StatementLine(
              label: tr.text('cash_outflows'), value: _money(store, outflows)),
          _StatementLine(
              label: tr.text('net_cash_flow'),
              value: _money(store, net),
              highlight: true),
        ],
      ),
    );
  }
}

class _StatementLine extends StatelessWidget {
  const _StatementLine(
      {required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final style = highlight
        ? Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w800)
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

String _cashFlowCategoryLabel(AppLocalizations tr, CashFlowCategory category) {
  switch (category) {
    case CashFlowCategory.investing:
      return tr.text('investing_activities');
    case CashFlowCategory.financing:
      return tr.text('financing_activities');
    case CashFlowCategory.operating:
      return tr.text('operating_activities');
  }
}

class _TaxReportTab extends StatelessWidget {
  const _TaxReportTab({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return _CachedFuturePanel<TaxReport>(
      store: store,
      cacheKey: 'tax_report',
      loadFuture: AccountingService.taxReport,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
        final report = snapshot.data ??
            const TaxReport(
                outputTax: 0,
                inputTax: 0,
                netTaxPayable: 0,
                payableAccountMovement: 0);
        return _StatementCard(
          store: store,
          title: tr.text('tax_report'),
          rows: [
            _StatementRow(tr.text('output_sales_tax'), report.outputTax),
            _StatementRow(tr.text('input_purchase_tax'), -report.inputTax),
            _StatementRow(tr.text('net_tax_payable'), report.netTaxPayable,
                highlight: true),
            _StatementRow(tr.text('tax_payable_account_movement'),
                report.payableAccountMovement),
          ],
        );
      },
    );
  }
}

class _AdvancedAccountingTab extends StatefulWidget {
  const _AdvancedAccountingTab({required this.store, this.cashOnly = false});

  final AppStore store;
  final bool cashOnly;

  @override
  State<_AdvancedAccountingTab> createState() => _AdvancedAccountingTabState();
}

class _AdvancedAccountingTabState extends State<_AdvancedAccountingTab> {
  late Future<_AdvancedAccountingData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    widget.store.addListener(_refresh);
  }

  Future<_AdvancedAccountingData> _load() async {
    final results = await Future.wait<Object>([
      AccountingService.listPaymentAccounts(),
      AccountingService.listCashLocations(),
      AccountingService.listCashTransfers(),
      AccountingService.listCashDrawers(),
      AccountingService.listCheques(),
      AccountingService.listAccountingPeriods(),
      AccountingService.listCostCenters(),
      AccountingService.listAccountingBranches(),
      AccountingService.listFixedAssets(),
      AccountingService.listCashBalancesReport(),
      AccountingService.listOpenCashDrawersReport(),
      AccountingService.listCashDrawerVarianceReport(),
      AccountingService.listCashTransferAuditReport(),
    ]);
    return _AdvancedAccountingData(
      paymentAccounts: results[0] as List<AdvancedAccountingItem>,
      cashLocations: results[1] as List<AdvancedAccountingItem>,
      cashTransfers: results[2] as List<AdvancedAccountingItem>,
      cashDrawers: results[3] as List<AdvancedAccountingItem>,
      cheques: results[4] as List<AdvancedAccountingItem>,
      periods: results[5] as List<AdvancedAccountingItem>,
      costCenters: results[6] as List<AdvancedAccountingItem>,
      branches: results[7] as List<AdvancedAccountingItem>,
      fixedAssets: results[8] as List<AdvancedAccountingItem>,
      cashBalancesReport: results[9] as List<AdvancedAccountingItem>,
      openCashDrawersReport: results[10] as List<AdvancedAccountingItem>,
      cashDrawerVarianceReport: results[11] as List<AdvancedAccountingItem>,
      cashTransferAuditReport: results[12] as List<AdvancedAccountingItem>,
    );
  }

  void _refresh() => setState(() => _future = _load());

  @override
  void dispose() {
    widget.store.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _createCashLocationDialog(
      {String initialType = 'cash_drawer'}) async {
    final tr = AppLocalizations.of(context);
    final name = TextEditingController();
    final code = TextEditingController();
    final notes = TextEditingController();
    final locations = await AccountingService.listActiveCashLocations();
    if (!mounted) return;
    final types = <String>[
      'main_vault',
      'branch_vault',
      'cash_drawer',
      'bank',
      'wallet',
      'other'
    ];
    String selectedType = initialType;
    String parentId = '';
    bool allowNegative = false;
    bool isDefault = false;
    bool bindToCurrentDevice = initialType == 'cash_drawer';
    final currentDeviceId = widget.store.appIdentity.deviceId.trim();
    final currentBranchId = widget.store.appIdentity.branchId.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.text('create_cash_location')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    decoration: InputDecoration(labelText: tr.text('name'))),
                const SizedBox(height: 8),
                TextField(
                    controller: code,
                    decoration: InputDecoration(labelText: tr.text('code'))),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: tr.text('cash_location_type')),
                  items: [
                    for (final type in types)
                      DropdownMenuItem(
                          value: type,
                          child: Text(_localizedAccountingType(type, tr)))
                  ],
                  onChanged: (value) => setDialogState(
                      () => selectedType = value ?? selectedType),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: parentId.isEmpty ? null : parentId,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: tr.text('parent_cash_location')),
                  items: [
                    DropdownMenuItem<String>(
                        value: '', child: Text(tr.text('no_parent'))),
                    for (final item in locations)
                      DropdownMenuItem(
                          value: item.id,
                          child: Text(_localizedAccountingName(item.name, tr))),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => parentId = value ?? ''),
                ),
                const SizedBox(height: 8),
                if (selectedType == 'cash_drawer') ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: bindToCurrentDevice,
                    title: const Text('ربط الدرج بالجهاز الحالي'),
                    subtitle: Text(currentDeviceId.isEmpty
                        ? 'لا يوجد Device ID متاح حالياً'
                        : currentDeviceId),
                    onChanged: (value) =>
                        setDialogState(() => bindToCurrentDevice = value),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                    controller: notes,
                    decoration: InputDecoration(labelText: tr.text('notes'))),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isDefault,
                  title: Text(tr.text('default_cash_location')),
                  onChanged: (value) => setDialogState(() => isDefault = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: allowNegative,
                  title: Text(tr.text('allow_negative_cash')),
                  onChanged: (value) =>
                      setDialogState(() => allowNegative = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr.text('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr.text('create'))),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await AccountingService.createCashLocation(
        name: name.text,
        code: code.text,
        type: selectedType,
        parentId: parentId,
        isDefault: isDefault,
        allowNegative: allowNegative,
        notes: notes.text,
        storeId: widget.store.appIdentity.storeId,
        branchId: currentBranchId,
        deviceId: selectedType == 'cash_drawer' && bindToCurrentDevice
            ? currentDeviceId
            : '',
      );
      if (mounted) _refresh();
    }
  }

  Future<void> _showCashTransferJournalHint(AdvancedAccountingItem item) async {
    final tr = AppLocalizations.of(context);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('journal_entry')),
        content: Text(
          item.notes.trim().isEmpty
              ? tr.text('journal_entry_reference_missing')
              : item.notes,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr.text('close'))),
        ],
      ),
    );
  }

  Future<void> _openDrawerDialog() async {
    final controller = TextEditingController(text: '0');
    final tr = AppLocalizations.of(context);
    final locations = await AccountingService.listActiveCashLocations();
    if (!mounted) return;
    final currentDeviceId = widget.store.appIdentity.deviceId.trim();
    final currentBranchId = widget.store.appIdentity.branchId.trim();
    final deviceDrawers = locations
        .where((item) =>
            item.type == 'cash_drawer' &&
            currentDeviceId.isNotEmpty &&
            item.referenceId == currentDeviceId)
        .toList();
    final drawers = deviceDrawers.isNotEmpty
        ? deviceDrawers
        : locations.where((item) => item.type == 'cash_drawer').toList();
    final sources =
        locations.where((item) => item.type != 'cash_drawer').toList();
    String selectedDrawerId = drawers.isNotEmpty ? drawers.first.id : '';
    String selectedFundingId = sources.isNotEmpty ? sources.first.id : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.text('open_cash_drawer')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue:
                    selectedDrawerId.isEmpty ? null : selectedDrawerId,
                decoration: InputDecoration(labelText: tr.text('cash_drawer')),
                items: drawers
                    .map((item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(_localizedAccountingName(item.name, tr))))
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => selectedDrawerId = value ?? ''),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  currentDeviceId.isEmpty
                      ? 'تحذير: لا يوجد Device ID للجهاز الحالي.'
                      : (deviceDrawers.isEmpty
                          ? 'لم يتم العثور على درج مربوط بهذا الجهاز، تم عرض كل الأدراج.'
                          : 'يتم استخدام درج الجهاز الحالي.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue:
                    selectedFundingId.isEmpty ? null : selectedFundingId,
                decoration: InputDecoration(
                    labelText: tr.text('opening_funding_source')),
                items: sources
                    .map((item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(
                            '${_localizedAccountingName(item.name, tr)} • ${formatCurrency(item.balance)}')))
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => selectedFundingId = value ?? ''),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration:
                    InputDecoration(labelText: tr.text('opening_balance')),
              ),
              const SizedBox(height: 4),
              Text(tr.text('opening_cash_transfer_hint'),
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr.text('cancel'))),
            FilledButton(
                onPressed: selectedDrawerId.isEmpty
                    ? null
                    : () => Navigator.pop(context, true),
                child: Text(tr.text('open'))),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      final activeUser = widget.store.activeUser;
      final actorName = activeUser?.fullName.trim().isNotEmpty == true
          ? activeUser!.fullName.trim()
          : (activeUser?.username.trim().isNotEmpty == true
              ? activeUser!.username.trim()
              : widget.store.currentRole);
      await AccountingService.openCashDrawer(
        drawerNo: drawers
            .firstWhere((item) => item.id == selectedDrawerId,
                orElse: () => AdvancedAccountingItem(
                    id: selectedDrawerId, name: 'درج النقد'))
            .name,
        cashLocationId: selectedDrawerId,
        fundingLocationId: selectedFundingId,
        openingBalance: double.tryParse(controller.text) ?? 0,
        openedBy: actorName,
        openedByUserId: activeUser?.id ?? '',
        storeId: widget.store.appIdentity.storeId,
        branchId: currentBranchId,
        deviceId: currentDeviceId,
      );
      if (mounted) _refresh();
    }
  }

  Future<void> _createCashTransferDialog() async {
    final tr = AppLocalizations.of(context);
    final amount = TextEditingController(text: '0');
    final notes = TextEditingController();
    final locations = await AccountingService.listActiveCashLocations();
    if (!mounted) return;
    String fromId = locations.isNotEmpty ? locations.first.id : '';
    String toId = locations.length > 1 ? locations[1].id : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.text('cash_transfer')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: fromId.isEmpty ? null : fromId,
                decoration:
                    InputDecoration(labelText: tr.text('from_cash_location')),
                items: locations
                    .map((item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(
                            '${_localizedAccountingName(item.name, tr)} • ${formatCurrency(item.balance)}')))
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => fromId = value ?? ''),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: toId.isEmpty ? null : toId,
                decoration:
                    InputDecoration(labelText: tr.text('to_cash_location')),
                items: locations
                    .map((item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(
                            '${_localizedAccountingName(item.name, tr)} • ${formatCurrency(item.balance)}')))
                    .toList(),
                onChanged: (value) => setDialogState(() => toId = value ?? ''),
              ),
              const SizedBox(height: 8),
              TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tr.text('amount'))),
              TextField(
                  controller: notes,
                  decoration: InputDecoration(labelText: tr.text('notes'))),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr.text('cancel'))),
            FilledButton(
                onPressed: fromId.isEmpty || toId.isEmpty || fromId == toId
                    ? null
                    : () => Navigator.pop(context, true),
                child: Text(tr.text('post'))),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await AccountingService.createCashTransfer(
        fromLocationId: fromId,
        toLocationId: toId,
        amount: double.tryParse(amount.text) ?? 0,
        notes: notes.text,
      );
      if (mounted) _refresh();
    }
  }

  Future<void> _manualJournalDialog() async {
    final tr = AppLocalizations.of(context);
    final description =
        TextEditingController(text: tr.text('manual_journal_entry'));
    final debitAmount = TextEditingController(text: '0');
    final creditAmount = TextEditingController(text: '0');
    final accounts = await AccountingService.listAccounts();
    final costCenters = await AccountingService.listCostCenters();
    final branches = await AccountingService.listAccountingBranches();
    if (accounts.length < 2) return;
    AccountingAccount? debitAccount = accounts.first;
    AccountingAccount? creditAccount =
        accounts.length > 1 ? accounts[1] : debitAccount;
    AdvancedAccountingItem? debitCostCenter;
    AdvancedAccountingItem? creditCostCenter;
    AdvancedAccountingItem? branch;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.text('create_manual_journal')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: description,
                    decoration:
                        InputDecoration(labelText: tr.text('description'))),
                const SizedBox(height: 8),
                DropdownButtonFormField<AdvancedAccountingItem?>(
                  initialValue: branch,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr.text('branch')),
                  items: [
                    DropdownMenuItem<AdvancedAccountingItem?>(
                        value: null, child: Text(tr.text('no_branch'))),
                    for (final item in branches)
                      DropdownMenuItem<AdvancedAccountingItem?>(
                          value: item,
                          child: Text(
                              '${item.accountCode} - ${_localizedAccountingName(item.name, tr)}')),
                  ],
                  onChanged: (value) => setDialogState(() => branch = value),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<AccountingAccount>(
                  initialValue: debitAccount,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: tr.text('debit_account')),
                  items: [
                    for (final a in accounts)
                      DropdownMenuItem(
                          value: a,
                          child: Text(
                              '${a.code} - ${_localizedAccountingName(a.name, tr)}'))
                  ],
                  onChanged: (value) =>
                      setDialogState(() => debitAccount = value),
                ),
                TextField(
                    controller: debitAmount,
                    keyboardType: TextInputType.number,
                    decoration:
                        InputDecoration(labelText: tr.text('debit_amount'))),
                DropdownButtonFormField<AdvancedAccountingItem?>(
                  initialValue: debitCostCenter,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: tr.text('debit_cost_center')),
                  items: [
                    DropdownMenuItem<AdvancedAccountingItem?>(
                        value: null, child: Text(tr.text('no_cost_center'))),
                    for (final item in costCenters)
                      DropdownMenuItem<AdvancedAccountingItem?>(
                          value: item,
                          child: Text(
                              '${item.accountCode} - ${_localizedAccountingName(item.name, tr)}')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => debitCostCenter = value),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<AccountingAccount>(
                  initialValue: creditAccount,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: tr.text('credit_account')),
                  items: [
                    for (final a in accounts)
                      DropdownMenuItem(
                          value: a,
                          child: Text(
                              '${a.code} - ${_localizedAccountingName(a.name, tr)}'))
                  ],
                  onChanged: (value) =>
                      setDialogState(() => creditAccount = value),
                ),
                TextField(
                    controller: creditAmount,
                    keyboardType: TextInputType.number,
                    decoration:
                        InputDecoration(labelText: tr.text('credit_amount'))),
                DropdownButtonFormField<AdvancedAccountingItem?>(
                  initialValue: creditCostCenter,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: tr.text('credit_cost_center')),
                  items: [
                    DropdownMenuItem<AdvancedAccountingItem?>(
                        value: null, child: Text(tr.text('no_cost_center'))),
                    for (final item in costCenters)
                      DropdownMenuItem<AdvancedAccountingItem?>(
                          value: item,
                          child: Text(
                              '${item.accountCode} - ${_localizedAccountingName(item.name, tr)}')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => creditCostCenter = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr.text('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr.text('post'))),
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
          JournalLineDraft(
              accountId: debitAccount!.id,
              debit: amount,
              credit: 0,
              costCenterId: debitCostCenter?.id ?? ''),
          JournalLineDraft(
              accountId: creditAccount!.id,
              debit: 0,
              credit: amount,
              costCenterId: creditCostCenter?.id ?? ''),
        ],
      );
      if (mounted) _refresh();
    }
  }

  Future<void> _runDepreciationForAllDialog() async {
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('run_depreciation')),
        content: Text(tr.text('run_depreciation_all_desc')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('run'))),
        ],
      ),
    );
    if (confirmed == true) {
      final posted = await AccountingService.runDepreciationForAllAssets();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              tr.format('depreciation_entries_posted', {'count': posted}))));
      _refresh();
    }
  }

  Future<void> _runDepreciationForAssetDialog(
      AdvancedAccountingItem item) async {
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.format('run_depreciation_for',
            {'name': _localizedAccountingName(item.name, tr)})),
        content: Text(tr.text('run_depreciation_asset_desc')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('run'))),
        ],
      ),
    );
    if (confirmed == true) {
      final posted =
          await AccountingService.runDepreciationForAsset(assetId: item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              tr.format('depreciation_entries_posted', {'count': posted}))));
      _refresh();
    }
  }

  Future<void> _createFixedAssetDialog() async {
    final tr = AppLocalizations.of(context);
    final code = TextEditingController();
    final name = TextEditingController();
    final category = TextEditingController(text: tr.text('equipment'));
    final purchaseValue = TextEditingController(text: '0');
    final usefulLifeMonths = TextEditingController(text: '0');
    final notes = TextEditingController();
    final accounts = await AccountingService.listAccounts();
    final assetAccounts = accounts.where((a) => a.type == 'asset').toList();
    if (assetAccounts.isEmpty) return;
    AccountingAccount? assetAccount = assetAccounts.firstWhere(
      (a) => a.subtype == 'fixed_assets',
      orElse: () => assetAccounts.first,
    );
    AccountingAccount? paymentAccount = assetAccounts.firstWhere(
      (a) => a.subtype == 'cash',
      orElse: () => assetAccounts.first,
    );
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.text('create_fixed_asset')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: code,
                  decoration: InputDecoration(labelText: tr.text('code'))),
              TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: tr.text('name'))),
              TextField(
                  controller: category,
                  decoration: InputDecoration(labelText: tr.text('category'))),
              TextField(
                  controller: purchaseValue,
                  keyboardType: TextInputType.number,
                  decoration:
                      InputDecoration(labelText: tr.text('purchase_value'))),
              TextField(
                  controller: usefulLifeMonths,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: tr.text('useful_life_months'))),
              const SizedBox(height: 8),
              DropdownButtonFormField<AccountingAccount>(
                initialValue: assetAccount,
                isExpanded: true,
                decoration:
                    InputDecoration(labelText: tr.text('fixed_assets_account')),
                items: [
                  for (final a in assetAccounts)
                    DropdownMenuItem(
                        value: a,
                        child: Text(
                            '${a.code} - ${_localizedAccountingName(a.name, tr)}'))
                ],
                onChanged: (value) =>
                    setDialogState(() => assetAccount = value),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<AccountingAccount>(
                initialValue: paymentAccount,
                isExpanded: true,
                decoration:
                    InputDecoration(labelText: tr.text('payment_account')),
                items: [
                  for (final a in assetAccounts)
                    DropdownMenuItem(
                        value: a,
                        child: Text(
                            '${a.code} - ${_localizedAccountingName(a.name, tr)}'))
                ],
                onChanged: (value) =>
                    setDialogState(() => paymentAccount = value),
              ),
              TextField(
                  controller: notes,
                  decoration: InputDecoration(labelText: tr.text('notes'))),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr.text('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr.text('create'))),
          ],
        ),
      ),
    );
    if (confirmed == true && assetAccount != null && paymentAccount != null) {
      await AccountingService.createFixedAsset(
        code: code.text,
        name: name.text,
        category: category.text,
        acquisitionDate: DateTime.now(),
        purchaseValue: double.tryParse(purchaseValue.text) ?? 0,
        usefulLifeMonths: int.tryParse(usefulLifeMonths.text) ?? 0,
        assetAccountId: assetAccount!.id,
        paymentAccountId: paymentAccount!.id,
        notes: notes.text,
      );
      if (mounted) _refresh();
    }
  }

  Future<void> _createPaymentAccountDialog() async {
    final tr = AppLocalizations.of(context);
    final name = TextEditingController();
    var type = 'bank';
    var isDefault = false;
    final accounts = await AccountingService.listAccounts();
    if (accounts.isEmpty) return;
    AccountingAccount? selected = accounts.firstWhere((a) => a.type == 'asset',
        orElse: () => accounts.first);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.text('create_payment_account')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: tr.text('name'))),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: InputDecoration(labelText: tr.text('type')),
                items: [
                  DropdownMenuItem(value: 'cash', child: Text(tr.text('cash'))),
                  DropdownMenuItem(value: 'bank', child: Text(tr.text('bank'))),
                  DropdownMenuItem(value: 'card', child: Text(tr.text('card'))),
                  DropdownMenuItem(
                      value: 'wallet', child: Text(tr.text('wallet'))),
                  DropdownMenuItem(
                      value: 'cheque', child: Text(tr.text('cheque'))),
                  DropdownMenuItem(
                      value: 'other', child: Text(tr.text('other'))),
                ],
                onChanged: (v) => setDialogState(() => type = v ?? type),
              ),
              DropdownButtonFormField<AccountingAccount>(
                initialValue: selected,
                decoration:
                    InputDecoration(labelText: tr.text('mapped_account')),
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(
                        value: a,
                        child: Text(
                            '${a.code} - ${_localizedAccountingName(a.name, tr)}'))
                ],
                onChanged: (v) => setDialogState(() => selected = v),
              ),
              CheckboxListTile(
                  value: isDefault,
                  onChanged: (v) =>
                      setDialogState(() => isDefault = v ?? false),
                  title: Text(tr.text('default_for_this_type'))),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr.text('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr.text('create')))
          ],
        ),
      ),
    );
    if (confirmed == true && selected != null) {
      await AccountingService.createPaymentAccount(
          name: name.text,
          type: type,
          accountId: selected!.id,
          isDefault: isDefault);
      if (mounted) _refresh();
    }
  }

  Future<void> _createChequeDialog() async {
    final tr = AppLocalizations.of(context);
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
          title: Text(tr.text('create_cheque')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: chequeNo,
                  decoration: InputDecoration(labelText: tr.text('cheque_no'))),
              DropdownButtonFormField<String>(
                initialValue: direction,
                decoration: InputDecoration(labelText: tr.text('direction')),
                items: [
                  DropdownMenuItem(
                      value: 'received', child: Text(tr.text('received'))),
                  DropdownMenuItem(
                      value: 'issued', child: Text(tr.text('issued'))),
                ],
                onChanged: (v) =>
                    setDialogState(() => direction = v ?? direction),
              ),
              TextField(
                  controller: partyName,
                  decoration:
                      InputDecoration(labelText: tr.text('party_name'))),
              TextField(
                  controller: bankName,
                  decoration: InputDecoration(labelText: tr.text('bank'))),
              TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tr.text('amount'))),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr.text('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr.text('create')))
          ],
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
    final tr = AppLocalizations.of(context);
    final code = TextEditingController();
    final name = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: code,
              decoration: InputDecoration(labelText: tr.text('code'))),
          TextField(
              controller: name,
              decoration: InputDecoration(labelText: tr.text('name'))),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('create')))
        ],
      ),
    );
    if (confirmed == true) {
      await AccountingService.createSimpleMasterData(
          table: table, code: code.text, name: name.text);
      if (mounted) _refresh();
    }
  }

  Future<void> _closeDrawerDialog(AdvancedAccountingItem item) async {
    final tr = AppLocalizations.of(context);
    final expected =
        await AccountingService.calculateCashDrawerExpectedCash(item.id);
    final locations = await AccountingService.listActiveCashLocations();
    if (!mounted) return;
    final counted = TextEditingController(text: expected.toStringAsFixed(2));
    final notes = TextEditingController();
    final transferTargets =
        locations.where((location) => location.id != item.referenceId).toList();
    final activeUsers =
        widget.store.users.where((user) => user.isActive).toList();
    final activeUser = widget.store.activeUser;
    final handoverUsers =
        activeUsers.where((user) => user.id != (activeUser?.id ?? '')).toList();
    String closeMode = 'close_only';
    String transferToId =
        transferTargets.isNotEmpty ? transferTargets.first.id : '';
    String nextUserId = handoverUsers.isNotEmpty ? handoverUsers.first.id : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.format(
              'close_item', {'name': _localizedAccountingName(item.name, tr)})),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(tr.format(
                  'expected_cash', {'amount': formatCurrency(expected)})),
              const SizedBox(height: 4),
              Text(tr.text('cash_reconciliation_difference_hint'),
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              TextField(
                  controller: counted,
                  keyboardType: TextInputType.number,
                  decoration:
                      InputDecoration(labelText: tr.text('counted_cash'))),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: closeMode,
                decoration: const InputDecoration(labelText: 'إجراء الإغلاق'),
                items: const [
                  DropdownMenuItem(
                      value: 'close_only',
                      child: Text('إغلاق الوردية وترك النقد في نفس الدرج')),
                  DropdownMenuItem(
                      value: 'transfer_location',
                      child: Text('إغلاق وتحويل النقد إلى درج / صندوق آخر')),
                  DropdownMenuItem(
                      value: 'handover_user',
                      child: Text('تسليم لموظف جديد وفتح وردية جديدة')),
                ],
                onChanged: (value) =>
                    setDialogState(() => closeMode = value ?? closeMode),
              ),
              if (closeMode == 'transfer_location') ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: transferToId.isEmpty ? null : transferToId,
                  decoration: const InputDecoration(labelText: 'التحويل إلى'),
                  items: transferTargets
                      .map((location) => DropdownMenuItem(
                          value: location.id,
                          child: Text(
                              '${_localizedAccountingName(location.name, tr)} • ${formatCurrency(location.balance)}')))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => transferToId = value ?? ''),
                ),
              ],
              if (closeMode == 'handover_user') ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: nextUserId.isEmpty ? null : nextUserId,
                  decoration:
                      const InputDecoration(labelText: 'الموظف المستلم'),
                  items: handoverUsers.map((user) {
                    final label = user.fullName.trim().isNotEmpty
                        ? user.fullName.trim()
                        : user.username.trim();
                    return DropdownMenuItem(
                        value: user.id,
                        child: Text(label.isEmpty ? user.id : label));
                  }).toList(),
                  onChanged: (value) =>
                      setDialogState(() => nextUserId = value ?? ''),
                ),
                const SizedBox(height: 4),
                Text(
                    'سيتم إغلاق وردية الموظف الحالي وفتح وردية جديدة للموظف المستلم بنفس المبلغ المعدود.',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              TextField(
                  controller: notes,
                  decoration: InputDecoration(labelText: tr.text('notes'))),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed:
                  (closeMode == 'transfer_location' && transferToId.isEmpty) ||
                          (closeMode == 'handover_user' && nextUserId.isEmpty)
                      ? null
                      : () => Navigator.pop(context, true),
              child: Text(tr.text('close')),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      final activeUser = widget.store.activeUser;
      final actorName = activeUser?.fullName.trim().isNotEmpty == true
          ? activeUser!.fullName.trim()
          : (activeUser?.username.trim().isNotEmpty == true
              ? activeUser!.username.trim()
              : widget.store.currentRole);
      final countedAmount = double.tryParse(counted.text) ?? 0;
      AppUser? selectedNextUser;
      for (final user in handoverUsers) {
        if (user.id == nextUserId) {
          selectedNextUser = user;
          break;
        }
      }
      final selectedNextUserName = selectedNextUser == null
          ? ''
          : (selectedNextUser.fullName.trim().isNotEmpty
              ? selectedNextUser.fullName.trim()
              : selectedNextUser.username.trim());
      String transferTargetName = transferToId;
      for (final location in transferTargets) {
        if (location.id == transferToId) {
          transferTargetName = _localizedAccountingName(location.name, tr);
          break;
        }
      }
      final effectiveNotes = [
        notes.text.trim(),
        if (closeMode == 'transfer_location')
          'تحويل النقد بعد الإغلاق إلى $transferTargetName',
        if (closeMode == 'handover_user')
          'تسليم الوردية إلى $selectedNextUserName',
      ].where((part) => part.trim().isNotEmpty).join(' • ');
      await AccountingService.closeCashDrawer(
        sessionId: item.id,
        countedCash: countedAmount,
        closedBy: actorName,
        closedByUserId: activeUser?.id ?? '',
        notes: effectiveNotes,
        depositToLocationId:
            closeMode == 'transfer_location' ? transferToId : '',
      );
      if (closeMode == 'handover_user' &&
          item.referenceId.trim().isNotEmpty &&
          selectedNextUser != null) {
        await AccountingService.openCashDrawer(
          drawerNo: item.name,
          cashLocationId: item.referenceId,
          openingBalance: countedAmount,
          openedBy: selectedNextUserName,
          openedByUserId: selectedNextUser.id,
          storeId: widget.store.appIdentity.storeId,
          branchId: widget.store.appIdentity.branchId,
          deviceId: widget.store.appIdentity.deviceId,
        );
      }
      if (mounted) _refresh();
    }
  }

  Future<void> _settleCheque(AdvancedAccountingItem item) async {
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.format(
            'clear_cheque', {'name': _localizedAccountingName(item.name, tr)})),
        content: Text(tr.format(
            'mark_cheque_cleared', {'amount': formatCurrency(item.balance)})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('clear')))
        ],
      ),
    );
    if (confirmed == true) {
      await AccountingService.settleCheque(chequeId: item.id);
      if (mounted) _refresh();
    }
  }

  Future<void> _bounceChequeDialog(AdvancedAccountingItem item) async {
    final tr = AppLocalizations.of(context);
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.format('bounce_cheque',
            {'name': _localizedAccountingName(item.name, tr)})),
        content: TextField(
            controller: reason,
            decoration: InputDecoration(labelText: tr.text('reason'))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('bounce')))
        ],
      ),
    );
    if (confirmed == true) {
      await AccountingService.bounceCheque(
          chequeId: item.id, reason: reason.text);
      if (mounted) _refresh();
    }
  }

  Future<void> _closePeriod(AdvancedAccountingItem item) async {
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.format(
            'close_period', {'name': _localizedAccountingName(item.name, tr)})),
        content: Text(tr.text('close_period_desc')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('close_period')))
        ],
      ),
    );
    if (confirmed == true) {
      await AccountingService.closeAccountingPeriod(periodId: item.id);
      if (mounted) _refresh();
    }
  }

  Future<void> _createPeriodDialog() async {
    final tr = AppLocalizations.of(context);
    final name = TextEditingController(text: tr.text('current_period'));
    final now = DateTime.now();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('create_accounting_period')),
        content: TextField(
            controller: name,
            decoration: InputDecoration(labelText: tr.text('period_name'))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('create'))),
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
    final canManageAccounting =
        widget.store.hasPermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    return FutureBuilder<_AdvancedAccountingData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError)
          return _ReportError(message: snapshot.error.toString());
        final data = snapshot.data ?? const _AdvancedAccountingData();
        if (widget.cashOnly) {
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
                      Text(tr.text('cash_management'),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(tr.text('cash_management_desc'),
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                              onPressed: canManageAccounting
                                  ? () => _createCashLocationDialog(
                                      initialType: 'main_vault')
                                  : null,
                              icon: const Icon(
                                  Icons.account_balance_wallet_outlined),
                              label: Text(tr.text('create_vault'))),
                          FilledButton.tonalIcon(
                              onPressed: canManageAccounting
                                  ? () => _createCashLocationDialog(
                                      initialType: 'cash_drawer')
                                  : null,
                              icon: const Icon(Icons.point_of_sale_outlined),
                              label: Text(tr.text('create_cash_drawer'))),
                          FilledButton.tonalIcon(
                              onPressed: canManageAccounting
                                  ? _openDrawerDialog
                                  : null,
                              icon: const Icon(Icons.play_circle_outline),
                              label: Text(tr.text('open_drawer'))),
                          FilledButton.tonalIcon(
                              onPressed: canManageAccounting
                                  ? _createCashTransferDialog
                                  : null,
                              icon: const Icon(Icons.compare_arrows_outlined),
                              label: Text(tr.text('cash_transfer'))),
                        ],
                      ),
                      if (!canManageAccounting) ...[
                        const SizedBox(height: 8),
                        Text(tr.text('accounting_read_only_permission'),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _AdvancedSection(
                  title: tr.text('cash_locations'),
                  icon: Icons.account_balance_wallet_outlined,
                  items: data.cashLocations),
              _AdvancedSection(
                title: tr.text('cash_drawer_sessions'),
                icon: Icons.point_of_sale_outlined,
                items: data.cashDrawers,
                actionBuilder: canManageAccounting
                    ? (item) => item.status == 'open'
                        ? [
                            TextButton.icon(
                                onPressed: () => _closeDrawerDialog(item),
                                icon: const Icon(Icons.lock_outline),
                                label: Text(tr.text('close')))
                          ]
                        : const <Widget>[]
                    : null,
              ),
              _AdvancedSection(
                  title: tr.text('cash_monitoring'),
                  icon: Icons.monitor_heart_outlined,
                  items: data.cashBalancesReport),
              _AdvancedSection(
                  title: tr.text('open_cash_drawers_report'),
                  icon: Icons.point_of_sale_outlined,
                  items: data.openCashDrawersReport),
              _AdvancedSection(
                  title: tr.text('cash_drawer_variance_report'),
                  icon: Icons.balance_outlined,
                  items: data.cashDrawerVarianceReport),
              _AdvancedSection(
                title: tr.text('cash_transfer_audit_report'),
                icon: Icons.receipt_long_outlined,
                items: data.cashTransferAuditReport,
                actionBuilder: (item) => [
                  TextButton.icon(
                      onPressed: () => _showCashTransferJournalHint(item),
                      icon: const Icon(Icons.menu_book_outlined),
                      label: Text(tr.text('view_journal')))
                ],
              ),
              _AdvancedSection(
                  title: tr.text('cash_transfers'),
                  icon: Icons.compare_arrows_outlined,
                  items: data.cashTransfers),
            ],
          );
        }
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
                    Text(tr.text('advanced_accounting_controls'),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(tr.text('advanced_accounting_controls_desc'),
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                            onPressed: canManageAccounting
                                ? _manualJournalDialog
                                : null,
                            icon: const Icon(Icons.edit_note_outlined),
                            label: Text(tr.text('manual_journal'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? () => _createCashLocationDialog(
                                    initialType: 'main_vault')
                                : null,
                            icon: const Icon(
                                Icons.account_balance_wallet_outlined),
                            label: Text(tr.text('create_vault'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? () => _createCashLocationDialog(
                                    initialType: 'cash_drawer')
                                : null,
                            icon: const Icon(Icons.point_of_sale_outlined),
                            label: Text(tr.text('create_cash_drawer'))),
                        FilledButton.tonalIcon(
                            onPressed:
                                canManageAccounting ? _openDrawerDialog : null,
                            icon: const Icon(Icons.play_circle_outline),
                            label: Text(tr.text('open_drawer'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? _createCashTransferDialog
                                : null,
                            icon: const Icon(Icons.compare_arrows_outlined),
                            label: Text(tr.text('cash_transfer'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? _createPaymentAccountDialog
                                : null,
                            icon: const Icon(
                                Icons.account_balance_wallet_outlined),
                            label: Text(tr.text('payment_account'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? _createChequeDialog
                                : null,
                            icon: const Icon(Icons.payments_outlined),
                            label: Text(tr.text('cheque'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? _createPeriodDialog
                                : null,
                            icon: const Icon(Icons.event_available_outlined),
                            label: Text(tr.text('create_period'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? _createFixedAssetDialog
                                : null,
                            icon: const Icon(Icons.business_center_outlined),
                            label: Text(tr.text('fixed_asset'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? _runDepreciationForAllDialog
                                : null,
                            icon: const Icon(Icons.calculate_outlined),
                            label: Text(tr.text('run_depreciation'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? () => _createMasterDataDialog('cost_centers',
                                    tr.text('create_cost_center'))
                                : null,
                            icon: const Icon(Icons.hub_outlined),
                            label: Text(tr.text('cost_center'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? () => _createMasterDataDialog(
                                    'accounting_branches',
                                    tr.text('create_branch'))
                                : null,
                            icon:
                                const Icon(Icons.store_mall_directory_outlined),
                            label: Text(tr.text('branch'))),
                      ],
                    ),
                    if (!canManageAccounting) ...[
                      const SizedBox(height: 8),
                      Text(tr.text('accounting_read_only_permission'),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context).colorScheme.error)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _AdvancedSection(
                title: tr.text('payment_accounts'),
                icon: Icons.account_balance_wallet_outlined,
                items: data.paymentAccounts),
            _AdvancedSection(
                title: tr.text('cash_monitoring'),
                icon: Icons.monitor_heart_outlined,
                items: data.cashBalancesReport),
            _AdvancedSection(
                title: tr.text('open_cash_drawers_report'),
                icon: Icons.point_of_sale_outlined,
                items: data.openCashDrawersReport),
            _AdvancedSection(
                title: tr.text('cash_drawer_variance_report'),
                icon: Icons.balance_outlined,
                items: data.cashDrawerVarianceReport),
            _AdvancedSection(
              title: tr.text('cash_transfer_audit_report'),
              icon: Icons.receipt_long_outlined,
              items: data.cashTransferAuditReport,
              actionBuilder: (item) => [
                TextButton.icon(
                    onPressed: () => _showCashTransferJournalHint(item),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: Text(tr.text('view_journal')))
              ],
            ),
            _AdvancedSection(
                title: tr.text('cash_locations'),
                icon: Icons.account_balance_wallet_outlined,
                items: data.cashLocations),
            _AdvancedSection(
                title: tr.text('cash_transfers'),
                icon: Icons.compare_arrows_outlined,
                items: data.cashTransfers),
            _AdvancedSection(
              title: tr.text('cash_drawer_sessions'),
              icon: Icons.point_of_sale_outlined,
              items: data.cashDrawers,
              actionBuilder: canManageAccounting
                  ? (item) => item.status == 'open'
                      ? [
                          TextButton.icon(
                              onPressed: () => _closeDrawerDialog(item),
                              icon: const Icon(Icons.lock_outline),
                              label: Text(tr.text('close')))
                        ]
                      : const <Widget>[]
                  : null,
            ),
            _AdvancedSection(
              title: tr.text('cheques'),
              icon: Icons.payments_outlined,
              items: data.cheques,
              actionBuilder: canManageAccounting
                  ? (item) => item.status == 'pending'
                      ? [
                          TextButton.icon(
                              onPressed: () => _settleCheque(item),
                              icon: const Icon(Icons.check_circle_outline),
                              label: Text(tr.text('clear'))),
                          TextButton.icon(
                              onPressed: () => _bounceChequeDialog(item),
                              icon: const Icon(Icons.cancel_outlined),
                              label: Text(tr.text('bounce'))),
                        ]
                      : const <Widget>[]
                  : null,
            ),
            _AdvancedSection(
              title: tr.text('accounting_periods'),
              icon: Icons.date_range_outlined,
              items: data.periods,
              actionBuilder: canManageAccounting
                  ? (item) => item.type == 'open'
                      ? [
                          TextButton.icon(
                              onPressed: () => _closePeriod(item),
                              icon: const Icon(Icons.event_busy_outlined),
                              label: Text(tr.text('close')))
                        ]
                      : const <Widget>[]
                  : null,
            ),
            _AdvancedSection(
              title: tr.text('fixed_assets'),
              icon: Icons.business_center_outlined,
              items: data.fixedAssets,
              actionBuilder: canManageAccounting
                  ? (item) => item.status == 'active'
                      ? [
                          TextButton.icon(
                              onPressed: () =>
                                  _runDepreciationForAssetDialog(item),
                              icon: const Icon(Icons.calculate_outlined),
                              label: Text(tr.text('depreciate')))
                        ]
                      : const <Widget>[]
                  : null,
            ),
            _AdvancedSection(
                title: tr.text('cost_centers'),
                icon: Icons.hub_outlined,
                items: data.costCenters),
            _AdvancedSection(
                title: tr.text('branches'),
                icon: Icons.store_mall_directory_outlined,
                items: data.branches),
          ],
        );
      },
    );
  }
}

class _AdvancedAccountingData {
  const _AdvancedAccountingData({
    this.paymentAccounts = const <AdvancedAccountingItem>[],
    this.cashLocations = const <AdvancedAccountingItem>[],
    this.cashTransfers = const <AdvancedAccountingItem>[],
    this.cashDrawers = const <AdvancedAccountingItem>[],
    this.cheques = const <AdvancedAccountingItem>[],
    this.periods = const <AdvancedAccountingItem>[],
    this.costCenters = const <AdvancedAccountingItem>[],
    this.branches = const <AdvancedAccountingItem>[],
    this.fixedAssets = const <AdvancedAccountingItem>[],
    this.cashBalancesReport = const <AdvancedAccountingItem>[],
    this.openCashDrawersReport = const <AdvancedAccountingItem>[],
    this.cashDrawerVarianceReport = const <AdvancedAccountingItem>[],
    this.cashTransferAuditReport = const <AdvancedAccountingItem>[],
  });

  final List<AdvancedAccountingItem> paymentAccounts;
  final List<AdvancedAccountingItem> cashLocations;
  final List<AdvancedAccountingItem> cashTransfers;
  final List<AdvancedAccountingItem> cashDrawers;
  final List<AdvancedAccountingItem> cheques;
  final List<AdvancedAccountingItem> periods;
  final List<AdvancedAccountingItem> costCenters;
  final List<AdvancedAccountingItem> branches;
  final List<AdvancedAccountingItem> fixedAssets;
  final List<AdvancedAccountingItem> cashBalancesReport;
  final List<AdvancedAccountingItem> openCashDrawersReport;
  final List<AdvancedAccountingItem> cashDrawerVarianceReport;
  final List<AdvancedAccountingItem> cashTransferAuditReport;
}

class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection(
      {required this.title,
      required this.icon,
      required this.items,
      this.actionBuilder});

  final String title;
  final IconData icon;
  final List<AdvancedAccountingItem> items;
  final List<Widget> Function(AdvancedAccountingItem item)? actionBuilder;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Card(
      elevation: 0,
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(tr.format('records_count', {'count': items.length})),
        children: items.isEmpty
            ? [ListTile(title: Text(tr.text('no_records_yet')))]
            : [
                for (final item in items)
                  ListTile(
                    title: Text(item.name.isEmpty
                        ? item.id
                        : _localizedAccountingName(item.name, tr)),
                    subtitle: Text([
                      _localizedAccountingType(item.type, tr),
                      _localizedAccountingStatus(item.status, tr),
                      item.accountCode,
                      _localizedAccountingName(item.accountName, tr),
                      _localizedAccountingNote(item.notes, tr),
                    ].where((value) => value.trim().isNotEmpty).join(' • ')),
                    trailing: Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (item.balance != 0)
                          Text(formatCurrency(item.balance)),
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
      titleKey: 'default_cash_account',
      subtitleKey: 'default_cash_account_desc',
      icon: Icons.payments_outlined,
    ),
    _AccountingSettingDefinition(
      key: 'default_bank_account_id',
      titleKey: 'default_bank_card_account',
      subtitleKey: 'default_bank_card_account_desc',
      icon: Icons.account_balance_outlined,
    ),
    _AccountingSettingDefinition(
      key: 'default_customers_account_id',
      titleKey: 'customers_receivable_account',
      subtitleKey: 'customers_receivable_account_desc',
      icon: Icons.people_outline,
    ),
    _AccountingSettingDefinition(
      key: 'default_suppliers_account_id',
      titleKey: 'suppliers_payable_account',
      subtitleKey: 'suppliers_payable_account_desc',
      icon: Icons.local_shipping_outlined,
    ),
    _AccountingSettingDefinition(
      key: 'default_inventory_account_id',
      titleKey: 'inventory_account',
      subtitleKey: 'inventory_account_desc',
      icon: Icons.inventory_2_outlined,
    ),
    _AccountingSettingDefinition(
      key: 'default_fixed_assets_account_id',
      titleKey: 'fixed_assets_account',
      subtitleKey: 'fixed_assets_account_desc',
      icon: Icons.business_center_outlined,
    ),
    _AccountingSettingDefinition(
      key: 'default_accumulated_depreciation_account_id',
      titleKey: 'accumulated_depreciation_account',
      subtitleKey: 'accumulated_depreciation_account_desc',
      icon: Icons.account_tree_outlined,
    ),
    _AccountingSettingDefinition(
      key: 'default_depreciation_expense_account_id',
      titleKey: 'depreciation_expense_account',
      subtitleKey: 'depreciation_expense_account_desc',
      icon: Icons.calculate_outlined,
    ),
    _AccountingSettingDefinition(
      key: 'default_sales_account_id',
      titleKey: 'sales_revenue_account',
      subtitleKey: 'sales_revenue_account_desc',
      icon: Icons.point_of_sale_outlined,
    ),
    _AccountingSettingDefinition(
      key: 'default_cogs_account_id',
      titleKey: 'cost_of_goods_sold_account',
      subtitleKey: 'cost_of_goods_sold_account_desc',
      icon: Icons.trending_down_outlined,
    ),
    _AccountingSettingDefinition(
      key: 'default_expense_account_id',
      titleKey: 'default_expense_account',
      subtitleKey: 'default_expense_account_desc',
      icon: Icons.receipt_long_outlined,
    ),
    _AccountingSettingDefinition(
      key: 'default_sales_tax_account_id',
      titleKey: 'sales_tax_account',
      subtitleKey: 'sales_tax_account_desc',
      icon: Icons.call_made_outlined,
    ),
    _AccountingSettingDefinition(
      key: 'default_purchase_tax_account_id',
      titleKey: 'purchase_tax_account',
      subtitleKey: 'purchase_tax_account_desc',
      icon: Icons.call_received_outlined,
    ),
    _AccountingSettingDefinition(
      key: 'default_tax_payable_account_id',
      titleKey: 'tax_payable_account',
      subtitleKey: 'tax_payable_account_desc',
      icon: Icons.account_balance_outlined,
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
      AccountingService.readDefaultVatRatePercent(),
    ]);
    return _AccountingSettingsData(
      accounts: (results[0] as List<AccountingAccount>)
          .where((account) => account.subtype != 'group' && account.isActive)
          .toList(),
      settings: results[1] as Map<String, String>,
      vatRatePercent: results[2] as double,
    );
  }

  Future<void> _updateSetting(String key, String accountId) async {
    await AccountingService.updateDefaultAccount(
        key: key, accountId: accountId);
    if (!mounted) return;
    setState(() => _future = _load());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              AppLocalizations.of(context).text('accounting_setting_updated'))),
    );
  }

  Future<void> _updateVatRate(double ratePercent) async {
    await AccountingService.updateDefaultVatRatePercent(ratePercent);
    if (!mounted) return;
    setState(() => _future = _load());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              AppLocalizations.of(context).text('accounting_setting_updated'))),
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
        final data = snapshot.data ??
            const _AccountingSettingsData(
                accounts: <AccountingAccount>[],
                settings: <String, String>{},
                vatRatePercent: 0);
        final canManageAccounting =
            widget.store.hasPermission(AppPermission.accountingManage);
        if (data.accounts.isEmpty) {
          return _EmptyAccountingState(
              message: AppLocalizations.of(context)
                  .text('no_active_posting_accounts_found'));
        }
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _definitions.length + 2,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          AppLocalizations.of(context)
                              .text('accounting_account_mapping'),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        AppLocalizations.of(context)
                            .text('accounting_account_mapping_desc'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      if (!canManageAccounting) ...[
                        const SizedBox(height: 8),
                        Text(
                          AppLocalizations.of(context)
                              .text('accounting_read_only_permission'),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                    ],
                  ),
                );
              }
              if (index == 1) {
                return _VatRateSettingRow(
                  ratePercent: data.vatRatePercent,
                  enabled: canManageAccounting,
                  onChanged: _updateVatRate,
                );
              }
              final definition = _definitions[index - 2];
              return _AccountingSettingRow(
                definition: definition,
                accounts: data.accounts,
                selectedAccountId: data.settings[definition.key] ?? '',
                onChanged: canManageAccounting
                    ? (accountId) => _updateSetting(definition.key, accountId)
                    : null,
              );
            },
          ),
        );
      },
    );
  }
}

class _AccountingSettingsData {
  const _AccountingSettingsData(
      {required this.accounts,
      required this.settings,
      required this.vatRatePercent});

  final List<AccountingAccount> accounts;
  final Map<String, String> settings;
  final double vatRatePercent;
}

class _AccountingSettingDefinition {
  const _AccountingSettingDefinition(
      {required this.key,
      required this.titleKey,
      required this.subtitleKey,
      required this.icon});

  final String key;
  final String titleKey;
  final String subtitleKey;
  final IconData icon;
}

class _VatRateSettingRow extends StatefulWidget {
  const _VatRateSettingRow(
      {required this.ratePercent,
      required this.enabled,
      required this.onChanged});

  final double ratePercent;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  State<_VatRateSettingRow> createState() => _VatRateSettingRowState();
}

class _VatRateSettingRowState extends State<_VatRateSettingRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
        text: widget.ratePercent.toStringAsFixed(
            widget.ratePercent == widget.ratePercent.roundToDouble() ? 0 : 2));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                  radius: 18, child: Icon(Icons.percent_outlined, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr.text('default_vat_rate'),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(tr.text('default_vat_rate_desc'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          );
          final field = TextField(
            controller: _controller,
            enabled: widget.enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: tr.text('vat_rate_percent'),
              suffixText: '%',
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) =>
                widget.onChanged(double.tryParse(value.trim()) ?? 0),
          );
          final save = FilledButton.icon(
            onPressed: widget.enabled
                ? () => widget
                    .onChanged(double.tryParse(_controller.text.trim()) ?? 0)
                : null,
            icon: const Icon(Icons.save_outlined),
            label: Text(tr.text('save')),
          );
          if (constraints.maxWidth < 760) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  info,
                  const SizedBox(height: 10),
                  field,
                  const SizedBox(height: 8),
                  save
                ]);
          }
          return Row(children: [
            Expanded(child: info),
            const SizedBox(width: 20),
            SizedBox(width: 260, child: field),
            const SizedBox(width: 8),
            save
          ]);
        },
      ),
    );
  }
}

class _AccountingSettingRow extends StatelessWidget {
  const _AccountingSettingRow(
      {required this.definition,
      required this.accounts,
      required this.selectedAccountId,
      required this.onChanged});

  final _AccountingSettingDefinition definition;
  final List<AccountingAccount> accounts;
  final String selectedAccountId;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final selectedExists =
        accounts.any((account) => account.id == selectedAccountId);
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
                    Text(tr.text(definition.titleKey),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(tr.text(definition.subtitleKey),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
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
        for (final account in accounts)
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
                  accountId == value) return;
              onChanged!(accountId);
            },
    );
  }
}

class _StatementCard extends StatelessWidget {
  const _StatementCard(
      {required this.store, required this.title, required this.rows});

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

String _money(AppStore store, double amount) =>
    formatUsdReferenceAmount(amount, store.storeProfile);

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
    double customerReceivables = 0;
    double customerCredits = 0;
    for (final customer in customers) {
      final balance = store.accountBalance('customer', customer.id);
      if (balance > 0) {
        customerReceivables += balance;
      } else if (balance < 0) {
        customerCredits += balance.abs();
      }
    }
    double supplierPayables = 0;
    double supplierAdvances = 0;
    for (final supplier in suppliers) {
      final balance = store.accountBalance('supplier', supplier.id);
      if (balance < 0) {
        supplierPayables += balance.abs();
      } else if (balance > 0) {
        supplierAdvances += balance;
      }
    }
    final today = DateTime.now();
    double todayCashIn = 0;
    double todayCashOut = 0;
    for (final txn in accountTransactions) {
      if (!_sameDay(txn.date, today)) continue;
      if (_isCashIn(txn)) {
        todayCashIn += _cashAmount(txn);
      }
      if (_isCashOut(txn)) {
        todayCashOut += _cashAmount(txn);
      }
    }
    return _AccountingMetrics(
      customerReceivables: customerReceivables,
      customerCredits: customerCredits,
      supplierPayables: supplierPayables,
      supplierAdvances: supplierAdvances,
      todayCashIn: todayCashIn,
      todayCashOut: todayCashOut,
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  static bool _isCashIn(AccountTransaction txn) =>
      txn.type == 'paymentReceived' ||
      (txn.type == 'paymentReversal' && txn.accountType == 'supplier');
  static bool _isCashOut(AccountTransaction txn) =>
      txn.type == 'paymentPaid' ||
      (txn.type == 'paymentReversal' && txn.accountType == 'customer');
  static double _cashAmount(AccountTransaction txn) =>
      txn.debit > 0 ? txn.debit : txn.credit;
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
