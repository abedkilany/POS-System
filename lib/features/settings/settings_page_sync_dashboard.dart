part of 'settings_page.dart';

extension _SyncDashboard on _UnifiedSyncSettingsCardState {
  Widget _clientSuspendedWarningCard(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    final reason = widget.store.runtime.suspendedByHostReason.trim().isEmpty
        ? tr.text('client_suspended_by_host_desc')
        : widget.store.runtime.suspendedByHostReason;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.42)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.pause_circle_outline, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr.text('client_suspended_by_host'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700, color: color.onSurface)),
                const SizedBox(height: 4),
                Text(reason),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _syncHeroHeader(
    BuildContext context, {
    required bool allGood,
    required bool isHost,
    required bool lanActive,
    required bool directActive,
    required String actionLabel,
  }) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final actionButtons = Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _busy || !_canManageSync ? null : _syncNow,
              icon: const Icon(Icons.sync_outlined),
              label: Text(actionLabel),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _testCurrentConnection,
              icon: const Icon(Icons.network_check_outlined),
              label: Text(tr.text('test_connection')),
            ),
            if (!isHost && widget.store.sync.activeClientPendingCount > 0)
              OutlinedButton.icon(
                onPressed: _busy || !_canManageSync
                    ? null
                    : _clearInvalidPendingChanges,
                icon: const Icon(Icons.cleaning_services_outlined),
                label: Text(tr.text('clear_invalid_pending')),
              ),
          ],
        );
        final titleBlock = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: compact ? 40 : 44,
              height: compact ? 40 : 44,
              decoration: BoxDecoration(
                color: allGood
                    ? Colors.green.withValues(alpha: 0.12)
                    : color.primaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                  allGood ? Icons.check_circle_outline : Icons.sync_outlined,
                  color: allGood ? Colors.green.shade700 : color.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr.text('sync_settings'),
                    style: (compact
                            ? Theme.of(context).textTheme.titleLarge
                            : Theme.of(context).textTheme.headlineSmall)
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    allGood
                        ? tr.text('all_data_synchronized')
                        : tr.text('needs_sync'),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: color.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleBlock,
              const SizedBox(height: 12),
              actionButtons,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 16),
            actionButtons,
          ],
        );
      },
    );
  }

  Widget _syncOverviewCard(BuildContext context,
      {required bool allGood,
      required bool isHost,
      required bool lanActive,
      required bool directActive,
      required int pendingCount}) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    final accent = allGood ? Colors.green : color.primary;
    return Container(
      width: double.infinity,
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final summary = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: accent.withValues(alpha: 0.14),
                foregroundColor: accent,
                child: Icon(allGood
                    ? Icons.verified_outlined
                    : Icons.sync_problem_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        allGood
                            ? tr.text('all_systems_are_running_smoothly')
                            : tr.text('needs_sync'),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(_humanStatus(context),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: color.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          );
          final metrics = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _compactStatusChip(
                  context,
                  Icons.dns_outlined,
                  isHost ? tr.text('host_device') : tr.text('client_device'),
                  color.primary),
              _compactStatusChip(
                  context,
                  Icons.lan_outlined,
                  '${tr.text('lan')}: ${lanActive ? tr.text('connection_state_active') : tr.text('off')}',
                  lanActive ? Colors.green : color.onSurfaceVariant),
              _compactStatusChip(
                  context,
                  Icons.sync,
                  '${tr.text('direct')}: ${directActive ? tr.text('connection_state_active') : tr.text('off')}',
                  directActive ? Colors.green : color.onSurfaceVariant),
              _compactStatusChip(
                  context,
                  Icons.storage_outlined,
                  '${tr.text('pending_changes')}: $pendingCount',
                  pendingCount == 0 ? Colors.green : color.error),
            ],
          );
          if (compact) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [summary, const SizedBox(height: 14), metrics]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: summary),
            const SizedBox(width: 16),
            Flexible(child: metrics)
          ]);
        },
      ),
    );
  }

  Widget _thisDeviceCard(BuildContext context,
      {required bool isHost,
      required bool lanActive,
      required bool directActive}) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    return _plainSyncPanel(
      context,
      icon: Icons.devices_outlined,
      title: tr.text('device_role'),
      subtitle: isHost
          ? tr.text('connection_role_host')
          : tr.text('connection_role_client'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _simpleInfoRow(
              context,
              tr.text('role'),
              isHost ? tr.text('host_device') : tr.text('client_device'),
              Icons.dns_outlined,
              color.primary),
          const SizedBox(height: 8),
          _simpleInfoRow(
              context,
              tr.text('lan_connection'),
              lanActive
                  ? tr.text('connection_state_active')
                  : tr.text('pairing_status_disabled'),
              Icons.lan_outlined,
              lanActive ? Colors.green : color.onSurfaceVariant),
          const SizedBox(height: 8),
          _simpleInfoRow(
              context,
              tr.text('direct_connection'),
              directActive
                  ? tr.text('connection_state_active')
                  : tr.text('connection_state_disabled'),
              Icons.sync,
              directActive ? Colors.green : color.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _addDeviceCard(BuildContext context,
      {required bool isHost, required bool isDirectClient}) {
    final tr = AppLocalizations.of(context);
    return _plainSyncPanel(
      context,
      icon: isHost ? Icons.add_link_outlined : Icons.link_outlined,
      title: isHost ? tr.text('pair_new_device') : tr.text('connect_device'),
      subtitle: isHost
          ? tr.text('pair_new_device_desc')
          : tr.text('connect_device_desc'),
      child: _pairingContent(context,
          isHost: isHost, isDirectClient: isDirectClient),
    );
  }

  bool _isLanClientConfigured(LanSyncSettings lan) =>
      lan.setupComplete &&
      lan.host.trim().isNotEmpty &&
      lan.secret.trim().isNotEmpty;

  bool _isDirectClientConfigured(DirectSyncSettings direct) =>
      direct.isConfigured && direct.apiBaseUrl.trim().isNotEmpty;

  String _clientTransportStatusLabel(BuildContext context,
      {required bool active, required bool configured}) {
    final tr = AppLocalizations.of(context);
    if (active) return tr.text('connection_state_active');
    if (configured) return tr.text('connection_state_disabled');
    return tr.text('not_configured');
  }
}
