part of 'accounting_page.dart';

extension _AdvancedCash on _AdvancedAccountingTabState {
  Future<void> _createCashLocationDialog(
      {String initialType = 'cash_drawer'}) async {
    widget.store.security.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final name = TextEditingController();
    final notes = TextEditingController();
    if (!mounted) return;
    final types = <String>[
      'main_vault',
      'branch_vault',
      'cash_drawer',
      'bank',
      'wallet',
      'other'
    ];
    String selectedType = initialType;
    bool isDefault = false;
    bool bindToCurrentDevice = initialType == 'cash_drawer';
    final currentDeviceId = widget.store.runtime.identity.deviceId.trim();
    final currentBranchId = widget.store.runtime.identity.branchId.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.text('create_cash_location')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    decoration: InputDecoration(labelText: tr.text('name'))),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: tr.text('cash_location_type')),
                  items: [
                    for (final type in types)
                      DropdownMenuItem(
                          value: type,
                          child: Text(_localizedAccountingType(type, tr)))
                  ],
                  onChanged: (value) => setDialogState(
                      () => selectedType = value ?? selectedType),
                ),
                const SizedBox(height: 8),
                if (selectedType == 'cash_drawer') ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: bindToCurrentDevice,
                    title: Text(tr.text('link_drawer_current_device')),
                    subtitle: Text(currentDeviceId.isEmpty
                        ? tr.text('no_device_id_available')
                        : currentDeviceId),
                    onChanged: (value) =>
                        setDialogState(() => bindToCurrentDevice = value),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                    controller: notes,
                    decoration: InputDecoration(labelText: tr.text('notes'))),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isDefault,
                  title: Text(tr.text('default_cash_location')),
                  onChanged: (value) => setDialogState(() => isDefault = value),
                ),
              ],
            ),
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
    if (confirmed == true) {
      await AccountingService.createCashLocation(
        name: name.text,
        type: selectedType,
        isDefault: isDefault,
        notes: notes.text,
        storeId: widget.store.runtime.identity.storeId,
        branchId: currentBranchId,
        deviceId: selectedType == 'cash_drawer' && bindToCurrentDevice
            ? currentDeviceId
            : '',
      );
      if (mounted) _refresh();
    }
  }

  Future<void> _showCashTransferJournalHint(AdvancedAccountingItem item) async {
    if (!mounted) return;
    await _showJournalDrillDown(
      context,
      store: widget.store,
      entryId: item.referenceId,
      referenceType: 'cash_transfer',
      referenceId: item.id,
      referenceNo: item.name,
    );
  }

  Future<void> _openingBalancesDialog() async {
    widget.store.security.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final locations = await AccountingService.listActiveCashLocations();
    if (!mounted) return;
    if (locations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('no_cash_locations'))),
      );
      return;
    }
    final amount = TextEditingController();
    final notes = TextEditingController();
    var selectedId = locations.first.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.text('opening_balances')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(tr.text('opening_balances_desc')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedId,
                decoration:
                    InputDecoration(labelText: tr.text('cash_location')),
                items: locations
                    .map((item) => DropdownMenuItem<String>(
                          value: item.id,
                          child: Text(_localizedAccountingName(item.name, tr)),
                        ))
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => selectedId = value ?? selectedId),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    InputDecoration(labelText: tr.text('opening_balance')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notes,
                decoration: InputDecoration(labelText: tr.text('notes')),
              ),
              const SizedBox(height: 8),
              Text(tr.text('opening_balance_once_hint'),
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr.text('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr.text('save'))),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final value = double.tryParse(amount.text.trim()) ?? 0;
    if (value <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr.text('positive_amount_required'))));
      }
      return;
    }
    try {
      final user = widget.store.security.activeUser;
      await AccountingService.recordOpeningCashLocationBalance(
        cashLocationId: selectedId,
        amount: value,
        storeId: widget.store.runtime.identity.storeId,
        branchId: widget.store.runtime.identity.branchId,
        createdBy: user?.fullName.trim().isNotEmpty == true
            ? user!.fullName.trim()
            : widget.store.security.currentRole,
        notes: notes.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr.text('opening_balance_saved'))));
        _refresh(force: true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      amount.dispose();
      notes.dispose();
    }
  }
}
