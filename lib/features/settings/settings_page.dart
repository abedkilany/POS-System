import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services/backup_download_service.dart';
import '../../core/services/barcode_feedback_service.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/services/lan_sync_service.dart';
import '../../core/services/local_database_service.dart';
import '../../core/sync_unified/sync_unified.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/responsive.dart';
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
    final navItems = [
      _SettingsNavData(icon: Icons.store_outlined, label: tr.text('store_information'), description: tr.text('store_information_desc')),
      _SettingsNavData(icon: Icons.account_balance_wallet_outlined, label: tr.text('financial_settings'), description: tr.text('currencies_pricing_desc')),
      _SettingsNavData(icon: Icons.sync_outlined, label: tr.text('sync'), description: tr.text('sync_nav_desc')),
      _SettingsNavData(icon: Icons.backup_outlined, label: tr.text('backup_restore'), description: tr.text('backup_preview_desc')),
      _SettingsNavData(icon: Icons.admin_panel_settings_outlined, label: tr.text('users_permissions'), description: tr.text('users_permissions_desc')),
    ];

    return DefaultTabController(
      length: navItems.length,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          final pages = [
            _settingsList(context, _generalCards(context)),
            _settingsList(context, _financialCards(context)),
            _settingsList(context, _syncCards(context)),
            _settingsList(context, _backupCards(context)),
            _settingsList(context, _adminCards(context)),
          ];

          if (!isWide) {
            return Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: TabBar(
                    isScrollable: true,
                    tabs: [for (final item in navItems) Tab(icon: Icon(item.icon), text: item.label)],
                  ),
                ),
                Expanded(child: TabBarView(children: pages)),
              ],
            );
          }

          return Builder(builder: (context) {
            final controller = DefaultTabController.of(context);
            return Row(
              children: [
                SizedBox(
                  width: 300,
                  child: AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) => _SettingsSideNav(
                      items: navItems,
                      selectedIndex: controller.index,
                      onSelected: controller.animateTo,
                      store: store,
                    ),
                  ),
                ),
                VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
                Expanded(child: TabBarView(children: pages)),
              ],
            );
          });
        },
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
      _SectionCard(
        icon: Icons.store_outlined,
        title: tr.text('store_information'),
        subtitle: tr.text('store_information_desc'),
        trailing: FilledButton.icon(
          onPressed: () => _editStoreProfile(context, profile),
          icon: const Icon(Icons.edit_outlined),
          label: Text(tr.text('edit')),
        ),
        child: Column(
          children: [
            _InfoTile(icon: Icons.storefront_outlined, title: tr.text('store_name'), value: profile.name),
            _InfoTile(icon: Icons.phone_outlined, title: tr.text('phone'), value: profile.phone.isEmpty ? '—' : profile.phone),
            _InfoTile(icon: Icons.location_on_outlined, title: tr.text('address'), value: profile.address.isEmpty ? '—' : profile.address),
            _InfoTile(icon: Icons.receipt_long_outlined, title: tr.text('invoice_footer'), value: profile.footerNote),
          ],
        ),
      ),
      _SystemIdentityCard(store: store),

      Card(
        child: Padding(
          padding: VentioResponsive.pageInsets(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr.text('theme'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment<ThemeMode>(value: ThemeMode.system, icon: const Icon(Icons.settings_suggest_outlined), label: Text(tr.text('theme_system'))),
                  ButtonSegment<ThemeMode>(value: ThemeMode.light, icon: const Icon(Icons.light_mode_outlined), label: Text(tr.text('theme_light'))),
                  ButtonSegment<ThemeMode>(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode_outlined), label: Text(tr.text('theme_dark'))),
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
          padding: VentioResponsive.pageInsets(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr.text('language'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [
                OutlinedButton(onPressed: () => onLocaleChanged(const Locale('en')), child: Text(tr.text('language_english'))),
                OutlinedButton(onPressed: () => onLocaleChanged(const Locale('ar')), child: Text(tr.text('language_arabic'))),
              ]),
            ],
          ),
        ),
      ),
      const _ScannerFeedbackSettingsCard(),
    ];
  }


  List<Widget> _financialCards(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final profile = store.storeProfile;
    return [
      _SectionCard(
        icon: Icons.payments_outlined,
        title: tr.text('currencies_pricing'),
        subtitle: tr.text('currencies_pricing_desc'),
        trailing: FilledButton.icon(
          onPressed: () => _editFinancialSettings(context, profile),
          icon: const Icon(Icons.edit_outlined),
          label: Text(tr.text('edit')),
        ),
        child: _InfoGrid(
          items: [
            _InfoGridItem(Icons.currency_exchange_outlined, tr.text('usd_lbp_exchange_rate'), '1 USD = ${profile.usdToLbpRate.toStringAsFixed(0)} LBP'),
            _InfoGridItem(Icons.visibility_outlined, tr.text('price_display_mode'), tr.text('price_display_${profile.priceDisplayMode}')),
            _InfoGridItem(Icons.attach_money_outlined, tr.text('default_product_currency'), profile.defaultProductCurrency),
            _InfoGridItem(Icons.tune_outlined, tr.text('lbp_rounding'), profile.lbpRounding <= 0 ? tr.text('no_rounding') : '${profile.lbpRounding} LBP'),
          ],
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
          padding: VentioResponsive.pageInsets(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.backup_outlined), title: Text(tr.text('backup_restore')), subtitle: Text(tr.text('backup_preview_desc'))),
              Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(bottom: 12), child: Chip(avatar: const Icon(Icons.storage_outlined, size: 18), label: Text(tr.text('local_db_hive'))))),
              _BackupSummaryCard(summary: store.currentBackupSummary),
              const SizedBox(height: 16),
              Text('Actions', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = constraints.maxWidth < 560 ? constraints.maxWidth : (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: itemWidth,
                        child: OutlinedButton.icon(
                          onPressed: () => _recoverExistingStore(context),
                          icon: const Icon(Icons.key_outlined),
                          label: Text(tr.text('recover_existing_store')),
                        ),
                      ),
                      if (!store.appIdentity.isClient) ...[
                        SizedBox(
                          width: itemWidth,
                          child: OutlinedButton.icon(
                            onPressed: () => _downloadRecoveryFile(context),
                            icon: const Icon(Icons.security_outlined),
                            label: Text(tr.text('download_recovery_file')),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: FilledButton.icon(
                            onPressed: () => _downloadBackupFile(context),
                            icon: const Icon(Icons.download_outlined),
                            label: Text(tr.text('export')),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: OutlinedButton.icon(
                            onPressed: () => _importBackupFile(context),
                            icon: const Icon(Icons.upload_file_outlined),
                            label: Text(tr.text('import')),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      Card(
        child: Padding(
          padding: VentioResponsive.pageInsets(context),
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
              label: Text(tr.text('clear_local_data')),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _rebuildFromHost(context),
              icon: const Icon(Icons.restore_page_outlined),
              label: Text(tr.text('rebuild_from_host')),
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
          subtitle: Text(tr.format('signed_in_as_role', {'user': store.activeUser?.fullName ?? tr.text('unknown_user'), 'role': store.currentRole})),
          trailing: FilledButton.icon(
            onPressed: store.canManageUsers ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => UsersPermissionsPage(store: store))) : null,
            icon: const Icon(Icons.manage_accounts_outlined),
            label: Text(tr.text('manage')),
          ),
        ),
      ),
    ];
  }




  Future<void> _editFinancialSettings(BuildContext context, StoreProfile profile) async {
    final tr = AppLocalizations.of(context);
    final rateController = TextEditingController(text: profile.usdToLbpRate.toStringAsFixed(0));
    String displayMode = profile.priceDisplayMode;
    String defaultCurrency = profile.defaultProductCurrency.toUpperCase() == 'LBP' ? 'LBP' : 'USD';
    int rounding = profile.lbpRounding;

    final result = await showDialog<StoreProfile>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(tr.text('financial_settings')),
            content: ResponsiveDialogBox(
              maxWidth: VentioResponsive.modalMaxWidth(context, 560),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: rateController,
                      decoration: InputDecoration(labelText: tr.text('usd_lbp_exchange_rate'), helperText: '1 USD = LBP'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: displayMode,
                      decoration: InputDecoration(labelText: tr.text('price_display_mode')),
                      items: [
                        DropdownMenuItem(value: 'usd', child: Text(tr.text('price_display_usd'))),
                        DropdownMenuItem(value: 'lbp', child: Text(tr.text('price_display_lbp'))),
                        DropdownMenuItem(value: 'both', child: Text(tr.text('price_display_both'))),
                      ],
                      onChanged: (value) => setState(() => displayMode = value ?? 'usd'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: defaultCurrency,
                      decoration: InputDecoration(labelText: tr.text('default_product_currency')),
                      items: const [
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                        DropdownMenuItem(value: 'LBP', child: Text('LBP')),
                      ],
                      onChanged: (value) => setState(() => defaultCurrency = value ?? 'USD'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: rounding,
                      decoration: InputDecoration(labelText: tr.text('lbp_rounding')),
                      items: [
                        DropdownMenuItem(value: 0, child: Text(tr.text('no_rounding'))),
                        const DropdownMenuItem(value: 1000, child: Text('1,000 LBP')),
                        const DropdownMenuItem(value: 5000, child: Text('5,000 LBP')),
                        const DropdownMenuItem(value: 10000, child: Text('10,000 LBP')),
                      ],
                      onChanged: (value) => setState(() => rounding = value ?? 0),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr.text('cancel'))),
              FilledButton(
                onPressed: () {
                  final rate = double.tryParse(rateController.text.trim()) ?? profile.usdToLbpRate;
                  Navigator.pop(dialogContext, profile.copyWith(
                    currency: displayMode == 'lbp' ? 'LBP' : 'USD',
                    usdToLbpRate: rate <= 0 ? profile.usdToLbpRate : rate,
                    priceDisplayMode: displayMode,
                    defaultProductCurrency: defaultCurrency,
                    lbpRounding: rounding,
                  ));
                },
                child: Text(tr.text('save')),
              ),
            ],
          ),
        );
      },
    );

    if (result != null) {
      await store.updateStoreProfile(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('financial_settings_updated'))));
      }
    }
  }

  Future<void> _editStoreProfile(BuildContext context, StoreProfile profile) async {
    final nameController = TextEditingController(text: profile.name);
    final phoneController = TextEditingController(text: profile.phone);
    final addressController = TextEditingController(text: profile.address);
    final footerController = TextEditingController(text: profile.footerNote);
    final tr = AppLocalizations.of(context);

    final result = await showDialog<StoreProfile>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(tr.text('edit_store_profile')),
              content: ResponsiveDialogBox(
                maxWidth: VentioResponsive.modalMaxWidth(context, 520),
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
                        // Keep the legacy currency value for backward compatibility only.
                        // Currency selection is now managed exclusively from Financial Settings.
                        currency: profile.currency,
                        footerNote: footerController.text.trim().isEmpty ? 'Thank you for shopping with us.' : footerController.text.trim(),
                        usdToLbpRate: profile.usdToLbpRate,
                        priceDisplayMode: profile.priceDisplayMode,
                        defaultProductCurrency: profile.defaultProductCurrency,
                        lbpRounding: profile.lbpRounding,
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
          decoration: InputDecoration(labelText: AppLocalizations.of(context).text('password_min_6')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(AppLocalizations.of(context).text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: Text(AppLocalizations.of(context).text('save'))),
        ],
      ),
    );
  }


  Future<void> _downloadRecoveryFile(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    final identity = store.appIdentity;
    final cloud = CloudSyncSettings.load();
    var confirmed = false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(tr.text('store_recovery_security')),
          content: ResponsiveDialogBox(
            maxWidth: VentioResponsive.modalMaxWidth(context, 540),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr.text('store_recovery_security_desc')),
                const SizedBox(height: 12),
                _SecureRecoveryLine(title: tr.text('store_id'), value: identity.storeId),
                _SecureRecoveryLine(title: tr.text('branch_id'), value: identity.branchId),
                _SecureRecoveryLine(title: tr.text('cloud_api_url'), value: cloud.apiBaseUrl.isEmpty ? '—' : cloud.apiBaseUrl),
                _SecureRecoveryLine(title: tr.text('recovery_key'), value: identity.recoveryKey),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: confirmed,
                  onChanged: (value) => setState(() => confirmed = value ?? false),
                  title: Text(tr.text('confirm_recovery_saved')),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr.text('cancel'))),
            FilledButton(onPressed: confirmed ? () => Navigator.pop(dialogContext, true) : null, child: Text(tr.text('download_recovery_file'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final filename = 'ventio_recovery_${identity.storeId}_${DateTime.now().millisecondsSinceEpoch}.json';
    try {
      await downloadTextFile(filename: filename, content: store.exportRecoveryFileJson(cloudApiUrl: cloud.apiBaseUrl));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('recovery_file_downloaded'))));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('backup_download_not_supported'))));
      }
    }
  }

  Future<void> _loadRecoveryFileIntoFields(
    BuildContext context, {
    required TextEditingController apiUrlController,
    required TextEditingController storeIdController,
    required TextEditingController branchIdController,
    required TextEditingController recoveryKeyController,
    required VoidCallback onLoaded,
  }) async {
    final tr = AppLocalizations.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['json'], withData: true);
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null || bytes.isEmpty) throw Exception(tr.text('empty_recovery_file'));
      final data = store.parseRecoveryFileJson(utf8.decode(bytes));
      if ((data['cloudApiUrl'] ?? '').isNotEmpty) apiUrlController.text = data['cloudApiUrl']!;
      storeIdController.text = data['storeId'] ?? '';
      branchIdController.text = data['branchId'] ?? '';
      recoveryKeyController.text = data['recoveryKey'] ?? '';
      onLoaded();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('recovery_file_loaded'))));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr.text('invalid_recovery_file')}: $error')));
      }
    }
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('import_backup_host_only'))));
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
        throw Exception(tr.text('empty_backup_file'));
      }

      var raw = utf8.decode(bytes);
      if (raw.trim().startsWith('{') && raw.contains('store_manager_pro_encrypted_backup')) {
        if (!context.mounted) return;
        final password = await _askPassword(context, title: AppLocalizations.of(context).text('backup_password'));
        if (password == null) return;
        if (!context.mounted) return;
        raw = store.decryptBackupJson(raw, password);
      }
      if (raw.trim().isEmpty) {
        throw Exception(tr.text('empty_backup_file'));
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
            title: Text(AppLocalizations.of(context).text('recover_existing_store')),
            content: ResponsiveDialogBox(
              maxWidth: VentioResponsive.modalMaxWidth(context, 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.of(context).text('recover_existing_store_desc')),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _loadRecoveryFileIntoFields(
                        context,
                        apiUrlController: apiUrlController,
                        storeIdController: storeIdController,
                        branchIdController: branchIdController,
                        recoveryKeyController: recoveryKeyController,
                        onLoaded: () => refresh(setState),
                      ),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text(AppLocalizations.of(context).text('upload_recovery_file')),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: apiUrlController,
                    decoration: InputDecoration(labelText: AppLocalizations.of(context).text('cloud_api_url'), hintText: 'https://your-cloud-api.vercel.app', border: const OutlineInputBorder()),
                    onChanged: (_) => refresh(setState),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: storeIdController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(labelText: AppLocalizations.of(context).text('store_id'), hintText: 'ST-XXXXXX', border: const OutlineInputBorder()),
                    onChanged: (_) => refresh(setState),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: branchIdController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(labelText: AppLocalizations.of(context).text('branch_id_optional'), hintText: AppLocalizations.of(context).text('branch_id_recover_hint'), border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: recoveryKeyController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(labelText: AppLocalizations.of(context).text('recovery_key'), hintText: 'RK-XXXX-XXXX-XXXX', border: const OutlineInputBorder()),
                    onChanged: (_) => refresh(setState),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(AppLocalizations.of(context).text('cancel'))),
              FilledButton(onPressed: canRecover ? () => Navigator.pop(dialogContext, true) : null, child: Text(AppLocalizations.of(context).text('recover'))),
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
            title: Text(AppLocalizations.of(context).text('clear_local_data')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This will erase all local data, settings, and Host pairing on this Client device. Other devices will not be affected.',
                ),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context).format('type_word_to_confirm', {'word': confirmationWord}),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: AppLocalizations.of(context).text('confirmation_word'),
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
                child: Text(AppLocalizations.of(context).text('cancel')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: canDelete ? () => Navigator.pop(dialogContext, true) : null,
                child: Text(AppLocalizations.of(context).text('clear_this_device')),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true) return;
    await store.factoryResetLocalDevice();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).text('device_reset_sign_in'))));
    }
  }

  Future<void> _pushHostCriticalEventToCloud(BuildContext context, String actionName) async {
    final tr = AppLocalizations.of(context);
    final identity = store.appIdentity;
    final cloud = CloudSyncSettings.load();
    if (!identity.isHost || !identity.isCloudEnabled || !cloud.isConfigured) return;

    if (context.mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text('$actionName • ${tr.text('cloud_push')}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr.text('uploading_host_event')),
              const SizedBox(height: 12),
              const LinearProgressIndicator(value: 0.70),
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
        SnackBar(content: Text(result.ok ? '$actionName ${tr.text('cloud_push_success')}' : '$actionName ${tr.text('cloud_push_failed')}: ${result.message}')),
      );
    }
  }

  Future<void> _rebuildFromHost(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context).text('rebuild_from_host')),
        content: Text(AppLocalizations.of(context).text('rebuild_from_host_desc')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(AppLocalizations.of(context).text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(AppLocalizations.of(context).text('rebuild'))),
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
          title: Text(AppLocalizations.of(context).text('rebuild_from_host')),
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
                Text(AppLocalizations.of(context).text('rebuild_keep_open_desc')),
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
          content: Text(success ? AppLocalizations.of(context).text('rebuild_completed_successfully') : message),
        ),
      );
    }
  }

  Future<void> _resetBusinessData(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    const confirmationWord = 'CONFIRM';
    String hostSafety = 'no_connected_devices';
    final token = 'RST-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';

    final step1 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(tr.text('reset_all_data')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr.text('reset_host_local_factory_desc')),
              const SizedBox(height: 16),
              Text(tr.text('confirm_host_safety_status')),
              RadioGroup<String>(
                groupValue: hostSafety,
                onChanged: (value) => setState(() => hostSafety = value ?? hostSafety),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<String>(
                      value: 'other_host_ready',
                      title: Text(tr.text('configured_another_host')),
                    ),
                    RadioListTile<String>(
                      value: 'not_ready',
                      title: Text(tr.text('no')),
                    ),
                    RadioListTile<String>(
                      value: 'no_connected_devices',
                      title: Text(tr.text('no_connected_devices')),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(AppLocalizations.of(context).text('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(tr.text('continue'))),
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
          title: Text(tr.text('reset_protection')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr.text('reset_protection_backup_generated')),
                const SizedBox(height: 8),
                SelectableText(token, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(controller: tokenController, decoration: InputDecoration(labelText: tr.text('reset_token'), border: const OutlineInputBorder()), onChanged: (_) => setState(() => canContinue = tokenController.text.trim() == token && confirmController.text.trim() == confirmationWord && passwordController.text.isNotEmpty)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.attach_file_outlined),
                  label: Text(tr.text('attach_reset_protection_backup')),
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
                TextField(controller: passwordController, obscureText: true, decoration: InputDecoration(labelText: tr.text('admin_password'), border: const OutlineInputBorder()), onChanged: (_) => setState(() => canContinue = tokenController.text.trim() == token && confirmController.text.trim() == confirmationWord && passwordController.text.isNotEmpty)),
                const SizedBox(height: 12),
                TextField(controller: confirmController, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: tr.text('type_confirm'), border: const OutlineInputBorder()), onChanged: (_) => setState(() => canContinue = tokenController.text.trim() == token && confirmController.text.trim() == confirmationWord && passwordController.text.isNotEmpty)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(AppLocalizations.of(context).text('cancel'))),
            FilledButton(onPressed: canContinue ? () => Navigator.pop(dialogContext, true) : null, child: Text(tr.text('verify'))),
          ],
        ),
      ),
    );
    if (verified != true) return;

    final passwordOk = await store.verifyAdminPassword(passwordController.text);
    if (!passwordOk) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('admin_password_incorrect'))) );
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
          title: Text(tr.text('final_irreversible_warning')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr.text('final_reset_warning')),
              const SizedBox(height: 12),
              TextField(controller: finalController, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: tr.text('type_confirm_again'), border: const OutlineInputBorder()), onChanged: (value) => setState(() => finalOk = value.trim() == confirmationWord)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(AppLocalizations.of(context).text('cancel'))),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error), onPressed: finalOk ? () => Navigator.pop(dialogContext, true) : null, child: Text(tr.text('erase_everything'))),
          ],
        ),
      ),
    );
    if (finalConfirm != true) return;

    await store.factoryResetLocalDevice();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('host_reset_completed'))) );
    }
  }

  Future<bool?> _confirmBackupImport(BuildContext context, BackupSummary summary) async {
    final tr = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('confirm_backup_import')),
        content: ResponsiveDialogBox(
          maxWidth: VentioResponsive.modalMaxWidth(context, 420),
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


class _ScannerFeedbackSettingsCard extends StatefulWidget {
  const _ScannerFeedbackSettingsCard();

  @override
  State<_ScannerFeedbackSettingsCard> createState() => _ScannerFeedbackSettingsCardState();
}

class _ScannerFeedbackSettingsCardState extends State<_ScannerFeedbackSettingsCard> {
  late BarcodeFeedbackSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = BarcodeFeedbackService.loadSettings();
  }

  Future<void> _save(BarcodeFeedbackSettings value) async {
    setState(() => _settings = value);
    await BarcodeFeedbackService.saveSettings(value);
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: VentioResponsive.pageInsets(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.qr_code_scanner_outlined),
              title: Text(tr.text('scanner_feedback')),
              subtitle: Text(tr.text('scanner_feedback_desc')),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr.text('scanner_feedback_sound')),
              subtitle: Text(tr.text('scanner_feedback_sound_desc')),
              value: _settings.soundEnabled,
              onChanged: (value) => _save(_settings.copyWith(soundEnabled: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr.text('scanner_feedback_vibration')),
              subtitle: Text(tr.text('scanner_feedback_vibration_desc')),
              value: _settings.vibrationEnabled,
              onChanged: (value) => _save(_settings.copyWith(vibrationEnabled: value)),
            ),
            const SizedBox(height: 8),
            Text(tr.text('scanner_feedback_volume')),
            Slider(
              value: _settings.volume,
              onChanged: _settings.soundEnabled ? (value) => _save(_settings.copyWith(volume: value)) : null,
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => BarcodeFeedbackService.play(force: true),
                icon: const Icon(Icons.volume_up_outlined),
                label: Text(tr.text('test_scanner_feedback')),
              ),
            ),
          ],
        ),
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
      padding: VentioResponsive.cardInsets(context),
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
        const SizedBox(height: 12),
        _InfoGrid(
          items: [
            _InfoGridItem(Icons.store_outlined, tr.text('store_name'), summary.storeName),
            _InfoGridItem(Icons.new_releases_outlined, tr.text('backup_version'), 'V${summary.version}'),
            _InfoGridItem(Icons.event_outlined, tr.text('backup_date'), _formatDate(summary.generatedAt)),
            _InfoGridItem(Icons.inventory_2_outlined, tr.text('products'), summary.productsCount.toString()),
            _InfoGridItem(Icons.people_alt_outlined, tr.text('customers'), summary.customersCount.toString()),
            _InfoGridItem(Icons.point_of_sale_outlined, tr.text('sales'), summary.salesCount.toString()),
            _InfoGridItem(Icons.local_shipping_outlined, tr.text('suppliers'), summary.suppliersCount.toString()),
            _InfoGridItem(Icons.receipt_long_outlined, tr.text('expenses'), summary.expensesCount.toString()),
          ],
        ),
      ],
    );
  }
}


































