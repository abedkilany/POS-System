import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/app_logging_service.dart';
import '../../core/services/backup_download_service.dart';
import '../../core/services/local_database_service.dart';
import '../../core/services/startup_timing_service.dart';
import '../../data/app_store.dart';
import '../../core/localization/app_localizations.dart';
import 'maintenance_service.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key, required this.store});

  final AppStore store;

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController;
  List<AppLogRecord> _appLogs = const <AppLogRecord>[];
  List<AuditLogRecord> _auditLogs = const <AuditLogRecord>[];
  bool _loading = true;
  AppLogLevel? _selectedLevel;
  String _selectedArea = '';
  String _selectedEntityType = '';

  static const List<String> _areas = <String>[
    '',
    'general',
    'sales',
    'expenses',
    'accounting',
    'sync',
    'backup',
    'login',
    'inventory',
    'maintenance',
    'security',
  ];

  static const List<String> _entityTypes = <String>[
    '',
    'general',
    'product',
    'sale',
    'purchase',
    'expense',
    'journal_entry',
    'customer',
    'supplier',
    'user',
    'account',
    'settings',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refresh();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final search = _searchController.text.trim();
    final appLogs = await AppLogger.fetch(
      query: AppLogQuery(
        level: _selectedLevel,
        area: _selectedArea.isEmpty ? null : _selectedArea,
        limit: 1000,
        search: search,
      ),
    );
    final auditLogs = await AuditLogger.fetch(
      query: AuditLogQuery(
        entityType: _selectedEntityType.isEmpty ? null : _selectedEntityType,
        limit: 1000,
        search: search,
      ),
    );
    if (!mounted) return;
    setState(() {
      _appLogs = appLogs;
      _auditLogs = auditLogs;
      _loading = false;
    });
  }

  Future<void> _copyReport() async {
    final report = await _buildReport();
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostic report copied.')),
    );
  }

  Future<void> _downloadDisplayedData() async {
    final data = await _buildPageData();
    final ts = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .substring(0, 14);
    await downloadTextFile(
      filename: 'ventio_diagnostics_displayed_$ts.json',
      content: data,
      dialogTitle: 'Save displayed diagnostics data',
      cancelMessage: 'Save cancelled',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Displayed diagnostics data downloaded.')),
    );
  }

  Future<void> _downloadAllData() async {
    final data = await _buildAllData();
    final ts = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .substring(0, 14);
    await downloadTextFile(
      filename: 'ventio_diagnostics_all_$ts.json',
      content: data,
      dialogTitle: 'Save all diagnostics data',
      cancelMessage: 'Save cancelled',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All diagnostics data downloaded.')),
    );
  }

  Future<void> _cleanupOldLogs() async {
    final deletedApp = await AppLogger.cleanup();
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Removed $deletedApp non-important technical logs older than 14 days.'),
      ),
    );
  }

  Future<void> _clearTechnicalLogs({bool includeImportant = true}) async {
    await AppLogger.deleteAll(includeImportant: includeImportant);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(includeImportant
            ? 'Cleared all technical logs.'
            : 'Cleared non-important technical logs.'),
      ),
    );
  }

  Future<void> _clearAuditLogs() async {
    final deleted = await AuditLogger.deleteAll();
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cleared $deleted audit logs.')),
    );
  }

  Future<String> _buildReport() async {
    final summary =
        await MaintenanceService(widget.store).runHealthCheck(deep: false);
    final appCounts = await AppLogger.counts();
    final auditCounts = await AuditLogger.counts();
    return jsonEncode(<String, dynamic>{
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'store': widget.store.appIdentity.toJson(),
      'maintenance': summary.toJson(),
      'startupTiming': StartupTimingService.snapshotJson(),
      'logCounts': <String, dynamic>{
        ...appCounts,
        ...auditCounts,
      },
      'technicalLogs': _appLogs.map((item) => item.toJson()).toList(),
      'auditLogs': _auditLogs.map((item) => item.toJson()).toList(),
      'localDatabaseKeys': LocalDatabaseService.keys(),
    });
  }

  Future<String> _buildPageData() async {
    return jsonEncode(<String, dynamic>{
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'filters': <String, dynamic>{
        'search': _searchController.text.trim(),
        'area': _selectedArea,
        'level': _selectedLevel?.name ?? '',
        'entityType': _selectedEntityType,
      },
      'technicalLogs': _appLogs.map((item) => item.toJson()).toList(),
      'auditLogs': _auditLogs.map((item) => item.toJson()).toList(),
    });
  }

  Future<String> _buildAllData() async {
    final search = _searchController.text.trim();
    final appLogs = await AppLogger.fetch(
      query: AppLogQuery(
        level: _selectedLevel,
        area: _selectedArea.isEmpty ? null : _selectedArea,
        limit: 1000000,
        search: search,
      ),
    );
    final auditLogs = await AuditLogger.fetch(
      query: AuditLogQuery(
        entityType: _selectedEntityType.isEmpty ? null : _selectedEntityType,
        limit: 1000000,
        search: search,
      ),
    );
    return jsonEncode(<String, dynamic>{
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'summary':
          (await MaintenanceService(widget.store).runHealthCheck(deep: false))
              .toJson(),
      'logCounts': <String, dynamic>{
        ...await AppLogger.counts(),
        ...await AuditLogger.counts(),
      },
      'technicalLogs': appLogs.map((item) => item.toJson()).toList(),
      'auditLogs': auditLogs.map((item) => item.toJson()).toList(),
      'localDatabaseKeys': LocalDatabaseService.keys(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics / التشخيص'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Technical Logs'),
            Tab(text: 'Audit Logs'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: tr.text('refresh'),
          ),
          IconButton(
            onPressed: _loading ? null : _copyReport,
            icon: const Icon(Icons.copy),
            tooltip: 'Copy report',
          ),
          IconButton(
            onPressed: _loading ? null : _downloadDisplayedData,
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Download displayed data',
          ),
          IconButton(
            onPressed: _loading ? null : _downloadAllData,
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Download all data',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _refresh(),
                  ),
                ),
                DropdownButton<String>(
                  value: _selectedArea,
                  hint: const Text('Area'),
                  items: _areas
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(value.isEmpty ? 'All areas' : value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _selectedArea = value ?? '');
                    _refresh();
                  },
                ),
                DropdownButton<AppLogLevel?>(
                  value: _selectedLevel,
                  hint: const Text('Level'),
                  items: <DropdownMenuItem<AppLogLevel?>>[
                    const DropdownMenuItem<AppLogLevel?>(
                      value: null,
                      child: Text('All levels'),
                    ),
                    for (final level in AppLogLevel.values)
                      DropdownMenuItem<AppLogLevel?>(
                        value: level,
                        child: Text(level.name),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedLevel = value);
                    _refresh();
                  },
                ),
                DropdownButton<String>(
                  value: _selectedEntityType,
                  hint: const Text('Entity type'),
                  items: _entityTypes
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(value.isEmpty ? 'All entities' : value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _selectedEntityType = value ?? '');
                    _refresh();
                  },
                ),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _cleanupOldLogs,
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('Delete old non-important logs'),
                ),
                OutlinedButton.icon(
                  onPressed: _loading ? null : () => _clearTechnicalLogs(),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear all technical logs'),
                ),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _clearAuditLogs,
                  icon: const Icon(Icons.rule_outlined),
                  label: const Text('Clear audit logs'),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _LogsList<AppLogRecord>(
                  items: _appLogs,
                  emptyText: 'No technical logs found.',
                  itemBuilder: (context, item) => _AppLogTile(item: item),
                ),
                _LogsList<AuditLogRecord>(
                  items: _auditLogs,
                  emptyText: 'No audit logs found.',
                  itemBuilder: (context, item) => _AuditLogTile(item: item),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogsList<T> extends StatelessWidget {
  const _LogsList({
    required this.items,
    required this.emptyText,
    required this.itemBuilder,
  });

  final List<T> items;
  final String emptyText;
  final Widget Function(BuildContext context, T item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Text(emptyText));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => itemBuilder(context, items[index]),
    );
  }
}

