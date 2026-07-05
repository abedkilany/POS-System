import 'package:flutter/material.dart';

import '../../core/services/accounting_aging_service.dart';
import '../../core/services/accounting_service.dart';
import '../../core/services/google_drive_backup_service.dart';
import '../../core/services/local_auto_backup_service.dart';
import '../../core/services/local_database_service.dart';
import '../../data/app_store.dart';
import '../../models/aging_report.dart';
import 'dashboard_snapshot_service.dart';

enum DashboardStatusLevel { healthy, warning, danger, neutral }

enum DashboardOperationType {
  sale,
  purchase,
  expense,
  payment,
  stockMovement,
  other,
}

class DashboardMetric {
  const DashboardMetric({
    required this.key,
    required this.value,
    required this.icon,
  });

  final String key;
  final double value;
  final IconData icon;
}

class DashboardOperationItem {
  const DashboardOperationItem({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.at,
  });

  final DashboardOperationType type;
  final String title;
  final String subtitle;
  final double amount;
  final DateTime at;
}

class DashboardHealthSnapshot {
  const DashboardHealthSnapshot({
    required this.level,
    required this.title,
    required this.detail,
    this.pendingCount = 0,
    this.lastUpdatedAt,
    this.isRunning = false,
  });

  final DashboardStatusLevel level;
  final String title;
  final String detail;
  final int pendingCount;
  final DateTime? lastUpdatedAt;
  final bool isRunning;
}

class DashboardAlertItem {
  const DashboardAlertItem({
    required this.level,
    required this.title,
    required this.message,
    required this.icon,
  });

  final DashboardStatusLevel level;
  final String title;
  final String message;
  final IconData icon;
}

class DashboardFinancialItem {
  const DashboardFinancialItem({
    required this.key,
    required this.title,
    required this.amount,
    required this.icon,
    this.level = DashboardStatusLevel.neutral,
  });

  final String key;
  final String title;
  final double amount;
  final IconData icon;
  final DashboardStatusLevel level;
}

