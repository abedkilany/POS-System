part of 'accounting_page.dart';

class _AccountsTab extends StatelessWidget {
  const _AccountsTab(
      {required this.store, required this.query, required this.accountType});

  final AppStore store;
  final String query;
  final String accountType;

  Future<List<_AccountRowData>?> _rowsFromSqlite(String normalizedQuery) async {
    final rows =
        await LocalDatabaseService.queryAccountingAccountRowsFromSqlite(
      accountType: accountType,
      query: normalizedQuery,
      limit: 500,
    );
    return rows
        ?.map((row) => _AccountRowData(
              id: row['id']?.toString() ?? '',
              name: row['name']?.toString() ?? '',
              subtitle: row['subtitle']?.toString() ?? '',
              balance: _doubleValue(row['balance']),
            ))
        .where((row) => row.id.trim().isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _normalizedSearchQuery(query);
    if (LocalDatabaseService.canQueryBusinessSqlite) {
      return FutureBuilder<List<_AccountRowData>?>(
        future: _rowsFromSqlite(normalizedQuery),
        builder: (context, snapshot) {
          final rows = snapshot.data;
          if (rows != null && !snapshot.hasError) {
            return _AccountsRowsView(
              store: store,
              accountType: accountType,
              rows: rows,
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          return _AccountsTabMemory(
            store: store,
            query: query,
            accountType: accountType,
          );
        },
      );
    }
    return _AccountsTabMemory(
      store: store,
      query: query,
      accountType: accountType,
    );
  }
}

// ignore: unused_element
class _AccountsTabMemory extends StatelessWidget {
  const _AccountsTabMemory(
      {required this.store, required this.query, required this.accountType});

  final AppStore store;
  final String query;
  final String accountType;
  static final RevisionKeyCache<List<_AccountRowData>> _rowsCache =
      RevisionKeyCache<List<_AccountRowData>>();
  static final RevisionKeyCache<Map<String, String>> _searchIndexCache =
      RevisionKeyCache<Map<String, String>>();

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final normalizedQuery = _normalizedSearchQuery(query);
    final dataRevision = accountType == 'customer'
        ? store.customersRevision
        : store.suppliersRevision;
    final rowsRevision = Object.hashAll(<Object?>[
      dataRevision,
      store.accounting.ledgerRevision,
    ]);
    final index = _searchIndexCache.getOrCompute(
      dataRevision,
      '${store.appIdentity.storeId}|$accountType',
      () {
        final map = <String, String>{};
        if (accountType == 'customer') {
          for (final customer in store.customers) {
            map[customer.id] = [
              customer.name,
              customer.phone,
              customer.address,
            ].join(' ').toLowerCase();
          }
        } else {
          for (final supplier in store.suppliers) {
            map[supplier.id] = [
              supplier.name,
              supplier.nameEn,
              supplier.nameAr,
              supplier.phone,
              supplier.address,
            ].join(' ').toLowerCase();
          }
        }
        return map;
      },
    );
    final rows = _rowsCache.getOrCompute(
      rowsRevision,
      '${store.appIdentity.storeId}|$accountType|$normalizedQuery',
      () {
        final computed = accountType == 'customer'
            ? store.customers
                .where((customer) =>
                    normalizedQuery.isEmpty ||
                    (index[customer.id]?.contains(normalizedQuery) ?? false))
                .map((customer) => _AccountRowData(
                      id: customer.id,
                      name: customer.name,
                      subtitle: [customer.phone, customer.address]
                          .where((part) => part.trim().isNotEmpty)
                          .join(' • '),
                      balance: store.accounting
                          .accountBalance('customer', customer.id),
                    ))
                .toList()
            : store.suppliers
                .where((supplier) =>
                    normalizedQuery.isEmpty ||
                    (index[supplier.id]?.contains(normalizedQuery) ?? false))
                .map((supplier) => _AccountRowData(
                      id: supplier.id,
                      name: supplier.name,
                      subtitle: [supplier.phone, supplier.address]
                          .where((part) => part.trim().isNotEmpty)
                          .join(' • '),
                      balance: store.accounting
                          .accountBalance('supplier', supplier.id),
                    ))
                .toList();
        computed.sort((a, b) => b.balance.abs().compareTo(a.balance.abs()));
        return computed;
      },
    );

    if (rows.isEmpty) {
      return _EmptyAccountingState(
          message: tr.text(accountType == 'customer'
              ? 'no_customers_found'
              : 'no_suppliers_found'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;
        final rowExtent = isWide ? 84.0 : 104.0;
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: isWide
              ? Column(
                  children: [
                    _AccountTableHeader(accountType: accountType),
                    Expanded(
                      child: ListView.builder(
                        scrollCacheExtent: _kAccountingListCacheExtent,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemExtent: rowExtent,
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return _AccountListRow(
                              store: store,
                              accountType: accountType,
                              row: row,
                              isWide: isWide);
                        },
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  scrollCacheExtent: _kAccountingListCacheExtent,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemExtent: rowExtent,
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return _AccountListRow(
                        store: store,
                        accountType: accountType,
                        row: row,
                        isWide: isWide);
                  },
                ),
        );
      },
    );
  }
}

class _AccountsRowsView extends StatelessWidget {
  const _AccountsRowsView({
    required this.store,
    required this.accountType,
    required this.rows,
  });

  final AppStore store;
  final String accountType;
  final List<_AccountRowData> rows;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (rows.isEmpty) {
      return _EmptyAccountingState(
          message: tr.text(accountType == 'customer'
              ? 'no_customers_found'
              : 'no_suppliers_found'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;
        final rowExtent = isWide ? 84.0 : 104.0;
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: isWide
              ? Column(
                  children: [
                    _AccountTableHeader(accountType: accountType),
                    Expanded(
                      child: ListView.builder(
                        scrollCacheExtent: _kAccountingListCacheExtent,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemExtent: rowExtent,
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return _AccountListRow(
                              store: store,
                              accountType: accountType,
                              row: row,
                              isWide: isWide);
                        },
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  scrollCacheExtent: _kAccountingListCacheExtent,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemExtent: rowExtent,
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return _AccountListRow(
                        store: store,
                        accountType: accountType,
                        row: row,
                        isWide: isWide);
                  },
                ),
        );
      },
    );
  }
}

class _AccountRowData {
  const _AccountRowData(
      {required this.id,
      required this.name,
      required this.subtitle,
      required this.balance});

  final String id;
  final String name;
  final String subtitle;
  final double balance;
}

class _AccountTableHeader extends StatelessWidget {
  const _AccountTableHeader({required this.accountType});

  final String accountType;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.55),
      child: Row(
        children: [
          Expanded(
              flex: 4,
              child: Text(
                  tr.text(accountType == 'customer' ? 'customer' : 'supplier'),
                  style: TextStyle(color: color, fontWeight: FontWeight.w700))),
          Expanded(
              flex: 2,
              child: Text(tr.text('balance'),
                  style: TextStyle(color: color, fontWeight: FontWeight.w700))),
          const SizedBox(width: 260),
        ],
      ),
    );
  }
}

