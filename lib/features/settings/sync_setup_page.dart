import 'package:flutter/material.dart';

import '../../core/services/lan_sync_service.dart';
import '../../data/app_store.dart';
import '../../models/app_identity.dart';

class SyncSetupPage extends StatefulWidget {
  const SyncSetupPage({super.key, required this.store, required this.onDone});

  final AppStore store;
  final Future<void> Function() onDone;

  @override
  State<SyncSetupPage> createState() => _SyncSetupPageState();
}

class _SyncSetupPageState extends State<SyncSetupPage> {
  final _hostController = TextEditingController(text: '192.168.1.100');
  final _portController = TextEditingController(text: '8787');
  final _tokenController = TextEditingController(text: LanSyncSettings.generateSecret());
  late final LanSyncService _syncService = LanSyncService(widget.store);
  bool _busy = false;
  String _status = '';

  int get _port => int.tryParse(_portController.text.trim()) ?? 8787;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _setupHost() async {
    setState(() {
      _busy = true;
      _status = 'Preparing host...';
    });
    try {
      final secret = _tokenController.text.trim().isEmpty ? LanSyncSettings.generateSecret() : _tokenController.text.trim();
      final settings = LanSyncSettings(
        host: _hostController.text.trim().isEmpty ? '0.0.0.0' : _hostController.text.trim(),
        port: _port,
        autoSyncEnabled: true,
        hostModeEnabled: true,
        setupComplete: true,
        mode: LanSyncDeviceMode.host,
        secret: secret,
      );
      await settings.save();
      final identity = widget.store.appIdentity;
      await widget.store.updateAppIdentity(identity.copyWith(
        deviceRole: DeviceRole.host,
        syncMode: identity.syncMode == SyncMode.localOnly ? SyncMode.lanOnly : identity.syncMode,
      ));
      await _syncService.startHost(port: _port);
      await widget.onDone();
    } catch (error) {
      setState(() => _status = 'Host setup failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setupClient() async {
    setState(() {
      _busy = true;
      _status = 'Connecting to host and cloning data...';
    });
    try {
      final secret = _tokenController.text.trim();
      final result = await _syncService.initialClone(_hostController.text.trim(), port: _port, token: secret);
      if (!result.ok) {
        setState(() => _status = result.message);
        return;
      }
      final settings = LanSyncSettings(
        host: _hostController.text.trim(),
        port: _port,
        autoSyncEnabled: true,
        hostModeEnabled: false,
        setupComplete: true,
        mode: LanSyncDeviceMode.client,
        secret: secret,
        lastPullCursor: DateTime.now(),
        lastConnectionAt: DateTime.now(),
        lastSyncAt: DateTime.now(),
      );
      await settings.save();
      final identity = widget.store.appIdentity;
      await widget.store.updateAppIdentity(identity.copyWith(
        deviceRole: DeviceRole.client,
        syncMode: identity.syncMode == SyncMode.localOnly ? SyncMode.lanOnly : identity.syncMode,
      ));
      await widget.onDone();
    } catch (error) {
      setState(() => _status = 'Client setup failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Icon(Icons.sync_alt, size: 56, color: color.primary),
                  const SizedBox(height: 16),
                  Text('Sync setup / إعداد المزامنة', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose Host for the main device with clean local data. Choose Client to copy the full database from the Host, then sync automatically online/offline.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _hostController,
                    decoration: const InputDecoration(
                      labelText: 'Host IP',
                      helperText: 'On Host this can stay as 0.0.0.0 or your LAN IP. On Client enter the Host LAN IP.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tokenController,
                    decoration: const InputDecoration(
                      labelText: 'Pairing token',
                      helperText: 'Use the same token on Host and Client.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _setupHost,
                        icon: const Icon(Icons.wifi_tethering),
                        label: const Text('This device is Host'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _setupClient,
                        icon: const Icon(Icons.devices_other),
                        label: const Text('This device is Client'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_busy) const Center(child: CircularProgressIndicator()),
                  if (_status.isNotEmpty) Text(_status, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

