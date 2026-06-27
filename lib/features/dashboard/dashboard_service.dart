import 'package:flutter/material.dart';

import '../../core/services/accounting_aging_service.dart';
import '../../core/services/accounting_service.dart';
import '../../core/services/google_drive_backup_service.dart';
import '../../core/services/local_auto_backup_service.dart';
import '../../data/app_store.dart';
import '../../models/aging_report.dart';

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
}

class DashboardService {
  const DashboardService();

  Future<DashboardState> buildState(
    AppStore store, {
    DateTime? now,
  }) async {
    final reference = (now ?? DateTime.now()).toLocal();
    final cashTotals = await currentCashTotals(store);
    final customerAging = AccountingAgingService.customerAgingFromStore(
      sales: store.sales,
      accountTransactions: store.accountTransactions,
      asOfDate: reference,
    );
    final supplierAging = AccountingAgingService.supplierAgingFromStore(
      purchases: store.purchases,
      accountTransactions: store.accountTransactions,
      asOfDate: reference,
    );
    final salesToday = todaySalesAmount(store, reference);
    final profitToday = todayProfitAmount(store, reference);
    final invoiceCount = todayInvoiceCount(store, reference);
    final accountingSummary = await AccountingService.incomeStatementReport();
    final cash = cashTotals.cash;
    final lowStock = lowStockCount(store);
    final operations = recentOperations(store, reference: reference);
    final sync = syncStatus(store, reference: reference);
    final backup = backupStatus(reference: reference);
    final alerts = dashboardAlerts(
      store,
      reference: reference,
      customerAging: customerAging,
      supplierAging: supplierAging,
      cashTotals: cashTotals,
      syncStatus: sync,
      backupStatus: backup,
    );
    final financialSummary = dashboardFinancialSummary(
      store,
      customerAging: customerAging,
      supplierAging: supplierAging,
      cashTotals: cashTotals,
      netProfit: accountingSummary.netProfit,
      expenseTotal: accountingSummary.expenses,
    );
    final charts = dashboardCharts(
      store,
      reference: reference,
      customerAging: customerAging,
      supplierAging: supplierAging,
    );

    return DashboardState(
      storeName: store.storeProfile.name.trim().isEmpty
          ? store.appIdentity.storeId
          : store.storeProfile.name,
      generatedAt: reference,
      todaySalesTotal: salesToday,
      todayProfitTotal: profitToday,
      todayInvoiceCount: invoiceCount,
      currentCashTotal: cash,
      lowStockCount: lowStock,
      alerts: alerts,
      financialSummary: financialSummary,
      charts: charts,
      recentOperations: operations,
      syncStatus: sync,
      backupStatus: backup,
    );
  }

  double todaySalesAmount(AppStore store, DateTime reference) {
    return store.sales
        .where((sale) => _isSameDay(sale.date, reference) && !sale.isDeleted)
        .fold<double>(0, (sum, sale) => sum + sale.total);
  }

  double todayProfitAmount(AppStore store, DateTime reference) {
    final salesProfit = store.sales
        .where((sale) => _isSameDay(sale.date, reference) && !sale.isDeleted)
        .fold<double>(0, (sum, sale) => sum + sale.grossProfit);
    final expenses = store.expenses
        .where((expense) =>
            expense.isPosted &&
            !expense.isDeleted &&
            _isSameDay(expense.date, reference))
        .fold<double>(0, (sum, expense) => sum + expense.amount);
    return salesProfit - expenses;
  }

  int todayInvoiceCount(AppStore store, DateTime reference) {
    return store.sales
        .where((sale) => _isSameDay(sale.date, reference) && !sale.isDeleted)
        .length;
  }

  int lowStockCount(AppStore store) => store.lowStockCount;

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
    final lowStockProducts = store.products
        .where((product) => product.trackStock && product.isLowStock)
        .toList()
      ..sort((a, b) => a.stock.compareTo(b.stock));
    if (lowStockProducts.isNotEmpty) {
      final names =
          lowStockProducts.take(3).map((item) => item.name).join(', ');
      alerts.add(
        DashboardAlertItem(
          level: DashboardStatusLevel.warning,
          title: 'Low stock',
          message:
              '${lowStockProducts.length} product(s) need replenishment${names.isEmpty ? '' : ': $names'}',
          icon: Icons.warning_amber_rounded,
        ),
      );
    }

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

