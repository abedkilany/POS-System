part of 'settings_page.dart';

class _AdvancedSyncDebugCard extends StatefulWidget {
  const _AdvancedSyncDebugCard({required this.store});

  final AppStore store;

  @override
  State<_AdvancedSyncDebugCard> createState() => _AdvancedSyncDebugCardState();
}

class _AdvancedSyncDebugCardState extends State<_AdvancedSyncDebugCard> {
  Future<_DirectMonitoringSnapshot>? _directMonitoringFuture;

  DirectControlPlaneService _controlPlaneService() =>
      DirectControlPlaneService(widget.store);

  @override
  void initState() {
    super.initState();
    _refreshDirectDevices();
  }

  void _refreshDirectDevices() {
    final directSettings = VpsControlPlaneSettings.load();
    if (widget.store.runtime.identity.isHost && directSettings.isConfigured) {
      _directMonitoringFuture = _loadAndAdoptDirectDevices(directSettings)
          .catchError((_) => const _DirectMonitoringSnapshot(
                devices: <DirectDeviceStatus>[],
              ));
    } else {
      _directMonitoringFuture = Future<_DirectMonitoringSnapshot>.value(
        _DirectMonitoringSnapshot(
          devices: const <DirectDeviceStatus>[],
          limit: widget.store.runtime.identity.isHost
              ? _localClientDeviceLimitStatus(
                  widget.store,
                  LanSyncSettings.load(),
                )
              : null,
        ),
      );
    }
  }

  Future<_DirectMonitoringSnapshot> _loadAndAdoptDirectDevices(
      VpsControlPlaneSettings directSettings) async {
    final service = _controlPlaneService();
    var result = await service.listDevicesWithLimit(directSettings);
    var devices = result.devices;
    final repaired = await _repairLegacyDirectDeviceLinks(
        service, directSettings, result.devices);
    if (repaired) {
      result = await service.listDevicesWithLimit(directSettings);
      devices = result.devices;
    }
    await _adoptDirectRegistryDevices(devices);
    return _DirectMonitoringSnapshot(
      devices: devices,
      limit: result.limit ??
          _localClientDeviceLimitStatus(widget.store, LanSyncSettings.load()),
    );
  }