class _AppLogTile extends StatelessWidget {
  const _AppLogTile({required this.item});

  final AppLogRecord item;

  @override
  Widget build(BuildContext context) {
    final color = switch (item.level) {
      AppLogLevel.debug => Colors.grey,
      AppLogLevel.info => Colors.blue,
      AppLogLevel.warning => Colors.orange,
      AppLogLevel.error => Colors.red,
      AppLogLevel.critical => Colors.deepOrange,
    };
    return Card(
      child: ListTile(
        leading: Icon(Icons.article_outlined, color: color),
        title: Text('${item.area} / ${item.action}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.message),
            if (item.details.isNotEmpty) Text(item.details),
            Text(
              '${item.createdAt.toLocal()}  •  ${item.level.name}  •  ${item.storeId.isEmpty ? '' : item.storeId}',
            ),
            if (item.isImportant) const Text('Important'),
          ],
        ),
        trailing: Chip(label: Text(item.level.name)),
      ),
    );
  }
}

class _AuditLogTile extends StatelessWidget {
  const _AuditLogTile({required this.item});

  final AuditLogRecord item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.rule_outlined),
        title: Text(item.summary),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${item.entityType} / ${item.action}'),
            if (item.fieldName.isNotEmpty)
              Text('${item.fieldName}: ${item.oldValue} -> ${item.newValue}'),
            if (item.details.isNotEmpty) Text(item.details),
            Text(item.createdAt.toLocal().toString()),
            if (item.isImportant) const Text('Important'),
          ],
        ),
        trailing: Text(item.userName.isEmpty ? item.userId : item.userName),
      ),
    );
  }
}
