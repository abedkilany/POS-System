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
import '../../core/shortcuts/app_shortcuts.dart';
import '../../core/sync_unified/sync_device_state.dart';
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
      _SettingsNavData(icon: Icons.keyboard_command_key_outlined, label: tr.text('keyboard_shortcuts'), description: tr.text('keyboard_shortcuts_desc')),
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
            _settingsList(context, _shortcutCards(context)),
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
              SegmentedButton<Locale>(
                segments: [
                  ButtonSegment<Locale>(value: const Locale('en'), label: Text(tr.text('language_english'))),
                  ButtonSegment<Locale>(value: const Locale('ar'), label: Text(tr.text('language_arabic'))),
                ],
                selected: {tr.locale},
                onSelectionChanged: (selection) => onLocaleChanged(selection.first),
              ),
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
            _InfoGridItem(Icons.receipt_long_outlined, tr.text('default_sale_invoice_currency'), profile.defaultSaleInvoiceCurrency),
            _InfoGridItem(Icons.payments_outlined, tr.text('default_sale_payment_currency'), profile.defaultSalePaymentCurrency),
            _InfoGridItem(Icons.tune_outlined, tr.text('lbp_rounding'), profile.lbpRounding <= 0 ? tr.text('no_rounding') : '${profile.lbpRounding} LBP'),
          ],
        ),
      ),
    ];
  }


  List<Widget> _shortcutCards(BuildContext context) => [
        const _KeyboardShortcutsSettingsCard(),
      ];

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
              Align(alignment: AlignmentDirectional.centerStart, child: Padding(padding: const EdgeInsets.only(bottom: 12), child: Chip(avatar: const Icon(Icons.storage_outlined, size: 18), label: Text(tr.text('local_db_hive'))))),
              _BackupSummaryCard(summary: store.currentBackupSummary),
              const SizedBox(height: 16),
              Text(tr.text('actions'), style: Theme.of(context).textTheme.titleSmall),
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
                  Text(isHost ? tr.text('data_management_desc') : tr.text('client_maintenance_desc')),
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
    String defaultSaleInvoiceCurrency = profile.defaultSaleInvoiceCurrency.toUpperCase() == 'LBP' ? 'LBP' : 'USD';
    String defaultSalePaymentCurrency = profile.defaultSalePaymentCurrency.toUpperCase() == 'LBP' ? 'LBP' : 'USD';
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
                    DropdownButtonFormField<String>(
                      initialValue: defaultSaleInvoiceCurrency,
                      decoration: InputDecoration(labelText: tr.text('default_sale_invoice_currency')),
                      items: const [
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                        DropdownMenuItem(value: 'LBP', child: Text('LBP')),
                      ],
                      onChanged: (value) => setState(() => defaultSaleInvoiceCurrency = value ?? 'USD'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: defaultSalePaymentCurrency,
                      decoration: InputDecoration(labelText: tr.text('default_sale_payment_currency')),
                      items: const [
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                        DropdownMenuItem(value: 'LBP', child: Text('LBP')),
                      ],
                      onChanged: (value) => setState(() => defaultSalePaymentCurrency = value ?? 'USD'),
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
                    defaultSaleInvoiceCurrency: defaultSaleInvoiceCurrency,
                    defaultSalePaymentCurrency: defaultSalePaymentCurrency,
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
                        name: nameController.text.trim().isEmpty ? tr.text('my_store') : nameController.text.trim(),
                        phone: phoneController.text.trim(),
                        address: addressController.text.trim(),
                        // Keep the legacy currency value for backward compatibility only.
                        // Currency selection is now managed exclusively from Financial Settings.
                        currency: profile.currency,
                        footerNote: footerController.text.trim().isEmpty ? tr.text('default_invoice_footer') : footerController.text.trim(),
                        usdToLbpRate: profile.usdToLbpRate,
                        priceDisplayMode: profile.priceDisplayMode,
                        defaultProductCurrency: profile.defaultProductCurrency,
                        defaultSaleInvoiceCurrency: profile.defaultSaleInvoiceCurrency,
                        defaultSalePaymentCurrency: profile.defaultSalePaymentCurrency,
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
      await downloadTextFile(filename: filename, content: store.exportRecoveryFileJson(cloudApiUrl: cloud.apiBaseUrl), dialogTitle: tr.text('save_recovery_file'), cancelMessage: tr.text('file_save_cancelled'));
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
      await downloadTextFile(filename: filename, content: store.exportBackupJson(), dialogTitle: tr.text('save_backup_file'), cancelMessage: tr.text('file_save_cancelled'));
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
        throw Exception(validation.errorMessage ?? tr.text('invalid_backup_file'));
      }

      if (!context.mounted) return;
      final confirmed = await _confirmBackupImport(context, validation.summary!);
      if (!context.mounted || confirmed != true) return;

      await store.importBackupJson(raw);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('backup_file_imported'))));
        await _pushHostCriticalEventToCloud(context, tr.text('import_backup_action'));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('backup_file_import_failed'))));
      }
    }
  }



  Future<void> _recoverExistingStore(BuildContext context) async {
    final tr = AppLocalizations.of(context);
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizeRuntimeMessage(result.message, tr))));
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
                Text(AppLocalizations.of(context).text('clear_local_data_warning')),
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

    final service = CloudSyncService(store);
    // Backup import replaces the full Host dataset. Publish a fresh materialized
    // Cloud snapshot before pushing the small restore marker, so Clients that
    // receive the marker can immediately rebuild from the new Host data.
    await service.publishBootstrapSnapshotToCloud(cloud, force: true);
    final result = await UnifiedSyncEngine(
      CloudSyncTransportAdapter(
        service: service,
        settings: cloud,
      ),
    ).syncNow();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.ok ? '$actionName ${tr.text('cloud_push_success')}' : '$actionName ${tr.text('cloud_push_failed')}: ${localizeRuntimeMessage(result.message, tr)}')),
      );
    }
  }

  Future<void> _rebuildFromHost(BuildContext context) async {
    final tr = AppLocalizations.of(context);
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
      _OperationProgress(0.05, tr.text('preparing_rebuild_percent')),
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
      progress.value = _OperationProgress(0.20, tr.text('resetting_local_client_state_percent'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (identity.syncMode == SyncMode.cloudConnected || identity.syncMode == SyncMode.marketplaceEnabled) {
        progress.value = _OperationProgress(0.40, tr.text('contacting_cloud_host_snapshot_percent'));
        final result = await UnifiedSyncEngine(
          CloudSyncTransportAdapter(
            service: CloudSyncService(store),
            settings: CloudSyncSettings.load(),
          ),
        ).rebuildFromHostSnapshot(
          onProgress: (value, label) => progress.value = _OperationProgress(value, '$label ${(value * 100).round()}%'),
        );
        progress.value = _OperationProgress(result.ok ? 1.0 : 0.90, result.ok ? tr.text('cloud_rebuild_completed_percent') : tr.text('cloud_rebuild_failed_verifying_percent'));
        message = localizeRuntimeMessage(result.message, tr);
        success = result.ok;
      } else {
        final settings = LanSyncSettings.load();
        progress.value = _OperationProgress(0.40, tr.text('contacting_lan_host_percent'));
        final result = await UnifiedSyncEngine(
          LanSyncTransportAdapter(
            service: LanSyncService(store),
            settings: settings,
          ),
        ).rebuildFromHostSnapshot(
          onProgress: (value, label) => progress.value = _OperationProgress(value, '$label ${(value * 100).round()}%'),
        );
        progress.value = _OperationProgress(result.ok ? 1.0 : 0.90, result.ok ? tr.text('lan_rebuild_completed_percent') : tr.text('lan_rebuild_failed_verifying_percent'));
        message = localizeRuntimeMessage(result.message, tr);
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

class _ScannedPairingPayload {
  const _ScannedPairingPayload({
    required this.raw,
    required this.code,
    required this.transport,
    required this.host,
    required this.port,
    required this.apiBaseUrl,
    required this.storeId,
    required this.branchId,
    required this.hostDeviceId,
    required this.cloudTenantId,
  });

  final String raw;
  final String code;
  final String transport;
  final String host;
  final String port;
  final String apiBaseUrl;
  final String storeId;
  final String branchId;
  final String hostDeviceId;
  final String cloudTenantId;
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
  final _lanIntervalController = TextEditingController();
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
  DateTime? _latestLanPairingExpiresAt;
  bool _latestLanPairingConsumed = false;
  bool _latestCloudPairingConsumed = false;
  bool _latestCloudPairingInvalid = false;
  DateTime? _lastCloudPairingStatusCheck;
  Timer? _pairingCountdownTimer;
  String _expectedPairingStoreId = '';
  String _expectedPairingBranchId = '';
  String _expectedPairingHostDeviceId = '';
  String _expectedPairingCloudTenantId = '';

  AppLocalizations get tr => AppLocalizations.of(context);

  static const _lanPairingExpiryStorageKey = 'lan_pairing_expires_at_v1';
  static const _cloudPairingCodeStorageKey = 'cloud_pairing_code_v1';
  static const _cloudPairingExpiryStorageKey = 'cloud_pairing_expires_at_v1';
  static const _pairingCodeLifetime = Duration(minutes: 5);
  String get _initialCloudHostReadyKey => 'cloud_initial_snapshot_ready_${widget.store.appIdentity.storeId}';

  @override
  void initState() {
    super.initState();
    final identity = widget.store.appIdentity;
    final lan = LanSyncSettings.load();
    final cloud = CloudSyncSettings.load();
    _deviceRole = identity.isClient ? DeviceRole.client : DeviceRole.host;
    _clientSyncMode = identity.activeSyncTransportNormalized == 'cloud' ? SyncMode.cloudConnected : SyncMode.lanOnly;
    _lanEnabledForHost = identity.isHost && lan.setupComplete && lan.isHost;
    _cloudEnabled = identity.isCloudEnabled && cloud.isConfigured;
    _lanHostController.text = lan.host;
    _lanPortController.text = lan.port.toString();
    _lanIntervalController.text = lan.intervalSeconds.toString();
    _lanTokenController.text = lan.secret.trim();
    _cloudApiController.text = cloud.apiBaseUrl;
    _cloudTokenController.text = cloud.apiToken;
    _cloudIntervalController.text = cloud.intervalSeconds.toString();
    for (final controller in [
      _lanHostController,
      _lanPortController,
      _lanIntervalController,
      _lanTokenController,
      _cloudApiController,
      _cloudTokenController,
      _cloudPairingCodeController,
      _cloudIntervalController,
    ]) {
      controller.addListener(_onSyncDraftChanged);
    }
    _loadActivePairingCodes();
    _startPairingCountdownTimer();
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
    _cloudApiController.dispose();
    _cloudTokenController.dispose();
    _cloudPairingCodeController.dispose();
    _cloudIntervalController.dispose();
    _transferDeviceController.dispose();
    _pairingCountdownTimer?.cancel();
    super.dispose();
  }

  int get _lanPort => int.tryParse(_lanPortController.text.trim()) ?? 8787;
  int get _lanInterval => int.tryParse(_lanIntervalController.text.trim())?.clamp(5, 3600).toInt() ?? LanSyncSettings.defaultIntervalSeconds;
  int get _cloudInterval => int.tryParse(_cloudIntervalController.text.trim())?.clamp(5, 3600).toInt() ?? 15;

  void _onSyncDraftChanged() {
    if (mounted) setState(() {});
  }

  bool get _hasUnsavedSyncChanges {
    final identity = widget.store.appIdentity;
    final lan = LanSyncSettings.load();
    final cloud = CloudSyncSettings.load();
    final role = identity.isClient ? DeviceRole.client : DeviceRole.host;
    final clientMode = identity.activeSyncTransportNormalized == 'cloud' ? SyncMode.cloudConnected : SyncMode.lanOnly;
    final lanEnabled = identity.isHost && lan.setupComplete && lan.isHost;
    final cloudEnabled = identity.isCloudEnabled && cloud.isConfigured;
    return _deviceRole != role ||
        _clientSyncMode != clientMode ||
        _lanEnabledForHost != lanEnabled ||
        _cloudEnabled != cloudEnabled ||
        _lanHostController.text.trim() != lan.host.trim() ||
        _lanPortController.text.trim() != lan.port.toString() ||
        _lanIntervalController.text.trim() != lan.intervalSeconds.toString() ||
        _cloudApiController.text.trim() != cloud.apiBaseUrl.trim() ||
        _cloudTokenController.text.trim() != cloud.apiToken.trim() ||
        _cloudIntervalController.text.trim() != cloud.intervalSeconds.toString();
  }

  void _resetSyncDraft({String? status}) {
    final identity = widget.store.appIdentity;
    final lan = LanSyncSettings.load();
    final cloud = CloudSyncSettings.load();
    setState(() {
      _deviceRole = identity.isClient ? DeviceRole.client : DeviceRole.host;
      _clientSyncMode = identity.activeSyncTransportNormalized == 'cloud' ? SyncMode.cloudConnected : SyncMode.lanOnly;
      _lanEnabledForHost = identity.isHost && lan.setupComplete && lan.isHost;
      _cloudEnabled = identity.isCloudEnabled && cloud.isConfigured;
      _lanHostController.text = lan.host;
      _lanPortController.text = lan.port.toString();
      _lanIntervalController.text = lan.intervalSeconds.toString();
      _cloudApiController.text = cloud.apiBaseUrl;
      _cloudTokenController.text = cloud.apiToken;
      _cloudIntervalController.text = cloud.intervalSeconds.toString();
      _status = status ?? AppLocalizations.of(context).text('cancelled');
    });
  }

  Future<void> _testCurrentConnection() async {
    final identity = widget.store.appIdentity;
    if (identity.isHost || _deviceRole == DeviceRole.host) {
      await _testPairedClientConnections();
      return;
    }
    final shouldTestCloud = identity.activeSyncTransportNormalized == 'cloud';
    if (shouldTestCloud) {
      await _testCloudConnection();
    } else {
      await _testHostConnection();
    }
  }

  String _simpleSyncError(Object error, {required String fallback}) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('pairing code expired') || lower.contains('already used')) {
      return tr.text('pairing_code_expired_or_used');
    }
    if (lower.contains('socketexception') || lower.contains('clientexception') || lower.contains('timeoutexception') || lower.contains('failed host lookup')) {
      return fallback;
    }
    if (lower.contains('null check operator used on a null value')) {
      return tr.text('pairing_state_refresh_failed');
    }
    return fallback;
  }

  Future<void> _saveSyncSettings() => _run(() async {
        final identity = widget.store.appIdentity;
        final tr = AppLocalizations.of(context);
        if (_deviceRole == DeviceRole.host) {
          await widget.store.updateAppIdentityLocalOnly(
            identity.copyWith(
              deviceRole: DeviceRole.host,
              syncMode: _cloudEnabled ? SyncMode.cloudConnected : (_lanEnabledForHost ? SyncMode.lanOnly : SyncMode.localOnly),
              activeSyncTransport: _cloudEnabled ? 'cloud' : (_lanEnabledForHost ? 'lan' : 'local'),
            ),
            source: 'sync settings save',
          );
          final existingLan = LanSyncSettings.load();
          final migratedLan = existingLan.withMigratedHostRegistry(widget.store.deviceId);
          await LanSyncSettings(
            host: _lanHostController.text.trim().isEmpty ? migratedLan.host : _lanHostController.text.trim(),
            port: _lanPort,
            intervalSeconds: _lanInterval,
            autoSyncEnabled: _lanEnabledForHost,
            hostModeEnabled: _lanEnabledForHost,
            setupComplete: _lanEnabledForHost,
            mode: _lanEnabledForHost ? LanSyncDeviceMode.host : LanSyncDeviceMode.unconfigured,
            secret: migratedLan.secret,
            pairedDevices: migratedLan.pairedDevices,
            hostRegistry: migratedLan.hostRegistry,
          ).save();
          await _cloudSettings(enabled: _cloudEnabled).save();
          if (!_cloudEnabled) await LocalDatabaseService.deleteString(_initialCloudHostReadyKey);
        } else {
          final activeTransport = _clientSyncMode == SyncMode.cloudConnected ? 'cloud' : 'lan';
          final lanSettings = LanSyncSettings.load();
          final cloudSettings = CloudSyncSettings.load();
          final lanConfigured = _isLanClientConfigured(lanSettings);
          final cloudConfigured = _isCloudClientConfigured(cloudSettings);
          if (activeTransport == 'lan' && !lanConfigured) {
            throw Exception(tr.text('lan_not_configured_cannot_switch'));
          }
          if (activeTransport == 'cloud' && !cloudConfigured) {
            throw Exception(tr.text('cloud_not_configured_cannot_switch'));
          }
          await widget.store.updateAppIdentityLocalOnly(
            identity.copyWith(
              deviceRole: DeviceRole.client,
              syncMode: _clientSyncMode,
              activeSyncTransport: activeTransport,
            ),
            source: 'sync settings save',
          );
          await lanSettings.copyWith(
            autoSyncEnabled: activeTransport == 'lan',
            hostModeEnabled: false,
            intervalSeconds: _lanInterval,
          ).save();
          await cloudSettings.copyWith(
            autoSyncEnabled: activeTransport == 'cloud',
          ).save();
          await widget.store.setActiveSyncTransport(activeTransport);
        }
        if (mounted) {
          _resetSyncDraft(status: AppLocalizations.of(context).text('sync_settings_saved'));
        }
      });

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
          _status = _simpleSyncError(error, fallback: tr.text('sync_failed_check_info'));
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

  CloudSyncSettings _cloudSettings({bool enabled = true, bool? autoSyncEnabled}) {
    final fallback = kIsWeb ? Uri.base.origin : '';
    final normalizedUrl = CloudSyncSettings.normalizeApiBaseUrl(
      _cloudApiController.text.trim().isEmpty ? fallback : _cloudApiController.text.trim(),
      fallback: fallback,
    );
    if (_cloudApiController.text.trim() != normalizedUrl) {
      _cloudApiController.text = normalizedUrl;
    }
    return CloudSyncSettings.load().copyWith(
      enabled: enabled,
      apiBaseUrl: normalizedUrl,
      apiToken: _cloudTokenController.text.trim(),
      autoSyncEnabled: autoSyncEnabled ?? enabled,
      intervalSeconds: _cloudInterval,
    );
  }

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
    final savedLan = LanSyncSettings.load();
    final identity = widget.store.appIdentity;
    final lanEnabled = identity.isHost && savedLan.setupComplete && savedLan.isHost;
    if (!_lanEnabledForHost || !lanEnabled) {
      throw StateError(tr.text('enable_lan_before_pairing_code'));
    }
    final current = savedLan.copyWith(
      host: _lanHostController.text.trim().isEmpty ? savedLan.host : _lanHostController.text.trim(),
      port: _lanPort,
    );
    final result = await _lanEngine(current).createPairingCode(ttlMinutes: _pairingCodeLifetime.inMinutes);
    if (!result.ok) throw StateError(localizeRuntimeMessage(result.message, tr));
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


  bool get _hasActiveLanPairingCode =>
      _lanTokenController.text.trim().isNotEmpty &&
      _latestLanPairingExpiresAt != null &&
      _latestLanPairingExpiresAt!.isAfter(DateTime.now());

  bool get _hasActiveCloudPairingCode =>
      _latestCloudPairingCode.trim().isNotEmpty &&
      _latestCloudPairingExpiresAt != null &&
      _latestCloudPairingExpiresAt!.isAfter(DateTime.now());

  String get _lanPairingButtonLabel => _hasActiveLanPairingCode ? tr.text('regenerate_new_lan_code') : tr.text('generate_lan_code');

  String get _cloudPairingButtonLabel => _hasActiveCloudPairingCode ? tr.text('regenerate_new_cloud_code') : tr.text('generate_cloud_code');

  Future<void> _refreshCloudPairingStatus() async {
    final code = _latestCloudPairingCode.trim();
    if (code.isEmpty || !widget.store.appIdentity.isHost) return;
    final settings = _cloudSettings(enabled: true);
    if (!settings.isConfigured || !settings.hasDeploymentToken) return;
    final result = await CloudSyncService(widget.store).pairingCodeStatus(settings, code);
    if (!mounted || !result.ok) return;
    if (result.status == 'consumed') {
      await _adoptConsumedCloudPairingDevice(result);
      if (!mounted) return;
    }
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


  Future<void> _adoptConsumedCloudPairingDevice(CloudPairingStatusResult result) async {
    final clientDeviceId = result.claimedByDeviceId.trim();
    if (clientDeviceId.isEmpty || !widget.store.appIdentity.isHost) return;

    final hostDeviceId = widget.store.deviceId.trim();
    final current = LanSyncSettings.load().withMigratedHostRegistry(hostDeviceId);
    final updated = current.withCloudPairedHostRegistryDevice(
      hostDeviceId: hostDeviceId,
      clientDeviceId: clientDeviceId,
      deviceToken: result.claimedDeviceToken,
      deviceName: result.claimedByDeviceName,
      pairedAt: result.claimedAt ?? DateTime.now(),
    );
    await updated.save();
  }

  Future<void> _handleCloudPairingButton() async {
    final identity = widget.store.appIdentity;
    final cloud = CloudSyncSettings.load();
    if (!_cloudEnabled || !identity.isCloudEnabled || !cloud.isConfigured) {
      setState(() => _status = tr.text('enable_cloud_before_pairing_code'));
      return;
    }
    if (_hasActiveCloudPairingCode) _expireCloudPairingCode();
    await _createCloudPairingCode();
  }

  Future<void> _handleLanPairingButton() async {
    final identity = widget.store.appIdentity;
    final lan = LanSyncSettings.load();
    final lanEnabled = identity.isHost && lan.setupComplete && lan.isHost;
    if (!_lanEnabledForHost || !lanEnabled) {
      setState(() => _status = tr.text('enable_lan_before_pairing_code'));
      return;
    }
    if (_hasActiveLanPairingCode) _expireLanPairingCode();
    await _generateLanToken();
  }


  Future<void> _requestHostTransfer() => _run(() async {
        await widget.store.requestHostTransfer(reason: tr.text('user_requested_host_role_reason'));
        final cloud = _cloudSettings(enabled: true);
        if (cloud.apiBaseUrl.trim().isNotEmpty) {
          await CloudSyncService(widget.store).requestHostTransfer(cloud, reason: tr.text('user_requested_host_role_reason'));
        }
        if (mounted) {
          setState(() => _status = tr.format('host_transfer_request_created', {'deviceId': widget.store.deviceId}));
        }
      });

  Future<void> _approveHostTransferFromUi() => _run(() async {
        final deviceId = _transferDeviceController.text.trim();
        if (deviceId.isEmpty) throw StateError(tr.text('client_device_id_required'));
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
          if (!cloudResult.ok) throw StateError(localizeRuntimeMessage(cloudResult.message, tr));
        }
        await widget.store.approveHostTransfer(deviceId);
        if (mounted) {
          setState(() {
            _deviceRole = DeviceRole.host;
            _status = tr.text('host_transfer_approved_wait_activation');
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
            _status = tr.text('host_transfer_activated_now_host');
          });
        }
      });

  String _normalizedPairingId(String value) => value.trim().toUpperCase();

  void _clearExpectedPairingTarget() {
    _expectedPairingStoreId = '';
    _expectedPairingBranchId = '';
    _expectedPairingHostDeviceId = '';
    _expectedPairingCloudTenantId = '';
  }

  void _rememberExpectedPairingTarget(_ScannedPairingPayload payload) {
    _expectedPairingStoreId = payload.storeId.trim();
    _expectedPairingBranchId = payload.branchId.trim();
    _expectedPairingHostDeviceId = payload.hostDeviceId.trim();
    _expectedPairingCloudTenantId = payload.cloudTenantId.trim();
  }

  _ScannedPairingPayload _parseScannedPairingPayload(String raw) {
    var code = raw.trim();
    var transport = '';
    var host = '';
    var port = '';
    var apiBaseUrl = '';
    var storeId = '';
    var branchId = '';
    var hostDeviceId = '';
    var cloudTenantId = '';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        transport = (decoded['transport'] ?? decoded['syncType'] ?? decoded['type'] ?? '').toString().toLowerCase();
        host = (decoded['host'] ?? decoded['hostIp'] ?? decoded['ip'] ?? '').toString().trim();
        port = (decoded['port'] ?? '').toString().trim();
        apiBaseUrl = (decoded['apiBaseUrl'] ?? decoded['apiUrl'] ?? decoded['cloudApiUrl'] ?? '').toString().trim();
        code = (decoded['pairingCode'] ?? decoded['pairing_code'] ?? decoded['code'] ?? decoded['token'] ?? decoded['pairingToken'] ?? raw).toString().trim();
        storeId = (decoded['storeId'] ?? decoded['store_id'] ?? '').toString().trim();
        branchId = (decoded['branchId'] ?? decoded['branch_id'] ?? '').toString().trim();
        hostDeviceId = (decoded['hostDeviceId'] ?? decoded['hostId'] ?? decoded['host_id'] ?? decoded['host_device_id'] ?? '').toString().trim();
        cloudTenantId = (decoded['cloudTenantId'] ?? decoded['tenantId'] ?? decoded['tenant_id'] ?? '').toString().trim();
      }
    } catch (_) {
      // Plain pairing code.
    }
    return _ScannedPairingPayload(
      raw: raw,
      code: code,
      transport: transport,
      host: host,
      port: port,
      apiBaseUrl: apiBaseUrl,
      storeId: storeId,
      branchId: branchId,
      hostDeviceId: hostDeviceId,
      cloudTenantId: cloudTenantId,
    );
  }

  void _applyParsedPairingPayload(_ScannedPairingPayload payload, {void Function(VoidCallback fn)? dialogSetState, SyncMode? fallbackMode}) {
    void apply() {
      if (payload.transport.contains('lan')) {
        _clientSyncMode = SyncMode.lanOnly;
      } else if (payload.transport.contains('cloud')) {
        _clientSyncMode = SyncMode.cloudConnected;
      } else if (fallbackMode != null) {
        _clientSyncMode = fallbackMode;
      }
      if (payload.host.isNotEmpty) _lanHostController.text = payload.host;
      if (payload.port.isNotEmpty) _lanPortController.text = payload.port;
      if (payload.apiBaseUrl.isNotEmpty) {
        try {
          _cloudApiController.text = CloudSyncSettings.normalizeApiBaseUrl(payload.apiBaseUrl);
        } catch (_) {
          _cloudApiController.text = payload.apiBaseUrl;
        }
      }
      if (_clientSyncMode == SyncMode.lanOnly) {
        _lanTokenController.text = payload.code;
      } else {
        _cloudPairingCodeController.text = payload.code;
      }
      _rememberExpectedPairingTarget(payload);
      _status = tr.text('qr_detected_review_connect');
    }

    if (dialogSetState != null) {
      dialogSetState(apply);
    } else if (mounted) {
      setState(apply);
    } else {
      apply();
    }
  }

  void _validateExpectedPairingTarget(AppIdentity identity) {
    final mismatches = <String>[];
    final actualStore = _normalizedPairingId(identity.storeId);
    final actualBranch = _normalizedPairingId(identity.branchId);
    final actualHost = _normalizedPairingId(identity.hostDeviceId);
    final actualTenant = _normalizedPairingId(identity.cloudTenantId);
    final expectedStore = _normalizedPairingId(_expectedPairingStoreId);
    final expectedBranch = _normalizedPairingId(_expectedPairingBranchId);
    final expectedHost = _normalizedPairingId(_expectedPairingHostDeviceId);
    final expectedTenant = _normalizedPairingId(_expectedPairingCloudTenantId);
    if (expectedStore.isNotEmpty && actualStore != expectedStore) mismatches.add(tr.text('store_id_label'));
    if (expectedBranch.isNotEmpty && actualBranch != expectedBranch) mismatches.add(tr.text('branch_id_label'));
    if (expectedHost.isNotEmpty && actualHost != expectedHost) mismatches.add(tr.text('host_id_label'));
    if (expectedTenant.isNotEmpty && actualTenant.isNotEmpty && actualTenant != expectedTenant) mismatches.add(tr.text('tenant_id_label'));
    if (mismatches.isNotEmpty) {
      throw Exception(tr.format('pairing_data_mismatch', {'items': mismatches.join(', ')}));
    }
  }

  void _validateAgainstExistingClientIdentity(AppIdentity before, AppIdentity after) {
    if (!before.isClient || before.hostDeviceId.trim().isEmpty) return;
    final mismatches = <String>[];
    if (_normalizedPairingId(before.storeId) != _normalizedPairingId(after.storeId)) mismatches.add(tr.text('store_id_label'));
    if (_normalizedPairingId(before.branchId) != _normalizedPairingId(after.branchId)) mismatches.add(tr.text('branch_id_label'));
    if (_normalizedPairingId(before.hostDeviceId) != _normalizedPairingId(after.hostDeviceId)) mismatches.add(tr.text('host_id_label'));
    if (mismatches.isNotEmpty) {
      throw Exception(tr.format('connection_different_store', {'items': mismatches.join(', ')}));
    }
  }

  Future<void> _scanConnectToStoreQr(void Function(VoidCallback fn) setDialogState, void Function(SyncMode mode) setDialogMode, SyncMode fallbackMode) async {
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
    final payload = _parseScannedPairingPayload(raw.trim());
    if (payload.transport.contains('lan')) {
      setDialogMode(SyncMode.lanOnly);
    } else if (payload.transport.contains('cloud')) {
      setDialogMode(SyncMode.cloudConnected);
    }
    _applyParsedPairingPayload(payload, dialogSetState: setDialogState, fallbackMode: fallbackMode);
  }

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
    final payload = _parseScannedPairingPayload(raw);
    _applyParsedPairingPayload(payload);
  }

  Future<void> _createCloudPairingCode() => _run(() async {
        final identity = widget.store.appIdentity;
        final cloud = CloudSyncSettings.load();
        if (!_cloudEnabled || !identity.isCloudEnabled || !cloud.isConfigured) {
          throw StateError(tr.text('enable_cloud_before_pairing_code'));
        }
        final result = await _cloudEngine(enabled: _cloudEnabled).createPairingCode(ttlMinutes: _pairingCodeLifetime.inMinutes);
        if (!result.ok) throw StateError(localizeRuntimeMessage(result.message, tr));
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

  Future<void> _clearInvalidPendingChanges() async {
    final pendingCount = widget.store.pendingSyncCount;
    if (pendingCount == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('clear_sync_settings_pending')),
        content: Text(tr.text('clear_sync_settings_pending_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr.text('cancel')),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.cleaning_services_outlined),
            label: Text(tr.text('clear')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() async {
      final removed = await widget.store.clearLocalOnlyPendingSyncChanges();
      if (!mounted) return;
      setState(() {
        _status = removed > 0
            ? tr.text('sync_settings_pending_cleared').replaceAll('{count}', removed.toString())
            : tr.text('no_sync_settings_pending_found');
      });
    });
  }

  Future<void> _syncNow() => _run(() async {
        final identity = widget.store.appIdentity;
        final lan = LanSyncSettings.load();
        final cloud = CloudSyncSettings.load();
        final hostLanEnabled = identity.isHost && (_lanEnabledForHost || (lan.setupComplete && lan.isHost));
        final hostCloudEnabled = identity.isHost && (_cloudEnabled || (identity.isCloudEnabled && cloud.isConfigured));
        final messages = <String>[];
        if (hostCloudEnabled || (!identity.isHost && identity.activeSyncTransportNormalized == 'cloud')) {
          final result = await _cloudEngine(enabled: true).syncNow(
            onProgress: (value, label) {
              if (mounted) setState(() { _status = '${tr.text('connection_cloud')}: ${localizeRuntimeMessage(label, tr)} ${(value * 100).round()}%'; _statusProgress = value; });
            },
          );
          if (!result.ok) throw StateError(localizeRuntimeMessage(result.message, tr));
          messages.add('${tr.text('connection_cloud')}: ${tr.text('sync_completed')}');
        }
        if (identity.isClient && identity.activeSyncTransportNormalized == 'lan') {
          final result = await _lanEngine().syncNow(
            onProgress: (value, label) {
              if (mounted) setState(() { _status = '${tr.text('connection_lan')}: ${localizeRuntimeMessage(label, tr)} ${(value * 100).round()}%'; _statusProgress = value; });
            },
          );
          if (!result.ok) throw StateError(localizeRuntimeMessage(result.message, tr));
          messages.add('${tr.text('connection_lan')}: ${tr.text('sync_completed')}');
        } else if (hostLanEnabled) {
          messages.add('${tr.text('connection_lan')}: ${tr.text('lan_host_running')}');
        }
        if (messages.isEmpty) {
          setState(() => _status = tr.text('no_sync_mode_enabled'));
        } else {
          setState(() { _status = messages.join(' • '); _statusProgress = 1.0; });
        }
      });

  String _shortDeviceLabel(String deviceId, {String name = ''}) {
    final trimmedName = name.trim();
    if (trimmedName.isNotEmpty) return trimmedName;
    final id = deviceId.trim();
    if (id.length <= 8) return id.isEmpty ? tr.text('unknown_client') : id;
    return '${tr.text('client_label')} ${id.substring(0, 4)}…${id.substring(id.length - 4)}';
  }

  String _formatShortDateTime(DateTime? value) {
    if (value == null) return tr.text('never');
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  String _peerSyncStatus(HostPeerSyncState? peer) {
    if (peer == null) return tr.text('connection_state_not_configured');
    if (peer.lastAckSequence > 0 || peer.lastAckCursor != null || peer.lastAppliedHostCursor != null) {
      return tr.text('synced');
    }
    return tr.text('sync_pending');
  }

  Future<void> _testPairedClientConnections() => _run(() async {
        setState(() { _status = tr.text('testing_paired_clients'); _statusProgress = 0.15; });
        final identity = widget.store.appIdentity;
        final lan = LanSyncSettings.load();
        final cloud = CloudSyncSettings.load();
        final peerStates = <String, HostPeerSyncState>{
          for (final state in SyncDeviceStateStore.loadPeerStates()) state.deviceId: state,
        };
        var cloudReachable = false;
        var cloudProblem = '';
        var cloudDevices = const <CloudDeviceStatus>[];
        if ((_cloudEnabled || identity.isCloudEnabled) && cloud.isConfigured) {
          final service = CloudSyncService(widget.store);
          final cloudConnection = await service.testConnection(cloud);
          cloudReachable = cloudConnection.ok;
          cloudProblem = cloudConnection.ok ? '' : cloudConnection.message;
          if (cloudReachable) {
            try {
              cloudDevices = await service.listDevices(cloud);
            } catch (error) {
              cloudReachable = false;
              cloudProblem = error.toString();
            }
          }
        }
        final cloudById = <String, CloudDeviceStatus>{
          for (final device in cloudDevices)
            if (device.deviceId.trim().isNotEmpty) device.deviceId.trim(): device,
        };
        // Phase 3: Host Registry is the single source of truth for
        // Monitoring/Test Connection device discovery. Cloud devices and peer
        // states are used only as status overlays for registered Clients.
        final registryById = <String, HostRegistryDevice>{
          for (final entry in lan.hostRegistry.entries)
            if (entry.key.trim().isNotEmpty && entry.value.isActive) entry.key.trim(): entry.value,
        };
        final ids = registryById.keys.toSet()..remove(identity.deviceId);

        if (ids.isEmpty) {
          setState(() {
            _status = tr.text('no_paired_clients_found');
            _statusProgress = 1.0;
          });
          return;
        }

        final lines = <String>[];
        var ready = 0;
        for (final id in ids) {
          final registryDevice = registryById[id];
          final cloudDevice = cloudById[id];
          final peer = peerStates[id];
          final lanToken = lan.pairedDevices[id]?.trim().isNotEmpty == true
              ? lan.pairedDevices[id]!.trim()
              : ((registryDevice?.source != 'cloud_pairing_claim' && registryDevice?.deviceToken.trim().isNotEmpty == true)
                  ? registryDevice!.deviceToken.trim()
                  : '');
          final parts = <String>[];
          if (cloudDevice != null) {
            if (cloudDevice.revoked) {
              parts.add(tr.text('cloud_unauthorized'));
            } else if (cloudDevice.online || cloudDevice.isOnline) {
              parts.add(tr.text('cloud_active'));
            } else {
              parts.add(tr.text('cloud_pending'));
            }
          } else if ((_cloudEnabled || identity.isCloudEnabled) && cloud.isConfigured) {
            parts.add(cloudReachable ? tr.text('cloud_not_configured') : '${tr.text('cloud_error')}${cloudProblem.isEmpty ? '' : ': $cloudProblem'}');
          }
          if (lanToken.isNotEmpty) {
            parts.add(tr.text('lan_active'));
          } else if (_lanEnabledForHost || (lan.setupComplete && lan.isHost)) {
            parts.add(tr.text('lan_not_configured'));
          }
          final peerSynced = peer != null && (peer.lastAckSequence > 0 || peer.lastAckCursor != null || peer.lastAppliedHostCursor != null);
          final syncStatus = _peerSyncStatus(peer);
          if (peerSynced && ((cloudDevice != null && !cloudDevice.revoked && (cloudDevice.online || cloudDevice.isOnline)) || lanToken.isNotEmpty)) ready++;
          parts.add(syncStatus);
          parts.add('${tr.text('last_sync')}: ${_formatShortDateTime(peer?.lastAckCursor ?? peer?.lastAppliedHostCursor ?? peer?.updatedAt)}');
          final label = _shortDeviceLabel(id, name: registryDevice?.deviceName ?? cloudDevice?.deviceName ?? '');
          lines.add('$label → ${parts.join(' | ')}');
        }

        final total = ids.length;
        setState(() {
          _status = '${tr.format('paired_clients_ready', {'ready': ready, 'total': total})} • ${lines.join(' • ')}';
          _statusProgress = 1.0;
        });
      });

  Future<void> _testCloudConnection() => _run(() async {
        setState(() { _status = tr.text('testing_cloud_connection'); _statusProgress = 0.25; });
        final result = await _cloudEngine(enabled: true).testConnection();
        if (!result.ok) throw StateError(localizeRuntimeMessage(result.message, tr));
        setState(() { _status = '${tr.text('connection_cloud')}: ${localizeRuntimeMessage(result.message, tr)}'; _statusProgress = 1.0; });
      });

  Future<void> _testHostConnection() => _run(() async {
        final lan = LanSyncSettings.load();
        final host = _lanHostController.text.trim().isEmpty ? lan.host : _lanHostController.text.trim();
        setState(() { _status = tr.text('testing_lan_connection'); _statusProgress = 0.25; });
        final result = await _lanEngine(lan.copyWith(host: host, port: _lanPort)).testConnection();
        if (!result.ok) throw StateError(localizeRuntimeMessage(result.message, tr));
        setState(() { _status = '${tr.text('connection_lan')}: ${tr.text('connection_ok')}'; _statusProgress = 1.0; });
      });

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    final identity = widget.store.appIdentity;
    final isHost = _deviceRole == DeviceRole.host;
    final lanActive = isHost ? _lanEnabledForHost : identity.syncMode == SyncMode.lanOnly;
    final cloudActive = isHost ? _cloudEnabled : identity.syncMode == SyncMode.cloudConnected;
    final hostActionLabel = tr.text('sync_now');
    final allGood = widget.store.pendingSyncCount == 0 && (lanActive || cloudActive || !isHost);

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
              cloudActive: cloudActive,
              actionLabel: hostActionLabel,
            ),
            if (widget.store.latestHostTransferNotification != null) ...[
              const SizedBox(height: 12),
              _hostChangedNotificationCard(),
            ],
            const SizedBox(height: 14),
            _syncOverviewCard(context, allGood: allGood, isHost: isHost, lanActive: lanActive, cloudActive: cloudActive),
            if (!isHost && widget.store.isSuspendedByHost) ...[
              const SizedBox(height: 14),
              _clientSuspendedWarningCard(context),
            ],
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final thisDevice = _thisDeviceCard(context, isHost: isHost, lanActive: lanActive, cloudActive: cloudActive);

                // Clients are paired during first-time setup/login. Once this
                // settings page is reachable, the Client should not show a
                // misleading "Connect Device" action again; Sync should only
                // show status, sync information, and management controls.
                if (!isHost) {
                  return thisDevice;
                }

                final addDevice = _addDeviceCard(context, isHost: true, isCloudClient: false);
                if (compact) {
                  return Column(children: [thisDevice, const SizedBox(height: 14), addDevice]);
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
            _syncChannelsCard(context, isHost: isHost, lanActive: lanActive, cloudActive: cloudActive),
            if (isHost) ...[
              const SizedBox(height: 14),
              _advancedSyncCard(context, isHost: isHost),
            ],
            const SizedBox(height: 14),
            _syncStatusMessage(context, color),
            const SizedBox(height: 14),
            _syncSaveCancelBar(context),
          ],
        ),
      ),
    );
  }


  Widget _clientSuspendedWarningCard(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    final reason = widget.store.suspendedByHostReason.trim().isEmpty
        ? tr.text('client_suspended_by_host_desc')
        : widget.store.suspendedByHostReason;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.42)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.pause_circle_outline, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr.text('client_suspended_by_host'), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: color.onSurface)),
                const SizedBox(height: 4),
                Text(reason),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _syncHeroHeader(
    BuildContext context, {
    required bool allGood,
    required bool isHost,
    required bool lanActive,
    required bool cloudActive,
    required String actionLabel,
  }) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final actionButtons = Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _syncNow,
              icon: const Icon(Icons.sync_outlined),
              label: Text(actionLabel),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _testCurrentConnection,
              icon: const Icon(Icons.network_check_outlined),
              label: Text(tr.text('test_connection')),
            ),
            if (widget.store.pendingSyncCount > 0)
              OutlinedButton.icon(
                onPressed: _busy ? null : _clearInvalidPendingChanges,
                icon: const Icon(Icons.cleaning_services_outlined),
                label: Text(tr.text('clear_invalid_pending')),
              ),
          ],
        );
        final titleBlock = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: compact ? 40 : 44,
              height: compact ? 40 : 44,
              decoration: BoxDecoration(
                color: allGood ? Colors.green.withValues(alpha: 0.12) : color.primaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(allGood ? Icons.check_circle_outline : Icons.sync_outlined, color: allGood ? Colors.green.shade700 : color.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr.text('sync_settings'),
                    style: (compact ? Theme.of(context).textTheme.titleLarge : Theme.of(context).textTheme.headlineSmall)?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    allGood ? tr.text('all_data_synchronized') : tr.text('needs_sync'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleBlock,
              const SizedBox(height: 12),
              actionButtons,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 16),
            actionButtons,
          ],
        );
      },
    );
  }

  Widget _syncOverviewCard(BuildContext context, {required bool allGood, required bool isHost, required bool lanActive, required bool cloudActive}) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    final accent = allGood ? Colors.green : color.primary;
    return Container(
      width: double.infinity,
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final summary = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: accent.withValues(alpha: 0.14),
                foregroundColor: accent,
                child: Icon(allGood ? Icons.verified_outlined : Icons.sync_problem_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(allGood ? tr.text('all_systems_are_running_smoothly') : tr.text('needs_sync'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(_humanStatus(context), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          );
          final metrics = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _compactStatusChip(context, Icons.dns_outlined, isHost ? tr.text('host_device') : tr.text('client_device'), color.primary),
              _compactStatusChip(context, Icons.lan_outlined, '${tr.text('lan')}: ${lanActive ? tr.text('connection_state_active') : tr.text('off')}', lanActive ? Colors.green : color.onSurfaceVariant),
              _compactStatusChip(context, Icons.cloud_outlined, '${tr.text('cloud')}: ${cloudActive ? tr.text('connection_state_active') : tr.text('off')}', cloudActive ? Colors.green : color.onSurfaceVariant),
              _compactStatusChip(context, Icons.storage_outlined, '${tr.text('pending_changes')}: ${widget.store.pendingSyncCount}', widget.store.pendingSyncCount == 0 ? Colors.green : color.error),
            ],
          );
          if (compact) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [summary, const SizedBox(height: 14), metrics]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: summary), const SizedBox(width: 16), Flexible(child: metrics)]);
        },
      ),
    );
  }

  Widget _thisDeviceCard(BuildContext context, {required bool isHost, required bool lanActive, required bool cloudActive}) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    return _plainSyncPanel(
      context,
      icon: Icons.devices_outlined,
      title: tr.text('device_role'),
      subtitle: isHost ? tr.text('connection_role_host') : tr.text('connection_role_client'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _simpleInfoRow(context, tr.text('role'), isHost ? tr.text('host_device') : tr.text('client_device'), Icons.dns_outlined, color.primary),
          const SizedBox(height: 8),
          _simpleInfoRow(context, tr.text('lan_connection'), lanActive ? tr.text('connection_state_active') : tr.text('pairing_status_disabled'), Icons.lan_outlined, lanActive ? Colors.green : color.onSurfaceVariant),
          const SizedBox(height: 8),
          _simpleInfoRow(context, tr.text('cloud_connection'), cloudActive ? tr.text('connection_state_active') : tr.text('connection_state_disabled'), Icons.cloud_outlined, cloudActive ? Colors.green : color.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _addDeviceCard(BuildContext context, {required bool isHost, required bool isCloudClient}) {
    final tr = AppLocalizations.of(context);
    return _plainSyncPanel(
      context,
      icon: isHost ? Icons.add_link_outlined : Icons.link_outlined,
      title: isHost ? tr.text('pair_new_device') : tr.text('connect_device'),
      subtitle: isHost ? tr.text('pair_new_device_desc') : tr.text('connect_device_desc'),
      child: _pairingContent(context, isHost: isHost, isCloudClient: isCloudClient),
    );
  }

  bool _isLanClientConfigured(LanSyncSettings lan) => lan.setupComplete && lan.host.trim().isNotEmpty && lan.secret.trim().isNotEmpty;

  bool _isCloudClientConfigured(CloudSyncSettings cloud) => cloud.isConfigured && cloud.apiBaseUrl.trim().isNotEmpty;

  String _clientTransportStatusLabel(BuildContext context, {required bool active, required bool configured}) {
    final tr = AppLocalizations.of(context);
    if (active) return tr.text('connection_state_active');
    if (configured) return tr.text('connection_state_disabled');
    return tr.text('not_configured');
  }

  Future<void> _openConnectToStoreDialog(SyncMode mode) async {
    final tr = AppLocalizations.of(context);
    final lan = LanSyncSettings.load();
    final cloud = CloudSyncSettings.load();
    _lanHostController.text = lan.host;
    _lanPortController.text = lan.port.toString();
    _lanIntervalController.text = lan.intervalSeconds.toString();
    _lanTokenController.text = lan.secret.trim();
    _cloudApiController.text = cloud.apiBaseUrl;
    _cloudPairingCodeController.clear();
    _clearExpectedPairingTarget();
    var dialogMode = mode;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isLan = dialogMode == SyncMode.lanOnly;
            final screenWidth = MediaQuery.sizeOf(context).width;
            final compact = screenWidth < 420;
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              title: Text(tr.text('connect_to_store'), maxLines: 2, overflow: TextOverflow.ellipsis),
              content: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: screenWidth < 568 ? screenWidth - 32 : 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(tr.text('connect_to_store_desc'), style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<SyncMode>(
                          showSelectedIcon: !compact,
                          segments: [
                            ButtonSegment<SyncMode>(value: SyncMode.lanOnly, icon: const Icon(Icons.lan_outlined), label: Text(tr.text('lan'))),
                            ButtonSegment<SyncMode>(value: SyncMode.cloudConnected, icon: const Icon(Icons.cloud_outlined), label: Text(tr.text('cloud'))),
                          ],
                          selected: {dialogMode},
                          onSelectionChanged: (value) => setDialogState(() => dialogMode = value.first),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SizedBox(
                          width: compact ? double.infinity : null,
                          child: OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _scanConnectToStoreQr(
                                      setDialogState,
                                      (mode) => setDialogState(() => dialogMode = mode),
                                      dialogMode,
                                    ),
                            icon: const Icon(Icons.qr_code_scanner_outlined),
                            label: Text(tr.text('scan_qr_code'), overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (isLan) ...[
                        TextField(controller: _lanHostController, decoration: InputDecoration(labelText: tr.text('host_ip_address'), border: const OutlineInputBorder())),
                        const SizedBox(height: 12),
                        TextField(controller: _lanPortController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr.text('port'), border: const OutlineInputBorder())),
                        const SizedBox(height: 12),
                        TextField(controller: _lanTokenController, decoration: InputDecoration(labelText: tr.text('pairing_token'), border: const OutlineInputBorder())),
                      ] else ...[
                        TextField(controller: _cloudApiController, decoration: InputDecoration(labelText: tr.text('api_url'), border: const OutlineInputBorder())),
                        const SizedBox(height: 12),
                        TextField(controller: _cloudPairingCodeController, decoration: InputDecoration(labelText: tr.text('pairing_code_from_host'), border: const OutlineInputBorder())),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(tr.text('cancel'))),
                FilledButton(
                  onPressed: () async {
                    if (isLan) {
                      final host = _lanHostController.text.trim();
                      final token = _lanTokenController.text.trim();
                      if (host.isEmpty || token.isEmpty) return;
                      if (widget.store.appIdentity.isClient && widget.store.appIdentity.hostDeviceId.trim().isNotEmpty) {
                        _validateExpectedPairingTarget(widget.store.appIdentity);
                      }
                      await LanSyncSettings.load().copyWith(
                        host: host,
                        port: _lanPort,
                        secret: token,
                        mode: LanSyncDeviceMode.client,
                        setupComplete: true,
                        hostModeEnabled: false,
                        autoSyncEnabled: widget.store.appIdentity.activeSyncTransportNormalized == 'lan',
                      ).save();
                    } else {
                      final apiUrl = _cloudApiController.text.trim();
                      final code = _cloudPairingCodeController.text.trim();
                      if (apiUrl.isEmpty || code.isEmpty) return;
                      final previousIdentity = widget.store.appIdentity;
                      final previousActive = previousIdentity.activeSyncTransportNormalized;
                      final settings = CloudSyncSettings.load().copyWith(
                        enabled: true,
                        apiBaseUrl: CloudSyncSettings.normalizeApiBaseUrl(apiUrl, fallback: kIsWeb ? Uri.base.origin : ''),
                        autoSyncEnabled: previousActive == 'cloud',
                      );
                      await settings.save();
                      final result = await CloudSyncService(widget.store).claimPairingCode(settings, code);
                      if (!result.ok) throw Exception(result.message);
                      final claimedIdentity = result.identity ?? widget.store.appIdentity;
                      _validateExpectedPairingTarget(claimedIdentity);
                      _validateAgainstExistingClientIdentity(previousIdentity, claimedIdentity);
                      if (previousActive == 'lan') {
                        await widget.store.setActiveSyncTransport('lan');
                      }
                    }
                    if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
                  },
                  child: Text(tr.text('save')),
                ),
              ],
            );
          },
        );
      },
    );
    if (saved == true && mounted) {
      setState(() => _status = tr.text('sync_settings_saved'));
      await widget.onSyncSettingsChanged?.call();
    }
  }

  Widget _syncChannelsCard(BuildContext context, {required bool isHost, required bool lanActive, required bool cloudActive}) {
    final tr = AppLocalizations.of(context);
    final lan = LanSyncSettings.load();
    final cloud = CloudSyncSettings.load();
    final lanConfigured = isHost ? _lanEnabledForHost : _isLanClientConfigured(lan);
    final cloudConfigured = isHost ? _cloudEnabled : _isCloudClientConfigured(cloud);
    return _plainSyncPanel(
      context,
      icon: Icons.hub_outlined,
      title: tr.text('sync_method'),
      subtitle: tr.text('sync_settings_desc'),
      child: Column(
        children: [
          if (!isHost) ...[
            _activeTransportSelector(context, lanConfigured: lanConfigured, cloudConfigured: cloudConfigured),
            const SizedBox(height: 12),
          ],
          _syncMethodExpansionTile(
            context,
            icon: Icons.lan_outlined,
            title: tr.text('lan_sync'),
            subtitle: isHost ? (lanConfigured ? tr.text('connection_state_active') : tr.text('connection_state_disabled')) : _clientTransportStatusLabel(context, active: lanActive, configured: lanConfigured),
            active: lanActive,
            configured: lanConfigured,
            accent: Colors.green,
            trailing: isHost
                ? Switch(value: _lanEnabledForHost, onChanged: _busy ? null : (value) => setState(() => _lanEnabledForHost = value))
                : (!lanConfigured ? TextButton.icon(onPressed: _busy ? null : () => _openConnectToStoreDialog(SyncMode.lanOnly), icon: const Icon(Icons.add_link_outlined), label: Text(tr.text('connect_to_store'))) : null),
            children: isHost
                ? [
                    if (_lanEnabledForHost) ...[
                      _hostIpInfoCard(),
                      ..._lanFields(showHostIp: false, forHost: true),
                    ] else
                      _miniLine(tr.text('status'), tr.text('connection_state_disabled')),
                  ]
                : [
                    _readOnlyTransportLine(context, tr.text('status'), _clientTransportStatusLabel(context, active: lanActive, configured: lanConfigured), lanActive ? Icons.check_circle_outline : (lanConfigured ? Icons.lock_outline : Icons.link_off_outlined)),
                    _readOnlyTransportLine(context, tr.text('host_ip_address'), lan.host.isEmpty ? '—' : lan.host, Icons.dns_outlined),
                    _readOnlyTransportLine(context, tr.text('port'), '${lan.port}', Icons.tag_outlined),
                    _readOnlyTransportLine(context, tr.text('pairing_token'), lan.secret.trim().isEmpty ? '—' : '••••••••', Icons.vpn_key_outlined),
                    _readOnlyTransportLine(context, tr.text('sync_interval'), tr.format('seconds_count', {'count': '${lan.intervalSeconds}'}), Icons.timer_outlined),
                  ],
          ),
          const Divider(height: 20),
          _syncMethodExpansionTile(
            context,
            icon: Icons.cloud_outlined,
            title: tr.text('cloud_sync'),
            subtitle: isHost ? (cloudConfigured ? tr.text('connection_state_active') : tr.text('connection_state_disabled')) : _clientTransportStatusLabel(context, active: cloudActive, configured: cloudConfigured),
            active: cloudActive,
            configured: cloudConfigured,
            accent: Colors.blue,
            trailing: isHost
                ? Switch(value: _cloudEnabled, onChanged: _busy ? null : (value) => setState(() => _cloudEnabled = value))
                : (!cloudConfigured ? TextButton.icon(onPressed: _busy ? null : () => _openConnectToStoreDialog(SyncMode.cloudConnected), icon: const Icon(Icons.add_link_outlined), label: Text(tr.text('connect_to_store'))) : null),
            children: isHost
                ? [
                    if (_cloudEnabled) ..._cloudFields(showPairingCode: false) else _miniLine(tr.text('status'), tr.text('connection_state_disabled')),
                  ]
                : [
                    _readOnlyTransportLine(context, tr.text('status'), _clientTransportStatusLabel(context, active: cloudActive, configured: cloudConfigured), cloudActive ? Icons.check_circle_outline : (cloudConfigured ? Icons.lock_outline : Icons.link_off_outlined)),
                    _readOnlyTransportLine(context, tr.text('api_url'), cloud.apiBaseUrl.isEmpty ? '—' : cloud.apiBaseUrl, Icons.cloud_outlined),
                    _readOnlyTransportLine(context, tr.text('sync_interval'), tr.format('seconds_count', {'count': '${cloud.intervalSeconds}'}), Icons.timer_outlined),
                  ],
          ),
        ],
      ),
    );
  }


  Widget _activeTransportSelector(BuildContext context, {required bool lanConfigured, required bool cloudConfigured}) {
    final tr = AppLocalizations.of(context);
    final canSwitchToLan = lanConfigured;
    final canSwitchToCloud = cloudConfigured;
    final alternateConfigured = _clientSyncMode == SyncMode.lanOnly ? cloudConfigured : lanConfigured;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(tr.text('active_transport'), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                Tooltip(message: alternateConfigured ? tr.text('switch_transport_available') : tr.text('switch_transport_locked'), child: Icon(alternateConfigured ? Icons.swap_horiz_outlined : Icons.lock_outline, size: 20)),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<SyncMode>(
              segments: [
                ButtonSegment<SyncMode>(value: SyncMode.lanOnly, icon: const Icon(Icons.lan_outlined), label: Text(tr.text('lan')), enabled: canSwitchToLan),
                ButtonSegment<SyncMode>(value: SyncMode.cloudConnected, icon: const Icon(Icons.cloud_outlined), label: Text(tr.text('cloud')), enabled: canSwitchToCloud),
              ],
              selected: {_clientSyncMode},
              onSelectionChanged: _busy
                  ? null
                  : (value) {
                      final next = value.first;
                      if (next == SyncMode.lanOnly && !lanConfigured) return;
                      if (next == SyncMode.cloudConnected && !cloudConfigured) return;
                      setState(() => _clientSyncMode = next);
                    },
            ),
            const SizedBox(height: 8),
            Text(alternateConfigured ? tr.text('active_transport_desc') : tr.text('active_transport_locked_desc'), style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _syncMethodExpansionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool active,
    bool configured = false,
    required Color accent,
    required List<Widget> children,
    Widget? trailing,
  }) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 8, bottom: 4),
      leading: CircleAvatar(
        backgroundColor: accent.withValues(alpha: active ? 0.14 : 0.07),
        foregroundColor: active ? accent : color.onSurfaceVariant,
        child: Icon(icon),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color.onSurfaceVariant)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: (active ? accent : color.onSurfaceVariant).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(999)),
            child: Text(active ? tr.text('connection_state_active') : (configured ? tr.text('connection_state_disabled') : tr.text('connection_state_not_configured')), style: TextStyle(color: active ? accent : color.onSurfaceVariant, fontWeight: FontWeight.w700)),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
          const Icon(Icons.expand_more),
        ],
      ),
      children: children,
    );
  }


  Widget _readOnlyTransportLine(BuildContext context, String title, String value, IconData icon) {
    final color = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.outlineVariant.withValues(alpha: 0.80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(width: VentioResponsive.adaptiveWidth(context, mobile: 105, tablet: 135, desktop: 150), child: Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color.onSurfaceVariant))),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  Widget _advancedSyncCard(BuildContext context, {required bool isHost}) {
    final tr = AppLocalizations.of(context);
    return _plainSyncPanel(
      context,
      icon: Icons.admin_panel_settings_outlined,
      title: tr.text('advanced_settings'),
      subtitle: tr.text('advanced_sync_settings_desc'),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(tr.text('advanced_settings')),
        children: [
          _transferHostCard(isHost: isHost),
        ],
      ),
    );
  }

  Widget _plainSyncPanel(BuildContext context, {required IconData icon, required String title, required String subtitle, required Widget child}) {
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _compactStatusChip(BuildContext context, IconData icon, String label, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _simpleInfoRow(BuildContext context, String label, String value, IconData icon, Color accent) {
    final color = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.surfaceContainerHighest.withValues(alpha: 0.32), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          CircleAvatar(radius: 18, backgroundColor: accent.withValues(alpha: 0.12), foregroundColor: accent, child: Icon(icon, size: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color.onSurfaceVariant)),
              Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: accent, fontWeight: FontWeight.w800)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _syncSaveCancelBar(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final changed = _hasUnsavedSyncChanges;
    final color = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: changed ? color.primary.withValues(alpha: 0.35) : color.outlineVariant),
        boxShadow: [BoxShadow(color: color.shadow.withValues(alpha: 0.05), blurRadius: 18, offset: const Offset(0, -4))],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy || !changed ? null : () => _resetSyncDraft(),
              icon: const Icon(Icons.close_outlined),
              label: Text(tr.text('cancel')),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy || !changed ? null : _saveSyncSettings,
              icon: const Icon(Icons.save_outlined),
              label: Text(tr.text('save')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _syncStatusMessage(BuildContext context, ColorScheme color) {
    final tr = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(color: color.surfaceContainerHighest.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(14)),
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
              OutlinedButton.icon(onPressed: _busy ? null : _handleLanPairingButton, icon: const Icon(Icons.lan_outlined), label: Text(_lanPairingButtonLabel)),
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
        _softNotice(
          context,
          Icons.info_outline,
          tr.text('connect_device'),
          tr.text('client_pairing_enter_or_scan_host_code'),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : _scanPairingQr,
            icon: const Icon(Icons.qr_code_scanner_outlined),
            label: Text(tr.text('scan_qr_code')),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          tr.text('replace_host_reset_required'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
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
      return '${tr.text('connection_role_host')} • ${tr.text('connection_lan')}: ${lan.setupComplete && lan.isHost ? tr.text('connection_state_active') : tr.text('connection_state_disabled')} • ${tr.text('connection_cloud')}: ${identity.isCloudEnabled && cloud.isConfigured ? tr.text('connection_state_active') : tr.text('connection_state_disabled')}';
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
      _PairingCodeVisualStatus.active => (label: tr.text('connection_state_active'), icon: Icons.check_circle_outline, background: Colors.green.withValues(alpha: 0.12), foreground: Colors.green.shade700),
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


  Widget _manualPairingValueTile({
    required String label,
    required String value,
    required String copiedMessage,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: AppLocalizations.of(context).text('copy_code'),
          onPressed: value.trim().isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: value));
                  if (!mounted) return;
                  setState(() => _status = copiedMessage);
                },
          icon: const Icon(Icons.copy_outlined),
        ),
      ),
      child: SelectableText(
        value,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(letterSpacing: value.length > 12 ? 0.8 : 0),
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
    final identity = widget.store.appIdentity;
    final payload = jsonEncode({
      'transport': 'lan',
      'host': host,
      'port': _lanPort,
      'pairingCode': code,
      'storeId': identity.storeId,
      'branchId': identity.branchId,
      'hostDeviceId': widget.store.deviceId,
      if (identity.cloudTenantId.trim().isNotEmpty) 'cloudTenantId': identity.cloudTenantId,
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
          Text(
            status == _PairingCodeVisualStatus.active
                ? tr.format('expires_in', {'time': _countdownText(_latestLanPairingExpiresAt)})
                : tr.format('pairing_code_state_help', {'status': _pairingStatusData(context, status).label.toLowerCase()}),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _manualPairingValueTile(label: tr.text('host_ip_address'), value: host, copiedMessage: tr.text('copied_to_clipboard')),
          const SizedBox(height: 10),
          _manualPairingValueTile(label: tr.text('port'), value: _lanPort.toString(), copiedMessage: tr.text('copied_to_clipboard')),
          const SizedBox(height: 10),
          _manualPairingValueTile(label: tr.text('pairing_token'), value: code, copiedMessage: tr.text('lan_pairing_code_copied')),
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
                data: jsonEncode({
                  'transport': 'cloud',
                  'apiBaseUrl': _cloudApiController.text.trim(),
                  'pairingCode': code,
                  'storeId': widget.store.appIdentity.storeId,
                  'branchId': widget.store.appIdentity.branchId,
                  'hostDeviceId': widget.store.deviceId,
                  if (widget.store.appIdentity.cloudTenantId.trim().isNotEmpty) 'cloudTenantId': widget.store.appIdentity.cloudTenantId,
                  'expiresAt': _latestCloudPairingExpiresAt?.toIso8601String(),
                }),
                version: QrVersions.auto,
                size: 180,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            expiresText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _manualPairingValueTile(label: tr.text('api_url'), value: _cloudApiController.text.trim(), copiedMessage: tr.text('copied_to_clipboard')),
          const SizedBox(height: 10),
          _manualPairingValueTile(label: tr.text('cloud_pairing_code'), value: code, copiedMessage: tr.text('cloud_pairing_code_copied')),
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
        TextField(
          controller: _lanIntervalController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context).text('auto_sync_interval_seconds'),
            helperText: AppLocalizations.of(context).text('sync_interval_range_hint'),
            border: const OutlineInputBorder(),
          ),
        ),
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
        if (!showPairingCode) ...[
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
        const SizedBox(height: 12),
      ];
}



class _AdvancedSyncDebugCard extends StatefulWidget {
  const _AdvancedSyncDebugCard({required this.store});

  final AppStore store;

  @override
  State<_AdvancedSyncDebugCard> createState() => _AdvancedSyncDebugCardState();
}

class _AdvancedSyncDebugCardState extends State<_AdvancedSyncDebugCard> {
  Future<List<CloudDeviceStatus>>? _cloudDevicesFuture;

  @override
  void initState() {
    super.initState();
    _refreshCloudDevices();
  }

  void _refreshCloudDevices() {
    final cloudSettings = CloudSyncSettings.load();
    if (widget.store.appIdentity.isHost && cloudSettings.isConfigured) {
      _cloudDevicesFuture = _loadAndAdoptCloudDevices(cloudSettings).catchError((_) => <CloudDeviceStatus>[]);
    } else {
      _cloudDevicesFuture = Future<List<CloudDeviceStatus>>.value(const <CloudDeviceStatus>[]);
    }
  }

  Future<List<CloudDeviceStatus>> _loadAndAdoptCloudDevices(CloudSyncSettings cloudSettings) async {
    final service = CloudSyncService(widget.store);
    var devices = await service.listDevices(cloudSettings);
    final repaired = await _repairLegacyCloudDeviceLinks(service, cloudSettings, devices);
    if (repaired) {
      devices = await service.listDevices(cloudSettings);
    }
    await _adoptCloudRegistryDevices(devices);
    return devices;
  }

  Future<bool> _repairLegacyCloudDeviceLinks(
    CloudSyncService service,
    CloudSyncSettings cloudSettings,
    List<CloudDeviceStatus> devices,
  ) async {
    final identity = widget.store.appIdentity;
    if (!identity.isHost) return false;
    final hostDeviceId = widget.store.deviceId.trim();
    if (hostDeviceId.isEmpty) return false;

    final settings = LanSyncSettings.load().withMigratedHostRegistry(hostDeviceId);
    final trustedDeviceIds = <String>{
      ...settings.hostRegistry.keys.map((id) => id.trim()).where((id) => id.isNotEmpty),
      ...settings.pairedDevices.keys.map((id) => id.trim()).where((id) => id.isNotEmpty),
    }..remove(hostDeviceId);
    if (trustedDeviceIds.isEmpty) return false;

    final repairIds = devices
        .where((device) {
          final deviceId = device.deviceId.trim();
          if (deviceId.isEmpty || deviceId == hostDeviceId) return false;
          if (!trustedDeviceIds.contains(deviceId)) return false;
          if (device.revoked || device.role.trim().toLowerCase() == 'host') return false;
          return device.hostDeviceId.trim().isEmpty;
        })
        .map((device) => device.deviceId.trim())
        .toSet();

    if (repairIds.isEmpty) return false;
    final result = await service.repairLegacyCloudDeviceLinks(
      cloudSettings,
      clientDeviceIds: repairIds,
    );
    return result.ok;
  }

  Future<void> _adoptCloudRegistryDevices(List<CloudDeviceStatus> devices) async {
    final identity = widget.store.appIdentity;
    if (!identity.isHost) return;
    final hostDeviceId = widget.store.deviceId.trim();
    if (hostDeviceId.isEmpty) return;

    final loadedSettings = LanSyncSettings.load();
    var settings = loadedSettings.withMigratedHostRegistry(hostDeviceId);
    var changed = settings.hostRegistry.length != loadedSettings.hostRegistry.length;

    for (final device in devices) {
      final clientDeviceId = device.deviceId.trim();
      if (clientDeviceId.isEmpty || clientDeviceId == hostDeviceId) continue;
      if (device.revoked || device.role.trim().toLowerCase() == 'host') continue;

      final cloudDeviceName = device.deviceName.trim();
      final before = settings.hostRegistry[clientDeviceId];

      // Fix #1 completion: Host Registry is the display source for Sync
      // Monitoring, so refresh an already-registered Client name from Cloud
      // whenever the Cloud device row reports a newer/manual deviceName.
      // This must work even for legacy Cloud rows that are already in the
      // Registry but do not yet have hostDeviceId populated correctly.
      if (before != null) {
        final registry = <String, HostRegistryDevice>{...settings.hostRegistry};
        final updated = before.copyWith(
          deviceName: cloudDeviceName.isNotEmpty ? cloudDeviceName : before.deviceName,
          lastSeenAt: device.lastSeenAt ?? before.lastSeenAt,
        );
        registry[clientDeviceId] = updated;
        settings = settings.copyWith(hostRegistry: Map.unmodifiable(registry));
        if (updated.deviceName != before.deviceName || updated.lastSeenAt != before.lastSeenAt) {
          changed = true;
        }
        continue;
      }

      // New Cloud-only Clients are adopted only when the Cloud row is explicitly
      // linked to this Host. Existing Registry members were handled above.
      if (device.hostDeviceId.trim() != hostDeviceId) continue;
      settings = settings.withCloudPairedHostRegistryDevice(
        hostDeviceId: hostDeviceId,
        clientDeviceId: clientDeviceId,
        deviceToken: '',
        deviceName: cloudDeviceName,
        pairedAt: device.lastSeenAt ?? DateTime.now(),
      );
      changed = true;
    }

    if (changed) await settings.save();
  }

  Future<void> _refresh() async {
    setState(_refreshCloudDevices);
    final cloudDevices = await (_cloudDevicesFuture ?? Future<List<CloudDeviceStatus>>.value(const <CloudDeviceStatus>[]));
    await _finalizeCloudWipeAcknowledgements(cloudDevices);
    if (mounted) setState(() {});
  }

  Future<void> _toggleSuspend(String deviceId, bool suspended) async {
    final shouldResume = suspended;
    if (shouldResume) {
      await SyncDeviceAccessStore.resume(deviceId);
    } else {
      await SyncDeviceAccessStore.suspend(deviceId);
    }

    final cloudSettings = CloudSyncSettings.load();
    if (cloudSettings.isConfigured) {
      await CloudSyncService(widget.store).setDeviceSuspended(
        cloudSettings,
        deviceId,
        suspended: !shouldResume,
      );
    }

    // Resume does not reset any cursor. The device keeps its last ACK/Cursor and
    // the next sync catches up all Host-authoritative events that were missed
    // while it was suspended.
    if (mounted) setState(() {});
  }


  Future<void> _permanentlyDeleteDeviceRecord(String deviceId, {String deviceToken = ''}) async {
    final id = deviceId.trim();
    if (id.isEmpty) return;
    final lanSettings = LanSyncSettings.load();
    final registryDevice = lanSettings.hostRegistry[id];
    final token = (deviceToken.trim().isNotEmpty ? deviceToken : (lanSettings.pairedDevices[id] ?? registryDevice?.deviceToken ?? '')).trim();
    final paired = Map<String, String>.from(lanSettings.pairedDevices)..remove(id);
    final registry = Map<String, HostRegistryDevice>.from(lanSettings.hostRegistry)..remove(id);
    await lanSettings.copyWith(pairedDevices: paired, hostRegistry: registry).save();
    await SyncDeviceStateStore.removePeerState(id);
    await SyncDeviceAccessStore.markDeleted(id, deviceToken: token);
  }

  Future<void> _finalizeCloudWipeAcknowledgements(List<CloudDeviceStatus> cloudDevices) async {
    // Fix #11: a wipe ACK must not automatically remove the device record from
    // the Host list. The Host keeps the Wipe Pending row visible and gives the
    // admin an always-available Permanent Delete action, because the physical
    // device may be lost, stolen, or never come back online.
    return;
  }

  Future<void> _deleteDevice(String deviceId) async {
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('delete_sync_device')),
        content: Text(tr.text('delete_sync_device_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(tr.text('cancel'))),
          FilledButton.tonal(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(tr.text('delete'))),
        ],
      ),
    );
    if (confirmed != true) return;

    final lanSettings = LanSyncSettings.load();
    final registryDevice = lanSettings.hostRegistry[deviceId];
    final deletedDeviceToken = (lanSettings.pairedDevices[deviceId] ?? registryDevice?.deviceToken ?? '').trim();

    await SyncDeviceAccessStore.markWipePending(deviceId, deviceToken: deletedDeviceToken);

    final cloudSettings = CloudSyncSettings.load();
    if (cloudSettings.isConfigured) {
      await CloudSyncService(widget.store).revokeDevice(cloudSettings, deviceId);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('sync_wipe_pending'))));
    await _refresh();
  }

  Future<void> _permanentDeleteDevice(String deviceId) async {
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('permanent_delete_sync_device')),
        content: Text(tr.text('permanent_delete_sync_device_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(tr.text('cancel'))),
          FilledButton.tonal(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(tr.text('permanent_delete'))),
        ],
      ),
    );
    if (confirmed != true) return;

    await _permanentlyDeleteDeviceRecord(deviceId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('sync_device_permanently_deleted'))));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final isHost = widget.store.appIdentity.isHost;
    final lanSettings = LanSyncSettings.load();
    final cloudSettings = CloudSyncSettings.load();
    final peers = SyncDeviceStateStore.loadPeerStates();
    final peerById = <String, HostPeerSyncState>{for (final peer in peers) peer.deviceId: peer};
    final selfState = SyncDeviceStateStore.load(widget.store.appIdentity);

    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.monitor_heart_outlined),
        title: Text(tr.text('sync_monitoring_diagnostics')),
        subtitle: Text(isHost ? tr.text('sync_monitoring_host_desc') : tr.text('sync_monitoring_client_desc')),
        initiallyExpanded: false,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (isHost)
            FutureBuilder<List<CloudDeviceStatus>>(
              future: _cloudDevicesFuture,
              builder: (context, snapshot) => _HostSyncMonitoringTable(
                store: widget.store,
                cloudDevices: snapshot.data ?? const <CloudDeviceStatus>[],
                peerStates: peerById,
                lanSettings: lanSettings,
                loadingCloudDevices: snapshot.connectionState == ConnectionState.waiting,
                onRefresh: _refresh,
                onToggleSuspend: _toggleSuspend,
                onDelete: _deleteDevice,
                onPermanentDelete: _permanentDeleteDevice,
              ),
            )
          else
            _ClientSyncMonitoringPanel(
              state: selfState,
              store: widget.store,
              lanSettings: lanSettings,
              cloudSettings: cloudSettings,
              onRefresh: _refresh,
            ),
        ],
      ),
    );
  }
}

