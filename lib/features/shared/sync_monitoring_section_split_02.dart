part of 'sync_monitoring_section.dart';

_SyncStatusView _syncStatusForClient(
  BuildContext context,
  SyncDeviceState state, {
  required int pendingCount,
}) {
  final tr = AppLocalizations.of(context);
  final lastSync = _lastSuccessfulSyncForClient(state);
  if (pendingCount == 0 && (state.lastAckSequence > 0 || lastSync != null)) {
    return _SyncStatusView(
        label: tr.text('synced'),
        color: Colors.green,
        icon: Icons.check_circle_outline);
  }
  if (pendingCount > 0) {
    return _SyncStatusView(
        label: tr.text('sync_pending'),
        color: Colors.orange,
        icon: Icons.schedule_outlined);
  }
  if (lastSync == null) {
    return _SyncStatusView(
        label: tr.text('sync_pending'),
        color: Colors.orange,
        icon: Icons.schedule_outlined);
  }
  return _SyncStatusView(
    label: tr.text('sync_stale'),
    color: Theme.of(context).colorScheme.error,
    icon: Icons.warning_amber_outlined,
  );
}

class _HostSyncMonitoringTable extends StatefulWidget {
  const _HostSyncMonitoringTable({
    required this.store,
    required this.peerDevices,
    required this.deviceLimit,
    required this.peerStates,
    required this.lanSettings,
    required this.loadingDirectDevices,
    required this.onRefresh,
    required this.onToggleSuspend,
    required this.onDelete,
    required this.onPermanentDelete,
  });

  final ApplicationSession store;
  final List<DirectDeviceStatus> peerDevices;
  final DirectDeviceLimitStatus? deviceLimit;
  final Map<String, HostPeerSyncState> peerStates;
  final LanSyncSettings lanSettings;
  final bool loadingDirectDevices;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String deviceId, bool suspended) onToggleSuspend;
  final Future<void> Function(String deviceId) onDelete;
  final Future<void> Function(String deviceId) onPermanentDelete;

  @override
  State<_HostSyncMonitoringTable> createState() =>
      _HostSyncMonitoringTableState();
}

class _HostSyncMonitoringTableState extends State<_HostSyncMonitoringTable> {
  final ScrollController _tableScrollController = ScrollController();

  @override
  void dispose() {
    _tableScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final directById = <String, DirectDeviceStatus>{
      for (final device in widget.peerDevices)
        if (device.deviceId.trim().isNotEmpty) device.deviceId.trim(): device,
    };
    final deleted = SyncDeviceAccessStore.deletedDeviceIds();
    final suspended = SyncDeviceAccessStore.suspendedDeviceIds();
    final wipePending = SyncDeviceAccessStore.wipePendingDeviceIds();
    final registryById = <String, HostRegistryDevice>{
      for (final entry in widget.lanSettings.hostRegistry.entries)
        if (entry.key.trim().isNotEmpty && entry.value.isActive)
          entry.key.trim(): entry.value,
    };
    final serverClientIds = directById.values
        .where((device) =>
            device.deviceId.trim().isNotEmpty &&
            device.deviceId.trim() != widget.store.sync.deviceId.trim() &&
            device.role.trim().toLowerCase() != 'host' &&
            !device.revoked)
        .map((device) => device.deviceId.trim());
    final deviceIds = <String>{
      ...registryById.keys,
      ...widget.lanSettings.pairedDevices.keys
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty),
      ...serverClientIds,
    }..removeWhere((id) => deleted.contains(id));
    final pairedDeviceIds = deviceIds.toList()..sort();
    final limitPanel = _deviceLimitPanel(
      context,
      widget.deviceLimit ??
          _localClientDeviceLimitStatus(widget.store, LanSyncSettings.load()),
      pairedDeviceIds.length,
    );

    final header = _HostStatusMonitoringCard(
      store: widget.store,
      lanSettings: widget.lanSettings,
      peerDevices: widget.peerDevices,
      peerStates: widget.peerStates,
    );

