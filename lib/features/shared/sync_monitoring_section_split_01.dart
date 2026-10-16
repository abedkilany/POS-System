part of 'sync_monitoring_section.dart';

class SyncMonitoringSection extends StatefulWidget {
  const SyncMonitoringSection({
    super.key,
    required this.store,
    this.forceHostView = false,
    this.storeIdOverride,
    this.branchIdOverride,
  });

  final ApplicationSession store;
  final bool forceHostView;
  final String? storeIdOverride;
  final String? branchIdOverride;

  @override
  State<SyncMonitoringSection> createState() => _SyncMonitoringSectionState();
}

class _SyncMonitoringSectionState extends State<SyncMonitoringSection> {
  Future<_DirectMonitoringSnapshot>? _directMonitoringFuture;
  StreamSubscription<SyncPeerLiveEvent>? _liveSubscription;

  ApplicationSession get store => widget.store;
  DirectControlPlaneService get _controlPlaneService =>
      DirectControlPlaneService(store);

  @override
  void initState() {
    super.initState();
    _liveSubscription = SyncDeviceStateStore.peerLiveEvents.stream.listen((_) {
      if (mounted) setState(() {});
    });
    _refreshDirectDevices();
  }

  @override
  void dispose() {
    _liveSubscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SyncMonitoringSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _refreshDirectDevices();
    }
  }

  void _refreshDirectDevices() {
    final lanSettings = LanSyncSettings.load();
    final fallback = _DirectMonitoringSnapshot(
      devices: const <DirectDeviceStatus>[],
      limit: store.runtime.identity.isHost
          ? _localClientDeviceLimitStatus(store, lanSettings)
          : null,
    );
    final controlPlaneSettings = VpsControlPlaneSettings.load();
    final showHostView = widget.forceHostView || store.runtime.identity.isHost;
    if (!showHostView || !controlPlaneSettings.isConfigured) {
      _directMonitoringFuture = Future<_DirectMonitoringSnapshot>.value(
        fallback,
      );
      return;
    }

    final remoteFuture = _loadAndAdoptDirectDevices(controlPlaneSettings);
    _directMonitoringFuture = remoteFuture.catchError((error, stackTrace) {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] monitoring device refresh failed error=$error',
      );
      return fallback;
    });
    _directMonitoringFuture!.then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<_DirectMonitoringSnapshot> _loadAndAdoptDirectDevices(
      VpsControlPlaneSettings controlPlaneSettings) async {
    final service = _controlPlaneService;
    var result = await service.listDevicesWithLimit(
      controlPlaneSettings,
      storeIdOverride: widget.storeIdOverride,
      branchIdOverride: widget.branchIdOverride,
    );
    var devices = result.devices;
    final repaired = await _repairLegacyDirectDeviceLinks(
        service, controlPlaneSettings, devices);
    if (repaired) {
      result = await service.listDevicesWithLimit(
        controlPlaneSettings,
        storeIdOverride: widget.storeIdOverride,
        branchIdOverride: widget.branchIdOverride,
      );
      devices = result.devices;
    }
    await _adoptDirectRegistryDevices(devices);
    return _DirectMonitoringSnapshot(
      devices: devices,
      limit: result.limit ??
          _localClientDeviceLimitStatus(store, LanSyncSettings.load()),
    );
  }

  Future<bool> _repairLegacyDirectDeviceLinks(
    DirectControlPlaneService service,
    VpsControlPlaneSettings controlPlaneSettings,
    List<DirectDeviceStatus> devices,
  ) async {
    final identity = store.runtime.identity;
    if (!identity.isHost) return false;
    final hostDeviceId = store.sync.deviceId.trim();
    if (hostDeviceId.isEmpty) return false;

    final lanSettings = LanSyncSettings.load();
    final trustedDeviceIds = <String>{
      ...lanSettings.pairedDevices.keys.map((id) => id.trim()),
      ...lanSettings.hostRegistry.keys.map((id) => id.trim()),
    }..removeWhere((id) => id.isEmpty);

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
      controlPlaneSettings,
      clientDeviceIds: repairIds,
    );
    return result.ok;
  }

  Future<void> _adoptDirectRegistryDevices(
      List<DirectDeviceStatus> devices) async {
    final identity = store.runtime.identity;
    if (!identity.isHost) return;
    final hostDeviceId = store.sync.deviceId.trim();
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

      final peerDeviceName = device.deviceName.trim();
      final before = settings.hostRegistry[clientDeviceId];
      if (before != null) {
        final registry = <String, HostRegistryDevice>{...settings.hostRegistry};
        final updated = before.copyWith(
          deviceName:
              peerDeviceName.isNotEmpty ? peerDeviceName : before.deviceName,
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

      if (device.hostDeviceId.trim() != hostDeviceId) continue;
      settings = settings.withDirectPairedHostRegistryDevice(
        hostDeviceId: hostDeviceId,
        clientDeviceId: clientDeviceId,
        deviceToken: '',
        deviceName: peerDeviceName,
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
    final shouldResume = suspended;
    if (shouldResume) {
      await SyncDeviceAccessStore.resume(deviceId);
    } else {
      await SyncDeviceAccessStore.suspend(deviceId);
    }

    final controlPlaneSettings = VpsControlPlaneSettings.load();
    if (controlPlaneSettings.isConfigured) {
      await _controlPlaneService.setDeviceSuspended(
        controlPlaneSettings,
        deviceId,
        suspended: !shouldResume,
      );
    }

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
      List<DirectDeviceStatus> peerDevices) async {
    return;
  }

  Future<void> _deleteDevice(String deviceId) async {
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

    final controlPlaneSettings = VpsControlPlaneSettings.load();
    if (controlPlaneSettings.isConfigured) {
      await _controlPlaneService.revokeDevice(controlPlaneSettings, deviceId);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr.text('sync_wipe_pending'))));
    await _refresh();
  }

  Future<void> _permanentDeleteDevice(String deviceId) async {
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
    final controlPlaneSettings = VpsControlPlaneSettings.load();
    if (controlPlaneSettings.isConfigured) {
      await _controlPlaneService.deleteDeviceRecord(
          controlPlaneSettings, deviceId);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('sync_device_permanently_deleted'))));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final isHost = widget.forceHostView || store.runtime.identity.isHost;
    final lanSettings = LanSyncSettings.load();
    final controlPlaneSettings = VpsControlPlaneSettings.load();
    final peers = SyncDeviceStateStore.loadPeerStates();
    final peerById = <String, HostPeerSyncState>{
      for (final peer in peers) peer.deviceId: peer
    };
    final selfState = SyncDeviceStateStore.load(store.runtime.identity);

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
                store: store,
                peerDevices:
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
              store: store,
              lanSettings: lanSettings,
              controlPlaneSettings: controlPlaneSettings,
              onRefresh: _refresh,
            ),
          const SizedBox(height: 12),
          const _SyncTraceDiagnosticsPanel(),
        ],
      ),
    );
  }
}