class _HostSyncMonitoringTable extends StatefulWidget {
  const _HostSyncMonitoringTable({
    required this.store,
    required this.cloudDevices,
    required this.peerStates,
    required this.lanSettings,
    required this.loadingCloudDevices,
    required this.onRefresh,
    required this.onToggleSuspend,
    required this.onDelete,
    required this.onPermanentDelete,
  });

  final AppStore store;
  final List<CloudDeviceStatus> cloudDevices;
  final Map<String, HostPeerSyncState> peerStates;
  final LanSyncSettings lanSettings;
  final bool loadingCloudDevices;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String deviceId, bool suspended) onToggleSuspend;
  final Future<void> Function(String deviceId) onDelete;
  final Future<void> Function(String deviceId) onPermanentDelete;

  @override
  State<_HostSyncMonitoringTable> createState() => _HostSyncMonitoringTableState();
}

class _HostSyncMonitoringTableState extends State<_HostSyncMonitoringTable> {
  final ScrollController _tableScrollController = ScrollController();

  @override
  void dispose() {
    _tableScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final cloudById = <String, CloudDeviceStatus>{
      for (final device in widget.cloudDevices)
        if (device.deviceId.trim().isNotEmpty) device.deviceId.trim(): device,
    };
    final deleted = SyncDeviceAccessStore.deletedDeviceIds();
    final suspended = SyncDeviceAccessStore.suspendedDeviceIds();
    final wipePending = SyncDeviceAccessStore.wipePendingDeviceIds();
    // Phase 3: Host Sync Monitoring must discover devices only from the
    // Host Registry. LAN pairing, Cloud rows, and peer history are status
    // details only; they must not add extra devices to this table.
    final registryById = <String, HostRegistryDevice>{
      for (final entry in widget.lanSettings.hostRegistry.entries)
        if (entry.key.trim().isNotEmpty && entry.value.isActive) entry.key.trim(): entry.value,
    };
    final deviceIds = registryById.keys.toSet()..removeWhere((id) => deleted.contains(id));
    final pairedDeviceIds = deviceIds.toList()..sort();

    final header = _HostStatusMonitoringCard(
      store: widget.store,
      lanSettings: widget.lanSettings,
      cloudDevices: widget.cloudDevices,
      peerStates: widget.peerStates,
    );

    if (pairedDeviceIds.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr.text('no_paired_devices_yet'), style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(onPressed: widget.onRefresh, icon: const Icon(Icons.refresh), label: Text(tr.text('refresh'))),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Text(tr.text('sync_monitoring_source_hint'), style: Theme.of(context).textTheme.bodySmall)),
            IconButton(tooltip: tr.text('refresh'), onPressed: widget.onRefresh, icon: const Icon(Icons.refresh)),
          ],
        ),
        if (widget.loadingCloudDevices) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 860) {
              return Column(
                children: [
                  for (final deviceId in pairedDeviceIds)
                    _HostPeerMonitoringCard(
                      store: widget.store,
                      deviceId: deviceId,
                      state: widget.peerStates[deviceId],
                      registryDevice: registryById[deviceId],
                      lanAuthorized: widget.lanSettings.pairedDevices.containsKey(deviceId) || ((registryById[deviceId]?.deviceToken.trim().isNotEmpty ?? false) && registryById[deviceId]?.source != 'cloud_pairing_claim'),
                      cloudDevice: cloudById[deviceId],
                      suspended: suspended.contains(deviceId),
                      wipePending: wipePending.contains(deviceId),
                      onToggleSuspend: () => widget.onToggleSuspend(deviceId, suspended.contains(deviceId)),
                      onDelete: () => widget.onDelete(deviceId),
                      onPermanentDelete: () => widget.onPermanentDelete(deviceId),
                    ),
                ],
              );
            }
            return Scrollbar(
              controller: _tableScrollController,
              thumbVisibility: true,
              trackVisibility: true,
              notificationPredicate: (notification) => notification.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _tableScrollController,
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(label: Text(tr.text('device'))),
                    DataColumn(label: Text(tr.text('active_transport'))),
                    DataColumn(label: Text(tr.text('connection_status'))),
                    DataColumn(label: Text(tr.text('sync_status'))),
                    DataColumn(label: Text(tr.text('last_successful_sync'))),
                    DataColumn(label: Text(tr.text('pending_changes'))),
                    DataColumn(label: Text(tr.text('last_ack_sequence'))),
                    DataColumn(label: Text(tr.text('actions'))),
                  ],
                  rows: [
                    for (final deviceId in pairedDeviceIds)
                      _hostPeerRow(
                        context,
                        deviceId: deviceId,
                        state: widget.peerStates[deviceId],
                        registryDevice: registryById[deviceId],
                        lanAuthorized: widget.lanSettings.pairedDevices.containsKey(deviceId) || ((registryById[deviceId]?.deviceToken.trim().isNotEmpty ?? false) && registryById[deviceId]?.source != 'cloud_pairing_claim'),
                        cloudDevice: cloudById[deviceId],
                        suspended: suspended.contains(deviceId),
                        wipePending: wipePending.contains(deviceId),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  DataRow _hostPeerRow(
    BuildContext context, {
    required String deviceId,
    required HostPeerSyncState? state,
    required HostRegistryDevice? registryDevice,
    required bool lanAuthorized,
    required CloudDeviceStatus? cloudDevice,
    required bool suspended,
    required bool wipePending,
  }) {
    final tr = AppLocalizations.of(context);
    final connection = _connectionStatusForHostPeer(context, state: state, cloudDevice: cloudDevice, suspended: suspended, wipePending: wipePending);
    final status = _syncStatusForHostPeer(context, state, lanAuthorized: lanAuthorized, cloudDevice: cloudDevice, suspended: suspended, wipePending: wipePending);
    return DataRow(
      cells: [
        DataCell(Text(_deviceLabel(deviceId, registryDevice: registryDevice, cloudDevice: cloudDevice))),
        DataCell(Text(_activeTransportForHostPeer(context, lanAuthorized: lanAuthorized, cloudDevice: cloudDevice, state: state))),
        DataCell(_StatusChip(label: connection.label, color: connection.color, icon: connection.icon)),
        DataCell(_StatusChip(label: status.label, color: status.color, icon: status.icon)),
        DataCell(Text(_formatDateTime(context, _lastSuccessfulSyncForHostPeer(state: state, cloudDevice: cloudDevice)))),
        DataCell(Text(_pendingChangesForHostPeer(context, store: widget.store, deviceId: deviceId, state: state, cloudDevice: cloudDevice))),
        DataCell(Text('${state?.lastAckSequence ?? cloudDevice?.lastAckSequence ?? 0}')),
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: wipePending ? null : () => widget.onToggleSuspend(deviceId, suspended), child: Text(suspended ? tr.text('resume') : tr.text('suspend'))),
            TextButton(
              onPressed: wipePending ? () => widget.onPermanentDelete(deviceId) : () => widget.onDelete(deviceId),
              child: Text(wipePending ? tr.text('permanent_delete') : tr.text('delete')),
            ),
          ],
        )),
      ],
    );
  }
}

