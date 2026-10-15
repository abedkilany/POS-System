// ignore_for_file: invalid_use_of_protected_member
part of 'database_page.dart';

extension _DatabasePageStatePart3 on _DatabasePageState {
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

  Future<void> _openCellEditor(
      int rowIndex, Map<String, dynamic> row, String column) async {
    final controller = TextEditingController(text: _displayValue(row[column]));
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(column),
        content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 1,
            maxLines: 8,
            decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_t('save'))),
        ],
      ),
    );
    if (saved != true) return;
    final updated = Map<String, dynamic>.from(row)
      ..remove('_db_index')
      ..remove('...');
    updated[column] = _coerceValue(controller.text, row[column]);
    await _writeRow(rowIndex, updated);
  }

  Future<void> _openRowEditor(
      {int? rowIndex, Map<String, dynamic>? row}) async {
    if (!widget.store.canManageDatabase) return;
    final decoded = _decode(_entries[_selectedKey] ?? '');
    final isNew = row == null;
    final existingRows = _rowsFor(decoded);
    final tableColumns = _columnsFor(existingRows)
        .where((column) => !column.startsWith('_db_') && column != '...')
        .toList(growable: false);
    final workingRow = <String, dynamic>{};

    if (isNew) {
      for (final column in tableColumns) {
        workingRow[column] = column == 'id'
            ? DateTime.now().microsecondsSinceEpoch.toString()
            : '';
      }
      if (workingRow.isEmpty) {
        workingRow['id'] = DateTime.now().microsecondsSinceEpoch.toString();
      }
    } else {
      workingRow.addAll(Map<String, dynamic>.from(row)
        ..remove('_db_index')
        ..remove('...'));
    }

    final columns = workingRow.keys.toList();
    final controllers = <String, TextEditingController>{
      for (final column in columns)
        column: TextEditingController(text: _displayValue(workingRow[column])),
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
                  TextField(
                      controller: controllers[column],
                      minLines: 1,
                      maxLines: _isLargeField(column) ? 5 : 1,
                      decoration: InputDecoration(
                          labelText: column,
                          border: const OutlineInputBorder())),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(isNew ? _t('add_record') : _t('save'))),
        ],
      ),
    );
    if (saved != true) return;
    for (final column in columns) {
      workingRow[column] =
          _coerceValue(controllers[column]?.text ?? '', workingRow[column]);
    }
    if (decoded is List) {
      await _writeRow(isNew ? decoded.length : (rowIndex ?? -1), workingRow);
    } else {
      await _writeSelectedKey(jsonEncode(workingRow));
    }
  }

  bool _isLargeField(String column) {
    final lower = column.toLowerCase();
    return lower.contains('items') ||
        lower.contains('payload') ||
        lower.contains('note') ||
        lower.contains('permissions') ||
        lower.contains('address');
  }

  Future<void> _writeRow(int rowIndex, Map<String, dynamic> row) async {
    if (!widget.store.canManageDatabase) return;
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
    if (!widget.store.canManageDatabase) return;
    if (!await _ensureDatabaseMutationAuthorization()) return;
    final changedKey = _selectedKey;
    await LocalDatabaseService.setString(changedKey, value);
    await _auditDatabaseMutation('raw_write', details: 'key=$changedKey');
    await widget.store.refreshAfterDatabaseChange(changedKey);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_t('database_saved_restart'))));
  }

  Future<void> _openRawEditor() async {
    if (!widget.store.canManageDatabase) return;
    final controller =
        TextEditingController(text: _entries[_selectedKey] ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_tf('raw_json_name', {'name': _selectedKey})),
        content: SizedBox(
            width: 900,
            child: TextField(
                controller: controller,
                minLines: 18,
                maxLines: 24,
                decoration:
                    const InputDecoration(border: OutlineInputBorder()))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_t('save_raw'))),
        ],
      ),
    );
    if (saved != true) return;
    final rawText = controller.text.trim();
    if (rawText.isNotEmpty) {
      try {
        jsonDecode(rawText);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_t('invalid_json'))));
        return;
      }
    }
    await _writeSelectedKey(controller.text);
  }

  Future<void> _confirmDeleteRow(int rowIndex) async {
    if (!widget.store.canManageDatabase) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('delete_record')),
        content: Text(_t('delete_record_question')),
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
    );
    if (confirmed != true) return;
    final decoded = _decode(_entries[_selectedKey] ?? '');
    if (decoded is! List || rowIndex < 0 || rowIndex >= decoded.length) return;
    final list = List<dynamic>.from(decoded)..removeAt(rowIndex);
    await _writeSelectedKey(jsonEncode(list));
  }

  Future<void> _confirmDeleteKey() async {
    if (!widget.store.canManageDatabase) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('delete_database_key')),
        content:
            Text(_tf('delete_database_key_question', {'key': _selectedKey})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_t('delete_key'))),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!await _ensureDatabaseMutationAuthorization()) return;
    final changedKey = _selectedKey;
    await LocalDatabaseService.deleteString(changedKey);
    await _auditDatabaseMutation('delete_key', details: 'key=$changedKey');
    await widget.store.refreshAfterDatabaseChange(changedKey);
    await _reload();
  }
}
