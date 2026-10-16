part of 'settings_page.dart';

extension _Sections on SettingsPage {
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
    final profile = store.runtime.profile;
    final displayName =
        profile.tradeName.trim().isNotEmpty ? profile.tradeName : profile.name;
    final legalName =
        profile.legalName.trim().isNotEmpty ? profile.legalName : profile.name;
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
          onPressed: store.security.hasPermission(AppPermission.settingsManage)
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
          onPressed: store.security.hasPermission(AppPermission.settingsManage)
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
          onPressed: store.security.hasPermission(AppPermission.settingsManage)
              ? () => _editOrganizationBranding(context, profile)
              : null,
          icon: const Icon(Icons.edit_outlined),
          label: Text(tr.text('edit')),
        ),
        child: Column(
          children: [
            _InfoTile(
                icon: Icons.image_outlined,
                title: tr.text('logo'),
                value: profile.logoDataBase64.isNotEmpty
                    ? (profile.logoFileName.isEmpty
                        ? tr.text('stored_in_database')
                        : profile.logoFileName)
                    : '—'),
            _InfoTile(
                icon: Icons.receipt_long_outlined,
                title: tr.text('invoice_footer'),
                value: profile.footerNote),
          ],
        ),
      ),
      _SectionCard(
        icon: Icons.inventory_2_outlined,
        title: tr.text('negative_stock_settings'),
        subtitle: tr.text('negative_stock_settings_desc'),
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(tr.text('allow_negative_stock')),
          subtitle: Text(tr.text('allow_negative_stock_desc')),
          value: profile.allowNegativeStock,
          onChanged: store.security.hasPermission(AppPermission.settingsManage)
              ? (value) async {
                  await store.runtime.updateStoreProfile(
                    profile.copyWith(allowNegativeStock: value),
                  );
                }
              : null,
        ),
      ),
      _SectionCard(
        icon: Icons.account_balance_wallet_outlined,
        title: tr.text('negative_cash_settings'),
        subtitle: tr.text('negative_cash_settings_desc'),
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(tr.text('allow_negative_cash_balance')),
          subtitle: Text(tr.text('allow_negative_cash_balance_desc')),
          value: profile.allowNegativeCashBalance,
          onChanged: store.security.hasPermission(AppPermission.settingsManage)
              ? (value) async {
                  await store.runtime.updateStoreProfile(
                    profile.copyWith(allowNegativeCashBalance: value),
                  );
                }
              : null,
        ),
      ),
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
                  ButtonSegment<Locale>(
                      value: const Locale('fr'),
                      label: Text(tr.text('language_french'))),
                ],
                selected: {tr.locale},
                onSelectionChanged: (selection) =>
                    onLocaleChanged(selection.first),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _aboutCards(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final identity = store.runtime.identity;
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
                    store.runtime.profile.name),
                _InfoGridItem(Icons.sync, tr.text('sync_mode'),
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
    final profile = store.runtime.profile;
    final docs = profile.documentNumbering;
    return [
      _SectionCard(
        icon: Icons.description_outlined,
        title: tr.text('document_settings'),
        subtitle: tr.text('document_settings_desc'),
        trailing: FilledButton.icon(
          onPressed: store.security.hasPermission(AppPermission.settingsManage)
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
    final profile = store.runtime.profile;
    final branches = profile.branches;
    return [
      _SectionCard(
        icon: Icons.account_tree_outlined,
        title: tr.text('branches'),
        subtitle: tr.text('branches_desc'),
        trailing: FilledButton.icon(
          onPressed: store.security.hasPermission(AppPermission.settingsManage)
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
                        onPressed: store.security
                                .hasPermission(AppPermission.settingsManage)
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

  String _costingMethodTitle(
      AppLocalizations tr, InventoryCostingMethod method) {
    switch (method) {
      case InventoryCostingMethod.fifo:
        return tr.text('fifo');
      case InventoryCostingMethod.lastPurchaseCost:
        return tr.text('last_cost');
      case InventoryCostingMethod.batch:
        return tr.text('unified_batch');
      case InventoryCostingMethod.weightedAverage:
        return tr.text('weighted_average_cost');
    }
  }

  Widget _inventoryCostingCard(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final method = store.inventory.inventoryCostingMethod;
    return _SectionCard(
      icon: Icons.inventory_2_outlined,
      title: tr.text('inventory_costing_method'),
      subtitle: tr.text('inventory_costing_method_desc'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(tr.text('unified_batch')),
            subtitle: Text(tr.text('unified_batch_fixed_desc')),
            trailing: const Icon(Icons.lock_outline),
          ),
          const SizedBox(height: 12),
          Text(
              '${tr.text('current_method')}: ${_costingMethodTitle(tr, method)}'),
          const SizedBox(height: 8),
          Text(
            tr.text('inventory_costing_method_note'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (store.catalog.costingMethodHistory.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(tr.text('history'),
                style: Theme.of(context).textTheme.titleSmall),
            for (final row
                in store.catalog.costingMethodHistory.reversed.take(5))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.timeline_outlined),
                title: Text(_costingMethodTitle(tr, row.method)),
                subtitle: Text(
                    '${DateFormat.yMd().add_Hm().format(row.effectiveFrom)}${row.effectiveTo == null ? ' → ${tr.text('active')}' : ' → ${DateFormat.yMd().add_Hm().format(row.effectiveTo!)}'}${row.reason.isEmpty ? '' : ' · ${row.reason}'}'),
              ),
          ],
        ],
      ),
    );
  }

  List<Widget> _financialCards(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final profile = store.runtime.profile;
    final activeCurrencies =
        profile.currencies.where((item) => item.isActive).toList();
    final base = profile.currencyByCode(profile.baseCurrency);
    final usdLbpRate =
        profile.latestExchangeRate('USD', 'LBP')?.rate ?? profile.usdToLbpRate;

    return [
      _SectionCard(
        icon: Icons.payments_outlined,
        title: tr.text('currencies_pricing'),
        subtitle: tr.text('currencies_pricing_desc'),
        trailing: FilledButton.icon(
          onPressed: store.security.hasPermission(AppPermission.settingsManage)
              ? () => _editFinancialSettings(context, profile)
              : null,
          icon: const Icon(Icons.edit_outlined),
          label: Text(tr.text('edit')),
        ),
        child: _InfoGrid(
          items: [
            _InfoGridItem(Icons.account_balance_outlined,
                tr.text('base_currency'), '${base.code} · ${base.name}'),
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
            _InfoGridItem(Icons.tune_outlined, tr.text('active_currencies'),
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
          onPressed: store.security.hasPermission(AppPermission.settingsManage)
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
                leading: CircleAvatar(
                    child: Text(currency.code.substring(0,
                        currency.code.length >= 2 ? 2 : currency.code.length))),
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
                      onPressed: store.security
                              .hasPermission(AppPermission.settingsManage)
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
      _SectionCard(
        icon: Icons.trending_up_outlined,
        title: tr.text('exchange_rates'),
        subtitle: tr.text('exchange_rates_desc'),
        trailing: FilledButton.icon(
          onPressed: store.security.hasPermission(AppPermission.settingsManage)
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
                  ..sort((a, b) => b.effectiveAt.compareTo(a.effectiveAt)))
                .take(12))
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
                  onPressed: store.security
                          .hasPermission(AppPermission.settingsManage)
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
    final isClient = store.runtime.identity.isClient;
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
              _BackupSummaryCard(summary: store.recovery.currentBackupSummary),
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
                      store.runtime.identity.hostDeviceId.trim().isNotEmpty;
                  final canRecoverStoreData =
                      store.security.hasPermission(AppPermission.syncManage);
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
                            onPressed:
                                (hasStoreIdentity && !canRecoverStoreData) ||
                                        !store.security.hasPermission(
                                            AppPermission.backupManage)
                                    ? null
                                    : () => _recoverExistingStore(context),
                            icon: Icon(recoverIcon),
                            label: Text(tr.text(recoverLabelKey)),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: OutlinedButton.icon(
                            onPressed: store.security.hasAnyPermission(<String>{
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
                            onPressed: store.security.hasAnyPermission(<String>{
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
                            onPressed: store.security.hasAnyPermission(<String>{
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
    final isHost = store.runtime.identity.isHost;
    final isClient = store.runtime.identity.isClient;
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
              onPressed:
                  store.security.hasPermission(AppPermission.databaseManage)
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
              onPressed: store.security.hasPermission(AppPermission.syncManage)
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
              onPressed: store.security.hasPermission(AppPermission.syncManage)
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
    if (!store.security.canManageUsers) {
      return [
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(tr.text('users_permissions')),
            subtitle: Text(tr.text('no_access_user_role_management')),
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
            'user':
                store.security.activeUser?.fullName ?? tr.text('unknown_user'),
            'role': store.security.currentRole
          })),
          trailing: FilledButton.icon(
            onPressed: store.security.canManageUsers
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
}
