import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/responsive.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/services/lan_sync_service.dart';
import '../../core/sync_unified/sync_unified.dart';
import '../../data/app_store.dart';
import '../barcode/barcode_scanner_page.dart';

enum _ConnectMode { lan, cloud }

enum _SetupStatus { idle, info, success, warning, error }

enum _QrPairingStatus { active, expired, consumed, invalid, disabled }

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
    text: LanSyncSettings.load().secret.trim().isNotEmpty
        ? LanSyncSettings.load().secret.trim()
        : LanSyncSettings.generatePairingCode(),
  );

  final _cloudApiController = TextEditingController(text: CloudSyncSettings.load().apiBaseUrl);
  final _cloudTokenController = TextEditingController(text: CloudSyncSettings.load().apiToken);
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
  bool _advancedCloud = false;
  String _status = '';
  _SetupStatus _statusType = _SetupStatus.idle;
  Timer? _qrCountdownTimer;
  DateTime? _qrExpiresAt;
  _QrPairingStatus _qrStatus = _QrPairingStatus.disabled;

  int get _port => int.tryParse(_portController.text.trim()) ?? 8787;

  String get _activePairingCode => _mode == _ConnectMode.cloud ? _cloudPairingCodeController.text.trim() : _lanTokenController.text.trim();

  String _countdownText(DateTime? expiresAt) {
    if (expiresAt == null) return '00:00';
    final seconds = expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 24 * 60 * 60).toInt();
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  void _startQrCountdownTimer() {
    _qrCountdownTimer?.cancel();
    _qrCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_qrStatus == _QrPairingStatus.active && _qrExpiresAt != null && !_qrExpiresAt!.isAfter(DateTime.now())) {
        setState(() => _qrStatus = _QrPairingStatus.expired);
        return;
      }
      if (_qrStatus == _QrPairingStatus.active) setState(() {});
    });
  }

  void _syncQrStatusFromInput() {
    final code = _activePairingCode;
    if (code.isEmpty) {
      _qrStatus = _QrPairingStatus.disabled;
      _qrExpiresAt = null;
      return;
    }
    if (_qrStatus == _QrPairingStatus.consumed || _qrStatus == _QrPairingStatus.invalid) return;
    if (_qrExpiresAt != null && !_qrExpiresAt!.isAfter(DateTime.now())) {
      _qrStatus = _QrPairingStatus.expired;
      return;
    }
    _qrStatus = _QrPairingStatus.active;
  }

  void _markQrConsumed() {
    if (!mounted) return;
    setState(() => _qrStatus = _QrPairingStatus.consumed);
  }

  void _markQrFailed(String message) {
    final lower = message.toLowerCase();
    final expiredOrUsed = lower.contains('expired') || lower.contains('already used') || lower.contains('410') || lower.contains('409');
    if (!mounted) return;
    setState(() => _qrStatus = expiredOrUsed ? _QrPairingStatus.expired : _QrPairingStatus.invalid);
  }

  void _setStatus(String message, {_SetupStatus type = _SetupStatus.info}) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _statusType = message.trim().isEmpty ? _SetupStatus.idle : type;
    });
  }

  void _clearStatus() {
    if (!mounted) return;
    setState(() {
      _status = '';
      _statusType = _SetupStatus.idle;
    });
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
    _cloudTokenController.dispose();
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
        final apiBaseUrl = (decoded['apiBaseUrl'] ?? decoded['apiUrl'] ?? decoded['cloudApiUrl'] ?? '').toString();
        final expiresAtRaw = (decoded['expiresAt'] ?? decoded['expires_at'] ?? '').toString();
        _qrExpiresAt = DateTime.tryParse(expiresAtRaw);

        if (host.trim().isNotEmpty) _hostController.text = host.trim();
        if (port.trim().isNotEmpty) _portController.text = port.trim();
        if (apiBaseUrl.trim().isNotEmpty) _cloudApiController.text = apiBaseUrl.trim();

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
    final lanCredentialsSaved = tr.text('lan_credentials_saved');
    final connectedLanSignIn = tr.text('connected_lan_sign_in');
    final lanConnectionFailed = tr.text('lan_connection_failed');

    setState(() {
      _busy = true;
      _status = connectLanStart;
      _statusType = _SetupStatus.info;
    });
    try {
      final secret = _lanTokenController.text.trim();
      final host = _hostController.text.trim();
      if (host.isEmpty) {
        _setStatus(hostIpRequiredLan, type: _SetupStatus.warning);
        return;
      }
      if (secret.isEmpty) {
        _setStatus(lanPairingCodeRequired, type: _SetupStatus.warning);
        return;
      }

      _setStatus(claimingLanPairing);
      final result = await _lanEngine().claimPairingCode(secret);
      if (!result.ok) {
        _markQrFailed(result.message);
        _setStatus(result.message, type: _SetupStatus.error);
        return;
      }

      _markQrConsumed();
      _setStatus(lanCredentialsSaved, type: _SetupStatus.success);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(connectedLanSignIn)),
      );
      await widget.onDone();
    } catch (error) {
      _markQrFailed(error.toString());
      _setStatus('$lanConnectionFailed: $error', type: _SetupStatus.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectCloud() async {
    final tr = AppLocalizations.of(context);
    final claimingCloudPairing = tr.text('claiming_cloud_pairing');
    final cloudPairingCodeRequired = tr.text('cloud_pairing_code_required');
    final verifyingPairingCode = tr.text('verifying_pairing_code');
    final cloudPairingCompleteBackground = tr.text('cloud_pairing_complete_background');
    final connectedStoreSignIn = tr.text('connected_store_sign_in');
    final cloudConnectionFailed = tr.text('cloud_connection_failed');

    setState(() {
      _busy = true;
      _status = claimingCloudPairing;
      _statusType = _SetupStatus.info;
    });
    try {
      final code = _cloudPairingCodeController.text.trim();
      if (code.isEmpty) {
        _setStatus(cloudPairingCodeRequired, type: _SetupStatus.warning);
        return;
      }

      final existing = CloudSyncSettings.load();
      final settings = CloudSyncSettings(
        enabled: true,
        apiBaseUrl: _cloudApiController.text.trim(),
        // Clients must not need the Host deployment token. Preserve an existing
        // token only for upgraded Host/advanced setups; normal client pairing
        // works with API URL + single-use code only.
        apiToken: _cloudTokenController.text.trim().isNotEmpty ? _cloudTokenController.text.trim() : existing.apiToken,
        autoSyncEnabled: true,
      );
      await settings.save();

      _setStatus(verifyingPairingCode);
      final result = await _cloudEngine(settings).claimPairingCode(code);
      if (!result.ok) {
        _markQrFailed(result.message);
        _setStatus(result.message, type: _SetupStatus.error);
        return;
      }

      if (!mounted) return;
      _markQrConsumed();
      _setStatus(cloudPairingCompleteBackground, type: _SetupStatus.success);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message.isEmpty ? connectedStoreSignIn : result.message)),
      );
      await widget.onDone();
    } catch (error) {
      _markQrFailed(error.toString());
      _setStatus('$cloudConnectionFailed: $error', type: _SetupStatus.error);
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

    return Scaffold(
      appBar: AppBar(
        title: Text(tr.text('connect_to_store')),
      ),
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: VentioResponsive.clampToScreen(context, 860, min: 280, horizontalPadding: 32)),
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: VentioResponsive.pageInsets(context),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      _buildHeader(context, tr, color),
                      const SizedBox(height: 24),
                      _buildSectionTitle(context, tr.text('connection_method'), Icons.hub_outlined),
                      const SizedBox(height: 12),
                      SegmentedButton<_ConnectMode>(
                        segments: [
                          ButtonSegment(value: _ConnectMode.cloud, label: Text(tr.text('connection_cloud')), icon: const Icon(Icons.cloud_outlined)),
                          ButtonSegment(value: _ConnectMode.lan, label: Text(tr.text('connection_lan')), icon: const Icon(Icons.wifi_outlined)),
                        ],
                        selected: {_mode},
                        onSelectionChanged: _busy
                            ? null
                            : (value) => setState(() {
                                  _mode = value.first;
                                  _status = '';
                                  _statusType = _SetupStatus.idle;
                                  _qrExpiresAt = null;
                                  _syncQrStatusFromInput();
                                }),
                      ),
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
                          label: Text(tr.text('connect_to_store')),
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
          if (_busy)
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.24),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: VentioResponsive.pageInsets(context),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(_status.isEmpty ? tr.text('connecting_downloading_store_data') : _status, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }


  ({String label, IconData icon, Color background, Color foreground}) _qrStatusData(BuildContext context, AppLocalizations tr) {
    final color = Theme.of(context).colorScheme;
    return switch (_qrStatus) {
      _QrPairingStatus.active => (label: tr.text('pairing_status_active'), icon: Icons.check_circle_outline, background: Colors.green.withValues(alpha: 0.12), foreground: Colors.green.shade700),
      _QrPairingStatus.expired => (label: tr.text('pairing_status_expired'), icon: Icons.timer_off_outlined, background: Colors.orange.withValues(alpha: 0.14), foreground: Colors.orange.shade800),
      _QrPairingStatus.consumed => (label: tr.text('pairing_status_consumed'), icon: Icons.done_all_outlined, background: Colors.green.withValues(alpha: 0.12), foreground: Colors.green.shade700),
      _QrPairingStatus.invalid => (label: tr.text('pairing_status_invalid'), icon: Icons.error_outline, background: color.errorContainer, foreground: color.onErrorContainer),
      _QrPairingStatus.disabled => (label: tr.text('pairing_status_disabled'), icon: Icons.block_outlined, background: Colors.grey.withValues(alpha: 0.16), foreground: color.onSurfaceVariant),
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
      _QrPairingStatus.active => Colors.green,
      _QrPairingStatus.consumed => Colors.green,
      _QrPairingStatus.expired => Colors.orange,
      _QrPairingStatus.invalid => color.error,
      _QrPairingStatus.disabled => color.outlineVariant,
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
                ? tr.text('connection_state_connected')
                : tr.text('connection_state_ready');
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
    _syncQrStatusFromInput();
    final color = Theme.of(context).colorScheme;
    final hasCode = _activePairingCode.isNotEmpty;
    final borderColor = _qrBorderColor(context);
    final helper = _qrStatus == _QrPairingStatus.active && _qrExpiresAt != null
        ? tr.format('expires_in', {'time': _countdownText(_qrExpiresAt)})
        : tr.format('pairing_code_state_help', {'status': _qrStatusData(context, tr).label.toLowerCase()});
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
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.qr_code_2_rounded, color: color.onSecondaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr.text('qr_pairing'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(hasCode ? tr.text('qr_pairing_detected') : tr.text('qr_pairing_empty'), style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
                _qrStatusBadge(context, tr),
              ],
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
          controller: _cloudApiController,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: tr.text('cloud_api_url'),
            helperText: tr.text('cloud_api_url_helper'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 8),
        ExpansionTile(
          initiallyExpanded: _advancedCloud,
          onExpansionChanged: (value) => setState(() => _advancedCloud = value),
          tilePadding: EdgeInsets.zero,
          title: Text(tr.text('advanced_cloud_settings')),
          subtitle: Text(tr.text('advanced_cloud_settings_desc')),
          children: [
            TextField(
              controller: _cloudTokenController,
              enabled: !_busy,
              obscureText: true,
              decoration: InputDecoration(
                labelText: tr.text('cloud_sync_token'),
                helperText: tr.text('cloud_sync_token_helper'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ];
}
