import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_brand.dart';
import '../../core/services/backup_download_service.dart';
import '../../core/services/barcode_feedback_service.dart';
import '../../core/services/cloud_sync_service.dart';
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
import '../../data/app_store.dart';
import '../../models/store_profile.dart';
import '../../models/app_identity.dart';
import '../../models/product_costing.dart';
import '../../models/user_role.dart';
import '../shared/sync_monitoring_section.dart';
import '../barcode/barcode_scanner_page.dart';
import 'users_permissions_page.dart';

part 'settings_page_backup.dart';
part 'settings_page_sync_shared.dart';

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
  final AppStore store;
  final Future<void> Function()? onSyncSettingsChanged;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final canAccessGeneralSettings = store.hasAnyPermission(<String>{
      AppPermission.settingsView,
      AppPermission.settingsManage,
      AppPermission.usersManage,
      AppPermission.rolesManage,
      AppPermission.permissionsManage,
    });
    final canAccessSyncSettings = store.hasAnyPermission(<String>{
      AppPermission.syncView,
      AppPermission.syncManage,
    });
    final canAccessBackupSettings = store.hasAnyPermission(<String>{
      AppPermission.backupExport,
      AppPermission.backupRestore,
      AppPermission.backupManage,
    });
    final sections = <_SettingsSection>[
      if (canAccessGeneralSettings)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.store_outlined,
              label: tr.text('store_information'),
              description: tr.text('store_information_desc')),
          page: _settingsList(context, _generalCards(context)),
        ),
      if (canAccessGeneralSettings)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.description_outlined,
              label: tr.text('document_settings'),
              description: tr.text('document_settings_desc')),
          page: _settingsList(context, _documentCards(context)),
        ),
      if (canAccessGeneralSettings)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.account_tree_outlined,
              label: tr.text('branches'),
              description: tr.text('branches_desc')),
          page: _settingsList(context, _branchCards(context)),
        ),
      if (canAccessGeneralSettings)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.receipt_long_outlined,
              label: tr.text('tax_settings'),
              description: tr.text('tax_settings_desc')),
          page: _settingsList(context, _taxCards(context)),
        ),
      if (canAccessGeneralSettings)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.currency_exchange_outlined,
              label: tr.text('currencies'),
              description: tr.text('currencies_pricing_desc')),
          page: _settingsList(context, _financialCards(context)),
        ),
      if (canAccessGeneralSettings)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.account_balance_wallet_outlined,
              label: tr.text('banks_cash_drawers'),
              description: tr.text('banks_cash_drawers_desc')),
          page: _settingsList(context, _cashBankCards(context)),
        ),
      if (canAccessSyncSettings)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.sync_outlined,
              label: tr.text('sync'),
              description: tr.text('sync_nav_desc')),
          page: _settingsList(context, _syncCards(context)),
        ),
      if (canAccessBackupSettings)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.backup_outlined,
              label: tr.text('backup_restore'),
              description: tr.text('backup_preview_desc')),
          page: _settingsList(context, _backupCards(context)),
        ),
      if (store.canManageUsers)
        _SettingsSection(
          nav: _SettingsNavData(
              icon: Icons.admin_panel_settings_outlined,
              label: tr.text('users_permissions'),
              description: tr.text('users_permissions_desc')),
          page: _settingsList(context, _adminCards(context)),
        ),
      _SettingsSection(
        nav: _SettingsNavData(
            icon: Icons.keyboard_command_key_outlined,
            label: tr.text('keyboard_shortcuts'),
            description: tr.text('keyboard_shortcuts_desc')),
        page: _settingsList(context, _shortcutCards(context)),
      ),
      _SettingsSection(
        nav: _SettingsNavData(
            icon: Icons.info_outline,
            label: tr.text('about_ventio'),
            description: tr.text('about_ventio_desc')),
        page: _settingsList(context, _aboutCards(context)),
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
          final pages = sections.map((section) => section.page).toList();

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
                      store: store,
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
    final displayName = profile.tradeName.trim().isNotEmpty
        ? profile.tradeName
        : profile.name;
    final legalName = profile.legalName.trim().isNotEmpty
        ? profile.legalName
        : profile.name;
    return [
      _SectionCard(
        icon: Icons.business_outlined,
        title: tr.text('organization_center'),
        subtitle: tr.text('organization_center_desc'),
        child: Text(
          tr.text('organization_center_helper'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
      _SectionCard(
        icon: Icons.storefront_outlined,
        title: tr.text('organization_general'),
        subtitle: tr.text('organization_general_desc'),
        trailing: FilledButton.icon(
          onPressed: store.hasPermission(AppPermission.settingsManage)
              ? () => _editOrganizationGeneral(context, profile)
              : null,
          icon: const Icon(Icons.edit_outlined),
          label: Text(tr.text('edit')),
        ),
        child: Column(
          children: [
            _InfoTile(
                icon: Icons.store_outlined,
                title: tr.text('store_name'),
                value: displayName),
            _InfoTile(
                icon: Icons.badge_outlined,
                title: tr.text('trade_name'),
                value: profile.tradeName.isEmpty ? '—' : profile.tradeName),
            _InfoTile(
                icon: Icons.phone_outlined,
                title: tr.text('phone'),
                value: profile.phone.isEmpty ? '—' : profile.phone),
            _InfoTile(
                icon: Icons.email_outlined,
                title: tr.text('email'),
                value: profile.email.isEmpty ? '—' : profile.email),
            _InfoTile(
                icon: Icons.language_outlined,
                title: tr.text('website'),
                value: profile.website.isEmpty ? '—' : profile.website),
          ],
        ),
      ),
      _SectionCard(
        icon: Icons.gavel_outlined,
        title: tr.text('organization_legal'),
        subtitle: tr.text('organization_legal_desc'),
        trailing: FilledButton.icon(
          onPressed: store.hasPermission(AppPermission.settingsManage)
              ? () => _editOrganizationLegal(context, profile)
              : null,
          icon: const Icon(Icons.edit_outlined),
          label: Text(tr.text('edit')),
        ),
        child: Column(
          children: [
            _InfoTile(
                icon: Icons.account_balance_outlined,
                title: tr.text('legal_name'),
                value: legalName),
            _InfoTile(
                icon: Icons.percent_outlined,
                title: tr.text('vat_number'),
                value: profile.vatNumber.isEmpty ? '—' : profile.vatNumber),
            _InfoTile(
                icon: Icons.confirmation_number_outlined,
                title: tr.text('tax_registration_number'),
                value: profile.taxRegistrationNumber.isEmpty
                    ? '—'
                    : profile.taxRegistrationNumber),
            _InfoTile(
                icon: Icons.article_outlined,
                title: tr.text('commercial_register_number'),
                value: profile.commercialRegisterNumber.isEmpty
                    ? '—'
                    : profile.commercialRegisterNumber),
            _InfoTile(
                icon: Icons.public_outlined,
                title: tr.text('country'),
                value: profile.country.isEmpty ? '—' : profile.country),
            _InfoTile(
                icon: Icons.map_outlined,
                title: tr.text('governorate'),
                value: profile.governorate.isEmpty ? '—' : profile.governorate),
            _InfoTile(
                icon: Icons.location_city_outlined,
                title: tr.text('city'),
                value: profile.city.isEmpty ? '—' : profile.city),
            _InfoTile(
                icon: Icons.location_on_outlined,
                title: tr.text('address'),
                value: profile.address.isEmpty ? '—' : profile.address),
          ],
        ),
      ),
      _SectionCard(
        icon: Icons.account_balance_wallet_outlined,
        title: tr.text('organization_financial'),
        subtitle: tr.text('organization_financial_desc'),
        child: Column(
          children: [
            _InfoTile(
                icon: Icons.currency_exchange_outlined,
                title: tr.text('base_currency'),
                value: profile.baseCurrency),
            _InfoTile(
                icon: Icons.sell_outlined,
                title: tr.text('default_product_currency'),
                value: profile.defaultProductCurrency),
            _InfoTile(
                icon: Icons.receipt_long_outlined,
                title: tr.text('default_sale_invoice_currency'),
                value: profile.defaultSaleInvoiceCurrency),
            _InfoTile(
                icon: Icons.payments_outlined,
                title: tr.text('default_sale_payment_currency'),
                value: profile.defaultSalePaymentCurrency),
            _InfoTile(
                icon: Icons.info_outline,
                title: tr.text('managed_from'),
                value: tr.text('currencies')),
          ],
        ),
      ),
      _SectionCard(
        icon: Icons.palette_outlined,
        title: tr.text('organization_branding'),
        subtitle: tr.text('organization_branding_desc'),
        trailing: FilledButton.icon(
          onPressed: store.hasPermission(AppPermission.settingsManage)
              ? () => _editOrganizationBranding(context, profile)
              : null,
          icon: const Icon(Icons.edit_outlined),
          label: Text(tr.text('edit')),
        ),
        child: Column(
          children: [
            _InfoTile(
                icon: Icons.image_outlined,
                title: tr.text('logo_path'),
                value: profile.logoPath.isEmpty ? '—' : profile.logoPath),
            _InfoTile(
                icon: Icons.receipt_long_outlined,
                title: tr.text('invoice_footer'),
                value: profile.footerNote),
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
              Text(tr.text('theme'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment<ThemeMode>(
                      value: ThemeMode.system,
                      icon: const Icon(Icons.settings_suggest_outlined),
                      label: Text(tr.text('theme_system'))),
                  ButtonSegment<ThemeMode>(
                      value: ThemeMode.light,
                      icon: const Icon(Icons.light_mode_outlined),
                      label: Text(tr.text('theme_light'))),
                  ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      icon: const Icon(Icons.dark_mode_outlined),
                      label: Text(tr.text('theme_dark'))),
                ],
                selected: {themeMode},
                onSelectionChanged: (selection) =>
                    onThemeModeChanged(selection.first),
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
              Text(tr.text('language'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              SegmentedButton<Locale>(
                segments: [
                  ButtonSegment<Locale>(
                      value: const Locale('en'),
                      label: Text(tr.text('language_english'))),
                  ButtonSegment<Locale>(
                      value: const Locale('ar'),
                      label: Text(tr.text('language_arabic'))),
                ],
                selected: {tr.locale},
                onSelectionChanged: (selection) =>
                    onLocaleChanged(selection.first),
              ),
            ],
          ),
        ),
      ),
      const _ScannerFeedbackSettingsCard(),
    ];
  }

  List<Widget> _aboutCards(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final identity = store.appIdentity;
    return [
      _SectionCard(
        icon: Icons.info_outline,
        title: tr.text('about_ventio'),
        subtitle: tr.text('about_ventio_desc'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _VentioBrandHeader(
              title: AppBrand.name,
              subtitle: tr.text('about_ventio_summary'),
            ),
            const SizedBox(height: 18),
            _InfoGrid(
              items: [
                _InfoGridItem(Icons.verified_outlined, tr.text('app_name'),
                    AppBrand.name),
                _InfoGridItem(Icons.new_releases_outlined,
                    tr.text('app_version'), AppBrand.version),
                _InfoGridItem(Icons.computer_outlined, tr.text('platform'),
                    identity.platform.name),
                _InfoGridItem(Icons.dns_outlined, tr.text('device_role'),
                    identity.deviceRole.name),
                _InfoGridItem(Icons.storefront_outlined, tr.text('store_name'),
                    store.storeProfile.name),
                _InfoGridItem(Icons.cloud_sync_outlined, tr.text('sync_mode'),
                    identity.isHost ? tr.text('host') : identity.syncMode.name),
              ],
            ),
            const _WindowsUpdateStatusCard(),
          ],
        ),
      ),
    ];
  }

  List<Widget> _documentCards(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final profile = store.storeProfile;
    final docs = profile.documentNumbering;
    return [
      _SectionCard(
        icon: Icons.description_outlined,
        title: tr.text('document_settings'),
        subtitle: tr.text('document_settings_desc'),
        trailing: FilledButton.icon(
          onPressed: store.hasPermission(AppPermission.settingsManage)
              ? () => _editDocumentNumbering(context, profile)
              : null,
          icon: const Icon(Icons.edit_outlined),
          label: Text(tr.text('edit')),
        ),
        child: Column(
          children: [
            _InfoTile(
                icon: Icons.receipt_long_outlined,
                title: tr.text('invoice_prefix'),
                value: docs.invoicePrefix),
            _InfoTile(
                icon: Icons.request_quote_outlined,
                title: tr.text('quote_prefix'),
                value: docs.quotePrefix),
            _InfoTile(
                icon: Icons.shopping_cart_outlined,
                title: tr.text('purchase_prefix'),
                value: docs.purchasePrefix),
            _InfoTile(
                icon: Icons.local_shipping_outlined,
                title: tr.text('delivery_note_prefix'),
                value: docs.deliveryNotePrefix),
            _InfoTile(
                icon: Icons.assignment_return_outlined,
                title: tr.text('return_prefix'),
                value: docs.returnPrefix),
          ],
        ),
      ),
      _SectionCard(
        icon: Icons.info_outline,
        title: tr.text('document_settings_note'),
        subtitle: tr.text('document_settings_note_desc'),
        child: Text(
          tr.text('document_settings_helper'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    ];
  }

  List<Widget> _branchCards(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final profile = store.storeProfile;
    final branches = profile.branches;
    return [
      _SectionCard(
        icon: Icons.account_tree_outlined,
        title: tr.text('branches'),
        subtitle: tr.text('branches_desc'),
        trailing: FilledButton.icon(
          onPressed: store.hasPermission(AppPermission.settingsManage)
              ? () => _editBranch(context, profile, null)
              : null,
          icon: const Icon(Icons.add_outlined),
          label: Text(tr.text('add_branch')),
        ),
        child: branches.isEmpty
            ? Text(
                tr.text('no_branches_yet'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              )
            : Column(
                children: [
                  for (final branch in branches)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(branch.isActive
                          ? Icons.storefront_outlined
                          : Icons.storefront_outlined),
                      title: Text(branch.name),
                      subtitle: Text([
                        if (branch.code.trim().isNotEmpty) branch.code,
                        if (branch.phone.trim().isNotEmpty) branch.phone,
                        if (branch.address.trim().isNotEmpty) branch.address,
                        branch.isActive
                            ? tr.text('active')
                            : tr.text('inactive'),
                      ].join(' • ')),
                      trailing: IconButton(
                        tooltip: tr.text('edit'),
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: store.hasPermission(AppPermission.settingsManage)
                            ? () => _editBranch(context, profile, branch)
                            : null,
                      ),
                    ),
                ],
              ),
      ),
      _SectionCard(
        icon: Icons.info_outline,
        title: tr.text('branches_note'),
        subtitle: tr.text('branches_note_desc'),
        child: Text(
          tr.text('branches_helper'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    ];
  }

  List<Widget> _taxCards(BuildContext context) {
    final tr = AppLocalizations.of(context);

    return [
      _SectionCard(
        icon: Icons.receipt_long_outlined,
        title: tr.text('tax_settings'),
        subtitle: tr.text('tax_settings_desc'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr.text('product_level_taxes_desc'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              tr.text('manage_product_taxes_hint'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    ];
  }

  String _costingMethodTitle(AppLocalizations tr, InventoryCostingMethod method) {
    switch (method) {
      case InventoryCostingMethod.fifo:
        return tr.text('fifo');
      case InventoryCostingMethod.lastPurchaseCost:
        return tr.text('last_cost');
      case InventoryCostingMethod.weightedAverage:
        return tr.text('weighted_average_cost');
    }
  }

  Widget _inventoryCostingCard(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final method = store.inventoryCostingMethod;
    return _SectionCard(
      icon: Icons.inventory_2_outlined,
      title: tr.text('inventory_costing_method'),
      subtitle: tr.text('inventory_costing_method_desc'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<InventoryCostingMethod>(
            segments: [
              ButtonSegment<InventoryCostingMethod>(
                value: InventoryCostingMethod.weightedAverage,
                icon: const Icon(Icons.functions_outlined),
                label: Text(tr.text('weighted_average_cost')),
              ),
              ButtonSegment<InventoryCostingMethod>(
                value: InventoryCostingMethod.fifo,
                icon: const Icon(Icons.low_priority_outlined),
                label: Text(tr.text('fifo')),
              ),
              ButtonSegment<InventoryCostingMethod>(
                value: InventoryCostingMethod.lastPurchaseCost,
                icon: const Icon(Icons.history_outlined),
                label: Text(tr.text('last_cost')),
              ),
            ],
            selected: {method},
            onSelectionChanged: (selection) async {
              final next = selection.first;
              if (next == method) return;
              await store.setInventoryCostingMethod(
                next,
                reason: tr.text('changed_from_settings'),
              );
            },
          ),
          const SizedBox(height: 12),
          Text('${tr.text('current_method')}: ${_costingMethodTitle(tr, method)}'),
          const SizedBox(height: 8),
          Text(
            tr.text('inventory_costing_method_note'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (store.costingMethodHistory.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(tr.text('history'), style: Theme.of(context).textTheme.titleSmall),
            for (final row in store.costingMethodHistory.reversed.take(5))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.timeline_outlined),
                title: Text(_costingMethodTitle(tr, row.method)),
                subtitle: Text('${DateFormat.yMd().add_Hm().format(row.effectiveFrom)}${row.effectiveTo == null ? ' → ${tr.text('active')}' : ' → ${DateFormat.yMd().add_Hm().format(row.effectiveTo!)}'}${row.reason.isEmpty ? '' : ' · ${row.reason}'}'),
              ),
          ],
        ],
      ),
    );
  }

  List<Widget> _cashBankCards(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return [
      _SectionCard(
        icon: Icons.account_balance_wallet_outlined,
        title: tr.text('banks_cash_drawers'),
        subtitle: tr.text('banks_cash_drawers_desc'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr.text('banks_cash_drawers_helper'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            _CurrentDeviceCashDrawerSettingsCard(store: store),
          ],
        ),
      ),
    ];
  }

  List<Widget> _financialCards(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final profile = store.storeProfile;
    final activeCurrencies =
        profile.currencies.where((item) => item.isActive).toList();
    final base = profile.currencyByCode(profile.baseCurrency);
    final usdLbpRate = profile.latestExchangeRate('USD', 'LBP')?.rate ??
        profile.usdToLbpRate;

    return [
      _SectionCard(
        icon: Icons.payments_outlined,
        title: tr.text('currencies_pricing'),
        subtitle: tr.text('currencies_pricing_desc'),
        trailing: FilledButton.icon(
          onPressed: store.hasPermission(AppPermission.settingsManage)
              ? () => _editFinancialSettings(context, profile)
              : null,
          icon: const Icon(Icons.edit_outlined),
          label: Text(tr.text('edit')),
        ),
        child: _InfoGrid(
          items: [
            _InfoGridItem(
                Icons.account_balance_outlined,
                tr.text('base_currency'),
                '${base.code} · ${base.name}'),
            _InfoGridItem(
                Icons.currency_exchange_outlined,
                tr.text('usd_lbp_exchange_rate'),
                '1 USD = ${usdLbpRate.toStringAsFixed(0)} LBP'),
            _InfoGridItem(
                Icons.price_change_outlined,
                tr.text('price_storage_decimals'),
                profile.priceStorageDecimals.toString()),
            _InfoGridItem(
                Icons.visibility_outlined,
                tr.text('price_display_mode'),
                _priceDisplayModeLabel(tr, profile)),
            _InfoGridItem(
                Icons.attach_money_outlined,
                tr.text('default_product_currency'),
                profile.defaultProductCurrency),
            _InfoGridItem(
                Icons.receipt_long_outlined,
                tr.text('default_sale_invoice_currency'),
                profile.defaultSaleInvoiceCurrency),
            _InfoGridItem(
                Icons.payments_outlined,
                tr.text('default_sale_payment_currency'),
                profile.defaultSalePaymentCurrency),
            _InfoGridItem(
                Icons.tune_outlined,
                tr.text('active_currencies'),
                activeCurrencies.map((item) => item.code).join(', ')),
          ],
        ),
      ),
      _inventoryCostingCard(context),
      _SectionCard(
        icon: Icons.monetization_on_outlined,
        title: tr.text('currencies'),
        subtitle: tr.text('currencies_desc'),
        trailing: FilledButton.icon(
          onPressed: store.hasPermission(AppPermission.settingsManage)
              ? () => _editCurrency(context, profile)
              : null,
          icon: const Icon(Icons.add_outlined),
          label: Text(tr.text('add_currency')),
        ),
        child: Column(
          children: [
            for (final currency in profile.currencies)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text(currency.code.substring(0, currency.code.length >= 2 ? 2 : currency.code.length))),
                title: Text('${currency.code} · ${currency.name}'),
                subtitle: Text(
                    '${tr.text('symbol')}: ${currency.symbol} · ${tr.text('accounting_decimals')}: ${currency.decimalPlaces} · ${tr.text('cash_decimals')}: ${currency.cashDecimalPlaces}${currency.roundingStep > 0 ? ' · ${tr.text('cash_rounding')}: ${currency.roundingStep.toStringAsFixed(0)} (${tr.text('cash_rounding_${currency.roundingMethod}')})' : ''}'),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    if (currency.isBase)
                      Chip(label: Text(tr.text('base_currency'))),
                    IconButton(
                      tooltip: tr.text('edit'),
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: store.hasPermission(AppPermission.settingsManage)
                          ? () => _editCurrency(context, profile,
                              currency: currency)
                          : null,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      _CurrentDeviceCashDrawerSettingsCard(store: store),
      _SectionCard(
        icon: Icons.trending_up_outlined,
        title: tr.text('exchange_rates'),
        subtitle: tr.text('exchange_rates_desc'),
        trailing: FilledButton.icon(
          onPressed: store.hasPermission(AppPermission.settingsManage)
              ? () => _editExchangeRate(context, profile)
              : null,
          icon: const Icon(Icons.add_outlined),
          label: Text(tr.text('add_exchange_rate')),
        ),
        child: Column(
          children: [
            if (profile.exchangeRates.isEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline),
                title: Text(tr.text('no_exchange_rates')),
              ),
            for (final rate in (profile.exchangeRates.toList()
              ..sort((a, b) => b.effectiveAt.compareTo(a.effectiveAt))).take(12))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(rate.isActive
                    ? Icons.check_circle_outline
                    : Icons.pause_circle_outline),
                title: Text(
                    '1 ${rate.fromCurrency} = ${rate.rate.toStringAsFixed(rate.rate >= 100 ? 0 : 6)} ${rate.toCurrency}'),
                subtitle: Text(
                    '${DateFormat.yMd().add_Hm().format(rate.effectiveAt)} · ${rate.source}${rate.note.isNotEmpty ? ' · ${rate.note}' : ''}'),
                trailing: IconButton(
                  tooltip: tr.text('edit'),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: store.hasPermission(AppPermission.settingsManage)
                      ? () => _editExchangeRate(context, profile, rate: rate)
                      : null,
                ),
              ),
          ],
        ),
      ),
    ];
  }


  List<Widget> _shortcutCards(BuildContext context) => [
        const _KeyboardShortcutsSettingsCard(),
      ];

  List<Widget> _syncCards(BuildContext context) => [
        _UnifiedSyncSettingsCard(
            store: store, onSyncSettingsChanged: onSyncSettingsChanged),
        SyncMonitoringSection(store: store),
      ];

  List<Widget> _backupCards(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final isClient = store.appIdentity.isClient;
    return [
      Card(
        child: Padding(
          padding: VentioResponsive.pageInsets(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.backup_outlined),
                  title: Text(tr.text('backup_restore')),
                  subtitle: Text(tr.text('backup_preview_desc'))),
              Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Chip(
                          avatar: const Icon(Icons.storage_outlined, size: 18),
                          label: Text(tr.text('local_db_sqlite'))))),
              _BackupSummaryCard(summary: store.currentBackupSummary),
              if (!isClient) ...[
                const SizedBox(height: 16),
                _AutoLocalBackupSettingsCard(store: store),
                const SizedBox(height: 16),
                _GoogleDriveBackupSettingsCard(store: store),
              ],
              const SizedBox(height: 16),
              Text(tr.text('actions'),
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = constraints.maxWidth < 560
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 12) / 2;
                  final hasStoreIdentity =
                      store.appIdentity.hostDeviceId.trim().isNotEmpty;
                  final canRecoverStoreData =
                      store.hasPermission(AppPermission.syncManage);
                  final recoverLabelKey = hasStoreIdentity
                      ? 'recover_store_data'
                      : 'recover_store_identity';
                  final recoverIcon = hasStoreIdentity
                      ? (canRecoverStoreData
                          ? Icons.download_outlined
                          : Icons.lock_outline)
                      : Icons.key_outlined;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      if (!isClient) ...[
                        SizedBox(
                          width: itemWidth,
                          child: OutlinedButton.icon(
                            onPressed: (hasStoreIdentity && !canRecoverStoreData) ||
                                    !store.hasPermission(AppPermission.backupManage)
                                ? null
                                : () => _recoverExistingStore(context),
                            icon: Icon(recoverIcon),
                            label: Text(tr.text(recoverLabelKey)),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: OutlinedButton.icon(
                            onPressed: store.hasAnyPermission(<String>{
                              AppPermission.backupRestore,
                              AppPermission.backupManage,
                            })
                                ? () => _downloadRecoveryFile(context)
                                : null,
                            icon: const Icon(Icons.security_outlined),
                            label: Text(tr.text('download_recovery_file')),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: FilledButton.icon(
                            onPressed: store.hasAnyPermission(<String>{
                              AppPermission.backupExport,
                              AppPermission.backupManage,
                            })
                                ? () => _downloadBackupFile(context)
                                : null,
                            icon: const Icon(Icons.download_outlined),
                            label: Text(tr.text('export')),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: OutlinedButton.icon(
                            onPressed: store.hasAnyPermission(<String>{
                              AppPermission.backupRestore,
                              AppPermission.backupManage,
                            })
                                ? () => _importBackupFile(context)
                                : null,
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
            Icon(Icons.warning_amber_outlined,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr.text('data_management'),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(isHost
                      ? tr.text('data_management_desc')
                      : tr.text('client_maintenance_desc')),
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
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: store.hasPermission(AppPermission.databaseManage)
                  ? () => _resetBusinessData(context)
                  : null,
              icon: const Icon(Icons.delete_forever_outlined),
              label: Text(tr.text('reset_all_data')),
            ),
          ),
        if (isClient) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: store.hasPermission(AppPermission.syncManage)
                  ? () => _clearLocalData(context)
                  : null,
              icon: const Icon(Icons.cleaning_services_outlined),
              label: Text(tr.text('clear_local_data')),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: store.hasPermission(AppPermission.syncManage)
                  ? () => _rebuildFromHost(context)
                  : null,
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
    if (!store.canManageUsers) {
      return [
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(tr.text('users_permissions')),
            subtitle: const Text('You do not have access to user or role management.'),
          ),
        ),
      ];
    }
    return [
      Card(
        child: ListTile(
          leading: const Icon(Icons.people),
          title: Text(tr.text('users_permissions')),
          subtitle: Text(tr.format('signed_in_as_role', {
            'user': store.activeUser?.fullName ?? tr.text('unknown_user'),
            'role': store.currentRole
          })),
          trailing: FilledButton.icon(
            onPressed: store.canManageUsers
                ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => PageTimingScope(
                              key: const ValueKey('UsersPermissionsPage'),
                              pageKey: 'UsersPermissionsPage',
                              pageLabel: 'Users permissions',
                              child: UsersPermissionsPage(store: store),
                            )))
                : null,
            icon: const Icon(Icons.manage_accounts_outlined),
            label: Text(tr.text('manage')),
          ),
        ),
      ),
    ];
  }

  String _priceDisplayModeLabel(AppLocalizations tr, StoreProfile profile) {
    switch (profile.priceDisplayMode) {
      case 'multiple':
        final codes = profile.priceDisplayCurrencies.isEmpty
            ? profile.currencies
                .where((item) => item.isActive)
                .map((item) => item.code)
                .join(', ')
            : profile.priceDisplayCurrencies.join(', ');
        return '${tr.text('price_display_multiple')} · $codes';
      case 'selectable':
        return tr.text('price_display_selectable');
      case 'default':
      default:
        return tr.text('price_display_default');
    }
  }

  Future<void> _editFinancialSettings(
      BuildContext context, StoreProfile profile) async {
    final tr = AppLocalizations.of(context);
    final activeCodes = profile.currencies
        .where((item) => item.isActive)
        .map((item) => item.code)
        .toList();
    String baseCurrency = activeCodes.contains(profile.baseCurrency)
        ? profile.baseCurrency
        : activeCodes.first;
    String displayMode = {'default', 'selectable', 'multiple'}.contains(profile.priceDisplayMode)
        ? profile.priceDisplayMode
        : 'default';
    final displayCurrencies = profile.priceDisplayCurrencies
        .where((code) => activeCodes.contains(code))
        .toSet()
        .toList();
    if (displayCurrencies.isEmpty) {
      displayCurrencies.add(activeCodes.contains(profile.defaultSaleInvoiceCurrency)
          ? profile.defaultSaleInvoiceCurrency
          : baseCurrency);
    }
    String defaultCurrency = activeCodes.contains(profile.defaultProductCurrency)
        ? profile.defaultProductCurrency
        : baseCurrency;
    String defaultSaleInvoiceCurrency =
        activeCodes.contains(profile.defaultSaleInvoiceCurrency)
            ? profile.defaultSaleInvoiceCurrency
            : defaultCurrency;
    String defaultSalePaymentCurrency =
        activeCodes.contains(profile.defaultSalePaymentCurrency)
            ? profile.defaultSalePaymentCurrency
            : defaultCurrency;
    int priceStorageDecimals = profile.priceStorageDecimals;

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
                    DropdownButtonFormField<String>(
                      initialValue: baseCurrency,
                      decoration:
                          InputDecoration(labelText: tr.text('base_currency')),
                      items: [
                        for (final code in activeCodes)
                          DropdownMenuItem(value: code, child: Text(code)),
                      ],
                      onChanged: (value) =>
                          setState(() => baseCurrency = value ?? baseCurrency),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: priceStorageDecimals,
                      decoration: InputDecoration(
                          labelText: tr.text('price_storage_decimals')),
                      items: const [
                        DropdownMenuItem(value: 2, child: Text('2')),
                        DropdownMenuItem(value: 3, child: Text('3')),
                        DropdownMenuItem(value: 4, child: Text('4')),
                        DropdownMenuItem(value: 5, child: Text('5')),
                        DropdownMenuItem(value: 6, child: Text('6')),
                      ],
                      onChanged: (value) => setState(
                          () => priceStorageDecimals = value ?? 4),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: displayMode,
                      decoration: InputDecoration(
                          labelText: tr.text('price_display_mode')),
                      items: [
                        DropdownMenuItem(
                            value: 'default',
                            child: Text(tr.text('price_display_default'))),
                        DropdownMenuItem(
                            value: 'selectable',
                            child: Text(tr.text('price_display_selectable'))),
                        DropdownMenuItem(
                            value: 'multiple',
                            child: Text(tr.text('price_display_multiple'))),
                      ],
                      onChanged: (value) =>
                          setState(() => displayMode = value ?? 'default'),
                    ),
                    if (displayMode == 'multiple') ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(tr.text('displayed_currencies')),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final code in activeCodes)
                            FilterChip(
                              label: Text(code),
                              selected: displayCurrencies.contains(code),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    if (!displayCurrencies.contains(code)) {
                                      displayCurrencies.add(code);
                                    }
                                  } else if (displayCurrencies.length > 1) {
                                    displayCurrencies.remove(code);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          tr.text('displayed_currencies_hint'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: defaultCurrency,
                      decoration: InputDecoration(
                          labelText: tr.text('default_product_currency')),
                      items: [
                        for (final code in activeCodes)
                          DropdownMenuItem(value: code, child: Text(code)),
                      ],
                      onChanged: (value) =>
                          setState(() => defaultCurrency = value ?? baseCurrency),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: defaultSaleInvoiceCurrency,
                      decoration: InputDecoration(
                          labelText: tr.text('default_sale_invoice_currency')),
                      items: [
                        for (final code in activeCodes)
                          DropdownMenuItem(value: code, child: Text(code)),
                      ],
                      onChanged: (value) => setState(() =>
                          defaultSaleInvoiceCurrency =
                              value ?? defaultCurrency),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: defaultSalePaymentCurrency,
                      decoration: InputDecoration(
                          labelText: tr.text('default_sale_payment_currency')),
                      items: [
                        for (final code in activeCodes)
                          DropdownMenuItem(value: code, child: Text(code)),
                      ],
                      onChanged: (value) => setState(() =>
                          defaultSalePaymentCurrency =
                              value ?? defaultCurrency),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(tr.text('cancel'))),
              FilledButton(
                onPressed: () {
                  final nextCurrencies = profile.currencies
                      .map((item) =>
                          item.copyWith(isBase: item.code == baseCurrency))
                      .toList(growable: false);
                  final nextDisplayCurrencies = displayMode == 'multiple'
                      ? displayCurrencies
                          .where((code) => activeCodes.contains(code))
                          .toSet()
                          .toList(growable: false)
                      : <String>[defaultSaleInvoiceCurrency];
                  Navigator.pop(
                    dialogContext,
                    profile.copyWith(
                      currency: baseCurrency,
                      baseCurrency: baseCurrency,
                      priceStorageDecimals: priceStorageDecimals,
                      currencies: nextCurrencies,
                      priceDisplayMode: displayMode,
                      priceDisplayCurrencies: nextDisplayCurrencies.isEmpty
                          ? <String>[defaultSaleInvoiceCurrency]
                          : nextDisplayCurrencies,
                      defaultProductCurrency: defaultCurrency,
                      defaultSaleInvoiceCurrency: defaultSaleInvoiceCurrency,
                      defaultSalePaymentCurrency: defaultSalePaymentCurrency,
                    ),
                  );
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
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr.text('financial_settings_updated'))));
      }
    }
  }

  Future<void> _editCurrency(
    BuildContext context,
    StoreProfile profile, {
    FinancialCurrency? currency,
  }) async {
    final tr = AppLocalizations.of(context);
    final isEditing = currency != null;
    final codeController =
        TextEditingController(text: currency?.code ?? '');
    final nameController =
        TextEditingController(text: currency?.name ?? '');
    final symbolController =
        TextEditingController(text: currency?.symbol ?? '');
    final decimalsController = TextEditingController(
        text: (currency?.decimalPlaces ?? 2).toString());
    final cashDecimalsController = TextEditingController(
        text: (currency?.cashDecimalPlaces ?? currency?.decimalPlaces ?? 2)
            .toString());
    final roundingController = TextEditingController(
        text: (currency?.roundingStep ?? 0) <= 0
            ? ''
            : (currency?.roundingStep ?? 0).toStringAsFixed(0));
    bool cashRoundingEnabled = (currency?.roundingStep ?? 0) > 0;
    String roundingMethod = currency?.roundingMethod ?? 'nearest';
    bool isBase = currency?.isBase ?? false;
    bool isActive = currency?.isActive ?? true;

    final result = await showDialog<FinancialCurrency>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isEditing ? tr.text('edit_currency') : tr.text('add_currency')),
          content: ResponsiveDialogBox(
            maxWidth: VentioResponsive.modalMaxWidth(context, 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: codeController,
                    enabled: !isEditing,
                    decoration:
                        InputDecoration(labelText: tr.text('currency_code')),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                      LengthLimitingTextInputFormatter(3),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameController,
                    decoration:
                        InputDecoration(labelText: tr.text('currency_name')),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: symbolController,
                    decoration:
                        InputDecoration(labelText: tr.text('symbol')),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: decimalsController,
                    decoration: InputDecoration(
                        labelText: tr.text('accounting_decimals')),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: cashDecimalsController,
                    decoration:
                        InputDecoration(labelText: tr.text('cash_decimals')),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr.text('enable_cash_rounding')),
                    subtitle: Text(tr.text('enable_cash_rounding_hint')),
                    value: cashRoundingEnabled,
                    onChanged: (value) =>
                        setState(() => cashRoundingEnabled = value),
                  ),
                  if (cashRoundingEnabled) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: roundingController,
                      decoration: InputDecoration(
                        labelText: tr.text('cash_rounding_increment'),
                        helperText: tr.text('cash_rounding_increment_hint'),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: roundingMethod,
                      decoration: InputDecoration(
                        labelText: tr.text('cash_rounding_method'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'nearest',
                          child: Text(tr.text('cash_rounding_nearest')),
                        ),
                        DropdownMenuItem(
                          value: 'up',
                          child: Text(tr.text('cash_rounding_up')),
                        ),
                        DropdownMenuItem(
                          value: 'down',
                          child: Text(tr.text('cash_rounding_down')),
                        ),
                      ],
                      onChanged: (value) => setState(
                          () => roundingMethod = value ?? 'nearest'),
                    ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr.text('base_currency')),
                    value: isBase,
                    onChanged: (value) => setState(() => isBase = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr.text('active')),
                    value: isActive,
                    onChanged: (value) => setState(() => isActive = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: () {
                final code = codeController.text.trim().toUpperCase();
                if (code.length != 3) return;
                final decimals =
                    int.tryParse(decimalsController.text.trim()) ?? 2;
                final cashDecimals =
                    int.tryParse(cashDecimalsController.text.trim()) ??
                        decimals;
                final rounding = cashRoundingEnabled
                    ? (double.tryParse(roundingController.text.trim()) ?? 0.0)
                    : 0.0;
                Navigator.pop(
                  dialogContext,
                  FinancialCurrency(
                    code: code,
                    name: nameController.text.trim().isEmpty
                        ? code
                        : nameController.text.trim(),
                    symbol: symbolController.text.trim().isEmpty
                        ? code
                        : symbolController.text.trim(),
                    decimalPlaces: decimals.clamp(0, 6).toInt(),
                    cashDecimalPlaces: cashDecimals.clamp(0, 6).toInt(),
                    roundingStep: rounding < 0 ? 0.0 : rounding,
                    roundingMethod: roundingMethod,
                    isBase: isBase,
                    isActive: isActive,
                  ),
                );
              },
              child: Text(tr.text('save')),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    final code = result.code;
    final existing = profile.currencies.where((item) => item.code != code);
    final nextCurrencies = [
      ...existing,
      result,
    ];
    final nextBase = result.isBase ? result.code : profile.baseCurrency;
    final normalizedCurrencies = nextCurrencies
        .map((item) => item.copyWith(isBase: item.code == nextBase))
        .toList(growable: false);
    await store.updateStoreProfile(profile.copyWith(
      baseCurrency: nextBase,
      currency: nextBase,
      currencies: normalizedCurrencies,
      defaultProductCurrency:
          profile.defaultProductCurrency == code || result.isActive
              ? profile.defaultProductCurrency
              : nextBase,
    ));
  }

  Future<void> _editExchangeRate(
    BuildContext context,
    StoreProfile profile, {
    CurrencyExchangeRate? rate,
  }) async {
    final tr = AppLocalizations.of(context);
    final codes = profile.currencies
        .where((item) => item.isActive)
        .map((item) => item.code)
        .toList();
    String fromCurrency = rate?.fromCurrency ??
        (codes.contains('USD') ? 'USD' : codes.first);
    String toCurrency = rate?.toCurrency ??
        (codes.contains('LBP') ? 'LBP' : codes.last);
    final rateController =
        TextEditingController(text: rate?.rate.toString() ?? '');
    final noteController = TextEditingController(text: rate?.note ?? '');
    bool isActive = rate?.isActive ?? true;

    final result = await showDialog<CurrencyExchangeRate>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(rate == null
              ? tr.text('add_exchange_rate')
              : tr.text('edit_exchange_rate')),
          content: ResponsiveDialogBox(
            maxWidth: VentioResponsive.modalMaxWidth(context, 500),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: fromCurrency,
                    decoration:
                        InputDecoration(labelText: tr.text('from_currency')),
                    items: [
                      for (final code in codes)
                        DropdownMenuItem(value: code, child: Text(code)),
                    ],
                    onChanged: (value) =>
                        setState(() => fromCurrency = value ?? fromCurrency),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: toCurrency,
                    decoration:
                        InputDecoration(labelText: tr.text('to_currency')),
                    items: [
                      for (final code in codes)
                        DropdownMenuItem(value: code, child: Text(code)),
                    ],
                    onChanged: (value) =>
                        setState(() => toCurrency = value ?? toCurrency),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: rateController,
                    decoration:
                        InputDecoration(labelText: tr.text('exchange_rate')),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: noteController,
                    decoration: InputDecoration(labelText: tr.text('note')),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr.text('active')),
                    value: isActive,
                    onChanged: (value) => setState(() => isActive = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: () {
                final parsedRate =
                    double.tryParse(rateController.text.trim()) ?? 0;
                if (parsedRate <= 0 || fromCurrency == toCurrency) return;
                Navigator.pop(
                  dialogContext,
                  CurrencyExchangeRate(
                    id: rate?.id ??
                        'fx_${DateTime.now().microsecondsSinceEpoch}',
                    fromCurrency: fromCurrency,
                    toCurrency: toCurrency,
                    rate: parsedRate,
                    effectiveAt: rate?.effectiveAt ?? DateTime.now(),
                    source: 'manual',
                    isActive: isActive,
                    note: noteController.text.trim(),
                  ),
                );
              },
              child: Text(tr.text('save')),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    final nextRates = [
      ...profile.exchangeRates.where((item) => item.id != result.id),
      result,
    ];
    final legacyUsdLbp = result.fromCurrency == 'USD' && result.toCurrency == 'LBP'
        ? result.rate
        : profile.usdToLbpRate;
    await store.updateStoreProfile(profile.copyWith(
      exchangeRates: nextRates,
      usdToLbpRate: legacyUsdLbp,
    ));
  }

  Future<void> _editDocumentNumbering(
      BuildContext context, StoreProfile profile) async {
    final docs = profile.documentNumbering;
    final invoiceController = TextEditingController(text: docs.invoicePrefix);
    final quoteController = TextEditingController(text: docs.quotePrefix);
    final purchaseController = TextEditingController(text: docs.purchasePrefix);
    final deliveryController = TextEditingController(text: docs.deliveryNotePrefix);
    final returnController = TextEditingController(text: docs.returnPrefix);
    final tr = AppLocalizations.of(context);

    final result = await showDialog<DocumentNumberingSettings>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(tr.text('document_settings')),
          content: ResponsiveDialogBox(
            maxWidth: VentioResponsive.modalMaxWidth(context, 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: invoiceController,
                    decoration: InputDecoration(labelText: tr.text('invoice_prefix')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: quoteController,
                    decoration: InputDecoration(labelText: tr.text('quote_prefix')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: purchaseController,
                    decoration: InputDecoration(labelText: tr.text('purchase_prefix')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: deliveryController,
                    decoration: InputDecoration(labelText: tr.text('delivery_note_prefix')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: returnController,
                    decoration: InputDecoration(labelText: tr.text('return_prefix')),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  DocumentNumberingSettings(
                    invoicePrefix: invoiceController.text.trim().isEmpty
                        ? 'INV-'
                        : invoiceController.text.trim(),
                    quotePrefix: quoteController.text.trim().isEmpty
                        ? 'QUO-'
                        : quoteController.text.trim(),
                    purchasePrefix: purchaseController.text.trim().isEmpty
                        ? 'PO-'
                        : purchaseController.text.trim(),
                    deliveryNotePrefix: deliveryController.text.trim().isEmpty
                        ? 'DN-'
                        : deliveryController.text.trim(),
                    returnPrefix: returnController.text.trim().isEmpty
                        ? 'RET-'
                        : returnController.text.trim(),
                  ),
                );
              },
              child: Text(tr.text('save')),
            ),
          ],
        );
      },
    );

    if (result != null) {
      if (!context.mounted) return;
      await _saveOrganizationProfile(
          context, profile.copyWith(documentNumbering: result));
    }
  }

  Future<void> _editBranch(BuildContext context, StoreProfile profile,
      OrganizationBranch? branch) async {
    final nameController = TextEditingController(text: branch?.name ?? '');
    final codeController = TextEditingController(text: branch?.code ?? '');
    final addressController = TextEditingController(text: branch?.address ?? '');
    final phoneController = TextEditingController(text: branch?.phone ?? '');
    var isActive = branch?.isActive ?? true;
    final tr = AppLocalizations.of(context);

    final result = await showDialog<OrganizationBranch>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text(branch == null
                ? tr.text('add_branch')
                : tr.text('edit_branch')),
            content: ResponsiveDialogBox(
              maxWidth: VentioResponsive.modalMaxWidth(context, 560),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(labelText: tr.text('branch_name')),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: codeController,
                      decoration: InputDecoration(labelText: tr.text('branch_code')),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      decoration: InputDecoration(labelText: tr.text('phone')),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(labelText: tr.text('address')),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: isActive,
                      onChanged: (value) => setState(() => isActive = value),
                      title: Text(tr.text('active')),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(tr.text('cancel'))),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(
                    dialogContext,
                    OrganizationBranch(
                      id: branch?.id ??
                          'branch_${DateTime.now().microsecondsSinceEpoch}',
                      name: name,
                      code: codeController.text.trim(),
                      address: addressController.text.trim(),
                      phone: phoneController.text.trim(),
                      isActive: isActive,
                    ),
                  );
                },
                child: Text(tr.text('save')),
              ),
            ],
          );
        });
      },
    );

    if (result == null) return;
    if (!context.mounted) return;
    final nextBranches = [
      ...profile.branches.where((item) => item.id != result.id),
      result,
    ];
    await _saveOrganizationProfile(
        context, profile.copyWith(branches: nextBranches));
  }

  Future<void> _editOrganizationGeneral(
      BuildContext context, StoreProfile profile) async {
    final nameController = TextEditingController(text: profile.name);
    final tradeNameController = TextEditingController(text: profile.tradeName);
    final phoneController = TextEditingController(text: profile.phone);
    final emailController = TextEditingController(text: profile.email);
    final websiteController = TextEditingController(text: profile.website);
    final tr = AppLocalizations.of(context);

    final result = await showDialog<StoreProfile>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(tr.text('organization_general')),
          content: ResponsiveDialogBox(
            maxWidth: VentioResponsive.modalMaxWidth(context, 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: nameController,
                      decoration:
                          InputDecoration(labelText: tr.text('store_name'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: tradeNameController,
                      decoration:
                          InputDecoration(labelText: tr.text('trade_name'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: phoneController,
                      decoration: InputDecoration(labelText: tr.text('phone'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(labelText: tr.text('email'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: websiteController,
                      keyboardType: TextInputType.url,
                      decoration:
                          InputDecoration(labelText: tr.text('website'))),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  profile.copyWith(
                    name: nameController.text.trim().isEmpty
                        ? tr.text('my_store')
                        : nameController.text.trim(),
                    tradeName: tradeNameController.text.trim(),
                    phone: phoneController.text.trim(),
                    email: emailController.text.trim(),
                    website: websiteController.text.trim(),
                  ),
                );
              },
              child: Text(tr.text('save')),
            ),
          ],
        );
      },
    );

    if (result != null) {
      if (!context.mounted) return;
      await _saveOrganizationProfile(context, result);
    }
  }

  Future<void> _editOrganizationLegal(
      BuildContext context, StoreProfile profile) async {
    final legalNameController = TextEditingController(text: profile.legalName);
    final vatController = TextEditingController(text: profile.vatNumber);
    final taxController =
        TextEditingController(text: profile.taxRegistrationNumber);
    final registerController =
        TextEditingController(text: profile.commercialRegisterNumber);
    final countryController = TextEditingController(text: profile.country);
    final governorateController =
        TextEditingController(text: profile.governorate);
    final cityController = TextEditingController(text: profile.city);
    final addressController = TextEditingController(text: profile.address);
    final tr = AppLocalizations.of(context);

    final result = await showDialog<StoreProfile>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(tr.text('organization_legal')),
          content: ResponsiveDialogBox(
            maxWidth: VentioResponsive.modalMaxWidth(context, 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: legalNameController,
                      decoration:
                          InputDecoration(labelText: tr.text('legal_name'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: vatController,
                      decoration:
                          InputDecoration(labelText: tr.text('vat_number'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: taxController,
                      decoration: InputDecoration(
                          labelText: tr.text('tax_registration_number'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: registerController,
                      decoration: InputDecoration(
                          labelText: tr.text('commercial_register_number'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: countryController,
                      decoration: InputDecoration(labelText: tr.text('country'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: governorateController,
                      decoration:
                          InputDecoration(labelText: tr.text('governorate'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: cityController,
                      decoration: InputDecoration(labelText: tr.text('city'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: addressController,
                      minLines: 2,
                      maxLines: 4,
                      decoration:
                          InputDecoration(labelText: tr.text('address'))),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  profile.copyWith(
                    legalName: legalNameController.text.trim(),
                    vatNumber: vatController.text.trim(),
                    taxRegistrationNumber: taxController.text.trim(),
                    commercialRegisterNumber: registerController.text.trim(),
                    country: countryController.text.trim(),
                    governorate: governorateController.text.trim(),
                    city: cityController.text.trim(),
                    address: addressController.text.trim(),
                  ),
                );
              },
              child: Text(tr.text('save')),
            ),
          ],
        );
      },
    );

    if (result != null) {
      if (!context.mounted) return;
      await _saveOrganizationProfile(context, result);
    }
  }

  Future<void> _editOrganizationBranding(
      BuildContext context, StoreProfile profile) async {
    final logoController = TextEditingController(text: profile.logoPath);
    final footerController = TextEditingController(text: profile.footerNote);
    final tr = AppLocalizations.of(context);

    final result = await showDialog<StoreProfile>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(tr.text('organization_branding')),
          content: ResponsiveDialogBox(
            maxWidth: VentioResponsive.modalMaxWidth(context, 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: logoController,
                      decoration:
                          InputDecoration(labelText: tr.text('logo_path'))),
                  const SizedBox(height: 12),
                  TextField(
                    controller: footerController,
                    minLines: 2,
                    maxLines: 4,
                    decoration:
                        InputDecoration(labelText: tr.text('invoice_footer')),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  profile.copyWith(
                    logoPath: logoController.text.trim(),
                    footerNote: footerController.text.trim().isEmpty
                        ? tr.text('default_invoice_footer')
                        : footerController.text.trim(),
                  ),
                );
              },
              child: Text(tr.text('save')),
            ),
          ],
        );
      },
    );

    if (result != null) {
      if (!context.mounted) return;
      await _saveOrganizationProfile(context, result);
    }
  }

  Future<void> _saveOrganizationProfile(
      BuildContext context, StoreProfile profile) async {
    final tr = AppLocalizations.of(context);
    await store.updateStoreProfile(profile);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('store_profile_updated'))));
    }
  }


  Future<void> _downloadBackupFile(BuildContext context) async {
    await SettingsBackupActions.downloadBackupFile(context, store);
  }

  Future<void> _importBackupFile(BuildContext context) async {
    await SettingsBackupActions.importBackupFile(context, store);
  }

  Future<void> _downloadRecoveryFile(BuildContext context) async {
    await SettingsBackupActions.downloadRecoveryFile(context, store);
  }

  Future<void> _recoverExistingStore(BuildContext context) async {
    await SettingsBackupActions.recoverExistingStore(context, store);
  }

  Future<void> _clearLocalData(BuildContext context) async {
    await SettingsBackupActions.clearLocalData(context, store);
  }

  Future<void> _rebuildFromHost(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context).text('rebuild_from_host')),
        content:
            Text(AppLocalizations.of(context).text('rebuild_from_host_desc')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(AppLocalizations.of(context).text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(AppLocalizations.of(context).text('rebuild'))),
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
                UnifiedSnapshotProgressView(
                  value: value.value,
                  label: value.label,
                ),
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
      progress.value = _OperationProgress(
          0.20, tr.text('resetting_local_client_state_percent'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (identity.syncMode == SyncMode.cloudConnected ||
          identity.syncMode == SyncMode.marketplaceEnabled) {
        progress.value = _OperationProgress(
            0.40, tr.text('contacting_cloud_host_snapshot_percent'));
        final result = await UnifiedSyncEngine(
          CloudSyncTransportAdapter(
            service: CloudSyncService(store),
            settings: CloudSyncSettings.load(),
          ),
        ).rebuildFromHostSnapshot(
          onProgress: (value, label) => progress.value =
              _OperationProgress(value, '$label ${(value * 100).round()}%'),
        );
        progress.value = _OperationProgress(
            result.ok ? 1.0 : 0.90,
            result.ok
                ? tr.text('cloud_rebuild_completed_percent')
                : tr.text('cloud_rebuild_failed_verifying_percent'));
        message = localizeRuntimeMessage(result.message, tr);
        success = result.ok;
      } else {
        final settings = LanSyncSettings.load();
        progress.value =
            _OperationProgress(0.40, tr.text('contacting_lan_host_percent'));
        final result = await UnifiedSyncEngine(
          LanSyncTransportAdapter(
            service: LanSyncService(store),
            settings: settings,
          ),
        ).rebuildFromHostSnapshot(
          onProgress: (value, label) => progress.value =
              _OperationProgress(value, '$label ${(value * 100).round()}%'),
        );
        progress.value = _OperationProgress(
            result.ok ? 1.0 : 0.90,
            result.ok
                ? tr.text('lan_rebuild_completed_percent')
                : tr.text('lan_rebuild_failed_verifying_percent'));
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
          content: Text(success
              ? AppLocalizations.of(context)
                  .text('rebuild_completed_successfully')
              : message),
        ),
      );
    }
  }

  Future<void> _resetBusinessData(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    const confirmationWord = 'CONFIRM';
    String hostSafety = 'no_connected_devices';
    final token =
        'RST-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';

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
                onChanged: (value) =>
                    setState(() => hostSafety = value ?? hostSafety),
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
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(AppLocalizations.of(context).text('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(tr.text('continue'))),
          ],
        ),
      ),
    );
    if (step1 != true) return;

    try {
      final backup =
          'RESET_PROTECTION_TOKEN:$token\n${await store.exportBackupJson()}';
      await downloadTextFile(
          filename:
              'reset_protection_backup_${DateTime.now().millisecondsSinceEpoch}.json',
          content: backup);
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
                SelectableText(token,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                    controller: tokenController,
                    decoration: InputDecoration(
                        labelText: tr.text('reset_token'),
                        border: const OutlineInputBorder()),
                    onChanged: (_) => setState(() => canContinue =
                        tokenController.text.trim() == token &&
                            confirmController.text.trim() == confirmationWord &&
                            passwordController.text.isNotEmpty)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.attach_file_outlined),
                  label: Text(tr.text('attach_reset_protection_backup')),
                  onPressed: () async {
                    final picked = await FilePicker.platform
                        .pickFiles(type: FileType.any, withData: true);
                    final bytes = picked?.files.single.bytes;
                    if (bytes == null) return;
                    final content = utf8.decode(bytes, allowMalformed: true);
                    if (content.startsWith('RESET_PROTECTION_TOKEN:$token')) {
                      tokenController.text = token;
                      setState(() => canContinue =
                          tokenController.text.trim() == token &&
                              confirmController.text.trim() ==
                                  confirmationWord &&
                              passwordController.text.isNotEmpty);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: tr.text('admin_password'),
                        border: const OutlineInputBorder()),
                    onChanged: (_) => setState(() => canContinue =
                        tokenController.text.trim() == token &&
                            confirmController.text.trim() == confirmationWord &&
                            passwordController.text.isNotEmpty)),
                const SizedBox(height: 12),
                TextField(
                    controller: confirmController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                        labelText: tr.text('type_confirm'),
                        border: const OutlineInputBorder()),
                    onChanged: (_) => setState(() => canContinue =
                        tokenController.text.trim() == token &&
                            confirmController.text.trim() == confirmationWord &&
                            passwordController.text.isNotEmpty)),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(AppLocalizations.of(context).text('cancel'))),
            FilledButton(
                onPressed: canContinue
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                child: Text(tr.text('verify'))),
          ],
        ),
      ),
    );
    if (verified != true) return;

    final passwordOk = await store.verifyAdminPassword(passwordController.text);
    if (!passwordOk) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr.text('admin_password_incorrect'))));
      }
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
              TextField(
                  controller: finalController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                      labelText: tr.text('type_confirm_again'),
                      border: const OutlineInputBorder()),
                  onChanged: (value) => setState(
                      () => finalOk = value.trim() == confirmationWord)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(AppLocalizations.of(context).text('cancel'))),
            FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error),
                onPressed:
                    finalOk ? () => Navigator.pop(dialogContext, true) : null,
                child: Text(tr.text('erase_everything'))),
          ],
        ),
      ),
    );
    if (finalConfirm != true) return;

    await store.factoryResetLocalDevice();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('host_reset_completed'))));
    }
  }
}