    if (pairedDeviceIds.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          if (limitPanel != null) ...[
            const SizedBox(height: 12),
            limitPanel,
          ],
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr.text('no_paired_devices_yet'),
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                      onPressed: widget.onRefresh,
                      icon: const Icon(Icons.refresh),
                      label: Text(tr.text('refresh'))),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        if (limitPanel != null) ...[
          const SizedBox(height: 12),
          limitPanel,
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: Text(tr.text('sync_monitoring_source_hint'),
                    style: Theme.of(context).textTheme.bodySmall)),
            IconButton(
                tooltip: tr.text('refresh'),
                onPressed: widget.onRefresh,
                icon: const Icon(Icons.refresh)),
          ],
        ),
        if (widget.loadingDirectDevices)
          const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 860) {
              return Column(
                children: [
                  for (final deviceId in pairedDeviceIds)
                    _HostPeerMonitoringCard(
                      store: widget.store,
                      deviceId: deviceId,
                      state: widget.peerStates[deviceId],
                      registryDevice: registryById[deviceId],
                      lanAuthorized: widget.lanSettings.pairedDevices
                              .containsKey(deviceId) ||
                          ((registryById[deviceId]
                                      ?.deviceToken
                                      .trim()
                                      .isNotEmpty ??
                                  false) &&
                              widget.lanSettings.setupComplete),
                      peerDevice: directById[deviceId],
                      suspended: suspended.contains(deviceId),
                      wipePending: wipePending.contains(deviceId),
                      onToggleSuspend: () => widget.onToggleSuspend(
                          deviceId, suspended.contains(deviceId)),
                      onDelete: () => widget.onDelete(deviceId),
                      onPermanentDelete: () =>
                          widget.onPermanentDelete(deviceId),
                    ),
                ],
              );
            }
            return Scrollbar(
              controller: _tableScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _tableScrollController,
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(label: Text(tr.text('device'))),
                    DataColumn(label: Text(tr.text('active_transport'))),
                    DataColumn(label: Text(tr.text('connection_status'))),
                    DataColumn(label: Text(tr.text('sync_status'))),
                    DataColumn(label: Text(tr.text('last_successful_sync'))),
                    DataColumn(label: Text(tr.text('pending_changes'))),
                    DataColumn(label: Text(tr.text('last_ack_sequence'))),
                    DataColumn(label: Text(tr.text('actions'))),
                  ],
                  rows: [
                    for (final deviceId in pairedDeviceIds)
                      _hostPeerRow(
                        context,
                        store: widget.store,
                        deviceId: deviceId,
                        state: widget.peerStates[deviceId],
                        registryDevice: registryById[deviceId],
                        lanAuthorized: widget.lanSettings.pairedDevices
                                .containsKey(deviceId) ||
                            ((registryById[deviceId]
                                        ?.deviceToken
                                        .trim()
                                        .isNotEmpty ??
                                    false) &&
                                widget.lanSettings.setupComplete),
                        peerDevice: directById[deviceId],
                        suspended: suspended.contains(deviceId),
                        wipePending: wipePending.contains(deviceId),
                        onToggleSuspend: () => widget.onToggleSuspend(
                            deviceId, suspended.contains(deviceId)),
                        onDelete: () => widget.onDelete(deviceId),
                        onPermanentDelete: () =>
                            widget.onPermanentDelete(deviceId),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

DataRow _hostPeerRow(
  BuildContext context, {
  required ApplicationSession store,
  required String deviceId,
  required HostPeerSyncState? state,
  required HostRegistryDevice? registryDevice,
  required bool lanAuthorized,
  required DirectDeviceStatus? peerDevice,
  required bool suspended,
  required bool wipePending,
  required VoidCallback onToggleSuspend,
  required VoidCallback onDelete,
  required VoidCallback onPermanentDelete,
}) {
  final tr = AppLocalizations.of(context);
  final pendingCount = _pendingChangesCountForHostPeer(
      store: store, deviceId: deviceId, state: state, peerDevice: peerDevice);
  final connection = _connectionStatusForHostPeer(context,
      deviceId: deviceId,
      state: state,
      peerDevice: peerDevice,
      suspended: suspended,
      wipePending: wipePending);
  final status = _syncStatusForHostPeer(context, state,
      pendingCount: pendingCount,
      lanAuthorized: lanAuthorized,
      peerDevice: peerDevice,
      suspended: suspended,
      wipePending: wipePending);
  return DataRow(
    cells: [
      DataCell(Text(_deviceLabel(context, deviceId,
          registryDevice: registryDevice, peerDevice: peerDevice))),
      DataCell(Text(_activeTransportForHostPeer(context,
          lanAuthorized: lanAuthorized, peerDevice: peerDevice, state: state))),
      DataCell(_StatusChip(
          label: connection.label,
          color: connection.color,
          icon: connection.icon)),
      DataCell(_StatusChip(
          label: status.label, color: status.color, icon: status.icon)),
      DataCell(Text(_formatDateTime(
          context,
          _lastSuccessfulSyncForHostPeer(
              state: state, peerDevice: peerDevice)))),
      DataCell(Text(_pendingChangesForHostPeer(context,
          store: store,
          deviceId: deviceId,
          state: state,
          peerDevice: peerDevice))),
      DataCell(Text('${_hostPeerAckSequence(state, peerDevice)}')),
      DataCell(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
              onPressed: wipePending ? null : onToggleSuspend,
              child: Text(suspended ? tr.text('resume') : tr.text('suspend'))),
          TextButton(
            onPressed: wipePending ? onPermanentDelete : onDelete,
            child: Text(
                wipePending ? tr.text('permanent_delete') : tr.text('delete')),
          ),
        ],
      )),
    ],
  );
}

