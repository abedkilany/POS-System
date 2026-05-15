import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/services/backup_download_service.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/services/lan_sync_service.dart';

import '../../core/localization/app_localizations.dart';
import '../../data/app_store.dart';
import '../../models/store_profile.dart';
import '../../models/app_identity.dart';
import 'users_permissions_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.onLocaleChanged, required this.onThemeModeChanged, required this.themeMode, required this.store, this.onSyncSettingsChanged});

  final ValueChanged<Locale> onLocaleChanged;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ThemeMode themeMode;
  final AppStore store;
  final Future<void> Function()? onSyncSettingsChanged;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 720;
    final tabs = [
      Tab(icon: const Icon(Icons.store_outlined), text: tr.text('store_information')),
      Tab(icon: const Icon(Icons.sync_outlined), text: tr.text('sync')),
      Tab(icon: const Icon(Icons.backup_outlined), text: tr.text('backup_restore')),
      Tab(icon: const Icon(Icons.admin_panel_settings_outlined), text: tr.text('users_permissions')),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              isScrollable: isCompact,
              tabs: tabs,
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _settingsList(context, _generalCards(context)),
                _settingsList(context, _syncCards(context)),
                _settingsList(context, _backupCards(context)),
                _settingsList(context, _adminCards(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsList(BuildContext context, List<Widget> children) {
    final width = MediaQuery.sizeOf(context).width;
    return ListView.separated(
      padding: EdgeInsets.all(width < 520 ? 8 : 16),
      itemCount: children.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => children[index],
    );
  }

  List<Widget> _generalCards(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final profile = store.storeProfile;
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.store),
                title: Text(tr.text('store_information')),
                subtitle: Text(tr.text('store_information_desc')),
                trailing: FilledButton.icon(onPressed: () => _editStoreProfile(context, profile), icon: const Icon(Icons.edit_outlined), label: Text(tr.text('edit'))),
              ),
              const Divider(height: 24),
              _Line(title: tr.text('store_name'), value: profile.name),
              _Line(title: tr.text('phone'), value: profile.phone.isEmpty ? '—' : profile.phone),
              _Line(title: tr.text('address'), value: profile.address.isEmpty ? '—' : profile.address),
              _Line(title: tr.text('currency'), value: profile.currency),
              _Line(title: tr.text('invoice_footer'), value: profile.footerNote),
            ],
          ),
        ),
      ),
      _SystemIdentityCard(store: store),

      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Theme', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment<ThemeMode>(value: ThemeMode.system, icon: Icon(Icons.settings_suggest_outlined), label: Text('System')),
                  ButtonSegment<ThemeMode>(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
                  ButtonSegment<ThemeMode>(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
                ],
                selected: {themeMode},
                onSelectionChanged: (selection) => onThemeModeChanged(selection.first),
              ),
            ],
          ),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr.text('language'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [
                OutlinedButton(onPressed: () => onLocaleChanged(const Locale('en')), child: const Text('English')),
                OutlinedButton(onPressed: () => onLocaleChanged(const Locale('ar')), child: const Text('العربية')),
              ]),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _syncCards(BuildContext context) => [
        _UnifiedSyncSettingsCard(store: store, onSyncSettingsChanged: onSyncSettingsChanged),
        _AdvancedSyncDebugCard(store: store),
      ];

  List<Widget> _backupCards(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.backup_outlined), title: Text(tr.text('backup_restore')), subtitle: Text(tr.text('backup_preview_desc'))),
              const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(bottom: 12), child: Chip(avatar: Icon(Icons.storage_outlined, size: 18), label: Text('Local DB: Hive')))),
              _BackupSummaryCard(summary: store.currentBackupSummary),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _downloadBackupFile(context),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Export'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _importBackupFile(context),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Import'),
                ),
              ),
            ],
          ),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _dataManagementTile(context),
        ),
      ),
    ];
  }


  Widget _dataManagementTile(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final isHost = store.appIdentity.isHost;
    final isClient = store.appIdentity.isClient;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_outlined, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr.text('data_management'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(isHost ? tr.text('data_management_desc') : 'Client maintenance affects only this device and is never synced to other devices.'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (isHost)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => _resetBusinessData(context),
              icon: const Icon(Icons.delete_forever_outlined),
              label: Text(tr.text('reset_all_data')),
            ),
          ),
        if (isClient) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _clearLocalData(context),
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('Clear Local Data'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _rebuildFromHost(context),
              icon: const Icon(Icons.restore_page_outlined),
              label: const Text('Rebuild From Host'),
            ),
          ),
        ],
      ],
    );
  }


  List<Widget> _adminCards(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return [
      Card(
        child: ListTile(
          leading: const Icon(Icons.people),
          title: Text(tr.text('users_permissions')),
          subtitle: Text("Signed in as ${store.activeUser?.fullName ?? 'Unknown'} • Role: ${store.currentRole}"),
          trailing: FilledButton.icon(
            onPressed: store.canManageUsers ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => UsersPermissionsPage(store: store))) : null,
            icon: const Icon(Icons.manage_accounts_outlined),
            label: Text(tr.text('manage')),
          ),
        ),
      ),
    ];
  }



  Future<void> _editStoreProfile(BuildContext context, StoreProfile profile) async {
    final nameController = TextEditingController(text: profile.name);
    final phoneController = TextEditingController(text: profile.phone);
    final addressController = TextEditingController(text: profile.address);
    final footerController = TextEditingController(text: profile.footerNote);
    String currency = profile.currency;
    final tr = AppLocalizations.of(context);

    final result = await showDialog<StoreProfile>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(tr.text('edit_store_profile')),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(controller: nameController, decoration: InputDecoration(labelText: tr.text('store_name'))),
                      const SizedBox(height: 12),
                      TextField(controller: phoneController, decoration: InputDecoration(labelText: tr.text('phone'))),
                      const SizedBox(height: 12),
                      TextField(controller: addressController, decoration: InputDecoration(labelText: tr.text('address'))),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: currency,
                        items: const [
                          DropdownMenuItem(value: 'USD', child: Text('USD')),
                          DropdownMenuItem(value: 'LBP', child: Text('LBP')),
                          DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                          DropdownMenuItem(value: 'AED', child: Text('AED')),
                          DropdownMenuItem(value: 'SAR', child: Text('SAR')),
                        ],
                        decoration: InputDecoration(labelText: tr.text('currency')),
                        onChanged: (value) => setState(() => currency = value ?? 'USD'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: footerController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(labelText: tr.text('invoice_footer')),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr.text('cancel'))),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      StoreProfile(
                        name: nameController.text.trim().isEmpty ? 'My Store' : nameController.text.trim(),
                        phone: phoneController.text.trim(),
                        address: addressController.text.trim(),
                        currency: currency,
                        footerNote: footerController.text.trim().isEmpty ? 'Thank you for shopping with us.' : footerController.text.trim(),
                      ),
                    );
                  },
                  child: Text(tr.text('save')),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      await store.updateStoreProfile(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('store_profile_updated'))));
      }
    }
  }



  Future<String?> _askPassword(BuildContext context, {required String title}) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password (min 6 characters)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(AppLocalizations.of(context).text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: Text(AppLocalizations.of(context).text('save'))),
        ],
      ),
    );
  }

  Future<void> _downloadBackupFile(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    final filename = 'store_backup_${DateTime.now().millisecondsSinceEpoch}.json';

    try {
      await downloadTextFile(filename: filename, content: store.exportBackupJson());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('backup_file_downloaded'))));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('backup_download_not_supported'))));
      }
    }
  }

  Future<void> _importBackupFile(BuildContext context) async {
    final tr = AppLocalizations.of(context);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('no_backup_file_selected'))));
        }
        return;
      }

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Empty backup file');
      }

      var raw = utf8.decode(bytes);
      if (raw.trim().startsWith('{') && raw.contains('store_manager_pro_encrypted_backup')) {
        if (!context.mounted) return;
        final password = await _askPassword(context, title: 'Backup password');
        if (password == null) return;
        if (!context.mounted) return;
        raw = store.decryptBackupJson(raw, password);
      }
      if (raw.trim().isEmpty) {
        throw Exception('Empty backup file');
      }

      final validation = store.validateBackupJson(raw);
      if (!validation.isValid || validation.summary == null) {
        throw Exception(validation.errorMessage ?? 'Invalid backup file');
      }

      if (!context.mounted) return;
      final confirmed = await _confirmBackupImport(context, validation.summary!);
      if (!context.mounted || confirmed != true) return;

      await store.importBackupJson(raw);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('backup_file_imported'))));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('backup_file_import_failed'))));
      }
    }
  }


  Future<void> _clearLocalData(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear Local Data'),
        content: const Text('This deletes only this Client device business data. Host data and other devices will not be affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Clear this device')),
        ],
      ),
    );
    if (confirmed != true) return;
    await store.clearLocalDeviceBusinessData();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Local Client data cleared. Rebuild from Host to restore current data.')));
    }
  }

  Future<void> _rebuildFromHost(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rebuild From Host'),
        content: const Text('This clears this Client device and downloads a fresh Host snapshot/events. Host data will not be changed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Rebuild')),
        ],
      ),
    );
    if (confirmed != true) return;

    final identity = store.appIdentity;
    String message;
    if (identity.syncMode == SyncMode.cloudConnected || identity.syncMode == SyncMode.marketplaceEnabled) {
      final result = await CloudSyncService(store).rebuildFromCloudHostSnapshot(CloudSyncSettings.load());
      message = result.message;
    } else {
      final settings = LanSyncSettings.load();
      final result = await LanSyncService(store).repairFromHostSnapshot(settings.host, port: settings.port, token: settings.secret);
      message = result.message;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _resetBusinessData(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('reset_all_data')),
        content: Text(tr.text('reset_all_data_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr.text('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr.text('reset')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final syncSettings = LanSyncSettings.load();
    if (!syncSettings.setupComplete || !syncSettings.isHost) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reset Data is allowed only on the Host device so it can be synced to all clients.')),
        );
      }
      return;
    }

    await store.resetBusinessData();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data reset on Host. Clients will reset automatically when they sync.')),
      );
    }
  }

  Future<bool?> _confirmBackupImport(BuildContext context, BackupSummary summary) async {
    final tr = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('confirm_backup_import')),
        content: SizedBox(
          width: 420,
          child: _BackupSummaryDetails(summary: summary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr.text('restore')),
          ),
        ],
      ),
    );
  }
}