class _DirectMonitoringSnapshot {
  const _DirectMonitoringSnapshot({
    required this.devices,
    this.limit,
  });

  final List<DirectDeviceStatus> devices;
  final DirectDeviceLimitStatus? limit;
}

DirectDeviceLimitStatus? _localClientDeviceLimitStatus(
  ApplicationSession store,
  LanSyncSettings settings, {
  String excludeDeviceId = '',
}) {
  final allowed = AccountAuthCache.load()?.devicesLimit;
  if (allowed == null) return null;
  final hostDeviceId = store.sync.deviceId.trim();
  final excluded = excludeDeviceId.trim();
  final linked = settings.hostRegistry.values.where((device) {
    final id = device.clientDeviceId.trim();
    if (id.isEmpty || id == hostDeviceId || id == excluded) return false;
    return device.isActive;
  }).length;
  final normalizedAllowed = allowed < 0 ? 0 : allowed;
  return DirectDeviceLimitStatus(
    allowed: normalizedAllowed,
    linked: linked,
    available: (normalizedAllowed - linked).clamp(0, 1 << 30).toInt(),
    limitReached: linked >= normalizedAllowed,
  );
}

class _SyncStatusView {
  const _SyncStatusView(
      {required this.label, required this.color, required this.icon});

  final String label;
  final Color color;
  final IconData icon;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(
      {required this.label, required this.color, required this.icon});

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: 0.45)),
    );
  }
}

String _deviceLabel(
  BuildContext context,
  String deviceId, {
  HostRegistryDevice? registryDevice,
  DirectDeviceStatus? peerDevice,
}) {
  final name = registryDevice?.deviceName.trim().isNotEmpty == true
      ? registryDevice!.deviceName.trim()
      : peerDevice?.deviceName.trim().isNotEmpty == true
          ? peerDevice!.deviceName.trim()
          : '';
  if (name.isNotEmpty) return name;
  final id = deviceId.trim();
  if (id.isEmpty) return AppLocalizations.of(context).text('unknown_device');
  if (id.length <= 8) return id;
  final prefix = id.substring(0, 4);
  final suffix = id.substring(id.length - 4);
  return '$prefix...$suffix';
}

String _formatDateTime(BuildContext context, DateTime? value) {
  if (value == null) return AppLocalizations.of(context).text('never');
  return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
}

