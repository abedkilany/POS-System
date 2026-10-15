part of 'accounting_page.dart';

extension _AdvancedAssets on _AdvancedAccountingTabState {
  Future<void> _runDepreciationForAllDialog() async {
    widget.store.security.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('run_depreciation')),
        content: Text(tr.text('run_depreciation_all_desc')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('run'))),
        ],
      ),
    );
    if (confirmed == true) {
      final posted = await AccountingService.runDepreciationForAllAssets();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              tr.format('depreciation_entries_posted', {'count': posted}))));
      _refresh();
    }
  }

  Future<void> _runDepreciationForAssetDialog(
      AdvancedAccountingItem item) async {
    widget.store.security.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.format('run_depreciation_for',
            {'name': _localizedAccountingName(item.name, tr)})),
        content: Text(tr.text('run_depreciation_asset_desc')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('run'))),
        ],
      ),
    );
    if (confirmed == true) {
      final posted =
          await AccountingService.runDepreciationForAsset(assetId: item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              tr.format('depreciation_entries_posted', {'count': posted}))));
      _refresh();
    }
  }

  Future<void> _createFixedAssetDialog() async {
    widget.store.security.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final name = TextEditingController();
    final purchaseValue = TextEditingController(text: '0');
    final usefulLifeMonths = TextEditingController(text: '0');
    final notes = TextEditingController();
    final accounts = (await AccountingService.listAccounts())
        .where((account) => account.isPostable && account.isActive)
        .toList();
    final assetAccounts = accounts
        .where((a) =>
            a.type == 'asset' &&
            a.subtype.startsWith('fixed_') &&
            a.subtype != 'fixed_assets')
        .toList();
    if (assetAccounts.isEmpty) return;

    String fixedAssetTypeLabel(AccountingAccount account) {
      return switch (account.subtype) {
        'fixed_equipment' => _accountingUiText(context, 'معدات وآلات',
            'Equipment & machinery', 'Équipements et machines'),
        'fixed_furniture' => _accountingUiText(context, 'أثاث وتجهيزات',
            'Furniture & fixtures', 'Mobilier et agencements'),
        'fixed_computers' => _accountingUiText(context, 'أجهزة وحواسيب',
            'Devices & computers', 'Appareils et ordinateurs'),
        'fixed_vehicles' =>
          _accountingUiText(context, 'سيارات', 'Vehicles', 'Véhicules'),
        'fixed_other' => _accountingUiText(context, 'أصول ثابتة أخرى',
            'Other fixed assets', 'Autres immobilisations'),
        _ => _localizedAccountingName(account.name, tr),
      };
    }

    AccountingAccount? assetAccount = assetAccounts.firstWhere(
      (a) => a.subtype == 'fixed_equipment',
      orElse: () => assetAccounts.first,
    );
    final counterpartAccounts =
        accounts.where((a) => a.id != assetAccount?.id).toList(growable: false);
    AccountingAccount? paymentAccount;
    for (final account in counterpartAccounts) {
      if (account.subtype == 'cash') {
        paymentAccount = account;
        break;
      }
    }
    paymentAccount ??=
        counterpartAccounts.isEmpty ? null : counterpartAccounts.first;
    var paymentMode = 'cash_drawer';
    var acquisitionDate = DateTime.now();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.text('create_fixed_asset')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: tr.text('name'))),
              TextField(
                  controller: purchaseValue,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      InputDecoration(labelText: tr.text('purchase_value'))),
              TextField(
                  controller: usefulLifeMonths,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: tr.text('useful_life_months'))),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_accountingUiText(context, 'تاريخ الاقتناء',
                    'Acquisition date', 'Date d’acquisition')),
                subtitle: Text(
                    '${acquisitionDate.year}-${acquisitionDate.month.toString().padLeft(2, '0')}-${acquisitionDate.day.toString().padLeft(2, '0')}'),
                trailing: const Icon(Icons.calendar_month_outlined),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: acquisitionDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setDialogState(() => acquisitionDate = picked);
                  }
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<AccountingAccount>(
                initialValue: assetAccount,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _accountingUiText(
                    context,
                    'نوع الأصل',
                    'Asset type',
                    'Type d’immobilisation',
                  ),
                ),
                items: [
                  for (final a in assetAccounts)
                    DropdownMenuItem(
                      value: a,
                      child: Text(fixedAssetTypeLabel(a)),
                    )
                ],
                onChanged: (value) => setDialogState(() {
                  assetAccount = value;
                  if (paymentAccount?.id == value?.id) {
                    paymentAccount = null;
                  }
                }),
              ),
              if (assetAccount != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    _accountingUiText(
                      context,
                      'سيتم التسجيل تلقائياً في الحساب: '
                          '${assetAccount!.code} - ${_localizedAccountingName(assetAccount!.name, tr)}',
                      'Will be posted automatically to: '
                          '${assetAccount!.code} - ${_localizedAccountingName(assetAccount!.name, tr)}',
                      'Sera comptabilisé automatiquement dans : '
                          '${assetAccount!.code} - ${_localizedAccountingName(assetAccount!.name, tr)}',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: paymentMode,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _accountingUiText(context, 'طريقة الدفع',
                      'Payment method', 'Mode de paiement'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'cash_drawer',
                    child: Text(_accountingUiText(
                      context,
                      'نقداً من صندوق الجهاز الحالي',
                      'Cash from current drawer',
                      'Espèces depuis la caisse actuelle',
                    )),
                  ),
                  DropdownMenuItem(
                    value: 'account',
                    child: Text(_accountingUiText(
                      context,
                      'حساب محاسبي آخر',
                      'Other accounting account',
                      'Autre compte comptable',
                    )),
                  ),
                ],
                onChanged: (value) =>
                    setDialogState(() => paymentMode = value ?? paymentMode),
              ),
              if (paymentMode == 'cash_drawer') ...[
                const SizedBox(height: 8),
                Text(
                  _accountingUiText(
                    context,
                    'سيتم تسجيل سحب نقدي فعلي من وردية صندوق هذا الجهاز وتخفيض رصيده تلقائياً.',
                    'A real cash withdrawal will be posted to this device drawer and its balance will be reduced automatically.',
                    'Un retrait réel sera enregistré dans la caisse de cet appareil et son solde sera réduit automatiquement.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else if (counterpartAccounts.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<AccountingAccount>(
                  initialValue: paymentAccount,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _accountingUiText(context, 'الحساب المقابل',
                        'Counterpart account', 'Compte de contrepartie'),
                  ),
                  items: [
                    for (final a in counterpartAccounts)
                      if (a.id != assetAccount?.id)
                        DropdownMenuItem(
                            value: a,
                            child: Text(
                                '${a.code} - ${_localizedAccountingName(a.name, tr)}'))
                  ],
                  onChanged: (value) =>
                      setDialogState(() => paymentAccount = value),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                  controller: notes,
                  decoration: InputDecoration(labelText: tr.text('notes'))),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr.text('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr.text('create'))),
          ],
        ),
      ),
    );
    if (confirmed != true || assetAccount == null) return;
    if (!mounted) return;
    try {
      final paidFromCashDrawer = paymentMode == 'cash_drawer';
      if (paidFromCashDrawer) {
        widget.store.security.requirePermission(AppPermission.cashBoxManage);
      }
      if (!paidFromCashDrawer && paymentAccount == null) {
        throw StateError(_accountingUiText(
          context,
          'يجب تحديد الحساب المقابل.',
          'A counterpart account is required.',
          'Un compte de contrepartie est requis.',
        ));
      }
      final user = widget.store.security.activeUser;
      final actor = user?.fullName.trim().isNotEmpty == true
          ? user!.fullName.trim()
          : widget.store.security.currentRole;
      await AccountingService.createFixedAsset(
        code: '',
        name: name.text,
        category: assetAccount!.name,
        acquisitionDate: acquisitionDate,
        purchaseValue: double.tryParse(purchaseValue.text) ?? 0,
        usefulLifeMonths: int.tryParse(usefulLifeMonths.text) ?? 0,
        assetAccountId: assetAccount!.id,
        paymentAccountId: paidFromCashDrawer ? '' : paymentAccount!.id,
        paidFromCashDrawer: paidFromCashDrawer,
        notes: notes.text,
        createdBy: actor,
        createdByUserId: user?.id ?? '',
        deviceId: widget.store.runtime.identity.deviceId,
        storeId: widget.store.runtime.identity.storeId,
        branchId: widget.store.runtime.identity.branchId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_accountingUiText(
            context,
            paidFromCashDrawer
                ? 'تم إنشاء الأصل وتسجيل السحب من الصندوق بنجاح.'
                : 'تم إنشاء الأصل والقيد المحاسبي بنجاح.',
            paidFromCashDrawer
                ? 'Asset created and cash drawer withdrawal posted successfully.'
                : 'Asset and journal entry created successfully.',
            paidFromCashDrawer
                ? 'Immobilisation créée et retrait de caisse enregistré avec succès.'
                : 'Immobilisation et écriture comptable créées avec succès.',
          )),
        ),
      );
      _refresh(force: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }
}
