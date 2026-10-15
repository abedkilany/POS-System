part of 'dashboard_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.store});

  final AppStore store;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const DashboardSnapshotService _service = DashboardSnapshotService();
  DashboardState? _state;
  bool _refreshInProgress = false;
  bool _firstReadyMarked = false;
  bool _suppressStartupRefresh = true;
  Timer? _refreshDebounce;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_handleStoreChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bootstrapDashboard();
    });
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_handleStoreChanged);
      widget.store.addListener(_handleStoreChanged);
      _suppressStartupRefresh = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _bootstrapDashboard(forceRefresh: true);
      });
    }
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    widget.store.removeListener(_handleStoreChanged);
    super.dispose();
  }

  void _handleStoreChanged() {
    if (!mounted) return;
    final hasHydratedState = _state?.isHydrated ?? false;
    if (hasHydratedState && !widget.store.runtime.isReady) return;
    if (widget.store.runtime.isReady && _suppressStartupRefresh) {
      _suppressStartupRefresh = false;
      if (hasHydratedState) return;
    }
    _scheduleRefresh();
  }

  Future<void> _bootstrapDashboard({bool forceRefresh = false}) async {
    final cachedSummary = await _service.loadCachedSummary(
      storeId: widget.store.runtime.identity.storeId,
    );
    if (!mounted) return;
    if (cachedSummary != null) {
      final cachedState = await _service.buildQuickStateFromCachedSummary(
        widget.store,
        cachedSummary,
      );
      if (!mounted) return;
      setState(() {
        _state = cachedState;
      });
      if (!_firstReadyMarked) {
        _firstReadyMarked = true;
        StartupTimingService.markPageReady(
          'DashboardPage',
          pageLabel: 'Dashboard',
          details: 'cached_quick_ready',
        );
      }
    }

    if (cachedSummary == null) {
      _scheduleRefresh(immediate: true);
    } else if (forceRefresh) {
      _scheduleRefresh();
    } else {
      _scheduleRefresh();
    }
  }

  void _scheduleRefresh({bool immediate = false}) {
    if (!mounted) return;
    if (_refreshInProgress) return;
    if ((_state?.isHydrated ?? false) && !widget.store.runtime.isReady) {
      return;
    }
    _refreshDebounce?.cancel();
    final delay = immediate ? Duration.zero : const Duration(seconds: 1);
    _refreshDebounce = Timer(delay, () {
      if (!mounted || _refreshInProgress) return;
      _refreshInProgress = true;
      unawaited(_refreshSnapshot());
    });
  }

  Future<void> _refreshSnapshot() async {
    try {
      final state = await _service.buildState(widget.store);
      if (!mounted) return;
      setState(() {
        _state = state;
      });
      if (!_firstReadyMarked) {
        _firstReadyMarked = true;
        StartupTimingService.markPageReady(
          'DashboardPage',
          pageLabel: 'Dashboard',
          details: 'fresh_snapshot_ready',
        );
      } else {
        StartupTimingService.markPageReady(
          'DashboardPage',
          pageLabel: 'Dashboard',
          details: 'dashboard_refreshed',
        );
      }
    } finally {
      _refreshInProgress = false;
    }
  }

  void _openQuickActionPage(String title, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _QuickActionFrame(
          title: title,
          child: page,
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    return DateFormat('yyyy-MM-dd').format(value.toLocal());
  }

  String _formatDateTime(DateTime value) {
    return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
  }

  String _money(double value) {
    return formatUsdReferenceAmount(value, widget.store.runtime.profile);
  }

  IconData _operationIcon(DashboardOperationType type) {
    return switch (type) {
      DashboardOperationType.sale => Icons.receipt_long_outlined,
      DashboardOperationType.purchase => Icons.shopping_cart_outlined,
      DashboardOperationType.expense => Icons.money_off_outlined,
      DashboardOperationType.payment => Icons.payments_outlined,
      DashboardOperationType.stockMovement => Icons.inventory_2_outlined,
      DashboardOperationType.other => Icons.bolt_outlined,
    };
  }

  Color _statusColor(BuildContext context, DashboardStatusLevel level) {
    final scheme = Theme.of(context).colorScheme;
    return switch (level) {
      DashboardStatusLevel.healthy => const Color(0xFF16A34A),
      DashboardStatusLevel.warning => const Color(0xFFF59E0B),
      DashboardStatusLevel.danger => scheme.error,
      DashboardStatusLevel.neutral => scheme.outline,
    };
  }

  List<_QuickAction> _quickActions(AppLocalizations tr) {
    return <_QuickAction>[
      _QuickAction(
        label: tr.text('sale_page'),
        icon: Icons.add_card_outlined,
        color: const Color(0xFF2563EB),
        onPressed: () => _openQuickActionPage(
          tr.text('sale_page'),
          SalesPage(store: widget.store),
        ),
      ),
      _QuickAction(
        label: tr.text('add_product'),
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFF0EA5E9),
        onPressed: () => _openQuickActionPage(
          tr.text('add_product'),
          ProductsPage(store: widget.store),
        ),
      ),
      _QuickAction(
        label: tr.text('new_purchase'),
        icon: Icons.shopping_bag_outlined,
        color: const Color(0xFFEF4444),
        onPressed: () => _openQuickActionPage(
          tr.text('new_purchase'),
          PurchasesPage(store: widget.store),
        ),
      ),
      _QuickAction(
        label: tr.text('receive_payment'),
        icon: Icons.south_west_rounded,
        color: const Color(0xFF22C55E),
        onPressed: () => _openQuickActionPage(
          tr.text('receive_payment'),
          AccountingPage(store: widget.store),
        ),
      ),
      _QuickAction(
        label: tr.text('add_expense'),
        icon: Icons.north_east_rounded,
        color: const Color(0xFF6366F1),
        onPressed: () => _openQuickActionPage(
          tr.text('add_expense'),
          ExpensesPage(store: widget.store),
        ),
      ),
      _QuickAction(
        label: tr.text('reports'),
        icon: Icons.analytics_outlined,
        color: const Color(0xFF8B5CF6),
        onPressed: () => _openQuickActionPage(
          tr.text('reports'),
          ReportsPage(store: widget.store),
        ),
      ),
    ];
  }

  String _financialLabel(AppLocalizations tr, DashboardFinancialItem item) {
    return switch (item.key) {
      'cash' => tr.text('cash'),
      'bank' => tr.text('bank'),
      'cards' => tr.text('bank_card'),
      'liquidity' => tr.text('cash_bank'),
      'receivables' => tr.text('customer_receivables'),
      'payables' => tr.text('supplier_payables'),
      'inventory' => tr.text('inventory_value_report'),
      'profit' => tr.text('net_profit'),
      'expenses' => tr.text('expenses_report'),
      'purchases' => tr.text('purchases'),
      _ => item.title,
    };
  }

  String _chartValue(DashboardChartSeries series, DashboardChartItem item) {
    if (series.displayAsMoney) return _money(item.value);
    final raw = item.value.toStringAsFixed(item.value % 1 == 0 ? 0 : 1);
    return raw.replaceFirst(RegExp(r'\.0$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = _state;
    if (state == null) {
      return _DashboardScaffold(
        child: Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: _softShadow(context),
            ),
            child: const Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    }

    final allCharts = state.charts;
    final mainChart = allCharts.isNotEmpty ? allCharts.first : null;
    final leadingFinancial = state.financialSummary.take(5).toList();

    final metrics = <_KpiData>[
      _KpiData(
        title: tr.text('today_sales'),
        value: _money(state.todaySalesTotal),
        note: tr.text('dashboard_better_than_yesterday'),
        icon: Icons.shopping_cart_outlined,
        color: const Color(0xFF2563EB),
      ),
      _KpiData(
        title: tr.text('net_profit'),
        value: _money(state.todayProfitTotal),
        note: state.todayProfitTotal >= 0
            ? tr.text('dashboard_positive_profit')
            : tr.text('dashboard_negative_profit'),
        icon: Icons.trending_up_rounded,
        color: const Color(0xFF16A34A),
      ),
      _KpiData(
        title: tr.text('today_invoices'),
        value: '${state.todayInvoiceCount}',
        note: tr.text('dashboard_invoice_count_note'),
        icon: Icons.receipt_long_outlined,
        color: const Color(0xFF8B5CF6),
      ),
      _KpiData(
        title: tr.text('closing_cash_balance'),
        value: state.isHydrated ? _money(state.currentCashTotal) : '—',
        note: state.isHydrated
            ? tr.text('cash')
            : tr.text('dashboard_preparing_indicator'),
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFFF97316),
      ),
    ];

    return _DashboardScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeroHeader(
            storeName: state.storeName,
            date: _formatDate(state.generatedAt),
            title:
                tr.format('dashboard_good_morning', {'store': state.storeName}),
            subtitle: tr.text('dashboard_business_summary'),
            sales: _money(state.todaySalesTotal),
            syncStatus: state.syncStatus,
            backupStatus: state.backupStatus,
            statusColor: (level) => _statusColor(context, level),
          ),
          if (!state.isHydrated) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: PageDataLoadIndicator(
                loadedCount: 1,
                totalCount: 2,
                label: tr.text('dashboard_preparing_indicator'),
              ),
            ),
          ],
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 1100
                  ? 4
                  : width >= 760
                      ? 2
                      : 1;
              final itemWidth = (width - (columns - 1) * 14) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: metrics
                    .map(
                      (metric) => SizedBox(
                        width: itemWidth,
                        child: _KpiCard(data: metric),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 18),
          _QuickActionsPanel(actions: _quickActions(tr)),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 980;
              final chart = _MainChartPanel(
                series: mainChart,
                title: mainChart == null
                    ? tr.text('sales_chart')
                    : localizeRuntimeMessage(mainChart.title, tr),
                formatValue: mainChart == null
                    ? (_) => ''
                    : (item) => _chartValue(mainChart, item),
                emptyLabel: tr.text('no_data_available'),
              );
              final alerts = _AlertsPanel(
                title: tr.text('dashboard_alerts'),
                clearText: tr.text('dashboard_alerts_clear'),
                alerts: state.alerts,
                statusColor: (level) => _statusColor(context, level),
              );
              if (!isWide) {
                return Column(
                  children: [chart, const SizedBox(height: 18), alerts],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: chart),
                  const SizedBox(width: 18),
                  Expanded(flex: 3, child: alerts),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          _FinancialSummaryPanel(
            title: tr.text('financial_summary'),
            items: leadingFinancial,
            labelBuilder: (item) => _financialLabel(tr, item),
            moneyBuilder: (value) => _money(value),
            statusColor: (level) => _statusColor(context, level),
          ),
          const SizedBox(height: 18),
          _OperationsPanel(
            title: tr.text('latest_operations'),
            emptyText: tr.text('no_sales_desc'),
            operations: state.recentOperations,
            operationIcon: _operationIcon,
            moneyBuilder: _money,
            dateBuilder: _formatDateTime,
          ),
          const SizedBox(height: 18),
          _SystemStatusPanel(
            title: tr.text('system_status'),
            items: [
              _SystemStatusData(
                title: tr.text('sync_status'),
                value: localizeRuntimeMessage(state.syncStatus.title, tr),
                icon: Icons.sync_rounded,
                color: _statusColor(context, state.syncStatus.level),
              ),
              _SystemStatusData(
                title: tr.text('current_backup_status'),
                value: localizeRuntimeMessage(state.backupStatus.title, tr),
                icon: Icons.sync,
                color: _statusColor(context, state.backupStatus.level),
              ),
              _SystemStatusData(
                title: tr.text('products'),
                value: '${widget.store.catalog.allProductsForDiagnostics.length}',
                icon: Icons.inventory_2_outlined,
                color: const Color(0xFF2563EB),
              ),
              _SystemStatusData(
                title: tr.text('customers'),
                value: '${widget.store.commerce.allCustomersForDiagnostics.length}',
                icon: Icons.people_alt_outlined,
                color: const Color(0xFF16A34A),
              ),
              _SystemStatusData(
                title: tr.text('low_stock_alerts'),
                value: '${state.lowStockCount}',
                icon: Icons.warning_amber_rounded,
                color: state.lowStockCount > 0
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF16A34A),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardScaffold extends StatelessWidget {
  const _DashboardScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primary.withValues(alpha: 0.055),
            scheme.surface,
            scheme.surface,
          ],
        ),
      ),
      child: ListView(
        padding: VentioResponsive.pageInsets(context).add(
          const EdgeInsets.only(bottom: 24),
        ),
        children: [child],
      ),
    );
  }
}

