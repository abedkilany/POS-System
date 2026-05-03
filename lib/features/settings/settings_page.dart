import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/backup_download_service.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/services/lan_sync_service.dart';
import '../../core/services/local_database_service.dart';

import '../../core/localization/app_localizations.dart';
import '../../data/app_store.dart';
import '../../models/store_profile.dart';
import '../../models/app_identity.dart';
import '../../models/user_role.dart';
import 'users_permissions_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.onLocaleChanged, required this.store});

  final ValueChanged<Locale> onLocaleChanged;
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final profile = store.storeProfile;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
                  trailing: FilledButton.icon(
                    onPressed: () => _editStoreProfile(context, profile),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(tr.text('edit')),
                  ),
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
        const SizedBox(height: 12),
        _SystemIdentityCard(store: store),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.people),
            title: Text(tr.text('users_permissions')),
            subtitle: Text("Signed in as ${store.activeUser?.fullName ?? 'Unknown'} • Role: ${store.currentRole}"),
            trailing: FilledButton.icon(
              onPressed: store.canManageUsers
                  ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => UsersPermissionsPage(store: store)))
                  : null,
              icon: const Icon(Icons.manage_accounts_outlined),
              label: const Text('Manage'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(tr.text('security_pin')),
            subtitle: Text(store.isPinEnabled ? tr.text('security_pin_enabled') : tr.text('security_pin_disabled')),
            trailing: FilledButton.icon(
              onPressed: () => _manageSecurityPin(context),
              icon: Icon(store.isPinEnabled ? Icons.lock_reset : Icons.password_outlined),
              label: Text(store.isPinEnabled ? tr.text('change_pin') : tr.text('enable_pin')),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _LanSyncCard(store: store),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.backup_outlined),
                  title: Text(tr.text('backup_restore')),
                  subtitle: Text(tr.text('backup_preview_desc')),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Chip(
                      avatar: Icon(Icons.storage_outlined, size: 18),
                      label: Text('Local DB: Hive'),
                    ),
                  ),
                ),
                _BackupSummaryCard(summary: store.currentBackupSummary),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _downloadBackupFile(context),
                      icon: const Icon(Icons.download_outlined),
                      label: Text(tr.text('download_backup_file')),
                    ),
                    FilledButton.icon(
                      onPressed: () => _downloadEncryptedBackupFile(context),
                      icon: const Icon(Icons.enhanced_encryption_outlined),
                      label: const Text('Encrypted backup'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _previewBackup(context),
                      icon: const Icon(Icons.visibility_outlined),
                      label: Text(tr.text('preview_backup_json')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _copyBackup(context),
                      icon: const Icon(Icons.copy_all_outlined),
                      label: Text(tr.text('copy_backup_json')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _importBackupFile(context),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text(tr.text('import_backup_file')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _restoreBackup(context),
                      icon: const Icon(Icons.settings_backup_restore_outlined),
                      label: Text(tr.text('restore_backup')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.warning_amber_outlined, color: Theme.of(context).colorScheme.error),
                  title: Text(tr.text('data_management')),
                  subtitle: Text(tr.text('data_management_desc')),
                  trailing: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                    onPressed: () => _resetBusinessData(context),
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: Text(tr.text('reset_all_data')),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr.text('language'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton(onPressed: () => onLocaleChanged(const Locale('en')), child: const Text('English')),
                    OutlinedButton(onPressed: () => onLocaleChanged(const Locale('ar')), child: const Text('العربية')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }


  Future<void> _manageSecurityPin(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    final controller = TextEditingController();
    final confirmController = TextEditingController();

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('security_pin')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr.text('pin_help')),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: true,
                maxLength: 8,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr.text('new_pin'), counterText: ''),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                obscureText: true,
                maxLength: 8,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr.text('confirm_pin'), counterText: ''),
              ),
            ],
          ),
        ),
        actions: [
          if (store.isPinEnabled)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'clear'),
              child: Text(tr.text('disable_pin')),
            ),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr.text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, 'save'), child: Text(tr.text('save'))),
        ],
      ),
    );

    if (action == null) return;

    try {
      if (action == 'clear') {
        await store.clearSecurityPin();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('pin_disabled'))));
        }
        return;
      }

      final pin = controller.text.trim();
      if (pin != confirmController.text.trim()) {
        throw ArgumentError('PIN mismatch');
      }
      await store.setSecurityPin(pin);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('pin_enabled'))));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('pin_invalid'))));
      }
    }
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
                        value: currency,
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



  Future<void> _downloadEncryptedBackupFile(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    final password = await _askPassword(context, title: 'Backup password');
    if (password == null) return;
    final filename = 'store_backup_encrypted_${DateTime.now().millisecondsSinceEpoch}.json';

    try {
      await downloadTextFile(filename: filename, content: store.exportEncryptedBackupJson(password));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Encrypted backup file downloaded')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('backup_download_not_supported'))));
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

  Future<void> _previewBackup(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    final prettyJson = const JsonEncoder.withIndent('  ').convert(jsonDecode(store.exportBackupJson()));

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('backup_json_preview')),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: SelectableText(prettyJson),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr.text('close'))),
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
        final password = await _askPassword(context, title: 'Backup password');
        if (password == null) return;
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
      if (confirmed != true) return;

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

  Future<void> _copyBackup(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: store.exportBackupJson()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).text('backup_copied'))));
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

  Future<void> _restoreBackup(BuildContext context) async {
    final controller = TextEditingController();
    final tr = AppLocalizations.of(context);
    final raw = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('restore_backup')),
        content: SizedBox(
          width: 620,
          child: TextField(
            controller: controller,
            minLines: 12,
            maxLines: 20,
            decoration: InputDecoration(
              hintText: tr.text('paste_backup_here'),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr.text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: Text(tr.text('restore'))),
        ],
      ),
    );

    if (raw == null || raw.trim().isEmpty) return;

    try {
      final validation = store.validateBackupJson(raw);
      if (!validation.isValid || validation.summary == null) {
        throw Exception(validation.errorMessage ?? 'Invalid backup JSON');
      }

      final confirmed = await _confirmBackupImport(context, validation.summary!);
      if (confirmed != true) return;

      await store.importBackupJson(raw);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('backup_restored'))));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('backup_restore_failed'))));
      }
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.35),
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
    final two = (int n) => n.toString().padLeft(2, '0');
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


