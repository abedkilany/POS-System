// ignore_for_file: invalid_use_of_protected_member
part of 'database_page.dart';

extension _DatabasePageStatePart2 on _DatabasePageState {
  Widget _buildSqlEditorView() {
    final theme = Theme.of(context);
    final canWrite = widget.store.canManageDatabase;
    final exportResultIndex = _latestExportableSqlResultIndex();
    final exportRows =
        exportResultIndex == null ? null : _sqlResults[exportResultIndex].rows;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.terminal_outlined),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _t('sql_editor'),
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          FilterChip(
                            label: Text(_t('write_mode')),
                            selected: canWrite && _sqlAllowWrites,
                            onSelected: _sqlRunning || !canWrite
                                ? null
                                : (value) =>
                                    setState(() => _sqlAllowWrites = value),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _sqlAllowWrites
                            ? _t('sql_write_mode_desc')
                            : _t('query_mode_desc'),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _sqlController,
                        minLines: 7,
                        maxLines: 12,
                        style: const TextStyle(fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          labelText: _t('sql_editor'),
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _sqlRunning ? null : _runSqlEditor,
                            icon: _sqlRunning
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.play_arrow),
                            label: Text(_sqlAllowWrites
                                ? _t('execute_sql')
                                : _t('run_query')),
                          ),
                          OutlinedButton.icon(
                            onPressed: _sqlRunning || _selectedKey.isEmpty
                                ? null
                                : _fillSqlForSelectedTable,
                            icon: const Icon(Icons.table_view_outlined),
                            label: Text(_t('select_current_table')),
                          ),
                          OutlinedButton.icon(
                            onPressed: _sqlRunning
                                ? null
                                : () => setState(() {
                                      _sqlController.text =
                                          'SELECT name FROM sqlite_master WHERE type = \'table\' ORDER BY name;';
                                      _sqlError = null;
                                    }),
                            icon: const Icon(Icons.list_alt_outlined),
                            label: Text(_t('list_tables')),
                          ),
                          TextButton.icon(
                            onPressed: _sqlRunning
                                ? null
                                : () => setState(() {
                                      _sqlController.clear();
                                      _sqlResults = const <SqlEditorResult>[];
                                      _expandedSqlExportIndex = null;
                                      _sqlError = null;
                                    }),
                            icon: const Icon(Icons.clear),
                            label: Text(_t('clear')),
                          ),
                        ],
                      ),
                      if (_sqlError != null) ...[
                        const SizedBox(height: 12),
                        Text(_sqlError!,
                            style: TextStyle(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w700)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildSqlResults()),
            ],
          ),
        ),
        if (exportRows != null)
          Positioned(
            right: 24,
            bottom: 24,
            child: SafeArea(
              minimum: const EdgeInsets.only(right: 4, bottom: 4),
              child: _buildSqlExportButton(exportRows, exportResultIndex!),
            ),
          ),
      ],
    );
  }

  Widget _buildSqlResults() {
    if (_sqlResults.isEmpty) {
      return Center(child: Text(_t('no_sql_results_yet')));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 112),
      itemCount: _sqlResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final result = _sqlResults[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(result.statement,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(result.message),
                if (result.isQuery) ...[
                  const SizedBox(height: 12),
                  _buildSqlResultTable(result.rows),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSqlResultTable(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return Text(_t('no_rows_returned'));
    final columns = <String>{};
    for (final row in rows) {
      columns.addAll(row.keys);
    }
    final orderedColumns = columns.toList()..sort();
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 720.0;

        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: tableWidth),
              child: DataTable(
                headingRowHeight: 48,
                dataRowMinHeight: 52,
                dataRowMaxHeight: 72,
                columnSpacing: 32,
                horizontalMargin: 16,
                columns: [
                  const DataColumn(label: Text('#')),
                  for (final column in orderedColumns)
                    DataColumn(label: Text(column)),
                ],
                rows: [
                  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
                    DataRow(
                      cells: [
                        DataCell(Text('${rowIndex + 1}')),
                        for (final column in orderedColumns)
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                  maxWidth: 360, minWidth: 120),
                              child: SelectableText(
                                  _displayValue(rows[rowIndex][column]),
                                  maxLines: 2),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  int? _latestExportableSqlResultIndex() {
    for (var index = _sqlResults.length - 1; index >= 0; index--) {
      final result = _sqlResults[index];
      if (result.isQuery && result.rows.isNotEmpty) return index;
    }
    return null;
  }

  Widget _buildSqlExportButton(
      List<Map<String, Object?>> rows, int resultIndex) {
    final expanded = _expandedSqlExportIndex == resultIndex;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (expanded) ...[
          _buildSqlExportFormatButton(
              'JSON', () => _exportSqlRows(rows, 'json')),
          const SizedBox(height: 8),
          _buildSqlExportFormatButton('CSV', () => _exportSqlRows(rows, 'csv')),
          const SizedBox(height: 8),
          _buildSqlExportFormatButton(
              'XLSX', () => _exportSqlRows(rows, 'xlsx')),
          const SizedBox(height: 8),
        ],
        FloatingActionButton.small(
          heroTag: 'sql-export-$resultIndex',
          tooltip:
              expanded ? _t('close_export_options') : _t('export_sql_result'),
          onPressed: () => setState(
              () => _expandedSqlExportIndex = expanded ? null : resultIndex),
          child: Icon(expanded ? Icons.close : Icons.file_download_outlined),
        ),
      ],
    );
  }

  Widget _buildSqlExportFormatButton(String label, VoidCallback onPressed) {
    return Material(
      elevation: 4,
      shape: const StadiumBorder(),
      color: Theme.of(context).colorScheme.surface,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }

  Future<void> _exportSqlRows(
      List<Map<String, Object?>> rows, String format) async {
    setState(() => _expandedSqlExportIndex = null);
    try {
      await SqlResultExportService.exportRows(
        rows: rows,
        format: format,
        baseFileName: 'sql_result_${_timestampForFileName()}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_tf(
              'sql_result_exported_as', {'format': format.toUpperCase()}))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _timestampForFileName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}_${two(now.month)}_${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  void _fillSqlForSelectedTable() {
    final tableName = _sqliteTableNameForKey(_selectedKey);
    _sqlController.text = 'SELECT * FROM $tableName LIMIT 100;';
    setState(() {
      _sqlError = null;
      _selectedMode = 'sql';
    });
  }

  String _sqliteTableNameForKey(String key) {
    switch (key) {
      case 'products_v4':
        return 'products';
      case 'customers_v4':
        return 'customers';
      case 'suppliers_v4':
        return 'suppliers';
      case 'sales_v4':
        return 'sales';
      case 'purchases_v1':
        return 'purchases';
      case 'expenses_v4':
        return 'expenses';
      case 'stock_movements_v1':
        return 'stock_movements';
      case 'supplier_product_prices_v1':
        return 'supplier_product_prices';
      case 'product_categories_v1':
        return 'catalog_categories';
      case 'product_brands_v1':
        return 'catalog_brands';
      case 'product_units_v1':
        return 'catalog_units';
      default:
        return key.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    }
  }

  Future<void> _runSqlEditor() async {
    if (!widget.store.canManageDatabase) {
      if (_sqlAllowWrites) {
        setState(() => _sqlAllowWrites = false);
      }
    }
    final script = _sqlController.text.trim();
    if (script.isEmpty) return;
    final statements = DatabaseSqlEditorService.splitStatements(script);
    if (statements.isEmpty) return;
    final hasWrites = statements.any(
        (statement) => !DatabaseSqlEditorService.isQueryStatement(statement));
    if (hasWrites) {
      if (!_sqlAllowWrites) {
        setState(() => _sqlError =
            '${_t('sql_script_contains_writes')} ${_t('enable_execute_writes_first')}');
        return;
      }
      if (!await _ensureDatabaseMutationAuthorization()) return;
      final confirmed = await _confirmSqlExecution(statements.length);
      if (confirmed != true) return;
    }

    setState(() {
      _sqlRunning = true;
      _sqlError = null;
    });
    try {
      final results = await DatabaseSqlEditorService.runScript(script,
          allowWrites: _sqlAllowWrites);
      if (hasWrites) {
        await _auditDatabaseMutation(
          'sql_write',
          details: 'statementCount=${statements.length}',
        );
      }
      await widget.store.refreshAfterDatabaseChange(_selectedKey);
      await _reload();
      if (!mounted) return;
      setState(() {
        _sqlResults = results;
        _expandedSqlExportIndex = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_t('execute_sql_local_only'))));
    } catch (error) {
      if (!mounted) return;
      setState(() => _sqlError = error.toString());
    } finally {
      if (mounted) setState(() => _sqlRunning = false);
    }
  }

  Future<bool?> _confirmSqlExecution(int statementCount) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('execute_sql_changes')),
        content:
            Text(_tf('execute_sql_changes_desc', {'count': statementCount})),
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
            child: Text(_t('execute')),
          ),
        ],
      ),
    );
  }

  Widget _buildDataView(dynamic decoded, List<String> columns,
      List<Map<String, dynamic>> visibleRows) {
    if (_selectedKey.isEmpty) {
      return Center(child: Text(_t('no_database_keys_found')));
    }
    if (visibleRows.isEmpty) {
      return Center(child: Text(_t('no_records_in_table')));
    }

    final sortColumnIndex =
        _sortColumn == null ? null : columns.indexOf(_sortColumn!);
    final table = DataTable(
      sortColumnIndex: sortColumnIndex != null && sortColumnIndex >= 0
          ? sortColumnIndex
          : null,
      sortAscending: _sortAscending,
      showCheckboxColumn: true,
      onSelectAll: (selected) {
        setState(() {
          final visibleIndexes = visibleRows
              .map((row) => row['_db_index'] as int? ?? -1)
              .where((index) => index >= 0);
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
                Text(_columnType(column, visibleRows),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                  constraints:
                      const BoxConstraints(maxWidth: 320, minWidth: 120),
                  child:
                      SelectableText(_displayValue(row[column]), maxLines: 1),
                ),
                onTap: column.startsWith('_db_')
                    ? null
                    : () => _openCellEditor(rowIndex, row, column),
              ),
            DataCell(Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                    tooltip: _t('edit_record'),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: widget.store.canManageDatabase
                        ? () => _openRowEditor(rowIndex: rowIndex, row: row)
                        : null),
                IconButton(
                  tooltip: _t('delete_record'),
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: Theme.of(context).colorScheme.error),
                  onPressed: decoded is List &&
                          rowIndex >= 0 &&
                          widget.store.canManageDatabase
                      ? () => _confirmDeleteRow(rowIndex)
                      : null,
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
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _horizontalTableController,
        scrollDirection: Axis.horizontal,
        child: Scrollbar(
          controller: _verticalTableController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _verticalTableController,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context)
                          .size
                          .width
                          .clamp(320.0, double.infinity)
                          .toDouble() -
                      (_sidebarCollapsed ||
                              MediaQuery.of(context).size.width < 720
                          ? 0
                          : 310)),
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
            Text(_tf('structure_name', {'name': _displayKey(_selectedKey)}),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('${_tf('records_count', {
                  'count': rowCount
                })} • ${_tf('raw_characters_count', {'count': raw.length})}'),
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
                      DataCell(
                          Text(_columnType(column, _rowsFor(_decode(raw))))),
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
    if (decoded is Map) {
      return [
        {'...': 'object', ...Map<String, dynamic>.from(decoded)}
      ];
    }
    return [
      {'value': decoded?.toString() ?? ''}
    ];
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
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
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
}
