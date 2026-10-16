part of 'accounting_page.dart';

class _CashBankReportTab extends StatelessWidget {
  const _CashBankReportTab({required this.store});

  final ApplicationSession store;

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

  final ApplicationSession store;
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
                    context,
                    'التدفقات النقدية متصالحة مع الرصيد',
                    'Cash flow reconciles to closing cash',
                    'Les flux de trésorerie sont rapprochés'),
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
                      DataColumn(
                          label: Text(_accountingUiText(
                              context, 'القيد', 'Journal', 'Écriture'))),
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
                            tooltip: _accountingUiText(context, 'عرض القيد',
                                'View journal', 'Voir l’écriture'),
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

  final ApplicationSession store;
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
                label: tr.text('cash_outflows'),
                value: _money(store, outflows)),
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

  final ApplicationSession store;
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