  Future<bool> _repairLegacyDirectDeviceLinks(
    DirectControlPlaneService service,
    VpsControlPlaneSettings directSettings,
    List<DirectDeviceStatus> devices,
  ) async {
    final identity = widget.store.runtime.identity;
    if (!identity.isHost) return false;
    final hostDeviceId = widget.store.sync.deviceId.trim();
    if (hostDeviceId.isEmpty) return false;

    final settings =
        LanSyncSettings.load().withMigratedHostRegistry(hostDeviceId);
    final trustedDeviceIds = <String>{
      ...settings.hostRegistry.keys
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty),
      ...settings.pairedDevices.keys
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty),
    }..remove(hostDeviceId);
    if (trustedDeviceIds.isEmpty) return false;

    final repairIds = devices
        .where((device) {
          final deviceId = device.deviceId.trim();
          if (deviceId.isEmpty || deviceId == hostDeviceId) return false;
          if (!trustedDeviceIds.contains(deviceId)) return false;
          if (device.revoked || device.role.trim().toLowerCase() == 'host') {
            return false;
          }
          return device.hostDeviceId.trim().isEmpty;
        })
        .map((device) => device.deviceId.trim())
        .toSet();

    if (repairIds.isEmpty) return false;
    final result = await service.repairLegacyDirectDeviceLinks(
      directSettings,
      clientDeviceIds: repairIds,
    );
    return result.ok;
  }

  Future<void> _adoptDirectRegistryDevices(
      List<DirectDeviceStatus> devices) async {
    final identity = widget.store.runtime.identity;
    if (!identity.isHost) return;
    final hostDeviceId = widget.store.sync.deviceId.trim();
    if (hostDeviceId.isEmpty) return;

    final loadedSettings = LanSyncSettings.load();
    var settings = loadedSettings.withMigratedHostRegistry(hostDeviceId);
    var changed =
        settings.hostRegistry.length != loadedSettings.hostRegistry.length;

    for (final device in devices) {
      final clientDeviceId = device.deviceId.trim();
      if (clientDeviceId.isEmpty || clientDeviceId == hostDeviceId) continue;
      if (device.revoked || device.role.trim().toLowerCase() == 'host') {
        continue;
      }

      final directDeviceName = device.deviceName.trim();
      final before = settings.hostRegistry[clientDeviceId];

      // Fix #1 completion: Host Registry is the display source for Sync
      // Monitoring, so refresh an already-registered Client name from Direct
      // whenever the Direct device row reports a newer/manual deviceName.
      // This must work even for legacy Direct rows that are already in the
      // Registry but do not yet have hostDeviceId populated correctly.
      if (before != null) {
        final registry = <String, HostRegistryDevice>{...settings.hostRegistry};
        final updated = before.copyWith(
          deviceName: directDeviceName.isNotEmpty
              ? directDeviceName
              : before.deviceName,
          lastSeenAt: device.lastSeenAt ?? before.lastSeenAt,
        );
        registry[clientDeviceId] = updated;
        settings = settings.copyWith(hostRegistry: Map.unmodifiable(registry));
        if (updated.deviceName != before.deviceName ||
            updated.lastSeenAt != before.lastSeenAt) {
          changed = true;
        }
        continue;
      }

      // New Direct-only Clients are adopted only when the Direct row is explicitly
      // linked to this Host. Existing Registry members were handled above.
      if (device.hostDeviceId.trim() != hostDeviceId) continue;
      settings = settings.withDirectPairedHostRegistryDevice(
        hostDeviceId: hostDeviceId,
        clientDeviceId: clientDeviceId,
        deviceToken: '',
        deviceName: directDeviceName,
        pairedAt: device.lastSeenAt ?? DateTime.now(),
      );
      changed = true;
    }

    if (changed) await settings.save();
  }

  Future<void> _refresh() async {
    setState(_refreshDirectDevices);
    final snapshot = await (_directMonitoringFuture ??
        Future<_DirectMonitoringSnapshot>.value(
            const _DirectMonitoringSnapshot(devices: <DirectDeviceStatus>[])));
    await _finalizeDirectWipeAcknowledgements(snapshot.devices);
    if (mounted) setState(() {});
  }

  Future<void> _toggleSuspend(String deviceId, bool suspended) async {
    widget.store.security.requirePermission(AppPermission.syncManage);
    final shouldResume = suspended;
    if (shouldResume) {
      await SyncDeviceAccessStore.resume(deviceId);
    } else {
      await SyncDeviceAccessStore.suspend(deviceId);
    }

    final directSettings = VpsControlPlaneSettings.load();
    if (directSettings.isConfigured) {
      await _controlPlaneService().setDeviceSuspended(
        directSettings,
        deviceId,
        suspended: !shouldResume,
      );
    }

    // Resume does not reset any cursor. The device keeps its last ACK/Cursor and
    // the next sync catches up all Host-authoritative events that were missed
    // while it was suspended.
    if (mounted) setState(() {});
  }

  Future<void> _permanentlyDeleteDeviceRecord(String deviceId,
      {String deviceToken = ''}) async {
    final id = deviceId.trim();
    if (id.isEmpty) return;
    final lanSettings = LanSyncSettings.load();
    final registryDevice = lanSettings.hostRegistry[id];
    final token = (deviceToken.trim().isNotEmpty
            ? deviceToken
            : (lanSettings.pairedDevices[id] ??
                registryDevice?.deviceToken ??
                ''))
        .trim();
    final paired = Map<String, String>.from(lanSettings.pairedDevices)
      ..remove(id);
    final registry =
        Map<String, HostRegistryDevice>.from(lanSettings.hostRegistry)
          ..remove(id);
    await lanSettings
        .copyWith(pairedDevices: paired, hostRegistry: registry)
        .save();
    await SyncDeviceStateStore.removePeerState(id);
    await SyncDeviceAccessStore.markDeleted(id, deviceToken: token);
  }

  Future<void> _finalizeDirectWipeAcknowledgements(
      List<DirectDeviceStatus> directDevices) async {
    // Fix #11: a wipe ACK must not automatically remove the device record from
    // the Host list. The Host keeps the Wipe Pending row visible and gives the
    // admin an always-available Permanent Delete action, because the physical
    // device may be lost, stolen, or never come back online.
    return;
  }

  Future<void> _deleteDevice(String deviceId) async {
    widget.store.security.requirePermission(AppPermission.syncManage);
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('delete_sync_device')),
        content: Text(tr.text('delete_sync_device_confirm')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(tr.text('cancel'))),
          FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(tr.text('delete'))),
        ],
      ),
    );
    if (confirmed != true) return;

    final lanSettings = LanSyncSettings.load();
    final registryDevice = lanSettings.hostRegistry[deviceId];
    final deletedDeviceToken = (lanSettings.pairedDevices[deviceId] ??
            registryDevice?.deviceToken ??
            '')
        .trim();

    await SyncDeviceAccessStore.markWipePending(deviceId,
        deviceToken: deletedDeviceToken);

    final directSettings = VpsControlPlaneSettings.load();
    if (directSettings.isConfigured) {
      await _controlPlaneService().revokeDevice(directSettings, deviceId);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr.text('sync_wipe_pending'))));
    await _refresh();
  }

  Future<void> _permanentDeleteDevice(String deviceId) async {
    widget.store.security.requirePermission(AppPermission.syncManage);
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('permanent_delete_sync_device')),
        content: Text(tr.text('permanent_delete_sync_device_confirm')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(tr.text('cancel'))),
          FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(tr.text('permanent_delete'))),
        ],
      ),
    );
    if (confirmed != true) return;

    await _permanentlyDeleteDeviceRecord(deviceId);
    final directSettings = VpsControlPlaneSettings.load();
    if (directSettings.isConfigured) {
      await _controlPlaneService().deleteDeviceRecord(directSettings, deviceId);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('sync_device_permanently_deleted'))));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final isHost = widget.store.runtime.identity.isHost;
    final lanSettings = LanSyncSettings.load();
    final directSettings = VpsControlPlaneSettings.load();
    final peers = SyncDeviceStateStore.loadPeerStates();
    final peerById = <String, HostPeerSyncState>{
      for (final peer in peers) peer.deviceId: peer
    };
    final selfState = SyncDeviceStateStore.load(widget.store.runtime.identity);

    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.monitor_heart_outlined),
        title: Text(tr.text('sync_monitoring_diagnostics')),
        subtitle: Text(isHost
            ? tr.text('sync_monitoring_host_desc')
            : tr.text('sync_monitoring_client_desc')),
        initiallyExpanded: false,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (isHost)
            FutureBuilder<_DirectMonitoringSnapshot>(
              future: _directMonitoringFuture,
              builder: (context, snapshot) => _HostSyncMonitoringTable(
                store: widget.store,
                directDevices:
                    snapshot.data?.devices ?? const <DirectDeviceStatus>[],
                deviceLimit: snapshot.data?.limit,
                peerStates: peerById,
                lanSettings: lanSettings,
                loadingDirectDevices:
                    snapshot.connectionState == ConnectionState.waiting,
                onRefresh: _refresh,
                onToggleSuspend: _toggleSuspend,
                onDelete: _deleteDevice,
                onPermanentDelete: _permanentDeleteDevice,
              ),
            )
          else
            _ClientSyncMonitoringPanel(
              state: selfState,
              store: widget.store,
              lanSettings: lanSettings,
              directSettings: directSettings,
              onRefresh: _refresh,
            ),
        ],
      ),
    );
  }
}

