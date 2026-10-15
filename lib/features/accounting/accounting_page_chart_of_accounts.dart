part of 'accounting_page.dart';

class _ChartOfAccountsTab extends StatefulWidget {
  const _ChartOfAccountsTab({required this.store, required this.query});

  final AppStore store;
  final String query;

  @override
  State<_ChartOfAccountsTab> createState() => _ChartOfAccountsTabState();
}

class _ChartOfAccountsTabState extends State<_ChartOfAccountsTab> {
  late Future<List<AccountingAccount>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = AccountingService.listAccounts(activeOnly: false);
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  List<({AccountingAccount account, int depth})> _flatten(
      List<AccountingAccount> accounts) {
    final byParent = <String, List<AccountingAccount>>{};
    for (final account in accounts) {
      byParent
          .putIfAbsent(account.parentId, () => <AccountingAccount>[])
          .add(account);
    }
    for (final children in byParent.values) {
      children.sort((a, b) => a.code.compareTo(b.code));
    }
    final result = <({AccountingAccount account, int depth})>[];
    final visited = <String>{};
    void addBranch(AccountingAccount account, int depth) {
      if (!visited.add(account.id)) return;
      result.add((account: account, depth: depth));
      for (final child in byParent[account.id] ?? const <AccountingAccount>[]) {
        addBranch(child, depth + 1);
      }
    }

    final roots = <AccountingAccount>[
      ...?byParent[''],
      ...accounts.where((a) =>
          a.parentId.isNotEmpty &&
          !accounts.any((candidate) => candidate.id == a.parentId)),
    ]..sort((a, b) => a.code.compareTo(b.code));
    for (final root in roots) {
      addBranch(root, 0);
    }
    for (final orphan in accounts.where((a) => !visited.contains(a.id)).toList()
      ..sort((a, b) => a.code.compareTo(b.code))) {
      addBranch(orphan, 0);
    }
    return result;
  }

