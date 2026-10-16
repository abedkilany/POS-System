part of 'accounting_page.dart';

class _GeneralLedgerTab extends StatefulWidget {
  const _GeneralLedgerTab({required this.store, required this.query});

  final ApplicationSession store;
  final String query;

  @override
  State<_GeneralLedgerTab> createState() => _GeneralLedgerTabState();
}

class _GeneralLedgerTabState extends State<_GeneralLedgerTab> {
  late Future<_GeneralLedgerFilterData> _filterDataFuture;
  String _accountId = '';
  String _branchId = '';
  String _costCenterId = '';
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toLocal();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 1)
        .subtract(const Duration(microseconds: 1));
    _filterDataFuture = _loadFilterData();
  }

  Future<_GeneralLedgerFilterData> _loadFilterData() async {
    final results = await Future.wait<Object>([
      AccountingService.listAccounts(),
      AccountingService.listGeneralLedgerBranches(),
      AccountingService.listCostCenters(),
    ]);
    return _GeneralLedgerFilterData(
      accounts: results[0] as List<AccountingAccount>,
      branches: results[1] as List<AdvancedAccountingItem>,
      costCenters: results[2] as List<AdvancedAccountingItem>,
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now().toLocal();
    final initialFrom = _from ?? DateTime(now.year, now.month, 1);
    final initialTo = _to ?? now;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
      initialDateRange: DateTimeRange(start: initialFrom, end: initialTo),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _to = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
        23,
        59,
        59,
        999,
        999,
      );
    });
  }

  String get _reportCacheKey => [
        'general_ledger_report_v2',
        _accountId,
        _branchId,
        _costCenterId,
        _from?.toIso8601String() ?? '',
        _to?.toIso8601String() ?? '',
      ].join('|');

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final normalizedQuery = _normalizedSearchQuery(widget.query);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<_GeneralLedgerFilterData>(
          future: _filterDataFuture,
          builder: (context, snapshot) {
            final data = snapshot.data ?? const _GeneralLedgerFilterData();
            return _GeneralLedgerFilterBar(
              accounts: data.accounts,
              branches: data.branches,
              costCenters: data.costCenters,
              accountId: _accountId,
              branchId: _branchId,
              costCenterId: _costCenterId,
              from: _from,
              to: _to,
              onAccountChanged: (value) => setState(() => _accountId = value),
              onBranchChanged: (value) => setState(() => _branchId = value),
              onCostCenterChanged: (value) =>
                  setState(() => _costCenterId = value),
              onPickRange: _pickRange,
              onClearRange: () => setState(() {
                _from = null;
                _to = null;
              }),
            );
          },
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _CachedFuturePanel<List<GeneralLedgerAccountReport>>(
            store: widget.store,
            cacheKey: _reportCacheKey,
            loadFuture: () => AccountingService.generalLedgerReport(
              accountId: _accountId,
              from: _from,
              to: _to,
              branchId: _branchId,
              costCenterId: _costCenterId,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _ReportError(message: snapshot.error.toString());
              }
              final rows = (snapshot.data ?? <GeneralLedgerAccountReport>[])
                  .where((account) {
                final hasBalance = account.lines.isNotEmpty ||
                    account.openingBalance.abs() > 0.0001;
                if (!hasBalance) return false;
                if (_matchesNormalized(normalizedQuery, [
                  account.accountCode,
                  account.accountName,
                  account.accountType,
                ])) {
                  return true;
                }
                return account.lines.any((line) => _matchesNormalized(
                      normalizedQuery,
                      [
                        line.entryNo,
                        line.referenceType,
                        line.referenceNo,
                        line.description,
                        line.memo,
                      ],
                    ));
              }).toList(growable: false);
              if (rows.isEmpty) {
                return _EmptyAccountingState(
                    message: tr.text('no_journal_entries_found'));
              }
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final account = rows[index];
                  return Card(
                    elevation: 0,
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(
                        '${account.accountCode} • ${_localizedAccountingName(account.accountName, tr)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_accountingUiText(context, 'افتتاحي', 'Opening', 'Ouverture')} ${_money(widget.store, account.openingBalance)}'
                        ' • ${tr.text('debit')} ${_money(widget.store, account.totalDebit)}'
                        ' • ${tr.text('credit')} ${_money(widget.store, account.totalCredit)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _accountingUiText(context, 'الرصيد الختامي',
                                'Closing balance', 'Solde de clôture'),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          Text(
                            _money(widget.store, account.closingBalance),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      children: [
                        _LedgerLinesTable(
                            store: widget.store, account: account),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GeneralLedgerFilterData {
  const _GeneralLedgerFilterData({
    this.accounts = const <AccountingAccount>[],
    this.branches = const <AdvancedAccountingItem>[],
    this.costCenters = const <AdvancedAccountingItem>[],
  });

  final List<AccountingAccount> accounts;
  final List<AdvancedAccountingItem> branches;
  final List<AdvancedAccountingItem> costCenters;
}

class _GeneralLedgerFilterBar extends StatelessWidget {
  const _GeneralLedgerFilterBar({
    required this.accounts,
    required this.branches,
    required this.costCenters,
    required this.accountId,
    required this.branchId,
    required this.costCenterId,
    required this.from,
    required this.to,
    required this.onAccountChanged,
    required this.onBranchChanged,
    required this.onCostCenterChanged,
    required this.onPickRange,
    required this.onClearRange,
  });

  final List<AccountingAccount> accounts;
  final List<AdvancedAccountingItem> branches;
  final List<AdvancedAccountingItem> costCenters;
  final String accountId;
  final String branchId;
  final String costCenterId;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<String> onAccountChanged;
  final ValueChanged<String> onBranchChanged;
  final ValueChanged<String> onCostCenterChanged;
  final VoidCallback onPickRange;
  final VoidCallback onClearRange;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    Widget dropdown({
      required String keyName,
      required String value,
      required String label,
      required List<DropdownMenuItem<String>> items,
      required ValueChanged<String> onChanged,
    }) {
      return SizedBox(
        width: 230,
        child: DropdownButtonFormField<String>(
          key: ValueKey('$keyName:$value'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          items: items,
          onChanged: (next) => onChanged(next ?? ''),
        ),
      );
    }

    final rangeLabel = from == null || to == null
        ? _accountingUiText(
            context, 'كل الفترات', 'All periods', 'Toutes périodes')
        : '${_dateText(from!)} → ${_dateText(to!)}';
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            dropdown(
              keyName: 'gl-account',
              value: accountId,
              label: tr.text('account'),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(_accountingUiText(context, 'كل الحسابات',
                      'All accounts', 'Tous les comptes')),
                ),
                for (final account in accounts.where((a) => a.isPostable))
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(
                      '${account.code} • ${_localizedAccountingName(account.name, tr)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: onAccountChanged,
            ),
            dropdown(
              keyName: 'gl-branch',
              value: branchId,
              label: _accountingUiText(context, 'الفرع', 'Branch', 'Branche'),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(_accountingUiText(context, 'كل الفروع',
                      'All branches', 'Toutes les branches')),
                ),
                for (final branch in branches.where((item) => item.isActive))
                  DropdownMenuItem(
                    value: branch.id,
                    child: Text(
                      _joinParts([branch.accountCode, branch.name]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: onBranchChanged,
            ),
            dropdown(
              keyName: 'gl-cost-center',
              value: costCenterId,
              label: _accountingUiText(
                  context, 'مركز التكلفة', 'Cost center', 'Centre de coût'),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(_accountingUiText(context, 'كل مراكز التكلفة',
                      'All cost centers', 'Tous les centres de coût')),
                ),
                for (final center in costCenters.where((item) => item.isActive))
                  DropdownMenuItem(
                    value: center.id,
                    child: Text(
                      _joinParts([center.accountCode, center.name]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: onCostCenterChanged,
            ),
            OutlinedButton.icon(
              onPressed: onPickRange,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(rangeLabel),
            ),
            if (from != null || to != null)
              TextButton.icon(
                onPressed: onClearRange,
                icon: const Icon(Icons.clear),
                label: Text(_accountingUiText(
                    context, 'كل الفترات', 'All periods', 'Toutes périodes')),
              ),
          ],
        ),
      ),
    );
  }
}

class _LedgerLinesTable extends StatelessWidget {
  const _LedgerLinesTable({required this.store, required this.account});

  final ApplicationSession store;
  final GeneralLedgerAccountReport account;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final lines = account.lines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lines.length > 200)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              _accountingUiText(
                context,
                'يتم عرض أول 200 حركة. ضيّق الفترة أو الحساب للوصول إلى تفاصيل أدق.',
                'Showing the first 200 movements. Narrow the period or account for more detail.',
                'Affichage des 200 premiers mouvements. Réduisez la période ou le compte pour plus de détails.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              DataColumn(label: Text(tr.text('date'))),
              DataColumn(
                  label: Text(_accountingUiText(
                      context, 'القيد', 'Journal', 'Écriture'))),
              DataColumn(label: Text(tr.text('reference'))),
              DataColumn(label: Text(tr.text('description'))),
              DataColumn(label: Text(tr.text('debit')), numeric: true),
              DataColumn(label: Text(tr.text('credit')), numeric: true),
              DataColumn(label: Text(tr.text('balance')), numeric: true),
            ],
            rows: [
              DataRow(cells: [
                const DataCell(Text('')),
                const DataCell(Text('')),
                const DataCell(Text('')),
                DataCell(Text(
                  _accountingUiText(context, 'الرصيد الافتتاحي للفترة',
                      'Opening balance', 'Solde d’ouverture'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                )),
                const DataCell(Text('')),
                const DataCell(Text('')),
                DataCell(Text(
                  _money(store, account.openingBalance),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                )),
              ]),
              for (final line in lines.take(200))
                DataRow(cells: [
                  DataCell(Text(_dateText(line.entryDate))),
                  DataCell(TextButton.icon(
                    onPressed: () => _showJournalDrillDown(
                      context,
                      store: store,
                      entryNo: line.entryNo,
                    ),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(line.entryNo),
                  )),
                  DataCell(
                      Text(_joinParts([line.referenceType, line.referenceNo]))),
                  DataCell(SizedBox(
                    width: 280,
                    child: Text(
                      line.memo.isEmpty ? line.description : line.memo,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
                  DataCell(Text(_money(store, line.debit))),
                  DataCell(Text(_money(store, line.credit))),
                  DataCell(Text(_money(store, line.runningBalance))),
                ]),
              DataRow(cells: [
                const DataCell(Text('')),
                const DataCell(Text('')),
                const DataCell(Text('')),
                DataCell(Text(
                  _accountingUiText(
                      context,
                      'إجمالي الفترة / الرصيد الختامي',
                      'Period totals / closing balance',
                      'Totaux / solde de clôture'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                )),
                DataCell(Text(
                  _money(store, account.totalDebit),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                )),
                DataCell(Text(
                  _money(store, account.totalCredit),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                )),
                DataCell(Text(
                  _money(store, account.closingBalance),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                )),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}
