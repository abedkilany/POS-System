part of 'accounting_page.dart';

class _AccountingSettingsTab extends StatefulWidget {
  const _AccountingSettingsTab({required this.store});

  final ApplicationSession store;

  @override
  State<_AccountingSettingsTab> createState() => _AccountingSettingsTabState();
}

class _AccountingSettingsTabState extends State<_AccountingSettingsTab> {
  late Future<_AccountingSettingsData> _future;
  int _lastSeenRevision = -1;
  static final RevisionKeyCache<Future<_AccountingSettingsData>> _futureCache =
      RevisionKeyCache<Future<_AccountingSettingsData>>();

  @override
  void initState() {
    super.initState();
    _future = _loadCached();
    _lastSeenRevision = widget.store.accounting.revision;
    widget.store.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _AccountingSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_refresh);
      widget.store.addListener(_refresh);
      _lastSeenRevision = widget.store.accounting.revision;
    }
  }

  Future<_AccountingSettingsData> _load() async {
    final legacyRate = await AccountingService.readDefaultVatRatePercent();
    final storeProfile = widget.store.runtime.profile;
    final profiles = <TaxProfile>[
      for (final profile in storeProfile.taxProfiles)
        if (storeProfile.taxConfigurationVersion <= 0 &&
            profile.id == TaxProfile.standardId)
          profile.copyWith(ratePercent: legacyRate)
        else
          profile,
    ];
    final standard = profiles.where(
      (item) => item.id == TaxProfile.standardId,
    );
    return _AccountingSettingsData(
      vatRatePercent:
          standard.isEmpty ? legacyRate : standard.first.ratePercent,
      profiles: profiles,
      defaultTaxProfileId: storeProfile.defaultTaxProfileId,
    );
  }

  Future<void> _updateVatRate(double ratePercent) async {
    widget.store.security.requirePermission(AppPermission.accountingManage);
    await widget.store.accounting.updateDefaultTaxRatePercent(ratePercent);
    if (!mounted) return;
    _refresh(force: true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context).text('accounting_setting_updated'),
        ),
      ),
    );
  }

  Future<void> _updateDefaultTaxProfile(
    _AccountingSettingsData data,
    String profileId,
  ) async {
    widget.store.security.requirePermission(AppPermission.accountingManage);
    await widget.store.accounting.updateTaxConfiguration(
      profiles: data.profiles,
      defaultTaxProfileId: profileId,
    );
    if (!mounted) return;
    _refresh(force: true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context).text('accounting_setting_updated'),
        ),
      ),
    );
  }

  Future<_AccountingSettingsData> _loadCached() {
    return _futureCache.getOrCompute(
      widget.store.accounting.revision,
      widget.store.runtime.identity.storeId,
      _load,
    );
  }

  void _refresh({bool force = false}) {
    if (!mounted) return;
    final revision = widget.store.accounting.revision;
    if (!force && revision == _lastSeenRevision) return;
    _lastSeenRevision = revision;
    setState(() => _future = _loadCached());
  }

  @override
  void dispose() {
    widget.store.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AccountingSettingsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(message: snapshot.error.toString());
        }
        final data = snapshot.data ??
            const _AccountingSettingsData(
              vatRatePercent: 0,
              profiles: TaxProfile.defaults,
              defaultTaxProfileId: TaxProfile.standardId,
            );
        final canManageAccounting =
            widget.store.security.hasPermission(AppPermission.accountingManage);
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                _accountingUiText(context, 'إعدادات المحاسبة العامة',
                    'General accounting settings', 'Paramètres comptables'),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                _accountingUiText(
                  context,
                  'تم توحيد ربط الحسابات ضمن تبويب «ربط الحسابات». إعدادات الحسابات الافتراضية القديمة ما زالت محفوظة داخلياً للتوافق فقط ولا يتم تعديلها من هذه الواجهة.',
                  'Account mapping is now managed only from the Account Roles tab. Legacy default-account values remain internal for compatibility and are no longer edited here.',
                  'Le rattachement des comptes est désormais géré uniquement dans l’onglet des rôles comptables. Les anciennes valeurs restent internes pour compatibilité.',
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_tree_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _accountingUiText(
                          context,
                          'Account Roles هي المرجع الرسمي لتوجيه القيود المحاسبية.',
                          'Account Roles are the official source for accounting posting mappings.',
                          'Les rôles comptables sont la source officielle du paramétrage des imputations.',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 28),
              _VatRateSettingRow(
                ratePercent: data.vatRatePercent,
                enabled: canManageAccounting,
                onChanged: _updateVatRate,
              ),
              const SizedBox(height: 8),
              _TaxProfilesSettingCard(
                profiles: data.profiles,
                defaultTaxProfileId: data.defaultTaxProfileId,
                enabled: canManageAccounting,
                onDefaultChanged: (value) =>
                    _updateDefaultTaxProfile(data, value),
              ),
              if (!canManageAccounting) ...[
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)
                      .text('accounting_read_only_permission'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AccountingSettingsData {
  const _AccountingSettingsData({
    required this.vatRatePercent,
    required this.profiles,
    required this.defaultTaxProfileId,
  });

  final double vatRatePercent;
  final List<TaxProfile> profiles;
  final String defaultTaxProfileId;
}

class _TaxProfilesSettingCard extends StatelessWidget {
  const _TaxProfilesSettingCard({
    required this.profiles,
    required this.defaultTaxProfileId,
    required this.enabled,
    required this.onDefaultChanged,
  });

  final List<TaxProfile> profiles;
  final String defaultTaxProfileId;
  final bool enabled;
  final ValueChanged<String> onDefaultChanged;

  String _treatmentLabel(BuildContext context, TaxTreatment treatment) {
    final tr = AppLocalizations.of(context);
    return switch (treatment) {
      TaxTreatment.standard => tr.text('tax_profile_standard'),
      TaxTreatment.zeroRated => tr.text('tax_profile_zero_rated'),
      TaxTreatment.exempt => tr.text('tax_profile_exempt'),
      TaxTreatment.outOfScope => tr.text('tax_profile_out_of_scope'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final active =
        profiles.where((item) => item.isActive).toList(growable: false);
    final selected = active.any((item) => item.id == defaultTaxProfileId)
        ? defaultTaxProfileId
        : (active.isEmpty ? null : active.first.id);
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr.text('tax_profiles'),
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              tr.text('tax_profiles_desc'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            for (final profile in active)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  profile.treatment == TaxTreatment.exempt
                      ? Icons.block_outlined
                      : Icons.percent_outlined,
                ),
                title: Text(profile.name),
                subtitle: Text(
                  '${profile.code} • ${_treatmentLabel(context, profile.treatment)}'
                  '${profile.treatment == TaxTreatment.standard ? ' • ${profile.ratePercent.toStringAsFixed(profile.ratePercent == profile.ratePercent.roundToDouble() ? 0 : 2)}%' : ''}',
                ),
              ),
            if (active.isNotEmpty) ...[
              const Divider(height: 20),
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: InputDecoration(
                  labelText: tr.text('default_tax_profile'),
                  helperText: tr.text('default_tax_profile_desc'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final profile in active)
                    DropdownMenuItem<String>(
                      value: profile.id,
                      child: Text('${profile.name} (${profile.code})'),
                    ),
                ],
                onChanged: enabled
                    ? (value) {
                        if (value != null && value != selected) {
                          onDefaultChanged(value);
                        }
                      }
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountingSettingDefinition {
  const _AccountingSettingDefinition(
      {required this.titleKey, required this.subtitleKey, required this.icon});

  final String titleKey;
  final String subtitleKey;
  final IconData icon;
}

class _VatRateSettingRow extends StatefulWidget {
  const _VatRateSettingRow(
      {required this.ratePercent,
      required this.enabled,
      required this.onChanged});

  final double ratePercent;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  State<_VatRateSettingRow> createState() => _VatRateSettingRowState();
}

class _VatRateSettingRowState extends State<_VatRateSettingRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
        text: widget.ratePercent.toStringAsFixed(
            widget.ratePercent == widget.ratePercent.roundToDouble() ? 0 : 2));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                  radius: 18, child: Icon(Icons.percent_outlined, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr.text('default_vat_rate'),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(tr.text('default_vat_rate_desc'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          );
          final field = TextField(
            controller: _controller,
            enabled: widget.enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: tr.text('vat_rate_percent'),
              suffixText: '%',
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) =>
                widget.onChanged(double.tryParse(value.trim()) ?? 0),
          );
          final save = FilledButton.icon(
            onPressed: widget.enabled
                ? () => widget
                    .onChanged(double.tryParse(_controller.text.trim()) ?? 0)
                : null,
            icon: const Icon(Icons.save_outlined),
            label: Text(tr.text('save')),
          );
          if (constraints.maxWidth < 760) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  info,
                  const SizedBox(height: 10),
                  field,
                  const SizedBox(height: 8),
                  save
                ]);
          }
          return Row(children: [
            Expanded(child: info),
            const SizedBox(width: 20),
            SizedBox(width: 260, child: field),
            const SizedBox(width: 8),
            save
          ]);
        },
      ),
    );
  }
}

class _AccountingSettingRow extends StatelessWidget {
  const _AccountingSettingRow(
      {required this.definition,
      required this.accounts,
      required this.selectedAccountId,
      required this.onChanged});

  final _AccountingSettingDefinition definition;
  final List<AccountingAccount> accounts;
  final String selectedAccountId;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final selectedExists = accounts.any(
        (account) => account.id == selectedAccountId && account.isPostable);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final selector = _AccountSelector(
            accounts: accounts,
            value: selectedExists ? selectedAccountId : null,
            onChanged: onChanged,
          );
          final info = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 18, child: Icon(definition.icon, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr.text(definition.titleKey),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(tr.text(definition.subtitleKey),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [info, const SizedBox(height: 10), selector],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: info),
              const SizedBox(width: 20),
              SizedBox(width: 380, child: selector),
            ],
          );
        },
      ),
    );
  }
}