class _BackupSummaryCard extends StatelessWidget {
  const _BackupSummaryCard({required this.summary});

  final BackupSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: _BackupSummaryDetails(summary: summary),
    );
  }
}

class _BackupSummaryDetails extends StatelessWidget {
  const _BackupSummaryDetails({required this.summary});

  final BackupSummary summary;

  String _formatDate(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr.text('current_backup_status'), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _Line(title: tr.text('store_name'), value: summary.storeName),
        _Line(title: tr.text('backup_version'), value: 'V${summary.version}'),
        _Line(title: tr.text('backup_date'), value: _formatDate(summary.generatedAt)),
        _Line(title: tr.text('products'), value: summary.productsCount.toString()),
        _Line(title: tr.text('customers'), value: summary.customersCount.toString()),
        _Line(title: tr.text('sales'), value: summary.salesCount.toString()),
        _Line(title: tr.text('suppliers'), value: summary.suppliersCount.toString()),
        _Line(title: tr.text('expenses'), value: summary.expensesCount.toString()),
      ],
    );
  }
}


































class _UnifiedSyncSettingsCard extends StatefulWidget {
  const _UnifiedSyncSettingsCard({required this.store, this.onSyncSettingsChanged});

  final AppStore store;
  final Future<void> Function()? onSyncSettingsChanged;

