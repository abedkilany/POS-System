part of 'sync_setup_page.dart';

extension _SyncSetupDiagnostics on _SyncSetupPageState {
  Widget _buildConnectionLogCard(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<List<String>>(
      valueListenable: SyncDiagnosticsLog.lines,
      builder: (context, diagnosticLines, _) {
        final directLines =
            diagnosticLines.where((line) => line.contains('[DIRECT_')).toList();
        final summary = SyncDiagnosticsLog.directSummary();
        final combined = <String>[..._connectionLog, ...directLines].join('\n');
        return Card(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.bug_report_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(AppLocalizations.of(context)
                          .text('connection_diagnostics'))),
                  IconButton(
                    tooltip: AppLocalizations.of(context).text('copy_log'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: combined));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(AppLocalizations.of(context)
                                .text('connection_log_copied'))));
                      }
                    },
                    icon: const Icon(Icons.copy_outlined),
                  ),
                ]),
                const SizedBox(height: 8),
                _buildDirectSummary(theme, summary),
                const SizedBox(height: 8),
                SelectableText(
                  combined,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDirectSummary(
      ThemeData theme, DirectDiagnosticsSummary summary) {
    final tr = AppLocalizations.of(context);
    final status = summary.hasConnection
        ? tr.text('ready')
        : tr.text('waiting_for_connection');
    final statusColor = summary.hasConnection
        ? Colors.green.shade700
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 6,
        children: [
          Text('${tr.text('direct')}: $status',
              style: TextStyle(color: statusColor)),
          Text(
              '${tr.text('ice')}: ${summary.iceState.isEmpty ? '-' : summary.iceState}'),
          Text(
              '${tr.text('path')}: ${summary.path.isEmpty ? '-' : summary.path}'),
          Text('${tr.text('restarts')}: ${summary.restartAttempts}'),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    final data = switch (_statusType) {
      _SetupStatus.success => (
          Icons.check_circle_outline,
          color.primaryContainer,
          color.onPrimaryContainer
        ),
      _SetupStatus.warning => (
          Icons.warning_amber_rounded,
          color.tertiaryContainer,
          color.onTertiaryContainer
        ),
      _SetupStatus.error => (
          Icons.error_outline,
          color.errorContainer,
          color.onErrorContainer
        ),
      _ => (
          Icons.info_outline,
          color.surfaceContainerHighest,
          color.onSurfaceVariant
        ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: data.$2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(data.$1, color: data.$3),
          const SizedBox(width: 10),
          Expanded(child: Text(_status, style: TextStyle(color: data.$3))),
          if (_connectionLog.isNotEmpty)
            IconButton(
              tooltip: tr.text('copy_connection_log'),
              onPressed: () async {
                await Clipboard.setData(
                    ClipboardData(text: _fullConnectionLogText));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(AppLocalizations.of(context)
                          .text('connection_log_copied'))));
                }
              },
              icon: Icon(Icons.copy_outlined, color: data.$3),
            ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: _busy ? null : _clearStatus,
            icon: Icon(Icons.close, color: data.$3),
          ),
        ],
      ),
    );
  }
}
