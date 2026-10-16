part of 'accounting_page.dart';

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
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: AppLocalizations.of(context).text('refresh'),
          onPressed: onRefresh,
          visualDensity: VisualDensity.compact,
          iconSize: 20,
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

  final ApplicationSession store;
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

  final ApplicationSession store;

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

  final ApplicationSession store;
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
          title: _accountingUiText(
              context, 'مصاريف الشهر', 'Month expenses', 'Charges du mois'),
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

  final ApplicationSession store;
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
                    formatUsdReferenceAmount(metric.amount, store.runtime.profile),
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
    final tabs = <({IconData icon, String label})>[
      (
        icon: Icons.people_alt_outlined,
        label: _accountingUiText(
            context, 'الحسابات المساعدة', 'Subledgers', 'Comptes auxiliaires'),
      ),
      (
        icon: Icons.menu_book_outlined,
        label: _accountingUiText(context, 'العمليات المحاسبية',
            'Accounting operations', 'Opérations comptables'),
      ),
      (
        icon: Icons.account_balance_wallet_outlined,
        label: _accountingUiText(
            context, 'النقد والبنوك', 'Cash & banks', 'Trésorerie et banques'),
      ),
      (
        icon: Icons.assessment_outlined,
        label: _accountingUiText(context, 'التقارير المالية',
            'Financial reports', 'Rapports financiers'),
      ),
      (
        icon: Icons.admin_panel_settings_outlined,
        label: _accountingUiText(
            context, 'الإدارة', 'Administration', 'Administration'),
      ),
    ];

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: TabBar(
          controller: controller,
          isScrollable: true,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 12),
          tabs: [
            for (final item in tabs)
              Tab(
                height: 40,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(item.icon, size: 18),
                    const SizedBox(width: 6),
                    Text(item.label),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AccountsAccountingGroup extends StatelessWidget {
  const _AccountsAccountingGroup({required this.store, required this.query});

  final ApplicationSession store;
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
                      builder: (_) => _AccountingPrintablePage(
                        store: store,
                        title: tr.text('customers'),
                        child: _AccountsTab(
                          store: store,
                          query: query,
                          accountType: 'customer',
                        ),
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 1,
                      builder: (_) => _AccountingPrintablePage(
                        store: store,
                        title: tr.text('suppliers'),
                        child: _AccountsTab(
                          store: store,
                          query: query,
                          accountType: 'supplier',
                        ),
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 2,
                      builder: (_) => _AccountingPrintablePage(
                        store: store,
                        title: tr.text('aging_reports'),
                        child: _AgingReportsTab(store: store, query: query),
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 3,
                      builder: (_) => _AccountingPrintablePage(
                        store: store,
                        title: tr.text('recent_transactions'),
                        child: _TransactionsTab(
                          store: store,
                          query: query,
                          cashOnly: false,
                        ),
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

  final ApplicationSession store;
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
                      builder: (_) => _AccountingPrintablePage(
                        store: store,
                        title: _accountingUiText(context, 'القيود اليومية',
                            'Journal entries', 'Écritures'),
                        child: _JournalEntriesTab(store: store, query: query),
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 1,
                      builder: (_) => _AccountingPrintablePage(
                        store: store,
                        title: tr.text('general_ledger'),
                        child: _GeneralLedgerTab(store: store, query: query),
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 2,
                      builder: (_) => _AccountingPrintablePage(
                        store: store,
                        title: tr.text('chart_of_accounts'),
                        child: _ChartOfAccountsTab(store: store, query: query),
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

class _CashAccountingGroup extends StatelessWidget {
  const _CashAccountingGroup({required this.store, required this.query});

  final ApplicationSession store;
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
                      builder: (_) => _AccountingPrintablePage(
                        store: store,
                        title: tr.text('cash_movement'),
                        child: _CashLedgerTransactionsTab(
                          store: store,
                          query: query,
                        ),
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 1,
                      builder: (_) => _AccountingPrintablePage(
                        store: store,
                        title: _accountingUiText(context, 'رقابة النقد',
                            'Cash control', 'Contrôle de caisse'),
                        child: _AdvancedAccountingTab(
                          store: store,
                          cashOnly: true,
                        ),
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 2,
                      builder: (_) => _AccountingPrintablePage(
                        store: store,
                        title: tr.text('cash_bank'),
                        child: _CashBankReportTab(store: store),
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
