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
import '../../widgets/summary_card.dart';
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
    setState(() {
      _stateFuture = _loadState();
    });
  }

  Future<DashboardState> _loadState() {
    return _service.buildState(widget.store);
  }

  void _openPage(Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  String _formatDateTime(DateTime value) {
    return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
  }

  String _formatDate(DateTime value) {
    return DateFormat('yyyy-MM-dd').format(value.toLocal());
  }

  IconData _operationIcon(DashboardOperationType type) {
    return switch (type) {
      DashboardOperationType.sale => Icons.receipt_long_outlined,
      DashboardOperationType.purchase => Icons.shopping_cart_outlined,
      DashboardOperationType.expense => Icons.money_off_csred_outlined,
      DashboardOperationType.payment => Icons.payments_outlined,
      DashboardOperationType.stockMovement => Icons.inventory_2_outlined,
      DashboardOperationType.other => Icons.bolt_outlined,
    };
  }

  Color _statusColor(BuildContext context, DashboardStatusLevel level) {
    final scheme = Theme.of(context).colorScheme;
    return switch (level) {
      DashboardStatusLevel.healthy => scheme.primary,
      DashboardStatusLevel.warning => Colors.amber.shade700,
      DashboardStatusLevel.danger => scheme.error,
      DashboardStatusLevel.neutral => scheme.outline,
    };
  }

  List<_QuickAction> _quickActions(AppLocalizations tr) {
    return <_QuickAction>[
      _QuickAction(
        label: tr.text('sale_page'),
        icon: Icons.receipt_long_outlined,
        onPressed: () => _openPage(SalesPage(store: widget.store)),
      ),
      _QuickAction(
        label: tr.text('add_product'),
        icon: Icons.inventory_2_outlined,
        onPressed: () => _openPage(ProductsPage(store: widget.store)),
      ),
      _QuickAction(
        label: tr.text('new_purchase'),
        icon: Icons.shopping_cart_outlined,
        onPressed: () => _openPage(PurchasesPage(store: widget.store)),
      ),
      _QuickAction(
        label: tr.text('receive_payment'),
        icon: Icons.payments_outlined,
        onPressed: () => _openPage(AccountingPage(store: widget.store)),
      ),
      _QuickAction(
        label: tr.text('pay_supplier'),
        icon: Icons.account_balance_wallet_outlined,
        onPressed: () => _openPage(ExpensesPage(store: widget.store)),
      ),
      _QuickAction(
        label: tr.text('reports'),
        icon: Icons.bar_chart_outlined,
        onPressed: () => _openPage(ReportsPage(store: widget.store)),
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
    if (series.displayAsMoney) {
      return formatUsdReferenceAmount(item.value, widget.store.storeProfile);
    }
    final raw = item.value.toStringAsFixed(item.value % 1 == 0 ? 0 : 1);
    return raw.replaceFirst(RegExp(r'\.0$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return FutureBuilder<DashboardState>(
      future: _stateFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return ListView(
            padding: VentioResponsive.pageInsets(context),
            children: const [
              SizedBox(
                height: 280,
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          );
        }

        if (snapshot.hasError) {
          return ListView(
            padding: VentioResponsive.pageInsets(context),
            children: [
              Card(
                child: Padding(
                  padding: VentioResponsive.pageInsets(context),
                  child: Text(
                    snapshot.error.toString(),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
            ],
          );
        }

        final state = snapshot.data;
        if (state == null) {
          return const SizedBox.shrink();
        }

        final metrics = <_DashboardMetricCardData>[
          _DashboardMetricCardData(
            title: tr.text('today_sales'),
            value: formatUsdReferenceAmount(
              state.todaySalesTotal,
              widget.store.storeProfile,
            ),
            icon: Icons.payments_outlined,
          ),
          _DashboardMetricCardData(
            title: tr.text('net_profit'),
            value: formatUsdReferenceAmount(
              state.todayProfitTotal,
              widget.store.storeProfile,
            ),
            icon: Icons.trending_up_outlined,
          ),
          _DashboardMetricCardData(
            title: tr.text('today_invoices'),
            value: '${state.todayInvoiceCount}',
            icon: Icons.receipt_long_outlined,
          ),
          _DashboardMetricCardData(
            title: tr.text('closing_cash_balance'),
            value: formatUsdReferenceAmount(
              state.currentCashTotal,
              widget.store.storeProfile,
            ),
            icon: Icons.account_balance_wallet_outlined,
          ),
        ];

        return ListView(
          padding: VentioResponsive.pageInsets(context),
          children: [
            Card(
              child: Padding(
                padding: VentioResponsive.pageInsets(context),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 900;
                    final headerChildren = <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.storeName,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _formatDate(state.generatedAt),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      _StatusBadge(
                        label: tr.text('sync_status'),
                        value: state.syncStatus.title,
                        detail: state.syncStatus.detail,
                        color: _statusColor(context, state.syncStatus.level),
                      ),
                      const SizedBox(width: 12),
                      _StatusBadge(
                        label: tr.text('current_backup_status'),
                        value: state.backupStatus.title,
                        detail: state.backupStatus.detail,
                        color: _statusColor(context, state.backupStatus.level),
                      ),
                    ];
                    return isNarrow
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              headerChildren.first,
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: headerChildren.skip(2).toList(),
                              ),
                            ],
                          )
                        : Row(children: headerChildren);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: metrics
                  .map(
                    (metric) => SummaryCard(
                      title: metric.title,
                      value: metric.value,
                      icon: metric.icon,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: VentioResponsive.pageInsets(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr.text('quick_actions'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 720;
                        final actionWidth = isNarrow
                            ? double.infinity
                            : (constraints.maxWidth - 16) / 2;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: _quickActions(tr)
                              .map(
                                (action) => SizedBox(
                                  width: actionWidth,
                                  child: FilledButton.tonalIcon(
                                    onPressed: action.onPressed,
                                    icon: Icon(action.icon),
                                    label: Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: Text(action.label),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 900;
                final chartCards = state.charts
                    .map(
                      (series) => _ChartCard(
                        series: series,
                        formatValue: (item) => _chartValue(series, item),
                      ),
                    )
                    .toList();
                if (isNarrow) {
                  return Column(
                    children: [
                      for (var i = 0; i < chartCards.length; i += 1) ...[
                        chartCards[i],
                        if (i != chartCards.length - 1)
                          const SizedBox(height: 16),
                      ],
                    ],
                  );
                }
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: chartCards
                      .map(
                        (card) => SizedBox(
                          width: (constraints.maxWidth - 16) / 2,
                          child: card,
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 900;
                final alertsPanel = Card(
                  child: Padding(
                    padding: VentioResponsive.pageInsets(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr.text('dashboard_alerts'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        if (state.alerts.isEmpty)
                          Text(tr.text('dashboard_alerts_clear'))
                        else
                          ...state.alerts.map(
                            (alert) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor:
                                    _statusColor(context, alert.level),
                                child: Icon(alert.icon, color: Colors.white),
                              ),
                              title: Text(alert.title),
                              subtitle: Text(alert.message),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
                final financialPanel = Card(
                  child: Padding(
                    padding: VentioResponsive.pageInsets(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr.text('financial_summary'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: state.financialSummary
                              .map(
                                (item) => SummaryCard(
                                  title: _financialLabel(tr, item),
                                  value: formatUsdReferenceAmount(
                                    item.amount,
                                    widget.store.storeProfile,
                                  ),
                                  icon: item.icon,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                );
                if (isNarrow) {
                  return Column(
                    children: [
                      alertsPanel,
                      const SizedBox(height: 16),
                      financialPanel,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: alertsPanel),
                    const SizedBox(width: 16),
                    Expanded(child: financialPanel),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 900;
                final latestOperationsPanel = Card(
                  child: Padding(
                    padding: VentioResponsive.pageInsets(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr.text('latest_operations'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        if (state.recentOperations.isEmpty)
                          Text(tr.text('no_sales_desc'))
                        else
                          ...state.recentOperations.map(
                            (operation) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                child: Icon(_operationIcon(operation.type)),
                              ),
                              title: Text(operation.title),
                              subtitle: Text(
                                '${operation.subtitle} - ${_formatDateTime(operation.at)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                formatUsdReferenceAmount(
                                  operation.amount,
                                  widget.store.storeProfile,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
                final snapshotPanel = Card(
                  child: Padding(
                    padding: VentioResponsive.pageInsets(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr.text('business_snapshot'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        _Line(
                          title: tr.text('inventory_value'),
                          value: formatUsdReferenceAmount(
                            widget.store.inventoryRetailValue,
                            widget.store.storeProfile,
                          ),
                        ),
                        _Line(
                          title: tr.text('inventory_cost_value'),
                          value: formatUsdReferenceAmount(
                            widget.store.inventoryCostValue,
                            widget.store.storeProfile,
                          ),
                        ),
                        _Line(
                          title: tr.text('suppliers'),
                          value: '${widget.store.suppliers.length}',
                        ),
                        _Line(
                          title: tr.text('customers'),
                          value: '${widget.store.customers.length}',
                        ),
                        _Line(
                          title: tr.text('expenses_count'),
                          value: '${widget.store.expenses.length}',
                        ),
                        _Line(
                          title: tr.text('low_stock_alerts'),
                          value: '${state.lowStockCount}',
                        ),
                      ],
                    ),
                  ),
                );
                if (isNarrow) {
                  return Column(
                    children: [
                      latestOperationsPanel,
                      const SizedBox(height: 16),
                      snapshotPanel,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: latestOperationsPanel),
                    const SizedBox(width: 16),
                    Expanded(child: snapshotPanel),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _DashboardMetricCardData {
  const _DashboardMetricCardData({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;
}

class _QuickAction {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final String label;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.series,
    required this.formatValue,
  });

  final DashboardChartSeries series;
  final String Function(DashboardChartItem item) formatValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxValue = series.items.isEmpty
        ? 0.0
        : series.items
            .map((item) => item.value)
            .reduce((a, b) => a > b ? a : b);
    final itemWidth = series.items.length > 12 ? 22.0 : 34.0;
    return Card(
      child: Padding(
        padding: VentioResponsive.pageInsets(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              series.title,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: series.items
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsetsDirectional.only(end: 10),
                          child: SizedBox(
                            width: itemWidth,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      width: itemWidth * 0.7,
                                      height: maxValue <= 0
                                          ? 6
                                          : 120 *
                                              (item.value / maxValue).clamp(
                                                0.06,
                                                1.0,
                                              ),
                                      decoration: BoxDecoration(
                                        color: item.color ??
                                            theme.colorScheme.primary,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall,
                                ),
                                Text(
                                  formatValue(item),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