class _HostStatusMonitoringCard extends StatelessWidget {
  const _HostStatusMonitoringCard({
    required this.store,
    required this.lanSettings,
    required this.cloudDevices,
    required this.peerStates,
  });

  final AppStore store;
  final LanSyncSettings lanSettings;
  final List<CloudDeviceStatus> cloudDevices;
  final Map<String, HostPeerSyncState> peerStates;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final lastAckSequence = <int>[
      for (final peer in peerStates.values) peer.lastAckSequence,
      for (final device in cloudDevices) device.lastAckSequence,
    ].fold<int>(0, (latest, value) => value > latest ? value : latest);
    final identity = store.appIdentity;
    final activeTransport = identity.activeSyncTransportNormalized;
    final lanReady = activeTransport == 'lan' &&
        lanSettings.setupComplete &&
        lanSettings.autoSyncEnabled;
    final cloudReady = activeTransport == 'cloud' && identity.isCloudEnabled;

    return Container(
      width: double.infinity,
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.dns_outlined, size: 20),
              Text(tr.text('host_status'), style: Theme.of(context).textTheme.titleSmall),
              _StatusChip(label: tr.text('host'), color: Theme.of(context).colorScheme.primary, icon: Icons.home_work_outlined),
              if (lanReady) _StatusChip(label: '${tr.text('connection_lan')}: ${tr.text('connection_state_active')}', color: Colors.green, icon: Icons.lan_outlined),
              if (cloudReady) _StatusChip(label: '${tr.text('connection_cloud')}: ${tr.text('connection_state_active')}', color: Colors.blue, icon: Icons.cloud_done_outlined),
              if (!lanReady && !cloudReady) _StatusChip(label: tr.text('connection_state_not_configured'), color: Theme.of(context).colorScheme.error, icon: Icons.link_off_outlined),
            ],
          ),
          const SizedBox(height: 12),
          _Line(title: tr.text('device_id'), value: identity.deviceId),
          _Line(title: tr.text('last_ack_sequence'), value: '$lastAckSequence'),
        ],
      ),
    );
  }
}

