import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/accounting/accounting_account_role.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/revision_cache.dart';
import '../../core/services/accounting_service.dart';
import '../../core/services/accounting_aging_service.dart';
import '../../core/services/cash_ledger_service.dart';
import '../../core/services/local_database_service.dart';
import '../../data/app_store.dart';
import 'accounting_snapshot_service.dart';
import '../../models/account_transaction.dart';
import '../../models/cash_ledger_transaction.dart';
import '../../models/accounting_account.dart';
import '../../models/journal_entry.dart';
import '../../models/tax_profile.dart';
import '../../models/aging_report.dart';
import '../../models/user_role.dart';
import '../accounts/account_ledger_widgets.dart';

const ScrollCacheExtent _kAccountingListCacheExtent =
    ScrollCacheExtent.pixels(2000);
const int _kCashFlowDetailRowLimit = 200;

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
  static const AccountingSnapshotService _snapshotService =
      AccountingSnapshotService();

  void _handleStoreChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleTopTabChanged() {
    if (!mounted || _tabController.indexIsChanging) return;
    if (_tabController.index >= 3 && _searchController.text.isNotEmpty) {
      _searchController.clear();
      return;
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_handleTopTabChanged);
    widget.store.addListener(_handleStoreChanged);
    _searchController.addListener(() =>
        setState(() => _query = _searchController.text.trim().toLowerCase()));
  }

  @override
  void didUpdateWidget(covariant AccountingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_handleStoreChanged);
      widget.store.addListener(_handleStoreChanged);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStoreChanged);
    _tabController.removeListener(_handleTopTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.canViewAccounting) {
      return _AccessDeniedScaffold(
        title: tr.text('accounting'),
        message: tr.text('no_access_accounting_data'),
      );
    }
    if (!widget.store.isCoreDataLoaded || !widget.store.isLedgerDataLoaded) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    return Padding(
      padding: VentioResponsive.pageInsets(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AccountingHeader(
            title: tr.text('accounting'),
            subtitle: _topSectionSubtitle(context, _tabController.index),
            onRefresh: () => setState(() {}),
          ),
          const SizedBox(height: 12),
          _AccountingSummaryStripLoader(store: widget.store),
          const SizedBox(height: 12),
          _AccountingTabs(controller: _tabController),
          const SizedBox(height: 10),
          if (_tabController.index <= 2) ...[
            _AccountingSearchField(
                controller: _searchController, query: _query),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _LazyTabPane(
                  controller: _tabController,
                  index: 0,
                  builder: (_) => _AccountsAccountingGroup(
                      store: widget.store, query: _query),
                ),
                _LazyTabPane(
                  controller: _tabController,
                  index: 1,
                  builder: (_) => _OperationsAccountingGroup(
                      store: widget.store, query: _query),
                ),
                _LazyTabPane(
                  controller: _tabController,
                  index: 2,
                  builder: (_) =>
                      _CashAccountingGroup(store: widget.store, query: _query),
                ),
                _LazyTabPane(
                  controller: _tabController,
                  index: 3,
                  builder: (_) => _ReportsAccountingGroup(
                      store: widget.store, query: _query),
                ),
                _LazyTabPane(
                  controller: _tabController,
                  index: 4,
                  builder: (_) => _SettingsAccountingGroup(store: widget.store),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessDeniedScaffold extends StatelessWidget {
  const _AccessDeniedScaffold({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 42),
                  const SizedBox(height: 12),
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountingHeader extends StatelessWidget {
  const _AccountingHeader({
    required this.title,
    required this.subtitle,
    required this.onRefresh,
  });

  final String title;
  final String subtitle;
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
                subtitle,
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
  int _lastSeenRevision = -1;

  @override
  void initState() {
    super.initState();
    _future = widget.loadFuture();
    _lastSeenRevision = widget.store.accounting.revision;
    widget.store.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _CachedFuturePanel<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_refresh);
      widget.store.addListener(_refresh);
      _lastSeenRevision = widget.store.accounting.revision;
    }
    if (oldWidget.cacheKey != widget.cacheKey) {
      _refresh(force: true);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_refresh);
    super.dispose();
  }

  void _refresh({bool force = false}) {
    if (!mounted) return;
    final revision = widget.store.accounting.revision;
    if (!force && revision == _lastSeenRevision) return;
    _lastSeenRevision = revision;
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

class _AccountingSummaryStripLoader extends StatefulWidget {
  const _AccountingSummaryStripLoader({required this.store});

  final AppStore store;

  @override
  State<_AccountingSummaryStripLoader> createState() =>
      _AccountingSummaryStripLoaderState();
}

class _AccountingSummaryStripLoaderState
    extends State<_AccountingSummaryStripLoader> {
  Future<Map<String, Object?>>? _future;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
  }

  @override
  void didUpdateWidget(covariant _AccountingSummaryStripLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _future = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _load();
      });
    }
  }

  void _load() {
    if (!mounted) return;
    final now = DateTime.now().toLocal();
    setState(() {
      _future = _AccountingPageState._snapshotService.metricsFor(
        widget.store,
        now: now,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toLocal();
    final cached = _AccountingPageState._snapshotService
        .peekMetrics(widget.store, now: now);
    if (cached != null) {
      return _CompactSummaryStrip(
        store: widget.store,
        metrics: _AccountingMetrics.fromSummary(cached),
      );
    }

    final future = _future;
    if (future == null) {
      return const _SummaryStripPlaceholder();
    }

    return FutureBuilder<Map<String, Object?>>(
      future: future,
      builder: (context, snapshot) {
        final summary = snapshot.data;
        if (summary != null) {
          return _CompactSummaryStrip(
            store: widget.store,
            metrics: _AccountingMetrics.fromSummary(summary),
          );
        }
        if (snapshot.hasError) {
          return const _SummaryStripPlaceholder();
        }
        return const _SummaryStripPlaceholder();
      },
    );
  }
}

class _SummaryStripPlaceholder extends StatelessWidget {
  const _SummaryStripPlaceholder();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: Center(
        child: CircularProgressIndicator.adaptive(
          strokeWidth: 2.4,
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
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
          icon: Icons.account_balance_wallet_outlined,
          title: _accountingUiText(context, 'رصيد النقد والخزن',
              'Cash & vault balance', 'Solde caisse et coffres'),
          amount: metrics.cashBalance),
      _SummaryMetric(
          icon: Icons.account_balance_outlined,
          title: tr.text('bank'),
          amount: metrics.bankBalance),
      _SummaryMetric(
          icon: Icons.point_of_sale_outlined,
          title: _accountingUiText(context, 'صافي مبيعات الشهر',
              'Month net sales', 'Ventes nettes du mois'),
          amount: metrics.monthNetSales),
      _SummaryMetric(
          icon: Icons.trending_up_outlined,
          title: _accountingUiText(context, 'مجمل ربح الشهر',
              'Month gross profit', 'Marge brute du mois'),
          amount: metrics.monthGrossProfit),
      _SummaryMetric(
          icon: Icons.receipt_long_outlined,
          title: _accountingUiText(context, 'مصاريف الشهر',
              'Month expenses', 'Charges du mois'),
          amount: metrics.monthExpenses),
      _SummaryMetric(
          icon: Icons.insights_outlined,
          title: _accountingUiText(context, 'صافي ربح الشهر',
              'Month net profit', 'Résultat net du mois'),
          amount: metrics.monthNetProfit),
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
            ? (constraints.maxWidth - 56) / 8
            : constraints.maxWidth >= 950
                ? (constraints.maxWidth - 40) / 6
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
              text: _accountingUiText(context, 'الحسابات المساعدة',
                  'Subledgers', 'Comptes auxiliaires'),
            ),
            Tab(
              icon: const Icon(Icons.menu_book_outlined),
              text: _accountingUiText(context, 'العمليات المحاسبية',
                  'Accounting operations', 'Opérations comptables'),
            ),
            Tab(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              text: _accountingUiText(context, 'النقد والبنوك',
                  'Cash & banks', 'Trésorerie et banques'),
            ),
            Tab(
              icon: const Icon(Icons.assessment_outlined),
              text: _accountingUiText(context, 'التقارير المالية',
                  'Financial reports', 'Rapports financiers'),
            ),
            Tab(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              text: _accountingUiText(
                  context, 'الإدارة', 'Administration', 'Administration'),
            ),
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
      length: 4,
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
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Builder(
              builder: (context) {
                final controller = DefaultTabController.of(context);
                return TabBarView(
                  children: [
                    _LazyTabPane(
                      controller: controller,
                      index: 0,
                      builder: (_) => _AccountsTab(
                        store: store,
                        query: query,
                        accountType: 'customer',
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 1,
                      builder: (_) => _AccountsTab(
                        store: store,
                        query: query,
                        accountType: 'supplier',
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 2,
                      builder: (_) =>
                          _AgingReportsTab(store: store, query: query),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 3,
                      builder: (_) => _TransactionsTab(
                        store: store,
                        query: query,
                        cashOnly: false,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OperationsAccountingGroup extends StatelessWidget {
  const _OperationsAccountingGroup({required this.store, required this.query});

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
                icon: const Icon(Icons.receipt_long_outlined),
                text: _accountingUiText(
                    context, 'القيود اليومية', 'Journal entries', 'Écritures'),
              ),
              Tab(
                  icon: const Icon(Icons.menu_book_outlined),
                  text: tr.text('general_ledger')),
              Tab(
                  icon: const Icon(Icons.account_tree_outlined),
                  text: tr.text('chart_of_accounts')),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Builder(
              builder: (context) {
                final controller = DefaultTabController.of(context);
                return TabBarView(
                  children: [
                    _LazyTabPane(
                      controller: controller,
                      index: 0,
                      builder: (_) =>
                          _JournalEntriesTab(store: store, query: query),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 1,
                      builder: (_) =>
                          _GeneralLedgerTab(store: store, query: query),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 2,
                      builder: (_) => _ChartOfAccountsTab(store: store, query: query),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartOfAccountsTab extends StatefulWidget {
  const _ChartOfAccountsTab({required this.store, required this.query});

  final AppStore store;
  final String query;

  @override
  State<_ChartOfAccountsTab> createState() => _ChartOfAccountsTabState();
}

class _ChartOfAccountsTabState extends State<_ChartOfAccountsTab> {
  late Future<List<AccountingAccount>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = AccountingService.listAccounts(activeOnly: false);
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  List<({AccountingAccount account, int depth})> _flatten(
      List<AccountingAccount> accounts) {
    final byParent = <String, List<AccountingAccount>>{};
    for (final account in accounts) {
      byParent
          .putIfAbsent(account.parentId, () => <AccountingAccount>[])
          .add(account);
    }
    for (final children in byParent.values) {
      children.sort((a, b) => a.code.compareTo(b.code));
    }
    final result = <({AccountingAccount account, int depth})>[];
    final visited = <String>{};
    void addBranch(AccountingAccount account, int depth) {
      if (!visited.add(account.id)) return;
      result.add((account: account, depth: depth));
      for (final child in byParent[account.id] ?? const <AccountingAccount>[]) {
        addBranch(child, depth + 1);
      }
    }

    final roots = <AccountingAccount>[
      ...?byParent[''],
      ...accounts.where((a) =>
          a.parentId.isNotEmpty &&
          !accounts.any((candidate) => candidate.id == a.parentId)),
    ]..sort((a, b) => a.code.compareTo(b.code));
    for (final root in roots) {
      addBranch(root, 0);
    }
    for (final orphan in accounts.where((a) => !visited.contains(a.id)).toList()
      ..sort((a, b) => a.code.compareTo(b.code))) {
      addBranch(orphan, 0);
    }
    return result;
  }

  Future<void> _createAccountDialog(List<AccountingAccount> accounts) async {
    widget.store.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    var parentId = '';
    var type = 'asset';
    var normalBalance = 'debit';
    var isPostable = true;
    final activeAccounts = accounts.where((a) => a.isActive).toList()
      ..sort((a, b) => a.code.compareTo(b.code));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.text('new_accounting_account')),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeController,
                    decoration: InputDecoration(
                      labelText: tr.text('account_code'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: tr.text('account_name'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: parentId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr.text('parent_account'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(tr.text('no_parent')),
                      ),
                      for (final account in activeAccounts)
                        DropdownMenuItem(
                          value: account.id,
                          child: Text('${account.code} • ${account.name}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (value) {
                      final selected = activeAccounts
                          .where((a) => a.id == value)
                          .firstOrNull;
                      setDialogState(() {
                        parentId = value ?? '';
                        if (selected != null) {
                          type = selected.type;
                          normalBalance = selected.normalBalance;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: InputDecoration(
                      labelText: tr.text('account_type'),
                      border: const OutlineInputBorder(),
                    ),
                    items: AccountingService.supportedAccountTypes
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(_accountTypeLabel(value, tr)),
                            ))
                        .toList(),
                    onChanged: (value) => setDialogState(() {
                      type = value ?? type;
                      normalBalance = _defaultNormalBalance(type);
                    }),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: normalBalance,
                    decoration: InputDecoration(
                      labelText: tr.text('normal_balance'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: 'debit', child: Text(tr.text('debit'))),
                      DropdownMenuItem(
                          value: 'credit', child: Text(tr.text('credit'))),
                    ],
                    onChanged: (value) => setDialogState(
                        () => normalBalance = value ?? normalBalance),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: isPostable,
                    title: Text(tr.text('allow_direct_posting')),
                    subtitle: Text(tr.text('allow_direct_posting_desc')),
                    onChanged: (value) =>
                        setDialogState(() => isPostable = value),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: descriptionController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: tr.text('description'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr.text('create')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await AccountingService.createAccount(
        code: codeController.text,
        name: nameController.text,
        type: type,
        normalBalance: normalBalance,
        parentId: parentId,
        description: descriptionController.text,
        isPostable: isPostable,
        storeId: widget.store.appIdentity.storeId,
      );
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr.text('account_created')),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString()),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  Future<void> _toggleAccount(AccountingAccount account) async {
    widget.store.requirePermission(AppPermission.accountingManage);
    try {
      await AccountingService.setAccountActive(
          accountId: account.id, active: !account.isActive);
      if (mounted) setState(_reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _deleteAccount(AccountingAccount account) async {
    widget.store.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('delete_account_confirm')),
        content: Text('${account.code} • ${account.name}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('delete'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AccountingService.deleteAccount(account.id);
      if (mounted) setState(_reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _accountTypeLabel(String type, AppLocalizations tr) {
    final key = <String, String>{
      'asset': 'account_type_asset',
      'liability': 'account_type_liability',
      'equity': 'account_type_equity',
      'revenue': 'account_type_revenue',
      'expense': 'account_type_expense',
      'cost_of_sales': 'account_type_cost_of_sales',
    }[type];
    return key == null ? type : tr.text(key);
  }

  String _defaultNormalBalance(String type) =>
      type == 'asset' || type == 'expense' || type == 'cost_of_sales'
          ? 'debit'
          : 'credit';

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final canManage =
        widget.store.hasPermission(AppPermission.accountingManage);
    return FutureBuilder<List<AccountingAccount>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        final accounts = snapshot.data ?? const <AccountingAccount>[];
        final normalizedQuery = _normalizedSearchQuery(widget.query);
        final rows = _flatten(accounts).where((row) {
          if (normalizedQuery.isEmpty) return true;
          final account = row.account;
          return _matchesNormalized(normalizedQuery, [
            account.code,
            account.name,
            account.type,
            account.subtype,
            account.description,
          ]);
        }).toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr.text('chart_of_accounts'),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        Text(tr.format('accounts_system_protected',
                            <String, Object?>{'count': accounts.length})),
                      ],
                    ),
                    FilledButton.icon(
                      onPressed: canManage
                          ? () => _createAccountDialog(accounts)
                          : null,
                      icon: const Icon(Icons.add),
                      label: Text(tr.text('new_account')),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.builder(
                  scrollCacheExtent: _kAccountingListCacheExtent,
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final account = row.account;
                    return Padding(
                      padding:
                          EdgeInsetsDirectional.only(start: row.depth * 22.0),
                      child: Card(
                        elevation: 0,
                        child: ListTile(
                          leading: Icon(account.isPostable
                              ? Icons.account_balance_wallet_outlined
                              : Icons.account_tree_outlined),
                          title: Text('${account.code} • ${account.name}',
                              style: TextStyle(
                                  fontWeight: account.isPostable
                                      ? FontWeight.w600
                                      : FontWeight.w800,
                                  decoration: account.isActive
                                      ? null
                                      : TextDecoration.lineThrough)),
                          subtitle: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Text(_accountTypeLabel(account.type, tr)),
                              Text(account.normalBalance == 'debit'
                                  ? '• ${tr.text('debit')}'
                                  : '• ${tr.text('credit')}'),
                              if (!account.isPostable)
                                Text('• ${tr.text('group')}'),
                              if (account.isSystem)
                                Text('• ${tr.text('system')}'),
                              if (!account.isActive)
                                Text('• ${tr.text('inactive')}'),
                            ],
                          ),
                          trailing: account.isSystem || !canManage
                              ? (account.isSystem
                                  ? const Icon(Icons.lock_outline, size: 20)
                                  : null)
                              : PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'toggle') {
                                      _toggleAccount(account);
                                    } else if (value == 'delete') {
                                      _deleteAccount(account);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'toggle',
                                      child: Text(account.isActive
                                          ? tr.text('deactivate')
                                          : tr.text('activate')),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(tr.text('delete')),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
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
                  text: _accountingUiText(context, 'رقابة النقد',
                      'Cash control', 'Contrôle de caisse')),
              Tab(
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  text: tr.text('cash_bank')),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Builder(
              builder: (context) {
                final controller = DefaultTabController.of(context);
                return TabBarView(
                  children: [
                    _LazyTabPane(
                      controller: controller,
                      index: 0,
                      builder: (_) => _CashLedgerTransactionsTab(
                        store: store,
                        query: query,
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 1,
                      builder: (_) => _AdvancedAccountingTab(
                        store: store,
                        cashOnly: true,
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 2,
                      builder: (_) => _CashBankReportTab(store: store),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

enum _AccountingReportRangeMode {
  today,
  week,
  month,
  year,
  accountingPeriod,
  custom,
}

class _AccountingReportRange {
  const _AccountingReportRange({
    required this.from,
    required this.to,
    required this.label,
  });

  final DateTime from;
  final DateTime to;
  final String label;

  String get cacheKey => '${from.toIso8601String()}|${to.toIso8601String()}';
}

class _ReportsAccountingGroup extends StatefulWidget {
  const _ReportsAccountingGroup({required this.store, required this.query});

  final AppStore store;
  final String query;

  @override
  State<_ReportsAccountingGroup> createState() =>
      _ReportsAccountingGroupState();
}

class _ReportsAccountingGroupState extends State<_ReportsAccountingGroup> {
  _AccountingReportRangeMode _mode = _AccountingReportRangeMode.month;
  DateTime? _customFrom;
  DateTime? _customTo;
  List<AdvancedAccountingItem> _accountingPeriods =
      const <AdvancedAccountingItem>[];
  String _selectedAccountingPeriodId = '';

  @override
  void initState() {
    super.initState();
    _loadAccountingPeriods();
  }

  Future<void> _loadAccountingPeriods() async {
    try {
      final periods = (await AccountingService.listAccountingPeriods())
          .where((period) =>
              DateTime.tryParse(period.accountCode) != null &&
              DateTime.tryParse(period.accountName) != null)
          .toList(growable: false);
      final now = DateTime.now().toLocal();
      AdvancedAccountingItem? current;
      for (final period in periods) {
        final start = DateTime.parse(period.accountCode).toLocal();
        final end = DateTime.parse(period.accountName).toLocal();
        final containsNow = !now.isBefore(_startOfDay(start)) &&
            !now.isAfter(_endOfDay(end));
        final isOpen = period.type.trim().toLowerCase() == 'open';
        if (containsNow && isOpen) {
          current = period;
          break;
        }
        if (current == null && containsNow) current = period;
      }
      if (!mounted) return;
      setState(() {
        _accountingPeriods = periods;
        final selected = current ?? (periods.isEmpty ? null : periods.first);
        _selectedAccountingPeriodId = selected?.id ?? '';
        if (current != null && _mode == _AccountingReportRangeMode.month) {
          _mode = _AccountingReportRangeMode.accountingPeriod;
        }
      });
    } catch (_) {
      // Date presets remain usable even if accounting-period metadata is unavailable.
    }
  }

  AdvancedAccountingItem? get _selectedAccountingPeriod {
    for (final period in _accountingPeriods) {
      if (period.id == _selectedAccountingPeriodId) return period;
    }
    return _accountingPeriods.isEmpty ? null : _accountingPeriods.first;
  }

  DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime _endOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day, 23, 59, 59, 999, 999);

  _AccountingReportRange _effectiveRange(BuildContext context) {
    final now = DateTime.now().toLocal();
    switch (_mode) {
      case _AccountingReportRangeMode.today:
        return _AccountingReportRange(
          from: _startOfDay(now),
          to: _endOfDay(now),
          label: _accountingUiText(context, 'اليوم', 'Today', 'Aujourd’hui'),
        );
      case _AccountingReportRangeMode.week:
        final today = _startOfDay(now);
        final start = today.subtract(Duration(days: today.weekday - 1));
        final end = start.add(const Duration(days: 6));
        return _AccountingReportRange(
          from: start,
          to: _endOfDay(end),
          label: _accountingUiText(
              context, 'هذا الأسبوع', 'This week', 'Cette semaine'),
        );
      case _AccountingReportRangeMode.month:
        final from = DateTime(now.year, now.month, 1);
        final nextMonth = now.month == 12
            ? DateTime(now.year + 1, 1, 1)
            : DateTime(now.year, now.month + 1, 1);
        return _AccountingReportRange(
          from: from,
          to: nextMonth.subtract(const Duration(microseconds: 1)),
          label: _accountingUiText(
              context, 'هذا الشهر', 'This month', 'Ce mois'),
        );
      case _AccountingReportRangeMode.year:
        return _AccountingReportRange(
          from: DateTime(now.year, 1, 1),
          to: DateTime(now.year, 12, 31, 23, 59, 59, 999, 999),
          label: _accountingUiText(
              context, 'هذه السنة', 'This year', 'Cette année'),
        );
      case _AccountingReportRangeMode.accountingPeriod:
        final period = _selectedAccountingPeriod;
        final start = DateTime.tryParse(period?.accountCode ?? '')?.toLocal();
        final end = DateTime.tryParse(period?.accountName ?? '')?.toLocal();
        if (period != null && start != null && end != null) {
          return _AccountingReportRange(
            from: _startOfDay(start),
            to: _endOfDay(end),
            label: period.name.trim().isEmpty
                ? _accountingUiText(context, 'فترة محاسبية',
                    'Accounting period', 'Période comptable')
                : period.name,
          );
        }
        final monthStart = DateTime(now.year, now.month, 1);
        return _AccountingReportRange(
          from: monthStart,
          to: _endOfDay(now),
          label: _accountingUiText(context, 'هذا الشهر', 'This month', 'Ce mois'),
        );
      case _AccountingReportRangeMode.custom:
        final from = _customFrom ?? DateTime(now.year, now.month, 1);
        final to = _customTo ?? now;
        return _AccountingReportRange(
          from: _startOfDay(from),
          to: _endOfDay(to),
          label: _accountingUiText(
              context, 'فترة مخصصة', 'Custom range', 'Période personnalisée'),
        );
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now().toLocal();
    final initialStart = _customFrom ?? DateTime(now.year, now.month, 1);
    final initialEnd = _customTo ?? now;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customFrom = picked.start;
      _customTo = picked.end;
      _mode = _AccountingReportRangeMode.custom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final range = _effectiveRange(context);
    return DefaultTabController(
      length: 6,
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
              Tab(
                  icon: const Icon(Icons.inventory_2_outlined),
                  text: tr.text('inventory')),
            ],
          ),
          const SizedBox(height: 8),
          _AccountingReportRangeBar(
            mode: _mode,
            range: range,
            accountingPeriods: _accountingPeriods,
            selectedAccountingPeriodId: _selectedAccountingPeriodId,
            onModeChanged: (mode) {
              if (mode == _AccountingReportRangeMode.custom) {
                _pickCustomRange();
                return;
              }
              setState(() => _mode = mode);
            },
            onAccountingPeriodChanged: (periodId) {
              setState(() {
                _selectedAccountingPeriodId = periodId;
                _mode = _AccountingReportRangeMode.accountingPeriod;
              });
            },
            onPickCustom: _pickCustomRange,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Builder(
              builder: (context) {
                final controller = DefaultTabController.of(context);
                final rangeToken = range.cacheKey;
                return TabBarView(
                  children: [
                    _LazyTabPane(
                      controller: controller,
                      index: 0,
                      cacheToken: 'trial|$rangeToken',
                      builder: (_) => _TrialBalanceTab(
                        store: widget.store,
                        query: widget.query,
                        from: range.from,
                        to: range.to,
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 1,
                      cacheToken: 'income|$rangeToken',
                      builder: (_) => _IncomeStatementTab(
                        store: widget.store,
                        from: range.from,
                        to: range.to,
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 2,
                      cacheToken: 'balance|$rangeToken',
                      builder: (_) => _BalanceSheetTab(
                        store: widget.store,
                        asOf: range.to,
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 3,
                      cacheToken: 'cashflow|$rangeToken',
                      builder: (_) => _CashFlowStatementTab(
                        store: widget.store,
                        from: range.from,
                        to: range.to,
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 4,
                      cacheToken: 'tax|$rangeToken',
                      builder: (_) => _TaxReportTab(
                        store: widget.store,
                        from: range.from,
                        to: range.to,
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 5,
                      builder: (_) =>
                          _InventoryManufacturingReportsTab(store: widget.store),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountingReportRangeBar extends StatelessWidget {
  const _AccountingReportRangeBar({
    required this.mode,
    required this.range,
    required this.accountingPeriods,
    required this.selectedAccountingPeriodId,
    required this.onModeChanged,
    required this.onAccountingPeriodChanged,
    required this.onPickCustom,
  });

  final _AccountingReportRangeMode mode;
  final _AccountingReportRange range;
  final List<AdvancedAccountingItem> accountingPeriods;
  final String selectedAccountingPeriodId;
  final ValueChanged<_AccountingReportRangeMode> onModeChanged;
  final ValueChanged<String> onAccountingPeriodChanged;
  final VoidCallback onPickCustom;

  @override
  Widget build(BuildContext context) {
    final hasAccountingPeriods = accountingPeriods.isNotEmpty;
    final effectiveMode =
        mode == _AccountingReportRangeMode.accountingPeriod &&
                !hasAccountingPeriods
            ? _AccountingReportRangeMode.month
            : mode;
    final dateRangeText =
        '${_dateText(range.from)} → ${_dateText(range.to)}';
    final selectedPeriodExists = accountingPeriods
        .any((period) => period.id == selectedAccountingPeriodId);
    final selectedPeriodValue = selectedPeriodExists
        ? selectedAccountingPeriodId
        : (accountingPeriods.isEmpty ? null : accountingPeriods.first.id);

    final modeSelector = DropdownButton<_AccountingReportRangeMode>(
      value: effectiveMode,
      underline: const SizedBox.shrink(),
      items: [
        DropdownMenuItem(
          value: _AccountingReportRangeMode.today,
          child: Text(
              _accountingUiText(context, 'اليوم', 'Today', 'Aujourd’hui')),
        ),
        DropdownMenuItem(
          value: _AccountingReportRangeMode.week,
          child: Text(_accountingUiText(
              context, 'هذا الأسبوع', 'This week', 'Cette semaine')),
        ),
        DropdownMenuItem(
          value: _AccountingReportRangeMode.month,
          child: Text(
              _accountingUiText(context, 'هذا الشهر', 'This month', 'Ce mois')),
        ),
        DropdownMenuItem(
          value: _AccountingReportRangeMode.year,
          child: Text(_accountingUiText(
              context, 'هذه السنة', 'This year', 'Cette année')),
        ),
        if (hasAccountingPeriods)
          DropdownMenuItem(
            value: _AccountingReportRangeMode.accountingPeriod,
            child: Text(_accountingUiText(context, 'فترة محاسبية',
                'Accounting period', 'Période comptable')),
          ),
        DropdownMenuItem(
          value: _AccountingReportRangeMode.custom,
          child: Text(_accountingUiText(context, 'فترة مخصصة', 'Custom range',
              'Période personnalisée')),
        ),
      ],
      onChanged: (value) {
        if (value != null) onModeChanged(value);
      },
    );

    final periodSelector = effectiveMode ==
                _AccountingReportRangeMode.accountingPeriod &&
            selectedPeriodValue != null
        ? DropdownButton<String>(
            value: selectedPeriodValue,
            underline: const SizedBox.shrink(),
            items: [
              for (final period in accountingPeriods)
                DropdownMenuItem(
                  value: period.id,
                  child: Text(
                    _accountingPeriodLabel(context, period),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) onAccountingPeriodChanged(value);
            },
          )
        : null;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final details = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.date_range_outlined, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${range.label} • $dateRangeText',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (effectiveMode == _AccountingReportRangeMode.custom) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: _accountingUiText(context, 'تغيير الفترة',
                        'Change range', 'Modifier la période'),
                    onPressed: onPickCustom,
                    icon: const Icon(Icons.edit_calendar_outlined, size: 20),
                  ),
                ],
              ],
            );
            if (constraints.maxWidth < 820) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  modeSelector,
                  if (periodSelector != null) ...[
                    const SizedBox(height: 4),
                    periodSelector,
                  ],
                  const SizedBox(height: 6),
                  details,
                ],
              );
            }
            return Row(
              children: [
                Text(
                  _accountingUiText(
                      context, 'فترة التقرير:', 'Report period:', 'Période :'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                modeSelector,
                if (periodSelector != null) ...[
                  const SizedBox(width: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: periodSelector,
                  ),
                ],
                const SizedBox(width: 18),
                Expanded(child: details),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _accountingPeriodLabel(
    BuildContext context, AdvancedAccountingItem period) {
  final name = period.name.trim();
  if (name.isNotEmpty) return name;
  final start = DateTime.tryParse(period.accountCode)?.toLocal();
  final end = DateTime.tryParse(period.accountName)?.toLocal();
  if (start != null && end != null) {
    return '${_dateText(start)} → ${_dateText(end)}';
  }
  return _accountingUiText(
      context, 'فترة محاسبية', 'Accounting period', 'Période comptable');
}

String _accountingUiText(
    BuildContext context, String ar, String en, String fr) {
  final language = Localizations.localeOf(context).languageCode;
  if (language == 'ar') return ar;
  if (language == 'fr') return fr;
  return en;
}

String _topSectionSubtitle(BuildContext context, int index) {
  switch (index) {
    case 0:
      return _accountingUiText(context, 'العملاء والموردون وأعمار الديون',
          'Customers, suppliers and aging', 'Clients, fournisseurs et échéances');
    case 1:
      return _accountingUiText(context, 'القيود اليومية ودفتر الأستاذ ودليل الحسابات',
          'Journal, general ledger and chart of accounts',
          'Journal, grand livre et plan comptable');
    case 2:
      return _accountingUiText(context, 'حركة النقد والبنوك والرقابة النقدية',
          'Cash, banks and treasury monitoring',
          'Trésorerie, banques et suivi');
    case 3:
      return _accountingUiText(context, 'التقارير المالية الرسمية حسب الفترة',
          'Period-based financial statements', 'Rapports financiers par période');
    case 4:
      return _accountingUiText(context, 'إدارة الفترات والربط والإعدادات المحاسبية',
          'Periods, mappings and accounting administration',
          'Périodes, rattachements et administration');
    default:
      return _accountingUiText(context, 'المحاسبة', 'Accounting', 'Comptabilité');
  }
}

class _SettingsAccountingGroup extends StatelessWidget {
  const _SettingsAccountingGroup({required this.store});

  final AppStore store;

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
                  icon: const Icon(Icons.auto_awesome_motion_outlined),
                  text: _accountingUiText(
                    context,
                    'الإدارة المحاسبية',
                    'Accounting administration',
                    'Administration comptable',
                  )),
              const Tab(
                  icon: Icon(Icons.account_tree_outlined),
                  text: 'ربط الحسابات'),
              Tab(
                  icon: const Icon(Icons.settings_outlined),
                  text: tr.text('settings')),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Builder(
              builder: (context) {
                final controller = DefaultTabController.of(context);
                return TabBarView(
                  children: [
                    _LazyTabPane(
                      controller: controller,
                      index: 0,
                      builder: (_) => _AdvancedAccountingTab(store: store),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 1,
                      builder: (_) => _AccountingRolesTab(store: store),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 2,
                      builder: (_) => _AccountingSettingsTab(store: store),
                    ),
                  ],
                );
              },
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

class _LazyTabPane extends StatefulWidget {
  const _LazyTabPane({
    required this.controller,
    required this.index,
    required this.builder,
    this.cacheToken,
  });

  final TabController controller;
  final int index;
  final WidgetBuilder builder;
  final Object? cacheToken;

  @override
  State<_LazyTabPane> createState() => _LazyTabPaneState();
}

class _LazyTabPaneState extends State<_LazyTabPane> {
  Widget? _builtChild;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleTabChanged);
  }

  @override
  void didUpdateWidget(covariant _LazyTabPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTabChanged);
      widget.controller.addListener(_handleTabChanged);
    }
    if (oldWidget.cacheToken != widget.cacheToken) {
      _builtChild = null;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTabChanged);
    super.dispose();
  }

  void _handleTabChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.controller.index == widget.index;
    if (active && _builtChild == null) {
      _builtChild = widget.builder(context);
    }
    return _builtChild ?? const SizedBox.expand();
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

  Future<List<_AccountRowData>?> _rowsFromSqlite(String normalizedQuery) async {
    final rows =
        await LocalDatabaseService.queryAccountingAccountRowsFromSqlite(
      accountType: accountType,
      query: normalizedQuery,
      limit: 500,
    );
    return rows
        ?.map((row) => _AccountRowData(
              id: row['id']?.toString() ?? '',
              name: row['name']?.toString() ?? '',
              subtitle: row['subtitle']?.toString() ?? '',
              balance: _doubleValue(row['balance']),
            ))
        .where((row) => row.id.trim().isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _normalizedSearchQuery(query);
    if (LocalDatabaseService.canQueryBusinessSqlite) {
      return FutureBuilder<List<_AccountRowData>?>(
        future: _rowsFromSqlite(normalizedQuery),
        builder: (context, snapshot) {
          final rows = snapshot.data;
          if (rows != null && !snapshot.hasError) {
            return _AccountsRowsView(
              store: store,
              accountType: accountType,
              rows: rows,
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          return _AccountsTabMemory(
            store: store,
            query: query,
            accountType: accountType,
          );
        },
      );
    }
    return _AccountsTabMemory(
      store: store,
      query: query,
      accountType: accountType,
    );
  }
}

// ignore: unused_element
class _AccountsTabMemory extends StatelessWidget {
  const _AccountsTabMemory(
      {required this.store, required this.query, required this.accountType});

  final AppStore store;
  final String query;
  final String accountType;
  static final RevisionKeyCache<List<_AccountRowData>> _rowsCache =
      RevisionKeyCache<List<_AccountRowData>>();
  static final RevisionKeyCache<Map<String, String>> _searchIndexCache =
      RevisionKeyCache<Map<String, String>>();

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final normalizedQuery = _normalizedSearchQuery(query);
    final dataRevision = accountType == 'customer'
        ? store.customersRevision
        : store.suppliersRevision;
    final rowsRevision = Object.hashAll(<Object?>[
      dataRevision,
      store.accounting.ledgerRevision,
    ]);
    final index = _searchIndexCache.getOrCompute(
      dataRevision,
      '${store.appIdentity.storeId}|$accountType',
      () {
        final map = <String, String>{};
        if (accountType == 'customer') {
          for (final customer in store.customers) {
            map[customer.id] = [
              customer.name,
              customer.phone,
              customer.address,
            ].join(' ').toLowerCase();
          }
        } else {
          for (final supplier in store.suppliers) {
            map[supplier.id] = [
              supplier.name,
              supplier.nameEn,
              supplier.nameAr,
              supplier.phone,
              supplier.address,
            ].join(' ').toLowerCase();
          }
        }
        return map;
      },
    );
    final rows = _rowsCache.getOrCompute(
      rowsRevision,
      '${store.appIdentity.storeId}|$accountType|$normalizedQuery',
      () {
        final computed = accountType == 'customer'
            ? store.customers
                .where((customer) =>
                    normalizedQuery.isEmpty ||
                    (index[customer.id]?.contains(normalizedQuery) ?? false))
                .map((customer) => _AccountRowData(
                      id: customer.id,
                      name: customer.name,
                      subtitle: [customer.phone, customer.address]
                          .where((part) => part.trim().isNotEmpty)
                          .join(' • '),
                      balance: store.accounting.accountBalance('customer', customer.id),
                    ))
                .toList()
            : store.suppliers
                .where((supplier) =>
                    normalizedQuery.isEmpty ||
                    (index[supplier.id]?.contains(normalizedQuery) ?? false))
                .map((supplier) => _AccountRowData(
                      id: supplier.id,
                      name: supplier.name,
                      subtitle: [supplier.phone, supplier.address]
                          .where((part) => part.trim().isNotEmpty)
                          .join(' • '),
                      balance: store.accounting.accountBalance('supplier', supplier.id),
                    ))
                .toList();
        computed.sort((a, b) => b.balance.abs().compareTo(a.balance.abs()));
        return computed;
      },
    );

    if (rows.isEmpty) {
      return _EmptyAccountingState(
          message: tr.text(accountType == 'customer'
              ? 'no_customers_found'
              : 'no_suppliers_found'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;
        final rowExtent = isWide ? 84.0 : 104.0;
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: isWide
              ? Column(
                  children: [
                    _AccountTableHeader(accountType: accountType),
                    Expanded(
                      child: ListView.builder(
                        scrollCacheExtent: _kAccountingListCacheExtent,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemExtent: rowExtent,
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return _AccountListRow(
                              store: store,
                              accountType: accountType,
                              row: row,
                              isWide: isWide);
                        },
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  scrollCacheExtent: _kAccountingListCacheExtent,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemExtent: rowExtent,
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
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

class _AccountsRowsView extends StatelessWidget {
  const _AccountsRowsView({
    required this.store,
    required this.accountType,
    required this.rows,
  });

  final AppStore store;
  final String accountType;
  final List<_AccountRowData> rows;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (rows.isEmpty) {
      return _EmptyAccountingState(
          message: tr.text(accountType == 'customer'
              ? 'no_customers_found'
              : 'no_suppliers_found'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;
        final rowExtent = isWide ? 84.0 : 104.0;
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: isWide
              ? Column(
                  children: [
                    _AccountTableHeader(accountType: accountType),
                    Expanded(
                      child: ListView.builder(
                        scrollCacheExtent: _kAccountingListCacheExtent,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemExtent: rowExtent,
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return _AccountListRow(
                              store: store,
                              accountType: accountType,
                              row: row,
                              isWide: isWide);
                        },
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  scrollCacheExtent: _kAccountingListCacheExtent,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemExtent: rowExtent,
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
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

class _AgingReportsTab extends StatefulWidget {
  const _AgingReportsTab({required this.store, required this.query});

  final AppStore store;
  final String query;

  @override
  State<_AgingReportsTab> createState() => _AgingReportsTabState();
}

class _AgingReportsTabState extends State<_AgingReportsTab> {
  Future<_AgingReportsData>? _future;
  int _futureRevision = -1;

  Future<_AgingReportsData> _reportsFromSqlite() async {
    final results = await Future.wait<AgingReportResult>([
      AccountingAgingService.customerAgingReport(),
      AccountingAgingService.supplierAgingReport(),
    ]);
    return _AgingReportsData(
      customerReport: results[0],
      supplierReport: results[1],
    );
  }

  Future<_AgingReportsData> _futureForRevision() {
    final revision = widget.store.accounting.revision;
    if (_future == null || _futureRevision != revision) {
      _futureRevision = revision;
      _future = _reportsFromSqlite();
    }
    return _future!;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AgingReportsData>(
      future: _futureForRevision(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        return _buildReports(
            context, snapshot.data ?? _AgingReportsData.empty());
      },
    );
  }

  Widget _buildReports(BuildContext context, _AgingReportsData reports) {
    final customerReport = reports.customerReport;
    final supplierReport = reports.supplierReport;

    return ListView(
      children: [
        _AgingReportSection(
          store: widget.store,
          title: AppLocalizations.of(context).text('customer_aging'),
          subtitle:
              AppLocalizations.of(context).text('customer_aging_subtitle'),
          icon: Icons.people_outline,
          report: customerReport,
          query: widget.query,
        ),
        const SizedBox(height: 12),
        _AgingReportSection(
          store: widget.store,
          title: AppLocalizations.of(context).text('supplier_aging'),
          subtitle:
              AppLocalizations.of(context).text('supplier_aging_subtitle'),
          icon: Icons.local_shipping_outlined,
          report: supplierReport,
          query: widget.query,
        ),
      ],
    );
  }
}

class _AgingReportsData {
  const _AgingReportsData({
    required this.customerReport,
    required this.supplierReport,
  });

  factory _AgingReportsData.empty() => _AgingReportsData(
        customerReport: AgingReportResult(
          asOfDate: DateTime.fromMillisecondsSinceEpoch(0),
          rows: const <AgingReportRow>[],
          openDocuments: const <AgingOpenDocument>[],
        ),
        supplierReport: AgingReportResult(
          asOfDate: DateTime.fromMillisecondsSinceEpoch(0),
          rows: const <AgingReportRow>[],
          openDocuments: const <AgingOpenDocument>[],
        ),
      );

  final AgingReportResult customerReport;
  final AgingReportResult supplierReport;
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


class _CashLedgerTransactionsTab extends StatefulWidget {
  const _CashLedgerTransactionsTab({required this.store, required this.query});

  final AppStore store;
  final String query;

  @override
  State<_CashLedgerTransactionsTab> createState() =>
      _CashLedgerTransactionsTabState();
}

class _CashLedgerTransactionsTabState
    extends State<_CashLedgerTransactionsTab> {
  late Future<List<CashLedgerTransaction>> _future;
  int _lastSeenRevision = -1;
  String _direction = '';
  String _type = '';
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _lastSeenRevision = widget.store.accounting.revision;
    widget.store.addListener(_handleStoreChanged);
    final now = DateTime.now().toLocal();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 1)
        .subtract(const Duration(microseconds: 1));
    _reload();
  }

  @override
  void didUpdateWidget(covariant _CashLedgerTransactionsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_handleStoreChanged);
      widget.store.addListener(_handleStoreChanged);
      _lastSeenRevision = widget.store.accounting.revision;
      _reload();
      return;
    }
    if (oldWidget.query != widget.query) {
      _reload();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStoreChanged);
    super.dispose();
  }

  void _handleStoreChanged() {
    if (!mounted) return;
    final revision = widget.store.accounting.revision;
    if (revision == _lastSeenRevision) return;
    _lastSeenRevision = revision;
    setState(_reload);
  }

  void _reload() {
    try {
      _future = CashLedgerService.current().list(
        search: widget.query.trim(),
        direction: _direction,
        type: _type,
        from: _from,
        to: _to,
        limit: 500,
      );
    } catch (error, stackTrace) {
      _future = Future<List<CashLedgerTransaction>>.error(error, stackTrace);
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now().toLocal();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
      initialDateRange: DateTimeRange(
        start: _from ?? DateTime(now.year, now.month, 1),
        end: _to ?? now,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _to = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
        23,
        59,
        59,
        999,
        999,
      );
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CashLedgerFilterBar(
          direction: _direction,
          type: _type,
          from: _from,
          to: _to,
          onDirectionChanged: (value) => setState(() {
            _direction = value;
            _reload();
          }),
          onTypeChanged: (value) => setState(() {
            _type = value;
            _reload();
          }),
          onPickRange: _pickRange,
          onClearRange: () => setState(() {
            _from = null;
            _to = null;
            _reload();
          }),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<List<CashLedgerTransaction>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator.adaptive());
              }
              if (snapshot.hasError) {
                return _ReportError(message: snapshot.error.toString());
              }
              final rows = snapshot.data ?? const <CashLedgerTransaction>[];
              if (rows.isEmpty) {
                return _EmptyAccountingState(
                  message: AppLocalizations.of(context).text('no_cash_movements'),
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
                  return Card(
                    elevation: 0,
                    clipBehavior: Clip.antiAlias,
                    child: isWide
                        ? Column(
                            children: [
                              const _CashLedgerTableHeader(),
                              Expanded(
                                child: ListView.builder(
                                  scrollCacheExtent: _kAccountingListCacheExtent,
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  itemExtent: 74,
                                  itemCount: rows.length,
                                  itemBuilder: (context, index) =>
                                      _CashLedgerTransactionRow(
                                    store: widget.store,
                                    transaction: rows[index],
                                    isWide: true,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            scrollCacheExtent: _kAccountingListCacheExtent,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            itemExtent: 96,
                            itemCount: rows.length,
                            itemBuilder: (context, index) =>
                                _CashLedgerTransactionRow(
                              store: widget.store,
                              transaction: rows[index],
                              isWide: false,
                            ),
                          ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CashLedgerFilterBar extends StatelessWidget {
  const _CashLedgerFilterBar({
    required this.direction,
    required this.type,
    required this.from,
    required this.to,
    required this.onDirectionChanged,
    required this.onTypeChanged,
    required this.onPickRange,
    required this.onClearRange,
  });

  final String direction;
  final String type;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<String> onDirectionChanged;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onPickRange;
  final VoidCallback onClearRange;

  @override
  Widget build(BuildContext context) {
    final rangeLabel = from == null || to == null
        ? _accountingUiText(
            context, 'كل الفترات', 'All periods', 'Toutes périodes')
        : '${_dateText(from!)} → ${_dateText(to!)}';
    const types = <String>[
      'receipt',
      'payment',
      'supplier_payment',
      'expense',
      'refund',
      'supplier_refund',
      'expense_refund',
      'cash_in',
      'cash_out',
      'cash_deposit',
      'cash_withdrawal',
      'transfer',
      'vault_transfer',
      'shift_transfer',
      'shortage',
      'overage',
      'opening',
      'closing',
      'reversal',
    ];
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                key: ValueKey('cash-direction:$direction'),
                initialValue: direction,
                isExpanded: true,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: _accountingUiText(
                      context, 'الاتجاه', 'Direction', 'Sens'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(_accountingUiText(
                        context, 'داخل وخارج', 'In & out', 'Entrées et sorties')),
                  ),
                  DropdownMenuItem(
                    value: 'in',
                    child: Text(AppLocalizations.of(context).text('cash_in')),
                  ),
                  DropdownMenuItem(
                    value: 'out',
                    child: Text(AppLocalizations.of(context).text('cash_out')),
                  ),
                ],
                onChanged: (value) => onDirectionChanged(value ?? ''),
              ),
            ),
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<String>(
                key: ValueKey('cash-type:$type'),
                initialValue: type,
                isExpanded: true,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: _accountingUiText(
                      context, 'نوع الحركة', 'Movement type', 'Type'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(_accountingUiText(context, 'كل الأنواع',
                        'All types', 'Tous les types')),
                  ),
                  for (final value in types)
                    DropdownMenuItem(
                      value: value,
                      child: Text(_cashLedgerTypeLabel(context, value)),
                    ),
                ],
                onChanged: (value) => onTypeChanged(value ?? ''),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onPickRange,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(rangeLabel),
            ),
            if (from != null || to != null)
              TextButton.icon(
                onPressed: onClearRange,
                icon: const Icon(Icons.clear),
                label: Text(_accountingUiText(
                    context, 'كل الفترات', 'All periods', 'Toutes périodes')),
              ),
          ],
        ),
      ),
    );
  }
}

class _CashLedgerTableHeader extends StatelessWidget {
  const _CashLedgerTableHeader();

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final style = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
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
            width: 120,
            child: Text(
              tr.text('cash_in'),
              style: style,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              tr.text('cash_out'),
              style: style,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _CashLedgerTransactionRow extends StatelessWidget {
  const _CashLedgerTransactionRow({
    required this.store,
    required this.transaction,
    required this.isWide,
  });

  final AppStore store;
  final CashLedgerTransaction transaction;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final isIn = transaction.isCashIn;
    final amountText = formatUsdReferenceAmount(
      transaction.amount,
      store.storeProfile,
    );
    final party = transaction.partyName.trim().isNotEmpty
        ? transaction.partyName.trim()
        : transaction.notes.trim().isNotEmpty
            ? transaction.notes.trim()
            : _cashLedgerPartyFallback(context, transaction.partyType);
    final reference = _joinParts([
      transaction.referenceNumber,
      transaction.paymentMethod,
    ]);
    final typeLabel = _cashLedgerTypeLabel(context, transaction.type);
    final directionLabel = tr.text(isIn ? 'cash_in' : 'cash_out');
    final directionColor = isIn
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;

    if (!isWide) {
      return ListTile(
        leading: CircleAvatar(
          child: Icon(
            isIn ? Icons.south_west : Icons.north_east,
            size: 20,
          ),
        ),
        title: Text(
          party.isEmpty ? typeLabel : party,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            _dateText(transaction.occurredAt.toLocal()),
            typeLabel,
            reference,
          ].where((part) => part.trim().isNotEmpty).join(' • '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _showJournalForCashLedgerTransaction(
          context,
          store: store,
          transaction: transaction,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              directionLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: directionColor,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            Text(
              amountText,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: directionColor,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: () => _showJournalForCashLedgerTransaction(
        context,
        store: store,
        transaction: transaction,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(_dateText(transaction.occurredAt.toLocal())),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Icon(
                  isIn ? Icons.south_west : Icons.north_east,
                  size: 18,
                  color: directionColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    typeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              party,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              reference,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              isIn ? amountText : '',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: isIn ? directionColor : null,
                    fontWeight: isIn ? FontWeight.w800 : null,
                  ),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              isIn ? '' : amountText,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: isIn ? null : directionColor,
                    fontWeight: isIn ? null : FontWeight.w800,
                  ),
            ),
          ),
          ],
        ),
      ),
    );
  }
}

String _cashLedgerPartyFallback(BuildContext context, String partyType) {
  final tr = AppLocalizations.of(context);
  switch (partyType.trim().toLowerCase()) {
    case 'customer':
      return tr.text('customer');
    case 'supplier':
      return tr.text('supplier');
    default:
      return '';
  }
}

String _cashLedgerTypeLabel(BuildContext context, String type) {
  final language = Localizations.localeOf(context).languageCode;
  final normalized = type.trim().toLowerCase();
  const ar = <String, String>{
    'receipt': 'قبض',
    'payment': 'دفع',
    'expense': 'مصروف نقدي',
    'refund': 'استرداد عميل',
    'supplier_refund': 'استرداد مورد',
    'expense_refund': 'استرداد مصروف',
    'supplier_payment': 'دفع مورد',
    'cash_in': 'إيداع نقدي',
    'cash_out': 'سحب نقدي',
    'cash_deposit': 'إيداع نقدي',
    'cash_withdrawal': 'سحب نقدي',
    'deposit': 'إيداع نقدي',
    'withdrawal': 'سحب نقدي',
    'transfer': 'تحويل نقدي',
    'vault_transfer': 'تحويل خزنة',
    'shift_transfer': 'تحويل وردية',
    'transfer_in': 'تحويل وارد',
    'transfer_out': 'تحويل صادر',
    'shortage': 'عجز صندوق',
    'overage': 'زيادة صندوق',
    'opening': 'افتتاح',
    'closing': 'إغلاق',
    'reversal': 'عكس حركة',
  };
  const en = <String, String>{
    'receipt': 'Receipt',
    'payment': 'Payment',
    'expense': 'Cash expense',
    'refund': 'Customer refund',
    'supplier_refund': 'Supplier refund',
    'expense_refund': 'Expense refund',
    'supplier_payment': 'Supplier payment',
    'cash_in': 'Cash deposit',
    'cash_out': 'Cash withdrawal',
    'cash_deposit': 'Cash deposit',
    'cash_withdrawal': 'Cash withdrawal',
    'deposit': 'Cash deposit',
    'withdrawal': 'Cash withdrawal',
    'transfer': 'Cash transfer',
    'vault_transfer': 'Vault transfer',
    'shift_transfer': 'Shift transfer',
    'transfer_in': 'Transfer in',
    'transfer_out': 'Transfer out',
    'shortage': 'Cash shortage',
    'overage': 'Cash overage',
    'opening': 'Opening',
    'closing': 'Closing',
    'reversal': 'Reversal',
  };
  final label = language == 'ar' ? ar[normalized] : en[normalized];
  if (label != null) return label;
  return type.replaceAll('_', ' ').trim();
}

Future<void> _showJournalForCashLedgerTransaction(
  BuildContext context, {
  required AppStore store,
  required CashLedgerTransaction transaction,
}) async {
  final referenceType = transaction.referenceType.trim();
  final referenceId = transaction.referenceId.trim();
  await _showJournalDrillDown(
    context,
    store: store,
    referenceType: referenceType,
    referenceId: referenceId,
    referenceNo: transaction.referenceNumber,
  );
}

Future<void> _showJournalForAccountTransaction(
  BuildContext context, {
  required AppStore store,
  required AccountTransaction transaction,
}) async {
  String referenceType = '';
  String referenceId = '';
  switch (transaction.type) {
    case 'saleInvoice':
      referenceType = 'sale';
      referenceId = transaction.referenceId;
      break;
    case 'purchaseInvoice':
      referenceType = 'purchase';
      referenceId = transaction.referenceId;
      break;
    case 'paymentReceived':
      referenceType = 'receipt_voucher';
      referenceId = _voucherIdFromAccountTransaction(
        transaction.id,
        const ['-customer-payment', '-customer-account-payment'],
      );
      break;
    case 'paymentPaid':
      referenceType = 'payment_voucher';
      referenceId = _voucherIdFromAccountTransaction(
        transaction.id,
        const ['-supplier-payment', '-supplier-account-payment'],
      );
      break;
    case 'saleReturn':
      referenceType = 'sale_return';
      break;
    case 'expense':
      referenceType = 'expense';
      referenceId = transaction.referenceId;
      break;
    default:
      break;
  }
  await _showJournalDrillDown(
    context,
    store: store,
    referenceType: referenceType,
    referenceId: referenceId,
    referenceNo: transaction.referenceNo,
  );
}

String _voucherIdFromAccountTransaction(String id, List<String> suffixes) {
  for (final suffix in suffixes) {
    if (id.endsWith(suffix) && id.length > suffix.length) {
      return id.substring(0, id.length - suffix.length);
    }
  }
  return '';
}

class _TransactionsTab extends StatelessWidget {
  const _TransactionsTab(
      {required this.store, required this.query, required this.cashOnly});

  final AppStore store;
  final String query;
  final bool cashOnly;
  static final RevisionKeyCache<List<AccountTransaction>> _rowsCache =
      RevisionKeyCache<List<AccountTransaction>>();

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _normalizedSearchQuery(query);
    final rows = _rowsCache.getOrCompute(
      store.accounting.ledgerRevision,
      '${store.appIdentity.storeId}|$cashOnly|$normalizedQuery',
      () {
        final computed = store.accounting.transactions
            .where((txn) =>
                (!cashOnly || _isCashTxn(txn)) &&
                _matchesNormalized(normalizedQuery, [
                  txn.accountName,
                  txn.referenceNo,
                  txn.paymentMethod,
                  txn.note,
                  txn.type
                ]))
            .toList(growable: false);
        computed.sort((a, b) => b.date.compareTo(a.date));
        return computed;
      },
    );

    if (rows.isEmpty) {
      return _EmptyAccountingState(
          message: AppLocalizations.of(context).text(
              cashOnly ? 'no_cash_movements' : 'no_account_transactions'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 780;
        final rowExtent = isWide ? 72.0 : 92.0;
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: isWide
              ? Column(
                  children: [
                    const _TransactionTableHeader(),
                    Expanded(
                      child: ListView.builder(
                        scrollCacheExtent: _kAccountingListCacheExtent,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemExtent: rowExtent,
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final transaction = rows[index];
                          return _TransactionRow(
                              store: store,
                              transaction: transaction,
                              isWide: isWide);
                        },
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  scrollCacheExtent: _kAccountingListCacheExtent,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemExtent: rowExtent,
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final transaction = rows[index];
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
              width: 118,
              child: Text(tr.text('debit'),
                  style: style, textAlign: TextAlign.end)),
          SizedBox(
              width: 118,
              child: Text(tr.text('credit'),
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
    final debitText = transaction.debit > 0
        ? formatUsdReferenceAmount(transaction.debit, store.storeProfile)
        : '';
    final creditText = transaction.credit > 0
        ? formatUsdReferenceAmount(transaction.credit, store.storeProfile)
        : '';
    final accountName = transaction.accountName.trim().isEmpty
        ? tr.text(
            transaction.accountType == 'supplier' ? 'supplier' : 'customer')
        : transaction.accountName;
    final typeText = _typeTitle(context, transaction.type);
    final methodText = transaction.paymentMethod.isEmpty
        ? ''
        : _paymentMethodLabel(context, transaction.paymentMethod);
    final note = transaction.note.trim();
    final postingLabel = transaction.debit > 0
        ? tr.text('debit')
        : tr.text('credit');
    final postingAmount = transaction.debit > 0 ? debitText : creditText;

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
        onTap: () => _showJournalForAccountTransaction(
          context,
          store: store,
          transaction: transaction,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(postingLabel,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(postingAmount,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
      );
    }

    return InkWell(
      onTap: () => _showJournalForAccountTransaction(
        context,
        store: store,
        transaction: transaction,
      ),
      child: Padding(
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
              width: 118,
              child: Text(debitText,
                  textAlign: TextAlign.end,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700))),
          SizedBox(
              width: 118,
              child: Text(creditText,
                  textAlign: TextAlign.end,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
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

class _JournalEntriesTab extends StatefulWidget {
  const _JournalEntriesTab({required this.store, required this.query});

  final AppStore store;
  final String query;

  @override
  State<_JournalEntriesTab> createState() => _JournalEntriesTabState();
}

class _JournalEntriesTabState extends State<_JournalEntriesTab> {
  String _status = '';
  String _source = '';
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toLocal();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 1)
        .subtract(const Duration(microseconds: 1));
  }

  Future<void> _pickRange() async {
    final now = DateTime.now().toLocal();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
      initialDateRange: DateTimeRange(
        start: _from ?? DateTime(now.year, now.month, 1),
        end: _to ?? now,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _to = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
        23,
        59,
        59,
        999,
        999,
      );
    });
  }


  Future<void> _editManualJournal(
      JournalEntrySummaryReport summary) async {
    widget.store.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    try {
      final details = await AccountingService.journalEntryDetails(
        entryId: summary.id,
      );
      if (details.isEmpty) {
        throw StateError('Manual journal details were not found.');
      }
      final entry = details.first;
      if (entry.referenceType != 'manual_journal' ||
          entry.source != 'manual' ||
          entry.status != 'posted' ||
          entry.reversedByEntryId.isNotEmpty) {
        throw StateError(
            'Only an active manual journal entry can be edited directly.');
      }
      if (entry.lines.length != 2) {
        throw StateError(
            'This manual journal has more than two lines and cannot be edited from the quick editor.');
      }

      final accounts = (await AccountingService.listAccounts())
          .where((account) => account.isPostable)
          .toList(growable: false);
      final costCenters = await AccountingService.listCostCenters();
      final branches = await AccountingService.listAccountingBranches();
      if (!mounted) return;

      final debitLine = entry.lines.firstWhere(
        (line) => line.debit > 0.005,
        orElse: () => entry.lines.first,
      );
      final creditLine = entry.lines.firstWhere(
        (line) => line.credit > 0.005,
        orElse: () => entry.lines.last,
      );
      AccountingAccount? accountById(String id) {
        for (final account in accounts) {
          if (account.id == id) return account;
        }
        return null;
      }

      AdvancedAccountingItem? advancedById(
          List<AdvancedAccountingItem> items, String id) {
        if (id.trim().isEmpty) return null;
        for (final item in items) {
          if (item.id == id) return item;
        }
        return null;
      }

      AccountingAccount? debitAccount = accountById(debitLine.accountId);
      AccountingAccount? creditAccount = accountById(creditLine.accountId);
      if (debitAccount == null || creditAccount == null) {
        throw StateError(
            'One of the journal accounts is no longer available for posting.');
      }
      AdvancedAccountingItem? debitCostCenter =
          advancedById(costCenters, debitLine.costCenterId);
      AdvancedAccountingItem? creditCostCenter =
          advancedById(costCenters, creditLine.costCenterId);
      AdvancedAccountingItem? branch = advancedById(branches, entry.branchId);
      var entryDate = entry.entryDate.toLocal();
      final description = TextEditingController(text: entry.description);
      final amount = TextEditingController(
        text: (debitLine.debit > 0 ? debitLine.debit : creditLine.credit)
            .toStringAsFixed(2),
      );

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(_accountingUiText(
              context,
              'تعديل القيد اليدوي',
              'Edit manual journal',
              'Modifier l’écriture manuelle',
            )),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: description,
                    decoration:
                        InputDecoration(labelText: tr.text('description')),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr.text('date')),
                    subtitle: Text(_dateText(entryDate)),
                    trailing: const Icon(Icons.calendar_month_outlined),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: entryDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(DateTime.now().year + 5, 12, 31),
                      );
                      if (picked != null) {
                        setDialogState(() => entryDate = picked);
                      }
                    },
                  ),
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
                              '${item.accountCode} - ${_localizedAccountingName(item.name, tr)}'),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => branch = value),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<AccountingAccount>(
                    initialValue: debitAccount,
                    isExpanded: true,
                    decoration:
                        InputDecoration(labelText: tr.text('debit_account')),
                    items: [
                      for (final account in accounts)
                        DropdownMenuItem<AccountingAccount>(
                          value: account,
                          child: Text(
                              '${account.code} - ${_localizedAccountingName(account.name, tr)}'),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => debitAccount = value),
                  ),
                  DropdownButtonFormField<AdvancedAccountingItem?>(
                    initialValue: debitCostCenter,
                    isExpanded: true,
                    decoration: InputDecoration(
                        labelText: tr.text('debit_cost_center')),
                    items: [
                      DropdownMenuItem<AdvancedAccountingItem?>(
                          value: null,
                          child: Text(tr.text('no_cost_center'))),
                      for (final item in costCenters)
                        DropdownMenuItem<AdvancedAccountingItem?>(
                          value: item,
                          child: Text(
                              '${item.accountCode} - ${_localizedAccountingName(item.name, tr)}'),
                        ),
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
                      for (final account in accounts)
                        DropdownMenuItem<AccountingAccount>(
                          value: account,
                          child: Text(
                              '${account.code} - ${_localizedAccountingName(account.name, tr)}'),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => creditAccount = value),
                  ),
                  DropdownButtonFormField<AdvancedAccountingItem?>(
                    initialValue: creditCostCenter,
                    isExpanded: true,
                    decoration: InputDecoration(
                        labelText: tr.text('credit_cost_center')),
                    items: [
                      DropdownMenuItem<AdvancedAccountingItem?>(
                          value: null,
                          child: Text(tr.text('no_cost_center'))),
                      for (final item in costCenters)
                        DropdownMenuItem<AdvancedAccountingItem?>(
                          value: item,
                          child: Text(
                              '${item.accountCode} - ${_localizedAccountingName(item.name, tr)}'),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => creditCostCenter = value),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        InputDecoration(labelText: tr.text('amount')),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr.text('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr.text('save')),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true) return;
      final value = double.tryParse(amount.text.trim()) ?? 0;
      if (value <= 0 || debitAccount == null || creditAccount == null) {
        throw StateError('A positive balanced journal amount is required.');
      }
      final user = widget.store.activeUser;
      final actor = user?.fullName.trim().isNotEmpty == true
          ? user!.fullName.trim()
          : widget.store.currentRole;
      await AccountingService.editManualJournalEntry(
        activeEntryId: entry.id,
        entryDate: entryDate,
        description: description.text,
        createdBy: actor,
        branchId: branch?.id ?? '',
        lines: [
          JournalLineDraft(
            accountId: debitAccount!.id,
            debit: value,
            credit: 0,
            costCenterId: debitCostCenter?.id ?? '',
          ),
          JournalLineDraft(
            accountId: creditAccount!.id,
            debit: 0,
            credit: value,
            costCenterId: creditCostCenter?.id ?? '',
          ),
        ],
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_accountingUiText(
            context,
            'تم تعديل القيد اليدوي وإعادة ترحيله.',
            'Manual journal edited and reposted.',
            'Écriture manuelle modifiée et repostée.',
          )),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String get _cacheKey => [
        'journal_entries_ui_v1',
        widget.query.trim().toLowerCase(),
        _status,
        _source,
        _from?.toIso8601String() ?? '',
        _to?.toIso8601String() ?? '',
      ].join('|');

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _JournalEntriesFilterBar(
          status: _status,
          source: _source,
          from: _from,
          to: _to,
          onStatusChanged: (value) => setState(() => _status = value),
          onSourceChanged: (value) => setState(() => _source = value),
          onPickRange: _pickRange,
          onClearRange: () => setState(() {
            _from = null;
            _to = null;
          }),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _CachedFuturePanel<List<JournalEntrySummaryReport>>(
            store: widget.store,
            cacheKey: _cacheKey,
            loadFuture: () => AccountingService.listJournalEntrySummaries(
              from: _from,
              to: _to,
              status: _status,
              source: _source,
              search: widget.query,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _ReportError(message: snapshot.error.toString());
              }
              final rows = snapshot.data ?? const <JournalEntrySummaryReport>[];
              if (rows.isEmpty) {
                return _EmptyAccountingState(
                    message: tr.text('no_journal_entries_found'));
              }
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final entry = rows[index];
                  return Card(
                    elevation: 0,
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.receipt_long_outlined, size: 20),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.entryNo,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          _AccountingStatusBadge(status: entry.status),
                        ],
                      ),
                      subtitle: Text(
                        [
                          _dateText(entry.entryDate.toLocal()),
                          _joinParts([entry.referenceType, entry.referenceNo]),
                          _journalSourceLabel(context, entry.source),
                          entry.description,
                          if (entry.reversalReason.trim().isNotEmpty)
                            entry.reversalReason.trim(),
                        ]
                            .where((part) => part.trim().isNotEmpty)
                            .join(' • '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _money(widget.store, entry.totalDebit),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                _accountingUiText(
                                  context,
                                  '${entry.lineCount} سطر',
                                  '${entry.lineCount} lines',
                                  '${entry.lineCount} lignes',
                                ),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          if (entry.referenceType == 'manual_journal' &&
                              entry.source == 'manual' &&
                              entry.status == 'posted' &&
                              entry.reversedByEntryId.isEmpty &&
                              entry.lineCount == 2 &&
                              widget.store.hasPermission(
                                  AppPermission.accountingManage))
                            IconButton(
                              tooltip: _accountingUiText(
                                context,
                                'تعديل القيد اليدوي',
                                'Edit manual journal',
                                'Modifier l’écriture manuelle',
                              ),
                              onPressed: () => _editManualJournal(entry),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          IconButton(
                            tooltip: _accountingUiText(context, 'عرض القيد', 'View journal', 'Voir l’écriture'),
                            onPressed: () => _showJournalDrillDown(
                              context,
                              store: widget.store,
                              entryId: entry.id,
                            ),
                            icon: const Icon(Icons.open_in_new),
                          ),
                        ],
                      ),
                      onTap: () => _showJournalDrillDown(
                        context,
                        store: widget.store,
                        entryId: entry.id,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _JournalEntriesFilterBar extends StatelessWidget {
  const _JournalEntriesFilterBar({
    required this.status,
    required this.source,
    required this.from,
    required this.to,
    required this.onStatusChanged,
    required this.onSourceChanged,
    required this.onPickRange,
    required this.onClearRange,
  });

  final String status;
  final String source;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onSourceChanged;
  final VoidCallback onPickRange;
  final VoidCallback onClearRange;

  @override
  Widget build(BuildContext context) {
    final rangeLabel = from == null || to == null
        ? _accountingUiText(
            context, 'كل الفترات', 'All periods', 'Toutes périodes')
        : '${_dateText(from!)} → ${_dateText(to!)}';
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                key: ValueKey('journal-status:$status'),
                initialValue: status,
                isExpanded: true,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: _accountingUiText(
                      context, 'حالة القيد', 'Entry status', 'Statut'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(_accountingUiText(
                        context, 'كل الحالات', 'All statuses', 'Tous statuts')),
                  ),
                  for (final value in const ['posted', 'reversed', 'draft', 'void'])
                    DropdownMenuItem(
                      value: value,
                      child: Text(_localizedAccountingStatus(
                          value, AppLocalizations.of(context))),
                    ),
                ],
                onChanged: (value) => onStatusChanged(value ?? ''),
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                key: ValueKey('journal-source:$source'),
                initialValue: source,
                isExpanded: true,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: _accountingUiText(
                      context, 'المصدر', 'Source', 'Source'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(_accountingUiText(
                        context, 'كل المصادر', 'All sources', 'Toutes sources')),
                  ),
                  for (final value in const ['system', 'manual', 'import', 'reversal'])
                    DropdownMenuItem(
                      value: value,
                      child: Text(_journalSourceLabel(context, value)),
                    ),
                ],
                onChanged: (value) => onSourceChanged(value ?? ''),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onPickRange,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(rangeLabel),
            ),
            if (from != null || to != null)
              TextButton.icon(
                onPressed: onClearRange,
                icon: const Icon(Icons.clear),
                label: Text(_accountingUiText(
                    context, 'كل الفترات', 'All periods', 'Toutes périodes')),
              ),
          ],
        ),
      ),
    );
  }
}

Future<List<JournalEntryDetailsReport>> _loadJournalDrillDown({
  String entryId = '',
  String entryNo = '',
  String referenceType = '',
  String referenceId = '',
  String referenceNo = '',
}) async {
  if (entryId.trim().isNotEmpty || entryNo.trim().isNotEmpty) {
    return AccountingService.journalEntryDetails(
      entryId: entryId,
      entryNo: entryNo,
    );
  }
  var rows = const <JournalEntryDetailsReport>[];
  if (referenceId.trim().isNotEmpty) {
    rows = await AccountingService.journalEntryDetails(
      referenceType: referenceType,
      referenceId: referenceId,
    );
  }
  if (rows.isEmpty && referenceNo.trim().isNotEmpty) {
    rows = await AccountingService.journalEntryDetails(
      referenceNo: referenceNo,
    );
  }
  return rows;
}

Future<void> _showJournalDrillDown(
  BuildContext context, {
  required AppStore store,
  String entryId = '',
  String entryNo = '',
  String referenceType = '',
  String referenceId = '',
  String referenceNo = '',
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.menu_book_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_accountingUiText(dialogContext, 'تفاصيل القيد',
                'Journal details', 'Détails de l’écriture')),
          ),
        ],
      ),
      content: SizedBox(
        width: 900,
        height: 560,
        child: FutureBuilder<List<JournalEntryDetailsReport>>(
          future: _loadJournalDrillDown(
            entryId: entryId,
            entryNo: entryNo,
            referenceType: referenceType,
            referenceId: referenceId,
            referenceNo: referenceNo,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator.adaptive());
            }
            if (snapshot.hasError) {
              return _ReportError(message: snapshot.error.toString());
            }
            final entries =
                snapshot.data ?? const <JournalEntryDetailsReport>[];
            if (entries.isEmpty) {
              return _EmptyAccountingState(
                message: _accountingUiText(
                  context,
                  'لم يتم العثور على قيد محاسبي مرتبط بهذه الحركة.',
                  'No linked journal entry was found for this movement.',
                  'Aucune écriture liée n’a été trouvée.',
                ),
              );
            }
            return ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _JournalDetailsCard(store: store, entry: entries[index]),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(MaterialLocalizations.of(dialogContext).closeButtonLabel),
        ),
      ],
    ),
  );
}

class _JournalDetailsCard extends StatelessWidget {
  const _JournalDetailsCard({required this.store, required this.entry});

  final AppStore store;
  final JournalEntryDetailsReport entry;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.entryNo,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                _AccountingStatusBadge(status: entry.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                _dateText(entry.entryDate.toLocal()),
                _joinParts([entry.referenceType, entry.referenceNo]),
                _journalSourceLabel(context, entry.source),
                entry.createdBy,
                entry.branchId,
              ].where((value) => value.trim().isNotEmpty).join(' • '),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            if (entry.description.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(entry.description),
            ],
            if (entry.reversalReason.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _accountingUiText(
                  context,
                  'سبب العكس: ${entry.reversalReason}',
                  'Reversal reason: ${entry.reversalReason}',
                  'Motif d’annulation : ${entry.reversalReason}',
                ),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text(_accountingUiText(
                      context, 'الحساب', 'Account', 'Compte'))),
                  DataColumn(label: Text(tr.text('debit')), numeric: true),
                  DataColumn(label: Text(tr.text('credit')), numeric: true),
                  DataColumn(label: Text(_accountingUiText(
                      context, 'الطرف', 'Party', 'Tiers'))),
                  DataColumn(label: Text(_accountingUiText(
                      context, 'البيان', 'Memo', 'Libellé'))),
                ],
                rows: [
                  for (final line in entry.lines)
                    DataRow(cells: [
                      DataCell(SizedBox(
                        width: 220,
                        child: Text(
                          '${line.accountCode} • ${_localizedAccountingName(line.accountName, tr)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
                      DataCell(Text(_money(store, line.debit))),
                      DataCell(Text(_money(store, line.credit))),
                      DataCell(Text(line.partyName)),
                      DataCell(SizedBox(
                        width: 260,
                        child: Text(line.memo, overflow: TextOverflow.ellipsis),
                      )),
                    ]),
                  DataRow(cells: [
                    DataCell(Text(
                      _accountingUiText(
                          context, 'الإجمالي', 'Total', 'Total'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    )),
                    DataCell(Text(
                      _money(store, entry.totalDebit),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    )),
                    DataCell(Text(
                      _money(store, entry.totalCredit),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    )),
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountingStatusBadge extends StatelessWidget {
  const _AccountingStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toLowerCase();
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (normalized) {
      'posted' || 'active' || 'cleared' || 'collected' || 'closed' =>
        (scheme.primaryContainer, scheme.onPrimaryContainer,
            Icons.check_circle_outline),
      'reversed' || 'void' || 'cancelled' || 'canceled' || 'bounced' =>
        (scheme.errorContainer, scheme.onErrorContainer, Icons.undo_outlined),
      'draft' || 'pending' || 'open' =>
        (scheme.tertiaryContainer, scheme.onTertiaryContainer,
            Icons.schedule_outlined),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant,
          Icons.info_outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            _localizedAccountingStatus(status, AppLocalizations.of(context)),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

String _journalSourceLabel(BuildContext context, String source) {
  switch (source.trim().toLowerCase()) {
    case 'system':
      return _accountingUiText(context, 'نظامي', 'System', 'Système');
    case 'manual':
      return _accountingUiText(context, 'يدوي', 'Manual', 'Manuel');
    case 'import':
      return _accountingUiText(context, 'مستورد', 'Imported', 'Importé');
    case 'reversal':
      return _accountingUiText(context, 'عكس', 'Reversal', 'Extourne');
    default:
      return source;
  }
}

class _GeneralLedgerTab extends StatefulWidget {
  const _GeneralLedgerTab({required this.store, required this.query});

  final AppStore store;
  final String query;

  @override
  State<_GeneralLedgerTab> createState() => _GeneralLedgerTabState();
}

class _GeneralLedgerTabState extends State<_GeneralLedgerTab> {
  late Future<_GeneralLedgerFilterData> _filterDataFuture;
  String _accountId = '';
  String _branchId = '';
  String _costCenterId = '';
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toLocal();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 1)
        .subtract(const Duration(microseconds: 1));
    _filterDataFuture = _loadFilterData();
  }

  Future<_GeneralLedgerFilterData> _loadFilterData() async {
    final results = await Future.wait<Object>([
      AccountingService.listAccounts(),
      AccountingService.listGeneralLedgerBranches(),
      AccountingService.listCostCenters(),
    ]);
    return _GeneralLedgerFilterData(
      accounts: results[0] as List<AccountingAccount>,
      branches: results[1] as List<AdvancedAccountingItem>,
      costCenters: results[2] as List<AdvancedAccountingItem>,
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now().toLocal();
    final initialFrom = _from ?? DateTime(now.year, now.month, 1);
    final initialTo = _to ?? now;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
      initialDateRange: DateTimeRange(start: initialFrom, end: initialTo),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _to = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
        23,
        59,
        59,
        999,
        999,
      );
    });
  }

  String get _reportCacheKey => [
        'general_ledger_report_v2',
        _accountId,
        _branchId,
        _costCenterId,
        _from?.toIso8601String() ?? '',
        _to?.toIso8601String() ?? '',
      ].join('|');

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final normalizedQuery = _normalizedSearchQuery(widget.query);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<_GeneralLedgerFilterData>(
          future: _filterDataFuture,
          builder: (context, snapshot) {
            final data = snapshot.data ?? const _GeneralLedgerFilterData();
            return _GeneralLedgerFilterBar(
              accounts: data.accounts,
              branches: data.branches,
              costCenters: data.costCenters,
              accountId: _accountId,
              branchId: _branchId,
              costCenterId: _costCenterId,
              from: _from,
              to: _to,
              onAccountChanged: (value) => setState(() => _accountId = value),
              onBranchChanged: (value) => setState(() => _branchId = value),
              onCostCenterChanged: (value) =>
                  setState(() => _costCenterId = value),
              onPickRange: _pickRange,
              onClearRange: () => setState(() {
                _from = null;
                _to = null;
              }),
            );
          },
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _CachedFuturePanel<List<GeneralLedgerAccountReport>>(
            store: widget.store,
            cacheKey: _reportCacheKey,
            loadFuture: () => AccountingService.generalLedgerReport(
              accountId: _accountId,
              from: _from,
              to: _to,
              branchId: _branchId,
              costCenterId: _costCenterId,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _ReportError(message: snapshot.error.toString());
              }
              final rows = (snapshot.data ?? <GeneralLedgerAccountReport>[])
                  .where((account) {
                final hasBalance = account.lines.isNotEmpty ||
                    account.openingBalance.abs() > 0.0001;
                if (!hasBalance) return false;
                if (_matchesNormalized(normalizedQuery, [
                  account.accountCode,
                  account.accountName,
                  account.accountType,
                ])) {
                  return true;
                }
                return account.lines.any((line) => _matchesNormalized(
                      normalizedQuery,
                      [
                        line.entryNo,
                        line.referenceType,
                        line.referenceNo,
                        line.description,
                        line.memo,
                      ],
                    ));
              }).toList(growable: false);
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
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_accountingUiText(context, 'افتتاحي', 'Opening', 'Ouverture')} ${_money(widget.store, account.openingBalance)}'
                        ' • ${tr.text('debit')} ${_money(widget.store, account.totalDebit)}'
                        ' • ${tr.text('credit')} ${_money(widget.store, account.totalCredit)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _accountingUiText(
                                context, 'الرصيد الختامي', 'Closing balance', 'Solde de clôture'),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          Text(
                            _money(widget.store, account.closingBalance),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      children: [
                        _LedgerLinesTable(store: widget.store, account: account),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GeneralLedgerFilterData {
  const _GeneralLedgerFilterData({
    this.accounts = const <AccountingAccount>[],
    this.branches = const <AdvancedAccountingItem>[],
    this.costCenters = const <AdvancedAccountingItem>[],
  });

  final List<AccountingAccount> accounts;
  final List<AdvancedAccountingItem> branches;
  final List<AdvancedAccountingItem> costCenters;
}

class _GeneralLedgerFilterBar extends StatelessWidget {
  const _GeneralLedgerFilterBar({
    required this.accounts,
    required this.branches,
    required this.costCenters,
    required this.accountId,
    required this.branchId,
    required this.costCenterId,
    required this.from,
    required this.to,
    required this.onAccountChanged,
    required this.onBranchChanged,
    required this.onCostCenterChanged,
    required this.onPickRange,
    required this.onClearRange,
  });

  final List<AccountingAccount> accounts;
  final List<AdvancedAccountingItem> branches;
  final List<AdvancedAccountingItem> costCenters;
  final String accountId;
  final String branchId;
  final String costCenterId;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<String> onAccountChanged;
  final ValueChanged<String> onBranchChanged;
  final ValueChanged<String> onCostCenterChanged;
  final VoidCallback onPickRange;
  final VoidCallback onClearRange;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    Widget dropdown({
      required String keyName,
      required String value,
      required String label,
      required List<DropdownMenuItem<String>> items,
      required ValueChanged<String> onChanged,
    }) {
      return SizedBox(
        width: 230,
        child: DropdownButtonFormField<String>(
          key: ValueKey('$keyName:$value'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          items: items,
          onChanged: (next) => onChanged(next ?? ''),
        ),
      );
    }

    final rangeLabel = from == null || to == null
        ? _accountingUiText(context, 'كل الفترات', 'All periods', 'Toutes périodes')
        : '${_dateText(from!)} → ${_dateText(to!)}';
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            dropdown(
              keyName: 'gl-account',
              value: accountId,
              label: tr.text('account'),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(_accountingUiText(
                      context, 'كل الحسابات', 'All accounts', 'Tous les comptes')),
                ),
                for (final account in accounts.where((a) => a.isPostable))
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(
                      '${account.code} • ${_localizedAccountingName(account.name, tr)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: onAccountChanged,
            ),
            dropdown(
              keyName: 'gl-branch',
              value: branchId,
              label: _accountingUiText(context, 'الفرع', 'Branch', 'Branche'),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(_accountingUiText(
                      context, 'كل الفروع', 'All branches', 'Toutes les branches')),
                ),
                for (final branch in branches.where((item) => item.isActive))
                  DropdownMenuItem(
                    value: branch.id,
                    child: Text(
                      _joinParts([branch.accountCode, branch.name]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: onBranchChanged,
            ),
            dropdown(
              keyName: 'gl-cost-center',
              value: costCenterId,
              label: _accountingUiText(
                  context, 'مركز التكلفة', 'Cost center', 'Centre de coût'),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(_accountingUiText(context, 'كل مراكز التكلفة',
                      'All cost centers', 'Tous les centres de coût')),
                ),
                for (final center in costCenters.where((item) => item.isActive))
                  DropdownMenuItem(
                    value: center.id,
                    child: Text(
                      _joinParts([center.accountCode, center.name]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: onCostCenterChanged,
            ),
            OutlinedButton.icon(
              onPressed: onPickRange,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(rangeLabel),
            ),
            if (from != null || to != null)
              TextButton.icon(
                onPressed: onClearRange,
                icon: const Icon(Icons.clear),
                label: Text(_accountingUiText(
                    context, 'كل الفترات', 'All periods', 'Toutes périodes')),
              ),
          ],
        ),
      ),
    );
  }
}

class _LedgerLinesTable extends StatelessWidget {
  const _LedgerLinesTable({required this.store, required this.account});

  final AppStore store;
  final GeneralLedgerAccountReport account;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final lines = account.lines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lines.length > 200)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              _accountingUiText(
                context,
                'يتم عرض أول 200 حركة. ضيّق الفترة أو الحساب للوصول إلى تفاصيل أدق.',
                'Showing the first 200 movements. Narrow the period or account for more detail.',
                'Affichage des 200 premiers mouvements. Réduisez la période ou le compte pour plus de détails.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              DataColumn(label: Text(tr.text('date'))),
              DataColumn(label: Text(_accountingUiText(context, 'القيد', 'Journal', 'Écriture'))),
              DataColumn(label: Text(tr.text('reference'))),
              DataColumn(label: Text(tr.text('description'))),
              DataColumn(label: Text(tr.text('debit')), numeric: true),
              DataColumn(label: Text(tr.text('credit')), numeric: true),
              DataColumn(label: Text(tr.text('balance')), numeric: true),
            ],
            rows: [
              DataRow(cells: [
                const DataCell(Text('')),
                const DataCell(Text('')),
                const DataCell(Text('')),
                DataCell(Text(
                  _accountingUiText(
                      context, 'الرصيد الافتتاحي للفترة', 'Opening balance', 'Solde d’ouverture'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                )),
                const DataCell(Text('')),
                const DataCell(Text('')),
                DataCell(Text(
                  _money(store, account.openingBalance),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                )),
              ]),
              for (final line in lines.take(200))
                DataRow(cells: [
                  DataCell(Text(_dateText(line.entryDate))),
                  DataCell(TextButton.icon(
                    onPressed: () => _showJournalDrillDown(
                      context,
                      store: store,
                      entryNo: line.entryNo,
                    ),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(line.entryNo),
                  )),
                  DataCell(Text(_joinParts([line.referenceType, line.referenceNo]))),
                  DataCell(SizedBox(
                    width: 280,
                    child: Text(
                      line.memo.isEmpty ? line.description : line.memo,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
                  DataCell(Text(_money(store, line.debit))),
                  DataCell(Text(_money(store, line.credit))),
                  DataCell(Text(_money(store, line.runningBalance))),
                ]),
              DataRow(cells: [
                const DataCell(Text('')),
                const DataCell(Text('')),
                const DataCell(Text('')),
                DataCell(Text(
                  _accountingUiText(
                      context, 'إجمالي الفترة / الرصيد الختامي', 'Period totals / closing balance', 'Totaux / solde de clôture'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                )),
                DataCell(Text(
                  _money(store, account.totalDebit),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                )),
                DataCell(Text(
                  _money(store, account.totalCredit),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                )),
                DataCell(Text(
                  _money(store, account.closingBalance),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                )),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrialBalanceTab extends StatelessWidget {
  const _TrialBalanceTab({
    required this.store,
    required this.query,
    required this.from,
    required this.to,
  });

  final AppStore store;
  final String query;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final normalizedQuery = _normalizedSearchQuery(query);
    return _CachedFuturePanel<List<TrialBalanceRowReport>>(
      store: store,
      cacheKey:
          'trial_balance_report_v2|${from.toIso8601String()}|${to.toIso8601String()}',
      loadFuture: () =>
          AccountingService.trialBalanceReport(from: from, to: to),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
        final allRows = (snapshot.data ?? <TrialBalanceRowReport>[])
            .where((row) =>
                row.debit.abs() > 0.0001 ||
                row.credit.abs() > 0.0001 ||
                row.debitBalance.abs() > 0.0001 ||
                row.creditBalance.abs() > 0.0001)
            .toList(growable: false);
        final rows = allRows
            .where((row) => _matchesNormalized(normalizedQuery,
                [row.accountCode, row.accountName, row.accountType]))
            .toList(growable: false);
        final totalDebit =
            allRows.fold<double>(0, (sum, row) => sum + row.debit);
        final totalCredit =
            allRows.fold<double>(0, (sum, row) => sum + row.credit);
        final totalDebitBalance =
            allRows.fold<double>(0, (sum, row) => sum + row.debitBalance);
        final totalCreditBalance =
            allRows.fold<double>(0, (sum, row) => sum + row.creditBalance);
        final movementDifference = totalDebit - totalCredit;
        final balanceDifference = totalDebitBalance - totalCreditBalance;
        final isBalanced = movementDifference.abs() <= 0.009 &&
            balanceDifference.abs() <= 0.009;
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FinancialReportTitle(
                      title: tr.text('trial_balance'),
                      subtitle: _accountingUiText(
                        context,
                        'عن الفترة ${_dateText(from)} → ${_dateText(to)}',
                        'For the period ${_dateText(from)} → ${_dateText(to)}',
                        'Pour la période ${_dateText(from)} → ${_dateText(to)}',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ReportBalanceBanner(
                      isBalanced: isBalanced,
                      balancedText: _accountingUiText(
                        context,
                        'ميزان المراجعة متوازن',
                        'Trial balance is balanced',
                        'La balance est équilibrée',
                      ),
                      warningText: _accountingUiText(
                        context,
                        'يوجد فرق: حركة ${_money(store, movementDifference)} • أرصدة ${_money(store, balanceDifference)}',
                        'Difference detected: movements ${_money(store, movementDifference)} • balances ${_money(store, balanceDifference)}',
                        'Écart détecté : mouvements ${_money(store, movementDifference)} • soldes ${_money(store, balanceDifference)}',
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: rows.isEmpty
                    ? _EmptyAccountingState(
                        message: tr.text('no_journal_entries_found'))
                    : SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: [
                              DataColumn(label: Text(tr.text('code'))),
                              DataColumn(label: Text(tr.text('account'))),
                              DataColumn(label: Text(tr.text('type'))),
                              DataColumn(
                                  label: Text(tr.text('debit')), numeric: true),
                              DataColumn(
                                  label: Text(tr.text('credit')), numeric: true),
                              DataColumn(
                                label: Text(_accountingUiText(context,
                                    'رصيد مدين', 'Debit balance', 'Solde débiteur')),
                                numeric: true,
                              ),
                              DataColumn(
                                label: Text(_accountingUiText(context,
                                    'رصيد دائن', 'Credit balance', 'Solde créditeur')),
                                numeric: true,
                              ),
                            ],
                            rows: [
                              for (final row in rows)
                                DataRow(cells: [
                                  DataCell(Text(row.accountCode)),
                                  DataCell(Text(_localizedAccountingName(
                                      row.accountName, tr))),
                                  DataCell(Text(_localizedAccountingType(
                                      row.accountType, tr))),
                                  DataCell(Text(_money(store, row.debit))),
                                  DataCell(Text(_money(store, row.credit))),
                                  DataCell(
                                      Text(_money(store, row.debitBalance))),
                                  DataCell(
                                      Text(_money(store, row.creditBalance))),
                                ]),
                              DataRow(cells: [
                                const DataCell(Text('')),
                                DataCell(Text(
                                  _accountingUiText(context, 'إجمالي التقرير',
                                      'Report totals', 'Totaux du rapport'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                )),
                                const DataCell(Text('')),
                                DataCell(Text(
                                  _money(store, totalDebit),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                )),
                                DataCell(Text(
                                  _money(store, totalCredit),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                )),
                                DataCell(Text(
                                  _money(store, totalDebitBalance),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                )),
                                DataCell(Text(
                                  _money(store, totalCreditBalance),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                )),
                              ]),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _IncomeStatementTab extends StatelessWidget {
  const _IncomeStatementTab({
    required this.store,
    required this.from,
    required this.to,
  });

  final AppStore store;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return _CachedFuturePanel<IncomeStatementReport>(
      store: store,
      cacheKey:
          'income_statement_report_v2|${from.toIso8601String()}|${to.toIso8601String()}',
      loadFuture: () =>
          AccountingService.incomeStatementReport(from: from, to: to),
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
              netProfit: 0,
            );
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _FinancialReportTitle(
                title: tr.text('income_statement'),
                subtitle: _accountingUiText(
                  context,
                  'عن الفترة ${_dateText(from)} → ${_dateText(to)}',
                  'For the period ${_dateText(from)} → ${_dateText(to)}',
                  'Pour la période ${_dateText(from)} → ${_dateText(to)}',
                ),
              ),
              const SizedBox(height: 16),
              _FinancialBreakdownSection(
                store: store,
                title: _accountingUiText(
                    context, 'الإيرادات من المبيعات', 'Sales revenue', 'Revenus des ventes'),
                rows: [
                  _StatementRow(tr.text('sales_revenue'), report.grossSales),
                  _StatementRow(tr.text('sales_returns'), -report.salesReturns),
                  _StatementRow(
                      tr.text('sales_discounts'), -report.salesDiscounts),
                ],
                totalLabel: tr.text('net_sales'),
                totalAmount: report.netSales,
              ),
              const SizedBox(height: 12),
              _FinancialBreakdownSection(
                store: store,
                title: tr.text('cost_of_goods_sold'),
                accountLines: report.costOfSalesLines,
                totalLabel: tr.text('cost_of_goods_sold'),
                totalAmount: report.costOfGoodsSold,
              ),
              const SizedBox(height: 12),
              _FinancialResultTile(
                store: store,
                label: tr.text('gross_profit'),
                amount: report.grossProfit,
              ),
              const SizedBox(height: 12),
              _FinancialBreakdownSection(
                store: store,
                title: tr.text('other_revenue'),
                accountLines: report.otherRevenueLines,
                totalLabel: tr.text('other_revenue'),
                totalAmount: report.otherRevenue,
              ),
              const SizedBox(height: 12),
              _FinancialBreakdownSection(
                store: store,
                title: tr.text('expenses'),
                accountLines: report.expenseLines,
                totalLabel: _accountingUiText(context, 'إجمالي المصروفات',
                    'Total expenses', 'Total des charges'),
                totalAmount: report.expenses,
              ),
              const SizedBox(height: 16),
              _FinancialResultTile(
                store: store,
                label: tr.text('net_profit'),
                amount: report.netProfit,
                prominent: true,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InventoryManufacturingReportBundle {
  const _InventoryManufacturingReportBundle({
    required this.inventory,
    required this.manufacturing,
    required this.waste,
    required this.countVariances,
  });

  final List<InventoryValuationRowReport> inventory;
  final List<ManufacturingOrderCostReport> manufacturing;
  final List<ManufacturingWasteReportRow> waste;
  final List<InventoryCountVarianceReportRow> countVariances;

  static Future<_InventoryManufacturingReportBundle> load() async {
    final inventory = await AccountingService.inventoryValuationReport();
    final manufacturing =
        await AccountingService.manufacturingOrderCostReport();
    final waste = await AccountingService.manufacturingWasteReport();
    final countVariances =
        await AccountingService.inventoryCountVarianceReport();
    return _InventoryManufacturingReportBundle(
      inventory: inventory,
      manufacturing: manufacturing,
      waste: waste,
      countVariances: countVariances,
    );
  }
}

class _InventoryManufacturingReportsTab extends StatelessWidget {
  const _InventoryManufacturingReportsTab({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    String label(String ar, String en) => isArabic ? ar : en;
    return _CachedFuturePanel<_InventoryManufacturingReportBundle>(
      store: store,
      cacheKey: 'inventory_manufacturing_reports',
      loadFuture: _InventoryManufacturingReportBundle.load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
        final data = snapshot.data ??
            const _InventoryManufacturingReportBundle(
              inventory: <InventoryValuationRowReport>[],
              manufacturing: <ManufacturingOrderCostReport>[],
              waste: <ManufacturingWasteReportRow>[],
              countVariances: <InventoryCountVarianceReportRow>[],
            );
        final inventoryTotal = data.inventory.fold<double>(
          0,
          (sum, row) => sum + row.totalValue,
        );
        final wasteTotal = data.waste.fold<double>(
          0,
          (sum, row) => sum + row.value,
        );
        final countNet = data.countVariances.fold<double>(
          0,
          (sum, row) => sum + row.differenceValue,
        );

        Widget table(List<DataColumn> columns, List<DataRow> rows) {
          if (rows.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(label('لا توجد بيانات', 'No data')),
            );
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(columns: columns, rows: rows),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: ExpansionTile(
                initiallyExpanded: true,
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(label('تقييم المخزون', 'Inventory valuation')),
                subtitle: Text(
                  '${label('الإجمالي', 'Total')}: ${_money(store, inventoryTotal)}',
                ),
                children: [
                  table(
                    [
                      DataColumn(label: Text(label('المنتج', 'Product'))),
                      DataColumn(label: Text(label('المستودع', 'Warehouse'))),
                      DataColumn(label: Text(label('الفئة', 'Class'))),
                      DataColumn(
                          numeric: true, label: Text(label('الكمية', 'Qty'))),
                      DataColumn(
                          numeric: true,
                          label: Text(label('كلفة الوحدة', 'Unit cost'))),
                      DataColumn(
                          numeric: true, label: Text(label('القيمة', 'Value'))),
                    ],
                    [
                      for (final row in data.inventory)
                        DataRow(cells: [
                          DataCell(Text(row.productName)),
                          DataCell(Text(row.warehouseName)),
                          DataCell(Text(row.inventoryCategory)),
                          DataCell(Text(row.quantity.toStringAsFixed(3))),
                          DataCell(Text(_money(store, row.unitCost))),
                          DataCell(Text(_money(store, row.totalValue))),
                        ]),
                    ],
                  ),
                ],
              ),
            ),
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.precision_manufacturing_outlined),
                title: Text(
                    label('تكلفة أوامر التصنيع', 'Manufacturing order cost')),
                children: [
                  table(
                    [
                      DataColumn(label: Text(label('الأمر', 'Order'))),
                      DataColumn(label: Text(label('المنتج', 'Product'))),
                      DataColumn(
                          numeric: true,
                          label: Text(label('الإنتاج', 'Output'))),
                      DataColumn(
                          numeric: true,
                          label: Text(label('المواد', 'Materials'))),
                      DataColumn(
                          numeric: true, label: Text(label('الهدر', 'Waste'))),
                      DataColumn(
                          numeric: true,
                          label:
                              Text(label('الكلفة المقبولة', 'Eligible cost'))),
                      DataColumn(
                          numeric: true,
                          label: Text(label('كلفة الوحدة', 'Unit cost'))),
                      DataColumn(label: Text(label('الحالة', 'Status'))),
                      DataColumn(label: Text(label('القيد', 'Journal'))),
                    ],
                    [
                      for (final row in data.manufacturing)
                        DataRow(cells: [
                          DataCell(Text(row.orderNo)),
                          DataCell(Text(row.outputProductName)),
                          DataCell(Text(row.outputQuantity.toStringAsFixed(3))),
                          DataCell(Text(_money(store, row.totalMaterialCost))),
                          DataCell(Text(_money(store, row.wasteValue))),
                          DataCell(Text(_money(store, row.eligibleCost))),
                          DataCell(Text(_money(store, row.actualUnitCost))),
                          DataCell(_AccountingStatusBadge(status: row.status)),
                          DataCell(IconButton(
                            tooltip: _accountingUiText(context, 'عرض القيد', 'View journal', 'Voir l’écriture'),
                            onPressed: row.journalEntryId.trim().isEmpty
                                ? null
                                : () => _showJournalDrillDown(
                                      context,
                                      store: store,
                                      entryId: row.journalEntryId,
                                    ),
                            icon: const Icon(Icons.open_in_new, size: 18),
                          )),
                        ]),
                    ],
                  ),
                ],
              ),
            ),
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: Text(label('هدر التصنيع', 'Manufacturing waste')),
                subtitle: Text(
                  '${label('الإجمالي', 'Total')}: ${_money(store, wasteTotal)}',
                ),
                children: [
                  table(
                    [
                      DataColumn(label: Text(label('الأمر', 'Order'))),
                      DataColumn(label: Text(label('المادة', 'Material'))),
                      DataColumn(
                          numeric: true, label: Text(label('الكمية', 'Qty'))),
                      DataColumn(
                          numeric: true,
                          label: Text(label('كلفة الوحدة', 'Unit cost'))),
                      DataColumn(
                          numeric: true, label: Text(label('القيمة', 'Value'))),
                      DataColumn(label: Text(label('السبب', 'Reason'))),
                    ],
                    [
                      for (final row in data.waste)
                        DataRow(cells: [
                          DataCell(Text(row.orderNo)),
                          DataCell(Text(row.productName)),
                          DataCell(Text(row.quantity.toStringAsFixed(3))),
                          DataCell(Text(_money(store, row.unitCost))),
                          DataCell(Text(_money(store, row.value))),
                          DataCell(Text(row.reason)),
                        ]),
                    ],
                  ),
                ],
              ),
            ),
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: Text(label('فروقات الجرد', 'Inventory count variances')),
                subtitle: Text(
                  '${label('صافي القيمة', 'Net value')}: ${_money(store, countNet)}',
                ),
                children: [
                  table(
                    [
                      DataColumn(label: Text(label('الجرد', 'Count'))),
                      DataColumn(label: Text(label('المنتج', 'Product'))),
                      DataColumn(
                          numeric: true,
                          label: Text(label('كمية النظام', 'System qty'))),
                      DataColumn(
                          numeric: true,
                          label: Text(label('المعدود', 'Counted'))),
                      DataColumn(
                          numeric: true,
                          label: Text(label('الفرق', 'Difference'))),
                      DataColumn(
                          numeric: true, label: Text(label('القيمة', 'Value'))),
                      DataColumn(label: Text(label('الحالة', 'Status'))),
                      DataColumn(label: Text(label('القيد', 'Journal'))),
                    ],
                    [
                      for (final row in data.countVariances)
                        DataRow(cells: [
                          DataCell(Text(row.countNo)),
                          DataCell(Text(row.productName)),
                          DataCell(Text(row.systemQuantity.toStringAsFixed(3))),
                          DataCell(
                              Text(row.countedQuantity.toStringAsFixed(3))),
                          DataCell(
                              Text(row.differenceQuantity.toStringAsFixed(3))),
                          DataCell(Text(_money(store, row.differenceValue))),
                          DataCell(_AccountingStatusBadge(status: row.status)),
                          DataCell(IconButton(
                            tooltip: _accountingUiText(context, 'عرض القيد', 'View journal', 'Voir l’écriture'),
                            onPressed: row.journalEntryId.trim().isEmpty
                                ? null
                                : () => _showJournalDrillDown(
                                      context,
                                      store: store,
                                      entryId: row.journalEntryId,
                                    ),
                            icon: const Icon(Icons.open_in_new, size: 18),
                          )),
                        ]),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BalanceSheetTab extends StatelessWidget {
  const _BalanceSheetTab({required this.store, required this.asOf});

  final AppStore store;
  final DateTime asOf;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return _CachedFuturePanel<BalanceSheetReport>(
      store: store,
      cacheKey: 'balance_sheet_report_v2|${asOf.toIso8601String()}',
      loadFuture: () => AccountingService.balanceSheetReport(asOf: asOf),
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
              difference: 0,
            );
        final isBalanced = report.difference.abs() <= 0.009;
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _FinancialReportTitle(
                title: tr.text('balance_sheet'),
                subtitle: _accountingUiText(
                  context,
                  'كما في ${_dateText(asOf)}',
                  'As of ${_dateText(asOf)}',
                  'Au ${_dateText(asOf)}',
                ),
              ),
              const SizedBox(height: 12),
              _ReportBalanceBanner(
                isBalanced: isBalanced,
                balancedText: _accountingUiText(
                    context, 'المركز المالي متوازن', 'Balance sheet is balanced', 'Le bilan est équilibré'),
                warningText: _accountingUiText(
                  context,
                  'يوجد فرق محاسبي بقيمة ${_money(store, report.difference)}',
                  'Accounting difference: ${_money(store, report.difference)}',
                  'Écart comptable : ${_money(store, report.difference)}',
                ),
              ),
              const SizedBox(height: 16),
              _FinancialBreakdownSection(
                store: store,
                title: _accountingUiText(
                    context, 'الأصول المتداولة', 'Current assets', 'Actifs courants'),
                accountLines: report.currentAssetLines,
                totalLabel: _accountingUiText(context, 'إجمالي الأصول المتداولة',
                    'Total current assets', 'Total actifs courants'),
                totalAmount: report.currentAssets,
              ),
              const SizedBox(height: 12),
              _FinancialBreakdownSection(
                store: store,
                title: _accountingUiText(context, 'الأصول غير المتداولة',
                    'Non-current assets', 'Actifs non courants'),
                accountLines: report.nonCurrentAssetLines,
                totalLabel: _accountingUiText(context, 'إجمالي الأصول غير المتداولة',
                    'Total non-current assets', 'Total actifs non courants'),
                totalAmount: report.nonCurrentAssets,
              ),
              const SizedBox(height: 12),
              _FinancialResultTile(
                store: store,
                label: tr.text('assets'),
                amount: report.assets,
              ),
              const SizedBox(height: 18),
              _FinancialBreakdownSection(
                store: store,
                title: _accountingUiText(context, 'الالتزامات المتداولة',
                    'Current liabilities', 'Passifs courants'),
                accountLines: report.currentLiabilityLines,
                totalLabel: _accountingUiText(context, 'إجمالي الالتزامات المتداولة',
                    'Total current liabilities', 'Total passifs courants'),
                totalAmount: report.currentLiabilities,
              ),
              const SizedBox(height: 12),
              _FinancialBreakdownSection(
                store: store,
                title: _accountingUiText(context, 'الالتزامات غير المتداولة',
                    'Non-current liabilities', 'Passifs non courants'),
                accountLines: report.nonCurrentLiabilityLines,
                totalLabel: _accountingUiText(context, 'إجمالي الالتزامات غير المتداولة',
                    'Total non-current liabilities', 'Total passifs non courants'),
                totalAmount: report.nonCurrentLiabilities,
              ),
              const SizedBox(height: 12),
              _FinancialBreakdownSection(
                store: store,
                title: tr.text('equity'),
                accountLines: report.equityLines,
                rows: [
                  _StatementRow(
                      tr.text('current_profit_loss'), report.retainedEarnings),
                ],
                totalLabel: _accountingUiText(
                    context, 'إجمالي حقوق الملكية والنتيجة', 'Total equity and result', 'Total capitaux propres et résultat'),
                totalAmount: report.equity + report.retainedEarnings,
              ),
              const SizedBox(height: 16),
              _FinancialResultTile(
                store: store,
                label: tr.text('liabilities_equity'),
                amount: report.liabilitiesAndEquity,
              ),
              const SizedBox(height: 8),
              _FinancialResultTile(
                store: store,
                label: _accountingUiText(
                    context, 'إجمالي الأصول', 'Total assets', 'Total des actifs'),
                amount: report.assets,
                prominent: true,
              ),
            ],
          ),
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
          child: ListView.builder(
            scrollCacheExtent: _kAccountingListCacheExtent,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemExtent: 76.0,
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text(
                    '${row.accountCode} • ${_localizedAccountingName(row.accountName, tr)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${tr.text('in')} ${_money(store, row.moneyIn)} • ${tr.text('out')} ${_money(store, row.moneyOut)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
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
  const _CashFlowStatementTab({
    required this.store,
    required this.from,
    required this.to,
  });

  final AppStore store;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return _CachedFuturePanel<CashFlowStatementReport>(
      store: store,
      cacheKey:
          'cash_flow_report_v2|${from.toIso8601String()}|${to.toIso8601String()}',
      loadFuture: () =>
          AccountingService.cashFlowStatementReport(from: from, to: to),
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
        final reconciliationDifference =
            report.openingCash + report.netChangeInCash - report.closingCash;
        final reconciled = reconciliationDifference.abs() <= 0.009;
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _FinancialReportTitle(
                title: tr.text('cash_flow_statement'),
                subtitle: _accountingUiText(
                  context,
                  'عن الفترة ${_dateText(from)} → ${_dateText(to)}',
                  'For the period ${_dateText(from)} → ${_dateText(to)}',
                  'Pour la période ${_dateText(from)} → ${_dateText(to)}',
                ),
              ),
              const SizedBox(height: 12),
              _ReportBalanceBanner(
                isBalanced: reconciled,
                balancedText: _accountingUiText(
                    context, 'التدفقات النقدية متصالحة مع الرصيد', 'Cash flow reconciles to closing cash', 'Les flux de trésorerie sont rapprochés'),
                warningText: _accountingUiText(
                  context,
                  'فرق المصالحة النقدية ${_money(store, reconciliationDifference)}',
                  'Cash reconciliation difference ${_money(store, reconciliationDifference)}',
                  'Écart de rapprochement de trésorerie ${_money(store, reconciliationDifference)}',
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _FinancialSummaryChip(
                    label: tr.text('opening_cash_balance'),
                    value: _money(store, report.openingCash),
                  ),
                  _FinancialSummaryChip(
                    label: tr.text('net_change_in_cash'),
                    value: _money(store, report.netChangeInCash),
                  ),
                  _FinancialSummaryChip(
                    label: tr.text('closing_cash_balance'),
                    value: _money(store, report.closingCash),
                    emphasized: true,
                  ),
                ],
              ),
              const SizedBox(height: 18),
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
              Text(
                tr.text('cash_flow_details'),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (report.lines.length > _kCashFlowDetailRowLimit)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    tr.format('cash_flow_details_limit_notice', {
                      'count': _kCashFlowDetailRowLimit,
                    }),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
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
                      DataColumn(label: Text(_accountingUiText(context, 'القيد', 'Journal', 'Écriture'))),
                    ],
                    rows: [
                      for (final line
                          in report.lines.take(_kCashFlowDetailRowLimit))
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
                          DataCell(IconButton(
                            tooltip: _accountingUiText(context, 'عرض القيد', 'View journal', 'Voir l’écriture'),
                            onPressed: () => _showJournalDrillDown(
                              context,
                              store: store,
                              entryNo: line.entryNo,
                            ),
                            icon: const Icon(Icons.open_in_new, size: 18),
                          )),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
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
            const Divider(height: 12),
            _StatementLine(
                label: tr.text('net_cash_flow'),
                value: _money(store, net),
                highlight: true),
          ],
        ),
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
  const _TaxReportTab({
    required this.store,
    required this.from,
    required this.to,
  });

  final AppStore store;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return _CachedFuturePanel<TaxReport>(
      store: store,
      cacheKey: 'tax_report|${from.toIso8601String()}|${to.toIso8601String()}',
      loadFuture: () => AccountingService.taxReport(from: from, to: to),
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
  int _lastSeenRevision = -1;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _lastSeenRevision = widget.store.accounting.revision;
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

  void _refresh({bool force = false}) {
    if (!mounted) return;
    final revision = widget.store.accounting.revision;
    if (!force && revision == _lastSeenRevision) return;
    _lastSeenRevision = revision;
    setState(() => _future = _load());
  }

  @override
  void dispose() {
    widget.store.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _createCashLocationDialog(
      {String initialType = 'cash_drawer'}) async {
    widget.store.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final name = TextEditingController();
    final notes = TextEditingController();
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
                if (selectedType == 'cash_drawer') ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: bindToCurrentDevice,
                    title: Text(tr.text('link_drawer_current_device')),
                    subtitle: Text(currentDeviceId.isEmpty
                        ? tr.text('no_device_id_available')
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
        type: selectedType,
        isDefault: isDefault,
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
    if (!mounted) return;
    await _showJournalDrillDown(
      context,
      store: widget.store,
      entryId: item.referenceId,
      referenceType: 'cash_transfer',
      referenceId: item.id,
      referenceNo: item.name,
    );
  }

  Future<void> _openingBalancesDialog() async {
    widget.store.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final locations = await AccountingService.listActiveCashLocations();
    if (!mounted) return;
    if (locations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('no_cash_locations'))),
      );
      return;
    }
    final amount = TextEditingController();
    final notes = TextEditingController();
    var selectedId = locations.first.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.text('opening_balances')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(tr.text('opening_balances_desc')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedId,
                decoration:
                    InputDecoration(labelText: tr.text('cash_location')),
                items: locations
                    .map((item) => DropdownMenuItem<String>(
                          value: item.id,
                          child: Text(_localizedAccountingName(item.name, tr)),
                        ))
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => selectedId = value ?? selectedId),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    InputDecoration(labelText: tr.text('opening_balance')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notes,
                decoration: InputDecoration(labelText: tr.text('notes')),
              ),
              const SizedBox(height: 8),
              Text(tr.text('opening_balance_once_hint'),
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr.text('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr.text('save'))),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final value = double.tryParse(amount.text.trim()) ?? 0;
    if (value <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr.text('positive_amount_required'))));
      }
      return;
    }
    try {
      final user = widget.store.activeUser;
      await AccountingService.recordOpeningCashLocationBalance(
        cashLocationId: selectedId,
        amount: value,
        storeId: widget.store.appIdentity.storeId,
        branchId: widget.store.appIdentity.branchId,
        createdBy: user?.fullName.trim().isNotEmpty == true
            ? user!.fullName.trim()
            : widget.store.currentRole,
        notes: notes.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr.text('opening_balance_saved'))));
        _refresh(force: true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      amount.dispose();
      notes.dispose();
    }
  }

  Future<void> _manualJournalDialog() async {
    widget.store.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final description =
        TextEditingController(text: tr.text('manual_journal_entry'));
    final debitAmount = TextEditingController(text: '0');
    final creditAmount = TextEditingController(text: '0');
    final accounts = (await AccountingService.listAccounts())
        .where((account) => account.isPostable)
        .toList();
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
    widget.store.requirePermission(AppPermission.accountingManage);
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
    widget.store.requirePermission(AppPermission.accountingManage);
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
    widget.store.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final code = TextEditingController();
    final name = TextEditingController();
    final category = TextEditingController(text: tr.text('equipment'));
    final purchaseValue = TextEditingController(text: '0');
    final usefulLifeMonths = TextEditingController(text: '0');
    final notes = TextEditingController();
    final accounts = (await AccountingService.listAccounts())
        .where((account) => account.isPostable)
        .toList();
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
    widget.store.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final name = TextEditingController();
    var type = 'bank';
    var isDefault = false;
    final accounts = (await AccountingService.listAccounts())
        .where((account) => account.isPostable)
        .toList();
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
    widget.store.requirePermission(AppPermission.accountingManage);
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
    widget.store.requirePermission(AppPermission.accountingManage);
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

  Future<void> _settleCheque(AdvancedAccountingItem item) async {
    widget.store.requirePermission(AppPermission.accountingManage);
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
    widget.store.requirePermission(AppPermission.accountingManage);
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
    widget.store.requirePermission(AppPermission.accountingManage);
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
    widget.store.requirePermission(AppPermission.accountingManage);
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
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
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
                      Text(
                        _accountingUiText(context, 'رقابة النقد والبنوك',
                            'Cash & bank control', 'Contrôle caisse et banque'),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _accountingUiText(
                          context,
                          'هذه الصفحة للمراجعة والتحليل فقط. عمليات فتح وإغلاق الوردية والتحويلات النقدية اليومية تُنفذ من صفحة الصندوق.',
                          'This page is read-only for review and analysis. Daily drawer opening/closing and cash transfers are performed from the Cash page.',
                          'Cette page est réservée au contrôle et à l’analyse. Les opérations quotidiennes de caisse sont effectuées depuis la page Caisse.',
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
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
                      label: Text(_accountingUiText(context, 'عرض القيد',
                          'View journal', 'Voir l’écriture')))
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
                            onPressed: canManageAccounting
                                ? _openingBalancesDialog
                                : null,
                            icon: const Icon(Icons.account_balance_outlined),
                            label: Text(tr.text('opening_balances'))),
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
                    label: Text(_accountingUiText(context, 'عرض القيد', 'View journal', 'Voir l’écriture')))
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
                      item.accountCode,
                      _localizedAccountingName(item.accountName, tr),
                      _localizedAccountingNote(item.notes, tr),
                    ].where((value) => value.trim().isNotEmpty).join(' • ')),
                    trailing: Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (item.status.trim().isNotEmpty)
                          _AccountingStatusBadge(status: item.status),
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

class _AccountingRolesTab extends StatefulWidget {
  const _AccountingRolesTab({required this.store});

  final AppStore store;

  @override
  State<_AccountingRolesTab> createState() => _AccountingRolesTabState();
}

class _AccountingRolesTabState extends State<_AccountingRolesTab> {
  late Future<_AccountingRolesData> _future;
  int _lastSeenRevision = -1;
  static final RevisionKeyCache<Future<_AccountingRolesData>> _futureCache =
      RevisionKeyCache<Future<_AccountingRolesData>>();

  static const List<String> _groupOrder = <String>[
    'core',
    'inventory',
    'sales',
    'expenses',
    'inventory_adjustments',
    'manufacturing',
    'cash',
    'parties',
    'equity',
    'fixed_assets',
    'tax',
  ];

  @override
  void initState() {
    super.initState();
    _future = _loadCached();
    _lastSeenRevision = widget.store.accounting.revision;
    widget.store.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _AccountingRolesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_refresh);
      widget.store.addListener(_refresh);
      _lastSeenRevision = widget.store.accounting.revision;
    }
  }

  Future<_AccountingRolesData> _load() async {
    final results = await Future.wait<Object>([
      AccountingService.listAccounts(activeOnly: true),
      AccountingService.readAccountRoleMap(),
      AccountingService.validateAccountRoleConfiguration(),
    ]);
    return _AccountingRolesData(
      accounts: (results[0] as List<AccountingAccount>)
          .where((account) => account.isActive && account.isPostable)
          .toList(),
      roles: results[1] as Map<String, String>,
      validationErrors: results[2] as List<String>,
    );
  }

  Future<_AccountingRolesData> _loadCached() {
    return _futureCache.getOrCompute(
      widget.store.accounting.revision,
      widget.store.appIdentity.storeId,
      _load,
    );
  }

  Future<void> _updateRole(String roleKey, String accountId) async {
    widget.store.requirePermission(AppPermission.accountingManage);
    await AccountingService.updateAccountRole(
      roleKey: roleKey,
      accountId: accountId,
    );
    if (!mounted) return;
    _refresh(force: true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(AppLocalizations.of(context)
              .text('account_role_mapping_updated'))),
    );
  }

  void _refresh({bool force = false}) {
    if (!mounted) return;
    final revision = widget.store.accounting.revision;
    if (!force && revision == _lastSeenRevision) return;
    _lastSeenRevision = revision;
    setState(() => _future = _loadCached());
  }

  @override
  void dispose() {
    widget.store.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return FutureBuilder<_AccountingRolesData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
        final data = snapshot.data ??
            const _AccountingRolesData(
              accounts: <AccountingAccount>[],
              roles: <String, String>{},
              validationErrors: <String>[],
            );
        final canManage =
            widget.store.hasPermission(AppPermission.accountingManage);
        final children = <Widget>[
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr.text('account_role_mapping_title'),
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr.text('account_role_mapping_desc'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  if (data.validationErrors.isEmpty)
                    Row(
                      children: [
                        const Icon(Icons.verified_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(tr.text('account_roles_valid'))),
                      ],
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .errorContainer
                            .withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(data.validationErrors.join('\n')),
                    ),
                  if (!canManage) ...[
                    const SizedBox(height: 8),
                    Text(
                      tr.text('account_roles_read_only'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ];

        for (final group in _groupOrder) {
          final roles = AccountingAccountRole.all
              .where((role) => role.group == group)
              .toList(growable: false);
          if (roles.isEmpty) continue;
          children.add(
            Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Row(
                      children: [
                        Icon(_accountRoleGroupIcon(group), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _accountRoleGroupTitle(group),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  for (var i = 0; i < roles.length; i++) ...[
                    _AccountingSettingRow(
                      definition: _AccountingSettingDefinition(
                        titleKey: roles[i].titleAr,
                        subtitleKey: roles[i].descriptionAr,
                        icon: _accountRoleGroupIcon(group),
                      ),
                      accounts: data.accounts,
                      selectedAccountId: data.roles[roles[i].settingKey] ?? '',
                      onChanged: canManage
                          ? (accountId) => _updateRole(roles[i].key, accountId)
                          : null,
                    ),
                    if (i != roles.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: children.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, index) => children[index],
        );
      },
    );
  }
}

class _AccountingRolesData {
  const _AccountingRolesData({
    required this.accounts,
    required this.roles,
    required this.validationErrors,
  });

  final List<AccountingAccount> accounts;
  final Map<String, String> roles;
  final List<String> validationErrors;
}

String _accountRoleGroupTitle(String group) => switch (group) {
      'core' => 'الحسابات الأساسية',
      'inventory' => 'المخزون',
      'sales' => 'المبيعات والإيرادات',
      'expenses' => 'المصروفات',
      'inventory_adjustments' => 'فروقات وتسويات المخزون',
      'manufacturing' => 'التصنيع',
      'cash' => 'الصندوق والتسويات النقدية',
      'parties' => 'العملاء والموردون',
      'equity' => 'حقوق الملكية',
      'fixed_assets' => 'الأصول الثابتة',
      'tax' => 'الضرائب',
      _ => group,
    };

IconData _accountRoleGroupIcon(String group) => switch (group) {
      'core' => Icons.hub_outlined,
      'inventory' => Icons.inventory_2_outlined,
      'sales' => Icons.point_of_sale_outlined,
      'expenses' => Icons.receipt_long_outlined,
      'inventory_adjustments' => Icons.tune_outlined,
      'manufacturing' => Icons.precision_manufacturing_outlined,
      'cash' => Icons.payments_outlined,
      'parties' => Icons.people_alt_outlined,
      'equity' => Icons.account_balance_wallet_outlined,
      'fixed_assets' => Icons.business_center_outlined,
      'tax' => Icons.percent_outlined,
      _ => Icons.account_tree_outlined,
    };

class _AccountingSettingsTab extends StatefulWidget {
  const _AccountingSettingsTab({required this.store});

  final AppStore store;

  @override
  State<_AccountingSettingsTab> createState() => _AccountingSettingsTabState();
}

class _AccountingSettingsTabState extends State<_AccountingSettingsTab> {
  late Future<_AccountingSettingsData> _future;
  int _lastSeenRevision = -1;
  static final RevisionKeyCache<Future<_AccountingSettingsData>> _futureCache =
      RevisionKeyCache<Future<_AccountingSettingsData>>();

  @override
  void initState() {
    super.initState();
    _future = _loadCached();
    _lastSeenRevision = widget.store.accounting.revision;
    widget.store.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _AccountingSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_refresh);
      widget.store.addListener(_refresh);
      _lastSeenRevision = widget.store.accounting.revision;
    }
  }

  Future<_AccountingSettingsData> _load() async {
    final legacyRate = await AccountingService.readDefaultVatRatePercent();
    final storeProfile = widget.store.storeProfile;
    final profiles = <TaxProfile>[
      for (final profile in storeProfile.taxProfiles)
        if (storeProfile.taxConfigurationVersion <= 0 &&
            profile.id == TaxProfile.standardId)
          profile.copyWith(ratePercent: legacyRate)
        else
          profile,
    ];
    final standard = profiles.where(
      (item) => item.id == TaxProfile.standardId,
    );
    return _AccountingSettingsData(
      vatRatePercent:
          standard.isEmpty ? legacyRate : standard.first.ratePercent,
      profiles: profiles,
      defaultTaxProfileId: storeProfile.defaultTaxProfileId,
    );
  }

  Future<void> _updateVatRate(double ratePercent) async {
    widget.store.requirePermission(AppPermission.accountingManage);
    await widget.store.updateDefaultTaxRatePercent(ratePercent);
    if (!mounted) return;
    _refresh(force: true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context).text('accounting_setting_updated'),
        ),
      ),
    );
  }

  Future<void> _updateDefaultTaxProfile(
    _AccountingSettingsData data,
    String profileId,
  ) async {
    widget.store.requirePermission(AppPermission.accountingManage);
    await widget.store.updateTaxConfiguration(
      profiles: data.profiles,
      defaultTaxProfileId: profileId,
    );
    if (!mounted) return;
    _refresh(force: true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context).text('accounting_setting_updated'),
        ),
      ),
    );
  }

  Future<_AccountingSettingsData> _loadCached() {
    return _futureCache.getOrCompute(
      widget.store.accounting.revision,
      widget.store.appIdentity.storeId,
      _load,
    );
  }

  void _refresh({bool force = false}) {
    if (!mounted) return;
    final revision = widget.store.accounting.revision;
    if (!force && revision == _lastSeenRevision) return;
    _lastSeenRevision = revision;
    setState(() => _future = _loadCached());
  }

  @override
  void dispose() {
    widget.store.removeListener(_refresh);
    super.dispose();
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
        final data = snapshot.data ?? const _AccountingSettingsData(
          vatRatePercent: 0,
          profiles: TaxProfile.defaults,
          defaultTaxProfileId: TaxProfile.standardId,
        );
        final canManageAccounting =
            widget.store.hasPermission(AppPermission.accountingManage);
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                _accountingUiText(context, 'إعدادات المحاسبة العامة',
                    'General accounting settings', 'Paramètres comptables'),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                _accountingUiText(
                  context,
                  'تم توحيد ربط الحسابات ضمن تبويب «ربط الحسابات». إعدادات الحسابات الافتراضية القديمة ما زالت محفوظة داخلياً للتوافق فقط ولا يتم تعديلها من هذه الواجهة.',
                  'Account mapping is now managed only from the Account Roles tab. Legacy default-account values remain internal for compatibility and are no longer edited here.',
                  'Le rattachement des comptes est désormais géré uniquement dans l’onglet des rôles comptables. Les anciennes valeurs restent internes pour compatibilité.',
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_tree_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _accountingUiText(
                          context,
                          'Account Roles هي المرجع الرسمي لتوجيه القيود المحاسبية.',
                          'Account Roles are the official source for accounting posting mappings.',
                          'Les rôles comptables sont la source officielle du paramétrage des imputations.',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 28),
              _VatRateSettingRow(
                ratePercent: data.vatRatePercent,
                enabled: canManageAccounting,
                onChanged: _updateVatRate,
              ),
              const SizedBox(height: 8),
              _TaxProfilesSettingCard(
                profiles: data.profiles,
                defaultTaxProfileId: data.defaultTaxProfileId,
                enabled: canManageAccounting,
                onDefaultChanged: (value) =>
                    _updateDefaultTaxProfile(data, value),
              ),
              if (!canManageAccounting) ...[
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)
                      .text('accounting_read_only_permission'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AccountingSettingsData {
  const _AccountingSettingsData({
    required this.vatRatePercent,
    required this.profiles,
    required this.defaultTaxProfileId,
  });

  final double vatRatePercent;
  final List<TaxProfile> profiles;
  final String defaultTaxProfileId;
}

class _TaxProfilesSettingCard extends StatelessWidget {
  const _TaxProfilesSettingCard({
    required this.profiles,
    required this.defaultTaxProfileId,
    required this.enabled,
    required this.onDefaultChanged,
  });

  final List<TaxProfile> profiles;
  final String defaultTaxProfileId;
  final bool enabled;
  final ValueChanged<String> onDefaultChanged;

  String _treatmentLabel(BuildContext context, TaxTreatment treatment) {
    final tr = AppLocalizations.of(context);
    return switch (treatment) {
      TaxTreatment.standard => tr.text('tax_profile_standard'),
      TaxTreatment.zeroRated => tr.text('tax_profile_zero_rated'),
      TaxTreatment.exempt => tr.text('tax_profile_exempt'),
      TaxTreatment.outOfScope => tr.text('tax_profile_out_of_scope'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final active = profiles.where((item) => item.isActive).toList(growable: false);
    final selected = active.any((item) => item.id == defaultTaxProfileId)
        ? defaultTaxProfileId
        : (active.isEmpty ? null : active.first.id);
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr.text('tax_profiles'),
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              tr.text('tax_profiles_desc'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            for (final profile in active)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  profile.treatment == TaxTreatment.exempt
                      ? Icons.block_outlined
                      : Icons.percent_outlined,
                ),
                title: Text(profile.name),
                subtitle: Text(
                  '${profile.code} • ${_treatmentLabel(context, profile.treatment)}'
                  '${profile.treatment == TaxTreatment.standard ? ' • ${profile.ratePercent.toStringAsFixed(profile.ratePercent == profile.ratePercent.roundToDouble() ? 0 : 2)}%' : ''}',
                ),
              ),
            if (active.isNotEmpty) ...[
              const Divider(height: 20),
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: InputDecoration(
                  labelText: tr.text('default_tax_profile'),
                  helperText: tr.text('default_tax_profile_desc'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final profile in active)
                    DropdownMenuItem<String>(
                      value: profile.id,
                      child: Text('${profile.name} (${profile.code})'),
                    ),
                ],
                onChanged: enabled
                    ? (value) {
                        if (value != null && value != selected) {
                          onDefaultChanged(value);
                        }
                      }
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountingSettingDefinition {
  const _AccountingSettingDefinition(
      {required this.titleKey,
      required this.subtitleKey,
      required this.icon});

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
    final selectedExists = accounts.any(
        (account) => account.id == selectedAccountId && account.isPostable);
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
    final foreground = isBalanced
        ? scheme.onPrimaryContainer
        : scheme.onErrorContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            isBalanced ? Icons.check_circle_outline : Icons.warning_amber_rounded,
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

  final AppStore store;
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
                _accountingUiText(context, 'تفاصيل الحسابات',
                    'Account details', 'Détails des comptes'),
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
  final AppStore store;
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

  final AppStore store;
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
