import 'package:flutter/material.dart';

import '../../core/services/backup_download_service.dart';
import '../../data/app_store.dart';
import '../database/database_page.dart';
import '../dev_tools/stress_lab_page.dart';
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
  String? _lastDiagnosticReport;

  @override
  void initState() {
    super.initState();
    _service = MaintenanceService(widget.store);
    _refresh();
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

  Future<void> _exportDiagnosticReport() async {
    final summary = _summary;
    if (summary == null) return;

    final report = _service.buildDiagnosticReport(summary);
    final timestamp = summary.generatedAt.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
    final filename = 'ventio_technical_report_$timestamp.json';

    try {
      await downloadTextFile(filename: filename, content: report);
      if (!mounted) return;
      setState(() => _lastDiagnosticReport = report);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Technical report saved: $filename')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error is StateError ? error.message : 'Could not save technical report.')),
      );
    }
  }

  Future<void> _confirmAndRunRepair(MaintenanceRepairAction action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Run maintenance repair?'),
        content: const Text('Ventio will run a safe repair action. Create a backup first if this is a production device.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Run repair')),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await _service.runRepair(action);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${result.title}: ${result.message}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    return RefreshIndicator(
      onRefresh: () => _refresh(deep: false),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Advanced Tools'),
                  SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DatabasePage(store: widget.store))),
                        icon: Icon(Icons.storage_outlined),
                        label: Text('Database Explorer'),
                      ),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StressLabPage(store: widget.store))),
                        icon: Icon(Icons.speed_outlined),
                        label: Text('Stress Lab'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          Row(
            children: [
              const Icon(Icons.health_and_safety_outlined, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Maintenance Center', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Simple health summary, database status, recommendations, and technical diagnostics.', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _loading ? null : () => _refresh(deep: false),
                icon: const Icon(Icons.refresh),
                label: const Text('Quick check'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const LinearProgressIndicator()
          else if (summary != null) ...[
            _HealthOverviewCard(summary: summary),
            const SizedBox(height: 16),
            _MaintenanceDashboard(summary: summary),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Readable report',
              icon: Icons.summarize_outlined,
              children: [
                _InfoRow(label: 'Status', value: summary.healthStatusLabel),
                _InfoRow(label: 'Health score', value: '${summary.healthScore}/100'),
                _InfoRow(label: 'Issues found', value: '${summary.criticalCount} critical, ${summary.warningCount} warnings, ${summary.infoCount} notes'),
                _InfoRow(label: 'Database storage', value: summary.databaseExists ? 'Secure Ventio AppData storage' : 'Not created yet'),
                _InfoRow(label: 'Database size', value: _formatBytes(summary.databaseSizeBytes)),
                _InfoRow(label: 'Last check', value: _formatDateTime(summary.generatedAt)),
                _InfoRow(label: 'Check type', value: _lastRunWasDeep ? 'Deep diagnostics' : 'Quick check'),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Recommendations',
              icon: Icons.lightbulb_outline,
              children: [
                for (final recommendation in summary.recommendations) _RecommendationTile(text: recommendation),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Database',
              icon: Icons.folder_outlined,
              children: [
                _InfoRow(label: 'Platform', value: summary.platformLabel),
                _InfoRow(label: 'Database directory', value: summary.databaseDirectoryPath),
                _InfoRow(label: 'Database file', value: summary.databaseFilePath),
                _InfoRow(label: 'Database exists', value: summary.databaseExists ? 'Yes' : 'No'),
                _InfoRow(label: 'Database size', value: _formatBytes(summary.databaseSizeBytes)),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Data snapshot',
              icon: Icons.analytics_outlined,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in summary.counts.entries) _CountChip(label: entry.key, count: entry.value),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Health checks',
              icon: Icons.fact_check_outlined,
              children: [
                for (final issue in summary.issues) _HealthTile(issue: issue),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Maintenance actions',
              icon: Icons.build_outlined,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _exportDiagnosticReport,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Export technical report'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _refresh(deep: false),
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('Quick re-check'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : () => _refresh(deep: true),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Run deep diagnostics'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _confirmAndRunRepair(MaintenanceRepairAction.repairMissingCloudQueue),
                      icon: const Icon(Icons.sync_problem_outlined),
                      label: const Text('Repair cloud sync queue'),
                    ),
                  ],
                ),
              ],
            ),
          ],
          if (_lastDiagnosticReport != null) ...[
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Technical report',
              icon: Icons.article_outlined,
              children: [
                Text('This JSON is for developer/support use. The readable summary above is for daily maintenance.', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                SelectableText(_lastDiagnosticReport!, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


class _MaintenanceDashboard extends StatelessWidget {
  const _MaintenanceDashboard({required this.summary});

  final MaintenanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _DashboardCardData(
        title: 'Database',
        icon: Icons.storage_outlined,
        severity: summary.databaseExists ? MaintenanceSeverity.ok : MaintenanceSeverity.warning,
        headline: summary.databaseExists ? 'Secure' : 'Not created',
        subtitle: summary.databaseExists ? 'Stored in Ventio AppData storage.' : 'Save a change to create the database file.',
        metrics: [
          _DashboardMetric('Size', _formatCompactBytes(summary.databaseSizeBytes)),
          _DashboardMetric('Keys', '${summary.counts['localDatabaseKeys'] ?? 0}'),
        ],
      ),
      _DashboardCardData(
        title: 'Inventory',
        icon: Icons.inventory_2_outlined,
        severity: _highestSeverity(summary, const ['negative_stock', 'zero_cost_products', 'zero_price_products', 'duplicate_product_names']),
        headline: _headlineFor(_highestSeverity(summary, const ['negative_stock', 'zero_cost_products', 'zero_price_products', 'duplicate_product_names'])),
        subtitle: '${summary.counts['products'] ?? 0} products tracked.',
        metrics: [
          _DashboardMetric('Products', '${summary.counts['products'] ?? 0}'),
          _DashboardMetric('Movements', '${summary.counts['stockMovements'] ?? 0}'),
        ],
      ),
      _DashboardCardData(
        title: 'Accounting',
        icon: Icons.account_balance_wallet_outlined,
        severity: _highestSeverity(summary, const ['overpaid_sales']),
        headline: _headlineFor(_highestSeverity(summary, const ['overpaid_sales'])),
        subtitle: '${summary.counts['accountTransactions'] ?? 0} account transactions found.',
        metrics: [
          _DashboardMetric('Expenses', '${summary.counts['expenses'] ?? 0}'),
          _DashboardMetric('Transactions', '${summary.counts['accountTransactions'] ?? 0}'),
        ],
      ),
      _DashboardCardData(
        title: 'Sync',
        icon: Icons.sync_outlined,
        severity: _highestSeverity(summary, const ['data_conflicts', 'pending_sync_changes']),
        headline: _headlineFor(_highestSeverity(summary, const ['data_conflicts', 'pending_sync_changes'])),
        subtitle: 'Pending changes: ${(summary.counts['pendingSyncChanges'] ?? 0) + (summary.counts['pendingSyncQueue'] ?? 0)}.',
        metrics: [
          _DashboardMetric('Queue', '${summary.counts['pendingSyncQueue'] ?? 0}'),
          _DashboardMetric('Conflicts', '${summary.counts['dataConflicts'] ?? 0}'),
        ],
      ),
      _DashboardCardData(
        title: 'Backups',
        icon: Icons.backup_outlined,
        severity: MaintenanceSeverity.info,
        headline: 'Recommended',
        subtitle: 'Create backups before updates, migration, or device changes.',
        metrics: [
          _DashboardMetric('Mode', 'Manual'),
          _DashboardMetric('Status', 'Advised'),
        ],
      ),
    ];

    return _SectionCard(
      title: 'Maintenance Dashboard Pro',
      icon: Icons.dashboard_customize_outlined,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            final cardWidth = isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
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

  static MaintenanceSeverity _highestSeverity(MaintenanceSummary summary, List<String> issueIds) {
    final issues = summary.issues.where((issue) => issueIds.contains(issue.id));
    if (issues.any((issue) => issue.severity == MaintenanceSeverity.critical)) return MaintenanceSeverity.critical;
    if (issues.any((issue) => issue.severity == MaintenanceSeverity.warning)) return MaintenanceSeverity.warning;
    if (issues.any((issue) => issue.severity == MaintenanceSeverity.info)) return MaintenanceSeverity.info;
    return MaintenanceSeverity.ok;
  }

  static String _headlineFor(MaintenanceSeverity severity) {
    return switch (severity) {
      MaintenanceSeverity.ok => 'Healthy',
      MaintenanceSeverity.info => 'Notes',
      MaintenanceSeverity.warning => 'Needs review',
      MaintenanceSeverity.critical => 'Critical',
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
              Expanded(child: Text(data.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
              Icon(icon, color: color),
            ],
          ),
          const SizedBox(height: 12),
          Text(data.headline, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 4),
          Text(data.subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final metric in data.metrics)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(metric.label, style: Theme.of(context).textTheme.labelSmall),
                      Text(metric.value, style: const TextStyle(fontWeight: FontWeight.w800)),
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
                      Text('Ventio is ${summary.healthStatusLabel}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(isHealthy ? 'No maintenance problems need action right now.' : 'Review the warnings below before continuing production work.'),
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
                _StatusChip(label: 'Critical', value: summary.criticalCount, icon: Icons.error_outline),
                _StatusChip(label: 'Warnings', value: summary.warningCount, icon: Icons.warning_amber_outlined),
                _StatusChip(label: 'Notes', value: summary.infoCount, icon: Icons.info_outline),
                _StatusChip(label: 'Pending sync', value: (summary.counts['pendingSyncChanges'] ?? 0) + (summary.counts['pendingSyncQueue'] ?? 0), icon: Icons.sync_outlined),
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
          Text('$score', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          const Text('/100'),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.value, required this.icon});

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
  const _SectionCard({required this.title, required this.icon, required this.children});

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
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
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
          SizedBox(width: 160, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
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
      title: Text(issue.title),
      subtitle: Text(issue.message),
      trailing: issue.repairAction == null ? null : const Icon(Icons.build_circle_outlined),
    );
  }
}