class _HostPeerMonitoringCard extends StatelessWidget {
  const _HostPeerMonitoringCard({
    required this.store,
    required this.deviceId,
    required this.state,
    required this.registryDevice,
    required this.lanAuthorized,
    required this.cloudDevice,
    required this.suspended,
    required this.wipePending,
    required this.onToggleSuspend,
    required this.onDelete,
    required this.onPermanentDelete,
  });

  final AppStore store;
  final String deviceId;
  final HostPeerSyncState? state;
  final HostRegistryDevice? registryDevice;
  final bool lanAuthorized;
  final CloudDeviceStatus? cloudDevice;
  final bool suspended;
  final bool wipePending;
  final VoidCallback onToggleSuspend;
  final VoidCallback onDelete;
  final VoidCallback onPermanentDelete;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final connection = _connectionStatusForHostPeer(context, state: state, cloudDevice: cloudDevice, suspended: suspended, wipePending: wipePending);
    final status = _syncStatusForHostPeer(context, state, lanAuthorized: lanAuthorized, cloudDevice: cloudDevice, suspended: suspended, wipePending: wipePending);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.devices_other_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(_deviceLabel(deviceId, registryDevice: registryDevice, cloudDevice: cloudDevice), style: Theme.of(context).textTheme.titleSmall)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _StatusChip(label: connection.label, color: connection.color, icon: connection.icon),
            _StatusChip(label: status.label, color: status.color, icon: status.icon),
          ]),
          const SizedBox(height: 12),
          _Line(title: tr.text('active_transport'), value: _activeTransportForHostPeer(context, lanAuthorized: lanAuthorized, cloudDevice: cloudDevice, state: state)),
          _Line(title: tr.text('connection_status'), value: connection.label),
          _Line(title: tr.text('sync_status'), value: status.label),
          _Line(title: tr.text('last_successful_sync'), value: _formatDateTime(context, _lastSuccessfulSyncForHostPeer(state: state, cloudDevice: cloudDevice))),
          _Line(title: tr.text('pending_changes'), value: _pendingChangesForHostPeer(context, store: store, deviceId: deviceId, state: state, cloudDevice: cloudDevice)),
          _Line(title: tr.text('last_ack_sequence'), value: '${state?.lastAckSequence ?? cloudDevice?.lastAckSequence ?? 0}'),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final fullWidth = constraints.maxWidth < 420;
              final suspendButton = OutlinedButton.icon(onPressed: wipePending ? null : onToggleSuspend, icon: Icon(suspended ? Icons.play_arrow_outlined : Icons.pause_circle_outline), label: Text(suspended ? tr.text('resume') : tr.text('suspend')));
              final deleteButton = OutlinedButton.icon(
                onPressed: wipePending ? onPermanentDelete : onDelete,
                icon: Icon(wipePending ? Icons.delete_forever_outlined : Icons.delete_outline),
                label: Text(wipePending ? tr.text('permanent_delete') : tr.text('delete')),
              );
              if (fullWidth) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    suspendButton,
                    const SizedBox(height: 8),
                    deleteButton,
                  ],
                );
              }
              return Wrap(spacing: 8, runSpacing: 8, children: [suspendButton, deleteButton]);
            },
          ),
        ],
      ),
    );
  }
}