class _AccountListRow extends StatelessWidget {
  const _AccountListRow(
      {required this.store,
      required this.accountType,
      required this.row,
      required this.isWide});

  final AppStore store;
  final String accountType;
  final _AccountRowData row;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final color = accountBalanceColor(context, store, accountType, row.id);
    final actions = [
      OutlinedButton.icon(
        onPressed: () => showAccountLedgerSheet(
            context: context,
            store: store,
            accountType: accountType,
            accountId: row.id,
            accountName: row.name),
        icon: const Icon(Icons.list_alt_outlined, size: 18),
        label: Text(tr.text('account_ledger')),
      ),
      FilledButton.icon(
        onPressed: () => showAccountPaymentDialog(
            context: context,
            store: store,
            accountType: accountType,
            accountId: row.id,
            accountName: row.name),
        icon: Icon(
            accountType == 'customer' ? Icons.call_received : Icons.call_made,
            size: 18),
        label: Text(accountType == 'customer'
            ? tr.text('receive_payment')
            : tr.text('pay_supplier')),
      ),
    ];

    if (!isWide) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                    radius: 18,
                    child: Icon(
                        accountType == 'customer'
                            ? Icons.person_outline
                            : Icons.local_shipping_outlined,
                        size: 20)),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700))),
                Text(
                    formatUsdReferenceAmount(
                        row.balance.abs(), store.storeProfile),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.w800)),
              ],
            ),
            if (row.subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(row.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                CircleAvatar(
                    radius: 17,
                    child: Icon(
                        accountType == 'customer'
                            ? Icons.person_outline
                            : Icons.local_shipping_outlined,
                        size: 19)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      if (row.subtitle.isNotEmpty)
                        Text(row.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
                formatUsdReferenceAmount(row.balance.abs(), store.storeProfile),
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w800)),
          ),
          SizedBox(
            width: 260,
            child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: actions),
          ),
        ],
      ),
    );
  }
}