  @override
  State<_UnifiedSyncSettingsCard> createState() => _UnifiedSyncSettingsCardState();
}

class _UnifiedSyncSettingsCardState extends State<_UnifiedSyncSettingsCard> {
  final _lanHostController = TextEditingController();
  final _lanPortController = TextEditingController();
  final _lanTokenController = TextEditingController();
  final _cloudApiController = TextEditingController();
  final _cloudTokenController = TextEditingController();
  final _cloudPairingCodeController = TextEditingController();
  final _cloudIntervalController = TextEditingController();
  DeviceRole _deviceRole = DeviceRole.host;
  SyncMode _clientSyncMode = SyncMode.lanOnly;
  bool _lanEnabledForHost = false;
  bool _cloudEnabled = false;
  bool _busy = false;
  String _status = '';
  List<String> _hostIpAddresses = const <String>[];
  bool _detectingHostIp = false;

  @override
  void initState() {
    super.initState();
    final identity = widget.store.appIdentity;
    final lan = LanSyncSettings.load();
    final cloud = CloudSyncSettings.load();
    _deviceRole = identity.isClient ? DeviceRole.client : DeviceRole.host;
    _clientSyncMode = identity.isCloudEnabled ? SyncMode.cloudConnected : SyncMode.lanOnly;
    _lanEnabledForHost = identity.isHost && lan.setupComplete && lan.isHost;
    _cloudEnabled = identity.isCloudEnabled && cloud.isConfigured;
    _lanHostController.text = lan.host;
    _lanPortController.text = lan.port.toString();
    _lanTokenController.text = lan.secret.trim().isNotEmpty ? lan.secret : LanSyncSettings.generateSecret();
    _cloudApiController.text = cloud.apiBaseUrl;
    _cloudTokenController.text = cloud.apiToken;
    _cloudIntervalController.text = cloud.intervalSeconds.toString();
    _refreshHostIpAddresses();
  }

