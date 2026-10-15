// ignore_for_file: invalid_use_of_protected_member
part of 'settings_page.dart';

extension _SyncChannels on _UnifiedSyncSettingsCardState {
  Widget _syncChannelsCard(BuildContext context,
      {required bool isHost,
      required bool lanActive,
      required bool directActive}) {
    final tr = AppLocalizations.of(context);
    final lan = LanSyncSettings.load();
    final direct = DirectSyncSettings.load();
    final lanConfigured =
        isHost ? _lanEnabledForHost : _isLanClientConfigured(lan);
    final directPlanDenied = _directSyncPlanDenied;
    final directPlanChecking = _directSyncPlanChecking;
    final directPlanAllowsUi = _directSyncPlanAllowsUi;
    final directConfigured = isHost
        ? _effectiveDirectEnabled
        : (_isDirectClientConfigured(direct) && directPlanAllowsUi);
    return _plainSyncPanel(
      context,
      icon: Icons.hub_outlined,
      title: tr.text('sync_method'),
      subtitle: tr.text('sync_settings_desc'),
      child: Column(
        children: [
          if (!isHost) ...[
            _activeTransportSelector(context,
                lanConfigured: lanConfigured,
                directConfigured: directConfigured),
            const SizedBox(height: 12),
          ],
          _syncMethodExpansionTile(
            context,
            icon: Icons.lan_outlined,
            title: tr.text('lan_sync'),
            subtitle: isHost
                ? (lanConfigured
                    ? tr.text('connection_state_active')
                    : tr.text('connection_state_disabled'))
                : _clientTransportStatusLabel(context,
                    active: lanActive, configured: lanConfigured),
            active: lanActive,
            configured: lanConfigured,
            accent: Colors.green,
            trailing: isHost
                ? Switch(
                    value: _lanEnabledForHost,
                    onChanged: _busy
                        ? null
                        : (value) {
                            setState(() => _lanEnabledForHost = value);
                            unawaited(_saveSyncSettings());
                          })
                : (!lanConfigured
                    ? TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _openConnectToStoreDialog(SyncMode.lanOnly),
                        icon: const Icon(Icons.add_link_outlined),
                        label: Text(tr.text('connect_to_store')))
                    : null),
            children: isHost
                ? [
                    if (_lanEnabledForHost) ...[
                      _hostIpInfoCard(),
                      ..._lanFields(showHostIp: false, forHost: true),
                    ] else
                      _miniLine(tr.text('status'),
                          tr.text('connection_state_disabled')),
                  ]
                : [
                    _readOnlyTransportLine(
                        context,
                        tr.text('status'),
                        _clientTransportStatusLabel(context,
                            active: lanActive, configured: lanConfigured),
                        lanActive
                            ? Icons.check_circle_outline
                            : (lanConfigured
                                ? Icons.lock_outline
                                : Icons.link_off_outlined)),
                    _readOnlyTransportLine(
                        context,
                        tr.text('pairing_token'),
                        lan.secret.trim().isEmpty ? '—' : '••••••••',
                        Icons.vpn_key_outlined),
                    const SizedBox(height: 12),
                    ..._lanClientFields(),
                  ],
          ),
          const Divider(height: 20),
          _syncMethodExpansionTile(
            context,
            icon: Icons.link_outlined,
            title: 'Direct',
            subtitle: isHost
                ? (directPlanChecking
                    ? tr.text('working')
                    : directPlanDenied
                        ? tr.text('direct_sync_plan_locked_short')
                        : (directConfigured
                            ? tr.text('connection_state_active')
                            : tr.text('connection_state_disabled')))
                : _clientTransportStatusLabel(context,
                    active: directActive, configured: directConfigured),
            active: directActive,
            configured: directConfigured,
            accent: Colors.blue,
            trailing: isHost
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (directPlanDenied) ...[
                        Icon(Icons.lock_outline,
                            size: 18,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                      ],
                      Switch(
                        value: _effectiveDirectEnabled,
                        onChanged:
                            (_busy || directPlanChecking || directPlanDenied)
                                ? null
                                : (value) {
                                    setState(() => _directEnabled = value);
                                    unawaited(_saveSyncSettings());
                                  },
                      ),
                    ],
                  )
                : (!directConfigured
                    ? TextButton.icon(
                        onPressed:
                            (_busy || directPlanChecking || directPlanDenied)
                                ? null
                                : () => _openConnectToStoreDialog(
                                    SyncMode.directConnected),
                        icon: Icon(directPlanAllowsUi
                            ? Icons.add_link_outlined
                            : Icons.lock_outline),
                        label: Text(directPlanAllowsUi
                            ? tr.text('connect_to_store')
                            : tr.text('direct_unavailable')),
                      )
                    : null),
            children: isHost
                ? [
                    if (directPlanChecking)
                      const Center(child: CircularProgressIndicator())
                    else if (directPlanDenied)
                      _softNotice(
                        context,
                        Icons.lock_outline,
                        tr.text('direct_sync_plan_locked_title'),
                        tr.text('direct_sync_plan_locked_desc'),
                      )
                    else if (_effectiveDirectEnabled)
                      ..._directFields(showPairingCode: false)
                    else
                      _miniLine(tr.text('status'),
                          tr.text('connection_state_disabled')),
                  ]
                : [
                    _readOnlyTransportLine(
                        context,
                        tr.text('status'),
                        _clientTransportStatusLabel(context,
                            active: directActive, configured: directConfigured),
                        directActive
                            ? Icons.check_circle_outline
                            : (directConfigured
                                ? Icons.lock_outline
                                : Icons.link_off_outlined)),
                  ],
          ),
        ],
      ),
    );
  }

  Widget _activeTransportSelector(BuildContext context,
      {required bool lanConfigured, required bool directConfigured}) {
    final tr = AppLocalizations.of(context);
    final canSwitchToLan = lanConfigured;
    final canSwitchToDirect = directConfigured;
    final alternateConfigured =
        _clientSyncMode == SyncMode.lanOnly ? directConfigured : lanConfigured;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(tr.text('active_transport'),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800))),
                Tooltip(
                    message: alternateConfigured
                        ? tr.text('switch_transport_available')
                        : tr.text('switch_transport_locked'),
                    child: Icon(
                        alternateConfigured
                            ? Icons.swap_horiz_outlined
                            : Icons.lock_outline,
                        size: 20)),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<SyncMode>(
              segments: [
                ButtonSegment<SyncMode>(
                    value: SyncMode.lanOnly,
                    icon: const Icon(Icons.lan_outlined),
                    label: Text(tr.text('lan')),
                    enabled: canSwitchToLan),
                ButtonSegment<SyncMode>(
                    value: SyncMode.directConnected,
                    icon: const Icon(Icons.link_outlined),
                    label: Text(tr.text('direct')),
                    enabled: canSwitchToDirect),
              ],
              selected: {_clientSyncMode},
              onSelectionChanged: _busy
                  ? null
                  : (value) {
                      final next = value.first;
                      if (next == SyncMode.lanOnly && !lanConfigured) return;
                      if (next == SyncMode.directConnected &&
                          !directConfigured) {
                        return;
                      }
                      setState(() {
                        _clientSyncMode = next;
                        _clientSyncModeDirty = true;
                      });
                    },
            ),
            const SizedBox(height: 8),
            Text(
                alternateConfigured
                    ? tr.text('active_transport_desc')
                    : tr.text('active_transport_locked_desc'),
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _syncMethodExpansionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool active,
    bool configured = false,
    required Color accent,
    required List<Widget> children,
    Widget? trailing,
  }) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 8, bottom: 4),
      leading: CircleAvatar(
        backgroundColor: accent.withValues(alpha: active ? 0.14 : 0.07),
        foregroundColor: active ? accent : color.onSurfaceVariant,
        child: Icon(icon),
      ),
      title: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: color.onSurfaceVariant)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: (active ? accent : color.onSurfaceVariant)
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999)),
            child: Text(
                active
                    ? tr.text('connection_state_active')
                    : (configured
                        ? tr.text('connection_state_disabled')
                        : tr.text('connection_state_not_configured')),
                style: TextStyle(
                    color: active ? accent : color.onSurfaceVariant,
                    fontWeight: FontWeight.w700)),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
          const Icon(Icons.expand_more),
        ],
      ),
      children: children,
    );
  }

  Widget _readOnlyTransportLine(
      BuildContext context, String title, String value, IconData icon) {
    final color = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.outlineVariant.withValues(alpha: 0.80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
              width: VentioResponsive.adaptiveWidth(context,
                  mobile: 105, tablet: 135, desktop: 150),
              child: Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: color.onSurfaceVariant))),
          const SizedBox(width: 8),
          Expanded(
              child: SelectableText(value,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  Widget _advancedSyncCard(BuildContext context, {required bool isHost}) {
    final tr = AppLocalizations.of(context);
    return _plainSyncPanel(
      context,
      icon: Icons.admin_panel_settings_outlined,
      title: tr.text('advanced_settings'),
      subtitle: tr.text('advanced_sync_settings_desc'),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(tr.text('advanced_settings')),
        children: [
          _transferHostCard(isHost: isHost),
        ],
      ),
    );
  }

  Widget _plainSyncPanel(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      required Widget child}) {
    final color = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
        color: color.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.outlineVariant.withValues(alpha: 0.75)),
        boxShadow: [
          BoxShadow(
              color: color.shadow.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: color.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _compactStatusChip(
      BuildContext context, IconData icon, String label, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _simpleInfoRow(BuildContext context, String label, String value,
      IconData icon, Color accent) {
    final color = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: color.surfaceContainerHighest.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          CircleAvatar(
              radius: 18,
              backgroundColor: accent.withValues(alpha: 0.12),
              foregroundColor: accent,
              child: Icon(icon, size: 18)),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: color.onSurfaceVariant)),
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: accent, fontWeight: FontWeight.w800)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _syncSaveCancelBar(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final changed = _hasUnsavedSyncChanges;
    final color = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: changed
                ? color.primary.withValues(alpha: 0.35)
                : color.outlineVariant),
        boxShadow: [
          BoxShadow(
              color: color.shadow.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, -4))
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy || !changed ? null : () => _resetSyncDraft(),
              icon: const Icon(Icons.close_outlined),
              label: Text(tr.text('cancel')),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy || !changed || !_canManageSync
                  ? null
                  : _saveSyncSettings,
              icon: const Icon(Icons.save_outlined),
              label: Text(tr.text('save')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _syncStatusMessage(BuildContext context, ColorScheme color) {
    final tr = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
          color: color.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_busy
              ? (_status.isEmpty ? tr.text('working') : _status)
              : (_status.isEmpty ? _humanStatus(context) : _status)),
          if (_busy) ...[
            const SizedBox(height: 8),
            UnifiedSnapshotProgressView(
              value: _statusProgress,
              label: _status.isEmpty ? tr.text('working') : _status,
            ),
          ],
        ],
      ),
    );
  }
}
