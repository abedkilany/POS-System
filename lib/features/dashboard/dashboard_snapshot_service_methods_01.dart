part of 'dashboard_snapshot_service.dart';

extension DashboardSnapshotServiceMethods1 on DashboardSnapshotService {
  String _summaryFutureKey(AppStore store, DateTime reference) =>
      '${store.appIdentity.storeId}:${store.dashboardRevision}:${reference.year}-${reference.month}-${reference.day}';

  Future<DashboardSnapshotCache?> loadCachedSummary({
    required String storeId,
  }) async {
    final raw = LocalDatabaseService.getString(DashboardSnapshotService._cacheKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = decoded.cast<String, Object?>();
      final summary = map['summary'];
      final cachedStoreId = DashboardSnapshotService._stringValue(map['storeId']);
      final dashboardRevision = map.containsKey('dashboardRevision')
          ? DashboardSnapshotService._intValue(map['dashboardRevision'])
          : map.containsKey('storeRevision')
              ? DashboardSnapshotService._intValue(map['storeRevision'])
              : null;
      final referenceUtc = DashboardSnapshotService._parseDate(map['referenceUtc'])?.toUtc();
      final savedAtUtc = DashboardSnapshotService._parseDate(map['savedAtUtc'])?.toUtc();
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
      DashboardSnapshotService._cacheKey,
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
      pendingSyncCount: DashboardSnapshotService._intValue(summary['pendingSyncCount']),
      reference: reference,
    );
    final backupStatus = _backupStatus(reference: reference);
    final alerts = DashboardSnapshotService._alertsFromSummary(summary);
    final financialSummary = <DashboardFinancialItem>[
      DashboardFinancialItem(
        key: 'today_sales',
        title: 'Today sales',
        amount: DashboardSnapshotService._doubleValue(summary['todaySalesTotal']),
        icon: Icons.shopping_cart_outlined,
      ),
      DashboardFinancialItem(
        key: 'today_profit',
        title: 'Today profit',
        amount: DashboardSnapshotService._doubleValue(summary['todayProfitTotal']),
        icon: Icons.trending_up_outlined,
        level: DashboardSnapshotService._doubleValue(summary['todayProfitTotal']) < 0
            ? DashboardStatusLevel.danger
            : DashboardStatusLevel.healthy,
      ),
      DashboardFinancialItem(
        key: 'inventory',
        title: 'Inventory',
        amount: DashboardSnapshotService._doubleValue(summary['inventoryCostValue']),
        icon: Icons.warehouse_outlined,
      ),
      DashboardFinancialItem(
        key: 'purchases',
        title: 'Purchases',
        amount: DashboardSnapshotService._doubleValue(summary['totalPurchasesAmount']),
        icon: Icons.shopping_cart_outlined,
      ),
      DashboardFinancialItem(
        key: 'expenses',
        title: 'Expenses',
        amount: DashboardSnapshotService._doubleValue(summary['totalExpensesAmount']),
        icon: Icons.money_off_csred_outlined,
      ),
    ];
    final charts = <DashboardChartSeries>[
      DashboardChartSeries(
        key: 'sales_7d',
        title: 'Sales last 7 days',
        items: DashboardSnapshotService._resolveSalesSeries(
          store,
          reference,
          summary['salesLast7Days'],
          days: 7,
        ),
      ),
      DashboardChartSeries(
        key: 'sales_30d',
        title: 'Sales last 30 days',
        items: DashboardSnapshotService._resolveSalesSeries(
          store,
          reference,
          summary['salesLast30Days'],
          days: 30,
        ),
      ),
      DashboardChartSeries(
        key: 'expenses_type',
        title: 'Expenses by type',
        items: DashboardSnapshotService._seriesFromSummaryList(summary['expenseCategories'],
            color: Colors.deepOrange),
      ),
      DashboardChartSeries(
        key: 'top_products',
        title: 'Top products',
        items: DashboardSnapshotService._seriesFromSummaryList(
          summary['topProducts'],
          color: Colors.purple,
        ),
        displayAsMoney: false,
      ),
      DashboardChartSeries(
        key: 'top_customers',
        title: 'Top customers',
        items:
            DashboardSnapshotService._seriesFromSummaryList(summary['topCustomers'], color: Colors.teal),
      ),
    ];
    return DashboardState(
      storeName: store.storeProfile.name.trim().isEmpty
          ? store.appIdentity.storeId
          : store.storeProfile.name,
      generatedAt: reference,
      todaySalesTotal: DashboardSnapshotService._doubleValue(summary['todaySalesTotal']),
      todayProfitTotal: DashboardSnapshotService._doubleValue(summary['todayProfitTotal']),
      todayInvoiceCount: DashboardSnapshotService._intValue(summary['todayInvoiceCount']),
      currentCashTotal: 0,
      lowStockCount: DashboardSnapshotService._intValue(summary['lowStockCount']),
      alerts: alerts,
      financialSummary: financialSummary,
      charts: charts,
      recentOperations:
          DashboardSnapshotService._recentOperations(summary['recentOperations'] as List<dynamic>?),
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
        pendingSyncCount: DashboardSnapshotService._intValue(summary['pendingSyncCount']),
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
        ...DashboardSnapshotService._alertsFromSummary(summary),
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
          amount: DashboardSnapshotService._doubleValue(summary['inventoryCostValue']),
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
          amount: DashboardSnapshotService._doubleValue(summary['totalPurchasesAmount']),
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
          items: DashboardSnapshotService._resolveSalesSeries(
            store,
            reference,
            summary['salesLast7Days'],
            days: 7,
          ),
        ),
        DashboardChartSeries(
          key: 'sales_30d',
          title: 'Sales last 30 days',
          items: DashboardSnapshotService._resolveSalesSeries(
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
              value: DashboardSnapshotService._doubleValue(summary['salesSince30Days']),
              color: Colors.blue,
            ),
            DashboardChartItem(
              label: 'Profit',
              value: DashboardSnapshotService._doubleValue(summary['profitSince30Days']),
              color: Colors.green,
            ),
          ],
        ),
        DashboardChartSeries(
          key: 'expenses_type',
          title: 'Expenses by type',
          items: DashboardSnapshotService._seriesFromSummaryList(summary['expenseCategories'],
              color: Colors.deepOrange),
        ),
        DashboardChartSeries(
          key: 'top_products',
          title: 'Top products',
          items: DashboardSnapshotService._seriesFromSummaryList(
            summary['topProducts'],
            color: Colors.purple,
          ),
          displayAsMoney: false,
        ),
        DashboardChartSeries(
          key: 'top_customers',
          title: 'Top customers',
          items: DashboardSnapshotService._seriesFromSummaryList(summary['topCustomers'],
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
      todaySalesTotal: DashboardSnapshotService._doubleValue(summary['todaySalesTotal']),
      todayProfitTotal: DashboardSnapshotService._doubleValue(summary['todayProfitTotal']),
      todayInvoiceCount: DashboardSnapshotService._intValue(summary['todayInvoiceCount']),
      currentCashTotal: cashTotals.cash,
      lowStockCount: DashboardSnapshotService._intValue(summary['lowStockCount']),
      alerts: alerts,
      financialSummary: financialSummary,
      charts: charts,
      recentOperations:
          DashboardSnapshotService._recentOperations(summary['recentOperations'] as List<dynamic>?),
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
    final existing = DashboardSnapshotService._summaryFutures[key];
    if (existing != null) return existing;
    final future = _computeAndCacheSummary(store, reference);
    DashboardSnapshotService._summaryFutures[key] = future;
    future.whenComplete(() {
      if (DashboardSnapshotService._summaryFutures[key] == future) {
        DashboardSnapshotService._summaryFutures.remove(key);
      }
    });
    return future;
  }

  Future<Map<String, Object?>> _computeAndCacheSummary(
    AppStore store,
    DateTime reference,
  ) async {
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
        // Keep dashboard DB-first; the in-memory store is only a safety net
        // when typed SQL is unavailable or fails.
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
}