class _AgingReportsTab extends StatefulWidget {
  const _AgingReportsTab({required this.store, required this.query});

  final AppStore store;
  final String query;

  @override
  State<_AgingReportsTab> createState() => _AgingReportsTabState();
}

class _AgingReportsTabState extends State<_AgingReportsTab> {
  Future<_AgingReportsData>? _future;
  int _futureRevision = -1;

  Future<_AgingReportsData> _reportsFromSqlite() async {
    final results = await Future.wait<AgingReportResult>([
      AccountingAgingService.customerAgingReport(),
      AccountingAgingService.supplierAgingReport(),
    ]);
    return _AgingReportsData(
      customerReport: results[0],
      supplierReport: results[1],
    );
  }

  Future<_AgingReportsData> _futureForRevision() {
    final revision = widget.store.accounting.revision;
    if (_future == null || _futureRevision != revision) {
      _futureRevision = revision;
      _future = _reportsFromSqlite();
    }
    return _future!;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AgingReportsData>(
      future: _futureForRevision(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        return _buildReports(
            context, snapshot.data ?? _AgingReportsData.empty());
      },
    );
  }

  Widget _buildReports(BuildContext context, _AgingReportsData reports) {
    final customerReport = reports.customerReport;
    final supplierReport = reports.supplierReport;

    return ListView(
      children: [
        _AgingReportSection(
          store: widget.store,
          title: AppLocalizations.of(context).text('customer_aging'),
          subtitle:
              AppLocalizations.of(context).text('customer_aging_subtitle'),
          icon: Icons.people_outline,
          report: customerReport,
          query: widget.query,
        ),
        const SizedBox(height: 12),
        _AgingReportSection(
          store: widget.store,
          title: AppLocalizations.of(context).text('supplier_aging'),
          subtitle:
              AppLocalizations.of(context).text('supplier_aging_subtitle'),
          icon: Icons.local_shipping_outlined,
          report: supplierReport,
          query: widget.query,
        ),
      ],
    );
  }
}

class _AgingReportsData {
  const _AgingReportsData({
    required this.customerReport,
    required this.supplierReport,
  });

  factory _AgingReportsData.empty() => _AgingReportsData(
        customerReport: AgingReportResult(
          asOfDate: DateTime.fromMillisecondsSinceEpoch(0),
          rows: const <AgingReportRow>[],
          openDocuments: const <AgingOpenDocument>[],
        ),
        supplierReport: AgingReportResult(
          asOfDate: DateTime.fromMillisecondsSinceEpoch(0),
          rows: const <AgingReportRow>[],
          openDocuments: const <AgingOpenDocument>[],
        ),
      );