class _ScannerFeedbackSettingsCard extends StatefulWidget {
  const _ScannerFeedbackSettingsCard();

  @override
  State<_ScannerFeedbackSettingsCard> createState() =>
      _ScannerFeedbackSettingsCardState();
}

class _ScannerFeedbackSettingsCardState
    extends State<_ScannerFeedbackSettingsCard> {
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
              onChanged: (value) =>
                  _save(_settings.copyWith(soundEnabled: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr.text('scanner_feedback_vibration')),
              subtitle: Text(tr.text('scanner_feedback_vibration_desc')),
              value: _settings.vibrationEnabled,
              onChanged: (value) =>
                  _save(_settings.copyWith(vibrationEnabled: value)),
            ),
            const SizedBox(height: 8),
            Text(tr.text('scanner_feedback_volume')),
            Slider(
              value: _settings.volume,
              onChanged: _settings.soundEnabled
                  ? (value) => _save(_settings.copyWith(volume: value))
                  : null,
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

class _AutoLocalBackupSettingsCard extends StatefulWidget {
  const _AutoLocalBackupSettingsCard({required this.store});

  final AppStore store;

  @override
  State<_AutoLocalBackupSettingsCard> createState() =>
      _AutoLocalBackupSettingsCardState();
}

class _AutoLocalBackupSettingsCardState
    extends State<_AutoLocalBackupSettingsCard> {
  LocalAutoBackupSettings? _settings;
  bool _saving = false;
  bool _hasChanges = false;
  bool _expanded = false;
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _dailyController = TextEditingController();
  final TextEditingController _weeklyController = TextEditingController();
  final TextEditingController _monthlyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pathController.addListener(_markChanged);
    _dailyController.addListener(_markChanged);
    _weeklyController.addListener(_markChanged);
    _monthlyController.addListener(_markChanged);
    _load();
  }

  @override
  void dispose() {
    _pathController.dispose();
    _dailyController.dispose();
    _weeklyController.dispose();
    _monthlyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await LocalAutoBackupService.loadSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _pathController.text = settings.locationPath;
      _dailyController.text = settings.dailyCount.toString();
      _weeklyController.text = settings.weeklyCount.toString();
      _monthlyController.text = settings.monthlyCount.toString();
      _hasChanges = false;
    });
  }

  void _markChanged() {
    final current = _settings;
    if (current == null || _saving) return;
    final changed =
        _settingsSignature(_draftSettings()) != _settingsSignature(current);
    if (changed != _hasChanges && mounted) {
      setState(() => _hasChanges = changed);
    }
  }

  String _settingsSignature(LocalAutoBackupSettings settings) =>
      '${settings.enabled}|${settings.locationPath.trim()}|${settings.dailyCount}|${settings.weeklyCount}|${settings.monthlyCount}';

  LocalAutoBackupSettings _draftSettings({bool? enabled}) {
    final current = _settings!;
    return current.copyWith(
      enabled: enabled ?? current.enabled,
      locationPath: _pathController.text.trim(),
      dailyCount:
          _count(_dailyController, LocalAutoBackupService.defaultDailyCount),
      weeklyCount:
          _count(_weeklyController, LocalAutoBackupService.defaultWeeklyCount),
      monthlyCount: _count(
          _monthlyController, LocalAutoBackupService.defaultMonthlyCount),
    );
  }

  int _count(TextEditingController controller, int fallback) {
    final value = int.tryParse(controller.text.trim());
    if (value == null || value <= 0) return fallback;
    return value;
  }

  Future<void> _save({bool? enabled}) async {
    final current = _settings;
    if (current == null) return;
    final tr = AppLocalizations.of(context);
    setState(() => _saving = true);
    final next = _draftSettings(enabled: enabled);
    try {
      await LocalAutoBackupService.saveSettings(next);
      if (!mounted) return;
      setState(() {
        _settings = next;
        _saving = false;
        _hasChanges = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('local_backup_settings_saved'))));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.format('could_not_save_backup_settings', {'error': error.toString()}))));
    }
  }

  Future<void> _pickDirectory() async {
    final tr = AppLocalizations.of(context);
    final picked = await FilePicker.platform
        .getDirectoryPath(dialogTitle: tr.text('choose_backup_folder'));
    if (picked == null || picked.trim().isEmpty) return;
    _pathController.text = picked;
  }

  Future<void> _backupNow() async {
    final tr = AppLocalizations.of(context);
    try {
      if (_hasChanges) {
        await _save();
      }
      final settings = await LocalAutoBackupService.loadSettings();
      await LocalAutoBackupService.createBackupNow(widget.store,
          settings: settings, reason: 'manual');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('local_backup_completed'))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr.format('local_backup_failed', {'error': error.toString()}))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final theme = Theme.of(context);
    final tr = AppLocalizations.of(context);
    if (settings == null) {
      return const Center(child: LinearProgressIndicator());
    }
    final disabled = widget.store.appIdentity.isClient;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.schedule_outlined),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      tr.text('automatic_local_backup'),
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(_expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down),
                  const SizedBox(width: 8),
                  Switch(
                    value: !disabled && settings.enabled,
                    onChanged: disabled || _saving
                        ? null
                        : (value) => _save(enabled: value),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            Text(disabled
                ? tr.text('local_backup_host_only')
                : tr.text('local_backup_background_desc')),
            const SizedBox(height: 12),
            TextField(
              controller: _pathController,
              enabled: !disabled && !_saving,
              decoration: InputDecoration(
                labelText: tr.text('backup_location'),
                helperText: tr.text('backup_location_default'),
                suffixIcon: IconButton(
                  tooltip: tr.text('browse'),
                  onPressed: disabled || _saving ? null : _pickDirectory,
                  icon: const Icon(Icons.folder_open_outlined),
                ),
              ),
              onSubmitted: (_) {
                if (_hasChanges) _save();
              },
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth < 620
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 24) / 3;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                        width: itemWidth,
                        child: _countField(
                            _dailyController, tr.text('daily_copies'), disabled)),
                    SizedBox(
                        width: itemWidth,
                        child: _countField(
                            _weeklyController, tr.text('weekly_copies'), disabled)),
                    SizedBox(
                        width: itemWidth,
                        child: _countField(
                            _monthlyController, tr.text('monthly_copies'), disabled)),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: disabled || _saving || !_hasChanges
                      ? null
                      : () => _save(),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(tr.text('save_backup_settings')),
                ),
                FilledButton.icon(
                  onPressed: disabled || _saving ? null : _backupNow,
                  icon: const Icon(Icons.backup_outlined),
                  label: Text(tr.text('backup_now')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _countField(
      TextEditingController controller, String label, bool disabled) {
    return TextField(
      controller: controller,
      enabled: !disabled && !_saving,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label),
      onSubmitted: (_) {
        if (_hasChanges) _save();
      },
    );
  }
}