enum _PairingCodeVisualStatus { active, expired, consumed, invalid, disabled }

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
  bool _latestLanPairingConsumed = false;
  bool _latestCloudPairingConsumed = false;
  bool _latestCloudPairingInvalid = false;
  DateTime? _lastCloudPairingStatusCheck;
  Timer? _pairingCountdownTimer;

  AppLocalizations get tr => AppLocalizations.of(context);

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
  int get _cloudInterval => int.tryParse(_cloudIntervalController.text.trim())?.clamp(5, 3600).toInt() ?? 5;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final tr = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _status = tr.text('working');
      _statusProgress = null;
    });
    try {
      await action();
      await widget.onSyncSettingsChanged?.call();
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = error.toString().contains('Pairing code expired or already used') ? tr.text('pairing_code_expired_or_used') : tr.text('sync_failed_check_info');
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
    _latestLanPairingConsumed = false;
    _showLanPairingCode = true;
    await LocalDatabaseService.setString(_lanPairingExpiryStorageKey, expiresAt.toIso8601String());
    if (mounted) setState(() => _status = tr.text('lan_pairing_code_created'));
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
      _latestCloudPairingInvalid = false;
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
      _refreshLanPairingConsumedState();
      if (_latestCloudPairingExpiresAt != null && !_latestCloudPairingExpiresAt!.isAfter(now)) _expireCloudPairingCode();
      if (_latestCloudPairingCode.trim().isNotEmpty && (_latestCloudPairingExpiresAt?.isAfter(now) ?? false)) {
        final lastCheck = _lastCloudPairingStatusCheck;
        if (lastCheck == null || now.difference(lastCheck).inSeconds >= 5) {
          _lastCloudPairingStatusCheck = now;
          unawaited(_refreshCloudPairingStatus());
        }
      }
      setState(() {});
    });
  }

  void _refreshLanPairingConsumedState() {
    final activeCode = _lanTokenController.text.trim();
    if (activeCode.isEmpty || _latestLanPairingConsumed) return;
    final expiresAt = _latestLanPairingExpiresAt;
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now())) return;
    final savedSecret = LanSyncSettings.load().secret.trim();
    if (savedSecret.isEmpty || savedSecret != activeCode) {
      _latestLanPairingConsumed = true;
      _showLanPairingCode = true;
    }
  }

  void _expireLanPairingCode() {
    _lanTokenController.clear();
    _latestLanPairingExpiresAt = null;
    _latestLanPairingConsumed = false;
    _showLanPairingCode = false;
    unawaited(LocalDatabaseService.deleteString(_lanPairingExpiryStorageKey));
    unawaited(LanSyncSettings.load().copyWith(secret: '').save());
  }

  void _expireCloudPairingCode() {
    _latestCloudPairingCode = '';
    _latestCloudPairingExpiresAt = null;
    _latestCloudPairingConsumed = false;
    _latestCloudPairingInvalid = false;
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


  Future<void> _refreshCloudPairingStatus() async {
    final code = _latestCloudPairingCode.trim();
    if (code.isEmpty || !widget.store.appIdentity.isHost) return;
    final settings = _cloudSettings(enabled: true);
    if (!settings.isConfigured || !settings.hasDeploymentToken) return;
    final result = await CloudSyncService(widget.store).pairingCodeStatus(settings, code);
    if (!mounted || !result.ok) return;
    setState(() {
      if (result.status == 'consumed') {
        _latestCloudPairingConsumed = true;
        _latestCloudPairingInvalid = false;
        _showCloudPairingCode = true;
      } else if (result.status == 'expired' || result.status == 'invalid') {
        _latestCloudPairingConsumed = false;
        _latestCloudPairingInvalid = result.status == 'invalid';
        _showCloudPairingCode = true;
        _latestCloudPairingExpiresAt = result.status == 'expired' ? DateTime.now().subtract(const Duration(seconds: 1)) : _latestCloudPairingExpiresAt;
      } else if (result.expiresAt != null) {
        _latestCloudPairingInvalid = false;
        _latestCloudPairingExpiresAt = result.expiresAt;
      }
    });
  }

  Future<bool> _confirmConnectToNewHost() async {
    final tr = AppLocalizations.of(context);
    if (!_hasExistingHostConnection) return true;
    const confirmationWord = 'CONFIRM';
    final controller = TextEditingController();
    var canContinue = false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(tr.text('connect_to_new_host')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr.text('connect_new_host_desc')),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: tr.text('type_confirm'), border: const OutlineInputBorder()),
                onChanged: (value) => setState(() => canContinue = value.trim() == confirmationWord),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(AppLocalizations.of(context).text('cancel'))),
            FilledButton(onPressed: canContinue ? () => Navigator.pop(dialogContext, true) : null, child: Text(tr.text('confirm'))),
          ],
        ),
      ),
    );
    return result == true;
  }

  String get _cloudPairingButtonLabel {
    final active = _latestCloudPairingCode.trim().isNotEmpty && (_latestCloudPairingExpiresAt?.isAfter(DateTime.now()) ?? false);
    if (!active) return AppLocalizations.of(context).text('generate_new_code');
    return _showCloudPairingCode ? AppLocalizations.of(context).text('hide_code') : AppLocalizations.of(context).text('show_code'); // stage1-final
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
    if (!active) return AppLocalizations.of(context).text('generate_new_code');
    return _showLanPairingCode ? AppLocalizations.of(context).text('hide_code') : AppLocalizations.of(context).text('show_code'); // stage1-final
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
            title: Text(AppLocalizations.of(context).text('approve_host_transfer')),
            content: Text(AppLocalizations.of(context).text('approve_host_transfer_desc').replaceAll('{deviceId}', deviceId)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(AppLocalizations.of(context).text('cancel'))),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(AppLocalizations.of(context).text('approve'))),
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
        builder: (_) => BarcodeScannerPage(
          title: AppLocalizations.of(context).text('scan_pairing_qr'),
          helpText: AppLocalizations.of(context).text('scan_pairing_qr_help'),
          formats: const [BarcodeFormat.qrCode],
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
      _status = tr.text('qr_detected_review_connect');
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
          _latestCloudPairingConsumed = false;
          _latestCloudPairingInvalid = false;
          _showCloudPairingCode = true;
          _status = tr.text('cloud_pairing_code_created');
        });
      });

  Future<void> _copyCloudPairingCode() async {
    final code = _latestCloudPairingCode.trim();
    if (code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).text('cloud_pairing_code_copied'))) );
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
        _latestLanPairingConsumed = true;
        _expireLanPairingCode();
        _expireCloudPairingCode();
        await CloudSyncSettings.load().copyWith(autoSyncEnabled: false, clearLastPullCursor: true).save();
        setState(() { _connectToNewHost = false; _status = tr.text('lan_client_connected_cloned'); });
      });

  Future<void> _claimCloudPairing() => _run(() async {
        if (!await _confirmConnectToNewHost()) return;
        final settings = _cloudSettings(enabled: true);
        await settings.save();
        final result = await _cloudEngine(enabled: true).claimPairingCode(_cloudPairingCodeController.text.trim());
        if (!result.ok) throw StateError(result.message);
        _latestCloudPairingConsumed = true;
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
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    final identity = widget.store.appIdentity;
    final lan = LanSyncSettings.load();
    final cloud = CloudSyncSettings.load();
    final isHost = _deviceRole == DeviceRole.host;
    final isCloudClient = !isHost && _clientSyncMode == SyncMode.cloudConnected;
    final needsInitialCloudHost = isHost && _cloudEnabled && !_initialCloudHostReady;
    final hostActionLabel = needsInitialCloudHost ? (_hostCreateFailed ? 'Retry Create Host' : 'Create New Host') : 'Sync Now';

    final lanActive = isHost ? _lanEnabledForHost : identity.syncMode == SyncMode.lanOnly;
    final cloudActive = isHost ? _cloudEnabled : identity.syncMode == SyncMode.cloudConnected;

    return Card(
      elevation: 0,
      child: Padding(
        padding: VentioResponsive.pageInsets(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.sync_outlined, color: color.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr.text('sync_settings'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(tr.text('sync_settings_desc'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (isHost)
                  FilledButton.icon(
                    onPressed: _busy ? null : (needsInitialCloudHost ? _createNewHost : _syncNow),
                    icon: Icon(needsInitialCloudHost ? Icons.add_business_outlined : Icons.sync_outlined),
                    label: Text(hostActionLabel),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _testHostConnection,
                    icon: const Icon(Icons.lan_outlined),
                    label: Text(tr.text('test_host_connection')),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (widget.store.latestHostTransferNotification != null) _hostChangedNotificationCard(),
            _syncSection(
              context,
              number: '1.',
              title: tr.text('connection_status'),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 760;
                  final tiles = [
                    _statusMetric(context, Icons.dns_outlined, tr.text('role'), isHost ? tr.text('host_device') : tr.text('client_device'), isHost ? tr.text('connection_role_host') : tr.text('connection_role_client'), color.primary),
                    _statusMetric(context, Icons.account_tree_outlined, tr.text('lan_connection'), lanActive ? tr.text('pairing_status_active') : tr.text('pairing_status_disabled'), lanActive ? tr.text('local_network_ready') : tr.text('not_enabled'), lanActive ? Colors.green : color.onSurfaceVariant),
                    _statusMetric(context, Icons.cloud_queue_outlined, tr.text('cloud_connection'), cloudActive ? tr.text('enabled') : tr.text('pairing_status_disabled'), cloudActive ? tr.text('cloud_services_online') : tr.text('cloud_sync_off'), cloudActive ? Colors.green : color.onSurfaceVariant),
                    _statusMetric(context, Icons.storage_outlined, tr.text('pending_changes'), '${widget.store.pendingSyncCount}', widget.store.pendingSyncCount == 0 ? tr.text('all_data_synchronized') : tr.text('needs_sync'), widget.store.pendingSyncCount == 0 ? color.primary : color.error),
                  ];
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: tiles.map((tile) => SizedBox(width: compact ? double.infinity : (constraints.maxWidth - 36) / 4, child: tile)).toList(),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            _syncSection(
              context,
              number: '2.',
              title: tr.text('sync_method'),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 720;
                  final lanCard = _methodCard(
                    context,
                    icon: Icons.lan_outlined,
                    title: tr.text('lan_sync'),
                    subtitle: tr.text('lan_sync_desc'),
                    enabled: lanActive,
                    badge: lanActive ? tr.text('enabled') : tr.text('off'),
                    accent: Colors.green,
                    trailing: isHost ? Switch(value: _lanEnabledForHost, onChanged: _busy ? null : (value) => setState(() => _lanEnabledForHost = value)) : null,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (isHost && _lanEnabledForHost) ...[
                        _hostIpInfoCard(),
                        ..._lanFields(showHostIp: false, forHost: true),
                      ] else if (!isHost && _clientSyncMode == SyncMode.lanOnly && (!_hasExistingHostConnection || _connectToNewHost)) ...[
                        ..._lanFields(showHostIp: true),
                      ] else ...[
                        _miniLine(tr.text('host_ip_address'), lan.host),
                        _miniLine(tr.text('port'), '${lan.port}'),
                      ],
                    ]),
                  );
                  final cloudCard = _methodCard(
                    context,
                    icon: Icons.cloud_outlined,
                    title: tr.text('cloud_sync'),
                    subtitle: tr.text('cloud_sync_desc'),
                    enabled: cloudActive,
                    badge: cloudActive ? tr.text('enabled') : tr.text('off'),
                    accent: Colors.blue,
                    trailing: isHost ? Switch(value: _cloudEnabled, onChanged: _busy ? null : (value) => setState(() => _cloudEnabled = value)) : null,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (isHost && _cloudEnabled) ..._cloudFields(showPairingCode: false)
                      else if (!isHost && _clientSyncMode == SyncMode.cloudConnected && (!_hasExistingHostConnection || _connectToNewHost)) ..._cloudFields(showPairingCode: true)
                      else ...[
                        _miniLine(tr.text('api_url'), cloud.apiBaseUrl.isEmpty ? '—' : cloud.apiBaseUrl),
                        _miniLine(tr.text('sync_interval'), tr.format('seconds_count', {'count': '${cloud.intervalSeconds}'})),
                      ],
                    ]),
                  );
                  if (compact) return Column(children: [lanCard, const SizedBox(height: 12), cloudCard]);
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: lanCard), const SizedBox(width: 14), Expanded(child: cloudCard)]);
                },
              ),
            ),
            const SizedBox(height: 14),
            _syncSection(
              context,
              number: '3.',
              title: isHost ? tr.text('pair_new_device') : tr.text('connect_device'),
              subtitle: isHost ? tr.text('pair_new_device_desc') : tr.text('connect_device_desc'),
              child: _pairingContent(context, isHost: isHost, isCloudClient: isCloudClient),
            ),
            const SizedBox(height: 14),
            _syncSection(
              context,
              number: '4.',
              title: tr.text('advanced_settings'),
              subtitle: tr.text('advanced_sync_settings_desc'),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(tr.text('show_advanced_actions')),
                children: [
                  _transferHostCard(isHost: isHost),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (isHost) OutlinedButton.icon(onPressed: _busy ? null : _testCloudConnection, icon: const Icon(Icons.cloud_done_outlined), label: Text(tr.text('test_cloud_connection'))),
                      if (!isHost) OutlinedButton.icon(onPressed: _busy ? null : _testHostConnection, icon: const Icon(Icons.lan_outlined), label: Text(tr.text('test_host_connection'))),
                      if (isHost) FilledButton.icon(onPressed: _busy ? null : _saveHostMode, icon: const Icon(Icons.save_outlined), label: Text(tr.text('save_host_settings'))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: VentioResponsive.cardInsets(context),
              decoration: BoxDecoration(color: color.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_busy ? (_status.isEmpty ? tr.text('working') : _status) : (_status.isEmpty ? _humanStatus(context) : _status)),
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

  Widget _pairingContent(BuildContext context, {required bool isHost, required bool isCloudClient}) {
    final tr = AppLocalizations.of(context);
    if (isHost) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(onPressed: _busy ? null : _handleLanPairingButton, icon: const Icon(Icons.qr_code_2_outlined), label: Text(_lanPairingButtonLabel)),
              OutlinedButton.icon(onPressed: _busy ? null : _handleCloudPairingButton, icon: const Icon(Icons.cloud_queue_outlined), label: Text(_cloudPairingButtonLabel)),
            ],
          ),
          if (_showLanPairingCode) ...[const SizedBox(height: 12), _lanPairingCodeCard()],
          if (_showCloudPairingCode) ...[const SizedBox(height: 12), _cloudPairingCodeCard()],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_hasExistingHostConnection && !_connectToNewHost) ...[
          _softNotice(
            context,
            Icons.check_circle_outline,
            tr.text('connection_status'),
            widget.store.appIdentity.hostDeviceId.trim().isNotEmpty
                ? tr.format('connected_to_host_summary', {
                    'storeId': widget.store.appIdentity.storeId,
                    'branchId': widget.store.appIdentity.branchId,
                    'hostDeviceId': widget.store.appIdentity.hostDeviceId,
                  })
                : tr.text('no_host_connected'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _busy ? null : () => setState(() => _connectToNewHost = true), icon: const Icon(Icons.add_link_outlined), label: Text(tr.text('connect_to_new_host'))),
        ] else ...[
          Text(tr.text('client_sync_type')),
          const SizedBox(height: 8),
          SegmentedButton<SyncMode>(
            segments: [
              ButtonSegment<SyncMode>(value: SyncMode.lanOnly, icon: const Icon(Icons.wifi_tethering_outlined), label: Text(tr.text('lan'))),
              ButtonSegment<SyncMode>(value: SyncMode.cloudConnected, icon: const Icon(Icons.cloud_outlined), label: Text(tr.text('cloud'))),
            ],
            selected: {_clientSyncMode},
            onSelectionChanged: _busy ? null : (value) => setState(() => _clientSyncMode = value.first),
          ),
          const SizedBox(height: 14),
          if (!isCloudClient) ...[
            Wrap(spacing: 10, runSpacing: 10, children: [
              OutlinedButton.icon(onPressed: _busy ? null : _scanPairingQr, icon: const Icon(Icons.qr_code_scanner_outlined), label: Text(tr.text('scan_qr_code'))),
              FilledButton.icon(onPressed: _busy ? null : _saveLanClient, icon: const Icon(Icons.link_outlined), label: Text(_hasExistingHostConnection ? tr.text('connect_to_new_lan_host') : tr.text('connect_to_lan_host'))),
            ]),
          ] else ...[
            Wrap(spacing: 10, runSpacing: 10, children: [
              OutlinedButton.icon(onPressed: _busy ? null : _scanPairingQr, icon: const Icon(Icons.qr_code_scanner_outlined), label: Text(tr.text('scan_qr_code'))),
              FilledButton.icon(onPressed: _busy ? null : _claimCloudPairing, icon: const Icon(Icons.cloud_done_outlined), label: Text(_hasExistingHostConnection ? tr.text('connect_to_new_cloud_host') : tr.text('pair_with_cloud_host'))),
            ]),
          ],
        ],
      ],
    );
  }

  Widget _syncSection(BuildContext context, {required String number, required String title, String? subtitle, required Widget child}) {
    final color = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
        color: color.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.outlineVariant.withValues(alpha: 0.75)),
        boxShadow: [BoxShadow(color: color.shadow.withValues(alpha: 0.04), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color.onSurface),
              children: [
                TextSpan(text: '$number ', style: TextStyle(color: color.primary)),
                TextSpan(text: title),
              ],
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color.onSurfaceVariant)),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _statusMetric(BuildContext context, IconData icon, String label, String value, String detail, Color accent) {
    final color = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: accent.withValues(alpha: 0.12), foregroundColor: accent, child: Icon(icon, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: accent)),
              const SizedBox(height: 2),
              Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color.onSurfaceVariant)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _methodCard(BuildContext context, {required IconData icon, required String title, required String subtitle, required bool enabled, required String badge, required Color accent, Widget? trailing, required Widget child}) {
    final color = Theme.of(context).colorScheme;
    return Container(
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
        color: enabled ? accent.withValues(alpha: 0.06) : color.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: enabled ? accent.withValues(alpha: 0.28) : color.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: enabled ? accent : color.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color.onSurfaceVariant)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
              child: Text(badge, style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ]),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _miniLine(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [Expanded(child: Text(title)), Text(value, style: const TextStyle(fontWeight: FontWeight.w600))]),
    );
  }

  Widget _softNotice(BuildContext context, IconData icon, String title, String value) {
    final color = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.surfaceContainerHighest.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [Icon(icon), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w600)), Text(value)]))]),
    );
  }

  String _humanStatus(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final identity = widget.store.appIdentity;
    if (identity.isHost) {
      final lan = LanSyncSettings.load();
      final cloud = CloudSyncSettings.load();
      return '${tr.text('connection_role_host')} • ${tr.text('connection_lan')}: ${lan.setupComplete && lan.isHost ? tr.text('connection_lan_enabled') : tr.text('connection_lan_disabled')} • ${tr.text('connection_cloud')}: ${identity.isCloudEnabled && cloud.isConfigured ? tr.text('connection_cloud_enabled') : tr.text('connection_cloud_disabled')}';
    }
    return '${tr.text('connection_role_client')} • ${identity.syncMode == SyncMode.cloudConnected ? tr.text('connection_cloud') : identity.syncMode == SyncMode.lanOnly ? tr.text('connection_lan') : tr.text('connection_local')}';
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
      padding: VentioResponsive.cardInsets(context),
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
            child: Text(AppLocalizations.of(context).text('host_changed_notification').replaceAll('{storeId}', storeId).replaceAll('{branchId}', branchId).replaceAll('{deviceId}', newHostDeviceId)),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).text('dismiss'),
            onPressed: _busy ? null : () { widget.store.clearHostTransferNotification(); },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _transferHostCard({required bool isHost}) {
    final tr = AppLocalizations.of(context);
    final pending = widget.store.pendingHostTransferRequest;
    final approvedForThisDevice = widget.store.approvedHostTransferDeviceId == widget.store.deviceId;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: VentioResponsive.cardInsets(context),
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
              Expanded(child: Text(tr.text('transfer_host_role'), style: Theme.of(context).textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 8),
          if (isHost) ...[
            Text(tr.text('transfer_host_role_desc')),
            const SizedBox(height: 8),
            if (pending != null) ...[
              Text(tr.text('latest_request').replaceAll('{deviceId}', (pending['requestingDeviceId'] ?? tr.text('unknown_device')).toString())),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => setState(() => _transferDeviceController.text = (pending['requestingDeviceId'] ?? '').toString()),
                icon: const Icon(Icons.input_outlined),
                label: Text(tr.text('use_latest_request')),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _transferDeviceController,
              decoration: InputDecoration(labelText: tr.text('client_device_id_to_approve'), border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _approveHostTransferFromUi,
                icon: const Icon(Icons.verified_user_outlined),
                label: Text(tr.text('approve_host_transfer')),
              ),
            ),
          ] else ...[
            Text(tr.text('this_client_device_id').replaceAll('{deviceId}', widget.store.deviceId)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _requestHostTransfer,
                icon: const Icon(Icons.outbox_outlined),
                label: Text(tr.text('request_to_become_host')),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy || !approvedForThisDevice ? null : _activateApprovedHostTransferFromUi,
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: Text(tr.text('activate_approved_host_transfer')),
              ),
            ),
            if (!approvedForThisDevice) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(tr.text('host_transfer_activation_hint')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _hostIpInfoCard() {
    final tr = AppLocalizations.of(context);
    final ipText = _detectingHostIp
        ? tr.text('detecting_local_ip')
        : (_hostIpAddresses.isEmpty ? tr.text('no_local_ipv4') : _hostIpAddresses.join('  •  '));
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: VentioResponsive.cardInsets(context),
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
                Text(tr.text('host_ip_address'), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(ipText),
                const SizedBox(height: 4),
                Text(tr.text('host_ip_desc')),
              ],
            ),
          ),
          IconButton(
            tooltip: tr.text('refresh_ip'),
            onPressed: _busy || _detectingHostIp ? null : _refreshHostIpAddresses,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
    );
  }


  _PairingCodeVisualStatus _pairingVisualStatus({
    required String code,
    required DateTime? expiresAt,
    required bool consumed,
    bool invalid = false,
  }) {
    if (invalid) return _PairingCodeVisualStatus.invalid;
    if (consumed) return _PairingCodeVisualStatus.consumed;
    if (code.trim().isEmpty) return _PairingCodeVisualStatus.disabled;
    if (expiresAt == null) return _PairingCodeVisualStatus.invalid;
    if (!expiresAt.isAfter(DateTime.now())) return _PairingCodeVisualStatus.expired;
    return _PairingCodeVisualStatus.active;
  }

  ({String label, IconData icon, Color background, Color foreground}) _pairingStatusData(
    BuildContext context,
    _PairingCodeVisualStatus status,
  ) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    return switch (status) {
      _PairingCodeVisualStatus.active => (label: tr.text('pairing_status_active'), icon: Icons.check_circle_outline, background: Colors.green.withValues(alpha: 0.12), foreground: Colors.green.shade700),
      _PairingCodeVisualStatus.expired => (label: tr.text('pairing_status_expired'), icon: Icons.timer_off_outlined, background: Colors.grey.withValues(alpha: 0.16), foreground: color.onSurfaceVariant),
      _PairingCodeVisualStatus.consumed => (label: tr.text('pairing_status_consumed'), icon: Icons.done_all_outlined, background: Colors.green.withValues(alpha: 0.12), foreground: Colors.green.shade700),
      _PairingCodeVisualStatus.invalid => (label: tr.text('pairing_status_invalid'), icon: Icons.error_outline, background: color.errorContainer, foreground: color.onErrorContainer),
      _PairingCodeVisualStatus.disabled => (label: tr.text('pairing_status_disabled'), icon: Icons.block_outlined, background: Colors.grey.withValues(alpha: 0.16), foreground: color.onSurfaceVariant),
    };
  }

  Widget _pairingStatusBadge(BuildContext context, _PairingCodeVisualStatus status) {
    final data = _pairingStatusData(context, status);
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

  Color _pairingBorderColor(BuildContext context, _PairingCodeVisualStatus status) {
    final color = Theme.of(context).colorScheme;
    return switch (status) {
      _PairingCodeVisualStatus.active => Colors.green,
      _PairingCodeVisualStatus.consumed => Colors.green,
      _PairingCodeVisualStatus.expired => Colors.grey,
      _PairingCodeVisualStatus.invalid => color.error,
      _PairingCodeVisualStatus.disabled => color.outlineVariant,
    };
  }

  Widget _lanPairingCodeCard() {
    final tr = AppLocalizations.of(context);
    final code = _lanTokenController.text.trim();
    if (code.isEmpty) return const SizedBox.shrink();
    final host = _lanHostController.text.trim().isNotEmpty ? _lanHostController.text.trim() : LanSyncSettings.load().host;
    final status = _pairingVisualStatus(code: code, expiresAt: _latestLanPairingExpiresAt, consumed: _latestLanPairingConsumed);
    final borderColor = _pairingBorderColor(context, status);
    final payload = jsonEncode({
      'transport': 'lan',
      'host': host,
      'port': _lanPort,
      'pairingCode': code,
      'expiresAt': _latestLanPairingExpiresAt?.toIso8601String(),
    });
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: VentioResponsive.pageInsets(context),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor.withValues(alpha: 0.65), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_2_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text(tr.text('lan_one_time_pairing_code'), style: Theme.of(context).textTheme.titleMedium)),
              _pairingStatusBadge(context, status),
              const SizedBox(width: 8),
              IconButton(
                tooltip: tr.text('copy_code'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('lan_pairing_code_copied'))) );
                },
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: VentioResponsive.cardInsets(context),
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
              labelText: tr.text('code'),
              helperText: status == _PairingCodeVisualStatus.active
                  ? tr.format('expires_in', {'time': _countdownText(_latestLanPairingExpiresAt)})
                  : tr.format('pairing_code_state_help', {'status': _pairingStatusData(context, status).label.toLowerCase()}),
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
    final tr = AppLocalizations.of(context);
    final code = _latestCloudPairingCode.trim();
    if (code.isEmpty) {
      return const SizedBox.shrink();
    }
    final status = _pairingVisualStatus(code: code, expiresAt: _latestCloudPairingExpiresAt, consumed: _latestCloudPairingConsumed, invalid: _latestCloudPairingInvalid);
    final borderColor = _pairingBorderColor(context, status);
    final expiresText = status == _PairingCodeVisualStatus.active
        ? tr.format('expires_in', {'time': _countdownText(_latestCloudPairingExpiresAt)})
        : tr.format('pairing_code_state_help', {'status': _pairingStatusData(context, status).label.toLowerCase()});
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: VentioResponsive.pageInsets(context),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor.withValues(alpha: 0.65), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_2_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text(tr.text('cloud_pairing_code'), style: Theme.of(context).textTheme.titleMedium)),
              _pairingStatusBadge(context, status),
              const SizedBox(width: 8),
              IconButton(
                tooltip: tr.text('copy_code'),
                onPressed: _copyCloudPairingCode,
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: VentioResponsive.cardInsets(context),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: jsonEncode({'transport': 'cloud', 'apiBaseUrl': _cloudApiController.text.trim(), 'pairingCode': code, 'expiresAt': _latestCloudPairingExpiresAt?.toIso8601String()}),
                version: QrVersions.auto,
                size: 180,
              ),
            ),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: InputDecoration(
              labelText: tr.text('code'),
              helperText: expiresText,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: tr.text('copy_code'),
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
          TextField(controller: _lanHostController, decoration: InputDecoration(labelText: AppLocalizations.of(context).text('manual_host_ip_optional'), border: const OutlineInputBorder())),
        if (showHostIp) const SizedBox(height: 12),
        TextField(controller: _lanPortController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: AppLocalizations.of(context).text('port'), border: const OutlineInputBorder())),
        const SizedBox(height: 12),
        if (!forHost) ...[
          TextField(
            controller: _lanTokenController,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).text('lan_pairing_code_label'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ];

  List<Widget> _cloudFields({required bool showPairingCode}) => [
        TextField(
          controller: _cloudApiController,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context).text('cloud_api_url'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (showPairingCode)
          TextField(
            controller: _cloudPairingCodeController,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).text('pairing_code_from_host'),
              border: const OutlineInputBorder(),
            ),
          ),
        if (showPairingCode) const SizedBox(height: 12),
        if (!showPairingCode)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.tune_outlined),
            title: Text(AppLocalizations.of(context).text('advanced_cloud_settings')),
            subtitle: Text(AppLocalizations.of(context).text('advanced_cloud_settings_desc')),
            childrenPadding: const EdgeInsets.only(top: 8, bottom: 8),
            children: [
              TextField(
                controller: _cloudTokenController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).text('cloud_token_label'),
                  helperText: AppLocalizations.of(context).text('cloud_token_helper_professional'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cloudIntervalController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).text('auto_sync_interval_seconds'),
                  border: const OutlineInputBorder(),
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
        title: Text(AppLocalizations.of(context).text('advanced_debug_information')),
        subtitle: Text(AppLocalizations.of(context).text('advanced_debug_information_desc')),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _Line(title: AppLocalizations.of(context).text('device_id'), value: store.deviceId),
          _Line(title: AppLocalizations.of(context).text('store_id'), value: store.appIdentity.storeId),
          _Line(title: AppLocalizations.of(context).text('branch_id'), value: store.appIdentity.branchId),
          _Line(title: AppLocalizations.of(context).text('role'), value: store.appIdentity.deviceRole.name),
          _Line(title: AppLocalizations.of(context).text('sync_mode'), value: store.appIdentity.syncMode.name),
          _Line(title: AppLocalizations.of(context).text('pending_changes'), value: '${store.pendingSyncCount}'),
          _Line(title: AppLocalizations.of(context).text('pending_queue'), value: '${store.pendingSyncQueueCount}'),
        ],
      ),
    );
  }
}