  final AgingReportResult customerReport;
  final AgingReportResult supplierReport;
}

class _AgingReportSection extends StatelessWidget {
  const _AgingReportSection({
    required this.store,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.report,
    required this.query,
  });

  final AppStore store;
  final String title;
  final String subtitle;
  final IconData icon;
  final AgingReportResult report;
  final String query;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final normalizedQuery = _normalizedSearchQuery(query);
    final rows = report.rows
        .where((row) => _matchesNormalized(normalizedQuery, [row.partyName]))
        .toList();
    final documents = report.openDocuments
        .where((doc) =>
            _matchesNormalized(normalizedQuery, [doc.partyName, doc.number]))
        .take(80)
        .toList();

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      Text(subtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                    ],
                  ),
                ),
                Text(_money(store, report.total),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _AgingBucketChip(
                    store: store,
                    label: tr.text('current'),
                    amount: report.current),
                _AgingBucketChip(
                    store: store, label: '0-30', amount: report.days1To30),
                _AgingBucketChip(
                    store: store, label: '31-60', amount: report.days31To60),
                _AgingBucketChip(
                    store: store, label: '61-90', amount: report.days61To90),
                _AgingBucketChip(
                    store: store, label: '90+', amount: report.over90),
              ],
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              _EmptyAccountingState(message: tr.text('no_aging_balances'))
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(label: Text(tr.text('account'))),
                    DataColumn(label: Text(tr.text('current')), numeric: true),
                    const DataColumn(label: Text('0-30'), numeric: true),
                    const DataColumn(label: Text('31-60'), numeric: true),
                    const DataColumn(label: Text('61-90'), numeric: true),
                    const DataColumn(label: Text('90+'), numeric: true),
                    DataColumn(label: Text(tr.text('total')), numeric: true),
                  ],
                  rows: [
                    for (final row in rows)
                      DataRow(cells: [
                        DataCell(Text(row.partyName,
                            overflow: TextOverflow.ellipsis)),
                        DataCell(Text(_money(store, row.current))),
                        DataCell(Text(_money(store, row.days1To30))),
                        DataCell(Text(_money(store, row.days31To60))),
                        DataCell(Text(_money(store, row.days61To90))),
                        DataCell(Text(_money(store, row.over90))),
                        DataCell(Text(_money(store, row.total))),
                      ]),
                  ],
                ),
              ),
            if (documents.isNotEmpty) ...[
              const Divider(height: 24),
              Text(tr.text('open_documents'),
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(label: Text(tr.text('date'))),
                    DataColumn(label: Text(tr.text('reference'))),
                    DataColumn(label: Text(tr.text('account'))),
                    DataColumn(label: Text(tr.text('age_days')), numeric: true),
                    DataColumn(label: Text(tr.text('bucket'))),
                    DataColumn(label: Text(tr.text('balance')), numeric: true),
                  ],
                  rows: [
                    for (final doc in documents)
                      DataRow(cells: [
                        DataCell(Text(_dateText(doc.date))),
                        DataCell(
                            Text(doc.number.isEmpty ? doc.id : doc.number)),
                        DataCell(Text(doc.partyName)),
                        DataCell(Text(doc.ageDays.toString())),
                        DataCell(
                            Text(_agingBucketText(context, doc.bucketLabel))),
                        DataCell(Text(_money(store, doc.openAmount))),
                      ]),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AgingBucketChip extends StatelessWidget {
  const _AgingBucketChip(
      {required this.store, required this.label, required this.amount});

  final AppStore store;
  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: ${_money(store, amount)}'),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    );
  }
}

String _agingBucketText(BuildContext context, String bucket) {
  switch (bucket) {
    case 'current':
      return AppLocalizations.of(context).text('current');
    case '0_30':
      return '0-30';
    case '31_60':
      return '31-60';
    case '61_90':
      return '61-90';
    default:
      return '90+';
  }
}