class _GoogleDriveBackupSettingsCard extends StatefulWidget {
  const _GoogleDriveBackupSettingsCard({required this.store});

  final AppStore store;

  @override
  State<_GoogleDriveBackupSettingsCard> createState() =>
      _GoogleDriveBackupSettingsCardState();
}

class _GoogleDriveBackupSettingsCardState
    extends State<_GoogleDriveBackupSettingsCard> {
  GoogleDriveBackupSettings? _settings;
  bool _saving = false;
  bool _hasChanges = false;
  bool _expanded = false;
  bool _showAdvancedSetup = false;
  int _developerTapCount = 0;
  final TextEditingController _clientIdController = TextEditingController();
  final TextEditingController _clientSecretController = TextEditingController();
  final TextEditingController _folderIdController = TextEditingController();
  final TextEditingController _dailyController = TextEditingController();
  final TextEditingController _weeklyController = TextEditingController();
  final TextEditingController _monthlyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _clientIdController,
      _clientSecretController,
      _folderIdController,
      _dailyController,
      _weeklyController,
      _monthlyController,
    ]) {
      controller.addListener(_markChanged);
    }
    _load();
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _folderIdController.dispose();
    _dailyController.dispose();
    _weeklyController.dispose();
    _monthlyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await GoogleDriveBackupService.loadSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _clientIdController.text = settings.clientId;
      _clientSecretController.text = settings.clientSecret;
      _folderIdController.text = settings.folderId;
      _dailyController.text = settings.dailyCount.toString();
      _weeklyController.text = settings.weeklyCount.toString();
      _monthlyController.text = settings.monthlyCount.toString();
      _hasChanges = false;
    });
  }

  void _markChanged() {
    final current = _settings;
    if (current == null || _saving) return;
    final changed =
        _settingsSignature(_draftSettings()) != _settingsSignature(current);
    if (changed != _hasChanges && mounted) {
      setState(() => _hasChanges = changed);
    }
  }

  String _settingsSignature(GoogleDriveBackupSettings settings) =>
      '${settings.enabled}|${settings.clientId.trim()}|${settings.clientSecret.trim()}|${settings.folderId.trim()}|${settings.dailyCount}|${settings.weeklyCount}|${settings.monthlyCount}';

  GoogleDriveBackupSettings _draftSettings({bool? enabled}) {
    final current = _settings!;
    return current.copyWith(
      enabled: enabled ?? current.enabled,
      clientId: _clientIdController.text.trim(),
      clientSecret: _clientSecretController.text.trim(),
      folderId: _folderIdController.text.trim(),
      dailyCount:
          _count(_dailyController, GoogleDriveBackupService.defaultDailyCount),
      weeklyCount: _count(
          _weeklyController, GoogleDriveBackupService.defaultWeeklyCount),
      monthlyCount: _count(
          _monthlyController, GoogleDriveBackupService.defaultMonthlyCount),
    );
  }

  int _count(TextEditingController controller, int fallback) {
    final value = int.tryParse(controller.text.trim());
    if (value == null || value <= 0) return fallback;
    return value;
  }

  Future<GoogleDriveBackupSettings?> _save({bool? enabled}) async {
    final current = _settings;
    if (current == null) return null;
    final tr = AppLocalizations.of(context);
    setState(() => _saving = true);
    final next = _draftSettings(enabled: enabled);
    try {
      await GoogleDriveBackupService.saveSettings(next);
      if (!mounted) return next;
      setState(() {
        _settings = next;
        _saving = false;
        _hasChanges = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('google_drive_backup_settings_saved'))));
      return next;
    } catch (error) {
      if (!mounted) return null;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr.format('could_not_save_google_drive_settings', {'error': error.toString()}))));
      return null;
    }
  }

  Future<void> _startConnect() async {
    final tr = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      final settings = _hasChanges ? await _save() : _settings;
      if (settings == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }
      final next = await GoogleDriveBackupService.connectWithServer(settings);
      if (!mounted) return;
      setState(() {
        _settings = next;
        _saving = false;
        _hasChanges = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('google_drive_connected'))));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.format('google_drive_connection_failed', {'error': error.toString()}))));
    }
  }

  Future<void> _disconnect() async {
    final tr = AppLocalizations.of(context);
    setState(() => _saving = true);
    await GoogleDriveBackupService.disconnect();
    await _load();
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('google_drive_disconnected'))));
  }

  Future<void> _importGoogleCredentialsFile() async {
    final tr = AppLocalizations.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception(tr.text('empty_google_credentials_file'));
      }
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final section = decoded['installed'] is Map
          ? decoded['installed'] as Map
          : decoded['web'] is Map
              ? decoded['web'] as Map
              : null;
      if (section == null) {
        throw Exception(tr.text('invalid_google_credentials_file'));
      }
      final clientId = (section['client_id'] ?? '').toString().trim();
      final clientSecret = (section['client_secret'] ?? '').toString().trim();
      if (clientId.isEmpty) {
        throw Exception(tr.text('google_client_id_not_found'));
      }
      _clientIdController.text = clientId;
      _clientSecretController.text = clientSecret;
      final saved = await _save();
      if (!mounted || saved == null) return;
      setState(() => _showAdvancedSetup = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr.text('google_credentials_imported_connect_now'))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr.format('could_not_import_google_credentials', {'error': error.toString()}))));
    }
  }

  void _handleDeveloperTap() {
    final tr = AppLocalizations.of(context);
    if (_showAdvancedSetup) return;
    _developerTapCount += 1;
    if (_developerTapCount >= 5) {
      _developerTapCount = 0;
      setState(() => _showAdvancedSetup = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('developer_setup_unlocked'))),
      );
    }
  }

  Future<void> _copyDriveFolderLink() async {
    final tr = AppLocalizations.of(context);
    final folderId = _settings?.folderId.trim() ?? '';
    if (folderId.isEmpty) return;
    await Clipboard.setData(ClipboardData(
        text: 'https://drive.google.com/drive/folders/$folderId'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('drive_folder_link_copied'))));
  }

  Future<void> _backupNow() async {
    final tr = AppLocalizations.of(context);
    try {
      if (_hasChanges) {
        await _save();
      }
      final settings = await GoogleDriveBackupService.loadSettings();
      await GoogleDriveBackupService.createBackupNow(widget.store,
          settings: settings, reason: 'manual');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('google_drive_backup_completed'))));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.format('google_drive_backup_failed', {'error': error.toString()}))));
    }
  }

  Future<void> _downloadFromDrive() async {
    final tr = AppLocalizations.of(context);
    try {
      if (_hasChanges) {
        await _save();
      }
      final settings = await GoogleDriveBackupService.loadSettings();
      final files =
          await GoogleDriveBackupService.listBackupFiles(settings: settings);
      if (!mounted) return;
      if (files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr.text('no_google_drive_backups_found'))));
        return;
      }
      final selected = await showDialog<GoogleDriveBackupFile>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr.text('download_backup_from_drive')),
          content: SizedBox(
            width: VentioResponsive.modalMaxWidth(context, 520),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: files.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final file = files[index];
                return ListTile(
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: Text(file.name),
                  subtitle: Text(
                      '${file.category}${file.createdAt == null ? '' : ' - ${_formatDriveBackupDate(file.createdAt!)}'}'),
                  onTap: () => Navigator.pop(dialogContext, file),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr.text('cancel')),
            ),
          ],
        ),
      );
      if (selected == null) return;
      final bytes = await GoogleDriveBackupService.downloadBackupFile(selected,
          settings: settings);
      await downloadBinaryFile(
        filename: selected.name,
        bytes: bytes,
        dialogTitle: tr.text('save_google_drive_backup'),
        cancelMessage: tr.text('backup_download_cancelled'),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('google_drive_backup_downloaded'))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr.format('google_drive_backup_download_failed', {'error': error.toString()}))));
    }
  }

  String _formatDriveBackupDate(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final theme = Theme.of(context);
    final tr = AppLocalizations.of(context);
    if (settings == null) {
      return const Center(child: LinearProgressIndicator());
    }
    final disabled = widget.store.appIdentity.isClient;
    final connected = settings.isAuthorized;
    final showDeveloperSetup = _showAdvancedSetup;
    final googleConfigured =
        CloudSyncSettings.load().apiBaseUrl.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            onLongPress: _handleDeveloperTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.cloud_upload_outlined),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      tr.text('google_drive_backup'),
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(_expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down),
                  const SizedBox(width: 8),
                  Switch(
                    value: !disabled && connected && settings.enabled,
                    onChanged: disabled || _saving || !connected
                        ? null
                        : (value) => _save(enabled: value),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            Text(disabled
                ? tr.text('google_drive_backup_host_only')
                : connected
                    ? tr.text('google_drive_backup_available_desc')
                    : googleConfigured
                        ? tr.text('google_drive_backup_connect_first')
                        : tr.text('google_drive_backup_not_configured')),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(connected
                  ? Icons.check_circle_outline
                  : googleConfigured
                      ? Icons.account_circle_outlined
                      : Icons.info_outline),
              title: Text(connected
                  ? tr.text('google_drive_is_connected')
                  : googleConfigured
                      ? tr.text('connect_with_google')
                      : tr.text('google_drive_not_ready')),
              subtitle: Text(connected
                  ? tr.text('google_drive_backup_upload_desc')
                  : googleConfigured
                      ? tr.text('google_drive_account_desc')
                      : tr.text('google_drive_packaged_server_required')),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth < 620
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 24) / 3;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                        width: itemWidth,
                        child: _countField(
                            _dailyController, tr.text('daily_copies'), disabled)),
                    SizedBox(
                        width: itemWidth,
                        child: _countField(
                            _weeklyController, tr.text('weekly_copies'), disabled)),
                    SizedBox(
                        width: itemWidth,
                        child: _countField(
                            _monthlyController, tr.text('monthly_copies'), disabled)),
                  ],
                );
              },
            ),
            if (showDeveloperSetup) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(tr.text('google_packaging_only_desc')),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed:
                    disabled || _saving ? null : _importGoogleCredentialsFile,
                icon: const Icon(Icons.file_upload_outlined),
                label: Text(tr.text('import_google_credentials_file')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _clientIdController,
                enabled: !disabled && !_saving,
                decoration: InputDecoration(
                  labelText: tr.text('google_oauth_client_id'),
                  helperText: tr.text('one_time_developer_setup_desc'),
                ),
                onSubmitted: (_) {
                  if (_hasChanges) _save();
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _clientSecretController,
                enabled: !disabled && !_saving,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: tr.text('google_oauth_client_secret_optional'),
                  helperText: tr.text('google_oauth_client_secret_helper'),
                ),
                onSubmitted: (_) {
                  if (_hasChanges) _save();
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _folderIdController,
                enabled: !disabled && !_saving,
                decoration: InputDecoration(
                  labelText: tr.text('drive_folder_id_optional'),
                  helperText: tr.text('drive_folder_id_helper'),
                ),
                onSubmitted: (_) {
                  if (_hasChanges) _save();
                },
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: disabled || _saving || !_hasChanges
                      ? null
                      : () => _save(),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(tr.text('save_backup_settings')),
                ),
                OutlinedButton.icon(
                  onPressed: disabled || _saving || !googleConfigured
                      ? null
                      : _startConnect,
                  icon: const Icon(Icons.account_circle_outlined),
                  label: Text(connected
                      ? tr.text('reconnect_with_google')
                      : tr.text('connect_with_google')),
                ),
                FilledButton.icon(
                  onPressed:
                      disabled || _saving || !connected ? null : _backupNow,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(tr.text('backup_now')),
                ),
                OutlinedButton.icon(
                  onPressed: disabled || _saving || !connected
                      ? null
                      : _downloadFromDrive,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: Text(tr.text('download_from_drive')),
                ),
                if (connected && settings.folderId.trim().isNotEmpty)
                  OutlinedButton.icon(
                    onPressed:
                        disabled || _saving ? null : _copyDriveFolderLink,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: Text(tr.text('copy_drive_folder_link')),
                  ),
                if (connected)
                  TextButton.icon(
                    onPressed: disabled || _saving ? null : _disconnect,
                    icon: const Icon(Icons.link_off_outlined),
                    label: Text(tr.text('disconnect')),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _countField(
      TextEditingController controller, String label, bool disabled) {
    return TextField(
      controller: controller,
      enabled: !disabled && !_saving,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label),
      onSubmitted: (_) {
        if (_hasChanges) _save();
      },
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
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.35),
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
        Text(tr.text('current_backup_status'),
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        _InfoGrid(
          items: [
            _InfoGridItem(
                Icons.store_outlined, tr.text('store_name'), summary.storeName),
            _InfoGridItem(Icons.new_releases_outlined,
                tr.text('backup_version'), 'V${summary.version}'),
            _InfoGridItem(Icons.event_outlined, tr.text('backup_date'),
                _formatDate(summary.generatedAt)),
            _InfoGridItem(Icons.inventory_2_outlined, tr.text('products'),
                summary.productsCount.toString()),
            _InfoGridItem(Icons.people_alt_outlined, tr.text('customers'),
                summary.customersCount.toString()),
            _InfoGridItem(Icons.point_of_sale_outlined, tr.text('sales'),
                summary.salesCount.toString()),
            _InfoGridItem(Icons.local_shipping_outlined, tr.text('suppliers'),
                summary.suppliersCount.toString()),
            _InfoGridItem(Icons.receipt_long_outlined, tr.text('expenses'),
                summary.expensesCount.toString()),
          ],
        ),
      ],
    );
  }
}