String _transportLabel(BuildContext context, String transport) {
  final tr = AppLocalizations.of(context);
  switch (transport.trim().toLowerCase()) {
    case 'lan':
      return tr.text('lan');
    case 'direct':
      return tr.text('connection_direct');
    case 'local':
      return tr.text('connection_local');
    default:
      return transport.trim().isEmpty ? tr.text('unknown') : transport;
  }
}

_SyncStatusView _connectionStatusForHostPeer(
  BuildContext context, {
  required String deviceId,
  required HostPeerSyncState? state,
  required DirectDeviceStatus? peerDevice,
  required bool suspended,
  bool wipePending = false,
}) {
  final tr = AppLocalizations.of(context);
  final live = SyncDeviceStateStore.livePeerStatus(deviceId);
  if (live?.online == true && !suspended && peerDevice?.revoked != true) {
    return _SyncStatusView(
        label: tr.text('connection_state_online'),
        color: Colors.green,
        icon: Icons.wifi_tethering_outlined);
  }
  return _SyncStatusView(
      label: tr.text('connection_state_offline'),
      color: Theme.of(context).colorScheme.error,
      icon: Icons.wifi_off_outlined);
}

_SyncStatusView _connectionStatusForClient(
  BuildContext context, {
  required SyncDeviceState state,
  required LanSyncSettings lanSettings,
  required VpsControlPlaneSettings controlPlaneSettings,
}) {
  final tr = AppLocalizations.of(context);
  final active = state.activeTransport.trim().toLowerCase();
  final configured = active == 'direct'
      ? controlPlaneSettings.isConfigured
      : active == 'lan'
          ? lanSettings.setupComplete
          : false;
  final lastSeen = state.lastSeenAt;
  final recentlySeen = lastSeen != null &&
      DateTime.now().toUtc().difference(lastSeen.toUtc()) <=
          const Duration(seconds: 90);
  if (recentlySeen) {
    return _SyncStatusView(
        label: tr.text('connection_state_active'),
        color: Colors.green,
        icon: Icons.wifi_tethering_outlined);
  }
  if (configured) {
    return _SyncStatusView(
        label: tr.text('connection_state_pending'),
        color: Colors.orange,
        icon: Icons.wifi_off_outlined);
  }
  return _SyncStatusView(
      label: tr.text('connection_state_not_configured'),
      color: Theme.of(context).colorScheme.error,
      icon: Icons.block_outlined);
}

String _activeTransportForHostPeer(
  BuildContext context, {
  required bool lanAuthorized,
  required DirectDeviceStatus? peerDevice,
  required HostPeerSyncState? state,
}) {
  final tr = AppLocalizations.of(context);
  final peerTransport =
      (peerDevice?.activeTransport ?? peerDevice?.transport ?? '')
          .trim()
          .toLowerCase();
  final lastTransport =
      (state?.lastSyncTransport ?? peerDevice?.lastSyncTransport ?? '')
          .trim()
          .toLowerCase();
  if (lastTransport == 'direct' ||
      (peerDevice?.lastSyncTransport ?? '').trim().toLowerCase() == 'direct' ||
      peerTransport == 'direct' ||
      (peerDevice?.activeTransport ?? '').trim().toLowerCase() == 'direct') {
    return _transportLabel(context, 'direct');
  }
  if (lanAuthorized && peerDevice != null) {
    final active = peerTransport.isNotEmpty ? peerTransport : lastTransport;
    if (active == 'lan' || active == 'direct') {
      return _transportLabel(context, active);
    }
    return '${tr.text('lan')} + ${tr.text('connection_direct')}';
  }
  if (peerDevice != null) {
    return _transportLabel(
        context, peerTransport.isNotEmpty ? peerTransport : 'direct');
  }
  if (lanAuthorized) return tr.text('lan');
  if (lastTransport.isNotEmpty) return _transportLabel(context, lastTransport);
  return tr.text('unknown');
}

String _pendingChangesForHostPeer(
  BuildContext context, {
  required ApplicationSession store,
  required String deviceId,
  required HostPeerSyncState? state,
  required DirectDeviceStatus? peerDevice,
}) {
  final ackSequence = _hostPeerAckSequence(state, peerDevice);
  final ackCursor = state?.lastAckCursor ??
      peerDevice?.lastAckCursor ??
      peerDevice?.lastAckAt;
  var count = 0;
  for (final change in store.sync.changes) {
    if (change.deviceId == deviceId) continue;
    final pending = ackSequence > 0 && change.sequence > 0
        ? change.sequence > ackSequence
        : ackCursor == null || change.createdAt.isAfter(ackCursor);
    if (pending) count++;
  }
  return '$count';
}

