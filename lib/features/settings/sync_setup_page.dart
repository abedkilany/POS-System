import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/responsive.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/services/lan_sync_service.dart';
import '../../core/sync_unified/sync_unified.dart';
import '../../core/snapshot/unified_snapshot_progress.dart';
import '../../data/app_store.dart';
import '../barcode/barcode_scanner_page.dart';

enum _ConnectMode { lan, cloud }

enum _SetupStatus { idle, info, success, warning, error }

enum _ClientPairingState { noCode, ready, connecting, connected, failed, expired }

class SyncSetupPage extends StatefulWidget {
  const SyncSetupPage({super.key, required this.store, required this.onDone});

  final AppStore store;
  final Future<void> Function() onDone;

  @override
  State<SyncSetupPage> createState() => _SyncSetupPageState();
}

class _SyncSetupPageState extends State<SyncSetupPage> {
  final _hostController = TextEditingController(text: LanSyncSettings.load().host);
  final _portController = TextEditingController(text: LanSyncSettings.load().port.toString());
  final _lanTokenController = TextEditingController(
    text: LanSyncSettings.load().secret.trim(),
  );

  final _cloudApiController = TextEditingController(text: CloudSyncSettings.load().apiBaseUrl);
  final _cloudPairingCodeController = TextEditingController();

  late final LanSyncService _lanSyncService = LanSyncService(widget.store);
  late final CloudSyncService _cloudSyncService = CloudSyncService(widget.store);

  UnifiedSyncEngine _lanEngine() => UnifiedSyncEngine(
        LanSyncTransportAdapter(
          service: _lanSyncService,
          settings: LanSyncSettings.load().copyWith(
            host: _hostController.text.trim(),
            port: _port,
            secret: _lanTokenController.text.trim(),
            mode: LanSyncDeviceMode.client,
            setupComplete: true,
            hostModeEnabled: false,
          ),
        ),
      );

  UnifiedSyncEngine _cloudEngine(CloudSyncSettings settings) => UnifiedSyncEngine(
        CloudSyncTransportAdapter(
          service: _cloudSyncService,
          settings: settings,
        ),
      );

  _ConnectMode _mode = _ConnectMode.cloud;
  bool _busy = false;
  String _status = '';
  _SetupStatus _statusType = _SetupStatus.idle;
  double? _snapshotProgressValue;
  String _snapshotProgressLabel = '';
  Timer? _qrCountdownTimer;
  DateTime? _qrExpiresAt;
  _ClientPairingState _qrStatus = _ClientPairingState.noCode;

  int get _port => int.tryParse(_portController.text.trim()) ?? 8787;

  String get _activePairingCode => _mode == _ConnectMode.cloud ? _cloudPairingCodeController.text.trim() : _lanTokenController.text.trim();