class _SettingsNavData {
  const _SettingsNavData({required this.icon, required this.label, required this.description});

  final IconData icon;
  final String label;
  final String description;
}

class _SettingsSideNav extends StatelessWidget {
  const _SettingsSideNav({required this.items, required this.selectedIndex, required this.onSelected, required this.store});

  final List<_SettingsNavData> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SettingsNavItem(
              item: items[i],
              selected: selectedIndex == i,
              onTap: () => onSelected(i),
            ),
          ),
        const SizedBox(height: 18),
        _SystemStatusPanel(store: store),
      ],
    );
  }
}

class _SettingsNavItem extends StatelessWidget {
  const _SettingsNavItem({required this.item, required this.selected, required this.onTap});

  final _SettingsNavData item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primaryContainer.withValues(alpha: 0.45) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? colorScheme.primary.withValues(alpha: 0.14) : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(item.icon, color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.label, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: selected ? colorScheme.primary : null, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(item.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _SystemStatusPanel extends StatelessWidget {
  const _SystemStatusPanel({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final identity = store.appIdentity;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.verified_user_outlined, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('System Status', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          _StatusBullet(label: identity.isHost ? 'Host Device' : 'Client Device'),
          const _StatusBullet(label: 'LAN Active'),
          _StatusBullet(label: identity.isCloudEnabled ? 'Cloud Online' : 'Cloud Disabled'),
          const _StatusBullet(label: 'Sync Active'),
          const Divider(height: 22),
          Text('All systems are running smoothly', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _StatusBullet extends StatelessWidget {
  const _StatusBullet({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(Icons.circle, size: 9, color: Colors.green.shade600),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.icon, required this.title, required this.subtitle, required this.child, this.trailing});

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      child: Padding(
        padding: VentioResponsive.pageInsets(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              ],
            ),
            const Divider(height: 28),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.title, required this.value});

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.7)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 14),
          SizedBox(width: VentioResponsive.adaptiveWidth(context, mobile: 120, tablet: 150, desktop: 170), child: Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _InfoGridItem {
  const _InfoGridItem(this.icon, this.title, this.value);
  final IconData icon;
  final String title;
  final String value;
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.items});

  final List<_InfoGridItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 3 : constraints.maxWidth >= 560 ? 2 : 1;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in items)
              SizedBox(
                width: (constraints.maxWidth - (columns - 1) * 12) / columns,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(item.icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 5),
                            Text(item.value, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleSmall),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(constraints: BoxConstraints(maxWidth: VentioResponsive.adaptiveWidth(context, mobile: 96, tablet: 120, desktop: 130)), child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Expanded(child: Text(value, style: Theme.of(context).textTheme.titleSmall)),
            ],
          );
        },
      ),
    );
  }
}



