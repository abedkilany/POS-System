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
    required this.cloudTenantId,
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
  final String cloudTenantId;
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
  return '${id.substring(0, 4)}…${id.substring(id.length - 4)}';
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
  // Cloud `online` is a sticky database flag and is not a live connection source.
  // Treat Cloud devices as online only when their heartbeat/lastSeen is fresh.
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
    return '${tr.text('lan')} + ${tr.text('cloud')}';
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