  void _startQrCountdownTimer() {
    _qrCountdownTimer?.cancel();
    _qrCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_qrStatus == _ClientPairingState.ready && _qrExpiresAt != null && !_qrExpiresAt!.isAfter(DateTime.now())) {
        setState(() => _qrStatus = _ClientPairingState.expired);
        return;
      }
      if (_qrStatus == _ClientPairingState.ready) setState(() {});
    });
  }

  void _syncQrStatusFromInput() {
    final code = _activePairingCode;
    if (code.isEmpty) {
      _qrStatus = _ClientPairingState.noCode;
      _qrExpiresAt = null;
      return;
    }
    if (_qrStatus == _ClientPairingState.connected || _qrStatus == _ClientPairingState.connecting) return;
    if (_qrExpiresAt != null && !_qrExpiresAt!.isAfter(DateTime.now())) {
      _qrStatus = _ClientPairingState.expired;
      return;
    }
    _qrStatus = _ClientPairingState.ready;
    if (_statusType == _SetupStatus.error) {
      _status = '';
      _statusType = _SetupStatus.idle;
    }
  }

  void _markQrFailed(String message) {
    final lower = message.toLowerCase();
    final expiredOrUsed = lower.contains('expired') || lower.contains('already used') || lower.contains('410') || lower.contains('409');
    if (!mounted) return;
    setState(() => _qrStatus = expiredOrUsed ? _ClientPairingState.expired : _ClientPairingState.failed);
  }

  void _setStatus(String message, {_SetupStatus type = _SetupStatus.info}) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _statusType = message.trim().isEmpty ? _SetupStatus.idle : type;
    });
  }

  void _setSnapshotProgress(double value, String label) {
    if (!mounted) return;
    setState(() {
      _snapshotProgressValue = value.clamp(0.0, 1.0).toDouble();
      _snapshotProgressLabel = label;
      _status = label;
      _statusType = _SetupStatus.info;
    });
  }

  void _clearStatus() {
    if (!mounted) return;
    setState(() {
      _status = '';
      _statusType = _SetupStatus.idle;
    });
  }


  void _beginConnectionAttempt(String message) {
    setState(() {
      _busy = true;
      _qrStatus = _ClientPairingState.connecting;
      _status = message;
      _statusType = _SetupStatus.info;
      _snapshotProgressValue = 0.02;
      _snapshotProgressLabel = message;
    });
  }

  Future<void> _finishSuccessfulConnection(String message) async {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _qrStatus = _ClientPairingState.connected;
      _status = message;
      _statusType = _SetupStatus.success;
    });
    try {
      await widget.onDone();
    } catch (_) {
      // Pairing has already succeeded. Navigation cleanup must never turn a
      // successful connection into an error message for the user.
    }
    if (!mounted) return;
    try {
      final navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.pop();
    } catch (_) {
      // Best-effort fallback only. The login gate will refresh after onDone.
    }
  }


  String _friendlyErrorMessage(Object error, {required String fallback}) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('pairing code expired') || lower.contains('already used') || lower.contains('410') || lower.contains('409')) {
      return AppLocalizations.of(context).text('pairing_code_expired_or_used');
    }
    if (lower.contains('socketexception') || lower.contains('clientexception') || lower.contains('timeoutexception') || lower.contains('failed host lookup')) {
      return fallback;
    }
    if (lower.contains('null check operator used on a null value')) {
      return AppLocalizations.of(context).text('pairing_state_refresh_failed');
    }
    return fallback;
  }

  @override
  void initState() {
    super.initState();
    _syncQrStatusFromInput();
    _startQrCountdownTimer();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _lanTokenController.dispose();
    _cloudApiController.dispose();
    _cloudPairingCodeController.dispose();
    _qrCountdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => BarcodeScannerPage(
          title: AppLocalizations.of(context).text('scan_pairing_qr'),
          helpText: AppLocalizations.of(context).text('scan_pairing_qr_help'),
          formats: const [BarcodeFormat.qrCode],
        ),
      ),
    );
    if (code == null || code.trim().isEmpty) return;
    _applyScannedPayload(code.trim());
  }

  void _applyScannedPayload(String raw) {
    String code = raw;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final transport = (decoded['transport'] ?? decoded['syncType'] ?? decoded['type'] ?? '').toString().toLowerCase();
        if (transport.contains('lan')) {
          _mode = _ConnectMode.lan;
        } else if (transport.contains('cloud')) {
          _mode = _ConnectMode.cloud;
        }

        final host = (decoded['host'] ?? decoded['hostIp'] ?? decoded['ip'] ?? '').toString();
        final port = (decoded['port'] ?? '').toString();
        final token = (decoded['pairingCode'] ?? decoded['pairing_code'] ?? decoded['code'] ?? decoded['token'] ?? decoded['pairingToken'] ?? '').toString();
        final expiresAtRaw = (decoded['expiresAt'] ?? decoded['expires_at'] ?? '').toString();
        _qrExpiresAt = DateTime.tryParse(expiresAtRaw);

        if (host.trim().isNotEmpty) _hostController.text = host.trim();
        if (port.trim().isNotEmpty) _portController.text = port.trim();

        code = token.trim().isNotEmpty ? token.trim() : raw;
      }
    } catch (_) {
      // Plain pairing code. Keep it as-is.
    }

    setState(() {
      if (_mode == _ConnectMode.lan) {
        _lanTokenController.text = code;
      } else {
        _cloudPairingCodeController.text = code;
      }
      _status = AppLocalizations.of(context).text('qr_detected_connecting');
      _statusType = _SetupStatus.info;
      _syncQrStatusFromInput();
    });
    Future.microtask(() async {
      if (!mounted || _busy) return;
      if (_mode == _ConnectMode.cloud && _cloudPairingCodeController.text.trim().isNotEmpty) {
        await _connectCloud();
      } else if (_mode == _ConnectMode.lan && _lanTokenController.text.trim().isNotEmpty) {
        await _connectLan();
      }
    });
  }

  Future<void> _connectLan() async {
    final tr = AppLocalizations.of(context);
    final connectLanStart = tr.text('connect_lan_start');
    final hostIpRequiredLan = tr.text('host_ip_required_lan');
    final lanPairingCodeRequired = tr.text('lan_pairing_code_required');
    final claimingLanPairing = tr.text('claiming_lan_pairing');
    final connectedLanSignIn = tr.text('connected_lan_sign_in');
    final lanConnectionFailed = tr.text('lan_connection_failed');

    _beginConnectionAttempt(connectLanStart);
    try {
      final secret = _lanTokenController.text.trim();
      final host = _hostController.text.trim();
      if (host.isEmpty) {
        setState(() => _qrStatus = _ClientPairingState.noCode);
        _setStatus(hostIpRequiredLan, type: _SetupStatus.warning);
        return;
      }
      if (secret.isEmpty) {
        setState(() => _qrStatus = _ClientPairingState.noCode);
        _setStatus(lanPairingCodeRequired, type: _SetupStatus.warning);
        return;
      }

      _setStatus(claimingLanPairing);
      final result = await _lanEngine().claimPairingCode(secret, onProgress: _setSnapshotProgress);
      if (!result.ok) {
        _markQrFailed(result.message);
        _setStatus(result.message, type: _SetupStatus.error);
        return;
      }

      await _finishSuccessfulConnection(connectedLanSignIn);
    } catch (error) {
      _markQrFailed(error.toString());
      _setStatus(_friendlyErrorMessage(error, fallback: lanConnectionFailed), type: _SetupStatus.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectCloud() async {
    final tr = AppLocalizations.of(context);
    final claimingCloudPairing = tr.text('claiming_cloud_pairing');
    final cloudPairingCodeRequired = tr.text('cloud_pairing_code_required');
    final verifyingPairingCode = tr.text('verifying_pairing_code');
    final connectedStoreSignIn = tr.text('connected_store_sign_in');
    final cloudConnectionFailed = tr.text('cloud_connection_failed');

    _beginConnectionAttempt(claimingCloudPairing);
    try {
      final code = _cloudPairingCodeController.text.trim();
      if (code.isEmpty) {
        setState(() => _qrStatus = _ClientPairingState.noCode);
        _setStatus(cloudPairingCodeRequired, type: _SetupStatus.warning);
        return;
      }

      final existing = CloudSyncSettings.load();
      final normalizedApiBaseUrl = existing.apiBaseUrl.trim().isNotEmpty
          ? existing.apiBaseUrl.trim()
          : CloudSyncSettings.bundledApiBaseUrl;
      _cloudApiController.text = normalizedApiBaseUrl;
      final settings = CloudSyncSettings(
        enabled: true,
        apiBaseUrl: normalizedApiBaseUrl,
        autoSyncEnabled: true,
      );
      await settings.save();

      _setStatus(verifyingPairingCode);
      final result = await _cloudEngine(settings).claimPairingCode(code, onProgress: _setSnapshotProgress);
      if (!result.ok) {
        _markQrFailed(result.message);
        _setStatus(result.message, type: _SetupStatus.error);
        return;
      }

      await _finishSuccessfulConnection(connectedStoreSignIn);
    } on FormatException catch (_) {
      _markQrFailed(cloudConnectionFailed);
      _setStatus(cloudConnectionFailed, type: _SetupStatus.error);
    } catch (error) {
      _markQrFailed(error.toString());
      _setStatus(_friendlyErrorMessage(error, fallback: cloudConnectionFailed), type: _SetupStatus.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() {
    return _mode == _ConnectMode.lan ? _connectLan() : _connectCloud();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    final isMobile = VentioResponsive.isMobile(context);
    final outerPadding = VentioResponsive.pagePadding(context);
    final cardMargin = EdgeInsets.all(isMobile ? 8 : 24);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr.text('connect_to_store')),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Align(
              alignment: AlignmentDirectional.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: VentioResponsive.clampToScreen(
                    context,
                    1100,
                    min: 280,
                    horizontalPadding: outerPadding * 2,
                  ),
                ),
                child: Card(
                  margin: cardMargin,
                  child: Padding(
                    padding: VentioResponsive.pageInsets(context),
                    child: ListView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        _buildHeader(context, tr, color),
                        SizedBox(height: isMobile ? 18 : 24),
                        _buildSectionTitle(context, tr.text('connection_method'), Icons.hub_outlined),
                        const SizedBox(height: 12),
                        _buildModeSelector(context, tr),
                        const SizedBox(height: 16),
                        _buildConnectionStateCard(context, tr),
                        const SizedBox(height: 16),
                        _buildQrCard(context, tr),
                        const SizedBox(height: 16),
                        _buildSectionTitle(context, tr.text(_mode == _ConnectMode.cloud ? 'cloud_setup' : 'lan_setup'), Icons.tune_outlined),
                        const SizedBox(height: 12),
                        if (_mode == _ConnectMode.cloud) ..._buildCloudFields(tr),
                        if (_mode == _ConnectMode.lan) ..._buildLanFields(tr),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _connect,
                            icon: const Icon(Icons.check_circle_outline),
                            label: Text(tr.text('connect_to_store'), overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_status.isNotEmpty) _buildStatusBanner(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: VentioResponsive.dialogLargeWidth(context)),
                    child: Card(
                      margin: EdgeInsets.all(outerPadding),
                      child: Padding(
                        padding: VentioResponsive.pageInsets(context),
                        child: UnifiedSnapshotProgressView(
                          value: _snapshotProgressValue,
                          label: _snapshotProgressLabel.isEmpty
                              ? (_status.isEmpty ? tr.text('connecting_downloading_store_data') : _status)
                              : _snapshotProgressLabel,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModeSelector(BuildContext context, AppLocalizations tr) {
    void selectMode(_ConnectMode mode) {
      if (_busy || _mode == mode) return;
      setState(() {
        _mode = mode;
        _status = '';
        _statusType = _SetupStatus.idle;
        _qrExpiresAt = null;
        _qrStatus = _ClientPairingState.noCode;
        _syncQrStatusFromInput();
      });
    }

    final segments = [
      ButtonSegment(value: _ConnectMode.cloud, label: Text(tr.text('connection_cloud')), icon: const Icon(Icons.cloud_outlined)),
      ButtonSegment(value: _ConnectMode.lan, label: Text(tr.text('connection_lan')), icon: const Icon(Icons.wifi_outlined)),
    ];

    if (!VentioResponsive.isMobile(context)) {
      return SegmentedButton<_ConnectMode>(
        segments: segments,
        selected: {_mode},
        onSelectionChanged: _busy ? null : (value) => selectMode(value.first),
      );
    }

    Widget mobileButton(_ConnectMode mode, IconData icon, String label) {
      final selected = _mode == mode;
      final buttonChild = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label, overflow: TextOverflow.ellipsis),
        ],
      );
      return SizedBox(
        width: double.infinity,
        child: selected
            ? FilledButton(onPressed: _busy ? null : () => selectMode(mode), child: buttonChild)
            : OutlinedButton(onPressed: _busy ? null : () => selectMode(mode), child: buttonChild),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        mobileButton(_ConnectMode.cloud, Icons.cloud_outlined, tr.text('connection_cloud')),
        const SizedBox(height: 8),
        mobileButton(_ConnectMode.lan, Icons.wifi_outlined, tr.text('connection_lan')),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations tr, ColorScheme color) {
    return Column(
      children: [
        Icon(Icons.sync_alt_rounded, size: 56, color: color.primary),
        const SizedBox(height: 16),
        Text(tr.text('connect_device_to_store'), style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(tr.text('connect_device_to_store_desc'), textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }


  ({String label, IconData icon, Color background, Color foreground}) _qrStatusData(BuildContext context, AppLocalizations tr) {
    final color = Theme.of(context).colorScheme;
    return switch (_qrStatus) {
      _ClientPairingState.ready => (label: tr.text('connection_state_pending'), icon: Icons.check_circle_outline, background: Colors.green.withValues(alpha: 0.12), foreground: Colors.green.shade700),
      _ClientPairingState.connecting => (label: tr.text('connection_state_connecting'), icon: Icons.sync_rounded, background: color.primaryContainer, foreground: color.onPrimaryContainer),
      _ClientPairingState.expired => (label: tr.text('pairing_status_expired'), icon: Icons.timer_off_outlined, background: Colors.orange.withValues(alpha: 0.14), foreground: Colors.orange.shade800),
      _ClientPairingState.connected => (label: tr.text('connection_state_active'), icon: Icons.done_all_outlined, background: Colors.green.withValues(alpha: 0.12), foreground: Colors.green.shade700),
      _ClientPairingState.failed => (label: tr.text('connection_state_error'), icon: Icons.error_outline, background: color.errorContainer, foreground: color.onErrorContainer),
      _ClientPairingState.noCode => (label: tr.text('pairing_status_no_code_entered'), icon: Icons.edit_note_outlined, background: Colors.grey.withValues(alpha: 0.16), foreground: color.onSurfaceVariant),
    };
  }

  Widget _qrStatusBadge(BuildContext context, AppLocalizations tr) {
    final data = _qrStatusData(context, tr);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: data.background, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon, size: 16, color: data.foreground),
          const SizedBox(width: 6),
          Text(data.label, style: TextStyle(color: data.foreground, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Color _qrBorderColor(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return switch (_qrStatus) {
      _ClientPairingState.ready => Colors.green,
      _ClientPairingState.connecting => color.primary,
      _ClientPairingState.connected => Colors.green,
      _ClientPairingState.expired => Colors.orange,
      _ClientPairingState.failed => color.error,
      _ClientPairingState.noCode => color.outlineVariant,
    };
  }

  Widget _buildConnectionStateCard(BuildContext context, AppLocalizations tr) {
    final color = Theme.of(context).colorScheme;
    final icon = _busy
        ? Icons.sync_rounded
        : _statusType == _SetupStatus.error
            ? Icons.error_outline
            : _statusType == _SetupStatus.success
                ? Icons.check_circle_outline
                : Icons.radio_button_unchecked;
    final title = _busy
        ? tr.text('connection_state_connecting')
        : _statusType == _SetupStatus.error
            ? tr.text('connection_state_error')
            : _statusType == _SetupStatus.success
                ? tr.text('connection_state_active')
                : tr.text('connection_state_pending');
    final subtitle = _mode == _ConnectMode.cloud ? tr.text('cloud_pairing_code_helper') : tr.text('lan_pairing_code_helper');
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.primaryContainer,
          foregroundColor: color.onPrimaryContainer,
          child: Icon(icon),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }

  Widget _buildQrCard(BuildContext context, AppLocalizations tr) {
    final color = Theme.of(context).colorScheme;
    final hasCode = _activePairingCode.isNotEmpty;
    final borderColor = _qrBorderColor(context);
    final helper = switch (_qrStatus) {
      _ClientPairingState.noCode => tr.text('scan_or_enter_host_pairing_code'),
      _ClientPairingState.ready => tr.text('pairing_code_ready_to_connect_help'),
      _ClientPairingState.connecting => tr.text('connecting_downloading_store_data'),
      _ClientPairingState.connected => tr.text('connected_store_sign_in'),
      _ClientPairingState.expired => tr.text('pairing_code_expired_or_used'),
      _ClientPairingState.failed => tr.text('connection_failed_check_code'),
    };
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor.withValues(alpha: 0.65), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compactHeader = constraints.maxWidth < 430;
                final titleColumn = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr.text('scan_host_qr_code'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasCode ? tr.text('pairing_code_ready_to_connect_help') : tr.text('scan_or_enter_host_pairing_code'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                );
                final iconBox = Container(
                  width: compactHeader ? 44 : 52,
                  height: compactHeader ? 44 : 52,
                  decoration: BoxDecoration(
                    color: color.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.qr_code_2_rounded, color: color.onSecondaryContainer),
                );

                if (compactHeader) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          iconBox,
                          const SizedBox(width: 10),
                          Expanded(child: titleColumn),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(alignment: AlignmentDirectional.centerStart, child: _qrStatusBadge(context, tr)),
                    ],
                  );
                }

                return Row(
                  children: [
                    iconBox,
                    const SizedBox(width: 12),
                    Expanded(child: titleColumn),
                    const SizedBox(width: 12),
                    Flexible(child: Align(alignment: AlignmentDirectional.centerEnd, child: _qrStatusBadge(context, tr))),
                  ],
                );
              },
            ),
            if (hasCode) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _qrStatusData(context, tr).background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(_qrStatusData(context, tr).icon, color: _qrStatusData(context, tr).foreground),
                    const SizedBox(width: 10),
                    Expanded(child: Text(helper, style: TextStyle(color: _qrStatusData(context, tr).foreground))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _scanQr,
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(tr.text('scan_qr_code')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final data = switch (_statusType) {
      _SetupStatus.success => (Icons.check_circle_outline, color.primaryContainer, color.onPrimaryContainer),
      _SetupStatus.warning => (Icons.warning_amber_rounded, color.tertiaryContainer, color.onTertiaryContainer),
      _SetupStatus.error => (Icons.error_outline, color.errorContainer, color.onErrorContainer),
      _ => (Icons.info_outline, color.surfaceContainerHighest, color.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: data.$2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(data.$1, color: data.$3),
          const SizedBox(width: 10),
          Expanded(child: Text(_status, style: TextStyle(color: data.$3))),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: _busy ? null : _clearStatus,
            icon: Icon(Icons.close, color: data.$3),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildLanFields(AppLocalizations tr) => [
        TextField(
          controller: _hostController,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: tr.text('host_ip'),
            helperText: tr.text('host_ip_helper'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _portController,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: tr.text('port'), border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _lanTokenController,
          enabled: !_busy,
          onChanged: (_) => setState(_syncQrStatusFromInput),
          decoration: InputDecoration(
            labelText: tr.text('lan_pairing_code'),
            helperText: tr.text('lan_pairing_code_helper'),
            border: const OutlineInputBorder(),
          ),
        ),
      ];

  List<Widget> _buildCloudFields(AppLocalizations tr) => [
        TextField(
          controller: _cloudPairingCodeController,
          enabled: !_busy,
          onChanged: (_) => setState(_syncQrStatusFromInput),
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: tr.text('cloud_pairing_code'),
            helperText: tr.text('cloud_pairing_code_helper'),
            border: const OutlineInputBorder(),
          ),
        ),
      ];
}
