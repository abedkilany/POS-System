import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services/backup_download_service.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/services/lan_sync_service.dart';
import '../../core/services/local_database_service.dart';
import '../../core/sync_unified/sync_unified.dart';

import '../../core/localization/app_localizations.dart';
import '../../data/app_store.dart';
import '../../models/store_profile.dart';
import '../../models/app_identity.dart';
import '../barcode/barcode_scanner_page.dart';
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
                child: OutlinedButton.icon(
                  onPressed: () => _recoverExistingStore(context),
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Recover Existing Store'),
                ),
              ),
              const SizedBox(height: 8),
              if (!store.appIdentity.isClient) ...[
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
    if (store.appIdentity.isClient) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import Backup is only available on the Host device.')));
      return;
    }

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
        await _pushHostCriticalEventToCloud(context, 'Import Backup');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('backup_file_import_failed'))));
      }
    }
  }



  Future<void> _recoverExistingStore(BuildContext context) async {
    final cloud = CloudSyncSettings.load();
    final apiUrlController = TextEditingController(text: cloud.apiBaseUrl);
    final storeIdController = TextEditingController(text: store.appIdentity.storeId);
    final branchIdController = TextEditingController();
    final recoveryKeyController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var canRecover = false;
        void refresh(StateSetter setState) {
          setState(() => canRecover = apiUrlController.text.trim().isNotEmpty && storeIdController.text.trim().isNotEmpty && recoveryKeyController.text.trim().isNotEmpty);
        }
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Recover Existing Store'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Enter the Cloud API URL, official Store ID, and Recovery Key. This device will recover the permanent store identity and download the latest Cloud snapshot.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: apiUrlController,
                    decoration: const InputDecoration(labelText: 'Cloud API URL', hintText: 'https://your-cloud-api.vercel.app', border: OutlineInputBorder()),
                    onChanged: (_) => refresh(setState),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: storeIdController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Store ID', hintText: 'ST-XXXXXX', border: OutlineInputBorder()),
                    onChanged: (_) => refresh(setState),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: branchIdController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Branch ID (optional)', hintText: 'Leave blank to recover the latest branch', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: recoveryKeyController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Recovery Key', hintText: 'RK-XXXX-XXXX-XXXX', border: OutlineInputBorder()),
                    onChanged: (_) => refresh(setState),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton(onPressed: canRecover ? () => Navigator.pop(dialogContext, true) : null, child: const Text('Recover')),
            ],
          ),
        );
      },
    );
    if (confirmed != true) return;
    try {
      final recoverySettings = cloud.copyWith(enabled: true, apiBaseUrl: apiUrlController.text.trim(), clearLastPullCursor: true);
      await recoverySettings.save();
      final result = await CloudSyncService(store).recoverExistingStoreFromCloud(
        recoverySettings,
        storeId: storeIdController.text,
        branchId: branchIdController.text,
        recoveryKey: recoveryKeyController.text,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _clearLocalData(BuildContext context) async {
    const confirmationWord = 'CONFIRM';
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final controller = TextEditingController();
        var canDelete = false;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Clear Local Data'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This will erase all local data, settings, and Host pairing on this Client device. Other devices will not be affected.',
                ),
                const SizedBox(height: 16),
                Text(
                  'Type $confirmationWord to confirm.',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Confirmation word',
                    hintText: confirmationWord,
                  ),
                  onChanged: (value) {
                    final next = value.trim() == confirmationWord;
                    if (next != canDelete) {
                      setState(() => canDelete = next);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: canDelete ? () => Navigator.pop(dialogContext, true) : null,
                child: const Text('Clear this device'),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true) return;
    await store.factoryResetLocalDevice();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This device was reset. Please sign in or set up again.')));
    }
  }

  Future<void> _pushHostCriticalEventToCloud(BuildContext context, String actionName) async {
    final identity = store.appIdentity;
    final cloud = CloudSyncSettings.load();
    if (!identity.isHost || !identity.isCloudEnabled || !cloud.isConfigured) return;

    if (context.mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text('$actionName • Cloud Push'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Uploading critical Host event to Cloud... 70%'),
              SizedBox(height: 12),
              LinearProgressIndicator(value: 0.70),
            ],
          ),
        ),
      );
    }

    final result = await UnifiedSyncEngine(
      CloudSyncTransportAdapter(
        service: CloudSyncService(store),
        settings: cloud,
      ),
    ).syncNow();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.ok ? '$actionName pushed to Cloud. Clients can rebuild/sync now.' : '$actionName was saved locally, but Cloud push failed: ${result.message}')),
      );
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

    final progress = ValueNotifier<_OperationProgress>(
      const _OperationProgress(0.05, 'Preparing rebuild... 5%'),
    );
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Rebuild From Host'),
          content: ValueListenableBuilder<_OperationProgress>(
            valueListenable: progress,
            builder: (_, value, __) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(value.label),
                const SizedBox(height: 10),
                LinearProgressIndicator(value: value.value),
                const SizedBox(height: 12),
                const Text('Keep this screen open while the Client clears local data, downloads the Host snapshot, and verifies it.'),
              ],
            ),
          ),
        ),
      );
    }

    final identity = store.appIdentity;
    String message = '';
    bool success = false;

    try {
      progress.value = const _OperationProgress(0.20, 'Resetting local Client state... 20%');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (identity.syncMode == SyncMode.cloudConnected || identity.syncMode == SyncMode.marketplaceEnabled) {
        progress.value = const _OperationProgress(0.40, 'Contacting Cloud Host snapshot... 40%');
        final result = await UnifiedSyncEngine(
          CloudSyncTransportAdapter(
            service: CloudSyncService(store),
            settings: CloudSyncSettings.load(),
          ),
        ).rebuildFromHostSnapshot(
          onProgress: (value, label) => progress.value = _OperationProgress(value, '$label ${(value * 100).round()}%'),
        );
        progress.value = _OperationProgress(result.ok ? 1.0 : 0.90, result.ok ? 'Cloud rebuild completed... 100%' : 'Cloud rebuild failed while verifying... 90%');
        message = result.message;
        success = result.ok;
      } else {
        final settings = LanSyncSettings.load();
        progress.value = const _OperationProgress(0.40, 'Contacting LAN Host... 40%');
        final result = await UnifiedSyncEngine(
          LanSyncTransportAdapter(
            service: LanSyncService(store),
            settings: settings,
          ),
        ).rebuildFromHostSnapshot(
          onProgress: (value, label) => progress.value = _OperationProgress(value, '$label ${(value * 100).round()}%'),
        );
        progress.value = _OperationProgress(result.ok ? 1.0 : 0.90, result.ok ? 'LAN rebuild completed... 100%' : 'LAN rebuild failed while verifying... 90%');
        message = result.message;
        success = result.ok;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progress.dispose();
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Rebuild completed successfully.' : message),
        ),
      );
    }
  }

  Future<void> _resetBusinessData(BuildContext context) async {
    const confirmationWord = 'CONFIRM';
    String hostSafety = 'no_connected_devices';
    final token = 'RST-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';

    final step1 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Reset All Data'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This is a local factory reset for this Host device. It will not create sync events.'),
              const SizedBox(height: 16),
              const Text('Before continuing, confirm your Host safety status:'),
              RadioGroup<String>(
                groupValue: hostSafety,
                onChanged: (value) => setState(() => hostSafety = value ?? hostSafety),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<String>(
                      value: 'other_host_ready',
                      title: Text('Yes, I configured another Host'),
                    ),
                    RadioListTile<String>(
                      value: 'not_ready',
                      title: Text('No'),
                    ),
                    RadioListTile<String>(
                      value: 'no_connected_devices',
                      title: Text('I do not have connected devices'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Continue')),
          ],
        ),
      ),
    );
    if (step1 != true) return;

    try {
      final backup = 'RESET_PROTECTION_TOKEN:$token\n${store.exportBackupJson()}';
      await downloadTextFile(filename: 'reset_protection_backup_${DateTime.now().millisecondsSinceEpoch}.json', content: backup);
    } catch (_) {
      // Backup download can fail on unsupported platforms; the visible token is still accepted.
    }

    if (!context.mounted) return;
    final tokenController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    var canContinue = false;
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Reset protection'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('A reset-protection backup was generated. Enter this token to continue:'),
                const SizedBox(height: 8),
                SelectableText(token, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(controller: tokenController, decoration: const InputDecoration(labelText: 'Reset token', border: OutlineInputBorder()), onChanged: (_) => setState(() => canContinue = tokenController.text.trim() == token && confirmController.text.trim() == confirmationWord && passwordController.text.isNotEmpty)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.attach_file_outlined),
                  label: const Text('Attach reset-protection backup'),
                  onPressed: () async {
                    final picked = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
                    final bytes = picked?.files.single.bytes;
                    if (bytes == null) return;
                    final content = utf8.decode(bytes, allowMalformed: true);
                    if (content.startsWith('RESET_PROTECTION_TOKEN:$token')) {
                      tokenController.text = token;
                      setState(() => canContinue = tokenController.text.trim() == token && confirmController.text.trim() == confirmationWord && passwordController.text.isNotEmpty);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Admin password', border: OutlineInputBorder()), onChanged: (_) => setState(() => canContinue = tokenController.text.trim() == token && confirmController.text.trim() == confirmationWord && passwordController.text.isNotEmpty)),
                const SizedBox(height: 12),
                TextField(controller: confirmController, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Type CONFIRM', border: OutlineInputBorder()), onChanged: (_) => setState(() => canContinue = tokenController.text.trim() == token && confirmController.text.trim() == confirmationWord && passwordController.text.isNotEmpty)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: canContinue ? () => Navigator.pop(dialogContext, true) : null, child: const Text('Verify')),
          ],
        ),
      ),
    );
    if (verified != true) return;

    final passwordOk = await store.verifyAdminPassword(passwordController.text);
    if (!passwordOk) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin password is incorrect.')));
      return;
    }

    if (!context.mounted) return;
    final finalController = TextEditingController();
    var finalOk = false;
    final finalConfirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Final irreversible warning'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('You will lose all data on this device. This reset cannot be undone from inside the app.'),
              const SizedBox(height: 12),
              TextField(controller: finalController, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Type CONFIRM again', border: OutlineInputBorder()), onChanged: (value) => setState(() => finalOk = value.trim() == confirmationWord)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error), onPressed: finalOk ? () => Navigator.pop(dialogContext, true) : null, child: const Text('Erase everything')),
          ],
        ),
      ),
    );
    if (finalConfirm != true) return;

    await store.factoryResetLocalDevice();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Host device reset completed.')));
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


