class _ClientSyncMonitoringPanel extends StatelessWidget {
  const _ClientSyncMonitoringPanel({
    required this.state,
    required this.store,
    required this.lanSettings,
    required this.cloudSettings,
    required this.onRefresh,
  });

  final SyncDeviceState state;
  final AppStore store;
  final LanSyncSettings lanSettings;
  final CloudSyncSettings cloudSettings;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final connection = _connectionStatusForClient(context, state: state, lanSettings: lanSettings, cloudSettings: cloudSettings);
    final status = _syncStatusForClient(context, state, pendingCount: store.activeClientPendingSyncCount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                _StatusChip(label: connection.label, color: connection.color, icon: connection.icon),
                _StatusChip(label: status.label, color: status.color, icon: status.icon),
              ]),
            ),
            IconButton(
              tooltip: tr.text('refresh'),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Line(title: tr.text('role'), value: tr.text('client')),
        _Line(title: tr.text('device_id'), value: store.appIdentity.deviceId),
        _Line(title: tr.text('active_transport'), value: _transportLabel(context, state.activeTransport.isNotEmpty ? state.activeTransport : store.appIdentity.activeSyncTransport)),
        _Line(title: tr.text('connection_status'), value: connection.label),
        _Line(title: tr.text('sync_status'), value: status.label),
        _Line(title: tr.text('last_successful_sync'), value: _formatDateTime(context, _lastSuccessfulSyncForClient(state))),
        _Line(title: tr.text('pending_changes'), value: '${store.activeClientPendingSyncCount}'),
        _Line(title: tr.text('last_ack_sequence'), value: '${state.lastAckSequence}'),
      ],
    );
  }
}