    final todayExpenses = store.expenses
        .where((expense) =>
            expense.isPosted &&
            !expense.isDeleted &&
            _isSameDay(expense.date, reference))
        .fold<double>(0, (sum, expense) => sum + expense.amount);
    final last7DaysAverage = _averageDailyExpense(store, reference, 7);
    if (todayExpenses > 0 &&
        last7DaysAverage > 0 &&
        todayExpenses > last7DaysAverage * 1.5) {
      alerts.add(
        DashboardAlertItem(
          level: DashboardStatusLevel.warning,
          title: 'High expense day',
          message:
              '${_formatMoney(todayExpenses)} today vs ${_formatMoney(last7DaysAverage)} daily average',
          icon: Icons.trending_down_outlined,
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

    if (store.blockingDataConflictCount > 0) {
      alerts.add(
        DashboardAlertItem(
          level: DashboardStatusLevel.danger,
          title: 'Blocking conflicts',
          message:
              '${store.blockingDataConflictCount} blocking conflict(s) need review',
          icon: Icons.rule_outlined,
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
        amount: store.inventoryCostValue,
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
        amount: store.totalPurchasesAmount,
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
        value: _salesTotalSince(
          store,
          reference.subtract(const Duration(days: 29)),
        ),
        color: Colors.blue,
      ),
      DashboardChartItem(
        label: 'Profit',
        value: _profitTotalSince(
          store,
          reference.subtract(const Duration(days: 29)),
        ),
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
    final start = DateTime(reference.year, reference.month, reference.day)
        .subtract(Duration(days: days - 1));
    final values = <String, double>{
      for (var i = 0; i < days; i += 1)
        _dateKey(start.add(Duration(days: i))): 0,
    };
    for (final sale in store.sales) {
      if (sale.isDeleted || sale.isCancelled) continue;
      final date = sale.date.toLocal();
      if (date.isBefore(start) || date.isAfter(reference)) continue;
      final key = _dateKey(date);
      values[key] = (values[key] ?? 0) + sale.total;
    }
    return values.entries
        .map(
          (entry) => DashboardChartItem(
            label: _shortDateLabel(entry.key),
            value: entry.value,
            color: Colors.blue,
          ),
        )
        .toList(growable: false);
  }

  double _salesTotalSince(AppStore store, DateTime from) {
    return store.sales
        .where((sale) =>
            !sale.isDeleted &&
            !sale.isCancelled &&
            !sale.date.toLocal().isBefore(from))
        .fold<double>(0, (sum, sale) => sum + sale.total);
  }

  double _profitTotalSince(AppStore store, DateTime from) {
    final salesProfit = store.sales
        .where((sale) =>
            !sale.isDeleted &&
            !sale.isCancelled &&
            !sale.date.toLocal().isBefore(from))
        .fold<double>(0, (sum, sale) => sum + sale.grossProfit);
    final expenses = store.expenses
        .where((expense) =>
            expense.isPosted &&
            !expense.isDeleted &&
            !expense.date.toLocal().isBefore(from))
        .fold<double>(0, (sum, expense) => sum + expense.amount);
    return salesProfit - expenses;
  }

  List<DashboardChartItem> _groupExpensesByCategory(AppStore store, int limit) {
    final totals = <String, double>{};
    for (final expense in store.expenses) {
      if (!expense.isPosted || expense.isDeleted) continue;
      final key = expense.category.trim().isEmpty
          ? 'Unspecified'
          : expense.category.trim();
      totals[key] = (totals[key] ?? 0) + expense.amount;
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .take(limit)
        .map(
          (entry) => DashboardChartItem(
            label: entry.key,
            value: entry.value,
            color: Colors.deepOrange,
          ),
        )
        .toList(growable: false);
  }

  List<DashboardChartItem> _topProductsByQuantity(AppStore store, int limit) {
    final totals = <String, double>{};
    for (final sale in store.sales) {
      if (sale.isDeleted || sale.isCancelled) continue;
      for (final item in sale.items) {
        totals[item.productName] =
            (totals[item.productName] ?? 0) + item.quantity;
      }
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .take(limit)
        .map(
          (entry) => DashboardChartItem(
            label: entry.key,
            value: entry.value,
            color: Colors.purple,
          ),
        )
        .toList(growable: false);
  }

  List<DashboardChartItem> _topCustomersBySales(AppStore store, int limit) {
    final totals = <String, double>{};
    for (final sale in store.sales) {
      if (sale.isDeleted || sale.isCancelled) continue;
      final name = sale.customerName.trim().isEmpty
          ? 'Walk-in customer'
          : sale.customerName.trim();
      totals[name] = (totals[name] ?? 0) + sale.total;
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .take(limit)
        .map(
          (entry) => DashboardChartItem(
            label: entry.key,
            value: entry.value,
            color: Colors.teal,
          ),
        )
        .toList(growable: false);
  }

  List<DashboardOperationItem> recentOperations(
    AppStore store, {
    DateTime? reference,
    int limit = 5,
  }) {
    final items = <DashboardOperationItem>[
      for (final sale in store.sales.where((item) => !item.isDeleted).take(20))
        DashboardOperationItem(
          type: DashboardOperationType.sale,
          title: sale.invoiceNo,
          subtitle:
              sale.customerName.trim().isEmpty ? 'Sale' : sale.customerName,
          amount: sale.total,
          at: sale.date,
        ),
      for (final purchase
          in store.purchases.where((item) => !item.isDeleted).take(20))
        DashboardOperationItem(
          type: DashboardOperationType.purchase,
          title: purchase.purchaseNo,
          subtitle: purchase.supplierName.trim().isEmpty
              ? 'Purchase'
              : purchase.supplierName,
          amount: purchase.subtotal,
          at: purchase.date,
        ),
      for (final expense
          in store.expenses.where((item) => !item.isDeleted).take(20))
        DashboardOperationItem(
          type: DashboardOperationType.expense,
          title: expense.title,
          subtitle: expense.category,
          amount: expense.amount,
          at: expense.date,
        ),
      for (final movement in store.stockMovements.take(20))
        DashboardOperationItem(
          type: DashboardOperationType.stockMovement,
          title: movement.type,
          subtitle: movement.productName,
          amount: movement.quantity.abs(),
          at: movement.date,
        ),
      for (final transaction in store.accountTransactions
          .where((item) => !item.isDeleted)
          .take(20))
        DashboardOperationItem(
          type: DashboardOperationType.payment,
          title: transaction.referenceNo.trim().isEmpty
              ? transaction.type
              : transaction.referenceNo,
          subtitle: transaction.accountName,
          amount: (transaction.debit - transaction.credit).abs(),
          at: transaction.date,
        ),
    ];

    items.sort((a, b) => b.at.compareTo(a.at));
    return items.take(limit).toList(growable: false);
  }

  DashboardHealthSnapshot syncStatus(
    AppStore store, {
    DateTime? reference,
  }) {
    final pending = store.pendingSyncCount;
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

  double _averageDailyExpense(AppStore store, DateTime reference, int days) {
    if (days <= 0) return 0;
    final start = reference.subtract(Duration(days: days - 1));
    final total = store.expenses
        .where((expense) =>
            expense.isPosted &&
            !expense.isDeleted &&
            !expense.date.isBefore(start) &&
            !expense.date.isAfter(reference))
        .fold<double>(0, (sum, expense) => sum + expense.amount);
    return total / days;
  }

  String _formatMoney(double value) {
    final normalized = value.isFinite ? value : 0;
    return normalized.toStringAsFixed(2);
  }

  String _dateKey(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  String _shortDateLabel(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length != 3) return dateKey;
    return '${parts[1]}/${parts[2]}';
  }

  bool _isSameDay(DateTime left, DateTime right) {
    final a = left.toLocal();
    final b = right.toLocal();
    return a.year == b.year && a.month == b.month && a.day == b.day;
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
