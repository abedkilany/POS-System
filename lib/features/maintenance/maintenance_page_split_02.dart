part of 'maintenance_page.dart';

class _MaintenancePageState extends State<MaintenancePage> {
  late final MaintenanceService _service;
  MaintenanceSummary? _summary;
  bool _loading = true;
  bool _lastRunWasDeep = false;
  bool _showDatabaseExplorer = false;
  bool _phase7Running = false;
  bool _recoveryRunning = false;
  bool _costRepairRunning = false;

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

  Future<void> _createRecoveryCheckpoint() async {
    if (_recoveryRunning || !widget.store.canManageMaintenance) return;
    final tr = AppLocalizations.of(context);
    setState(() => _recoveryRunning = true);
    try {
      final result = await DisasterRecoveryService(widget.store)
          .createVerifiedCheckpoint();
      if (!mounted) return;
      await _refresh(deep: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.ok
              ? tr.text('recovery_checkpoint_verified')
              : result.message),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${tr.text('recovery_checkpoint_failed')}: $error')),
      );
    } finally {
      if (mounted) setState(() => _recoveryRunning = false);
    }
  }

  Future<void> _verifyLatestRecoveryBackup() async {
    if (_recoveryRunning || !widget.store.canManageMaintenance) return;
    final tr = AppLocalizations.of(context);
    setState(() => _recoveryRunning = true);
    try {
      final result =
          await DisasterRecoveryService(widget.store).verifyLatestBackup();
      if (!mounted) return;
      await _refresh(deep: false);
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(result.ok
              ? tr.text('recovery_restore_drill_passed')
              : tr.text('recovery_restore_drill_failed')),
          content: SelectableText(
            '${result.message}\n\n${result.path}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr.text('ok')),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('${tr.text('recovery_restore_drill_failed')}: $error')),
      );
    } finally {
      if (mounted) setState(() => _recoveryRunning = false);
    }
  }

  Future<void> _repairProductCosts() async {
    if (_costRepairRunning || !widget.store.canManageMaintenance) return;
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('repair_product_costs_title')),
        content: Text(tr.text('repair_product_costs_desc')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(tr.text('repair_product_costs_confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _costRepairRunning = true);
    try {
      final result = await ProductCostRepairService(widget.store).repair();
      if (!mounted) return;
      await _refresh(deep: true);
      if (!mounted) return;
      final repairMessage = tr.format('repair_product_costs_done', {
        'batches': result.repairedBatches,
        'products': result.rebuiltProducts,
        'unresolved': result.unresolvedBatches,
      });
      final reconciliationMessage = result.inventoryReconciled
          ? tr.text('repair_product_costs_status_ok')
          : tr.format('repair_product_costs_status_pending', {
              'difference': result.inventoryDifference.toStringAsFixed(2),
              'gl': result.inventoryGlBalance.toStringAsFixed(2),
              'valuation': result.inventoryValuation.toStringAsFixed(2),
            });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 7),
          content: Text('$repairMessage\n$reconciliationMessage'),
        ),
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      await _showCostRepairError(error, stackTrace);
    } finally {
      if (mounted) setState(() => _costRepairRunning = false);
    }
  }

  Future<void> _showCostRepairError(Object error, StackTrace stackTrace) async {
    if (!mounted) return;
    final tr = AppLocalizations.of(context);
    final details = <String>[
      'Ventio product cost repair failure',
      'Time: ${DateTime.now().toUtc().toIso8601String()}',
      '${tr.text('error_type')}: ${error.runtimeType}',
      '${tr.text('error_message')}: $error',
      '${tr.text('stack_trace')}:',
      stackTrace.toString(),
    ].join('\n');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(
                child: Text(tr.text('repair_product_costs_error_details'))),
          ],
        ),
        content: SizedBox(
          width: 760,
          height: 430,
          child: SingleChildScrollView(
            child: SelectableText(
              details,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: details));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(tr.text('diagnostic_report_copied'))),
              );
            },
            icon: const Icon(Icons.copy_outlined),
            label: Text(tr.text('copy')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(tr.text('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _showRecoveryReadiness() async {
    if (!widget.store.canManageMaintenance) return;
    final tr = AppLocalizations.of(context);
    setState(() => _recoveryRunning = true);
    try {
      final readiness =
          await DisasterRecoveryService(widget.store).assessReadiness();
      if (!mounted) return;
      final entries = readiness.checks.entries.toList(growable: false);
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr.text('disaster_recovery_readiness')),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  readiness.ready
                      ? tr.text('disaster_recovery_ready')
                      : tr.text('disaster_recovery_not_ready'),
                  style: Theme.of(dialogContext)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                for (final entry in entries)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(entry.value
                        ? Icons.check_circle_outline
                        : Icons.error_outline),
                    title: Text(_recoveryCheckLabel(tr, entry.key)),
                  ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr.text('ok')),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${tr.text('disaster_recovery_readiness')}: $error')),
      );
    } finally {
      if (mounted) setState(() => _recoveryRunning = false);
    }
  }

  String _recoveryCheckLabel(AppLocalizations tr, String key) {
    return switch (key) {
      'hostDevice' => tr.text('recovery_check_host_device'),
      'healthGate' => tr.text('recovery_check_health_gate'),
      'recoveryKey' => tr.text('recovery_check_recovery_key'),
      'localBackupEnabled' => tr.text('recovery_check_local_backup'),
      'recentBackup' => tr.text('recovery_check_recent_backup'),
      'recentRestoreDrill' => tr.text('recovery_check_restore_drill'),
      'platformSupported' => tr.text('recovery_check_platform'),
      _ => key,
    };
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

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _runCashPhase7Migration() async {
    if (_phase7Running || !widget.store.canManageMaintenance) return;
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr.text('phase7_title')),
            content: Text(tr.text('phase7_desc')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(tr.text('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(tr.text('run_phase7')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _phase7Running = true);
    try {
      final report = await _service.runCashPhase7Migration();
      if (!mounted) return;
      final errorCount =
          report.issues.where((issue) => issue.severity == 'error').length;
      final warningCount =
          report.issues.where((issue) => issue.severity == 'warning').length;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(report.hasErrors
              ? tr.text('phase7_completed_with_issues')
              : tr.text('phase7_completed')),
          content: SingleChildScrollView(
            child: SelectableText(tr.format('phase7_report', {
              'runId': report.runId,
              'receipts': report.legacyReceiptsFound,
              'payments': report.legacyPaymentsFound,
              'vouchers': report.vouchersCreated,
              'allocations': report.allocationsCreated,
              'invoiceJournals': report.invoiceEntriesCreated,
              'voucherJournals': report.voucherEntriesCreated,
              'ledgerRows': report.ledgerRowsCreated,
              'caches': report.paymentCachesRebuilt,
              'errors': errorCount,
              'warnings': warningCount,
              'result': report.hasErrors
                  ? tr.text('phase7_not_reconciled')
                  : tr.text('phase7_no_blocking_errors'),
            })),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(tr.text('close'))),
          ],
        ),
      );
      if (mounted) await _refresh(deep: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.format('phase7_failed', {'error': error}))),
      );
    } finally {
      if (mounted) setState(() => _phase7Running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.canViewMaintenance) {
      return _AccessDeniedScaffold(
        title: tr.text('maintenance'),
        message: tr.text('no_access_maintenance_tools'),
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
    final canRepairProductCosts = availableRepairActions
            .contains(MaintenanceRepairAction.repairProductCosts) ||
        widget.store.stockTrackedProducts.isNotEmpty;
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
            FilledButton.icon(
              onPressed: (!_loading &&
                      !_costRepairRunning &&
                      widget.store.canManageMaintenance &&
                      canRepairProductCosts)
                  ? _repairProductCosts
                  : null,
              icon: _costRepairRunning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.price_check_outlined),
              label: Text(tr.text('repair_product_costs')),
            ),
            OutlinedButton.icon(
              onPressed:
                  (!_recoveryRunning && widget.store.canManageMaintenance)
                      ? _showRecoveryReadiness
                      : null,
              icon: const Icon(Icons.health_and_safety_outlined),
              label: Text(tr.text('disaster_recovery_readiness')),
            ),
            FilledButton.icon(
              onPressed: (!_recoveryRunning &&
                      widget.store.canManageMaintenance &&
                      widget.store.hasPermission(AppPermission.backupExport))
                  ? _createRecoveryCheckpoint
                  : null,
              icon: _recoveryRunning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.shield_outlined),
              label: Text(tr.text('create_recovery_checkpoint')),
            ),
            OutlinedButton.icon(
              onPressed: (!_recoveryRunning &&
                      widget.store.canManageMaintenance &&
                      widget.store.hasPermission(AppPermission.backupExport))
                  ? _verifyLatestRecoveryBackup
                  : null,
              icon: const Icon(Icons.verified_user_outlined),
              label: Text(tr.text('verify_latest_backup')),
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
              label: Text(tr.text('diagnostics')),
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
            FilledButton.icon(
              key: const ValueKey('CashPhase7MigrationButton'),
              onPressed: widget.store.canManageMaintenance && !_phase7Running
                  ? _runCashPhase7Migration
                  : null,
              icon: _phase7Running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.account_balance_outlined),
              label: Text(tr.text('phase7_migration')),
            ),
          ],
        ),
      ],
    );
  }
}