int _pendingChangesCountForHostPeer({
  required ApplicationSession store,
  required String deviceId,
  required HostPeerSyncState? state,
  required DirectDeviceStatus? peerDevice,
}) {
  final ackSequence = _hostPeerAckSequence(state, peerDevice);
  final ackCursor = state?.lastAckCursor ??
      peerDevice?.lastAckCursor ??
      peerDevice?.lastAckAt;
  var count = 0;
  for (final change in store.sync.changes) {
    if (change.deviceId == deviceId) continue;
    final pending = ackSequence > 0 && change.sequence > 0
        ? change.sequence > ackSequence
        : ackCursor == null || change.createdAt.isAfter(ackCursor);
    if (pending) count++;
  }
  return count;
}

class _SyncTraceDiagnosticsPanel extends StatefulWidget {
  const _SyncTraceDiagnosticsPanel();

  @override
  State<_SyncTraceDiagnosticsPanel> createState() =>
      _SyncTraceDiagnosticsPanelState();
}

class _SyncTraceDiagnosticsPanelState
    extends State<_SyncTraceDiagnosticsPanel> {
  bool _showLog = false;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!_showLog) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => setState(() => _showLog = true),
          icon: const Icon(Icons.terminal_outlined),
          label: Text(tr.text('show_log')),
        ),
      );
    }

    final theme = Theme.of(context);
    return ValueListenableBuilder<List<String>>(
      valueListenable: SyncDiagnosticsLog.lines,
      builder: (context, lines, _) {
        final trace = lines
            .where((line) => line.contains('[SYNC_TRACE]'))
            .toList(growable: false);
        final text = trace.join('\n');
        return Card(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.route_outlined),
                    const SizedBox(width: 8),
                    Expanded(child: Text(tr.text('sync_trace_diagnostics'))),
                    IconButton(
                      tooltip: tr.text('hide_log'),
                      onPressed: () => setState(() => _showLog = false),
                      icon: const Icon(Icons.visibility_off_outlined),
                    ),
                    IconButton(
                      tooltip: tr.text('copy_sync_trace'),
                      onPressed: text.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(
                                  ClipboardData(text: text));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text(tr.text('sync_trace_copied'))),
                                );
                              }
                            },
                      icon: const Icon(Icons.copy_outlined),
                    ),
                    IconButton(
                      tooltip: tr.text('clear_sync_trace'),
                      onPressed: text.isEmpty
                          ? null
                          : SyncDiagnosticsLog.clearSyncTrace,
                      icon: const Icon(Icons.delete_sweep_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  text.isEmpty ? 'No sync trace yet.' : text,
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
}

int _hostPeerAckSequence(
  HostPeerSyncState? state,
  DirectDeviceStatus? peerDevice,
) {
  final local = state?.lastAckSequence ?? 0;
  final direct = peerDevice?.lastAckSequence ?? 0;
  return local > direct ? local : direct;
}

DateTime? _latestSyncDate(DateTime? current, DateTime? candidate) {
  if (current == null) return candidate;
  if (candidate == null) return current;
  return candidate.isAfter(current) ? candidate : current;
}

DateTime? _lastSuccessfulSyncForHostPeer({
  required HostPeerSyncState? state,
  required DirectDeviceStatus? peerDevice,
}) {
  DateTime? latest;
  latest = _latestSyncDate(latest, state?.lastAckCursor);
  latest = _latestSyncDate(latest, state?.lastAppliedHostCursor);
  latest = _latestSyncDate(latest, peerDevice?.lastAckAt);
  latest = _latestSyncDate(latest, peerDevice?.lastAckCursor);
  return latest;
}

DateTime? _lastSuccessfulSyncForClient(SyncDeviceState state) {
  return state.lastAckCursor ?? state.lastAppliedHostCursor;
}

_SyncStatusView _syncStatusForHostPeer(
  BuildContext context,
  HostPeerSyncState? state, {
  required int pendingCount,
  required bool lanAuthorized,
  required DirectDeviceStatus? peerDevice,
  required bool suspended,
  bool wipePending = false,
}) {
  final tr = AppLocalizations.of(context);
  final hasAck = _hostPeerAckSequence(state, peerDevice) > 0 ||
      state?.lastAckCursor != null ||
      peerDevice?.lastAckCursor != null ||
      peerDevice?.lastAckAt != null;
  if (pendingCount == 0 && hasAck) {
    return _SyncStatusView(
        label: tr.text('synced'),
        color: Colors.green,
        icon: Icons.check_circle_outline);
  }
  return _SyncStatusView(
      label: tr.text('sync_pending'),
      color: Colors.orange,
      icon: Icons.schedule_outlined);
}
