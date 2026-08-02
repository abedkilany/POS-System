part of 'settings_page.dart';

enum _PairingCodeVisualStatus { active, expired, consumed, invalid, disabled }

class _OperationProgress {
  const _OperationProgress(this.value, this.label);

  final double value;
  final String label;
}

class _ScannedPairingPayload {
  const _ScannedPairingPayload({
    required this.raw,
    required this.code,
    required this.transport,
    required this.host,
    required this.port,
    required this.apiBaseUrl,
    required this.storeId,
    required this.branchId,
    required this.hostDeviceId,
    required this.controlPlaneTenantId,
  });

  final String raw;
  final String code;
  final String transport;
  final String host;
  final String port;
  final String apiBaseUrl;
  final String storeId;
  final String branchId;
  final String hostDeviceId;
  final String controlPlaneTenantId;
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
  DirectDeviceStatus? directDevice,
}) {
  final name = registryDevice?.deviceName.trim().isNotEmpty == true
      ? registryDevice!.deviceName.trim()
      : directDevice?.deviceName.trim().isNotEmpty == true
          ? directDevice!.deviceName.trim()
          : '';
  if (name.isNotEmpty) return name;
  final id = deviceId.trim();
  if (id.isEmpty) return AppLocalizations.of(context).text('unknown_device');
  if (id.length <= 8) return id;
  final prefix = id.substring(0, 4);
  final suffix = id.substring(id.length - 4);
  return '$prefix…$suffix';
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
  required DirectDeviceStatus? directDevice,
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
  if (suspended || directDevice?.revoked == true) {
    return _SyncStatusView(
        label: tr.text('connection_state_pending'),
        color: Theme.of(context).colorScheme.error,
        icon: Icons.sync_disabled);
  }
  final lastSeen = _lastSeenForHostPeer(state: state, directDevice: directDevice);
  // Direct `online` is a sticky database flag and is not a live connection source.
  // Treat Direct devices as online only when their heartbeat/lastSeen is fresh.
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
  required VpsControlPlaneSettings directSettings,
}) {
  final tr = AppLocalizations.of(context);
  final active = state.activeTransport.trim().toLowerCase();
  final configured = active == 'direct'
      ? directSettings.isConfigured
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
  required DirectDeviceStatus? directDevice,
  required HostPeerSyncState? state,
}) {
  final tr = AppLocalizations.of(context);
  final directTransport =
      (directDevice?.activeTransport ?? directDevice?.transport ?? '')
          .trim()
          .toLowerCase();
  final lastTransport =
      (state?.lastSyncTransport ?? directDevice?.lastSyncTransport ?? '')
          .trim()
          .toLowerCase();
  if (lanAuthorized && directDevice != null) {
    final active = directTransport.isNotEmpty ? directTransport : lastTransport;
    if (active == 'lan' || active == 'direct') {
      return _transportLabel(context, active);
    }
    return '${tr.text('lan')} + ${tr.text('direct')}';
  }
  if (directDevice != null) {
    return _transportLabel(
        context, directTransport.isNotEmpty ? directTransport : 'direct');
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
  required DirectDeviceStatus? directDevice,
}) {
  final ackSequence = _hostPeerAckSequence(state, directDevice);
  final ackCursor = state?.lastAckCursor ??
      directDevice?.lastAckCursor ??
      directDevice?.lastAckAt;
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

int _hostPeerAckSequence(
  HostPeerSyncState? state,
  DirectDeviceStatus? directDevice,
) {
  final local = state?.lastAckSequence ?? 0;
  final direct = directDevice?.lastAckSequence ?? 0;
  return local > direct ? local : direct;
}

DateTime? _latestSyncDate(DateTime? current, DateTime? candidate) {
  if (current == null) return candidate;
  if (candidate == null) return current;
  return candidate.isAfter(current) ? candidate : current;
}

DateTime? _lastSuccessfulSyncForHostPeer({
  required HostPeerSyncState? state,
  required DirectDeviceStatus? directDevice,
}) {
  DateTime? latest;
  latest = _latestSyncDate(latest, state?.lastAckCursor);
  latest = _latestSyncDate(latest, state?.lastAppliedHostCursor);
  latest = _latestSyncDate(latest, directDevice?.lastAckAt);
  latest = _latestSyncDate(latest, directDevice?.lastAckCursor);
  if (latest == null && _hostPeerAckSequence(state, directDevice) > 0) {
    latest = _latestSyncDate(state?.updatedAt, directDevice?.lastSeenAt);
  }
  return latest;
}

DateTime? _lastSeenForHostPeer({
  required HostPeerSyncState? state,
  required DirectDeviceStatus? directDevice,
}) {
  return directDevice?.lastSeenAt ?? state?.updatedAt;
}

DateTime? _lastSuccessfulSyncForClient(SyncDeviceState state) {
  return state.lastAckCursor ?? state.lastAppliedHostCursor;
}

_SyncStatusView _syncStatusForHostPeer(
  BuildContext context,
  HostPeerSyncState? state, {
  required bool lanAuthorized,
  required DirectDeviceStatus? directDevice,
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
  if (directDevice?.revoked == true) {
    return _SyncStatusView(
        label: tr.text('revoked'),
        color: Theme.of(context).colorScheme.error,
        icon: Icons.block_outlined);
  }
  if (!lanAuthorized && directDevice == null) {
    return _SyncStatusView(
        label: tr.text('connection_state_not_configured'),
        color: Theme.of(context).colorScheme.outline,
        icon: Icons.link_off_outlined);
  }
  final lastSync =
      _lastSuccessfulSyncForHostPeer(state: state, directDevice: directDevice);
  if (lanAuthorized && directDevice == null) {
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
  // Keep Client Diagnostics consistent with the top connection/sync bar.
  // The top bar treats an existing ACK/applied cursor as Synced even when the
  // last successful sync is not recent; Diagnostics should not independently
  // downgrade it to stale just because time has passed.
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