class _SyncStatusView {
  const _SyncStatusView({required this.label, required this.color, required this.icon});

  final String label;
  final Color color;
  final IconData icon;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color, required this.icon});

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: 0.45)),
    );
  }
}



_SyncStatusView _connectionStatusForHostPeer(BuildContext context, {required HostPeerSyncState? state, required CloudDeviceStatus? cloudDevice, required bool suspended, bool wipePending = false}) {
  final tr = AppLocalizations.of(context);
  if (wipePending) {
    return _SyncStatusView(label: tr.text('wipe_pending'), color: Theme.of(context).colorScheme.error, icon: Icons.delete_sweep_outlined);
  }
  if (suspended || cloudDevice?.revoked == true) {
    return _SyncStatusView(label: tr.text('connection_state_pending'), color: Theme.of(context).colorScheme.error, icon: Icons.cloud_off_outlined);
  }
  final lastSeen = _lastSeenForHostPeer(state: state, cloudDevice: cloudDevice);
  // Cloud `online` is a sticky database flag and is not a live connection source.
  // Treat Cloud devices as online only when their heartbeat/lastSeen is fresh.
  final recentlySeen = lastSeen != null && DateTime.now().toUtc().difference(lastSeen.toUtc()) <= const Duration(seconds: 90);
  if (recentlySeen) {
    return _SyncStatusView(label: tr.text('connection_state_active'), color: Colors.green, icon: Icons.wifi_tethering_outlined);
  }
  if (lastSeen != null) {
    return _SyncStatusView(label: tr.text('connection_state_pending'), color: Colors.orange, icon: Icons.wifi_off_outlined);
  }
  return _SyncStatusView(label: tr.text('unknown'), color: Theme.of(context).colorScheme.outline, icon: Icons.help_outline);
}

