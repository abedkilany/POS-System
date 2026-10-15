part of 'accounting_page.dart';

extension _AdvancedJournal on _AdvancedAccountingTabState {
  Future<void> _manualJournalDialog() async {
    widget.store.security.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final description =
        TextEditingController(text: tr.text('manual_journal_entry'));
    final debitAmount = TextEditingController(text: '0');
    final creditAmount = TextEditingController(text: '0');
    final accounts = (await AccountingService.listAccounts())
        .where((account) => account.isPostable)
        .toList();
    final costCenters = await AccountingService.listCostCenters();
    final branches = await AccountingService.listAccountingBranches();
    if (accounts.length < 2) return;
    AccountingAccount? debitAccount = accounts.first;
    AccountingAccount? creditAccount =
        accounts.length > 1 ? accounts[1] : debitAccount;
    AdvancedAccountingItem? debitCostCenter;
    AdvancedAccountingItem? creditCostCenter;
    AdvancedAccountingItem? branch;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.text('create_manual_journal')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: description,
                    decoration:
                        InputDecoration(labelText: tr.text('description'))),
                const SizedBox(height: 8),
                DropdownButtonFormField<AdvancedAccountingItem?>(
                  initialValue: branch,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr.text('branch')),
                  items: [
                    DropdownMenuItem<AdvancedAccountingItem?>(
                        value: null, child: Text(tr.text('no_branch'))),
                    for (final item in branches)
                      DropdownMenuItem<AdvancedAccountingItem?>(
                          value: item,
                          child: Text(
                              '${item.accountCode} - ${_localizedAccountingName(item.name, tr)}')),
                  ],
                  onChanged: (value) => setDialogState(() => branch = value),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<AccountingAccount>(
                  initialValue: debitAccount,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: tr.text('debit_account')),
                  items: [
                    for (final a in accounts)
                      DropdownMenuItem(
                          value: a,
                          child: Text(
                              '${a.code} - ${_localizedAccountingName(a.name, tr)}'))
                  ],
                  onChanged: (value) =>
                      setDialogState(() => debitAccount = value),
                ),
                TextField(
                    controller: debitAmount,
                    keyboardType: TextInputType.number,
                    decoration:
                        InputDecoration(labelText: tr.text('debit_amount'))),
                DropdownButtonFormField<AdvancedAccountingItem?>(
                  initialValue: debitCostCenter,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: tr.text('debit_cost_center')),
                  items: [
                    DropdownMenuItem<AdvancedAccountingItem?>(
                        value: null, child: Text(tr.text('no_cost_center'))),
                    for (final item in costCenters)
                      DropdownMenuItem<AdvancedAccountingItem?>(
                          value: item,
                          child: Text(
                              '${item.accountCode} - ${_localizedAccountingName(item.name, tr)}')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => debitCostCenter = value),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<AccountingAccount>(
                  initialValue: creditAccount,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: tr.text('credit_account')),
                  items: [
                    for (final a in accounts)
                      DropdownMenuItem(
                          value: a,
                          child: Text(
                              '${a.code} - ${_localizedAccountingName(a.name, tr)}'))
                  ],
                  onChanged: (value) =>
                      setDialogState(() => creditAccount = value),
                ),
                TextField(
                    controller: creditAmount,
                    keyboardType: TextInputType.number,
                    decoration:
                        InputDecoration(labelText: tr.text('credit_amount'))),
                DropdownButtonFormField<AdvancedAccountingItem?>(
                  initialValue: creditCostCenter,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: tr.text('credit_cost_center')),
                  items: [
                    DropdownMenuItem<AdvancedAccountingItem?>(
                        value: null, child: Text(tr.text('no_cost_center'))),
                    for (final item in costCenters)
                      DropdownMenuItem<AdvancedAccountingItem?>(
                          value: item,
                          child: Text(
                              '${item.accountCode} - ${_localizedAccountingName(item.name, tr)}')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => creditCostCenter = value),
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
                child: Text(tr.text('post'))),
          ],
        ),
      ),
    );
    if (confirmed == true && debitAccount != null && creditAccount != null) {
      final debit = double.tryParse(debitAmount.text) ?? 0;
      final credit = double.tryParse(creditAmount.text) ?? 0;
      final amount = debit > 0 ? debit : credit;
      await AccountingService.createManualJournalEntry(
        entryDate: DateTime.now(),
        description: description.text,
        branchId: branch?.id ?? '',
        lines: [
          JournalLineDraft(
              accountId: debitAccount!.id,
              debit: amount,
              credit: 0,
              costCenterId: debitCostCenter?.id ?? ''),
          JournalLineDraft(
              accountId: creditAccount!.id,
              debit: 0,
              credit: amount,
              costCenterId: creditCostCenter?.id ?? ''),
        ],
      );
      if (mounted) _refresh();
    }
  }
}
