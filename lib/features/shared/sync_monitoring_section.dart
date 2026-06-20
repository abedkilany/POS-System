import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/account_auth_service.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/services/lan_sync_service.dart';
import '../../core/sync_unified/sync_device_state.dart';
import '../../data/app_store.dart';

class SyncMonitoringSection extends StatefulWidget {
  const SyncMonitoringSection({
    super.key,
    required this.store,
  });

  final AppStore store;

  @override
  State<SyncMonitoringSection> createState() => _SyncMonitoringSectionState();
}

class _SyncMonitoringSectionState extends State<SyncMonitoringSection> {
  Future<_CloudMonitoringSnapshot>? _cloudMonitoringFuture;

  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _refreshCloudDevices();
  }

  @override
  void didUpdateWidget(covariant SyncMonitoringSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _refreshCloudDevices();
    }
  }

  void _refreshCloudDevices() {
    final cloudSettings = CloudSyncSettings.load();
    if (store.appIdentity.isHost && cloudSettings.isConfigured) {
      _cloudMonitoringFuture = _loadAndAdoptCloudDevices(cloudSettings)
          .catchError((_) => const _CloudMonitoringSnapshot(
                devices: <CloudDeviceStatus>[],
              ));
    } else {
      _cloudMonitoringFuture = Future<_CloudMonitoringSnapshot>.value(
        _CloudMonitoringSnapshot(
          devices: const <CloudDeviceStatus>[],
          limit: store.appIdentity.isHost
              ? _localClientDeviceLimitStatus(
                  store,
                  LanSyncSettings.load(),
                )
              : null,
        ),
      );
    }
  }

  Future<_CloudMonitoringSnapshot> _loadAndAdoptCloudDevices(
      CloudSyncSettings cloudSettings) async {
    final service = CloudSyncService(store);
    var result = await service.listDevicesWithLimit(cloudSettings);
    var devices = result.devices;
    final repaired =
        await _repairLegacyCloudDeviceLinks(service, cloudSettings, devices);
    if (repaired) {
      result = await service.listDevicesWithLimit(cloudSettings);
      devices = result.devices;
    }
    await _adoptCloudRegistryDevices(devices);
    return _CloudMonitoringSnapshot(
      devices: devices,
      limit: result.limit ??
          _localClientDeviceLimitStatus(store, LanSyncSettings.load()),
    );
  }

  Future<bool> _repairLegacyCloudDeviceLinks(
    CloudSyncService service,
    CloudSyncSettings cloudSettings,
    List<CloudDeviceStatus> devices,
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
    final result = await service.repairLegacyCloudDeviceLinks(
      cloudSettings,
      clientDeviceIds: repairIds,
    );
    return result.ok;
  }

  Future<void> _adoptCloudRegistryDevices(
      List<CloudDeviceStatus> devices) async {
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

      final cloudDeviceName = device.deviceName.trim();
      final before = settings.hostRegistry[clientDeviceId];
      if (before != null) {
        final registry = <String, HostRegistryDevice>{...settings.hostRegistry};
        final updated = before.copyWith(
          deviceName:
              cloudDeviceName.isNotEmpty ? cloudDeviceName : before.deviceName,
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
      settings = settings.withCloudPairedHostRegistryDevice(
        hostDeviceId: hostDeviceId,
        clientDeviceId: clientDeviceId,
        deviceToken: '',
        deviceName: cloudDeviceName,
        pairedAt: device.lastSeenAt ?? DateTime.now(),
      );
      changed = true;
    }

    if (changed) await settings.save();
  }

  Future<void> _refresh() async {
    setState(_refreshCloudDevices);
    final snapshot = await (_cloudMonitoringFuture ??
        Future<_CloudMonitoringSnapshot>.value(
            const _CloudMonitoringSnapshot(devices: <CloudDeviceStatus>[])));
    await _finalizeCloudWipeAcknowledgements(snapshot.devices);
    if (mounted) setState(() {});
  }

  Future<void> _toggleSuspend(String deviceId, bool suspended) async {
    final shouldResume = suspended;
    if (shouldResume) {
      await SyncDeviceAccessStore.resume(deviceId);
    } else {
      await SyncDeviceAccessStore.suspend(deviceId);
    }

    final cloudSettings = CloudSyncSettings.load();
    if (cloudSettings.isConfigured) {
      await CloudSyncService(store).setDeviceSuspended(
        cloudSettings,
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

  Future<void> _finalizeCloudWipeAcknowledgements(
      List<CloudDeviceStatus> cloudDevices) async {
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

    final cloudSettings = CloudSyncSettings.load();
    if (cloudSettings.isConfigured) {
      await CloudSyncService(store).revokeDevice(cloudSettings, deviceId);
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
    final cloudSettings = CloudSyncSettings.load();
    if (cloudSettings.isConfigured) {
      await CloudSyncService(store).deleteDeviceRecord(cloudSettings, deviceId);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('sync_device_permanently_deleted'))));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final isHost = store.appIdentity.isHost;
    final lanSettings = LanSyncSettings.load();
    final cloudSettings = CloudSyncSettings.load();
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
            FutureBuilder<_CloudMonitoringSnapshot>(
              future: _cloudMonitoringFuture,
              builder: (context, snapshot) => _HostSyncMonitoringTable(
                store: store,
                cloudDevices:
                    snapshot.data?.devices ?? const <CloudDeviceStatus>[],
                deviceLimit: snapshot.data?.limit,
                peerStates: peerById,
                lanSettings: lanSettings,
                loadingCloudDevices:
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
              cloudSettings: cloudSettings,
              onRefresh: _refresh,
            ),
        ],
      ),
    );
  }
}