_SyncStatusView _connectionStatusForClient(BuildContext context, {required SyncDeviceState state, required LanSyncSettings lanSettings, required CloudSyncSettings cloudSettings}) {
  final tr = AppLocalizations.of(context);
  final active = state.activeTransport.trim().toLowerCase();
  final configured = active == 'cloud' ? cloudSettings.isConfigured : active == 'lan' ? lanSettings.setupComplete : false;
  final lastSeen = state.lastSeenAt;
  final recentlySeen = lastSeen != null && DateTime.now().toUtc().difference(lastSeen.toUtc()) <= const Duration(seconds: 90);
  if (recentlySeen) {
    return _SyncStatusView(label: tr.text('connection_state_active'), color: Colors.green, icon: Icons.wifi_tethering_outlined);
  }
  if (configured) {
    return _SyncStatusView(label: tr.text('connection_state_pending'), color: Colors.orange, icon: Icons.wifi_off_outlined);
  }
  return _SyncStatusView(label: tr.text('connection_state_not_configured'), color: Theme.of(context).colorScheme.error, icon: Icons.block_outlined);
}

String _activeTransportForHostPeer(BuildContext context, {required bool lanAuthorized, required CloudDeviceStatus? cloudDevice, required HostPeerSyncState? state}) {
  final tr = AppLocalizations.of(context);
  final cloudTransport = (cloudDevice?.activeTransport ?? cloudDevice?.transport ?? '').trim().toLowerCase();
  final lastTransport = (state?.lastSyncTransport ?? cloudDevice?.lastSyncTransport ?? '').trim().toLowerCase();
  if (lanAuthorized && cloudDevice != null) {
    final active = cloudTransport.isNotEmpty ? cloudTransport : lastTransport;
    if (active == 'lan' || active == 'cloud') return _transportLabel(context, active);
    return '${tr.text('lan')} + ${tr.text('cloud')}';
  }
  if (cloudDevice != null) return _transportLabel(context, cloudTransport.isNotEmpty ? cloudTransport : 'cloud');
  if (lanAuthorized) return tr.text('lan');
  if (lastTransport.isNotEmpty) return _transportLabel(context, lastTransport);
  return tr.text('unknown');
}


String _pendingChangesForHostPeer(
  BuildContext context, {
  required AppStore store,
  required String deviceId,
  required HostPeerSyncState? state,
  required CloudDeviceStatus? cloudDevice,
}) {
  final ackSequence = state?.lastAckSequence ?? cloudDevice?.lastAckSequence ?? 0;
  final ackCursor = state?.lastAckCursor ?? cloudDevice?.lastAckCursor ?? cloudDevice?.lastAckAt;
  var count = 0;
  for (final change in store.syncChanges) {
    if (change.deviceId == deviceId) continue;
    final sequencePending = change.sequence > ackSequence;
    final cursorPending = ackCursor == null || change.createdAt.isAfter(ackCursor);
    if (sequencePending || cursorPending) count++;
  }
  return '$count';
}

DateTime? _lastSuccessfulSyncForHostPeer({required HostPeerSyncState? state, required CloudDeviceStatus? cloudDevice}) {
  return state?.lastAckCursor ?? state?.lastAppliedHostCursor ?? cloudDevice?.lastAckAt ?? cloudDevice?.lastAckCursor;
}

DateTime? _lastSeenForHostPeer({required HostPeerSyncState? state, required CloudDeviceStatus? cloudDevice}) {
  return cloudDevice?.lastSeenAt ?? state?.updatedAt;
}

DateTime? _lastSuccessfulSyncForClient(SyncDeviceState state) {
  return state.lastAckCursor ?? state.lastAppliedHostCursor;
}

