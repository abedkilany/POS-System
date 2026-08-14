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
    final tr = AppLocalizations.of(context);
    final report = await _buildReport();
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr.text('diagnostic_report_copied'))),
    );
  }

  Future<void> _downloadDisplayedData() async {
    final tr = AppLocalizations.of(context);
    final data = await _buildPageData();
    final ts = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .substring(0, 14);
    await downloadTextFile(
      filename: 'ventio_diagnostics_displayed_$ts.json',
      content: data,
      dialogTitle: tr.text('save_displayed_diagnostics_data'),
      cancelMessage: tr.text('save_cancelled'),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr.text('displayed_diagnostics_downloaded'))),
    );
  }

  Future<void> _downloadAllData() async {
    final tr = AppLocalizations.of(context);
    final data = await _buildAllData();
    final ts = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .substring(0, 14);
    await downloadTextFile(
      filename: 'ventio_diagnostics_all_$ts.json',
      content: data,
      dialogTitle: tr.text('save_all_diagnostics_data'),
      cancelMessage: tr.text('save_cancelled'),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr.text('all_diagnostics_downloaded'))),
    );
  }

  Future<void> _cleanupOldLogs() async {
    final tr = AppLocalizations.of(context);
    final deletedApp = await AppLogger.cleanup();
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr.format('old_technical_logs_removed', {
          'count': deletedApp,
          'days': 14,
        })),
      ),
    );
  }

  Future<void> _clearTechnicalLogs({bool includeImportant = true}) async {
    final tr = AppLocalizations.of(context);
    await AppLogger.deleteAll(includeImportant: includeImportant);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr.text(includeImportant
            ? 'all_technical_logs_cleared'
            : 'non_important_technical_logs_cleared')),
      ),
    );
  }

  Future<void> _clearAuditLogs() async {
    final tr = AppLocalizations.of(context);
    final deleted = await AuditLogger.deleteAll();
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(tr.format('audit_logs_cleared', {'count': deleted}))),
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
    final tr = AppLocalizations.of(context);
    final report = StartupTimingService.buildTextReport();
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr.text('startup_timing_report_copied'))),
    );
  }

  Future<void> _saveStartupTimingReport() async {
    final tr = AppLocalizations.of(context);
    final savedPath = await StartupTimingService.saveTextReport();
    if (!mounted) return;
    if (savedPath == null || savedPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('startup_timing_report_not_saved'))),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              tr.format('startup_timing_report_saved', {'path': savedPath}))),
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
    final tr = AppLocalizations.of(context);
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
                  localizeRuntimeMessage(record.label, tr),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(tr.format('startup_timing_record_details', {
                  'category': localizeRuntimeMessage(record.category, tr),
                  'start': _formatMs(record.startedAtMs),
                  'end': _formatMs(record.endedAtMs),
                  'duration': _formatMs(record.durationMs),
                  'status': record.failed ? tr.text('failed') : '',
                })),
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
    final tr = AppLocalizations.of(context);
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
    final readyLabel = startupReadyMs == null
        ? tr.text('status_pending')
        : _formatMs(startupReadyMs);
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
                    tr.text('startup_performance'),
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
                        ? tr.text('no_startup_timing_data')
                        : tr.format('startup_timing_records_summary', {
                            'count': records.length,
                            'total': totalLabel,
                          }),
                  ),
                ),
                TextButton.icon(
                  onPressed: _copyStartupTimingReport,
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(tr.text('copy')),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _saveStartupTimingReport,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text(tr.text('save')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildMetricChip(
                  tr.text('total_session'),
                  totalLabel,
                  icon: Icons.timer_outlined,
                ),
                if (startupMode.isNotEmpty)
                  _buildMetricChip(
                    tr.text('startup_mode'),
                    startupMode,
                    icon: Icons.layers_outlined,
                  ),
                _buildMetricChip(
                  tr.text('ready_to_use'),
                  readyLabel,
                  icon: Icons.play_circle_outline,
                ),
                _buildMetricChip(
                  tr.text('app_initialization'),
                  _formatMsOrPending(appInitializeMs),
                  icon: Icons.engineering_outlined,
                ),
                _buildMetricChip(
                  tr.text('store_ready'),
                  _formatMsOrPending(storeReadyAtMs),
                  icon: Icons.check_circle_outline,
                ),
                _buildMetricChip(
                  tr.text('first_frame'),
                  _formatMsOrPending(firstFrameAtMs),
                  icon: Icons.visibility_outlined,
                ),
                _buildMetricChip(
                  tr.text('background_warmup'),
                  _formatMsOrPending(primeHeavyCachesMs),
                  icon: Icons.sync,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (records.isNotEmpty)
              Text(
                tr.text('startup_performance_explanation'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            const SizedBox(height: 12),
            if (records.isEmpty)
              Text(tr.text('reopen_app_for_startup_trace'))
            else ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (interestingRecords['localDatabaseInitialize'] != null)
                    _buildMetricChip(
                      tr.text('local_database_bootstrap'),
                      _formatMs(
                        _asInt((interestingRecords['localDatabaseInitialize']
                                as Map)['durationMs']) ??
                            0,
                      ),
                    ),
                  if (interestingRecords['sqliteBootstrap'] != null)
                    _buildMetricChip(
                      tr.text('sqlite_bootstrap'),
                      _formatMs(
                        _asInt((interestingRecords['sqliteBootstrap']
                                as Map)['durationMs']) ??
                            0,
                      ),
                    ),
                  if (interestingRecords['appStoreLegacyStartupLoad'] != null)
                    _buildMetricChip(
                      tr.text('legacy_startup_load'),
                      _formatMs(
                        _asInt((interestingRecords['appStoreLegacyStartupLoad']
                                as Map)['durationMs']) ??
                            0,
                      ),
                    ),
                  if (interestingRecords['appStoreFastStartupLoad'] != null)
                    _buildMetricChip(
                      tr.text('fast_startup_load'),
                      _formatMs(
                        _asInt((interestingRecords['appStoreFastStartupLoad']
                                as Map)['durationMs']) ??
                            0,
                      ),
                    ),
                  if (interestingRecords['appStoreCoreDeferredStartup'] != null)
                    _buildMetricChip(
                      tr.text('deferred_core_load'),
                      _formatMs(
                        _asInt((interestingRecords[
                                    'appStoreCoreDeferredStartup']
                                as Map)['durationMs']) ??
                            0,
                      ),
                    ),
                  if (interestingRecords['appStoreSyncDeferredStartup'] != null)
                    _buildMetricChip(
                      tr.text('sync_deferred_load'),
                      _formatMs(
                        _asInt((interestingRecords[
                                    'appStoreSyncDeferredStartup']
                                as Map)['durationMs']) ??
                            0,
                      ),
                    ),
                  if (interestingRecords['reportsPrewarm'] != null)
                    _buildMetricChip(
                      tr.text('reports_prewarm'),
                      _formatMs(
                        _asInt((interestingRecords['reportsPrewarm']
                                as Map)['durationMs']) ??
                            0,
                      ),
                    ),
                  if (interestingRecords['accountingPrewarm'] != null)
                    _buildMetricChip(
                      tr.text('accounting_prewarm'),
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
                          tr.format('startup_category_summary', {
                            'count': categoryRecords.length,
                            'total': _formatMs(categoryTotal),
                          }),
                        ),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          if (categoryRecords.isEmpty)
                            Text(tr.text('no_category_timings'))
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
        title: Text(tr.text('diagnostics')),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: tr.text('technical_logs')),
            Tab(text: tr.text('audit_logs')),
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
            tooltip: tr.text('copy_report'),
          ),
          IconButton(
            onPressed: _loading ? null : _downloadDisplayedData,
            icon: const Icon(Icons.file_download_outlined),
            tooltip: tr.text('download_displayed_data'),
          ),
          IconButton(
            onPressed: _loading ? null : _downloadAllData,
            icon: const Icon(Icons.download_outlined),
            tooltip: tr.text('download_all_data'),
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
                    decoration: InputDecoration(
                      labelText: tr.text('search'),
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _refresh(),
                  ),
                ),
                DropdownButton<String>(
                  value: _selectedArea,
                  hint: Text(tr.text('area')),
                  items: _areas
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(
                              value.isEmpty ? tr.text('all_areas') : value),
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
                  hint: Text(tr.text('level')),
                  items: <DropdownMenuItem<AppLogLevel?>>[
                    DropdownMenuItem<AppLogLevel?>(
                      value: null,
                      child: Text(tr.text('all_levels')),
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
                  hint: Text(tr.text('entity_type')),
                  items: _entityTypes
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(
                              value.isEmpty ? tr.text('all_entities') : value),
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
                  label: Text(tr.text('delete_old_non_important_logs')),
                ),
                OutlinedButton.icon(
                  onPressed: _loading ? null : () => _clearTechnicalLogs(),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(tr.text('clear_all_technical_logs')),
                ),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _clearAuditLogs,
                  icon: const Icon(Icons.rule_outlined),
                  label: Text(tr.text('clear_audit_logs')),
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
                  emptyText: tr.text('no_technical_logs_found'),
                  itemBuilder: (context, item) => _AppLogTile(item: item),
                ),
                _LogsList<AuditLogRecord>(
                  items: _auditLogs,
                  emptyText: tr.text('no_audit_logs_found'),
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
    final tr = AppLocalizations.of(context);
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
            if (item.isImportant) Text(tr.text('important')),
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
    final tr = AppLocalizations.of(context);
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
            if (item.isImportant) Text(tr.text('important')),
          ],
        ),
        trailing: Text(item.userName.isEmpty ? item.userId : item.userName),
      ),
    );
  }
}