class _SecureRecoveryLine extends StatelessWidget {
  const _SecureRecoveryLine({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ),
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
    return _SectionCard(
      icon: Icons.hub_outlined,
      title: tr.text('system_foundation'),
      subtitle: tr.text('system_foundation_desc'),
      trailing: Chip(
        avatar: const Icon(Icons.lock_outline, size: 16),
        label: Text(tr.text('read_only')),
      ),
      child: _InfoGrid(
        items: [
          _InfoGridItem(Icons.tag_outlined, tr.text('store_id'), identity.storeId),
          _InfoGridItem(Icons.business_outlined, tr.text('branch_id'), identity.branchId),
          _InfoGridItem(Icons.devices_outlined, tr.text('device_id'), identity.deviceId),
          _InfoGridItem(Icons.computer_outlined, tr.text('platform'), identity.platform.name),
          _InfoGridItem(Icons.dns_outlined, tr.text('device_role'), identity.deviceRole.name),
          _InfoGridItem(Icons.badge_outlined, tr.text('app_role'), identity.appRole.name),
          _InfoGridItem(Icons.sync_outlined, tr.text('sync_mode'), identity.isHost ? tr.text('host_lan_cloud_controlled') : identity.syncMode.name),
          _InfoGridItem(Icons.cloud_outlined, tr.text('cloud_tenant'), identity.cloudTenantId.isEmpty ? '—' : identity.cloudTenantId),
        ],
      ),
    );
  }
}