  Future<void> _createAccountDialog(List<AccountingAccount> accounts) async {
    widget.store.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    var parentId = '';
    var type = 'asset';
    var normalBalance = 'debit';
    var isPostable = true;
    final activeAccounts = accounts.where((a) => a.isActive).toList()
      ..sort((a, b) => a.code.compareTo(b.code));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.text('new_accounting_account')),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeController,
                    decoration: InputDecoration(
                      labelText: tr.text('account_code'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: tr.text('account_name'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: parentId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr.text('parent_account'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(tr.text('no_parent')),
                      ),
                      for (final account in activeAccounts)
                        DropdownMenuItem(
                          value: account.id,
                          child: Text('${account.code} • ${account.name}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (value) {
                      final selected = activeAccounts
                          .where((a) => a.id == value)
                          .firstOrNull;
                      setDialogState(() {
                        parentId = value ?? '';
                        if (selected != null) {
                          type = selected.type;
                          normalBalance = selected.normalBalance;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: InputDecoration(
                      labelText: tr.text('account_type'),
                      border: const OutlineInputBorder(),
                    ),
                    items: AccountingService.supportedAccountTypes
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(_accountTypeLabel(value, tr)),
                            ))
                        .toList(),
                    onChanged: (value) => setDialogState(() {
                      type = value ?? type;
                      normalBalance = _defaultNormalBalance(type);
                    }),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: normalBalance,
                    decoration: InputDecoration(
                      labelText: tr.text('normal_balance'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: 'debit', child: Text(tr.text('debit'))),
                      DropdownMenuItem(
                          value: 'credit', child: Text(tr.text('credit'))),
                    ],
                    onChanged: (value) => setDialogState(
                        () => normalBalance = value ?? normalBalance),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: isPostable,
                    title: Text(tr.text('allow_direct_posting')),
                    subtitle: Text(tr.text('allow_direct_posting_desc')),
                    onChanged: (value) =>
                        setDialogState(() => isPostable = value),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: descriptionController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: tr.text('description'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr.text('create')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await AccountingService.createAccount(
        code: codeController.text,
        name: nameController.text,
        type: type,
        normalBalance: normalBalance,
        parentId: parentId,
        description: descriptionController.text,
        isPostable: isPostable,
        storeId: widget.store.appIdentity.storeId,
      );
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr.text('account_created')),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString()),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  Future<void> _toggleAccount(AccountingAccount account) async {
    widget.store.requirePermission(AppPermission.accountingManage);
    try {
      await AccountingService.setAccountActive(
          accountId: account.id, active: !account.isActive);
      if (mounted) setState(_reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _editAccountDialog(
    List<AccountingAccount> accounts,
    AccountingAccount account,
  ) async {
    widget.store.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final codeController = TextEditingController(text: account.code);
    final nameController = TextEditingController(text: account.name);
    final descriptionController =
        TextEditingController(text: account.description);
    var parentId = account.parentId;
    var type = account.type;
    var normalBalance = account.normalBalance;
    var isPostable = account.isPostable;

    final descendantIds = <String>{};
    void collectDescendants(String parent) {
      for (final candidate in accounts) {
        if (candidate.parentId == parent && descendantIds.add(candidate.id)) {
          collectDescendants(candidate.id);
        }
      }
    }

    collectDescendants(account.id);
    final activeAccounts = accounts
        .where((candidate) =>
            candidate.isActive &&
            candidate.id != account.id &&
            !descendantIds.contains(candidate.id))
        .toList()
      ..sort((a, b) => a.code.compareTo(b.code));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${tr.text('edit')} ${tr.text('account_name')}'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeController,
                    decoration: InputDecoration(
                      labelText: tr.text('account_code'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: tr.text('account_name'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: parentId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr.text('parent_account'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(tr.text('no_parent')),
                      ),
                      for (final candidate in activeAccounts)
                        DropdownMenuItem(
                          value: candidate.id,
                          child: Text(
                            '${candidate.code} • ${candidate.name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      final selected = activeAccounts
                          .where((candidate) => candidate.id == value)
                          .firstOrNull;
                      setDialogState(() {
                        parentId = value ?? '';
                        if (selected != null) {
                          type = selected.type;
                          normalBalance = selected.normalBalance;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: InputDecoration(
                      labelText: tr.text('account_type'),
                      border: const OutlineInputBorder(),
                    ),
                    items: AccountingService.supportedAccountTypes
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(_accountTypeLabel(value, tr)),
                            ))
                        .toList(),
                    onChanged: (value) => setDialogState(() {
                      type = value ?? type;
                      normalBalance = _defaultNormalBalance(type);
                    }),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: normalBalance,
                    decoration: InputDecoration(
                      labelText: tr.text('normal_balance'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: 'debit', child: Text(tr.text('debit'))),
                      DropdownMenuItem(
                          value: 'credit', child: Text(tr.text('credit'))),
                    ],
                    onChanged: (value) => setDialogState(
                        () => normalBalance = value ?? normalBalance),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: isPostable,
                    title: Text(tr.text('allow_direct_posting')),
                    subtitle: Text(tr.text('allow_direct_posting_desc')),
                    onChanged: (value) =>
                        setDialogState(() => isPostable = value),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: descriptionController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: tr.text('description'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr.text('save')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await AccountingService.updateAccount(
        accountId: account.id,
        code: codeController.text,
        name: nameController.text,
        type: type,
        normalBalance: normalBalance,
        subtype: account.subtype,
        parentId: parentId,
        currency: account.currency,
        description: descriptionController.text,
        isPostable: isPostable,
      );
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr.text('account_updated')),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString()),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  Future<void> _deleteAccount(AccountingAccount account) async {
    widget.store.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('delete_account_confirm')),
        content: Text('${account.code} • ${account.name}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('delete'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AccountingService.deleteAccount(account.id);
      if (mounted) setState(_reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _accountTypeLabel(String type, AppLocalizations tr) {
    final key = <String, String>{
      'asset': 'account_type_asset',
      'liability': 'account_type_liability',
      'equity': 'account_type_equity',
      'revenue': 'account_type_revenue',
      'expense': 'account_type_expense',
      'cost_of_sales': 'account_type_cost_of_sales',
    }[type];
    return key == null ? type : tr.text(key);
  }

  String _defaultNormalBalance(String type) =>
      type == 'asset' || type == 'expense' || type == 'cost_of_sales'
          ? 'debit'
          : 'credit';

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final canManage =
        widget.store.hasPermission(AppPermission.accountingManage);
    return FutureBuilder<List<AccountingAccount>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        final accounts = snapshot.data ?? const <AccountingAccount>[];
        final normalizedQuery = _normalizedSearchQuery(widget.query);
        final rows = _flatten(accounts).where((row) {
          if (normalizedQuery.isEmpty) return true;
          final account = row.account;
          return _matchesNormalized(normalizedQuery, [
            account.code,
            account.name,
            account.type,
            account.subtype,
            account.description,
          ]);
        }).toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr.text('chart_of_accounts'),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        Text(tr.format('accounts_system_protected',
                            <String, Object?>{'count': accounts.length})),
                      ],
                    ),
                    FilledButton.icon(
                      onPressed: canManage
                          ? () => _createAccountDialog(accounts)
                          : null,
                      icon: const Icon(Icons.add),
                      label: Text(tr.text('new_account')),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.builder(
                  scrollCacheExtent: _kAccountingListCacheExtent,
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final account = row.account;
                    return Padding(
                      padding:
                          EdgeInsetsDirectional.only(start: row.depth * 22.0),
                      child: Card(
                        elevation: 0,
                        child: ListTile(
                          leading: Icon(account.isPostable
                              ? Icons.account_balance_wallet_outlined
                              : Icons.account_tree_outlined),
                          title: Text('${account.code} • ${account.name}',
                              style: TextStyle(
                                  fontWeight: account.isPostable
                                      ? FontWeight.w600
                                      : FontWeight.w800,
                                  decoration: account.isActive
                                      ? null
                                      : TextDecoration.lineThrough)),
                          subtitle: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Text(_accountTypeLabel(account.type, tr)),
                              Text(account.normalBalance == 'debit'
                                  ? '• ${tr.text('debit')}'
                                  : '• ${tr.text('credit')}'),
                              if (!account.isPostable)
                                Text('• ${tr.text('group')}'),
                              if (account.isSystem)
                                Text('• ${tr.text('system')}'),
                              if (!account.isActive)
                                Text('• ${tr.text('inactive')}'),
                            ],
                          ),
                          trailing: account.isSystem || !canManage
                              ? (account.isSystem
                                  ? const Icon(Icons.lock_outline, size: 20)
                                  : null)
                              : PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _editAccountDialog(accounts, account);
                                    } else if (value == 'toggle') {
                                      _toggleAccount(account);
                                    } else if (value == 'delete') {
                                      _deleteAccount(account);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text(tr.text('edit')),
                                    ),
                                    PopupMenuItem(
                                      value: 'toggle',
                                      child: Text(account.isActive
                                          ? tr.text('deactivate')
                                          : tr.text('activate')),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(tr.text('delete')),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
