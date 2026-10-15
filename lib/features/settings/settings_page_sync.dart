part of 'settings_page.dart';

const _lanPairingExpiryStorageKey = 'lan_pairing_expires_at_v1';
const _directPairingCodeStorageKey = 'direct_pairing_code_v1';
const _directPairingExpiryStorageKey = 'direct_pairing_expires_at_v1';
const _pairingCodeLifetime = Duration(minutes: 5);

class _UnifiedSyncSettingsCard extends StatefulWidget {
  const _UnifiedSyncSettingsCard(
      {required this.store, this.onSyncSettingsChanged});

  final AppStore store;
  final Future<void> Function()? onSyncSettingsChanged;

  @override
  State<_UnifiedSyncSettingsCard> createState() =>
      _UnifiedSyncSettingsCardState();
}

class _UnifiedSyncSettingsCardState extends State<_UnifiedSyncSettingsCard> {
  final _lanHostController = TextEditingController();
  final _lanPortController = TextEditingController();
  final _lanIntervalController = TextEditingController();
  final _lanTokenController = TextEditingController();
  final _directApiController = TextEditingController();
  final _directPairingCodeController = TextEditingController();
  final _directIntervalController = TextEditingController();
  final _transferDeviceController = TextEditingController();
  DeviceRole _deviceRole = DeviceRole.host;
  SyncMode _clientSyncMode = SyncMode.lanOnly;
  bool _clientSyncModeDirty = false;
  bool _lanEnabledForHost = false;
  bool _directEnabled = false;
  bool _busy = false;
  String _status = '';
  double? _statusProgress;
  String _latestDirectPairingCode = '';
  String _latestPairingTransport = 'direct';
  DateTime? _latestDirectPairingExpiresAt;
  List<String> _hostIpAddresses = const <String>[];
  bool _detectingHostIp = false;
  bool _showLanPairingCode = false;
  bool _showDirectPairingCode = false;
  bool _showDirectDiagnostics = false;
  DateTime? _latestLanPairingExpiresAt;
  bool _latestLanPairingConsumed = false;
  bool _latestDirectPairingConsumed = false;
  bool _latestDirectPairingInvalid = false;
  DateTime? _lastDirectPairingStatusCheck;
  Timer? _pairingCountdownTimer;
  Timer? _syncAutoSaveTimer;
  String _expectedPairingStoreId = '';
  String _expectedPairingBranchId = '';
  String _expectedPairingHostDeviceId = '';
  String _expectedPairingControlPlaneId = '';

  AppLocalizations get tr => AppLocalizations.of(context);
  bool get _canManageSync =>
      widget.store.hasPermission(AppPermission.syncManage);

  String get _initialDirectHostReadyKey =>
      'direct_initial_snapshot_ready_${widget.store.appIdentity.storeId}';

  bool? _directSyncPlanAllowed;

  bool get _directSyncPlanChecking => _directSyncPlanAllowed == null;
  bool get _directSyncPlanDenied => _directSyncPlanAllowed == false;
  bool get _directSyncPlanAllowsUi => _directSyncPlanAllowed == true;
  bool get _effectiveDirectEnabled => _directEnabled && _directSyncPlanAllowsUi;

  @override
  void initState() {
    super.initState();
    // Direct entitlement is controlled by Admin > Subscribers. Until the
    // live entitlement is verified, keep Direct disabled by default.
    _directSyncPlanAllowed = null;
    final identity = widget.store.appIdentity;
    final lan = LanSyncSettings.load();
    final direct = DirectSyncSettings.load();
    _deviceRole = identity.isClient ? DeviceRole.client : DeviceRole.host;
    _clientSyncMode = _runtimeClientTransport() == 'direct'
        ? SyncMode.directConnected
        : SyncMode.lanOnly;
    _clientSyncModeDirty = false;
    _lanEnabledForHost = identity.isHost && lan.setupComplete && lan.isHost;
    _directEnabled = identity.isDirectEnabled;
    _lanHostController.text = lan.host;
    _lanPortController.text = lan.port.toString();
    _lanIntervalController.text = lan.intervalSeconds.toString();
    _lanTokenController.text = lan.secret.trim();
    _directApiController.text = direct.apiBaseUrl;
    _directIntervalController.text =
        LanSyncSettings.defaultIntervalSeconds.toString();
    for (final controller in [
      _lanHostController,
      _lanPortController,
      _lanIntervalController,
      _lanTokenController,
      _directApiController,
      _directPairingCodeController,
      _directIntervalController,
    ]) {
      controller.addListener(_onSyncDraftChanged);
    }
    _loadActivePairingCodes();
    _startPairingCountdownTimer();
    unawaited(_refreshDirectSyncPlanAccess());
    // Do not auto-detect or write the LAN Host/IP when the page opens.
    // IP detection is a user-driven action from the Refresh IP button so
    // the Save button only becomes enabled after an intentional change.
  }

