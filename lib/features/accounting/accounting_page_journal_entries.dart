part of 'accounting_page.dart';

class _JournalEntriesTab extends StatefulWidget {
  const _JournalEntriesTab({required this.store, required this.query});

  final AppStore store;
  final String query;

  @override
  State<_JournalEntriesTab> createState() => _JournalEntriesTabState();
}

class _JournalEntriesTabState extends State<_JournalEntriesTab> {
  String _status = '';
  String _source = '';
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toLocal();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 1)
        .subtract(const Duration(microseconds: 1));
  }

  Future<void> _pickRange() async {
    final now = DateTime.now().toLocal();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
      initialDateRange: DateTimeRange(
        start: _from ?? DateTime(now.year, now.month, 1),
        end: _to ?? now,
      ),
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

  Future<void> _editManualJournal(JournalEntrySummaryReport summary) async {
    widget.store.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    try {
      final details = await AccountingService.journalEntryDetails(
        entryId: summary.id,
      );
      if (details.isEmpty) {
        throw StateError('Manual journal details were not found.');
      }
      final entry = details.first;
      if (entry.referenceType != 'manual_journal' ||
          entry.source != 'manual' ||
          entry.status != 'posted' ||
          entry.reversedByEntryId.isNotEmpty) {
        throw StateError(
            'Only an active manual journal entry can be edited directly.');
      }
      if (entry.lines.length != 2) {
        throw StateError(
            'This manual journal has more than two lines and cannot be edited from the quick editor.');
      }

      final accounts = (await AccountingService.listAccounts())
          .where((account) => account.isPostable)
          .toList(growable: false);
      final costCenters = await AccountingService.listCostCenters();
      final branches = await AccountingService.listAccountingBranches();
      if (!mounted) return;

      final debitLine = entry.lines.firstWhere(
        (line) => line.debit > 0.005,
        orElse: () => entry.lines.first,
      );
      final creditLine = entry.lines.firstWhere(
        (line) => line.credit > 0.005,
        orElse: () => entry.lines.last,
      );
      AccountingAccount? accountById(String id) {
        for (final account in accounts) {
          if (account.id == id) return account;
        }
        return null;
      }

      AdvancedAccountingItem? advancedById(
          List<AdvancedAccountingItem> items, String id) {
        if (id.trim().isEmpty) return null;
        for (final item in items) {
          if (item.id == id) return item;
        }
        return null;
      }

      AccountingAccount? debitAccount = accountById(debitLine.accountId);
      AccountingAccount? creditAccount = accountById(creditLine.accountId);
      if (debitAccount == null || creditAccount == null) {
        throw StateError(
            'One of the journal accounts is no longer available for posting.');
      }
      AdvancedAccountingItem? debitCostCenter =
          advancedById(costCenters, debitLine.costCenterId);
      AdvancedAccountingItem? creditCostCenter =
          advancedById(costCenters, creditLine.costCenterId);
      AdvancedAccountingItem? branch = advancedById(branches, entry.branchId);
      var entryDate = entry.entryDate.toLocal();
      final description = TextEditingController(text: entry.description);
      final amount = TextEditingController(
        text: (debitLine.debit > 0 ? debitLine.debit : creditLine.credit)
            .toStringAsFixed(2),
      );

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(_accountingUiText(
              context,
              'تعديل القيد اليدوي',
              'Edit manual journal',
              'Modifier l’écriture manuelle',
            )),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: description,
                    decoration:
                        InputDecoration(labelText: tr.text('description')),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr.text('date')),
                    subtitle: Text(_dateText(entryDate)),
                    trailing: const Icon(Icons.calendar_month_outlined),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: entryDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(DateTime.now().year + 5, 12, 31),
                      );
                      if (picked != null) {
                        setDialogState(() => entryDate = picked);
                      }
                    },
                  ),
                  DropdownButtonFormField<AdvancedAccountingItem?>(
                    initialValue: branch,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr.text('branch')),
                    items: [
                      DropdownMenuItem<AdvancedAccountingItem?>(
                          value: null, child: Text(tr.text('no_branch'))),
                      for (final item in branches)
                        DropdownMenuItem<AdvancedAccountingItem?>(
                          value: item,
                          child: Text(
                              '${item.accountCode} - ${_localizedAccountingName(item.name, tr)}'),
                        ),
                    ],
                    onChanged: (value) => setDialogState(() => branch = value),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<AccountingAccount>(
                    initialValue: debitAccount,
                    isExpanded: true,
                    decoration:
                        InputDecoration(labelText: tr.text('debit_account')),
                    items: [
                      for (final account in accounts)
                        DropdownMenuItem<AccountingAccount>(
                          value: account,
                          child: Text(
                              '${account.code} - ${_localizedAccountingName(account.name, tr)}'),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => debitAccount = value),
                  ),
                  DropdownButtonFormField<AdvancedAccountingItem?>(
                    initialValue: debitCostCenter,
                    isExpanded: true,
                    decoration: InputDecoration(
                        labelText: tr.text('debit_cost_center')),
                    items: [
                      DropdownMenuItem<AdvancedAccountingItem?>(
                          value: null, child: Text(tr.text('no_cost_center'))),
                      for (final item in costCenters)
                        DropdownMenuItem<AdvancedAccountingItem?>(
                          value: item,
                          child: Text(
                              '${item.accountCode} - ${_localizedAccountingName(item.name, tr)}'),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => debitCostCenter = value),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<AccountingAccount>(
                    initialValue: creditAccount,
                    isExpanded: true,
                    decoration:
                        InputDecoration(labelText: tr.text('credit_account')),
                    items: [
                      for (final account in accounts)
                        DropdownMenuItem<AccountingAccount>(
                          value: account,
                          child: Text(
                              '${account.code} - ${_localizedAccountingName(account.name, tr)}'),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => creditAccount = value),
                  ),
                  DropdownButtonFormField<AdvancedAccountingItem?>(
                    initialValue: creditCostCenter,
                    isExpanded: true,
                    decoration: InputDecoration(
                        labelText: tr.text('credit_cost_center')),
                    items: [
                      DropdownMenuItem<AdvancedAccountingItem?>(
                          value: null, child: Text(tr.text('no_cost_center'))),
                      for (final item in costCenters)
                        DropdownMenuItem<AdvancedAccountingItem?>(
                          value: item,
                          child: Text(
                              '${item.accountCode} - ${_localizedAccountingName(item.name, tr)}'),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => creditCostCenter = value),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tr.text('amount')),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr.text('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr.text('save')),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true) return;
      final value = double.tryParse(amount.text.trim()) ?? 0;
      if (value <= 0 || debitAccount == null || creditAccount == null) {
        throw StateError('A positive balanced journal amount is required.');
      }
      final user = widget.store.activeUser;
      final actor = user?.fullName.trim().isNotEmpty == true
          ? user!.fullName.trim()
          : widget.store.currentRole;
      await AccountingService.editManualJournalEntry(
        activeEntryId: entry.id,
        entryDate: entryDate,
        description: description.text,
        createdBy: actor,
        branchId: branch?.id ?? '',
        lines: [
          JournalLineDraft(
            accountId: debitAccount!.id,
            debit: value,
            credit: 0,
            costCenterId: debitCostCenter?.id ?? '',
          ),
          JournalLineDraft(
            accountId: creditAccount!.id,
            debit: 0,
            credit: value,
            costCenterId: creditCostCenter?.id ?? '',
          ),
        ],
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_accountingUiText(
            context,
            'تم تعديل القيد اليدوي وإعادة ترحيله.',
            'Manual journal edited and reposted.',
            'Écriture manuelle modifiée et repostée.',
          )),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String get _cacheKey => [
        'journal_entries_ui_v1',
        widget.query.trim().toLowerCase(),
        _status,
        _source,
        _from?.toIso8601String() ?? '',
        _to?.toIso8601String() ?? '',
      ].join('|');

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _JournalEntriesFilterBar(
          status: _status,
          source: _source,
          from: _from,
          to: _to,
          onStatusChanged: (value) => setState(() => _status = value),
          onSourceChanged: (value) => setState(() => _source = value),
          onPickRange: _pickRange,
          onClearRange: () => setState(() {
            _from = null;
            _to = null;
          }),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _CachedFuturePanel<List<JournalEntrySummaryReport>>(
            store: widget.store,
            cacheKey: _cacheKey,
            loadFuture: () => AccountingService.listJournalEntrySummaries(
              from: _from,
              to: _to,
              status: _status,
              source: _source,
              search: widget.query,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _ReportError(message: snapshot.error.toString());
              }
              final rows = snapshot.data ?? const <JournalEntrySummaryReport>[];
              if (rows.isEmpty) {
                return _EmptyAccountingState(
                    message: tr.text('no_journal_entries_found'));
              }
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final entry = rows[index];
                  return Card(
                    elevation: 0,
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.receipt_long_outlined, size: 20),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.entryNo,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          _AccountingStatusBadge(status: entry.status),
                        ],
                      ),
                      subtitle: Text(
                        [
                          _dateText(entry.entryDate.toLocal()),
                          _joinParts([entry.referenceType, entry.referenceNo]),
                          _journalSourceLabel(context, entry.source),
                          entry.description,
                          if (entry.reversalReason.trim().isNotEmpty)
                            entry.reversalReason.trim(),
                        ].where((part) => part.trim().isNotEmpty).join(' • '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _money(widget.store, entry.totalDebit),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                _accountingUiText(
                                  context,
                                  '${entry.lineCount} سطر',
                                  '${entry.lineCount} lines',
                                  '${entry.lineCount} lignes',
                                ),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          if (entry.referenceType == 'manual_journal' &&
                              entry.source == 'manual' &&
                              entry.status == 'posted' &&
                              entry.reversedByEntryId.isEmpty &&
                              entry.lineCount == 2 &&
                              widget.store.hasPermission(
                                  AppPermission.accountingManage))
                            IconButton(
                              tooltip: _accountingUiText(
                                context,
                                'تعديل القيد اليدوي',
                                'Edit manual journal',
                                'Modifier l’écriture manuelle',
                              ),
                              onPressed: () => _editManualJournal(entry),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          IconButton(
                            tooltip: _accountingUiText(context, 'عرض القيد',
                                'View journal', 'Voir l’écriture'),
                            onPressed: () => _showJournalDrillDown(
                              context,
                              store: widget.store,
                              entryId: entry.id,
                            ),
                            icon: const Icon(Icons.open_in_new),
                          ),
                        ],
                      ),
                      onTap: () => _showJournalDrillDown(
                        context,
                        store: widget.store,
                        entryId: entry.id,
                      ),
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

class _JournalEntriesFilterBar extends StatelessWidget {
  const _JournalEntriesFilterBar({
    required this.status,
    required this.source,
    required this.from,
    required this.to,
    required this.onStatusChanged,
    required this.onSourceChanged,
    required this.onPickRange,
    required this.onClearRange,
  });

  final String status;
  final String source;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onSourceChanged;
  final VoidCallback onPickRange;
  final VoidCallback onClearRange;

  @override
  Widget build(BuildContext context) {
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
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                key: ValueKey('journal-status:$status'),
                initialValue: status,
                isExpanded: true,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: _accountingUiText(
                      context, 'حالة القيد', 'Entry status', 'Statut'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(_accountingUiText(
                        context, 'كل الحالات', 'All statuses', 'Tous statuts')),
                  ),
                  for (final value in const [
                    'posted',
                    'reversed',
                    'draft',
                    'void'
                  ])
                    DropdownMenuItem(
                      value: value,
                      child: Text(_localizedAccountingStatus(
                          value, AppLocalizations.of(context))),
                    ),
                ],
                onChanged: (value) => onStatusChanged(value ?? ''),
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                key: ValueKey('journal-source:$source'),
                initialValue: source,
                isExpanded: true,
                decoration: InputDecoration(
                  isDense: true,
                  labelText:
                      _accountingUiText(context, 'المصدر', 'Source', 'Source'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(_accountingUiText(context, 'كل المصادر',
                        'All sources', 'Toutes sources')),
                  ),
                  for (final value in const [
                    'system',
                    'manual',
                    'import',
                    'reversal'
                  ])
                    DropdownMenuItem(
                      value: value,
                      child: Text(_journalSourceLabel(context, value)),
                    ),
                ],
                onChanged: (value) => onSourceChanged(value ?? ''),
              ),
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

Future<List<JournalEntryDetailsReport>> _loadJournalDrillDown({
  String entryId = '',
  String entryNo = '',
  String referenceType = '',
  String referenceId = '',
  String referenceNo = '',
}) async {
  if (entryId.trim().isNotEmpty || entryNo.trim().isNotEmpty) {
    return AccountingService.journalEntryDetails(
      entryId: entryId,
      entryNo: entryNo,
    );
  }
  var rows = const <JournalEntryDetailsReport>[];
  if (referenceId.trim().isNotEmpty) {
    rows = await AccountingService.journalEntryDetails(
      referenceType: referenceType,
      referenceId: referenceId,
    );
  }
  if (rows.isEmpty && referenceNo.trim().isNotEmpty) {
    rows = await AccountingService.journalEntryDetails(
      referenceNo: referenceNo,
    );
  }
  return rows;
}

Future<void> _showJournalDrillDown(
  BuildContext context, {
  required AppStore store,
  String entryId = '',
  String entryNo = '',
  String referenceType = '',
  String referenceId = '',
  String referenceNo = '',
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.menu_book_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_accountingUiText(dialogContext, 'تفاصيل القيد',
                'Journal details', 'Détails de l’écriture')),
          ),
        ],
      ),
      content: SizedBox(
        width: 900,
        height: 560,
        child: FutureBuilder<List<JournalEntryDetailsReport>>(
          future: _loadJournalDrillDown(
            entryId: entryId,
            entryNo: entryNo,
            referenceType: referenceType,
            referenceId: referenceId,
            referenceNo: referenceNo,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator.adaptive());
            }
            if (snapshot.hasError) {
              return _ReportError(message: snapshot.error.toString());
            }
            final entries =
                snapshot.data ?? const <JournalEntryDetailsReport>[];
            if (entries.isEmpty) {
              return _EmptyAccountingState(
                message: _accountingUiText(
                  context,
                  'لم يتم العثور على قيد محاسبي مرتبط بهذه الحركة.',
                  'No linked journal entry was found for this movement.',
                  'Aucune écriture liée n’a été trouvée.',
                ),
              );
            }
            return ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _JournalDetailsCard(store: store, entry: entries[index]),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(MaterialLocalizations.of(dialogContext).closeButtonLabel),
        ),
      ],
    ),
  );
}

class _JournalDetailsCard extends StatelessWidget {
  const _JournalDetailsCard({required this.store, required this.entry});

  final AppStore store;
  final JournalEntryDetailsReport entry;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.entryNo,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                _AccountingStatusBadge(status: entry.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                _dateText(entry.entryDate.toLocal()),
                _joinParts([entry.referenceType, entry.referenceNo]),
                _journalSourceLabel(context, entry.source),
                entry.createdBy,
                entry.branchId,
              ].where((value) => value.trim().isNotEmpty).join(' • '),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            if (entry.description.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(entry.description),
            ],
            if (entry.reversalReason.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _accountingUiText(
                  context,
                  'سبب العكس: ${entry.reversalReason}',
                  'Reversal reason: ${entry.reversalReason}',
                  'Motif d’annulation : ${entry.reversalReason}',
                ),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(
                      label: Text(_accountingUiText(
                          context, 'الحساب', 'Account', 'Compte'))),
                  DataColumn(label: Text(tr.text('debit')), numeric: true),
                  DataColumn(label: Text(tr.text('credit')), numeric: true),
                  DataColumn(
                      label: Text(_accountingUiText(
                          context, 'الطرف', 'Party', 'Tiers'))),
                  DataColumn(
                      label: Text(_accountingUiText(
                          context, 'البيان', 'Memo', 'Libellé'))),
                ],
                rows: [
                  for (final line in entry.lines)
                    DataRow(cells: [
                      DataCell(SizedBox(
                        width: 220,
                        child: Text(
                          '${line.accountCode} • ${_localizedAccountingName(line.accountName, tr)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
                      DataCell(Text(_money(store, line.debit))),
                      DataCell(Text(_money(store, line.credit))),
                      DataCell(Text(line.partyName)),
                      DataCell(SizedBox(
                        width: 260,
                        child: Text(line.memo, overflow: TextOverflow.ellipsis),
                      )),
                    ]),
                  DataRow(cells: [
                    DataCell(Text(
                      _accountingUiText(context, 'الإجمالي', 'Total', 'Total'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    )),
                    DataCell(Text(
                      _money(store, entry.totalDebit),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    )),
                    DataCell(Text(
                      _money(store, entry.totalCredit),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    )),
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountingStatusBadge extends StatelessWidget {
  const _AccountingStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toLowerCase();
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (normalized) {
      'posted' || 'active' || 'cleared' || 'collected' || 'closed' => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          Icons.check_circle_outline
        ),
      'reversed' || 'void' || 'cancelled' || 'canceled' || 'bounced' => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          Icons.undo_outlined
        ),
      'draft' || 'pending' || 'open' => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          Icons.schedule_outlined
        ),
      _ => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          Icons.info_outline
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            _localizedAccountingStatus(status, AppLocalizations.of(context)),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

String _journalSourceLabel(BuildContext context, String source) {
  switch (source.trim().toLowerCase()) {
    case 'system':
      return _accountingUiText(context, 'نظامي', 'System', 'Système');
    case 'manual':
      return _accountingUiText(context, 'يدوي', 'Manual', 'Manuel');
    case 'import':
      return _accountingUiText(context, 'مستورد', 'Imported', 'Importé');
    case 'reversal':
      return _accountingUiText(context, 'عكس', 'Reversal', 'Extourne');
    default:
      return source;
  }
}
