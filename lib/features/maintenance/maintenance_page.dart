import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/services/backup_download_service.dart';
import '../../core/services/windows_release_catalog.dart';
import '../../core/services/page_timing_scope.dart';
import '../../data/app_store.dart';
import '../../core/localization/app_localizations.dart';
import '../database/database_page.dart';
import '../dev_tools/stress_lab_page.dart';
import 'diagnostics_page.dart';
import 'maintenance_models.dart';
import 'maintenance_service.dart';

class MaintenancePage extends StatefulWidget {
  const MaintenancePage({super.key, required this.store});

  final AppStore store;

  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  late final MaintenanceService _service;
  MaintenanceSummary? _summary;
  bool _loading = true;
  bool _lastRunWasDeep = false;
  bool _showDatabaseExplorer = false;
  bool get _showAdvancedTools =>
      kDebugMode || widget.store.canManageMaintenance;

  @override
  void initState() {
    super.initState();
    _service = MaintenanceService(widget.store);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refresh();
    });
  }

  Future<void> _refresh({bool deep = false}) async {
    setState(() => _loading = true);
    final summary = await _service.runHealthCheck(deep: deep);
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _loading = false;
      _lastRunWasDeep = deep;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex += 1;
    }
    return '${size.toStringAsFixed(size >= 10 || unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }

  String _formatDateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} ${two(value.hour)}:${two(value.minute)}';
  }

  String _formatReleaseSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    return _formatBytes(bytes);
  }

  String _releaseSubtitle(AppLocalizations tr, WindowsReleaseItem item) {
    final parts = <String>[];
    if (item.version != null && item.version!.isNotEmpty) {
      final build = item.build == null ? '' : ' build ${item.build}';
      parts.add('${tr.text('version')}: ${item.version}$build');
    }
    final size = _formatReleaseSize(item.sizeBytes);
    if (size.isNotEmpty) parts.add(size);
    if (item.publishedAt != null) parts.add(_formatDateTime(item.publishedAt!));
    return parts.isEmpty ? item.name : parts.join(' • ');
  }

  Future<void> _showWindowsInstallerReleases() async {
    final tr = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(tr.text('windows_installer_versions')),
        content: const SizedBox(
          width: 360,
          child: Center(
            heightFactor: 1.5,
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );

    List<WindowsReleaseItem> releases;
    Object? error;
    try {
      releases = await WindowsReleaseCatalogService().fetchReleases();
    } catch (e) {
      releases = const <WindowsReleaseItem>[];
      error = e;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('windows_installer_versions')),
        content: SizedBox(
          width: 520,
          child: releases.isEmpty
              ? Text(error == null
                  ? tr.text('no_windows_installers_found')
                  : tr.text('could_not_load_windows_installers'))
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: releases.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = releases[index];
                      return ListTile(
                        leading:
                            const Icon(Icons.download_for_offline_outlined),
                        title: Text(item.name),
                        subtitle: Text(_releaseSubtitle(tr, item)),
                        trailing: FilledButton.icon(
                          onPressed: () {
                            WindowsReleaseCatalogService().download(item);
                          },
                          icon: const Icon(Icons.download_outlined),
                          label: Text(tr.text('download')),
                        ),
                      );
                    },
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr.text('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _exportDiagnosticReport() async {
    final summary = _summary;
    if (summary == null) return;

    final report = _service.buildDiagnosticReport(summary);
    final timestamp = summary.generatedAt
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .substring(0, 14);
    final filename = 'ventio_technical_report_$timestamp.json';

    final tr = AppLocalizations.of(context);
    try {
      await downloadTextFile(
          filename: filename,
          content: report,
          dialogTitle: tr.text('technical_report_saved'),
          cancelMessage: tr.text('file_save_cancelled'));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${tr.text('technical_report_saved')}: $filename')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error is StateError
                ? localizeRuntimeMessage(error.message, tr)
                : tr.text('could_not_save_technical_report'))),
      );
    }
  }

  Future<void> _confirmAndRunRepair(MaintenanceRepairAction action) async {
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('run_maintenance_repair')),
        content: Text(tr.text('maintenance_repair_confirm_desc')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr.text('run_repair'))),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await _service.runRepair(action);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              '${_localizedMaintenanceRepairTitle(tr, result.title)}: ${_localizedMaintenanceRepairMessage(tr, result.message)}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.canViewMaintenance) {
      return const _AccessDeniedScaffold(
        title: 'Maintenance',
        message: 'You do not have access to maintenance tools.',
      );
    }
    final summary = _summary;
    final availableRepairActions = summary?.issues
            .map((issue) => issue.repairAction)
            .whereType<MaintenanceRepairAction>()
            .toSet() ??
        const <MaintenanceRepairAction>{};

    if (_showDatabaseExplorer) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () =>
                      setState(() => _showDatabaseExplorer = false),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                ),
                const SizedBox(width: 8),
                const Icon(Icons.storage_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr.text('database_explorer'),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        tr.text('maintenance_center'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: DatabasePage(store: widget.store)),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () => _refresh(deep: false),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 16),
          if (_showAdvancedTools) _buildAdvancedToolsCard(tr),
          Row(
            children: [
              const Icon(Icons.health_and_safety_outlined, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr.text('maintenance_center'),
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(tr.text('maintenance_center_desc'),
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildMaintenanceActionsCard(tr, summary, availableRepairActions),
          const SizedBox(height: 16),
          if (_loading)
            const LinearProgressIndicator()
          else if (summary != null) ...[
            _HealthOverviewCard(summary: summary),
            const SizedBox(height: 16),
            _MaintenanceDashboard(summary: summary),
            const SizedBox(height: 16),
            _SectionCard(
              title: tr.text('readable_report'),
              icon: Icons.summarize_outlined,
              children: [
                _InfoRow(
                    label: tr.text('status'),
                    value: _localizedMaintenanceHealthStatus(tr, summary)),
                _InfoRow(
                    label: tr.text('health_score'),
                    value: '${summary.healthScore}/100'),
                _InfoRow(
                    label: tr.text('issues_found'),
                    value:
                        "${summary.criticalCount} ${tr.text('critical')}, ${summary.warningCount} ${tr.text('warnings')}, ${summary.infoCount} ${tr.text('notes')}"),
                _InfoRow(
                    label: tr.text('database_storage'),
                    value: summary.databaseExists
                        ? tr.text('secure_appdata_storage')
                        : tr.text('not_created_yet')),
                _InfoRow(
                    label: tr.text('database_size'),
                    value: _formatBytes(summary.databaseSizeBytes)),
                _InfoRow(
                    label: tr.text('last_check'),
                    value: _formatDateTime(summary.generatedAt)),
                _InfoRow(
                    label: tr.text('check_type'),
                    value: _lastRunWasDeep
                        ? tr.text('deep_diagnostics')
                        : tr.text('quick_check')),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: tr.text('recommendations'),
              icon: Icons.lightbulb_outline,
              children: [
                for (final recommendation in summary.recommendations)
                  _RecommendationTile(
                      text: _localizedMaintenanceRecommendation(
                          tr, recommendation)),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: tr.text('database'),
              icon: Icons.folder_outlined,
              children: [
                _InfoRow(
                    label: tr.text('platform'), value: summary.platformLabel),
                _InfoRow(
                    label: tr.text('database_directory'),
                    value: summary.databaseDirectoryPath),
                _InfoRow(
                    label: tr.text('database_file'),
                    value: summary.databaseFilePath),
                _InfoRow(
                    label: tr.text('database_exists'),
                    value: summary.databaseExists
                        ? tr.text('yes')
                        : tr.text('no')),
                _InfoRow(
                    label: tr.text('database_size'),
                    value: _formatBytes(summary.databaseSizeBytes)),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: tr.text('data_snapshot'),
              icon: Icons.analytics_outlined,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in summary.counts.entries)
                      _CountChip(label: entry.key, count: entry.value),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: tr.text('health_checks'),
              icon: Icons.fact_check_outlined,
              children: [
                for (final issue in summary.issues) _HealthTile(issue: issue),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMaintenanceActionsCard(
    AppLocalizations tr,
    MaintenanceSummary? summary,
    Set<MaintenanceRepairAction> availableRepairActions,
  ) {
    return _SectionCard(
      title: tr.text('maintenance_actions'),
      icon: Icons.build_outlined,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: (!_loading && widget.store.canManageMaintenance)
                  ? () => _refresh(deep: false)
                  : null,
              icon: const Icon(Icons.cleaning_services_outlined),
              label: Text(tr.text('quick_recheck')),
            ),
            OutlinedButton.icon(
              onPressed: (!_loading && widget.store.canManageMaintenance)
                  ? () => _refresh(deep: true)
                  : null,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(tr.text('run_deep_diagnostics')),
            ),
            OutlinedButton.icon(
              onPressed: summary == null || !widget.store.canManageMaintenance
                  ? null
                  : _exportDiagnosticReport,
              icon: const Icon(Icons.description_outlined),
              label: Text(tr.text('export_technical_report')),
            ),
            OutlinedButton.icon(
              onPressed: widget.store.canManageMaintenance
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PageTimingScope(
                            key: const ValueKey('DiagnosticsPage'),
                            pageKey: 'DiagnosticsPage',
                            pageLabel: 'Diagnostics',
                            child: DiagnosticsPage(store: widget.store),
                          ),
                        ),
                      )
                  : null,
              icon: const Icon(Icons.monitor_heart_outlined),
              label: const Text('Diagnostics / التشخيص'),
            ),
            OutlinedButton.icon(
              onPressed: widget.store.canManageDatabase
                  ? () => setState(() => _showDatabaseExplorer = true)
                  : null,
              icon: const Icon(Icons.storage_outlined),
              label: Text(tr.text('database_explorer')),
            ),
            OutlinedButton.icon(
              onPressed: widget.store.canManageMaintenance
                  ? _showWindowsInstallerReleases
                  : null,
              icon: const Icon(Icons.download_for_offline_outlined),
              label: Text(tr.text('windows_installer_versions')),
            ),
            if (availableRepairActions
                .contains(MaintenanceRepairAction.repairMissingCloudQueue))
              OutlinedButton.icon(
                onPressed: _loading || !widget.store.canManageMaintenance
                    ? null
                    : () => _confirmAndRunRepair(
                        MaintenanceRepairAction.repairMissingCloudQueue),
                icon: const Icon(Icons.sync_problem_outlined),
                label: Text(tr.text('repair_cloud_sync_queue')),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAdvancedToolsCard(AppLocalizations tr) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr.text('advanced_tools')),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (widget.store.isStressLabEnabled)
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PageTimingScope(
                          key: const ValueKey('StressLabPage'),
                          pageKey: 'StressLabPage',
                          pageLabel: 'Stress lab',
                          child: StressLabPage(store: widget.store),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.speed_outlined),
                    label: Text(tr.text('stress_lab')),
                  ),
              ],
            ),
          ],
        ),
      ),
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

class _MaintenanceDashboard extends StatelessWidget {
  const _MaintenanceDashboard({required this.summary});

  final MaintenanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final backupSeverity = _highestSeverity(
        summary, const ['local_backup_status', 'google_drive_backup_status']);
    final cards = [
      _DashboardCardData(
        title: tr.text('database'),
        icon: Icons.storage_outlined,
        severity: summary.databaseExists
            ? MaintenanceSeverity.ok
            : MaintenanceSeverity.warning,
        headline:
            summary.databaseExists ? tr.text('secure') : tr.text('not_created'),
        subtitle: summary.databaseExists
            ? tr.text('stored_in_appdata')
            : tr.text('save_change_create_db'),
        metrics: [
          _DashboardMetric(
              tr.text('size'), _formatCompactBytes(summary.databaseSizeBytes)),
          _DashboardMetric(
              tr.text('keys'), '${summary.counts['localDatabaseKeys'] ?? 0}'),
        ],
      ),
      _DashboardCardData(
        title: tr.text('inventory'),
        icon: Icons.inventory_2_outlined,
        severity: _highestSeverity(summary, const [
          'negative_stock',
          'zero_cost_products',
          'zero_price_products',
          'duplicate_product_names'
        ]),
        headline: _headlineFor(
            context,
            _highestSeverity(summary, const [
              'negative_stock',
              'zero_cost_products',
              'zero_price_products',
              'duplicate_product_names'
            ])),
        subtitle: tr.format(
            'products_tracked', {'count': summary.counts['products'] ?? 0}),
        metrics: [
          _DashboardMetric(
              tr.text('products'), '${summary.counts['products'] ?? 0}'),
          _DashboardMetric(
              tr.text('movements'), '${summary.counts['stockMovements'] ?? 0}'),
        ],
      ),
      _DashboardCardData(
        title: tr.text('accounting'),
        icon: Icons.account_balance_wallet_outlined,
        severity: _highestSeverity(summary, const ['overpaid_sales']),
        headline: _headlineFor(
            context, _highestSeverity(summary, const ['overpaid_sales'])),
        subtitle: tr.format('account_transactions_found',
            {'count': summary.counts['accountTransactions'] ?? 0}),
        metrics: [
          _DashboardMetric(
              tr.text('expenses'), '${summary.counts['expenses'] ?? 0}'),
          _DashboardMetric(tr.text('transactions'),
              '${summary.counts['accountTransactions'] ?? 0}'),
        ],
      ),
      _DashboardCardData(
        title: tr.text('sync'),
        icon: Icons.sync_outlined,
        severity: _highestSeverity(
            summary, const ['data_conflicts', 'pending_sync_changes']),
        headline: _headlineFor(
            context,
            _highestSeverity(
                summary, const ['data_conflicts', 'pending_sync_changes'])),
        subtitle: tr.format('pending_changes_count', {
          'count': (summary.counts['pendingSyncChanges'] ?? 0) +
              (summary.counts['pendingSyncQueue'] ?? 0)
        }),
        metrics: [
          _DashboardMetric(
              tr.text('queue'), '${summary.counts['pendingSyncQueue'] ?? 0}'),
          _DashboardMetric(
              tr.text('conflicts'), '${summary.counts['dataConflicts'] ?? 0}'),
        ],
      ),
      _DashboardCardData(
        title: tr.text('backups'),
        icon: Icons.backup_outlined,
        severity: backupSeverity,
        headline: _headlineFor(context, backupSeverity),
        subtitle: tr.text('backup_status_dashboard_desc'),
        metrics: [
          _DashboardMetric(
              tr.text('local_backup'),
              (summary.counts['localBackupEnabled'] ?? 0) == 1
                  ? tr.text('enabled')
                  : tr.text('disabled')),
          _DashboardMetric(
              tr.text('google_drive'),
              (summary.counts['googleDriveConnected'] ?? 0) == 1
                  ? tr.text('connected')
                  : tr.text('not_connected')),
        ],
      ),
    ];

    return _SectionCard(
      title: tr.text('maintenance_dashboard_pro'),
      icon: Icons.dashboard_customize_outlined,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            final cardWidth =
                isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  SizedBox(
                    width: cardWidth,
                    child: _DashboardCard(data: card),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  static MaintenanceSeverity _highestSeverity(
      MaintenanceSummary summary, List<String> issueIds) {
    final issues = summary.issues.where((issue) => issueIds.contains(issue.id));
    if (issues.any((issue) => issue.severity == MaintenanceSeverity.critical)) {
      return MaintenanceSeverity.critical;
    }
    if (issues.any((issue) => issue.severity == MaintenanceSeverity.warning)) {
      return MaintenanceSeverity.warning;
    }
    if (issues.any((issue) => issue.severity == MaintenanceSeverity.info)) {
      return MaintenanceSeverity.info;
    }
    return MaintenanceSeverity.ok;
  }

  static String _headlineFor(
      BuildContext context, MaintenanceSeverity severity) {
    final tr = AppLocalizations.of(context);
    return switch (severity) {
      MaintenanceSeverity.ok => tr.text('healthy'),
      MaintenanceSeverity.info => tr.text('notes'),
      MaintenanceSeverity.warning => tr.text('needs_review'),
      MaintenanceSeverity.critical => tr.text('critical'),
    };
  }

  static String _formatCompactBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex += 1;
    }
    return '${size.toStringAsFixed(size >= 10 || unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }
}

class _DashboardCardData {
  const _DashboardCardData({
    required this.title,
    required this.icon,
    required this.severity,
    required this.headline,
    required this.subtitle,
    required this.metrics,
  });

  final String title;
  final IconData icon;
  final MaintenanceSeverity severity;
  final String headline;
  final String subtitle;
  final List<_DashboardMetric> metrics;
}

class _DashboardMetric {
  const _DashboardMetric(this.label, this.value);

  final String label;
  final String value;
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.data});

  final _DashboardCardData data;

  @override
  Widget build(BuildContext context) {
    final color = switch (data.severity) {
      MaintenanceSeverity.ok => Colors.green,
      MaintenanceSeverity.info => Colors.blue,
      MaintenanceSeverity.warning => Colors.orange,
      MaintenanceSeverity.critical => Colors.red,
    };
    final icon = switch (data.severity) {
      MaintenanceSeverity.ok => Icons.check_circle_outline,
      MaintenanceSeverity.info => Icons.info_outline,
      MaintenanceSeverity.warning => Icons.warning_amber_outlined,
      MaintenanceSeverity.critical => Icons.error_outline,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(data.icon, size: 24),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(data.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800))),
              Icon(icon, color: color),
            ],
          ),
          const SizedBox(height: 12),
          Text(data.headline,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 4),
          Text(data.subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final metric in data.metrics)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(metric.label,
                          style: Theme.of(context).textTheme.labelSmall),
                      Text(metric.value,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthOverviewCard extends StatelessWidget {
  const _HealthOverviewCard({required this.summary});

  final MaintenanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final isHealthy = summary.isHealthy;
    final icon = summary.criticalCount > 0
        ? Icons.error_outline
        : summary.warningCount > 0
            ? Icons.warning_amber_outlined
            : Icons.check_circle_outline;
    final color = summary.criticalCount > 0
        ? Colors.red
        : summary.warningCount > 0
            ? Colors.orange
            : Colors.green;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          tr.format('ventio_health_status', {
                            'status':
                                _localizedMaintenanceHealthStatus(tr, summary)
                          }),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(isHealthy
                          ? tr.text('no_maintenance_action_needed')
                          : tr.text('review_warnings_before_production')),
                    ],
                  ),
                ),
                _ScoreBadge(score: summary.healthScore),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(
                    label: tr.text('critical'),
                    value: summary.criticalCount,
                    icon: Icons.error_outline),
                _StatusChip(
                    label: tr.text('warnings'),
                    value: summary.warningCount,
                    icon: Icons.warning_amber_outlined),
                _StatusChip(
                    label: tr.text('notes'),
                    value: summary.infoCount,
                    icon: Icons.info_outline),
                _StatusChip(
                    label: tr.text('pending_sync'),
                    value: (summary.counts['pendingSyncChanges'] ?? 0) +
                        (summary.counts['pendingSyncQueue'] ?? 0),
                    icon: Icons.sync_outlined),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$score',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const Text('/100'),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(
      {required this.label, required this.value, required this.icon});

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text('$label: $value'),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard(
      {required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 160,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _RecommendationTile extends StatelessWidget {
  const _RecommendationTile({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label: $count'));
  }
}

class _HealthTile extends StatelessWidget {
  const _HealthTile({required this.issue});

  final MaintenanceIssue issue;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final icon = switch (issue.severity) {
      MaintenanceSeverity.ok => Icons.check_circle_outline,
      MaintenanceSeverity.warning => Icons.warning_amber_outlined,
      MaintenanceSeverity.critical => Icons.error_outline,
      MaintenanceSeverity.info => Icons.info_outline,
    };
    final color = switch (issue.severity) {
      MaintenanceSeverity.ok => Colors.green,
      MaintenanceSeverity.warning => Colors.orange,
      MaintenanceSeverity.critical => Colors.red,
      MaintenanceSeverity.info => Colors.blue,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(_localizedMaintenanceIssueTitle(tr, issue)),
      subtitle: Text(_localizedMaintenanceIssueMessage(tr, issue)),
      trailing: issue.repairAction == null
          ? null
          : const Icon(Icons.build_circle_outlined),
    );
  }
}

String _localizedMaintenanceHealthStatus(
    AppLocalizations tr, MaintenanceSummary summary) {
  if (summary.criticalCount > 0) return tr.text('maintenance_status_critical');
  if (summary.warningCount > 0) return tr.text('maintenance_status_needs');
  if (summary.infoCount > 0) return tr.text('maintenance_status_notes');
  return tr.text('healthy');
}

String _localizedMaintenanceRecommendation(
    AppLocalizations tr, String recommendation) {
  return switch (recommendation) {
    'Run the app once, then run the health check again to confirm the SQLite database file is created.' =>
      tr.text('maintenance_rec_create_db'),
    'Add products to start inventory tracking.' =>
      tr.text('maintenance_rec_add_products'),
    'Create a first sale invoice to validate the sales workflow.' =>
      tr.text('maintenance_rec_first_sale'),
    'Open sync tools and complete pending synchronization when the network is available.' =>
      tr.text('maintenance_rec_sync'),
    'Review data conflicts before creating more invoices.' =>
      tr.text('maintenance_rec_conflicts'),
    'Create a fresh backup before major updates or device changes.' =>
      tr.text('maintenance_rec_backup_fresh'),
    'Create a backup after fixing any maintenance warnings.' =>
      tr.text('maintenance_rec_backup_after'),
    _ => recommendation,
  };
}

String _localizedMaintenanceRepairTitle(AppLocalizations tr, String title) {
  return switch (title) {
    'Database re-check completed' => tr.text('maintenance_recheck_completed'),
    'Cloud sync queue repair completed' =>
      tr.text('maintenance_cloud_queue_repair_completed'),
    _ => title,
  };
}

String _localizedMaintenanceRepairMessage(AppLocalizations tr, String message) {
  final count = _leadingCount(message);
  if (message == 'No data was changed. The health check was refreshed only.') {
    return tr.text('maintenance_recheck_no_changes');
  }
  if (message.startsWith('No missing Host')) {
    return tr.text('maintenance_cloud_queue_repair_none');
  }
  if (count != null && message.contains('missing Host')) {
    return tr.format('maintenance_cloud_queue_repair_count', {'count': count});
  }
  return localizeRuntimeMessage(message, tr);
}

String _localizedMaintenanceIssueTitle(
    AppLocalizations tr, MaintenanceIssue issue) {
  return tr.text('maintenance_issue_${issue.id}_title');
}

String _localizedMaintenanceIssueMessage(
    AppLocalizations tr, MaintenanceIssue issue) {
  switch (issue.id) {
    case 'deep_diagnostics_skipped':
      return tr.text('maintenance_issue_deep_diagnostics_skipped_message');
    case 'database_location':
      if (!issue.message.startsWith('SQLite database file found')) {
        return tr.text('maintenance_issue_database_location_missing');
      }
      return tr.text('maintenance_issue_database_location_found_sqlite');
    case 'local_database_keys':
      return tr.format('maintenance_issue_local_database_keys_message',
          {'count': _leadingCount(issue.message) ?? 0});
    case 'local_backup_status':
    case 'google_drive_backup_status':
      return _localizedMaintenanceBackupIssue(tr, issue.message);
    case 'duplicate_product_names':
    case 'duplicate_customer_names':
    case 'duplicate_supplier_names':
    case 'negative_stock':
    case 'zero_cost_products':
    case 'zero_price_products':
    case 'empty_sales':
    case 'overpaid_sales':
    case 'sale_items_missing_products':
    case 'empty_purchases':
    case 'data_conflicts':
    case 'pending_sync_changes':
      return _localizedMaintenanceCountIssue(tr, issue);
    default:
      return issue.message;
  }
}

String _localizedMaintenanceBackupIssue(AppLocalizations tr, String message) {
  return switch (message) {
    'Backups are managed by the Host device.' =>
      tr.text('maintenance_issue_backups_managed_by_host'),
    'Automatic local backup is healthy.' =>
      tr.text('maintenance_issue_local_backup_ok'),
    'Automatic local backup is disabled.' =>
      tr.text('maintenance_issue_local_backup_disabled'),
    'Automatic local backup is enabled, but no successful backup was recorded yet.' =>
      tr.text('maintenance_issue_local_backup_never'),
    'Automatic local backup is older than the recommended window.' =>
      tr.text('maintenance_issue_local_backup_old'),
    'Google Drive backup is healthy.' =>
      tr.text('maintenance_issue_google_drive_backup_ok'),
    'Google Drive backup is not connected.' =>
      tr.text('maintenance_issue_google_drive_not_connected'),
    'Google Drive backup is connected but automatic backup is disabled.' =>
      tr.text('maintenance_issue_google_drive_disabled'),
    'Google Drive backup is enabled, but no successful backup was recorded yet.' =>
      tr.text('maintenance_issue_google_drive_never'),
    'Google Drive backup is older than the recommended window.' =>
      tr.text('maintenance_issue_google_drive_old'),
    _ => message,
  };
}

String _localizedMaintenanceCountIssue(
    AppLocalizations tr, MaintenanceIssue issue) {
  final prefix = 'maintenance_issue_${issue.id}';
  if (issue.message.startsWith('No ')) return tr.text('${prefix}_ok');
  return tr
      .format('${prefix}_found', {'count': _leadingCount(issue.message) ?? 0});
}

int? _leadingCount(String value) {
  final match = RegExp(r'^(\d+)').firstMatch(value.trim());
  return match == null ? null : int.tryParse(match.group(1)!);
}