class DashboardChartItem {
  const DashboardChartItem({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final double value;
  final Color? color;
}

class DashboardChartSeries {
  const DashboardChartSeries({
    required this.key,
    required this.title,
    required this.items,
    this.displayAsMoney = true,
  });

  final String key;
  final String title;
  final List<DashboardChartItem> items;
  final bool displayAsMoney;
}

class DashboardState {
  const DashboardState({
    required this.storeName,
    required this.generatedAt,
    required this.todaySalesTotal,
    required this.todayProfitTotal,
    required this.todayInvoiceCount,
    required this.currentCashTotal,
    required this.lowStockCount,
    required this.alerts,
    required this.financialSummary,
    required this.charts,
    required this.recentOperations,
    required this.syncStatus,
    required this.backupStatus,
    this.isHydrated = true,
  });

  final String storeName;
  final DateTime generatedAt;
  final double todaySalesTotal;
  final double todayProfitTotal;
  final int todayInvoiceCount;
  final double currentCashTotal;
  final int lowStockCount;
  final List<DashboardAlertItem> alerts;
  final List<DashboardFinancialItem> financialSummary;
  final List<DashboardChartSeries> charts;
  final List<DashboardOperationItem> recentOperations;
  final DashboardHealthSnapshot syncStatus;
  final DashboardHealthSnapshot backupStatus;
  final bool isHydrated;
}

class DashboardService {
  const DashboardService();

  Future<DashboardState> buildState(
    AppStore store, {
    DateTime? now,
  }) async {
    final reference = (now ?? DateTime.now()).toLocal();
    if (LocalDatabaseService.canQueryBusinessSqlite) {
      return _buildStateFromSqlite(store, reference);
    }
    return DashboardSnapshotService().buildState(store, now: reference);
  }

  Future<DashboardState> _buildStateFromSqlite(
    AppStore store,
    DateTime reference,
  ) async {
    final summary = await LocalDatabaseService.buildDashboardSummaryFromSqlite(
          reference: reference,
        ) ??
        <String, Object?>{};
    final customerAging =
        await AccountingAgingService.customerAgingReport(asOfDate: reference);
    final supplierAging =
        await AccountingAgingService.supplierAgingReport(asOfDate: reference);
    final cashTotals = await currentCashTotals(store);
    final accountingSummary = await AccountingService.incomeStatementReport();
    final sync = syncStatus(
      store,
      reference: reference,
      pendingSyncCount: _intValue(summary['pendingSyncCount']),
    );
    final backup = backupStatus(reference: reference);
    final lowStockNames = (summary['lowStockNames'] as List<dynamic>? ?? const <dynamic>[])
        .map((item) => item.toString())
        .take(3)
        .toList(growable: false);
    final alerts = <DashboardAlertItem>[
      if (_intValue(summary['lowStockCount']) > 0)
        DashboardAlertItem(
          level: DashboardStatusLevel.warning,
          title: 'Low stock',
          message:
              '${_intValue(summary['lowStockCount'])} product(s) need replenishment${lowStockNames.isEmpty ? '' : ': ${lowStockNames.join(', ')}'}',
          icon: Icons.warning_amber_rounded,
        ),
      if (_doubleValue(summary['todayExpenseTotal']) > 0 &&
          _doubleValue(summary['last7ExpenseAverage']) > 0 &&
          _doubleValue(summary['todayExpenseTotal']) >
              _doubleValue(summary['last7ExpenseAverage']) * 1.5)
        DashboardAlertItem(
          level: DashboardStatusLevel.warning,
          title: 'High expense day',
          message:
              '${_doubleValue(summary['todayExpenseTotal']).toStringAsFixed(2)} today vs ${_doubleValue(summary['last7ExpenseAverage']).toStringAsFixed(2)} daily average',
          icon: Icons.trending_down_outlined,
        ),
      if (_intValue(summary['blockingConflictCount']) > 0)
        DashboardAlertItem(
          level: DashboardStatusLevel.danger,
          title: 'Blocking conflicts',
          message:
              '${_intValue(summary['blockingConflictCount'])} blocking conflict(s) need review',
          icon: Icons.rule_outlined,
        ),
      if (customerAging.total > 0)
        DashboardAlertItem(
          level: customerAging.over90 > 0
              ? DashboardStatusLevel.danger
              : DashboardStatusLevel.warning,
          title: 'Open receivables',
          message:
              '${customerAging.total.toStringAsFixed(2)} across ${customerAging.openDocuments.length} invoice(s)',
          icon: Icons.account_balance_outlined,
        ),
      if (supplierAging.total > 0)
        DashboardAlertItem(
          level: supplierAging.over90 > 0
              ? DashboardStatusLevel.danger
              : DashboardStatusLevel.warning,
          title: 'Open payables',
          message:
              '${supplierAging.total.toStringAsFixed(2)} across ${supplierAging.openDocuments.length} bill(s)',
          icon: Icons.payments_outlined,
        ),
      if (backup.level != DashboardStatusLevel.healthy)
        DashboardAlertItem(
          level: backup.level,
          title: 'Backup attention',
          message: backup.detail,
          icon: Icons.backup_outlined,
        ),
      if (sync.level != DashboardStatusLevel.healthy)
        DashboardAlertItem(
          level: sync.level,
          title: 'Sync attention',
          message: sync.detail,
          icon: Icons.sync_problem_outlined,
        ),
    ];
    final financialSummary = <DashboardFinancialItem>[
      DashboardFinancialItem(
        key: 'cash',
        title: 'Cash',
        amount: cashTotals.cash,
        icon: Icons.payments_outlined,
      ),
      DashboardFinancialItem(
        key: 'bank',
        title: 'Bank',
        amount: cashTotals.bank,
        icon: Icons.account_balance_outlined,
      ),
      DashboardFinancialItem(
        key: 'cards',
        title: 'Cards',
        amount: cashTotals.cards,
        icon: Icons.credit_card_outlined,
      ),
      DashboardFinancialItem(
        key: 'liquidity',
        title: 'Liquidity',
        amount: cashTotals.totalLiquidity,
        icon: Icons.savings_outlined,
      ),
      DashboardFinancialItem(
        key: 'receivables',
        title: 'Receivables',
        amount: customerAging.total,
        icon: Icons.how_to_reg_outlined,
      ),
      DashboardFinancialItem(
        key: 'payables',
        title: 'Payables',
        amount: supplierAging.total,
        icon: Icons.receipt_long_outlined,
      ),
      DashboardFinancialItem(
        key: 'inventory',
        title: 'Inventory',
        amount: _doubleValue(summary['inventoryCostValue']),
        icon: Icons.warehouse_outlined,
      ),
      DashboardFinancialItem(
        key: 'profit',
        title: 'Net profit',
        amount: accountingSummary.netProfit,
        icon: Icons.trending_up_outlined,
        level: accountingSummary.netProfit < 0
            ? DashboardStatusLevel.danger
            : DashboardStatusLevel.healthy,
      ),
      DashboardFinancialItem(
        key: 'expenses',
        title: 'Expenses',
        amount: accountingSummary.expenses,
        icon: Icons.money_off_csred_outlined,
      ),
      DashboardFinancialItem(
        key: 'purchases',
        title: 'Purchases',
        amount: _doubleValue(summary['totalPurchasesAmount']),
        icon: Icons.shopping_cart_outlined,
      ),
    ];
    final charts = <DashboardChartSeries>[
      DashboardChartSeries(
        key: 'sales_7d',
        title: 'Sales last 7 days',
        items: _seriesFromSummaryList(summary['salesLast7Days']),
      ),
      DashboardChartSeries(
        key: 'sales_30d',
        title: 'Sales last 30 days',
        items: _seriesFromSummaryList(summary['salesLast30Days']),
      ),
      DashboardChartSeries(
        key: 'sales_profit',
        title: 'Sales vs profit',
        items: <DashboardChartItem>[
          DashboardChartItem(
            label: 'Sales',
            value: _doubleValue(summary['salesSince30Days']),
            color: Colors.blue,
          ),
          DashboardChartItem(
            label: 'Profit',
            value: _doubleValue(summary['profitSince30Days']),
            color: Colors.green,
          ),
        ],
      ),
      DashboardChartSeries(
        key: 'expenses_type',
        title: 'Expenses by type',
        items: _seriesFromSummaryList(summary['expenseCategories'],
            color: Colors.deepOrange),
      ),
      DashboardChartSeries(
        key: 'top_products',
        title: 'Top products',
        items: _seriesFromSummaryList(
          summary['topProducts'],
          color: Colors.purple,
        ),
        displayAsMoney: false,
      ),
      DashboardChartSeries(
        key: 'top_customers',
        title: 'Top customers',
        items: _seriesFromSummaryList(summary['topCustomers'],
            color: Colors.teal),
      ),
      DashboardChartSeries(
        key: 'receivable_pressure',
        title: 'Receivables pressure',
        items: <DashboardChartItem>[
          DashboardChartItem(label: 'Current', value: customerAging.current),
          DashboardChartItem(
            label: 'Over 30',
            value: customerAging.days1To30 +
                customerAging.days31To60 +
                customerAging.days61To90 +
                customerAging.over90,
          ),
        ],
      ),
      DashboardChartSeries(
        key: 'payable_pressure',
        title: 'Payables pressure',
        items: <DashboardChartItem>[
          DashboardChartItem(label: 'Current', value: supplierAging.current),
          DashboardChartItem(
            label: 'Over 30',
            value: supplierAging.days1To30 +
                supplierAging.days31To60 +
                supplierAging.days61To90 +
                supplierAging.over90,
          ),
        ],
      ),
    ];

    return DashboardState(
      storeName: store.storeProfile.name.trim().isEmpty
          ? store.appIdentity.storeId
          : store.storeProfile.name,
      generatedAt: reference,
      todaySalesTotal: _doubleValue(summary['todaySalesTotal']),
      todayProfitTotal: _doubleValue(summary['todayProfitTotal']),
      todayInvoiceCount: _intValue(summary['todayInvoiceCount']),
      currentCashTotal: cashTotals.cash,
      lowStockCount: _intValue(summary['lowStockCount']),
      alerts: alerts,
      financialSummary: financialSummary,
      charts: charts,
      recentOperations: _recentOperations(summary['recentOperations']),
      syncStatus: sync,
      backupStatus: backup,
    );
  }

  double todaySalesAmount(AppStore store, DateTime reference) {
    return 0;
  }

  double todayProfitAmount(AppStore store, DateTime reference) {
    return 0;
  }

  int todayInvoiceCount(AppStore store, DateTime reference) {
    return 0;
  }

  int lowStockCount(AppStore store) => 0;

  Future<CashBalanceTotals> currentCashTotals(AppStore store) async {
    if (!AccountingService.isAvailable) return CashBalanceTotals();
    try {
      final rows = await AccountingService.listCashBalancesReport();
      final totals = CashBalanceTotals();
      for (final item in rows.where((item) => item.isActive)) {
        final type = item.type.trim().toLowerCase();
        final balance = item.balance;
        if (type == 'bank') {
          totals.bank += balance;
        } else if (type == 'card' ||
            type == 'wallet' ||
            type == 'cheque' ||
            type == 'other') {
          totals.cards += balance;
        } else {
          totals.cash += balance;
        }
      }
      return totals;
    } catch (_) {
      return CashBalanceTotals();
    }
  }

  List<DashboardAlertItem> dashboardAlerts(
    AppStore store, {
    required DateTime reference,
    required AgingReportResult customerAging,
    required AgingReportResult supplierAging,
    required CashBalanceTotals cashTotals,
    required DashboardHealthSnapshot syncStatus,
    required DashboardHealthSnapshot backupStatus,
  }) {
    final alerts = <DashboardAlertItem>[];
    if (customerAging.total > 0) {
      alerts.add(
        DashboardAlertItem(
          level: customerAging.over90 > 0
              ? DashboardStatusLevel.danger
              : DashboardStatusLevel.warning,
          title: 'Open receivables',
          message:
              '${_formatMoney(customerAging.total)} across ${customerAging.openDocuments.length} invoice(s)',
          icon: Icons.account_balance_outlined,
        ),
      );
    }

    if (supplierAging.total > 0) {
      alerts.add(
        DashboardAlertItem(
          level: supplierAging.over90 > 0
              ? DashboardStatusLevel.danger
              : DashboardStatusLevel.warning,
          title: 'Open payables',
          message:
              '${_formatMoney(supplierAging.total)} across ${supplierAging.openDocuments.length} bill(s)',
          icon: Icons.payments_outlined,
        ),
      );
    }

    if (backupStatus.level != DashboardStatusLevel.healthy) {
      alerts.add(
        DashboardAlertItem(
          level: backupStatus.level,
          title: 'Backup attention',
          message: backupStatus.detail,
          icon: Icons.backup_outlined,
        ),
      );
    }

    if (syncStatus.level != DashboardStatusLevel.healthy) {
      alerts.add(
        DashboardAlertItem(
          level: syncStatus.level,
          title: 'Sync attention',
          message: syncStatus.detail,
          icon: Icons.sync_problem_outlined,
        ),
      );
    }

    return alerts;
  }

  List<DashboardFinancialItem> dashboardFinancialSummary(
    AppStore store, {
    required AgingReportResult customerAging,
    required AgingReportResult supplierAging,
    required CashBalanceTotals cashTotals,
    required double netProfit,
    required double expenseTotal,
  }) {
    return <DashboardFinancialItem>[
      DashboardFinancialItem(
        key: 'cash',
        title: 'Cash',
        amount: cashTotals.cash,
        icon: Icons.payments_outlined,
      ),
      DashboardFinancialItem(
        key: 'bank',
        title: 'Bank',
        amount: cashTotals.bank,
        icon: Icons.account_balance_outlined,
      ),
      DashboardFinancialItem(
        key: 'cards',
        title: 'Cards',
        amount: cashTotals.cards,
        icon: Icons.credit_card_outlined,
      ),
      DashboardFinancialItem(
        key: 'liquidity',
        title: 'Liquidity',
        amount: cashTotals.totalLiquidity,
        icon: Icons.savings_outlined,
      ),
      DashboardFinancialItem(
        key: 'receivables',
        title: 'Receivables',
        amount: customerAging.total,
        icon: Icons.how_to_reg_outlined,
      ),
      DashboardFinancialItem(
        key: 'payables',
        title: 'Payables',
        amount: supplierAging.total,
        icon: Icons.receipt_long_outlined,
      ),
      DashboardFinancialItem(
        key: 'inventory',
        title: 'Inventory',
        amount: 0,
        icon: Icons.warehouse_outlined,
      ),
      DashboardFinancialItem(
        key: 'profit',
        title: 'Net profit',
        amount: netProfit,
        icon: Icons.trending_up_outlined,
        level: netProfit < 0
            ? DashboardStatusLevel.danger
            : DashboardStatusLevel.healthy,
      ),
      DashboardFinancialItem(
        key: 'expenses',
        title: 'Expenses',
        amount: expenseTotal,
        icon: Icons.money_off_csred_outlined,
      ),
      DashboardFinancialItem(
        key: 'purchases',
        title: 'Purchases',
        amount: 0,
        icon: Icons.shopping_cart_outlined,
      ),
    ];
  }

  List<DashboardChartSeries> dashboardCharts(
    AppStore store, {
    required DateTime reference,
    required AgingReportResult customerAging,
    required AgingReportResult supplierAging,
  }) {
    final salesLast7Days = _dailySalesSeries(store, reference, 7);
    final salesLast30Days = _dailySalesSeries(store, reference, 30);
    final salesVsProfit = <DashboardChartItem>[
      DashboardChartItem(
        label: 'Sales',
        value: 0,
        color: Colors.blue,
      ),
      DashboardChartItem(
        label: 'Profit',
        value: 0,
        color: Colors.green,
      ),
    ];
    final expensesByType = _groupExpensesByCategory(store, 5);
    final topProducts = _topProductsByQuantity(store, 5);
    final topCustomers = _topCustomersBySales(store, 5);

    // Aging inputs are kept in the signature so the charts stay aligned with
    // the same ledger snapshot used by the alert and financial sections.
    final receivablePressure = DashboardChartSeries(
      key: 'receivable_pressure',
      title: 'Receivables pressure',
      items: <DashboardChartItem>[
        DashboardChartItem(label: 'Current', value: customerAging.current),
        DashboardChartItem(
            label: 'Over 30',
            value: customerAging.days1To30 +
                customerAging.days31To60 +
                customerAging.days61To90 +
                customerAging.over90),
      ],
    );
    final payablePressure = DashboardChartSeries(
      key: 'payable_pressure',
      title: 'Payables pressure',
      items: <DashboardChartItem>[
        DashboardChartItem(label: 'Current', value: supplierAging.current),
        DashboardChartItem(
            label: 'Over 30',
            value: supplierAging.days1To30 +
                supplierAging.days31To60 +
                supplierAging.days61To90 +
                supplierAging.over90),
      ],
    );
    final profitChart = DashboardChartSeries(
      key: 'sales_profit',
      title: 'Sales vs profit',
      items: salesVsProfit,
    );

    return <DashboardChartSeries>[
      DashboardChartSeries(
        key: 'sales_7d',
        title: 'Sales last 7 days',
        items: salesLast7Days,
      ),
      DashboardChartSeries(
        key: 'sales_30d',
        title: 'Sales last 30 days',
        items: salesLast30Days,
      ),
      profitChart,
      DashboardChartSeries(
        key: 'expenses_type',
        title: 'Expenses by type',
        items: expensesByType,
      ),
      DashboardChartSeries(
        key: 'top_products',
        title: 'Top products',
        items: topProducts,
        displayAsMoney: false,
      ),
      DashboardChartSeries(
        key: 'top_customers',
        title: 'Top customers',
        items: topCustomers,
      ),
      receivablePressure,
      payablePressure,
    ];
  }

  List<DashboardChartItem> _dailySalesSeries(
    AppStore store,
    DateTime reference,
    int days,
  ) {
    return const <DashboardChartItem>[];
  }

  List<DashboardChartItem> _groupExpensesByCategory(AppStore store, int limit) {
    return const <DashboardChartItem>[];
  }

  List<DashboardChartItem> _topProductsByQuantity(AppStore store, int limit) {
    return const <DashboardChartItem>[];
  }

  List<DashboardChartItem> _topCustomersBySales(AppStore store, int limit) {
    return const <DashboardChartItem>[];
  }

  List<DashboardOperationItem> recentOperations(
    AppStore store, {
    DateTime? reference,
    int limit = 5,
  }) {
    return const <DashboardOperationItem>[];
  }

  DashboardHealthSnapshot syncStatus(
    AppStore store, {
    DateTime? reference,
    int? pendingSyncCount,
  }) {
    final pending = pendingSyncCount ?? store.pendingSyncCount;
    if (store.isSuspendedByHost) {
      return DashboardHealthSnapshot(
        level: DashboardStatusLevel.danger,
        title: 'Sync paused',
        detail: store.suspendedByHostReason,
        pendingCount: pending,
        lastUpdatedAt: reference,
      );
    }
    if (pending > 0) {
      return DashboardHealthSnapshot(
        level: DashboardStatusLevel.warning,
        title: 'Sync pending',
        detail: '$pending pending change(s)',
        pendingCount: pending,
        lastUpdatedAt: reference,
      );
    }
    return DashboardHealthSnapshot(
      level: DashboardStatusLevel.healthy,
      title: 'Sync ready',
      detail: 'No pending local sync work',
      pendingCount: 0,
      lastUpdatedAt: reference,
    );
  }

  DashboardHealthSnapshot backupStatus({
    DateTime? reference,
  }) {
    final localStatus = LocalAutoBackupService.status.value;
    final googleStatus = GoogleDriveBackupService.status.value;
    final localSuccess = LocalAutoBackupService.lastSuccessAt();
    final googleSuccess = GoogleDriveBackupService.lastSuccessAt();
    final latestSuccess = _latestDate(localSuccess, googleSuccess);
    final latestError = <String>[
      if (localStatus.lastError.trim().isNotEmpty) localStatus.lastError.trim(),
      if (googleStatus.lastError.trim().isNotEmpty)
        googleStatus.lastError.trim(),
    ].join(' | ');
    final running = localStatus.isRunning || googleStatus.isRunning;
    var level = DashboardStatusLevel.healthy;
    if (running) {
      level = DashboardStatusLevel.warning;
    } else if (latestSuccess == null) {
      level = DashboardStatusLevel.warning;
    } else {
      final age = reference == null
          ? 0
          : reference.toLocal().difference(latestSuccess.toLocal()).inDays;
      if (age >= 14) {
        level = DashboardStatusLevel.danger;
      } else if (age >= 7) {
        level = DashboardStatusLevel.warning;
      }
    }
    return DashboardHealthSnapshot(
      level: level,
      title: running
          ? 'Backup running'
          : latestSuccess == null
              ? 'Backup needed'
              : 'Backup ready',
      detail: latestError.isNotEmpty
          ? latestError
          : latestSuccess == null
              ? 'No successful backup yet'
              : 'Last backup at ${latestSuccess.toLocal()}',
      lastUpdatedAt: latestSuccess,
      isRunning: running,
    );
  }

  int _intValue(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _doubleValue(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<DashboardChartItem> _seriesFromSummaryList(
    Object? value, {
    Color? color,
  }) {
    if (value is! List) return const <DashboardChartItem>[];
    final items = <DashboardChartItem>[];
    for (final entry in value.whereType<Map>()) {
      final data = Map<String, Object?>.from(entry);
      final label = (data['label'] ?? data['key'] ?? '').toString().trim();
      if (label.isEmpty) continue;
      items.add(
        DashboardChartItem(
          label: label,
          value: _doubleValue(data['value']),
          color: color,
        ),
      );
    }
    return items;
  }

  List<DashboardOperationItem> _recentOperations(Object? value) {
    if (value is! List) return const <DashboardOperationItem>[];
    final items = <DashboardOperationItem>[];
    for (final entry in value.whereType<Map>()) {
      final data = Map<String, Object?>.from(entry);
      final type = _operationTypeFromString(data['type']?.toString() ?? '');
      final title = data['title']?.toString().trim() ?? '';
      final subtitle = data['subtitle']?.toString().trim() ?? '';
      final at = DateTime.tryParse(data['at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      items.add(
        DashboardOperationItem(
          type: type,
          title: title,
          subtitle: subtitle,
          amount: _doubleValue(data['amount']),
          at: at,
        ),
      );
    }
    items.sort((a, b) => b.at.compareTo(a.at));
    return items.take(5).toList(growable: false);
  }

  DashboardOperationType _operationTypeFromString(String value) {
    switch (value.trim().toLowerCase()) {
      case 'sale':
        return DashboardOperationType.sale;
      case 'purchase':
        return DashboardOperationType.purchase;
      case 'expense':
        return DashboardOperationType.expense;
      case 'payment':
        return DashboardOperationType.payment;
      case 'stockmovement':
      case 'stock_movement':
        return DashboardOperationType.stockMovement;
      default:
        return DashboardOperationType.other;
    }
  }

  String _formatMoney(double value) {
    final normalized = value.isFinite ? value : 0;
    return normalized.toStringAsFixed(2);
  }

  DateTime? _latestDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }
}

class CashBalanceTotals {
  double cash = 0;
  double bank = 0;
  double cards = 0;

  double get totalLiquidity => cash + bank + cards;
}
