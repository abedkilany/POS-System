import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/account_auth_service.dart';
import '../../core/services/direct_control_plane_service.dart';
import '../../core/services/lan_sync_service.dart';
import '../../core/services/sync_diagnostics_log.dart';
import '../../core/sync_unified/sync_device_state.dart';
import '../../data/app_store.dart';

class SyncMonitoringSection extends StatefulWidget {
  const SyncMonitoringSection({
    super.key,
    required this.store,
    this.forceHostView = false,
    this.storeIdOverride,
    this.branchIdOverride,
  });

  final AppStore store;
  final bool forceHostView;
  final String? storeIdOverride;
  final String? branchIdOverride;

  @override
  State<SyncMonitoringSection> createState() => _SyncMonitoringSectionState();
}

class _SyncMonitoringSectionState extends State<SyncMonitoringSection> {
  Future<_DirectMonitoringSnapshot>? _directMonitoringFuture;

  AppStore get store => widget.store;
  DirectControlPlaneService get _controlPlaneService =>
      DirectControlPlaneService(store);

  @override
  void initState() {
    super.initState();
    _refreshDirectDevices();
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
      limit: store.appIdentity.isHost
          ? _localClientDeviceLimitStatus(store, lanSettings)
          : null,
    );
    final controlPlaneSettings = VpsControlPlaneSettings.load();
    final showHostView = widget.forceHostView || store.appIdentity.isHost;
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
    final identity = store.appIdentity;
    if (!identity.isHost) return false;
    final hostDeviceId = store.deviceId.trim();
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
    final identity = store.appIdentity;
    if (!identity.isHost) return;
    final hostDeviceId = store.deviceId.trim();
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
    final isHost = widget.forceHostView || store.appIdentity.isHost;
    final lanSettings = LanSyncSettings.load();
    final controlPlaneSettings = VpsControlPlaneSettings.load();
    final peers = SyncDeviceStateStore.loadPeerStates();
    final peerById = <String, HostPeerSyncState>{
      for (final peer in peers) peer.deviceId: peer
    };
    final selfState = SyncDeviceStateStore.load(store.appIdentity);

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
  AppStore store,
  LanSyncSettings settings, {
  String excludeDeviceId = '',
}) {
  final allowed = AccountAuthCache.load()?.devicesLimit;
  if (allowed == null) return null;
  final hostDeviceId = store.deviceId.trim();
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
  required HostPeerSyncState? state,
  required DirectDeviceStatus? peerDevice,
  required bool suspended,
  bool wipePending = false,
}) {
  final tr = AppLocalizations.of(context);
  if (wipePending) {
    return _SyncStatusView(
        label: tr.text('wipe_pending'),
        color: Theme.of(context).colorScheme.error,
        icon: Icons.delete_sweep_outlined);
  }
  if (suspended || peerDevice?.revoked == true) {
    return _SyncStatusView(
        label: tr.text('connection_state_pending'),
        color: Theme.of(context).colorScheme.error,
        icon: Icons.sync_disabled);
  }
  final lastSeen = _lastSeenForHostPeer(state: state, peerDevice: peerDevice);
  final recentlySeen = lastSeen != null &&
      DateTime.now().toUtc().difference(lastSeen.toUtc()) <=
          const Duration(seconds: 90);
  if (recentlySeen) {
    return _SyncStatusView(
        label: tr.text('connection_state_active'),
        color: Colors.green,
        icon: Icons.wifi_tethering_outlined);
  }
  if (lastSeen != null) {
    return _SyncStatusView(
        label: tr.text('connection_state_pending'),
        color: Colors.orange,
        icon: Icons.wifi_off_outlined);
  }
  return _SyncStatusView(
      label: tr.text('unknown'),
      color: Theme.of(context).colorScheme.outline,
      icon: Icons.help_outline);
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
  required AppStore store,
  required String deviceId,
  required HostPeerSyncState? state,
  required DirectDeviceStatus? peerDevice,
}) {
  final ackSequence = _hostPeerAckSequence(state, peerDevice);
  final ackCursor = state?.lastAckCursor ??
      peerDevice?.lastAckCursor ??
      peerDevice?.lastAckAt;
  var count = 0;
  for (final change in store.syncChanges) {
    if (change.deviceId == deviceId) continue;
    final pending = ackSequence > 0 && change.sequence > 0
        ? change.sequence > ackSequence
        : ackCursor == null || change.createdAt.isAfter(ackCursor);
    if (pending) count++;
  }
  return '$count';
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
    if (!_showLog) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => setState(() => _showLog = true),
          icon: const Icon(Icons.terminal_outlined),
          label: const Text('Show log'),
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
                    const Expanded(child: Text('Sync trace diagnostics')),
                    IconButton(
                      tooltip: 'Hide log',
                      onPressed: () => setState(() => _showLog = false),
                      icon: const Icon(Icons.visibility_off_outlined),
                    ),
                    IconButton(
                      tooltip: 'Copy sync trace',
                      onPressed: text.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(
                                  ClipboardData(text: text));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Sync trace copied')),
                                );
                              }
                            },
                      icon: const Icon(Icons.copy_outlined),
                    ),
                    IconButton(
                      tooltip: 'Clear sync trace',
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
  if (latest == null && _hostPeerAckSequence(state, peerDevice) > 0) {
    latest = _latestSyncDate(state?.updatedAt, peerDevice?.lastSeenAt);
  }
  return latest;
}

