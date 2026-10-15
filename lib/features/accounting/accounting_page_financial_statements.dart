part of 'accounting_page.dart';

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
                                  label: Text(tr.text('credit')),
                                  numeric: true),
                              DataColumn(
                                label: Text(_accountingUiText(
                                    context,
                                    'رصيد مدين',
                                    'Debit balance',
                                    'Solde débiteur')),
                                numeric: true,
                              ),
                              DataColumn(
                                label: Text(_accountingUiText(
                                    context,
                                    'رصيد دائن',
                                    'Credit balance',
                                    'Solde créditeur')),
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
                title: _accountingUiText(context, 'الإيرادات من المبيعات',
                    'Sales revenue', 'Revenus des ventes'),
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
                            tooltip: _accountingUiText(context, 'عرض القيد',
                                'View journal', 'Voir l’écriture'),
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
                            tooltip: _accountingUiText(context, 'عرض القيد',
                                'View journal', 'Voir l’écriture'),
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
                balancedText: _accountingUiText(context, 'المركز المالي متوازن',
                    'Balance sheet is balanced', 'Le bilan est équilibré'),
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
                title: _accountingUiText(context, 'الأصول المتداولة',
                    'Current assets', 'Actifs courants'),
                accountLines: report.currentAssetLines,
                totalLabel: _accountingUiText(
                    context,
                    'إجمالي الأصول المتداولة',
                    'Total current assets',
                    'Total actifs courants'),
                totalAmount: report.currentAssets,
              ),
              const SizedBox(height: 12),
              _FinancialBreakdownSection(
                store: store,
                title: _accountingUiText(context, 'الأصول غير المتداولة',
                    'Non-current assets', 'Actifs non courants'),
                accountLines: report.nonCurrentAssetLines,
                totalLabel: _accountingUiText(
                    context,
                    'إجمالي الأصول غير المتداولة',
                    'Total non-current assets',
                    'Total actifs non courants'),
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
                totalLabel: _accountingUiText(
                    context,
                    'إجمالي الالتزامات المتداولة',
                    'Total current liabilities',
                    'Total passifs courants'),
                totalAmount: report.currentLiabilities,
              ),
              const SizedBox(height: 12),
              _FinancialBreakdownSection(
                store: store,
                title: _accountingUiText(context, 'الالتزامات غير المتداولة',
                    'Non-current liabilities', 'Passifs non courants'),
                accountLines: report.nonCurrentLiabilityLines,
                totalLabel: _accountingUiText(
                    context,
                    'إجمالي الالتزامات غير المتداولة',
                    'Total non-current liabilities',
                    'Total passifs non courants'),
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
                    context,
                    'إجمالي حقوق الملكية والنتيجة',
                    'Total equity and result',
                    'Total capitaux propres et résultat'),
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
                label: _accountingUiText(context, 'إجمالي الأصول',
                    'Total assets', 'Total des actifs'),
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
