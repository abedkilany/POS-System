import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:printing/printing.dart';

import '../../core/app_brand.dart';
import '../../core/services/backup_download_service.dart';
import '../../core/services/barcode_feedback_service.dart';
import '../../core/services/direct_control_plane_service.dart';
import '../../core/services/direct_sync_settings.dart';
import '../../core/services/account_auth_service.dart';
import '../../core/services/accounting_service.dart';
import '../../core/services/google_drive_backup_service.dart';
import '../../core/services/lan_sync_service.dart';
import '../../core/services/local_database_service.dart';
import '../../core/services/local_auto_backup_service.dart';
import '../../core/services/app_update_service.dart';
import '../../core/services/sync_diagnostics_log.dart';
import '../../core/services/page_timing_scope.dart';
import '../../core/shortcuts/app_shortcuts.dart';
import '../../core/sync_unified/sync_device_state.dart';
import '../../core/sync_unified/sync_unified.dart';
import '../../core/snapshot/unified_snapshot_progress.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/responsive.dart';
import 'package:ventio/core/contracts/application_session.dart';
import '../../models/store_profile.dart';
import '../../models/print_settings.dart';
import '../../models/app_identity.dart';
import '../../models/product_costing.dart';
import '../../models/warehouse.dart';
import '../../models/user_role.dart';
import '../shared/sync_monitoring_section.dart';
import '../security/sensitive_action_guard.dart';
import '../maintenance/phase10_health_service.dart';
import '../barcode/barcode_scanner_page.dart';
import '../assistant/assistant_provider_settings_page.dart';
import 'users_permissions_page.dart';