DateTime? _lastSeenForHostPeer({
  required HostPeerSyncState? state,
  required DirectDeviceStatus? peerDevice,
}) {
  return peerDevice?.lastSeenAt ?? state?.updatedAt;
}

DateTime? _lastSuccessfulSyncForClient(SyncDeviceState state) {
  return state.lastAckCursor ?? state.lastAppliedHostCursor;
}

_SyncStatusView _syncStatusForHostPeer(
  BuildContext context,
  HostPeerSyncState? state, {
  required bool lanAuthorized,
  required DirectDeviceStatus? peerDevice,
  required bool suspended,
  bool wipePending = false,
}) {
  final tr = AppLocalizations.of(context);
  if (wipePending) {
    return _SyncStatusView(
        label: tr.text('wipe_pending'),
        color: Theme.of(context).colorScheme.error,
        icon: Icons.delete_sweep_outlined);
  }
  if (suspended) {
    return _SyncStatusView(
        label: tr.text('suspended'),
        color: Colors.orange,
        icon: Icons.pause_circle_outline);
  }
  if (peerDevice?.revoked == true) {
    return _SyncStatusView(
        label: tr.text('revoked'),
        color: Theme.of(context).colorScheme.error,
        icon: Icons.block_outlined);
  }
  if (!lanAuthorized && peerDevice == null) {
    return _SyncStatusView(
        label: tr.text('connection_state_not_configured'),
        color: Theme.of(context).colorScheme.outline,
        icon: Icons.link_off_outlined);
  }
  final lastSync =
      _lastSuccessfulSyncForHostPeer(state: state, peerDevice: peerDevice);
  if (lanAuthorized && peerDevice == null) {
    return _SyncStatusView(
        label: tr.text('lan_host_running'),
        color: Colors.green,
        icon: Icons.dns_outlined);
  }
  if (lastSync == null) {
    return _SyncStatusView(
        label: tr.text('sync_pending'),
        color: Colors.orange,
        icon: Icons.schedule_outlined);
  }
  final now = DateTime.now().toUtc();
  final age = now.difference(lastSync.toUtc());
  if (age <= const Duration(minutes: 5)) {
    return _SyncStatusView(
        label: tr.text('synced'),
        color: Colors.green,
        icon: Icons.check_circle_outline);
  }
  if (age <= const Duration(hours: 1)) {
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

  final AppStore store;
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
            device.deviceId.trim() != widget.store.deviceId.trim() &&
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
  required AppStore store,
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
  final connection = _connectionStatusForHostPeer(context,
      state: state,
      peerDevice: peerDevice,
      suspended: suspended,
      wipePending: wipePending);
  final status = _syncStatusForHostPeer(context, state,
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

  final AppStore store;
  final LanSyncSettings lanSettings;
  final List<DirectDeviceStatus> peerDevices;
  final Map<String, HostPeerSyncState> peerStates;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final identity = store.appIdentity;
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
              value: '${store.latestStoredAuthoritativeSequence}'),
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

  final AppStore store;
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
    final connection = _connectionStatusForHostPeer(context,
        state: state,
        peerDevice: peerDevice,
        suspended: suspended,
        wipePending: wipePending);
    final status = _syncStatusForHostPeer(context, state,
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
  final AppStore store;
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
        pendingCount: store.activeClientPendingSyncCount);
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
        _Line(title: tr.text('device_id'), value: store.appIdentity.deviceId),
        _Line(
            title: tr.text('active_transport'),
            value: _transportLabel(
                context,
                state.activeTransport.isNotEmpty
                    ? state.activeTransport
                    : store.appIdentity.activeSyncTransport)),
        _Line(title: tr.text('connection_status'), value: connection.label),
        _Line(title: tr.text('sync_status'), value: status.label),
        _Line(
            title: tr.text('last_successful_sync'),
            value:
                _formatDateTime(context, _lastSuccessfulSyncForClient(state))),
        _Line(
            title: tr.text('pending_changes'),
            value: '${store.activeClientPendingSyncCount}'),
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