class _HostStatusMonitoringCard extends StatelessWidget {
  const _HostStatusMonitoringCard({
    required this.store,
    required this.lanSettings,
    required this.peerDevices,
    required this.peerStates,
  });

  final ApplicationSession store;
  final LanSyncSettings lanSettings;
  final List<DirectDeviceStatus> peerDevices;
  final Map<String, HostPeerSyncState> peerStates;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final identity = store.runtime.identity;
    final activeTransport = identity.activeSyncTransportNormalized;
    final lanReady = activeTransport == 'lan' &&
        lanSettings.setupComplete &&
        lanSettings.autoSyncEnabled;
    final directReady = activeTransport == 'direct' && identity.isDirectEnabled;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.dns_outlined, size: 20),
              Text(tr.text('host_status'),
                  style: Theme.of(context).textTheme.titleSmall),
              _StatusChip(
                  label: tr.text('host'),
                  color: Theme.of(context).colorScheme.primary,
                  icon: Icons.home_work_outlined),
              if (lanReady)
                _StatusChip(
                    label:
                        '${tr.text('connection_lan')}: ${tr.text('connection_state_active')}',
                    color: Colors.green,
                    icon: Icons.lan_outlined),
              if (directReady)
                _StatusChip(
                    label:
                        '${tr.text('connection_direct')}: ${tr.text('connection_state_active')}',
                    color: Colors.blue,
                    icon: Icons.sync),
              if (!lanReady && !directReady)
                _StatusChip(
                    label: tr.text('connection_state_not_configured'),
                    color: Theme.of(context).colorScheme.error,
                    icon: Icons.link_off_outlined),
            ],
          ),
          const SizedBox(height: 12),
          _Line(title: tr.text('device_id'), value: identity.deviceId),
          _Line(
              title: tr.text('host_sequence'),
              value: '${store.sync.latestStoredAuthoritativeSequence}'),
        ],
      ),
    );
  }
}

class _HostPeerMonitoringCard extends StatelessWidget {
  const _HostPeerMonitoringCard({
    required this.store,
    required this.deviceId,
    required this.state,
    required this.registryDevice,
    required this.lanAuthorized,
    required this.peerDevice,
    required this.suspended,
    required this.wipePending,
    required this.onToggleSuspend,
    required this.onDelete,
    required this.onPermanentDelete,
  });

  final ApplicationSession store;
  final String deviceId;
  final HostPeerSyncState? state;
  final HostRegistryDevice? registryDevice;
  final bool lanAuthorized;
  final DirectDeviceStatus? peerDevice;
  final bool suspended;
  final bool wipePending;
  final VoidCallback onToggleSuspend;
  final VoidCallback onDelete;
  final VoidCallback onPermanentDelete;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final pendingCount = _pendingChangesCountForHostPeer(
        store: store, deviceId: deviceId, state: state, peerDevice: peerDevice);
    final connection = _connectionStatusForHostPeer(context,
        deviceId: deviceId,
        state: state,
        peerDevice: peerDevice,
        suspended: suspended,
        wipePending: wipePending);
    final status = _syncStatusForHostPeer(context, state,
        pendingCount: pendingCount,
        lanAuthorized: lanAuthorized,
        peerDevice: peerDevice,
        suspended: suspended,
        wipePending: wipePending);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.devices_other_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                      _deviceLabel(context, deviceId,
                          registryDevice: registryDevice,
                          peerDevice: peerDevice),
                      style: Theme.of(context).textTheme.titleSmall)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _StatusChip(
                label: connection.label,
                color: connection.color,
                icon: connection.icon),
            _StatusChip(
                label: status.label, color: status.color, icon: status.icon),
          ]),
          const SizedBox(height: 12),
          _Line(
              title: tr.text('active_transport'),
              value: _activeTransportForHostPeer(context,
                  lanAuthorized: lanAuthorized,
                  peerDevice: peerDevice,
                  state: state)),
          _Line(title: tr.text('connection_status'), value: connection.label),
          _Line(title: tr.text('sync_status'), value: status.label),
          _Line(
              title: tr.text('last_successful_sync'),
              value: _formatDateTime(
                  context,
                  _lastSuccessfulSyncForHostPeer(
                      state: state, peerDevice: peerDevice))),
          _Line(
              title: tr.text('pending_changes'),
              value: _pendingChangesForHostPeer(context,
                  store: store,
                  deviceId: deviceId,
                  state: state,
                  peerDevice: peerDevice)),
          _Line(
              title: tr.text('last_ack_sequence'),
              value: '${_hostPeerAckSequence(state, peerDevice)}'),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final fullWidth = constraints.maxWidth < 420;
              final suspendButton = OutlinedButton.icon(
                  onPressed: wipePending ? null : onToggleSuspend,
                  icon: Icon(suspended
                      ? Icons.play_arrow_outlined
                      : Icons.pause_circle_outline),
                  label:
                      Text(suspended ? tr.text('resume') : tr.text('suspend')));
              final deleteButton = OutlinedButton.icon(
                onPressed: wipePending ? onPermanentDelete : onDelete,
                icon: Icon(wipePending
                    ? Icons.delete_forever_outlined
                    : Icons.delete_outline),
                label: Text(wipePending
                    ? tr.text('permanent_delete')
                    : tr.text('delete')),
              );
              if (fullWidth) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    suspendButton,
                    const SizedBox(height: 8),
                    deleteButton,
                  ],
                );
              }
              return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [suspendButton, deleteButton]);
            },
          ),
        ],
      ),
    );
  }
}

