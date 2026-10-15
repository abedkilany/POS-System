import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';

import '../../core/services/local_database_service.dart';
import '../../core/services/database_sql_editor_service.dart';
import '../../core/services/app_logging_service.dart';
import '../../core/services/sql_result_export_service.dart';
import '../../data/app_store.dart';
import '../security/sensitive_action_guard.dart';
import '../../models/user_role.dart';
part 'database_page_methods_01.dart';
part 'database_page_methods_02.dart';
part 'database_page_methods_03.dart';

class DatabasePage extends StatefulWidget {
  const DatabasePage({super.key, required this.store});

  final AppStore store;

  @override
  State<DatabasePage> createState() => _DatabasePageState();
}

class _DatabasePageState extends State<DatabasePage> {
  String _selectedKey = '';
  String _tableQuery = '';
  String _recordQuery = '';
  String _selectedMode = 'data';
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
  final TextEditingController _sqlController = TextEditingController(
      text:
          'SELECT name FROM sqlite_master WHERE type = \'table\' ORDER BY name;');
  bool _sqlAllowWrites = false;
  bool _sqlRunning = false;
  String? _sqlError;
  List<SqlEditorResult> _sqlResults = const <SqlEditorResult>[];
  int? _expandedSqlExportIndex;

  @override
  void dispose() {
    _horizontalTableController.dispose();
    _verticalTableController.dispose();
    _sqlController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _reload();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _requireDatabasePassword());
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.store.security.canManageDatabase &&
        !widget.store.security.hasPermission(AppPermission.databaseView)) {
      return _AccessDeniedScaffold(
        title: _t('database_page'),
        message: _t('no_access_database_tools'),
      );
    }
    final allKeys = _entries.keys.toList()..sort();
    final normalizedTableQuery = _tableQuery.trim().toLowerCase();
    final keys = allKeys
        .where((key) =>
            key.toLowerCase().contains(normalizedTableQuery) ||
            _displayKey(key).toLowerCase().contains(normalizedTableQuery))
        .toList(growable: false);
    final raw = _selectedKey.isEmpty ? '' : (_entries[_selectedKey] ?? '');
    final decoded = _decode(raw);
    final rows = _rowsFor(decoded);
    final filteredRows = rows.where((row) {
      final text = _rowSearchText(row);
      return text.contains(_recordQuery.trim().toLowerCase());
    }).toList(growable: false);
    final columns = _columnsFor(filteredRows.isEmpty ? rows : filteredRows);
    final sortedRows = _sortedRows(filteredRows);
    // Pagination is calculated from data records only. The header row is rendered by
    // DataTable and must not reduce the number of records displayed per page.
    final totalRecords = sortedRows.length;
    final pageCount =
        totalRecords == 0 ? 1 : ((totalRecords - 1) ~/ _pageSize) + 1;
    final safePage = _page.clamp(0, pageCount - 1).toInt();
    final pageStart = totalRecords == 0 ? 0 : safePage * _pageSize;
    final pageEnd = totalRecords == 0
        ? 0
        : (pageStart + _pageSize).clamp(0, totalRecords).toInt();
    final visibleRows = sortedRows.sublist(pageStart, pageEnd);

    if (!_databaseUnlocked) return _buildLockedView();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final content = Column(
          children: [
            if (compact) _buildMobileTableSelector(keys),
            _buildToolbar(
                decoded, pageStart, pageEnd, totalRecords, safePage, pageCount),
            const Divider(height: 1),
            Expanded(
              child: _selectedMode == 'structure'
                  ? _buildStructureView(columns, rows.length, raw)
                  : _selectedMode == 'sql'
                      ? _buildSqlEditorView()
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
}

class _AccessDeniedScaffold extends StatelessWidget {
  const _AccessDeniedScaffold({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
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
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