class _OperationProgress {
  const _OperationProgress(this.value, this.label);

  final double value;
  final String label;
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
  final _transferDeviceController = TextEditingController();
  DeviceRole _deviceRole = DeviceRole.host;
  SyncMode _clientSyncMode = SyncMode.lanOnly;
  bool _lanEnabledForHost = false;
  bool _cloudEnabled = false;
  bool _busy = false;
  String _status = '';
  double? _statusProgress;
  String _latestCloudPairingCode = '';
  DateTime? _latestCloudPairingExpiresAt;
  List<String> _hostIpAddresses = const <String>[];
  bool _detectingHostIp = false;
  bool _showLanPairingCode = false;
  bool _showCloudPairingCode = false;
  bool _connectToNewHost = false;
  bool _hostCreateFailed = false;
  DateTime? _latestLanPairingExpiresAt;
  Timer? _pairingCountdownTimer;

  static const _lanPairingExpiryStorageKey = 'lan_pairing_expires_at_v1';
  static const _cloudPairingCodeStorageKey = 'cloud_pairing_code_v1';
  static const _cloudPairingExpiryStorageKey = 'cloud_pairing_expires_at_v1';
  static const _pairingCodeLifetime = Duration(minutes: 5);
  String get _initialCloudHostReadyKey => 'cloud_initial_snapshot_ready_${widget.store.appIdentity.storeId}';
  bool get _initialCloudHostReady => LocalDatabaseService.getString(_initialCloudHostReadyKey) == 'true';

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
    _lanTokenController.text = lan.secret.trim();
    _cloudApiController.text = cloud.apiBaseUrl;
    _cloudTokenController.text = cloud.apiToken;
    _cloudIntervalController.text = cloud.intervalSeconds.toString();
    _loadActivePairingCodes();
    _startPairingCountdownTimer();
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
    _transferDeviceController.dispose();
    _pairingCountdownTimer?.cancel();
    super.dispose();
  }

  int get _lanPort => int.tryParse(_lanPortController.text.trim()) ?? 8787;
  int get _cloudInterval => int.tryParse(_cloudIntervalController.text.trim())?.clamp(30, 3600).toInt() ?? 30;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Working...';
      _statusProgress = null;
    });
    try {
      await action();
      await widget.onSyncSettingsChanged?.call();
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = error.toString().contains('Pairing code expired or already used') ? 'Pairing code expired or already used. Ask the Host device for a new code.' : 'Failed. Please check the information and try again.';
          _statusProgress = null;
        });
      }
      return;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _statusProgress = null;
        });
      }
    }
  }

  CloudSyncSettings _cloudSettings({bool enabled = true}) => CloudSyncSettings.load().copyWith(
        enabled: enabled,
        apiBaseUrl: _cloudApiController.text.trim().isEmpty ? (kIsWeb ? Uri.base.origin : '') : _cloudApiController.text.trim(),
        apiToken: _cloudTokenController.text.trim(),
        autoSyncEnabled: enabled,
        intervalSeconds: _cloudInterval,
      );

  UnifiedSyncEngine _cloudEngine({bool enabled = true}) => UnifiedSyncEngine(
        CloudSyncTransportAdapter(
          service: CloudSyncService(widget.store),
          settings: _cloudSettings(enabled: enabled),
        ),
      );

  UnifiedSyncEngine _lanEngine([LanSyncSettings? settings]) => UnifiedSyncEngine(
        LanSyncTransportAdapter(
          service: LanSyncService(widget.store),
          settings: settings ?? LanSyncSettings.load(),
        ),
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

  Future<void> _generateLanToken() async {
    final current = LanSyncSettings.load().copyWith(
      host: _lanHostController.text.trim().isEmpty ? LanSyncSettings.load().host : _lanHostController.text.trim(),
      port: _lanPort,
    );
    final result = await _lanEngine(current).createPairingCode(ttlMinutes: _pairingCodeLifetime.inMinutes);
    if (!result.ok) throw StateError(result.message);
    final code = result.code;
    final expiresAt = result.expiresAt ?? DateTime.now().add(_pairingCodeLifetime);
    _lanTokenController.text = code;
    _latestLanPairingExpiresAt = expiresAt;
    _showLanPairingCode = true;
    await LocalDatabaseService.setString(_lanPairingExpiryStorageKey, expiresAt.toIso8601String());
    if (mounted) setState(() => _status = 'LAN pairing code created.');
  }

  void _loadActivePairingCodes() {
    final now = DateTime.now();
    final lanExpiry = DateTime.tryParse(LocalDatabaseService.getString(_lanPairingExpiryStorageKey) ?? '');
    if (_lanTokenController.text.trim().isNotEmpty && lanExpiry != null && lanExpiry.isAfter(now)) {
      _latestLanPairingExpiresAt = lanExpiry;
      _showLanPairingCode = false;
    } else if (lanExpiry != null && !lanExpiry.isAfter(now)) {
      _expireLanPairingCode();
    }
    final cloudCode = LocalDatabaseService.getString(_cloudPairingCodeStorageKey) ?? '';
    final cloudExpiry = DateTime.tryParse(LocalDatabaseService.getString(_cloudPairingExpiryStorageKey) ?? '');
    if (cloudCode.trim().isNotEmpty && cloudExpiry != null && cloudExpiry.isAfter(now)) {
      _latestCloudPairingCode = cloudCode.trim();
      _latestCloudPairingExpiresAt = cloudExpiry;
      _showCloudPairingCode = false;
    } else if (cloudExpiry != null && !cloudExpiry.isAfter(now)) {
      _expireCloudPairingCode();
    }
  }

  void _startPairingCountdownTimer() {
    _pairingCountdownTimer?.cancel();
    _pairingCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      if (_latestLanPairingExpiresAt != null && !_latestLanPairingExpiresAt!.isAfter(now)) _expireLanPairingCode();
      if (_latestCloudPairingExpiresAt != null && !_latestCloudPairingExpiresAt!.isAfter(now)) _expireCloudPairingCode();
      setState(() {});
    });
  }

  void _expireLanPairingCode() {
    _lanTokenController.clear();
    _latestLanPairingExpiresAt = null;
    _showLanPairingCode = false;
    unawaited(LocalDatabaseService.deleteString(_lanPairingExpiryStorageKey));
    unawaited(LanSyncSettings.load().copyWith(secret: '').save());
  }

  void _expireCloudPairingCode() {
    _latestCloudPairingCode = '';
    _latestCloudPairingExpiresAt = null;
    _showCloudPairingCode = false;
    unawaited(LocalDatabaseService.deleteString(_cloudPairingCodeStorageKey));
    unawaited(LocalDatabaseService.deleteString(_cloudPairingExpiryStorageKey));
  }

  String _countdownText(DateTime? expiresAt) {
    if (expiresAt == null) return '00:00';
    final seconds = expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 24 * 60 * 60).toInt();
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  bool get _hasExistingHostConnection => widget.store.appIdentity.hostDeviceId.trim().isNotEmpty;

  Future<bool> _confirmConnectToNewHost() async {
    if (!_hasExistingHostConnection) return true;
    const confirmationWord = 'CONFIRM';
    final controller = TextEditingController();
    var canContinue = false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Connect to New Host'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This will erase the current store data and settings on this device, then connect to a new Host and download its full store data.'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Type CONFIRM', border: OutlineInputBorder()),
                onChanged: (value) => setState(() => canContinue = value.trim() == confirmationWord),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: canContinue ? () => Navigator.pop(dialogContext, true) : null, child: const Text('Confirm')),
          ],
        ),
      ),
    );
    return result == true;
  }

  String get _cloudPairingButtonLabel {
    final active = _latestCloudPairingCode.trim().isNotEmpty && (_latestCloudPairingExpiresAt?.isAfter(DateTime.now()) ?? false);
    if (!active) return 'Generate New Code';
    return _showCloudPairingCode ? 'Hide Code' : 'Show Code'; // stage1-final
  }

  Future<void> _handleCloudPairingButton() async {
    final active = _latestCloudPairingCode.trim().isNotEmpty && (_latestCloudPairingExpiresAt?.isAfter(DateTime.now()) ?? false);
    if (!active) {
      await _createCloudPairingCode();
      return;
    }
    setState(() => _showCloudPairingCode = !_showCloudPairingCode);
  }

  String get _lanPairingButtonLabel {
    final active = _lanTokenController.text.trim().isNotEmpty && (_latestLanPairingExpiresAt?.isAfter(DateTime.now()) ?? false);
    if (!active) return 'Generate New Code';
    return _showLanPairingCode ? 'Hide Code' : 'Show Code'; // stage1-final
  }

  Future<void> _handleLanPairingButton() async {
    final active = _lanTokenController.text.trim().isNotEmpty && (_latestLanPairingExpiresAt?.isAfter(DateTime.now()) ?? false);
    if (!active) {
      await _generateLanToken();
      return;
    }
    setState(() => _showLanPairingCode = !_showLanPairingCode);
  }


  Future<void> _requestHostTransfer() => _run(() async {
        await widget.store.requestHostTransfer(reason: 'User requested Host role from Sync Settings.');
        final cloud = _cloudSettings(enabled: true);
        if (cloud.apiBaseUrl.trim().isNotEmpty) {
          await CloudSyncService(widget.store).requestHostTransfer(cloud, reason: 'User requested Host role from Sync Settings.');
        }
        if (mounted) {
          setState(() => _status = 'Host transfer request created. Ask the current Host to approve this Device ID: ${widget.store.deviceId}');
        }
      });

  Future<void> _approveHostTransferFromUi() => _run(() async {
        final deviceId = _transferDeviceController.text.trim();
        if (deviceId.isEmpty) throw StateError('Client Device ID is required.');
        final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Approve Host Transfer'),
            content: Text('This device will stop being Host and $deviceId will become the new Host. Continue?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Approve')),
            ],
          ),
        );
        if (confirmed != true) return;
        final cloud = _cloudSettings(enabled: true);
        if (cloud.isConfigured) {
          final cloudResult = await CloudSyncService(widget.store).approveHostTransfer(cloud, deviceId);
          if (!cloudResult.ok) throw StateError(cloudResult.message);
        }
        await widget.store.approveHostTransfer(deviceId);
        if (mounted) {
          setState(() {
            _deviceRole = DeviceRole.client;
            _status = 'Host transfer approved. This device is now a Client. The new Host must activate and upload a fresh snapshot.';
          });
        }
      });

  Future<void> _activateApprovedHostTransferFromUi() => _run(() async {
        final cloud = _cloudSettings(enabled: true);
        if (cloud.apiBaseUrl.trim().isNotEmpty) {
          await CloudSyncService(widget.store).activateHostTransfer(cloud);
        }
        await widget.store.activateApprovedHostTransfer();
        if (mounted) {
          setState(() {
            _deviceRole = DeviceRole.host;
            _status = 'Host transfer activated. This device is now Host and a fresh snapshot was queued.';
          });
        }
      });

  Future<void> _scanPairingQr() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerPage(
          title: 'Scan pairing QR',
          helpText: 'Point the camera at the Host pairing QR code.',
          formats: [BarcodeFormat.qrCode],
        ),
      ),
    );
    if (raw == null || raw.trim().isEmpty) return;
    _applyScannedPairingPayload(raw.trim());
  }

  void _applyScannedPairingPayload(String raw) {
    String code = raw;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final transport = (decoded['transport'] ?? decoded['syncType'] ?? decoded['type'] ?? '').toString().toLowerCase();
        if (transport.contains('lan')) {
          _clientSyncMode = SyncMode.lanOnly;
        } else if (transport.contains('cloud')) {
          _clientSyncMode = SyncMode.cloudConnected;
        }
        final host = (decoded['host'] ?? decoded['hostIp'] ?? decoded['ip'] ?? '').toString();
        final port = (decoded['port'] ?? '').toString();
        final token = (decoded['pairingCode'] ?? decoded['pairing_code'] ?? decoded['code'] ?? decoded['token'] ?? decoded['pairingToken'] ?? '').toString();
        final apiBaseUrl = (decoded['apiBaseUrl'] ?? decoded['apiUrl'] ?? decoded['cloudApiUrl'] ?? '').toString();
        if (host.trim().isNotEmpty) _lanHostController.text = host.trim();
        if (port.trim().isNotEmpty) _lanPortController.text = port.trim();
        if (apiBaseUrl.trim().isNotEmpty) _cloudApiController.text = apiBaseUrl.trim();
        code = token.trim().isNotEmpty ? token.trim() : raw;
      }
    } catch (_) {
      // Plain pairing code.
    }
    setState(() {
      if (_clientSyncMode == SyncMode.lanOnly) {
        _lanTokenController.text = code;
      } else {
        _cloudPairingCodeController.text = code;
      }
      _status = 'QR detected. Review the connection details, then connect.';
    });
  }

  Future<void> _createCloudPairingCode() => _run(() async {
        await _saveCloudSettingsForPairing();
        final result = await _cloudEngine(enabled: true).createPairingCode(ttlMinutes: _pairingCodeLifetime.inMinutes);
        if (!result.ok) throw StateError(result.message);
        final expiresAt = result.expiresAt ?? DateTime.now().add(_pairingCodeLifetime);
        await LocalDatabaseService.setString(_cloudPairingCodeStorageKey, result.code);
        await LocalDatabaseService.setString(_cloudPairingExpiryStorageKey, expiresAt.toIso8601String());
        setState(() {
          _latestCloudPairingCode = result.code;
          _latestCloudPairingExpiresAt = expiresAt;
          _showCloudPairingCode = true;
          _status = 'Cloud pairing code created.';
        });
      });

  Future<void> _copyCloudPairingCode() async {
    final code = _latestCloudPairingCode.trim();
    if (code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cloud pairing code copied.')));
  }

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
        final existingLan = LanSyncSettings.load();
        final lanSecret = _lanTokenController.text.trim();
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
          pairedDevices: existingLan.pairedDevices,
        ).save();
        await _cloudSettings(enabled: _cloudEnabled).save();
        if (!_cloudEnabled) await LocalDatabaseService.deleteString(_initialCloudHostReadyKey);
        setState(() => _status = 'Host sync settings saved.');
      });

  Future<void> _saveLanClient() => _run(() async {
        if (!await _confirmConnectToNewHost()) return;
        final secret = _lanTokenController.text.trim();
        if (secret.isEmpty) throw StateError('LAN pairing code is required.');
        final lanSettings = LanSyncSettings.load().copyWith(
          host: _lanHostController.text.trim(),
          port: _lanPort,
          secret: secret,
          mode: LanSyncDeviceMode.client,
          setupComplete: true,
          hostModeEnabled: false,
        );
        final result = await _lanEngine(lanSettings).claimPairingCode(secret);
        if (!result.ok) throw StateError(result.message);
        _expireLanPairingCode();
        _expireCloudPairingCode();
        await CloudSyncSettings.load().copyWith(autoSyncEnabled: false, clearLastPullCursor: true).save();
        setState(() { _connectToNewHost = false; _status = 'LAN Client connected and cloned from Host.'; });
      });

  Future<void> _claimCloudPairing() => _run(() async {
        if (!await _confirmConnectToNewHost()) return;
        final settings = _cloudSettings(enabled: true);
        await settings.save();
        final result = await _cloudEngine(enabled: true).claimPairingCode(_cloudPairingCodeController.text.trim());
        if (!result.ok) throw StateError(result.message);
        _expireCloudPairingCode();
        _expireLanPairingCode();
        await LanSyncSettings.load().copyWith(autoSyncEnabled: false, setupComplete: false, mode: LanSyncDeviceMode.unconfigured, hostModeEnabled: false, clearLastPullCursor: true).save();
        setState(() { _connectToNewHost = false; _status = result.message; });
      });


  Future<void> _createNewHost() => _run(() async {
        setState(() { _status = 'Connecting to Cloud'; _statusProgress = 0.10; });
        await _saveCloudSettingsForPairing();
        setState(() { _status = 'Creating Host'; _statusProgress = 0.25; });
        final cloudEngine = _cloudEngine(enabled: true);
        final registerResult = await cloudEngine.registerCurrentHost(transportName: 'cloud');
        if (!registerResult.ok) throw StateError(registerResult.message);
        setState(() { _status = 'Preparing store data'; _statusProgress = 0.45; });
        setState(() { _status = 'Uploading initial snapshot'; _statusProgress = 0.70; });
        final snapshotRequestedAt = DateTime.now().toUtc().subtract(const Duration(seconds: 2));
        final result = await cloudEngine.createInitialHostSnapshot(
          minSnapshotUpdatedAt: snapshotRequestedAt,
          onProgress: (value, label) {
            if (mounted) setState(() { _status = label; _statusProgress = value < 0.70 ? 0.70 : value; });
          },
        );
        setState(() { _status = 'Verifying upload'; _statusProgress = 0.90; });
        if (!result.ok || result.pushed <= 0) {
          _hostCreateFailed = true;
          throw StateError(result.ok ? 'Initial snapshot upload was not verified. Please retry Create New Host.' : result.message);
        }
        await LocalDatabaseService.setString(_initialCloudHostReadyKey, 'true');
        setState(() { _hostCreateFailed = false; _status = 'Store is ready'; _statusProgress = 1.0; });
      });

  Future<void> _syncNow() => _run(() async {
        final identity = widget.store.appIdentity;
        if (identity.isCloudEnabled) {
          final result = await _cloudEngine(enabled: true).syncNow(
            onProgress: (value, label) {
              if (mounted) setState(() { _status = 'Cloud sync: $label ${(value * 100).round()}%'; _statusProgress = value; });
            },
          );
          if (!result.ok) throw StateError(result.message);
          setState(() { _status = 'Cloud sync complete... 100% • ${result.message}'; _statusProgress = 1.0; });
        } else if (identity.syncMode == SyncMode.lanOnly) {
          final result = await _lanEngine().syncNow(
            onProgress: (value, label) {
              if (mounted) setState(() { _status = 'LAN sync: $label ${(value * 100).round()}%'; _statusProgress = value; });
            },
          );
          if (!result.ok) throw StateError(result.message);
          setState(() { _status = 'LAN sync complete... 100% • ${result.message}'; _statusProgress = 1.0; });
        } else {
          setState(() => _status = 'No sync mode is enabled.');
        }
      });

  Future<void> _testCloudConnection() => _run(() async {
        setState(() { _status = 'Testing Cloud connection... 25%'; _statusProgress = 0.25; });
        final result = await _cloudEngine(enabled: true).testConnection();
        if (!result.ok) throw StateError(result.message);
        setState(() { _status = 'Cloud connection OK. ${result.message}'; _statusProgress = 1.0; });
      });

  Future<void> _testHostConnection() => _run(() async {
        final lan = LanSyncSettings.load();
        final host = _lanHostController.text.trim().isEmpty ? lan.host : _lanHostController.text.trim();
        setState(() { _status = 'Testing LAN Host connection... 25%'; _statusProgress = 0.25; });
        final result = await _lanEngine(lan.copyWith(host: host, port: _lanPort)).testConnection();
        if (!result.ok) throw StateError(result.message);
        setState(() { _status = 'LAN Host connection OK. ${result.message}'; _statusProgress = 1.0; });
      });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final isHost = _deviceRole == DeviceRole.host;
    final isCloudClient = !isHost && _clientSyncMode == SyncMode.cloudConnected;
    final needsInitialCloudHost = _deviceRole == DeviceRole.host && _cloudEnabled && !_initialCloudHostReady;
    final hostActionLabel = needsInitialCloudHost ? (_hostCreateFailed ? 'Retry Create Host' : 'Create New Host') : 'Sync Now';
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
              onSelectionChanged: null,
            ),
            const SizedBox(height: 8),
            Text(
              'Host/Client role is controlled by the official Transfer Host flow only.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (widget.store.latestHostTransferNotification != null) _hostChangedNotificationCard(),
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
                ..._lanFields(showHostIp: false, forHost: true),
                SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _busy ? null : _handleLanPairingButton, icon: const Icon(Icons.qr_code_2_outlined), label: Text(_lanPairingButtonLabel))),
                const SizedBox(height: 12),
                if (_showLanPairingCode) _lanPairingCodeCard(),
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
                SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _busy ? null : _handleCloudPairingButton, icon: const Icon(Icons.qr_code_2_outlined), label: Text(_cloudPairingButtonLabel))),
                const SizedBox(height: 12),
                if (_showCloudPairingCode) _cloudPairingCodeCard(),
              ],
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _saveHostMode, icon: const Icon(Icons.save_outlined), label: const Text('Save Host Settings'))),
              _transferHostCard(isHost: true),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).dividerColor)),
                child: Text(widget.store.appIdentity.hostDeviceId.trim().isNotEmpty
                    ? 'Connection Status: Connected to ${widget.store.appIdentity.storeId} / ${widget.store.appIdentity.branchId} / ${widget.store.appIdentity.hostDeviceId}'
                    : 'Connection Status: No Host Connected'),
              ),
              _transferHostCard(isHost: false),
              const SizedBox(height: 12),
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
              if (_hasExistingHostConnection && !_connectToNewHost)
                SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : () => setState(() => _connectToNewHost = true), icon: const Icon(Icons.add_link_outlined), label: const Text('Connect to New Host')))
              else if (!isCloudClient) ...[
                ..._lanFields(showHostIp: true),
                OutlinedButton.icon(onPressed: _busy ? null : _scanPairingQr, icon: const Icon(Icons.qr_code_scanner_outlined), label: const Text('Scan QR Code')),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _saveLanClient, icon: const Icon(Icons.link_outlined), label: Text(_hasExistingHostConnection ? 'Connect to New LAN Host' : 'Connect to LAN Host'))),
              ] else ...[
                ..._cloudFields(showPairingCode: true),
                OutlinedButton.icon(onPressed: _busy ? null : _scanPairingQr, icon: const Icon(Icons.qr_code_scanner_outlined), label: const Text('Scan QR Code')),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _claimCloudPairing, icon: const Icon(Icons.cloud_done_outlined), label: Text(_hasExistingHostConnection ? 'Connect to New Cloud Host' : 'Pair with Cloud Host'))),
              ],
            ],
            if (isHost) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : (needsInitialCloudHost ? _createNewHost : _syncNow),
                icon: Icon(needsInitialCloudHost ? Icons.add_business_outlined : Icons.sync_outlined),
                label: Text(hostActionLabel),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _testCloudConnection,
                icon: const Icon(Icons.cloud_done_outlined),
                label: const Text('Test Cloud Connection'),
              ),
            ] else ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _testHostConnection,
                icon: const Icon(Icons.lan_outlined),
                label: const Text('Test Host Connection'),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_busy ? (_status.isEmpty ? 'Working...' : _status) : (_status.isEmpty ? _humanStatus : _status)),
                  if (_busy) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _statusProgress),
                  ],
                ],
              ),
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


  Widget _hostChangedNotificationCard() {
    final notice = widget.store.latestHostTransferNotification;
    if (notice == null) return const SizedBox.shrink();
    final newHostDeviceId = notice['newHostDeviceId']?.toString() ?? '';
    final storeId = notice['storeId']?.toString() ?? widget.store.appIdentity.storeId;
    final branchId = notice['branchId']?.toString() ?? widget.store.appIdentity.branchId;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Host changed for $storeId / $branchId. New Host Device ID: $newHostDeviceId'),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: _busy ? null : () { widget.store.clearHostTransferNotification(); },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _transferHostCard({required bool isHost}) {
    final pending = widget.store.pendingHostTransferRequest;
    final approvedForThisDevice = widget.store.approvedHostTransferDeviceId == widget.store.deviceId;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text('Transfer Host Role', style: Theme.of(context).textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 8),
          if (isHost) ...[
            const Text('Approve a Client device to become the new Host. This device will become a Client after approval.'),
            const SizedBox(height: 8),
            if (pending != null) ...[
              Text('Latest request: ${pending['requestingDeviceId'] ?? 'Unknown device'}'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => setState(() => _transferDeviceController.text = (pending['requestingDeviceId'] ?? '').toString()),
                icon: const Icon(Icons.input_outlined),
                label: const Text('Use Latest Request'),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _transferDeviceController,
              decoration: const InputDecoration(labelText: 'Client Device ID to approve', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _approveHostTransferFromUi,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Approve Host Transfer'),
              ),
            ),
          ] else ...[
            Text('This Client Device ID: ${widget.store.deviceId}'),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _requestHostTransfer,
                icon: const Icon(Icons.outbox_outlined),
                label: const Text('Request to Become Host'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy || !approvedForThisDevice ? null : _activateApprovedHostTransferFromUi,
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('Activate Approved Host Transfer'),
              ),
            ),
            if (!approvedForThisDevice) const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Activation becomes available after the current Host approves this Device ID.'),
            ),
          ],
        ],
      ),
    );
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

  Widget _lanPairingCodeCard() {
    final code = _lanTokenController.text.trim();
    if (code.isEmpty) return const SizedBox.shrink();
    final host = _lanHostController.text.trim().isNotEmpty ? _lanHostController.text.trim() : LanSyncSettings.load().host;
    final payload = jsonEncode({
      'transport': 'lan',
      'host': host,
      'port': _lanPort,
      'pairingCode': code,
    });
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_2_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text('LAN One-Time Pairing Code', style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                tooltip: 'Copy code',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('LAN pairing code copied.')));
                },
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 180,
              ),
            ),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'Code',
              helperText: 'Expires in ${_countdownText(_latestLanPairingExpiresAt)}',
              border: const OutlineInputBorder(),
            ),
            child: Text(
              code,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(letterSpacing: 1.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cloudPairingCodeCard() {
    final code = _latestCloudPairingCode.trim();
    if (code.isEmpty) {
      return const SizedBox.shrink();
    }
    final expiresText = 'Expires in ${_countdownText(_latestCloudPairingExpiresAt)}';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_2_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text('Cloud Pairing Code', style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                tooltip: 'Copy code',
                onPressed: _copyCloudPairingCode,
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: jsonEncode({'transport': 'cloud', 'apiBaseUrl': _cloudApiController.text.trim(), 'pairingCode': code}),
                version: QrVersions.auto,
                size: 180,
              ),
            ),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'Code',
              helperText: expiresText,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Copy code',
                onPressed: _copyCloudPairingCode,
                icon: const Icon(Icons.copy_outlined),
              ),
            ),
            child: Text(
              code,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(letterSpacing: 1.2),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _lanFields({required bool showHostIp, bool forHost = false}) => [
        if (showHostIp)
          TextField(controller: _lanHostController, decoration: const InputDecoration(labelText: 'Manual Host IP (optional)', border: OutlineInputBorder())),
        if (showHostIp) const SizedBox(height: 12),
        TextField(controller: _lanPortController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        if (!forHost) ...[
          TextField(
            controller: _lanTokenController,
            decoration: const InputDecoration(
              labelText: 'LAN Pairing Code',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ];

  List<Widget> _cloudFields({required bool showPairingCode}) => [
        TextField(
          controller: _cloudApiController,
          decoration: const InputDecoration(
            labelText: 'Cloud API URL',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (showPairingCode)
          TextField(
            controller: _cloudPairingCodeController,
            decoration: const InputDecoration(
              labelText: 'Pairing code from Host',
              border: OutlineInputBorder(),
            ),
          ),
        if (showPairingCode) const SizedBox(height: 12),
        if (!showPairingCode)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.tune_outlined),
            title: const Text('Advanced Cloud Settings'),
            subtitle: const Text('Host-only deployment token and background sync timing.'),
            childrenPadding: const EdgeInsets.only(top: 8, bottom: 8),
            children: [
              TextField(
                controller: _cloudTokenController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Cloud deployment token',
                  helperText: 'Host only. Clients pair with a one-time code and never need this token.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cloudIntervalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Auto sync interval seconds',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
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