class _LanSyncCard extends StatefulWidget {
  const _LanSyncCard({required this.store});

  final AppStore store;

  @override
  State<_LanSyncCard> createState() => _LanSyncCardState();
}

class _LanSyncCardState extends State<_LanSyncCard> {
  late final LanSyncService _syncService;
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _cloudApiController = TextEditingController();
  final TextEditingController _cloudTokenController = TextEditingController();
  String _status = 'Ready';
  bool _busy = false;
  bool _autoSyncEnabled = false;
  bool _hostModeEnabled = false;
  bool _cloudAutoSyncEnabled = true;
  DateTime? _lastConnectionAt;
  DateTime? _lastSyncAt;

  @override
  void initState() {
    super.initState();
    _syncService = LanSyncService(widget.store);
    final settings = LanSyncSettings.load();
    _hostController.text = settings.host;
    _portController.text = settings.port.toString();
    _tokenController.text = settings.secret;
    final cloudSettings = CloudSyncSettings.load();
    _cloudApiController.text = cloudSettings.apiBaseUrl.isEmpty ? Uri.base.origin : cloudSettings.apiBaseUrl;
    _cloudTokenController.text = cloudSettings.apiToken;
    _cloudAutoSyncEnabled = cloudSettings.autoSyncEnabled;
    _autoSyncEnabled = settings.autoSyncEnabled;
    _hostModeEnabled = settings.hostModeEnabled;
    _lastConnectionAt = settings.lastConnectionAt;
    _lastSyncAt = settings.lastSyncAt;
    if (_hostModeEnabled) {
      _syncService.startHost(port: settings.port).then((_) {
        if (mounted) setState(() => _status = 'Host running on port ${settings.port}');
      }).catchError((error) {
        if (mounted) setState(() => _status = 'Host start failed: $error');
      });
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    _cloudApiController.dispose();
    _cloudTokenController.dispose();
    super.dispose();
  }

  int get _port => int.tryParse(_portController.text.trim()) ?? 8787;


  CloudSyncSettings get _cloudSettings {
    final loaded = CloudSyncSettings.load();
    return loaded.copyWith(
      enabled: true,
      apiBaseUrl: _cloudApiController.text.trim().isEmpty ? Uri.base.origin : _cloudApiController.text.trim(),
      apiToken: _cloudTokenController.text.trim(),
      autoSyncEnabled: _cloudAutoSyncEnabled,
    );
  }

  Future<void> _saveCloudSettings() async {
    await _cloudSettings.save();
    final identity = widget.store.appIdentity;
    if (identity.syncMode != SyncMode.cloudConnected || identity.deviceRole != DeviceRole.client) {
      await widget.store.updateAppIdentity(identity.copyWith(syncMode: SyncMode.cloudConnected, deviceRole: DeviceRole.client));
    }
  }

  Future<void> _saveSettings({DateTime? lastConnectionAt, DateTime? lastSyncAt}) async {
    final settings = LanSyncSettings(
      host: _hostController.text.trim().isEmpty ? '192.168.1.100' : _hostController.text.trim(),
      port: _port,
      autoSyncEnabled: _autoSyncEnabled,
      hostModeEnabled: _hostModeEnabled,
      setupComplete: true,
      mode: _hostModeEnabled ? LanSyncDeviceMode.host : LanSyncDeviceMode.client,
      secret: _tokenController.text.trim(),
      lastConnectionAt: lastConnectionAt ?? _lastConnectionAt,
      lastSyncAt: lastSyncAt ?? _lastSyncAt,
    );
    await settings.save();
    final identity = widget.store.appIdentity;
    final desiredRole = _hostModeEnabled ? DeviceRole.host : DeviceRole.client;
    final desiredSyncMode = identity.syncMode == SyncMode.localOnly ? SyncMode.lanOnly : identity.syncMode;
    if (identity.deviceRole != desiredRole || identity.syncMode != desiredSyncMode) {
      await widget.store.updateAppIdentity(identity.copyWith(deviceRole: desiredRole, syncMode: desiredSyncMode));
    }
    _lastConnectionAt = settings.lastConnectionAt;
    _lastSyncAt = settings.lastSyncAt;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;

    if (kIsWeb) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cloud_sync_outlined),
                title: const Text('Cloud sync / مزامنة سحابية'),
                subtitle: const Text('Web build uses Cloud API + Neon. LAN Host/Client is Desktop only.'),
                trailing: const Chip(label: Text('Web mode')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _cloudApiController,
                decoration: const InputDecoration(
                  labelText: 'Cloud API URL',
                  helperText: 'On Vercel this is usually the current site URL.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cloudTokenController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Cloud sync token',
                  helperText: 'Use the same value as CLOUD_SYNC_TOKEN in Vercel. Required for cloud sync.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto cloud sync'),
                subtitle: const Text('Automatically pushes and pulls cloud changes about every 30 seconds when token is configured.'),
                value: _cloudAutoSyncEnabled,
                onChanged: _busy ? null : (value) => setState(() => _cloudAutoSyncEnabled = value),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  Chip(label: Text("Cloud queue: ${widget.store.pendingSyncQueueForTarget('cloud', readyOnly: false).length}")),
                  Chip(label: Text('Device: ${widget.store.deviceId}')),
                  Chip(label: Text('Store: ${widget.store.appIdentity.storeId}')),
                  Chip(label: Text("Cursor: ${CloudSyncSettings.load().lastPullCursor?.toLocal().toString().split('.').first ?? 'first pull'}")),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              await _saveCloudSettings();
                              setState(() => _status = 'Cloud settings saved.');
                            }),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save cloud settings'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              await _saveCloudSettings();
                              final result = await CloudSyncService(widget.store).testConnection(_cloudSettings);
                              setState(() => _status = result.message);
                            }),
                    icon: const Icon(Icons.network_check_outlined),
                    label: const Text('Test API'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              await _saveCloudSettings();
                              final result = await CloudSyncService(widget.store).syncNow(_cloudSettings);
                              setState(() => _status = result.message);
                            }),
                    icon: const Icon(Icons.cloud_sync_outlined),
                    label: const Text('Sync now'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              await widget.store.retryFailedSyncQueue(target: 'cloud');
                              setState(() => _status = 'Failed cloud queue items are pending again.');
                            }),
                    icon: const Icon(Icons.replay_outlined),
                    label: const Text('Retry cloud queue'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_status),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sync_alt_outlined),
              title: Text(tr.text('lan_sync')),
              subtitle: Text(tr.text('lan_sync_desc')),
              trailing: Chip(
                avatar: Icon(_hostModeEnabled ? Icons.wifi_tethering : Icons.devices_other, size: 18),
                label: Text(_hostModeEnabled ? tr.text('host_mode') : tr.text('client_mode')),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                Chip(label: Text('${tr.text('device_id')}: ${widget.store.deviceId}')),
                Chip(label: Text('${tr.text('pending_changes')}: ${widget.store.pendingSyncCount}')),
                Chip(label: Text('Queue: ${widget.store.pendingSyncQueueCount}')),
                Chip(label: Text("Host queue: ${widget.store.pendingSyncQueueForTarget('host', readyOnly: false).length}")),
                if (_lastConnectionAt != null) Chip(label: Text('${tr.text('last_connection')}: ${_lastConnectionAt!.toLocal()}')),
                if (_lastSyncAt != null) Chip(label: Text('${tr.text('last_sync')}: ${_lastSyncAt!.toLocal()}')),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr.text('auto_sync')),
              subtitle: Text(tr.text('auto_sync_desc')),
              value: _autoSyncEnabled,
              onChanged: (value) => setState(() => _autoSyncEnabled = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr.text('host_mode')),
              subtitle: Text(tr.text('host_mode_desc')),
              value: _hostModeEnabled,
              onChanged: (value) => setState(() => _hostModeEnabled = value),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _hostController,
                    decoration: InputDecoration(labelText: tr.text('host_ip'), border: const OutlineInputBorder()),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: tr.text('port'), border: const OutlineInputBorder()),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _tokenController,
                    decoration: const InputDecoration(labelText: 'Pairing token', border: OutlineInputBorder()),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            await _saveSettings();
                            setState(() => _status = tr.text('settings_saved'));
                          }),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(tr.text('save_settings')),
                ),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            if (_syncService.isHosting) {
                              await _syncService.stopHost();
                              _hostModeEnabled = false;
                              await _saveSettings();
                              setState(() => _status = tr.text('host_stopped'));
                            } else {
                              await _syncService.startHost(port: _port);
                              _hostModeEnabled = true;
                              await _saveSettings();
                              setState(() => _status = '${tr.text('host_started')} ${_port}');
                            }
                          }),
                  icon: Icon(_syncService.isHosting ? Icons.stop_circle_outlined : Icons.wifi_tethering),
                  label: Text(_syncService.isHosting ? tr.text('stop_host') : tr.text('start_host')),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            await _saveSettings();
                            final result = await _syncService.testConnection(_hostController.text, port: _port, token: _tokenController.text.trim());
                            if (result.ok) {
                              _lastConnectionAt = DateTime.now();
                              await _saveSettings(lastConnectionAt: _lastConnectionAt);
                            }
                            setState(() => _status = result.message);
                          }),
                  icon: const Icon(Icons.network_check_outlined),
                  label: Text(tr.text('test_connection')),
                ),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            await _saveSettings();
                            final result = await _syncService.syncNow(_hostController.text, port: _port, token: _tokenController.text.trim());
                            if (result.ok) {
                              _lastConnectionAt = DateTime.now();
                              _lastSyncAt = DateTime.now();
                              await _saveSettings(lastConnectionAt: _lastConnectionAt, lastSyncAt: _lastSyncAt);
                            }
                            setState(() => _status = result.message);
                          }),
                  icon: const Icon(Icons.sync_outlined),
                  label: Text(tr.text('sync_now')),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            await widget.store.retryFailedSyncQueue(target: _hostModeEnabled ? null : 'host');
                            setState(() => _status = 'Failed queue items are pending again.');
                          }),
                  icon: const Icon(Icons.replay_outlined),
                  label: const Text('Retry failed queue'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Reset sync setup'),
                                    content: const Text('This will only reset Host/Client sync setup. Business data will stay on this device. Restart the app to see the setup screen again.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                                      FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Reset')),
                                    ],
                                  ),
                                ) ??
                                false;
                            if (!confirm) return;
                            await _syncService.stopHost();
                            await LanSyncSettings.resetSetup();
                            _autoSyncEnabled = true;
                            _hostModeEnabled = false;
                            _lastConnectionAt = null;
                            _lastSyncAt = null;
                            setState(() => _status = 'Sync setup was reset. Restart the app to choose Host or Client again.');
                          }),
                  icon: const Icon(Icons.restart_alt_outlined),
                  label: const Text('Reset sync setup'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_busy ? tr.text('working') : _status),
            ),
            const SizedBox(height: 8),
            Text(tr.text('lan_sync_alpha_note'), style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
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
              title: const Text('System foundation'),
              subtitle: const Text('Store, branch, device role, app role, and sync mode.'),
              trailing: FilledButton.icon(
                onPressed: store.hasPermission(AppPermission.settingsManage) ? () => _editIdentity(context, store) : null,
                icon: const Icon(Icons.tune_outlined),
                label: const Text('Configure'),
              ),
            ),
            const Divider(height: 24),
            _Line(title: 'Store ID', value: identity.storeId),
            _Line(title: 'Branch ID', value: identity.branchId),
            _Line(title: 'Device ID', value: identity.deviceId),
            _Line(title: 'Platform', value: identity.platform.name),
            _Line(title: 'Device role', value: identity.deviceRole.name),
            _Line(title: 'App role', value: identity.appRole.name),
            _Line(title: 'Sync mode', value: identity.syncMode.name),
            _Line(title: 'Cloud tenant', value: identity.cloudTenantId.isEmpty ? '—' : identity.cloudTenantId),
          ],
        ),
      ),
    );
  }

  Future<void> _editIdentity(BuildContext context, AppStore store) async {
    final current = store.appIdentity;
    final storeIdController = TextEditingController(text: current.storeId);
    final branchIdController = TextEditingController(text: current.branchId);
    final deviceNameController = TextEditingController(text: current.deviceName);
    final cloudTenantController = TextEditingController(text: current.cloudTenantId);
    var deviceRole = current.deviceRole;
    var appRole = current.appRole;
    var syncMode = current.syncMode;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Configure system foundation'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: storeIdController, decoration: const InputDecoration(labelText: 'Store ID')),
                  TextField(controller: branchIdController, decoration: const InputDecoration(labelText: 'Branch ID')),
                  TextField(controller: deviceNameController, decoration: const InputDecoration(labelText: 'Device name')),
                  TextField(controller: cloudTenantController, decoration: const InputDecoration(labelText: 'Cloud tenant ID / future Neon tenant')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<DeviceRole>(
                    value: deviceRole,
                    decoration: const InputDecoration(labelText: 'Device role'),
                    items: DeviceRole.values.map((item) => DropdownMenuItem(value: item, child: Text(item.name))).toList(),
                    onChanged: (value) => setState(() => deviceRole = value ?? deviceRole),
                  ),
                  DropdownButtonFormField<AppRole>(
                    value: appRole,
                    decoration: const InputDecoration(labelText: 'App role'),
                    items: AppRole.values.map((item) => DropdownMenuItem(value: item, child: Text(item.name))).toList(),
                    onChanged: (value) => setState(() => appRole = value ?? appRole),
                  ),
                  DropdownButtonFormField<SyncMode>(
                    value: syncMode,
                    decoration: const InputDecoration(labelText: 'Sync mode'),
                    items: SyncMode.values.map((item) => DropdownMenuItem(value: item, child: Text(item.name))).toList(),
                    onChanged: (value) => setState(() => syncMode = value ?? syncMode),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved != true || !context.mounted) return;
    await store.updateAppIdentity(current.copyWith(
      storeId: storeIdController.text.trim().isEmpty ? current.storeId : storeIdController.text.trim(),
      branchId: branchIdController.text.trim().isEmpty ? 'main' : branchIdController.text.trim(),
      deviceName: deviceNameController.text.trim(),
      cloudTenantId: cloudTenantController.text.trim(),
      deviceRole: deviceRole,
      appRole: appRole,
      syncMode: syncMode,
    ));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('System foundation updated.')));
    }
  }
}
