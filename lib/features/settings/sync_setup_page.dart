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

  int get _port => int.tryParse(_portController.text.trim()) ?? 8787;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _lanTokenController.dispose();
    _cloudApiController.dispose();
    _cloudTokenController.dispose();
    _cloudPairingCodeController.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerPage(
          title: 'Scan pairing QR',
          helpText: 'Point the camera at the Host pairing QR code.',
          formats: [BarcodeFormat.qrCode],
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
      _status = 'QR detected. Connecting automatically...';
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
    setState(() {
      _busy = true;
      _status = AppLocalizations.of(context).text('connect_lan_start');
    });
    try {
      final secret = _lanTokenController.text.trim();
      final host = _hostController.text.trim();
      if (host.isEmpty) {
        setState(() => _status = AppLocalizations.of(context).text('host_ip_required_lan'));
        return;
      }
      if (secret.isEmpty) {
        setState(() => _status = AppLocalizations.of(context).text('lan_pairing_code_required'));
        return;
      }

      if (mounted) setState(() => _status = AppLocalizations.of(context).text('claiming_lan_pairing'));
      final result = await _lanEngine().claimPairingCode(secret);
      if (!result.ok) {
        setState(() => _status = result.message);
        return;
      }

      if (mounted) setState(() => _status = AppLocalizations.of(context).text('lan_credentials_saved'));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).text('connected_lan_sign_in'))),
      );
      await widget.onDone();
    } catch (error) {
      if (mounted) setState(() => _status = '${AppLocalizations.of(context).text('lan_connection_failed')}: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectCloud() async {
    setState(() {
      _busy = true;
      _status = AppLocalizations.of(context).text('claiming_cloud_pairing');
    });
    try {
      final code = _cloudPairingCodeController.text.trim();
      if (code.isEmpty) {
        setState(() => _status = AppLocalizations.of(context).text('cloud_pairing_code_required'));
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

      if (mounted) setState(() => _status = AppLocalizations.of(context).text('verifying_pairing_code'));
      final result = await _cloudEngine(settings).claimPairingCode(code);
      if (!result.ok) {
        setState(() => _status = result.message);
        return;
      }

      if (!mounted) return;
      if (mounted) setState(() => _status = AppLocalizations.of(context).text('cloud_pairing_complete_background'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message.isEmpty ? AppLocalizations.of(context).text('connected_store_sign_in') : result.message)),
      );
      await widget.onDone();
    } catch (error) {
      if (mounted) setState(() => _status = '${AppLocalizations.of(context).text('cloud_connection_failed')}: $error');
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
              constraints: BoxConstraints(maxWidth: VentioResponsive.clampToScreen(context, 760, min: 280, horizontalPadding: 32)),
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      Icon(Icons.link, size: 56, color: color.primary),
                      const SizedBox(height: 16),
                      Text(tr.text('connect_device_to_store'), style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text(
                        tr.text('connect_device_to_store_desc'),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
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
                                }),
                      ),
                      const SizedBox(height: 16),
                      if (_mode == _ConnectMode.cloud) ..._buildCloudFields(tr),
                      if (_mode == _ConnectMode.lan) ..._buildLanFields(tr),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _scanQr,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: Text(tr.text('scan_qr_code')),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _connect,
                          icon: const Icon(Icons.check_circle_outline),
                          label: Text(tr.text('connect_to_store')),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_status.isNotEmpty) Text(_status, textAlign: TextAlign.center),
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
                    padding: const EdgeInsets.all(24),
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