_SyncStatusView _syncStatusForHostPeer(BuildContext context, HostPeerSyncState? state, {required bool lanAuthorized, required CloudDeviceStatus? cloudDevice, required bool suspended, bool wipePending = false}) {
  final tr = AppLocalizations.of(context);
  if (wipePending) {
    return _SyncStatusView(label: tr.text('wipe_pending'), color: Theme.of(context).colorScheme.error, icon: Icons.delete_sweep_outlined);
  }
  if (suspended) {
    return _SyncStatusView(label: tr.text('suspended'), color: Colors.orange, icon: Icons.pause_circle_outline);
  }
  if (cloudDevice?.revoked == true) {
    return _SyncStatusView(label: tr.text('unauthorized'), color: Theme.of(context).colorScheme.error, icon: Icons.block_outlined);
  }
  final now = DateTime.now();
  final lastSync = _lastSuccessfulSyncForHostPeer(state: state, cloudDevice: cloudDevice);
  final hasAnyAuth = lanAuthorized || cloudDevice != null;
  if (!hasAnyAuth && state == null) {
    return _SyncStatusView(label: tr.text('connection_state_not_configured'), color: Theme.of(context).colorScheme.error, icon: Icons.block_outlined);
  }
  if (lastSync == null) {
    return _SyncStatusView(label: tr.text('not_synced_yet'), color: Theme.of(context).colorScheme.error, icon: Icons.sync_problem_outlined);
  }
  final age = now.difference(lastSync.toLocal());
  if (age <= const Duration(minutes: 10)) {
    return _SyncStatusView(label: tr.text('synced'), color: Colors.green, icon: Icons.check_circle_outline);
  }
  if (age <= const Duration(hours: 2)) {
    return _SyncStatusView(label: tr.text('sync_delayed'), color: Colors.orange, icon: Icons.schedule_outlined);
  }
  return _SyncStatusView(label: tr.text('needs_attention'), color: Theme.of(context).colorScheme.error, icon: Icons.warning_amber_outlined);
}

String _deviceLabel(String deviceId, {HostRegistryDevice? registryDevice, CloudDeviceStatus? cloudDevice}) {
  final registryName = registryDevice?.deviceName.trim() ?? '';
  if (registryName.isNotEmpty) return registryName;
  final cloudName = cloudDevice?.deviceName.trim() ?? '';
  if (cloudName.isNotEmpty) return cloudName;
  return _shortDeviceId(deviceId);
}



_SyncStatusView _syncStatusForClient(BuildContext context, SyncDeviceState state, {required int pendingCount}) {
  final tr = AppLocalizations.of(context);
  final lastSync = _lastSuccessfulSyncForClient(state);

  // Keep Client Diagnostics consistent with the top connection/sync bar.
  // The top bar treats an existing ACK/applied cursor as Synced even when the
  // last successful sync is not recent; Diagnostics should not independently
  // downgrade that same state to Needs Attention just because the timestamp aged.
  if (pendingCount > 0) {
    return _SyncStatusView(label: tr.text('sync_pending'), color: Colors.orange, icon: Icons.pending_actions_outlined);
  }
  if (lastSync == null) {
    return _SyncStatusView(label: tr.text('not_synced_yet'), color: Theme.of(context).colorScheme.error, icon: Icons.sync_problem_outlined);
  }
  return _SyncStatusView(label: tr.text('synced'), color: Colors.green, icon: Icons.check_circle_outline);
}


String _transportLabel(BuildContext context, String value) {
  final tr = AppLocalizations.of(context);
  switch (value.trim().toLowerCase()) {
    case 'cloud':
      return tr.text('cloud');
    case 'lan':
      return tr.text('lan');
    case 'local':
      return tr.text('local');
    default:
      return tr.text('unknown');
  }
}

String _formatDateTime(BuildContext context, DateTime? value) {
  final tr = AppLocalizations.of(context);
  if (value == null) return tr.text('never');
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String _shortDeviceId(String value) {
  final id = value.trim();
  if (id.length <= 14) return id;
  return '${id.substring(0, 6)}…${id.substring(id.length - 6)}';
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
            Text(AppLocalizations.of(context).text('system_status'), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          _StatusBullet(label: AppLocalizations.of(context).text(identity.isHost ? 'host_device' : 'client_device')),
          _StatusBullet(label: '${AppLocalizations.of(context).text('connection_lan')}: ${AppLocalizations.of(context).text('connection_state_active')}'),
          _StatusBullet(label: '${AppLocalizations.of(context).text('connection_cloud')}: ${AppLocalizations.of(context).text(identity.isCloudEnabled ? 'connection_state_active' : 'connection_state_disabled')}'),
          _StatusBullet(label: '${AppLocalizations.of(context).text('connection_sync_health')}: ${AppLocalizations.of(context).text('connection_state_active')}'),
          const Divider(height: 22),
          Text(AppLocalizations.of(context).text('all_systems_are_running_smoothly'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
  const _InfoGridItem(this.icon, this.title, this.value, {this.onEdit});
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onEdit;
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
                            Row(
                              children: [
                                Expanded(
                                  child: Text(item.value, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                ),
                                if (item.onEdit != null) ...[
                                  const SizedBox(width: 8),
                                  IconButton.filledTonal(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: AppLocalizations.of(context).text('edit'),
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    onPressed: item.onEdit,
                                  ),
                                ],
                              ],
                            ),
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


class _KeyboardShortcutsSettingsCard extends StatefulWidget {
  const _KeyboardShortcutsSettingsCard();

  @override
  State<_KeyboardShortcutsSettingsCard> createState() => _KeyboardShortcutsSettingsCardState();
}

class _KeyboardShortcutsSettingsCardState extends State<_KeyboardShortcutsSettingsCard> {
  late SaleShortcutSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = SaleShortcutSettings.load();
  }

  String _keyLabel(AppLocalizations tr, String keyName) {
    if (keyName == SaleShortcutSettings.noneKey) return tr.text('shortcut_none');
    return keyName;
  }

  Future<void> _setSaleShortcut(SaleShortcutAction action, String keyName) async {
    final tr = AppLocalizations.of(context);
    if (_settings.isSaleKeyUsedByAnotherAction(keyName, action)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('shortcut_key_already_used'))));
      return;
    }
    final next = _settings.copyWithSaleActionKey(action, keyName);
    setState(() => _settings = next);
    await next.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('shortcuts_saved'))));
  }

  Future<void> _setPaymentShortcut(SalePaymentShortcutAction action, String keyName) async {
    final tr = AppLocalizations.of(context);
    if (_settings.isPaymentKeyUsedByAnotherAction(keyName, action)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('shortcut_key_already_used'))));
      return;
    }
    final next = _settings.copyWithPaymentActionKey(action, keyName);
    setState(() => _settings = next);
    await next.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('shortcuts_saved'))));
  }

  Future<void> _setPurchasesShortcut(PurchasesShortcutAction action, String keyName) async {
    final tr = AppLocalizations.of(context);
    if (_settings.isPurchasesKeyUsedByAnotherAction(keyName, action)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('shortcut_key_already_used'))));
      return;
    }
    final next = _settings.copyWithPurchasesActionKey(action, keyName);
    setState(() => _settings = next);
    await next.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('shortcuts_saved'))));
  }

  Future<void> _setPurchaseDialogShortcut(PurchaseDialogShortcutAction action, String keyName) async {
    final tr = AppLocalizations.of(context);
    if (_settings.isPurchaseDialogKeyUsedByAnotherAction(keyName, action)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('shortcut_key_already_used'))));
      return;
    }
    final next = _settings.copyWithPurchaseDialogActionKey(action, keyName);
    setState(() => _settings = next);
    await next.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('shortcuts_saved'))));
  }

  Future<void> _resetDefaults() async {
    final next = SaleShortcutSettings.defaults();
    setState(() => _settings = next);
    await next.save();
  }

  Widget _shortcutDropdown({
    required BuildContext context,
    required String? value,
    required ValueChanged<String> onChanged,
  }) {
    final tr = AppLocalizations.of(context);
    return DropdownButtonFormField<String>(
      initialValue: value ?? SaleShortcutSettings.noneKey,
      decoration: const InputDecoration(isDense: true),
      items: [
        for (final keyName in SaleShortcutSettings.availableKeys)
          DropdownMenuItem(value: keyName, child: Text(_keyLabel(tr, keyName))),
      ],
      onChanged: (value) {
        if (value == null) return;
        onChanged(value);
      },
    );
  }

  Widget _buildSaleShortcuts(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr.text('sale_page'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(tr.text('keyboard_shortcuts_sale_hint'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final action in SaleShortcutAction.values) ...[
          Row(
            children: [
              Expanded(child: Text(tr.text(action.labelKey))),
              SizedBox(
                width: 160,
                child: _shortcutDropdown(
                  context: context,
                  value: _settings.saleBindings[action],
                  onChanged: (value) => _setSaleShortcut(action, value),
                ),
              ),
            ],
          ),
          const Divider(height: 18),
        ],
      ],
    );
  }

  Widget _buildPaymentShortcuts(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr.text('shortcut_page_sale_payment'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(tr.text('keyboard_shortcuts_payment_hint'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final action in SalePaymentShortcutAction.values) ...[
          Row(
            children: [
              Expanded(child: Text(tr.text(action.labelKey))),
              SizedBox(
                width: 160,
                child: _shortcutDropdown(
                  context: context,
                  value: _settings.paymentBindings[action],
                  onChanged: (value) => _setPaymentShortcut(action, value),
                ),
              ),
            ],
          ),
          const Divider(height: 18),
        ],
      ],
    );
  }


  Widget _buildPurchasesShortcuts(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr.text('purchases'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(tr.text('keyboard_shortcuts_purchases_hint'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final action in PurchasesShortcutAction.values) ...[
          Row(
            children: [
              Expanded(child: Text(tr.text(action.labelKey))),
              SizedBox(
                width: 160,
                child: _shortcutDropdown(
                  context: context,
                  value: _settings.purchasesBindings[action],
                  onChanged: (value) => _setPurchasesShortcut(action, value),
                ),
              ),
            ],
          ),
          const Divider(height: 18),
        ],
      ],
    );
  }

  Widget _buildPurchaseDialogShortcuts(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr.text('shortcut_page_purchase_dialog'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(tr.text('keyboard_shortcuts_purchase_dialog_hint'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final action in PurchaseDialogShortcutAction.values) ...[
          Row(
            children: [
              Expanded(child: Text(tr.text(action.labelKey))),
              SizedBox(
                width: 160,
                child: _shortcutDropdown(
                  context: context,
                  value: _settings.purchaseDialogBindings[action],
                  onChanged: (value) => _setPurchaseDialogShortcut(action, value),
                ),
              ),
            ],
          ),
          const Divider(height: 18),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return _SectionCard(
      icon: Icons.keyboard_command_key_outlined,
      title: tr.text('keyboard_shortcuts'),
      subtitle: tr.text('keyboard_shortcuts_desc'),
      trailing: TextButton.icon(
        onPressed: _resetDefaults,
        icon: const Icon(Icons.restore_outlined),
        label: Text(tr.text('restore_defaults')),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSaleShortcuts(context),
          const SizedBox(height: 18),
          _buildPaymentShortcuts(context),
          const SizedBox(height: 18),
          _buildPurchasesShortcuts(context),
          const SizedBox(height: 18),
          _buildPurchaseDialogShortcuts(context),
        ],
      ),
    );
  }
}

class _SystemIdentityCard extends StatefulWidget {
  const _SystemIdentityCard({required this.store});

  final AppStore store;

  @override
  State<_SystemIdentityCard> createState() => _SystemIdentityCardState();
}

class _SystemIdentityCardState extends State<_SystemIdentityCard> {
  Future<void> _editDeviceName() async {
    final tr = AppLocalizations.of(context);
    final controller = TextEditingController(text: widget.store.appIdentity.deviceName);
    String? errorText;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(tr.text('device_name')),
              content: TextField(
                controller: controller,
                autofocus: true,
                maxLength: 60,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: tr.text('device_name'),
                  errorText: errorText,
                ),
                onSubmitted: (_) {
                  final value = controller.text.trim().replaceAll(RegExp(r'\s+'), ' ');
                  if (value.isEmpty) {
                    setDialogState(() => errorText = tr.text('device_name_empty'));
                    return;
                  }
                  Navigator.of(dialogContext).pop(value);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(tr.text('cancel')),
                ),
                FilledButton(
                  onPressed: () {
                    final value = controller.text.trim().replaceAll(RegExp(r'\s+'), ' ');
                    if (value.isEmpty) {
                      setDialogState(() => errorText = tr.text('device_name_empty'));
                      return;
                    }
                    Navigator.of(dialogContext).pop(value);
                  },
                  child: Text(tr.text('save')),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) return;
    try {
      await widget.store.updateDeviceName(result);
      final cloud = CloudSyncSettings.load();
      if (widget.store.appIdentity.isCloudEnabled && cloud.isConfigured) {
        await CloudSyncService(widget.store).registerCurrentDevice(
          cloud,
          transport: widget.store.appIdentity.activeSyncTransportNormalized == 'lan' ? 'cloud' : widget.store.appIdentity.activeSyncTransportNormalized,
        );
      }
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tr.text('device_name')} ${tr.text('save')}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final identity = widget.store.appIdentity;
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
          _InfoGridItem(Icons.badge_outlined, tr.text('device_name'), identity.deviceName.trim().isEmpty ? identity.deviceId : identity.deviceName.trim(), onEdit: _editDeviceName),
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
