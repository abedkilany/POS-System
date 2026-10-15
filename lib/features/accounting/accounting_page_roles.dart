part of 'accounting_page.dart';

class _AccountingRolesTab extends StatefulWidget {
  const _AccountingRolesTab({required this.store});

  final AppStore store;

  @override
  State<_AccountingRolesTab> createState() => _AccountingRolesTabState();
}

class _AccountingRolesTabState extends State<_AccountingRolesTab> {
  late Future<_AccountingRolesData> _future;
  int _lastSeenRevision = -1;
  static final RevisionKeyCache<Future<_AccountingRolesData>> _futureCache =
      RevisionKeyCache<Future<_AccountingRolesData>>();

  static const List<String> _groupOrder = <String>[
    'core',
    'inventory',
    'sales',
    'expenses',
    'inventory_adjustments',
    'manufacturing',
    'cash',
    'parties',
    'equity',
    'fixed_assets',
    'tax',
  ];

  @override
  void initState() {
    super.initState();
    _future = _loadCached();
    _lastSeenRevision = widget.store.accounting.revision;
    widget.store.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _AccountingRolesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_refresh);
      widget.store.addListener(_refresh);
      _lastSeenRevision = widget.store.accounting.revision;
    }
  }

  Future<_AccountingRolesData> _load() async {
    final results = await Future.wait<Object>([
      AccountingService.listAccounts(activeOnly: true),
      AccountingService.readAccountRoleMap(),
      AccountingService.validateAccountRoleConfiguration(),
    ]);
    return _AccountingRolesData(
      accounts: (results[0] as List<AccountingAccount>)
          .where((account) => account.isActive && account.isPostable)
          .toList(),
      roles: results[1] as Map<String, String>,
      validationErrors: results[2] as List<String>,
    );
  }

  Future<_AccountingRolesData> _loadCached() {
    return _futureCache.getOrCompute(
      widget.store.accounting.revision,
      widget.store.runtime.identity.storeId,
      _load,
    );
  }

  Future<void> _updateRole(String roleKey, String accountId) async {
    widget.store.security.requirePermission(AppPermission.accountingManage);
    await AccountingService.updateAccountRole(
      roleKey: roleKey,
      accountId: accountId,
    );
    if (!mounted) return;
    _refresh(force: true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(AppLocalizations.of(context)
              .text('account_role_mapping_updated'))),
    );
  }

  void _refresh({bool force = false}) {
    if (!mounted) return;
    final revision = widget.store.accounting.revision;
    if (!force && revision == _lastSeenRevision) return;
    _lastSeenRevision = revision;
    setState(() => _future = _loadCached());
  }

  @override
  void dispose() {
    widget.store.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return FutureBuilder<_AccountingRolesData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
        final data = snapshot.data ??
            const _AccountingRolesData(
              accounts: <AccountingAccount>[],
              roles: <String, String>{},
              validationErrors: <String>[],
            );
        final canManage =
            widget.store.security.hasPermission(AppPermission.accountingManage);
        final children = <Widget>[
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr.text('account_role_mapping_title'),
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr.text('account_role_mapping_desc'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  if (data.validationErrors.isEmpty)
                    Row(
                      children: [
                        const Icon(Icons.verified_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(tr.text('account_roles_valid'))),
                      ],
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .errorContainer
                            .withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(data.validationErrors.join('\n')),
                    ),
                  if (!canManage) ...[
                    const SizedBox(height: 8),
                    Text(
                      tr.text('account_roles_read_only'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ];

        for (final group in _groupOrder) {
          final roles = AccountingAccountRole.all
              .where((role) => role.group == group)
              .toList(growable: false);
          if (roles.isEmpty) continue;
          children.add(
            Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Row(
                      children: [
                        Icon(_accountRoleGroupIcon(group), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _accountRoleGroupTitle(group),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  for (var i = 0; i < roles.length; i++) ...[
                    _AccountingSettingRow(
                      definition: _AccountingSettingDefinition(
                        titleKey: roles[i].titleAr,
                        subtitleKey: roles[i].descriptionAr,
                        icon: _accountRoleGroupIcon(group),
                      ),
                      accounts: data.accounts,
                      selectedAccountId: data.roles[roles[i].settingKey] ?? '',
                      onChanged: canManage
                          ? (accountId) => _updateRole(roles[i].key, accountId)
                          : null,
                    ),
                    if (i != roles.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: children.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, index) => children[index],
        );
      },
    );
  }
}

class _AccountingRolesData {
  const _AccountingRolesData({
    required this.accounts,
    required this.roles,
    required this.validationErrors,
  });

  final List<AccountingAccount> accounts;
  final Map<String, String> roles;
  final List<String> validationErrors;
}

String _accountRoleGroupTitle(String group) => switch (group) {
      'core' => 'الحسابات الأساسية',
      'inventory' => 'المخزون',
      'sales' => 'المبيعات والإيرادات',
      'expenses' => 'المصروفات',
      'inventory_adjustments' => 'فروقات وتسويات المخزون',
      'manufacturing' => 'التصنيع',
      'cash' => 'الصندوق والتسويات النقدية',
      'parties' => 'العملاء والموردون',
      'equity' => 'حقوق الملكية',
      'fixed_assets' => 'الأصول الثابتة',
      'tax' => 'الضرائب',
      _ => group,
    };

IconData _accountRoleGroupIcon(String group) => switch (group) {
      'core' => Icons.hub_outlined,
      'inventory' => Icons.inventory_2_outlined,
      'sales' => Icons.point_of_sale_outlined,
      'expenses' => Icons.receipt_long_outlined,
      'inventory_adjustments' => Icons.tune_outlined,
      'manufacturing' => Icons.precision_manufacturing_outlined,
      'cash' => Icons.payments_outlined,
      'parties' => Icons.people_alt_outlined,
      'equity' => Icons.account_balance_wallet_outlined,
      'fixed_assets' => Icons.business_center_outlined,
      'tax' => Icons.percent_outlined,
      _ => Icons.account_tree_outlined,
    };