class _ClientSyncMonitoringPanel extends StatelessWidget {
  const _ClientSyncMonitoringPanel({
    required this.state,
    required this.store,
    required this.lanSettings,
    required this.controlPlaneSettings,
    required this.onRefresh,
  });

  final SyncDeviceState state;
  final ApplicationSession store;
  final LanSyncSettings lanSettings;
  final VpsControlPlaneSettings controlPlaneSettings;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final connection = _connectionStatusForClient(context,
        state: state,
        lanSettings: lanSettings,
        controlPlaneSettings: controlPlaneSettings);
    final status = _syncStatusForClient(context, state,
        pendingCount: store.sync.activeClientPendingCount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                _StatusChip(
                    label: connection.label,
                    color: connection.color,
                    icon: connection.icon),
                _StatusChip(
                    label: status.label,
                    color: status.color,
                    icon: status.icon),
              ]),
            ),
            IconButton(
              tooltip: tr.text('refresh'),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Line(title: tr.text('role'), value: tr.text('client')),
        _Line(title: tr.text('device_id'), value: store.runtime.identity.deviceId),
        _Line(
            title: tr.text('active_transport'),
            value: _transportLabel(
                context,
                state.activeTransport.isNotEmpty
                    ? state.activeTransport
                    : store.runtime.identity.activeSyncTransport)),
        _Line(title: tr.text('connection_status'), value: connection.label),
        _Line(title: tr.text('sync_status'), value: status.label),
        _Line(
            title: tr.text('last_successful_sync'),
            value:
                _formatDateTime(context, _lastSuccessfulSyncForClient(state))),
        _Line(
            title: tr.text('pending_changes'),
            value: '${store.sync.activeClientPendingCount}'),
        _Line(
            title: tr.text('last_ack_sequence'),
            value: '${state.lastAckSequence}'),
      ],
    );
  }
}

Widget? _deviceLimitPanel(
  BuildContext context,
  DirectDeviceLimitStatus? limit,
  int localLinkedClients,
) {
  if (limit == null) return null;
  final theme = Theme.of(context);
  final linked = limit.linked;
  final available = limit.available;
  final reached = limit.limitReached;
  final tr = AppLocalizations.of(context);
  final message = linked == 0
      ? tr.text('device_limit_no_devices')
      : reached
          ? tr.text('device_limit_reached')
          : tr.format('device_limit_available', {
              'count': available,
              'plural': available == 1 ? '' : 's',
            });
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: reached
          ? theme.colorScheme.errorContainer.withValues(alpha: 0.35)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: reached
            ? theme.colorScheme.error.withValues(alpha: 0.45)
            : theme.dividerColor,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            Text(tr.format('device_limit_allowed', {'count': limit.allowed})),
            Text(tr.format('device_limit_linked', {'count': linked})),
            Text(tr.format('device_limit_slots', {'count': available})),
            if (localLinkedClients != linked)
              Text(tr.format(
                  'device_limit_local_list', {'count': localLinkedClients})),
          ],
        ),
      ],
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleSmall),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 130),
                  child: Text(title,
                      maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(value,
                      style: Theme.of(context).textTheme.titleSmall)),
            ],
          );
        },
      ),
    );
  }
}
