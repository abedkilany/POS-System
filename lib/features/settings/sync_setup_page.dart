import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/services/lan_sync_service.dart';
import '../../data/app_store.dart';
import '../../models/app_identity.dart';
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
        : LanSyncSettings.generateSecret(),
  );

  final _cloudApiController = TextEditingController(text: CloudSyncSettings.load().apiBaseUrl);
  final _cloudTokenController = TextEditingController(text: CloudSyncSettings.load().apiToken);
  final _cloudPairingCodeController = TextEditingController();

  late final LanSyncService _lanSyncService = LanSyncService(widget.store);
  late final CloudSyncService _cloudSyncService = CloudSyncService(widget.store);

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
        final token = (decoded['token'] ?? decoded['pairingToken'] ?? decoded['pairing_code'] ?? decoded['pairingCode'] ?? decoded['code'] ?? '').toString();
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
      _status = 'Pairing QR loaded. Review the details, then connect.';
    });
  }

  Future<void> _connectLan() async {
    setState(() {
      _busy = true;
      _status = AppLocalizations.of(context).text('connecting_cloning');
    });
    try {
      final secret = _lanTokenController.text.trim();
      final host = _hostController.text.trim();
      if (host.isEmpty) {
        setState(() => _status = 'Host IP is required for LAN connection.');
        return;
      }
      if (secret.isEmpty) {
        setState(() => _status = 'Pairing token is required.');
        return;
      }

      final result = await _lanSyncService.initialClone(host, port: _port, token: secret);
      if (!result.ok) {
        setState(() => _status = result.message);
        return;
      }

      final settings = LanSyncSettings(
        host: host,
        port: _port,
        autoSyncEnabled: true,
        hostModeEnabled: false,
        setupComplete: true,
        mode: LanSyncDeviceMode.client,
        secret: secret,
        lastPullCursor: LanSyncSettings.load().lastPullCursor,
        lastConnectionAt: DateTime.now(),
        lastSyncAt: DateTime.now(),
      );
      await settings.save();

      final identity = widget.store.appIdentity;
      await widget.store.updateAppIdentityDuringSetup(
        identity.copyWith(
          deviceRole: DeviceRole.client,
          syncMode: SyncMode.lanOnly,
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connected to LAN Host. Please sign in.')),
      );
      await widget.onDone();
    } catch (error) {
      if (mounted) setState(() => _status = 'LAN connection failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectCloud() async {
    setState(() {
      _busy = true;
      _status = 'Connecting to Cloud Host and downloading data...';
    });
    try {
      final code = _cloudPairingCodeController.text.trim();
      if (code.isEmpty) {
        setState(() => _status = 'Cloud pairing code is required.');
        return;
      }

      final settings = CloudSyncSettings(
        enabled: true,
        apiBaseUrl: _cloudApiController.text.trim(),
        apiToken: _cloudTokenController.text.trim(),
        autoSyncEnabled: true,
      );
      await settings.save();

      final result = await _cloudSyncService.claimPairingCode(settings, code);
      if (!result.ok) {
        setState(() => _status = result.message);
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message.isEmpty ? 'Connected to Store. Please sign in.' : result.message)),
      );
      await widget.onDone();
    } catch (error) {
      if (mounted) setState(() => _status = 'Cloud connection failed: $error');
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
        title: const Text('Connect to Store'),
      ),
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      Icon(Icons.link, size: 56, color: color.primary),
                      const SizedBox(height: 16),
                      Text('Connect this device to a Store', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      const Text(
                        'Choose LAN or Cloud, enter the pairing code, or scan the Host QR code. After pairing, the device downloads the Store data and returns to Login.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      SegmentedButton<_ConnectMode>(
                        segments: const [
                          ButtonSegment(value: _ConnectMode.cloud, label: Text('Cloud'), icon: Icon(Icons.cloud_outlined)),
                          ButtonSegment(value: _ConnectMode.lan, label: Text('LAN'), icon: Icon(Icons.wifi_outlined)),
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
                      if (_mode == _ConnectMode.cloud) ..._buildCloudFields(),
                      if (_mode == _ConnectMode.lan) ..._buildLanFields(tr),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _scanQr,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan QR Code'),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _connect,
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Connect to Store'),
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
                      children: const [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Connecting and downloading Store data...'),
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
            helperText: 'Enter the Host IP or scan the Host QR code.',
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
            labelText: tr.text('pairing_token'),
            helperText: 'Paste the LAN pairing token or scan the QR code.',
            border: const OutlineInputBorder(),
          ),
        ),
      ];

  List<Widget> _buildCloudFields() => [
        TextField(
          controller: _cloudApiController,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'Cloud API URL',
            helperText: 'Use the default value unless your Store uses a custom server.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _cloudPairingCodeController,
          enabled: !_busy,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Cloud Pairing Code',
            helperText: 'Paste the pairing code or scan the QR code from the Host.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          initiallyExpanded: _advancedCloud,
          onExpansionChanged: (value) => setState(() => _advancedCloud = value),
          tilePadding: EdgeInsets.zero,
          title: const Text('Advanced Cloud Settings'),
          subtitle: const Text('Technical settings. Usually not needed.'),
          children: [
            TextField(
              controller: _cloudTokenController,
              enabled: !_busy,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Cloud Sync Token',
                helperText: 'Advanced only. Leave unchanged if already configured.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ];
}