class _CurrentDeviceCashDrawerSettingsCard extends StatefulWidget {
  const _CurrentDeviceCashDrawerSettingsCard({required this.store});

  final AppStore store;

  @override
  State<_CurrentDeviceCashDrawerSettingsCard> createState() =>
      _CurrentDeviceCashDrawerSettingsCardState();
}

class _CurrentDeviceCashDrawerSettingsCardState
    extends State<_CurrentDeviceCashDrawerSettingsCard> {
  late Future<List<AdvancedAccountingItem>> _future;
  String _selectedDrawerId = '';
  bool _saving = false;

  String get _deviceId => widget.store.deviceId.trim();
  String get _branchId => widget.store.appIdentity.branchId.trim();

  @override
  void initState() {
    super.initState();
    _future = _loadDrawers();
  }

  Future<List<AdvancedAccountingItem>> _loadDrawers() async {
    final items = await AccountingService.listActiveCashLocations(includeBank: false);
    final drawers = items.where((item) => item.type == 'cash_drawer').toList();
    final current = drawers.where((item) => item.referenceId == _deviceId);
    _selectedDrawerId = current.isEmpty ? '' : current.first.id;
    return drawers;
  }

  void _refresh() {
    setState(() {
      _future = _loadDrawers();
    });
  }

  Future<void> _save() async {
    final tr = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      if (_selectedDrawerId.isEmpty) {
        await AccountingService.unlinkCashDrawerFromDevice(deviceId: _deviceId);
      } else {
        await AccountingService.linkCashDrawerToDevice(
          cashLocationId: _selectedDrawerId,
          deviceId: _deviceId,
          branchId: _branchId,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('saved'))),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return _SectionCard(
      icon: Icons.point_of_sale_outlined,
      title: tr.text('current_device_cash_drawer'),
      subtitle: tr.text('current_device_cash_drawer_desc'),
      trailing: IconButton(
        tooltip: tr.text('refresh'),
        onPressed: _saving ? null : _refresh,
        icon: const Icon(Icons.refresh_outlined),
      ),
      child: FutureBuilder<List<AdvancedAccountingItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(),
            );
          }
          final drawers = snapshot.data ?? const <AdvancedAccountingItem>[];
          final currentDevice = _deviceId.isEmpty ? tr.text('unknown') : _deviceId;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoGrid(
                items: [
                  _InfoGridItem(Icons.devices_outlined, 'Device ID', currentDevice),
                  _InfoGridItem(
                    Icons.storefront_outlined,
                    tr.text('branch'),
                    _branchId.isEmpty ? tr.text('not_set') : _branchId,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedDrawerId.isEmpty ? '' : _selectedDrawerId,
                decoration: InputDecoration(
                  labelText: tr.text('linked_cash_drawer'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<String>(
                    value: '',
                    child: Text(tr.text('no_cash_drawer_linked')),
                  ),
                  for (final drawer in drawers)
                    DropdownMenuItem<String>(
                      value: drawer.id,
                      child: Text(
                        drawer.referenceId.isEmpty
                            ? drawer.name
                            : '${drawer.name} • ${drawer.referenceId}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _selectedDrawerId = value ?? ''),
              ),
              const SizedBox(height: 12),
              Text(
                tr.text('current_device_cash_drawer_hint'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _saving || _deviceId.isEmpty ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(tr.text('save')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() => _selectedDrawerId = '');
                            _save();
                          },
                    icon: const Icon(Icons.link_off_outlined),
                    label: Text(tr.text('unlink_cash_drawer')),
                  ),
                ],
              ),
              if (drawers.isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  tr.text('create_cash_drawer_from_accounting_hint'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _UnifiedSyncSettingsCard extends StatefulWidget {
  const _UnifiedSyncSettingsCard(
      {required this.store, this.onSyncSettingsChanged});

  final AppStore store;
  final Future<void> Function()? onSyncSettingsChanged;

  @override
  State<_UnifiedSyncSettingsCard> createState() =>
      _UnifiedSyncSettingsCardState();
}

class _UnifiedSyncSettingsCardState extends State<_UnifiedSyncSettingsCard> {
  final _lanHostController = TextEditingController();
  final _lanPortController = TextEditingController();
  final _lanIntervalController = TextEditingController();
  final _lanTokenController = TextEditingController();
  final _cloudApiController = TextEditingController();
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
  String get _initialCloudHostReadyKey =>
      'cloud_initial_snapshot_ready_${widget.store.appIdentity.storeId}';

  bool? _cloudSyncPlanAllowed;

  bool get _cloudSyncPlanDenied => _cloudSyncPlanAllowed == false;
  bool get _cloudSyncPlanAllowsUi => !_cloudSyncPlanDenied;
  bool get _effectiveCloudEnabled => _cloudEnabled && _cloudSyncPlanAllowsUi;

  bool? _cachedCloudPlanAccessForUi(AccountAuthCache? cache) {
    if (cache == null) return null;
    if (cache.cloudSyncEnabled) return true;

    // A local Host created before Cloud Sync is enabled usually has a cached
    // registered_local=false result and no account token. That is not an
    // authoritative denial; the server will enforce the entitlement when a
    // Cloud pairing code is requested.
    if (widget.store.appIdentity.isHost && cache.accountToken.trim().isEmpty) {
      return null;
    }

    return false;
  }

  @override
  void initState() {
    super.initState();
    _cloudSyncPlanAllowed =
        _cachedCloudPlanAccessForUi(AccountAuthCache.load());
    unawaited(_refreshCloudSyncPlanAccess());
    final identity = widget.store.appIdentity;
    final lan = LanSyncSettings.load();
    final cloud = CloudSyncSettings.load();
    _deviceRole = identity.isClient ? DeviceRole.client : DeviceRole.host;
    _clientSyncMode = identity.activeSyncTransportNormalized == 'cloud'
        ? SyncMode.cloudConnected
        : SyncMode.lanOnly;
    _lanEnabledForHost = identity.isHost && lan.setupComplete && lan.isHost;
    _cloudEnabled = identity.isCloudEnabled && _cloudSyncPlanAllowsUi;
    _lanHostController.text = lan.host;
    _lanPortController.text = lan.port.toString();
    _lanIntervalController.text = lan.intervalSeconds.toString();
    _lanTokenController.text = lan.secret.trim();
    _cloudApiController.text = cloud.apiBaseUrl;
    _cloudIntervalController.text = cloud.intervalSeconds.toString();
    for (final controller in [
      _lanHostController,
      _lanPortController,
      _lanIntervalController,
      _lanTokenController,
      _cloudApiController,
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
    _cloudPairingCodeController.dispose();
    _cloudIntervalController.dispose();
    _transferDeviceController.dispose();
    _pairingCountdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshCloudSyncPlanAccess() async {
    final cache = AccountAuthCache.load();
    bool? planAllowed = _cachedCloudPlanAccessForUi(cache);
    final identityAtStart = widget.store.appIdentity;
    final cloudAtStart = CloudSyncSettings.load();

    String boolLabel(bool? value) {
      if (value == null) return 'unknown';
      return value ? 'true' : 'false';
    }

    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] cloudPlanAccess:start '
      'device=${identityAtStart.deviceId} '
      'role=${identityAtStart.deviceRole.name} '
      'store=${identityAtStart.storeId} '
      'branch=${identityAtStart.branchId} '
      'syncMode=${identityAtStart.syncMode.name} '
      'activeTransport=${identityAtStart.activeSyncTransportNormalized} '
      'apiBase=${cloudAtStart.apiBaseUrl} '
      'cloudConfigured=${cloudAtStart.isConfigured} '
      'hasDeviceToken=${identityAtStart.deviceToken.trim().isNotEmpty} '
      'cacheExists=${cache != null} '
      'cacheMode=${cache?.mode ?? ''} '
      'cacheStore=${cache?.storeId ?? ''} '
      'cacheBranch=${cache?.branchId ?? ''} '
      'hasAccountToken=${cache?.accountToken.trim().isNotEmpty == true} '
      'cacheAllowed=${boolLabel(planAllowed)}',
    );

    try {
      final token = cache?.accountToken.trim() ?? '';
      if (token.isNotEmpty) {
        final result =
            await AccountAuthService().refreshSession(accountToken: token);
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] cloudPlanAccess:session '
          'ok=${result.ok} '
          'store=${result.storeId} '
          'branch=${result.branchId} '
          'status=${result.subscriptionStatus} '
          'allowed=${result.cloudSyncEnabled} '
          'message=${result.message}',
        );
        if (result.ok) {
          await AccountAuthService.cacheOnlineResult(result,
              mode: cache?.mode ?? 'login');
          planAllowed = result.cloudSyncEnabled;
        }
      } else {
        SyncDiagnosticsLog.add(
            '[SYNC_TRACE] cloudPlanAccess:session skipped=noAccountToken');
      }

      // Fallback for local Host sessions. After the user signs in locally as
      // admin, account_auth_cache_v1 may be missing or stale, while the device
      // still has valid store/device credentials. Ask the server directly for
      // this store's Cloud Sync entitlement using device auth.
      if (planAllowed != true) {
        final fallbackAllowed = await CloudSyncService(widget.store)
            .checkCloudSyncPlanAccess(CloudSyncSettings.load());
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] cloudPlanAccess:fallback '
          'allowed=$fallbackAllowed '
          'previous=${boolLabel(planAllowed)}',
        );
        if (fallbackAllowed != null) planAllowed = fallbackAllowed;
      }

      if (!mounted) return;
      final identity = widget.store.appIdentity;
      setState(() {
        _cloudSyncPlanAllowed = planAllowed;
        _cloudEnabled = identity.isCloudEnabled && planAllowed != false;
      });
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] cloudPlanAccess:final '
        'allowed=${boolLabel(planAllowed)} '
        'denied=${planAllowed == false} '
        'uiAllows=${planAllowed != false} '
        'identityCloud=${identity.isCloudEnabled} '
        'switchValue=$_cloudEnabled',
      );
    } catch (error) {
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] cloudPlanAccess:refreshFailed $error');
      if (mounted && _cloudSyncPlanAllowed != true) {
        setState(() {
          _status = 'Could not verify Cloud Sync access.';
        });
      }
      // Keep the cached plan state if the server cannot be reached.
    }
  }

  int get _lanPort => int.tryParse(_lanPortController.text.trim()) ?? 8787;
  int get _lanInterval => LanSyncSettings.defaultIntervalSeconds;
  int get _cloudInterval => CloudSyncSettings.defaultIntervalSeconds;

  void _onSyncDraftChanged() {
    if (mounted) setState(() {});
  }

  bool get _hasUnsavedSyncChanges {
    final identity = widget.store.appIdentity;
    final lan = LanSyncSettings.load();
    final role = identity.isClient ? DeviceRole.client : DeviceRole.host;
    final clientMode = identity.activeSyncTransportNormalized == 'cloud'
        ? SyncMode.cloudConnected
        : SyncMode.lanOnly;
    final lanEnabled = identity.isHost && lan.setupComplete && lan.isHost;
    final cloudEnabled = identity.isCloudEnabled && _cloudSyncPlanAllowsUi;
    return _deviceRole != role ||
        _clientSyncMode != clientMode ||
        _lanEnabledForHost != lanEnabled ||
        _cloudEnabled != cloudEnabled ||
        _lanHostController.text.trim() != lan.host.trim() ||
        _lanPortController.text.trim() != lan.port.toString();
  }

  void _resetSyncDraft({String? status}) {
    final identity = widget.store.appIdentity;
    final lan = LanSyncSettings.load();
    final cloud = CloudSyncSettings.load();
    setState(() {
      _deviceRole = identity.isClient ? DeviceRole.client : DeviceRole.host;
      _clientSyncMode = identity.activeSyncTransportNormalized == 'cloud'
          ? SyncMode.cloudConnected
          : SyncMode.lanOnly;
      _lanEnabledForHost = identity.isHost && lan.setupComplete && lan.isHost;
      _cloudEnabled = identity.isCloudEnabled && _cloudSyncPlanAllowsUi;
      _lanHostController.text = lan.host;
      _lanPortController.text = lan.port.toString();
      _lanIntervalController.text = lan.intervalSeconds.toString();
      _cloudApiController.text = cloud.apiBaseUrl;
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
    if (lower.contains('pairing code expired') ||
        lower.contains('already used')) {
      return tr.text('pairing_code_expired_or_used');
    }
    if (lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('timeoutexception') ||
        lower.contains('failed host lookup')) {
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
          if (_cloudEnabled && _cloudSyncPlanDenied) {
            throw Exception(tr.text('cloud_sync_plan_required'));
          }
          final effectiveCloudEnabled = _effectiveCloudEnabled;
          await widget.store.updateAppIdentityLocalOnly(
            identity.copyWith(
              deviceRole: DeviceRole.host,
              syncMode: effectiveCloudEnabled
                  ? SyncMode.cloudConnected
                  : (_lanEnabledForHost
                      ? SyncMode.lanOnly
                      : SyncMode.localOnly),
              activeSyncTransport: effectiveCloudEnabled
                  ? 'cloud'
                  : (_lanEnabledForHost ? 'lan' : 'local'),
            ),
            source: 'sync settings save',
          );
          final existingLan = LanSyncSettings.load();
          final migratedLan =
              existingLan.withMigratedHostRegistry(widget.store.deviceId);
          await LanSyncSettings(
            host: _lanHostController.text.trim().isEmpty
                ? migratedLan.host
                : _lanHostController.text.trim(),
            port: _lanPort,
            intervalSeconds: _lanInterval,
            autoSyncEnabled: _lanEnabledForHost,
            hostModeEnabled: _lanEnabledForHost,
            setupComplete: _lanEnabledForHost,
            mode: _lanEnabledForHost
                ? LanSyncDeviceMode.host
                : LanSyncDeviceMode.unconfigured,
            secret: migratedLan.secret,
            pairedDevices: migratedLan.pairedDevices,
            hostRegistry: migratedLan.hostRegistry,
          ).save();
          await _cloudSettings(enabled: effectiveCloudEnabled).save();
          if (!effectiveCloudEnabled) {
            await LocalDatabaseService.deleteString(_initialCloudHostReadyKey);
          }
        } else {
          final activeTransport =
              _clientSyncMode == SyncMode.cloudConnected ? 'cloud' : 'lan';
          final lanSettings = LanSyncSettings.load();
          final cloudSettings = CloudSyncSettings.load();
          final lanConfigured = _isLanClientConfigured(lanSettings);
          final cloudConfigured = _isCloudClientConfigured(cloudSettings);
          if (activeTransport == 'lan' && !lanConfigured) {
            throw Exception(tr.text('lan_not_configured_cannot_switch'));
          }
          if (activeTransport == 'cloud' && _cloudSyncPlanDenied) {
            throw Exception(tr.text('cloud_sync_plan_required'));
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
          await lanSettings
              .copyWith(
                autoSyncEnabled: activeTransport == 'lan',
                hostModeEnabled: false,
                intervalSeconds: _lanInterval,
              )
              .save();
          await cloudSettings
              .copyWith(
                autoSyncEnabled: activeTransport == 'cloud',
              )
              .save();
          await widget.store.setActiveSyncTransport(activeTransport);
        }
        if (mounted) {
          _resetSyncDraft(
              status: AppLocalizations.of(context).text('sync_settings_saved'));
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
          _status = _simpleSyncError(error,
              fallback: tr.text('sync_failed_check_info'));
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

  CloudSyncSettings _cloudSettings(
      {bool enabled = true, bool? autoSyncEnabled}) {
    final current = CloudSyncSettings.load();
    final normalizedUrl = current.apiBaseUrl.trim().isNotEmpty
        ? current.apiBaseUrl
        : CloudSyncSettings.normalizeApiBaseUrl(
            CloudSyncSettings.bundledApiBaseUrl,
            fallback: kIsWeb ? Uri.base.origin : '',
          );
    return current.copyWith(
      enabled: enabled,
      apiBaseUrl: normalizedUrl,
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

  UnifiedSyncEngine _lanEngine([LanSyncSettings? settings]) =>
      UnifiedSyncEngine(
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
    final lanEnabled =
        identity.isHost && savedLan.setupComplete && savedLan.isHost;
    if (!_lanEnabledForHost || !lanEnabled) {
      throw StateError(tr.text('enable_lan_before_pairing_code'));
    }
    final current = savedLan.copyWith(
      host: _lanHostController.text.trim().isEmpty
          ? savedLan.host
          : _lanHostController.text.trim(),
      port: _lanPort,
    );
    final result = await _lanEngine(current)
        .createPairingCode(ttlMinutes: _pairingCodeLifetime.inMinutes);
    if (!result.ok) {
      throw StateError(localizeRuntimeMessage(result.message, tr));
    }
    final code = result.code;
    final expiresAt =
        result.expiresAt ?? DateTime.now().add(_pairingCodeLifetime);
    _lanTokenController.text = code;
    _latestLanPairingExpiresAt = expiresAt;
    _latestLanPairingConsumed = false;
    _showLanPairingCode = true;
    await LocalDatabaseService.setString(
        _lanPairingExpiryStorageKey, expiresAt.toIso8601String());
    if (mounted) setState(() => _status = tr.text('lan_pairing_code_created'));
  }

  void _loadActivePairingCodes() {
    final now = DateTime.now();
    final lanExpiry = DateTime.tryParse(
        LocalDatabaseService.getString(_lanPairingExpiryStorageKey) ?? '');
    if (_lanTokenController.text.trim().isNotEmpty &&
        lanExpiry != null &&
        lanExpiry.isAfter(now)) {
      _latestLanPairingExpiresAt = lanExpiry;
      _showLanPairingCode = false;
    } else if (lanExpiry != null && !lanExpiry.isAfter(now)) {
      _expireLanPairingCode();
    }
    final cloudCode =
        LocalDatabaseService.getString(_cloudPairingCodeStorageKey) ?? '';
    final cloudExpiry = DateTime.tryParse(
        LocalDatabaseService.getString(_cloudPairingExpiryStorageKey) ?? '');
    if (cloudCode.trim().isNotEmpty &&
        cloudExpiry != null &&
        cloudExpiry.isAfter(now)) {
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
      if (_latestLanPairingExpiresAt != null &&
          !_latestLanPairingExpiresAt!.isAfter(now)) {
        _expireLanPairingCode();
      }
      _refreshLanPairingConsumedState();
      if (_latestCloudPairingExpiresAt != null &&
          !_latestCloudPairingExpiresAt!.isAfter(now)) {
        _expireCloudPairingCode();
      }
      if (_latestCloudPairingCode.trim().isNotEmpty &&
          (_latestCloudPairingExpiresAt?.isAfter(now) ?? false)) {
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
    final seconds = expiresAt
        .difference(DateTime.now())
        .inSeconds
        .clamp(0, 24 * 60 * 60)
        .toInt();
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

  String get _lanPairingButtonLabel => _hasActiveLanPairingCode
      ? tr.text('regenerate_new_lan_code')
      : tr.text('generate_lan_code');

  String get _cloudPairingButtonLabel => _hasActiveCloudPairingCode
      ? tr.text('regenerate_new_cloud_code')
      : tr.text('generate_cloud_code');

  Future<void> _refreshCloudPairingStatus() async {
    final code = _latestCloudPairingCode.trim();
    if (code.isEmpty || !widget.store.appIdentity.isHost) return;
    final settings = _cloudSettings(enabled: true);
    if (!settings.isConfigured) return;
    final result =
        await CloudSyncService(widget.store).pairingCodeStatus(settings, code);
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
        _latestCloudPairingExpiresAt = result.status == 'expired'
            ? DateTime.now().subtract(const Duration(seconds: 1))
            : _latestCloudPairingExpiresAt;
      } else if (result.expiresAt != null) {
        _latestCloudPairingInvalid = false;
        _latestCloudPairingExpiresAt = result.expiresAt;
      }
    });
  }

  Future<void> _adoptConsumedCloudPairingDevice(
      CloudPairingStatusResult result) async {
    final clientDeviceId = result.claimedByDeviceId.trim();
    if (clientDeviceId.isEmpty || !widget.store.appIdentity.isHost) return;

    final hostDeviceId = widget.store.deviceId.trim();
    final current =
        LanSyncSettings.load().withMigratedHostRegistry(hostDeviceId);
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
    try {
      final devices = await CloudSyncService(widget.store)
          .listDevicesWithLimit(_cloudSettings(enabled: true));
      if (devices.limit?.limitReached == true) {
        setState(() => _status = tr.text('device_limit_reached'));
        return;
      }
    } catch (_) {
      // The server still enforces the limit when creating/claiming the code.
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
    final limit = _localClientDeviceLimitStatus(widget.store, lan);
    if (limit?.limitReached == true) {
      setState(() => _status = tr.text('device_limit_reached'));
      return;
    }
    if (_hasActiveLanPairingCode) _expireLanPairingCode();
    await _generateLanToken();
  }

  Future<void> _requestHostTransfer() => _run(() async {
        await widget.store.requestHostTransfer(
            reason: tr.text('user_requested_host_role_reason'));
        final cloud = _cloudSettings(enabled: true);
        if (cloud.apiBaseUrl.trim().isNotEmpty) {
          await CloudSyncService(widget.store).requestHostTransfer(cloud,
              reason: tr.text('user_requested_host_role_reason'));
        }
        if (mounted) {
          setState(() => _status = tr.format('host_transfer_request_created',
              {'deviceId': widget.store.deviceId}));
        }
      });

  Future<void> _approveHostTransferFromUi() => _run(() async {
        final deviceId = _transferDeviceController.text.trim();
        if (deviceId.isEmpty) {
          throw StateError(tr.text('client_device_id_required'));
        }
        final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(
                AppLocalizations.of(context).text('approve_host_transfer')),
            content: Text(AppLocalizations.of(context)
                .text('approve_host_transfer_desc')
                .replaceAll('{deviceId}', deviceId)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(AppLocalizations.of(context).text('cancel'))),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(AppLocalizations.of(context).text('approve'))),
            ],
          ),
        );
        if (confirmed != true) return;
        final cloud = _cloudSettings(enabled: true);
        if (cloud.isConfigured) {
          final cloudResult = await CloudSyncService(widget.store)
              .approveHostTransfer(cloud, deviceId);
          if (!cloudResult.ok) {
            throw StateError(localizeRuntimeMessage(cloudResult.message, tr));
          }
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
        transport = (decoded['transport'] ??
                decoded['syncType'] ??
                decoded['type'] ??
                '')
            .toString()
            .toLowerCase();
        host = (decoded['host'] ?? decoded['hostIp'] ?? decoded['ip'] ?? '')
            .toString()
            .trim();
        port = (decoded['port'] ?? '').toString().trim();
        apiBaseUrl = (decoded['apiBaseUrl'] ??
                decoded['apiUrl'] ??
                decoded['cloudApiUrl'] ??
                '')
            .toString()
            .trim();
        code = (decoded['pairingCode'] ??
                decoded['pairing_code'] ??
                decoded['code'] ??
                decoded['token'] ??
                decoded['pairingToken'] ??
                raw)
            .toString()
            .trim();
        storeId =
            (decoded['storeId'] ?? decoded['store_id'] ?? '').toString().trim();
        branchId = (decoded['branchId'] ?? decoded['branch_id'] ?? '')
            .toString()
            .trim();
        hostDeviceId = (decoded['hostDeviceId'] ??
                decoded['hostId'] ??
                decoded['host_id'] ??
                decoded['host_device_id'] ??
                '')
            .toString()
            .trim();
        cloudTenantId = (decoded['cloudTenantId'] ??
                decoded['tenantId'] ??
                decoded['tenant_id'] ??
                '')
            .toString()
            .trim();
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

  void _applyParsedPairingPayload(_ScannedPairingPayload payload,
      {void Function(VoidCallback fn)? dialogSetState,
      SyncMode? fallbackMode}) {
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
    if (expectedStore.isNotEmpty && actualStore != expectedStore) {
      mismatches.add(tr.text('store_id_label'));
    }
    if (expectedBranch.isNotEmpty && actualBranch != expectedBranch) {
      mismatches.add(tr.text('branch_id_label'));
    }
    if (expectedHost.isNotEmpty && actualHost != expectedHost) {
      mismatches.add(tr.text('host_id_label'));
    }
    if (expectedTenant.isNotEmpty &&
        actualTenant.isNotEmpty &&
        actualTenant != expectedTenant) {
      mismatches.add(tr.text('tenant_id_label'));
    }
    if (mismatches.isNotEmpty) {
      throw Exception(
          tr.format('pairing_data_mismatch', {'items': mismatches.join(', ')}));
    }
  }

  void _validateAgainstExistingClientIdentity(
      AppIdentity before, AppIdentity after) {
    if (!before.isClient || before.hostDeviceId.trim().isEmpty) return;
    final mismatches = <String>[];
    if (_normalizedPairingId(before.storeId) !=
        _normalizedPairingId(after.storeId)) {
      mismatches.add(tr.text('store_id_label'));
    }
    if (_normalizedPairingId(before.branchId) !=
        _normalizedPairingId(after.branchId)) {
      mismatches.add(tr.text('branch_id_label'));
    }
    if (_normalizedPairingId(before.hostDeviceId) !=
        _normalizedPairingId(after.hostDeviceId)) {
      mismatches.add(tr.text('host_id_label'));
    }
    if (mismatches.isNotEmpty) {
      throw Exception(tr.format(
          'connection_different_store', {'items': mismatches.join(', ')}));
    }
  }

  Future<void> _scanConnectToStoreQr(
      void Function(VoidCallback fn) setDialogState,
      void Function(SyncMode mode) setDialogMode,
      SyncMode fallbackMode) async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PageTimingScope(
          key: const ValueKey('BarcodeScannerPage'),
          pageKey: 'BarcodeScannerPage',
          pageLabel: 'Barcode scanner',
          child: BarcodeScannerPage(
            title: AppLocalizations.of(context).text('scan_pairing_qr'),
            helpText: AppLocalizations.of(context).text('scan_pairing_qr_help'),
            formats: const [BarcodeFormat.qrCode],
          ),
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
    _applyParsedPairingPayload(payload,
        dialogSetState: setDialogState, fallbackMode: fallbackMode);
  }

  Future<void> _scanPairingQr() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PageTimingScope(
          key: const ValueKey('BarcodeScannerPage'),
          pageKey: 'BarcodeScannerPage',
          pageLabel: 'Barcode scanner',
          child: BarcodeScannerPage(
            title: AppLocalizations.of(context).text('scan_pairing_qr'),
            helpText: AppLocalizations.of(context).text('scan_pairing_qr_help'),
            formats: const [BarcodeFormat.qrCode],
          ),
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
        final result = await _cloudEngine(enabled: _cloudEnabled)
            .createPairingCode(ttlMinutes: _pairingCodeLifetime.inMinutes);
        if (!result.ok) {
          throw StateError(localizeRuntimeMessage(result.message, tr));
        }
        final expiresAt =
            result.expiresAt ?? DateTime.now().add(_pairingCodeLifetime);
        await LocalDatabaseService.setString(
            _cloudPairingCodeStorageKey, result.code);
        await LocalDatabaseService.setString(
            _cloudPairingExpiryStorageKey, expiresAt.toIso8601String());
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
            ? tr
                .text('sync_settings_pending_cleared')
                .replaceAll('{count}', removed.toString())
            : tr.text('no_sync_settings_pending_found');
      });
    });
  }

  Future<void> _syncNow() => _run(() async {
        final identity = widget.store.appIdentity;
        final lan = LanSyncSettings.load();
        final cloud = CloudSyncSettings.load();
        final hostLanEnabled = identity.isHost &&
            (_lanEnabledForHost || (lan.setupComplete && lan.isHost));
        final hostCloudEnabled = identity.isHost &&
            (_cloudEnabled || (identity.isCloudEnabled && cloud.isConfigured));
        final messages = <String>[];
        if (hostCloudEnabled ||
            (!identity.isHost &&
                identity.activeSyncTransportNormalized == 'cloud')) {
          final result = await _cloudEngine(enabled: true).syncNow(
            onProgress: (value, label) {
              if (mounted) {
                setState(() {
                  _status =
                      '${tr.text('connection_cloud')}: ${localizeRuntimeMessage(label, tr)} ${(value * 100).round()}%';
                  _statusProgress = value;
                });
              }
            },
          );
          if (!result.ok) {
            throw StateError(localizeRuntimeMessage(result.message, tr));
          }
          messages.add(
              '${tr.text('connection_cloud')}: ${tr.text('sync_completed')}');
        }
        if (identity.isClient &&
            identity.activeSyncTransportNormalized == 'lan') {
          final result = await _lanEngine().syncNow(
            onProgress: (value, label) {
              if (mounted) {
                setState(() {
                  _status =
                      '${tr.text('connection_lan')}: ${localizeRuntimeMessage(label, tr)} ${(value * 100).round()}%';
                  _statusProgress = value;
                });
              }
            },
          );
          if (!result.ok) {
            throw StateError(localizeRuntimeMessage(result.message, tr));
          }
          messages.add(
              '${tr.text('connection_lan')}: ${tr.text('sync_completed')}');
        } else if (hostLanEnabled) {
          messages.add(
              '${tr.text('connection_lan')}: ${tr.text('lan_host_running')}');
        }
        if (messages.isEmpty) {
          setState(() => _status = tr.text('no_sync_mode_enabled'));
        } else {
          setState(() {
            _status = messages.join(' • ');
            _statusProgress = 1.0;
          });
        }
      });

  String _shortDeviceLabel(String deviceId, {String name = ''}) {
    final trimmedName = name.trim();
    if (trimmedName.isNotEmpty) return trimmedName;
    final id = deviceId.trim();
    if (id.length <= 8) return id.isEmpty ? tr.text('unknown_client') : id;
    final prefix = id.substring(0, 4);
    final suffix = id.substring(id.length - 4);
    return '${tr.text('client_label')} $prefix…$suffix';
  }

  String _formatShortDateTime(DateTime? value) {
    if (value == null) return tr.text('never');
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  String _peerSyncStatus(HostPeerSyncState? peer) {
    if (peer == null) return tr.text('connection_state_not_configured');
    if (peer.lastAckSequence > 0 ||
        peer.lastAckCursor != null ||
        peer.lastAppliedHostCursor != null) {
      return tr.text('synced');
    }
    return tr.text('sync_pending');
  }

  Future<void> _testPairedClientConnections() => _run(() async {
        setState(() {
          _status = tr.text('testing_paired_clients');
          _statusProgress = 0.15;
        });
        final identity = widget.store.appIdentity;
        final lan = LanSyncSettings.load();
        final cloud = CloudSyncSettings.load();
        final peerStates = <String, HostPeerSyncState>{
          for (final state in SyncDeviceStateStore.loadPeerStates())
            state.deviceId: state,
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
            if (device.deviceId.trim().isNotEmpty)
              device.deviceId.trim(): device,
        };
        // Phase 3: Host Registry is the single source of truth for
        // Monitoring/Test Connection device discovery. Cloud devices and peer
        // states are used only as status overlays for registered Clients.
        final registryById = <String, HostRegistryDevice>{
          for (final entry in lan.hostRegistry.entries)
            if (entry.key.trim().isNotEmpty && entry.value.isActive)
              entry.key.trim(): entry.value,
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
              : ((registryDevice?.source != 'cloud_pairing_claim' &&
                      registryDevice?.deviceToken.trim().isNotEmpty == true)
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
          } else if ((_cloudEnabled || identity.isCloudEnabled) &&
              cloud.isConfigured) {
            parts.add(cloudReachable
                ? tr.text('cloud_not_configured')
                : '${tr.text('cloud_error')}${cloudProblem.isEmpty ? '' : ': $cloudProblem'}');
          }
          if (lanToken.isNotEmpty) {
            parts.add(tr.text('lan_active'));
          } else if (_lanEnabledForHost || (lan.setupComplete && lan.isHost)) {
            parts.add(tr.text('lan_not_configured'));
          }
          final peerSynced = peer != null &&
              (peer.lastAckSequence > 0 ||
                  peer.lastAckCursor != null ||
                  peer.lastAppliedHostCursor != null);
          final syncStatus = _peerSyncStatus(peer);
          if (peerSynced &&
              ((cloudDevice != null &&
                      !cloudDevice.revoked &&
                      (cloudDevice.online || cloudDevice.isOnline)) ||
                  lanToken.isNotEmpty)) {
            ready++;
          }
          parts.add(syncStatus);
          parts.add(
              '${tr.text('last_sync')}: ${_formatShortDateTime(peer?.lastAckCursor ?? peer?.lastAppliedHostCursor ?? peer?.updatedAt)}');
          final label = _shortDeviceLabel(id,
              name:
                  registryDevice?.deviceName ?? cloudDevice?.deviceName ?? '');
          lines.add('$label → ${parts.join(' | ')}');
        }

        final total = ids.length;
        setState(() {
          _status = '${tr.format('paired_clients_ready', {
                'ready': ready,
                'total': total
              })} • ${lines.join(' • ')}';
          _statusProgress = 1.0;
        });
      });

  Future<void> _testCloudConnection() => _run(() async {
        setState(() {
          _status = tr.text('testing_cloud_connection');
          _statusProgress = 0.25;
        });
        final result = await _cloudEngine(enabled: true).testConnection();
        if (!result.ok) {
          throw StateError(localizeRuntimeMessage(result.message, tr));
        }
        setState(() {
          _status =
              '${tr.text('connection_cloud')}: ${localizeRuntimeMessage(result.message, tr)}';
          _statusProgress = 1.0;
        });
      });

  Future<void> _testHostConnection() => _run(() async {
        final lan = LanSyncSettings.load();
        final host = _lanHostController.text.trim().isEmpty
            ? lan.host
            : _lanHostController.text.trim();
        setState(() {
          _status = tr.text('testing_lan_connection');
          _statusProgress = 0.25;
        });
        final result =
            await _lanEngine(lan.copyWith(host: host, port: _lanPort))
                .testConnection();
        if (!result.ok) {
          throw StateError(localizeRuntimeMessage(result.message, tr));
        }
        setState(() {
          _status = '${tr.text('connection_lan')}: ${tr.text('connection_ok')}';
          _statusProgress = 1.0;
        });
      });

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    final identity = widget.store.appIdentity;
    final isHost = _deviceRole == DeviceRole.host;
    final lanActive =
        isHost ? _lanEnabledForHost : identity.syncMode == SyncMode.lanOnly;
    final cloudActive = isHost
        ? _effectiveCloudEnabled
        : (identity.syncMode == SyncMode.cloudConnected &&
            _cloudSyncPlanAllowsUi);
    final hostActionLabel = tr.text('sync_now');
    final allGood = widget.store.pendingSyncCount == 0 &&
        (lanActive || cloudActive || !isHost);

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
            _syncOverviewCard(context,
                allGood: allGood,
                isHost: isHost,
                lanActive: lanActive,
                cloudActive: cloudActive),
            if (!isHost && widget.store.isSuspendedByHost) ...[
              const SizedBox(height: 14),
              _clientSuspendedWarningCard(context),
            ],
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final thisDevice = _thisDeviceCard(context,
                    isHost: isHost,
                    lanActive: lanActive,
                    cloudActive: cloudActive);

                // Clients are paired during first-time setup/login. Once this
                // settings page is reachable, the Client should not show a
                // misleading "Connect Device" action again; Sync should only
                // show status, sync information, and management controls.
                if (!isHost) {
                  return thisDevice;
                }

                final addDevice =
                    _addDeviceCard(context, isHost: true, isCloudClient: false);
                if (compact) {
                  return Column(children: [
                    thisDevice,
                    const SizedBox(height: 14),
                    addDevice
                  ]);
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
            _syncChannelsCard(context,
                isHost: isHost, lanActive: lanActive, cloudActive: cloudActive),
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
                Text(tr.text('client_suspended_by_host'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700, color: color.onSurface)),
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
                color: allGood
                    ? Colors.green.withValues(alpha: 0.12)
                    : color.primaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                  allGood ? Icons.check_circle_outline : Icons.sync_outlined,
                  color: allGood ? Colors.green.shade700 : color.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr.text('sync_settings'),
                    style: (compact
                            ? Theme.of(context).textTheme.titleLarge
                            : Theme.of(context).textTheme.headlineSmall)
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    allGood
                        ? tr.text('all_data_synchronized')
                        : tr.text('needs_sync'),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: color.onSurfaceVariant),
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

  Widget _syncOverviewCard(BuildContext context,
      {required bool allGood,
      required bool isHost,
      required bool lanActive,
      required bool cloudActive}) {
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
                child: Icon(allGood
                    ? Icons.verified_outlined
                    : Icons.sync_problem_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        allGood
                            ? tr.text('all_systems_are_running_smoothly')
                            : tr.text('needs_sync'),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(_humanStatus(context),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: color.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          );
          final metrics = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _compactStatusChip(
                  context,
                  Icons.dns_outlined,
                  isHost ? tr.text('host_device') : tr.text('client_device'),
                  color.primary),
              _compactStatusChip(
                  context,
                  Icons.lan_outlined,
                  '${tr.text('lan')}: ${lanActive ? tr.text('connection_state_active') : tr.text('off')}',
                  lanActive ? Colors.green : color.onSurfaceVariant),
              _compactStatusChip(
                  context,
                  Icons.cloud_outlined,
                  '${tr.text('cloud')}: ${cloudActive ? tr.text('connection_state_active') : tr.text('off')}',
                  cloudActive ? Colors.green : color.onSurfaceVariant),
              _compactStatusChip(
                  context,
                  Icons.storage_outlined,
                  '${tr.text('pending_changes')}: ${widget.store.pendingSyncCount}',
                  widget.store.pendingSyncCount == 0
                      ? Colors.green
                      : color.error),
            ],
          );
          if (compact) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [summary, const SizedBox(height: 14), metrics]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: summary),
            const SizedBox(width: 16),
            Flexible(child: metrics)
          ]);
        },
      ),
    );
  }

  Widget _thisDeviceCard(BuildContext context,
      {required bool isHost,
      required bool lanActive,
      required bool cloudActive}) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    return _plainSyncPanel(
      context,
      icon: Icons.devices_outlined,
      title: tr.text('device_role'),
      subtitle: isHost
          ? tr.text('connection_role_host')
          : tr.text('connection_role_client'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _simpleInfoRow(
              context,
              tr.text('role'),
              isHost ? tr.text('host_device') : tr.text('client_device'),
              Icons.dns_outlined,
              color.primary),
          const SizedBox(height: 8),
          _simpleInfoRow(
              context,
              tr.text('lan_connection'),
              lanActive
                  ? tr.text('connection_state_active')
                  : tr.text('pairing_status_disabled'),
              Icons.lan_outlined,
              lanActive ? Colors.green : color.onSurfaceVariant),
          const SizedBox(height: 8),
          _simpleInfoRow(
              context,
              tr.text('cloud_connection'),
              cloudActive
                  ? tr.text('connection_state_active')
                  : tr.text('connection_state_disabled'),
              Icons.cloud_outlined,
              cloudActive ? Colors.green : color.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _addDeviceCard(BuildContext context,
      {required bool isHost, required bool isCloudClient}) {
    final tr = AppLocalizations.of(context);
    return _plainSyncPanel(
      context,
      icon: isHost ? Icons.add_link_outlined : Icons.link_outlined,
      title: isHost ? tr.text('pair_new_device') : tr.text('connect_device'),
      subtitle: isHost
          ? tr.text('pair_new_device_desc')
          : tr.text('connect_device_desc'),
      child: _pairingContent(context,
          isHost: isHost, isCloudClient: isCloudClient),
    );
  }

  bool _isLanClientConfigured(LanSyncSettings lan) =>
      lan.setupComplete &&
      lan.host.trim().isNotEmpty &&
      lan.secret.trim().isNotEmpty;

  bool _isCloudClientConfigured(CloudSyncSettings cloud) =>
      cloud.isConfigured && cloud.apiBaseUrl.trim().isNotEmpty;

  String _clientTransportStatusLabel(BuildContext context,
      {required bool active, required bool configured}) {
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
    var dialogBusy = false;
    double? dialogProgressValue;
    var dialogProgressLabel = '';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isLan = dialogMode == SyncMode.lanOnly;
            final screenWidth = MediaQuery.sizeOf(context).width;
            final compact = screenWidth < 420;
            return AlertDialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              title: Text(tr.text('connect_to_store'),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: screenWidth < 568 ? screenWidth - 32 : 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(tr.text('connect_to_store_desc'),
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<SyncMode>(
                          showSelectedIcon: !compact,
                          segments: [
                            ButtonSegment<SyncMode>(
                                value: SyncMode.lanOnly,
                                icon: const Icon(Icons.lan_outlined),
                                label: Text(tr.text('lan'))),
                            ButtonSegment<SyncMode>(
                                value: SyncMode.cloudConnected,
                                icon: const Icon(Icons.cloud_outlined),
                                label: Text(tr.text('cloud'))),
                          ],
                          selected: {dialogMode},
                          onSelectionChanged: dialogBusy
                              ? null
                              : (value) => setDialogState(
                                  () => dialogMode = value.first),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SizedBox(
                          width: compact ? double.infinity : null,
                          child: OutlinedButton.icon(
                            onPressed: (_busy || dialogBusy)
                                ? null
                                : () => _scanConnectToStoreQr(
                                      setDialogState,
                                      (mode) => setDialogState(
                                          () => dialogMode = mode),
                                      dialogMode,
                                    ),
                            icon: const Icon(Icons.qr_code_scanner_outlined),
                            label: Text(tr.text('scan_qr_code'),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (isLan) ...[
                        TextField(
                            enabled: !dialogBusy,
                            controller: _lanHostController,
                            decoration: InputDecoration(
                                labelText: tr.text('host_ip_address'),
                                border: const OutlineInputBorder())),
                        const SizedBox(height: 12),
                        TextField(
                            enabled: !dialogBusy,
                            controller: _lanPortController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                                labelText: tr.text('port'),
                                border: const OutlineInputBorder())),
                        const SizedBox(height: 12),
                        TextField(
                            enabled: !dialogBusy,
                            controller: _lanTokenController,
                            decoration: InputDecoration(
                                labelText: tr.text('pairing_token'),
                                border: const OutlineInputBorder())),
                      ] else ...[
                        TextField(
                            enabled: !dialogBusy,
                            controller: _cloudPairingCodeController,
                            decoration: InputDecoration(
                                labelText: tr.text('pairing_code_from_host'),
                                border: const OutlineInputBorder())),
                      ],
                      if (dialogBusy) ...[
                        const SizedBox(height: 16),
                        UnifiedSnapshotProgressView(
                          value: dialogProgressValue,
                          label: dialogProgressLabel.isEmpty
                              ? tr.text('connecting_downloading_store_data')
                              : dialogProgressLabel,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(tr.text('cancel'))),
                FilledButton(
                  onPressed: dialogBusy
                      ? null
                      : () async {
                          setDialogState(() {
                            dialogBusy = true;
                            dialogProgressValue = 0.04;
                            dialogProgressLabel =
                                tr.text('connecting_downloading_store_data');
                          });
                          void dialogProgress(double value, String label) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() {
                              dialogProgressValue = value;
                              dialogProgressLabel =
                                  localizeRuntimeMessage(label, tr);
                            });
                          }

                          try {
                            if (isLan) {
                              final host = _lanHostController.text.trim();
                              final token = _lanTokenController.text.trim();
                              if (host.isEmpty || token.isEmpty) {
                                setDialogState(() => dialogBusy = false);
                                return;
                              }
                              final previousIdentity = widget.store.appIdentity;
                              final previousActive = previousIdentity
                                  .activeSyncTransportNormalized;
                              final result = await LanSyncService(widget.store)
                                  .claimPairingCode(
                                host,
                                port: _lanPort,
                                code: token,
                                onProgress: dialogProgress,
                              );
                              if (!result.ok) throw Exception(result.message);
                              _validateExpectedPairingTarget(
                                  widget.store.appIdentity);
                              _validateAgainstExistingClientIdentity(
                                  previousIdentity, widget.store.appIdentity);
                              if (previousActive == 'cloud') {
                                await widget.store
                                    .setActiveSyncTransport('cloud');
                              }
                            } else {
                              final code =
                                  _cloudPairingCodeController.text.trim();
                              if (code.isEmpty) {
                                setDialogState(() => dialogBusy = false);
                                return;
                              }
                              final previousIdentity = widget.store.appIdentity;
                              final previousActive = previousIdentity
                                  .activeSyncTransportNormalized;
                              final settings =
                                  CloudSyncSettings.load().copyWith(
                                enabled: true,
                                autoSyncEnabled: previousActive == 'cloud',
                              );
                              await settings.save();
                              final result =
                                  await CloudSyncService(widget.store)
                                      .claimPairingCode(settings, code,
                                          onProgress: dialogProgress);
                              if (!result.ok) throw Exception(result.message);
                              final claimedIdentity =
                                  result.identity ?? widget.store.appIdentity;
                              _validateExpectedPairingTarget(claimedIdentity);
                              _validateAgainstExistingClientIdentity(
                                  previousIdentity, claimedIdentity);
                              if (previousActive == 'lan') {
                                await widget.store
                                    .setActiveSyncTransport('lan');
                              }
                            }
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (error) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() {
                              dialogBusy = false;
                              dialogProgressLabel =
                                  localizeRuntimeMessage(error.toString(), tr);
                            });
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(localizeRuntimeMessage(
                                    error.toString(), tr))));
                          }
                        },
                  child:
                      Text(dialogBusy ? tr.text('working') : tr.text('save')),
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

  Widget _syncChannelsCard(BuildContext context,
      {required bool isHost,
      required bool lanActive,
      required bool cloudActive}) {
    final tr = AppLocalizations.of(context);
    final lan = LanSyncSettings.load();
    final cloud = CloudSyncSettings.load();
    final lanConfigured =
        isHost ? _lanEnabledForHost : _isLanClientConfigured(lan);
    final cloudPlanDenied = _cloudSyncPlanDenied;
    final cloudPlanAllowsUi = _cloudSyncPlanAllowsUi;
    final cloudConfigured = isHost
        ? _effectiveCloudEnabled
        : (_isCloudClientConfigured(cloud) && cloudPlanAllowsUi);
    return _plainSyncPanel(
      context,
      icon: Icons.hub_outlined,
      title: tr.text('sync_method'),
      subtitle: tr.text('sync_settings_desc'),
      child: Column(
        children: [
          if (!isHost) ...[
            _activeTransportSelector(context,
                lanConfigured: lanConfigured, cloudConfigured: cloudConfigured),
            const SizedBox(height: 12),
          ],
          _syncMethodExpansionTile(
            context,
            icon: Icons.lan_outlined,
            title: tr.text('lan_sync'),
            subtitle: isHost
                ? (lanConfigured
                    ? tr.text('connection_state_active')
                    : tr.text('connection_state_disabled'))
                : _clientTransportStatusLabel(context,
                    active: lanActive, configured: lanConfigured),
            active: lanActive,
            configured: lanConfigured,
            accent: Colors.green,
            trailing: isHost
                ? Switch(
                    value: _lanEnabledForHost,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _lanEnabledForHost = value))
                : (!lanConfigured
                    ? TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _openConnectToStoreDialog(SyncMode.lanOnly),
                        icon: const Icon(Icons.add_link_outlined),
                        label: Text(tr.text('connect_to_store')))
                    : null),
            children: isHost
                ? [
                    if (_lanEnabledForHost) ...[
                      _hostIpInfoCard(),
                      ..._lanFields(showHostIp: false, forHost: true),
                    ] else
                      _miniLine(tr.text('status'),
                          tr.text('connection_state_disabled')),
                  ]
                : [
                    _readOnlyTransportLine(
                        context,
                        tr.text('status'),
                        _clientTransportStatusLabel(context,
                            active: lanActive, configured: lanConfigured),
                        lanActive
                            ? Icons.check_circle_outline
                            : (lanConfigured
                                ? Icons.lock_outline
                                : Icons.link_off_outlined)),
                    _readOnlyTransportLine(context, tr.text('host_ip_address'),
                        lan.host.isEmpty ? '—' : lan.host, Icons.dns_outlined),
                    _readOnlyTransportLine(context, tr.text('port'),
                        '${lan.port}', Icons.tag_outlined),
                    _readOnlyTransportLine(
                        context,
                        tr.text('pairing_token'),
                        lan.secret.trim().isEmpty ? '—' : '••••••••',
                        Icons.vpn_key_outlined),
                  ],
          ),
          const Divider(height: 20),
          _syncMethodExpansionTile(
            context,
            icon: Icons.cloud_outlined,
            title: tr.text('cloud_sync'),
            subtitle: isHost
                ? (cloudPlanDenied
                    ? tr.text('cloud_sync_plan_locked_short')
                    : (cloudConfigured
                        ? tr.text('connection_state_active')
                        : tr.text('connection_state_disabled')))
                : _clientTransportStatusLabel(context,
                    active: cloudActive, configured: cloudConfigured),
            active: cloudActive,
            configured: cloudConfigured,
            accent: Colors.blue,
            trailing: isHost
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (cloudPlanDenied) ...[
                        Icon(Icons.lock_outline,
                            size: 18,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                      ],
                      Switch(
                        value: _effectiveCloudEnabled,
                        onChanged: (_busy || cloudPlanDenied)
                            ? null
                            : (value) => setState(() => _cloudEnabled = value),
                      ),
                    ],
                  )
                : (!cloudConfigured
                    ? TextButton.icon(
                        onPressed: (_busy || cloudPlanDenied)
                            ? null
                            : () => _openConnectToStoreDialog(
                                SyncMode.cloudConnected),
                        icon: Icon(cloudPlanAllowsUi
                            ? Icons.add_link_outlined
                            : Icons.lock_outline),
                        label: Text(cloudPlanAllowsUi
                            ? tr.text('connect_to_store')
                            : tr.text('cloud_sync_plan_locked_short')))
                    : null),
            children: isHost
                ? [
                    if (cloudPlanDenied)
                      _softNotice(
                        context,
                        Icons.lock_outline,
                        tr.text('cloud_sync_plan_locked_title'),
                        tr.text('cloud_sync_plan_locked_desc'),
                      )
                    else if (_effectiveCloudEnabled)
                      ..._cloudFields(showPairingCode: false)
                    else
                      _miniLine(tr.text('status'),
                          tr.text('connection_state_disabled')),
                  ]
                : [
                    _readOnlyTransportLine(
                        context,
                        tr.text('status'),
                        _clientTransportStatusLabel(context,
                            active: cloudActive, configured: cloudConfigured),
                        cloudActive
                            ? Icons.check_circle_outline
                            : (cloudConfigured
                                ? Icons.lock_outline
                                : Icons.link_off_outlined)),
                  ],
          ),
        ],
      ),
    );
  }

  Widget _activeTransportSelector(BuildContext context,
      {required bool lanConfigured, required bool cloudConfigured}) {
    final tr = AppLocalizations.of(context);
    final canSwitchToLan = lanConfigured;
    final canSwitchToCloud = cloudConfigured && _cloudSyncPlanAllowsUi;
    final alternateConfigured =
        _clientSyncMode == SyncMode.lanOnly ? cloudConfigured : lanConfigured;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(tr.text('active_transport'),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800))),
                Tooltip(
                    message: alternateConfigured
                        ? tr.text('switch_transport_available')
                        : tr.text('switch_transport_locked'),
                    child: Icon(
                        alternateConfigured
                            ? Icons.swap_horiz_outlined
                            : Icons.lock_outline,
                        size: 20)),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<SyncMode>(
              segments: [
                ButtonSegment<SyncMode>(
                    value: SyncMode.lanOnly,
                    icon: const Icon(Icons.lan_outlined),
                    label: Text(tr.text('lan')),
                    enabled: canSwitchToLan),
                ButtonSegment<SyncMode>(
                    value: SyncMode.cloudConnected,
                    icon: const Icon(Icons.cloud_outlined),
                    label: Text(tr.text('cloud')),
                    enabled: canSwitchToCloud),
              ],
              selected: {_clientSyncMode},
              onSelectionChanged: _busy
                  ? null
                  : (value) {
                      final next = value.first;
                      if (next == SyncMode.lanOnly && !lanConfigured) return;
                      if (next == SyncMode.cloudConnected && !cloudConfigured) {
                        return;
                      }
                      setState(() => _clientSyncMode = next);
                    },
            ),
            const SizedBox(height: 8),
            Text(
                alternateConfigured
                    ? tr.text('active_transport_desc')
                    : tr.text('active_transport_locked_desc'),
                style: Theme.of(context).textTheme.bodySmall),
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
      title: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: color.onSurfaceVariant)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: (active ? accent : color.onSurfaceVariant)
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999)),
            child: Text(
                active
                    ? tr.text('connection_state_active')
                    : (configured
                        ? tr.text('connection_state_disabled')
                        : tr.text('connection_state_not_configured')),
                style: TextStyle(
                    color: active ? accent : color.onSurfaceVariant,
                    fontWeight: FontWeight.w700)),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
          const Icon(Icons.expand_more),
        ],
      ),
      children: children,
    );
  }

  Widget _readOnlyTransportLine(
      BuildContext context, String title, String value, IconData icon) {
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
          SizedBox(
              width: VentioResponsive.adaptiveWidth(context,
                  mobile: 105, tablet: 135, desktop: 150),
              child: Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: color.onSurfaceVariant))),
          const SizedBox(width: 8),
          Expanded(
              child: SelectableText(value,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700))),
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

  Widget _plainSyncPanel(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      required Widget child}) {
    final color = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
        color: color.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.outlineVariant.withValues(alpha: 0.75)),
        boxShadow: [
          BoxShadow(
              color: color.shadow.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 8))
        ],
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
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: color.onSurfaceVariant)),
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

  Widget _compactStatusChip(
      BuildContext context, IconData icon, String label, Color accent) {
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
          Text(label,
              style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _simpleInfoRow(BuildContext context, String label, String value,
      IconData icon, Color accent) {
    final color = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: color.surfaceContainerHighest.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          CircleAvatar(
              radius: 18,
              backgroundColor: accent.withValues(alpha: 0.12),
              foregroundColor: accent,
              child: Icon(icon, size: 18)),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: color.onSurfaceVariant)),
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: accent, fontWeight: FontWeight.w800)),
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
        border: Border.all(
            color: changed
                ? color.primary.withValues(alpha: 0.35)
                : color.outlineVariant),
        boxShadow: [
          BoxShadow(
              color: color.shadow.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, -4))
        ],
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
      decoration: BoxDecoration(
          color: color.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_busy
              ? (_status.isEmpty ? tr.text('working') : _status)
              : (_status.isEmpty ? _humanStatus(context) : _status)),
          if (_busy) ...[
            const SizedBox(height: 8),
            UnifiedSnapshotProgressView(
              value: _statusProgress,
              label: _status.isEmpty ? tr.text('working') : _status,
            ),
          ],
        ],
      ),
    );
  }

  Widget _pairingContent(BuildContext context,
      {required bool isHost, required bool isCloudClient}) {
    final tr = AppLocalizations.of(context);
    if (isHost) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                  onPressed: _busy ? null : _handleLanPairingButton,
                  icon: const Icon(Icons.lan_outlined),
                  label: Text(_lanPairingButtonLabel)),
              OutlinedButton.icon(
                  onPressed: _busy ? null : _handleCloudPairingButton,
                  icon: const Icon(Icons.cloud_queue_outlined),
                  label: Text(_cloudPairingButtonLabel)),
            ],
          ),
          if (_showLanPairingCode) ...[
            const SizedBox(height: 12),
            _lanPairingCodeCard()
          ],
          if (_showCloudPairingCode) ...[
            const SizedBox(height: 12),
            _cloudPairingCodeCard()
          ],
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
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _miniLine(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Expanded(child: Text(title)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600))
      ]),
    );
  }

  Widget _softNotice(
      BuildContext context, IconData icon, String title, String value) {
    final color = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: color.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(icon),
        const SizedBox(width: 10),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(value)
            ]))
      ]),
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
    final storeId =
        notice['storeId']?.toString() ?? widget.store.appIdentity.storeId;
    final branchId =
        notice['branchId']?.toString() ?? widget.store.appIdentity.branchId;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(AppLocalizations.of(context)
                .text('host_changed_notification')
                .replaceAll('{storeId}', storeId)
                .replaceAll('{branchId}', branchId)
                .replaceAll('{deviceId}', newHostDeviceId)),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).text('dismiss'),
            onPressed: _busy
                ? null
                : () {
                    widget.store.clearHostTransferNotification();
                  },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _transferHostCard({required bool isHost}) {
    final tr = AppLocalizations.of(context);
    final pending = widget.store.pendingHostTransferRequest;
    final approvedForThisDevice =
        widget.store.approvedHostTransferDeviceId == widget.store.deviceId;
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
              Expanded(
                  child: Text(tr.text('transfer_host_role'),
                      style: Theme.of(context).textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 8),
          if (isHost) ...[
            Text(tr.text('transfer_host_role_desc')),
            const SizedBox(height: 8),
            if (pending != null) ...[
              Text(tr.text('latest_request').replaceAll(
                  '{deviceId}',
                  (pending['requestingDeviceId'] ?? tr.text('unknown_device'))
                      .toString())),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => setState(() => _transferDeviceController.text =
                        (pending['requestingDeviceId'] ?? '').toString()),
                icon: const Icon(Icons.input_outlined),
                label: Text(tr.text('use_latest_request')),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _transferDeviceController,
              decoration: InputDecoration(
                  labelText: tr.text('client_device_id_to_approve'),
                  border: const OutlineInputBorder()),
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
            Text(tr
                .text('this_client_device_id')
                .replaceAll('{deviceId}', widget.store.deviceId)),
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
                onPressed: _busy || !approvedForThisDevice
                    ? null
                    : _activateApprovedHostTransferFromUi,
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: Text(tr.text('activate_approved_host_transfer')),
              ),
            ),
            if (!approvedForThisDevice)
              Padding(
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
        : (_hostIpAddresses.isEmpty
            ? tr.text('no_local_ipv4')
            : _hostIpAddresses.join('  •  '));
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
                Text(tr.text('host_ip_address'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(ipText),
                const SizedBox(height: 4),
                Text(tr.text('host_ip_desc')),
              ],
            ),
          ),
          IconButton(
            tooltip: tr.text('refresh_ip'),
            onPressed:
                _busy || _detectingHostIp ? null : _refreshHostIpAddresses,
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
    if (!expiresAt.isAfter(DateTime.now())) {
      return _PairingCodeVisualStatus.expired;
    }
    return _PairingCodeVisualStatus.active;
  }

  ({String label, IconData icon, Color background, Color foreground})
      _pairingStatusData(
    BuildContext context,
    _PairingCodeVisualStatus status,
  ) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    return switch (status) {
      _PairingCodeVisualStatus.active => (
          label: tr.text('connection_state_active'),
          icon: Icons.check_circle_outline,
          background: Colors.green.withValues(alpha: 0.12),
          foreground: Colors.green.shade700
        ),
      _PairingCodeVisualStatus.expired => (
          label: tr.text('pairing_status_expired'),
          icon: Icons.timer_off_outlined,
          background: Colors.grey.withValues(alpha: 0.16),
          foreground: color.onSurfaceVariant
        ),
      _PairingCodeVisualStatus.consumed => (
          label: tr.text('pairing_status_consumed'),
          icon: Icons.done_all_outlined,
          background: Colors.green.withValues(alpha: 0.12),
          foreground: Colors.green.shade700
        ),
      _PairingCodeVisualStatus.invalid => (
          label: tr.text('pairing_status_invalid'),
          icon: Icons.error_outline,
          background: color.errorContainer,
          foreground: color.onErrorContainer
        ),
      _PairingCodeVisualStatus.disabled => (
          label: tr.text('pairing_status_disabled'),
          icon: Icons.block_outlined,
          background: Colors.grey.withValues(alpha: 0.16),
          foreground: color.onSurfaceVariant
        ),
    };
  }

  Widget _pairingStatusBadge(
      BuildContext context, _PairingCodeVisualStatus status) {
    final data = _pairingStatusData(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: data.background, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon, size: 16, color: data.foreground),
          const SizedBox(width: 6),
          Text(data.label,
              style: TextStyle(
                  color: data.foreground, fontWeight: FontWeight.w700)),
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
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(letterSpacing: value.length > 12 ? 0.8 : 0),
      ),
    );
  }

  Color _pairingBorderColor(
      BuildContext context, _PairingCodeVisualStatus status) {
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
    final host = _lanHostController.text.trim().isNotEmpty
        ? _lanHostController.text.trim()
        : LanSyncSettings.load().host;
    final status = _pairingVisualStatus(
        code: code,
        expiresAt: _latestLanPairingExpiresAt,
        consumed: _latestLanPairingConsumed);
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
      if (identity.cloudTenantId.trim().isNotEmpty)
        'cloudTenantId': identity.cloudTenantId,
      'expiresAt': _latestLanPairingExpiresAt?.toIso8601String(),
    });
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: VentioResponsive.pageInsets(context),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: borderColor.withValues(alpha: 0.65), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_2_outlined),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(tr.text('lan_one_time_pairing_code'),
                      style: Theme.of(context).textTheme.titleMedium)),
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
                ? tr.format('expires_in',
                    {'time': _countdownText(_latestLanPairingExpiresAt)})
                : tr.format('pairing_code_state_help', {
                    'status':
                        _pairingStatusData(context, status).label.toLowerCase()
                  }),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _manualPairingValueTile(
              label: tr.text('host_ip_address'),
              value: host,
              copiedMessage: tr.text('copied_to_clipboard')),
          const SizedBox(height: 10),
          _manualPairingValueTile(
              label: tr.text('port'),
              value: _lanPort.toString(),
              copiedMessage: tr.text('copied_to_clipboard')),
          const SizedBox(height: 10),
          _manualPairingValueTile(
              label: tr.text('pairing_token'),
              value: code,
              copiedMessage: tr.text('lan_pairing_code_copied')),
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
    final status = _pairingVisualStatus(
        code: code,
        expiresAt: _latestCloudPairingExpiresAt,
        consumed: _latestCloudPairingConsumed,
        invalid: _latestCloudPairingInvalid);
    final borderColor = _pairingBorderColor(context, status);
    final expiresText = status == _PairingCodeVisualStatus.active
        ? tr.format('expires_in',
            {'time': _countdownText(_latestCloudPairingExpiresAt)})
        : tr.format('pairing_code_state_help', {
            'status': _pairingStatusData(context, status).label.toLowerCase()
          });
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: VentioResponsive.pageInsets(context),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: borderColor.withValues(alpha: 0.65), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_2_outlined),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(tr.text('cloud_pairing_code'),
                      style: Theme.of(context).textTheme.titleMedium)),
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
                  'pairingCode': code,
                  'storeId': widget.store.appIdentity.storeId,
                  'branchId': widget.store.appIdentity.branchId,
                  'hostDeviceId': widget.store.deviceId,
                  if (widget.store.appIdentity.cloudTenantId.trim().isNotEmpty)
                    'cloudTenantId': widget.store.appIdentity.cloudTenantId,
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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _manualPairingValueTile(
              label: tr.text('cloud_pairing_code'),
              value: code,
              copiedMessage: tr.text('cloud_pairing_code_copied')),
        ],
      ),
    );
  }

  List<Widget> _lanFields(
          {required bool showHostIp,
          bool forHost = false,
          bool dialogBusy = false}) =>
      [
        if (showHostIp)
          TextField(
              enabled: !dialogBusy,
              controller: _lanHostController,
              decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)
                      .text('manual_host_ip_optional'),
                  border: const OutlineInputBorder())),
        if (showHostIp) const SizedBox(height: 12),
        TextField(
            enabled: !dialogBusy,
            controller: _lanPortController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: AppLocalizations.of(context).text('port'),
                border: const OutlineInputBorder())),
        const SizedBox(height: 12),
        if (!forHost) ...[
          TextField(
            controller: _lanTokenController,
            decoration: InputDecoration(
              labelText:
                  AppLocalizations.of(context).text('lan_pairing_code_label'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ];

  List<Widget> _cloudFields({required bool showPairingCode}) => [
        if (showPairingCode)
          TextField(
            controller: _cloudPairingCodeController,
            decoration: InputDecoration(
              labelText:
                  AppLocalizations.of(context).text('pairing_code_from_host'),
              border: const OutlineInputBorder(),
            ),
          ),
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
  Future<_CloudMonitoringSnapshot>? _cloudMonitoringFuture;

  @override
  void initState() {
    super.initState();
    _refreshCloudDevices();
  }

  void _refreshCloudDevices() {
    final cloudSettings = CloudSyncSettings.load();
    if (widget.store.appIdentity.isHost && cloudSettings.isConfigured) {
      _cloudMonitoringFuture = _loadAndAdoptCloudDevices(cloudSettings)
          .catchError((_) => const _CloudMonitoringSnapshot(
                devices: <CloudDeviceStatus>[],
              ));
    } else {
      _cloudMonitoringFuture = Future<_CloudMonitoringSnapshot>.value(
        _CloudMonitoringSnapshot(
          devices: const <CloudDeviceStatus>[],
          limit: widget.store.appIdentity.isHost
              ? _localClientDeviceLimitStatus(
                  widget.store,
                  LanSyncSettings.load(),
                )
              : null,
        ),
      );
    }
  }

  Future<_CloudMonitoringSnapshot> _loadAndAdoptCloudDevices(
      CloudSyncSettings cloudSettings) async {
    final service = CloudSyncService(widget.store);
    var result = await service.listDevicesWithLimit(cloudSettings);
    var devices = result.devices;
    final repaired = await _repairLegacyCloudDeviceLinks(
        service, cloudSettings, result.devices);
    if (repaired) {
      result = await service.listDevicesWithLimit(cloudSettings);
      devices = result.devices;
    }
    await _adoptCloudRegistryDevices(devices);
    return _CloudMonitoringSnapshot(
      devices: devices,
      limit: result.limit ??
          _localClientDeviceLimitStatus(widget.store, LanSyncSettings.load()),
    );
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

    final settings =
        LanSyncSettings.load().withMigratedHostRegistry(hostDeviceId);
    final trustedDeviceIds = <String>{
      ...settings.hostRegistry.keys
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty),
      ...settings.pairedDevices.keys
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty),
    }..remove(hostDeviceId);
    if (trustedDeviceIds.isEmpty) return false;

    final repairIds = devices
        .where((device) {
          final deviceId = device.deviceId.trim();
          if (deviceId.isEmpty || deviceId == hostDeviceId) return false;
          if (!trustedDeviceIds.contains(deviceId)) return false;
          if (device.revoked || device.role.trim().toLowerCase() == 'host') {
            return false;
          }
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

  Future<void> _adoptCloudRegistryDevices(
      List<CloudDeviceStatus> devices) async {
    final identity = widget.store.appIdentity;
    if (!identity.isHost) return;
    final hostDeviceId = widget.store.deviceId.trim();
    if (hostDeviceId.isEmpty) return;

    final loadedSettings = LanSyncSettings.load();
    var settings = loadedSettings.withMigratedHostRegistry(hostDeviceId);
    var changed =
        settings.hostRegistry.length != loadedSettings.hostRegistry.length;

    for (final device in devices) {
      final clientDeviceId = device.deviceId.trim();
      if (clientDeviceId.isEmpty || clientDeviceId == hostDeviceId) continue;
      if (device.revoked || device.role.trim().toLowerCase() == 'host') {
        continue;
      }

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
          deviceName:
              cloudDeviceName.isNotEmpty ? cloudDeviceName : before.deviceName,
          lastSeenAt: device.lastSeenAt ?? before.lastSeenAt,
        );
        registry[clientDeviceId] = updated;
        settings = settings.copyWith(hostRegistry: Map.unmodifiable(registry));
        if (updated.deviceName != before.deviceName ||
            updated.lastSeenAt != before.lastSeenAt) {
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
    final snapshot = await (_cloudMonitoringFuture ??
        Future<_CloudMonitoringSnapshot>.value(
            const _CloudMonitoringSnapshot(devices: <CloudDeviceStatus>[])));
    await _finalizeCloudWipeAcknowledgements(snapshot.devices);
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

  Future<void> _permanentlyDeleteDeviceRecord(String deviceId,
      {String deviceToken = ''}) async {
    final id = deviceId.trim();
    if (id.isEmpty) return;
    final lanSettings = LanSyncSettings.load();
    final registryDevice = lanSettings.hostRegistry[id];
    final token = (deviceToken.trim().isNotEmpty
            ? deviceToken
            : (lanSettings.pairedDevices[id] ??
                registryDevice?.deviceToken ??
                ''))
        .trim();
    final paired = Map<String, String>.from(lanSettings.pairedDevices)
      ..remove(id);
    final registry =
        Map<String, HostRegistryDevice>.from(lanSettings.hostRegistry)
          ..remove(id);
    await lanSettings
        .copyWith(pairedDevices: paired, hostRegistry: registry)
        .save();
    await SyncDeviceStateStore.removePeerState(id);
    await SyncDeviceAccessStore.markDeleted(id, deviceToken: token);
  }

  Future<void> _finalizeCloudWipeAcknowledgements(
      List<CloudDeviceStatus> cloudDevices) async {
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
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(tr.text('cancel'))),
          FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(tr.text('delete'))),
        ],
      ),
    );
    if (confirmed != true) return;

    final lanSettings = LanSyncSettings.load();
    final registryDevice = lanSettings.hostRegistry[deviceId];
    final deletedDeviceToken = (lanSettings.pairedDevices[deviceId] ??
            registryDevice?.deviceToken ??
            '')
        .trim();

    await SyncDeviceAccessStore.markWipePending(deviceId,
        deviceToken: deletedDeviceToken);

    final cloudSettings = CloudSyncSettings.load();
    if (cloudSettings.isConfigured) {
      await CloudSyncService(widget.store)
          .revokeDevice(cloudSettings, deviceId);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr.text('sync_wipe_pending'))));
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
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(tr.text('cancel'))),
          FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(tr.text('permanent_delete'))),
        ],
      ),
    );
    if (confirmed != true) return;

    await _permanentlyDeleteDeviceRecord(deviceId);
    final cloudSettings = CloudSyncSettings.load();
    if (cloudSettings.isConfigured) {
      await CloudSyncService(widget.store)
          .deleteDeviceRecord(cloudSettings, deviceId);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('sync_device_permanently_deleted'))));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final isHost = widget.store.appIdentity.isHost;
    final lanSettings = LanSyncSettings.load();
    final cloudSettings = CloudSyncSettings.load();
    final peers = SyncDeviceStateStore.loadPeerStates();
    final peerById = <String, HostPeerSyncState>{
      for (final peer in peers) peer.deviceId: peer
    };
    final selfState = SyncDeviceStateStore.load(widget.store.appIdentity);

    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.monitor_heart_outlined),
        title: Text(tr.text('sync_monitoring_diagnostics')),
        subtitle: Text(isHost
            ? tr.text('sync_monitoring_host_desc')
            : tr.text('sync_monitoring_client_desc')),
        initiallyExpanded: false,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (isHost)
            FutureBuilder<_CloudMonitoringSnapshot>(
              future: _cloudMonitoringFuture,
              builder: (context, snapshot) => _HostSyncMonitoringTable(
                store: widget.store,
                cloudDevices:
                    snapshot.data?.devices ?? const <CloudDeviceStatus>[],
                deviceLimit: snapshot.data?.limit,
                peerStates: peerById,
                lanSettings: lanSettings,
                loadingCloudDevices:
                    snapshot.connectionState == ConnectionState.waiting,
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
    required this.deviceLimit,
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
  final CloudDeviceLimitStatus? deviceLimit;
  final Map<String, HostPeerSyncState> peerStates;
  final LanSyncSettings lanSettings;
  final bool loadingCloudDevices;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String deviceId, bool suspended) onToggleSuspend;
  final Future<void> Function(String deviceId) onDelete;
  final Future<void> Function(String deviceId) onPermanentDelete;

  @override
  State<_HostSyncMonitoringTable> createState() =>
      _HostSyncMonitoringTableState();
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
        if (entry.key.trim().isNotEmpty && entry.value.isActive)
          entry.key.trim(): entry.value,
    };
    final deviceIds = registryById.keys.toSet()
      ..removeWhere((id) => deleted.contains(id));
    final pairedDeviceIds = deviceIds.toList()..sort();
    final limitPanel = _deviceLimitPanel(context, pairedDeviceIds.length);

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
          if (limitPanel != null) ...[
            const SizedBox(height: 12),
            limitPanel,
          ],
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr.text('no_paired_devices_yet'),
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                      onPressed: widget.onRefresh,
                      icon: const Icon(Icons.refresh),
                      label: Text(tr.text('refresh'))),
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
        if (limitPanel != null) ...[
          const SizedBox(height: 12),
          limitPanel,
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: Text(tr.text('sync_monitoring_source_hint'),
                    style: Theme.of(context).textTheme.bodySmall)),
            IconButton(
                tooltip: tr.text('refresh'),
                onPressed: widget.onRefresh,
                icon: const Icon(Icons.refresh)),
          ],
        ),
        if (widget.loadingCloudDevices)
          const LinearProgressIndicator(minHeight: 2),
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
                      lanAuthorized: widget.lanSettings.pairedDevices
                              .containsKey(deviceId) ||
                          ((registryById[deviceId]
                                      ?.deviceToken
                                      .trim()
                                      .isNotEmpty ??
                                  false) &&
                              registryById[deviceId]?.source !=
                                  'cloud_pairing_claim'),
                      cloudDevice: cloudById[deviceId],
                      suspended: suspended.contains(deviceId),
                      wipePending: wipePending.contains(deviceId),
                      onToggleSuspend: () => widget.onToggleSuspend(
                          deviceId, suspended.contains(deviceId)),
                      onDelete: () => widget.onDelete(deviceId),
                      onPermanentDelete: () =>
                          widget.onPermanentDelete(deviceId),
                    ),
                ],
              );
            }
            return Scrollbar(
              controller: _tableScrollController,
              thumbVisibility: true,
              trackVisibility: true,
              notificationPredicate: (notification) =>
                  notification.metrics.axis == Axis.horizontal,
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
                        lanAuthorized: widget.lanSettings.pairedDevices
                                .containsKey(deviceId) ||
                            ((registryById[deviceId]
                                        ?.deviceToken
                                        .trim()
                                        .isNotEmpty ??
                                    false) &&
                                registryById[deviceId]?.source !=
                                    'cloud_pairing_claim'),
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

  Widget? _deviceLimitPanel(BuildContext context, int localLinkedClients) {
    final limit = widget.deviceLimit;
    if (limit == null) return null;
    final theme = Theme.of(context);
    final linked = limit.linked;
    final available = limit.available;
    final reached = limit.limitReached;
    final tr = AppLocalizations.of(context);
    final message = linked == 0
        ? tr.text('device_limit_no_devices')
        : reached
            ? tr.text('device_limit_reached')
            : tr.format('device_limit_available', {
                'count': available,
                'plural': available == 1 ? '' : 's',
              });
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: reached
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.35)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: reached
              ? theme.colorScheme.error.withValues(alpha: 0.45)
              : theme.dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              Text(tr.format('device_limit_allowed', {'count': limit.allowed})),
              Text(tr.format('device_limit_linked', {'count': linked})),
              Text(tr.format('device_limit_slots', {'count': available})),
              if (localLinkedClients != linked)
                Text(tr.format(
                    'device_limit_local_list', {'count': localLinkedClients})),
            ],
          ),
        ],
      ),
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
    final connection = _connectionStatusForHostPeer(context,
        state: state,
        cloudDevice: cloudDevice,
        suspended: suspended,
        wipePending: wipePending);
    final status = _syncStatusForHostPeer(context, state,
        lanAuthorized: lanAuthorized,
        cloudDevice: cloudDevice,
        suspended: suspended,
        wipePending: wipePending);
    return DataRow(
      cells: [
        DataCell(Text(_deviceLabel(context, deviceId,
            registryDevice: registryDevice, cloudDevice: cloudDevice))),
        DataCell(Text(_activeTransportForHostPeer(context,
            lanAuthorized: lanAuthorized,
            cloudDevice: cloudDevice,
            state: state))),
        DataCell(_StatusChip(
            label: connection.label,
            color: connection.color,
            icon: connection.icon)),
        DataCell(_StatusChip(
            label: status.label, color: status.color, icon: status.icon)),
        DataCell(Text(_formatDateTime(
            context,
            _lastSuccessfulSyncForHostPeer(
                state: state, cloudDevice: cloudDevice)))),
        DataCell(Text(_pendingChangesForHostPeer(context,
            store: widget.store,
            deviceId: deviceId,
            state: state,
            cloudDevice: cloudDevice))),
        DataCell(Text(
            '${state?.lastAckSequence ?? cloudDevice?.lastAckSequence ?? 0}')),
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
                onPressed: wipePending
                    ? null
                    : () => widget.onToggleSuspend(deviceId, suspended),
                child:
                    Text(suspended ? tr.text('resume') : tr.text('suspend'))),
            TextButton(
              onPressed: wipePending
                  ? () => widget.onPermanentDelete(deviceId)
                  : () => widget.onDelete(deviceId),
              child: Text(wipePending
                  ? tr.text('permanent_delete')
                  : tr.text('delete')),
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
              Text(tr.text('host_status'),
                  style: Theme.of(context).textTheme.titleSmall),
              _StatusChip(
                  label: tr.text('host'),
                  color: Theme.of(context).colorScheme.primary,
                  icon: Icons.home_work_outlined),
              if (lanReady)
                _StatusChip(
                    label:
                        '${tr.text('connection_lan')}: ${tr.text('connection_state_active')}',
                    color: Colors.green,
                    icon: Icons.lan_outlined),
              if (cloudReady)
                _StatusChip(
                    label:
                        '${tr.text('connection_cloud')}: ${tr.text('connection_state_active')}',
                    color: Colors.blue,
                    icon: Icons.cloud_done_outlined),
              if (!lanReady && !cloudReady)
                _StatusChip(
                    label: tr.text('connection_state_not_configured'),
                    color: Theme.of(context).colorScheme.error,
                    icon: Icons.link_off_outlined),
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
    final connection = _connectionStatusForHostPeer(context,
        state: state,
        cloudDevice: cloudDevice,
        suspended: suspended,
        wipePending: wipePending);
    final status = _syncStatusForHostPeer(context, state,
        lanAuthorized: lanAuthorized,
        cloudDevice: cloudDevice,
        suspended: suspended,
        wipePending: wipePending);
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
              Expanded(
                  child: Text(
                      _deviceLabel(context, deviceId,
                          registryDevice: registryDevice,
                          cloudDevice: cloudDevice),
                      style: Theme.of(context).textTheme.titleSmall)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _StatusChip(
                label: connection.label,
                color: connection.color,
                icon: connection.icon),
            _StatusChip(
                label: status.label, color: status.color, icon: status.icon),
          ]),
          const SizedBox(height: 12),
          _Line(
              title: tr.text('active_transport'),
              value: _activeTransportForHostPeer(context,
                  lanAuthorized: lanAuthorized,
                  cloudDevice: cloudDevice,
                  state: state)),
          _Line(title: tr.text('connection_status'), value: connection.label),
          _Line(title: tr.text('sync_status'), value: status.label),
          _Line(
              title: tr.text('last_successful_sync'),
              value: _formatDateTime(
                  context,
                  _lastSuccessfulSyncForHostPeer(
                      state: state, cloudDevice: cloudDevice))),
          _Line(
              title: tr.text('pending_changes'),
              value: _pendingChangesForHostPeer(context,
                  store: store,
                  deviceId: deviceId,
                  state: state,
                  cloudDevice: cloudDevice)),
          _Line(
              title: tr.text('last_ack_sequence'),
              value:
                  '${state?.lastAckSequence ?? cloudDevice?.lastAckSequence ?? 0}'),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final fullWidth = constraints.maxWidth < 420;
              final suspendButton = OutlinedButton.icon(
                  onPressed: wipePending ? null : onToggleSuspend,
                  icon: Icon(suspended
                      ? Icons.play_arrow_outlined
                      : Icons.pause_circle_outline),
                  label:
                      Text(suspended ? tr.text('resume') : tr.text('suspend')));
              final deleteButton = OutlinedButton.icon(
                onPressed: wipePending ? onPermanentDelete : onDelete,
                icon: Icon(wipePending
                    ? Icons.delete_forever_outlined
                    : Icons.delete_outline),
                label: Text(wipePending
                    ? tr.text('permanent_delete')
                    : tr.text('delete')),
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
              return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [suspendButton, deleteButton]);
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
    final connection = _connectionStatusForClient(context,
        state: state, lanSettings: lanSettings, cloudSettings: cloudSettings);
    final status = _syncStatusForClient(context, state,
        pendingCount: store.activeClientPendingSyncCount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                _StatusChip(
                    label: connection.label,
                    color: connection.color,
                    icon: connection.icon),
                _StatusChip(
                    label: status.label,
                    color: status.color,
                    icon: status.icon),
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
        _Line(
            title: tr.text('active_transport'),
            value: _transportLabel(
                context,
                state.activeTransport.isNotEmpty
                    ? state.activeTransport
                    : store.appIdentity.activeSyncTransport)),
        _Line(title: tr.text('connection_status'), value: connection.label),
        _Line(title: tr.text('sync_status'), value: status.label),
        _Line(
            title: tr.text('last_successful_sync'),
            value:
                _formatDateTime(context, _lastSuccessfulSyncForClient(state))),
        _Line(
            title: tr.text('pending_changes'),
            value: '${store.activeClientPendingSyncCount}'),
        _Line(
            title: tr.text('last_ack_sequence'),
            value: '${state.lastAckSequence}'),
      ],
    );
  }
}