  @override
  void dispose() {
    _lanHostController.dispose();
    _lanPortController.dispose();
    _lanTokenController.dispose();
    _cloudApiController.dispose();
    _cloudTokenController.dispose();
    _cloudPairingCodeController.dispose();
    _cloudIntervalController.dispose();
    super.dispose();
  }

  int get _lanPort => int.tryParse(_lanPortController.text.trim()) ?? 8787;
  int get _cloudInterval => int.tryParse(_cloudIntervalController.text.trim())?.clamp(30, 3600).toInt() ?? 30;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Working...';
    });
    try {
      await action();
      await widget.onSyncSettingsChanged?.call();
    } catch (error) {
      if (mounted) setState(() => _status = 'Failed: $error');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  CloudSyncSettings _cloudSettings({bool enabled = true}) => CloudSyncSettings.load().copyWith(
        enabled: enabled,
        apiBaseUrl: _cloudApiController.text.trim().isEmpty ? (kIsWeb ? Uri.base.origin : '') : _cloudApiController.text.trim(),
        apiToken: _cloudTokenController.text.trim(),
        autoSyncEnabled: enabled,
        intervalSeconds: _cloudInterval,
      );

  Future<void> _refreshHostIpAddresses() async {
    if (_detectingHostIp) return;
    if (mounted) setState(() => _detectingHostIp = true);
    try {
      final addresses = await LanSyncSettings.localIpv4Addresses();
      if (!mounted) return;
      setState(() {
        _hostIpAddresses = addresses;
        if (_deviceRole == DeviceRole.host && addresses.isNotEmpty) {
          _lanHostController.text = addresses.first;
        }
      });
    } finally {
      if (mounted) setState(() => _detectingHostIp = false);
    }
  }

  void _generateLanToken() {
    setState(() {
      _lanTokenController.text = LanSyncSettings.generateSecret();
      _status = 'New LAN pairing token generated. Save Host Settings to apply it.';
    });
  }

  Future<void> _createCloudPairingCode() => _run(() async {
        await _saveCloudSettingsForPairing();
        final result = await CloudSyncService(widget.store).createPairingCode(_cloudSettings(enabled: true));
        if (!result.ok) throw StateError(result.message);
        final expiry = result.expiresAt == null ? '' : ' • Expires: ${result.expiresAt!.toLocal()}';
        setState(() => _status = 'Cloud pairing code: ${result.code}$expiry');
      });

  Future<void> _saveCloudSettingsForPairing() async {
    final identity = widget.store.appIdentity;
    await widget.store.updateAppIdentity(identity.copyWith(
      deviceRole: DeviceRole.host,
      syncMode: SyncMode.cloudConnected,
    ));
    await _cloudSettings(enabled: true).save();
  }

  Future<void> _saveHostMode() => _run(() async {
        final identity = widget.store.appIdentity;
        final lanSecret = _lanTokenController.text.trim().isEmpty ? LanSyncSettings.generateSecret() : _lanTokenController.text.trim();
        await widget.store.updateAppIdentity(identity.copyWith(
          deviceRole: DeviceRole.host,
          syncMode: _cloudEnabled ? SyncMode.cloudConnected : (_lanEnabledForHost ? SyncMode.lanOnly : SyncMode.localOnly),
        ));
        await LanSyncSettings(
          host: _lanHostController.text.trim().isEmpty ? LanSyncSettings.load().host : _lanHostController.text.trim(),
          port: _lanPort,
          autoSyncEnabled: _lanEnabledForHost,
          hostModeEnabled: _lanEnabledForHost,
          setupComplete: _lanEnabledForHost,
          mode: _lanEnabledForHost ? LanSyncDeviceMode.host : LanSyncDeviceMode.unconfigured,
          secret: lanSecret,
        ).save();
        await _cloudSettings(enabled: _cloudEnabled).save();
        setState(() => _status = 'Host sync settings saved.');
      });

  Future<void> _saveLanClient() => _run(() async {
        final identity = widget.store.appIdentity;
        final secret = _lanTokenController.text.trim();
        final result = await LanSyncService(widget.store).initialClone(_lanHostController.text.trim(), port: _lanPort, token: secret);
        if (!result.ok) throw StateError(result.message);
        await LanSyncSettings(
          host: _lanHostController.text.trim(),
          port: _lanPort,
          autoSyncEnabled: true,
          hostModeEnabled: false,
          setupComplete: true,
          mode: LanSyncDeviceMode.client,
          secret: secret,
          lastConnectionAt: DateTime.now(),
          lastSyncAt: DateTime.now(),
        ).save();
        await CloudSyncSettings.load().copyWith(autoSyncEnabled: false, clearLastPullCursor: true).save();
        await widget.store.updateAppIdentity(identity.copyWith(deviceRole: DeviceRole.client, syncMode: SyncMode.lanOnly));
        setState(() => _status = 'LAN Client connected and cloned from Host.');
      });

  Future<void> _claimCloudPairing() => _run(() async {
        await _cloudSettings(enabled: true).save();
        await LanSyncSettings.load().copyWith(autoSyncEnabled: false, setupComplete: false, mode: LanSyncDeviceMode.unconfigured, hostModeEnabled: false, clearLastPullCursor: true).save();
        final result = await CloudSyncService(widget.store).claimPairingCode(_cloudSettings(enabled: true), _cloudPairingCodeController.text.trim());
        if (!result.ok) throw StateError(result.message);
        setState(() => _status = result.message);
      });

  Future<void> _syncNow() => _run(() async {
        final identity = widget.store.appIdentity;
        if (identity.isCloudEnabled) {
          final result = await CloudSyncService(widget.store).syncNow(_cloudSettings(enabled: true));
          if (!result.ok) throw StateError(result.message);
          setState(() => _status = result.message);
        } else if (identity.syncMode == SyncMode.lanOnly) {
          final lan = LanSyncSettings.load();
          final result = await LanSyncService(widget.store).syncNow(lan.host, port: lan.port, token: lan.secret);
          if (!result.ok) throw StateError(result.message);
          setState(() => _status = result.message);
        } else {
          setState(() => _status = 'No sync mode is enabled.');
        }
      });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final isHost = _deviceRole == DeviceRole.host;
    final isCloudClient = !isHost && _clientSyncMode == SyncMode.cloudConnected;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sync_alt_outlined),
              title: const Text('Sync Settings'),
              subtitle: const Text('Choose the device type first. Only the required settings are shown.'),
            ),
            const SizedBox(height: 8),
            SegmentedButton<DeviceRole>(
              segments: const [
                ButtonSegment<DeviceRole>(value: DeviceRole.host, icon: Icon(Icons.desktop_windows_outlined), label: Text('Host')),
                ButtonSegment<DeviceRole>(value: DeviceRole.client, icon: Icon(Icons.devices_other_outlined), label: Text('Client')),
              ],
              selected: {_deviceRole},
              onSelectionChanged: _busy ? null : (value) => setState(() => _deviceRole = value.first),
            ),
            const SizedBox(height: 16),
            if (isHost) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('LAN Sync'),
                subtitle: const Text('Allow nearby devices on the same network to connect to this Host.'),
                value: _lanEnabledForHost,
                onChanged: _busy ? null : (value) => setState(() => _lanEnabledForHost = value),
              ),
              if (_lanEnabledForHost) ...[
                _hostIpInfoCard(),
                ..._lanFields(showHostIp: false),
              ],
              const Divider(height: 28),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Cloud Sync'),
                subtitle: const Text('Allow remote devices to sync through the cloud.'),
                value: _cloudEnabled,
                onChanged: _busy ? null : (value) => setState(() => _cloudEnabled = value),
              ),
              if (_cloudEnabled) ...[
                ..._cloudFields(showPairingCode: false),
                SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _busy ? null : _createCloudPairingCode, icon: const Icon(Icons.qr_code_2_outlined), label: const Text('Generate Cloud Pairing Code'))),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _saveHostMode, icon: const Icon(Icons.save_outlined), label: const Text('Save Host Settings'))),
            ] else ...[
              const Text('Client Sync Type'),
              const SizedBox(height: 8),
              SegmentedButton<SyncMode>(
                segments: const [
                  ButtonSegment<SyncMode>(value: SyncMode.lanOnly, icon: Icon(Icons.wifi_tethering_outlined), label: Text('LAN')),
                  ButtonSegment<SyncMode>(value: SyncMode.cloudConnected, icon: Icon(Icons.cloud_outlined), label: Text('Cloud')),
                ],
                selected: {_clientSyncMode},
                onSelectionChanged: _busy ? null : (value) => setState(() => _clientSyncMode = value.first),
              ),
              const SizedBox(height: 16),
              if (!isCloudClient) ...[
                ..._lanFields(showHostIp: true),
                SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _saveLanClient, icon: const Icon(Icons.link_outlined), label: const Text('Connect to LAN Host'))),
              ] else ...[
                ..._cloudFields(showPairingCode: true),
                SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _claimCloudPairing, icon: const Icon(Icons.cloud_done_outlined), label: const Text('Pair with Cloud Host'))),
              ],
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _busy ? null : _syncNow, icon: const Icon(Icons.sync_outlined), label: const Text('Sync Now')),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
              child: Text(_busy ? 'Working...' : (_status.isEmpty ? _humanStatus : _status)),
            ),
          ],
        ),
      ),
    );
  }

  String get _humanStatus {
    final identity = widget.store.appIdentity;
    if (identity.isHost) {
      final lan = LanSyncSettings.load();
      final cloud = CloudSyncSettings.load();
      return 'Host • LAN: ${lan.setupComplete && lan.isHost ? 'Enabled' : 'Disabled'} • Cloud: ${identity.isCloudEnabled && cloud.isConfigured ? 'Enabled' : 'Disabled'}';
    }
    return 'Client • ${identity.syncMode == SyncMode.cloudConnected ? 'Cloud' : identity.syncMode == SyncMode.lanOnly ? 'LAN' : 'Local'}';
  }

  Widget _hostIpInfoCard() {
    final ipText = _detectingHostIp
        ? 'Detecting local IP...'
        : (_hostIpAddresses.isEmpty ? 'No local IPv4 address detected yet.' : _hostIpAddresses.join('  •  '));
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lan_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Host IP Address', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(ipText),
                const SizedBox(height: 4),
                const Text('Use this IP from LAN Clients if automatic discovery does not find the Host.'),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh IP',
            onPressed: _busy || _detectingHostIp ? null : _refreshHostIpAddresses,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
    );
  }

  List<Widget> _lanFields({required bool showHostIp}) => [
        if (showHostIp)
          TextField(controller: _lanHostController, decoration: const InputDecoration(labelText: 'Manual Host IP (optional)', border: OutlineInputBorder())),
        if (showHostIp) const SizedBox(height: 12),
        TextField(controller: _lanPortController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(
          controller: _lanTokenController,
          decoration: InputDecoration(
            labelText: 'Pairing Token',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'Generate token',
              onPressed: _busy ? null : _generateLanToken,
              icon: const Icon(Icons.refresh_outlined),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ];

  List<Widget> _cloudFields({required bool showPairingCode}) => [
        TextField(controller: _cloudApiController, decoration: const InputDecoration(labelText: 'Cloud API URL', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _cloudTokenController, obscureText: true, decoration: const InputDecoration(labelText: 'Cloud sync token', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _cloudIntervalController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Auto sync interval seconds', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        if (showPairingCode) TextField(controller: _cloudPairingCodeController, decoration: const InputDecoration(labelText: 'Pairing code from Host', border: OutlineInputBorder())),
        if (showPairingCode) const SizedBox(height: 12),
      ];
}

class _AdvancedSyncDebugCard extends StatelessWidget {
  const _AdvancedSyncDebugCard({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.bug_report_outlined),
        title: const Text('Advanced / Debug Information'),
        subtitle: const Text('Technical sync details are hidden by default.'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _Line(title: 'Device ID', value: store.deviceId),
          _Line(title: 'Store ID', value: store.appIdentity.storeId),
          _Line(title: 'Branch ID', value: store.appIdentity.branchId),
          _Line(title: 'Role', value: store.appIdentity.deviceRole.name),
          _Line(title: 'Sync Mode', value: store.appIdentity.syncMode.name),
          _Line(title: 'Pending Changes', value: '${store.pendingSyncCount}'),
          _Line(title: 'Pending Queue', value: '${store.pendingSyncQueueCount}'),
        ],
      ),
    );
  }
}


class _Line extends StatelessWidget {
  const _Line({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(title)),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.titleSmall)),
        ],
      ),
    );
  }
}


class _SystemIdentityCard extends StatelessWidget {
  const _SystemIdentityCard({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final identity = store.appIdentity;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.hub_outlined),
              title: Text(tr.text('system_foundation')),
              subtitle: Text(tr.text('system_foundation_desc')),
              trailing: const Chip(label: Text('Read only')),
            ),
            const Divider(height: 24),
            _Line(title: tr.text('store_id'), value: identity.storeId),
            _Line(title: tr.text('branch_id'), value: identity.branchId),
            _Line(title: tr.text('device_id'), value: identity.deviceId),
            _Line(title: tr.text('platform'), value: identity.platform.name),
            _Line(title: tr.text('device_role'), value: identity.deviceRole.name),
            _Line(title: tr.text('app_role'), value: identity.appRole.name),
            _Line(title: tr.text('sync_mode'), value: identity.isHost ? 'Host: LAN and Cloud are controlled from Sync page' : identity.syncMode.name),
            _Line(title: tr.text('cloud_tenant'), value: identity.cloudTenantId.isEmpty ? '—' : identity.cloudTenantId),
          ],
        ),
      ),
    );
  }

}