class _QuickActionFrame extends StatelessWidget {
  const _QuickActionFrame({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: SafeArea(
        child: child,
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.storeName,
    required this.date,
    required this.title,
    required this.subtitle,
    required this.sales,
    required this.syncStatus,
    required this.backupStatus,
    required this.statusColor,
  });

  final String storeName;
  final String date;
  final String title;
  final String subtitle;
  final String sales;
  final DashboardHealthSnapshot syncStatus;
  final DashboardHealthSnapshot backupStatus;
  final Color Function(DashboardStatusLevel level) statusColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tr = AppLocalizations.of(context);
    final scheme = theme.colorScheme;
    return _PremiumSurface(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 780;
          final intro = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        colors: [
                          scheme.primary,
                          scheme.primary.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _StatusPill(
                    title: localizeRuntimeMessage(syncStatus.title, tr),
                    subtitle: localizeRuntimeMessage(syncStatus.detail, tr),
                    icon: Icons.sync_rounded,
                    color: statusColor(syncStatus.level),
                  ),
                  _StatusPill(
                    title: localizeRuntimeMessage(backupStatus.title, tr),
                    subtitle: localizeRuntimeMessage(backupStatus.detail, tr),
                    icon: Icons.sync,
                    color: statusColor(backupStatus.level),
                  ),
                ],
              ),
            ],
          );

          final performance = Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_graph_rounded, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        storeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  sales,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  date,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [intro, const SizedBox(height: 18), performance],
            );
          }

          return Row(
            children: [
              Expanded(flex: 7, child: intro),
              const SizedBox(width: 22),
              Expanded(flex: 3, child: performance),
            ],
          );
        },
      ),
    );
  }
}

class _KpiData {
  const _KpiData({
    required this.title,
    required this.value,
    required this.note,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String note;
  final IconData icon;
  final Color color;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});

  final _KpiData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _PremiumSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBubble(icon: data.icon, color: data.color),
              const Spacer(),
              Icon(Icons.north_east_rounded, color: data.color, size: 18),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            data.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            data.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            data.note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: data.color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
}