class _CloudMonitoringSnapshot {
  const _CloudMonitoringSnapshot({
    required this.devices,
    this.limit,
  });

  final List<CloudDeviceStatus> devices;
  final CloudDeviceLimitStatus? limit;
}

CloudDeviceLimitStatus? _localClientDeviceLimitStatus(
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
  return CloudDeviceLimitStatus(
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
  String deviceId, {
  HostRegistryDevice? registryDevice,
  CloudDeviceStatus? cloudDevice,
}) {
  final name = registryDevice?.deviceName.trim().isNotEmpty == true
      ? registryDevice!.deviceName.trim()
      : cloudDevice?.deviceName.trim().isNotEmpty == true
          ? cloudDevice!.deviceName.trim()
          : '';
  if (name.isNotEmpty) return name;
  final id = deviceId.trim();
  if (id.isEmpty) return 'Unknown device';
  if (id.length <= 8) return id;
  return '${id.substring(0, 4)}...${id.substring(id.length - 4)}';
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
    case 'cloud':
      return tr.text('connection_cloud');
    case 'local':
      return tr.text('connection_local');
    default:
      return transport.trim().isEmpty ? tr.text('unknown') : transport;
  }
}

_SyncStatusView _connectionStatusForHostPeer(
  BuildContext context, {
  required HostPeerSyncState? state,
  required CloudDeviceStatus? cloudDevice,
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
  if (suspended || cloudDevice?.revoked == true) {
    return _SyncStatusView(
        label: tr.text('connection_state_pending'),
        color: Theme.of(context).colorScheme.error,
        icon: Icons.cloud_off_outlined);
  }
  final lastSeen = _lastSeenForHostPeer(state: state, cloudDevice: cloudDevice);
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
  required CloudSyncSettings cloudSettings,
}) {
  final tr = AppLocalizations.of(context);
  final active = state.activeTransport.trim().toLowerCase();
  final configured = active == 'cloud'
      ? cloudSettings.isConfigured
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
  required CloudDeviceStatus? cloudDevice,
  required HostPeerSyncState? state,
}) {
  final tr = AppLocalizations.of(context);
  final cloudTransport =
      (cloudDevice?.activeTransport ?? cloudDevice?.transport ?? '')
          .trim()
          .toLowerCase();
  final lastTransport =
      (state?.lastSyncTransport ?? cloudDevice?.lastSyncTransport ?? '')
          .trim()
          .toLowerCase();
  if (lanAuthorized && cloudDevice != null) {
    final active = cloudTransport.isNotEmpty ? cloudTransport : lastTransport;
    if (active == 'lan' || active == 'cloud') {
      return _transportLabel(context, active);
    }
    return '${tr.text('lan')} + ${tr.text('connection_cloud')}';
  }
  if (cloudDevice != null) {
    return _transportLabel(
        context, cloudTransport.isNotEmpty ? cloudTransport : 'cloud');
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
  required CloudDeviceStatus? cloudDevice,
}) {
  final ackSequence =
      state?.lastAckSequence ?? cloudDevice?.lastAckSequence ?? 0;
  final ackCursor = state?.lastAckCursor ??
      cloudDevice?.lastAckCursor ??
      cloudDevice?.lastAckAt;
  var count = 0;
  for (final change in store.syncChanges) {
    if (change.deviceId == deviceId) continue;
    final sequencePending = change.sequence > ackSequence;
    final cursorPending =
        ackCursor == null || change.createdAt.isAfter(ackCursor);
    if (sequencePending || cursorPending) count++;
  }
  return '$count';
}

