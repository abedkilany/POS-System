part of 'app.dart';

class _NoAccessPage extends StatelessWidget {
  const _NoAccessPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 42),
                  const SizedBox(height: 12),
                  Text(
                    AppLocalizations.of(context).text('no_accessible_pages'),
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context).text('no_access_to_sections'),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _TransportState {
  checking,
  active,
  online,
  pending,
  provisioning,
  suspended,
  offline,
  error,
  disabled,
  notConfigured
}

class _TransportSnapshot {
  const _TransportSnapshot({
    required this.label,
    required this.state,
    required this.message,
    this.lastSeenAt,
    this.lastSuccessfulSyncAt,
  });

  final String label;
  final _TransportState state;
  final String message;
  final DateTime? lastSeenAt;
  final DateTime? lastSuccessfulSyncAt;
}

class _ConnectionStatusSnapshot {
  const _ConnectionStatusSnapshot({
    required this.roleLabel,
    required this.roleMessage,
    required this.lan,
    required this.direct,
    required this.syncHealth,
    required this.activeTransportLabel,
    required this.pendingChanges,
  });

  final String roleLabel;
  final String roleMessage;
  final _TransportSnapshot lan;
  final _TransportSnapshot direct;
  final _TransportSnapshot syncHealth;
  final String activeTransportLabel;
  final int pendingChanges;
}

class HostConnectionIndicator extends StatefulWidget {
  const HostConnectionIndicator(
      {super.key, required this.store, this.compact = false});

  final AppStore store;
  final bool compact;

  @override
  State<HostConnectionIndicator> createState() =>
      _HostConnectionIndicatorState();
}

