part of 'accounting_page.dart';

class _AdvancedAccountingTab extends StatefulWidget {
  const _AdvancedAccountingTab({required this.store, this.cashOnly = false});

  final ApplicationSession store;
  final bool cashOnly;

  @override
  State<_AdvancedAccountingTab> createState() => _AdvancedAccountingTabState();
}

class _AdvancedAccountingTabState extends State<_AdvancedAccountingTab> {
  late Future<_AdvancedAccountingData> _future;
  int _lastSeenRevision = -1;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _lastSeenRevision = widget.store.accounting.revision;
    widget.store.addListener(_refresh);
  }

  Future<_AdvancedAccountingData> _load() async {
    final results = await Future.wait<Object>([
      AccountingService.listPaymentAccounts(),
      AccountingService.listCashLocations(),
      AccountingService.listCashTransfers(),
      AccountingService.listCashDrawers(),
      AccountingService.listCheques(),
      AccountingService.listAccountingPeriods(),
      AccountingService.listCostCenters(),
      AccountingService.listAccountingBranches(),
      AccountingService.listFixedAssets(),
      AccountingService.listCashBalancesReport(),
      AccountingService.listOpenCashDrawersReport(),
      AccountingService.listCashDrawerVarianceReport(),
      AccountingService.listCashTransferAuditReport(),
    ]);
    return _AdvancedAccountingData(
      paymentAccounts: results[0] as List<AdvancedAccountingItem>,
      cashLocations: results[1] as List<AdvancedAccountingItem>,
      cashTransfers: results[2] as List<AdvancedAccountingItem>,
      cashDrawers: results[3] as List<AdvancedAccountingItem>,
      cheques: results[4] as List<AdvancedAccountingItem>,
      periods: results[5] as List<AdvancedAccountingItem>,
      costCenters: results[6] as List<AdvancedAccountingItem>,
      branches: results[7] as List<AdvancedAccountingItem>,
      fixedAssets: results[8] as List<AdvancedAccountingItem>,
      cashBalancesReport: results[9] as List<AdvancedAccountingItem>,
      openCashDrawersReport: results[10] as List<AdvancedAccountingItem>,
      cashDrawerVarianceReport: results[11] as List<AdvancedAccountingItem>,
      cashTransferAuditReport: results[12] as List<AdvancedAccountingItem>,
    );
  }

  void _refresh({bool force = false}) {
    if (!mounted) return;
    final revision = widget.store.accounting.revision;
    if (!force && revision == _lastSeenRevision) return;
    _lastSeenRevision = revision;
    setState(() => _future = _load());
  }

  @override
  void dispose() {
    widget.store.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canManageAccounting =
        widget.store.security.hasPermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    return FutureBuilder<_AdvancedAccountingData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
        final data = snapshot.data ?? const _AdvancedAccountingData();
        if (widget.cashOnly) {
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _accountingUiText(context, 'رقابة النقد والبنوك',
                            'Cash & bank control', 'Contrôle caisse et banque'),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _accountingUiText(
                          context,
                          'هذه الصفحة للمراجعة والتحليل فقط. عمليات فتح وإغلاق الوردية والتحويلات النقدية اليومية تُنفذ من صفحة الصندوق.',
                          'This page is read-only for review and analysis. Daily drawer opening/closing and cash transfers are performed from the Cash page.',
                          'Cette page est réservée au contrôle et à l’analyse. Les opérations quotidiennes de caisse sont effectuées depuis la page Caisse.',
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _AdvancedSection(
                  title: tr.text('cash_locations'),
                  icon: Icons.account_balance_wallet_outlined,
                  items: data.cashLocations),
              _AdvancedSection(
                title: tr.text('cash_drawer_sessions'),
                icon: Icons.point_of_sale_outlined,
                items: data.cashDrawers,
              ),
              _AdvancedSection(
                  title: tr.text('cash_monitoring'),
                  icon: Icons.monitor_heart_outlined,
                  items: data.cashBalancesReport),
              _AdvancedSection(
                  title: tr.text('open_cash_drawers_report'),
                  icon: Icons.point_of_sale_outlined,
                  items: data.openCashDrawersReport),
              _AdvancedSection(
                  title: tr.text('cash_drawer_variance_report'),
                  icon: Icons.balance_outlined,
                  items: data.cashDrawerVarianceReport),
              _AdvancedSection(
                title: tr.text('cash_transfer_audit_report'),
                icon: Icons.receipt_long_outlined,
                items: data.cashTransferAuditReport,
                actionBuilder: (item) => [
                  TextButton.icon(
                      onPressed: () => _showCashTransferJournalHint(item),
                      icon: const Icon(Icons.menu_book_outlined),
                      label: Text(_accountingUiText(context, 'عرض القيد',
                          'View journal', 'Voir l’écriture')))
                ],
              ),
              _AdvancedSection(
                  title: tr.text('cash_transfers'),
                  icon: Icons.compare_arrows_outlined,
                  items: data.cashTransfers),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr.text('advanced_accounting_controls'),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(tr.text('advanced_accounting_controls_desc'),
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                            onPressed: canManageAccounting
                                ? _manualJournalDialog
                                : null,
                            icon: const Icon(Icons.edit_note_outlined),
                            label: Text(tr.text('manual_journal'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? () => _createCashLocationDialog(
                                    initialType: 'main_vault')
                                : null,
                            icon: const Icon(
                                Icons.account_balance_wallet_outlined),
                            label: Text(tr.text('create_vault'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? () => _createCashLocationDialog(
                                    initialType: 'cash_drawer')
                                : null,
                            icon: const Icon(Icons.point_of_sale_outlined),
                            label: Text(tr.text('create_cash_drawer'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? _openingBalancesDialog
                                : null,
                            icon: const Icon(Icons.account_balance_outlined),
                            label: Text(tr.text('opening_balances'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? _createPaymentAccountDialog
                                : null,
                            icon: const Icon(
                                Icons.account_balance_wallet_outlined),
                            label: Text(tr.text('payment_account'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? _createChequeDialog
                                : null,
                            icon: const Icon(Icons.payments_outlined),
                            label: Text(tr.text('cheque'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? _createPeriodDialog
                                : null,
                            icon: const Icon(Icons.event_available_outlined),
                            label: Text(tr.text('create_period'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? _createFixedAssetDialog
                                : null,
                            icon: const Icon(Icons.business_center_outlined),
                            label: Text(tr.text('fixed_asset'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? _runDepreciationForAllDialog
                                : null,
                            icon: const Icon(Icons.calculate_outlined),
                            label: Text(tr.text('run_depreciation'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? () => _createMasterDataDialog('cost_centers',
                                    tr.text('create_cost_center'))
                                : null,
                            icon: const Icon(Icons.hub_outlined),
                            label: Text(tr.text('cost_center'))),
                        FilledButton.tonalIcon(
                            onPressed: canManageAccounting
                                ? () => _createMasterDataDialog(
                                    'accounting_branches',
                                    tr.text('create_branch'))
                                : null,
                            icon:
                                const Icon(Icons.store_mall_directory_outlined),
                            label: Text(tr.text('branch'))),
                      ],
                    ),
                    if (!canManageAccounting) ...[
                      const SizedBox(height: 8),
                      Text(tr.text('accounting_read_only_permission'),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context).colorScheme.error)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _AdvancedSection(
                title: tr.text('payment_accounts'),
                icon: Icons.account_balance_wallet_outlined,
                items: data.paymentAccounts),
            _AdvancedSection(
                title: tr.text('cash_monitoring'),
                icon: Icons.monitor_heart_outlined,
                items: data.cashBalancesReport),
            _AdvancedSection(
                title: tr.text('open_cash_drawers_report'),
                icon: Icons.point_of_sale_outlined,
                items: data.openCashDrawersReport),
            _AdvancedSection(
                title: tr.text('cash_drawer_variance_report'),
                icon: Icons.balance_outlined,
                items: data.cashDrawerVarianceReport),
            _AdvancedSection(
              title: tr.text('cash_transfer_audit_report'),
              icon: Icons.receipt_long_outlined,
              items: data.cashTransferAuditReport,
              actionBuilder: (item) => [
                TextButton.icon(
                    onPressed: () => _showCashTransferJournalHint(item),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: Text(_accountingUiText(context, 'عرض القيد',
                        'View journal', 'Voir l’écriture')))
              ],
            ),
            _AdvancedSection(
                title: tr.text('cash_locations'),
                icon: Icons.account_balance_wallet_outlined,
                items: data.cashLocations),
            _AdvancedSection(
                title: tr.text('cash_transfers'),
                icon: Icons.compare_arrows_outlined,
                items: data.cashTransfers),
            _AdvancedSection(
              title: tr.text('cash_drawer_sessions'),
              icon: Icons.point_of_sale_outlined,
              items: data.cashDrawers,
            ),
            _AdvancedSection(
              title: tr.text('cheques'),
              icon: Icons.payments_outlined,
              items: data.cheques,
              actionBuilder: canManageAccounting
                  ? (item) => item.status == 'pending'
                      ? [
                          TextButton.icon(
                              onPressed: () => _settleCheque(item),
                              icon: const Icon(Icons.check_circle_outline),
                              label: Text(tr.text('clear'))),
                          TextButton.icon(
                              onPressed: () => _bounceChequeDialog(item),
                              icon: const Icon(Icons.cancel_outlined),
                              label: Text(tr.text('bounce'))),
                        ]
                      : const <Widget>[]
                  : null,
            ),
            _AdvancedSection(
              title: tr.text('accounting_periods'),
              icon: Icons.date_range_outlined,
              items: data.periods,
              actionBuilder: canManageAccounting
                  ? (item) => item.type == 'open'
                      ? [
                          TextButton.icon(
                              onPressed: () => _closePeriod(item),
                              icon: const Icon(Icons.event_busy_outlined),
                              label: Text(tr.text('close')))
                        ]
                      : const <Widget>[]
                  : null,
            ),
            _AdvancedSection(
              title: tr.text('fixed_assets'),
              icon: Icons.business_center_outlined,
              items: data.fixedAssets,
              actionBuilder: canManageAccounting
                  ? (item) => item.status == 'active'
                      ? [
                          TextButton.icon(
                              onPressed: () =>
                                  _runDepreciationForAssetDialog(item),
                              icon: const Icon(Icons.calculate_outlined),
                              label: Text(tr.text('depreciate')))
                        ]
                      : const <Widget>[]
                  : null,
            ),
            _AdvancedSection(
                title: tr.text('cost_centers'),
                icon: Icons.hub_outlined,
                items: data.costCenters),
            _AdvancedSection(
                title: tr.text('branches'),
                icon: Icons.store_mall_directory_outlined,
                items: data.branches),
          ],
        );
      },
    );
  }
}

class _AdvancedAccountingData {
  const _AdvancedAccountingData({
    this.paymentAccounts = const <AdvancedAccountingItem>[],
    this.cashLocations = const <AdvancedAccountingItem>[],
    this.cashTransfers = const <AdvancedAccountingItem>[],
    this.cashDrawers = const <AdvancedAccountingItem>[],
    this.cheques = const <AdvancedAccountingItem>[],
    this.periods = const <AdvancedAccountingItem>[],
    this.costCenters = const <AdvancedAccountingItem>[],
    this.branches = const <AdvancedAccountingItem>[],
    this.fixedAssets = const <AdvancedAccountingItem>[],
    this.cashBalancesReport = const <AdvancedAccountingItem>[],
    this.openCashDrawersReport = const <AdvancedAccountingItem>[],
    this.cashDrawerVarianceReport = const <AdvancedAccountingItem>[],
    this.cashTransferAuditReport = const <AdvancedAccountingItem>[],
  });

  final List<AdvancedAccountingItem> paymentAccounts;
  final List<AdvancedAccountingItem> cashLocations;
  final List<AdvancedAccountingItem> cashTransfers;
  final List<AdvancedAccountingItem> cashDrawers;
  final List<AdvancedAccountingItem> cheques;
  final List<AdvancedAccountingItem> periods;
  final List<AdvancedAccountingItem> costCenters;
  final List<AdvancedAccountingItem> branches;
  final List<AdvancedAccountingItem> fixedAssets;
  final List<AdvancedAccountingItem> cashBalancesReport;
  final List<AdvancedAccountingItem> openCashDrawersReport;
  final List<AdvancedAccountingItem> cashDrawerVarianceReport;
  final List<AdvancedAccountingItem> cashTransferAuditReport;
}

class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection(
      {required this.title,
      required this.icon,
      required this.items,
      this.actionBuilder});

  final String title;
  final IconData icon;
  final List<AdvancedAccountingItem> items;
  final List<Widget> Function(AdvancedAccountingItem item)? actionBuilder;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Card(
      elevation: 0,
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(tr.format('records_count', {'count': items.length})),
        children: items.isEmpty
            ? [ListTile(title: Text(tr.text('no_records_yet')))]
            : [
                for (final item in items)
                  ListTile(
                    title: Text(item.name.isEmpty
                        ? item.id
                        : _localizedAccountingName(item.name, tr)),
                    subtitle: Text([
                      _localizedAccountingType(item.type, tr),
                      item.accountCode,
                      _localizedAccountingName(item.accountName, tr),
                      _localizedAccountingNote(item.notes, tr),
                    ].where((value) => value.trim().isNotEmpty).join(' • ')),
                    trailing: Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (item.status.trim().isNotEmpty)
                          _AccountingStatusBadge(status: item.status),
                        if (item.balance != 0)
                          Text(formatCurrency(item.balance)),
                        ...?actionBuilder?.call(item),
                      ],
                    ),
                  ),
              ],
      ),
    );
  }
}