class _HostSyncMonitoringTable extends StatefulWidget {
  const _HostSyncMonitoringTable({
    required this.store,
    required this.directDevices,
    required this.deviceLimit,
    required this.peerStates,
    required this.lanSettings,
    required this.loadingDirectDevices,
    required this.onRefresh,
    required this.onToggleSuspend,
    required this.onDelete,
    required this.onPermanentDelete,
  });

  final AppStore store;
  final List<DirectDeviceStatus> directDevices;
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
      for (final device in widget.directDevices)
        if (device.deviceId.trim().isNotEmpty) device.deviceId.trim(): device,
    };
    final deleted = SyncDeviceAccessStore.deletedDeviceIds();
    final suspended = SyncDeviceAccessStore.suspendedDeviceIds();
    final wipePending = SyncDeviceAccessStore.wipePendingDeviceIds();
    // Phase 3: Host Sync Monitoring must discover devices only from the
    // Host Registry. LAN pairing, Direct rows, and peer history are status
    // details only; they must not add extra devices to this table.
    final registryById = <String, HostRegistryDevice>{
      for (final entry in widget.lanSettings.hostRegistry.entries)
        if (entry.key.trim().isNotEmpty && entry.value.isActive)
          entry.key.trim(): entry.value,
    };
    final deviceIds = registryById.keys.toSet()
      ..removeWhere((id) => deleted.contains(id));
    final pairedDeviceIds = deviceIds.toList()..sort();
    final limitPanel = _deviceLimitPanel(context, pairedDeviceIds.length);

    final header = _HostStatusMonitoringCard(
      store: widget.store,
      lanSettings: widget.lanSettings,
      directDevices: widget.directDevices,
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
                              registryById[deviceId]?.source !=
                                  'direct_pairing_claim'),
                      directDevice: directById[deviceId],
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
              trackVisibility: true,
              notificationPredicate: (notification) =>
                  notification.metrics.axis == Axis.horizontal,
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
                                registryById[deviceId]?.source !=
                                    'direct_pairing_claim'),
                        directDevice: directById[deviceId],
                        suspended: suspended.contains(deviceId),
                        wipePending: wipePending.contains(deviceId),
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

  Widget? _deviceLimitPanel(BuildContext context, int localLinkedClients) {
    final limit = widget.deviceLimit;
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

  DataRow _hostPeerRow(
    BuildContext context, {
    required String deviceId,
    required HostPeerSyncState? state,
    required HostRegistryDevice? registryDevice,
    required bool lanAuthorized,
    required DirectDeviceStatus? directDevice,
    required bool suspended,
    required bool wipePending,
  }) {
    final tr = AppLocalizations.of(context);
    final connection = _connectionStatusForHostPeer(context,
        state: state,
        directDevice: directDevice,
        suspended: suspended,
        wipePending: wipePending);
    final status = _syncStatusForHostPeer(context, state,
        lanAuthorized: lanAuthorized,
        directDevice: directDevice,
        suspended: suspended,
        wipePending: wipePending);
    return DataRow(
      cells: [
        DataCell(Text(_deviceLabel(context, deviceId,
            registryDevice: registryDevice, directDevice: directDevice))),
        DataCell(Text(_activeTransportForHostPeer(context,
            lanAuthorized: lanAuthorized,
            directDevice: directDevice,
            state: state))),
        DataCell(_StatusChip(
            label: connection.label,
            color: connection.color,
            icon: connection.icon)),
        DataCell(_StatusChip(
            label: status.label, color: status.color, icon: status.icon)),
        DataCell(Text(_formatDateTime(
            context,
            _lastSuccessfulSyncForHostPeer(
                state: state, directDevice: directDevice)))),
        DataCell(Text(_pendingChangesForHostPeer(context,
            store: widget.store,
            deviceId: deviceId,
            state: state,
            directDevice: directDevice))),
        DataCell(Text(
            '${state?.lastAckSequence ?? directDevice?.lastAckSequence ?? 0}')),
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
                onPressed: wipePending
                    ? null
                    : () => widget.onToggleSuspend(deviceId, suspended),
                child:
                    Text(suspended ? tr.text('resume') : tr.text('suspend'))),
            TextButton(
              onPressed: wipePending
                  ? () => widget.onPermanentDelete(deviceId)
                  : () => widget.onDelete(deviceId),
              child: Text(wipePending
                  ? tr.text('permanent_delete')
                  : tr.text('delete')),
            ),
          ],
        )),
      ],
    );
  }
}