  @override
  void dispose() {
    _lanHostController.dispose();
    _lanPortController.dispose();
    _lanIntervalController.dispose();
    _lanTokenController.dispose();
    _directApiController.dispose();
    _directPairingCodeController.dispose();
    _directIntervalController.dispose();
    _transferDeviceController.dispose();
    _pairingCountdownTimer?.cancel();
    _syncAutoSaveTimer?.cancel();
    super.dispose();
  }

  // Legacy entitlement refresh is retained for the next server cleanup phase.
  // It is intentionally not called by the Direct/LAN settings UI.
  // ignore: unused_element
  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    final identity = widget.store.appIdentity;
    final isHost = _deviceRole == DeviceRole.host;
    final runtimeClientTransport = isHost
        ? identity.activeSyncTransportNormalized
        : _runtimeClientTransport();
    final lanActive =
        isHost ? _lanEnabledForHost : runtimeClientTransport == 'lan';
    final directActive = isHost
        ? _effectiveDirectEnabled
        : (runtimeClientTransport == 'direct' && _directSyncPlanAllowsUi);
    final hostActionLabel = tr.text('sync_now');
    final pendingCount = isHost ? 0 : widget.store.activeClientPendingSyncCount;
    final allGood = pendingCount == 0 && (lanActive || directActive || !isHost);

    return Card(
      elevation: 0,
      child: Padding(
        padding: VentioResponsive.pageInsets(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _syncHeroHeader(
              context,
              allGood: allGood,
              isHost: isHost,
              lanActive: lanActive,
              directActive: directActive,
              actionLabel: hostActionLabel,
            ),
            if (widget.store.latestHostTransferNotification != null) ...[
              const SizedBox(height: 12),
              _hostChangedNotificationCard(),
            ],
            const SizedBox(height: 14),
            _syncOverviewCard(context,
                allGood: allGood,
                isHost: isHost,
                lanActive: lanActive,
                directActive: directActive,
                pendingCount: pendingCount),
            if (!isHost && widget.store.isSuspendedByHost) ...[
              const SizedBox(height: 14),
              _clientSuspendedWarningCard(context),
            ],
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final thisDevice = _thisDeviceCard(context,
                    isHost: isHost,
                    lanActive: lanActive,
                    directActive: directActive);

                // Clients are paired during first-time setup/login. Once this
                // settings page is reachable, the Client should not show a
                // misleading "Connect Device" action again; Sync should only
                // show status, sync information, and management controls.
                if (!isHost) {
                  return thisDevice;
                }

                final addDevice = _addDeviceCard(context,
                    isHost: true, isDirectClient: false);
                if (compact) {
                  return Column(children: [
                    thisDevice,
                    const SizedBox(height: 14),
                    addDevice
                  ]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: thisDevice),
                    const SizedBox(width: 14),
                    Expanded(child: addDevice),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            _syncChannelsCard(context,
                isHost: isHost,
                lanActive: lanActive,
                directActive: directActive),
            if (isHost) ...[
              const SizedBox(height: 14),
              _advancedSyncCard(context, isHost: isHost),
            ],
            const SizedBox(height: 14),
            _syncStatusMessage(context, color),
            if (!isHost) ...[
              const SizedBox(height: 14),
              _syncSaveCancelBar(context),
            ],
          ],
        ),
      ),
    );
  }
}
