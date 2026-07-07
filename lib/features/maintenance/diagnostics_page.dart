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

  Future<void> _copyStartupTimingReport() async {
    final report = StartupTimingService.buildTextReport();
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Startup timing report copied.')),
    );
  }

  Future<void> _saveStartupTimingReport() async {
    final savedPath = await StartupTimingService.saveTextReport();
    if (!mounted) return;
    if (savedPath == null || savedPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Startup timing report was not saved.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Startup timing report saved: $savedPath')),
    );
  }

  String _formatMs(num value) {
    final ms = value.toDouble();
    if (ms < 1000) {
      return '${ms.toStringAsFixed(ms == ms.truncateToDouble() ? 0 : 1)} ms';
    }
    final seconds = ms / 1000;
    return '${seconds.toStringAsFixed(seconds < 10 ? 2 : 1)} s';
  }

  int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  String _formatMsOrPending(int? value) {
    return value == null ? 'pending' : _formatMs(value);
  }

  Widget _buildMetricChip(
    String label,
    String value, {
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildStartupRecordTile(StartupTimingRecord record) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: record.failed
              ? theme.colorScheme.error.withValues(alpha: 0.35)
              : theme.dividerColor,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            record.failed ? Icons.error_outline : Icons.timelapse_outlined,
            color: record.failed
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'category=${record.category} | start=${_formatMs(record.startedAtMs)} | end=${_formatMs(record.endedAtMs)} | duration=${_formatMs(record.durationMs)}${record.failed ? ' | failed' : ''}',
                ),
                if (record.details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SelectableText(record.details),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartupTimingCard() {
    final records = StartupTimingService.snapshot();
    final summary = StartupTimingService.startupSummaryJson();
    final totalElapsed = _asInt(summary['totalElapsedMs']) ?? 0;
    final startupReadyMs = _asInt(summary['startupReadyMs']);
    final startupMode = (summary['startupMode'] ?? '').toString();
    final appInitializeMs = _asInt(summary['appInitializeMs']);
    final primeHeavyCachesMs = _asInt(summary['primeHeavyCachesMs']);
    final storeReadyAtMs = _asInt(summary['storeReadyAtMs']);
    final firstFrameAtMs = _asInt(summary['firstFrameAtMs']);
    final categoryTotals = Map<String, dynamic>.from(
      summary['categoryTotalsMs'] as Map? ?? const <String, dynamic>{},
    );
    final interestingRecords = Map<String, dynamic>.from(
      summary['interestingRecords'] as Map? ?? const <String, dynamic>{},
    );
    final groupedRecords = <String, List<StartupTimingRecord>>{};
    for (final record in records) {
      (groupedRecords[record.category] ??= <StartupTimingRecord>[]).add(record);
    }
    const categoryOrder = <String>[
      'bootstrap',
      'database',
      'app_store',
      'ui',
      'reports',
      'accounting',
      'startup',
    ];
    final orderedCategories = <String>[
      ...categoryOrder.where(groupedRecords.containsKey),
      ...groupedRecords.keys.where((key) => !categoryOrder.contains(key)),
    ];
    final readyLabel =
        startupReadyMs == null ? 'pending' : _formatMs(startupReadyMs);
    final totalLabel = records.isEmpty ? '0 ms' : _formatMs(totalElapsed);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timer_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Startup performance',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    records.isEmpty
                        ? 'No startup timing data captured yet.'
                        : '${records.length} timing records captured. Total session: $totalLabel',
                  ),
                ),
                TextButton.icon(
                  onPressed: _copyStartupTimingReport,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _saveStartupTimingReport,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildMetricChip(
                  'Total session',
                  totalLabel,
                  icon: Icons.timer_outlined,
                ),
                if (startupMode.isNotEmpty)
                  _buildMetricChip(
                    'Startup mode',
                    startupMode,
                    icon: Icons.layers_outlined,
                  ),
                _buildMetricChip(
                  'Ready to use',
                  readyLabel,
                  icon: Icons.play_circle_outline,
                ),
                _buildMetricChip(
                  'App init',
                  _formatMsOrPending(appInitializeMs),
                  icon: Icons.engineering_outlined,
                ),
                _buildMetricChip(
                  'Store ready',
                  _formatMsOrPending(storeReadyAtMs),
                  icon: Icons.check_circle_outline,
                ),
                _buildMetricChip(
                  'First frame',
                  _formatMsOrPending(firstFrameAtMs),
                  icon: Icons.visibility_outlined,
                ),
                _buildMetricChip(
                  'Background warmup',
                  _formatMsOrPending(primeHeavyCachesMs),
                  icon: Icons.cloud_sync_outlined,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (records.isNotEmpty)
              Text(
                'Ready to use is the later of store ready and first frame. The groups below show which startup step consumed time.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            const SizedBox(height: 12),
            if (records.isEmpty)
              const Text(
                  'Open the app again and this section will show the startup trace.')
            else ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (interestingRecords['localDatabaseInitialize'] != null)
                    _buildMetricChip(
                      'Local DB bootstrap',
                      _formatMs(
                        _asInt((interestingRecords['localDatabaseInitialize']
                                as Map)['durationMs']) ??
                            0,
                      ),
                    ),
                  if (interestingRecords['sqliteBootstrap'] != null)
                    _buildMetricChip(
                      'SQLite bootstrap',
                      _formatMs(
                        _asInt((interestingRecords['sqliteBootstrap']
                                as Map)['durationMs']) ??
                            0,
                      ),
                    ),
                  if (interestingRecords['appStoreLegacyStartupLoad'] != null)
                    _buildMetricChip(
                      'Legacy startup load',
                      _formatMs(
                        _asInt((interestingRecords['appStoreLegacyStartupLoad']
                                as Map)['durationMs']) ??
                            0,
                      ),
                    ),
                  if (interestingRecords['appStoreFastStartupLoad'] != null)
                    _buildMetricChip(
                      'Fast startup load',
                      _formatMs(
                        _asInt((interestingRecords['appStoreFastStartupLoad']
                                as Map)['durationMs']) ??
                            0,
                      ),
                    ),
                  if (interestingRecords['appStoreCoreDeferredStartup'] != null)
                    _buildMetricChip(
                      'Deferred core load',
                      _formatMs(
                        _asInt((interestingRecords[
                                    'appStoreCoreDeferredStartup']
                                as Map)['durationMs']) ??
                            0,
                      ),
                    ),
                  if (interestingRecords['appStoreSyncDeferredStartup'] != null)
                    _buildMetricChip(
                      'Sync deferred load',
                      _formatMs(
                        _asInt((interestingRecords[
                                    'appStoreSyncDeferredStartup']
                                as Map)['durationMs']) ??
                            0,
                      ),
                    ),
                  if (interestingRecords['reportsPrewarm'] != null)
                    _buildMetricChip(
                      'Reports prewarm',
                      _formatMs(
                        _asInt((interestingRecords['reportsPrewarm']
                                as Map)['durationMs']) ??
                            0,
                      ),
                    ),
                  if (interestingRecords['accountingPrewarm'] != null)
                    _buildMetricChip(
                      'Accounting prewarm',
                      _formatMs(
                        _asInt((interestingRecords['accountingPrewarm']
                                as Map)['durationMs']) ??
                            0,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: orderedCategories.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final category = orderedCategories[index];
                    final categoryRecords =
                        groupedRecords[category] ?? const [];
                    final categoryTotal = _asInt(categoryTotals[category]) ?? 0;
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ExpansionTile(
                        title: Text(
                          category,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${categoryRecords.length} steps · total ${_formatMs(categoryTotal)}',
                        ),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          if (categoryRecords.isEmpty)
                            const Text('No timings captured in this category.')
                          else
                            Column(
                              children: [
                                for (var i = 0;
                                    i < categoryRecords.length;
                                    i += 1) ...[
                                  _buildStartupRecordTile(categoryRecords[i]),
                                  if (i != categoryRecords.length - 1)
                                    const SizedBox(height: 8),
                                ],
                              ],
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
          const SizedBox(height: 12),
          _buildStartupTimingCard(),
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
