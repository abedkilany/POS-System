// ignore_for_file: invalid_use_of_protected_member
part of 'database_page.dart';

extension _DatabasePageStatePart1 on _DatabasePageState {
  String _t(String key) => AppLocalizations.of(context).text(key);
  String _tf(String key, Map<String, Object?> values) =>
      AppLocalizations.of(context).format(key, values);

  String _displayKey(String key) {
    switch (key) {
      case 'supplier_product_prices_v1':
        return 'Supplier Product Prices';
      case 'products_v4':
        return 'Products';
      case 'customers_v4':
        return 'Customers';
      case 'suppliers_v4':
        return 'Suppliers';
      case 'sales_v4':
        return 'Sales';
      case 'purchases_v1':
        return 'Purchases';
      case 'expenses_v4':
        return 'Expenses';
      case 'stock_movements_v1':
        return 'Stock Movements';
      case 'product_categories_v1':
        return 'Product Categories';
      case 'product_brands_v1':
        return 'Product Brands';
      case 'product_units_v1':
        return 'Product Units';
    }
    return key;
  }

  Future<void> _reload() async {
    final entries = await LocalDatabaseService.adminEntries();
    final keys = entries.keys.toList()..sort();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      if (_selectedKey.isEmpty || !entries.containsKey(_selectedKey)) {
        _selectedKey = keys.isEmpty ? '' : keys.first;
      }
      _page = 0;
      _selectedRowIndexes.clear();
    });
  }

  void _deleteSelectedRows() async {
    if (!widget.store.security.canManageDatabase) return;
    final raw = _selectedKey.isEmpty ? '' : (_entries[_selectedKey] ?? '');
    final decoded = _decode(raw);
    if (decoded is! List) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(_t('delete_records')),
            content: Text(_tf('delete_selected_records_question',
                {'count': _selectedRowIndexes.length})),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(_t('cancel'))),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(_t('delete')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    final updated = <dynamic>[];
    for (var i = 0; i < decoded.length; i++) {
      if (!_selectedRowIndexes.contains(i)) updated.add(decoded[i]);
    }
    await _writeSelectedKey(jsonEncode(updated));
  }

  Widget _buildLockedView() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 42),
                const SizedBox(height: 12),
                Text(_t('database_locked'),
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(_t('database_password_hint'), textAlign: TextAlign.center),
                const SizedBox(height: 18),
                FilledButton.icon(
                    onPressed: _requireDatabasePassword,
                    icon: const Icon(Icons.password),
                    label: Text(_t('enter_password'))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _verifyDatabasePassword(String password) async {
    final adminOk = await widget.store.security.verifyAdminPassword(password);
    if (!adminOk) return false;
    return widget.store.security.authorizeSensitiveAction(
      action: SensitiveAction.databaseDestructive,
      password: password,
    );
  }

  Future<bool> _ensureDatabaseMutationAuthorization() async {
    try {
      widget.store.security.requireSensitiveActionAuthorization(
        SensitiveAction.databaseDestructive,
      );
      return true;
    } on SensitiveActionAuthRequiredException {
      if (!mounted) return false;
      return requestSensitiveActionAuthorization(
        context,
        widget.store,
        action: SensitiveAction.databaseDestructive,
      );
    }
  }

  Future<void> _auditDatabaseMutation(
    String action, {
    String details = '',
  }) async {
    final user = widget.store.security.activeUser;
    final identity = widget.store.runtime.identity;
    await AuditLogger.record(
      entityType: 'database',
      entityId: _selectedKey,
      action: action,
      summary: 'Database maintenance mutation',
      details: details,
      userId: user?.id ?? '',
      userName: user?.username ?? '',
      storeId: identity.storeId,
      branchId: identity.branchId,
      sessionId: widget.store.sync.deviceId,
      traceId: widget.store.sync.deviceId,
      deviceId: widget.store.sync.deviceId,
      sourceModule: 'database',
      isImportant: true,
    );
  }

  Future<void> _requireDatabasePassword() async {
    if (!mounted || _databaseUnlocked || _passwordPromptShown) return;
    _passwordPromptShown = true;
    final controller = TextEditingController();
    String? error;
    final unlocked = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_t('database_password')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_t('admin_password_required')),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: _t('password'),
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
                onSubmitted: (_) async {
                  final ok = await _verifyDatabasePassword(controller.text);
                  if (!context.mounted) return;
                  if (ok) {
                    Navigator.pop(context, true);
                  } else {
                    setDialogState(() => error = _t('wrong_password'));
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(_t('cancel'))),
            FilledButton(
              onPressed: () async {
                final ok = await _verifyDatabasePassword(controller.text);
                if (!context.mounted) return;
                if (ok) {
                  Navigator.pop(context, true);
                } else {
                  setDialogState(() => error = _t('wrong_password'));
                }
              },
              child: Text(_t('unlock')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (!mounted) return;
    setState(() {
      _databaseUnlocked = unlocked == true;
      _passwordPromptShown = false;
    });
  }

  Widget _buildMobileTableSelector(List<String> keys) {
    final value = keys.contains(_selectedKey) ? _selectedKey : null;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.storage_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _t('database_page'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    tooltip: _t('refresh')),
                IconButton(
                  onPressed: _selectedKey.isEmpty ? null : _confirmDeleteKey,
                  icon: Icon(Icons.delete_forever_outlined,
                      color: Theme.of(context).colorScheme.error),
                  tooltip: _t('delete_selected_table_key'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: InputDecoration(
                hintText: _t('search_tables'),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (value) => setState(() => _tableQuery = value),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: value,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _t('selected_table'),
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: [
                for (final key in keys)
                  DropdownMenuItem<String>(
                    value: key,
                    child: Text(_displayKey(key),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (key) {
                if (key == null) return;
                setState(() {
                  _selectedKey = key;
                  _page = 0;
                  _selectedRowIndexes.clear();
                  _sortColumn = null;
                  _sortAscending = true;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(List<String> keys) {
    return Container(
      width: 310,
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storage_outlined, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_t('database_page'),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    Text(_t('manage_database_records'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            decoration: InputDecoration(
              hintText: _t('search_tables'),
              suffixIcon: const Icon(Icons.search),
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (value) => setState(() => _tableQuery = value),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: keys.length,
              itemBuilder: (context, index) {
                final key = keys[index];
                final selected = key == _selectedKey;
                final count = _rowsFor(_decode(_entries[key] ?? '')).length;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Material(
                    color: selected
                        ? Theme.of(context)
                            .colorScheme
                            .secondaryContainer
                            .withValues(alpha: 0.45)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: const Icon(Icons.table_chart_outlined, size: 20),
                      title: Text(_displayKey(key),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500)),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999)),
                        child: Text('$count',
                            style: Theme.of(context).textTheme.labelSmall),
                      ),
                      onTap: () => setState(() {
                        _selectedKey = key;
                        _page = 0;
                        _selectedRowIndexes.clear();
                        _sortColumn = null;
                        _sortAscending = true;
                      }),
                    ),
                  ),
                );
              },
            ),
          ),
          Row(
            children: [
              IconButton(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  tooltip: _t('refresh')),
              IconButton(
                onPressed: _selectedKey.isEmpty ? null : _confirmDeleteKey,
                icon: Icon(Icons.delete_forever_outlined,
                    color: Theme.of(context).colorScheme.error),
                tooltip: _t('delete_selected_table_key'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _rowSearchText(Map<String, dynamic> row) {
    final buffer = StringBuffer();
    for (final value in row.values) {
      final text = value?.toString().trim();
      if (text == null || text.isEmpty) continue;
      buffer.write(text);
      buffer.write(' ');
    }
    return buffer.toString().toLowerCase();
  }

  Widget _buildToolbar(dynamic decoded, int start, int end, int total,
      int safePage, int pageCount) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final searchField = SizedBox(
          width: compact ? double.infinity : 360,
          child: TextField(
            decoration: InputDecoration(
              hintText: _t('search_records'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _recordQuery.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => setState(() => _recordQuery = ''),
                      icon: const Icon(Icons.close)),
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (value) => setState(() {
              _recordQuery = value;
              _page = 0;
              _selectedRowIndexes.clear();
            }),
          ),
        );
        final pageControls = Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            IconButton(
                onPressed: safePage > 0 ? () => setState(() => _page--) : null,
                icon: const Icon(Icons.chevron_left)),
            IconButton(
                onPressed: safePage < pageCount - 1
                    ? () => setState(() => _page++)
                    : null,
                icon: const Icon(Icons.chevron_right)),
            Text(_tf('page_range', {
              'start': start + (total == 0 ? 0 : 1),
              'end': end,
              'total': total
            })),
            DropdownButton<int>(
              value: _pageSize,
              items: const [25, 50, 100]
                  .map((value) => DropdownMenuItem<int>(
                      value: value, child: Text('$value')))
                  .toList(),
              onChanged: (value) => setState(() {
                _pageSize = value ?? 50;
                _page = 0;
              }),
            ),
            Text(_t('per_page')),
          ],
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (!compact)
                    IconButton(
                      onPressed: () => setState(
                          () => _sidebarCollapsed = !_sidebarCollapsed),
                      icon: Icon(_sidebarCollapsed
                          ? Icons.keyboard_double_arrow_right
                          : Icons.keyboard_double_arrow_left),
                      tooltip: _sidebarCollapsed
                          ? _t('expand_sidebar')
                          : _t('collapse_sidebar'),
                    ),
                  if (!compact) const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            _tf('table_name',
                                {'name': _displayKey(_selectedKey)}),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        Text(_tf('records_count', {'count': total}),
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
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'refresh') _reload();
                      if (value == 'columns') {
                        setState(() => _selectedMode = 'structure');
                      }
                      if (value == 'data') {
                        setState(() => _selectedMode = 'data');
                      }
                      if (value == 'sql') setState(() => _selectedMode = 'sql');
                      if (value == 'add') _openRowEditor();
                      if (value == 'deleteSelected') _deleteSelectedRows();
                      if (value == 'raw') _openRawEditor();
                      if (value == 'delete') _confirmDeleteKey();
                      if (value == '25') setState(() => _pageSize = 25);
                      if (value == '50') setState(() => _pageSize = 50);
                      if (value == '100') setState(() => _pageSize = 100);
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                          value: 'refresh', child: Text(_t('refresh'))),
                      if (_selectedMode != 'structure')
                        PopupMenuItem(
                            value: 'columns', child: Text(_t('columns'))),
                      if (_selectedMode != 'data')
                        PopupMenuItem(
                            value: 'data', child: Text(_t('data_view'))),
                      if (_selectedMode != 'sql')
                        PopupMenuItem(
                            value: 'sql', child: Text(_t('sql_editor'))),
                      PopupMenuItem(
                          enabled:
                              decoded is List && widget.store.security.canManageDatabase,
                          value: 'add',
                          child: Text(_t('add_record'))),
                      if (_selectedRowIndexes.isNotEmpty)
                        PopupMenuItem(
                            enabled: widget.store.security.canManageDatabase,
                            value: 'deleteSelected',
                            child: Text(_tf('delete_selected_records_count',
                                {'count': _selectedRowIndexes.length}))),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                          enabled: widget.store.security.canManageDatabase,
                          value: 'raw',
                          child: Text(_t('edit_raw_json'))),
                      PopupMenuItem(
                          enabled: widget.store.security.canManageDatabase,
                          value: 'delete',
                          child: Text(_t('delete_selected_table_key'))),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                          value: '25',
                          child: Text(_tf('rows_per_page', {'count': 25}))),
                      PopupMenuItem(
                          value: '50',
                          child: Text(_tf('rows_per_page', {'count': 50}))),
                      PopupMenuItem(
                          value: '100',
                          child: Text(_tf('rows_per_page', {'count': 100}))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (compact) ...[
                searchField,
                const SizedBox(height: 8),
                Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: pageControls),
              ] else
                Row(
                  children: [
                    searchField,
                    const Spacer(),
                    pageControls,
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