class _SettingsNavData {
  const _SettingsNavData(
      {required this.icon, required this.label, required this.description});

  final IconData icon;
  final String label;
  final String description;
}

class _SettingsSection {
  const _SettingsSection({required this.nav, required this.page});

  final _SettingsNavData nav;
  final Widget page;
}

class _SettingsSideNav extends StatelessWidget {
  const _SettingsSideNav(
      {required this.items,
      required this.selectedIndex,
      required this.onSelected,
      required this.store});

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
  const _SettingsNavItem(
      {required this.item, required this.selected, required this.onTap});

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
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.45)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.14)
                  : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(item.icon,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: selected ? colorScheme.primary : null,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(item.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 20,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _VentioBrandHeader extends StatelessWidget {
  const _VentioBrandHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.55),
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1218),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                'assets/branding/ventio_app_icon_1024.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.storefront_outlined,
                  color: colorScheme.primary,
                  size: 34,
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowsUpdateStatusCard extends StatefulWidget {
  const _WindowsUpdateStatusCard();

  @override
  State<_WindowsUpdateStatusCard> createState() =>
      _WindowsUpdateStatusCardState();
}

class _WindowsUpdateStatusCardState extends State<_WindowsUpdateStatusCard> {
  late final AppUpdateService _service = getAppUpdateService();
  late final VoidCallback _updateStatusListener;
  VoidCallback? _cancelDownload;
  AppUpdateInfo? _latest;
  DateTime? _lastCheckedAt;
  bool _checking = false;
  bool _downloading = false;
  bool _installing = false;
  double? _downloadProgress;
  String? _downloadedInstallerPath;
  String _statusKey = 'you_are_up_to_date';
  String _statusValue = '';

  @override
  void initState() {
    super.initState();
    _updateStatusListener = () {
      if (!mounted) return;
      final state = AppUpdateService.status.value;
      setState(() {
        _latest = state.latest;
        _lastCheckedAt = state.lastCheckedAt;
        _checking = state.checking;
        _downloading = state.downloading;
        _installing = state.installing;
        _downloadProgress = state.downloadProgress;
        _downloadedInstallerPath = state.downloadedInstallerPath;
        if (state.lastError.isNotEmpty && !_downloading && !_installing) {
          _statusKey = 'could_not_check_updates';
          _statusValue = '';
        } else if (_installing) {
          _statusKey = 'installing_update';
          _statusValue = '';
        } else if (_downloading) {
          _statusKey = 'downloading';
          _statusValue = _latest?.displayVersion ?? '';
        } else if (_readyToInstall) {
          _statusKey = 'update_downloaded';
          _statusValue = _latest?.displayVersion ?? '';
        } else if (_hasUpdate) {
          _statusKey = 'update_available';
          _statusValue = _latest?.displayVersion ?? '';
        } else {
          _statusKey = 'you_are_up_to_date';
          _statusValue = '';
        }
      });
    };
    AppUpdateService.status.addListener(_updateStatusListener);
    _updateStatusListener();
  }

  @override
  void dispose() {
    AppUpdateService.status.removeListener(_updateStatusListener);
    super.dispose();
  }

  bool get _hasUpdate =>
      _latest?.isNewerThan(AppBrand.versionName, AppBrand.buildNumber) ?? false;

  bool get _readyToInstall => _downloadedInstallerPath != null;

  bool get _isBusy => _downloading || _installing;

  String _lastCheckedText(AppLocalizations tr) {
    final value = _lastCheckedAt;
    if (value == null) return tr.text('last_checked_not_checked');
    final local = value.toLocal();
    final date = DateFormat('MMM d, h:mm a').format(local);
    return tr.format('last_checked_at', {'time': date});
  }

  Future<void> _check() async {
    if (_checking) return;
    final tr = AppLocalizations.of(context);
    final previousUpdate = _latest;
    setState(() {
      _checking = true;
      _statusKey = 'checking_for_updates';
      _statusValue = '';
    });
    try {
      final latest = await _service.fetchLatest();
      if (!mounted) return;
      setState(() {
        _latest = latest;
        _lastCheckedAt = DateTime.now();
        final updateChanged =
            previousUpdate?.displayVersion != latest?.displayVersion;
        if (latest == null || updateChanged) {
          _downloadedInstallerPath = null;
          _downloadProgress = null;
          _downloading = false;
          _installing = false;
        }
        _statusKey = _hasUpdate ? 'update_available' : 'you_are_up_to_date';
        _statusValue = latest?.displayVersion ?? '';
      });
      if (latest != null) {
        final restoredPath = await _service.getDownloadedInstallerPath(latest);
        if (!mounted) return;
        setState(() {
          _downloadedInstallerPath = restoredPath;
          if (restoredPath == null) {
            _downloadProgress = null;
            _downloading = false;
            _installing = false;
          } else {
            _statusKey = 'update_downloaded';
          }
        });
      } else {
        await _service.clearDownloadedUpdate();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _lastCheckedAt = DateTime.now();
        _statusKey = 'could_not_check_updates';
        _statusValue = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                tr.format('update_check_failed', {'error': error.toString()}))),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _downloadUpdate() async {
    final update = _latest;
    if (update == null || !_hasUpdate) return;
    if (_isBusy) return;
    final tr = AppLocalizations.of(context);
    _cancelDownload = null;
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _statusKey = 'downloading';
      _statusValue = update.displayVersion;
    });
    try {
      final installerPath = await _service.downloadUpdate(
        update,
        onProgress: (value) {
          if (!mounted) return;
          setState(() => _downloadProgress = value);
        },
        registerCancel: (cancel) => _cancelDownload = cancel,
      );
      if (!mounted) return;
      setState(() {
        _downloadedInstallerPath = installerPath;
        _downloading = false;
        _downloadProgress = 1;
        _statusKey = 'update_downloaded';
        _statusValue = update.displayVersion;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('update_downloaded'))),
      );
    } catch (error) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      setState(() {
        _downloading = false;
        _downloadProgress = null;
      });
      if (error.toString().contains('Update download cancelled')) {
        return;
      }
      await _service.clearDownloadedUpdate();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
            content:
                Text(tr.format('update_failed', {'error': error.toString()}))),
      );
    }
  }

  Future<void> _installReadyUpdate() async {
    await _installUpdate();
  }

  Future<void> _installUpdate() async {
    final installerPath = _downloadedInstallerPath;
    if (installerPath == null || installerPath.trim().isEmpty || _installing) {
      return;
    }
    final tr = AppLocalizations.of(context);
    setState(() {
      _installing = true;
      _downloadProgress = null;
      _statusKey = 'installing_update';
      _statusValue = '';
    });
    try {
      await _service.launchInstaller(installerPath);
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      SystemNavigator.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _installing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(tr.format('update_failed', {'error': error.toString()}))),
      );
    }
  }

  Future<void> _cancelDownloadUpdate() async {
    if (!_downloading) return;
    final cancel = _cancelDownload;
    _cancelDownload = null;
    cancel?.call();
    await _service.clearDownloadedUpdate();
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _downloadProgress = null;
      _statusKey = _hasUpdate ? 'update_available' : 'you_are_up_to_date';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_service.isSupported) return const SizedBox.shrink();
    final tr = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = _readyToInstall
        ? Colors.green.shade700
        : _hasUpdate
            ? colorScheme.primary
            : Colors.blue.shade700;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 18),
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final showProgressRing = _downloading || _installing;
          final statusIcon = SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (showProgressRing)
                  SizedBox(
                    width: 76,
                    height: 76,
                    child: CircularProgressIndicator(
                      value: _installing ? null : _downloadProgress,
                      strokeWidth: 4,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(colorScheme.primary),
                    ),
                  ),
                Icon(Icons.sync_outlined, size: 40, color: iconColor),
                if (!showProgressRing)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: _readyToInstall
                            ? Colors.green
                            : colorScheme.primary,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: colorScheme.surface, width: 2),
                      ),
                      child: Icon(
                        _readyToInstall ? Icons.check : Icons.arrow_downward,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
              ],
            ),
          );
          final statusText = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (_statusKey == 'update_available' ||
                            _statusKey == 'update_downloaded') &&
                        _statusValue.isNotEmpty
                    ? '${tr.text(_statusKey)}: $_statusValue'
                    : tr.text(_statusKey),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                _lastCheckedText(tr),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              if (_downloading || _installing) ...[
                const SizedBox(height: 8),
                Text(
                  _installing
                      ? tr.text('installing_update')
                      : _downloadProgress == null
                          ? tr.text('downloading')
                          : '${tr.text('downloading')} ${(_downloadProgress! * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          );
          final action = _hasUpdate
              ? (_downloading
                  ? TextButton.icon(
                      onPressed: _cancelDownloadUpdate,
                      icon: const Icon(Icons.close),
                      label: Text(tr.text('cancel')),
                    )
                  : _readyToInstall
                      ? FilledButton.icon(
                          onPressed: _installing ? null : _installReadyUpdate,
                          icon: const Icon(Icons.check_circle_outline),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                          ),
                          label: Text(tr.text('update_now')),
                        )
                      : FilledButton.icon(
                          onPressed: _installing ? null : _downloadUpdate,
                          icon: const Icon(Icons.download_outlined),
                          label: Text(tr.text('install_update')),
                        ))
              : FilledButton(
                  onPressed: _checking ? null : _check,
                  child: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(tr.text('check_for_updates')),
                );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    statusIcon,
                    const SizedBox(width: 24),
                    Expanded(child: statusText),
                  ],
                ),
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            );
          }
          return Row(
            children: [
              statusIcon,
              const SizedBox(width: 24),
              Expanded(child: statusText),
              const SizedBox(width: 16),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _SystemStatusPanel extends StatelessWidget {
  const _SystemStatusPanel({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final identity = store.appIdentity;
    final lan = LanSyncSettings.load();
    final cloud = CloudSyncSettings.load();
    final transport = identity.activeSyncTransportNormalized;
    final lanConfigured = lan.setupComplete || lan.isHost || lan.isClient;
    final lanActive = transport == 'lan' && lanConfigured;
    final cloudActive = identity.isCloudEnabled && cloud.isConfigured;
    final pending = store.pendingSyncCount;

    final roleLabel = identity.isHost
        ? tr.text('host_device')
        : identity.isClient
            ? tr.text('client_device')
            : tr.text('local');

    final lanState = lanActive
        ? tr.text('connection_state_active')
        : lanConfigured
            ? tr.text('connection_state_disabled')
            : tr.text('connection_state_not_configured');

    final cloudState = cloudActive
        ? tr.text('connection_state_active')
        : identity.isCloudEnabled
            ? tr.text('connection_state_not_configured')
            : tr.text('connection_state_disabled');

    final syncState = pending > 0
        ? '${tr.text('connection_state_pending')} ($pending)'
        : (lanActive || cloudActive)
            ? tr.text('connection_state_active')
            : tr.text('connection_state_disabled');

    final healthy =
        pending == 0 && (lanActive || cloudActive || transport == 'local');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.verified_user_outlined,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(tr.text('system_status'),
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          _StatusBullet(
            label: roleLabel,
            state: _StatusBulletState.info,
          ),
          _StatusBullet(
            label: '${tr.text('connection_lan')}: $lanState',
            state: lanActive
                ? _StatusBulletState.ok
                : lanConfigured
                    ? _StatusBulletState.disabled
                    : _StatusBulletState.warning,
          ),
          _StatusBullet(
            label: '${tr.text('connection_cloud')}: $cloudState',
            state: cloudActive
                ? _StatusBulletState.ok
                : identity.isCloudEnabled
                    ? _StatusBulletState.warning
                    : _StatusBulletState.disabled,
          ),
          _StatusBullet(
            label: '${tr.text('connection_sync_health')}: $syncState',
            state: pending > 0
                ? _StatusBulletState.warning
                : (lanActive || cloudActive)
                    ? _StatusBulletState.ok
                    : _StatusBulletState.disabled,
          ),
          const Divider(height: 22),
          Text(
              healthy
                  ? tr.text('all_systems_are_running_smoothly')
                  : pending > 0
                      ? '${tr.text('pending_changes')}: $pending'
                      : '${tr.text('sync')}: ${tr.text('connection_state_disabled')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

enum _StatusBulletState { ok, warning, disabled, info }

class _StatusBullet extends StatelessWidget {
  const _StatusBullet(
      {required this.label, this.state = _StatusBulletState.ok});
  final String label;
  final _StatusBulletState state;

  Color _color(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (state) {
      case _StatusBulletState.ok:
        return Colors.green.shade600;
      case _StatusBulletState.warning:
        return Colors.orange.shade700;
      case _StatusBulletState.disabled:
        return scheme.onSurfaceVariant.withValues(alpha: 0.65);
      case _StatusBulletState.info:
        return scheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(Icons.circle, size: 9, color: _color(context)),
        const SizedBox(width: 10),
        Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.child,
      this.trailing});

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
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side:
              BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      child: Padding(
        padding: VentioResponsive.pageInsets(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon,
                    size: 28, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
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
  const _InfoTile(
      {required this.icon, required this.title, required this.value});

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.7)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 22, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 14),
          SizedBox(
              width: VentioResponsive.adaptiveWidth(context,
                  mobile: 120, tablet: 150, desktop: 170),
              child: Text(title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Expanded(
              child: Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600))),
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
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 560
                ? 2
                : 1;
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
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.28),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(item.icon,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(item.value,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w700)),
                                ),
                                if (item.onEdit != null) ...[
                                  const SizedBox(width: 8),
                                  IconButton.filledTonal(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: AppLocalizations.of(context)
                                        .text('edit'),
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 18),
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
              ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: VentioResponsive.adaptiveWidth(context,
                          mobile: 96, tablet: 120, desktop: 130)),
                  child: Text(title,
                      maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(value,
                      style: Theme.of(context).textTheme.titleSmall)),
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
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
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
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontFamily: 'monospace'),
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
  State<_KeyboardShortcutsSettingsCard> createState() =>
      _KeyboardShortcutsSettingsCardState();
}

class _KeyboardShortcutsSettingsCardState
    extends State<_KeyboardShortcutsSettingsCard> {
  late SaleShortcutSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = SaleShortcutSettings.load();
  }

  String _keyLabel(AppLocalizations tr, String keyName) {
    if (keyName == SaleShortcutSettings.noneKey) {
      return tr.text('shortcut_none');
    }
    return keyName;
  }

  Future<void> _setSaleShortcut(
      SaleShortcutAction action, String keyName) async {
    final tr = AppLocalizations.of(context);
    if (_settings.isSaleKeyUsedByAnotherAction(keyName, action)) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('shortcut_key_already_used'))));
      return;
    }
    final next = _settings.copyWithSaleActionKey(action, keyName);
    setState(() => _settings = next);
    await next.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr.text('shortcuts_saved'))));
  }

  Future<void> _setPaymentShortcut(
      SalePaymentShortcutAction action, String keyName) async {
    final tr = AppLocalizations.of(context);
    if (_settings.isPaymentKeyUsedByAnotherAction(keyName, action)) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('shortcut_key_already_used'))));
      return;
    }
    final next = _settings.copyWithPaymentActionKey(action, keyName);
    setState(() => _settings = next);
    await next.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr.text('shortcuts_saved'))));
  }

  Future<void> _setPurchasesShortcut(
      PurchasesShortcutAction action, String keyName) async {
    final tr = AppLocalizations.of(context);
    if (_settings.isPurchasesKeyUsedByAnotherAction(keyName, action)) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('shortcut_key_already_used'))));
      return;
    }
    final next = _settings.copyWithPurchasesActionKey(action, keyName);
    setState(() => _settings = next);
    await next.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr.text('shortcuts_saved'))));
  }

  Future<void> _setPurchaseDialogShortcut(
      PurchaseDialogShortcutAction action, String keyName) async {
    final tr = AppLocalizations.of(context);
    if (_settings.isPurchaseDialogKeyUsedByAnotherAction(keyName, action)) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('shortcut_key_already_used'))));
      return;
    }
    final next = _settings.copyWithPurchaseDialogActionKey(action, keyName);
    setState(() => _settings = next);
    await next.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr.text('shortcuts_saved'))));
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
        Text(tr.text('sale_page'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(tr.text('keyboard_shortcuts_sale_hint'),
            style: Theme.of(context).textTheme.bodySmall),
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
        Text(tr.text('shortcut_page_sale_payment'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(tr.text('keyboard_shortcuts_payment_hint'),
            style: Theme.of(context).textTheme.bodySmall),
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
        Text(tr.text('purchases'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(tr.text('keyboard_shortcuts_purchases_hint'),
            style: Theme.of(context).textTheme.bodySmall),
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
        Text(tr.text('shortcut_page_purchase_dialog'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(tr.text('keyboard_shortcuts_purchase_dialog_hint'),
            style: Theme.of(context).textTheme.bodySmall),
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
                  onChanged: (value) =>
                      _setPurchaseDialogShortcut(action, value),
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
    final controller =
        TextEditingController(text: widget.store.appIdentity.deviceName);
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
                  final value =
                      controller.text.trim().replaceAll(RegExp(r'\s+'), ' ');
                  if (value.isEmpty) {
                    setDialogState(
                        () => errorText = tr.text('device_name_empty'));
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
                    final value =
                        controller.text.trim().replaceAll(RegExp(r'\s+'), ' ');
                    if (value.isEmpty) {
                      setDialogState(
                          () => errorText = tr.text('device_name_empty'));
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
          transport:
              widget.store.appIdentity.activeSyncTransportNormalized == 'lan'
                  ? 'cloud'
                  : widget.store.appIdentity.activeSyncTransportNormalized,
        );
      }
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tr.text('device_name')} ${tr.text('save')}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
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
          _InfoGridItem(
              Icons.tag_outlined, tr.text('store_id'), identity.storeId),
          _InfoGridItem(
              Icons.business_outlined, tr.text('branch_id'), identity.branchId),
          _InfoGridItem(
              Icons.devices_outlined, tr.text('device_id'), identity.deviceId),
          _InfoGridItem(
              Icons.badge_outlined,
              tr.text('device_name'),
              identity.deviceName.trim().isEmpty
                  ? identity.deviceId
                  : identity.deviceName.trim(),
              onEdit: _editDeviceName),
          _InfoGridItem(Icons.computer_outlined, tr.text('platform'),
              identity.platform.name),
          _InfoGridItem(Icons.dns_outlined, tr.text('device_role'),
              identity.deviceRole.name),
          _InfoGridItem(
              Icons.badge_outlined, tr.text('app_role'), identity.appRole.name),
          _InfoGridItem(
              Icons.sync_outlined,
              tr.text('sync_mode'),
              identity.isHost
                  ? tr.text('host_lan_cloud_controlled')
                  : identity.syncMode.name),
          _InfoGridItem(Icons.cloud_outlined, tr.text('cloud_tenant'),
              identity.cloudTenantId.isEmpty ? '—' : identity.cloudTenantId),
        ],
      ),
    );
  }
}
