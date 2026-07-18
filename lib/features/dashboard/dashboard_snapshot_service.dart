import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/services/accounting_aging_service.dart';
import '../../core/services/accounting_service.dart';
import '../../core/services/google_drive_backup_service.dart';
import '../../core/services/local_auto_backup_service.dart';
import '../../core/services/local_database_service.dart';
import '../../core/services/startup_timing_service.dart';
import '../../data/app_store.dart';
import 'dashboard_service.dart';

class DashboardSnapshotService {
  const DashboardSnapshotService();
  static const String _cacheKey = 'dashboard_snapshot_summary_v2';
  static final Map<String, Future<Map<String, Object?>>> _summaryFutures =
      <String, Future<Map<String, Object?>>>{};

  @visibleForTesting
  static Map<String, Object?> computeSnapshotForTesting(
    Map<String, Object?> input,
  ) =>
      _computeSnapshot(input);

  String _summaryFutureKey(AppStore store, DateTime reference) =>
      '${store.appIdentity.storeId}:${store.dashboardRevision}:${reference.year}-${reference.month}-${reference.day}';

  Future<DashboardSnapshotCache?> loadCachedSummary({
    required String storeId,
  }) async {
    final raw = LocalDatabaseService.getString(_cacheKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = decoded.cast<String, Object?>();
      final summary = map['summary'];
      final cachedStoreId = _stringValue(map['storeId']);
      final dashboardRevision = map.containsKey('dashboardRevision')
          ? _intValue(map['dashboardRevision'])
          : map.containsKey('storeRevision')
              ? _intValue(map['storeRevision'])
              : null;
      final referenceUtc = _parseDate(map['referenceUtc'])?.toUtc();
      final savedAtUtc = _parseDate(map['savedAtUtc'])?.toUtc();
      if (summary is Map &&
          dashboardRevision != null &&
          cachedStoreId == storeId) {
        return DashboardSnapshotCache(
          storeId: cachedStoreId,
          dashboardRevision: dashboardRevision,
          referenceUtc: referenceUtc ?? DateTime.now().toUtc(),
          savedAtUtc: savedAtUtc ?? DateTime.now().toUtc(),
          summary: Map<String, Object?>.from(summary),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCachedSummary(
    Map<String, Object?> summary, {
    required String storeId,
    required int dashboardRevision,
    required DateTime reference,
  }) async {
    await LocalDatabaseService.setString(
      _cacheKey,
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'storeId': storeId,
        'dashboardRevision': dashboardRevision,
        'storeRevision': dashboardRevision,
        'savedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'referenceUtc': reference.toUtc().toIso8601String(),
        'summary': summary,
      }),
    );
  }

  Future<DashboardState> buildState(
    AppStore store, {
    DateTime? now,
  }) async {
    final reference = (now ?? DateTime.now()).toLocal();
    final summary = await StartupTimingService.measure(
      'dashboard.snapshot_build',
      () async {
        final computed = await StartupTimingService.measure(
          'dashboard.compute_snapshot',
          () => _summaryFutureFor(store, reference),
          category: 'dashboard',
        );
        return computed;
      },
      category: 'dashboard',
    );
    return _assembleState(store, reference: reference, summary: summary);
  }

  Future<void> prewarmSummary(AppStore store, {DateTime? now}) async {
    final reference = (now ?? DateTime.now()).toLocal();
    _summaryFutureFor(store, reference);
  }

  Future<DashboardState> buildStateFromCachedSummary(
    AppStore store,
    DashboardSnapshotCache snapshot, {
    DateTime? now,
  }) async {
    final reference = (now ?? DateTime.now()).toLocal();
    return _assembleState(store,
        reference: reference, summary: snapshot.summary);
  }

  Future<DashboardState> buildQuickStateFromCachedSummary(
    AppStore store,
    DashboardSnapshotCache snapshot, {
    DateTime? now,
  }) async {
    final reference = (now ?? DateTime.now()).toLocal();
    final summary = snapshot.summary;
    final syncStatus = _syncStatus(
      store,
      pendingSyncCount: _intValue(summary['pendingSyncCount']),
      reference: reference,
    );
    final backupStatus = _backupStatus(reference: reference);
    final alerts = _alertsFromSummary(summary);
    final financialSummary = <DashboardFinancialItem>[
      DashboardFinancialItem(
        key: 'today_sales',
        title: 'Today sales',
        amount: _doubleValue(summary['todaySalesTotal']),
        icon: Icons.shopping_cart_outlined,
      ),
      DashboardFinancialItem(
        key: 'today_profit',
        title: 'Today profit',
        amount: _doubleValue(summary['todayProfitTotal']),
        icon: Icons.trending_up_outlined,
        level: _doubleValue(summary['todayProfitTotal']) < 0
            ? DashboardStatusLevel.danger
            : DashboardStatusLevel.healthy,
      ),
      DashboardFinancialItem(
        key: 'inventory',
        title: 'Inventory',
        amount: _doubleValue(summary['inventoryCostValue']),
        icon: Icons.warehouse_outlined,
      ),
      DashboardFinancialItem(
        key: 'purchases',
        title: 'Purchases',
        amount: _doubleValue(summary['totalPurchasesAmount']),
        icon: Icons.shopping_cart_outlined,
      ),
      DashboardFinancialItem(
        key: 'expenses',
        title: 'Expenses',
        amount: _doubleValue(summary['totalExpensesAmount']),
        icon: Icons.money_off_csred_outlined,
      ),
    ];
    final charts = <DashboardChartSeries>[
      DashboardChartSeries(
        key: 'sales_7d',
        title: 'Sales last 7 days',
        items: _resolveSalesSeries(
          store,
          reference,
          summary['salesLast7Days'],
          days: 7,
        ),
      ),
      DashboardChartSeries(
        key: 'sales_30d',
        title: 'Sales last 30 days',
        items: _resolveSalesSeries(
          store,
          reference,
          summary['salesLast30Days'],
          days: 30,
        ),
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
        items:
            _seriesFromSummaryList(summary['topCustomers'], color: Colors.teal),
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
      currentCashTotal: 0,
      lowStockCount: _intValue(summary['lowStockCount']),
      alerts: alerts,
      financialSummary: financialSummary,
      charts: charts,
      recentOperations:
          _recentOperations(summary['recentOperations'] as List<dynamic>?),
      syncStatus: syncStatus,
      backupStatus: backupStatus,
      isHydrated: false,
    );
  }

  Future<DashboardState> _assembleState(
    AppStore store, {
    required DateTime reference,
    required Map<String, Object?> summary,
  }) async {
    final customerAging = await StartupTimingService.measure(
      'dashboard.customer_aging',
      () => AccountingAgingService.customerAgingReport(asOfDate: reference),
      category: 'dashboard',
    );
    final supplierAging = await StartupTimingService.measure(
      'dashboard.supplier_aging',
      () => AccountingAgingService.supplierAgingReport(asOfDate: reference),
      category: 'dashboard',
    );
    final cashTotals = await StartupTimingService.measure(
      'dashboard.cash_totals',
      _currentCashTotals,
      category: 'dashboard',
    );
    final accountingSummary = await StartupTimingService.measure(
      'dashboard.accounting_summary',
      AccountingService.incomeStatementReport,
      category: 'dashboard',
    );

    final syncStatus = await StartupTimingService.measure(
      'dashboard.sync_status',
      () => _syncStatus(
        store,
        pendingSyncCount: _intValue(summary['pendingSyncCount']),
        reference: reference,
      ),
      category: 'dashboard',
    );
    final backupStatus = await StartupTimingService.measure(
      'dashboard.backup_status',
      () => _backupStatus(reference: reference),
      category: 'dashboard',
    );

    final alerts = await StartupTimingService.measure(
      'dashboard.alerts',
      () => <DashboardAlertItem>[
        ..._alertsFromSummary(summary),
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
        if (backupStatus.level != DashboardStatusLevel.healthy)
          DashboardAlertItem(
            level: backupStatus.level,
            title: 'Backup attention',
            message: backupStatus.detail,
            icon: Icons.backup_outlined,
          ),
        if (syncStatus.level != DashboardStatusLevel.healthy)
          DashboardAlertItem(
            level: syncStatus.level,
            title: 'Sync attention',
            message: syncStatus.detail,
            icon: Icons.sync_problem_outlined,
          ),
      ],
      category: 'dashboard',
    );

    final financialSummary = await StartupTimingService.measure(
      'dashboard.financial_summary',
      () => <DashboardFinancialItem>[
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
      ],
      category: 'dashboard',
    );

    final charts = await StartupTimingService.measure(
      'dashboard.charts',
      () => <DashboardChartSeries>[
        DashboardChartSeries(
          key: 'sales_7d',
          title: 'Sales last 7 days',
          items: _resolveSalesSeries(
            store,
            reference,
            summary['salesLast7Days'],
            days: 7,
          ),
        ),
        DashboardChartSeries(
          key: 'sales_30d',
          title: 'Sales last 30 days',
          items: _resolveSalesSeries(
            store,
            reference,
            summary['salesLast30Days'],
            days: 30,
          ),
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
      ],
      category: 'dashboard',
    );

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
      recentOperations:
          _recentOperations(summary['recentOperations'] as List<dynamic>?),
      syncStatus: syncStatus,
      backupStatus: backupStatus,
    );
  }

  Future<CashBalanceTotals> _currentCashTotals() async {
    if (!AccountingService.isAvailable) return CashBalanceTotals();
    try {
      final rows = await AccountingService.listCashBalancesReport();
      final totals = CashBalanceTotals();
      for (final item in rows.where((item) => item.isActive)) {
        final type = item.type.trim().toLowerCase();
        if (type == 'bank') {
          totals.bank += item.balance;
        } else if (type == 'card' ||
            type == 'wallet' ||
            type == 'cheque' ||
            type == 'other') {
          totals.cards += item.balance;
        } else {
          totals.cash += item.balance;
        }
      }
      return totals;
    } catch (_) {
      return CashBalanceTotals();
    }
  }

  DashboardHealthSnapshot _syncStatus(
    AppStore store, {
    required int pendingSyncCount,
    required DateTime reference,
  }) {
    if (store.isSuspendedByHost) {
      return DashboardHealthSnapshot(
        level: DashboardStatusLevel.danger,
        title: 'Sync paused',
        detail: store.suspendedByHostReason,
        pendingCount: pendingSyncCount,
        lastUpdatedAt: reference,
      );
    }
    if (pendingSyncCount > 0) {
      return DashboardHealthSnapshot(
        level: DashboardStatusLevel.warning,
        title: 'Sync pending',
        detail: '$pendingSyncCount pending change(s)',
        pendingCount: pendingSyncCount,
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

  DashboardHealthSnapshot _backupStatus({DateTime? reference}) {
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

  DateTime? _latestDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  Future<Map<String, Object?>> _summaryFutureFor(
    AppStore store,
    DateTime reference,
  ) {
    final key = _summaryFutureKey(store, reference);
    final existing = _summaryFutures[key];
    if (existing != null) return existing;
    final future = _computeAndCacheSummary(store, reference);
    _summaryFutures[key] = future;
    future.whenComplete(() {
      if (_summaryFutures[key] == future) {
        _summaryFutures.remove(key);
      }
    });
    return future;
  }

  Future<Map<String, Object?>> _computeAndCacheSummary(
    AppStore store,
    DateTime reference,
  ) async {
    if (store.isHeavyDataLoaded) {
      final computed = await StartupTimingService.measure(
        'dashboard.snapshot_memory_summary',
        () async => _computeSnapshotFromStore(store, reference),
        category: 'dashboard',
      );
      await _saveCachedSummary(
        computed,
        storeId: store.appIdentity.storeId,
        dashboardRevision: store.dashboardRevision,
        reference: reference,
      );
      return computed;
    }
    if (LocalDatabaseService.canQueryBusinessSqlite) {
      try {
        final sqliteSummary = await StartupTimingService.measure(
          'dashboard.snapshot_sql_summary',
          () => LocalDatabaseService.buildDashboardSummaryFromSqlite(
            reference: reference,
          ),
          category: 'dashboard',
        );
        if (sqliteSummary != null) {
          await _saveCachedSummary(
            sqliteSummary,
            storeId: store.appIdentity.storeId,
            dashboardRevision: store.dashboardRevision,
            reference: reference,
          );
          return sqliteSummary;
        }
      } catch (_) {
        // Keep the runtime SQLite-first. If the typed SQL path fails, use the
        // already loaded in-memory store instead of raw JSON.
      }
    }
    final computed = await StartupTimingService.measure(
      'dashboard.snapshot_store_summary',
      () async => _computeSnapshotFromStore(store, reference),
      category: 'dashboard',
    );
    await _saveCachedSummary(
      computed,
      storeId: store.appIdentity.storeId,
      dashboardRevision: store.dashboardRevision,
      reference: reference,
    );
    return computed;
  }

  // ignore: unused_element
  Future<Map<String, Object?>> _computeSnapshotFromStore(
    AppStore store,
    DateTime reference,
  ) async {
    final today = DateTime(reference.year, reference.month, reference.day);
    final start7 = today.subtract(const Duration(days: 6));
    final start30 = today.subtract(const Duration(days: 29));

    final products = store.products;
    final sales = store.sales;
    final purchases = store.purchases;
    final expenses = store.expenses;
    final stockMovements = store.stockMovements;
    final accountTransactions = store.accountTransactions;
    final syncQueue = store.syncQueue;

    final sales7 = _dateMap(start7, 7);
    final sales30 = _dateMap(start30, 30);
    final topProducts = <String, double>{};
    final topCustomers = <String, double>{};
    final expenseCategories = <String, double>{};
    final recentOps = <Map<String, Object?>>[];
    final recentStockMovements = <Map<String, Object?>>[];
    final lowStockNames = <String>[];
    final codeCounts = <String, int>{};
    final barcodeCounts = <String, int>{};

    var todaySalesTotal = 0.0;
    var todayProfitTotal = 0.0;
    var todayInvoiceCount = 0;
    var salesSince30Days = 0.0;
    var profitSince30Days = 0.0;
    var totalPurchasesAmount = 0.0;
    var totalExpensesAmount = 0.0;
    var inventoryCostValue = 0.0;
    var lowStockCount = 0;
    var pendingSyncCount = 0;
    var todayExpenseTotal = 0.0;
    final expenseDailyTotals = <String, double>{};

    for (final product in products) {
      if (product.isDeleted) continue;
      final code = product.code.trim().toLowerCase();
      if (code.isNotEmpty) {
        codeCounts[code] = (codeCounts[code] ?? 0) + 1;
      }
      final barcode = product.barcode.trim().toLowerCase();
      if (barcode.isNotEmpty) {
        barcodeCounts[barcode] = (barcodeCounts[barcode] ?? 0) + 1;
      }
      if (!product.trackStock) continue;
      final stock = product.stock;
      inventoryCostValue += product.usdCost * stock;
      if (stock <= product.lowStockThreshold) {
        lowStockCount += 1;
        final name =
            product.name.trim().isEmpty ? 'Product' : product.name.trim();
        lowStockNames.add(name);
      }
    }
    await Future<void>.delayed(Duration.zero);

    for (final sale in sales) {
      if (sale.isDeleted || sale.isCancelled) continue;
      final date = sale.date;
      final day = DateTime(date.year, date.month, date.day);
      final total = sale.effectiveTransactionAmount > 0
          ? sale.effectiveTransactionAmount
          : sale.total;
      final grossProfit = sale.grossProfit;
      if (_isSameDay(day, today)) {
        todaySalesTotal += total;
        todayProfitTotal += grossProfit;
        todayInvoiceCount += 1;
      }
      if (!day.isBefore(start30)) {
        salesSince30Days += total;
        profitSince30Days += grossProfit;
      }
      final key = _dateKey(day);
      if (sales7.containsKey(key)) sales7[key] = (sales7[key] ?? 0) + total;
      if (sales30.containsKey(key)) sales30[key] = (sales30[key] ?? 0) + total;
      final customerName = sale.customerName.trim().isEmpty
          ? 'Walk-in customer'
          : sale.customerName.trim();
      topCustomers[customerName] = (topCustomers[customerName] ?? 0) + total;
      for (final item in sale.items) {
        final name = item.productName.trim();
        if (name.isEmpty) continue;
        topProducts[name] = (topProducts[name] ?? 0) + item.quantity;
      }
      recentOps.add(<String, Object?>{
        'type': 'sale',
        'title': sale.invoiceNo,
        'subtitle': customerName,
        'amount': total,
        'at': date.toIso8601String(),
      });
    }
    await Future<void>.delayed(Duration.zero);

    for (final purchase in purchases) {
      if (purchase.isDeleted || purchase.isCancelled) continue;
      final date = purchase.date;
      final subtotal = purchase.subtotal;
      totalPurchasesAmount += subtotal;
      recentOps.add(<String, Object?>{
        'type': 'purchase',
        'title': purchase.purchaseNo,
        'subtitle': purchase.supplierName.trim().isEmpty
            ? 'Purchase'
            : purchase.supplierName.trim(),
        'amount': subtotal,
        'at': date.toIso8601String(),
      });
    }
    await Future<void>.delayed(Duration.zero);

    for (final expense in expenses) {
      if (expense.isDeleted || !expense.isPosted) continue;
      final date = expense.date;
      final amount = expense.amount;
      totalExpensesAmount += amount;
      final category = expense.category.trim().isEmpty
          ? 'Unspecified'
          : expense.category.trim();
      expenseCategories[category] = (expenseCategories[category] ?? 0) + amount;
      final key = _dateKey(DateTime(date.year, date.month, date.day));
      expenseDailyTotals[key] = (expenseDailyTotals[key] ?? 0) + amount;
      if (_isSameDay(date, today)) {
        todayExpenseTotal += amount;
      }
      recentOps.add(<String, Object?>{
        'type': 'expense',
        'title': expense.title,
        'subtitle': category,
        'amount': amount,
        'at': date.toIso8601String(),
      });
    }
    await Future<void>.delayed(Duration.zero);

    for (final raw in stockMovements) {
      final date = raw.date;
      final qty = raw.quantity;
      recentStockMovements.add(<String, Object?>{
        'type': raw.type,
        'title': raw.productName.isEmpty ? 'Movement' : raw.productName,
        'subtitle': raw.referenceNo,
        'amount': qty.abs(),
        'at': date.toIso8601String(),
      });
      recentOps.add(<String, Object?>{
        'type': 'stockMovement',
        'title': raw.type.isEmpty ? 'Movement' : raw.type,
        'subtitle': raw.productName,
        'amount': qty.abs(),
        'at': date.toIso8601String(),
      });
    }
    await Future<void>.delayed(Duration.zero);

    for (final txn in accountTransactions) {
      if (txn.isDeleted) continue;
      recentOps.add(<String, Object?>{
        'type': 'payment',
        'title': txn.referenceNo.isEmpty
            ? (txn.type.isEmpty ? 'Payment' : txn.type)
            : txn.referenceNo,
        'subtitle': txn.accountName,
        'amount': (txn.debit - txn.credit).abs(),
        'at': txn.date.toIso8601String(),
      });
    }
    await Future<void>.delayed(Duration.zero);

    for (final item in syncQueue) {
      if (item.isPending) pendingSyncCount += 1;
    }

    recentOps.sort((a, b) {
      final aDate = DateTime.tryParse(a['at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse(b['at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    final duplicateCodeCount =
        codeCounts.values.where((count) => count > 1).length;
    final duplicateBarcodeCount =
        barcodeCounts.values.where((count) => count > 1).length;
    final expenseList = expenseCategories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topProductList = topProducts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCustomerList = topCustomers.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return <String, Object?>{
      'todaySalesTotal': todaySalesTotal,
      'todayProfitTotal': todayProfitTotal,
      'todayInvoiceCount': todayInvoiceCount,
      'salesSince30Days': salesSince30Days,
      'profitSince30Days': profitSince30Days,
      'salesLast7Days': sales7.entries
          .map((entry) => <String, Object?>{
                'label': _shortDateLabel(entry.key),
                'value': entry.value,
              })
          .toList(growable: false),
      'salesLast30Days': sales30.entries
          .map((entry) => <String, Object?>{
                'label': _shortDateLabel(entry.key),
                'value': entry.value,
              })
          .toList(growable: false),
      'expenseCategories': expenseList
          .map((entry) => <String, Object?>{
                'label': entry.key,
                'value': entry.value,
              })
          .toList(growable: false),
      'topProducts': topProductList
          .map((entry) => <String, Object?>{
                'label': entry.key,
                'value': entry.value,
              })
          .toList(growable: false),
      'topCustomers': topCustomerList
          .map((entry) => <String, Object?>{
                'label': entry.key,
                'value': entry.value,
              })
          .toList(growable: false),
      'recentOperations': recentOps.take(5).toList(growable: false),
      'recentStockMovements':
          recentStockMovements.take(8).toList(growable: false),
      'totalPurchasesAmount': totalPurchasesAmount,
      'totalExpensesAmount': totalExpensesAmount,
      'inventoryCostValue': inventoryCostValue,
      'lowStockCount': lowStockCount,
      'lowStockNames': lowStockNames,
      'todayExpenseTotal': todayExpenseTotal,
      'last7ExpenseAverage': _averageForWindow(expenseDailyTotals, start7, 7),
      'pendingSyncCount': pendingSyncCount,
      'blockingConflictCount': duplicateCodeCount + duplicateBarcodeCount,
    };
  }

  static Map<String, Object?> _computeSnapshot(
    Map<String, Object?> input,
  ) {
    final reference = DateTime.tryParse(input['reference']?.toString() ?? '') ??
        DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final start7 = today.subtract(const Duration(days: 6));
    final start30 = today.subtract(const Duration(days: 29));
    final products = _decodeJsonListPayload(
      input['productsJson']?.toString() ?? '[]',
    );
    final sales =
        _decodeJsonListPayload(input['salesJson']?.toString() ?? '[]');
    final purchases =
        _decodeJsonListPayload(input['purchasesJson']?.toString() ?? '[]');
    final expenses =
        _decodeJsonListPayload(input['expensesJson']?.toString() ?? '[]');
    final stockMovements = _decodeJsonListPayload(
      input['stockMovementsJson']?.toString() ?? '[]',
    );
    final accountTransactions = _decodeJsonListPayload(
      input['accountTransactionsJson']?.toString() ?? '[]',
    );
    final syncQueue =
        _decodeJsonListPayload(input['syncQueueJson']?.toString() ?? '[]');

    final sales7 = _dateMap(start7, 7);
    final sales30 = _dateMap(start30, 30);
    final topProducts = <String, double>{};
    final topCustomers = <String, double>{};
    final expenseCategories = <String, double>{};
    final recentOps = <Map<String, Object?>>[];
    final recentStockMovements = <Map<String, Object?>>[];
    final lowStockNames = <String>[];
    final codeCounts = <String, int>{};
    final barcodeCounts = <String, int>{};

    var todaySalesTotal = 0.0;
    var todayProfitTotal = 0.0;
    var todayInvoiceCount = 0;
    var salesSince30Days = 0.0;
    var profitSince30Days = 0.0;
    var totalPurchasesAmount = 0.0;
    var totalExpensesAmount = 0.0;
    var inventoryCostValue = 0.0;
    var lowStockCount = 0;
    var pendingSyncCount = 0;
    var todayExpenseTotal = 0.0;
    final expenseDailyTotals = <String, double>{};

    for (final raw in products) {
      if (_isDeleted(raw)) continue;
      final code = _normalizedKey(raw['code']);
      if (code.isNotEmpty) codeCounts[code] = (codeCounts[code] ?? 0) + 1;
      final barcode = _normalizedKey(raw['barcode']);
      if (barcode.isNotEmpty) {
        barcodeCounts[barcode] = (barcodeCounts[barcode] ?? 0) + 1;
      }
      if (!_boolValue(raw['trackStock'], fallback: true)) continue;
      final stock = _doubleValue(raw['stock']);
      final threshold = _doubleValue(raw['lowStockThreshold'], fallback: 5);
      inventoryCostValue +=
          _doubleValue(raw['usdCost'], fallback: _doubleValue(raw['cost'])) *
              stock;
      if (stock <= threshold) {
        lowStockCount += 1;
        final name = _stringValue(raw['name'],
            fallback: _stringValue(raw['nameEn'],
                fallback: _stringValue(raw['nameAr'], fallback: 'Product')));
        lowStockNames.add(name);
      }
    }

    for (final raw in sales) {
      if (_isDeleted(raw) || _isCancelledStatus(raw['status'])) continue;
      final date = _parseDate(raw['date']);
      if (date == null) continue;
      final day = DateTime(date.year, date.month, date.day);
      final total = _saleTotal(raw);
      final grossProfit = _saleGrossProfit(raw);
      if (_isSameDay(day, today)) {
        todaySalesTotal += total;
        todayProfitTotal += grossProfit;
        todayInvoiceCount += 1;
      }
      if (!day.isBefore(start30)) {
        salesSince30Days += total;
        profitSince30Days += grossProfit;
      }
      final key = _dateKey(day);
      if (sales7.containsKey(key)) sales7[key] = (sales7[key] ?? 0) + total;
      if (sales30.containsKey(key)) sales30[key] = (sales30[key] ?? 0) + total;
      final customerName =
          _stringValue(raw['customerName'], fallback: 'Walk-in customer');
      topCustomers[customerName] = (topCustomers[customerName] ?? 0) + total;
      final items = raw['items'] as List<dynamic>? ?? const <dynamic>[];
      for (final item in items) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final name = _stringValue(map['productName']);
        if (name.isEmpty) continue;
        topProducts[name] =
            (topProducts[name] ?? 0) + _doubleValue(map['quantity']);
      }
      recentOps.add(<String, Object?>{
        'type': 'sale',
        'title': _stringValue(raw['invoiceNo']),
        'subtitle': customerName,
        'amount': total,
        'at': date.toIso8601String(),
      });
    }

    for (final raw in purchases) {
      if (_isDeleted(raw) || _isCancelledStatus(raw['status'])) continue;
      final date = _parseDate(raw['date']);
      if (date == null) continue;
      final subtotal =
          _doubleValue(raw['subtotal'], fallback: _sumItems(raw['items']));
      totalPurchasesAmount += subtotal;
      recentOps.add(<String, Object?>{
        'type': 'purchase',
        'title': _stringValue(raw['purchaseNo']),
        'subtitle': _stringValue(raw['supplierName'], fallback: 'Purchase'),
        'amount': subtotal,
        'at': date.toIso8601String(),
      });
    }

    for (final raw in expenses) {
      if (_isDeleted(raw) || !_isPostedExpense(raw)) continue;
      final date = _parseDate(raw['date']);
      if (date == null) continue;
      final amount = _doubleValue(raw['amount']);
      totalExpensesAmount += amount;
      expenseCategories[
              _stringValue(raw['category'], fallback: 'Unspecified')] =
          (expenseCategories[
                      _stringValue(raw['category'], fallback: 'Unspecified')] ??
                  0) +
              amount;
      final key = _dateKey(DateTime(date.year, date.month, date.day));
      expenseDailyTotals[key] = (expenseDailyTotals[key] ?? 0) + amount;
      if (_isSameDay(date, today)) {
        todayExpenseTotal += amount;
      }
      recentOps.add(<String, Object?>{
        'type': 'expense',
        'title': _stringValue(raw['title']),
        'subtitle': _stringValue(raw['category'], fallback: 'Unspecified'),
        'amount': amount,
        'at': date.toIso8601String(),
      });
    }

    for (final raw in stockMovements) {
      final date = _parseDate(raw['date']);
      if (date == null) continue;
      final qty = _doubleValue(raw['quantity']);
      recentStockMovements.add(<String, Object?>{
        'type': _stringValue(raw['type'], fallback: 'movement'),
        'title': _stringValue(raw['productName'], fallback: 'Movement'),
        'subtitle': _stringValue(raw['referenceNo']),
        'amount': qty.abs(),
        'at': date.toIso8601String(),
      });
      recentOps.add(<String, Object?>{
        'type': 'stockMovement',
        'title': _stringValue(raw['type'], fallback: 'Movement'),
        'subtitle': _stringValue(raw['productName']),
        'amount': qty.abs(),
        'at': date.toIso8601String(),
      });
    }

    for (final raw in accountTransactions) {
      if (_isDeleted(raw)) continue;
      final date = _parseDate(raw['date']);
      if (date == null) continue;
      recentOps.add(<String, Object?>{
        'type': 'payment',
        'title': _stringValue(raw['referenceNo'],
            fallback: _stringValue(raw['type'], fallback: 'Payment')),
        'subtitle': _stringValue(raw['accountName']),
        'amount':
            (_doubleValue(raw['debit']) - _doubleValue(raw['credit'])).abs(),
        'at': date.toIso8601String(),
      });
    }

    for (final raw in syncQueue) {
      if (_isPendingSyncQueueItem(raw)) pendingSyncCount += 1;
    }

    recentOps.sort((a, b) {
      final aDate = DateTime.tryParse(a['at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse(b['at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    final duplicateCodeCount =
        codeCounts.values.where((count) => count > 1).length;
    final duplicateBarcodeCount =
        barcodeCounts.values.where((count) => count > 1).length;
    final expenseList = expenseCategories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topProductList = topProducts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCustomerList = topCustomers.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return <String, Object?>{
      'todaySalesTotal': todaySalesTotal,
      'todayProfitTotal': todayProfitTotal,
      'todayInvoiceCount': todayInvoiceCount,
      'salesSince30Days': salesSince30Days,
      'profitSince30Days': profitSince30Days,
      'salesLast7Days': sales7.entries
          .map((entry) => <String, Object?>{
                'label': _shortDateLabel(entry.key),
                'value': entry.value
              })
          .toList(growable: false),
      'salesLast30Days': sales30.entries
          .map((entry) => <String, Object?>{
                'label': _shortDateLabel(entry.key),
                'value': entry.value
              })
          .toList(growable: false),
      'expenseCategories': expenseList
          .map((entry) =>
              <String, Object?>{'label': entry.key, 'value': entry.value})
          .toList(growable: false),
      'topProducts': topProductList
          .map((entry) =>
              <String, Object?>{'label': entry.key, 'value': entry.value})
          .toList(growable: false),
      'topCustomers': topCustomerList
          .map((entry) =>
              <String, Object?>{'label': entry.key, 'value': entry.value})
          .toList(growable: false),
      'recentOperations': recentOps.take(5).toList(growable: false),
      'recentStockMovements':
          recentStockMovements.take(8).toList(growable: false),
      'totalPurchasesAmount': totalPurchasesAmount,
      'totalExpensesAmount': totalExpensesAmount,
      'inventoryCostValue': inventoryCostValue,
      'lowStockCount': lowStockCount,
      'lowStockNames': lowStockNames,
      'todayExpenseTotal': todayExpenseTotal,
      'last7ExpenseAverage': _averageForWindow(expenseDailyTotals, start7, 7),
      'pendingSyncCount': pendingSyncCount,
      'blockingConflictCount': duplicateCodeCount + duplicateBarcodeCount,
    };
  }

  static List<Map<String, dynamic>> _decodeJsonListPayload(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) return const <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  static List<DashboardAlertItem> _alertsFromSummary(
      Map<String, Object?> summary) {
    final alerts = <DashboardAlertItem>[];
    final lowStockCount = _intValue(summary['lowStockCount']);
    final lowStockNames =
        (summary['lowStockNames'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => item.toString())
            .take(3)
            .toList(growable: false);
    if (lowStockCount > 0) {
      alerts.add(
        DashboardAlertItem(
          level: DashboardStatusLevel.warning,
          title: 'Low stock',
          message:
              '$lowStockCount product(s) need replenishment${lowStockNames.isEmpty ? '' : ': ${lowStockNames.join(', ')}'}',
          icon: Icons.warning_amber_rounded,
        ),
      );
    }
    final todayExpenseTotal = _doubleValue(summary['todayExpenseTotal']);
    final last7ExpenseAverage = _doubleValue(summary['last7ExpenseAverage']);
    if (todayExpenseTotal > 0 &&
        last7ExpenseAverage > 0 &&
        todayExpenseTotal > last7ExpenseAverage * 1.5) {
      alerts.add(
        DashboardAlertItem(
          level: DashboardStatusLevel.warning,
          title: 'High expense day',
          message:
              '${todayExpenseTotal.toStringAsFixed(2)} today vs ${last7ExpenseAverage.toStringAsFixed(2)} daily average',
          icon: Icons.trending_down_outlined,
        ),
      );
    }
    if (_intValue(summary['blockingConflictCount']) > 0) {
      alerts.add(
        DashboardAlertItem(
          level: DashboardStatusLevel.danger,
          title: 'Blocking conflicts',
          message:
              '${_intValue(summary['blockingConflictCount'])} blocking conflict(s) need review',
          icon: Icons.rule_outlined,
        ),
      );
    }
    return alerts;
  }

  static List<DashboardOperationItem> _recentOperations(
    List<dynamic>? rawItems,
  ) {
    final items = <DashboardOperationItem>[];
    for (final item in rawItems ?? const <dynamic>[]) {
      if (item is! Map) continue;
      final data = Map<String, dynamic>.from(item);
      items.add(
        DashboardOperationItem(
          type: _operationTypeFromString(data['type']?.toString() ?? ''),
          title: data['title']?.toString() ?? '',
          subtitle: data['subtitle']?.toString() ?? '',
          amount: _doubleValue(data['amount']),
          at: DateTime.tryParse(data['at']?.toString() ?? '') ?? DateTime.now(),
        ),
      );
    }
    return items;
  }

  static List<DashboardChartItem> _seriesFromSummaryList(
    dynamic raw, {
    Color? color,
  }) {
    final items = <DashboardChartItem>[];
    final rows = raw is List ? raw : const <dynamic>[];
    for (final item in rows) {
      if (item is Map) {
        final data = Map<String, dynamic>.from(item);
        final label = data['label']?.toString() ?? '';
        if (label.isEmpty) continue;
        items.add(
          DashboardChartItem(
            label: label,
            value: _doubleValue(data['value']),
            color: color,
          ),
        );
      } else if (item is MapEntry) {
        final label = item.key.toString();
        items.add(
          DashboardChartItem(
            label: label,
            value: _doubleValue(item.value),
            color: color,
          ),
        );
      }
    }
    return items;
  }

  static List<DashboardChartItem> _resolveSalesSeries(
    AppStore store,
    DateTime reference,
    dynamic raw, {
    required int days,
  }) {
    final summarySeries = _seriesFromSummaryList(raw);
    if (summarySeries.any((item) => item.value > 0)) {
      return summarySeries;
    }
    final liveSeries = _salesSeriesFromStore(store, reference, days);
    if (liveSeries.any((item) => item.value > 0)) {
      return liveSeries;
    }
    return summarySeries;
  }

  static List<DashboardChartItem> _salesSeriesFromStore(
    AppStore store,
    DateTime reference,
    int days,
  ) {
    if (days <= 0) return const <DashboardChartItem>[];
    final today = DateTime(reference.year, reference.month, reference.day);
    final start = today.subtract(Duration(days: days - 1));
    final totals = <String, double>{
      for (var i = 0; i < days; i += 1)
        _dateKey(start.add(Duration(days: i))): 0,
    };
    for (final sale in store.sales) {
      if (sale.isDeleted || sale.isCancelled) continue;
      final date = sale.date.toLocal();
      if (date.isBefore(start) || date.isAfter(reference)) continue;
      final amount = sale.effectiveTransactionAmount > 0
          ? sale.effectiveTransactionAmount
          : sale.total;
      final key = _dateKey(date);
      totals[key] = (totals[key] ?? 0) + amount;
    }
    return totals.entries
        .map(
          (entry) => DashboardChartItem(
            label: _shortDateLabel(entry.key),
            value: entry.value,
            color: Colors.blue,
          ),
        )
        .toList(growable: false);
  }

  static Map<String, double> _dateMap(DateTime start, int days) {
    return <String, double>{
      for (var i = 0; i < days; i += 1)
        _dateKey(start.add(Duration(days: i))): 0,
    };
  }

  static double _averageForWindow(
    Map<String, double> totals,
    DateTime start,
    int days,
  ) {
    if (days <= 0) return 0;
    var total = 0.0;
    for (var i = 0; i < days; i += 1) {
      total += totals[_dateKey(start.add(Duration(days: i)))] ?? 0;
    }
    return total / days;
  }

  static bool _isDeleted(Map<String, dynamic> item) =>
      (item['deletedAt']?.toString() ?? '').isNotEmpty;

  static bool _isPostedExpense(Map<String, dynamic> item) {
    final status = item['status']?.toString().trim().toLowerCase() ?? '';
    return status.isEmpty || status == 'posted';
  }

  static bool _isCancelledStatus(dynamic value) {
    final status = value?.toString().trim().toLowerCase() ?? '';
    return status == 'cancelled' ||
        status == 'returned' ||
        status == 'reversed';
  }

  static bool _isPendingSyncQueueItem(Map<String, dynamic> item) {
    final status = item['status']?.toString() ?? 'pending';
    if (status == 'pending' || status == 'failed') return true;
    if (status != 'inProgress') return false;
    final updated = DateTime.tryParse(item['updatedAt']?.toString() ?? '');
    return updated == null ||
        updated.isBefore(DateTime.now().subtract(const Duration(seconds: 30)));
  }

  static double _sumItems(dynamic rawItems) {
    final items = rawItems as List<dynamic>? ?? const <dynamic>[];
    var total = 0.0;
    for (final item in items) {
      if (item is! Map) continue;
      final data = Map<String, dynamic>.from(item);
      total += _itemLineTotal(data);
    }
    return total;
  }

  static double _saleTotal(Map<String, dynamic> raw) {
    final total = _doubleValue(raw['total']);
    if (total > 0) return total;
    final subtotal = _sumItems(raw['items']);
    final discount = _doubleValue(raw['discount']);
    final computed = (subtotal - discount).clamp(0, double.infinity).toDouble();
    if (subtotal > 0 || discount > 0) return computed;
    if (_hasNumericValue(raw['transactionAmount'])) {
      final transactionAmount = _doubleValue(raw['transactionAmount']);
      if (transactionAmount != 0) return transactionAmount;
    }
    if (_hasNumericValue(raw['baseAmount'])) {
      final baseAmount = _doubleValue(raw['baseAmount']);
      if (baseAmount != 0) return baseAmount;
    }
    return total;
  }

  static double _saleGrossProfit(Map<String, dynamic> raw) {
    if (_hasNumericValue(raw['grossProfit'])) {
      return _doubleValue(raw['grossProfit']);
    }
    final items = raw['items'] as List<dynamic>? ?? const <dynamic>[];
    var profit = 0.0;
    for (final item in items) {
      if (item is! Map) continue;
      final data = Map<String, dynamic>.from(item);
      if (_hasNumericValue(data['lineProfit'])) {
        profit += _doubleValue(data['lineProfit']);
      } else {
        profit += _itemLineTotal(data) - _itemLineCost(data);
      }
    }
    return profit - _doubleValue(raw['discount']);
  }

  static double _itemLineTotal(Map<String, dynamic> item) {
    if (_hasNumericValue(item['lineTotal'])) {
      return _doubleValue(item['lineTotal']);
    }
    final unitPrice = _doubleValue(
      item['unitPrice'],
      fallback: _doubleValue(item['unitCost']),
    );
    return _doubleValue(item['quantity']) * unitPrice;
  }

  static double _itemLineCost(Map<String, dynamic> item) {
    final consumptions =
        item['costLayerConsumptions'] as List<dynamic>? ?? const <dynamic>[];
    var consumedCost = 0.0;
    for (final raw in consumptions) {
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw);
      consumedCost += _doubleValue(
        data['totalCost'],
        fallback:
            _doubleValue(data['quantity']) * _doubleValue(data['unitCost']),
      );
    }
    if (consumedCost > 0) return consumedCost;
    final conversion = _doubleValue(item['conversionToBase'], fallback: 1);
    final baseQuantity = _doubleValue(
      item['baseQuantity'],
      fallback: _doubleValue(item['quantity']) * conversion,
    );
    final unitCost = _doubleValue(
      item['unitCostAtSale'],
      fallback: _doubleValue(
        item['unitCost'],
        fallback: _doubleValue(item['costPrice']),
      ),
    );
    return unitCost * baseQuantity;
  }

  static bool _boolValue(Object? value, {bool fallback = false}) {
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase();
    if (text == null || text.isEmpty) return fallback;
    return text == 'true' || text == '1' || text == 'yes';
  }

  static double _doubleValue(Object? value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static bool _hasNumericValue(Object? value) {
    if (value is num) return value.isFinite;
    return double.tryParse(value?.toString() ?? '') != null;
  }

  static int _intValue(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _stringValue(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String _normalizedKey(Object? value) =>
      value?.toString().trim().toLowerCase() ?? '';

  static DateTime? _parseDate(Object? value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  static bool _isSameDay(DateTime left, DateTime right) {
    final a = left.toLocal();
    final b = right.toLocal();
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _dateKey(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  static String _shortDateLabel(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length != 3) return dateKey;
    return '${parts[1]}/${parts[2]}';
  }

  static DashboardOperationType _operationTypeFromString(String value) {
    switch (value) {
      case 'sale':
        return DashboardOperationType.sale;
      case 'purchase':
        return DashboardOperationType.purchase;
      case 'expense':
        return DashboardOperationType.expense;
      case 'payment':
        return DashboardOperationType.payment;
      case 'stockMovement':
        return DashboardOperationType.stockMovement;
      default:
        return DashboardOperationType.other;
    }
  }
}

class DashboardSnapshotCache {
  const DashboardSnapshotCache({
    required this.storeId,
    required this.dashboardRevision,
    required this.referenceUtc,
    required this.savedAtUtc,
    required this.summary,
  });

  final String storeId;
  final int dashboardRevision;
  final DateTime referenceUtc;
  final DateTime savedAtUtc;
  final Map<String, Object?> summary;
}
