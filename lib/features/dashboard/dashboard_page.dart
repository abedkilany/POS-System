import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/responsive.dart';
import '../../data/app_store.dart';
import '../accounting/accounting_page.dart';
import '../expenses/expenses_page.dart';
import '../products/products_page.dart';
import '../purchases/purchases_page.dart';
import '../reports/reports_page.dart';
import '../sales/sales_page.dart';
import 'dashboard_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.store});

  final AppStore store;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const DashboardService _service = DashboardService();

  late Future<DashboardState> _stateFuture;

  @override
  void initState() {
    super.initState();
    _stateFuture = _loadState();
    widget.store.addListener(_handleStoreChanged);
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_handleStoreChanged);
      widget.store.addListener(_handleStoreChanged);
      _stateFuture = _loadState();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStoreChanged);
    super.dispose();
  }

  void _handleStoreChanged() {
    if (!mounted) return;
    setState(() => _stateFuture = _loadState());
  }

  Future<DashboardState> _loadState() => _service.buildState(widget.store);

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

  String _t(AppLocalizations tr, String key, String ar, String en) {
    final value = tr.text(key);
    if (value != key) return value;
    return tr.isArabic ? ar : en;
  }

  String _formatDate(DateTime value) {
    return DateFormat('yyyy-MM-dd').format(value.toLocal());
  }

  String _formatDateTime(DateTime value) {
    return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
  }

  String _money(double value) {
    return formatUsdReferenceAmount(value, widget.store.storeProfile);
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

    return FutureBuilder<DashboardState>(
      future: _stateFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
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

        if (snapshot.hasError) {
          return _DashboardScaffold(
            child: _PremiumSurface(
              padding: const EdgeInsets.all(24),
              child: Text(snapshot.error.toString()),
            ),
          );
        }

        final state = snapshot.data;
        if (state == null) return const SizedBox.shrink();

        final allCharts = state.charts;
        final mainChart = allCharts.isNotEmpty ? allCharts.first : null;
        final secondaryCharts = allCharts.skip(1).take(2).toList();
        final leadingFinancial = state.financialSummary.take(5).toList();

        final metrics = <_KpiData>[
          _KpiData(
            title: tr.text('today_sales'),
            value: _money(state.todaySalesTotal),
            note: _t(tr, 'dashboard_better_than_yesterday', 'أداء اليوم', 'Today'),
            icon: Icons.shopping_cart_outlined,
            color: const Color(0xFF2563EB),
          ),
          _KpiData(
            title: tr.text('net_profit'),
            value: _money(state.todayProfitTotal),
            note: state.todayProfitTotal >= 0
                ? _t(tr, 'dashboard_positive_profit', 'ربح موجب', 'Positive profit')
                : _t(tr, 'dashboard_negative_profit', 'تحتاج مراجعة', 'Needs review'),
            icon: Icons.trending_up_rounded,
            color: const Color(0xFF16A34A),
          ),
          _KpiData(
            title: tr.text('today_invoices'),
            value: '${state.todayInvoiceCount}',
            note: _t(tr, 'dashboard_invoice_count_note', 'فاتورة اليوم', 'Invoices today'),
            icon: Icons.receipt_long_outlined,
            color: const Color(0xFF8B5CF6),
          ),
          _KpiData(
            title: tr.text('closing_cash_balance'),
            value: _money(state.currentCashTotal),
            note: tr.text('cash'),
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
                title: _t(
                  tr,
                  'dashboard_good_morning',
                  'صباح الخير، ${state.storeName}',
                  'Good morning, ${state.storeName}',
                ),
                subtitle: _t(
                  tr,
                  'dashboard_business_summary',
                  'إليك ملخص أعمالك لهذا اليوم',
                  'Here is your business summary for today',
                ),
                sales: _money(state.todaySalesTotal),
                syncStatus: state.syncStatus,
                backupStatus: state.backupStatus,
                statusColor: (level) => _statusColor(context, level),
              ),
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
                    title: mainChart?.title ??
                        _t(tr, 'sales_chart', 'مؤشر المبيعات', 'Sales trend'),
                    formatValue: mainChart == null
                        ? (_) => ''
                        : (item) => _chartValue(mainChart, item),
                    emptyLabel: _t(
                      tr,
                      'no_data_available',
                      'لا توجد بيانات كافية للعرض',
                      'No data available',
                    ),
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 980;
                  final charts = _SmallChartsPanel(
                    title: _t(tr, 'dashboard_more_indicators', 'مؤشرات إضافية', 'More indicators'),
                    charts: secondaryCharts,
                    formatValue: _chartValue,
                    emptyLabel: _t(
                      tr,
                      'no_data_available',
                      'لا توجد بيانات إضافية',
                      'No extra data',
                    ),
                  );
                  final operations = _OperationsPanel(
                    title: tr.text('latest_operations'),
                    emptyText: tr.text('no_sales_desc'),
                    operations: state.recentOperations,
                    operationIcon: _operationIcon,
                    moneyBuilder: _money,
                    dateBuilder: _formatDateTime,
                  );
                  if (!isWide) {
                    return Column(
                      children: [charts, const SizedBox(height: 18), operations],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: charts),
                      const SizedBox(width: 18),
                      Expanded(child: operations),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              _SystemStatusPanel(
                title: _t(tr, 'system_status', 'حالة النظام', 'System status'),
                items: [
                  _SystemStatusData(
                    title: tr.text('sync_status'),
                    value: state.syncStatus.title,
                    icon: Icons.sync_rounded,
                    color: _statusColor(context, state.syncStatus.level),
                  ),
                  _SystemStatusData(
                    title: tr.text('current_backup_status'),
                    value: state.backupStatus.title,
                    icon: Icons.cloud_done_outlined,
                    color: _statusColor(context, state.backupStatus.level),
                  ),
                  _SystemStatusData(
                    title: tr.text('products'),
                    value: '${widget.store.products.length}',
                    icon: Icons.inventory_2_outlined,
                    color: const Color(0xFF2563EB),
                  ),
                  _SystemStatusData(
                    title: tr.text('customers'),
                    value: '${widget.store.customers.length}',
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
      },
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
                    title: syncStatus.title,
                    subtitle: syncStatus.detail,
                    icon: Icons.sync_rounded,
                    color: statusColor(syncStatus.level),
                  ),
                  _StatusPill(
                    title: backupStatus.title,
                    subtitle: backupStatus.detail,
                    icon: Icons.cloud_done_outlined,
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

class _QuickActionsPanel extends StatelessWidget {
  const _QuickActionsPanel({required this.actions});

  final List<_QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _PremiumSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: AppLocalizations.of(context).text('quick_actions'),
            icon: Icons.flash_on_rounded,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 6
                  : constraints.maxWidth >= 620
                      ? 3
                      : 2;
              final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: actions.map((action) {
                  return SizedBox(
                    width: width,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: action.onPressed,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: action.color.withValues(alpha: 0.075),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: action.color.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Column(
                          children: [
                            _IconBubble(icon: action.icon, color: action.color),
                            const SizedBox(height: 10),
                            Text(
                              action.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MainChartPanel extends StatelessWidget {
  const _MainChartPanel({
    required this.series,
    required this.title,
    required this.formatValue,
    required this.emptyLabel,
  });

  final DashboardChartSeries? series;
  final String title;
  final String Function(DashboardChartItem item) formatValue;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = series?.items ?? const <DashboardChartItem>[];
    return _PremiumSurface(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: title, icon: Icons.show_chart_rounded),
          const SizedBox(height: 18),
          if (items.isEmpty)
            SizedBox(height: 260, child: Center(child: Text(emptyLabel)))
          else ...[
            SizedBox(
              height: 260,
              child: _LineChart(items: items),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: items.take(7).map((item) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${item.label}  ${formatValue(item)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlertsPanel extends StatelessWidget {
  const _AlertsPanel({
    required this.title,
    required this.clearText,
    required this.alerts,
    required this.statusColor,
  });

  final String title;
  final String clearText;
  final List<DashboardAlertItem> alerts;
  final Color Function(DashboardStatusLevel level) statusColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _PremiumSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: title, icon: Icons.notifications_active_outlined),
          const SizedBox(height: 14),
          if (alerts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                clearText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF16A34A),
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            ...alerts.take(5).map((alert) {
              final color = statusColor(alert.level);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.075),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: color.withValues(alpha: 0.10)),
                  ),
                  child: Row(
                    children: [
                      _IconBubble(icon: alert.icon, color: color, size: 38),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alert.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              alert.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _FinancialSummaryPanel extends StatelessWidget {
  const _FinancialSummaryPanel({
    required this.title,
    required this.items,
    required this.labelBuilder,
    required this.moneyBuilder,
    required this.statusColor,
  });

  final String title;
  final List<DashboardFinancialItem> items;
  final String Function(DashboardFinancialItem item) labelBuilder;
  final String Function(double value) moneyBuilder;
  final Color Function(DashboardStatusLevel level) statusColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _PremiumSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: title, icon: Icons.account_balance_wallet_outlined),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1000
                  ? 5
                  : constraints.maxWidth >= 680
                      ? 3
                      : 1;
              final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: items.map((item) {
                  final color = statusColor(item.level);
                  return SizedBox(
                    width: width,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.055),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        children: [
                          _IconBubble(icon: item.icon, color: color, size: 42),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  labelBuilder(item),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  moneyBuilder(item.amount),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SmallChartsPanel extends StatelessWidget {
  const _SmallChartsPanel({
    required this.title,
    required this.charts,
    required this.formatValue,
    required this.emptyLabel,
  });

  final String title;
  final List<DashboardChartSeries> charts;
  final String Function(DashboardChartSeries series, DashboardChartItem item)
      formatValue;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _PremiumSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: title, icon: Icons.leaderboard_outlined),
          const SizedBox(height: 14),
          if (charts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(emptyLabel),
            )
          else
            ...charts.map((series) {
              final maxValue = series.items.isEmpty
                  ? 0.0
                  : series.items.map((item) => item.value).fold<double>(0, (a, b) => math.max(a, b).toDouble());
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      series.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...series.items.take(4).map((item) {
                      final percent = maxValue <= 0 ? 0.0 : item.value / maxValue;
                      final color = item.color ?? theme.colorScheme.primary;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  formatValue(series, item),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: percent.clamp(0.0, 1.0).toDouble(),
                                minHeight: 8,
                                backgroundColor: color.withValues(alpha: 0.10),
                                valueColor: AlwaysStoppedAnimation<Color>(color),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _OperationsPanel extends StatelessWidget {
  const _OperationsPanel({
    required this.title,
    required this.emptyText,
    required this.operations,
    required this.operationIcon,
    required this.moneyBuilder,
    required this.dateBuilder,
  });

  final String title;
  final String emptyText;
  final List<DashboardOperationItem> operations;
  final IconData Function(DashboardOperationType type) operationIcon;
  final String Function(double value) moneyBuilder;
  final String Function(DateTime value) dateBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _PremiumSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: title, icon: Icons.history_rounded),
          const SizedBox(height: 14),
          if (operations.isEmpty)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(emptyText),
            )
          else
            ...operations.take(6).map((operation) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 13),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IconBubble(
                      icon: operationIcon(operation.type),
                      color: scheme.primary,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  operation.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                moneyBuilder(operation.amount),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${operation.subtitle} · ${dateBuilder(operation.at)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _SystemStatusData {
  const _SystemStatusData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
}

class _SystemStatusPanel extends StatelessWidget {
  const _SystemStatusPanel({required this.title, required this.items});

  final String title;
  final List<_SystemStatusData> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _PremiumSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: title, icon: Icons.verified_outlined),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1000
                  ? 5
                  : constraints.maxWidth >= 720
                      ? 3
                      : 1;
              final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: items.map((item) {
                  return SizedBox(
                    width: width,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: item.color.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Row(
                        children: [
                          _IconBubble(icon: item.icon, color: item.color, size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PremiumSurface extends StatelessWidget {
  const _PremiumSurface({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        boxShadow: _softShadow(context),
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  const _IconBubble({
    required this.icon,
    required this.color,
    this.size = 48,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.105),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      child: Icon(icon, color: color, size: size * 0.48),
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({required this.items});

  final List<DashboardChartItem> items;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LineChartPainter(
        items: items,
        color: Theme.of(context).colorScheme.primary,
        gridColor: Theme.of(context).colorScheme.outlineVariant,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({
    required this.items,
    required this.color,
    required this.gridColor,
  });

  final List<DashboardChartItem> items;
  final Color color;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty || size.width <= 0 || size.height <= 0) return;

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final values = items.map((item) => item.value).toList();
    final maxValue = values.fold<double>(values.first, (a, b) => math.max(a, b).toDouble());
    final minValue = values.reduce(math.min);
    final span = math.max(1.0, maxValue - minValue).toDouble();
    final dx = items.length <= 1 ? size.width : size.width / (items.length - 1);
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final normalized = (values[i] - minValue) / span;
      final y = size.height - (normalized * size.height * 0.72) - size.height * 0.14;
      points.add(Offset(dx * i, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final controlX = (previous.dx + current.dx) / 2;
      path.cubicTo(controlX, previous.dy, controlX, current.dy, current.dx, current.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.20),
          color.withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = color;
    final dotBorder = Paint()..color = Colors.white;
    for (final point in points) {
      canvas.drawCircle(point, 5.5, dotBorder);
      canvas.drawCircle(point, 3.4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.items != items ||
        oldDelegate.color != color ||
        oldDelegate.gridColor != gridColor;
  }
}

List<BoxShadow> _softShadow(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.055),
      blurRadius: 30,
      offset: const Offset(0, 14),
    ),
  ];
}