DateTime? _lastSuccessfulSyncForHostPeer({
  required HostPeerSyncState? state,
  required CloudDeviceStatus? cloudDevice,
}) {
  return state?.lastAckCursor ??
      state?.lastAppliedHostCursor ??
      cloudDevice?.lastAckAt ??
      cloudDevice?.lastAckCursor;
}

DateTime? _lastSeenForHostPeer({
  required HostPeerSyncState? state,
  required CloudDeviceStatus? cloudDevice,
}) {
  return cloudDevice?.lastSeenAt ?? state?.updatedAt;
}

DateTime? _lastSuccessfulSyncForClient(SyncDeviceState state) {
  return state.lastAckCursor ?? state.lastAppliedHostCursor;
}

_SyncStatusView _syncStatusForHostPeer(
  BuildContext context,
  HostPeerSyncState? state, {
  required bool lanAuthorized,
  required CloudDeviceStatus? cloudDevice,
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
  if (cloudDevice?.revoked == true) {
    return _SyncStatusView(
        label: tr.text('revoked'),
        color: Theme.of(context).colorScheme.error,
        icon: Icons.block_outlined);
  }
  if (!lanAuthorized && cloudDevice == null) {
    return _SyncStatusView(
        label: tr.text('connection_state_not_configured'),
        color: Theme.of(context).colorScheme.outline,
        icon: Icons.link_off_outlined);
  }
  final lastSync =
      _lastSuccessfulSyncForHostPeer(state: state, cloudDevice: cloudDevice);
  if (lanAuthorized && cloudDevice == null) {
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
    required this.cloudDevices,
    required this.deviceLimit,
    required this.peerStates,
    required this.lanSettings,
    required this.loadingCloudDevices,
    required this.onRefresh,
    required this.onToggleSuspend,
    required this.onDelete,
    required this.onPermanentDelete,
  });

  final AppStore store;
  final List<CloudDeviceStatus> cloudDevices;
  final CloudDeviceLimitStatus? deviceLimit;
  final Map<String, HostPeerSyncState> peerStates;
  final LanSyncSettings lanSettings;
  final bool loadingCloudDevices;
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
    final cloudById = <String, CloudDeviceStatus>{
      for (final device in widget.cloudDevices)
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
    final deviceIds = registryById.keys.toSet()
      ..removeWhere((id) => deleted.contains(id));
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
      cloudDevices: widget.cloudDevices,
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
        if (widget.loadingCloudDevices)
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
                      cloudDevice: cloudById[deviceId],
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
                        cloudDevice: cloudById[deviceId],
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
  required CloudDeviceStatus? cloudDevice,
  required bool suspended,
  required bool wipePending,
  required VoidCallback onToggleSuspend,
  required VoidCallback onDelete,
  required VoidCallback onPermanentDelete,
}) {
  final tr = AppLocalizations.of(context);
  final connection = _connectionStatusForHostPeer(context,
      state: state,
      cloudDevice: cloudDevice,
      suspended: suspended,
      wipePending: wipePending);
  final status = _syncStatusForHostPeer(context, state,
      lanAuthorized: lanAuthorized,
      cloudDevice: cloudDevice,
      suspended: suspended,
      wipePending: wipePending);
  return DataRow(
    cells: [
      DataCell(Text(_deviceLabel(deviceId,
          registryDevice: registryDevice, cloudDevice: cloudDevice))),
      DataCell(Text(_activeTransportForHostPeer(context,
          lanAuthorized: lanAuthorized,
          cloudDevice: cloudDevice,
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
              state: state, cloudDevice: cloudDevice)))),
      DataCell(Text(_pendingChangesForHostPeer(context,
          store: store,
          deviceId: deviceId,
          state: state,
          cloudDevice: cloudDevice))),
      DataCell(Text(
          '${state?.lastAckSequence ?? cloudDevice?.lastAckSequence ?? 0}')),
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
    required this.cloudDevices,
    required this.peerStates,
  });

  final AppStore store;
  final LanSyncSettings lanSettings;
  final List<CloudDeviceStatus> cloudDevices;
  final Map<String, HostPeerSyncState> peerStates;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final lastAckSequence = <int>[
      for (final peer in peerStates.values) peer.lastAckSequence,
      for (final device in cloudDevices) device.lastAckSequence,
    ].fold<int>(0, (latest, value) => value > latest ? value : latest);
    final identity = store.appIdentity;
    final activeTransport = identity.activeSyncTransportNormalized;
    final lanReady = activeTransport == 'lan' &&
        lanSettings.setupComplete &&
        lanSettings.autoSyncEnabled;
    final cloudReady = activeTransport == 'cloud' && identity.isCloudEnabled;

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
              if (cloudReady)
                _StatusChip(
                    label:
                        '${tr.text('connection_cloud')}: ${tr.text('connection_state_active')}',
                    color: Colors.blue,
                    icon: Icons.cloud_done_outlined),
              if (!lanReady && !cloudReady)
                _StatusChip(
                    label: tr.text('connection_state_not_configured'),
                    color: Theme.of(context).colorScheme.error,
                    icon: Icons.link_off_outlined),
            ],
          ),
          const SizedBox(height: 12),
          _Line(title: tr.text('device_id'), value: identity.deviceId),
          _Line(title: tr.text('last_ack_sequence'), value: '$lastAckSequence'),
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
    required this.cloudDevice,
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
  final CloudDeviceStatus? cloudDevice;
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
        cloudDevice: cloudDevice,
        suspended: suspended,
        wipePending: wipePending);
    final status = _syncStatusForHostPeer(context, state,
        lanAuthorized: lanAuthorized,
        cloudDevice: cloudDevice,
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
                      _deviceLabel(deviceId,
                          registryDevice: registryDevice,
                          cloudDevice: cloudDevice),
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
                  cloudDevice: cloudDevice,
                  state: state)),
          _Line(title: tr.text('connection_status'), value: connection.label),
          _Line(title: tr.text('sync_status'), value: status.label),
          _Line(
              title: tr.text('last_successful_sync'),
              value: _formatDateTime(
                  context,
                  _lastSuccessfulSyncForHostPeer(
                      state: state, cloudDevice: cloudDevice))),
          _Line(
              title: tr.text('pending_changes'),
              value: _pendingChangesForHostPeer(context,
                  store: store,
                  deviceId: deviceId,
                  state: state,
                  cloudDevice: cloudDevice)),
          _Line(
              title: tr.text('last_ack_sequence'),
              value:
                  '${state?.lastAckSequence ?? cloudDevice?.lastAckSequence ?? 0}'),
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
    required this.cloudSettings,
    required this.onRefresh,
  });

  final SyncDeviceState state;
  final AppStore store;
  final LanSyncSettings lanSettings;
  final CloudSyncSettings cloudSettings;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final connection = _connectionStatusForClient(context,
        state: state, lanSettings: lanSettings, cloudSettings: cloudSettings);
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
  CloudDeviceLimitStatus? limit,
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
