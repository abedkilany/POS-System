import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';

import '../../core/services/local_database_service.dart';
import '../../data/app_store.dart';

class DatabasePage extends StatefulWidget {
  const DatabasePage({super.key, required this.store});

  final AppStore store;

  @override
  State<DatabasePage> createState() => _DatabasePageState();
}

class _DatabasePageState extends State<DatabasePage> {
  String _t(String key) => AppLocalizations.of(context).text(key);
  String _tf(String key, Map<String, Object?> values) => AppLocalizations.of(context).format(key, values);
  String _selectedKey = '';
  String _tableQuery = '';
  String _recordQuery = '';
  final String _selectedMode = 'data';
  int _page = 0;
  int _pageSize = 50;
  Map<String, String> _entries = const <String, String>{};
  final Set<int> _selectedRowIndexes = <int>{};
  bool _sidebarCollapsed = false;
  bool _databaseUnlocked = false;
  bool _passwordPromptShown = false;
  String? _sortColumn;
  bool _sortAscending = true;
  final ScrollController _horizontalTableController = ScrollController();
  final ScrollController _verticalTableController = ScrollController();

  @override
  void dispose() {
    _horizontalTableController.dispose();
    _verticalTableController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requireDatabasePassword());
  }

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

  void _reload() {
    final entries = LocalDatabaseService.allEntries();
    final keys = entries.keys.toList()..sort();
    setState(() {
      _entries = entries;
      if (_selectedKey.isEmpty || !entries.containsKey(_selectedKey)) {
        _selectedKey = keys.isEmpty ? '' : keys.first;
      }
      _page = 0;
      _selectedRowIndexes.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final allKeys = _entries.keys.toList()..sort();
    final normalizedTableQuery = _tableQuery.trim().toLowerCase();
    final keys = allKeys
        .where((key) => key.toLowerCase().contains(normalizedTableQuery) || _displayKey(key).toLowerCase().contains(normalizedTableQuery))
        .toList(growable: false);
    final raw = _selectedKey.isEmpty ? '' : (_entries[_selectedKey] ?? '');
    final decoded = _decode(raw);
    final rows = _rowsFor(decoded);
    final filteredRows = rows.where((row) {
      final text = jsonEncode(row).toLowerCase();
      return text.contains(_recordQuery.trim().toLowerCase());
    }).toList(growable: false);
    final columns = _columnsFor(filteredRows.isEmpty ? rows : filteredRows);
    final sortedRows = _sortedRows(filteredRows);
    // Pagination is calculated from data records only. The header row is rendered by
    // DataTable and must not reduce the number of records displayed per page.
    final totalRecords = sortedRows.length;
    final pageCount = totalRecords == 0 ? 1 : ((totalRecords - 1) ~/ _pageSize) + 1;
    final safePage = _page.clamp(0, pageCount - 1).toInt();
    final pageStart = totalRecords == 0 ? 0 : safePage * _pageSize;
    final pageEnd = totalRecords == 0 ? 0 : (pageStart + _pageSize).clamp(0, totalRecords).toInt();
    final visibleRows = sortedRows.sublist(pageStart, pageEnd);

    if (!_databaseUnlocked) return _buildLockedView();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final content = Column(
          children: [
            if (compact) _buildMobileTableSelector(keys),
            _buildToolbar(decoded, pageStart, pageEnd, totalRecords, safePage, pageCount),
            const Divider(height: 1),
            Expanded(
              child: _selectedMode == 'structure'
                  ? _buildStructureView(columns, rows.length, raw)
                  : _buildDataView(decoded, columns, visibleRows),
            ),
          ],
        );
        if (compact) return content;
        return Row(
          children: [
            if (!_sidebarCollapsed) _buildSidebar(keys),
            if (!_sidebarCollapsed) const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        );
      },
    );
  }


  
  void _deleteSelectedRows() async {
    final raw = _selectedKey.isEmpty ? '' : (_entries[_selectedKey] ?? '');
    final decoded = _decode(raw);
    if (decoded is! List) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(_t('delete_records')),
            content: Text(_tf('delete_selected_records_question', {'count': _selectedRowIndexes.length})),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_t('cancel'))),
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
    await LocalDatabaseService.setString(_selectedKey, jsonEncode(updated));
    _reload();
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
                Text(_t('database_locked'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(_t('database_password_hint'), textAlign: TextAlign.center),
                const SizedBox(height: 18),
                FilledButton.icon(onPressed: _requireDatabasePassword, icon: const Icon(Icons.password), label: Text(_t('enter_password'))),
              ],
            ),
          ),
        ),
      ),
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
                  final ok = await widget.store.verifyAdminPassword(controller.text);
                  if (!context.mounted) return;
                  if (ok) {
                    Navigator.pop(context, true);
                  } else {
                    setDialogState(() => error = 'Wrong password');
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_t('cancel'))),
            FilledButton(
              onPressed: () async {
                final ok = await widget.store.verifyAdminPassword(controller.text);
                if (!context.mounted) return;
                if (ok) {
                  Navigator.pop(context, true);
                } else {
                  setDialogState(() => error = 'Wrong password');
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(onPressed: _reload, icon: const Icon(Icons.refresh), tooltip: _t('refresh')),
                IconButton(
                  onPressed: _selectedKey.isEmpty ? null : _confirmDeleteKey,
                  icon: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: [
                for (final key in keys)
                  DropdownMenuItem<String>(
                    value: key,
                    child: Text(_displayKey(key), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                    Text(_t('database_page'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    Text(_t('manage_database_records'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
                    color: selected ? Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.45) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: const Icon(Icons.table_chart_outlined, size: 20),
                      title: Text(_displayKey(key), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
                        child: Text('$count', style: Theme.of(context).textTheme.labelSmall),
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
              IconButton(onPressed: _reload, icon: const Icon(Icons.refresh), tooltip: _t('refresh')),
              IconButton(
                onPressed: _selectedKey.isEmpty ? null : _confirmDeleteKey,
                icon: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
                tooltip: _t('delete_selected_table_key'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(dynamic decoded, int start, int end, int total, int safePage, int pageCount) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final searchField = SizedBox(
          width: compact ? double.infinity : 360,
          child: TextField(
            decoration: InputDecoration(
              hintText: _t('search_records'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _recordQuery.isEmpty ? null : IconButton(onPressed: () => setState(() => _recordQuery = ''), icon: const Icon(Icons.close)),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
            IconButton(onPressed: safePage > 0 ? () => setState(() => _page--) : null, icon: const Icon(Icons.chevron_left)),
            IconButton(onPressed: safePage < pageCount - 1 ? () => setState(() => _page++) : null, icon: const Icon(Icons.chevron_right)),
            Text(_tf('page_range', {'start': start + (total == 0 ? 0 : 1), 'end': end, 'total': total})),
            DropdownButton<int>(
              value: _pageSize,
              items: const [25, 50, 100].map((value) => DropdownMenuItem<int>(value: value, child: Text('$value'))).toList(),
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
                      onPressed: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                      icon: Icon(_sidebarCollapsed ? Icons.keyboard_double_arrow_right : Icons.keyboard_double_arrow_left),
                      tooltip: _sidebarCollapsed ? _t('expand_sidebar') : _t('collapse_sidebar'),
                    ),
                  if (!compact) const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_tf('table_name', {'name': _displayKey(_selectedKey)}), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        Text(_tf('records_count', {'count': total}), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'refresh') _reload();
                      if (value == 'columns') _openRawEditor();
                      if (value == 'add') _openRowEditor();
                      if (value == 'deleteSelected') _deleteSelectedRows();
                      if (value == 'raw') _openRawEditor();
                      if (value == 'delete') _confirmDeleteKey();
                      if (value == '25') setState(() => _pageSize = 25);
                      if (value == '50') setState(() => _pageSize = 50);
                      if (value == '100') setState(() => _pageSize = 100);
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'refresh', child: Text(_t('refresh'))),
                      PopupMenuItem(value: 'columns', child: Text(_t('columns'))),
                      PopupMenuItem(enabled: decoded is List, value: 'add', child: Text(_t('add_record'))),
                      if (_selectedRowIndexes.isNotEmpty) PopupMenuItem(value: 'deleteSelected', child: Text(_tf('delete_selected_records_count', {'count': _selectedRowIndexes.length}))),
                      const PopupMenuDivider(),
                      PopupMenuItem(value: 'raw', child: Text(_t('edit_raw_json'))),
                      PopupMenuItem(value: 'delete', child: Text(_t('delete_selected_table_key'))),
                      const PopupMenuDivider(),
                      PopupMenuItem(value: '25', child: Text(_tf('rows_per_page', {'count': 25}))),
                      PopupMenuItem(value: '50', child: Text(_tf('rows_per_page', {'count': 50}))),
                      PopupMenuItem(value: '100', child: Text(_tf('rows_per_page', {'count': 100}))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (compact) ...[
                searchField,
                const SizedBox(height: 8),
                Align(alignment: AlignmentDirectional.centerStart, child: pageControls),
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

  Widget _buildDataView(dynamic decoded, List<String> columns, List<Map<String, dynamic>> visibleRows) {
    if (_selectedKey.isEmpty) return Center(child: Text(_t('no_database_keys_found')));
    if (visibleRows.isEmpty) return Center(child: Text(_t('no_records_in_table')));

    final sortColumnIndex = _sortColumn == null ? null : columns.indexOf(_sortColumn!);
    final table = DataTable(
      sortColumnIndex: sortColumnIndex != null && sortColumnIndex >= 0 ? sortColumnIndex : null,
      sortAscending: _sortAscending,
      showCheckboxColumn: true,
      onSelectAll: (selected) {
        setState(() {
          final visibleIndexes = visibleRows.map((row) => row['_db_index'] as int? ?? -1).where((index) => index >= 0);
          if (selected == true) {
            _selectedRowIndexes.addAll(visibleIndexes);
          } else {
            _selectedRowIndexes.removeAll(visibleIndexes);
          }
        });
      },
      headingRowHeight: 42,
      dataRowMinHeight: 42,
      dataRowMaxHeight: 52,
      columnSpacing: 28,
      horizontalMargin: 16,
      columns: [
        for (final column in columns)
          DataColumn(
            onSort: (_, __) => _sortByColumn(column),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(column, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(width: 4),
                Text(_columnType(column, visibleRows), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(width: 4),
                const Icon(Icons.unfold_more, size: 14),
              ],
            ),
          ),
        DataColumn(label: Text(_t('actions'))),
      ],
      rows: visibleRows.map((row) {
        final rowIndex = row['_db_index'] as int? ?? -1;
        return DataRow(
          selected: _selectedRowIndexes.contains(rowIndex),
          onSelectChanged: rowIndex >= 0
              ? (selected) => setState(() {
                    if (selected == true) {
                      _selectedRowIndexes.add(rowIndex);
                    } else {
                      _selectedRowIndexes.remove(rowIndex);
                    }
                  })
              : null,
          cells: [
            for (final column in columns)
              DataCell(
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320, minWidth: 120),
                  child: SelectableText(_displayValue(row[column]), maxLines: 1),
                ),
                onTap: column.startsWith('_db_') ? null : () => _openCellEditor(rowIndex, row, column),
              ),
            DataCell(Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(tooltip: _t('edit_record'), icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _openRowEditor(rowIndex: rowIndex, row: row)),
                IconButton(
                  tooltip: _t('delete_record'),
                  icon: Icon(Icons.delete_outline, size: 20, color: Theme.of(context).colorScheme.error),
                  onPressed: decoded is List && rowIndex >= 0 ? () => _confirmDeleteRow(rowIndex) : null,
                ),
              ],
            )),
          ],
        );
      }).toList(),
    );

    return Scrollbar(
      controller: _horizontalTableController,
      thumbVisibility: true,
      notificationPredicate: (notification) => notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _horizontalTableController,
        scrollDirection: Axis.horizontal,
        child: Scrollbar(
          controller: _verticalTableController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _verticalTableController,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width.clamp(320.0, double.infinity).toDouble() - (_sidebarCollapsed || MediaQuery.of(context).size.width < 720 ? 0 : 310)),
              child: table,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStructureView(List<String> columns, int rowCount, String raw) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(_tf('structure_name', {'name': _displayKey(_selectedKey)}), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('${_tf('records_count', {'count': rowCount})} • ${_tf('raw_characters_count', {'count': raw.length})}'),
            const Divider(height: 28),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text(_t('column'))),
                  DataColumn(label: Text(_t('type'))),
                ],
                rows: [
                  for (final column in columns)
                    DataRow(cells: [
                      DataCell(Text(column)),
                      DataCell(Text(_columnType(column, _rowsFor(_decode(raw))))),
                    ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  dynamic _decode(String raw) {
    if (raw.trim().isEmpty) return '';
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  List<Map<String, dynamic>> _rowsFor(dynamic decoded) {
    if (decoded is List) {
      return [
        for (var i = 0; i < decoded.length; i++)
          if (decoded[i] is Map)
            {'_db_index': i, ...Map<String, dynamic>.from(decoded[i] as Map)}
          else
            {'_db_index': i, 'value': decoded[i]},
      ];
    }
    if (decoded is Map) return [{'...': 'object', ...Map<String, dynamic>.from(decoded)}];
    return [{'value': decoded?.toString() ?? ''}];
  }

  List<String> _columnsFor(List<Map<String, dynamic>> rows) {
    final keys = <String>{};
    for (final row in rows) {
      keys.addAll(row.keys);
    }
    final ordered = <String>[];
    if (keys.remove('_db_index')) ordered.add('_db_index');
    if (keys.remove('store_id')) ordered.add('store_id');
    if (keys.remove('entity_type')) ordered.add('entity_type');
    if (keys.remove('entity_id')) ordered.add('entity_id');
    if (keys.remove('id')) ordered.add('id');
    if (keys.remove('name')) ordered.add('name');
    if (keys.remove('payload')) ordered.add('payload');
    ordered.addAll(keys.toList()..sort());
    return ordered;
  }

  String _displayValue(dynamic value) {
    if (value == null) return '';
    if (value is Map || value is List) return jsonEncode(value);
    return value.toString();
  }

  String _columnType(String column, List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final value = row[column];
      if (value == null) continue;
      if (value is int) return 'int';
      if (value is double || value is num) return 'num';
      if (value is bool) return 'bool';
      if (value is Map) return 'jsonb';
      if (value is List) return 'jsonb';
      return 'text';
    }
    return 'text';
  }

  dynamic _coerceValue(String text, dynamic currentValue) {
    if (currentValue is int) return int.tryParse(text) ?? currentValue;
    if (currentValue is double) return double.tryParse(text) ?? currentValue;
    if (currentValue is num) return num.tryParse(text) ?? currentValue;
    if (currentValue is bool) {
      final normalized = text.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') return true;
      if (normalized == 'false' || normalized == '0' || normalized == 'no') return false;
      return currentValue;
    }
    if (currentValue is Map || currentValue is List) {
      try {
        return jsonDecode(text);
      } catch (_) {
        return currentValue;
      }
    }
    return text;
  }

  List<Map<String, dynamic>> _sortedRows(List<Map<String, dynamic>> rows) {
    final column = _sortColumn;
    if (column == null) return rows;
    final sorted = List<Map<String, dynamic>>.from(rows);
    sorted.sort((a, b) {
      final result = _compareValues(a[column], b[column]);
      return _sortAscending ? result : -result;
    });
    return sorted;
  }

  int _compareValues(dynamic a, dynamic b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    final dateA = DateTime.tryParse(a.toString());
    final dateB = DateTime.tryParse(b.toString());
    if (dateA != null && dateB != null) return dateA.compareTo(dateB);
    return a.toString().toLowerCase().compareTo(b.toString().toLowerCase());
  }

  void _sortByColumn(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
      _page = 0;
    });
  }

  Future<void> _openCellEditor(int rowIndex, Map<String, dynamic> row, String column) async {
    final controller = TextEditingController(text: _displayValue(row[column]));
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(column),
        content: TextField(controller: controller, autofocus: true, minLines: 1, maxLines: 8, decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_t('save'))),
        ],
      ),
    );
    if (saved != true) return;
    final updated = Map<String, dynamic>.from(row)..remove('_db_index')..remove('...');
    updated[column] = _coerceValue(controller.text, row[column]);
    await _writeRow(rowIndex, updated);
  }

  Future<void> _openRowEditor({int? rowIndex, Map<String, dynamic>? row}) async {
    final decoded = _decode(_entries[_selectedKey] ?? '');
    final isNew = row == null;
    final existingRows = _rowsFor(decoded);
    final tableColumns = _columnsFor(existingRows).where((column) => !column.startsWith('_db_') && column != '...').toList(growable: false);
    final workingRow = <String, dynamic>{};

    if (isNew) {
      for (final column in tableColumns) {
        workingRow[column] = column == 'id' ? DateTime.now().microsecondsSinceEpoch.toString() : '';
      }
      if (workingRow.isEmpty) workingRow['id'] = DateTime.now().microsecondsSinceEpoch.toString();
    } else {
      workingRow.addAll(Map<String, dynamic>.from(row)..remove('_db_index')..remove('...'));
    }

    final columns = workingRow.keys.toList();
    final controllers = <String, TextEditingController>{
      for (final column in columns) column: TextEditingController(text: _displayValue(workingRow[column])),
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isNew ? _t('add_record') : _t('edit_record')),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final column in columns) ...[
                  TextField(controller: controllers[column], minLines: 1, maxLines: _isLargeField(column) ? 5 : 1, decoration: InputDecoration(labelText: column, border: const OutlineInputBorder())),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(isNew ? _t('add_record') : _t('save'))),
        ],
      ),
    );
    if (saved != true) return;
    for (final column in columns) {
      workingRow[column] = _coerceValue(controllers[column]?.text ?? '', workingRow[column]);
    }
    if (decoded is List) {
      await _writeRow(isNew ? decoded.length : (rowIndex ?? -1), workingRow);
    } else {
      await _writeSelectedKey(jsonEncode(workingRow));
    }
  }

  bool _isLargeField(String column) {
    final lower = column.toLowerCase();
    return lower.contains('items') || lower.contains('payload') || lower.contains('note') || lower.contains('permissions') || lower.contains('address');
  }

  Future<void> _writeRow(int rowIndex, Map<String, dynamic> row) async {
    final decoded = _decode(_entries[_selectedKey] ?? '');
    if (decoded is List) {
      final list = List<dynamic>.from(decoded);
      if (rowIndex >= 0 && rowIndex < list.length) {
        list[rowIndex] = row;
      } else {
        list.add(row);
      }
      await _writeSelectedKey(jsonEncode(list));
      return;
    }
    await _writeSelectedKey(jsonEncode(row));
  }

  Future<void> _writeSelectedKey(String value) async {
    await LocalDatabaseService.setString(_selectedKey, value);
    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t('database_saved_restart'))));
  }

  Future<void> _openRawEditor() async {
    final controller = TextEditingController(text: _entries[_selectedKey] ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_tf('raw_json_name', {'name': _selectedKey})),
        content: SizedBox(width: 900, child: TextField(controller: controller, minLines: 18, maxLines: 24, decoration: const InputDecoration(border: OutlineInputBorder()))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_t('save_raw'))),
        ],
      ),
    );
    if (saved != true) return;
    await _writeSelectedKey(controller.text);
  }

  Future<void> _confirmDeleteRow(int rowIndex) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('delete_record')),
        content: Text(_t('delete_record_question')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_t('cancel'))),
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
    );
    if (confirmed != true) return;
    final decoded = _decode(_entries[_selectedKey] ?? '');
    if (decoded is! List || rowIndex < 0 || rowIndex >= decoded.length) return;
    final list = List<dynamic>.from(decoded)..removeAt(rowIndex);
    await _writeSelectedKey(jsonEncode(list));
  }

  Future<void> _confirmDeleteKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('delete_database_key')),
        content: Text(_tf('delete_database_key_question', {'key': _selectedKey})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_t('delete_key'))),
        ],
      ),
    );
    if (confirmed != true) return;
    await LocalDatabaseService.deleteString(_selectedKey);
    _reload();
  }
}