class _HostStatusMonitoringCard extends StatelessWidget {
  const _HostStatusMonitoringCard({
    required this.store,
    required this.lanSettings,
    required this.directDevices,
    required this.peerStates,
  });

  final AppStore store;
  final LanSyncSettings lanSettings;
  final List<DirectDeviceStatus> directDevices;
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
      padding: VentioResponsive.cardInsets(context),
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
    required this.directDevice,
    required this.suspended,
    required this.wipePending,
    required this.onToggleSuspend,
    required this.onDelete,
    required this.onPermanentDelete,
  });

  final AppStore store;
  final String deviceId;
  final HostPeerSyncState? state;
  final HostRegistryDevice? registryDevice;
  final bool lanAuthorized;
  final DirectDeviceStatus? directDevice;
  final bool suspended;
  final bool wipePending;
  final VoidCallback onToggleSuspend;
  final VoidCallback onDelete;
  final VoidCallback onPermanentDelete;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final connection = _connectionStatusForHostPeer(context,
        state: state,
        directDevice: directDevice,
        suspended: suspended,
        wipePending: wipePending);
    final status = _syncStatusForHostPeer(context, state,
        lanAuthorized: lanAuthorized,
        directDevice: directDevice,
        suspended: suspended,
        wipePending: wipePending);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: VentioResponsive.cardInsets(context),
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
                          directDevice: directDevice),
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
                  directDevice: directDevice,
                  state: state)),
          _Line(title: tr.text('connection_status'), value: connection.label),
          _Line(title: tr.text('sync_status'), value: status.label),
          _Line(
              title: tr.text('last_successful_sync'),
              value: _formatDateTime(
                  context,
                  _lastSuccessfulSyncForHostPeer(
                      state: state, directDevice: directDevice))),
          _Line(
              title: tr.text('pending_changes'),
              value: _pendingChangesForHostPeer(context,
                  store: store,
                  deviceId: deviceId,
                  state: state,
                  directDevice: directDevice)),
          _Line(
              title: tr.text('last_ack_sequence'),
              value:
                  '${state?.lastAckSequence ?? directDevice?.lastAckSequence ?? 0}'),
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
    required this.directSettings,
    required this.onRefresh,
  });

  final SyncDeviceState state;
  final AppStore store;
  final LanSyncSettings lanSettings;
  final VpsControlPlaneSettings directSettings;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final connection = _connectionStatusForClient(context,
        state: state, lanSettings: lanSettings, directSettings: directSettings);
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