class _HostConnectionIndicatorState extends State<HostConnectionIndicator> {
  Timer? _timer;
  bool _didStartRefreshLoop = false;
  _ConnectionStatusSnapshot _snapshot = const _ConnectionStatusSnapshot(
    roleLabel: '',
    roleMessage: '...',
    lan: _TransportSnapshot(
        label: 'LAN', state: _TransportState.checking, message: '...'),
    direct: _TransportSnapshot(
        label: 'Direct', state: _TransportState.checking, message: '...'),
    syncHealth: _TransportSnapshot(
        label: '', state: _TransportState.checking, message: '...'),
    activeTransportLabel: '',
    pendingChanges: 0,
  );

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didStartRefreshLoop) return;
    _didStartRefreshLoop = true;
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _t(String key) => AppLocalizations.of(context).text(key);
  String _rt(String message) =>
      localizeRuntimeMessage(message, AppLocalizations.of(context));

  String _roleLabel() {
    final identity = widget.store.runtime.identity;
    if (identity.isHost) return _t('connection_role_host');
    if (identity.isClient) return _t('connection_role_client');
    return _t('connection_role_local');
  }

  String _roleMessage() {
    final identity = widget.store.runtime.identity;
    if (identity.isHost) return _t('connection_role_host_desc');
    if (identity.isClient) return _t('connection_role_client_desc');
    return _t('connection_role_local_desc');
  }

  String _activeTransportLabel() {
    final identity = widget.store.runtime.identity;
    if (identity.isHost) {
      final lan =
          UnifiedSyncFactory.isLanSetupComplete ? _t('connection_lan') : '';
      final direct = 'Direct';
      final parts = [lan, direct]
          .where((part) => part.trim().isNotEmpty)
          .toList(growable: false);
      if (parts.isEmpty) return _t('local');
      return parts.join(' + ');
    }
    final active = identity.activeSyncTransportNormalized;
    if (active == 'lan') return _t('connection_lan');
    if (active == 'direct') return 'Direct';
    return _t('local');
  }

  bool _isActiveTransport(_TransportSnapshot snapshot) {
    final identity = widget.store.runtime.identity;
    if (identity.isHost) {
      if (snapshot.label == _t('connection_lan')) {
        return UnifiedSyncFactory.isLanSetupComplete;
      }
      if (snapshot.label == 'Direct') return true;
      return true;
    }
    final active = identity.activeSyncTransportNormalized;
    if (snapshot.label == _t('connection_lan')) return active == 'lan';
    if (snapshot.label == 'Direct') return active == 'direct';
    return true;
  }

  Future<_TransportSnapshot> _readLanStatus() async {
    if (kIsWeb) {
      return _TransportSnapshot(
        label: _t('connection_lan'),
        state: _TransportState.disabled,
        message: _t('connection_lan_web_disabled'),
      );
    }

    final identity = widget.store.runtime.identity;
    final settings = LanSyncSettings.load();
    final hasSavedLanSettings =
        settings.host.trim().isNotEmpty || settings.secret.trim().isNotEmpty;
    final lanEnabledForRole = identity.isHost
        ? settings.setupComplete && settings.isHost
        : identity.isClient &&
            identity.activeSyncTransportNormalized == 'lan' &&
            settings.setupComplete &&
            settings.isClient;

    if (!lanEnabledForRole) {
      return _TransportSnapshot(
        label: _t('connection_lan'),
        state: hasSavedLanSettings
            ? _TransportState.disabled
            : _TransportState.notConfigured,
        message: hasSavedLanSettings
            ? _t('connection_state_disabled')
            : _t('connection_lan_not_configured'),
      );
    }

    // A device can be the store Host, but LAN is only Active when the LAN
    // settings explicitly say the LAN host service is enabled/configured.
    if (identity.isHost && settings.isHost) {
      return _TransportSnapshot(
        label: _t('connection_lan'),
        state: _TransportState.active,
        message: _t('connection_lan_host_active'),
      );
    }

    try {
      final status =
          await UnifiedSyncFactory.lanEngine(widget.store, settings: settings)
              .getHostStatus();
      if (status.hostReachable) {
        return _TransportSnapshot(
          label: _t('connection_lan'),
          state: _TransportState.online,
          message: status.message.isEmpty
              ? _t('connection_lan_host_reachable')
              : _rt(status.message),
          lastSeenAt: status.lastSeenAt ?? DateTime.now(),
        );
      }
      return _TransportSnapshot(
        label: _t('connection_lan'),
        state: _TransportState.offline,
        message: status.message.isEmpty
            ? _t('connection_lan_host_offline')
            : _rt(status.message),
        lastSeenAt: status.lastSeenAt,
      );
    } catch (error) {
      return _TransportSnapshot(
        label: _t('connection_lan'),
        state: _TransportState.error,
        message: "${_t('connection_lan_check_failed')}: $error",
      );
    }
  }

  Future<_TransportSnapshot> _readDirectStatus() async {
    final tr = AppLocalizations.of(context);
    final identity = widget.store.runtime.identity;
    final settings = DirectSyncSettings.load();
    final directEnabledForRole = identity.isHost
        ? true
        : identity.isClient &&
            identity.activeSyncTransportNormalized == 'direct' &&
            settings.isConfigured;

    if (!directEnabledForRole) {
      return _TransportSnapshot(
        label: 'Direct',
        state: settings.isConfigured
            ? _TransportState.disabled
            : _TransportState.notConfigured,
        message: settings.isConfigured
            ? _t('connection_state_disabled')
            : _t('direct_not_configured_message'),
      );
    }

    try {
      final status =
          await UnifiedSyncFactory.directEngine(widget.store).getHostStatus();
      if (status.hostReachable) {
        return _TransportSnapshot(
          label: 'Direct',
          state: _TransportState.online,
          message: status.message.isEmpty
              ? _t('direct_host_reachable_message')
              : status.message,
          lastSeenAt: status.lastSeenAt ?? DateTime.now(),
        );
      }

      return _TransportSnapshot(
        label: 'Direct',
        state: _TransportState.offline,
        message: status.message.isEmpty
            ? _t('direct_host_not_reachable')
            : status.message,
        lastSeenAt: status.lastSeenAt,
      );
    } catch (error) {
      return _TransportSnapshot(
        label: 'Direct',
        state: _TransportState.error,
        message: tr.format('direct_connection_check_failed', {'error': error}),
      );
    }
  }

  _TransportSnapshot _readSyncHealthStatus() {
    final identity = widget.store.runtime.identity;
    final pending = widget.store.runtime.isSyncDataLoaded
        ? (identity.isClient
            ? widget.store.sync.activeClientPendingCount
            : widget.store.sync.pendingCount)
        : 0;
    final lastSuccessfulSync =
        SyncDeviceStateStore.lastSuccessfulSyncAt(identity);

    if (identity.isClient && widget.store.runtime.isSuspendedByHost) {
      return _TransportSnapshot(
        label: _t('connection_sync_health'),
        state: _TransportState.suspended,
        message: widget.store.runtime.suspendedByHostReason.trim().isEmpty
            ? _t('client_suspended_by_host_desc')
            : _rt(widget.store.runtime.suspendedByHostReason),
        lastSuccessfulSyncAt: lastSuccessfulSync,
      );
    }

    final lanSettings = LanSyncSettings.load();
    final directSettings = DirectSyncSettings.load();
    final hasSavedDirectSettings = directSettings.isConfigured;
    final lanEnabled = identity.isHost
        ? lanSettings.setupComplete && lanSettings.isHost
        : identity.isClient &&
            identity.activeSyncTransportNormalized == 'lan' &&
            lanSettings.setupComplete &&
            lanSettings.isClient;
    final directEnabled = identity.isHost
        ? true
        : identity.isClient &&
            identity.activeSyncTransportNormalized == 'direct' &&
            hasSavedDirectSettings;

    if (!lanEnabled && !directEnabled) {
      return _TransportSnapshot(
        label: _t('connection_sync_health'),
        state: _TransportState.disabled,
        message: _t('connection_state_disabled'),
        lastSuccessfulSyncAt: lastSuccessfulSync,
      );
    }

    if (pending > 0) {
      return _TransportSnapshot(
        label: _t('connection_sync_health'),
        state: _TransportState.pending,
        message: identity.isClient
            ? '${_t('sync_pending')} • $pending ${_t('connection_sync_pending_suffix')}'
            : '${_t('connection_sync_pending_prefix')} $pending ${_t('connection_sync_pending_suffix')}',
        lastSuccessfulSyncAt: lastSuccessfulSync,
      );
    }

    if (lastSuccessfulSync == null) {
      return _TransportSnapshot(
        label: _t('connection_sync_health'),
        state: _TransportState.notConfigured,
        message: _t('not_synced_yet'),
      );
    }

    return _TransportSnapshot(
      label: _t('connection_sync_health'),
      state: _TransportState.active,
      message: _t('synced'),
      lastSuccessfulSyncAt: lastSuccessfulSync,
    );
  }

  Future<void> _refresh() async {
    final checking = _ConnectionStatusSnapshot(
      roleLabel: _roleLabel(),
      roleMessage: _roleMessage(),
      lan: _TransportSnapshot(
          label: _t('connection_lan'),
          state: _TransportState.checking,
          message: _t('connection_lan_checking')),
      direct: _TransportSnapshot(
          label: _t('direct'),
          state: _TransportState.checking,
          message: _t('checking_direct_connection')),
      syncHealth: _TransportSnapshot(
          label: _t('connection_sync_health'),
          state: _TransportState.checking,
          message: _t('connection_sync_checking')),
      activeTransportLabel: _activeTransportLabel(),
      pendingChanges: widget.store.runtime.isSyncDataLoaded
          ? (widget.store.runtime.identity.isClient
              ? widget.store.sync.activeClientPendingCount
              : widget.store.sync.pendingCount)
          : 0,
    );
    if (mounted) setState(() => _snapshot = checking);

    final lan = await _readLanStatus();
    final direct = await _readDirectStatus();
    final syncHealth = _readSyncHealthStatus();
    if (!mounted) return;
    setState(() {
      _snapshot = _ConnectionStatusSnapshot(
        roleLabel: _roleLabel(),
        roleMessage: _roleMessage(),
        lan: lan,
        direct: direct,
        syncHealth: syncHealth,
        activeTransportLabel: _activeTransportLabel(),
        pendingChanges: widget.store.runtime.isSyncDataLoaded
            ? (widget.store.runtime.identity.isClient
                ? widget.store.sync.activeClientPendingCount
                : widget.store.sync.pendingCount)
            : 0,
      );
    });
  }

  Color _stateColor(BuildContext context, _TransportState state) {
    final theme = Theme.of(context);
    return switch (state) {
      _TransportState.active => Colors.green,
      _TransportState.online => Colors.green,
      _TransportState.pending => Colors.orange,
      _TransportState.provisioning => Colors.blue,
      _TransportState.suspended => Colors.orange,
      _TransportState.offline => theme.colorScheme.error,
      _TransportState.error => theme.colorScheme.error,
      _TransportState.checking => Colors.amber,
      _TransportState.disabled => Colors.grey,
      _TransportState.notConfigured => Colors.grey,
    };
  }

  String _stateText(_TransportState state) {
    return switch (state) {
      _TransportState.active => _t('connection_state_active'),
      _TransportState.online => _t('connection_state_active'),
      _TransportState.pending => _t('connection_state_pending'),
      _TransportState.provisioning => _t('connection_state_provisioning'),
      _TransportState.suspended => _t('suspended'),
      _TransportState.offline => _t('connection_state_pending'),
      _TransportState.error => _t('connection_state_error'),
      _TransportState.checking => _t('connection_state_checking'),
      _TransportState.disabled => _t('connection_state_disabled'),
      _TransportState.notConfigured => _t('connection_state_not_configured'),
    };
  }

  String _timeText(DateTime? value) {
    if (value == null) return _t('never');
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _lastSeenText(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    return ' • ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  bool _needsAttention(_TransportSnapshot snapshot) {
    return switch (snapshot.state) {
      _TransportState.offline ||
      _TransportState.error ||
      _TransportState.pending ||
      _TransportState.provisioning ||
      _TransportState.suspended ||
      _TransportState.checking =>
        true,
      _ => false,
    };
  }

  _TransportSnapshot get _activeConnectionSnapshot {
    final identity = widget.store.runtime.identity;
    if (identity.isHost) {
      final candidates = <_TransportSnapshot>[];
      if (UnifiedSyncFactory.isLanSetupComplete) candidates.add(_snapshot.lan);
      candidates.add(_snapshot.direct);
      if (candidates.isEmpty) return _snapshot.lan;
      if (candidates.any((item) => item.state == _TransportState.checking)) {
        return candidates
            .firstWhere((item) => item.state == _TransportState.checking);
      }
      if (candidates.any((item) =>
          item.state == _TransportState.online ||
          item.state == _TransportState.active)) {
        return candidates.firstWhere((item) =>
            item.state == _TransportState.online ||
            item.state == _TransportState.active);
      }
      return candidates.first;
    }
    final active = identity.activeSyncTransportNormalized;
    if (active == 'lan') return _snapshot.lan;
    if (active == 'direct') return _snapshot.direct;
    return _TransportSnapshot(
        label: _t('local'),
        state: _TransportState.disabled,
        message: _t('connection_role_local_desc'));
  }

  bool get _hasAttention {
    final activeConnection = _activeConnectionSnapshot;
    return _needsAttention(activeConnection) ||
        _needsAttention(_snapshot.syncHealth);
  }

  _TransportState get _summaryState {
    final activeConnection = _activeConnectionSnapshot;
    if (activeConnection.state == _TransportState.checking ||
        _snapshot.syncHealth.state == _TransportState.checking) {
      return _TransportState.checking;
    }
    if (_hasAttention) return _TransportState.error;
    return _TransportState.active;
  }

  String get _connectionSummaryLabel {
    final connection = _activeConnectionSnapshot;
    if (connection.state == _TransportState.online ||
        connection.state == _TransportState.active) {
      return _t('connection_state_active');
    }
    if (connection.state == _TransportState.disabled) {
      return _t('connection_state_disabled');
    }
    if (connection.state == _TransportState.notConfigured) {
      return _t('connection_state_not_configured');
    }
    return _stateText(connection.state);
  }

  String get _syncSummaryLabel {
    final sync = _snapshot.syncHealth;
    if (sync.state == _TransportState.active) return _t('synced');
    if (sync.state == _TransportState.suspended) return _t('suspended');
    if (sync.state == _TransportState.pending) {
      return widget.store.runtime.identity.isClient
          ? _t('sync_pending')
          : _t('connection_state_pending');
    }
    if (sync.state == _TransportState.notConfigured) {
      return _t('not_synced_yet');
    }
    return _stateText(sync.state);
  }

  String get _summaryLabel {
    if (_summaryState == _TransportState.checking) {
      return _t('connection_state_checking');
    }
    return '$_connectionSummaryLabel • $_syncSummaryLabel';
  }

  PopupMenuItem<void> _detailItem(BuildContext context, IconData icon,
      String title, _TransportSnapshot snapshot,
      {bool activeTransport = true}) {
    final theme = Theme.of(context);
    final color =
        activeTransport ? _stateColor(context, snapshot.state) : Colors.grey;
    final titleSuffix =
        activeTransport ? '' : ' (${_t('connection_state_disabled')})';
    return PopupMenuItem<void>(
      enabled: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$title$titleSuffix: ${_stateText(snapshot.state)}',
                    style: theme.textTheme.labelLarge),
                if (snapshot.message.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${snapshot.message}${_lastSeenText(snapshot.lastSeenAt)}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<void> _infoItem(
      BuildContext context, IconData icon, String title, String value) {
    final theme = Theme.of(context);
    return PopupMenuItem<void>(
      enabled: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: theme.colorScheme.primary, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lan = _snapshot.lan;
    final direct = _snapshot.direct;
    final syncHealth = _snapshot.syncHealth;
    final summaryColor = _stateColor(context, _summaryState);
    final tooltip = [
      _summaryLabel,
      _snapshot.roleLabel,
      '${_t('active_transport')}: ${_snapshot.activeTransportLabel}',
      '${_t('connection_status')}: $_connectionSummaryLabel',
      '${_t('sync_status')}: $_syncSummaryLabel',
      '${_t('pending_changes')}: ${_snapshot.pendingChanges}',
      '${_t('last_successful_sync')}: ${_timeText(syncHealth.lastSuccessfulSyncAt)}',
      "${_t('connection_lan')}: ${_stateText(lan.state)}${_lastSeenText(lan.lastSeenAt)} — ${lan.message}",
      "${_t('direct')}: ${_stateText(direct.state)}${_lastSeenText(direct.lastSeenAt)} — ${direct.message}",
    ].join('\n');

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: Tooltip(
        message: tooltip,
        child: PopupMenuButton<void>(
          tooltip: tooltip,
          constraints: BoxConstraints(
              minWidth: 280,
              maxWidth: VentioResponsive.modalMaxWidth(context, 390)),
          onOpened: _refresh,
          itemBuilder: (context) => [
            PopupMenuItem<void>(
              enabled: false,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.circle, color: summaryColor, size: 12),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_summaryLabel,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text(_snapshot.roleLabel,
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            _infoItem(context, Icons.swap_horiz_outlined,
                _t('active_transport'), _snapshot.activeTransportLabel),
            _infoItem(context, Icons.device_hub_outlined,
                _t('connection_status'), _connectionSummaryLabel),
            _infoItem(context, Icons.sync_outlined, _t('sync_status'),
                _syncSummaryLabel),
            _infoItem(context, Icons.pending_actions_outlined,
                _t('pending_changes'), _snapshot.pendingChanges.toString()),
            _infoItem(
                context,
                Icons.verified_outlined,
                _t('last_successful_sync'),
                _timeText(syncHealth.lastSuccessfulSyncAt)),
            const PopupMenuDivider(),
            _detailItem(context, Icons.lan_outlined, _t('connection_lan'), lan,
                activeTransport: _isActiveTransport(lan)),
            _detailItem(context, Icons.link_outlined, 'Direct', direct,
                activeTransport: _isActiveTransport(direct)),
            PopupMenuItem<void>(
              enabled: false,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(_snapshot.roleMessage,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: summaryColor.withValues(alpha: 0.12),
              border: Border.all(color: summaryColor.withValues(alpha: 0.38)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: summaryColor, size: 9),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    _summaryLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