part 'settings_page_backup.dart';
part 'settings_page_backup_helpers.dart';
part 'settings_page_sync_shared.dart';
part 'settings_general.dart';
part 'settings_currency.dart';
part 'settings_printer.dart';
part 'settings_sync.dart';
part 'settings_devices.dart';
part 'settings_security.dart';
part 'settings_page_sections.dart';
part 'settings_page_financial_actions.dart';
part 'settings_page_organization_actions.dart';
part 'settings_page_data_actions.dart';
part 'settings_page_sync_configuration.dart';
part 'settings_page_sync_pairing_actions.dart';
part 'settings_page_sync_operations.dart';
part 'settings_page_sync_dashboard.dart';
part 'settings_page_sync_connect_dialog.dart';
part 'settings_page_sync_channels.dart';
part 'settings_page_sync_pairing_views.dart';
part 'settings_page_backup_widgets.dart';
part 'settings_page_cash_widgets.dart';
part 'settings_page_sync.dart';
part 'settings_page_sync_monitoring.dart';
part 'settings_page_navigation_widgets.dart';
part 'settings_page_update_widgets.dart';
part 'settings_page_info_widgets.dart';
part 'settings_page_shortcuts_identity_widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage(
      {super.key,
      required this.onLocaleChanged,
      required this.onThemeModeChanged,
      required this.themeMode,
      required this.store,
      this.onSyncSettingsChanged});

  final ValueChanged<Locale> onLocaleChanged;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ThemeMode themeMode;
  final ApplicationSession store;
  final Future<void> Function()? onSyncSettingsChanged;

  bool get _supportsKeyboardShortcuts =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final canAccessGeneralSettings = store.security.hasAnyPermission(<String>{
      AppPermission.settingsView,
      AppPermission.settingsManage,
      AppPermission.usersManage,
      AppPermission.rolesManage,
      AppPermission.permissionsManage,
    });
    final canAccessSyncSettings = store.security.hasAnyPermission(<String>{
      AppPermission.syncView,
      AppPermission.syncManage,
    });
    final canAccessBackupSettings = store.security.hasAnyPermission(<String>{
      AppPermission.backupExport,
      AppPermission.backupRestore,
      AppPermission.backupManage,
    });
    final sections = <_SettingsSection>[
      if (canAccessGeneralSettings)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.tune_outlined,
              label: tr.text('settings_general'),
              description: tr.text('settings_general_desc')),
          pageBuilder: (context) =>
              _settingsList(context, _organizedGeneralCards(context)),
        ),
      if (canAccessGeneralSettings)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.auto_awesome_outlined,
              label: tr.text('assistant_settings_title'),
              description: tr.text('assistant_settings_description')),
          pageBuilder: (context) => AssistantProviderSettingsPage(store: store),
        ),
      if (canAccessGeneralSettings)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.description_outlined,
              label: tr.text('settings_documents'),
              description: tr.text('document_settings_desc')),
          pageBuilder: (context) =>
              _settingsList(context, _documentCards(context)),
        ),
      if (canAccessGeneralSettings)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.account_tree_outlined,
              label: tr.text('settings_branches_warehouses'),
              description: tr.text('settings_branches_warehouses_desc')),
          pageBuilder: (context) =>
              _settingsList(context, _organizedBranchCards(context)),
        ),
      if (canAccessGeneralSettings)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.receipt_long_outlined,
              label: tr.text('settings_taxes'),
              description: tr.text('tax_settings_desc')),
          pageBuilder: (context) => _settingsList(context, _taxCards(context)),
        ),
      if (canAccessGeneralSettings)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.currency_exchange_outlined,
              label: tr.text('settings_currency_pricing'),
              description: tr.text('currencies_pricing_desc')),
          pageBuilder: (context) =>
              _settingsList(context, _organizedCurrencyCards(context)),
        ),
      if (canAccessGeneralSettings)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.print_outlined,
              label: tr.text('settings_printers'),
              description: tr.text('settings_printers_desc')),
          pageBuilder: (context) =>
              _settingsList(context, _printerCards(context)),
        ),
      if (canAccessSyncSettings)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.sync_outlined,
              label: tr.text('sync'),
              description: tr.text('sync_nav_desc')),
          pageBuilder: (context) =>
              _settingsList(context, _organizedSyncCards(context)),
        ),
      if (canAccessSyncSettings || canAccessGeneralSettings)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.devices_other_outlined,
              label: tr.text('settings_devices'),
              description: tr.text('settings_devices_desc')),
          pageBuilder: (context) =>
              _settingsList(context, _deviceCards(context)),
        ),
      if (canAccessBackupSettings)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.backup_outlined,
              label: tr.text('settings_backups'),
              description: tr.text('backup_preview_desc')),
          pageBuilder: (context) =>
              _settingsList(context, _backupCards(context)),
        ),
      if (store.security.hasAnyPermission(<String>{
        AppPermission.usersManage,
        AppPermission.rolesManage,
        AppPermission.permissionsManage,
      }))
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.admin_panel_settings_outlined,
              label: tr.text('settings_security_permissions'),
              description: tr.text('settings_security_permissions_desc')),
          pageBuilder: (context) =>
              _settingsList(context, _securityCards(context)),
        ),
      if (_supportsKeyboardShortcuts)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.keyboard_command_key_outlined,
              label: tr.text('keyboard_shortcuts'),
              description: tr.text('keyboard_shortcuts_desc')),
          pageBuilder: (context) =>
              _settingsList(context, _shortcutCards(context)),
        ),
      _SettingsSection(
        nav: _SettingsNavData(
            icon: Icons.info_outline,
            label: tr.text('about_ventio'),
            description: tr.text('about_ventio_desc')),
        pageBuilder: (context) => _settingsList(context, _aboutCards(context)),
      ),
    ];

    return DefaultTabController(
      length: sections.length,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          if (sections.isEmpty) {
            return const SizedBox.shrink();
          }
          final navItems = sections.map((section) => section.nav).toList();
          final pages = sections
              .map((section) => _DeferredSettingsPage(
                    builder: section.pageBuilder,
                  ))
              .toList();

          if (!isWide) {
            return Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: TabBar(
                    isScrollable: true,
                    tabs: [
                      for (final item in navItems)
                        Tab(icon: Icon(item.icon), text: item.label)
                    ],
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
                    ),
                  ),
                ),
                VerticalDivider(
                    width: 1,
                    color: Theme.of(context).colorScheme.outlineVariant),
                Expanded(child: TabBarView(children: pages)),
              ],
            );
          });
        },
      ),
    );
  }
}
